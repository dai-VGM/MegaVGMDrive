`timescale 1ns/1ps

// Profile-local reset controller.  PLL loss asserts both release synchronizers
// asynchronously.  Video reset deasserts after three clk_sys edges and is not
// affected by shell/player reset.  Player reset then holds for the same proven
// 1.25 second interval used by the production MegaVGMPlayer POR.
module ym2610_player_reset_controller #(
    parameter int POR_HOLD_CYCLES = 25_000_000
) (
    input  logic        ref_clk,
    input  logic        clk,
    input  logic        pll_locked,
    input  logic        shell_reset,
    input  logic        software_reset,
    output logic        video_reset,
    output logic        player_reset,
    output logic        por_active,
    output logic [2:0]  last_reset_source,
    output logic        pll_unlock_observed,
    output logic [15:0] video_reset_edge_count
);
    localparam int POR_WIDTH = (POR_HOLD_CYCLES <= 1) ? 1 :
                               $clog2(POR_HOLD_CYCLES + 1);
    localparam logic [POR_WIDTH-1:0] POR_LAST =
        POR_WIDTH'((POR_HOLD_CYCLES <= 1) ? 0 : POR_HOLD_CYCLES - 1);

    logic [2:0] video_release_sync;
    logic [POR_WIDTH-1:0] por_counter;
    logic pll_ref_meta, pll_ref_sync, pll_ref_q, pll_ref_seen;
    logic pll_unlock_ref;
    logic [15:0] video_reset_count_ref;
    logic pll_unlock_sync_q;
    logic [15:0] video_reset_count_sync_q;

    // CLK_50M remains available when the generated clock loses lock, so it is
    // the only clock that can retain evidence of a runtime PLL event.
    always_ff @(posedge ref_clk or posedge shell_reset) begin
        if (shell_reset) begin
            pll_ref_meta <= 1'b0;
            pll_ref_sync <= 1'b0;
            pll_ref_q <= 1'b0;
            pll_ref_seen <= 1'b0;
            pll_unlock_ref <= 1'b0;
            video_reset_count_ref <= 16'd0;
        end else begin
            pll_ref_meta <= pll_locked;
            pll_ref_sync <= pll_ref_meta;
            pll_ref_q <= pll_ref_sync;
            if (software_reset) begin
                pll_ref_seen <= 1'b0;
                pll_unlock_ref <= 1'b0;
                video_reset_count_ref <= 16'd0;
            end else begin
                if (pll_ref_sync)
                    pll_ref_seen <= 1'b1;
                if (pll_ref_seen && pll_ref_q && !pll_ref_sync) begin
                    pll_unlock_ref <= 1'b1;
                    if (video_reset_count_ref != 16'hffff)
                        video_reset_count_ref <= video_reset_count_ref + 16'd1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge pll_locked) begin
        if (!pll_locked)
            video_release_sync <= 3'b000;
        else
            video_release_sync <= {video_release_sync[1:0], 1'b1};
    end

    assign video_reset = !video_release_sync[2];

    always_ff @(posedge clk or negedge pll_locked or posedge shell_reset) begin
        if (shell_reset) begin
            player_reset <= 1'b1;
            por_active <= 1'b1;
            por_counter <= '0;
            last_reset_source <= 3'd2;
            pll_unlock_observed <= 1'b0;
            pll_unlock_sync_q <= 1'b0;
            video_reset_edge_count <= 16'd0;
            video_reset_count_sync_q <= 16'd0;
        end else if (!pll_locked) begin
            player_reset <= 1'b1;
            por_active <= 1'b1;
            por_counter <= '0;
            last_reset_source <= 3'd1;
            pll_unlock_observed <= 1'b0;
            pll_unlock_sync_q <= 1'b0;
            video_reset_edge_count <= 16'd0;
            video_reset_count_sync_q <= 16'd0;
        end else begin
            pll_unlock_sync_q <= pll_unlock_ref;
            pll_unlock_observed <= pll_unlock_sync_q;
            video_reset_count_sync_q <= video_reset_count_ref;
            video_reset_edge_count <= video_reset_count_sync_q;

            if (software_reset) begin
                player_reset <= 1'b1;
                por_active <= 1'b1;
                por_counter <= '0;
                last_reset_source <= 3'd3;
            end else if (video_reset) begin
                player_reset <= 1'b1;
                por_active <= 1'b1;
                por_counter <= '0;
            end else if (POR_HOLD_CYCLES <= 1 || por_counter == POR_LAST) begin
                player_reset <= 1'b0;
                por_active <= 1'b0;
            end else begin
                player_reset <= 1'b1;
                por_active <= 1'b1;
                por_counter <= por_counter + {{(POR_WIDTH-1){1'b0}}, 1'b1};
            end
        end
    end
endmodule

// Backend load_done/play_ready are already emitted only after the common
// loader drains its final partial word.  This profile fence independently
// decodes those live drain indicators and requires two consecutive quiescent
// cycles before producing the one scanner permission pulse.
module ym2610_player_load_fence (
    input  logic        clk,
    input  logic        reset,
    input  logic        ioctl_download,
    input  logic        load_busy,
    input  logic        load_done,
    input  logic        play_ready_pulse,
    input  logic        load_error,
    input  logic        overflow_error,
    input  logic [15:0] fifo_debug,
    input  logic [15:0] ready_debug,
    input  logic [15:0] word_debug,
    input  logic        ddram_busy,
    input  logic        ddram_rd,
    input  logic        ddram_we,
    output logic        scanner_ready_pulse,
    output logic [7:0]  load_generation,
    output logic [31:0] fence_count,
    output logic        fence_waiting,
    output logic        fence_stable
);
    logic download_q;
    logic armed;
    logic play_ready_seen;
    logic stable_q;

    wire download_start = ioctl_download && !download_q;
    wire backend_drained = !ioctl_download && load_done && !load_busy &&
                           fifo_debug[7] && !ready_debug[10] &&
                           !ready_debug[9] && !ready_debug[8] &&
                           !ready_debug[7] && !ready_debug[6] &&
                           !word_debug[2] && !ddram_busy &&
                           !ddram_rd && !ddram_we;

    assign fence_waiting = armed && play_ready_seen;
    assign fence_stable = stable_q;

    always_ff @(posedge clk) begin
        scanner_ready_pulse <= 1'b0;
        if (reset) begin
            download_q <= 1'b0;
            armed <= 1'b0;
            play_ready_seen <= 1'b0;
            stable_q <= 1'b0;
            load_generation <= 8'd0;
            fence_count <= 32'd0;
        end else begin
            download_q <= ioctl_download;
            if (download_start) begin
                armed <= 1'b1;
                play_ready_seen <= 1'b0;
                stable_q <= 1'b0;
                load_generation <= load_generation + 8'd1;
            end
            if (play_ready_pulse)
                play_ready_seen <= 1'b1;

            if (load_error || overflow_error) begin
                armed <= 1'b0;
                play_ready_seen <= 1'b0;
                stable_q <= 1'b0;
            end else if (armed && play_ready_seen && backend_drained) begin
                if (stable_q) begin
                    scanner_ready_pulse <= 1'b1;
                    fence_count <= fence_count + 32'd1;
                    armed <= 1'b0;
                    play_ready_seen <= 1'b0;
                    stable_q <= 1'b0;
                end else begin
                    stable_q <= 1'b1;
                end
            end else begin
                stable_q <= 1'b0;
            end
        end
    end
endmodule

`timescale 1ns/1ps

module tb_mode5_start_hold_fallback;
    logic clk = 1'b0;
    logic reset_n = 1'b0;

    wire [15:0] mode5_start_hold_debug;
    wire [31:0] mode5_player_start_count;
    wire [31:0] mode5_load_done_edge_count;
    wire mode5_player_start_to_player;
    wire player_busy;
    wire [15:0] vgm_player_core_debug;

    always #5 clk = ~clk;

    mister_vgm_md_top #(
        .REGION_MODE                     (5),
        .VGM_LOAD_ADDR_WIDTH             (8),
        .MODE5_VGM_BACKEND               (0),
        .POWER_ON_RESET_CYCLES           (32'd0),
        .START_DELAY_CYCLES              (32'd0),
        .AUDIO_WARMUP_SAMPLES            (16'd0),
        .MODE5_SOUND_RESET_CYCLES        (32'd0),
        .MODE5_AUDIO_UNMUTE_DELAY_CYCLES (32'd0)
    ) dut (
        .clk                            (clk),
        .reset_n                        (reset_n),
        .audio_lpf_mode                 (2'b00),
        .audio_gain_boost               (1'b0),
        .audio_psg_level                (2'b00),
        .ioctl_download                 (1'b0),
        .ioctl_wr                       (1'b0),
        .ioctl_addr                     (27'd0),
        .ioctl_dout                     (8'd0),
        .ioctl_index                    (16'd0),
        .player_busy                    (player_busy),
        .mode5_player_start_pulse_debug (mode5_player_start_to_player),
        .mode5_start_hold_debug         (mode5_start_hold_debug),
        .mode5_player_start_count       (mode5_player_start_count),
        .mode5_load_done_edge_count     (mode5_load_done_edge_count),
        .vgm_player_core_debug          (vgm_player_core_debug),
        .ddram_busy                     (1'b0),
        .ddram_dout                     (64'd0),
        .ddram_dout_ready               (1'b0)
    );

    initial begin
        repeat (4) @(posedge clk);
        reset_n = 1'b1;
        wait (dut.reset === 1'b0);
        repeat (4) @(posedge clk);

        force dut.vgm_load_done = 1'b1;
        force dut.vgm_load_busy = 1'b0;
        force dut.vgm_load_error = 1'b0;
        force dut.vgm_load_overflow = 1'b0;
        force dut.vgm_load_size = 9'd128;
        force dut.loaded_vgm_mode.play_ready_pulse = 1'b1;
        @(posedge clk);
        @(posedge clk);
        release dut.loaded_vgm_mode.play_ready_pulse;

        repeat (4) @(posedge clk);

        if (mode5_load_done_edge_count == 32'd0) begin
            $display("FAIL load-ready fallback was not accepted");
            $finish;
        end

        if (mode5_player_start_count == 32'd0) begin
            $display("FAIL player start was not counted");
            $finish;
        end

        if (!vgm_player_core_debug[15] && !vgm_player_core_debug[12]) begin
            $display("FAIL start_to_player dropped before player saw start core=%04h sh=%04h",
                     vgm_player_core_debug, mode5_start_hold_debug);
            $finish;
        end

        $display("PASS tb_mode5_start_hold_fallback debug=%04h",
                 mode5_start_hold_debug);
        $finish;
    end
endmodule

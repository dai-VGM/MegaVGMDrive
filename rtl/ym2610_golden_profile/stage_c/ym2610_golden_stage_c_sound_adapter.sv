// SPDX-License-Identifier: GPL-2.0-or-later
// Stage C standard-YM2610 sound boundary. It uses the verified HW-0 JT10
// source blobs without the HW-0 sequencer, ROMs, video, or self-test top.
`timescale 1ns/1ps

module ym2610_golden_stage_c_sound_adapter #(
    parameter int CLK_SYS_HZ = 20_000_000,
    parameter int BUSY_TIMEOUT_CYCLES = 100_000
) (
    input  logic               clk,
    input  logic               reset,
    input  logic               core_reset,
    input  logic               publish_enable,
    input  logic [31:0]        chip_clock,

    input  logic               write_req,
    input  logic               write_port,
    input  logic [7:0]         write_address,
    input  logic [7:0]         write_data,
    output logic               write_accept,
    output logic               write_busy,
    output logic               busy_timeout,
    output logic               write_while_busy,
    output logic [31:0]        accepted_write_count,

    output logic signed [15:0] audio_l,
    output logic signed [15:0] audio_r,
    output logic               audio_sample_valid,
    output logic signed [15:0] fm_l,
    output logic signed [15:0] fm_r,
    output logic [7:0]         psg_a,
    output logic [7:0]         psg_b,
    output logic [7:0]         psg_c,
    output logic [9:0]         psg_snd,
    output logic signed [15:0] adpcma_l,
    output logic signed [15:0] adpcma_r,
    output logic signed [15:0] adpcmb_l,
    output logic signed [15:0] adpcmb_r,
    output logic               adpcma_request,
    output logic               adpcmb_request,
    output logic [19:0]        adpcma_addr,
    output logic [3:0]         adpcma_bank,
    output logic [23:0]        adpcmb_addr,
    output logic               unexpected_pcm_request,
    output logic               unexpected_pcm_activity,
    output logic               core_ready,
    output logic               public_sample_rise,
    output logic               cen,
    output logic [31:0]        cen_accumulator,
    output logic               clock_invalid
);
    localparam int WATCHDOG_WIDTH = $clog2(BUSY_TIMEOUT_CYCLES + 1);

    typedef enum logic [3:0] {
        W_IDLE,
        W_PRE_STATUS_SETUP,
        W_PRE_STATUS_SAMPLE,
        W_ADDR_DRIVE,
        W_ADDR_RELEASE,
        W_DATA_STATUS_SETUP,
        W_DATA_STATUS_SAMPLE,
        W_DATA_DRIVE,
        W_DATA_RELEASE,
        W_POST_STATUS_SETUP,
        W_POST_STATUS_SAMPLE,
        W_ERROR
    } write_state_t;

    write_state_t write_state;
    logic [WATCHDOG_WIDTH-1:0] watchdog;
    logic post_busy_seen;
    logic held_port;
    logic [7:0] held_address;
    logic [7:0] held_data;

    logic [1:0] core_bus_addr;
    logic [7:0] core_bus_din;
    logic core_bus_cs_n;
    logic core_bus_wr_n;
    logic [7:0] core_bus_dout;
    logic core_irq_n;
    logic core_sample;
    logic sample_d;
    logic [2:0] warmup_count;
    logic [32:0] cen_sum;
    logic adpcma_roe_n;
    logic adpcmb_roe_n;
    logic [5:0] unused_adpcma_eos;
    logic [5:0] unused_adpcma_command;
    logic unused_adpcmb_eos;
    logic unused_adpcmb_active;
    logic unused_adpcmb_command_update;
    logic [7:0] unused_debug;
    logic signed [15:0] unused_core_mix_l;
    logic signed [15:0] unused_core_mix_r;

    logic signed [16:0] mix_l;
    logic signed [16:0] mix_r;
    wire signed [16:0] psg_scaled =
        $signed({2'b00, psg_snd, 5'd0});

    assign clock_invalid = chip_clock == 0 || chip_clock > CLK_SYS_HZ;
    assign cen_sum = {1'b0, cen_accumulator} + {1'b0, chip_clock};

    function automatic signed [15:0] saturate17(
        input logic signed [16:0] value
    );
        begin
            if (value > 17'sd32767)
                saturate17 = 16'sh7fff;
            else if (value < -17'sd32768)
                saturate17 = 16'sh8000;
            else
                saturate17 = value[15:0];
        end
    endfunction

    always_comb begin
        mix_l = {fm_l[15], fm_l} + psg_scaled;
        mix_r = {fm_r[15], fm_r} + psg_scaled;
        if (publish_enable && core_ready && !busy_timeout &&
            !unexpected_pcm_request && !unexpected_pcm_activity &&
            !clock_invalid) begin
            audio_l = saturate17(mix_l);
            audio_r = saturate17(mix_r);
            audio_sample_valid = core_sample;
        end else begin
            audio_l = 16'sd0;
            audio_r = 16'sd0;
            audio_sample_valid = 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (reset || core_reset) begin
            cen_accumulator <= 32'd0;
            cen <= 1'b1;
        end else if (clock_invalid) begin
            cen_accumulator <= 32'd0;
            cen <= 1'b0;
        end else if (cen_sum >= CLK_SYS_HZ) begin
            cen_accumulator <= cen_sum[31:0] - CLK_SYS_HZ;
            cen <= 1'b1;
        end else begin
            cen_accumulator <= cen_sum[31:0];
            cen <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (reset || core_reset) begin
            sample_d <= 1'b0;
            warmup_count <= 3'd0;
            core_ready <= 1'b0;
        end else begin
            sample_d <= core_sample;
            if (!core_ready && core_sample && !sample_d &&
                warmup_count < 3'd5)
                warmup_count <= warmup_count + 3'd1;
            if (!core_ready && !core_sample && sample_d &&
                warmup_count == 3'd5)
                core_ready <= 1'b1;
        end
    end

    assign public_sample_rise =
        core_ready && core_sample && !sample_d && !core_reset;
    // The pinned ADPCM-A driver leaves roe_n unknown until its first command.
    // At this Stage C boundary only an explicitly asserted low is a request;
    // an actual low is still monitored and is a fatal contract violation.
    always_comb begin
        adpcma_request = 1'b0;
        adpcmb_request = 1'b0;
        case (adpcma_roe_n)
            1'b0: adpcma_request = 1'b1;
            default: begin end
        endcase
        case (adpcmb_roe_n)
            1'b0: adpcmb_request = 1'b1;
            default: begin end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset || core_reset) begin
            unexpected_pcm_request <= 1'b0;
            unexpected_pcm_activity <= 1'b0;
        end else if (core_ready) begin
            if (adpcma_request || adpcmb_request)
                unexpected_pcm_request <= 1'b1;
            if (adpcma_l != 0 || adpcma_r != 0 ||
                adpcmb_l != 0 || adpcmb_r != 0)
                unexpected_pcm_activity <= 1'b1;
        end
    end

    assign write_busy = write_state != W_IDLE;

    always_ff @(posedge clk) begin
        write_accept <= 1'b0;

        if (reset || core_reset) begin
            write_state <= W_IDLE;
            core_bus_addr <= 2'b00;
            core_bus_din <= 8'h00;
            core_bus_cs_n <= 1'b1;
            core_bus_wr_n <= 1'b1;
            held_port <= 1'b0;
            held_address <= 8'd0;
            held_data <= 8'd0;
            watchdog <= '0;
            post_busy_seen <= 1'b0;
            busy_timeout <= 1'b0;
            write_while_busy <= 1'b0;
            accepted_write_count <= 32'd0;
        end else begin
            case (write_state)
                W_IDLE: begin
                    core_bus_addr <= 2'b00;
                    core_bus_din <= 8'h00;
                    core_bus_cs_n <= 1'b1;
                    core_bus_wr_n <= 1'b1;
                    watchdog <= '0;
                    post_busy_seen <= 1'b0;
                    if (write_req) begin
                        held_port <= write_port;
                        held_address <= write_address;
                        held_data <= write_data;
                        write_state <= W_PRE_STATUS_SETUP;
                    end
                end

                W_PRE_STATUS_SETUP: begin
                    core_bus_addr <= 2'b00;
                    core_bus_din <= 8'h00;
                    core_bus_cs_n <= 1'b0;
                    core_bus_wr_n <= 1'b1;
                    write_state <= W_PRE_STATUS_SAMPLE;
                end

                W_PRE_STATUS_SAMPLE: begin
                    if (core_bus_dout[7] == 1'b0) begin
                        core_bus_cs_n <= 1'b1;
                        watchdog <= '0;
                        write_state <= W_ADDR_DRIVE;
                    end else if (watchdog == BUSY_TIMEOUT_CYCLES-1) begin
                        busy_timeout <= 1'b1;
                        write_state <= W_ERROR;
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                W_ADDR_DRIVE: begin
                    core_bus_addr <= {held_port, 1'b0};
                    core_bus_din <= held_address;
                    core_bus_cs_n <= 1'b0;
                    core_bus_wr_n <= 1'b0;
                    write_state <= W_ADDR_RELEASE;
                end

                W_ADDR_RELEASE: begin
                    core_bus_addr <= 2'b00;
                    core_bus_din <= 8'h00;
                    core_bus_cs_n <= 1'b1;
                    core_bus_wr_n <= 1'b1;
                    write_state <= W_DATA_STATUS_SETUP;
                end

                W_DATA_STATUS_SETUP: begin
                    core_bus_addr <= 2'b00;
                    core_bus_din <= 8'h00;
                    core_bus_cs_n <= 1'b0;
                    core_bus_wr_n <= 1'b1;
                    write_state <= W_DATA_STATUS_SAMPLE;
                end

                W_DATA_STATUS_SAMPLE: begin
                    if (core_bus_dout[7] == 1'b0) begin
                        core_bus_cs_n <= 1'b1;
                        watchdog <= '0;
                        write_state <= W_DATA_DRIVE;
                    end else if (watchdog == BUSY_TIMEOUT_CYCLES-1) begin
                        busy_timeout <= 1'b1;
                        write_state <= W_ERROR;
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                W_DATA_DRIVE: begin
                    core_bus_addr <= {held_port, 1'b1};
                    core_bus_din <= held_data;
                    core_bus_cs_n <= 1'b0;
                    core_bus_wr_n <= 1'b0;
                    write_state <= W_DATA_RELEASE;
                end

                W_DATA_RELEASE: begin
                    core_bus_addr <= 2'b00;
                    core_bus_din <= 8'h00;
                    core_bus_cs_n <= 1'b1;
                    core_bus_wr_n <= 1'b1;
                    write_accept <= 1'b1;
                    accepted_write_count <= accepted_write_count + 32'd1;
                    watchdog <= '0;
                    post_busy_seen <= 1'b0;
                    write_state <= W_POST_STATUS_SETUP;
                end

                W_POST_STATUS_SETUP: begin
                    core_bus_addr <= 2'b00;
                    core_bus_din <= 8'h00;
                    core_bus_cs_n <= 1'b0;
                    core_bus_wr_n <= 1'b1;
                    write_state <= W_POST_STATUS_SAMPLE;
                end

                W_POST_STATUS_SAMPLE: begin
                    if (core_bus_dout[7] == 1'b1) begin
                        post_busy_seen <= 1'b1;
                        if (watchdog == BUSY_TIMEOUT_CYCLES-1) begin
                            busy_timeout <= 1'b1;
                            write_state <= W_ERROR;
                        end else begin
                            watchdog <= watchdog + 1'b1;
                        end
                    end else if (post_busy_seen) begin
                        core_bus_cs_n <= 1'b1;
                        watchdog <= '0;
                        write_state <= W_IDLE;
                    end else if (watchdog == BUSY_TIMEOUT_CYCLES-1) begin
                        busy_timeout <= 1'b1;
                        write_state <= W_ERROR;
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                W_ERROR: begin
                    core_bus_addr <= 2'b00;
                    core_bus_din <= 8'h00;
                    core_bus_cs_n <= 1'b1;
                    core_bus_wr_n <= 1'b1;
                end

                default: write_state <= W_ERROR;
            endcase

            if ((write_state == W_ADDR_DRIVE ||
                 write_state == W_DATA_DRIVE) &&
                core_bus_dout[7] == 1'b1)
                write_while_busy <= 1'b1;
        end
    end

    ym2610_hw0_jt12_top #(
        .use_lfo(1),
        .use_ssg(1),
        .num_ch(6),
        .use_pcm(0),
        .use_adpcm(1),
        .JT49_DIV(3)
    ) u_core (
        .rst(reset || core_reset),
        .clk(clk),
        .cen(cen),
        .din(core_bus_din),
        .addr(core_bus_addr),
        .cs_n(core_bus_cs_n),
        .wr_n(core_bus_wr_n),
        .ladder(1'b0),
        .dout(core_bus_dout),
        .irq_n(core_irq_n),
        .en_hifi_pcm(1'b0),
        .adpcma_addr(adpcma_addr),
        .adpcma_bank(adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n),
        .adpcma_data(8'h00),
        .adpcmb_addr(adpcmb_addr),
        .adpcmb_data(8'h00),
        .adpcmb_roe_n(adpcmb_roe_n),
        .IOA_in(8'h00),
        .IOB_in(8'h00),
        .psg_A(psg_a),
        .psg_B(psg_b),
        .psg_C(psg_c),
        .fm_snd_left(fm_l),
        .fm_snd_right(fm_r),
        .adpcmA_l(adpcma_l),
        .adpcmA_r(adpcma_r),
        .adpcmB_l(adpcmb_l),
        .adpcmB_r(adpcmb_r),
        .psg_snd(psg_snd),
        .snd_right(unused_core_mix_r),
        .snd_left(unused_core_mix_l),
        .snd_sample(core_sample),
        .debug_bus(8'h00),
        .debug_view(unused_debug),
        .hw0_adpcma_eos(unused_adpcma_eos),
        .hw0_adpcma_command(unused_adpcma_command),
        .hw0_adpcma_left(),
        .hw0_adpcma_right(),
        .hw0_adpcmb_eos(unused_adpcmb_eos),
        .hw0_adpcmb_active(unused_adpcmb_active),
        .hw0_adpcmb_command_update(unused_adpcmb_command_update),
        .hw0_adpcmb_left(),
        .hw0_adpcmb_right()
    );

    wire unused_core_status = ^{
        core_irq_n, unused_debug, unused_core_mix_l, unused_core_mix_r,
        unused_adpcma_eos, unused_adpcma_command, unused_adpcmb_eos,
        unused_adpcmb_active, unused_adpcmb_command_update
    };
endmodule

`timescale 1ns/1ps

// Synthesizable standalone YM2610 wrapper.  The five-pulse publication gate
// is the explicit hardware form of the Phase 0 warm-up contract: the core is
// never paused, and the sixth internal sample is the first public sample.
module ym2610_hw0_jt10_wrapper (
    input  logic               clk,
    input  logic               rst,
    input  logic               cen,
    input  logic         [1:0] bus_addr,
    input  logic         [7:0] bus_din,
    input  logic               bus_cs_n,
    input  logic               bus_wr_n,
    output logic         [7:0] bus_dout,
    output logic               irq_n,
    output logic signed [15:0] snd_left,
    output logic signed [15:0] snd_right,
    output logic               snd_sample,
    output logic         [7:0] psg_a,
    output logic         [7:0] psg_b,
    output logic         [7:0] psg_c,
    output logic         [9:0] psg_snd,
    output logic        [19:0] adpcma_addr,
    output logic         [3:0] adpcma_bank,
    output logic               adpcma_roe_n,
    input  logic         [7:0] adpcma_data,
    output logic        [23:0] adpcmb_addr,
    output logic               adpcmb_roe_n,
    input  logic         [7:0] adpcmb_data,
    output logic               ready,
    output logic         [2:0] reset_cen_count,
    output logic         [5:0] adpcma_eos,
    output logic         [5:0] adpcma_command,
    output logic               adpcmb_eos,
    output logic               adpcmb_active,
    output logic               adpcmb_command_update,
    output logic signed [15:0] internal_left,
    output logic signed [15:0] internal_right,
    output logic               internal_sample
);
    logic signed [15:0] core_left;
    logic signed [15:0] core_right;
    logic signed [15:0] unused_fm_right;
    logic        [7:0] unused_debug;
    logic              core_sample;
    logic        [2:0] warmup_count;
    logic              sample_d;

    assign internal_left = core_left;
    assign internal_right = core_right;
    assign internal_sample = core_sample;
    assign snd_left = ready ? core_left : 16'sd0;
    assign snd_right = ready ? core_right : 16'sd0;
    assign snd_sample = ready ? core_sample : 1'b0;

    always_ff @(posedge clk) begin
        if (rst) begin
            reset_cen_count <= cen ? 3'd1 : 3'd0;
        end else if (reset_cen_count < 3'd6 && cen) begin
            reset_cen_count <= reset_cen_count + 3'd1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            warmup_count <= 3'd0;
            ready <= 1'b0;
            sample_d <= 1'b0;
        end else if (reset_cen_count != 3'd6) begin
            warmup_count <= 3'd0;
            ready <= 1'b0;
            sample_d <= core_sample;
        end else begin
            sample_d <= core_sample;
            if (!ready && core_sample && !sample_d && warmup_count < 3'd5)
                warmup_count <= warmup_count + 3'd1;
            if (!ready && !core_sample && sample_d && warmup_count == 3'd5)
                ready <= 1'b1;
        end
    end

    ym2610_hw0_jt12_top #(
        .use_lfo(1), .use_ssg(1), .num_ch(6),
        .use_pcm(0), .use_adpcm(1), .JT49_DIV(3)
    ) u_core (
        .rst(rst), .clk(clk), .cen(cen),
        .din(bus_din), .addr(bus_addr), .cs_n(bus_cs_n),
        .wr_n(bus_wr_n), .ladder(1'b0),
        .dout(bus_dout), .irq_n(irq_n), .en_hifi_pcm(1'b0),
        .adpcma_addr(adpcma_addr), .adpcma_bank(adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n), .adpcma_data(adpcma_data),
        .adpcmb_addr(adpcmb_addr), .adpcmb_data(adpcmb_data),
        .adpcmb_roe_n(adpcmb_roe_n),
        .IOA_in(8'h00), .IOB_in(8'h00),
        .psg_A(psg_a), .psg_B(psg_b), .psg_C(psg_c),
        .fm_snd_left(), .fm_snd_right(unused_fm_right),
        .adpcmA_l(), .adpcmA_r(), .adpcmB_l(), .adpcmB_r(),
        .psg_snd(psg_snd), .snd_right(core_right),
        .snd_left(core_left), .snd_sample(core_sample),
        .debug_bus(8'h00), .debug_view(unused_debug),
        .hw0_adpcma_eos(adpcma_eos),
        .hw0_adpcma_command(adpcma_command),
        .hw0_adpcmb_eos(adpcmb_eos),
        .hw0_adpcmb_active(adpcmb_active),
        .hw0_adpcmb_command_update(adpcmb_command_update)
    );
endmodule

`timescale 1ns/1ps

module ym2610_hw0_top #(
    parameter bit FAST_SIM = 1'b0,
    parameter integer BOOT_SAMPLES = 32768
) (
    input  logic               clk_sys,
    input  logic               reset,
    output logic signed [15:0] audio_l,
    output logic signed [15:0] audio_r,
    output logic               audio_sample,
    output logic               video_ce,
    output logic               video_hs,
    output logic               video_vs,
    output logic               video_de,
    output logic         [7:0] video_r,
    output logic         [7:0] video_g,
    output logic         [7:0] video_b,
    output logic         [3:0] debug_phase,
    output logic         [7:0] debug_microcode_index,
    output logic        [31:0] debug_accepted_writes,
    output logic               debug_busy_timeout,
    output logic               debug_write_while_busy,
    output logic        [15:0] debug_restart_count,
    output logic               debug_measurement_active,
    output logic         [3:0] debug_measurement_phase,
    output logic               debug_adpcma_request,
    output logic               debug_adpcmb_request,
    output logic         [5:0] debug_adpcma_eos,
    output logic               debug_adpcmb_eos,
    output logic               debug_adpcmb_active,
    output logic        [19:0] debug_adpcma_addr,
    output logic         [3:0] debug_adpcma_bank,
    output logic        [23:0] debug_adpcmb_addr,
    output logic         [7:0] debug_psg_a,
    output logic         [7:0] debug_psg_b,
    output logic         [7:0] debug_psg_c,
    output logic         [9:0] debug_psg_snd,
    output logic               debug_core_ready,
    output logic         [2:0] debug_reset_cen_count,
    output logic               debug_halted
);
    localparam logic [24:0] JT10_NTSC_CEN_INC = 25'd6434443;

    logic [23:0] cen_accum;
    logic [24:0] cen_sum;
    logic        jt10_cen;
    logic [8:0]  chip_cycle_mod432;

    logic [1:0] bus_addr;
    logic [7:0] bus_din;
    logic       bus_cs_n;
    logic       bus_wr_n;
    logic [7:0] bus_dout;
    logic       irq_n;
    logic signed [15:0] core_left;
    logic signed [15:0] core_right;
    logic       core_sample;
    logic signed [15:0] internal_left;
    logic signed [15:0] internal_right;
    logic       internal_sample;
    logic [5:0] adpcma_command;
    logic       adpcmb_command_update;
    logic [7:0] adpcma_data;
    logic [7:0] adpcmb_data;
    logic       adpcma_roe_n;
    logic       adpcmb_roe_n;

    assign cen_sum = {1'b0, cen_accum} + JT10_NTSC_CEN_INC;

    always_ff @(posedge clk_sys) begin
        if (reset) begin
            cen_accum <= 24'd0;
            jt10_cen <= 1'b1;
        end else if (FAST_SIM) begin
            cen_accum <= 24'd0;
            jt10_cen <= 1'b1;
        end else begin
            cen_accum <= cen_sum[23:0];
            jt10_cen <= cen_sum[24];
        end
    end

    always_ff @(posedge clk_sys) begin
        if (reset) chip_cycle_mod432 <= 9'd0;
        else if (jt10_cen) begin
            if (chip_cycle_mod432 == 9'd431)
                chip_cycle_mod432 <= 9'd0;
            else chip_cycle_mod432 <= chip_cycle_mod432 + 9'd1;
        end
    end

    ym2610_hw0_adpcma_rom u_rom_a (
        .address(debug_adpcma_addr), .bank(debug_adpcma_bank),
        .data(adpcma_data)
    );
    ym2610_hw0_adpcmb_rom u_rom_b (
        .address(debug_adpcmb_addr), .data(adpcmb_data)
    );

    ym2610_hw0_jt10_wrapper u_jt10 (
        .clk(clk_sys), .rst(reset), .cen(jt10_cen),
        .bus_addr(bus_addr), .bus_din(bus_din),
        .bus_cs_n(bus_cs_n), .bus_wr_n(bus_wr_n),
        .bus_dout(bus_dout), .irq_n(irq_n),
        .snd_left(core_left), .snd_right(core_right),
        .snd_sample(core_sample),
        .psg_a(debug_psg_a), .psg_b(debug_psg_b),
        .psg_c(debug_psg_c), .psg_snd(debug_psg_snd),
        .adpcma_addr(debug_adpcma_addr),
        .adpcma_bank(debug_adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n),
        .adpcma_data(adpcma_data),
        .adpcmb_addr(debug_adpcmb_addr),
        .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(adpcmb_data),
        .ready(debug_core_ready),
        .reset_cen_count(debug_reset_cen_count),
        .adpcma_eos(debug_adpcma_eos),
        .adpcma_command(adpcma_command),
        .adpcmb_eos(debug_adpcmb_eos),
        .adpcmb_active(debug_adpcmb_active),
        .adpcmb_command_update(adpcmb_command_update),
        .internal_left(internal_left), .internal_right(internal_right),
        .internal_sample(internal_sample)
    );

    // ROM output-enable pins are active low; expose active-high requests.
    always_comb begin
        debug_adpcma_request = !adpcma_roe_n;
        debug_adpcmb_request = !adpcmb_roe_n;
    end

    ym2610_hw0_sequencer #(
        .FAST_SIM(FAST_SIM), .BOOT_SAMPLES(BOOT_SAMPLES)
    ) u_sequencer (
        .clk(clk_sys), .reset(reset), .core_ready(debug_core_ready),
        .audio_zero(core_left == 16'sd0 && core_right == 16'sd0),
        .sample_strobe(core_sample),
        .chip_cycle_mod432(chip_cycle_mod432), .bus_dout(bus_dout),
        .adpcmb_eos(debug_adpcmb_eos),
        .adpcmb_active(debug_adpcmb_active),
        .bus_addr(bus_addr), .bus_din(bus_din),
        .bus_cs_n(bus_cs_n), .bus_wr_n(bus_wr_n),
        .test_phase(debug_phase),
        .microcode_index(debug_microcode_index),
        .accepted_write_count(debug_accepted_writes),
        .busy_timeout(debug_busy_timeout),
        .write_while_busy(debug_write_while_busy),
        .sequence_restart_count(debug_restart_count),
        .measurement_active(debug_measurement_active),
        .measurement_phase(debug_measurement_phase),
        .halted(debug_halted)
    );

    assign audio_l = debug_halted ? 16'sd0 : core_left;
    assign audio_r = debug_halted ? 16'sd0 : core_right;
    assign audio_sample = debug_halted ? 1'b0 : core_sample;

    ym2610_hw0_video u_video (
        .clk(clk_sys), .reset(reset), .phase(debug_phase),
        .error(debug_halted), .ce_pixel(video_ce),
        .hsync(video_hs), .vsync(video_vs), .de(video_de),
        .r(video_r), .g(video_g), .b(video_b)
    );
endmodule

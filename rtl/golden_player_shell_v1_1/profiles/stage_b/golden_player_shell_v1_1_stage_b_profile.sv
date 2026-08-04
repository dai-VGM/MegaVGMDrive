// SPDX-License-Identifier: GPL-2.0-or-later
// Golden Player Shell v1.1 adapter for the immutable Stage B scanner stack.

`timescale 1ns/1ps

module golden_player_shell_v1_1_profile #(
    parameter int VGM_ADDR_WIDTH = 23,
    parameter int CLK_SYS_HZ = 20_000_000
) (
    input  logic                      clk_sys,
    input  logic                      reset,
    input  logic                      download_active,
    input  logic [31:0]               uploaded_physical_size,
    input  logic                      upload_complete,
    input  logic                      file_read_ready,
    input  logic                      file_read_valid,
    input  logic [7:0]                file_read_data,
    output logic                      file_read_request,
    output logic [VGM_ADDR_WIDTH-1:0] file_read_address,
    output logic                      pcm_a_read_request,
    output logic [VGM_ADDR_WIDTH-1:0] pcm_a_read_address,
    output logic                      pcm_b_read_request,
    output logic [VGM_ADDR_WIDTH-1:0] pcm_b_read_address,
    input  logic [1:0]                osd_audio_lpf_mode,
    input  logic                      osd_audio_gain_boost,
    input  logic [1:0]                osd_audio_psg_level,
    input  logic                      title_valid,
    input  logic [7:0]                title_text_byte,
    input  logic                      shell_sample_timing,
    output logic signed [15:0]        profile_audio_l,
    output logic signed [15:0]        profile_audio_r,
    output logic                      profile_audio_sample_valid,
    output logic                      profile_audio_enable,
    output logic                      playback_active,
    output logic                      profile_fatal,
    output logic [15:0]               profile_status,
    output logic [15:0]               debug_page_data,
    output logic [31:0]               parser_start_count,
    output logic [31:0]               scanner_start_count,
    output logic [31:0]               sound_write_count
);
    logic signed [15:0] stage_b_audio_l;
    logic signed [15:0] stage_b_audio_r;
    logic               stage_b_audio_sample_valid;

    // This is the hardware-PASS Stage B profile, not a copied scanner. It
    // directly owns the one scanner/read client and its generation contract.
    ym2610_golden_stage_a #(
        .VGM_ADDR_WIDTH(VGM_ADDR_WIDTH)
    ) stage_b_core (
        .clk_sys(clk_sys),
        .reset(reset),
        .download_active(download_active),
        .uploaded_physical_size(uploaded_physical_size),
        .upload_complete(upload_complete),
        .file_read_ready(file_read_ready),
        .file_read_valid(file_read_valid),
        .file_read_data(file_read_data),
        .file_read_request(file_read_request),
        .file_read_address(file_read_address),
        .pcm_a_read_request(pcm_a_read_request),
        .pcm_a_read_address(pcm_a_read_address),
        .pcm_b_read_request(pcm_b_read_request),
        .pcm_b_read_address(pcm_b_read_address),
        .osd_audio_lpf_mode(osd_audio_lpf_mode),
        .osd_audio_gain_boost(osd_audio_gain_boost),
        .osd_audio_psg_level(osd_audio_psg_level),
        .title_valid(title_valid),
        .title_text_byte(title_text_byte),
        .shell_sample_timing(shell_sample_timing),
        .audio_l(stage_b_audio_l),
        .audio_r(stage_b_audio_r),
        .audio_sample_valid(stage_b_audio_sample_valid),
        .playback_active(playback_active),
        .profile_fatal(profile_fatal),
        .profile_status(profile_status),
        .debug_page_data(debug_page_data),
        .parser_start_count(parser_start_count),
        .scanner_start_count(scanner_start_count),
        .sound_write_count(sound_write_count)
    );

    // Stage B never opens the v1.1 audio contract. The clocked authority is
    // reset-safe and remains zero for accepted/rejected scans and every reload.
    always_ff @(posedge clk_sys) begin
        if (reset)
            profile_audio_enable <= 1'b0;
        else
            profile_audio_enable <= 1'b0;
    end

    assign profile_audio_l = 16'sd0;
    assign profile_audio_r = 16'sd0;
    assign profile_audio_sample_valid = 1'b0;

    wire unused_stage_b_contract = ^{
        CLK_SYS_HZ, stage_b_audio_l, stage_b_audio_r,
        stage_b_audio_sample_valid
    };
endmodule

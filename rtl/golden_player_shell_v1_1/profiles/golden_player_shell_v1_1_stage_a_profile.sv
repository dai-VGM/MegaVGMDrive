// SPDX-License-Identifier: GPL-2.0-or-later
// Golden Player Shell v1.1 Stage A inert profile.

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
    // Keep the ABI authority clocked and reset-safe even though Stage A can
    // never enable it. Synthesis may reduce this invariant to a constant.
    always_ff @(posedge clk_sys) begin
        if (reset)
            profile_audio_enable <= 1'b0;
        else
            profile_audio_enable <= 1'b0;
    end

    assign file_read_request = 1'b0;
    assign file_read_address = '0;
    assign pcm_a_read_request = 1'b0;
    assign pcm_a_read_address = '0;
    assign pcm_b_read_request = 1'b0;
    assign pcm_b_read_address = '0;
    assign profile_audio_l = 16'sd0;
    assign profile_audio_r = 16'sd0;
    assign profile_audio_sample_valid = 1'b0;
    assign playback_active = 1'b0;
    assign profile_fatal = 1'b0;
    assign profile_status = 16'd0;
    assign debug_page_data = 16'd0;
    assign parser_start_count = 32'd0;
    assign scanner_start_count = 32'd0;
    assign sound_write_count = 32'd0;

    wire unused_inputs = ^{
        download_active, uploaded_physical_size, upload_complete,
        file_read_ready, file_read_valid, file_read_data,
        osd_audio_lpf_mode, osd_audio_gain_boost, osd_audio_psg_level,
        title_valid, title_text_byte, shell_sample_timing, CLK_SYS_HZ
    };
endmodule

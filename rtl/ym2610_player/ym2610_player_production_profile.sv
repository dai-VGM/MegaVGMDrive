// SPDX-License-Identifier: GPL-2.0-or-later
//
// YM2610 production profile for the immutable Golden Player Shell v1.1 ABI.
// The shell owns HPS/ioctl, physical DDR upload, title, video, and reset. This
// module is only the logical DDR client and the already-validated YM2610
// player/audio backend.

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
    logic download_q;
    logic upload_session_armed;
    logic core_load_done_pulse;
    logic [7:0] load_generation;

    logic core_mem_req;
    logic [VGM_ADDR_WIDTH-1:0] core_mem_addr;
    logic signed [15:0] core_audio_l;
    logic signed [15:0] core_audio_r;
    logic core_audio_sample;
    logic core_external_mute;
    logic [31:0] core_start_count;
    logic [31:0] core_scanner_start_count;
    logic [3:0] core_load_state;
    logic [31:0] core_parser_command_count;
    logic core_fatal;
    logic [7:0] core_fatal_code;

    // The physical backend's upload_complete level is asserted only after an
    // accepted index-1 upload has ended and its final write has drained. One
    // generation is allocated at the raw download edge and published once,
    // after raw download has returned low. No backend debug signal participates.
    always_ff @(posedge clk_sys) begin
        core_load_done_pulse <= 1'b0;
        if (reset) begin
            download_q <= 1'b0;
            upload_session_armed <= 1'b0;
            load_generation <= 8'd0;
        end else begin
            download_q <= download_active;

            if (download_active && !download_q) begin
                upload_session_armed <= 1'b1;
                load_generation <= load_generation + 8'd1;
            end

            if (upload_session_armed && upload_complete &&
                !download_active) begin
                core_load_done_pulse <= 1'b1;
                upload_session_armed <= 1'b0;
            end
        end
    end

    ym2610_player_core #(
        .SYS_CLK_HZ(CLK_SYS_HZ),
        .ADDR_WIDTH(VGM_ADDR_WIDTH)
    ) production_player (
        .clk(clk_sys),
        .hard_reset(reset),
        .soft_reset(1'b0),
        .ioctl_download(download_active),
        .load_done_pulse(core_load_done_pulse),
        .file_size(uploaded_physical_size),
        .load_generation(load_generation),
        .mem_req(core_mem_req),
        .mem_addr(core_mem_addr),
        .mem_ready(file_read_ready),
        .mem_valid(file_read_valid),
        .mem_data(file_read_data),
        .audio_l(core_audio_l),
        .audio_r(core_audio_r),
        .audio_sample(core_audio_sample),
        .external_mute(core_external_mute),
        .start_pulse(),
        .start_count(core_start_count),
        .scanner_start_count(core_scanner_start_count),
        .load_state(core_load_state),
        .scanner_state(),
        .parser_state(),
        .parser_command_count(core_parser_command_count),
        .fatal_active(core_fatal),
        .fatal_code(core_fatal_code),
        .classification(),
        .raw_variant_b(),
        .reject_code(),
        .original_size(),
        .parser_pc(),
        .parser_opcode(),
        .wait_remaining(),
        .parser_samples(),
        .parser_writes(),
        .port0_writes(),
        .port1_writes(),
        .loop_count(),
        .descriptor_a_count(),
        .descriptor_b_count(),
        .b_only_writes(),
        .unknown_writes(),
        .first_bad_pc(),
        .first_bad_port(),
        .first_bad_address(),
        .first_bad_data(),
        .unsupported_pc(),
        .unsupported_opcode(),
        .pcm_requests(),
        .pcm_responses(),
        .adpcma_requests(),
        .adpcmb_requests(),
        .pcm_last_address(),
        .adpcma_last_address(),
        .adpcmb_last_address(),
        .adpcma_fetch_requests(),
        .adpcma_fetch_responses(),
        .adpcmb_fetch_requests(),
        .adpcmb_fetch_responses(),
        .pcm_occupancy(),
        .parser_underflow(),
        .adpcma_underflow(),
        .adpcmb_underflow(),
        .stale_response(),
        .owner_mismatch(),
        .busy_timeout(),
        .write_while_busy(),
        .memory_timeout(),
        .memory_request_held(),
        .memory_outstanding(),
        .memory_held_owner(),
        .memory_outstanding_owner(),
        .last_memory_accept_addr(),
        .last_memory_response_addr(),
        .last_memory_accept_generation(),
        .last_memory_response_generation(),
        .pcm_request_held(),
        .pcm_response_pending(),
        .pcm_held_space_b(),
        .pcm_held_logical_addr(),
        .player_heartbeat(),
        .ddr_heartbeat(),
        .peak_l(),
        .peak_r(),
        .psg_a(),
        .psg_b(),
        .psg_c(),
        .psg_snd(),
        .adpcma_l(),
        .adpcma_r(),
        .adpcmb_l(),
        .adpcmb_r()
    );

    assign file_read_request = core_mem_req;
    assign file_read_address = core_mem_addr;

    // The existing player core already arbitrates scanner, parser, and both
    // PCM spaces onto the single immutable shell read-client boundary.
    assign pcm_a_read_request = 1'b0;
    assign pcm_a_read_address = '0;
    assign pcm_b_read_request = 1'b0;
    assign pcm_b_read_address = '0;

    // Normal mode is a wire-only handoff. No YM2610 selector or post-mix
    // arithmetic is introduced in this candidate.
    assign profile_audio_l = core_audio_l;
    assign profile_audio_r = core_audio_r;
    assign profile_audio_sample_valid = core_audio_sample;
    assign profile_audio_enable = !reset && !core_external_mute;
    assign playback_active = core_load_state == 4'd7;
    assign profile_fatal = core_fatal;
    assign profile_status = {core_fatal, 3'd0, core_fatal_code,
                             core_load_state};
    assign debug_page_data = 16'd0;
    assign parser_start_count = core_start_count;
    assign scanner_start_count = core_scanner_start_count;
    assign sound_write_count = core_parser_command_count;

    wire unused_shell_profile_inputs = ^{
        osd_audio_lpf_mode,
        osd_audio_gain_boost,
        osd_audio_psg_level,
        title_valid,
        title_text_byte,
        shell_sample_timing
    };

endmodule

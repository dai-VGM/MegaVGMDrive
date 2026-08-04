// SPDX-License-Identifier: GPL-2.0-or-later
// Golden Player Shell v1.1 adapter for the immutable YM2610 Stage C profile.

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
    localparam logic [4:0] LC_SOUND_ZERO_WAIT = 5'd9;
    localparam logic [4:0] LC_PLAYBACK_ARM    = 5'd10;
    localparam logic [4:0] LC_PLAYBACK        = 5'd11;

    logic signed [15:0] stage_c_audio_l;
    logic signed [15:0] stage_c_audio_r;
    logic               stage_c_audio_sample_valid;
    logic               stage_c_playback_active;
    logic               stage_c_profile_fatal;
    logic [15:0]        stage_c_profile_status;
    logic [15:0]        stage_c_debug_page_data;

    wire [4:0] stage_c_lifecycle = stage_c_profile_status[7:3];
    wire stage_c_parser_owned = stage_c_profile_status[14];
    wire stage_c_reader_outstanding = stage_c_profile_status[13];
    wire stage_c_sound_ready = stage_c_profile_status[12];
    wire stage_c_pcm_request_fault = stage_c_profile_status[11];
    wire stage_c_pcm_activity_fault = stage_c_profile_status[10];
    wire stage_c_parser_ended = stage_c_debug_page_data[0];

    // This is a direct instance of the existing Stage C public profile. The
    // scanner, owner, parser, sound adapter, wait engine, and JT10/JT49 path
    // remain in their original source blobs.
    ym2610_golden_stage_a #(
        .VGM_ADDR_WIDTH(VGM_ADDR_WIDTH),
        .CLK_SYS_HZ(CLK_SYS_HZ)
    ) stage_c_core (
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
        .audio_l(stage_c_audio_l),
        .audio_r(stage_c_audio_r),
        .audio_sample_valid(stage_c_audio_sample_valid),
        .playback_active(stage_c_playback_active),
        .profile_fatal(stage_c_profile_fatal),
        .profile_status(stage_c_profile_status),
        .debug_page_data(stage_c_debug_page_data),
        .parser_start_count(parser_start_count),
        .scanner_start_count(scanner_start_count),
        .sound_write_count(sound_write_count)
    );

    // The Stage C profile enters PLAYBACK_ARM only after its explicit sound
    // reset, reset-CEN warmup, BUSY-clear/core-ready observation, and a known
    // zero public sample. Opening here makes the registered gate visible for
    // one full clk_sys cycle before the parser consumes its registered start
    // pulse. A false precondition fails closed; no hierarchy is consulted.
    always_ff @(posedge clk_sys) begin
        case ({reset, download_active})
            2'b00: begin
                case (stage_c_lifecycle)
                    LC_PLAYBACK_ARM: begin
                        // Plain case matching makes every X/Z precondition
                        // take the default fail-closed path.
                        case ({stage_c_profile_fatal,
                               stage_c_pcm_request_fault,
                               stage_c_pcm_activity_fault,
                               stage_c_parser_owned,
                               stage_c_reader_outstanding,
                               stage_c_sound_ready,
                               stage_c_audio_sample_valid,
                               stage_c_audio_l,
                               stage_c_audio_r})
                            {1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0,
                             16'sd0, 16'sd0}:
                                profile_audio_enable <= 1'b1;
                            default: profile_audio_enable <= 1'b0;
                        endcase
                    end

                    LC_PLAYBACK: begin
                        case ({stage_c_profile_fatal,
                               stage_c_pcm_request_fault,
                               stage_c_pcm_activity_fault,
                               profile_audio_enable,
                               stage_c_parser_owned,
                               stage_c_sound_ready,
                               stage_c_playback_active,
                               stage_c_parser_ended})
                            8'b0001_1110:
                                profile_audio_enable <= 1'b1;
                            default: profile_audio_enable <= 1'b0;
                        endcase
                    end

                    default: profile_audio_enable <= 1'b0;
                endcase
            end

            default: profile_audio_enable <= 1'b0;
        endcase
    end

    assign profile_audio_l =
        profile_audio_enable ? stage_c_audio_l : 16'sd0;
    assign profile_audio_r =
        profile_audio_enable ? stage_c_audio_r : 16'sd0;
    assign profile_audio_sample_valid =
        profile_audio_enable ? stage_c_audio_sample_valid : 1'b0;
    assign playback_active = stage_c_playback_active;
    assign profile_fatal = stage_c_profile_fatal;
    assign profile_status = stage_c_profile_status;
    assign debug_page_data = stage_c_debug_page_data;

    // LC_SOUND_ZERO_WAIT is intentionally decoded only for audit visibility:
    // core-ready alone is not accepted as proof of the Stage C zero sample.
    wire unused_zero_wait_contract =
        stage_c_lifecycle == LC_SOUND_ZERO_WAIT;
endmodule

// SPDX-License-Identifier: GPL-2.0-or-later
// Golden Player Shell v1.1 lab-only direct-audio contract profile.

`timescale 1ns/1ps

module golden_player_shell_v1_1_profile #(
    parameter int VGM_ADDR_WIDTH = 23,
    parameter int CLK_SYS_HZ = 20_000_000,
    parameter int SAMPLE_HZ = 44_100,
    parameter int SILENCE_SAMPLES = 88_200,
    parameter int TONE_SAMPLES = 44_100,
    parameter int TONE_HZ = 1_000,
    parameter logic signed [15:0] TONE_AMPLITUDE = 16'sd2048
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
    typedef enum logic [1:0] {
        LAB_SILENCE,
        LAB_TONE,
        LAB_IDLE
    } lab_state_t;

    lab_state_t state;
    logic [31:0] sample_accumulator;
    logic [32:0] sample_sum;
    logic sample_tick;
    logic [31:0] state_sample_count;
    logic [31:0] tone_phase;
    logic signed [15:0] held_sample;

    assign sample_sum = {1'b0, sample_accumulator} + SAMPLE_HZ;

    always_ff @(posedge clk_sys) begin
        if (reset || download_active) begin
            sample_accumulator <= 32'd0;
            sample_tick <= 1'b0;
        end else if (sample_sum >= CLK_SYS_HZ) begin
            sample_accumulator <= sample_sum[31:0] - CLK_SYS_HZ;
            sample_tick <= 1'b1;
        end else begin
            sample_accumulator <= sample_sum[31:0];
            sample_tick <= 1'b0;
        end
    end

    always_ff @(posedge clk_sys) begin
        if (reset) begin
            state <= LAB_SILENCE;
            state_sample_count <= 32'd0;
            tone_phase <= 32'd0;
            held_sample <= 16'sd0;
            profile_audio_enable <= 1'b0;
        end else if (download_active) begin
            // Loading never starts audio. Abort a pending/running lab sequence
            // and remain idle until software Reset explicitly rearms it.
            state <= LAB_IDLE;
            state_sample_count <= 32'd0;
            tone_phase <= 32'd0;
            held_sample <= 16'sd0;
            profile_audio_enable <= 1'b0;
        end else if (sample_tick) begin
            case (state)
                LAB_SILENCE: begin
                    held_sample <= 16'sd0;
                    profile_audio_enable <= 1'b0;
                    if (state_sample_count == SILENCE_SAMPLES-1) begin
                        state <= LAB_TONE;
                        state_sample_count <= 32'd0;
                        tone_phase <= 32'd0;
                        held_sample <= TONE_AMPLITUDE;
                        profile_audio_enable <= 1'b1;
                    end else begin
                        state_sample_count <= state_sample_count + 32'd1;
                    end
                end

                LAB_TONE: begin
                    held_sample <=
                        tone_phase < (SAMPLE_HZ / 2) ?
                        TONE_AMPLITUDE : -TONE_AMPLITUDE;
                    if (tone_phase + TONE_HZ >= SAMPLE_HZ)
                        tone_phase <= tone_phase + TONE_HZ - SAMPLE_HZ;
                    else
                        tone_phase <= tone_phase + TONE_HZ;
                    if (state_sample_count == TONE_SAMPLES-1) begin
                        state <= LAB_IDLE;
                        state_sample_count <= 32'd0;
                        held_sample <= 16'sd0;
                        profile_audio_enable <= 1'b0;
                    end else begin
                        state_sample_count <= state_sample_count + 32'd1;
                    end
                end

                default: begin
                    state <= LAB_IDLE;
                    state_sample_count <= 32'd0;
                    tone_phase <= 32'd0;
                    held_sample <= 16'sd0;
                    profile_audio_enable <= 1'b0;
                end
            endcase
        end
    end

    assign profile_audio_l = profile_audio_enable ? held_sample : 16'sd0;
    assign profile_audio_r = profile_audio_enable ? held_sample : 16'sd0;
    assign profile_audio_sample_valid = profile_audio_enable && sample_tick;

    assign file_read_request = 1'b0;
    assign file_read_address = '0;
    assign pcm_a_read_request = 1'b0;
    assign pcm_a_read_address = '0;
    assign pcm_b_read_request = 1'b0;
    assign pcm_b_read_address = '0;
    assign playback_active = 1'b0;
    assign profile_fatal = 1'b0;
    assign profile_status = {13'd0, state, profile_audio_enable};
    assign debug_page_data = 16'd0;
    assign parser_start_count = 32'd0;
    assign scanner_start_count = 32'd0;
    assign sound_write_count = 32'd0;

    wire unused_inputs = ^{
        uploaded_physical_size, upload_complete, file_read_ready,
        file_read_valid, file_read_data, osd_audio_lpf_mode,
        osd_audio_gain_boost, osd_audio_psg_level, title_valid,
        title_text_byte, shell_sample_timing
    };
endmodule

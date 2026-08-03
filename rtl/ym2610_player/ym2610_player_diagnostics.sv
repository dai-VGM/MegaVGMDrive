`timescale 1ns/1ps

// Lightweight first-fatal recorder.  Live progress is sampled until the first
// fatal state, then frozen until POR/software reset or the next upload.  Video
// heartbeats intentionally bypass this recorder so they continue visibly.
module ym2610_player_diagnostics (
    input  logic        clk,
    input  logic        reset,
    input  logic        fatal_active,
    input  logic [7:0]  fatal_code,
    input  logic [3:0]  player_state,
    input  logic [4:0]  scanner_state,
    input  logic [3:0]  parser_state,
    input  logic        memory_request,
    input  logic        request_held,
    input  logic        outstanding,
    input  logic        ddram_busy,
    input  logic [1:0]  held_owner,
    input  logic [1:0]  outstanding_owner,
    input  logic [22:0] last_accept_addr,
    input  logic [22:0] last_response_addr,
    input  logic [7:0]  load_generation,
    input  logic [7:0]  last_accept_generation,
    input  logic [7:0]  last_response_generation,
    input  logic [31:0] player_heartbeat,
    input  logic [31:0] ddr_heartbeat,
    input  logic [31:0] scanner_start_count,
    input  logic [31:0] playback_start_count,
    input  logic [31:0] parser_command_count,
    input  logic [31:0] adpcma_fetch_requests,
    input  logic [31:0] adpcma_fetch_responses,
    input  logic [31:0] adpcmb_fetch_requests,
    input  logic [31:0] adpcmb_fetch_responses,
    input  logic [15:0] upload_fifo_debug,
    input  logic        upload_partial_valid,
    input  logic        pcm_request_held,
    input  logic        pcm_response_pending,
    input  logic        pcm_held_space_b,
    input  logic        parser_underflow,
    input  logic        adpcma_underflow,
    input  logic        adpcmb_underflow,
    input  logic        stale_response,
    input  logic        owner_mismatch,
    input  logic        response_timeout,

    output logic [7:0]  first_fatal_code,
    output logic [3:0]  recorded_player_state,
    output logic [4:0]  recorded_scanner_state,
    output logic [3:0]  recorded_parser_state,
    output logic        recorded_memory_request,
    output logic        recorded_request_held,
    output logic        recorded_outstanding,
    output logic        recorded_ddram_busy,
    output logic [1:0]  recorded_held_owner,
    output logic [1:0]  recorded_outstanding_owner,
    output logic [22:0] recorded_last_accept_addr,
    output logic [22:0] recorded_last_response_addr,
    output logic [7:0]  recorded_load_generation,
    output logic [7:0]  recorded_last_accept_generation,
    output logic [7:0]  recorded_last_response_generation,
    output logic [31:0] recorded_player_heartbeat,
    output logic [31:0] recorded_ddr_heartbeat,
    output logic [31:0] recorded_scanner_start_count,
    output logic [31:0] recorded_playback_start_count,
    output logic [31:0] recorded_parser_command_count,
    output logic [31:0] recorded_adpcma_fetch_requests,
    output logic [31:0] recorded_adpcma_fetch_responses,
    output logic [31:0] recorded_adpcmb_fetch_requests,
    output logic [31:0] recorded_adpcmb_fetch_responses,
    output logic [15:0] recorded_upload_fifo_debug,
    output logic        recorded_upload_partial_valid,
    output logic        recorded_pcm_request_held,
    output logic        recorded_pcm_response_pending,
    output logic        recorded_pcm_held_space_b,
    output logic [5:0]  recorded_error_flags
);
    logic fatal_q;

    always_ff @(posedge clk) begin
        if (reset) begin
            fatal_q <= 1'b0;
            first_fatal_code <= 8'd0;
            recorded_player_state <= 4'd0;
            recorded_scanner_state <= 5'd0;
            recorded_parser_state <= 4'd0;
            recorded_memory_request <= 1'b0;
            recorded_request_held <= 1'b0;
            recorded_outstanding <= 1'b0;
            recorded_ddram_busy <= 1'b0;
            recorded_held_owner <= 2'd0;
            recorded_outstanding_owner <= 2'd0;
            recorded_last_accept_addr <= 23'd0;
            recorded_last_response_addr <= 23'd0;
            recorded_load_generation <= 8'd0;
            recorded_last_accept_generation <= 8'd0;
            recorded_last_response_generation <= 8'd0;
            recorded_player_heartbeat <= 32'd0;
            recorded_ddr_heartbeat <= 32'd0;
            recorded_scanner_start_count <= 32'd0;
            recorded_playback_start_count <= 32'd0;
            recorded_parser_command_count <= 32'd0;
            recorded_adpcma_fetch_requests <= 32'd0;
            recorded_adpcma_fetch_responses <= 32'd0;
            recorded_adpcmb_fetch_requests <= 32'd0;
            recorded_adpcmb_fetch_responses <= 32'd0;
            recorded_upload_fifo_debug <= 16'd0;
            recorded_upload_partial_valid <= 1'b0;
            recorded_pcm_request_held <= 1'b0;
            recorded_pcm_response_pending <= 1'b0;
            recorded_pcm_held_space_b <= 1'b0;
            recorded_error_flags <= 6'd0;
        end else begin
            fatal_q <= fatal_active;
            if (fatal_active && !fatal_q)
                first_fatal_code <= fatal_code;
            if (!fatal_active) begin
                recorded_player_state <= player_state;
                recorded_scanner_state <= scanner_state;
                recorded_parser_state <= parser_state;
                recorded_memory_request <= memory_request;
                recorded_request_held <= request_held;
                recorded_outstanding <= outstanding;
                recorded_ddram_busy <= ddram_busy;
                recorded_held_owner <= held_owner;
                recorded_outstanding_owner <= outstanding_owner;
                recorded_last_accept_addr <= last_accept_addr;
                recorded_last_response_addr <= last_response_addr;
                recorded_load_generation <= load_generation;
                recorded_last_accept_generation <= last_accept_generation;
                recorded_last_response_generation <= last_response_generation;
                recorded_player_heartbeat <= player_heartbeat;
                recorded_ddr_heartbeat <= ddr_heartbeat;
                recorded_scanner_start_count <= scanner_start_count;
                recorded_playback_start_count <= playback_start_count;
                recorded_parser_command_count <= parser_command_count;
                recorded_adpcma_fetch_requests <= adpcma_fetch_requests;
                recorded_adpcma_fetch_responses <= adpcma_fetch_responses;
                recorded_adpcmb_fetch_requests <= adpcmb_fetch_requests;
                recorded_adpcmb_fetch_responses <= adpcmb_fetch_responses;
                recorded_upload_fifo_debug <= upload_fifo_debug;
                recorded_upload_partial_valid <= upload_partial_valid;
                recorded_pcm_request_held <= pcm_request_held;
                recorded_pcm_response_pending <= pcm_response_pending;
                recorded_pcm_held_space_b <= pcm_held_space_b;
                recorded_error_flags <= {response_timeout, owner_mismatch,
                    stale_response, adpcmb_underflow, adpcma_underflow,
                    parser_underflow};
            end
        end
    end
endmodule

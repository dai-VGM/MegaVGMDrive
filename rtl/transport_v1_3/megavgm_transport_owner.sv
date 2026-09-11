// SPDX-License-Identifier: GPL-2.0-or-later
// Interface wrapper from Phase1B; versioned v1.3 shared owner body below.
// Generic owner: caller supplies admitted-session/parser/audio facts.
module megavgm_transport_owner #(
    parameter logic [15:0] VGM_LOAD_FILE_INDEX=16'd1,
    parameter logic [15:0] MODE5_TRANSITION_FILE_INDEX=16'd2,
    parameter logic [31:0] MODE5_TRACK_FADE_CYCLES=32'd2_000_000,
    parameter logic [31:0] MODE5_LOOP_LIMIT_FADE_SAMPLES=32'd88200
)(
    input logic clk, reset,
    input logic ioctl_download, ioctl_wr,
    input logic [15:0] ioctl_index,
    input logic [26:0] ioctl_addr,
    input logic [7:0] ioctl_dout,
    input logic mode5_backend_ioctl_wait,
    input logic playback_started, player_busy, loaded_player_done,
    input logic [31:0] session_id,
    input logic vgm_load_busy, vgm_load_error, vgm_load_overflow, vgm_player_error,
    input logic audio_runtime_open,
    input logic [31:0] vgm_wait_ticks_consumed_debug,
    input logic mode5_player_loop_entry_pulse, mode5_player_loop_boundary_pulse,
    output wire mode5_ioctl_download, mode5_ioctl_wr, ioctl_wait,
    output wire mode5_load_begin_pulse, halt_loop,
    output wire [8:0] gain,
    output wire fade_active, released, end_pulse, loop_limit_active
);
    wire mode5_playback_started=playback_started;
    wire mode5_done_armed_i=playback_started;
    wire [31:0] mode5_done_armed_session_id_i=session_id;
    wire [31:0] mode5_playback_session_id_i=session_id;
    wire mode5_load_session_active=!playback_started;
    logic mode5_ioctl_download_d=0,mode5_host_ioctl_download_d=0,player_done_d=0;
    wire mode5_transition_wait,mode5_parser_done_edge,mode5_done_edge;
    always_ff @(posedge clk) begin
        if(reset) begin mode5_ioctl_download_d<=0;player_done_d<=0;end
        else begin mode5_ioctl_download_d<=mode5_ioctl_download;player_done_d<=loaded_player_done;end
    end
logic mode5_audio_ever_open = 1'b0;
logic mode5_transition_fade_active = 1'b0;
logic mode5_transition_end_pending = 1'b0;
logic mode5_transition_released = 1'b0;
logic mode5_transition_end_pulse = 1'b0;
logic [31:0] mode5_transition_fade_counter = 32'd0;
logic [8:0] mode5_transition_gain = 9'd256;
logic mode5_transition_loop_limit_active = 1'b0;
logic mode5_transition_control_download_d = 1'b0;
logic mode5_transition_control_valid = 1'b0;
logic [3:0] mode5_transition_control_seen = 4'd0;
logic mode5_loop_limit_policy_pending = 1'b0;
logic mode5_loop_limit_policy_active = 1'b0;
logic mode5_loop_limit_policy_value = 1'b0;
logic mode5_loop_limit_policy_update_pulse = 1'b0;
logic mode5_loop_region_started = 1'b0;
logic mode5_loop_first_boundary_seen = 1'b0;
logic mode5_loop_second_active = 1'b0;
logic [31:0] mode5_loop_start_wait_ticks = 32'd0;
logic [31:0] mode5_loop_second_start_wait_ticks = 32'd0;
logic [31:0] mode5_loop_length_samples = 32'd0;
logic [31:0] mode5_loop_fade_start_samples = 32'd0;
logic [31:0] mode5_loop_fade_samples = 32'd0;
logic [39:0] mode5_loop_fade_accumulator = 40'd0;
logic [31:0] mode5_wait_ticks_consumed_d = 32'd0;
`include "rtl/transport_v1_3/owner_body.svh"

    assign gain=mode5_transition_gain;
    assign halt_loop=mode5_halt_at_loop_boundary;
    assign fade_active=mode5_transition_fade_active;
    assign released=mode5_transition_released;
    assign end_pulse=mode5_transition_end_pulse;
    assign loop_limit_active=mode5_transition_loop_limit_active;
endmodule

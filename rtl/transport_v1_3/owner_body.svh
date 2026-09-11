// SPDX-License-Identifier: GPL-2.0-or-later
// Transport v1.3 test extension. Shared source body for A and B; one fade owner.
// Reference: PlaylistLoopLab 294d63e / GoldenTransport Phase1B 744d51a.
localparam logic [7:0] POLICY_OFF=8'h00, POLICY_TWO_LOOPS=8'h01,
                       COMMAND_FADE_ONLY=8'h02;
logic [7:0] mode5_transition_command = POLICY_OFF;
logic mode5_fade_only_request = 1'b0;
logic mode5_fade_only_owned = 1'b0;
wire mode5_fade_only_accept;
wire mode5_fade_only_halted =
    mode5_fade_only_owned && mode5_transition_released &&
    (mode5_transition_gain == 9'd0) && !vgm_player_error &&
    !vgm_load_error && !vgm_load_overflow;
// Extend the existing owner's lifetime through ENDED; never re-arm on policy.
// The latch is ownership only, not a separate fade engine or reset generator.
always_ff @(posedge clk) begin
    if (reset || mode5_load_begin_pulse) mode5_fade_only_owned <= 1'b0;
    else if (mode5_fade_only_accept) mode5_fade_only_owned <= 1'b1;
end
wire mode5_selected_download =
    ioctl_download && (ioctl_index == VGM_LOAD_FILE_INDEX);
wire mode5_transition_control_download =
    ioctl_download &&
    (ioctl_index == MODE5_TRANSITION_FILE_INDEX);
wire mode5_transition_start_load =
    mode5_selected_download && !mode5_ioctl_download_d &&
    !mode5_transition_fade_active &&
    !mode5_transition_released &&
    mode5_audio_ever_open &&
    (MODE5_TRACK_FADE_CYCLES != 32'd0);
assign mode5_transition_wait =
    mode5_transition_fade_active || mode5_transition_start_load;
assign mode5_ioctl_download =
    mode5_selected_download && !mode5_transition_wait;
assign mode5_ioctl_wr =
    ioctl_wr && mode5_selected_download && !mode5_transition_wait;
// Transport policy records must remain serviceable while an
// audible transition owns index 1; Repeat One can therefore
// cancel a pending loop-limit fade without opening a second VGM
// download. Backend wait remains authoritative for index 1.
assign ioctl_wait =
    (mode5_selected_download && mode5_transition_wait) |
    mode5_backend_ioctl_wait;
assign mode5_load_begin_pulse =
    mode5_ioctl_download && !mode5_ioctl_download_d &&
    (ioctl_index == VGM_LOAD_FILE_INDEX);
assign mode5_parser_done_edge =
    loaded_player_done &&
    !player_done_d &&
    mode5_playback_started &&
    mode5_done_armed_i &&
    (mode5_done_armed_session_id_i == mode5_playback_session_id_i) &&
    !mode5_load_session_active &&
    !vgm_load_busy &&
    !vgm_load_error &&
    !vgm_load_overflow &&
    !vgm_player_error;
assign mode5_done_edge = mode5_transition_end_pulse;

localparam logic [31:0] MODE5_TRACK_FADE_STEP_CYCLES =
    (MODE5_TRACK_FADE_CYCLES < 32'd256) ? 32'd1 :
    ((MODE5_TRACK_FADE_CYCLES + 32'd255) >> 8);
wire [31:0] mode5_loop_second_samples =
    vgm_wait_ticks_consumed_debug -
    mode5_loop_second_start_wait_ticks;
wire mode5_loop_fade_due =
    mode5_loop_limit_policy_active &&
    mode5_loop_first_boundary_seen &&
    mode5_loop_second_active &&
    !mode5_transition_fade_active &&
    (mode5_loop_second_samples >=
     mode5_loop_fade_start_samples);
wire mode5_loop_wait_tick =
    vgm_wait_ticks_consumed_debug !=
    mode5_wait_ticks_consumed_d;
wire [40:0] mode5_loop_fade_accumulator_next =
    {1'b0, mode5_loop_fade_accumulator} +
    (mode5_loop_wait_tick ? 41'd256 : 41'd0);
wire mode5_halt_at_loop_boundary =
    mode5_loop_limit_policy_active &&
    mode5_loop_second_active;
wire mode5_loop_limit_transition_eligible =
    mode5_playback_started &&
    player_busy &&
    !loaded_player_done &&
    mode5_done_armed_i &&
    (mode5_done_armed_session_id_i == mode5_playback_session_id_i) &&
    !mode5_load_session_active &&
    !vgm_load_busy &&
    !vgm_load_error &&
    !vgm_load_overflow &&
    !vgm_player_error;

assign mode5_fade_only_accept =
    mode5_fade_only_request && !mode5_fade_only_owned &&
    !mode5_transition_released && mode5_loop_limit_transition_eligible &&
    !mode5_selected_download;

// Legacy MV/02 policy values 00 and 01 retain their exact meaning.
// MV/02 command 02 is FADE_ONLY. Commit only on a complete index-2 falling edge.
// Main's existing indexed file-transfer endpoint carries this
// sound-family-independent transport policy. Index 2 contains a
// four-byte record: "MV", version 2, byte 3 = policy 0/1 or FADE_ONLY 2.
// A policy is sent before index 1 so the exact new session
// owns it; FADE_ONLY addresses only a currently playing session.
// Partial, oversized, or unknown records are
// ignored.
always_ff @(posedge clk) begin
    if (reset) begin
        mode5_transition_control_download_d <= 1'b0;
        mode5_transition_control_valid <= 1'b0;
        mode5_transition_control_seen <= 4'd0;
        mode5_loop_limit_policy_pending <= 1'b0;
        mode5_loop_limit_policy_value <= 1'b0;
        mode5_loop_limit_policy_update_pulse <= 1'b0;
        mode5_fade_only_request <= 1'b0;
        mode5_transition_command <= POLICY_OFF;
    end else begin
        mode5_transition_control_download_d <=
            mode5_transition_control_download;
        mode5_loop_limit_policy_update_pulse <= 1'b0;
        mode5_fade_only_request <= 1'b0;
        if (mode5_transition_control_download &&
            !mode5_transition_control_download_d) begin
            mode5_transition_control_valid <= 1'b1;
            mode5_transition_control_seen <= 4'd0;
        end
        if (mode5_transition_control_download && ioctl_wr) begin
            unique case (ioctl_addr)
                27'd0: begin
                    mode5_transition_control_seen[0] <= 1'b1;
                    if (ioctl_dout != 8'h4d)
                        mode5_transition_control_valid <= 1'b0;
                end
                27'd1: begin
                    mode5_transition_control_seen[1] <= 1'b1;
                    if (ioctl_dout != 8'h56)
                        mode5_transition_control_valid <= 1'b0;
                end
                27'd2: begin
                    mode5_transition_control_seen[2] <= 1'b1;
                    if (ioctl_dout != 8'h02)
                        mode5_transition_control_valid <= 1'b0;
                end
                27'd3: begin
                    mode5_transition_control_seen[3] <= 1'b1;
                    mode5_transition_command <= ioctl_dout;
                    if (ioctl_dout == POLICY_OFF || ioctl_dout == POLICY_TWO_LOOPS)
                        mode5_loop_limit_policy_value <= ioctl_dout[0];
                    if (ioctl_dout != POLICY_OFF && ioctl_dout != POLICY_TWO_LOOPS &&
                        ioctl_dout != COMMAND_FADE_ONLY)
                        mode5_transition_control_valid <= 1'b0;
                end
                default:
                    mode5_transition_control_valid <= 1'b0;
            endcase
        end
        if (!mode5_transition_control_download &&
            mode5_transition_control_download_d) begin
            if (mode5_transition_control_valid &&
                mode5_transition_control_seen == 4'hf) begin
                if (mode5_transition_command == COMMAND_FADE_ONLY)
                    mode5_fade_only_request <= 1'b1;
                else begin
                    mode5_loop_limit_policy_pending <= mode5_loop_limit_policy_value;
                    mode5_loop_limit_policy_update_pulse <= 1'b1;
                end
            end
            mode5_transition_control_valid <= 1'b0;
            mode5_transition_control_seen <= 4'd0;
        end
    end
end

// Measure the first actual traversal of the VGM loop region. The
// source is the parser's consumed-wait counter, not the optional
// header estimate. The first 0x66 establishes L and starts loop 2;
// its final min(L, two seconds) samples own the fade schedule.
always_ff @(posedge clk) begin
    if (reset) begin
        mode5_loop_limit_policy_active <= 1'b0;
        mode5_loop_region_started <= 1'b0;
        mode5_loop_first_boundary_seen <= 1'b0;
        mode5_loop_second_active <= 1'b0;
        mode5_loop_start_wait_ticks <= 32'd0;
        mode5_loop_second_start_wait_ticks <= 32'd0;
        mode5_loop_length_samples <= 32'd0;
        mode5_loop_fade_start_samples <= 32'd0;
        mode5_loop_fade_samples <= 32'd0;
        mode5_wait_ticks_consumed_d <= 32'd0;
    end else begin
        mode5_wait_ticks_consumed_d <=
            vgm_wait_ticks_consumed_debug;
        if (mode5_load_begin_pulse) begin
            mode5_loop_limit_policy_active <=
                mode5_loop_limit_policy_pending;
            mode5_loop_region_started <= 1'b0;
            mode5_loop_first_boundary_seen <= 1'b0;
            mode5_loop_second_active <= 1'b0;
            mode5_loop_start_wait_ticks <= 32'd0;
            mode5_loop_second_start_wait_ticks <= 32'd0;
            mode5_loop_length_samples <= 32'd0;
            mode5_loop_fade_start_samples <= 32'd0;
            mode5_loop_fade_samples <= 32'd0;
        end else begin
            if (mode5_loop_limit_policy_update_pulse)
                mode5_loop_limit_policy_active <=
                    mode5_loop_limit_policy_value;
            if (mode5_player_loop_entry_pulse &&
                !mode5_loop_first_boundary_seen &&
                !mode5_loop_region_started) begin
                mode5_loop_region_started <= 1'b1;
                mode5_loop_start_wait_ticks <=
                    vgm_wait_ticks_consumed_debug;
            end
            if (mode5_player_loop_boundary_pulse &&
                !mode5_loop_first_boundary_seen &&
                mode5_loop_region_started) begin
                mode5_loop_first_boundary_seen <= 1'b1;
                mode5_loop_second_active <= 1'b1;
                mode5_loop_second_start_wait_ticks <=
                    vgm_wait_ticks_consumed_debug;
                mode5_loop_length_samples <=
                    vgm_wait_ticks_consumed_debug -
                    mode5_loop_start_wait_ticks;
                if ((vgm_wait_ticks_consumed_debug -
                     mode5_loop_start_wait_ticks) >
                    MODE5_LOOP_LIMIT_FADE_SAMPLES) begin
                    mode5_loop_fade_start_samples <=
                        (vgm_wait_ticks_consumed_debug -
                         mode5_loop_start_wait_ticks) -
                        MODE5_LOOP_LIMIT_FADE_SAMPLES;
                    mode5_loop_fade_samples <=
                        MODE5_LOOP_LIMIT_FADE_SAMPLES;
                end else begin
                    mode5_loop_fade_start_samples <= 32'd0;
                    mode5_loop_fade_samples <=
                        vgm_wait_ticks_consumed_debug -
                        mode5_loop_start_wait_ticks;
                end
            end else if (mode5_player_loop_boundary_pulse &&
                         mode5_loop_second_active) begin
                mode5_loop_second_active <= 1'b0;
            end
        end
    end
end

// One owner serializes every audible track replacement. For an
// explicit load, ioctl_wait holds Main at FIO_FILE_TX(enable)
// until the old output reaches zero. For natural END, ENDED is
// withheld until the same ramp completes. LOOP_LIMIT retains this
// owner, but its gain is paced by actual VGM wait samples and its
// completion is the second real loop boundary. A load arriving
// during a ramp joins it; it cannot start a second transition.
always_ff @(posedge clk) begin
    if (reset) begin
        mode5_host_ioctl_download_d <= 1'b0;
        mode5_audio_ever_open <= 1'b0;
        mode5_transition_fade_active <= 1'b0;
        mode5_transition_end_pending <= 1'b0;
        mode5_transition_released <= 1'b0;
        mode5_transition_end_pulse <= 1'b0;
        mode5_transition_fade_counter <= 32'd0;
        mode5_loop_fade_accumulator <= 40'd0;
        mode5_transition_gain <= 9'd256;
        mode5_transition_loop_limit_active <= 1'b0;
    end else begin
        mode5_host_ioctl_download_d <= ioctl_download;
        mode5_transition_end_pulse <= 1'b0;

        if (mode5_load_begin_pulse) begin
            mode5_audio_ever_open <= 1'b0;
            mode5_transition_loop_limit_active <= 1'b0;
            mode5_loop_fade_accumulator <= 40'd0;
        end else if (audio_runtime_open && player_busy) begin
            mode5_audio_ever_open <= 1'b1;
        end

        // A command joins the existing envelope without pausing/restarting it.
        if (mode5_fade_only_accept && mode5_transition_fade_active)
            mode5_transition_end_pending <= 1'b1;
        if (mode5_transition_fade_active) begin
            if (vgm_player_error || vgm_load_error ||
                vgm_load_overflow) begin
                // FATAL keeps its established immediate ownership;
                // do not manufacture ENDED from an interrupted tail.
                mode5_transition_fade_active <= 1'b0;
                mode5_transition_end_pending <= 1'b0;
                mode5_transition_released <= 1'b1;
                mode5_transition_fade_counter <= 32'd0;
                mode5_loop_fade_accumulator <= 40'd0;
                mode5_transition_gain <= 9'd0;
                mode5_transition_loop_limit_active <= 1'b0;
            end else if (mode5_transition_loop_limit_active && mode5_fade_only_accept) begin
                // Same takeover rule as manual replacement: retain current gain,
                // use the existing clock-paced ramp, and end rather than load.
                mode5_transition_loop_limit_active <= 1'b0;
                mode5_transition_end_pending <= 1'b1;
                mode5_transition_fade_counter <= 32'd0;
                mode5_loop_fade_accumulator <= 40'd0;
            end else if (mode5_transition_loop_limit_active) begin
                if (mode5_player_loop_boundary_pulse &&
                    mode5_loop_second_active) begin
                    // The boundary is authoritative. It both
                    // clamps rounding residue to zero and emits the
                    // single transport END; no loop-3 fetch occurs.
                    mode5_transition_gain <= 9'd0;
                    mode5_transition_fade_active <= 1'b0;
                    mode5_transition_released <= 1'b1;
                    mode5_transition_end_pending <= 1'b1;
                    mode5_transition_end_pulse <= 1'b1;
                    mode5_loop_fade_accumulator <= 40'd0;
                end else if (mode5_loop_limit_policy_update_pulse &&
                             !mode5_loop_limit_policy_value) begin
                    // Repeat One cancels only the loop-limit
                    // owner; native looping resumes at full gain.
                    mode5_transition_fade_active <= 1'b0;
                    mode5_transition_end_pending <= 1'b0;
                    mode5_transition_gain <= 9'd256;
                    mode5_transition_loop_limit_active <= 1'b0;
                    mode5_loop_fade_accumulator <= 40'd0;
                end else if (mode5_selected_download &&
                             !mode5_host_ioctl_download_d) begin
                    // Manual replacement keeps the same owner but
                    // uses the established 100 ms transport ramp.
                    mode5_transition_loop_limit_active <= 1'b0;
                    mode5_transition_end_pending <= 1'b0;
                    mode5_transition_fade_counter <= 32'd0;
                    mode5_loop_fade_accumulator <= 40'd0;
                end else if ((mode5_loop_fade_samples != 32'd0) &&
                             (mode5_loop_fade_accumulator_next >=
                              {9'd0, mode5_loop_fade_samples})) begin
                    mode5_loop_fade_accumulator <=
                        mode5_loop_fade_accumulator_next[39:0] -
                        {8'd0, mode5_loop_fade_samples};
                    if (mode5_transition_gain != 9'd0)
                        mode5_transition_gain <=
                            mode5_transition_gain - 9'd1;
                end else begin
                    mode5_loop_fade_accumulator <=
                        mode5_loop_fade_accumulator_next[39:0];
                end
            end else if (mode5_parser_done_edge) begin
                mode5_transition_end_pending <= 1'b1;
            end else if (mode5_transition_fade_counter >=
                (MODE5_TRACK_FADE_STEP_CYCLES - 32'd1)) begin
                mode5_transition_fade_counter <= 32'd0;
                if (mode5_transition_gain <= 9'd1) begin
                    mode5_transition_gain <= 9'd0;
                    mode5_transition_fade_active <= 1'b0;
                    mode5_transition_released <= 1'b1;
                    if (mode5_transition_end_pending ||
                        mode5_parser_done_edge)
                        mode5_transition_end_pulse <= 1'b1;
                end else begin
                    mode5_transition_gain <=
                        mode5_transition_gain - 9'd1;
                end
            end else begin
                mode5_transition_fade_counter <=
                    mode5_transition_fade_counter + 32'd1;
            end
        end else if (!mode5_transition_released &&
                     !mode5_fade_only_accept && mode5_loop_fade_due &&
                     mode5_loop_limit_transition_eligible) begin
            mode5_transition_fade_active <= 1'b1;
            mode5_transition_end_pending <= 1'b1;
            mode5_transition_fade_counter <= 32'd0;
            mode5_loop_fade_accumulator <= 40'd0;
            mode5_transition_gain <=
                (mode5_audio_ever_open &&
                 (mode5_loop_fade_samples != 32'd0)) ?
                9'd256 : 9'd0;
            mode5_transition_loop_limit_active <= 1'b1;
        end else if (!mode5_transition_released &&
                     (mode5_parser_done_edge || mode5_fade_only_accept ||
                      mode5_transition_start_load)) begin
            if ((mode5_audio_ever_open || mode5_fade_only_accept) &&
                (MODE5_TRACK_FADE_CYCLES != 32'd0)) begin
                mode5_transition_fade_active <= 1'b1;
                mode5_transition_end_pending <=
                    mode5_parser_done_edge || mode5_fade_only_accept;
                mode5_transition_fade_counter <= 32'd0;
                mode5_loop_fade_accumulator <= 40'd0;
                mode5_transition_gain <= 9'd256;
                mode5_transition_loop_limit_active <= 1'b0;
            end else begin
                mode5_transition_released <= 1'b1;
                mode5_transition_gain <= 9'd0;
                if (mode5_parser_done_edge || mode5_fade_only_accept) begin
                    mode5_transition_end_pending <= 1'b1;
                    mode5_transition_end_pulse <= 1'b1;
                end
            end
        end else if (mode5_transition_released &&
                     !ioctl_download && !mode5_fade_only_owned &&
                     !mode5_transition_loop_limit_active &&
                     mode5_playback_started &&
                     !loaded_player_done) begin
            // Internal repeat/re-arm has no download falling edge.
            mode5_transition_released <= 1'b0;
            mode5_transition_end_pending <= 1'b0;
            mode5_transition_gain <= 9'd256;
            mode5_transition_loop_limit_active <= 1'b0;
            mode5_loop_fade_accumulator <= 40'd0;
        end else if (mode5_transition_released &&
                     !mode5_ioctl_download &&
                     mode5_ioctl_download_d) begin
            // Only completion of an accepted index-1 VGM load
            // re-arms the next session. An index-2 policy record
            // must retain the ended session's zero-gain owner;
            // otherwise the following load re-fades old audio.
            mode5_transition_released <= 1'b0;
            mode5_transition_end_pending <= 1'b0;
            mode5_transition_gain <= 9'd256;
            mode5_transition_loop_limit_active <= 1'b0;
            mode5_loop_fade_accumulator <= 40'd0;
        end
    end
end

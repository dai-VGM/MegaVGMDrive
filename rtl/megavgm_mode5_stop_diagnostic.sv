// Sticky, observer-only mode-5 stop classifier.
//
// This module has no control outputs.  It samples the production transport and
// audio signals, classifies the first sustained invariant failure, and freezes
// one snapshot until core reset.  Window parameters are exposed so simulation
// can prove every class without changing the 20 MHz hardware thresholds.
module megavgm_mode5_stop_diagnostic #(
    parameter logic [31:0] PLAY_WINDOW_CYCLES = 32'd10_000_000,
    parameter logic [31:0] HANDOFF_TIMEOUT_CYCLES = 32'd60_000_000,
    parameter logic [31:0] LOOP_TIMEOUT_CYCLES = 32'd60_000_000,
    parameter logic [2:0]  RAW_MISSING_WINDOWS = 3'd4
) (
    input  logic               clk,
    input  logic               reset,

    input  logic [31:0]        session_id,
    input  logic               playback_started,
    input  logic               player_busy,
    input  logic               player_done,
    input  logic [31:0]        progress_count,
    input  logic               raw_audio_sample_valid,
    input  logic               handoff_audio_valid,
    input  logic               audio_runtime_open,
    input  logic [8:0]         audio_runtime_gain,
    input  logic signed [15:0] raw_audio_l,
    input  logic signed [15:0] raw_audio_r,
    input  logic signed [15:0] output_audio_l,
    input  logic signed [15:0] output_audio_r,

    input  logic               load_active,
    input  logic               ioctl_download,
    input  logic               ioctl_wait,
    input  logic               player_session_reset,
    input  logic               sound_core_reset,
    input  logic               ended_pulse,
    input  logic [31:0]        ended_count,
    input  logic               load_begin_pulse,
    input  logic [31:0]        load_begin_count,
    input  logic               session_start_pulse,
    input  logic [31:0]        session_start_count,

    input  logic               loop_boundary_pulse,
    input  logic               loop_length_valid,
    input  logic [31:0]        loop_length,
    input  logic               loop_limit_armed,
    input  logic               loop_limit_active,
    input  logic               fade_active,
    input  logic [2:0]         transition_reason,

    input  logic               fatal_live,
    input  logic [7:0]         fatal_code,

    output logic [383:0]       snapshot_bus
);
    localparam logic [2:0] CLASS_NONE = 3'd0;
    localparam logic [2:0] CLASS_AUDIO_ONLY = 3'd1;
    localparam logic [2:0] CLASS_PLAYER_STOP = 3'd2;
    localparam logic [2:0] CLASS_LOAD_HANDOFF = 3'd3;
    localparam logic [2:0] CLASS_LOOP_LIMIT = 3'd4;
    localparam logic [2:0] CLASS_FATAL = 3'd5;
    localparam logic [2:0] CLASS_OTHER = 3'd6;

    logic [31:0] progress_count_d;
    logic [31:0] ended_count_d;
    logic [31:0] load_begin_count_d;
    logic [31:0] session_start_count_d;
    logic [8:0]  audio_runtime_gain_d;

    logic [31:0] play_window_counter;
    logic        play_progress_seen;
    logic        play_raw_valid_seen;
    logic        play_raw_nonzero_seen;
    logic        play_output_nonzero_seen;
    logic [2:0]  raw_missing_window_count;
    logic [31:0] player_missing_counter;
    logic [31:0] handoff_counter;
    logic [31:0] loop_age_counter;
    logic [31:0] loop_stall_counter;
    logic [31:0] current_loop_count;

    logic        snapshot_valid;
    logic [2:0]  snapshot_class;
    logic [31:0] snapshot_session;
    logic        snapshot_player_busy;
    logic        snapshot_player_done;
    logic [31:0] snapshot_progress;
    logic        snapshot_progress_seen;
    logic        snapshot_raw_valid;
    logic        snapshot_raw_valid_seen;
    logic        snapshot_handoff_valid;
    logic        snapshot_audio_open;
    logic [8:0]  snapshot_gain;
    logic signed [15:0] snapshot_raw_l;
    logic signed [15:0] snapshot_raw_r;
    logic signed [15:0] snapshot_output_l;
    logic signed [15:0] snapshot_output_r;
    logic        snapshot_load_active;
    logic        snapshot_ioctl_wait;
    logic        snapshot_player_reset;
    logic        snapshot_sound_reset;
    logic [31:0] snapshot_ended_count;
    logic [31:0] snapshot_load_count;
    logic [31:0] snapshot_start_count;
    logic [31:0] snapshot_loop_count;
    logic        snapshot_loop_length_valid;
    logic [31:0] snapshot_loop_length;
    logic        snapshot_loop_limit_armed;
    logic        snapshot_loop_limit_active;
    logic        snapshot_fade_active;
    logic [2:0]  snapshot_transition_reason;
    logic [7:0]  snapshot_fatal_code;
    logic [2:0]  snapshot_status_state;
    logic        snapshot_raw_nonzero_seen;
    logic        snapshot_output_nonzero_seen;
    logic [31:0] snapshot_observation_cycles;
    logic        snapshot_playback_started;
    logic        snapshot_ioctl_download;
    logic        snapshot_ended_pulse;
    logic        snapshot_load_begin_pulse;
    logic        snapshot_start_pulse;

    wire progress_event = progress_count != progress_count_d;
    wire count_progress_event =
        (ended_count != ended_count_d) ||
        (load_begin_count != load_begin_count_d) ||
        (session_start_count != session_start_count_d);
    wire raw_nonzero_event = raw_audio_sample_valid &&
        ((raw_audio_l != 16'sd0) || (raw_audio_r != 16'sd0));
    wire output_nonzero_event =
        (output_audio_l != 16'sd0) || (output_audio_r != 16'sd0);

    wire play_observation_active =
        (session_id != 32'd0) && playback_started && player_busy &&
        !player_done && !load_active && !ioctl_download &&
        !player_session_reset && !sound_core_reset && !fade_active &&
        !fatal_live;
    wire player_missing_active =
        (session_id != 32'd0) && playback_started && !player_busy &&
        !player_done && !load_active && !ioctl_download &&
        !player_session_reset && !sound_core_reset && !fade_active &&
        !fatal_live;
    wire handoff_observation_active =
        !ioctl_download && !fade_active && !fatal_live &&
        (load_active || sound_core_reset ||
         (load_begin_count > session_start_count) ||
         (ioctl_wait && !player_busy));
    wire loop_observation_active =
        loop_limit_active ||
        (fade_active && (transition_reason == 3'd4));
    wire loop_progress_event =
        progress_event || count_progress_event ||
        (audio_runtime_gain != audio_runtime_gain_d) ||
        loop_boundary_pulse;

    wire play_window_expired =
        play_observation_active &&
        (play_window_counter >= (PLAY_WINDOW_CYCLES - 32'd1));
    wire play_progress_seen_now = play_progress_seen || progress_event;
    wire play_raw_seen_now =
        play_raw_valid_seen || raw_audio_sample_valid;
    wire play_raw_nonzero_seen_now =
        play_raw_nonzero_seen || raw_nonzero_event;
    wire play_output_nonzero_seen_now =
        play_output_nonzero_seen || output_nonzero_event;
    wire sustained_audio_gate_fault =
        !handoff_audio_valid || !audio_runtime_open ||
        (audio_runtime_gain == 9'd0) ||
        (play_raw_nonzero_seen_now && !play_output_nonzero_seen_now);

    wire [2:0] live_status_state =
        fatal_live ? 3'd4 :
        load_active ? 3'd1 :
        player_busy ? 3'd2 :
        player_done ? 3'd3 : 3'd0;

    logic [2:0] trigger_class;
    logic [31:0] trigger_observation_cycles;
    always_comb begin
        trigger_class = CLASS_NONE;
        trigger_observation_cycles = 32'd0;
        if (fatal_live) begin
            trigger_class = CLASS_FATAL;
        end else if (loop_observation_active &&
                     ((loop_age_counter >=
                       (LOOP_TIMEOUT_CYCLES - 32'd1)) ||
                      (loop_stall_counter >=
                       (PLAY_WINDOW_CYCLES - 32'd1)))) begin
            trigger_class = CLASS_LOOP_LIMIT;
            trigger_observation_cycles = loop_age_counter;
        end else if (handoff_observation_active &&
                     (handoff_counter >=
                      (HANDOFF_TIMEOUT_CYCLES - 32'd1))) begin
            trigger_class = CLASS_LOAD_HANDOFF;
            trigger_observation_cycles = handoff_counter;
        end else if (player_missing_active &&
                     (player_missing_counter >=
                      (PLAY_WINDOW_CYCLES - 32'd1))) begin
            trigger_class = CLASS_PLAYER_STOP;
            trigger_observation_cycles = player_missing_counter;
        end else if (play_window_expired && !play_progress_seen_now) begin
            trigger_class = CLASS_PLAYER_STOP;
            trigger_observation_cycles = play_window_counter;
        end else if (play_window_expired && play_progress_seen_now &&
                     play_raw_seen_now && sustained_audio_gate_fault) begin
            trigger_class = CLASS_AUDIO_ONLY;
            trigger_observation_cycles = play_window_counter;
        end else if (play_window_expired && play_progress_seen_now &&
                     !play_raw_seen_now &&
                     (raw_missing_window_count >=
                      (RAW_MISSING_WINDOWS - 3'd1))) begin
            // Parser/wait transport is alive but the selected sound path has
            // produced no sample-valid event for several complete windows.
            // This is deliberately not called AUDIO_ONLY because the 9f30ca6
            // handoff latch cannot open without an authoritative valid edge.
            trigger_class = CLASS_OTHER;
            trigger_observation_cycles =
                play_window_counter +
                (raw_missing_window_count * PLAY_WINDOW_CYCLES);
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            progress_count_d <= 32'd0;
            ended_count_d <= 32'd0;
            load_begin_count_d <= 32'd0;
            session_start_count_d <= 32'd0;
            audio_runtime_gain_d <= 9'd0;
            play_window_counter <= 32'd0;
            play_progress_seen <= 1'b0;
            play_raw_valid_seen <= 1'b0;
            play_raw_nonzero_seen <= 1'b0;
            play_output_nonzero_seen <= 1'b0;
            raw_missing_window_count <= 3'd0;
            player_missing_counter <= 32'd0;
            handoff_counter <= 32'd0;
            loop_age_counter <= 32'd0;
            loop_stall_counter <= 32'd0;
            current_loop_count <= 32'd0;
            snapshot_valid <= 1'b0;
            snapshot_class <= CLASS_NONE;
            snapshot_session <= 32'd0;
            snapshot_player_busy <= 1'b0;
            snapshot_player_done <= 1'b0;
            snapshot_progress <= 32'd0;
            snapshot_progress_seen <= 1'b0;
            snapshot_raw_valid <= 1'b0;
            snapshot_raw_valid_seen <= 1'b0;
            snapshot_handoff_valid <= 1'b0;
            snapshot_audio_open <= 1'b0;
            snapshot_gain <= 9'd0;
            snapshot_raw_l <= 16'sd0;
            snapshot_raw_r <= 16'sd0;
            snapshot_output_l <= 16'sd0;
            snapshot_output_r <= 16'sd0;
            snapshot_load_active <= 1'b0;
            snapshot_ioctl_wait <= 1'b0;
            snapshot_player_reset <= 1'b0;
            snapshot_sound_reset <= 1'b0;
            snapshot_ended_count <= 32'd0;
            snapshot_load_count <= 32'd0;
            snapshot_start_count <= 32'd0;
            snapshot_loop_count <= 32'd0;
            snapshot_loop_length_valid <= 1'b0;
            snapshot_loop_length <= 32'd0;
            snapshot_loop_limit_armed <= 1'b0;
            snapshot_loop_limit_active <= 1'b0;
            snapshot_fade_active <= 1'b0;
            snapshot_transition_reason <= 3'd0;
            snapshot_fatal_code <= 8'd0;
            snapshot_status_state <= 3'd0;
            snapshot_raw_nonzero_seen <= 1'b0;
            snapshot_output_nonzero_seen <= 1'b0;
            snapshot_observation_cycles <= 32'd0;
            snapshot_playback_started <= 1'b0;
            snapshot_ioctl_download <= 1'b0;
            snapshot_ended_pulse <= 1'b0;
            snapshot_load_begin_pulse <= 1'b0;
            snapshot_start_pulse <= 1'b0;
        end else begin
            progress_count_d <= progress_count;
            ended_count_d <= ended_count;
            load_begin_count_d <= load_begin_count;
            session_start_count_d <= session_start_count;
            audio_runtime_gain_d <= audio_runtime_gain;

            if (load_begin_pulse) begin
                current_loop_count <= 32'd0;
            end else if (loop_boundary_pulse &&
                         (current_loop_count != 32'hffff_ffff)) begin
                current_loop_count <= current_loop_count + 32'd1;
            end

            if (!play_observation_active) begin
                play_window_counter <= 32'd0;
                play_progress_seen <= 1'b0;
                play_raw_valid_seen <= 1'b0;
                play_raw_nonzero_seen <= 1'b0;
                play_output_nonzero_seen <= 1'b0;
                raw_missing_window_count <= 3'd0;
            end else if (play_window_expired) begin
                play_window_counter <= 32'd0;
                play_progress_seen <= 1'b0;
                play_raw_valid_seen <= 1'b0;
                play_raw_nonzero_seen <= 1'b0;
                play_output_nonzero_seen <= 1'b0;
                if (play_progress_seen_now && !play_raw_seen_now &&
                    (raw_missing_window_count != 3'd7)) begin
                    raw_missing_window_count <=
                        raw_missing_window_count + 3'd1;
                end else if (play_raw_seen_now) begin
                    raw_missing_window_count <= 3'd0;
                end
            end else begin
                play_window_counter <= play_window_counter + 32'd1;
                play_progress_seen <=
                    play_progress_seen || progress_event;
                play_raw_valid_seen <=
                    play_raw_valid_seen || raw_audio_sample_valid;
                play_raw_nonzero_seen <=
                    play_raw_nonzero_seen || raw_nonzero_event;
                play_output_nonzero_seen <=
                    play_output_nonzero_seen || output_nonzero_event;
            end

            if (player_missing_active)
                player_missing_counter <= player_missing_counter + 32'd1;
            else
                player_missing_counter <= 32'd0;

            if (handoff_observation_active)
                handoff_counter <= handoff_counter + 32'd1;
            else
                handoff_counter <= 32'd0;

            if (!loop_observation_active) begin
                loop_age_counter <= 32'd0;
                loop_stall_counter <= 32'd0;
            end else begin
                loop_age_counter <= loop_age_counter + 32'd1;
                if (loop_progress_event)
                    loop_stall_counter <= 32'd0;
                else
                    loop_stall_counter <= loop_stall_counter + 32'd1;
            end

            if (!snapshot_valid && (trigger_class != CLASS_NONE)) begin
                snapshot_valid <= 1'b1;
                snapshot_class <= trigger_class;
                snapshot_session <= session_id;
                snapshot_player_busy <= player_busy;
                snapshot_player_done <= player_done;
                snapshot_progress <= progress_count;
                snapshot_progress_seen <= play_progress_seen_now;
                snapshot_raw_valid <= raw_audio_sample_valid;
                snapshot_raw_valid_seen <= play_raw_seen_now;
                snapshot_handoff_valid <= handoff_audio_valid;
                snapshot_audio_open <= audio_runtime_open;
                snapshot_gain <= audio_runtime_gain;
                snapshot_raw_l <= raw_audio_l;
                snapshot_raw_r <= raw_audio_r;
                snapshot_output_l <= output_audio_l;
                snapshot_output_r <= output_audio_r;
                snapshot_load_active <= load_active;
                snapshot_ioctl_wait <= ioctl_wait;
                snapshot_player_reset <= player_session_reset;
                snapshot_sound_reset <= sound_core_reset;
                snapshot_ended_count <= ended_count;
                snapshot_load_count <= load_begin_count;
                snapshot_start_count <= session_start_count;
                snapshot_loop_count <= current_loop_count;
                snapshot_loop_length_valid <= loop_length_valid;
                snapshot_loop_length <= loop_length;
                snapshot_loop_limit_armed <= loop_limit_armed;
                snapshot_loop_limit_active <= loop_limit_active;
                snapshot_fade_active <= fade_active;
                snapshot_transition_reason <= transition_reason;
                snapshot_fatal_code <= fatal_code;
                snapshot_status_state <= live_status_state;
                snapshot_raw_nonzero_seen <=
                    play_raw_nonzero_seen_now;
                snapshot_output_nonzero_seen <=
                    play_output_nonzero_seen_now;
                snapshot_observation_cycles <=
                    trigger_observation_cycles;
                snapshot_playback_started <= playback_started;
                snapshot_ioctl_download <= ioctl_download;
                snapshot_ended_pulse <= ended_pulse;
                snapshot_load_begin_pulse <= load_begin_pulse;
                snapshot_start_pulse <= session_start_pulse;
            end
        end
    end

    // Packed observer contract consumed only by the diagnostic overlay.
    // [2:0] class, [34:3] session, [35] busy, [36] done,
    // [68:37] progress, [69] progress-seen, [70] raw-valid-now,
    // [71] raw-valid-seen, [72] handoff-valid, [73] output-open,
    // [82:74] gain, [98:83]/[114:99] raw L/R,
    // [130:115]/[146:131] post-gain L/R, [147] load-active,
    // [148] ioctl-wait, [149] player-reset, [150] sound-reset,
    // [182:151] END count, [214:183] load count, [246:215] start count,
    // [278:247] loop count, [279] loop-length-valid, [311:280] length,
    // [312] loop-limit-armed, [313] loop-limit-active, [314] fade-active,
    // [317:315] reason, [325:318] fatal code, [328:326] status,
    // [329] snapshot-valid, [330]/[331] raw/output nonzero seen,
    // [363:332] observation cycles, [364] playback-started,
    // [365] ioctl-download, [366] END pulse, [367] load pulse,
    // [368] start pulse. Remaining high bits are zero/reserved.
    always_comb begin
        snapshot_bus = 384'd0;
        snapshot_bus[2:0] = snapshot_class;
        snapshot_bus[34:3] = snapshot_session;
        snapshot_bus[35] = snapshot_player_busy;
        snapshot_bus[36] = snapshot_player_done;
        snapshot_bus[68:37] = snapshot_progress;
        snapshot_bus[69] = snapshot_progress_seen;
        snapshot_bus[70] = snapshot_raw_valid;
        snapshot_bus[71] = snapshot_raw_valid_seen;
        snapshot_bus[72] = snapshot_handoff_valid;
        snapshot_bus[73] = snapshot_audio_open;
        snapshot_bus[82:74] = snapshot_gain;
        snapshot_bus[98:83] = snapshot_raw_l;
        snapshot_bus[114:99] = snapshot_raw_r;
        snapshot_bus[130:115] = snapshot_output_l;
        snapshot_bus[146:131] = snapshot_output_r;
        snapshot_bus[147] = snapshot_load_active;
        snapshot_bus[148] = snapshot_ioctl_wait;
        snapshot_bus[149] = snapshot_player_reset;
        snapshot_bus[150] = snapshot_sound_reset;
        snapshot_bus[182:151] = snapshot_ended_count;
        snapshot_bus[214:183] = snapshot_load_count;
        snapshot_bus[246:215] = snapshot_start_count;
        snapshot_bus[278:247] = snapshot_loop_count;
        snapshot_bus[279] = snapshot_loop_length_valid;
        snapshot_bus[311:280] = snapshot_loop_length;
        snapshot_bus[312] = snapshot_loop_limit_armed;
        snapshot_bus[313] = snapshot_loop_limit_active;
        snapshot_bus[314] = snapshot_fade_active;
        snapshot_bus[317:315] = snapshot_transition_reason;
        snapshot_bus[325:318] = snapshot_fatal_code;
        snapshot_bus[328:326] = snapshot_status_state;
        snapshot_bus[329] = snapshot_valid;
        snapshot_bus[330] = snapshot_raw_nonzero_seen;
        snapshot_bus[331] = snapshot_output_nonzero_seen;
        snapshot_bus[363:332] = snapshot_observation_cycles;
        snapshot_bus[364] = snapshot_playback_started;
        snapshot_bus[365] = snapshot_ioctl_download;
        snapshot_bus[366] = snapshot_ended_pulse;
        snapshot_bus[367] = snapshot_load_begin_pulse;
        snapshot_bus[368] = snapshot_start_pulse;
    end
endmodule

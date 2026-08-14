`timescale 1ns/1ps

`ifndef SEMANTIC_FAST_SIM
`define SEMANTIC_FAST_SIM 1'b1
`endif

module jt10_p3_clean_isolated_s4_top;
    localparam logic [63:0] FNV_OFFSET = 64'hcbf29ce484222325;
    localparam integer SIM_BOOT = 256;
    localparam integer SIM_PREROLL = 128;
    localparam integer SIM_DWELL = 8193;
    localparam integer SIM_INTER = 128;
    localparam integer SIM_PAN = 2048;
    localparam integer SIM_PAN_INTER = 128;
    // Keep the established Phase 4A natural-restart settling window while
    // the exact-count pacing TB separately proves the 79901-tick hardware
    // interval.
    localparam integer SIM_NATURAL_SILENCE = 512;
    localparam integer SIM_FINAL = 256;
    localparam integer SEMANTIC_FAST_MODE = `SEMANTIC_FAST_SIM;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic video_reset = 1'b1;
    integer run_id = 1;
    integer failures = 0;
    integer system_cycle = 0;
    integer public_samples = 0;
    integer internal_samples = 0;
    integer last_public_cycle = -1;
    integer cadence_errors = 0;
    integer width_errors = 0;
    integer drops = 0;
    integer duplicates = 0;
    integer tick_missed = 0;
    integer tick_duplicates = 0;
    integer x_count = 0;
    integer public_width = 0;
    integer cold_zero_samples = 0;
    integer final_zero_samples = 0; // retained legacy diagnostic
    logic final_dwell_armed, final_dwell_complete, final_dwell_short, final_dwell_break;
    logic [31:0] final_dwell_count;
    integer phase_transition_index = 0;
    integer color_visits [1:7];
    integer loop_hash_index = 0;
    integer color_event_tick [0:1][0:7];
    integer sound_event_tick [0:1][0:8];
    integer stop_event_tick [0:1][0:8];
    integer zero_event_tick [0:1][0:8];
    integer sound_event_index = 0;
    integer stop_event_index = 0;
    integer zero_event_index = 0;
    integer pan_leak = 0;
    integer left_nonzero = 0;
    integer right_nonzero = 0;
    integer natural_logical [0:3];
    integer natural_public [0:3];
    integer natural_zero_latency [0:3];
    integer natural_run = -1;
    integer zero_wait_samples = 0;
    integer stale_prefix = 0;
    integer x_audio = 0;
    integer x_internal = 0;
    integer x_control = 0;
    integer x_psg = 0;
    integer x_rom_a = 0;
    integer x_rom_b = 0;
    integer pre_ready_x = 0;
    integer pre_ready_nonzero = 0;
    integer phase5_zero_latency = -1;
    integer phase5_zero_wait = 0;
    integer phase5_request_after_stop = 0;
    integer psg_bc_spurious = 0;
    integer psg_a_nonzero = 0;
    integer unexpected_adpcm_requests = 0;
    integer a6_overflow_events = 0;
    logic phase5_stop_seen = 1'b0;
    logic previous_public = 1'b0;
    logic previous_internal = 1'b0;
    logic previous_measurement = 1'b0;
    logic previous_b_active = 1'b0;
    logic previous_b_eos = 1'b0;
    logic previous_external_mute = 1'b1;
    logic [6:0] previous_segment_state = 7'd0;
    logic [3:0] last_display_phase = 4'd0;
    logic [15:0] first_prefix_l [0:1][0:15];
    logic [15:0] first_prefix_r [0:1][0:15];
    integer prefix_count [0:3];
    logic [63:0] phase_hash [0:1][1:5];
    integer phase_hash_count [0:1][1:5];
    logic [63:0] natural_hash [0:3];

    // Semantic progress budgets derive from the configured sample windows.
    localparam integer SEMANTIC_STATE_SAMPLE_BUDGET =
        SIM_DWELL + SIM_FINAL;
    localparam integer SEMANTIC_MAX_ATTEMPTS_PER_PHASE = 6;
    localparam integer SEMANTIC_PHASE_SAMPLE_BUDGET =
        (SEMANTIC_MAX_ATTEMPTS_PER_PHASE + 1) *
        SEMANTIC_STATE_SAMPLE_BUDGET;
    localparam integer SEMANTIC_PHASES_PER_LOOP = 8;
    localparam integer SEMANTIC_REQUIRED_LOOPS = 2;
    localparam integer SEMANTIC_FULL_LOOP_SAMPLE_BUDGET =
        SEMANTIC_REQUIRED_LOOPS * SEMANTIC_PHASES_PER_LOOP *
        SEMANTIC_PHASE_SAMPLE_BUDGET;
    localparam longint SEMANTIC_NCO_DENOMINATOR = 64'd16777216;
    localparam longint SEMANTIC_NCO_NUMERATOR = 64'd6434443;
    localparam integer SEMANTIC_FAST0_MAX_SAMPLE_CYCLES =
        (64'd144 * SEMANTIC_NCO_DENOMINATOR +
         SEMANTIC_NCO_NUMERATOR - 1) / SEMANTIC_NCO_NUMERATOR;
    localparam integer SEMANTIC_FAST1_MAX_SAMPLE_CYCLES = 144;
    localparam integer SEMANTIC_MAX_SAMPLE_CYCLES =
        SEMANTIC_FAST_MODE ? SEMANTIC_FAST1_MAX_SAMPLE_CYCLES :
                             SEMANTIC_FAST0_MAX_SAMPLE_CYCLES;
    localparam integer SEMANTIC_SAMPLE_PROGRESS_CYCLES =
        2 * SEMANTIC_MAX_SAMPLE_CYCLES;
    localparam integer SEMANTIC_WALL_SAFETY_CYCLES =
        SEMANTIC_FULL_LOOP_SAMPLE_BUDGET *
        SEMANTIC_MAX_SAMPLE_CYCLES + 4 * SEMANTIC_STATE_SAMPLE_BUDGET;
    integer semantic_state_entry_sample = 0;
    integer semantic_phase_entry_sample = 0;
    integer semantic_loop_entry_sample = 0;
    integer semantic_timeout_public_samples = 0;
    integer semantic_last_progress_cycle = 0;
    integer semantic_timeout_count = 0;
    logic semantic_timeout_fired = 1'b0;
    logic semantic_timeout_tracker_started = 1'b0;
    logic [6:0] semantic_timeout_previous_state = 7'd0;
    logic [3:0] semantic_timeout_previous_phase = 4'd0;
    logic [15:0] semantic_timeout_previous_loop = 16'd0;
    logic [8*32-1:0] semantic_last_progress_event = "reset";

    // Semantic sample-valid contract.  System-cycle measurements are
    // informational only and never determine PASS/FAIL.
    integer semantic_logical_samples = 0;
    integer semantic_public_rises = 0;
    integer semantic_public_falls = 0;
    integer semantic_missing_pulses = 0;
    integer semantic_duplicate_pulses = 0;
    integer semantic_overlap_pulses = 0;
    integer semantic_order_errors = 0;
    integer semantic_interval_min = 32'h7fffffff;
    integer semantic_interval_max = 0;
    integer semantic_width_min = 32'h7fffffff;
    integer semantic_width_max = 0;
    integer semantic_pulse_start_cycle = 0;
    logic semantic_pulse_open = 1'b0;

    // Versioned semantic-silence monitor outputs.  The monitor reads only
    // explicit TB connections and has no path that can drive the DUT.
    wire [31:0] semantic_transition_entries;
    wire [31:0] semantic_transition_completes;
    wire [31:0] semantic_zero_qualified;
    wire [31:0] semantic_zero_confirmed;
    wire [31:0] semantic_zero_timed_out;
    wire [31:0] semantic_mute_assertions;
    wire [31:0] semantic_post_samples;
    wire [31:0] semantic_silence_errors;
    wire semantic_transition_active;
    wire semantic_mute_deadline_active;
    wire semantic_post_sample_pending;
    wire [2:0] semantic_current_zero_class;
    wire [7:0] semantic_first_failure_code;
    wire [31:0] semantic_first_failure_cycle;
    wire [4:0] semantic_expected_program;
    wire [6:0] semantic_expected_state;
    wire [1:0] semantic_setup_count;
    wire [7:0] semantic_transition_zero_count;
    wire [1:0] semantic_completion_reason;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_sample;
    wire video_ce, video_hs, video_vs, video_de;
    wire [7:0] video_r, video_g, video_b;
    wire [3:0] debug_phase;
    wire [6:0] debug_segment_state;
    wire [2:0] debug_startup_state;
    wire debug_external_mute, debug_sample_tick;
    wire [31:0] debug_sample_tick_count;
    wire debug_sample_cadence_error, debug_sample_width_error;
    wire [7:0] debug_microcode_index;
    wire [31:0] debug_accepted_writes;
    wire debug_busy_timeout, debug_write_while_busy;
    wire debug_zero_timeout, debug_phase_error;
    wire [15:0] debug_restart_count;
    wire debug_measurement_active;
    wire [3:0] debug_measurement_phase;
    wire debug_adpcma_request, debug_adpcmb_request;
    wire [5:0] debug_adpcma_eos;
    wire debug_adpcmb_eos, debug_adpcmb_active;
    wire [19:0] debug_adpcma_addr;
    wire [3:0] debug_adpcma_bank;
    wire [23:0] debug_adpcmb_addr;
    wire [7:0] debug_psg_a, debug_psg_b, debug_psg_c;
    wire [9:0] debug_psg_snd;
    wire debug_core_ready;
    wire [2:0] debug_reset_cen_count;
    wire debug_halted;

    wire internal_sample = dut.internal_sample;
    wire b_chon = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.chon;
    wire b_restart = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.restart;
    wire b_adv = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.adv;
    wire b_nibble = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.nibble_sel;
    wire clk_en_55 = dut.u_jt10.u_core.clk_en_55;
    wire [1:0] b_pan = dut.u_jt10.u_core.alr_b;
    wire b_logical = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.decoder_cen && clk_en_55 && b_adv && b_chon &&
                     !b_restart && !debug_adpcmb_eos;

    function automatic [63:0] hash_byte(
        input [63:0] hash_in, input [7:0] value
    );
        hash_byte = (hash_in ^ value) * 64'h00000100000001b3;
    endfunction
    function automatic [63:0] hash_u16(
        input [63:0] hash_in, input [15:0] value
    );
        hash_u16 = hash_byte(hash_byte(hash_in, value[7:0]), value[15:8]);
    endfunction
    function automatic [63:0] hash_stereo(
        input [63:0] hash_in,
        input [15:0] left_value, input [15:0] right_value
    );
        hash_stereo = hash_u16(hash_u16(hash_in, left_value), right_value);
    endfunction

    task automatic fail(input [8*64-1:0] message);
        begin
            failures = failures + 1;
            $display("HW0_FAIL run=%0d cycle=%0d tick=%0d state=%0d phase=%0d reason=%0s",
                     run_id,system_cycle,debug_sample_tick_count,
                     debug_segment_state,debug_phase,message);
        end
    endtask

    always #5 clk = ~clk;

    task automatic semantic_timeout_fail(
        input [8*32-1:0] timeout_class,
        input [8*48-1:0] expected_next
    );
        integer elapsed_state;
        begin
            if (!semantic_timeout_fired) begin
                semantic_timeout_fired = 1'b1;
                semantic_timeout_count = semantic_timeout_count + 1;
                elapsed_state = public_samples -
                    semantic_state_entry_sample;
                $display("HW0_SEM_TIMEOUT class=%0s state=%0d phase=%0d tick=%0d public=%0d state_entry_sample=%0d elapsed_semantic_samples=%0d last_progress_cycle=%0d last_progress_event=%0s expected_next_event=%0s system_cycle=%0d fast_sim=%0d",
                    timeout_class, debug_segment_state, debug_phase,
                    debug_sample_tick_count, public_samples,
                    semantic_state_entry_sample, elapsed_state,
                    semantic_last_progress_cycle,
                    semantic_last_progress_event, expected_next,
                    system_cycle, SEMANTIC_FAST_MODE);
                fail("SEMANTIC_TIMEOUT");
            end
        end
    endtask

    always @(posedge clk) begin : monitor
        logic public_rise;
        logic internal_rise;
        logic public_fall;
        integer p;
        integer li;
        system_cycle = system_cycle + 1;
        #1;
        public_rise = audio_sample && !previous_public;
        internal_rise = internal_sample && !previous_internal;
        public_fall = !audio_sample && previous_public;

        if (!debug_core_ready) begin
            if ($isunknown(audio_l) || $isunknown(audio_r) ||
                $isunknown(audio_sample)) pre_ready_x = pre_ready_x + 1;
            else if (audio_l != 0 || audio_r != 0 || audio_sample != 0)
                pre_ready_nonzero = pre_ready_nonzero + 1;
        end
        if (debug_phase == 4 &&
            (dut.u_jt10.u_core.gen_adpcm.u_acc.u_left.overflow ||
             dut.u_jt10.u_core.gen_adpcm.u_acc.u_right.overflow))
            a6_overflow_events = a6_overflow_events + 1;
        if ((debug_phase == 1 || debug_phase == 2) &&
            (debug_adpcma_request === 1'b1 ||
             debug_adpcmb_request === 1'b1))
            unexpected_adpcm_requests = unexpected_adpcm_requests + 1;

        if (!reset && debug_core_ready) begin
            if (!semantic_timeout_tracker_started) begin
                semantic_timeout_tracker_started = 1'b1;
                semantic_state_entry_sample = public_samples;
                semantic_phase_entry_sample = public_samples;
                semantic_loop_entry_sample = public_samples;
                semantic_last_progress_cycle = system_cycle;
                semantic_timeout_previous_state = debug_segment_state;
                semantic_timeout_previous_phase = debug_phase;
                semantic_timeout_previous_loop = debug_restart_count;
                semantic_last_progress_event = "core_ready";
            end else begin
                if (debug_segment_state !=
                    semantic_timeout_previous_state) begin
                    semantic_state_entry_sample = public_samples;
                    semantic_timeout_previous_state = debug_segment_state;
                    semantic_last_progress_cycle = system_cycle;
                    semantic_last_progress_event = "state_change";
                end
                if (debug_phase != semantic_timeout_previous_phase) begin
                    semantic_phase_entry_sample = public_samples;
                    semantic_timeout_previous_phase = debug_phase;
                    semantic_last_progress_cycle = system_cycle;
                    semantic_last_progress_event = "phase_change";
                end
                if (debug_restart_count !=
                    semantic_timeout_previous_loop) begin
                    semantic_loop_entry_sample = public_samples;
                    semantic_timeout_previous_loop = debug_restart_count;
                    semantic_last_progress_cycle = system_cycle;
                    semantic_last_progress_event = "loop_complete";
                end
                if (debug_sample_tick) begin
                    semantic_timeout_public_samples =
                        semantic_timeout_public_samples + 1;
                    semantic_last_progress_cycle = system_cycle;
                    semantic_last_progress_event = "sample_tick";
                end else if (system_cycle - semantic_last_progress_cycle >
                             SEMANTIC_SAMPLE_PROGRESS_CYCLES)
                    semantic_timeout_fail("sample_progress",
                                          "sample_tick");
                if (public_samples - semantic_state_entry_sample >
                    SEMANTIC_STATE_SAMPLE_BUDGET)
                    semantic_timeout_fail("state_progress",
                                          "state_change");
                if (public_samples - semantic_phase_entry_sample >
                    SEMANTIC_PHASE_SAMPLE_BUDGET)
                    semantic_timeout_fail("phase_progress",
                                          "phase_change");
                if (public_samples > SEMANTIC_FULL_LOOP_SAMPLE_BUDGET &&
                    debug_restart_count < SEMANTIC_REQUIRED_LOOPS)
                    semantic_timeout_fail("full_loop",
                                          "loop_complete");
            end
            if ($isunknown(audio_l) || $isunknown(audio_r) ||
                $isunknown(audio_sample)) begin
                if (x_audio == 0)
                    $display("HW0_FIRST_X_AUDIO cycle=%0d l=%h r=%h sample=%b bits=%0d/%0d/%0d",
                        system_cycle,audio_l,audio_r,audio_sample,
                        $isunknown(audio_l),$isunknown(audio_r),
                        $isunknown(audio_sample));
                x_audio=x_audio+1;
            end
            if ($isunknown(dut.internal_left) ||
                $isunknown(dut.internal_right) ||
                $isunknown(dut.internal_sample))
                x_internal=x_internal+1;
            if ($isunknown(debug_phase) ||
                $isunknown(debug_segment_state) ||
                $isunknown(debug_startup_state) ||
                $isunknown(debug_external_mute) ||
                $isunknown(debug_sample_tick) ||
                $isunknown(debug_busy_timeout) ||
                $isunknown(debug_write_while_busy) ||
                $isunknown(debug_zero_timeout) ||
                $isunknown(debug_phase_error)) begin
                x_control=x_control+1;
            end
            if ($isunknown(debug_psg_a) || $isunknown(debug_psg_b) ||
                $isunknown(debug_psg_c) || $isunknown(debug_psg_snd)) begin
                if (x_psg == 0)
                    $display("HW0_FIRST_X_PSG cycle=%0d a=%h b=%h c=%h snd=%h bits=%0d/%0d/%0d/%0d",
                        system_cycle,debug_psg_a,debug_psg_b,debug_psg_c,
                        debug_psg_snd,$isunknown(debug_psg_a),
                        $isunknown(debug_psg_b),$isunknown(debug_psg_c),
                        $isunknown(debug_psg_snd));
                x_psg=x_psg+1;
            end
            if (debug_adpcma_request &&
                ($isunknown(debug_adpcma_addr) ||
                 $isunknown(debug_adpcma_bank) ||
                 $isunknown(dut.adpcma_data))) x_rom_a=x_rom_a+1;
            if (debug_adpcmb_request &&
                ($isunknown(debug_adpcmb_addr) ||
                 $isunknown(dut.adpcmb_data))) x_rom_b=x_rom_b+1;
            x_count = x_audio+x_internal+x_control+x_psg+x_rom_a+x_rom_b;
            if (internal_rise) internal_samples = internal_samples + 1;
            if (internal_rise && !audio_sample) drops = drops + 1;
            if (public_rise) begin
                public_samples = public_samples + 1;
                if (!internal_rise) duplicates = duplicates + 1;
                semantic_public_rises = semantic_public_rises + 1;
                if (!debug_sample_tick) begin
                    tick_missed = tick_missed + 1;
                    semantic_duplicate_pulses =
                        semantic_duplicate_pulses + 1;
                    cadence_errors = cadence_errors + 1;
                end
                if (semantic_pulse_open) begin
                    semantic_overlap_pulses =
                        semantic_overlap_pulses + 1;
                    width_errors = width_errors + 1;
                end
                semantic_pulse_open = 1'b1;
                semantic_pulse_start_cycle = system_cycle;
                if (last_public_cycle >= 0) begin
                    if (system_cycle - last_public_cycle <
                        semantic_interval_min)
                        semantic_interval_min =
                            system_cycle - last_public_cycle;
                    if (system_cycle - last_public_cycle >
                        semantic_interval_max)
                        semantic_interval_max =
                            system_cycle - last_public_cycle;
                end
                last_public_cycle = system_cycle;
                if (debug_external_mute && (audio_l != 0 || audio_r != 0))
                    fail("EXTERNAL_MUTE_NONZERO");
                if (debug_segment_state == 7'd1 &&
                    debug_accepted_writes != 0)
                    fail("BOOT_WRITE");
            end
            if (debug_sample_tick) begin
                semantic_logical_samples = semantic_logical_samples + 1;
                if (!public_rise) begin
                    tick_duplicates = tick_duplicates + 1;
                    semantic_missing_pulses =
                        semantic_missing_pulses + 1;
                    cadence_errors = cadence_errors + 1;
                end
                if (previous_public) begin
                    semantic_overlap_pulses =
                        semantic_overlap_pulses + 1;
                    width_errors = width_errors + 1;
                end
            end
            if (public_fall) begin
                semantic_public_falls = semantic_public_falls + 1;
                if (!semantic_pulse_open) begin
                    semantic_order_errors = semantic_order_errors + 1;
                    width_errors = width_errors + 1;
                end else begin
                    if (system_cycle - semantic_pulse_start_cycle <
                        semantic_width_min)
                        semantic_width_min =
                            system_cycle - semantic_pulse_start_cycle;
                    if (system_cycle - semantic_pulse_start_cycle >
                        semantic_width_max)
                        semantic_width_max =
                            system_cycle - semantic_pulse_start_cycle;
                end
                semantic_pulse_open = 1'b0;
            end
        end

        if (!reset && debug_phase != last_display_phase) begin
            if (debug_phase != 0) begin
                if (phase_transition_index < 16)
                    color_event_tick[phase_transition_index/8]
                                    [phase_transition_index%8] =
                        debug_sample_tick_count;
                case (phase_transition_index % 8)
                    0: if (debug_phase != 1) fail("PHASE_ORDER_FM");
                    1: if (debug_phase != 2) fail("PHASE_ORDER_SSG");
                    2: if (debug_phase != 3) fail("PHASE_ORDER_A0");
                    3: if (debug_phase != 4) fail("PHASE_ORDER_A6");
                    4: if (debug_phase != 5) fail("PHASE_ORDER_B");
                    5: if (debug_phase != 6) fail("PHASE_ORDER_PAN");
                    6: if (debug_phase != 7) fail("PHASE_ORDER_PAN");
                    default: if (debug_phase != 8)
                        fail("PHASE_ORDER_NATURAL");
                endcase
                phase_transition_index = phase_transition_index + 1;
                color_visits[debug_phase] =
                    color_visits[debug_phase] + 1;
                $display("HW0_PHASE run=%0d loop=%0d phase=%0d tick=%0d state=%0d writes=%0d",
                         run_id, debug_restart_count, debug_phase,
                         debug_sample_tick_count, debug_segment_state,
                         debug_accepted_writes);
            end
            last_display_phase = debug_phase;
        end

        if (!reset && !debug_external_mute && previous_external_mute) begin
            if (sound_event_index < 18)
                sound_event_tick[sound_event_index/9]
                                [sound_event_index%9] =
                    debug_sample_tick_count;
            sound_event_index = sound_event_index + 1;
        end
        if (!reset && debug_external_mute && !previous_external_mute) begin
            if (zero_event_index < 18)
                zero_event_tick[zero_event_index/9]
                               [zero_event_index%9] =
                    debug_sample_tick_count;
            zero_event_index = zero_event_index + 1;
        end
        if (!reset && debug_segment_state != previous_segment_state) begin
            case (debug_segment_state)
                7'd8,7'd16,7'd23,7'd30,7'd37,7'd44,7'd51,
                7'd58,7'd63: begin
                    if (stop_event_index < 18)
                        stop_event_tick[stop_event_index/9]
                                       [stop_event_index%9] =
                            debug_sample_tick_count;
                    stop_event_index = stop_event_index + 1;
                end
                default: ;
            endcase
            previous_segment_state = debug_segment_state;
        end

        if (public_rise) begin
            if (debug_phase == 2) begin
                if (debug_psg_a != 0) psg_a_nonzero = psg_a_nonzero + 1;
                if (debug_psg_b != 0 || debug_psg_c != 0)
                    psg_bc_spurious = psg_bc_spurious + 1;
            end
            if (debug_restart_count == 0 && debug_phase == 0 &&
                debug_segment_state == 7'd1 &&
                !dut.u_sequencer.program_active) begin
                if (audio_l != 0 || audio_r != 0) fail("COLD_NONZERO");
                cold_zero_samples = cold_zero_samples + 1;
            end
            if (debug_phase == 0 && debug_segment_state == 7'd65) begin
                if (audio_l != 0 || audio_r != 0) fail("FINAL_NONZERO");
                final_zero_samples = final_zero_samples + 1;
            end

            p = debug_measurement_phase;
            li = debug_restart_count == 0 ? 0 : 1;
            if (debug_measurement_active && p >= 1 && p <= 5 &&
                phase_hash_count[li][p] < (p == 4 ? 8192 :
                                           p == 5 ? 4097 : 4096)) begin
                // Phase 4A's 4096-sample post-START goal includes one active
                // boundary sample already seen by its monitor, hence 4097
                // active-lane samples in the published hash.
                if (p != 5 || b_chon) begin
                    phase_hash[li][p] = hash_stereo(phase_hash[li][p],
                                                    audio_l, audio_r);
                    phase_hash_count[li][p] =
                        phase_hash_count[li][p] + 1;
                end
            end

            if (debug_phase == 6 && b_chon) begin
                if (b_pan == 2'b10) begin
                    if (audio_r != 0) pan_leak = pan_leak + 1;
                    if (audio_l != 0) left_nonzero = left_nonzero + 1;
                end else if (b_pan == 2'b01) begin
                    if (audio_l != 0) pan_leak = pan_leak + 1;
                    if (audio_r != 0) right_nonzero = right_nonzero + 1;
                end
            end
            // The Phase 4A restart anchor is exactly the first 1024 public
            // samples (512 logical nibbles).  Raw decoder chon may remain set
            // after EOS until a later command RESET, so never extend the
            // audio window with post-EOS digital zero.
            if (natural_run >= 0 && natural_run <= 3 && b_chon &&
                natural_public[natural_run] < 1024) begin
                natural_public[natural_run] =
                    natural_public[natural_run] + 1;
                natural_hash[natural_run] = hash_stereo(
                    natural_hash[natural_run], audio_l, audio_r);
                if (prefix_count[natural_run] < 16) begin
                    if ((natural_run & 1) == 0) begin
                        first_prefix_l[natural_run >> 1]
                                      [prefix_count[natural_run]] = audio_l;
                        first_prefix_r[natural_run >> 1]
                                      [prefix_count[natural_run]] = audio_r;
                    end else if (audio_l !==
                                 first_prefix_l[natural_run >> 1]
                                               [prefix_count[natural_run]] ||
                                 audio_r !==
                                 first_prefix_r[natural_run >> 1]
                                               [prefix_count[natural_run]]) begin
                        stale_prefix = stale_prefix + 1;
                    end
                    prefix_count[natural_run] =
                        prefix_count[natural_run] + 1;
                end
            end
            if (natural_run >= 0 && natural_run <= 3 &&
                !b_chon && debug_adpcmb_eos &&
                natural_zero_latency[natural_run] < 0) begin
                if (audio_l == 0 && audio_r == 0)
                    natural_zero_latency[natural_run] = zero_wait_samples;
                else zero_wait_samples = zero_wait_samples + 1;
            end
            if (phase5_stop_seen && phase5_zero_latency < 0) begin
                if (audio_l == 0 && audio_r == 0)
                    phase5_zero_latency = phase5_zero_wait;
                else phase5_zero_wait = phase5_zero_wait + 1;
            end
        end

        if (debug_phase == 5 && !b_chon && previous_b_active) begin
            phase5_stop_seen = 1'b1;
            phase5_zero_wait = 0;
            phase5_zero_latency = -1;
        end
        if (phase5_stop_seen && debug_phase == 0 &&
            debug_segment_state == 7'd38 &&
            debug_adpcmb_request === 1'b1)
            phase5_request_after_stop = phase5_request_after_stop + 1;

        if (debug_phase == 7 && b_chon && !previous_b_active) begin
            natural_run = natural_run + 1;
            if (natural_run > 3) fail("NATURAL_EXTRA_START");
            $display("HW0_NATURAL_START run=%0d playback=%0d address=%06h",
                     run_id, natural_run, debug_adpcmb_addr);
        end
        if (debug_phase == 7 && !b_chon && previous_b_active &&
            natural_run >= 0 && natural_run <= 3) begin
            zero_wait_samples = 0;
            natural_zero_latency[natural_run] = -1;
        end
        if (debug_phase == 7 && b_logical && natural_run >= 0 &&
            natural_run <= 3)
            natural_logical[natural_run] = natural_logical[natural_run] + 1;

        previous_public = audio_sample;
        previous_internal = internal_sample;
        previous_measurement = debug_measurement_active;
        previous_b_active = b_chon;
        previous_b_eos = debug_adpcmb_eos;
        previous_external_mute = debug_external_mute;
    end

    ym2610_hw0_top #(
        .FAST_SIM(`SEMANTIC_FAST_SIM),
        .BOOT_SAMPLES(SIM_BOOT),
        .COLOR_PREROLL_SAMPLES(SIM_PREROLL),
        .SOUND_DWELL_SAMPLES(SIM_DWELL),
        .INTER_SILENCE_SAMPLES(SIM_INTER),
        .PAN_DWELL_SAMPLES(SIM_PAN),
        .PAN_INTER_SAMPLES(SIM_PAN_INTER),
        .NATURAL_SILENCE_SAMPLES(SIM_NATURAL_SILENCE),
        .FINAL_SILENCE_SAMPLES(SIM_FINAL),
        .REFERENCE_DWELL_SAMPLES(SIM_DWELL),
        .REFERENCE_GAP_SAMPLES(SIM_INTER),
        .PCM_ATTEMPT_SAMPLES(SIM_DWELL),
        .A0_ATTEMPT_SAMPLES(4097),
        .A6_ATTEMPT_SAMPLES(8193),
        .B_ATTEMPT_SAMPLES(4098),
        .PCM_ATTEMPT_GAP_SAMPLES(SIM_INTER),
        .PCM_RESULT_SAMPLES(SIM_INTER),
        .SUMMARY_SAMPLES(SIM_FINAL)
    ) dut (
        .clk_sys(clk), .reset(reset), .video_reset(video_reset),
        .audio_l(audio_l), .audio_r(audio_r), .audio_sample(audio_sample),
        .video_ce(video_ce), .video_hs(video_hs), .video_vs(video_vs),
        .video_de(video_de), .video_r(video_r), .video_g(video_g),
        .video_b(video_b), .debug_phase(debug_phase),
        .debug_segment_state(debug_segment_state),
        .debug_startup_state(debug_startup_state),
        .debug_external_mute(debug_external_mute),
        .debug_sample_tick(debug_sample_tick),
        .debug_sample_tick_count(debug_sample_tick_count),
        .debug_sample_cadence_error(debug_sample_cadence_error),
        .debug_sample_width_error(debug_sample_width_error),
        .debug_microcode_index(debug_microcode_index),
        .debug_accepted_writes(debug_accepted_writes),
        .debug_busy_timeout(debug_busy_timeout),
        .debug_write_while_busy(debug_write_while_busy),
        .debug_zero_timeout(debug_zero_timeout),
        .debug_phase_error(debug_phase_error),
        .debug_restart_count(debug_restart_count),
        .debug_measurement_active(debug_measurement_active),
        .debug_measurement_phase(debug_measurement_phase),
        .debug_adpcma_request(debug_adpcma_request),
        .debug_adpcmb_request(debug_adpcmb_request),
        .debug_adpcma_eos(debug_adpcma_eos),
        .debug_adpcmb_eos(debug_adpcmb_eos),
        .debug_adpcmb_active(debug_adpcmb_active),
        .debug_adpcma_addr(debug_adpcma_addr),
        .debug_adpcma_bank(debug_adpcma_bank),
        .debug_adpcmb_addr(debug_adpcmb_addr),
        .debug_psg_a(debug_psg_a), .debug_psg_b(debug_psg_b),
        .debug_psg_c(debug_psg_c), .debug_psg_snd(debug_psg_snd),
        .debug_core_ready(debug_core_ready),
        .debug_reset_cen_count(debug_reset_cen_count),
        .debug_halted(debug_halted)
    );

    // S4: only the semantic-silence contract differs from frozen TB5.
    semantic_silence_monitor #(
        .FIX_SETUP_BOUNDARY(1),
        .FIX_ZERO_CLASS(1),
        .FAST_MODE(SEMANTIC_FAST_MODE),
        .RUN_ID(1)
    ) u_semantic_silence_monitor (
        .clk(clk), .reset(reset), .system_cycle(system_cycle),
        .sample_tick_count(debug_sample_tick_count),
        .public_sample_count(public_samples),
        .public_sample(audio_sample), .phase(debug_phase),
        .state(debug_segment_state),
        .zero_wait(dut.u_sequencer.zero_wait_state),
        .zero_sample_ok(dut.u_sequencer.zero_sample_ok),
        .zero_run_count(dut.u_sequencer.zero_run_count),
        .zero_state_sample_count(dut.u_sequencer.sample_count),
        .program_active(dut.u_sequencer.program_active),
        .program_id(dut.u_sequencer.program_id),
        .microcode_index(debug_microcode_index),
        .accepted_write_count(debug_accepted_writes),
        .diag_attempt_index(dut.u_sequencer.diag_attempt_index),
        .adpcma_request(debug_adpcma_request),
        .adpcmb_request(debug_adpcmb_request),
        .restart_count(debug_restart_count),
        .external_mute(debug_external_mute),
        .internal_left(dut.internal_left),
        .internal_right(dut.internal_right),
        .public_left(audio_l), .public_right(audio_r),
        .current_zero_class(semantic_current_zero_class),
        .transition_active(semantic_transition_active),
        .mute_deadline_active(semantic_mute_deadline_active),
        .post_sample_pending(semantic_post_sample_pending),
        .transition_entries(semantic_transition_entries),
        .transition_completes(semantic_transition_completes),
        .zero_qualified_total(semantic_zero_qualified),
        .zero_confirmed_total(semantic_zero_confirmed),
        .zero_timed_out_total(semantic_zero_timed_out),
        .mute_assertions(semantic_mute_assertions),
        .post_samples(semantic_post_samples),
        .silence_errors(semantic_silence_errors),
        .first_failure_code(semantic_first_failure_code),
        .first_failure_cycle(semantic_first_failure_cycle),
        .expected_program_debug(semantic_expected_program),
        .expected_state_debug(semantic_expected_state),
        .setup_count_debug(semantic_setup_count),
        .transition_zero_count_debug(semantic_transition_zero_count),
        .completion_reason_debug(semantic_completion_reason)
    );

    final_public_zero_dwell #(.MODE(3), .FINAL_POST_INDEX(64), .REQUIRED_SAMPLES(512)) u_final_dwell (
        .clk(clk), .reset(reset), .public_sample(audio_sample),
        .external_mute(debug_external_mute), .public_left(audio_l), .public_right(audio_r),
        .semantic_mute_assertions(semantic_mute_assertions), .semantic_post_samples(semantic_post_samples),
        .phase(4'd0), .state(7'd0), .terminal_check(1'b0),
        .armed(final_dwell_armed), .complete(final_dwell_complete), .short(final_dwell_short),
        .nonzero_break(final_dwell_break), .count(final_dwell_count));

    initial begin
        integer i, j;
        if (!$value$plusargs("RUN_ID=%d", run_id)) run_id = 1;
        for (j = 0; j < 2; j = j + 1) begin
            for (i = 1; i <= 5; i = i + 1) begin
                phase_hash[j][i] = FNV_OFFSET;
                phase_hash_count[j][i] = 0;
            end
            for (i = 0; i < 9; i = i + 1) begin
                sound_event_tick[j][i]=0;
                stop_event_tick[j][i]=0;
                zero_event_tick[j][i]=0;
                if (i < 8) color_event_tick[j][i]=0;
            end
        end
        for (i = 0; i < 4; i = i + 1) begin
            natural_hash[i] = FNV_OFFSET;
            natural_logical[i] = 0;
            natural_public[i] = 0;
            natural_zero_latency[i] = -1;
            prefix_count[i] = 0;
        end
        for (i = 1; i <= 7; i = i + 1) color_visits[i] = 0;

        repeat (4) @(posedge clk);
        video_reset = 1'b0;
        repeat (64) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        fork
            begin
                wait (debug_restart_count >= SEMANTIC_REQUIRED_LOOPS ||
                      semantic_timeout_fired);
            end
            begin
                repeat (SEMANTIC_WALL_SAFETY_CYCLES) @(posedge clk);
                if (debug_restart_count < SEMANTIC_REQUIRED_LOOPS)
                    semantic_timeout_fail("wall_safety",
                                          "loop_complete");
            end
        join_any
        disable fork;
        wait (final_dwell_complete);
        repeat (1) @(posedge clk);

        if (debug_halted || debug_busy_timeout || debug_write_while_busy ||
            debug_zero_timeout || debug_phase_error)
            fail("SEQUENCER_ERROR");
        if (debug_reset_cen_count != 6) fail("RESET_CEN_COUNT");
        if (phase_transition_index != 16) fail("PHASES_INCOMPLETE");
        if (sound_event_index != 18 || stop_event_index != 18 ||
            zero_event_index != 18) fail("TIMELINE_EVENT_COUNT");
        for (i = 1; i <= 7; i = i + 1)
            if (color_visits[i] != 2)
                fail("COLOR_VISIT_COUNT");
        if (cold_zero_samples < SIM_BOOT) fail("COLD_SILENCE_SHORT");
        if (!final_dwell_complete) fail("FINAL_SILENCE_SHORT");
        if (cadence_errors != 0 || width_errors != 0 ||
            drops != 0 || duplicates != 0 || tick_missed != 0 ||
            tick_duplicates != 0 || debug_sample_cadence_error ||
            debug_sample_width_error) fail("SAMPLE_CONTRACT");
        if (pre_ready_x != 0 || pre_ready_nonzero != 0)
            fail("PRE_READY_AUDIO");
        if (x_count != 0) fail("PUBLIC_X");
        for (j = 0; j < 2; j = j + 1) begin
            if (phase_hash_count[j][1] != 4096 ||
                phase_hash[j][1] != 64'h8aadd7a6819038e5) fail("FM_HASH");
            if (phase_hash_count[j][2] != 4096 ||
                phase_hash[j][2] != 64'h54730095b12b6325) fail("SSG_HASH");
            if (phase_hash_count[j][3] != 4096 ||
                phase_hash[j][3] != 64'hadf8cc2f2f81c1b9) fail("ADPCMA0_HASH");
            if (phase_hash_count[j][4] != 8192 ||
                phase_hash[j][4] != 64'h32cb891931682fe9) fail("ADPCMA6_HASH");
            if (phase_hash_count[j][5] != 4097 ||
                phase_hash[j][5] != 64'h1207d84363d4ed39) fail("ADPCMB_HASH");
        end
        if (a6_overflow_events != 0) fail("ADPCMA6_OVERFLOW");
        if (!phase5_stop_seen || phase5_zero_latency < 0 ||
            phase5_zero_latency > 3 || phase5_request_after_stop != 0)
            fail("ADPCMB_RESET_STOP");
        if (pan_leak != 0 || left_nonzero == 0 || right_nonzero == 0)
            fail("PAN_ISOLATION");
        if (psg_a_nonzero == 0 || psg_bc_spurious != 0)
            fail("SSG_ISOLATION");
        if (unexpected_adpcm_requests != 0)
            fail("ADPCM_IDLE_FETCH");
        for (i = 0; i < 4; i = i + 1) begin
            if (natural_logical[i] != 512) fail("NATURAL_LOGICAL_COUNT");
            if (natural_zero_latency[i] < 0 ||
                natural_zero_latency[i] > 4) fail("NATURAL_ZERO_LATENCY");
            if (natural_hash[i] != 64'he142f7da424b1531)
                fail("NATURAL_HASH");
        end
        if (natural_hash[0] != natural_hash[1] ||
            natural_hash[0] != natural_hash[2] ||
            natural_hash[0] != natural_hash[3] || stale_prefix != 0)
            fail("NATURAL_RESTART");

        for (j = 0; j < 2; j = j + 1) begin
            for (i = 0; i < 8; i = i + 1) begin
                if (sound_event_tick[j][i] < color_event_tick[j][i] +
                                                   SIM_PREROLL)
                    fail("COLOR_START_ORDER");
                if (stop_event_tick[j][i] <= sound_event_tick[j][i] ||
                    zero_event_tick[j][i] <= stop_event_tick[j][i])
                    fail("STOP_ZERO_ORDER");
            end
            if (stop_event_tick[j][8] <= sound_event_tick[j][8] ||
                zero_event_tick[j][8] <= stop_event_tick[j][8])
                fail("RESTART_STOP_ZERO_ORDER");
        end

        if (semantic_transition_active ||
            semantic_mute_deadline_active ||
            semantic_post_sample_pending ||
            semantic_transition_entries !=
            semantic_transition_completes ||
            semantic_transition_completes !=
            semantic_mute_assertions ||
            semantic_silence_errors != 0)
            fail("SEMANTIC_SILENCE_CONTRACT");
        $display("HW0_SEM_SILENCE run=%0d mode=%0d entries=%0d completes=%0d confirm=%0d timeout=%0d mute=%0d post=%0d qualified=%0d errors=%0d",
            run_id, SEMANTIC_FAST_MODE,
            semantic_transition_entries,
            semantic_transition_completes,
            semantic_zero_confirmed, semantic_zero_timed_out,
            semantic_mute_assertions, semantic_post_samples,
            semantic_zero_qualified, semantic_silence_errors);
        $display("HW0_SEM_CADENCE run=%0d mode=%0d logical=%0d rise=%0d fall=%0d missing=%0d duplicate=%0d overlap=%0d order=%0d interval=%0d/%0d width=%0d/%0d",
            run_id, SEMANTIC_FAST_MODE, semantic_logical_samples,
            semantic_public_rises, semantic_public_falls,
            semantic_missing_pulses, semantic_duplicate_pulses,
            semantic_overlap_pulses, semantic_order_errors,
            semantic_interval_min, semantic_interval_max,
            semantic_width_min, semantic_width_max);
        $display("HW0_SEM_TIMEOUT_SUMMARY run=%0d mode=%0d state_budget=%0d phase_budget=%0d loop_budget=%0d wall_cycles=%0d sample_gap_cycles=%0d semantic_samples=%0d errors=%0d",
            run_id, SEMANTIC_FAST_MODE,
            SEMANTIC_STATE_SAMPLE_BUDGET,
            SEMANTIC_PHASE_SAMPLE_BUDGET,
            SEMANTIC_FULL_LOOP_SAMPLE_BUDGET,
            SEMANTIC_WALL_SAFETY_CYCLES,
            SEMANTIC_SAMPLE_PROGRESS_CYCLES,
            semantic_timeout_public_samples,
            semantic_timeout_count);
        $display("HW0_HASH run=%0d fm=%016h ssg=%016h a0=%016h a6=%016h b=%016h counts=%0d/%0d/%0d/%0d/%0d loop2=%016h/%016h/%016h/%016h/%016h",
            run_id, phase_hash[0][1], phase_hash[0][2], phase_hash[0][3],
            phase_hash[0][4], phase_hash[0][5], phase_hash_count[0][1],
            phase_hash_count[0][2], phase_hash_count[0][3],
            phase_hash_count[0][4], phase_hash_count[0][5],
            phase_hash[1][1],phase_hash[1][2],phase_hash[1][3],
            phase_hash[1][4],phase_hash[1][5]);
        $display("HW0_CONTRACT run=%0d writes=%0d timeout=%0d busy_write=%0d zero_timeout=%0d phase_error=%0d cadence_errors=%0d width_errors=%0d drops=%0d duplicates=%0d tick=%0d/%0d x=%0d cold=%0d final=%0d b_reset_zero=%0d b_post_request=%0d pan_leak=%0d pan_nonzero=%0d/%0d natural=%0d/%0d/%0d/%0d natural_public=%0d/%0d/%0d/%0d restart_hash=%016h/%016h/%016h/%016h stale=%0d loops=%0d",
            run_id, debug_accepted_writes, debug_busy_timeout,
            debug_write_while_busy,debug_zero_timeout,debug_phase_error,
            cadence_errors,width_errors,drops,duplicates,
            tick_missed,tick_duplicates,x_count,cold_zero_samples,final_zero_samples,
            phase5_zero_latency, phase5_request_after_stop,
            pan_leak, left_nonzero, right_nonzero,
            natural_logical[0],natural_logical[1],natural_logical[2],natural_logical[3],
            natural_public[0],natural_public[1],natural_public[2],natural_public[3],
            natural_hash[0],natural_hash[1],natural_hash[2],natural_hash[3],stale_prefix,
            debug_restart_count);
        $display("HW0_X run=%0d pre_ready=%0d/%0d audio=%0d internal=%0d control=%0d psg=%0d rom_a=%0d rom_b=%0d ssg_bc=%0d adpcm_idle=%0d a6_overflow=%0d",
            run_id,pre_ready_x,pre_ready_nonzero,x_audio,x_internal,x_control,x_psg,
            x_rom_a,x_rom_b,psg_bc_spurious,unexpected_adpcm_requests,
            a6_overflow_events);
        $display("HW0_TIMELINE run=%0d fm=%0d/%0d/%0d/%0d ssg=%0d/%0d/%0d/%0d a0=%0d/%0d/%0d/%0d a6=%0d/%0d/%0d/%0d b=%0d/%0d/%0d/%0d left=%0d/%0d/%0d/%0d right=%0d/%0d/%0d/%0d natural=%0d/%0d/%0d/%0d restart=%0d/%0d/%0d loops=%0d",
            run_id,
            color_event_tick[0][0],sound_event_tick[0][0],stop_event_tick[0][0],zero_event_tick[0][0],
            color_event_tick[0][1],sound_event_tick[0][1],stop_event_tick[0][1],zero_event_tick[0][1],
            color_event_tick[0][2],sound_event_tick[0][2],stop_event_tick[0][2],zero_event_tick[0][2],
            color_event_tick[0][3],sound_event_tick[0][3],stop_event_tick[0][3],zero_event_tick[0][3],
            color_event_tick[0][4],sound_event_tick[0][4],stop_event_tick[0][4],zero_event_tick[0][4],
            color_event_tick[0][5],sound_event_tick[0][5],stop_event_tick[0][5],zero_event_tick[0][5],
            color_event_tick[0][6],sound_event_tick[0][6],stop_event_tick[0][6],zero_event_tick[0][6],
            color_event_tick[0][7],sound_event_tick[0][7],stop_event_tick[0][7],zero_event_tick[0][7],
            sound_event_tick[0][8],stop_event_tick[0][8],zero_event_tick[0][8],debug_restart_count);
        $display("P3_CLEAN_LEGACY_SUMMARY failures=%0d", failures);
        // Target-only P3 observer owns terminal acceptance and termination.
    end
endmodule

module tb_ym2610_hw0_pcm_diag_negative;
    logic clk=0, reset=1, sample_tick=0;
    logic [31:0] tick_count=0;
    logic [2:0] phase_index=0, attempt_index=0;
    logic phase_begin=0, attempt_begin=0, attempt_end=0;
    logic stop_pass=0, pan_right=0, raw_request=0, capture_event=0;
    logic [23:0] rom_address=0;
    logic [7:0] rom_data=0;
    logic signed [15:0] lane_left=0,lane_right=0;
    logic signed [15:0] final_left=0,final_right=0;
    logic signed [15:0] output_left=0,output_right=0;
    wire attempt_active;
    wire [6:0] status_seen,status_fail;
    wire [34:0] summary_pass;
    wire [4:0] summary_valid;
    wire [27:0] event_counts;
    wire [111:0] first_event_ticks;
    wire [7:0] request_count,address_change_count,distinct_address_count;
    wire [2:0] completed_attempt_count;
    wire [23:0] first_address,last_address;
    wire [3:0] last_error_code;
    integer failures=0;

    always #5 clk=~clk;
    always @(posedge clk) if(!reset) tick_count<=tick_count+1;
    task automatic fail(input [8*64-1:0] message);
        begin failures=failures+1;
            $display("HW0_NEGATIVE_FAIL case_phase=%0d seen=%02h fail=%02h summary=%09h code=%0d reason=%0s",
                phase_index,status_seen,status_fail,summary_pass,
                last_error_code,message);
        end
    endtask
    task automatic begin_case(input [2:0] p);
        begin
            reset=1; repeat(2) @(posedge clk); reset=0;
            begin_case_no_reset(p);
        end
    endtask
    task automatic begin_case_no_reset(input [2:0] p);
        begin
            phase_index=p; attempt_index=0; phase_begin=1;
            @(posedge clk); #1; phase_begin=0; attempt_begin=1;
            @(posedge clk); #1; attempt_begin=0;
        end
    endtask
    task automatic request_only;
        begin raw_request=1; @(posedge clk); #1; raw_request=0; end
    endtask
    task automatic two_captures;
        begin
            raw_request=1; capture_event=1; rom_address=24'h002000;
            rom_data=8'h29; @(posedge clk); #1;
            rom_address=24'h002001; rom_data=8'h72;
            @(posedge clk); #1;
            raw_request=0; capture_event=0;
            repeat(2) @(posedge clk);
        end
    endtask
    task automatic audio_event(input bit lane_on,input bit final_on,
                               input bit output_on);
        begin
            lane_left=lane_on?16'sd7:0;
            final_left=final_on?16'sd9:0;
            output_left=output_on?16'sd9:0;
            sample_tick=1; @(posedge clk); #1; sample_tick=0;
            lane_left=0; final_left=0; output_left=0;
        end
    endtask
    task automatic close_case(input bit stop_ok);
        begin
            stop_pass=stop_ok; attempt_end=1;
            @(posedge clk); #1; attempt_end=0; stop_pass=0;
            @(posedge clk); #1;
        end
    endtask

    ym2610_hw0_pcm_diag_monitor dut(
        .clk(clk),.reset(reset),.sample_tick(sample_tick),
        .sample_tick_count(tick_count),.phase_index(phase_index),
        .attempt_index(attempt_index),.phase_begin(phase_begin),
        .attempt_begin(attempt_begin),.attempt_end(attempt_end),
        .stop_pass(stop_pass),.pan_right(pan_right),
        .raw_request(raw_request),.capture_event(capture_event),
        .rom_address(rom_address),.rom_data(rom_data),
        .lane_left(lane_left),.lane_right(lane_right),
        .final_left(final_left),.final_right(final_right),
        .output_left(output_left),.output_right(output_right),
        .attempt_active(attempt_active),.status_seen(status_seen),
        .status_fail(status_fail),.summary_pass(summary_pass),
        .summary_valid(summary_valid),.event_counts(event_counts),
        .first_event_ticks(first_event_ticks),.request_count(request_count),
        .first_address(first_address),.last_address(last_address),
        .address_change_count(address_change_count),
        .distinct_address_count(distinct_address_count),
        .completed_attempt_count(completed_attempt_count),
        .last_error_code(last_error_code));

    initial begin
        // ROM response suppressed: raw request survives, capture/progress fail.
        begin_case(0); request_only(); close_case(1);
        if(!status_seen[0] || status_seen[1] || status_seen[2] ||
           !status_fail[1] || !status_fail[2] || last_error_code!=5)
            fail("ROM_RESPONSE_STOP");
        if(summary_pass[6:0]==7'h7f) fail("ROM_FAILURE_NOT_LATCHED");

        // Legal changing transactions with a zero source lane.
        begin_case(1); two_captures(); audio_event(0,0,0); close_case(1);
        if(status_seen[2:0]!=3'b111 || status_seen[3] ||
           !status_fail[3] || last_error_code!=6 ||
           distinct_address_count!=2)
            fail("SOURCE_LANE_ZERO");

        // Lane/final are live but the post-mute HW output is held at zero.
        begin_case(2); two_captures(); audio_event(1,1,0); close_case(1);
        if(status_seen[4:0]!=5'b11111 || status_seen[5] ||
           !status_fail[5] || last_error_code!=8)
            fail("EXTERNAL_MUTE");

        // EOS/restart suppression is represented by a failed stop result.
        begin_case(4); two_captures(); audio_event(1,1,1); close_case(0);
        if(status_seen[5:0]!=6'b111111 || status_seen[6] ||
           !status_fail[6] || last_error_code!=10)
            fail("EOS_RESTART_SUPPRESSED");

        // Repeat all four faults without reset and insert a fully passing pan
        // row.  The observer has no feedback path to the sequencer: every
        // later phase remains runnable and the five-row summary preserves all
        // earlier red cells.
        reset=1; repeat(2) @(posedge clk); reset=0;
        begin_case_no_reset(0); request_only(); close_case(1);
        begin_case_no_reset(1); two_captures(); audio_event(0,0,0);
        close_case(1);
        begin_case_no_reset(2); two_captures(); audio_event(1,1,0);
        close_case(1);
        begin_case_no_reset(3); pan_right=0; two_captures();
        audio_event(1,1,1); close_case(1);
        begin_case_no_reset(4); two_captures(); audio_event(1,1,1);
        close_case(0);
        if(summary_valid!=5'h1f || summary_pass[6:0]!=7'h41 ||
           summary_pass[13:7]!=7'h47 ||
           summary_pass[20:14]!=7'h5f ||
           summary_pass[27:21]!=7'h7f ||
           summary_pass[34:28]!=7'h3f || last_error_code!=5)
            fail("NONFATAL_CONTINUATION_SUMMARY");

        if(failures) $fatal(1,"negative controls failed (%0d)",failures);
        $display("HW0_NEGATIVE controls=rom_stop/lane_zero/output_mute/eos_suppress continuation=5/5 summary=PASS red_cells=PASS result=PASS");
        $finish;
    end
endmodule

module tb_ym2610_hw0_video_diag;
    logic clk=0,reset=1;
    logic [3:0] phase=0,error_code=0;
    logic error=0,diag_attempt_active=0,summary_active=0;
    logic [6:0] diag_seen=0,diag_fail=0;
    logic [2:0] diag_attempt=0,diag_completed_attempts=0;
    logic [34:0] diag_summary=0;
    logic [4:0] diag_summary_valid=0;
    wire ce_pixel,hsync,vsync,de;
    wire [7:0] r,g,b;
    integer failures=0;
    integer i,j,code;
    logic [23:0] expected_color;
    always #5 clk=~clk;
    task automatic fail(input [8*48-1:0] message);
        begin failures=failures+1;
            $display("HW0_VIDEO_FAIL x=%0d y=%0d rgb=%02h%02h%02h reason=%0s",
                dut.h_count,dut.v_count,r,g,b,message);
        end
    endtask
    task automatic expect_pixel(input integer x,input integer y,
                                input [23:0] expected,
                                input [8*48-1:0] message);
        begin
            while(dut.h_count!=x || dut.v_count!=y) @(posedge clk);
            #1; if({r,g,b}!==expected) fail(message);
        end
    endtask
    ym2610_hw0_video dut(
        .clk(clk),.reset(reset),.phase(phase),.error(error),
        .error_code(error_code),.diag_seen(diag_seen),
        .diag_fail(diag_fail),.diag_attempt(diag_attempt),
        .diag_completed_attempts(diag_completed_attempts),
        .diag_attempt_active(diag_attempt_active),
        .diag_summary(diag_summary),
        .diag_summary_valid(diag_summary_valid),
        .summary_active(summary_active),.ce_pixel(ce_pixel),
        .hsync(hsync),.vsync(vsync),.de(de),.r(r),.g(g),.b(b));
    initial begin
        repeat(4) @(posedge clk); reset=0;

        // All four marker quadrants, including its priority over phase color.
        phase=3;
        expect_pixel(505,8,24'hffffff,"CHECKER_WHITE");
        expect_pixel(513,8,24'hff00b0,"CHECKER_MAGENTA");
        expect_pixel(505,16,24'hff00b0,"CHECKER_MAGENTA_LOWER");
        expect_pixel(513,16,24'hffffff,"CHECKER_WHITE_LOWER");

        // Every display phase preserves its established background color.
        for (i=0;i<=8;i=i+1) begin
            phase=i;
            case(i)
                1: expected_color=24'h0030ff;
                2: expected_color=24'h00d040;
                3: expected_color=24'hffe000;
                4: expected_color=24'hff7000;
                5: expected_color=24'hff00b0;
                6: expected_color=24'h00d8e8;
                7: expected_color=24'hffffff;
                8: expected_color=24'h000018;
                default: expected_color=24'h000030;
            endcase
            expect_pixel(20,100,expected_color,"PHASE_BACKGROUND");
        end

        // Exercise all four seen/fail input combinations in every status
        // column.  Fail has the existing priority when both bits are high.
        phase=3;
        for (i=0;i<7;i=i+1) begin
            diag_seen=0; diag_fail=0;
            expect_pixel(20+i*68,10,24'h303038,"STATUS_STATE_0_GRAY");
            diag_seen[i]=1;
            expect_pixel(20+i*68,10,24'h20e060,"STATUS_STATE_1_GREEN");
            diag_seen[i]=0; diag_fail[i]=1;
            expect_pixel(20+i*68,10,24'hff2020,"STATUS_STATE_2_RED");
            diag_seen[i]=1;
            expect_pixel(20+i*68,10,24'hff2020,"STATUS_STATE_3_FAIL_PRIORITY");
        end
        diag_seen=0; diag_fail=0;

        // Current, completed, and pending rendering for attempts 0 through 5.
        diag_completed_attempts=0; diag_attempt_active=1;
        for (i=0;i<6;i=i+1) begin
            diag_attempt=i;
            expect_pixel(75+i*64,220,24'h20e060,"ATTEMPT_CURRENT_0_TO_5");
        end
        diag_attempt_active=0; diag_completed_attempts=6;
        for (i=0;i<6;i=i+1)
            expect_pixel(75+i*64,220,24'hffffff,"ATTEMPT_DONE_0_TO_5");
        diag_completed_attempts=0;
        for (i=0;i<6;i=i+1)
            expect_pixel(75+i*64,220,24'h303038,"ATTEMPT_PENDING_0_TO_5");
        phase=7; diag_attempt=4; diag_attempt_active=1;
        for (i=3;i<6;i=i+1)
            expect_pixel(75+i*64,220,24'h303038,"NATURAL_UNUSED_ATTEMPT");

        // Check all row identifiers and every row/column matrix mapping in
        // valid-green, valid-red, and invalid-gray states.
        summary_active=1; phase=8; diag_summary=0;
        diag_summary_valid=5'h1f;
        for (i=0;i<5;i=i+1) begin
            case(i)
                0: expected_color=24'hffe000;
                1: expected_color=24'hff7000;
                2: expected_color=24'hff00b0;
                3: expected_color=24'h00d8e8;
                default: expected_color=24'hffffff;
            endcase
            expect_pixel(12,45+i*38,expected_color,"SUMMARY_ROW_COLOR_0_TO_4");
        end
        for (i=0;i<5;i=i+1) begin
            for (j=0;j<7;j=j+1) begin
                diag_summary=0;
                expect_pixel(60+j*60,45+i*38,24'hff2020,"SUMMARY_CELL_RED_5X7");
                diag_summary[i*7+j]=1;
                expect_pixel(60+j*60,45+i*38,24'h20e060,"SUMMARY_CELL_GREEN_5X7");
            end
        end
        diag_summary=0; diag_summary_valid=0;
        for (i=0;i<5;i=i+1)
            for (j=0;j<7;j=j+1)
                expect_pixel(60+j*60,45+i*38,24'h303038,"SUMMARY_CELL_GRAY_5X7");

        // Exhaust all 16 fatal codes and all four bit boxes.
        summary_active=0; error=1;
        expect_pixel(20,100,24'hff0000,"FATAL_RED");
        for (code=0;code<16;code=code+1) begin
            error_code=code;
            for (j=0;j<4;j=j+1) begin
                expected_color=((code >> (3-j)) & 1) ?
                               24'hffffff : 24'h000000;
                expect_pixel(165+j*52,200,expected_color,
                             "FATAL_CODE_0_TO_15");
            end
        end
        expect_pixel(505,8,24'hffffff,"FATAL_CHECKER_PRIORITY");

        // Outside the active 529x240 raster, RGB must remain the black
        // default regardless of phase/error state.
        expect_pixel(600,250,24'h000000,"OUT_OF_RANGE_DEFAULT");
        if(failures) $fatal(1,"video diagnostic failed (%0d)",failures);
        $display("HW0_VIDEO marker=4/4 phases=9/9 status_vectors=4x7 attempts=0-5 summary=5x7x3 fatal_codes=0-15 out_of_range=PASS result=PASS");
        $finish;
    end
endmodule

// PCM-path diagnostic positive contract.  Every hardware attempt is retained;
// only the human-duration holds are reduced.
module tb_ym2610_hw0_pcm_diag;
    localparam logic [63:0] FNV_OFFSET = 64'hcbf29ce484222325;
    localparam integer SIM_BOOT = 256;
    localparam integer SIM_PREROLL = 128;
    localparam integer SIM_DWELL = 8193;
    localparam integer SIM_GAP = 128;
    localparam integer SIM_NATURAL = 512;
    localparam integer SIM_RESULT = 128;
    localparam integer SIM_SUMMARY = 256;
    logic clk = 0;
    logic reset = 1;
    logic video_reset = 1;
    integer run_id = 1;
    integer failures = 0;
    integer system_cycle = 0;
    integer last_public_cycle = -1;
    integer public_width = 0;
    integer cadence_errors = 0;
    integer width_errors = 0;
    integer drops = 0;
    integer duplicates = 0;
    integer tick_missed = 0;
    integer tick_duplicates = 0;
    integer x_count = 0;
    integer x_control = 0;
    integer x_audio = 0;
    integer x_adpcma_lane = 0;
    integer x_adpcmb_lane = 0;
    integer x_adpcma_rom = 0;
    integer x_adpcmb_rom = 0;
    integer summary_count = 0;
    integer requested_loops = 2;
    integer phase_visits [1:8];
    integer attempt_closures [0:4];
    integer pan_leak = 0;
    integer pan_expected = 0;
    integer natural_index = -1;
    integer natural_logical [0:11];
    integer natural_public [0:11];
    integer natural_stale = 0;
    integer li;
    integer pi;
    integer ai;
    logic previous_public = 0;
    logic previous_internal = 0;
    logic previous_diag_active = 0;
    logic previous_summary = 0;
    logic previous_b_chon = 0;
    logic [3:0] previous_phase = 0;
    logic [15:0] prefix_l [0:5][0:15];
    logic [15:0] prefix_r [0:5][0:15];
    integer prefix_count [0:11];
    logic [63:0] reference_hash [0:1][1:2];
    integer reference_count [0:1][1:2];
    logic [63:0] pcm_hash [0:1][0:2][0:5];
    integer pcm_count [0:1][0:2][0:5];
    logic [63:0] natural_hash [0:11];

    wire signed [15:0] audio_l, audio_r;
    wire audio_sample;
    wire video_ce, video_hs, video_vs, video_de;
    wire [7:0] video_r, video_g, video_b;
    wire [3:0] debug_phase;
    wire [6:0] debug_segment_state;
    wire [2:0] debug_startup_state;
    wire debug_external_mute, debug_sample_tick;
    wire [31:0] debug_sample_tick_count;
    wire debug_sample_cadence_error, debug_sample_width_error;
    wire [31:0] debug_accepted_writes;
    wire debug_busy_timeout, debug_write_while_busy;
    wire debug_zero_timeout, debug_phase_error, debug_halted;
    wire [15:0] debug_restart_count;
    wire debug_measurement_active;
    wire [3:0] debug_measurement_phase;
    wire [2:0] debug_diag_phase, debug_diag_attempt;
    wire [2:0] debug_diag_completed_attempts;
    wire debug_diag_attempt_active;
    wire [6:0] debug_diag_seen, debug_diag_fail;
    wire [34:0] debug_diag_summary;
    wire [4:0] debug_diag_summary_valid;
    wire [27:0] debug_diag_event_counts;
    wire [111:0] debug_diag_first_ticks;
    wire [7:0] debug_diag_request_count;
    wire [23:0] debug_diag_first_addr, debug_diag_last_addr;
    wire [7:0] debug_diag_address_changes;
    wire [7:0] debug_diag_distinct_addresses;
    wire [3:0] debug_last_error_code;
    wire debug_summary_active;
    wire debug_adpcma_request, debug_adpcmb_request;
    wire [19:0] debug_adpcma_addr;
    wire [3:0] debug_adpcma_bank;
    wire [23:0] debug_adpcmb_addr;
    wire debug_adpcmb_eos, debug_adpcmb_active;
    wire debug_core_ready;
    wire [2:0] debug_reset_cen_count;
    wire signed [15:0] debug_jt10_final_left;
    wire signed [15:0] debug_jt10_final_right;
    wire signed [15:0] debug_premute_left;
    wire signed [15:0] debug_premute_right;
    wire signed [15:0] debug_adpcma_left;
    wire signed [15:0] debug_adpcma_right;
    wire signed [15:0] debug_adpcmb_left;
    wire signed [15:0] debug_adpcmb_right;

    wire internal_sample = dut.internal_sample;
    wire b_chon = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.chon;
    wire b_restart = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.restart;
    wire b_adv = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.adv;
    wire b_nibble = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.nibble_sel;
    wire clk_en_55 = dut.u_jt10.u_core.clk_en_55;
    wire [1:0] b_pan = dut.u_jt10.u_core.alr_b;
    wire b_logical = dut.u_jt10.u_core.gen_adpcm.u_adpcm_b.decoder_cen && clk_en_55 && b_adv && b_chon &&
                     !b_restart && !debug_adpcmb_eos;

    function automatic [63:0] hash_byte(input [63:0] h, input [7:0] v);
        hash_byte = (h ^ v) * 64'h00000100000001b3;
    endfunction
    function automatic [63:0] hash_u16(input [63:0] h, input [15:0] v);
        hash_u16 = hash_byte(hash_byte(h,v[7:0]),v[15:8]);
    endfunction
    function automatic [63:0] hash_stereo(
        input [63:0] h, input [15:0] l, input [15:0] r);
        hash_stereo = hash_u16(hash_u16(h,l),r);
    endfunction
    task automatic fail(input [8*72-1:0] message);
        begin
            failures = failures + 1;
            $display("HW0_DIAG_FAIL run=%0d tick=%0d state=%0d phase=%0d diag=%0d/%0d code=%0d reason=%0s",
                run_id,debug_sample_tick_count,debug_segment_state,
                debug_phase,debug_diag_phase,debug_diag_attempt,
                debug_last_error_code,message);
        end
    endtask

    always #5 clk = ~clk;

    always @(posedge clk) begin : monitor
        logic public_rise;
        logic internal_rise;
        integer p;
        integer d;
        system_cycle = system_cycle + 1;
        #1;
        public_rise = audio_sample && !previous_public;
        internal_rise = internal_sample && !previous_internal;

        if (!reset && debug_core_ready) begin
            if (debug_sample_tick_count != 0 &&
                (^ {audio_sample,debug_phase,
                debug_segment_state,debug_diag_seen,debug_diag_fail,
                debug_diag_summary,debug_last_error_code} === 1'bx)) begin
                x_count = x_count + 1;
                x_control = x_control + 1;
                if (x_control == 1)
                    $display("HW0_DIAG_X category=control tick=%0d audio_sample=%b phase=%b state=%b seen=%b fail=%b summary=%b code=%b",
                        debug_sample_tick_count,audio_sample,debug_phase,
                        debug_segment_state,debug_diag_seen,debug_diag_fail,
                        debug_diag_summary,debug_last_error_code);
            end
            if (debug_diag_attempt_active &&
                ((debug_diag_phase <= 1 &&
                  (^debug_adpcma_request === 1'bx)) ||
                 (debug_diag_phase >= 2 &&
                  (^debug_adpcmb_request === 1'bx)))) begin
                x_count = x_count + 1;
                x_control = x_control + 1;
                if (x_control == 1)
                    $display("HW0_DIAG_X category=request tick=%0d phase=%0d state=%0d",
                        debug_sample_tick_count,debug_phase,debug_segment_state);
            end
            if (debug_adpcma_request &&
                (^ {debug_adpcma_bank,debug_adpcma_addr,
                    dut.adpcma_data} === 1'bx)) begin
                x_count = x_count + 1;
                x_adpcma_rom = x_adpcma_rom + 1;
                if (x_adpcma_rom == 1)
                    $display("HW0_DIAG_X category=adpcma_rom tick=%0d phase=%0d state=%0d",
                        debug_sample_tick_count,debug_phase,debug_segment_state);
            end
            if (debug_adpcmb_request &&
                (^ {debug_adpcmb_addr,dut.adpcmb_data} === 1'bx)) begin
                x_count = x_count + 1;
                x_adpcmb_rom = x_adpcmb_rom + 1;
                if (x_adpcmb_rom == 1)
                    $display("HW0_DIAG_X category=adpcmb_rom tick=%0d phase=%0d state=%0d",
                        debug_sample_tick_count,debug_phase,debug_segment_state);
            end
            if (internal_rise && !audio_sample) drops = drops + 1;
            if (public_rise) begin
                if ((^ {audio_l,audio_r,
                    debug_jt10_final_left,debug_jt10_final_right,
                    debug_premute_left,debug_premute_right} === 1'bx)) begin
                    x_count = x_count + 1;
                    x_audio = x_audio + 1;
                    if (x_audio == 1)
                        $display("HW0_DIAG_X category=audio tick=%0d phase=%0d state=%0d",
                            debug_sample_tick_count,debug_phase,debug_segment_state);
                end
                if (debug_diag_attempt_active && debug_diag_phase <= 1 &&
                    (^ {debug_adpcma_left,debug_adpcma_right} === 1'bx)) begin
                    x_count = x_count + 1;
                    x_adpcma_lane = x_adpcma_lane + 1;
                    if (x_adpcma_lane == 1)
                        $display("HW0_DIAG_X category=adpcma_lane tick=%0d phase=%0d state=%0d",
                            debug_sample_tick_count,debug_phase,debug_segment_state);
                end
                if (debug_diag_attempt_active && debug_diag_phase >= 2 &&
                    (^ {debug_adpcmb_left,debug_adpcmb_right} === 1'bx)) begin
                    x_count = x_count + 1;
                    x_adpcmb_lane = x_adpcmb_lane + 1;
                    if (x_adpcmb_lane == 1)
                        $display("HW0_DIAG_X category=adpcmb_lane tick=%0d phase=%0d state=%0d",
                            debug_sample_tick_count,debug_phase,debug_segment_state);
                end
                if (!internal_rise) duplicates = duplicates + 1;
                if (!debug_sample_tick) tick_missed = tick_missed + 1;
                if (last_public_cycle >= 0 &&
                    system_cycle-last_public_cycle != 144)
                    cadence_errors = cadence_errors + 1;
                last_public_cycle = system_cycle;
                if (debug_external_mute && (audio_l != 0 || audio_r != 0))
                    fail("MUTED_OUTPUT_NONZERO");
                if (debug_diag_attempt_active &&
                    ({debug_jt10_final_left,debug_jt10_final_right} !==
                     {debug_premute_left,debug_premute_right}))
                    fail("FINAL_PREMUTE_MISMATCH");
                if (debug_diag_attempt_active && !debug_external_mute &&
                    ({debug_premute_left,debug_premute_right} !==
                     {audio_l,audio_r}))
                    fail("PREMUTE_OUTPUT_MISMATCH");

                li = debug_restart_count < 2 ? debug_restart_count : 1;
                p = debug_measurement_phase;
                if (debug_measurement_active && p >= 1 && p <= 5) begin
                    if (p <= 2 && reference_count[li][p] < 4096) begin
                        reference_hash[li][p] = hash_stereo(
                            reference_hash[li][p],audio_l,audio_r);
                        reference_count[li][p] = reference_count[li][p]+1;
                    end else if (p >= 3) begin
                        d = p-3;
                        ai = debug_diag_attempt;
                        if (pcm_count[li][d][ai] <
                            (p == 4 ? 8192 : p == 5 ? 4097 : 4096) &&
                            (p != 5 || b_chon)) begin
                            pcm_hash[li][d][ai] = hash_stereo(
                                pcm_hash[li][d][ai],audio_l,audio_r);
                            pcm_count[li][d][ai] = pcm_count[li][d][ai]+1;
                        end
                    end
                end

                if (debug_phase == 6 && b_chon) begin
                    if (b_pan == 2'b10) begin
                        if (audio_r != 0) pan_leak = pan_leak + 1;
                        if (audio_l != 0) pan_expected = pan_expected + 1;
                    end else if (b_pan == 2'b01) begin
                        if (audio_l != 0) pan_leak = pan_leak + 1;
                        if (audio_r != 0) pan_expected = pan_expected + 1;
                    end
                end
                if (natural_index >= 0 && natural_index < 12 && b_chon &&
                    natural_public[natural_index] < 1024) begin
                    natural_hash[natural_index] = hash_stereo(
                        natural_hash[natural_index],audio_l,audio_r);
                    natural_public[natural_index] =
                        natural_public[natural_index]+1;
                    if (prefix_count[natural_index] < 16) begin
                        if ((natural_index & 1) == 0) begin
                            prefix_l[natural_index>>1]
                                    [prefix_count[natural_index]] = audio_l;
                            prefix_r[natural_index>>1]
                                    [prefix_count[natural_index]] = audio_r;
                        end else if (audio_l !==
                            prefix_l[natural_index>>1]
                                    [prefix_count[natural_index]] ||
                            audio_r !== prefix_r[natural_index>>1]
                                    [prefix_count[natural_index]])
                            natural_stale = natural_stale + 1;
                        prefix_count[natural_index] =
                            prefix_count[natural_index]+1;
                    end
                end
            end
            if (debug_sample_tick && !public_rise)
                tick_duplicates = tick_duplicates + 1;
            if (audio_sample) public_width = public_width + 1;
            else if (previous_public) begin
                if (public_width != 6) width_errors = width_errors + 1;
                public_width = 0;
            end
        end

        if (!reset && debug_phase != previous_phase) begin
            if (debug_phase >= 1 && debug_phase <= 8) begin
                phase_visits[debug_phase] = phase_visits[debug_phase]+1;
                $display("HW0_DIAG_PHASE run=%0d loop=%0d phase=%0d tick=%0d state=%0d",
                    run_id,debug_restart_count,debug_phase,
                    debug_sample_tick_count,debug_segment_state);
            end
            previous_phase = debug_phase;
        end
        if (!reset && previous_diag_active && !debug_diag_attempt_active) begin
            attempt_closures[debug_diag_phase] =
                attempt_closures[debug_diag_phase]+1;
            $display("HW0_DIAG_ATTEMPT run=%0d loop=%0d diag=%0d attempt=%0d complete=%0d seen=%02h fail=%02h req=%0d distinct=%0d addrchg=%0d first=%06h last=%06h",
                run_id,debug_restart_count,debug_diag_phase,
                debug_diag_attempt,debug_diag_completed_attempts,
                debug_diag_seen,debug_diag_fail,
                debug_diag_request_count,debug_diag_distinct_addresses,
                debug_diag_address_changes,
                debug_diag_first_addr,debug_diag_last_addr);
            if (debug_diag_seen != 7'h7f || debug_diag_fail != 0)
                fail("PCM_STATUS_NOT_ALL_PASS");
            if (debug_diag_request_count == 0 ||
                debug_diag_distinct_addresses < 2 ||
                debug_diag_address_changes == 0 ||
                debug_diag_first_addr == debug_diag_last_addr)
                fail("PCM_TRANSACTION_EVIDENCE");
            if (debug_diag_event_counts[3:0] == 0 ||
                debug_diag_event_counts[7:4] == 0 ||
                debug_diag_event_counts[11:8] == 0 ||
                debug_diag_event_counts[15:12] == 0 ||
                debug_diag_event_counts[19:16] == 0 ||
                debug_diag_event_counts[23:20] == 0 ||
                debug_diag_event_counts[27:24] == 0)
                fail("PCM_EVENT_COUNTS");
        end
        if (!reset && debug_summary_active && !previous_summary) begin
            summary_count = summary_count + 1;
            if (debug_diag_summary_valid != 5'h1f ||
                debug_diag_summary != {35{1'b1}})
                fail("SUMMARY_MATRIX_NOT_ALL_PASS");
            if (debug_diag_completed_attempts != 3)
                fail("SUMMARY_ATTEMPT_COUNT");
            if (debug_last_error_code != 0) fail("POSITIVE_ERROR_CODE");
            $display("HW0_DIAG_SUMMARY run=%0d loop=%0d matrix=%09h valid=%02h code=%0d",
                run_id,debug_restart_count,debug_diag_summary,
                debug_diag_summary_valid,debug_last_error_code);
        end
        if (debug_phase == 7 && b_chon && !previous_b_chon) begin
            natural_index = natural_index + 1;
            if (natural_index >= 12) fail("NATURAL_START_OVERFLOW");
        end
        if (debug_phase == 7 && b_logical &&
            natural_index >= 0 && natural_index < 12)
            natural_logical[natural_index] =
                natural_logical[natural_index]+1;

        previous_public = audio_sample;
        previous_internal = internal_sample;
        previous_diag_active = debug_diag_attempt_active;
        previous_summary = debug_summary_active;
        previous_b_chon = b_chon;
    end

    ym2610_hw0_top #(
        .FAST_SIM(`SEMANTIC_FAST_SIM), .BOOT_SAMPLES(SIM_BOOT),
        .COLOR_PREROLL_SAMPLES(SIM_PREROLL),
        .SOUND_DWELL_SAMPLES(SIM_DWELL),
        .INTER_SILENCE_SAMPLES(SIM_GAP),
        .PAN_DWELL_SAMPLES(SIM_DWELL),
        .PAN_INTER_SAMPLES(SIM_GAP),
        .NATURAL_SILENCE_SAMPLES(SIM_NATURAL),
        .FINAL_SILENCE_SAMPLES(SIM_RESULT),
        .REFERENCE_DWELL_SAMPLES(SIM_DWELL),
        .REFERENCE_GAP_SAMPLES(SIM_GAP),
        .PCM_ATTEMPT_SAMPLES(SIM_DWELL),
        .A0_ATTEMPT_SAMPLES(4097),
        .A6_ATTEMPT_SAMPLES(8193),
        .B_ATTEMPT_SAMPLES(4098),
        .PCM_ATTEMPT_GAP_SAMPLES(SIM_GAP),
        .PCM_RESULT_SAMPLES(SIM_RESULT),
        .SUMMARY_SAMPLES(SIM_SUMMARY)
    ) dut (
        .clk_sys(clk),.reset(reset),.video_reset(video_reset),
        .audio_l(audio_l),.audio_r(audio_r),.audio_sample(audio_sample),
        .video_ce(video_ce),.video_hs(video_hs),.video_vs(video_vs),
        .video_de(video_de),.video_r(video_r),.video_g(video_g),
        .video_b(video_b),.debug_phase(debug_phase),
        .debug_segment_state(debug_segment_state),
        .debug_startup_state(debug_startup_state),
        .debug_external_mute(debug_external_mute),
        .debug_sample_tick(debug_sample_tick),
        .debug_sample_tick_count(debug_sample_tick_count),
        .debug_sample_cadence_error(debug_sample_cadence_error),
        .debug_sample_width_error(debug_sample_width_error),
        .debug_accepted_writes(debug_accepted_writes),
        .debug_busy_timeout(debug_busy_timeout),
        .debug_write_while_busy(debug_write_while_busy),
        .debug_zero_timeout(debug_zero_timeout),
        .debug_phase_error(debug_phase_error),
        .debug_restart_count(debug_restart_count),
        .debug_measurement_active(debug_measurement_active),
        .debug_measurement_phase(debug_measurement_phase),
        .debug_diag_phase(debug_diag_phase),
        .debug_diag_attempt(debug_diag_attempt),
        .debug_diag_completed_attempts(debug_diag_completed_attempts),
        .debug_diag_attempt_active(debug_diag_attempt_active),
        .debug_diag_seen(debug_diag_seen),.debug_diag_fail(debug_diag_fail),
        .debug_diag_summary(debug_diag_summary),
        .debug_diag_summary_valid(debug_diag_summary_valid),
        .debug_diag_event_counts(debug_diag_event_counts),
        .debug_diag_first_ticks(debug_diag_first_ticks),
        .debug_diag_request_count(debug_diag_request_count),
        .debug_diag_first_addr(debug_diag_first_addr),
        .debug_diag_last_addr(debug_diag_last_addr),
        .debug_diag_address_changes(debug_diag_address_changes),
        .debug_diag_distinct_addresses(debug_diag_distinct_addresses),
        .debug_last_error_code(debug_last_error_code),
        .debug_summary_active(debug_summary_active),
        .debug_adpcma_request(debug_adpcma_request),
        .debug_adpcma_addr(debug_adpcma_addr),
        .debug_adpcma_bank(debug_adpcma_bank),
        .debug_adpcmb_request(debug_adpcmb_request),
        .debug_adpcmb_addr(debug_adpcmb_addr),
        .debug_adpcmb_eos(debug_adpcmb_eos),
        .debug_adpcmb_active(debug_adpcmb_active),
        .debug_core_ready(debug_core_ready),
        .debug_reset_cen_count(debug_reset_cen_count),
        .debug_jt10_final_left(debug_jt10_final_left),
        .debug_jt10_final_right(debug_jt10_final_right),
        .debug_premute_left(debug_premute_left),
        .debug_premute_right(debug_premute_right),
        .debug_adpcma_left(debug_adpcma_left),
        .debug_adpcma_right(debug_adpcma_right),
        .debug_adpcmb_left(debug_adpcmb_left),
        .debug_adpcmb_right(debug_adpcmb_right),
        .debug_halted(debug_halted)
    );

    initial begin
        integer l, p, a, i;
        if (!$value$plusargs("RUN_ID=%d",run_id)) run_id=1;
        if (!$value$plusargs("LOOPS=%d",requested_loops)) requested_loops=2;
        if (requested_loops < 1 || requested_loops > 2)
            $fatal(1,"LOOPS must be 1 or 2");
        for (l=0;l<2;l=l+1) begin
            for (p=1;p<=2;p=p+1) begin
                reference_hash[l][p]=FNV_OFFSET;
                reference_count[l][p]=0;
            end
            for (p=0;p<3;p=p+1)
                for (a=0;a<6;a=a+1) begin
                    pcm_hash[l][p][a]=FNV_OFFSET;
                    pcm_count[l][p][a]=0;
                end
        end
        for(i=0;i<12;i=i+1) begin
            natural_hash[i]=FNV_OFFSET; natural_logical[i]=0;
            natural_public[i]=0; prefix_count[i]=0;
        end
        for(i=1;i<=8;i=i+1) phase_visits[i]=0;
        for(i=0;i<5;i=i+1) attempt_closures[i]=0;
        repeat(4) @(posedge clk); video_reset=0;
        repeat(64) @(posedge clk); @(negedge clk); reset=0;
        fork
            wait(debug_restart_count>=requested_loops);
            begin repeat(100000000) @(posedge clk); fail("FULL_LOOP_TIMEOUT"); end
        join_any
        disable fork;
        repeat(32) @(posedge clk);

        if(debug_halted || debug_busy_timeout || debug_write_while_busy ||
           debug_phase_error) fail("FATAL_SEQUENCER_ERROR");
        if(debug_zero_timeout) fail("STOP_TIMEOUT");
        if(debug_reset_cen_count!=6) fail("RESET_CEN_COUNT");
        if(summary_count!=requested_loops) fail("SUMMARY_COUNT");
        for(i=1;i<=8;i=i+1)
            if(phase_visits[i]!=requested_loops) fail("PHASE_VISIT_COUNT");
        if(attempt_closures[0]!=6*requested_loops ||
           attempt_closures[1]!=6*requested_loops ||
           attempt_closures[2]!=6*requested_loops ||
           attempt_closures[3]!=6*requested_loops ||
           attempt_closures[4]!=3*requested_loops) fail("ATTEMPT_COUNTS");
        for(l=0;l<requested_loops;l=l+1) begin
            if(reference_count[l][1]!=4096 ||
               reference_hash[l][1]!=64'h8aadd7a6819038e5) fail("FM_HASH");
            if(reference_count[l][2]!=4096 ||
               reference_hash[l][2]!=64'h54730095b12b6325) fail("SSG_HASH");
            for(a=0;a<6;a=a+1) begin
                if(pcm_count[l][0][a]!=4096 ||
                   pcm_hash[l][0][a]!=64'hadf8cc2f2f81c1b9)
                    fail("A0_ATTEMPT_HASH");
                if(pcm_count[l][1][a]!=8192 ||
                   pcm_hash[l][1][a]!=64'h32cb891931682fe9)
                    fail("A6_ATTEMPT_HASH");
                if(pcm_count[l][2][a]!=4097 ||
                   pcm_hash[l][2][a]!=64'h1207d84363d4ed39)
                    fail("B_ATTEMPT_HASH");
            end
        end
        for(i=0;i<6*requested_loops;i=i+1) begin
            if(natural_logical[i]!=512 || natural_public[i]!=1024 ||
               natural_hash[i]!=64'he142f7da424b1531)
                fail("NATURAL_RESTART_HASH");
        end
        if(natural_stale!=0) fail("NATURAL_STALE_PREFIX");
        if(pan_leak!=0 || pan_expected==0) fail("PAN_ISOLATION");
        if(cadence_errors||width_errors||drops||duplicates||tick_missed||
           tick_duplicates||debug_sample_cadence_error||
           debug_sample_width_error) fail("SAMPLE_CONTRACT");
        if(x_count) fail("RELEVANT_XZ");

        $display("HW0_DIAG_HASH run=%0d fm=%016h ssg=%016h a0=%016h a6=%016h b=%016h restart=%016h attempts=6/6/6 natural=3 loops=%0d",
            run_id,reference_hash[0][1],reference_hash[0][2],
            pcm_hash[0][0][0],pcm_hash[0][1][0],pcm_hash[0][2][0],
            natural_hash[0],debug_restart_count);
        $display("HW0_DIAG_CONTRACT run=%0d summaries=%0d attempts=%0d/%0d/%0d/%0d/%0d busy=%0d write_busy=%0d zero_timeout=%0d fatal=%0d code=%0d x=%0d xcat=%0d/%0d/%0d/%0d/%0d/%0d drop=%0d duplicate=%0d pan_leak=%0d",
            run_id,summary_count,attempt_closures[0],attempt_closures[1],
            attempt_closures[2],attempt_closures[3],attempt_closures[4],
            debug_busy_timeout,debug_write_while_busy,debug_zero_timeout,
            debug_halted,debug_last_error_code,x_count,x_control,x_audio,
            x_adpcma_lane,x_adpcmb_lane,x_adpcma_rom,x_adpcmb_rom,
            drops,duplicates,pan_leak);
        if(failures) $fatal(1,"HW0 PCM diagnostic failed (%0d)",failures);
        $display("HW0_DIAG_PASS run=%0d",run_id);
        $finish;
    end
endmodule

module tb_ym2610_hw0_reset_injection;
    localparam integer SIM_BOOT = 256;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic video_reset = 1'b1;
    integer target_state = 7;
    integer failures = 0;
    integer boot_entry_tick;
    integer boot_exit_tick;
    integer flat_before;
    integer flat_after;
    integer flat_delta;

    wire signed [15:0] audio_l, audio_r;
    wire audio_sample;
    wire video_ce, video_hs, video_vs, video_de;
    wire [7:0] video_r, video_g, video_b;
    wire [3:0] debug_phase;
    wire [6:0] debug_segment_state;
    wire [2:0] debug_startup_state;
    wire debug_external_mute, debug_sample_tick;
    wire [31:0] debug_sample_tick_count;
    wire [31:0] debug_accepted_writes;
    wire debug_busy_timeout, debug_write_while_busy;
    wire debug_zero_timeout, debug_phase_error, debug_halted;
    wire debug_core_ready;
    wire debug_adpcma_request, debug_adpcmb_request;
    wire [6:0] debug_diag_seen,debug_diag_fail;
    wire [34:0] debug_diag_summary;
    wire [4:0] debug_diag_summary_valid;
    wire debug_diag_attempt_active;
    wire [2:0] debug_diag_completed_attempts;

    task automatic fail(input [8*64-1:0] message);
        begin
            failures=failures+1;
            $display("HW0_RESET_FAIL target=%0d tick=%0d state=%0d reason=%0s",
                     target_state,debug_sample_tick_count,
                     debug_segment_state,message);
        end
    endtask

    always #5 clk = ~clk;

    ym2610_hw0_top #(
        .FAST_SIM(`SEMANTIC_FAST_SIM), .BOOT_SAMPLES(SIM_BOOT),
        .COLOR_PREROLL_SAMPLES(128), .SOUND_DWELL_SAMPLES(8193),
        .INTER_SILENCE_SAMPLES(128), .PAN_DWELL_SAMPLES(2048),
        .PAN_INTER_SAMPLES(128), .NATURAL_SILENCE_SAMPLES(128),
        .FINAL_SILENCE_SAMPLES(256),
        .REFERENCE_DWELL_SAMPLES(8193), .REFERENCE_GAP_SAMPLES(128),
        .PCM_ATTEMPT_SAMPLES(8193), .PCM_ATTEMPT_GAP_SAMPLES(128),
        .PCM_RESULT_SAMPLES(128), .SUMMARY_SAMPLES(256)
    ) dut (
        .clk_sys(clk),.reset(reset),.video_reset(video_reset),
        .audio_l(audio_l),.audio_r(audio_r),.audio_sample(audio_sample),
        .video_ce(video_ce),.video_hs(video_hs),.video_vs(video_vs),
        .video_de(video_de),.video_r(video_r),.video_g(video_g),
        .video_b(video_b),.debug_phase(debug_phase),
        .debug_segment_state(debug_segment_state),
        .debug_startup_state(debug_startup_state),
        .debug_external_mute(debug_external_mute),
        .debug_sample_tick(debug_sample_tick),
        .debug_sample_tick_count(debug_sample_tick_count),
        .debug_accepted_writes(debug_accepted_writes),
        .debug_busy_timeout(debug_busy_timeout),
        .debug_write_while_busy(debug_write_while_busy),
        .debug_zero_timeout(debug_zero_timeout),
        .debug_phase_error(debug_phase_error),
        .debug_core_ready(debug_core_ready),
        .debug_adpcma_request(debug_adpcma_request),
        .debug_adpcmb_request(debug_adpcmb_request),
        .debug_diag_seen(debug_diag_seen),
        .debug_diag_fail(debug_diag_fail),
        .debug_diag_summary(debug_diag_summary),
        .debug_diag_summary_valid(debug_diag_summary_valid),
        .debug_diag_completed_attempts(debug_diag_completed_attempts),
        .debug_diag_attempt_active(debug_diag_attempt_active),
        .debug_halted(debug_halted)
    );

    initial begin
        if (!$value$plusargs("TARGET_STATE=%d",target_state))
            target_state=7;
        repeat(4) @(posedge clk);
        video_reset=1'b0;
        repeat(64) @(posedge clk);
        @(negedge clk); reset=1'b0;
        fork
            wait(debug_segment_state==target_state &&
                 !debug_external_mute);
            begin repeat(26000000) @(posedge clk); fail("TARGET_TIMEOUT"); end
        join_any
        disable fork;
        repeat(4) @(posedge clk);
        if (debug_halted) fail("PRE_RESET_HALTED");

        @(negedge clk);
        flat_before=dut.u_video.v_count*638+dut.u_video.h_count;
        reset=1'b1;
        #1;
        if(audio_l!==0 || audio_r!==0 || !debug_external_mute)
            fail("RESET_NOT_IMMEDIATE_ZERO");
        repeat(20) @(posedge clk);
        #1;
        flat_after=dut.u_video.v_count*638+dut.u_video.h_count;
        flat_delta=(flat_after-flat_before+167156)%167156;
        if(flat_delta!=10) fail("VIDEO_TIMING_RESET");
        if(debug_phase!=0 || debug_segment_state!=0 ||
           debug_accepted_writes!=0 || debug_diag_seen!=0 ||
           debug_diag_fail!=0 || debug_diag_summary!=0 ||
           debug_diag_summary_valid!=0 || debug_diag_attempt_active ||
           debug_diag_completed_attempts!=0)
            fail("RESET_STATE_NOT_CLEAR");
        if(audio_l!==0 || audio_r!==0 || audio_sample!==0)
            fail("RESET_AUDIO_NONZERO");

        @(negedge clk); reset=1'b0;
        wait(debug_segment_state==7'd1);
        boot_entry_tick=debug_sample_tick_count;
        while(debug_segment_state==7'd1) begin
            @(posedge clk); #1;
            if(debug_accepted_writes!=0 || debug_phase!=0 ||
               !debug_external_mute || audio_l!=0 || audio_r!=0 ||
               debug_adpcmb_request===1'b1)
                fail("RESTART_BOOT_CONTRACT");
        end
        boot_exit_tick=debug_sample_tick_count;
        if(boot_exit_tick-boot_entry_tick!=SIM_BOOT)
            fail("RESTART_BOOT_DURATION");
        wait(debug_phase==1);
        if(debug_accepted_writes!=18 || !debug_external_mute ||
           audio_l!=0 || audio_r!=0 ||
           debug_adpcma_request!==1'b0 ||
           debug_adpcmb_request!==1'b0)
            fail("RESTART_NOT_FM_HEAD");
        if(debug_halted || debug_busy_timeout || debug_write_while_busy ||
           debug_zero_timeout || debug_phase_error)
            fail("RESTART_ERROR");
        if(failures!=0) $fatal(1,"reset injection failed (%0d)",failures);
        $display("HW0_RESET target=%0d immediate_zero=PASS video_continuity=PASS boot=%0d writes=0 restart_phase=FM result=PASS",
                 target_state,boot_exit_tick-boot_entry_tick);
        $finish;
    end
endmodule

// Exact-count pacing audit.  It drives one logical sample tick per clock and
// stubs only the public BUSY/EOS contracts, so multi-second hardware counts
// can be checked without simulating hundreds of millions of JT10 clocks.
module tb_ym2610_hw0_pacing;
    localparam integer BOOT = 159801;
    localparam integer PREROLL = 53267;
    localparam integer REFERENCE_DWELL = 159801;
    localparam integer REFERENCE_GAP = 53267;
    localparam integer PCM_ATTEMPT = 53267;
    localparam integer PCM_GAP = 26634;
    localparam integer PCM_RESULT = 159801;
    localparam integer NATURAL_SILENCE = 79901;
    localparam integer SUMMARY = 532670;

    logic clk = 1'b0;
    logic reset = 1'b1;
    // This duration-only stub advances chip/sample counters at the same
    // artificial rate.  Offset them by seven so the real-core SSG congruence
    // (chip 428, sample mod 128 = 53) remains reachable in the stub model.
    logic [8:0] chip_cycle = 9'd7;
    logic [7:0] address_latch [0:1];
    logic [2:0] busy_left = 3'd0;
    logic adpcmb_active = 1'b0;
    logic adpcmb_eos = 1'b0;
    logic short_mode = 1'b0;
    integer short_ticks = 0;
    integer failures = 0;
    integer phase_events = 0;
    integer start_events = 0;
    integer attempt_events = 0;
    integer summary_events = 0;
    logic [6:0] last_state = 7'h7f;
    logic [3:0] last_phase = 4'hf;
    logic last_mute = 1'b1;
    logic [31:0] state_enter_tick = 0;
    logic [31:0] color_tick = 0;

    wire [1:0] bus_addr;
    wire [7:0] bus_din;
    wire bus_cs_n, bus_wr_n;
    wire [7:0] bus_dout = busy_left != 0 ? 8'h80 : 8'h00;
    wire [3:0] display_phase;
    wire [6:0] segment_state;
    wire [2:0] startup_state;
    wire audio_mute;
    wire [31:0] sample_tick_count;
    wire [7:0] microcode_index;
    wire [31:0] accepted_write_count;
    wire busy_timeout, write_while_busy, zero_timeout, phase_error;
    wire [15:0] restart_count;
    wire measurement_active;
    wire [3:0] measurement_phase;
    wire [2:0] diag_phase_index, diag_attempt_index;
    wire diag_phase_begin, diag_attempt_begin, diag_attempt_end;
    wire diag_stop_pass, diag_pan_right, summary_active;
    wire [3:0] fatal_error_code;
    wire halted;

    task automatic fail(input [8*64-1:0] message);
        begin
            failures = failures + 1;
            $display("HW0_PACING_FAIL tick=%0d state=%0d count=%0d halt=%0d busy=%0d write=%0d zero=%0d phase=%0d reason=%0s",
                     sample_tick_count, segment_state, dut.sample_count,
                     halted,busy_timeout,write_while_busy,zero_timeout,
                     phase_error,message);
        end
    endtask

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (reset) begin
            chip_cycle <= 9'd7;
            busy_left <= 0;
            short_ticks <= 0;
        end else begin
            chip_cycle <= chip_cycle == 9'd431 ? 9'd0 : chip_cycle + 9'd1;
            if (busy_left != 0) busy_left <= busy_left - 3'd1;
            if (adpcmb_active && short_mode) begin
                if (short_ticks + 1 >= 512) begin
                    short_ticks <= 0;
                    adpcmb_active <= 1'b0;
                    adpcmb_eos <= 1'b1;
                end else short_ticks <= short_ticks + 1;
            end
        end
        #1;
        if (!reset && segment_state != last_state) begin
            case (last_state)
                7'd1,7'd73:
                    if (sample_tick_count-state_enter_tick != BOOT) fail("BOOT_DURATION");
                7'd3,7'd11,7'd19,7'd27,7'd35,7'd43,7'd57:
                    if (sample_tick_count-state_enter_tick != PREROLL) fail("PREROLL_DURATION");
                7'd10,7'd18:
                    if (sample_tick_count-state_enter_tick != REFERENCE_GAP) fail("REFERENCE_GAP");
                7'd25,7'd33,7'd41,7'd49,7'd69:
                    if (sample_tick_count-state_enter_tick != PCM_GAP) fail("PCM_GAP");
                7'd62:
                    if (sample_tick_count-state_enter_tick != NATURAL_SILENCE) fail("NATURAL_SILENCE_DURATION");
                7'd26,7'd34,7'd42,7'd56,7'd70:
                    if (sample_tick_count-state_enter_tick != PCM_RESULT) fail("RESULT_DURATION");
                7'd71:
                    if (sample_tick_count-state_enter_tick != SUMMARY) fail("SUMMARY_DURATION");
                7'd7,7'd15:
                    if (sample_tick_count-dut.sound_start_tick != REFERENCE_DWELL) fail("REFERENCE_DWELL");
                7'd22,7'd30,7'd38,7'd46,7'd53:
                    if (sample_tick_count-dut.sound_start_tick != PCM_ATTEMPT) fail("PCM_ATTEMPT");
                default: ;
            endcase
            state_enter_tick = sample_tick_count;
            last_state = segment_state;
        end
        if (!reset && display_phase != last_phase) begin
            if (display_phase != 0) begin
                phase_events = phase_events + 1;
                if (display_phase == 8) summary_events = summary_events + 1;
                color_tick = sample_tick_count;
                $display("HW0_PACING_COLOR loop=%0d phase=%0d tick=%0d state=%0d",
                         restart_count, display_phase, sample_tick_count,
                         segment_state);
            end
            last_phase = display_phase;
        end
        if (!reset && diag_attempt_end) attempt_events = attempt_events + 1;
        if (!reset && !audio_mute && last_mute) begin
            start_events = start_events + 1;
            $display("HW0_PACING_START loop=%0d phase=%0d color_tick=%0d start_tick=%0d delta=%0d",
                     restart_count,display_phase,color_tick,
                     sample_tick_count,sample_tick_count-color_tick);
        end
        last_mute = audio_mute;
    end

    // Capture the public address/data write and provide a deterministic BUSY
    // pulse.  Register contents and ordering remain owned by the DUT.
    always @(negedge clk) begin
        if (!reset && !bus_cs_n && !bus_wr_n) begin
            if (!bus_addr[0]) address_latch[bus_addr[1]] = bus_din;
            else begin
                busy_left = 3'd3;
                if (!bus_addr[1] && address_latch[0] == 8'h14)
                    short_mode = bus_din == 8'h20;
                if (!bus_addr[1] && address_latch[0] == 8'h10) begin
                    if (bus_din == 8'h80) begin
                        adpcmb_active = 1'b1;
                        adpcmb_eos = 1'b0;
                        short_ticks = 0;
                    end else if (bus_din == 8'h01) begin
                        adpcmb_active = 1'b0;
                        adpcmb_eos = 1'b0;
                        short_ticks = 0;
                    end
                end
            end
        end
    end

    ym2610_hw0_sequencer #(
        .BOOT_SAMPLES(BOOT), .COLOR_PREROLL_SAMPLES(PREROLL),
        .SOUND_DWELL_SAMPLES(REFERENCE_DWELL),
        .INTER_SILENCE_SAMPLES(REFERENCE_GAP),
        .PAN_DWELL_SAMPLES(PCM_ATTEMPT),
        .PAN_INTER_SAMPLES(PCM_GAP),
        .NATURAL_SILENCE_SAMPLES(NATURAL_SILENCE),
        .FINAL_SILENCE_SAMPLES(PCM_RESULT),
        .REFERENCE_DWELL_SAMPLES(REFERENCE_DWELL),
        .REFERENCE_GAP_SAMPLES(REFERENCE_GAP),
        .PCM_ATTEMPT_SAMPLES(PCM_ATTEMPT),
        .PCM_ATTEMPT_GAP_SAMPLES(PCM_GAP),
        .PCM_RESULT_SAMPLES(PCM_RESULT),
        .SUMMARY_SAMPLES(SUMMARY)
    ) dut (
        .clk(clk), .reset(reset), .core_ready(1'b1), .audio_zero(1'b1),
        .sample_tick(!reset), .sample_contract_error(1'b0),
        .chip_cycle_mod432(chip_cycle), .bus_dout(bus_dout),
        .adpcmb_eos(adpcmb_eos), .adpcmb_active(adpcmb_active),
        .adpcma_request(1'b0),
        .adpcmb_request(adpcmb_active),
        .diag_rom_range_error(1'b0),
        .bus_addr(bus_addr), .bus_din(bus_din),
        .bus_cs_n(bus_cs_n), .bus_wr_n(bus_wr_n),
        .display_phase(display_phase), .segment_state(segment_state),
        .startup_state(startup_state), .audio_mute(audio_mute),
        .sample_tick_count(sample_tick_count),
        .microcode_index(microcode_index),
        .accepted_write_count(accepted_write_count),
        .busy_timeout(busy_timeout),
        .write_while_busy(write_while_busy), .zero_timeout(zero_timeout),
        .phase_error(phase_error), .sequence_restart_count(restart_count),
        .measurement_active(measurement_active),
        .measurement_phase(measurement_phase),
        .diag_phase_index(diag_phase_index),
        .diag_attempt_index(diag_attempt_index),
        .diag_phase_begin(diag_phase_begin),
        .diag_attempt_begin(diag_attempt_begin),
        .diag_attempt_end(diag_attempt_end),
        .diag_stop_pass(diag_stop_pass), .diag_pan_right(diag_pan_right),
        .summary_active(summary_active), .fatal_error_code(fatal_error_code),
        .halted(halted)
    );

    initial begin
        repeat (8) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        fork
            begin wait (restart_count >= 2); wait(segment_state==7'd73); end
            begin repeat (20000000) @(posedge clk); fail("TIMEOUT"); end
        join_any
        disable fork;
        repeat (8) @(posedge clk);
        if (halted || busy_timeout || write_while_busy || zero_timeout ||
            phase_error) fail("SEQUENCER_ERROR");
        if (phase_events != 16 || start_events != 64 ||
            attempt_events != 54 || summary_events != 2)
            fail("EVENT_COUNT");
        if (accepted_write_count != 478)
            fail("WRITE_COUNT");
        if (failures != 0) $fatal(1,"HW0 pacing failed (%0d)",failures);
        $display("HW0_PACING boot=%0d preroll=%0d reference=%0d/%0d pcm=%0d/%0d result=%0d natural=%0d summary=%0d phases=%0d starts=%0d attempts=%0d summaries=%0d writes=%0d loops=%0d result=PASS",
                 BOOT,PREROLL,REFERENCE_DWELL,REFERENCE_GAP,
                 PCM_ATTEMPT,PCM_GAP,PCM_RESULT,NATURAL_SILENCE,SUMMARY,
                 phase_events,start_events,attempt_events,summary_events,
                 accepted_write_count,restart_count);
        $finish;
    end
endmodule

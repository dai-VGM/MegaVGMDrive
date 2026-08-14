`timescale 1ns/1ps

module jt10_p3_clean_isolated_v3_wrapper;
    jt10_p3_clean_isolated_s4_top base();

    logic p_flush = 1'b0;
    logic [6:0] p_source;
    logic [3:0] p_expected_current;
    logic [3:0] p_expected_next;
    logic p_expected_visible;
    logic p_arm;
    logic p_consume;
    logic p_valid;
    integer p_arms;
    integer p_consumes;
    integer p_visible;
    integer p_failures;
    logic [7:0] p_first_failure;
    gatee_phase_token_monitor #(
        .ENABLE(1), .FATAL_ON_ERROR(0)
    ) u_phase_contract (
        .clk(base.clk), .reset(base.reset),
        .state(base.debug_segment_state), .phase(base.debug_phase),
        .program_active(base.dut.u_sequencer.program_active),
        .program_id(base.dut.u_sequencer.program_id), .flush(p_flush),
        .phase_event_source(p_source),
        .expected_current_phase(p_expected_current),
        .expected_next_phase(p_expected_next),
        .expected_visible_event(p_expected_visible),
        .token_arm(p_arm), .token_consume(p_consume),
        .token_valid(p_valid), .token_arms(p_arms),
        .token_consumes(p_consumes), .visible_events(p_visible),
        .failures(p_failures), .first_failure_code(p_first_failure)
    );

    logic [15:0] r_baseline;
    logic r_seen_transition;
    logic [2:0] r_owner;
    logic [15:0] r_delta;
    integer r_transition_id;
    integer r_legal_count;
    logic r_post_restart_completion;
    integer r_failures;
    logic [7:0] r_first_failure;
    wire restart_setup_window =
        base.debug_segment_state == 7'd72 && base.debug_phase == 0 &&
        base.dut.u_sequencer.program_active &&
        base.dut.u_sequencer.program_id == 0;
    gatee_restart_ownership_monitor #(
        .ENABLE(1), .FATAL_ON_ERROR(0)
    ) u_restart_contract (
        .clk(base.clk), .reset(base.reset),
        .state(base.debug_segment_state), .phase(base.debug_phase),
        .zero_wait(base.dut.u_sequencer.zero_wait_state),
        .transition_completes(base.semantic_transition_completes),
        .restart_count(base.debug_restart_count),
        .program_active(base.dut.u_sequencer.program_active),
        .program_id(base.dut.u_sequencer.program_id),
        .restart_setup_window(restart_setup_window),
        .restart_baseline(r_baseline),
        .restart_seen_in_transition(r_seen_transition),
        .restart_owner(r_owner), .restart_delta(r_delta),
        .transition_id(r_transition_id),
        .legal_restart_count(r_legal_count),
        .post_restart_completion_seen(r_post_restart_completion),
        .failures(r_failures), .first_failure_code(r_first_failure)
    );

    logic h_flush = 1'b0;
    logic h_token_valid;
    integer h_transition_id;
    logic [6:0] h_source_state;
    logic [2:0] h_source_class;
    integer h_entry_cycle;
    integer h_completion_cycle;
    logic [6:0] h_expected_state;
    logic [4:0] h_expected_program;
    logic [1:0] h_completion_reason;
    logic h_event_seen;
    integer h_bnd1;
    integer h_bnd2;
    integer h_bnd3;
    integer h_event_count;
    logic h_bnd_pass;
    integer h_failures;
    logic [7:0] h_first_failure;

    logic if_entry;
    logic if_completion;
    logic [6:0] if_source_state;
    logic [2:0] if_attempt;
    logic [2:0] if_source_class;
    logic [4:0] if_program;
    logic [6:0] if_next_state;
    logic [2:0] if_current_class;
    logic [1:0] if_reason;
    logic [31:0] if_entry_id;
    logic [31:0] if_completion_id;
    logic if_token_valid;
    integer if_failures;
    logic [7:0] if_first_failure;

    logic selector_token_valid;
    logic selector_non_target_pending;
    logic [1:0] selector_token_id;
    logic [31:0] selector_transition_id;
    logic [4:0] selector_expected_program;
    logic [6:0] selector_expected_next_state;
    logic [2:0] selector_source_class;
    logic [2:0] selector_current_class;
    logic [1:0] selector_expected_reason;
    logic selector_bnd_event;
    logic [1:0] selector_bnd_event_id;
    logic [3:0] selector_event_count;
    logic [3:0] selector_bnd1;
    logic [3:0] selector_bnd2;
    logic [3:0] selector_bnd3;
    logic [3:0] selector_non_target_count;
    logic [7:0] selector_failures;
    logic [7:0] selector_first_failure;

    logic selector_entry_event;
    logic selector_completion_event;
    logic selector_rearm;
    logic bnd_counter_enable;
    logic epoch_global_pending;
    logic epoch_qualified_pending;
    logic epoch;
    logic [3:0] inventory_index;
    logic terminal_ready;
    logic epoch_contract_pass;
    logic integration_complete;
    integer global_entries;
    integer global_completions;
    integer qualified_entries;
    integer qualified_completions;
    integer out_domain_entries;
    integer out_domain_completions;
    integer epoch_advances;
    integer owned_restart_rearms;
    integer third_epoch_events;
    integer epoch0_qualified;
    integer epoch0_targets;
    integer epoch0_non_targets;
    integer epoch1_qualified;
    integer epoch1_targets;
    integer epoch1_non_targets;
    integer epoch0_h_acceptance;
    integer epoch1_h_acceptance;
    integer epoch0_h_injection;
    integer epoch1_h_injection;
    integer epoch1_local_bnd1;
    integer epoch1_local_bnd2;
    integer epoch1_local_bnd3;
    logic epoch1_local_pass;
    integer aggregate_targets;
    integer aggregate_non_targets;
    integer aggregate_bnd1;
    integer aggregate_bnd2;
    integer aggregate_bnd3;
    integer global_id_mismatches;
    integer target_duplicate_drop;
    integer epoch_errors;
    logic [7:0] epoch_first_error;

    wire selector_reset = base.reset | selector_rearm;
    wire selector_semantic_clock = base.reset ? base.clk :
        (if_entry | if_completion | selector_rearm);
    wire external_target_valid = selector_bnd_event |
                                 selector_token_valid;
    wire [1:0] external_target_id = selector_bnd_event ?
                                    selector_bnd_event_id :
                                    selector_token_id;

    gatee_bounded_event_monitor #(
        .ENABLE(1), .FATAL_ON_ERROR(0),
        .TOKEN_TIMEOUT_CYCLES(1000000), .USE_EXTERNAL_SELECTOR(1)
    ) u_h4_v3 (
        .clk(base.clk), .reset(base.reset),
        .state(base.debug_segment_state),
        .attempt(base.dut.u_sequencer.diag_attempt_index),
        .zero_wait(base.dut.u_sequencer.zero_wait_state),
        .capture_enable(1'b1),
        .transition_completes(base.semantic_transition_completes),
        .semantic_expected_program(base.semantic_expected_program),
        .semantic_expected_state(base.semantic_expected_state),
        .semantic_setup_count(base.semantic_setup_count),
        .semantic_completion_reason(base.semantic_completion_reason),
        .semantic_zero_count(base.semantic_transition_zero_count),
        .semantic_current_zero_class(base.semantic_current_zero_class),
        .external_target_valid(external_target_valid),
        .external_target_id(external_target_id),
        .bnd_counter_enable(bnd_counter_enable),
        .program_active(base.dut.u_sequencer.program_active),
        .program_id(base.dut.u_sequencer.program_id),
        .restart_count(base.debug_restart_count),
        .rom_a_request(base.debug_adpcma_request),
        .rom_b_request(base.debug_adpcmb_request),
        .mute(base.debug_external_mute),
        .public_sample(base.audio_sample),
        .internal_left(base.dut.internal_left),
        .internal_right(base.dut.internal_right),
        .public_left(base.audio_l), .public_right(base.audio_r),
        .flush(h_flush), .transition_token_valid(h_token_valid),
        .transition_id(h_transition_id),
        .source_state_token(h_source_state),
        .source_zero_class(h_source_class),
        .entry_cycle(h_entry_cycle),
        .completion_cycle(h_completion_cycle),
        .expected_destination_state(h_expected_state),
        .expected_program(h_expected_program),
        .completion_reason(h_completion_reason),
        .event_seen(h_event_seen), .bnd1_events(h_bnd1),
        .bnd2_events(h_bnd2), .bnd3_events(h_bnd3),
        .bnd_event_count(h_event_count), .bnd_pass(h_bnd_pass),
        .failures(h_failures), .first_failure_code(h_first_failure),
        .interface_entry_event(if_entry),
        .interface_completion_event(if_completion),
        .interface_entry_source_state(if_source_state),
        .interface_entry_attempt(if_attempt),
        .interface_entry_source_class(if_source_class),
        .interface_completion_program(if_program),
        .interface_completion_next_state(if_next_state),
        .interface_completion_current_class(if_current_class),
        .interface_completion_reason(if_reason),
        .interface_entry_id(if_entry_id),
        .interface_completion_id(if_completion_id),
        .interface_token_valid(if_token_valid),
        .interface_failures(if_failures),
        .interface_first_failure_code(if_first_failure)
    );

    gatee_h_selector_only u_selector (
        .clk(selector_semantic_clock), .reset(selector_reset),
        .entry_event(selector_entry_event),
        .completion_event(selector_completion_event),
        .source_state(if_source_state), .source_attempt(if_attempt),
        .completion_expected_program(if_program),
        .completion_next_state(if_next_state),
        .completion_source_zero_class(if_source_class),
        .completion_current_zero_class(if_current_class),
        .completion_reason(if_reason),
        .token_valid(selector_token_valid),
        .non_target_pending(selector_non_target_pending),
        .token_bnd_id(selector_token_id),
        .transition_id(selector_transition_id),
        .token_expected_program(selector_expected_program),
        .token_expected_next_state(selector_expected_next_state),
        .token_source_zero_class(selector_source_class),
        .token_current_zero_class(selector_current_class),
        .token_completion_reason(selector_expected_reason),
        .bnd_event(selector_bnd_event),
        .bnd_event_id(selector_bnd_event_id),
        .bnd_event_count(selector_event_count),
        .bnd1_events(selector_bnd1), .bnd2_events(selector_bnd2),
        .bnd3_events(selector_bnd3),
        .non_target_count(selector_non_target_count),
        .failures(selector_failures),
        .first_failure_code(selector_first_failure)
    );

    gatee_v3_epoch_interface u_epoch (
        .clk(base.clk), .reset(base.reset),
        .global_entry_event(if_entry),
        .global_completion_event(if_completion),
        .global_entry_source_state(if_source_state),
        .global_entry_attempt(if_attempt),
        .global_entry_id(if_entry_id),
        .global_completion_id(if_completion_id),
        .p_token_consume(p_consume), .p_event_source(p_source),
        .p_failures(p_failures), .r_owner(r_owner),
        .r_legal_restart_count(r_legal_count),
        .r_failures(r_failures),
        .selector_token_valid(selector_token_valid),
        .selector_non_target_pending(selector_non_target_pending),
        .selector_token_bnd_id(selector_token_id),
        .selector_transition_id(selector_transition_id),
        .selector_bnd_event(selector_bnd_event),
        .selector_bnd_event_id(selector_bnd_event_id),
        .selector_bnd_event_count(selector_event_count),
        .selector_bnd1_events(selector_bnd1),
        .selector_bnd2_events(selector_bnd2),
        .selector_bnd3_events(selector_bnd3),
        .selector_non_target_count(selector_non_target_count),
        .selector_failures(selector_failures),
        .h_transition_token_valid(h_token_valid),
        .h_entry_cycle(h_entry_cycle),
        .h_completion_cycle(h_completion_cycle),
        .h_event_seen(h_event_seen), .h_bnd1_events(h_bnd1),
        .h_bnd2_events(h_bnd2), .h_bnd3_events(h_bnd3),
        .h_bnd_event_count(h_event_count), .h_bnd_pass(h_bnd_pass),
        .h_failures(h_failures), .h_interface_failures(if_failures),
        .selector_entry_event(selector_entry_event),
        .selector_completion_event(selector_completion_event),
        .selector_rearm_pulse(selector_rearm),
        .bnd_counter_enable(bnd_counter_enable),
        .global_pending(epoch_global_pending),
        .qualified_pending(epoch_qualified_pending), .epoch(epoch),
        .inventory_index(inventory_index),
        .terminal_ready(terminal_ready),
        .epoch_contract_pass(epoch_contract_pass),
        .integration_complete(integration_complete),
        .global_entries(global_entries),
        .global_completions(global_completions),
        .qualified_entries(qualified_entries),
        .qualified_completions(qualified_completions),
        .out_of_domain_entries(out_domain_entries),
        .out_of_domain_completions(out_domain_completions),
        .epoch_advances(epoch_advances),
        .owned_restart_rearms(owned_restart_rearms),
        .third_epoch_events(third_epoch_events),
        .epoch0_qualified(epoch0_qualified),
        .epoch0_targets(epoch0_targets),
        .epoch0_non_targets(epoch0_non_targets),
        .epoch1_qualified(epoch1_qualified),
        .epoch1_targets(epoch1_targets),
        .epoch1_non_targets(epoch1_non_targets),
        .epoch0_h_acceptance(epoch0_h_acceptance),
        .epoch1_h_acceptance(epoch1_h_acceptance),
        .epoch0_h_injection(epoch0_h_injection),
        .epoch1_h_injection(epoch1_h_injection),
        .epoch1_local_bnd1(epoch1_local_bnd1),
        .epoch1_local_bnd2(epoch1_local_bnd2),
        .epoch1_local_bnd3(epoch1_local_bnd3),
        .epoch1_local_pass(epoch1_local_pass),
        .aggregate_targets(aggregate_targets),
        .aggregate_non_targets(aggregate_non_targets),
        .aggregate_bnd1(aggregate_bnd1),
        .aggregate_bnd2(aggregate_bnd2),
        .aggregate_bnd3(aggregate_bnd3),
        .global_id_mismatches(global_id_mismatches),
        .target_duplicate_drop(target_duplicate_drop),
        .errors(epoch_errors), .first_error_code(epoch_first_error)
    );

    integer seam_xz = 0;
    always @(posedge base.clk) begin
        #4;
        if (!base.reset &&
            ($isunknown(if_entry) || $isunknown(if_completion) ||
             $isunknown(selector_entry_event) ||
             $isunknown(selector_completion_event) ||
             $isunknown(selector_rearm) ||
             $isunknown(bnd_counter_enable) || $isunknown(epoch) ||
             $isunknown(external_target_valid) ||
             $isunknown(external_target_id)))
            seam_xz = seam_xz + 1;
    end

    integer bounded_only = 0;
    logic pass_reported = 1'b0;
    initial begin
        if (!$value$plusargs("BOUNDED_ONLY=%d", bounded_only))
            bounded_only = 0;
    end

    always @(posedge base.clk) begin
        #5;
        if (!base.reset && epoch_contract_pass && !pass_reported) begin
            if (p_failures != 0 || r_failures != 0 ||
                selector_failures != 0 || epoch_errors != 0 ||
                h_failures != 0 || if_failures != 0 ||
                h_first_failure == 8'd13 ||
                global_id_mismatches != 0 ||
                target_duplicate_drop != 0 || seam_xz != 0 ||
                base.semantic_silence_errors != 0 ||
                base.semantic_missing_pulses != 0 ||
                base.semantic_duplicate_pulses != 0 ||
                base.semantic_overlap_pulses != 0 ||
                base.semantic_order_errors != 0 ||
                base.cadence_errors != 0 || base.width_errors != 0 ||
                base.drops != 0 || base.duplicates != 0 ||
                base.tick_missed != 0 || base.tick_duplicates != 0 ||
                base.debug_busy_timeout || base.debug_write_while_busy ||
                base.debug_phase_error || base.debug_zero_timeout ||
                base.unexpected_adpcm_requests != 0 || base.x_count != 0)
                $fatal(1, "V3 epoch bounded aggregate mismatch");
            pass_reported = 1'b1;
            $display("V3_EPOCH_BOUNDED_PASS global=%0d/%0d qualified=%0d out_domain=%0d epoch_count=2 advance=%0d rearm=%0d third=%0d epoch0=%0d/%0d/%0d h_accept=%0d h_inject=%0d epoch1=%0d/%0d/%0d h_accept=%0d h_inject=%0d local=%0d/%0d/%0d local_pass=%0d aggregate=%0d/%0d BND=%0d/%0d/%0d duplicate_drop=%0d id_mismatch=%0d phase=%0d restart=%0d selector=%0d epoch_errors=%0d h=%0d interface=%0d post_sample=%0d XZ=%0d busy=%0d/%0d",
                global_entries, global_completions, qualified_entries,
                out_domain_entries, epoch_advances,
                owned_restart_rearms, third_epoch_events,
                epoch0_qualified, epoch0_targets,
                epoch0_non_targets, epoch0_h_acceptance,
                epoch0_h_injection, epoch1_qualified, epoch1_targets,
                epoch1_non_targets, epoch1_h_acceptance,
                epoch1_h_injection, epoch1_local_bnd1,
                epoch1_local_bnd2, epoch1_local_bnd3,
                epoch1_local_pass, aggregate_targets,
                aggregate_non_targets, aggregate_bnd1,
                aggregate_bnd2, aggregate_bnd3,
                target_duplicate_drop, global_id_mismatches,
                p_failures, r_failures, selector_failures, epoch_errors,
                h_failures, if_failures, base.semantic_silence_errors,
                seam_xz + base.x_count, base.debug_busy_timeout,
                base.debug_write_while_busy);
            if (bounded_only != 0)
                $finish;
        end
    end
endmodule

`timescale 1ns/1ps

`ifndef ZMODE
`define ZMODE 0
`endif

module tb_jt10_semantic_zero_attempt_offline_replay;
    import semantic_timeline_authority_pkg::*;

    localparam integer MODE = `ZMODE;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic reset = 1'b1;
    logic loop_epoch = 1'b0;
    logic [6:0] raw_state = 0;
    logic [3:0] raw_phase = 0;
    logic [2:0] raw_attempt = 0;
    logic raw_program_active = 1'b0;
    logic [4:0] raw_program = 0;
    logic external_mute = 1'b1;

    logic event_valid;
    logic event_loop;
    logic [3:0] event_family;
    logic [2:0] event_attempt;
    logic [1:0] event_kind;
    logic [6:0] event_state;
    logic [3:0] event_phase;
    logic event_program_active;
    logic [4:0] event_program;
    integer a_start;
    integer a_stop;
    integer a_zero;
    integer a_failures;
    logic [7:0] a_first_code;

    semantic_timeline_adapter u_adapter (
        .clk(clk), .reset(reset), .loop_epoch(loop_epoch), .state(raw_state),
        .phase(raw_phase), .raw_attempt(raw_attempt),
        .program_active(raw_program_active), .program_id(raw_program),
        .external_mute(external_mute), .event_valid(event_valid),
        .event_loop(event_loop), .event_family(event_family),
        .event_attempt(event_attempt), .event_kind(event_kind),
        .event_state(event_state), .event_phase(event_phase),
        .event_program_active(event_program_active),
        .event_program(event_program), .start_events(a_start),
        .stop_events(a_stop), .zero_events(a_zero), .failures(a_failures),
        .first_failure_code(a_first_code)
    );

    logic observed_epoch = 1'b0;
    integer r_start;
    integer r_stop;
    integer r_zero;
    integer r_loop0_start;
    integer r_loop0_stop;
    integer r_loop0_zero;
    integer r_loop1_start;
    integer r_loop1_stop;
    integer r_loop1_zero;
    integer r_completed;
    integer r_rearm;
    integer r_missing;
    integer r_duplicate;
    integer r_ownership;
    integer r_order;
    integer r_loop_errors;
    integer r_failures;
    logic [7:0] r_first_code;
    logic r_loop0_complete;
    logic r_loop1_complete;
    logic r_integration_complete;
    logic r_pass;

    semantic_timeline_rearm_r3 u_r3 (
        .clk(clk), .reset(reset), .flush(1'b0), .loop_rearm(1'b0),
        .observed_epoch(observed_epoch), .event_valid(event_valid),
        .event_loop(event_loop), .event_family(event_family),
        .event_attempt(event_attempt), .event_kind(event_kind),
        .event_state(event_state), .event_phase(event_phase),
        .event_program_active(event_program_active),
        .event_program(event_program), .start_count(r_start),
        .stop_count(r_stop), .zero_count(r_zero),
        .loop0_start_count(r_loop0_start),
        .loop0_stop_count(r_loop0_stop), .loop0_zero_count(r_loop0_zero),
        .loop1_start_count(r_loop1_start),
        .loop1_stop_count(r_loop1_stop), .loop1_zero_count(r_loop1_zero),
        .completed_slots(r_completed), .rearm_count(r_rearm),
        .missing_errors(r_missing), .duplicate_errors(r_duplicate),
        .ownership_errors(r_ownership), .order_errors(r_order),
        .loop_errors(r_loop_errors), .failures(r_failures),
        .first_failure_code(r_first_code),
        .loop0_complete(r_loop0_complete), .loop1_complete(r_loop1_complete),
        .integration_complete(r_integration_complete), .pass(r_pass)
    );

    function automatic logic [2:0] artifact_raw_attempt(
        input logic loop_value,
        input logic [3:0] family,
        input logic [2:0] attempt,
        input logic [1:0] kind
    );
        begin
            if (loop_value && (family == F_FM || family == F_SSG))
                artifact_raw_attempt = 3'd2;
            else
                artifact_raw_attempt =
                    expected_raw_attempt(family, attempt, kind);
        end
    endfunction

    task automatic sample_cycle;
        begin
            @(posedge clk);
            #5;
        end
    endtask

    task automatic emit_raw_slot(
        input logic loop_value,
        input logic [3:0] family,
        input logic [2:0] attempt
    );
        begin
            // Establish the family start state while muted.
            @(negedge clk);
            loop_epoch = loop_value;
            raw_state = start_state(family);
            raw_phase = family_phase(family);
            raw_attempt = artifact_raw_attempt(
                loop_value, family, attempt, K_START);
            raw_program_active = start_active(family);
            raw_program = start_program(family);
            external_mute = 1'b1;
            sample_cycle();

            // START: falling mute edge.
            @(negedge clk);
            external_mute = 1'b0;
            sample_cycle();

            // STOP: transition into the family stop state.
            @(negedge clk);
            raw_state = stop_state(family);
            raw_phase = family_phase(family);
            raw_attempt = artifact_raw_attempt(
                loop_value, family, attempt, K_STOP);
            raw_program_active = stop_active(family);
            raw_program = stop_program(family);
            sample_cycle();

            // ZERO: rising mute edge at the post-state.
            @(negedge clk);
            raw_state = zero_post_state(family, attempt);
            raw_phase = zero_phase(family);
            raw_attempt = artifact_raw_attempt(
                loop_value, family, attempt, K_ZERO);
            raw_program_active = 1'b0;
            external_mute = 1'b1;
            sample_cycle();
        end
    endtask

    task automatic emit_raw_loop(input logic loop_value);
        logic [3:0] family;
        logic [2:0] attempt;
        logic [3:0] old_family;
        logic [2:0] old_attempt;
        integer index;
        begin
            family = F_FM;
            attempt = 0;
            for (index = 0; index < 32; index = index + 1) begin
                emit_raw_slot(loop_value, family, attempt);
                old_family = family;
                old_attempt = attempt;
                family = next_family(old_family, old_attempt);
                attempt = next_attempt(old_family, old_attempt);
            end
        end
    endtask

    integer expected_zero;
    integer expected_failures;
    initial begin
        repeat (3) @(negedge clk);
        reset = 1'b0;
        @(negedge clk);
        emit_raw_loop(1'b0);
        if (!r_loop0_complete || r_failures != 0 || a_failures != 0)
            $fatal(1, "loop0 replay mismatch mode=%0d", MODE);

        @(negedge clk);
        observed_epoch = 1'b1;
        loop_epoch = 1'b1;
        sample_cycle();
        if (r_rearm != 1 || u_r3.stage != 3'd0 || r_failures != 0)
            $fatal(1, "offline epoch rearm mismatch mode=%0d", MODE);

        emit_raw_loop(1'b1);
        repeat (2) sample_cycle();

        expected_zero = MODE == 0 ? 62 : MODE == 3 ? 64 : 63;
        expected_failures = MODE == 3 ? 0 : MODE == 0 ? 2 : 1;
        if (a_start != 64 || a_stop != 64 || a_zero != expected_zero ||
            a_failures != expected_failures ||
            (expected_failures != 0 && a_first_code != 4))
            $fatal(1, "offline A1 mismatch mode=%0d A=%0d/%0d/%0d fail=%0d code=%0d expected=%0d/%0d",
                   MODE, a_start, a_stop, a_zero, a_failures, a_first_code,
                   expected_zero, expected_failures);

        if (MODE == 3) begin
            if (r_failures != 0 || r_start != 64 || r_stop != 64 ||
                r_zero != 64 || !r_loop1_complete ||
                !r_integration_complete || !r_pass || r_rearm != 1)
                $fatal(1, "offline Z3 R3 mismatch");
        end else begin
            if (r_failures != 1 || r_first_code != 13 ||
                r_integration_complete)
                $fatal(1, "offline derivative mismatch mode=%0d Rfail=%0d code=%0d",
                       MODE, r_failures, r_first_code);
        end

        $display("OFFLINE_REPLAY_PASS mode=%0d A1=%0d/%0d/%0d failures=%0d R3_failures=%0d R3_code=%0d complete=%0d",
                 MODE, a_start, a_stop, a_zero, a_failures,
                 r_failures, r_first_code, r_integration_complete);
        $finish;
    end
endmodule

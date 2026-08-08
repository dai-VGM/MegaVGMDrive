`timescale 1ns/1ps

module tb_jt10_semantic_zero_attempt_two_layer_negative;
    import semantic_timeline_authority_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic reset = 1'b1;
    logic loop_epoch = 1'b0;
    logic [6:0] raw_state = 0;
    logic [3:0] raw_phase = 0;
    logic [2:0] raw_attempt = 0;
    logic raw_program_active = 1'b0;
    logic [4:0] raw_program = 0;
    logic external_mute = 1'b0;

    logic a_valid;
    logic a_loop;
    logic [3:0] a_family;
    logic [2:0] a_attempt;
    logic [1:0] a_kind;
    logic [6:0] a_state;
    logic [3:0] a_phase;
    logic a_program_active;
    logic [4:0] a_program;
    integer a_start;
    integer a_stop;
    integer a_zero;
    integer a_failures;
    logic [7:0] a_first_code;

    semantic_timeline_adapter u_adapter (
        .clk(clk), .reset(reset), .loop_epoch(loop_epoch), .state(raw_state),
        .phase(raw_phase), .raw_attempt(raw_attempt),
        .program_active(raw_program_active), .program_id(raw_program),
        .external_mute(external_mute), .event_valid(a_valid),
        .event_loop(a_loop), .event_family(a_family),
        .event_attempt(a_attempt), .event_kind(a_kind),
        .event_state(a_state), .event_phase(a_phase),
        .event_program_active(a_program_active), .event_program(a_program),
        .start_events(a_start), .stop_events(a_stop), .zero_events(a_zero),
        .failures(a_failures), .first_failure_code(a_first_code)
    );

    logic use_adapter = 1'b0;
    logic d_valid = 1'b0;
    logic d_loop = 1'b0;
    logic [3:0] d_family = F_FM;
    logic [2:0] d_attempt = 0;
    logic [1:0] d_kind = K_START;
    logic [6:0] d_state = 0;
    logic [3:0] d_phase = 0;
    logic d_program_active = 1'b0;
    logic [4:0] d_program = 0;

    wire r_valid = use_adapter ? a_valid : d_valid;
    wire r_loop = use_adapter ? a_loop : d_loop;
    wire [3:0] r_family = use_adapter ? a_family : d_family;
    wire [2:0] r_attempt = use_adapter ? a_attempt : d_attempt;
    wire [1:0] r_kind = use_adapter ? a_kind : d_kind;
    wire [6:0] r_state = use_adapter ? a_state : d_state;
    wire [3:0] r_phase = use_adapter ? a_phase : d_phase;
    wire r_program_active = use_adapter ? a_program_active : d_program_active;
    wire [4:0] r_program = use_adapter ? a_program : d_program;

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
        .observed_epoch(1'b0), .event_valid(r_valid), .event_loop(r_loop),
        .event_family(r_family), .event_attempt(r_attempt),
        .event_kind(r_kind), .event_state(r_state), .event_phase(r_phase),
        .event_program_active(r_program_active), .event_program(r_program),
        .start_count(r_start), .stop_count(r_stop), .zero_count(r_zero),
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

    task automatic reset_all(input logic initial_mute);
        begin
            @(negedge clk);
            reset = 1'b1;
            use_adapter = 1'b0;
            d_valid = 1'b0;
            loop_epoch = 1'b0;
            raw_state = 0;
            raw_phase = 0;
            raw_attempt = 0;
            raw_program_active = 1'b0;
            raw_program = 0;
            external_mute = initial_mute;
            repeat (2) @(negedge clk);
            reset = 1'b0;
            @(negedge clk);
        end
    endtask

    task automatic emit_direct(
        input logic [3:0] family,
        input logic [2:0] attempt,
        input logic [1:0] kind
    );
        begin
            @(negedge clk);
            use_adapter = 1'b0;
            d_loop = 1'b0;
            d_family = family;
            d_attempt = attempt;
            d_kind = kind;
            d_state = kind == K_START ? start_state(family) :
                      kind == K_STOP ? stop_state(family) :
                                       zero_post_state(family, attempt);
            d_phase = kind == K_ZERO ? zero_phase(family) :
                                      family_phase(family);
            d_program_active = kind == K_START ? start_active(family) :
                               kind == K_STOP ? stop_active(family) : 1'b0;
            d_program = kind == K_START ? start_program(family) :
                        kind == K_STOP ? stop_program(family) : 0;
            d_valid = 1'b1;
            @(negedge clk);
            d_valid = 1'b0;
        end
    endtask

    task automatic emit_direct_slot(
        input logic [3:0] family,
        input logic [2:0] attempt
    );
        begin
            emit_direct(family, attempt, K_START);
            emit_direct(family, attempt, K_STOP);
            emit_direct(family, attempt, K_ZERO);
        end
    endtask

    task automatic advance_to(
        input logic [3:0] target_family,
        input logic [2:0] target_attempt
    );
        logic [3:0] family;
        logic [2:0] attempt;
        logic [3:0] old_family;
        logic [2:0] old_attempt;
        integer guard;
        begin
            family = F_FM;
            attempt = 0;
            guard = 0;
            while ((family != target_family || attempt != target_attempt) &&
                   guard < 32) begin
                emit_direct_slot(family, attempt);
                old_family = family;
                old_attempt = attempt;
                family = next_family(old_family, old_attempt);
                attempt = next_attempt(old_family, old_attempt);
                guard = guard + 1;
            end
            if (family != target_family || attempt != target_attempt)
                $fatal(1, "target tuple not reachable");
            emit_direct(target_family, target_attempt, K_START);
            emit_direct(target_family, target_attempt, K_STOP);
            if (r_failures != 0 || u_r3.stage != 3'd2)
                $fatal(1, "failed to prepare R3 WAIT_ZERO target=%0d/%0d",
                       target_family, target_attempt);
        end
    endtask

    task automatic emit_adapter_zero(
        input logic [6:0] state_value,
        input logic [3:0] phase_value,
        input logic [2:0] raw_value,
        input logic [4:0] program_value
    );
        begin
            @(negedge clk);
            use_adapter = 1'b1;
            d_valid = 1'b0;
            raw_state = state_value;
            raw_phase = phase_value;
            raw_attempt = raw_value;
            raw_program_active = 1'b0;
            raw_program = program_value;
            external_mute = 1'b0;
            @(negedge clk);
            external_mute = 1'b1;
            @(posedge clk);
            #5;
        end
    endtask

    task automatic check_valid_wrong(
        input integer case_id,
        input logic [3:0] expected_family,
        input logic [2:0] expected_attempt,
        input logic [6:0] raw_state_value,
        input logic [2:0] raw_value,
        input logic [3:0] mapped_family,
        input logic [2:0] mapped_attempt,
        input logic [7:0] expected_r3_code
    );
        integer saved_r_start;
        integer saved_r_stop;
        integer saved_r_zero;
        begin
            reset_all(1'b0);
            advance_to(expected_family, expected_attempt);
            saved_r_start = r_start;
            saved_r_stop = r_stop;
            saved_r_zero = r_zero;
            emit_adapter_zero(raw_state_value, zero_phase(mapped_family),
                              raw_value, 0);
            if (a_failures != 0 || !a_valid || a_zero != 1 ||
                a_family != mapped_family || a_attempt != mapped_attempt ||
                a_kind != K_ZERO || r_failures != 1 ||
                r_first_code != expected_r3_code ||
                r_start != saved_r_start || r_stop != saved_r_stop ||
                r_zero != saved_r_zero)
                $fatal(1, "LayerB case%0d mismatch A=%0d/%0d/%0d/%0d R=%0d/%0d zero=%0d",
                       case_id, a_valid, a_family, a_attempt, a_failures,
                       r_failures, r_first_code, r_zero);
            $display("LAYER_B_PASS case=%0d A1_publish=1 A1_code4=0 mapped=%0d/%0d R3_accept=0 R3_code=%0d",
                     case_id, mapped_family, mapped_attempt, expected_r3_code);
        end
    endtask

    task automatic check_invalid_no_publish(
        input integer case_id,
        input logic [3:0] expected_family,
        input logic [2:0] expected_attempt,
        input logic [6:0] invalid_state,
        input logic [2:0] invalid_raw
    );
        integer saved_r_start;
        integer saved_r_stop;
        integer saved_r_zero;
        begin
            reset_all(1'b0);
            advance_to(expected_family, expected_attempt);
            saved_r_start = r_start;
            saved_r_stop = r_stop;
            saved_r_zero = r_zero;
            emit_adapter_zero(invalid_state, zero_phase(expected_family),
                              invalid_raw, 0);
            if (a_failures != 1 || a_first_code != 4 || a_valid ||
                a_zero != 0 || r_failures != 0 ||
                r_start != saved_r_start || r_stop != saved_r_stop ||
                r_zero != saved_r_zero ||
                u_r3.stage != 3'd2)
                $fatal(1, "LayerA case%0d mismatch A=%0d/%0d/%0d R=%0d/%0d",
                       case_id, a_valid, a_failures, a_first_code,
                       r_failures, r_first_code);
            $display("LAYER_A_PASS case=%0d A1_publish=0 A1_code=4 R3_input=0",
                     case_id);
        end
    endtask

    task automatic check_wrong_program;
        begin
            reset_all(1'b1);
            @(negedge clk);
            use_adapter = 1'b1;
            raw_state = start_state(F_FM);
            raw_phase = family_phase(F_FM);
            raw_attempt = 3'd2;
            raw_program_active = 1'b1;
            raw_program = 5'd31;
            external_mute = 1'b1;
            @(negedge clk);
            external_mute = 1'b0;
            @(posedge clk);
            #5;
            if (a_failures != 0 || !a_valid || a_family != F_FM ||
                a_attempt != 0 || r_failures != 1 || r_first_code != 3)
                $fatal(1, "wrong program responsibility mismatch");
            $display("PROGRAM_AUTHORITY_PASS A1_publish=1 R3_code=3");
        end
    endtask

    task automatic check_wrong_phase;
        begin
            reset_all(1'b0);
            emit_direct(F_FM, 0, K_START);
            emit_direct(F_FM, 0, K_STOP);
            emit_adapter_zero(zero_post_state(F_FM, 0), 4'd9, 3'd2,
                              stop_program(F_FM));
            if (a_failures != 0 || !a_valid || r_failures != 1 ||
                r_first_code != 18)
                $fatal(1, "wrong phase responsibility mismatch");
            $display("PHASE_AUTHORITY_PASS A1_publish=1 R3_code=18");
        end
    endtask

    task automatic check_duplicate_and_order;
        begin
            reset_all(1'b0);
            emit_direct(F_FM, 0, K_START);
            emit_direct(F_FM, 0, K_START);
            if (r_failures != 1 || r_first_code != 2)
                $fatal(1, "duplicate START not detected");
            $display("DUPLICATE_AUTHORITY_PASS R3_code=2");

            reset_all(1'b0);
            emit_direct(F_FM, 0, K_STOP);
            if (r_failures != 1 || r_first_code != 9)
                $fatal(1, "order swap not detected");
            $display("ORDER_AUTHORITY_PASS R3_code=9");
        end
    endtask

    initial begin
        // Layer A: invalid raw classifier rows never reach R3.
        check_invalid_no_publish(1, F_A6, 5,
            zero_post_state(F_A6, 5), 3'd4);
        check_invalid_no_publish(2, F_B, 1,
            zero_post_state(F_B, 1), 3'd0);
        check_invalid_no_publish(3, F_NATURAL2, 2,
            zero_post_state(F_NATURAL2, 2), 3'd1);

        // Layer B: valid physical tuples publish, then R3 rejects ownership.
        check_valid_wrong(4, F_A0, 3, zero_post_state(F_A0, 3), 3'd2,
                          F_A0, 1, 8'd4);
        check_valid_wrong(5, F_LEFT, 2, zero_post_state(F_LEFT, 2), 3'd1,
                          F_LEFT, 0, 8'd4);
        check_valid_wrong(6, F_RIGHT, 1, zero_post_state(F_RIGHT, 1), 3'd2,
                          F_LEFT, 1, 8'd6);
        check_valid_wrong(7, F_NATURAL1, 0,
                          zero_post_state(F_NATURAL1, 0), 3'd2,
                          F_NATURAL1, 2, 8'd4);

        check_wrong_program();
        check_wrong_phase();
        check_duplicate_and_order();
        $display("TWO_LAYER_NEGATIVE_PASS");
        $finish;
    end
endmodule

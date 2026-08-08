`timescale 1ns/1ps

`ifndef ZMODE
`define ZMODE 0
`endif

module tb_jt10_semantic_zero_attempt_adapter_unit;
    import semantic_timeline_authority_pkg::*;

    localparam integer MODE = `ZMODE;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic reset = 1'b1;
    logic loop_epoch = 1'b0;
    logic [6:0] state = 0;
    logic [3:0] phase = 0;
    logic [2:0] raw_attempt = 0;
    logic program_active = 1'b0;
    logic [4:0] program_id = 0;
    logic external_mute = 1'b0;
    logic event_valid;
    logic event_loop;
    logic [3:0] event_family;
    logic [2:0] event_attempt;
    logic [1:0] event_kind;
    logic [6:0] event_state;
    logic [3:0] event_phase;
    logic event_program_active;
    logic [4:0] event_program;
    integer start_events;
    integer stop_events;
    integer zero_events;
    integer failures;
    logic [7:0] first_failure_code;

    semantic_timeline_adapter dut (
        .clk(clk), .reset(reset), .loop_epoch(loop_epoch), .state(state),
        .phase(phase), .raw_attempt(raw_attempt),
        .program_active(program_active), .program_id(program_id),
        .external_mute(external_mute), .event_valid(event_valid),
        .event_loop(event_loop), .event_family(event_family),
        .event_attempt(event_attempt), .event_kind(event_kind),
        .event_state(event_state), .event_phase(event_phase),
        .event_program_active(event_program_active),
        .event_program(event_program), .start_events(start_events),
        .stop_events(stop_events), .zero_events(zero_events),
        .failures(failures), .first_failure_code(first_failure_code)
    );

    task automatic reset_adapter;
        begin
            @(negedge clk);
            reset = 1'b1;
            loop_epoch = 1'b0;
            state = 0;
            phase = 0;
            raw_attempt = 0;
            program_active = 1'b0;
            program_id = 0;
            external_mute = 1'b0;
            repeat (2) @(negedge clk);
            reset = 1'b0;
            @(negedge clk);
        end
    endtask

    function automatic logic normalization_enabled(input logic [3:0] family);
        begin
            case (MODE)
                0: normalization_enabled = 1'b0;
                1: normalization_enabled = family == F_FM;
                2: normalization_enabled = family == F_SSG;
                default: normalization_enabled =
                    family == F_FM || family == F_SSG;
            endcase
        end
    endfunction

    task automatic drive_zero_edge(
        input logic [6:0] zero_state_value,
        input logic [3:0] phase_value,
        input logic [2:0] raw_value,
        input logic [4:0] program_value
    );
        begin
            @(negedge clk);
            state = zero_state_value;
            phase = phase_value;
            raw_attempt = raw_value;
            program_active = 1'b0;
            program_id = program_value;
            external_mute = 1'b0;
            @(negedge clk); // establish state while mute remains low
            external_mute = 1'b1;
            @(posedge clk);
            #4;
        end
    endtask

    task automatic check_single_attempt_zero(
        input logic [3:0] family,
        input logic [2:0] raw_value
    );
        logic expect_publish;
        begin
            reset_adapter();
            drive_zero_edge(zero_post_state(family, 0), zero_phase(family),
                            raw_value, stop_program(family));
            expect_publish = raw_value == 0 || normalization_enabled(family);
            if (expect_publish) begin
                if (!event_valid || event_family != family ||
                    event_attempt != 0 || event_kind != K_ZERO ||
                    zero_events != 1 || failures != 0)
                    $fatal(1, "Z%0d family%0d raw%0d publish mismatch ev=%0d tuple=%0d/%0d/%0d zero=%0d fail=%0d code=%0d",
                           MODE, family, raw_value, event_valid,
                           event_family, event_attempt, event_kind,
                           zero_events, failures, first_failure_code);
            end else begin
                if (event_valid || zero_events != 0 || failures != 1 ||
                    first_failure_code != 4)
                    $fatal(1, "Z%0d family%0d raw%0d expected code4 ev=%0d zero=%0d fail=%0d code=%0d",
                           MODE, family, raw_value, event_valid, zero_events,
                           failures, first_failure_code);
            end
            $display("ADAPTER_ZERO_CASE_PASS mode=%0d family=%0d raw=%0d publish=%0d code4=%0d",
                     MODE, family, raw_value, expect_publish,
                     !expect_publish);
        end
    endtask

    task automatic check_invalid_raw(
        input integer case_id,
        input logic [6:0] state_value,
        input logic [3:0] phase_value,
        input logic [2:0] raw_value
    );
        begin
            reset_adapter();
            drive_zero_edge(state_value, phase_value, raw_value, 0);
            if (event_valid || zero_events != 0 || failures != 1 ||
                first_failure_code != 4)
                $fatal(1, "invalid case%0d mode%0d mismatch ev=%0d zero=%0d fail=%0d code=%0d",
                       case_id, MODE, event_valid, zero_events, failures,
                       first_failure_code);
            $display("ADAPTER_INVALID_PASS mode=%0d case=%0d code=4",
                     MODE, case_id);
        end
    endtask

    task automatic check_duplicate_level;
        integer saved_zero;
        begin
            reset_adapter();
            drive_zero_edge(zero_post_state(F_FM, 0), zero_phase(F_FM),
                            3'd2, stop_program(F_FM));
            if (MODE != 1 && MODE != 3) begin
                // Only candidates that normalize FM are meaningful here.
            end else begin
                if (!event_valid || zero_events != 1 || failures != 0)
                    $fatal(1, "duplicate setup mismatch");
                saved_zero = zero_events;
                @(posedge clk);
                #4;
                if (event_valid || zero_events != saved_zero || failures != 0)
                    $fatal(1, "held mute duplicated ZERO");
                $display("ADAPTER_DUPLICATE_LEVEL_PASS mode=%0d", MODE);
            end
        end
    endtask

    integer index;
    logic [2:0] raw_values [0:4];
    initial begin
        raw_values[0] = 0;
        raw_values[1] = 1;
        raw_values[2] = 2;
        raw_values[3] = 5;
        raw_values[4] = 7;

        for (index = 0; index < 5; index = index + 1) begin
            check_single_attempt_zero(F_FM, raw_values[index]);
            check_single_attempt_zero(F_SSG, raw_values[index]);
        end

        // Layer-A invalid tuples are invariant across Z0--Z3.
        check_invalid_raw(1, zero_post_state(F_A6, 5),
                          zero_phase(F_A6), 3'd4);
        check_invalid_raw(2, zero_post_state(F_B, 1),
                          zero_phase(F_B), 3'd0);
        check_invalid_raw(3, zero_post_state(F_NATURAL2, 2),
                          zero_phase(F_NATURAL2), 3'd1);
        check_invalid_raw(4, 7'd5, 4'd0, 3'd0);  // wrong FM ZERO state
        check_invalid_raw(5, 7'd13, 4'd0, 3'd0); // wrong SSG ZERO state
        check_duplicate_level();

        $display("ADAPTER_UNIT_PASS mode=%0d", MODE);
        $finish;
    end
endmodule

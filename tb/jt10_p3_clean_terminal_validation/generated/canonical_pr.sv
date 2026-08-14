`timescale 1ns/1ps

// Versioned, TB-only acceptance monitors.  Every port is an input from the
// frozen graph or an observer output; these modules have no DUT drive path.

module gatee_phase_token_monitor #(
    parameter integer ENABLE = 1,
    parameter integer FATAL_ON_ERROR = 0
) (
    input  logic       clk,
    input  logic       reset,
    input  logic [6:0] state,
    input  logic [3:0] phase,
    input  logic       program_active,
    input  logic [4:0] program_id,
    input  logic       flush,
    output logic [6:0] phase_event_source,
    output logic [3:0] expected_current_phase,
    output logic [3:0] expected_next_phase,
    output logic       expected_visible_event,
    output logic       token_arm,
    output logic       token_consume,
    output logic       token_valid,
    output integer     token_arms,
    output integer     token_consumes,
    output integer     visible_events,
    output integer     failures,
    output logic [7:0] first_failure_code
);
    localparam logic [7:0] P_NONE               = 8'd0;
    localparam logic [7:0] P_PHASE_SKIP         = 8'd1;
    localparam logic [7:0] P_PHASE_REPEAT       = 8'd2;
    localparam logic [7:0] P_WRONG_PHASE        = 8'd3;
    localparam logic [7:0] P_WRONG_STATE        = 8'd4;
    localparam logic [7:0] P_WRONG_PROGRAM      = 8'd5;
    localparam logic [7:0] P_TOKEN_MISSING      = 8'd6;
    localparam logic [7:0] P_DUPLICATE_TOKEN    = 8'd7;
    localparam logic [7:0] P_LATE_TOKEN         = 8'd8;
    localparam logic [7:0] P_UNEXPECTED_VISIBLE = 8'd9;
    localparam logic [7:0] P_DUPLICATE_VISIBLE  = 8'd10;

    logic [6:0] previous_state;
    logic [3:0] previous_phase;
    logic [3:0] sequence_phase;
    logic [6:0] token_state;
    logic [3:0] token_phase;
    logic token_program_active;
    logic [4:0] token_program_id;
    logic last_visible_consumed;
    integer token_age;

    function automatic [3:0] mapped_phase(input logic [6:0] value);
        begin
            case (value)
                7'd3:  mapped_phase = 4'd1;
                7'd11: mapped_phase = 4'd2;
                7'd19: mapped_phase = 4'd3;
                7'd27: mapped_phase = 4'd4;
                7'd35: mapped_phase = 4'd5;
                7'd43: mapped_phase = 4'd6;
                7'd57: mapped_phase = 4'd7;
                7'd71: mapped_phase = 4'd8;
                default: mapped_phase = 4'd0;
            endcase
        end
    endfunction

    function automatic expected_active(input logic [6:0] value);
        begin
            case (value)
                7'd3, 7'd19, 7'd27, 7'd35, 7'd43, 7'd57:
                    expected_active = 1'b1;
                default: expected_active = 1'b0;
            endcase
        end
    endfunction

    function automatic [4:0] mapped_program(input logic [6:0] value);
        begin
            case (value)
                7'd3:  mapped_program = 5'd1;
                7'd11: mapped_program = 5'd3;
                7'd19: mapped_program = 5'd7;
                7'd27: mapped_program = 5'd10;
                7'd35: mapped_program = 5'd13;
                7'd43: mapped_program = 5'd14;
                7'd57: mapped_program = 5'd16;
                7'd71: mapped_program = 5'd17;
                default: mapped_program = 5'd31;
            endcase
        end
    endfunction

    task automatic phase_fail(input logic [7:0] code);
        begin
            if (first_failure_code == P_NONE) begin
                first_failure_code = code;
                failures = failures + 1;
                $display("GATEE_P_FAIL code=%0d state=%0d phase=%0d expected=%0d program=%0d/%0d",
                    code, state, phase, sequence_phase,
                    program_active, program_id);
                if (FATAL_ON_ERROR) $fatal(1, "Gate E phase token failure %0d", code);
            end
        end
    endtask

    always @(posedge clk) begin : phase_contract
        logic source_event;
        logic visible_event;
        logic [3:0] source_phase;
        #1;
        token_arm = 1'b0;
        token_consume = 1'b0;
        expected_visible_event = 1'b0;
        if (reset || !ENABLE) begin
            previous_state = state;
            previous_phase = phase;
            sequence_phase = 4'd1;
            phase_event_source = 0;
            expected_current_phase = 4'd1;
            expected_next_phase = 4'd2;
            token_valid = 1'b0;
            token_age = 0;
            token_arms = 0;
            token_consumes = 0;
            visible_events = 0;
            failures = 0;
            first_failure_code = P_NONE;
            last_visible_consumed = 1'b0;
        end else begin
            source_phase = mapped_phase(state);
            source_event = state != previous_state && source_phase != 0;
            visible_event = phase != previous_phase && phase != 0;

            if (token_valid) token_age = token_age + 1;

            if (source_event) begin
                phase_event_source = state;
                expected_current_phase = sequence_phase;
                expected_next_phase = sequence_phase == 8 ? 1 :
                                      sequence_phase + 1'b1;
                expected_visible_event = 1'b1;
                token_arm = 1'b1;
                token_arms = token_arms + 1;
                if (token_valid) phase_fail(P_DUPLICATE_TOKEN);
                if (source_phase != sequence_phase) begin
                    if (source_phase < sequence_phase)
                        phase_fail(P_PHASE_REPEAT);
                    else
                        phase_fail(P_PHASE_SKIP);
                end
                token_state = state;
                token_phase = source_phase;
                token_program_active = expected_active(state);
                token_program_id = mapped_program(state);
                token_valid = 1'b1;
                token_age = 0;
                last_visible_consumed = 1'b0;
            end

            if (visible_event) begin
                visible_events = visible_events + 1;
                if (!token_valid) begin
                    if (last_visible_consumed)
                        phase_fail(P_DUPLICATE_VISIBLE);
                    else
                        phase_fail(P_UNEXPECTED_VISIBLE);
                end else begin
                    if (token_age != 0) phase_fail(P_LATE_TOKEN);
                    if (phase != token_phase) phase_fail(P_WRONG_PHASE);
                    if (state != token_state) phase_fail(P_WRONG_STATE);
                    if (program_active != token_program_active ||
                        program_id != token_program_id)
                        phase_fail(P_WRONG_PROGRAM);
                    token_consume = 1'b1;
                    token_consumes = token_consumes + 1;
                    token_valid = 1'b0;
                    sequence_phase = token_phase == 8 ? 1 :
                                     token_phase + 1'b1;
                    expected_current_phase = sequence_phase;
                    expected_next_phase = sequence_phase == 8 ? 1 :
                                          sequence_phase + 1'b1;
                    last_visible_consumed = 1'b1;
                    $display("GATEE_P_EVENT source=%0d phase=%0d program=%0d/%0d arm=%0d consume=%0d",
                        token_state, token_phase, program_active, program_id,
                        token_arms, token_consumes);
                end
            end

            if (flush && token_valid) phase_fail(P_TOKEN_MISSING);
            previous_state = state;
            previous_phase = phase;
        end
    end
endmodule

module gatee_restart_ownership_monitor #(
    parameter integer ENABLE = 1,
    parameter integer FATAL_ON_ERROR = 0
) (
    input  logic        clk,
    input  logic        reset,
    input  logic [6:0]  state,
    input  logic [3:0]  phase,
    input  logic        zero_wait,
    input  logic [31:0] transition_completes,
    input  logic [15:0] restart_count,
    input  logic        program_active,
    input  logic [4:0]  program_id,
    input  logic        restart_setup_window,
    output logic [15:0] restart_baseline,
    output logic        restart_seen_in_transition,
    output logic [2:0]  restart_owner,
    output logic [15:0] restart_delta,
    output integer      transition_id,
    output integer      legal_restart_count,
    output logic        post_restart_completion_seen,
    output integer      failures,
    output logic [7:0]  first_failure_code
);
    localparam logic [7:0] R_NONE              = 8'd0;
    localparam logic [7:0] R_UNEXPECTED        = 8'd1;
    localparam logic [7:0] R_WRONG_TARGET      = 8'd2;
    localparam logic [7:0] R_WRONG_PROGRAM     = 8'd3;
    localparam logic [7:0] R_DUPLICATE         = 8'd4;
    localparam logic [7:0] R_LATE              = 8'd5;
    localparam logic [7:0] R_OUTSIDE_SETUP     = 8'd6;
    localparam logic [7:0] R_EDGE_DROP         = 8'd7;
    localparam logic [7:0] R_ROLLBACK          = 8'd8;
    localparam logic [2:0] O_NONE  = 3'd0;
    localparam logic [2:0] O_OLD   = 3'd1;
    localparam logic [2:0] O_SETUP = 3'd3;

    logic [6:0] previous_state;
    logic previous_zero_wait;
    logic [31:0] previous_completes;
    logic [15:0] previous_restart_count;
    logic transition_active;
    integer cycle_count;
    integer last_restart_cycle;

    task automatic restart_fail(input logic [7:0] code);
        begin
            if (first_failure_code == R_NONE) begin
                first_failure_code = code;
                failures = failures + 1;
                $display("GATEE_R_FAIL code=%0d state=%0d phase=%0d restart=%0d baseline=%0d transition=%0d",
                    code, state, phase, restart_count,
                    restart_baseline, transition_id);
                if (FATAL_ON_ERROR) $fatal(1, "Gate E restart ownership failure %0d", code);
            end
        end
    endtask

    always @(posedge clk) begin : restart_contract
        logic raw_edge;
        logic completion_edge;
        logic [16:0] unsigned_step;
        #1;
        if (reset || !ENABLE) begin
            previous_state = state;
            previous_zero_wait = zero_wait;
            previous_completes = transition_completes;
            previous_restart_count = restart_count;
            restart_baseline = restart_count;
            restart_seen_in_transition = 1'b0;
            restart_owner = O_NONE;
            restart_delta = 0;
            transition_id = 0;
            legal_restart_count = 0;
            post_restart_completion_seen = 1'b0;
            failures = 0;
            first_failure_code = R_NONE;
            transition_active = 1'b0;
            cycle_count = 0;
            last_restart_cycle = -100;
        end else begin
            cycle_count = cycle_count + 1;
            raw_edge = restart_count != previous_restart_count;
            completion_edge = transition_completes != previous_completes;
            unsigned_step = {1'b0,restart_count} -
                            {1'b0,previous_restart_count};

            if (restart_count < previous_restart_count)
                restart_fail(R_ROLLBACK);
            else if (raw_edge && unsigned_step != 1)
                restart_fail(R_EDGE_DROP);

            if (zero_wait && !previous_zero_wait) begin
                transition_id = transition_id + 1;
                transition_active = 1'b1;
                restart_baseline = restart_count;
                restart_delta = 0;
                restart_seen_in_transition = 1'b0;
                restart_owner = O_OLD;
                $display("GATEE_R_ENTRY id=%0d state=%0d restart_baseline=%0d",
                    transition_id, state, restart_baseline);
            end

            if (raw_edge) begin
                if (cycle_count == last_restart_cycle + 1)
                    restart_fail(R_DUPLICATE);
                else if (transition_active) begin
                    restart_seen_in_transition = 1'b1;
                    restart_owner = O_OLD;
                    restart_fail(R_UNEXPECTED);
                end else if (previous_state == 7'd71) begin
                    if (state != 7'd72 || phase != 0)
                        restart_fail(R_WRONG_TARGET);
                    else if (!program_active || program_id != 0)
                        restart_fail(R_WRONG_PROGRAM);
                    else if (!restart_setup_window)
                        restart_fail(R_OUTSIDE_SETUP);
                    else begin
                        restart_owner = O_SETUP;
                        legal_restart_count = legal_restart_count + 1;
                        $display("GATEE_R_EVENT owner=O-SETUP source=71 target=72 phase=0 program=0 restart=%0d",
                            restart_count);
                    end
                end else begin
                    restart_fail(R_LATE);
                end
                last_restart_cycle = cycle_count;
            end

            if (transition_active)
                restart_delta = restart_count - restart_baseline;

            if (completion_edge) begin
                if (restart_count != restart_baseline)
                    restart_fail(R_UNEXPECTED);
                if (legal_restart_count > 0 && state == 7'd10 && !raw_edge)
                    post_restart_completion_seen = 1'b1;
                transition_active = 1'b0;
                restart_owner = O_NONE;
                $display("GATEE_R_COMPLETE id=%0d state=%0d raw=%0d delta=%0d baseline=%0d restart=%0d",
                    transition_id, state, raw_edge, restart_delta,
                    restart_baseline, restart_count);
            end

            previous_state = state;
            previous_zero_wait = zero_wait;
            previous_completes = transition_completes;
            previous_restart_count = restart_count;
        end
    end
endmodule

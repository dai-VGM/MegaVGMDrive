`timescale 1ns/1ps

// Passive POST-NBA adapter.  It classifies actual sequencer transitions into
// normalized semantic tuples; it does not contain expected ordering state.
module semantic_timeline_adapter (
    input  logic        clk,
    input  logic        reset,
    input  logic        loop_epoch,
    input  logic [6:0]  state,
    input  logic [3:0]  phase,
    input  logic [2:0]  raw_attempt,
    input  logic        program_active,
    input  logic [4:0]  program_id,
    input  logic        external_mute,
    output logic        event_valid,
    output logic        event_loop,
    output logic [3:0]  event_family,
    output logic [2:0]  event_attempt,
    output logic [1:0]  event_kind,
    output logic [6:0]  event_state,
    output logic [3:0]  event_phase,
    output logic        event_program_active,
    output logic [4:0]  event_program,
    output integer      start_events,
    output integer      stop_events,
    output integer      zero_events,
    output integer      failures,
    output logic [7:0]  first_failure_code
);
    import semantic_timeline_authority_pkg::*;

    logic previous_mute;
    logic [6:0] previous_state;
    integer family_i;
    integer attempt_i;
    integer match_count;
    logic [3:0] classified_family;
    logic [2:0] classified_attempt;

    wire [21:0] qualifier_known_vector = {
        loop_epoch, state, phase, raw_attempt,
        program_active, program_id, external_mute
    };

    function automatic logic [2:0] normalize_attempt(
        input logic [3:0] family,
        input logic [2:0] attempt
    );
        begin
            case (family)
                F_FM, F_SSG: normalize_attempt = 3'd0;
                F_RIGHT: normalize_attempt = attempt - 3'd3;
                default: normalize_attempt = attempt;
            endcase
        end
    endfunction

    // Z-series seam: only the selected single-attempt family uses the same
    // semantic normalization already used by START/STOP.  Expanded families
    // retain the frozen expected_raw_attempt comparison byte-for-byte.
    function automatic logic zero_attempt_matches(
        input logic [3:0] family,
        input logic [2:0] semantic_attempt,
        input logic [2:0] raw
    );
        begin
            if (family == F_FM)
                zero_attempt_matches =
                    normalize_attempt(family, raw) == semantic_attempt;
            else
                zero_attempt_matches = raw == expected_raw_attempt(
                    family, semantic_attempt, K_ZERO);
        end
    endfunction

    task automatic adapter_failure(input logic [7:0] code);
        begin
            failures = failures + 1;
            if (first_failure_code == 0)
                first_failure_code = code;
        end
    endtask

    task automatic publish_event(
        input logic [1:0] kind,
        input logic [3:0] family,
        input logic [2:0] attempt
    );
        begin
            event_valid = 1'b1;
            event_loop = loop_epoch;
            event_family = family;
            event_attempt = attempt;
            event_kind = kind;
            event_state = state;
            event_phase = phase;
            event_program_active = program_active;
            event_program = program_id;
        end
    endtask

    always @(posedge clk) begin
        #3;
        event_valid = 1'b0;
        if (reset) begin
            previous_mute = external_mute;
            previous_state = state;
            event_loop = 1'b0;
            event_family = 4'hf;
            event_attempt = 3'h7;
            event_kind = 2'h3;
            event_state = 7'h7f;
            event_phase = 4'hf;
            event_program_active = 1'b0;
            event_program = 5'h1f;
            start_events = 0;
            stop_events = 0;
            zero_events = 0;
            failures = 0;
            first_failure_code = 8'd0;
        end else begin
            if ($isunknown(qualifier_known_vector)) begin
                adapter_failure(8'd1);
            end else if (!external_mute && previous_mute) begin
                match_count = 0;
                classified_family = 4'hf;
                for (family_i = 0; family_i < 9; family_i = family_i + 1) begin
                    if (state == start_state(family_i[3:0])) begin
                        match_count = match_count + 1;
                        classified_family = family_i[3:0];
                    end
                end
                if (match_count != 1) begin
                    adapter_failure(8'd2);
                end else begin
                    classified_attempt = normalize_attempt(
                        classified_family, raw_attempt);
                    publish_event(K_START, classified_family,
                                  classified_attempt);
                    start_events = start_events + 1;
                end
            end else if (state != previous_state) begin
                match_count = 0;
                classified_family = 4'hf;
                for (family_i = 0; family_i < 9; family_i = family_i + 1) begin
                    if (state == stop_state(family_i[3:0])) begin
                        match_count = match_count + 1;
                        classified_family = family_i[3:0];
                    end
                end
                if (match_count == 1) begin
                    classified_attempt = normalize_attempt(
                        classified_family, raw_attempt);
                    publish_event(K_STOP, classified_family,
                                  classified_attempt);
                    stop_events = stop_events + 1;
                end
            end

            if (external_mute && !previous_mute) begin
                if (event_valid) begin
                    adapter_failure(8'd5);
                end else begin
                    match_count = 0;
                    classified_family = 4'hf;
                    classified_attempt = 3'h7;
                    for (family_i = 0; family_i < 9;
                         family_i = family_i + 1) begin
                        for (attempt_i = 0;
                             attempt_i < family_attempt_count(family_i[3:0]);
                             attempt_i = attempt_i + 1) begin
                            if (state == zero_post_state(
                                    family_i[3:0], attempt_i[2:0]) &&
                                zero_attempt_matches(
                                    family_i[3:0], attempt_i[2:0],
                                    raw_attempt)) begin
                                match_count = match_count + 1;
                                classified_family = family_i[3:0];
                                classified_attempt = attempt_i[2:0];
                            end
                        end
                    end
                    if (match_count != 1) begin
                        adapter_failure(8'd4);
                    end else begin
                        publish_event(K_ZERO, classified_family,
                                      classified_attempt);
                        zero_events = zero_events + 1;
                    end
                end
            end
            previous_mute = external_mute;
            previous_state = state;
        end
    end
endmodule

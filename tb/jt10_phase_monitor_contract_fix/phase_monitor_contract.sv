`timescale 1ns/1ps

// Versioned, input-only reconstruction of the frozen HW0 phase monitor.
// P0 preserves the legacy token and terminal cardinality exactly. P1 repairs
// only the visible-phase token; P2 repairs only terminal two-loop cardinality;
// P3 applies both independent repairs.
module jt10_phase_monitor_contract #(
    parameter bit CORRECT_TOKEN = 1'b0,
    parameter bit CORRECT_TERMINAL = 1'b0
) (
    input  logic       clk,
    input  logic       reset,
    input  logic [3:0] phase,
    input  logic       terminal,
    output integer     failures,
    output integer     phase_events,
    output integer     order_errors,
    output integer     missing_errors,
    output integer     duplicate_errors,
    output integer     third_loop_errors,
    output integer     visit_errors,
    output logic       terminal_checked,
    output logic       terminal_pass
);
    logic [3:0] last_phase;
    integer visits [1:8];
    integer i;

    function automatic [3:0] expected_phase(input integer index);
        begin
            if (CORRECT_TOKEN) begin
                case (index % 8)
                    0: expected_phase = 1;
                    1: expected_phase = 2;
                    2: expected_phase = 3;
                    3: expected_phase = 4;
                    4: expected_phase = 5;
                    5: expected_phase = 6;
                    6: expected_phase = 7;
                    default: expected_phase = 8;
                endcase
            end else begin
                case (index % 8)
                    0: expected_phase = 1;
                    1: expected_phase = 2;
                    2: expected_phase = 3;
                    3: expected_phase = 4;
                    4: expected_phase = 5;
                    5, 6: expected_phase = 6;
                    default: expected_phase = 7;
                endcase
            end
        end
    endfunction

    task automatic fail_order;
        begin
            failures = failures + 1;
            order_errors = order_errors + 1;
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            failures = 0;
            phase_events = 0;
            order_errors = 0;
            missing_errors = 0;
            duplicate_errors = 0;
            third_loop_errors = 0;
            visit_errors = 0;
            terminal_checked = 1'b0;
            terminal_pass = 1'b0;
            last_phase = 0;
            for (i = 1; i <= 8; i = i + 1) visits[i] = 0;
        end else begin
            if (phase != last_phase) begin
                if (phase != 0) begin
                    if (phase_events >= 16) begin
                        failures = failures + 1;
                        third_loop_errors = third_loop_errors + 1;
                    end
                    if (phase != expected_phase(phase_events))
                        fail_order();
                    phase_events = phase_events + 1;
                    if (phase >= 1 && phase <= 8)
                        visits[phase] = visits[phase] + 1;
                    else begin
                        failures = failures + 1;
                        order_errors = order_errors + 1;
                    end
                end
                last_phase = phase;
            end

            if (terminal && !terminal_checked) begin
                terminal_checked = 1'b1;
                if (CORRECT_TERMINAL) begin
                    if (phase_events != 16) begin
                        failures = failures + 1;
                        missing_errors = missing_errors + 1;
                    end
                    for (i = 1; i <= 8; i = i + 1)
                        if (visits[i] != 2) begin
                            failures = failures + 1;
                            visit_errors = visit_errors + 1;
                        end
                end else begin
                    if (phase_events != 17) begin
                        failures = failures + 1;
                        missing_errors = missing_errors + 1;
                    end
                    for (i = 1; i <= 7; i = i + 1)
                        if (visits[i] != (i == 1 ? 3 : i == 6 ? 4 : 2)) begin
                            failures = failures + 1;
                            visit_errors = visit_errors + 1;
                        end
                end
                terminal_pass = (failures == 0);
            end
        end
    end
endmodule

`timescale 1ns/1ps

// Versioned L-B monitors.  B0/B1 consume only the historical raw chon edge;
// B2 consumes an explicit tuple; B3 consumes the already-validated adapter
// START token and deliberately does not classify raw sequencer state.
module natural_start_legacy_monitor #(
    parameter integer LIMIT = 4
) (
    input logic clk, input logic reset, input logic phase7,
    input logic b_chon,
    output integer failures, output integer starts
);
    logic previous_b_chon;
    always @(posedge clk) begin
        if (reset) begin
            previous_b_chon = 0; starts = -1; failures = 0;
        end else begin
            if (phase7 && b_chon && !previous_b_chon) begin
                starts = starts + 1;
                if (starts >= LIMIT) failures = failures + 1;
            end
            previous_b_chon = b_chon;
        end
    end
endmodule

module natural_start_tuple_monitor (
    input logic clk, input logic reset, input logic terminal,
    input logic token_valid, input logic token_loop,
    input logic [3:0] token_family, input logic [2:0] token_attempt,
    input logic [1:0] token_kind,
    output integer failures, output integer starts,
    output integer duplicate_errors, output integer missing_errors,
    output integer order_errors, output integer third_loop_errors,
    output integer n1_starts, output integer n2_starts,
    output integer loop0_starts, output integer loop1_starts,
    output logic complete
);
    import semantic_timeline_authority_pkg::*;
    logic seen [0:1][0:1][0:2];
    integer i,j,k;
    function automatic integer family_slot(input logic [3:0] family);
        if (family == F_NATURAL1) family_slot = 0;
        else if (family == F_NATURAL2) family_slot = 1;
        else family_slot = -1;
    endfunction
    task automatic bad_order; begin failures=failures+1; order_errors=order_errors+1; end endtask
    always @(posedge clk) begin
        if (reset) begin
            failures=0; starts=0; duplicate_errors=0; missing_errors=0;
            order_errors=0; third_loop_errors=0; n1_starts=0; n2_starts=0;
            loop0_starts=0; loop1_starts=0; complete=0;
            for (i=0;i<2;i=i+1) for(j=0;j<2;j=j+1) for(k=0;k<3;k=k+1) seen[i][j][k]=0;
        end else begin
            if (token_valid && token_kind == K_START &&
                (token_family == F_NATURAL1 || token_family == F_NATURAL2)) begin
                if (token_loop > 1) begin
                    failures=failures+1; third_loop_errors=third_loop_errors+1;
                end else if (token_attempt > 2) begin
                    bad_order();
                end else if (seen[token_loop][family_slot(token_family)][token_attempt]) begin
                    failures=failures+1; duplicate_errors=duplicate_errors+1;
                end else begin
                    seen[token_loop][family_slot(token_family)][token_attempt]=1;
                    starts=starts+1;
                    if (token_family == F_NATURAL1) n1_starts=n1_starts+1;
                    else n2_starts=n2_starts+1;
                    if (!token_loop) loop0_starts=loop0_starts+1;
                    else loop1_starts=loop1_starts+1;
                    if (starts == 12) complete=1;
                end
            end
            if (terminal && !complete) begin
                failures=failures+1; missing_errors=missing_errors+1;
            end
        end
    end
endmodule

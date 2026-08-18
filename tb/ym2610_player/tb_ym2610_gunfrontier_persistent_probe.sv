`timescale 1ns/1ps

module tb_ym2610_gunfrontier_persistent_probe;
    logic fatal_active, raw_valid, raw_current, diag_valid, diag_current, profile_fatal;
    logic [7:0] reject_code;
    logic [19:0] raw_addr, diag_addr;

    ym2610_gunfrontier_reject_probe dut (
        .fatal_active(fatal_active), .reject_code(reject_code),
        .range_fault_valid(raw_valid), .range_fault_addr(raw_addr),
        .range_fault_current(raw_current),
        .diag_range_fault_valid(diag_valid), .diag_range_fault_addr(diag_addr),
        .diag_range_fault_current(diag_current), .profile_fatal(profile_fatal)
    );

    function automatic logic expected_probe(
        input logic active, input logic [7:0] code, input logic valid,
        input logic [19:0] addr, input logic current
    );
`ifdef YM2610_GF_PERSISTENT_VALID_PROBE
        expected_probe = active && code == 8'h0b && valid;
`elsif YM2610_GF_PERSISTENT_RG1_PROBE
        expected_probe = active && code == 8'h0b && valid &&
                         addr == 20'h07600 && current;
`else
        expected_probe = 1'bx;
`endif
    endfunction

    task automatic check(input logic active, input logic [7:0] code,
                         input logic valid, input logic [19:0] addr,
                         input logic current);
        logic expected;
        begin
            fatal_active = active;
            reject_code = code;
            raw_valid = 1'b0;
            raw_addr = 20'd0;
            raw_current = 1'b0;
            diag_valid = valid;
            diag_addr = addr;
            diag_current = current;
            #1;
            expected = expected_probe(active, code, valid, addr, current);
            if (profile_fatal !== expected)
                $fatal(1, "persistent probe mismatch");
        end
    endtask

    initial begin
        check(1'b1, 8'h0b, 1'b1, 20'h07600, 1'b1);
        check(1'b1, 8'h0b, 1'b0, 20'h07600, 1'b1);
        check(1'b1, 8'h0c, 1'b1, 20'h07600, 1'b1);
        check(1'b1, 8'h0b, 1'b1, 20'h07601, 1'b1);
        check(1'b1, 8'h0b, 1'b1, 20'h07600, 1'b0);
        $display("PASS: persistent range-fault probe");
        $finish;
    end
endmodule

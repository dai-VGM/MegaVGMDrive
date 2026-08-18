`timescale 1ns/1ps

module tb_ym2610_gunfrontier_rg1_decomp_probe;
    logic fatal_active, range_fault_valid, range_fault_current, profile_fatal;
    logic [7:0] reject_code;
    logic [19:0] range_fault_addr;

    ym2610_gunfrontier_reject_probe dut (
        .fatal_active(fatal_active), .reject_code(reject_code),
        .range_fault_valid(range_fault_valid), .range_fault_addr(range_fault_addr),
        .range_fault_current(range_fault_current), .profile_fatal(profile_fatal)
    );

    function automatic logic expected_probe(
        input logic active, input logic [7:0] code, input logic valid,
        input logic [19:0] addr, input logic current
    );
`ifdef YM2610_GF_RG1_CURRENT_PROBE
        expected_probe = active && code == 8'h0b && valid && current;
`elsif YM2610_GF_RG1_ADDR_PROBE
        expected_probe = active && code == 8'h0b && valid && addr == 20'h07600;
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
            range_fault_valid = valid;
            range_fault_addr = addr;
            range_fault_current = current;
            #1;
            expected = expected_probe(active, code, valid, addr, current);
            if (profile_fatal !== expected)
                $fatal(1, "decomp mismatch code=%02h addr=%05h current=%0d got=%0d expected=%0d",
                       code, addr, current, profile_fatal, expected);
        end
    endtask

    initial begin
        check(1'b1, 8'h0b, 1'b1, 20'h07600, 1'b1);
        check(1'b1, 8'h0b, 1'b1, 20'h07601, 1'b1);
        check(1'b1, 8'h0b, 1'b1, 20'h07600, 1'b0);
        check(1'b1, 8'h0c, 1'b1, 20'h07600, 1'b1);
        check(1'b0, 8'h0b, 1'b1, 20'h07600, 1'b1);
        $display("PASS: YM2610 Gun Frontier RG1 decomposition probe");
        $finish;
    end
endmodule

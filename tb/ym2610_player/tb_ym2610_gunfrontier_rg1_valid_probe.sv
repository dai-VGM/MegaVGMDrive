`timescale 1ns/1ps

module tb_ym2610_gunfrontier_rg1_valid_probe;
    logic fatal_active, range_fault_valid, range_fault_current, profile_fatal;
    logic [7:0] reject_code;
    logic [19:0] range_fault_addr;

    ym2610_gunfrontier_reject_probe dut (
        .fatal_active(fatal_active), .reject_code(reject_code),
        .range_fault_valid(range_fault_valid), .range_fault_addr(range_fault_addr),
        .range_fault_current(range_fault_current), .profile_fatal(profile_fatal)
    );

    task automatic check(input logic active, input logic [7:0] code,
                         input logic valid, input logic expected);
        begin
            fatal_active = active;
            reject_code = code;
            range_fault_valid = valid;
            range_fault_addr = 20'd0;
            range_fault_current = 1'b0;
            #1;
            if (profile_fatal !== expected)
                $fatal(1, "valid probe mismatch active=%0d code=%02h valid=%0d got=%0d expected=%0d",
                       active, code, valid, profile_fatal, expected);
        end
    endtask

    initial begin
        check(1'b1, 8'h0b, 1'b1, 1'b1);
        check(1'b1, 8'h0b, 1'b0, 1'b0);
        check(1'b1, 8'h0c, 1'b1, 1'b0);
        check(1'b0, 8'h0b, 1'b1, 1'b0);
        $display("PASS: YM2610 Gun Frontier RG1 valid probe");
        $finish;
    end
endmodule

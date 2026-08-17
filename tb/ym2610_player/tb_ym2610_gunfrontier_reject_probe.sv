`timescale 1ns/1ps

module tb_ym2610_gunfrontier_reject_probe;
    logic fatal_active;
    logic [7:0] reject_code;
    logic profile_fatal;
    logic expected;

    ym2610_gunfrontier_reject_probe dut (
        .fatal_active(fatal_active), .reject_code(reject_code),
        .profile_fatal(profile_fatal)
    );

    function automatic logic expected_probe(
        input logic active, input logic [7:0] code
    );
`ifdef YM2610_GF_REJECT_PROBE_BIT0
        expected_probe = active && code[0];
`elsif YM2610_GF_REJECT_PROBE_BIT1
        expected_probe = active && code[1];
`elsif YM2610_GF_REJECT_PROBE_BIT2
        expected_probe = active && code[2];
`else
        expected_probe = active;
`endif
    endfunction

    task automatic check_code(input logic active, input logic [7:0] code);
        begin
            fatal_active = active;
            reject_code = code;
            #1;
            expected = expected_probe(active, code);
            if (profile_fatal !== expected)
                $fatal(1, "probe mismatch active=%0d code=%02h got=%0d expected=%0d",
                       active, code, profile_fatal, expected);
        end
    endtask

    initial begin
        check_code(1'b0, 8'h09);
        check_code(1'b0, 8'h0a);
        check_code(1'b0, 8'h0b);
        check_code(1'b0, 8'h0c);
        check_code(1'b0, 8'h0d);
        check_code(1'b0, 8'h0e);
        check_code(1'b1, 8'h09);
        check_code(1'b1, 8'h0a);
        check_code(1'b1, 8'h0b);
        check_code(1'b1, 8'h0c);
        check_code(1'b1, 8'h0d);
        check_code(1'b1, 8'h0e);
        $display("PASS: YM2610 Gun Frontier reject probe");
        $finish;
    end
endmodule

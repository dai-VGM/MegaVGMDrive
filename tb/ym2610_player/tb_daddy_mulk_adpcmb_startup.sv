`timescale 1ns/1ps

// Focused source-level reproducer for the Daddy Mulk first ADPCM-B request.
// The bad case places cen55 inside the MMR command-update lifetime.  Before
// the fix that phase requests the stale cursor before the restart branch can
// load the newly programmed start address.
module tb_daddy_mulk_adpcmb_startup;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic cen = 1'b1;
    logic cen55 = 1'b0;
    logic acmd_on_b = 1'b0;
    logic acmd_rep_b = 1'b0;
    logic acmd_rst_b = 1'b0;
    logic acmd_up_b = 1'b0;
    logic [1:0] alr_b = 2'b11;
    logic [15:0] astart_b = 16'h03ae;
    logic [15:0] aend_b = 16'h0473;
    logic [15:0] adeltan_b = 16'h556a;
    logic [7:0] aeg_b = 8'h78;
    logic [7:0] data = 8'h55;
    logic clr_flag = 1'b0;
    wire flag;
    wire [23:0] addr;
    wire roe_n;
    wire signed [15:0] pcm_l;
    wire signed [15:0] pcm_r;

    integer failures = 0;
    integer phase;

    always #5 clk = ~clk;

    jt10_adpcm_drvB dut (
        .rst_n(rst_n), .clk(clk), .cen(cen), .cen55(cen55),
        .acmd_on_b(acmd_on_b), .acmd_rep_b(acmd_rep_b),
        .acmd_rst_b(acmd_rst_b), .acmd_up_b(acmd_up_b),
        .alr_b(alr_b), .astart_b(astart_b), .aend_b(aend_b),
        .adeltan_b(adeltan_b), .aeg_b(aeg_b), .flag(flag),
        .clr_flag(clr_flag), .addr(addr), .data(data), .roe_n(roe_n),
        .pcm55_l(pcm_l), .pcm55_r(pcm_r)
    );

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            failures = failures + 1;
            $display("DADDY_STARTUP_FAIL %s", message);
        end
    endtask

    task automatic reset_case;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            cen55 = 1'b0;
            acmd_on_b = 1'b0;
            acmd_up_b = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic accept_start;
        begin
            @(negedge clk);
            acmd_on_b = 1'b1;
            acmd_up_b = 1'b1;
            @(posedge clk);
            #1;
            check(dut.restart && dut.adv,
                  "accepted START did not arm restart/advance");
        end
    endtask

    task automatic pulse_cen55;
        begin
            @(negedge clk);
            cen55 = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            cen55 = 1'b0;
        end
    endtask

    initial begin
        // Successful ordering: the one-shot command update has cleared before
        // the 55 kHz restart event.
        reset_case();
        accept_start();
        @(negedge clk);
        acmd_up_b = 1'b0;
        pulse_cen55();
        check(addr == 24'h03ae00, "good phase loaded the wrong start");
        check(!roe_n, "good phase omitted the first ROM request");

        // Failing production ordering: cen55 is published while acmd_up_b is
        // still pending.  A legal implementation must not request the old
        // address; it waits for the first restart event after update clears.
        for (phase = 0; phase < 16; phase = phase + 1) begin
            reset_case();
            accept_start();
            repeat (phase) @(posedge clk);
            pulse_cen55();
`ifdef EXPECT_DADDY_LEGACY_FAILURE
            check(addr == 24'h000000 && !roe_n,
                  "legacy bad phase did not reproduce stale address-zero read");
`else
            check(roe_n, "bad phase exposed a ROM request before start reload");
`endif
            @(negedge clk);
            acmd_up_b = 1'b0;
            repeat (15 - phase) @(posedge clk);
            pulse_cen55();
            check(addr == 24'h03ae00,
                  "bad phase recovery loaded wrong start");
            check(!roe_n,
                  "bad phase recovery omitted first legal request");
        end

        if (failures != 0)
            $fatal(1, "Daddy Mulk startup failures=%0d", failures);
`ifdef EXPECT_DADDY_LEGACY_FAILURE
        $display("DADDY_MULK_STARTUP legacy_bad_phase=REPRODUCED first_addr=000000 result=PASS");
`else
        $display("DADDY_MULK_STARTUP good_phase=PASS phase_sweep=16 bad_phase=PASS first_addr=03ae00 result=PASS");
`endif
        $finish;
    end
endmodule

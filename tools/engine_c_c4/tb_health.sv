`timescale 1ns/1ps
module tb_health;
    logic clk=0,reset=1,new_session=0,work_pending=0,busy=0,rd=0,valid=0;
    logic [7:0] burst=1;
    logic [28:0] address=29'h06000000;
    wire fatal;
    always #5 clk=~clk;
    c4_ddr_health #(.RESPONSE_CYCLES(8),.DESCRIPTOR_CYCLES(16),.BUSY_CYCLES(16)) dut(.*);
    task tick; @(posedge clk);#1;@(negedge clk);endtask
    task clear;reset=1;tick();reset=0;tick();endtask
    initial begin
        clear();work_pending=1;
        // Each timely burst beat refreshes age; no timeout for a legal burst.
        burst=4;rd=1;tick();rd=0;
        repeat(4) begin repeat(7) begin tick();assert(!fatal) else $fatal;end
            valid=1;tick();valid=0;end
        repeat(20) tick();assert(!fatal && dut.remaining==0) else $fatal;
        // No fabricated data, timeout stays sticky across a late response.
        rd=1;burst=1;tick();rd=0;repeat(7) tick();assert(!fatal) else $fatal;
        tick();assert(fatal) else $fatal;valid=1;tick();valid=0;
        new_session=1;tick();new_session=0;assert(!fatal) else $fatal;
        address=29'h06100000;rd=1;tick();rd=0;
        repeat(15) begin tick();assert(!fatal) else $fatal;end
        tick();assert(fatal) else $fatal;clear();
        // No idle-OSD watchdog and no user/host pacing timeout.
        work_pending=0;busy=1;repeat(30) tick();assert(!fatal) else $fatal;
        work_pending=1;repeat(15) tick();assert(!fatal) else $fatal;
        tick();assert(fatal) else $fatal;
        clear();assert(!fatal) else $fatal;
        $display("DDR health: burst progress, missing beat, late drain, session clear, idle exclusion, BUSY timeout, Stop reset PASS");
        $finish;
    end
endmodule

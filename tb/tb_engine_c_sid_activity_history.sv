`timescale 1ns/1ps
module tb_engine_c_sid_activity_history;
    logic clk=0,reset=1,vblank_start=0,reg_write=0;
    logic [4:0] reg_addr=0;
    logic [23:0] history;
    sid_activity_history dut(.*);
    always #5 clk=~clk;

    task tick; begin @(posedge clk); #1; end endtask
    task write_reg(input [4:0] addr); begin reg_addr=addr;reg_write=1;tick();reg_write=0;end endtask
    task frame; begin vblank_start=1;tick();vblank_start=0;tick();end endtask
    task check_history(input [23:0] value,input [255:0] name); begin
        if(history!==value) begin $display("FAIL %s got=%h want=%h",name,history,value);$fatal;end
    end endtask

    initial begin
        repeat(2) tick(); reset=0; tick(); check_history(0,"reset");
        write_reg(5'h00); frame(); if(history[5:0]!==6'b000001 || history[23:6]!==0)$fatal(1,"voice1 map");
        write_reg(5'h07); write_reg(5'h0e); write_reg(5'h18); frame();
        if(history[11:6]!==6'b000001 || history[17:12]!==6'b000001 || history[23:18]!==6'b000001)$fatal(1,"simultaneous frame lanes");
        write_reg(5'h06); write_reg(5'h0d); write_reg(5'h14); frame();
        if(history[5:0]!==6'b000101 || history[11:6]!==6'b000011 || history[17:12]!==6'b000011)$fatal(1,"range edges");
        reg_addr=5'h18;reg_write=1;vblank_start=1;tick();reg_write=0;vblank_start=0;tick();
        if(history[23:18]!==6'b000101)$fatal(1,"vblank boundary write lost");
        repeat(6) frame(); check_history(0,"six frame decay");
        write_reg(5'h00);frame(); reset=1;tick();reset=0;tick();check_history(0,"new session clear");
        write_reg(5'h15);write_reg(5'h17);frame();check_history(0,"unmapped registers");
        $display("ENGINE_C_SID_ACTIVITY_HISTORY_PASS");
        $finish;
    end
endmodule

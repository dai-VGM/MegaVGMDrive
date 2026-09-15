`timescale 1ns/1ps
module tb_scheduler_ticks;
    logic clk=0,reset=1,enable=0,mem_valid=0;logic [31:0] num=985248;
    wire mem_req,ce,done,fatal;wire [3:0] mem_addr;wire [31:0] ticks;
    logic [78:0] record;
    always #1 clk=~clk;
    sid_native_scheduler #(.SYS_HZ(2000000),.RW(4)) dut(
        .clk(clk),.reset(reset),.enable(enable),.halt(1'b0),.halt_loop(1'b0),
        .loop_valid(1'b0),.loop_start_cycle(64'd0),.clock_num(num),.clock_den(32'd1),
        .mem_req(mem_req),.mem_addr(mem_addr),.mem_valid(mem_valid),.mem_data(record),
        .ce_sid(ce),.reg_write(),.reg_addr(),.reg_data(),.busy(),.done(done),.fatal(fatal),
        .native_cycle(),.launched(),.loop_entry_pulse(),.loop_boundary_pulse(),
        .loop_count(),.transport_ticks(ticks));
    always @(posedge clk)begin
        mem_valid<=mem_req;
        if(mem_req)record<={1'b0,1'b1,64'd1000000,13'd0};
    end
    task tick;@(posedge clk);#1;@(negedge clk);endtask
    task run(input logic [31:0] frequency,input integer expected);
        reset=1;enable=0;mem_valid=0;tick();reset=0;num=frequency;enable=1;
        while(!done&&!fatal)tick();
        assert(!fatal&&ticks==expected)else $fatal(1,"tick drift num=%0d got=%0d expected=%0d",frequency,ticks,expected);
        $display("RATIONAL TICKS num=%0d native=1000000 ticks=%0d PASS",frequency,ticks);
    endtask
    initial begin
        run(985248,44760);
        run(1022727,43120);
        $finish;
    end
    initial begin #20000000;$fatal(1,"timeout");end
endmodule

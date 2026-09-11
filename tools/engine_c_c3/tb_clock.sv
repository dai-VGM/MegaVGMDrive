`timescale 1ns/1ps
module tb_clock;
    logic clk=0,reset=1,enable=0;
    always #25 clk=~clk;
    logic [31:0] clock_num=0,clock_den=0;
    wire req,ce_sid,reg_write,busy,done,fatal,launched;
    wire [11:0] addr;
    logic valid=0;
    wire [63:0] native_cycle;
    sid_native_scheduler dut(
        .clk(clk),.reset(reset),.enable(enable),.clock_num(clock_num),.clock_den(clock_den),
        .mem_req(req),.mem_addr(addr),.mem_valid(valid),
        .mem_data({1'b1,64'd1000000000,13'd0}),.ce_sid(ce_sid),.reg_write(reg_write),
        .reg_addr(),.reg_data(),.busy(busy),.done(done),.fatal(fatal),
        .native_cycle(native_cycle),.launched(launched));
    always @(posedge clk) valid<=!reset && req;
    task tick; @(posedge clk);#1;@(negedge clk);endtask
    task check_clock(input logic [31:0] num,den);
        logic sampled_ce;
        logic [63:0] count,period;
        reset=1;enable=0;tick();reset=0;
        clock_num=num;clock_den=den;enable=1;
        while(!launched) tick();
        count=0;period=64'd20000000*64'(den);
        // Input bus no longer supplies a valid clock: launched config must hold.
        clock_num=1;clock_den=0;
        for(integer n=1;n<=2000000;n++) begin
            sampled_ce=ce_sid;tick();
            if(sampled_ce) count=count+1;
            assert(count==(64'(n)*64'(num))/period && native_cycle==count &&
                   dut.step==num && dut.period==period && !fatal && !done && !reg_write)
                else $fatal(1,"clock count/config hold at n=%0d num=%0d den=%0d",n,num,den);
        end
        $display("CLOCK num=%0d den=%0d SYS=2000000 CE=%0d phase=%0d config held",num,den,count,dut.phase);
    endtask
    initial begin
        check_clock(985248,1);check_clock(1022727,1);
        check_clock(985248*2,2);check_clock(1022727*2,2);
        check_clock(985248*4359,4359);check_clock(1022727*4199,4199);
        $finish;
    end
endmodule

// SPDX-License-Identifier: GPL-2.0-or-later
// WRITE(n) is sampled by SID at CE edge n (n=0 is the launch edge).
// At that edge the oscillator consumes the old register, as a physical bus
// write at the end of a SID cycle does. New register is used at CE n+1.
module sid_native_scheduler #(
    parameter integer SYS_HZ=20000000, RW=12
)(
    input logic clk, reset, enable, halt,
    input logic [31:0] clock_num,clock_den,
    output logic mem_req,
    output logic [RW-1:0] mem_addr,
    input logic mem_valid,
    input logic [77:0] mem_data,
    output logic ce_sid, reg_write,
    output logic [4:0] reg_addr,
    output logic [7:0] reg_data,
    output logic busy, done, fatal,
    output logic [63:0] native_cycle,
    output logic launched
);
    logic running;
    logic [63:0] phase, period;
    logic [31:0] step;
    wire [64:0] sum = {1'b0,phase}+{33'd0,step};
    typedef enum logic[1:0] {FETCH, RECEIVE, HAVE} fetch_t;
    fetch_t fetch;
    logic [77:0] head;
    wire [63:0] due=head[76:13];
    wire launch=enable && !halt && !launched && fetch==HAVE;
    // halt terminates event consumption only after common-owner completion.
    // Free running after launch, INCLUDING EOF/fatal/halt. Never pause to catch up.
    assign ce_sid=!reset && running && sum>={1'b0,period};
    wire tick=launch || ce_sid;
    wire [63:0] target=launch ? 64'd0 : native_cycle+1;
    assign mem_req=enable && !halt && fetch==FETCH && !done && !fatal;
    assign reg_write=!reset && !halt && !done && !fatal && tick && fetch==HAVE &&
                     !head[77] && due==target;
    assign reg_addr=head[12:8];
    assign reg_data=head[7:0];
    assign busy=launched && !halt && !done && !fatal;
    always @(posedge clk) begin
        if(reset) begin
            running<=0; phase<=0; fetch<=FETCH; mem_addr<=0; head<=0;
            done<=0; fatal<=0; native_cycle<=0; launched<=0;
            step<=0;period<=0;
        end else begin
            if(running) phase<=ce_sid ? 64'(sum-{1'b0,period}) : sum[63:0];
            if(mem_req) fetch<=RECEIVE;
            if(fetch==RECEIVE && mem_valid) begin head<=mem_data; fetch<=HAVE; end
            if(launch) begin
                running<=1; launched<=1; phase<=0;
                step<=clock_num;period<=64'(SYS_HZ)*{32'd0,clock_den};
            end
            if(ce_sid && !halt && !done && !fatal) begin
                if(native_cycle==64'hffffffffffffffff) fatal<=1;
                else native_cycle<=target;
            end
            if(!halt && !done && !fatal) begin
                if(tick && (fetch!=HAVE || due<target)) fatal<=1;
                if(reg_write) begin mem_addr<=mem_addr+1'b1; fetch<=FETCH; end
                // EOF may immediately follow WRITE on the same native cycle.
                if(launched && fetch==HAVE && head[77]) begin
                    if(due==native_cycle || (ce_sid && due==target)) done<=1;
                    else if(due<native_cycle) fatal<=1;
                end
                if(launch && head[77] && due==0) done<=1;
            end
        end
    end
endmodule

// SPDX-License-Identifier: GPL-2.0-or-later
// WRITE(n) is sampled by SID at CE edge n (n=0 is the launch edge).
// At that edge the oscillator consumes the old register, as a physical bus
// write at the end of a SID cycle does. New register is used at CE n+1.
module sid_native_scheduler #(
    parameter integer SYS_HZ=20000000, RW=12
)(
    input logic clk, reset, enable, halt, halt_loop,
	input logic loop_valid,
	input logic [63:0] loop_start_cycle,
    input logic [31:0] clock_num,clock_den,
    output logic mem_req,
    output logic [RW-1:0] mem_addr,
    input logic mem_valid,
    input logic [78:0] mem_data,
    output logic ce_sid, reg_write,
    output logic [4:0] reg_addr,
    output logic [7:0] reg_data,
    output logic busy, done, fatal,
    output logic [63:0] native_cycle,
	output logic launched,
	output logic loop_entry_pulse,loop_boundary_pulse,
	output logic [31:0] loop_count,transport_ticks
);
    logic running;
    logic [63:0] phase, period;
    logic [31:0] step;
    wire [64:0] sum = {1'b0,phase}+{33'd0,step};
    typedef enum logic[1:0] {FETCH, RECEIVE, HAVE} fetch_t;
    fetch_t fetch;
	logic loop_hold,loop_entry_seen,boundary_pending;
	logic [63:0] transport_phase;
    logic [78:0] head;
    wire [63:0] due=head[76:13];
	wire head_eof=head[77],head_loop_boundary=head[78];
    wire launch=enable && !halt && !launched && fetch==HAVE;
    // halt terminates event consumption only after common-owner completion.
    // Free running after launch, INCLUDING EOF/fatal/halt. Never pause to catch up.
    assign ce_sid=!reset && running && sum>={1'b0,period};
    wire tick=launch || ce_sid;
    wire [63:0] target=launch ? 64'd0 : native_cycle+1;
    assign mem_req=enable && !halt && !loop_hold && fetch==FETCH && !done && !fatal;
	// The decoder's boundary marker is consumed during the system-clock slots
	// before its SID edge. The edge itself can therefore both publish the
	// boundary and execute a loop-start WRITE without shifting native timing.
	wire preconsume_boundary=enable && !halt && !loop_hold && fetch==HAVE &&
		head_loop_boundary && head_eof && due==target && !boundary_pending;
	assign reg_write=!reset && !halt && !done && !fatal && tick && fetch==HAVE &&
					 !(boundary_pending && halt_loop) &&
					 !head_eof && !head_loop_boundary && due==target;
    assign reg_addr=head[12:8];
    assign reg_data=head[7:0];
    assign busy=launched && !halt && !done && !fatal;
    always @(posedge clk) begin
        if(reset) begin
            running<=0; phase<=0; fetch<=FETCH; mem_addr<=0; head<=0;
			done<=0; fatal<=0; native_cycle<=0; launched<=0;loop_hold<=0;boundary_pending<=0;
			loop_entry_seen<=0;loop_entry_pulse<=0;loop_boundary_pulse<=0;loop_count<=0;
			transport_phase<=0;transport_ticks<=0;
            step<=0;period<=0;
        end else begin
			loop_entry_pulse<=0;loop_boundary_pulse<=0;
            if(running) phase<=ce_sid ? 64'(sum-{1'b0,period}) : sum[63:0];
            if(mem_req) fetch<=RECEIVE;
            if(fetch==RECEIVE && mem_valid) begin head<=mem_data; fetch<=HAVE; end
			if(preconsume_boundary) begin
				mem_addr<=mem_addr+1'b1;fetch<=FETCH;boundary_pending<=1;
			end
            if(launch) begin
                running<=1; launched<=1; phase<=0;
                step<=clock_num;period<=64'(SYS_HZ)*{32'd0,clock_den};
            end
			if(ce_sid && !halt && !done && !fatal) begin
                if(native_cycle==64'hffffffffffffffff) fatal<=1;
                else native_cycle<=target;
				if(transport_phase+64'(44100)*{32'd0,clock_den}>={32'd0,clock_num}) begin
					transport_phase<=transport_phase+64'(44100)*{32'd0,clock_den}-{32'd0,clock_num};
					if(transport_ticks!=32'hffffffff)transport_ticks<=transport_ticks+1'b1;
				end else transport_phase<=transport_phase+64'(44100)*{32'd0,clock_den};
				if(loop_valid&&!loop_entry_seen&&target==loop_start_cycle) begin
					loop_entry_seen<=1;loop_entry_pulse<=1;
				end
				if(boundary_pending) begin
					loop_boundary_pulse<=1;boundary_pending<=0;
					if(loop_count!=32'hffffffff)loop_count<=loop_count+1'b1;
					if(halt_loop)loop_hold<=1;
				end
            end
            if(!halt && !done && !fatal) begin
				if(tick && !boundary_pending && (fetch!=HAVE || due<target)) fatal<=1;
				if(tick && boundary_pending && !halt_loop && fetch!=HAVE) fatal<=1;
				if(tick && boundary_pending && !halt_loop && fetch==HAVE && due<target) fatal<=1;
                if(reg_write) begin mem_addr<=mem_addr+1'b1; fetch<=FETCH; end
                // EOF may immediately follow WRITE on the same native cycle.
				if(launched && fetch==HAVE && head_eof && !head_loop_boundary) begin
                    if(due==native_cycle || (ce_sid && due==target)) done<=1;
                    else if(due<native_cycle) fatal<=1;
                end
				if(launch && head_eof && !head_loop_boundary && due==0) done<=1;
				if(launch&&loop_valid&&loop_start_cycle==0)begin loop_entry_seen<=1;loop_entry_pulse<=1;end
            end
        end
    end
endmodule

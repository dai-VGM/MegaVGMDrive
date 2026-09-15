// SPDX-License-Identifier: GPL-2.0-or-later
`include "rtl/engine_c_c2_capacity/capacity.vh"
module engine_c_lab #(
    parameter integer AW=23, MAX_FILE_BYTES=`C2_MAX_FILE_BYTES,
    parameter integer MAX_RECORDS=((MAX_FILE_BYTES-128)/16)/2+1, SYS_HZ=20000000
)(
    input logic clk, reset, start, transport_halt,loop_halt,
    input logic [31:0] file_size,
    output logic rd_req,
    output logic [AW-1:0] rd_addr,
    input logic rd_ready, rd_valid,
    input logic [7:0] rd_data,
    output logic busy, done, fatal, loaded,
    output logic [7:0] error_code,
    output logic ce_sid, reg_write,
    output logic [4:0] reg_addr,
    output logic [7:0] reg_data,
    output logic [63:0] native_cycle,
    output logic signed [17:0] audio,
    output logic sample_valid, audio_ready,
	output logic [31:0] writes,
	output logic loop_valid,loop_entry_pulse,loop_boundary_pulse,
	output logic [31:0] loop_count,transport_ticks,
    input logic store_busy,store_valid,
    input logic [63:0] store_dout,
    output logic store_rd,store_we,
    output logic [28:0] store_addr,
    output logic [63:0] store_din,
    output logic [7:0] store_be,store_burst
);
    localparam RW=$clog2(MAX_RECORDS);
    initial begin
        // The frozen upload backend reserves eight MiB before descriptor DDR.
        if(AW!=23 || MAX_FILE_BYTES<160 || MAX_FILE_BYTES>8388608 ||
           MAX_RECORDS!=((MAX_FILE_BYTES-128)/16)/2+1)
            $fatal(1,"C2 capacity parameters exceed raw DDR or truncate records");
    end
    logic wr, parser_fatal, scheduler_fatal, launched, pipeline_running;
    logic [RW-1:0] wa, ra;
    logic [77:0] wd;
	logic [78:0] q;
    logic [RW:0] record_count;
    logic [63:0] total_cycles;
    logic [7:0] parser_error_code;
    logic req, valid,record_ready,parser_loaded,store_prepared,store_fatal;
    logic session_model;
    logic [7:0] session_timing;
    logic [31:0] session_clock_num,session_clock_den;
    logic use_v2,v1_start,v2_start,routed,dispatch_fatal,dispatch_req;
    logic [AW-1:0] dispatch_addr,v1_rd_addr;
    logic v1_rd_req,v1_loaded,v1_fatal,v1_model;
    logic [7:0] v1_error,v1_timing;
    logic [31:0] v1_num,v1_den;
    logic v1_store_rd,v1_store_we,v1_mem_valid;
    logic [28:0] v1_store_addr;
    logic [63:0] v1_store_din;
    logic [7:0] v1_store_be,v1_store_burst;
	logic [77:0] v1_q;
	logic [78:0] v2_q;
    logic v2_loaded,v2_fatal,v2_model,v2_mem_valid,v2_rd;
    logic [7:0] v2_error,v2_timing,v2_burst;
    logic [31:0] v2_num,v2_den;
	logic v2_loop_valid;
	logic [63:0] v2_loop_start_cycle;
    logic [28:0] v2_addr;
    version_dispatch #(.AW(AW)) dispatch(
        .clk(clk),.reset(reset),.start(start),.file_size(file_size),
        .rd_req(dispatch_req),.rd_addr(dispatch_addr),.rd_ready(rd_ready),.rd_valid(rd_valid),.rd_data(rd_data),
        .use_v2(use_v2),.v1_start(v1_start),.v2_start(v2_start),.routed(routed),.fatal(dispatch_fatal));
    assign rd_req=routed?(use_v2?1'b0:v1_rd_req):dispatch_req;
    assign rd_addr=routed?v1_rd_addr:dispatch_addr;
    assign loaded=use_v2?v2_loaded:(v1_loaded && store_prepared);
    assign parser_loaded=v1_loaded;
    assign parser_fatal=dispatch_fatal || (use_v2?v2_fatal:v1_fatal);
    assign parser_error_code=dispatch_fatal?8'h03:(use_v2?v2_error:v1_error);
    assign session_model=use_v2?v2_model:v1_model;
    assign session_timing=use_v2?v2_timing:v1_timing;
    assign session_clock_num=use_v2?v2_num:v1_num;
    assign session_clock_den=use_v2?v2_den:v1_den;
    assign valid=use_v2?v2_mem_valid:v1_mem_valid;
	assign q=use_v2?v2_q:{1'b0,v1_q};
	assign loop_valid=use_v2&&v2_loop_valid;
    assign store_rd=use_v2?v2_rd:v1_store_rd;
    assign store_we=use_v2?1'b0:v1_store_we;
    assign store_addr=use_v2?v2_addr:v1_store_addr;
    assign store_burst=use_v2?v2_burst:v1_store_burst;
    assign store_din=use_v2?64'd0:v1_store_din;
    assign store_be=use_v2?8'd0:v1_store_be;
    packed_stream #(.MAX_FILE_BYTES(MAX_FILE_BYTES),.RW(RW)) packed_path(
        .clk(clk),.reset(reset || !use_v2),.start(v2_start),.halt(transport_halt),
        .file_size(file_size),.loaded(v2_loaded),.fatal(v2_fatal),.error_code(v2_error),
        .session_model(v2_model),.session_timing(v2_timing),.session_clock_num(v2_num),.session_clock_den(v2_den),
		.loop_valid(v2_loop_valid),.loop_start_cycle(v2_loop_start_cycle),
        .mem_req(req && use_v2),.mem_addr(ra),.mem_valid(v2_mem_valid),.mem_data(v2_q),
        .d_busy(store_busy),.d_valid(store_valid && use_v2),.d_dout(store_dout),
        .d_rd(v2_rd),.d_addr(v2_addr),.d_burst(v2_burst));
    c2_record_store #(.RW(RW)) records (
        .clk(clk),.reset(reset),.validated(parser_loaded),
        .record_wr(wr),.record_addr(wa),.record_data(wd),.record_count(record_count),
        .record_ready(record_ready),.prepared(store_prepared),.fatal(store_fatal),
        .mem_req(req && !use_v2),.mem_addr(ra),.mem_valid(v1_mem_valid),.mem_data(v1_q),
        .d_busy(store_busy),.d_valid(store_valid && !use_v2),.d_dout(store_dout),
        .d_rd(v1_store_rd),.d_we(v1_store_we),.d_addr(v1_store_addr),.d_din(v1_store_din),
        .d_be(v1_store_be),.d_burst(v1_store_burst)
    );
    mvgmsid_loader #(.AW(AW), .MAX_FILE_BYTES(MAX_FILE_BYTES), .MAX_RECORDS(MAX_RECORDS)) loader (
        .clk(clk),.reset(reset),.start(v1_start),.file_size(file_size),
        .rd_req(v1_rd_req),.rd_addr(v1_rd_addr),.rd_ready(rd_ready),.rd_valid(rd_valid),.rd_data(rd_data),
        .loaded(v1_loaded),.fatal(v1_fatal),.error_code(v1_error),
        .session_model(v1_model),.session_timing(v1_timing),
        .session_clock_num(v1_num),.session_clock_den(v1_den),
        .record_ready(record_ready),
        .record_wr(wr),.record_addr(wa),.record_data(wd),.record_count(record_count),
        .stream_cycles(total_cycles)
    );
    sid_native_scheduler #(.SYS_HZ(SYS_HZ),.RW(RW)) scheduler (
		.clk(clk),.reset(reset),.enable(loaded && !parser_fatal),.halt(transport_halt),.halt_loop(loop_halt),
		.loop_valid(loop_valid),.loop_start_cycle(v2_loop_start_cycle),
        .clock_num(session_clock_num),.clock_den(session_clock_den),
        .mem_req(req),.mem_addr(ra),.mem_valid(valid),.mem_data(q),
        .ce_sid(ce_sid),.reg_write(reg_write),.reg_addr(reg_addr),.reg_data(reg_data),
		.busy(busy),.done(done),.fatal(scheduler_fatal),.native_cycle(native_cycle),.launched(launched),
		.loop_entry_pulse(loop_entry_pulse),.loop_boundary_pulse(loop_boundary_pulse),
		.loop_count(loop_count),.transport_ticks(transport_ticks)
    );
    wire signed [17:0] sid_audio;
    wire sid_valid;
    sid_session_wrapper sound (
        .clk(clk),.reset(reset || !loaded),.ce_sid(ce_sid),.model(session_model),
        .reg_addr(reg_addr),.reg_data(reg_data),.reg_write(reg_write),
        .audio(sid_audio),.sample_valid(sid_valid),.audio_ready(audio_ready),
        .pipeline_running(pipeline_running)
    );
    assign fatal=parser_fatal || scheduler_fatal || store_fatal;
    assign error_code=store_fatal ? 8'h81 : scheduler_fatal ? 8'h80 : parser_error_code;
    // Raw qualified SID publication survives parser EOF. The common owner alone
    // applies the final gain; neither parser busy nor done is an audio gate.
    assign audio=audio_ready && !fatal ? sid_audio : 18'sd0;
    assign sample_valid=audio_ready && !fatal && sid_valid;
    always @(posedge clk) begin
        if(reset) writes<=0;
        else if(reg_write) writes<=writes+1;
    end
endmodule

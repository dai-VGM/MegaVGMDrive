// SPDX-License-Identifier: GPL-2.0-or-later
`include "rtl/engine_c_c2_capacity/capacity.vh"
module engine_c_lab #(
    parameter integer AW=23, MAX_FILE_BYTES=`C2_MAX_FILE_BYTES,
    parameter integer MAX_RECORDS=((MAX_FILE_BYTES-128)/16)/2+1, SYS_HZ=20000000
)(
    input logic clk, reset, start,
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
    logic [77:0] wd, q;
    logic [RW:0] record_count;
    logic [63:0] total_cycles;
    logic [7:0] parser_error_code;
    logic req, valid,record_ready,parser_loaded,store_prepared,store_fatal;
    c2_record_store #(.RW(RW)) records (
        .clk(clk),.reset(reset),.validated(parser_loaded),
        .record_wr(wr),.record_addr(wa),.record_data(wd),.record_count(record_count),
        .record_ready(record_ready),.prepared(store_prepared),.fatal(store_fatal),
        .mem_req(req),.mem_addr(ra),.mem_valid(valid),.mem_data(q),
        .d_busy(store_busy),.d_valid(store_valid),.d_dout(store_dout),
        .d_rd(store_rd),.d_we(store_we),.d_addr(store_addr),.d_din(store_din),
        .d_be(store_be),.d_burst(store_burst)
    );
    assign loaded=parser_loaded && store_prepared;
    mvgmsid_loader #(.AW(AW), .MAX_FILE_BYTES(MAX_FILE_BYTES), .MAX_RECORDS(MAX_RECORDS)) loader (
        .clk(clk),.reset(reset),.start(start),.file_size(file_size),
        .rd_req(rd_req),.rd_addr(rd_addr),.rd_ready(rd_ready),.rd_valid(rd_valid),.rd_data(rd_data),
        .loaded(parser_loaded),.fatal(parser_fatal),.error_code(parser_error_code),
        .record_ready(record_ready),
        .record_wr(wr),.record_addr(wa),.record_data(wd),.record_count(record_count),
        .stream_cycles(total_cycles)
    );
    sid_native_scheduler #(.SYS_HZ(SYS_HZ),.RW(RW)) scheduler (
        .clk(clk),.reset(reset),.enable(loaded && !parser_fatal),
        .mem_req(req),.mem_addr(ra),.mem_valid(valid),.mem_data(q),
        .ce_sid(ce_sid),.reg_write(reg_write),.reg_addr(reg_addr),.reg_data(reg_data),
        .busy(busy),.done(done),.fatal(scheduler_fatal),.native_cycle(native_cycle),.launched(launched)
    );
    wire signed [17:0] sid_audio;
    wire sid_valid;
    sid_session_wrapper sound (
        .clk(clk),.reset(reset || !loaded),.ce_sid(ce_sid),.model(1'b0),
        .reg_addr(reg_addr),.reg_data(reg_data),.reg_write(reg_write),
        .audio(sid_audio),.sample_valid(sid_valid),.audio_ready(audio_ready),
        .pipeline_running(pipeline_running)
    );
    assign fatal=parser_fatal || scheduler_fatal || store_fatal;
    assign error_code=store_fatal ? 8'h81 : scheduler_fatal ? 8'h80 : parser_error_code;
    // Lab EOF only; production fade/transport integration is a later phase.
    assign audio=busy && audio_ready && !fatal ? sid_audio : 18'sd0;
    assign sample_valid=busy && audio_ready && !fatal && sid_valid;
    always @(posedge clk) begin
        if(reset) writes<=0;
        else if(reg_write) writes<=writes+1;
    end
endmodule

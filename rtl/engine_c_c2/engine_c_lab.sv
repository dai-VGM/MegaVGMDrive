// SPDX-License-Identifier: GPL-2.0-or-later
module engine_c_lab #(
    parameter integer AW=23, MAX_RECORDS=4096, SYS_HZ=20000000
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
    output logic [31:0] writes
);
    localparam RW=$clog2(MAX_RECORDS);
    logic wr, parser_fatal, scheduler_fatal, launched, pipeline_running;
    logic [RW-1:0] wa, ra;
    logic [77:0] wd, q;
    logic [RW:0] record_count;
    logic [63:0] total_cycles;
    logic [7:0] parser_error_code;
    logic req, valid;
    // Fully validated, timestamped RAM; old contents are unreachable because
    // every session rebuilds the descriptor range starting at zero.
    logic [77:0] records [0:MAX_RECORDS-1];
    always @(posedge clk) begin
        if(wr) records[wa]<=wd;
        valid<=!reset && req;
        if(req) q<=records[ra];
    end
    mvgmsid_loader #(.AW(AW), .MAX_RECORDS(MAX_RECORDS)) loader (
        .clk(clk),.reset(reset),.start(start),.file_size(file_size),
        .rd_req(rd_req),.rd_addr(rd_addr),.rd_ready(rd_ready),.rd_valid(rd_valid),.rd_data(rd_data),
        .loaded(loaded),.fatal(parser_fatal),.error_code(parser_error_code),
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
    assign fatal=parser_fatal || scheduler_fatal;
    assign error_code=scheduler_fatal ? 8'h80 : parser_error_code;
    // Lab EOF only; production fade/transport integration is a later phase.
    assign audio=busy && audio_ready && !fatal ? sid_audio : 18'sd0;
    assign sample_valid=busy && audio_ready && !fatal && sid_valid;
    always @(posedge clk) begin
        if(reset) writes<=0;
        else if(reg_write) writes<=writes+1;
    end
endmodule

// SPDX-License-Identifier: GPL-2.0-or-later
// C2 bounded lab preflight. No writes reach SID until the complete file validates.
`include "rtl/engine_c_c2_capacity/capacity.vh"
module mvgmsid_loader #(
    parameter integer AW=23, MAX_FILE_BYTES=`C2_MAX_FILE_BYTES,
    parameter integer MAX_EVENTS=(MAX_FILE_BYTES-128)/16,
    parameter integer MAX_RECORDS=MAX_EVENTS/2+1,
    parameter integer LOAD_WATCHDOG=20000000
)(
    input logic clk, reset, start,
    input logic [31:0] file_size,
    output logic rd_req,
    output logic [AW-1:0] rd_addr,
    input logic rd_ready, rd_valid,
    input logic [7:0] rd_data,
    output logic loaded, fatal,
    output logic [7:0] error_code,
    input logic record_ready,
    output logic record_wr,
    output logic [$clog2(MAX_RECORDS)-1:0] record_addr,
    output logic [77:0] record_data,
    output logic [$clog2(MAX_RECORDS):0] record_count,
    output logic [63:0] stream_cycles
);
    initial begin
        if(AW<1 || AW>31 || MAX_FILE_BYTES<160 || MAX_RECORDS<2 ||
           64'(MAX_FILE_BYTES)>(64'd1<<AW) ||
           MAX_EVENTS!=(MAX_FILE_BYTES-128)/16 || MAX_RECORDS<MAX_EVENTS/2+1)
            $fatal(1,"C2 invalid file/event/record capacity parameters");
    end
    typedef enum logic[2:0] {IDLE, REQUEST, RESPONSE, HEADER, EVENT, FINISH, FAILED} state_t;
    state_t state;
    logic [1023:0] header;
    logic [127:0] event_word;
    logic [31:0] pos, size_latched, watchdog;
    logic [63:0] event_index, event_count, elapsed;
    logic wrote_this_cycle;
    wire [31:0] flags = header[128+:32];
    wire [63:0] count = header[320+:64];
    wire [63:0] bytes_count = header[384+:64];
    wire [63:0] operand = event_word[64+:64];
    assign rd_req = state==REQUEST;
    assign rd_addr = pos[AW-1:0];
    task automatic reject(input logic[7:0] code);
        begin fatal<=1; error_code<=code; state<=FAILED; end
    endtask
    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE; loaded<=0; fatal<=0; error_code<=0; record_wr<=0;
            record_count<=0; record_addr<=0; record_data<=0; header<=0;
            event_word<=0; pos<=0; size_latched<=0; watchdog<=0;
            event_index<=0; event_count<=0; elapsed<=0; stream_cycles<=0;
            wrote_this_cycle<=0;
        end else begin
            record_wr<=0;
            case(state)
            IDLE: if(start) begin
                size_latched<=file_size;
                if(file_size<144 || file_size>MAX_FILE_BYTES ||
                   {32'd0,file_size}>(64'd1<<AW)) reject(1);
                else state<=REQUEST;
            end
            REQUEST: begin
                if(rd_ready) begin state<=RESPONSE; watchdog<=0; end
                else if(watchdog==LOAD_WATCHDOG-1) reject(2);
                else watchdog<=watchdog+1;
            end
            RESPONSE: begin
                if(rd_valid) begin
                    watchdog<=0;
                    if(pos<128) header[pos[6:0]*8+:8]<=rd_data;
                    else event_word[pos[3:0]*8+:8]<=rd_data;
                    pos<=pos+1;
                    if(pos==127) state<=HEADER;
                    else if(pos>=128 && pos[3:0]==15) state<=EVENT;
                    else state<=REQUEST;
                end else if(watchdog==LOAD_WATCHDOG-1) reject(2);
                else watchdog<=watchdog+1;
            end
            HEADER: begin
                if(header[0+:64]!=64'h004449534d47564d ||
                   header[64+:32]!=32'h00000001 ||
                   header[96+:32]!=32'h00100080) reject(3);
                else if((flags & ~32'h1d)!=0 || header[248+:8]!=0 ||
                        header[288+:32]!=0) reject(4);
                // v1 accepted subset, not a new format: PAL/6581/single only.
                else if(header[160+:32]!=985248 || header[192+:32]!=1 ||
                        header[224+:8]!=1 || header[232+:8]!=1 ||
                        header[240+:8]!=1 || header[256+:32]==0) reject(5);
                else if(count==0 || count>64'(MAX_EVENTS) || count[63:60]!=0 ||
                        bytes_count!=(count<<4) || bytes_count>64'hffffffffffffff7f ||
                        bytes_count+128!={32'd0,size_latched}) reject(6);
                else if((flags[0] != (header[512+:64]!=0)) ||
                        header[576+:192]!=0) reject(7);
                else begin
                    event_count<=count; stream_cycles<=header[448+:64];
                    state<=REQUEST;
                end
            end
            EVENT: begin
                if(event_word[24+:40]!=0) reject(8);
                else case(event_word[7:0])
                0: begin
                    if(event_word[8+:16]!=0 || operand==0 ||
                       operand>~elapsed || event_index==event_count-1) reject(9);
                    else begin
                        elapsed<=elapsed+operand; wrote_this_cycle<=0;
                        event_index<=event_index+1; state<=REQUEST;
                    end
                end
                1: begin
                    if(event_word[15:8]>24 || operand!=0 || wrote_this_cycle ||
                       event_index==event_count-1) reject(10);
                    else if(32'(record_count)>=MAX_RECORDS-1) reject(11);
                    else if(record_ready) begin
                        record_wr<=1; record_addr<=record_count[$clog2(MAX_RECORDS)-1:0];
                        record_data<={1'b0,elapsed,event_word[12:8],event_word[23:16]};
                        record_count<=record_count+1;
                        wrote_this_cycle<=1; event_index<=event_index+1; state<=REQUEST;
                    end
                end
                255: begin
                    if(event_word[127:8]!=0 || event_index!=event_count-1 ||
                       elapsed!=stream_cycles || pos!=size_latched) reject(12);
                    else if(record_ready) begin
                        record_wr<=1; record_addr<=record_count[$clog2(MAX_RECORDS)-1:0];
                        record_data<={1'b1,elapsed,13'd0}; record_count<=record_count+1;
                        state<=FINISH;
                    end
                end
                default: reject(13);
                endcase
            end
            FINISH: loaded<=1;
            default: ;
            endcase
        end
    end
endmodule

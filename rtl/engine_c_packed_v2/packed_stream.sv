// SPDX-License-Identifier: GPL-2.0-or-later
// Strict preflight, then direct packed DDR replay to bounded canonical FIFO.
// C7.2 adds strict Packed-v2 manual loops without resetting SID/audio state.
module packed_stream #(
    parameter integer MAX_FILE_BYTES=8388608, RW=18, FIFO_DEPTH=128, PREFILL=64,
    parameter integer WATCHDOG=20000000
)(
    input logic clk,reset,start,halt,
    input logic [31:0] file_size,
    output logic loaded,fatal,
    output logic [7:0] error_code,
    output logic session_model,
    output logic [7:0] session_timing,
    output logic [31:0] session_clock_num,session_clock_den,
	output logic loop_valid,
	output logic [63:0] loop_start_cycle,
    input logic mem_req,
    input logic [RW-1:0] mem_addr,
    output logic mem_valid,
    output logic [78:0] mem_data,
    input logic d_busy,d_valid,
    input logic [63:0] d_dout,
    output logic d_rd,
    output logic [28:0] d_addr,
    output logic [7:0] d_burst
);
    localparam FW=$clog2(FIFO_DEPTH);
    typedef enum logic [3:0] {IDLE,HEADER,CHECK,LEB,TAG,DATA,EMIT,REWIND,FINISHED,FAILED} state_t;
    state_t state;
    logic [1023:0] header;
    logic [31:0] size_latched,pos,record_start,rewind_byte,loop_byte_offset;
    logic replay,byte_valid,byte_take,reader_fatal,loop_checkpoint_valid;
	logic loop_rewind,first_after_loop;
    logic [7:0] byte_data;
    logic [63:0] delta,elapsed,write_count,last_write_cycle;
	logic [63:0] loop_write_index,loop_end_cycle,loop_first_target,timeline_base;
    logic [3:0] group;
    logic [78:0] holding;
    logic [78:0] fifo[0:FIFO_DEPTH-1];
    logic [FW-1:0] wp,rp;
    logic [FW:0] fill;
    logic [RW-1:0] consumed;
    wire [31:0] flags=header[128+:32], num=header[160+:32],den=header[192+:32];
    wire [7:0] model=header[224+:8],timing=header[232+:8];
    wire [63:0] expected_count=header[320+:64],body_bytes=header[384+:64],end_cycle=header[448+:64];
	wire [63:0] header_loop_index=header[576+:64],header_loop_start=header[640+:64],
		header_loop_end=header[704+:64];
    wire [64:0] ordinary_next_cycle={1'b0,elapsed}+{1'b0,delta};
	wire [63:0] source_next_cycle=first_after_loop?loop_first_target:ordinary_next_cycle[63:0];
	wire [64:0] absolute_next_cycle={1'b0,source_next_cycle}+{1'b0,timeline_base};
    wire [63:0] leb_value=delta | ({57'd0,byte_data[6:0]} << (7*group));
    wire clock_ok=num!=0 && den!=0 &&
        ((timing==1 && {32'd0,num}==64'd985248*{32'd0,den}) ||
         (timing==2 && {32'd0,num}==64'd1022727*{32'd0,den}));
    wire reader_reset=reset || state==IDLE || state==REWIND;
    wire pop=mem_req && loaded && fill!=0 && !fatal && !halt;
    wire push=state==EMIT && replay && int'(fill)<FIFO_DEPTH && !fatal && !halt;
    assign byte_take=!fatal && !halt &&
        (state==HEADER || state==LEB || state==TAG || state==DATA);
    packed_byte_reader #(.WATCHDOG(WATCHDOG)) reader(
        .clk(clk),.reset(reader_reset),.enable(state!=IDLE && state!=FAILED && !halt),
        .first_byte(replay?rewind_byte:32'd0),.file_size(size_latched),
        .byte_valid(byte_valid),.byte_data(byte_data),.byte_take(byte_take),.fatal(reader_fatal),
        .d_busy(d_busy),.d_valid(d_valid),.d_dout(d_dout),.d_rd(d_rd),.d_addr(d_addr),.d_burst(d_burst));
    task automatic reject(input logic [7:0] code);
        begin fatal<=1;error_code<=code;state<=FAILED;end
    endtask
    initial if(FIFO_DEPTH<4 || (FIFO_DEPTH&(FIFO_DEPTH-1))!=0 || PREFILL<2 || PREFILL>FIFO_DEPTH)
        $fatal(1,"invalid packed canonical FIFO geometry");
    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE;header<=0;size_latched<=0;pos<=0;record_start<=0;rewind_byte<=128;replay<=0;
            delta<=0;elapsed<=0;write_count<=0;last_write_cycle<=0;group<=0;holding<=0;
			loop_valid<=0;loop_start_cycle<=0;loop_write_index<=0;loop_end_cycle<=0;
			loop_byte_offset<=0;loop_first_target<=0;loop_checkpoint_valid<=0;
			loop_rewind<=0;first_after_loop<=0;timeline_base<=0;
            wp<=0;rp<=0;fill<=0;consumed<=0;mem_valid<=0;mem_data<=0;
            loaded<=0;fatal<=0;error_code<=0;
            session_model<=0;session_timing<=0;session_clock_num<=0;session_clock_den<=0;
        end else begin
            mem_valid<=0;
            if(pop) begin
                if(mem_addr!=consumed) reject(8'h91);
                mem_data<=fifo[rp];mem_valid<=1;rp<=rp+1'b1;consumed<=consumed+1'b1;
            end
            if(push) begin fifo[wp]<=holding;wp<=wp+1'b1;end
            case({push,pop})
                2'b10:fill<=fill+1'b1;
                2'b01:fill<=fill-1'b1;
                default:;
            endcase
            if(replay && !loaded && (int'(fill)>=PREFILL || (state==FINISHED && fill!=0))) loaded<=1;
            if(reader_fatal) reject(8'h92);
            else if(!fatal && !halt) begin
                if(byte_take && byte_valid) pos<=pos+1'b1;
                // Missing EOF/truncated record at physical end, even without a new byte.
                if(pos==size_latched && (state==LEB || state==TAG || state==DATA)) reject(8'h93);
                else case(state)
                IDLE:if(start) begin
                    size_latched<=file_size;
                    if(file_size<130 || file_size>MAX_FILE_BYTES) reject(1);
                    else state<=HEADER;
                end
                HEADER:if(byte_valid) begin
                    header[pos[6:0]*8+:8]<=byte_data;
                    if(pos==127) state<=CHECK;
                end
                CHECK:begin
                    if(header[0+:64]!=64'h004449534d47564d || header[64+:32]!=32'h00000002 ||
                       header[96+:32]!=32'h00010080) reject(3);
                    else if((flags&~32'h1f)!=0 || header[248+:8]!=0 || header[288+:32]!=0) reject(4);
                    else if(!clock_ok || (model!=1 && model!=2) || header[240+:8]!=1 || header[256+:32]==0) reject(5);
                    // Bounds before multiplication: never wrap an untrusted count.
                    else if(expected_count>64'(MAX_FILE_BYTES/3) || body_bytes>64'(MAX_FILE_BYTES-128) ||
                            body_bytes+128!={32'd0,size_latched} || body_bytes<expected_count*3+2 ||
                            body_bytes>expected_count*12+11) reject(6);
                    else if(flags[0]!=(header[512+:64]!=0)) reject(7);
					else if(flags[1] && (!(header_loop_start<header_loop_end) ||
						header_loop_end!=end_cycle || header_loop_index>expected_count)) reject(8'h96);
					else if(!flags[1] && header[576+:192]!=0) reject(7);
                    else begin
						loop_valid<=flags[1];loop_start_cycle<=header_loop_start;
						loop_write_index<=header_loop_index;loop_end_cycle<=header_loop_end;
						record_start<=128;state<=LEB;
					end
                end
                LEB:if(byte_valid) begin
                    if((group==9 && byte_data!=1) || (group!=0 && !byte_data[7] && byte_data[6:0]==0)) reject(8'h94);
                    else begin
                        delta<=leb_value;
                        if(byte_data[7]) group<=group+1'b1;
                        else state<=TAG;
                    end
                end
                TAG:if(byte_valid) begin
                    if(!first_after_loop && ordinary_next_cycle[64]) reject(8'h95);
					else if(absolute_next_cycle[64]) reject(8'h95);
                    else if(byte_data==255) begin
                        if(pos+1!=size_latched || write_count!=expected_count || source_next_cycle!=end_cycle) reject(12);
						else if(!replay && flags[1] && !loop_checkpoint_valid &&
							!(write_count==header_loop_index &&
							  ((!write_count && header_loop_start==0) ||
							   (write_count && last_write_cycle<=header_loop_start)))) reject(8'h97);
						else if(!replay && flags[1] && header_loop_index<expected_count &&
							loop_first_target==header_loop_start && last_write_cycle==header_loop_end) reject(8'h98);
                        else begin
							if(!replay && flags[1] && write_count==header_loop_index && !loop_checkpoint_valid) begin
								loop_byte_offset<=record_start;loop_first_target<=source_next_cycle;
								loop_checkpoint_valid<=1;
							end
							holding<={replay&&loop_valid,1'b1,absolute_next_cycle[63:0],13'd0};
							state<=EMIT;
						end
					end else if(byte_data>24 || write_count>=expected_count ||
							(!replay && write_count!=0 && delta==0) || source_next_cycle>end_cycle) reject(10);
					else begin
						if(!replay && flags[1] && write_count==header_loop_index) begin
							if((write_count!=0 && last_write_cycle>header_loop_start) ||
								source_next_cycle<header_loop_start) reject(8'h97);
							else begin loop_byte_offset<=record_start;loop_first_target<=source_next_cycle;
								loop_checkpoint_valid<=1;holding<={2'b00,absolute_next_cycle[63:0],byte_data[4:0],8'd0};
								elapsed<=source_next_cycle;state<=DATA;end
						end else begin
							holding<={2'b00,absolute_next_cycle[63:0],byte_data[4:0],8'd0};
							elapsed<=source_next_cycle;state<=DATA;
						end
                    end
					first_after_loop<=0;
                end
                DATA:if(byte_valid) begin holding[7:0]<=byte_data;last_write_cycle<=elapsed;write_count<=write_count+1'b1;state<=EMIT;end
                EMIT:if(!replay || push) begin
					if(holding[78]) begin
						timeline_base<=timeline_base+(loop_end_cycle-loop_start_cycle);
						rewind_byte<=loop_byte_offset;loop_rewind<=1;first_after_loop<=1;state<=REWIND;
					end else if(holding[77]) begin
                        if(!replay) begin
							replay<=1;rewind_byte<=128;loop_rewind<=0;timeline_base<=0;state<=REWIND;
                            session_model<=(model==2);session_timing<=timing;
                            session_clock_num<=num;session_clock_den<=den;
                        end else state<=FINISHED;
                    end else begin delta<=0;group<=0;record_start<=pos;state<=LEB;end
                end
                REWIND:begin
					pos<=rewind_byte;record_start<=rewind_byte;delta<=0;group<=0;
					if(loop_rewind)begin elapsed<=loop_start_cycle;write_count<=loop_write_index;end
					else begin elapsed<=0;write_count<=0;last_write_cycle<=0;end
					state<=LEB;
				end
                default:;
                endcase
            end
        end
    end
endmodule

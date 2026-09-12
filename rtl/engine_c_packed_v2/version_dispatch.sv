// SPDX-License-Identifier: GPL-2.0-or-later
// Only format identity is inspected here. Each path performs full validation.
module version_dispatch #(parameter integer AW=23,WATCHDOG=20000000)(
    input logic clk,reset,start,
    output logic rd_req,
    output logic [AW-1:0] rd_addr,
    input logic rd_ready,rd_valid,
    input logic [7:0] rd_data,
    input logic [31:0] file_size,
    output logic use_v2,v1_start,v2_start,routed,fatal
);
    typedef enum logic[2:0] {IDLE,REQUEST,RESPONSE,CHECK,START1,START2,ACTIVE,FAILED} state_t;
    state_t state;
    logic [127:0] identity;
    logic [3:0] pos;
    logic [31:0] timer;
    assign rd_req=state==REQUEST;
    assign rd_addr={{(AW-4){1'b0}},pos};
    assign v1_start=state==START1;
    assign v2_start=state==START2;
    assign routed=state==START1 || state==START2 || state==ACTIVE;
    always @(posedge clk) begin
        if(reset) begin state<=IDLE;identity<=0;pos<=0;timer<=0;use_v2<=0;fatal<=0;end
        else case(state)
        IDLE:if(start) begin
            if(file_size<16) begin fatal<=1;state<=FAILED;end
            else state<=REQUEST;
        end
        REQUEST:if(rd_ready) begin state<=RESPONSE;timer<=0;end
            else if(timer==WATCHDOG-1) begin fatal<=1;state<=FAILED;end
            else timer<=timer+1;
        RESPONSE:if(rd_valid) begin
            identity[pos*8+:8]<=rd_data;timer<=0;
            if(pos==15) state<=CHECK;
            else begin pos<=pos+1'b1;state<=REQUEST;end
        end else if(timer==WATCHDOG-1) begin fatal<=1;state<=FAILED;end
            else timer<=timer+1;
        CHECK:begin
            if(identity[63:0]!=64'h004449534d47564d || identity[95:80]!=0 || identity[111:96]!=128 ||
                !((identity[79:64]==1 && identity[127:112]==16) ||
                  (identity[79:64]==2 && identity[127:112]==1))) begin fatal<=1;state<=FAILED;end
            else if(identity[79:64]==2) begin use_v2<=1;state<=START2;end
            else state<=START1;
        end
        START1,START2:state<=ACTIVE;
        default:;
        endcase
    end
endmodule

// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only raw-file DDR bursts -> byte FIFO. Never writes expanded records.
module packed_byte_reader #(
    parameter integer WORDS=64, BURST=16, WATCHDOG=20000000
)(
    input logic clk,reset,enable,
    input logic [31:0] first_byte,file_size,
    output logic byte_valid,
    output logic [7:0] byte_data,
    input logic byte_take,
    output logic fatal,
    input logic d_busy,d_valid,
    input logic [63:0] d_dout,
    output logic d_rd,
    output logic [28:0] d_addr,
    output logic [7:0] d_burst
);
    localparam W=$clog2(WORDS);
    logic [63:0] fifo[0:WORDS-1];
    logic [W-1:0] wp,rp;
    logic [W:0] count;
    logic [2:0] lane;
    logic [31:0] fetched,consumed,timer;
    logic [7:0] remaining;
    logic pending;
    wire [31:0] end_word=(file_size+7)>>3;
    wire push=pending && d_valid;
    wire pop=byte_valid && byte_take;
    wire pop_word=pop && lane==7;
    assign byte_valid=enable && !fatal && count!=0 && consumed<file_size;
    assign byte_data=fifo[rp][lane*8+:8];
    initial if(WORDS<32 || (WORDS&(WORDS-1))!=0 || BURST<1 || BURST>WORDS/2 || BURST>255)
        $fatal(1,"invalid packed byte FIFO geometry");
    always @(posedge clk) begin
        if(reset) begin
            wp<=0;rp<=0;count<=0;lane<=0;fetched<=first_byte>>3;consumed<=first_byte;
            timer<=0;remaining<=0;pending<=0;fatal<=0;d_rd<=0;d_addr<=0;d_burst<=0;
        end else begin
            d_rd<=0;
            if(enable && !fatal) begin
                if(pending || (!pending && fetched<end_word && int'(count)<=WORDS-BURST)) begin
                    if(timer==WATCHDOG-1) fatal<=1;
                    else timer<=timer+1;
                end else timer<=0;
                if(!pending && !d_rd && !d_busy && fetched<end_word && int'(count)<=WORDS-BURST) begin
                    d_addr<=29'h06000000+29'(fetched);
                    d_burst<=end_word-fetched<32'(BURST)?8'(end_word-fetched):8'(BURST);
                    remaining<=end_word-fetched<32'(BURST)?8'(end_word-fetched):8'(BURST);
                    pending<=1;d_rd<=1;timer<=0;
                end
                if(push) begin
                    if(int'(count)==WORDS && !pop_word) fatal<=1;
                    fifo[wp]<=d_dout;wp<=wp+1'b1;fetched<=fetched+1'b1;
                    remaining<=remaining-1'b1;timer<=0;
                    if(remaining==1) pending<=0;
                end
                if(pop) begin
                    consumed<=consumed+1'b1;lane<=lane+1'b1;
                    if(lane==7) rp<=rp+1'b1;
                end
                case({push,pop_word})
                    2'b10: count<=count+1'b1;
                    2'b01: count<=count-1'b1;
                    default: ;
                endcase
            end
        end
    end
endmodule

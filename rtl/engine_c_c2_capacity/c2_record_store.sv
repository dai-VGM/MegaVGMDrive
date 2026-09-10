// C2 capacity storage, NOT a SID scheduler. 128-bit DDR descriptor slots:
// low 78 bits are the unchanged {EOF, absolute cycle, address, data} record.
// Raw file occupies byte 0x30000000..0x307fffff. Descriptors start at 0x30800000.
module c2_record_store #(
    parameter integer RW=17, FIFO_DEPTH=64, BURST_RECORDS=8,
    parameter logic [28:0] BASE_WORD=29'h06100000,
    parameter integer REGION_BYTES=4194304, WATCHDOG=20000000
)(
    input logic clk,reset,validated,
    input logic record_wr,
    input logic [RW-1:0] record_addr,
    input logic [77:0] record_data,
    input logic [RW:0] record_count,
    output logic record_ready,prepared,fatal,
    input logic mem_req,
    input logic [RW-1:0] mem_addr,
    output logic mem_valid,
    output logic [77:0] mem_data,
    input logic d_busy,d_valid,
    input logic [63:0] d_dout,
    output logic d_rd,d_we,
    output logic [28:0] d_addr,
    output logic [63:0] d_din,
    output logic [7:0] d_be,d_burst
);
    localparam FW=$clog2(FIFO_DEPTH);
    initial begin
        if(RW<1 || RW>18 || (64'd1<<RW)*16>64'(REGION_BYTES))
            $fatal(1,"C2 descriptor address width exceeds reserved DDR region");
        if(FIFO_DEPTH<8 || (FIFO_DEPTH&(FIFO_DEPTH-1))!=0 ||
           BURST_RECORDS<1 || BURST_RECORDS>127 || BURST_RECORDS>FIFO_DEPTH/2)
            $fatal(1,"C2 invalid FIFO/burst geometry");
        if((64'(BASE_WORD)<<3)+64'(REGION_BYTES)>64'h100000000)
            $fatal(1,"C2 descriptor region overflow");
    end
    typedef enum logic[2:0] {IDLE,LO,HI,DRAIN,FETCH,RETURN_DATA} state_t;
    state_t state;
    logic [77:0] holding;
    logic [RW-1:0] write_index;
    logic [RW:0] fetched,consumed;
    logic [77:0] fifo[0:FIFO_DEPTH-1];
    logic [FW-1:0] wp,rp;
    logic [FW:0] count;
    logic [7:0] beats,request_records;
    logic [63:0] low_word;
    logic [31:0] watchdog;
    wire pop=mem_req && prepared && count!=0 && !fatal;
    wire push=state==RETURN_DATA && d_valid && beats[0];
    wire [RW:0] left=record_count-fetched;
    wire [RW:0] prefill=record_count<(RW+1)'(FIFO_DEPTH/2)?record_count:(RW+1)'(FIFO_DEPTH/2);
    assign record_ready=!reset&&!fatal&&state==IDLE&&!record_wr&&!validated;
    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE; prepared<=0;fatal<=0;holding<=0;write_index<=0;
            fetched<=0;consumed<=0;wp<=0;rp<=0;count<=0;beats<=0;request_records<=0;
            low_word<=0;mem_valid<=0;mem_data<=0;d_rd<=0;d_we<=0;d_addr<=0;
            d_din<=0;d_be<=0;d_burst<=0;watchdog<=0;
        end else begin
            d_rd<=0;d_we<=0;mem_valid<=0;
            if(state!=IDLE) begin
                if(watchdog==WATCHDOG-1) fatal<=1;
                else watchdog<=watchdog+1;
            end else watchdog<=0;
            if(pop) begin
                if(mem_addr!=consumed[RW-1:0]) fatal<=1;
                else begin mem_data<=fifo[rp];mem_valid<=1;rp<=rp+1'b1;consumed<=consumed+1'b1; end
            end
            case({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: ;
            endcase
            if(validated && (RW+1)'(count)>=prefill && prefill!=0) prepared<=1;
            if(!fatal) case(state)
            IDLE: begin
                if(record_wr) begin holding<=record_data;write_index<=record_addr;state<=LO; end
                else if(validated && fetched<record_count && (FIFO_DEPTH-int'(count))>=BURST_RECORDS) begin
                    request_records<=left<(RW+1)'(BURST_RECORDS)?8'(left):8'(BURST_RECORDS);
                    state<=FETCH;
                end
            end
            LO: if(!d_busy) begin
                d_addr<=BASE_WORD+(29'(write_index)<<1);d_din<=holding[63:0];
                d_be<=8'hff;d_burst<=1;d_we<=1;state<=HI;
            end
            HI: if(!d_busy) begin
                d_addr<=BASE_WORD+(29'(write_index)<<1)+1'b1;d_din<={50'd0,holding[77:64]};
                d_be<=8'hff;d_burst<=1;d_we<=1;state<=DRAIN;
            end
            DRAIN: if(!d_busy) state<=IDLE;
            FETCH: if(!d_busy) begin
                d_addr<=BASE_WORD+(29'(fetched)<<1);d_burst<=request_records<<1;
                d_rd<=1;beats<=0;state<=RETURN_DATA;
            end
            RETURN_DATA: if(d_valid) begin
                watchdog<=0;
                if(!beats[0]) low_word<=d_dout;
                else begin
                    fifo[wp]<={d_dout[13:0],low_word};wp<=wp+1'b1;fetched<=fetched+1'b1;
                    if(d_dout[63:14]!=0 || int'(count)==FIFO_DEPTH) fatal<=1;
                end
                beats<=beats+1'b1;
                if(beats+1'b1==(request_records<<1)) state<=IDLE;
            end
            default: fatal<=1;
            endcase
        end
    end
endmodule

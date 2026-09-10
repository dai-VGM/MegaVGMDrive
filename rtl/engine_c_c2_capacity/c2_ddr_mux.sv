// C2 storage arbiter. One queued command/client; one outstanding read burst.
// Reset is CORE reset, never per-download reset: drain old transactions before
// a new session can use the same client. Clients issue registered strobes.
module c2_ddr_mux(
    input logic clk, reset,
    input logic a_rd,a_we,b_rd,b_we,
    input logic [28:0] a_addr,b_addr,
    input logic [63:0] a_din,b_din,
    input logic [7:0] a_be,b_be,a_burst,b_burst,
    output logic a_busy,b_busy,a_valid,b_valid,
    output logic [63:0] a_dout,b_dout,
    input logic busy, valid,
    input logic [63:0] dout,
    output logic rd,we,
    output logic [28:0] addr,
    output logic [63:0] din,
    output logic [7:0] be,burst
);
    logic aq,bq,ar,br, inflight,owner;
    logic [28:0] aa,ba;
    logic [63:0] ad,bd;
    logic [7:0] ae,beq,ab,bb,remaining;
    wire choose_b=bq;
    wire issue=!reset && !busy && !inflight && (aq||bq);
    assign a_busy=reset||busy||inflight||aq||a_rd||a_we;
    assign b_busy=reset||busy||inflight||bq||b_rd||b_we;
    assign addr=choose_b?ba:aa;
    assign din=choose_b?bd:ad;
    assign be=choose_b?beq:ae;
    assign burst=choose_b?bb:ab;
    assign rd=issue && (choose_b?br:ar);
    assign we=issue && !(choose_b?br:ar);
    assign a_valid=valid&&inflight&&!owner;
    assign b_valid=valid&&inflight&&owner;
    assign a_dout=dout;
    assign b_dout=dout;
    always @(posedge clk) begin
        if(reset) begin
            aq<=0;bq<=0;inflight<=0;owner<=0;remaining<=0;
            aa<=0;ba<=0;ad<=0;bd<=0;ae<=0;beq<=0;ab<=0;bb<=0;ar<=0;br<=0;
        end else begin
            if(a_rd||a_we) begin aq<=1;aa<=a_addr;ad<=a_din;ae<=a_be;ab<=a_burst;ar<=a_rd; end
            if(b_rd||b_we) begin bq<=1;ba<=b_addr;bd<=b_din;beq<=b_be;bb<=b_burst;br<=b_rd; end
            if(issue) begin
                if(choose_b) bq<=0; else aq<=0;
                if(rd) begin inflight<=1;owner<=choose_b;remaining<=burst; end
            end
            if(valid && inflight) begin
                remaining<=remaining-1'b1;
                if(remaining==1) inflight<=0;
            end
        end
    end
endmodule

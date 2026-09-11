// C4-only fault observer. No normal-path ready/clock/backpressure feedback.
// Raw-response budget matches vgm_ddram_backend.READ_TIMEOUT_CYCLES (1024).
// Descriptor-response/BUSY budgets match C2's watchdog (one SYS second).
module c4_ddr_health #(
    parameter integer RESPONSE_CYCLES=1024, DESCRIPTOR_CYCLES=20000000, BUSY_CYCLES=20000000,
    parameter logic [28:0] DESCRIPTOR_BASE_WORD=29'h06100000
)(
    input logic clk,reset,new_session,work_pending,
    input logic busy,rd,valid,
    input logic [7:0] burst,
    input logic [28:0] address,
    output logic fatal
);
    logic [8:0] remaining;
    logic [31:0] response_age,busy_age,response_limit;
    always @(posedge clk) begin
        if(reset) begin remaining<=0;response_age<=0;busy_age<=0;fatal<=0;response_limit<=RESPONSE_CYCLES;end
        else begin
            if(new_session) fatal<=0;
            // Transactions may span a session: keep tracking their actual drain.
            if(rd && !busy) begin
                remaining<={1'b0,burst};response_age<=0;
                response_limit<=address>=DESCRIPTOR_BASE_WORD ? DESCRIPTOR_CYCLES : RESPONSE_CYCLES;
            end
            else if(remaining!=0) begin
                if(valid) begin remaining<=remaining-1'b1;response_age<=0;end
                else if(response_age>=response_limit-1) fatal<=1;
                else response_age<=response_age+1'b1;
            end
            if(work_pending && busy) begin
                if(busy_age>=BUSY_CYCLES-1) fatal<=1;
                else busy_age<=busy_age+1'b1;
            end else busy_age<=0;
        end
    end
endmodule

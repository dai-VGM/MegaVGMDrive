// SPDX-License-Identifier: GPL-2.0-or-later
module sid_session_wrapper(
    input logic clk, reset, ce_sid, model,
    input logic [4:0] reg_addr,
    input logic [7:0] reg_data,
    input logic reg_write,
    output logic signed [17:0] audio,
    output logic sample_valid, audio_ready, pipeline_running
);
    wire [17:0] raw;
    wire published;
    logic session_model;
    always @(posedge clk) if(reset) session_model<=model;
    sid_top #(.DUAL(0), .MULTI_FILTERS(1)) sid (
        .clk(clk), .reset(reset), .ce_1m(ce_sid), .sample_pulse(published),
        .cs(reg_write), .we(reg_write), .addr(reg_addr), .data_in(reg_data), .data_out(),
        .fc_offset_l(13'd0), .fc_offset_r(13'd0),
        .pot_x_l(8'hff), .pot_y_l(8'hff), .pot_x_r(8'hff), .pot_y_r(8'hff),
        .ext_in_l(18'd0), .ext_in_r(18'd0), .audio_l(raw), .audio_r(),
        .filter_en(1'b1), .mode(session_model), .cfg(2'd0),
        .ld_clk(clk), .ld_addr(12'd0), .ld_data(16'd0), .ld_wr(1'b0)
    );
    // Pulse arrives WITH the committed output. Consumer samples it next edge.
    assign audio=reset ? 18'sd0 : $signed(raw);
    assign sample_valid=!reset && published && pipeline_running;
    always @(posedge clk) begin
        if(reset) begin audio_ready<=0; pipeline_running<=0; end
        else begin
            if(ce_sid) pipeline_running<=1;
            if(sample_valid) audio_ready<=1;
        end
    end
endmodule

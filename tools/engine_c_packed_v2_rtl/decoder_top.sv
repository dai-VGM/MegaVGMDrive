module decoder_top(
    input logic clk,reset,start,halt,
    input logic [31:0] file_size,
    output logic loaded,fatal,session_model,
    output logic [7:0] error_code,session_timing,
    output logic [31:0] session_clock_num,session_clock_den,
    input logic mem_req,
    input logic [17:0] mem_addr,
    output logic mem_valid,
    output logic [77:0] mem_data,
    input logic d_busy,d_valid,
    input logic [63:0] d_dout,
    output logic d_rd,
    output logic [28:0] d_addr,
    output logic [7:0] d_burst
);
    wire store_busy,store_valid,store_rd;
    wire [63:0] store_dout;
    wire [28:0] store_addr;
    wire [7:0] store_burst;
    packed_stream #(.WATCHDOG(1024)) dut(
        .clk(clk),.reset(reset),.start(start),.halt(halt),.file_size(file_size),
        .loaded(loaded),.fatal(fatal),.error_code(error_code),.session_model(session_model),
        .session_timing(session_timing),.session_clock_num(session_clock_num),.session_clock_den(session_clock_den),
        .mem_req(mem_req),.mem_addr(mem_addr),.mem_valid(mem_valid),.mem_data(mem_data),
        .d_busy(store_busy),.d_valid(store_valid),.d_dout(store_dout),
        .d_rd(store_rd),.d_addr(store_addr),.d_burst(store_burst));
    c2_ddr_mux mux(.clk(clk),.reset(reset),
        .a_rd(1'b0),.a_we(1'b0),.a_addr(29'd0),.a_din(64'd0),.a_be(8'd0),.a_burst(8'd0),
        .a_busy(),.a_valid(),.a_dout(),
        .b_rd(store_rd),.b_we(1'b0),.b_addr(store_addr),.b_din(64'd0),.b_be(8'd0),.b_burst(store_burst),
        .b_busy(store_busy),.b_valid(store_valid),.b_dout(store_dout),
        .busy(d_busy),.valid(d_valid),.dout(d_dout),
        .rd(d_rd),.we(),.addr(d_addr),.din(),.be(),.burst(d_burst));
endmodule

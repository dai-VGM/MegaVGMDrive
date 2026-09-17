module c2_sim_top(
    input logic clk, reset, start, reference_reset, loop_halt,
    input logic [31:0] file_size,
    input logic ddr_busy, ddr_valid,
    input logic [63:0] ddr_dout,
    output logic ddr_rd, ddr_we,
    output logic [28:0] ddr_addr,
    output logic [63:0] ddr_din,
    output logic [7:0] ddr_be, ddr_burst,
    output logic rd_req,
    output logic [22:0] rd_addr,
    input logic rd_ready, rd_valid,
    input logic [7:0] rd_data,
    output logic busy, done, fatal, loaded,
    output logic [7:0] error_code,
    output logic ce_sid, reg_write,
    output logic [4:0] reg_addr,
    output logic [7:0] reg_data,
    output logic [63:0] native_cycle,
    output logic signed [17:0] audio, raw_audio, reference_audio,
    output logic sample_valid, audio_ready, raw_valid, reference_valid,
    output logic [31:0] writes,
    output logic [23:0] oscillator,
    output logic [15:0] frequency,
    output logic [3:0] pipe_state,
    output logic observed_model, sid_model,
    output logic [7:0] observed_timing,
    output logic [31:0] observed_num,observed_den,
	output logic loop_valid,loop_entry_pulse,loop_boundary_pulse,
	output logic [31:0] loop_count,transport_ticks,
	output logic sid_reset
);
    wire store_busy,store_valid,store_rd,store_we;
    wire [63:0] store_dout,store_din;
    wire [28:0] store_addr;
    wire [7:0] store_be,store_burst;
    wire transport_halt=1'b0;
    wire sid_model_8580,sid_timing_ntsc;
    engine_c_lab dut(.*);
    c2_ddr_mux mux(.clk(clk),.reset(reset),
        .a_rd(1'b0),.a_we(1'b0),.a_addr(29'd0),.a_din(64'd0),.a_be(8'd0),.a_burst(8'd0),
        .a_busy(),.a_valid(),.a_dout(),
        .b_rd(store_rd),.b_we(store_we),.b_addr(store_addr),.b_din(store_din),
        .b_be(store_be),.b_burst(store_burst),.b_busy(store_busy),
        .b_valid(store_valid),.b_dout(store_dout),
        .busy(ddr_busy),.valid(ddr_valid),.dout(ddr_dout),
        .rd(ddr_rd),.we(ddr_we),.addr(ddr_addr),.din(ddr_din),.be(ddr_be),.burst(ddr_burst));
    assign oscillator=dut.sound.sid.chip[0].v1.oscillator;
    assign frequency=dut.sound.sid.Voice_1_Freq[0];
    assign raw_audio=dut.sound.audio;
    assign raw_valid=dut.sound.sample_valid;
    assign pipe_state=dut.sound.sid.state;
    assign observed_model=dut.session_model;
    assign sid_model=dut.sound.session_model;
    assign observed_timing=dut.session_timing;
    assign observed_num=dut.session_clock_num;
    assign observed_den=dut.session_clock_den;
	assign sid_reset=dut.sound.reset;
    sid_session_wrapper clean_reference(
        .clk(clk),.reset(reference_reset || reset || !loaded),.ce_sid(ce_sid),.model(observed_model),
        .reg_addr(reg_addr),.reg_data(reg_data),.reg_write(reg_write),
        .audio(reference_audio),.sample_valid(reference_valid),.audio_ready(),.pipeline_running()
    );
endmodule

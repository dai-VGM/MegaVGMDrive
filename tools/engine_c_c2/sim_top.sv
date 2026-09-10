module c2_sim_top(
    input logic clk, reset, start, reference_reset,
    input logic [31:0] file_size,
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
    output logic [3:0] pipe_state
);
    engine_c_lab dut(.*);
    assign oscillator=dut.sound.sid.chip[0].v1.oscillator;
    assign frequency=dut.sound.sid.Voice_1_Freq[0];
    assign raw_audio=dut.sound.audio;
    assign raw_valid=dut.sound.sample_valid;
    assign pipe_state=dut.sound.sid.state;
    sid_session_wrapper clean_reference(
        .clk(clk),.reset(reference_reset || reset || !loaded),.ce_sid(ce_sid),.model(1'b0),
        .reg_addr(reg_addr),.reg_data(reg_data),.reg_write(reg_write),
        .audio(reference_audio),.sample_valid(reference_valid),.audio_ready(),.pipeline_running()
    );
endmodule

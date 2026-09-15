// SPDX-License-Identifier: GPL-2.0-or-later
// C4 adapter: parser EOF != transport completion. SID runs throughout the tail.
module engine_c_transport_profile #(
    parameter integer VGM_ADDR_WIDTH=23, CLK_SYS_HZ=20000000
)(
    input logic clk_sys, reset, download_active, transport_finish, transport_loop_halt,io_fault,
    output logic profile_started, parser_done, audio_ready,
    input logic [31:0] uploaded_physical_size,
    input logic upload_complete, file_read_ready, file_read_valid,
    input logic [7:0] file_read_data,
    output logic file_read_request,
    output logic [VGM_ADDR_WIDTH-1:0] file_read_address,
    output logic pcm_a_read_request, pcm_b_read_request,
    output logic [VGM_ADDR_WIDTH-1:0] pcm_a_read_address, pcm_b_read_address,
    input logic [1:0] osd_audio_lpf_mode, osd_audio_psg_level,
    input logic osd_audio_gain_boost, title_valid, shell_sample_timing,
    input logic [7:0] title_text_byte,
    output logic signed [15:0] profile_audio_l, profile_audio_r,
    output logic profile_audio_sample_valid, profile_audio_enable,
    output logic playback_active, profile_done, profile_fatal,
    output logic [15:0] profile_status, debug_page_data,
    output logic [31:0] parser_start_count, scanner_start_count, sound_write_count,
	output logic loop_valid,loop_entry_pulse,loop_boundary_pulse,
	output logic [31:0] loop_count,transport_ticks,
    input logic store_busy,store_valid,
    input logic [63:0] store_dout,
    output logic store_rd,store_we,
    output logic [28:0] store_addr,
    output logic [63:0] store_din,
    output logic [7:0] store_be,store_burst
);
    logic claimed, start, loaded, ready, raw_busy, raw_done, finished, engine_fatal;
    assign profile_fatal=engine_fatal || io_fault;
    assign profile_started=claimed && loaded && !session_reset;
    assign parser_done=profile_started && raw_done;
    assign playback_active=profile_started && !finished && !profile_fatal;
    assign profile_done=finished;
    assign audio_ready=ready;
    always @(posedge clk_sys) begin
        if(session_reset) finished<=0;
        else if(transport_finish && !profile_fatal) finished<=1;
    end
    logic [7:0] error_code;
    logic signed [17:0] audio;
    wire session_reset=reset || download_active;
    assign start=upload_complete && !claimed && !session_reset;
    always @(posedge clk_sys) begin
        if(session_reset) claimed<=0;
        else if(start) claimed<=1;
        if(reset) parser_start_count<=0;
        else if(start) parser_start_count<=parser_start_count+1;
    end
    engine_c_lab #(.AW(VGM_ADDR_WIDTH),.SYS_HZ(CLK_SYS_HZ)) engine (
		.clk(clk_sys),.reset(session_reset),.start(start),.transport_halt(finished || io_fault),
		.loop_halt(transport_loop_halt),.file_size(uploaded_physical_size),
        .rd_req(file_read_request),.rd_addr(file_read_address),.rd_ready(file_read_ready),
        .rd_valid(file_read_valid),.rd_data(file_read_data),.busy(raw_busy),
        .done(raw_done),.fatal(engine_fatal),.loaded(loaded),.error_code(error_code),
        .ce_sid(),.reg_write(),.reg_addr(),.reg_data(),.native_cycle(),
        .audio(audio),.sample_valid(profile_audio_sample_valid),.audio_ready(ready),
		.writes(sound_write_count),.loop_valid(loop_valid),.loop_entry_pulse(loop_entry_pulse),
		.loop_boundary_pulse(loop_boundary_pulse),.loop_count(loop_count),.transport_ticks(transport_ticks),
        .store_busy(store_busy),.store_valid(store_valid),.store_dout(store_dout),
        .store_rd(store_rd),.store_we(store_we),.store_addr(store_addr),.store_din(store_din),
        .store_be(store_be),.store_burst(store_burst)
    );
    assign profile_audio_enable=ready && playback_active && !profile_fatal && !session_reset;
    // Width adaptation only: signed 18 -> signed 16; no chip algorithm tuning.
    assign profile_audio_l=audio[17:2];
    assign profile_audio_r=audio[17:2];
    assign profile_status={error_code,4'd0,profile_fatal,profile_done,playback_active,loaded};
    assign debug_page_data=profile_status;
    assign scanner_start_count=parser_start_count;
    assign pcm_a_read_request=0;
    assign pcm_b_read_request=0;
    assign pcm_a_read_address=0;
    assign pcm_b_read_address=0;
endmodule

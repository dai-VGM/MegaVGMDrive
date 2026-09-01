`timescale 1ns/1ps

module tb_mode5_cold_start_handoff;
    localparam int FILE_SIZE = 76;
    localparam int POR_CYCLES = 8;
    localparam int COLD_START_DELAY_CYCLES = 20_000;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic reset_n = 1'b0;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;
    logic [15:0] ioctl_index = 16'd1;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_sample_valid;
    wire player_busy;
    wire audio_gate_open;
    wire audio_muted;
    wire mode5_load_ready;
    wire vgm_load_busy;
    wire vgm_load_done;
    wire vgm_header_valid;
    wire vgm_player_error;
    wire mode5_sound_reset_active;
    wire [31:0] playback_session;
    wire [31:0] load_begin_count;
    wire [31:0] player_start_count;

    byte file_bytes [0:FILE_SIZE-1];
    integer cycle = 0;
    integer active_session = 0;
    integer t0 [1:2];
    integer t_download_end [1:2];
    integer t_session [1:2];
    integer t_parser [1:2];
    integer t_first_write [1:2];
    integer t_positive_wait [1:2];
    integer t_first_sample [1:2];
    integer t_first_raw_nonzero [1:2];
    integer t_gate_open [1:2];
    integer t_first_final_nonzero [1:2];
    integer reset_after_parser [1:2];
    integer previous_session = 0;
    logic audio_gate_open_d = 1'b0;
    logic ready_seen = 1'b0;

    mister_vgm_md_top #(
        .REGION_MODE(5),
        .VGM_LOAD_ADDR_WIDTH(8),
        .MODE5_VGM_BACKEND(0),
        .POWER_ON_RESET_CYCLES(POR_CYCLES),
        .START_DELAY_CYCLES(COLD_START_DELAY_CYCLES),
        .INIT_AUDIO_SAMPLE_EDGES(0),
        .AUDIO_WARMUP_SAMPLES(0),
        .GATE_TO_START_CYCLES(0),
        .CLK_SYS_HZ(20_000_000),
        .VGM_WAIT_HZ(44_100),
        .MODE5_SOUND_RESET_CYCLES(8),
        .MODE5_AUDIO_UNMUTE_DELAY_CYCLES(0),
        .REPLAY_ENABLE(1'b0),
        .START_ACCEPT_TIMEOUT_CYCLES(100_000)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .audio_l(audio_l),
        .audio_r(audio_r),
        .audio_sample_valid(audio_sample_valid),
        .audio_lpf_mode(2'd0),
        .audio_gain_boost(1'b0),
        .audio_psg_level(2'd0),
        .player_busy(player_busy),
        .audio_gate_open(audio_gate_open),
        .audio_muted(audio_muted),
        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index),
        .ioctl_wait(),
        .mode5_load_ready(mode5_load_ready),
        .vgm_load_busy(vgm_load_busy),
        .vgm_load_done(vgm_load_done),
        .vgm_header_valid(vgm_header_valid),
        .vgm_player_error(vgm_player_error),
        .mode5_sound_reset_active(mode5_sound_reset_active),
        .mode5_playback_session_id(playback_session),
        .mode5_load_begin_count(load_begin_count),
        .mode5_player_start_count(player_start_count)
    );

    always @(posedge clk) begin
        cycle <= cycle + 1;
        audio_gate_open_d <= audio_gate_open;
`ifndef EXPECT_COLD_CUTOFF
        if (mode5_load_ready) begin
            ready_seen <= 1'b1;
            if (!audio_gate_open)
                $fatal(1, "mode5_load_ready asserted before final audio gate");
        end
        if (ready_seen && reset_n &&
            (!mode5_load_ready || !audio_gate_open))
            $fatal(1, "cold handoff readiness was not stable");
`endif

        if (playback_session != previous_session) begin
            active_session = playback_session;
            if (active_session >= 1 && active_session <= 2)
                t_session[active_session] = cycle;
            previous_session = playback_session;
        end

        if (active_session >= 1 && active_session <= 2) begin
            if (t_parser[active_session] < 0 &&
                t_download_end[active_session] >= 0 && player_busy)
                t_parser[active_session] = cycle;
            if (t_first_write[active_session] < 0 &&
                t_download_end[active_session] >= 0 &&
                dut.loaded_vgm_mode.psg_cmd_valid) begin
                t_first_write[active_session] = cycle;
            end
            if (t_positive_wait[active_session] < 0 &&
                t_parser[active_session] >= 0 &&
                dut.loaded_vgm_mode.positive_wait_active_debug)
                t_positive_wait[active_session] = cycle;
            if (t_first_sample[active_session] < 0 &&
                t_parser[active_session] >= 0 && audio_sample_valid)
                t_first_sample[active_session] = cycle;
            if (t_first_raw_nonzero[active_session] < 0 &&
                t_parser[active_session] >= 0 &&
                (dut.raw_audio_l != 16'sd0 || dut.raw_audio_r != 16'sd0))
                t_first_raw_nonzero[active_session] = cycle;
            if (t_gate_open[active_session] < 0 &&
                audio_gate_open && !audio_gate_open_d)
                t_gate_open[active_session] = cycle;
            if (t_first_final_nonzero[active_session] < 0 &&
                t_parser[active_session] >= 0 &&
                (audio_l != 16'sd0 || audio_r != 16'sd0))
                t_first_final_nonzero[active_session] = cycle;
            if (t_parser[active_session] >= 0 &&
                !ioctl_download &&
                dut.loaded_vgm_mode.mode5_loaded_player_reset)
                reset_after_parser[active_session] = 1;
        end
    end

    task automatic send_file(input integer session_number);
        integer i;
        begin
            @(negedge clk);
`ifndef EXPECT_COLD_CUTOFF
            if (!mode5_load_ready || !audio_gate_open)
                $fatal(1, "load_file %0d issued before handoff ready",
                    session_number);
`endif
            t0[session_number] = cycle;
            if (audio_gate_open)
                t_gate_open[session_number] = cycle;
            ioctl_download = 1'b1;
            for (i = 0; i < FILE_SIZE; i = i + 1) begin
                @(negedge clk);
                ioctl_addr = i;
                ioctl_dout = file_bytes[i];
                ioctl_wr = 1'b1;
                @(negedge clk);
                ioctl_wr = 1'b0;
            end
            @(negedge clk);
            ioctl_download = 1'b0;
            t_download_end[session_number] = cycle;
        end
    endtask

    task automatic wait_for_final_audio(input integer session_number);
        integer timeout;
        begin
            timeout = 0;
            while (t_first_final_nonzero[session_number] < 0 &&
                   timeout < 200_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (t_first_final_nonzero[session_number] < 0)
                $fatal(1, "session %0d produced no final audio", session_number);
        end
    endtask

    task automatic print_timeline(input integer session_number,
                                  input string label);
        begin
            $display("%s T0=%0d download_end=%0d session=%0d parser=%0d first_write=%0d positive_wait=%0d first_sample=%0d raw_nonzero=%0d gate_open=%0d final_nonzero=%0d reset_after_parser=%0d",
                label,
                t0[session_number] - t0[session_number],
                t_download_end[session_number] - t0[session_number],
                t_session[session_number] - t0[session_number],
                t_parser[session_number] - t0[session_number],
                t_first_write[session_number] - t0[session_number],
                t_positive_wait[session_number] - t0[session_number],
                t_first_sample[session_number] - t0[session_number],
                t_first_raw_nonzero[session_number] - t0[session_number],
                t_gate_open[session_number] < 0 ? -1 :
                    t_gate_open[session_number] - t0[session_number],
                t_first_final_nonzero[session_number] - t0[session_number],
                reset_after_parser[session_number]);
        end
    endtask

    integer i;
    initial begin
        for (i = 0; i < FILE_SIZE; i = i + 1) file_bytes[i] = 8'd0;
        for (i = 1; i <= 2; i = i + 1) begin
            t0[i] = -1;
            t_download_end[i] = -1;
            t_session[i] = -1;
            t_parser[i] = -1;
            t_first_write[i] = -1;
            t_positive_wait[i] = -1;
            t_first_sample[i] = -1;
            t_first_raw_nonzero[i] = -1;
            t_gate_open[i] = -1;
            t_first_final_nonzero[i] = -1;
            reset_after_parser[i] = 0;
        end

        file_bytes[0] = "V";
        file_bytes[1] = "g";
        file_bytes[2] = "m";
        file_bytes[3] = " ";
        file_bytes[4] = FILE_SIZE - 4;
        file_bytes['h08] = 8'h50;
        file_bytes['h09] = 8'h01;
        file_bytes['h34] = 8'h0c;
        file_bytes['h40] = 8'h50;
        file_bytes['h41] = 8'h80;
        file_bytes['h42] = 8'h50;
        file_bytes['h43] = 8'h04;
        file_bytes['h44] = 8'h50;
        file_bytes['h45] = 8'h90;
        file_bytes['h46] = 8'h61;
        file_bytes['h47] = 8'hff;
        file_bytes['h48] = 8'h00;
        file_bytes['h49] = 8'h50;
        file_bytes['h4a] = 8'h9f;
        file_bytes['h4b] = 8'h66;

        repeat (4) @(posedge clk);
        reset_n = 1'b1;

        wait (mode5_load_ready);
        send_file(1);
        wait_for_final_audio(1);

        send_file(2);
        wait_for_final_audio(2);

        print_timeline(1, "COLD");
        print_timeline(2, "WARM");
        $display("COUNTS load_file=%0d session=%0d player_start=%0d",
            load_begin_count, playback_session, player_start_count);

`ifdef EXPECT_COLD_CUTOFF
        if (!(t_first_raw_nonzero[1] >= 0 &&
              t_gate_open[1] > t_first_raw_nonzero[1] &&
              t_first_final_nonzero[1] >= t_gate_open[1]))
            $fatal(1, "cold cutoff was not reproduced");
`else
        if (t_gate_open[1] != t0[1])
            $fatal(1, "first load began before cold audio handoff readiness");
        if (t_first_final_nonzero[1] != t_first_raw_nonzero[1])
            $fatal(1, "cold playback hid or advanced internal audio");
`endif
        if (load_begin_count != 2 || playback_session != 2 ||
            player_start_count != 2)
            $fatal(1, "duplicate/lost load begin=%0d session=%0d start=%0d",
                load_begin_count, playback_session, player_start_count);
        if (reset_after_parser[1] || reset_after_parser[2])
            $fatal(1, "parser reset reasserted after playback start");
        if (t_first_final_nonzero[2] != t_first_raw_nonzero[2])
            $fatal(1, "warm playback hid or advanced internal audio");

        $display("PASS tb_mode5_cold_start_handoff");
        $finish;
    end
endmodule

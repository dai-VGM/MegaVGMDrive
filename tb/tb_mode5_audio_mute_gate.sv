`timescale 1ns/1ps

module tb_mode5_audio_mute_gate;

    logic clk = 1'b0;
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
    wire player_done;
    wire startup_reset_active;
    wire startup_waiting;
    wire startup_done;
    wire audio_gate_open;
    wire audio_muted;
    wire vgm_load_busy;
    wire vgm_load_done;
    wire vgm_load_error;
    wire vgm_load_overflow;
    wire vgm_header_valid;
    wire vgm_player_error;
    wire mode5_sound_reset_active;
    wire mode5_player_start_pulse_debug;

    always #5 clk = ~clk;

    mister_vgm_md_top #(
        .REGION_MODE                    (5),
        .VGM_LOAD_ADDR_WIDTH            (8),
        .VGM_LOAD_FILE_INDEX            (16'd1),
        .POWER_ON_RESET_CYCLES          (32'd4),
        .START_DELAY_CYCLES             (32'd4),
        .INIT_AUDIO_SAMPLE_EDGES        (16'd0),
        .AUDIO_WARMUP_SAMPLES           (16'd0),
        .GATE_TO_START_CYCLES           (16'd1),
        .CLK_SYS_HZ                     (32'd20_000_000),
        .VGM_WAIT_HZ                    (32'd44_100),
        .REPLAY_ENABLE                  (1'b0),
        .PLAYER_RESET_CYCLES            (32'd8),
        .START_ACCEPT_TIMEOUT_CYCLES    (32'd2000),
        .PLAYER_DONE_TIMEOUT_TICKS      (32'd1000),
        .REPLAY_DELAY_TICKS             (32'd8),
        .MODE5_SOUND_RESET_CYCLES       (32'd8),
        .MODE5_AUDIO_UNMUTE_DELAY_CYCLES(32'd8)
    ) dut (
        .clk                            (clk),
        .reset_n                        (reset_n),
        .audio_l                        (audio_l),
        .audio_r                        (audio_r),
        .audio_sample_valid             (audio_sample_valid),
        .player_busy                    (player_busy),
        .player_done                    (player_done),
        .player_pc_debug                (),
        .player_last_cmd_debug          (),
        .startup_reset_active           (startup_reset_active),
        .startup_waiting                (startup_waiting),
        .startup_done                   (startup_done),
        .audio_gate_open                (audio_gate_open),
        .audio_muted                    (audio_muted),
        .ioctl_download                 (ioctl_download),
        .ioctl_wr                       (ioctl_wr),
        .ioctl_addr                     (ioctl_addr),
        .ioctl_dout                     (ioctl_dout),
        .ioctl_index                    (ioctl_index),
        .vgm_load_busy                  (vgm_load_busy),
        .vgm_load_done                  (vgm_load_done),
        .vgm_load_error                 (vgm_load_error),
        .vgm_load_overflow              (vgm_load_overflow),
        .vgm_header_valid               (vgm_header_valid),
        .vgm_player_error               (vgm_player_error),
        .vgm_unsupported_opcode         (),
        .vgm_unsupported_pc             (),
        .vgm_player_error_code          (),
        .vgm_load_size                  (),
        .vgm_load_magic                 (),
        .vgm_data_start_debug           (),
        .vgm_current_pc_debug           (),
        .vgm_loop_pc_debug              (),
        .vgm_loop_valid_debug           (),
        .vgm_loop_taken_debug           (),
        .vgm_end_command_seen           (),
        .vgm_restarted_from_data_start  (),
        .vgm_pcm_oob                    (),
        .vgm_pcm_oob_count              (),
        .vgm_wait_ticks_consumed_debug  (),
        .mode5_sound_reset_active       (mode5_sound_reset_active),
        .mode5_player_start_pulse_debug (mode5_player_start_pulse_debug),
        .fm_adjust_clip_count_l         (),
        .fm_adjust_clip_count_r         (),
        .genmix_wrap_count_l            (),
        .genmix_wrap_count_r            (),
        .ym_write_requested_count       (),
        .ym_write_accepted_count        (),
        .ym_write_dropped_or_busy_count (),
        .ym_port0_count                 (),
        .ym_port1_count                 (),
        .last_ym_port                   (),
        .last_ym_addr                   (),
        .last_ym_data                   (),
        .jt12_cen_interval_1_count      (),
        .jt12_cen_interval_2_count      (),
        .jt12_cen_interval_3_count      (),
        .jt12_cen_interval_4_count      (),
        .jt12_cen_interval_ge5_count    (),
        .jt12_cen_interval_min          (),
        .jt12_cen_interval_max          (),
        .jt12_cen_interval_last         (),
        .fm_raw_abs_peak                (),
        .fm_adjust_abs_peak             (),
        .fm_lpf_abs_peak                (),
        .genmix_abs_peak                (),
        .md_final_audio_abs_peak        ()
    );

    function automatic [7:0] wait_vgm_byte(input int addr);
        begin
            unique case (addr)
                0: wait_vgm_byte = "V";
                1: wait_vgm_byte = "g";
                2: wait_vgm_byte = "m";
                3: wait_vgm_byte = " ";
                'h34: wait_vgm_byte = 8'h0c;
                'h35: wait_vgm_byte = 8'h00;
                'h36: wait_vgm_byte = 8'h00;
                'h37: wait_vgm_byte = 8'h00;
                'h40: wait_vgm_byte = 8'h61;
                'h41: wait_vgm_byte = 8'hff;
                'h42: wait_vgm_byte = 8'hff;
                'h43: wait_vgm_byte = 8'h66;
                default: wait_vgm_byte = 8'h00;
            endcase
        end
    endfunction

    task automatic assert_silent(input string label);
        begin
            if (!audio_muted || audio_l !== 16'sd0 || audio_r !== 16'sd0) begin
                $display("FAIL %s muted=%0b audio_l=%0d audio_r=%0d",
                         label, audio_muted, audio_l, audio_r);
                $finish;
            end
        end
    endtask

    task automatic write_download_byte(input int addr);
        begin
            @(posedge clk);
            ioctl_addr <= addr[26:0];
            ioctl_dout <= wait_vgm_byte(addr);
            ioctl_wr <= 1'b1;
            assert_silent("during load");
            @(posedge clk);
            ioctl_wr <= 1'b0;
            assert_silent("during load");
        end
    endtask

    task automatic load_wait_vgm;
        int i;
        begin
            @(posedge clk);
            ioctl_index <= 16'd1;
            ioctl_download <= 1'b1;
            for (i = 0; i <= 'h43; i = i + 1) begin
                write_download_byte(i);
            end
            @(posedge clk);
            ioctl_download <= 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        assert_silent("reset asserted");

        reset_n <= 1'b1;
        // Isolate the final mode5 mute gate from the existing startup FSM's
        // JT12 sample-strobe wait; this TB checks load/running/unmute-delay
        // behavior, not the audio core's sample generator.
        force dut.audio_gate_open = 1'b1;
        repeat (32) begin
            @(posedge clk);
            assert_silent("before load");
        end

        load_wait_vgm();

        wait (mode5_sound_reset_active);
        assert_silent("sound reset active");
        wait (mode5_player_start_pulse_debug);
        assert_silent("player start pulse");
        wait (player_busy && vgm_header_valid);
        assert_silent("before unmute delay");

        repeat (7) begin
            @(posedge clk);
            assert_silent("unmute delay");
        end

        repeat (20000) begin
            @(posedge clk);
            if (!audio_muted) begin
                if (!audio_gate_open || !player_busy || !vgm_load_done ||
                    vgm_load_busy || vgm_load_error || vgm_load_overflow ||
                    vgm_player_error) begin
                    $display("FAIL unmuted with bad state gate=%0b busy=%0b done=%0b load_busy=%0b load_error=%0b overflow=%0b player_error=%0b",
                             audio_gate_open, player_busy, vgm_load_done,
                             vgm_load_busy, vgm_load_error, vgm_load_overflow,
                             vgm_player_error);
                    $finish;
                end
                $display("PASS tb_mode5_audio_mute_gate");
                $finish;
            end
        end

        $display("FAIL audio did not unmute gate=%0b muted=%0b busy=%0b done=%0b header=%0b load_done=%0b load_busy=%0b load_error=%0b overflow=%0b player_error=%0b sample_valid=%0b startup_waiting=%0b startup_done=%0b",
                 audio_gate_open, audio_muted, player_busy, player_done,
                 vgm_header_valid, vgm_load_done, vgm_load_busy,
                 vgm_load_error, vgm_load_overflow, vgm_player_error,
                 audio_sample_valid, startup_waiting, startup_done);
        $finish;
    end

endmodule

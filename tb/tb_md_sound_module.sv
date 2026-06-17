`timescale 1ns/1ps

module tb_md_sound_module;

    logic clk = 1'b0;
    logic reset = 1'b1;

    logic       ym_cmd_valid = 1'b0;
    logic       ym_cmd_port  = 1'b0;
    logic [7:0] ym_cmd_reg   = 8'h00;
    logic [7:0] ym_cmd_data  = 8'h00;

    logic       psg_cmd_valid = 1'b0;
    logic [7:0] psg_cmd_data  = 8'h00;

    logic ym_cmd_ready;
    logic psg_cmd_ready;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    logic              audio_sample_valid;

    integer tb_ym_send_count = 0;
    integer tb_psg_send_count = 0;
    integer dut_ym_write_count = 0;
    integer dut_psg_write_count = 0;
    integer audio_sample_count = 0;
    integer audio_file = 0;
    integer audio_fm_only_file = 0;
    integer audio_psg_only_file = 0;
    integer audio_fm_l_file = 0;
    integer audio_fm_r_file = 0;
    integer audio_dump_count = 0;
    integer audio_sample_valid_count = 0;
    integer audio_sample_valid_count_at_dump_start = 0;
    integer audio_sample_valid_seen_by_writer = 0;
    integer wait_samples_call_count = 0;
    integer wait_samples_requested_total = 0;
    integer wait_samples_actual_total = 0;
    integer wait_samples_clk_total = 0;
    integer wait_samples_ym_write_during_wait = 0;
    integer wait_samples_psg_write_during_wait = 0;
    integer vgm_wait_sample_progress = 0;
    integer pcm_bank_size = 0;
    integer pcm_pos = 0;
    integer pcm_seek_count = 0;
    integer dac_stream_command_count = 0;
    integer dac_generated_write_count = 0;
    integer dac_enable_write_count = 0;
    logic [7:0] pcm_bank [0:65535];
    logic [31:0] tb_vgm_pc = 32'h00000000;
    logic [7:0] tb_last_cmd = 8'h00;
    logic audio_sample_valid_prev_mon = 1'b0;
    bit audio_record_done = 1'b0;

`ifdef TEST_PSG_TONE
    localparam int AUDIO_DUMP_SAMPLE_COUNT = 10000;
`elsif TEST_VGM_FULL_PCM_REGION_50K
    localparam int AUDIO_DUMP_SAMPLE_COUNT = 50000;
`elsif TEST_VGM_FULL_PCM_REGION_10K
    localparam int AUDIO_DUMP_SAMPLE_COUNT = 10000;
`elsif TEST_VGM_FULL_START_10K
    localparam int AUDIO_DUMP_SAMPLE_COUNT = 50000;
`elsif TEST_VGM_PCM_5K
    localparam int AUDIO_DUMP_SAMPLE_COUNT = 10000;
`else
    localparam int AUDIO_DUMP_SAMPLE_COUNT = 15000;
`endif

    md_sound_module dut (
        .clk           (clk),
        .reset         (reset),

        .ym_cmd_valid  (ym_cmd_valid),
        .ym_cmd_port   (ym_cmd_port),
        .ym_cmd_reg    (ym_cmd_reg),
        .ym_cmd_data   (ym_cmd_data),

        .psg_cmd_valid (psg_cmd_valid),
        .psg_cmd_data  (psg_cmd_data),

        .ym_cmd_ready  (ym_cmd_ready),
        .psg_cmd_ready (psg_cmd_ready),

        .audio_l            (audio_l),
        .audio_r            (audio_r),
        .audio_sample_valid (audio_sample_valid),
        .audio_lpf_mode     (2'b00),
        .audio_gain_boost   (1'b0),
        .audio_psg_level    (2'b00),
        .fm_adjust_clip_count_l(),
        .fm_adjust_clip_count_r(),
        .genmix_wrap_count_l(),
        .genmix_wrap_count_r(),
        .ym_write_requested_count(),
        .ym_write_accepted_count(),
        .ym_write_dropped_or_busy_count(),
        .ym_port0_count(),
        .ym_port1_count(),
        .last_ym_port(),
        .last_ym_addr(),
        .last_ym_data(),
        .jt12_cen_interval_1_count(),
        .jt12_cen_interval_2_count(),
        .jt12_cen_interval_3_count(),
        .jt12_cen_interval_4_count(),
        .jt12_cen_interval_ge5_count(),
        .jt12_cen_interval_min(),
        .jt12_cen_interval_max(),
        .jt12_cen_interval_last(),
        .fm_raw_abs_peak(),
        .fm_adjust_abs_peak(),
        .fm_lpf_abs_peak(),
        .genmix_abs_peak(),
        .final_audio_abs_peak()
    );

    // 100 MHz simulation clock. This is not the final Mega Drive master clock;
    // it is only a simple clock source for bring-up simulation.
    always #5 clk = ~clk;

    task automatic send_ym(
        input bit         port,
        input logic [7:0] regno,
        input logic [7:0] data
    );
        begin
            @(posedge clk);
            wait (ym_cmd_ready);
            @(posedge clk);
            ym_cmd_port  <= port;
            ym_cmd_reg   <= regno;
            ym_cmd_data  <= data;
            ym_cmd_valid <= 1'b1;
            tb_ym_send_count++;
            tb_last_cmd = port ? 8'h53 : 8'h52;
            if (!port && regno == 8'h2B) begin
                dac_enable_write_count++;
            end
`ifdef VERBOSE_TB_LOG
            if (tb_ym_send_count <= 20) begin
                $display("TB_SEND_YM count=%0d time=%0t port=%0d reg=%02h data=%02h",
                         tb_ym_send_count, $time, port, regno, data);
            end
`endif
            @(posedge clk);
            ym_cmd_valid <= 1'b0;
            ym_cmd_port  <= 1'b0;
            ym_cmd_reg   <= 8'h00;
            ym_cmd_data  <= 8'h00;
        end
    endtask

    task automatic send_psg(input logic [7:0] data);
        begin
            @(posedge clk);
            wait (psg_cmd_ready);
            @(posedge clk);
            psg_cmd_data  <= data;
            psg_cmd_valid <= 1'b1;
            tb_psg_send_count++;
            tb_last_cmd = 8'h50;
`ifdef VERBOSE_TB_LOG
            if (tb_psg_send_count <= 20) begin
                $display("TB_SEND_PSG count=%0d time=%0t data=%02h",
                         tb_psg_send_count, $time, data);
            end
`endif
            @(posedge clk);
            psg_cmd_valid <= 1'b0;
            psg_cmd_data  <= 8'h00;
        end
    endtask

    task automatic wait_samples(input integer n);
        integer waited;
        integer clk_waited;
        integer ym_writes_before;
        integer psg_writes_before;
            bit prev_audio_sample_valid;
            begin
            wait_samples_call_count++;
            tb_last_cmd = 8'h61;
            waited = 0;
            clk_waited = 0;
            ym_writes_before = tb_ym_send_count;
            psg_writes_before = tb_psg_send_count;
            prev_audio_sample_valid = audio_sample_valid;
            while (waited < n) begin
                @(posedge clk);
                clk_waited++;
                if (audio_sample_valid && !prev_audio_sample_valid) begin
                    waited++;
                end
                prev_audio_sample_valid = audio_sample_valid;
            end
            wait_samples_requested_total += n;
            wait_samples_actual_total += waited;
            wait_samples_clk_total += clk_waited;
            vgm_wait_sample_progress += waited;
            wait_samples_ym_write_during_wait += tb_ym_send_count - ym_writes_before;
            wait_samples_psg_write_during_wait += tb_psg_send_count - psg_writes_before;

`ifdef VERBOSE_TB_LOG
            if (wait_samples_call_count <= 20 ||
                (wait_samples_call_count % 1000) == 0) begin
                $display("TB_WAIT_SAMPLES count=%0d pc=%08h request=%0d actual_audio_sample_valid=%0d clk_waited=%0d ym_writes_during_wait=%0d psg_writes_during_wait=%0d totals request=%0d actual=%0d vgm_progress=%0d",
                         wait_samples_call_count, tb_vgm_pc, n, waited, clk_waited,
                         tb_ym_send_count - ym_writes_before,
                         tb_psg_send_count - psg_writes_before,
                         wait_samples_requested_total, wait_samples_actual_total,
                         vgm_wait_sample_progress);
            end
`endif
        end
    endtask

    task automatic send_ym_slow(
        input bit         port,
        input logic [7:0] regno,
        input logic [7:0] data
    );
        begin
            send_ym(port, regno, data);

            // md_sound_module now waits for the JT12 busy bit after each data
            // write, so one logical write is enough. Leave a tiny gap in the
            // testbench log so consecutive register writes are easy to read.
            repeat (16) @(posedge clk);
        end
    endtask

    task automatic run_psg_tone_test;
        begin
            $display("TEST_PSG_TONE_START time=%0t", $time);

            // Mute every PSG channel first.
            send_psg(8'h9F); // channel 0 volume: silent
            send_psg(8'hBF); // channel 1 volume: silent
            send_psg(8'hDF); // channel 2 volume: silent
            send_psg(8'hFF); // noise volume: silent

            // SN76489 tone channel 0 period = 0x100.
            // 0x80 latches channel 0 tone low nibble, the next byte writes high bits.
            send_psg(8'h80);
            send_psg(8'h10);

            // Channel 0 volume = 0, which is the loudest attenuation setting.
            send_psg(8'h90);
        end
    endtask

    task automatic run_ym_tone_test;
        begin
            $display("TEST_YM_TONE_START time=%0t", $time);

            // YM2612 channel 1 in user-facing terms is register channel index 0.
            // This is a deliberately simple 4-operator patch for bring-up:
            // algorithm 7 makes all operators audible as carriers, which is easy
            // to hear even if the patch is not musically polished.
            send_ym_slow(1'b0, 8'h22, 8'h00); // LFO off
            send_ym_slow(1'b0, 8'h27, 8'h00); // timers/off, normal channel mode
            send_ym_slow(1'b0, 8'h2B, 8'h00); // DAC off
            send_ym_slow(1'b0, 8'h28, 8'h00); // key off channel 1

            // Detune/multiple for operators 1..4.
            send_ym_slow(1'b0, 8'h30, 8'h01);
            send_ym_slow(1'b0, 8'h34, 8'h01);
            send_ym_slow(1'b0, 8'h38, 8'h01);
            send_ym_slow(1'b0, 8'h3C, 8'h01);

            // Total level. Keep the tone moderate to avoid clipping after WAV gain.
            send_ym_slow(1'b0, 8'h40, 8'h28);
            send_ym_slow(1'b0, 8'h44, 8'h28);
            send_ym_slow(1'b0, 8'h48, 8'h28);
            send_ym_slow(1'b0, 8'h4C, 8'h28);

            // Attack rate.
            send_ym_slow(1'b0, 8'h50, 8'h1F);
            send_ym_slow(1'b0, 8'h54, 8'h1F);
            send_ym_slow(1'b0, 8'h58, 8'h1F);
            send_ym_slow(1'b0, 8'h5C, 8'h1F);

            // Decay/sustain/release: hold a steady simple tone.
            send_ym_slow(1'b0, 8'h60, 8'h00);
            send_ym_slow(1'b0, 8'h64, 8'h00);
            send_ym_slow(1'b0, 8'h68, 8'h00);
            send_ym_slow(1'b0, 8'h6C, 8'h00);
            send_ym_slow(1'b0, 8'h70, 8'h00);
            send_ym_slow(1'b0, 8'h74, 8'h00);
            send_ym_slow(1'b0, 8'h78, 8'h00);
            send_ym_slow(1'b0, 8'h7C, 8'h00);
            send_ym_slow(1'b0, 8'h80, 8'h0F);
            send_ym_slow(1'b0, 8'h84, 8'h0F);
            send_ym_slow(1'b0, 8'h88, 8'h0F);
            send_ym_slow(1'b0, 8'h8C, 8'h0F);
            send_ym_slow(1'b0, 8'h90, 8'h00);
            send_ym_slow(1'b0, 8'h94, 8'h00);
            send_ym_slow(1'b0, 8'h98, 8'h00);
            send_ym_slow(1'b0, 8'h9C, 8'h00);

            // Frequency and pan. A4/A0 pick a middle-ish note, B4 pans both sides.
            send_ym_slow(1'b0, 8'hA4, 8'h22);
            send_ym_slow(1'b0, 8'hA0, 8'h69);
            send_ym_slow(1'b0, 8'hB0, 8'h07); // feedback 0, algorithm 7
            send_ym_slow(1'b0, 8'hB4, 8'hC0); // left + right

            // Key on all four operators for channel 1.
            send_ym_slow(1'b0, 8'h28, 8'hF0);
        end
    endtask

    always @(posedge clk) begin
        if (!reset && dut.jt12_wr_n == 1'b0) begin
            dut_ym_write_count++;
`ifdef VERBOSE_TB_LOG
            if (dut_ym_write_count <= 20) begin
                $display("DUT_JT12_WRITE count=%0d time=%0t ym_state=%0d fm_addr=%0d fm_din=%02h fm_wr_n=%0b",
                         dut_ym_write_count, $time, dut.ym_state,
                         dut.jt12_addr, dut.jt12_din, dut.jt12_wr_n);
            end
`endif
        end

        if (!reset && dut.jt89_wr_n == 1'b0) begin
            dut_psg_write_count++;
`ifdef VERBOSE_TB_LOG
            if (dut_psg_write_count <= 20) begin
                $display("DUT_JT89_WRITE count=%0d time=%0t psg_din=%02h psg_wr_n=%0b",
                         dut_psg_write_count, $time, dut.jt89_din, dut.jt89_wr_n);
            end
`endif
        end

        if (!reset) begin
            if (audio_sample_valid && !audio_sample_valid_prev_mon) begin
                audio_sample_valid_count++;
            end
            audio_sample_valid_prev_mon <= audio_sample_valid;

            audio_sample_count++;
`ifdef VERBOSE_TB_LOG
            if ((audio_sample_count % 200000) == 0) begin
                $display("AUDIO_MON time=%0t fm_l=%0d fm_r=%0d psg=%0d mix_l=%0d mix_r=%0d audio_l=%0d audio_r=%0d",
                         $time, dut.fm_left, dut.fm_right, dut.psg_sound,
                         dut.pre_lpf_l, dut.pre_lpf_r, audio_l, audio_r);
            end
`endif
        end

        if (reset) begin
            audio_sample_valid_prev_mon <= 1'b0;
        end
    end

`ifdef TEST_VGM_FULL_PCM_REGION_50K
    initial begin
        integer last_audio_sample_valid_count;
        integer idle_clk_count;

        last_audio_sample_valid_count = 0;
        idle_clk_count = 0;

        wait (!reset);
        wait (dut.audio_path_enable);

        while (!audio_record_done) begin
            @(posedge clk);

            if (audio_sample_valid_count != last_audio_sample_valid_count) begin
                last_audio_sample_valid_count = audio_sample_valid_count;
                idle_clk_count = 0;
            end else begin
                idle_clk_count++;
            end

            if (idle_clk_count >= 1000000) begin
                $display("AUDIO_WATCHDOG_TIMEOUT time=%0t idle_clk_count=%0d",
                         $time, idle_clk_count);
                $display("WATCHDOG_PROGRESS sample_count=%0d audio_dump_count=%0d audio_sample_valid_edges=%0d tb_vgm_pc=%08h last_cmd=%02h",
                         audio_sample_count,
                         audio_dump_count,
                         audio_sample_valid_count,
                         tb_vgm_pc,
                         tb_last_cmd);
                $display("WATCHDOG_WAIT wait_calls=%0d wait_requested_total=%0d wait_actual_edges_total=%0d wait_clk_total=%0d vgm_wait_sample_progress=%0d",
                         wait_samples_call_count,
                         wait_samples_requested_total,
                         wait_samples_actual_total,
                         wait_samples_clk_total,
                         vgm_wait_sample_progress);
                $display("WATCHDOG_WRITES ym_write_count=%0d psg_write_count=%0d dut_ym_write_count=%0d dut_psg_write_count=%0d",
                         tb_ym_send_count,
                         tb_psg_send_count,
                         dut_ym_write_count,
                         dut_psg_write_count);
                $display("WATCHDOG_PCM pcm_bank_size=%0d pcm_pos=%0d pcm_seek_count=%0d dac_stream_command_count=%0d dac_generated_write_count=%0d dac_enable_write_count=%0d",
                         pcm_bank_size,
                         pcm_pos,
                         pcm_seek_count,
                         dac_stream_command_count,
                         dac_generated_write_count,
                         dac_enable_write_count);
                $display("WATCHDOG_STATE ym_state=%0d ym_cmd_ready=%0b psg_cmd_ready=%0b jt12_wr_n=%0b jt12_addr=%0d jt12_din=%02h jt12_dout=%02h jt89_wr_n=%0b jt89_din=%02h audio_path_enable=%0b audio_sample_valid=%0b",
                         dut.ym_state,
                         ym_cmd_ready,
                         psg_cmd_ready,
                         dut.jt12_wr_n,
                         dut.jt12_addr,
                         dut.jt12_din,
                         dut.jt12_dout,
                         dut.jt89_wr_n,
                         dut.jt89_din,
                         dut.audio_path_enable,
                         audio_sample_valid);
                $finish;
            end
        end
    end
`endif

    initial begin
        bit audio_sample_valid_prev_writer;

`ifdef TEST_PSG_TONE
        audio_file = $fopen("/tmp/md_sound_psg_tone_final.txt", "w");
`elsif TEST_VGM_FULL_PCM_REGION_50K
        audio_file = $fopen("/tmp/md_sound_test_vgm_full_pcm_region_50k.txt", "w");
`elsif TEST_VGM_FULL_PCM_REGION_10K
        audio_file = $fopen("/tmp/md_sound_test_vgm_full_pcm_region_10k.txt", "w");
`elsif TEST_VGM_FULL_START_10K
        audio_file = $fopen("/tmp/md_sound_test_vgm_full_start_50k.txt", "w");
`elsif TEST_VGM_PCM_5K
        audio_file = $fopen("/tmp/md_sound_test_vgm_pcm_10k.txt", "w");
`else
        audio_file = $fopen("/tmp/md_sound_audio_15k.txt", "w");
`endif
        if (audio_file == 0) begin
`ifdef TEST_PSG_TONE
            $display("ERROR: failed to open /tmp/md_sound_psg_tone_final.txt");
`elsif TEST_VGM_FULL_PCM_REGION_50K
            $display("ERROR: failed to open /tmp/md_sound_test_vgm_full_pcm_region_50k.txt");
`elsif TEST_VGM_FULL_PCM_REGION_10K
            $display("ERROR: failed to open /tmp/md_sound_test_vgm_full_pcm_region_10k.txt");
`elsif TEST_VGM_FULL_START_10K
            $display("ERROR: failed to open /tmp/md_sound_test_vgm_full_start_50k.txt");
`elsif TEST_VGM_PCM_5K
            $display("ERROR: failed to open /tmp/md_sound_test_vgm_pcm_10k.txt");
`else
            $display("ERROR: failed to open /tmp/md_sound_audio_15k.txt");
`endif
            $finish;
        end
`ifdef TEST_PSG_TONE
        audio_fm_only_file = $fopen("/tmp/md_sound_psg_tone_fm_only.txt", "w");
`elsif TEST_VGM_FULL_PCM_REGION_50K
        audio_fm_only_file = $fopen("/tmp/md_sound_test_vgm_full_pcm_region_fm_only_50k.txt", "w");
`else
        audio_fm_only_file = $fopen("/tmp/md_sound_fm_only_15k.txt", "w");
`endif
        if (audio_fm_only_file == 0) begin
`ifdef TEST_PSG_TONE
            $display("ERROR: failed to open /tmp/md_sound_psg_tone_fm_only.txt");
`elsif TEST_VGM_FULL_PCM_REGION_50K
            $display("ERROR: failed to open /tmp/md_sound_test_vgm_full_pcm_region_fm_only_50k.txt");
`else
            $display("ERROR: failed to open /tmp/md_sound_fm_only_15k.txt");
`endif
            $finish;
        end
`ifdef TEST_PSG_TONE
        audio_psg_only_file = $fopen("/tmp/md_sound_psg_tone_psg_only.txt", "w");
`elsif TEST_VGM_FULL_PCM_REGION_50K
        audio_psg_only_file = $fopen("/tmp/md_sound_test_vgm_full_pcm_region_psg_only_50k.txt", "w");
`else
        audio_psg_only_file = $fopen("/tmp/md_sound_psg_only_15k.txt", "w");
`endif
        if (audio_psg_only_file == 0) begin
`ifdef TEST_PSG_TONE
            $display("ERROR: failed to open /tmp/md_sound_psg_tone_psg_only.txt");
`elsif TEST_VGM_FULL_PCM_REGION_50K
            $display("ERROR: failed to open /tmp/md_sound_test_vgm_full_pcm_region_psg_only_50k.txt");
`else
            $display("ERROR: failed to open /tmp/md_sound_psg_only_15k.txt");
`endif
            $finish;
        end
`ifdef DUMP_EXTRA_AUDIO
        audio_fm_l_file = $fopen("/tmp/md_sound_fm_l_20k.txt", "w");
        if (audio_fm_l_file == 0) begin
            $display("ERROR: failed to open /tmp/md_sound_fm_l_20k.txt");
            $finish;
        end
        audio_fm_r_file = $fopen("/tmp/md_sound_fm_r_20k.txt", "w");
        if (audio_fm_r_file == 0) begin
            $display("ERROR: failed to open /tmp/md_sound_fm_r_20k.txt");
            $finish;
        end
`endif

        wait (!reset);
        wait (dut.audio_path_enable);
`ifdef TEST_VGM_PCM_5K
        wait (dac_stream_command_count > 0);
`endif
        audio_sample_valid_count_at_dump_start = audio_sample_valid_count;
        audio_sample_valid_prev_writer = audio_sample_valid;
        $display("AUDIO_DUMP_START time=%0t trigger=audio_sample_valid samples=%0d",
                 $time, AUDIO_DUMP_SAMPLE_COUNT);

        while (audio_dump_count < AUDIO_DUMP_SAMPLE_COUNT) begin
            @(posedge clk);
            if (audio_sample_valid && !audio_sample_valid_prev_writer) begin
                $fdisplay(audio_file, "%0d %0d", audio_l, audio_r);
                $fdisplay(audio_fm_only_file, "%0d %0d", dut.fm_mixer_l, dut.fm_mixer_r);
                $fdisplay(audio_psg_only_file, "%0d %0d", dut.psg_adjust, dut.psg_adjust);
`ifdef DUMP_EXTRA_AUDIO
                $fdisplay(audio_fm_l_file, "%0d %0d", dut.fm_mixer_l, dut.fm_mixer_l);
                $fdisplay(audio_fm_r_file, "%0d %0d", dut.fm_mixer_r, dut.fm_mixer_r);
`endif
                audio_sample_valid_seen_by_writer++;
                audio_dump_count++;
            end
            audio_sample_valid_prev_writer = audio_sample_valid;
        end

        $fclose(audio_file);
        $fclose(audio_fm_only_file);
        $fclose(audio_psg_only_file);
`ifdef DUMP_EXTRA_AUDIO
        $fclose(audio_fm_l_file);
        $fclose(audio_fm_r_file);
`endif
        audio_record_done = 1'b1;
`ifdef TEST_PSG_TONE
        $display("AUDIO_DUMP_DONE time=%0t samples=%0d file=/tmp/md_sound_psg_tone_final.txt",
                 $time, audio_dump_count);
`elsif TEST_VGM_FULL_PCM_REGION_50K
        $display("AUDIO_DUMP_DONE time=%0t samples=%0d file=/tmp/md_sound_test_vgm_full_pcm_region_50k.txt",
                 $time, audio_dump_count);
`elsif TEST_VGM_FULL_PCM_REGION_10K
        $display("AUDIO_DUMP_DONE time=%0t samples=%0d file=/tmp/md_sound_test_vgm_full_pcm_region_10k.txt",
                 $time, audio_dump_count);
`elsif TEST_VGM_FULL_START_10K
        $display("AUDIO_DUMP_DONE time=%0t samples=%0d file=/tmp/md_sound_test_vgm_full_start_50k.txt",
                 $time, audio_dump_count);
`elsif TEST_VGM_PCM_5K
        $display("AUDIO_DUMP_DONE time=%0t samples=%0d file=/tmp/md_sound_test_vgm_pcm_10k.txt",
                 $time, audio_dump_count);
`else
        $display("AUDIO_DUMP_DONE time=%0t samples=%0d file=/tmp/md_sound_audio_15k.txt",
                 $time, audio_dump_count);
`endif
        $display("AUDIO_DUMP_CHECK audio_sample_valid_count=%0d audio_sample_valid_since_dump_start=%0d writer_seen_audio_sample_valid=%0d wav_written_samples=%0d match=%0d vgm_pc=%08h vgm_wait_sample_progress=%0d",
                 audio_sample_valid_count,
                 audio_sample_valid_count - audio_sample_valid_count_at_dump_start,
                 audio_sample_valid_seen_by_writer,
                 audio_dump_count,
                 (audio_sample_valid_seen_by_writer == audio_dump_count),
                 tb_vgm_pc,
                 vgm_wait_sample_progress);
        $display("WAIT_SUMMARY calls=%0d requested_total=%0d actual_audio_sample_valid_total=%0d clk_total=%0d ym_writes_during_wait=%0d psg_writes_during_wait=%0d",
                 wait_samples_call_count, wait_samples_requested_total,
                 wait_samples_actual_total, wait_samples_clk_total,
                 wait_samples_ym_write_during_wait,
                 wait_samples_psg_write_during_wait);
        $display("TB_FINAL_SUMMARY wav_written_samples=%0d audio_sample_valid_edges=%0d wait_samples_call_count=%0d wait_requested_total=%0d wait_actual_edges_total=%0d final_tb_vgm_pc=%08h ym_write_count=%0d psg_write_count=%0d",
                 audio_dump_count,
                 audio_sample_valid_count - audio_sample_valid_count_at_dump_start,
                 wait_samples_call_count,
                 wait_samples_requested_total,
                 wait_samples_actual_total,
                 tb_vgm_pc,
                 tb_ym_send_count,
                 tb_psg_send_count);
        $display("PCM_SUMMARY pcm_bank_size=%0d pcm_seek_count=%0d dac_stream_command_count=%0d dac_generated_write_count=%0d dac_enable_write_count=%0d",
                 pcm_bank_size,
                 pcm_seek_count,
                 dac_stream_command_count,
                 dac_generated_write_count,
                 dac_enable_write_count);
    end

    initial begin
`ifdef ENABLE_VCD
        $dumpfile("/tmp/tb_md_sound_module.vcd");
        $dumpvars(0, tb_md_sound_module);
`endif

        // Keep reset asserted long enough for the DUT and jt12 reset stretcher
        // to settle before accepting commands.
        repeat (32) @(posedge clk);
        reset <= 1'b0;

`ifdef TEST_PSG_TONE
        run_psg_tone_test();
`elsif TEST_YM_TONE
        run_ym_tone_test();
`else
        fork
            begin
`ifdef TEST_VGM_FULL_PCM_REGION_50K
                `include "/tmp/vgm_full_pcm_region.svh"
`elsif TEST_VGM_FULL_PCM_REGION_10K
                `include "/tmp/vgm_full_pcm_region.svh"
`elsif TEST_VGM_FULL_START_10K
                `include "/tmp/vgm_full_start.svh"
`elsif TEST_VGM_PCM_5K
                `include "/Users/daizo/Downloads/vgm_pcm_init.svh"
`else
                `include "/Users/daizo/Downloads/vgm_init.svh"
`endif
            end
`ifdef VERBOSE_TB_LOG
            begin
                repeat (8) begin
                    repeat (256) @(posedge clk);
                    $display("time=%0t audio_l=%0d audio_r=%0d", $time, audio_l, audio_r);
                end
            end
`endif
        join_none
`endif

        wait (audio_record_done);
        repeat (1024) @(posedge clk);
        $display("DONE");
        $finish;
    end

endmodule

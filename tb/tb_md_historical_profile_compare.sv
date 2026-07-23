`timescale 1ns/1ps

// Cross-revision sample comparator for the last hardware-verified MD-only
// audio profile (91193848) and the integrated production profile.
module tb_md_historical_profile_compare;
    localparam integer SAMPLE_COUNT = 2048;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ym_cmd_valid = 1'b0;
    logic ym_cmd_port = 1'b0;
    logic [7:0] ym_cmd_reg = 8'd0;
    logic [7:0] ym_cmd_data = 8'd0;
    logic psg_cmd_valid = 1'b0;
    logic [7:0] psg_cmd_data = 8'd0;
    logic ym_cmd_ready;
    logic psg_cmd_ready;
    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    logic audio_sample_valid;

    integer fixture = 0;
    integer gain = 0;
    integer sample_file;
    string sample_path;
    integer sample_count = 0;
    integer sample_min = 32767;
    integer sample_max = -32768;
    integer clip_count = 0;
    integer xz_count = 0;
    longint signed sum_sq = 0;
    longint unsigned cycle_count = 0;
    logic recording = 1'b0;
    logic [63:0] sample_hash = 64'hcbf29ce484222325;

    always #25 clk = ~clk; // Production clk_sys: exact 20 MHz.

    md_sound_module dut (
        .clk(clk),
        .reset(reset),
        .ym_cmd_valid(ym_cmd_valid),
        .ym_cmd_port(ym_cmd_port),
        .ym_cmd_reg(ym_cmd_reg),
        .ym_cmd_data(ym_cmd_data),
        .psg_cmd_valid(psg_cmd_valid),
        .psg_cmd_data(psg_cmd_data),
        .ym_cmd_ready(ym_cmd_ready),
        .psg_cmd_ready(psg_cmd_ready),
        .audio_l(audio_l),
        .audio_r(audio_r),
        .audio_sample_valid(audio_sample_valid),
        .audio_lpf_mode(2'b00),
        .audio_gain_boost(gain[0]),
        .audio_psg_level(2'b00),
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

    task automatic send_ym(input logic [7:0] reg_addr,
                           input logic [7:0] reg_data);
        begin
            while (!ym_cmd_ready) @(posedge clk);
            @(negedge clk);
            ym_cmd_reg = reg_addr;
            ym_cmd_data = reg_data;
            ym_cmd_valid = 1'b1;
            @(negedge clk);
            ym_cmd_valid = 1'b0;
            ym_cmd_reg = 8'd0;
            ym_cmd_data = 8'd0;
        end
    endtask

    task automatic send_psg(input logic [7:0] data);
        begin
            while (!psg_cmd_ready) @(posedge clk);
            @(negedge clk);
            psg_cmd_data = data;
            psg_cmd_valid = 1'b1;
            @(negedge clk);
            psg_cmd_valid = 1'b0;
            psg_cmd_data = 8'd0;
        end
    endtask

    task automatic wait_samples(input integer count);
        integer seen;
        begin
            seen = 0;
            while (seen < count) begin
                @(posedge clk);
                if (audio_sample_valid) seen++;
            end
        end
    endtask

    task automatic setup_fm;
        begin
            send_ym(8'h22, 8'h00);
            send_ym(8'h27, 8'h00);
            send_ym(8'h2b, 8'h00);
            send_ym(8'h30, 8'h01);
            send_ym(8'h34, 8'h01);
            send_ym(8'h38, 8'h01);
            send_ym(8'h3c, 8'h01);
            send_ym(8'h40, 8'h28);
            send_ym(8'h44, 8'h28);
            send_ym(8'h48, 8'h28);
            send_ym(8'h4c, 8'h28);
            send_ym(8'h50, 8'h1f);
            send_ym(8'h54, 8'h1f);
            send_ym(8'h58, 8'h1f);
            send_ym(8'h5c, 8'h1f);
            send_ym(8'ha4, 8'h22);
            send_ym(8'ha0, 8'h69);
            send_ym(8'hb0, 8'h07);
            send_ym(8'hb4, 8'hc0);
        end
    endtask

    task automatic setup_psg;
        begin
            send_psg(8'h9f);
            send_psg(8'hbf);
            send_psg(8'hdf);
            send_psg(8'hff);
            send_psg(8'h80);
            send_psg(8'h10);
            send_psg(8'h90);
        end
    endtask

    always @(posedge clk) begin
        longint signed square;
        cycle_count <= cycle_count + 1;
        if (recording && audio_sample_valid && sample_count < SAMPLE_COUNT) begin
            if ((^{dut.fm_left, dut.fm_right, dut.psg_sound,
                   dut.pre_lpf_postmix_l, dut.pre_lpf_selected_l,
                   audio_l, audio_r}) === 1'bx)
                xz_count++;
            square = $signed(audio_l) * $signed(audio_l);
            sum_sq = sum_sq + square;
            if ($signed(audio_l) < sample_min) sample_min = $signed(audio_l);
            if ($signed(audio_l) > sample_max) sample_max = $signed(audio_l);
            if (audio_l == 16'sh7fff || audio_l == 16'sh8000) clip_count++;
            sample_hash = (sample_hash ^ {32'd0, audio_l, audio_r}) *
                          64'h00000100000001b3;
            $fdisplay(sample_file,
                      "%0d %0d %0d %0d %0d %0d %0d %0d %0d",
                      sample_count, cycle_count,
                      $signed(dut.fm_left), $signed(dut.fm_right),
                      $signed(dut.psg_sound),
                      $signed(dut.pre_lpf_postmix_l),
                      $signed(dut.pre_lpf_selected_l),
                      $signed(audio_l), $signed(audio_r));
            sample_count++;
        end
    end

    initial begin
        integer timeout;
        if (!$value$plusargs("FIXTURE=%d", fixture)) fixture = 0;
        if (!$value$plusargs("GAIN=%d", gain)) gain = 0;
        if (!$value$plusargs("SAMPLE_FILE=%s", sample_path))
            sample_path = "/tmp/md-historical-profile-samples.txt";
        if (fixture < 0 || fixture > 2) $fatal(1, "invalid fixture");
        sample_file = $fopen(sample_path, "w");
        if (!sample_file) $fatal(1, "cannot open %s", sample_path);

        repeat (32) @(posedge clk);
        reset = 1'b0;
        timeout = 0;
        while (!dut.audio_path_enable && timeout < 2_000_000) begin
            timeout++;
            @(posedge clk);
        end
        if (!dut.audio_path_enable) $fatal(1, "audio startup timeout");
        wait_samples(128);

        case (fixture)
            0: begin
                setup_fm();
                recording = 1'b1;
                send_ym(8'h28, 8'hf0);
            end
            1: begin
                setup_psg();
                recording = 1'b1;
            end
            2: begin
                send_ym(8'h2b, 8'h80);
                fork
                    begin
                        for (integer i = 0; i < 8192; i++)
                            send_ym(8'h2a, 8'h20 + (i * 5));
                    end
                join_none
                wait_samples(128);
                recording = 1'b1;
            end
        endcase

        timeout = 0;
        while (sample_count < SAMPLE_COUNT && timeout < 20_000_000) begin
            timeout++;
            @(posedge clk);
        end
        if (sample_count != SAMPLE_COUNT)
            $fatal(1, "sample timeout count=%0d", sample_count);
        recording = 1'b0;
        $fclose(sample_file);
        if (xz_count != 0) $fatal(1, "X/Z samples=%0d", xz_count);
        $display("MD_HISTORICAL_PROFILE fixture=%0d gain=%0d samples=%0d min=%0d max=%0d sum_sq=%0d hash=%016h clips=%0d xz=%0d",
                 fixture, gain, sample_count, sample_min, sample_max, sum_sq,
                 sample_hash, clip_count, xz_count);
        $finish;
    end
endmodule

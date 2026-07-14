module tb_ym2151_pitch_ratio;
    localparam int MEASURE_CYCLES = 200_000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cmd_valid = 1'b0;
    logic [7:0] cmd_reg = 8'd0;
    logic [7:0] cmd_data = 8'd0;

    wire fixed_ready;
    wire legacy_ready;
    wire signed [15:0] fixed_audio_l;
    wire signed [15:0] legacy_audio_l;
    wire fixed_sample_valid;
    wire legacy_sample_valid;

    integer fixed_crossings = 0;
    integer legacy_crossings = 0;
    integer fixed_samples = 0;
    integer legacy_samples = 0;
    integer fixed_sample_strobes = 0;
    integer legacy_sample_strobes = 0;
    integer fixed_nonzero = 0;
    integer legacy_nonzero = 0;
    logic fixed_sign_valid = 1'b0;
    logic legacy_sign_valid = 1'b0;
    logic fixed_sign = 1'b0;
    logic legacy_sign = 1'b0;
    logic measuring = 1'b0;

    ym2151_sound_module #(
        .CLK_SYS_HZ              (32'd20_000_000),
        .YM2151_CLK_HZ           (32'd4_000_000),
        .LEGACY_FULL_RATE_CEN_P1 (1'b0)
    ) fixed_dut (
        .clk                (clk),
        .reset              (reset),
        .ym2151_cmd_valid   (cmd_valid),
        .ym2151_cmd_reg     (cmd_reg),
        .ym2151_cmd_data    (cmd_data),
        .ym2151_cmd_ready   (fixed_ready),
        .audio_l            (fixed_audio_l),
        .audio_r            (),
        .audio_sample_valid (fixed_sample_valid)
    );

    ym2151_sound_module #(
        .CLK_SYS_HZ              (32'd20_000_000),
        .YM2151_CLK_HZ           (32'd4_000_000),
        .LEGACY_FULL_RATE_CEN_P1 (1'b1)
    ) legacy_dut (
        .clk                (clk),
        .reset              (reset),
        .ym2151_cmd_valid   (cmd_valid),
        .ym2151_cmd_reg     (cmd_reg),
        .ym2151_cmd_data    (cmd_data),
        .ym2151_cmd_ready   (legacy_ready),
        .audio_l            (legacy_audio_l),
        .audio_r            (),
        .audio_sample_valid (legacy_sample_valid)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (reset || !measuring) begin
            fixed_sample_strobes <= 0;
            legacy_sample_strobes <= 0;
        end else begin
            if (fixed_sample_valid) fixed_sample_strobes <= fixed_sample_strobes + 1;
            if (legacy_sample_valid) legacy_sample_strobes <= legacy_sample_strobes + 1;
        end
    end

    always_ff @(posedge clk) begin
        if (reset || !measuring) begin
            fixed_crossings <= 0;
            fixed_samples <= 0;
            fixed_nonzero <= 0;
            fixed_sign_valid <= 1'b0;
            fixed_sign <= 1'b0;
        end else if (fixed_sample_valid && (^fixed_audio_l !== 1'bx)) begin
            fixed_samples <= fixed_samples + 1;
            if (fixed_audio_l != 16'sd0) begin
                fixed_nonzero <= fixed_nonzero + 1;
                if (fixed_sign_valid && fixed_sign != fixed_audio_l[15]) begin
                    fixed_crossings <= fixed_crossings + 1;
                end
                fixed_sign <= fixed_audio_l[15];
                fixed_sign_valid <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset || !measuring) begin
            legacy_crossings <= 0;
            legacy_samples <= 0;
            legacy_nonzero <= 0;
            legacy_sign_valid <= 1'b0;
            legacy_sign <= 1'b0;
        end else if (legacy_sample_valid && (^legacy_audio_l !== 1'bx)) begin
            legacy_samples <= legacy_samples + 1;
            if (legacy_audio_l != 16'sd0) begin
                legacy_nonzero <= legacy_nonzero + 1;
                if (legacy_sign_valid && legacy_sign != legacy_audio_l[15]) begin
                    legacy_crossings <= legacy_crossings + 1;
                end
                legacy_sign <= legacy_audio_l[15];
                legacy_sign_valid <= 1'b1;
            end
        end
    end

    task send_cmd(input logic [7:0] reg_addr, input logic [7:0] reg_data);
        begin
            while (!(fixed_ready && legacy_ready)) @(posedge clk);
            @(negedge clk);
            cmd_reg = reg_addr;
            cmd_data = reg_data;
            cmd_valid = 1'b1;
            @(negedge clk);
            cmd_valid = 1'b0;
            while (!(fixed_ready && legacy_ready)) @(posedge clk);
        end
    endtask

    task load_smoke_vgm_tone;
        begin
            // Exact YM2151 register setup from testdata/YM2151_SMOKE.VGM.
            send_cmd(8'h08, 8'h00);
            send_cmd(8'h18, 8'h00);
            send_cmd(8'h19, 8'h00);
            send_cmd(8'h1b, 8'hc0);
            send_cmd(8'h20, 8'hc7);
            send_cmd(8'h28, 8'h4a);
            send_cmd(8'h30, 8'h00);

            send_cmd(8'h40, 8'h01);
            send_cmd(8'h60, 8'h10);
            send_cmd(8'h80, 8'h1f);
            send_cmd(8'ha0, 8'h08);
            send_cmd(8'hc0, 8'h04);
            send_cmd(8'he0, 8'h0f);

            send_cmd(8'h48, 8'h01);
            send_cmd(8'h68, 8'h10);
            send_cmd(8'h88, 8'h1f);
            send_cmd(8'ha8, 8'h08);
            send_cmd(8'hc8, 8'h04);
            send_cmd(8'he8, 8'h0f);

            send_cmd(8'h50, 8'h01);
            send_cmd(8'h70, 8'h10);
            send_cmd(8'h90, 8'h1f);
            send_cmd(8'hb0, 8'h08);
            send_cmd(8'hd0, 8'h04);
            send_cmd(8'hf0, 8'h0f);

            send_cmd(8'h58, 8'h01);
            send_cmd(8'h78, 8'h10);
            send_cmd(8'h98, 8'h1f);
            send_cmd(8'hb8, 8'h08);
            send_cmd(8'hd8, 8'h04);
            send_cmd(8'hf8, 8'h0f);
            send_cmd(8'h08, 8'h78);
        end
    endtask

    initial begin
        // JT51's inferred shift registers require reset while cen_p1 clocks.
        // The wrapper normally stops its accumulator during reset, so force
        // only the test enable long enough to initialize those inferred SRLs.
        force fixed_dut.jt51_cen_p1 = 1'b1;
        force legacy_dut.jt51_cen_p1 = 1'b1;
        repeat (64) @(posedge clk);
        release fixed_dut.jt51_cen_p1;
        release legacy_dut.jt51_cen_p1;
        @(posedge clk);
        reset <= 1'b0;
        repeat (4) @(posedge clk);
        load_smoke_vgm_tone();

        // Let both envelopes reach a stable audible portion before comparing.
        repeat (20_000) @(posedge clk);
        measuring <= 1'b1;
        repeat (MEASURE_CYCLES) @(posedge clk);
        measuring <= 1'b0;
        @(posedge clk);

        if (fixed_samples == 0 || legacy_samples == 0) begin
            $display("FAIL no valid JT51 audio samples fixed=%0d/%0d legacy=%0d/%0d",
                     fixed_samples, fixed_sample_strobes,
                     legacy_samples, legacy_sample_strobes);
            $finish;
        end
        if (fixed_crossings < 8 || legacy_crossings < 16) begin
            $display("FAIL insufficient tone crossings fixed=%0d/%0d legacy=%0d/%0d",
                     fixed_crossings, fixed_nonzero,
                     legacy_crossings, legacy_nonzero);
            $finish;
        end
        if ((legacy_crossings * 100 < fixed_crossings * 190) ||
            (legacy_crossings * 100 > fixed_crossings * 210)) begin
            $display("FAIL legacy/fixed pitch ratio is not 2.0: fixed=%0d legacy=%0d",
                     fixed_crossings, legacy_crossings);
            $finish;
        end

        $display("PASS tb_ym2151_pitch_ratio fixed_crossings=%0d legacy_crossings=%0d ratio_x1000=%0d fixed_samples=%0d legacy_samples=%0d",
                 fixed_crossings, legacy_crossings,
                 (legacy_crossings * 1000) / fixed_crossings,
                 fixed_samples, legacy_samples);
        $finish;
    end
endmodule

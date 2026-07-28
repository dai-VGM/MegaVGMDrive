`timescale 1ns/1ps

/* verilator lint_off BLKSEQ */
module tb_megavgm_video_timing;
    localparam realtime VIDEO_HALF_PERIOD_NS = 19.8609731877;

    logic clk_video;
    logic reset = 1'b1;
    logic forced_scandoubler = 1'b0;

    wire raw_ce_pix;
    wire [8:0] h_count;
    wire [8:0] v_count;
    wire raw_hblank;
    wire raw_vblank;
    wire raw_hsync;
    wire raw_vsync;
    wire raw_de;
    wire vblank_start;

    wire mixer_ce_pixel;
    wire [7:0] mixer_r;
    wire [7:0] mixer_g;
    wire [7:0] mixer_b;
    wire mixer_hs;
    wire mixer_vs;
    wire mixer_de;
    /* verilator lint_off SYNCASYNCNET */
    tri [21:0] gamma_bus;
    /* verilator lint_on SYNCASYNCNET */

    assign gamma_bus[20:0] = 21'd0;

    initial clk_video = 1'b0;
    always #(VIDEO_HALF_PERIOD_NS) clk_video = ~clk_video;

    megavgm_video_timing timing (
        .clk_video   (clk_video),
        .reset       (reset),
        .ce_pix      (raw_ce_pix),
        .h_count     (h_count),
        .v_count     (v_count),
        .hblank      (raw_hblank),
        .vblank      (raw_vblank),
        .hsync       (raw_hsync),
        .vsync       (raw_vsync),
        .de          (raw_de),
        .vblank_start(vblank_start)
    );

    video_mixer #(
        .LINE_LENGTH(324),
        .HALF_DEPTH(0),
        .GAMMA(1)
    ) mixer (
        .CLK_VIDEO (clk_video),
        .CE_PIXEL  (mixer_ce_pixel),
        .ce_pix    (raw_ce_pix),
        .scandoubler(forced_scandoubler),
        .hq2x      (1'b0),
        .gamma_bus (gamma_bus),
        .R         (raw_de ? {h_count[4:0], 3'b000} : 8'd0),
        .G         (raw_de ? {v_count[4:0], 3'b000} : 8'd0),
        .B         (raw_de ? 8'h40 : 8'd0),
        .HSync     (raw_hsync),
        .VSync     (raw_vsync),
        .HBlank    (raw_hblank),
        .VBlank    (raw_vblank),
        .HDMI_FREEZE(1'b0),
        .freeze_sync(),
        .VGA_R     (mixer_r),
        .VGA_G     (mixer_g),
        .VGA_B     (mixer_b),
        .VGA_VS    (mixer_vs),
        .VGA_HS    (mixer_hs),
        .VGA_DE    (mixer_de)
    );

    task automatic wait_raw_frame_start;
        begin
            do @(posedge clk_video);
            while (!(raw_ce_pix && (h_count == 9'd0) && (v_count == 9'd0)));
        end
    endtask

    task automatic check_raw_frame;
        integer ce_count;
        integer de_count;
        integer hsync_count;
        integer vsync_count;
        integer line_count;
        integer vblank_start_count;
        integer xz_count;
        logic previous_ce;
        realtime frame_start;
        realtime frame_end;
        real frame_hz;
        real horizontal_hz;
        real ce_hz;
        begin
            wait_raw_frame_start();
            frame_start = $realtime;
            // wait_raw_frame_start consumed the first active pixel.
            ce_count = 1;
            de_count = 1;
            hsync_count = 0;
            vsync_count = 0;
            line_count = 1;
            vblank_start_count = 0;
            xz_count = 0;
            previous_ce = 1'b0;

            forever begin
                @(posedge clk_video);
                if ((^{
                    raw_ce_pix, h_count, v_count, raw_hblank, raw_vblank,
                    raw_hsync, raw_vsync, raw_de
                }) === 1'bx) begin
                    xz_count = xz_count + 1;
                end
                if (raw_ce_pix && previous_ce) begin
                    $fatal(1, "raw CE_PIXEL wider than one video clock");
                end
                previous_ce = raw_ce_pix;

                if (raw_ce_pix &&
                    (h_count == 9'd0) &&
                    (v_count == 9'd0)) begin
                    frame_end = $realtime;
                    break;
                end

                if (raw_ce_pix) begin
                    ce_count = ce_count + 1;
                    if (vblank_start)
                        vblank_start_count = vblank_start_count + 1;
                    if (raw_de) de_count = de_count + 1;
                    if (raw_hsync) hsync_count = hsync_count + 1;
                    if (raw_vsync) vsync_count = vsync_count + 1;
                    if (h_count == 9'd0) line_count = line_count + 1;
                end
            end

            frame_hz = 1.0e9 / (frame_end - frame_start);
            horizontal_hz = frame_hz * line_count;
            ce_hz = ce_count * frame_hz;

            if (ce_count != 400 * 262)
                $fatal(1, "raw frame CE count %0d", ce_count);
            if (de_count != 320 * 240)
                $fatal(1, "raw active count %0d", de_count);
            if (line_count != 262)
                $fatal(1, "raw line count %0d", line_count);
            if (vblank_start_count != 1)
                $fatal(1, "raw VBlank start pulse count %0d",
                       vblank_start_count);
            if (hsync_count != 32 * 262)
                $fatal(1, "raw HSync width/count %0d", hsync_count);
            if (vsync_count != 3 * 400)
                $fatal(1, "raw VSync width/count %0d", vsync_count);
            if (xz_count != 0)
                $fatal(1, "raw timing X/Z count %0d", xz_count);
            if ((horizontal_hz < 15733.0) || (horizontal_hz > 15736.0))
                $fatal(1, "raw horizontal rate %0f", horizontal_hz);
            if ((frame_hz < 60.04) || (frame_hz > 60.07))
                $fatal(1, "raw frame rate %0f", frame_hz);

            $display(
                "RAW PASS master_hz=25175000 ce_hz=%0.3f active=320x240 total=400x262 hsync=32 positive vsync=3 positive h_hz=%0.6f v_hz=%0.6f xz=%0d",
                ce_hz, horizontal_hz, frame_hz, xz_count
            );
        end
    endtask

    task automatic wait_mixer_vsync_rise;
        logic previous_vs;
        begin
            previous_vs = mixer_vs;
            forever begin
                @(negedge clk_video);
                if (!previous_vs && mixer_vs) break;
                previous_vs = mixer_vs;
            end
        end
    endtask

    task automatic check_mixer_mode(
        input bit expected_scandoubler,
        input real expected_horizontal_hz
    );
        integer hsync_rises;
        integer de_samples;
        integer color_changes;
        integer xz_count;
        logic previous_hs;
        logic previous_vs;
        logic previous_ce;
        logic [23:0] previous_rgb;
        realtime frame_start;
        realtime frame_end;
        real frame_hz;
        real horizontal_hz;
        begin
            forced_scandoubler = expected_scandoubler;
            repeat (3) wait_mixer_vsync_rise();

            wait_mixer_vsync_rise();
            frame_start = $realtime;
            hsync_rises = 0;
            de_samples = 0;
            color_changes = 0;
            xz_count = 0;
            previous_hs = mixer_hs;
            previous_vs = mixer_vs;
            previous_ce = 1'b0;
            previous_rgb = {mixer_r, mixer_g, mixer_b};

            forever begin
                @(negedge clk_video);
                if ((^{
                    mixer_ce_pixel, mixer_r, mixer_g, mixer_b,
                    mixer_hs, mixer_vs, mixer_de
                }) === 1'bx) begin
                    xz_count = xz_count + 1;
                end
                if (mixer_ce_pixel && previous_ce)
                    $fatal(1, "mixer CE_PIXEL wider than one video clock");
                previous_ce = mixer_ce_pixel;

                if (!previous_hs && mixer_hs)
                    hsync_rises = hsync_rises + 1;
                previous_hs = mixer_hs;

                if (!previous_vs && mixer_vs) begin
                    frame_end = $realtime;
                    break;
                end
                previous_vs = mixer_vs;

                if (mixer_ce_pixel && mixer_de) begin
                    de_samples = de_samples + 1;
                    if ({mixer_r, mixer_g, mixer_b} != previous_rgb)
                        color_changes = color_changes + 1;
                    previous_rgb = {mixer_r, mixer_g, mixer_b};
                end

            end

            frame_hz = 1.0e9 / (frame_end - frame_start);
            horizontal_hz = hsync_rises * frame_hz;

            if (xz_count != 0)
                $fatal(1, "mixer X/Z count %0d", xz_count);
            if (de_samples == 0)
                $fatal(1, "mixer produced no active pixels");
            if (color_changes == 0)
                $fatal(1, "mixer active image did not change");
            if ((frame_hz < 60.0) || (frame_hz > 60.1))
                $fatal(1, "mixer frame rate %0f", frame_hz);
            if ((horizontal_hz < expected_horizontal_hz - 30.0) ||
                (horizontal_hz > expected_horizontal_hz + 30.0)) begin
                $fatal(1, "mixer horizontal rate %0f expected %0f",
                       horizontal_hz, expected_horizontal_hz);
            end

            $display(
                "MIXER PASS forced=%0d h_hz=%0.6f v_hz=%0.6f hsync_lines=%0d active_samples=%0d changes=%0d xz=%0d",
                expected_scandoubler, horizontal_hz, frame_hz,
                hsync_rises, de_samples, color_changes, xz_count
            );
        end
    endtask

    initial begin
        repeat (16) @(posedge clk_video);
        reset = 1'b0;

        check_raw_frame();
        check_mixer_mode(1'b0, 15734.375);
        check_mixer_mode(1'b1, 31468.750);

        $display("PASS tb_megavgm_video_timing");
        $finish;
    end

    initial begin
        #500ms;
        $fatal(1, "video timing timeout");
    end
endmodule

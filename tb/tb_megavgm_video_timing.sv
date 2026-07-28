`timescale 1ns/1ps

/* verilator lint_off BLKSEQ */
module tb_megavgm_video_timing;
    localparam realtime VIDEO_HALF_PERIOD_NS = 25.0;

    logic clk_video;
    logic reset = 1'b1;

    wire raw_ce_pix;
    wire [8:0] h_count;
    wire [8:0] v_count;
    wire raw_hblank;
    wire raw_vblank;
    wire raw_hsync;
    wire raw_vsync;
    wire raw_de;
    wire vblank_start;

    wire public_ce_pixel = raw_ce_pix;
    wire [7:0] public_r = raw_de ?
                          {h_count[4:0], 3'b000} : 8'd0;
    wire [7:0] public_g = raw_de ?
                          {v_count[4:0], 3'b000} : 8'd0;
    wire [7:0] public_b = raw_de ? 8'h40 : 8'd0;
    wire public_hs = raw_hsync;
    wire public_vs = raw_vsync;
    wire public_de = raw_de;

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
        integer clocks_since_ce;
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
            clocks_since_ce = 0;
            previous_ce = 1'b0;

            forever begin
                @(posedge clk_video);
                clocks_since_ce = clocks_since_ce + 1;
                if ((^{
                    raw_ce_pix, h_count, v_count, raw_hblank, raw_vblank,
                    raw_hsync, raw_vsync, raw_de, public_ce_pixel,
                    public_r, public_g, public_b, public_hs, public_vs,
                    public_de
                }) === 1'bx) begin
                    xz_count = xz_count + 1;
                end
                if ((public_ce_pixel !== raw_ce_pix) ||
                    (public_hs !== raw_hsync) ||
                    (public_vs !== raw_vsync) ||
                    (public_de !== raw_de)) begin
                    $fatal(1, "public native timing differs from raw timing");
                end
                if (!public_de &&
                    ({public_r, public_g, public_b} !== 24'd0)) begin
                    $fatal(1, "public RGB is nonzero outside active video");
                end
                if (raw_ce_pix && previous_ce) begin
                    $fatal(1, "raw CE_PIXEL wider than one video clock");
                end
                if (raw_ce_pix && (clocks_since_ce != 3)) begin
                    $fatal(1, "raw CE_PIXEL interval %0d clocks",
                           clocks_since_ce);
                end
                if (raw_ce_pix)
                    clocks_since_ce = 0;
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

            if (ce_count != 424 * 262)
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
            if (vsync_count != 3 * 424)
                $fatal(1, "raw VSync width/count %0d", vsync_count);
            if (xz_count != 0)
                $fatal(1, "raw timing X/Z count %0d", xz_count);
            if ((horizontal_hz < 15722.0) || (horizontal_hz > 15725.0))
                $fatal(1, "raw horizontal rate %0f", horizontal_hz);
            if ((frame_hz < 60.00) || (frame_hz > 60.03))
                $fatal(1, "raw frame rate %0f", frame_hz);

            $display(
                "RAW PASS master_hz=20000000 ce_hz=%0.3f interval=3 active=320x240 total=424x262 hsync=32 positive vsync=3 positive h_hz=%0.6f v_hz=%0.6f xz=%0d",
                ce_hz, horizontal_hz, frame_hz, xz_count
            );
        end
    endtask

    initial begin
        repeat (16) @(posedge clk_video);
        reset = 1'b0;

        check_raw_frame();

        $display("PASS tb_megavgm_video_timing");
        $finish;
    end

    initial begin
        #500ms;
        $fatal(1, "video timing timeout");
    end
endmodule

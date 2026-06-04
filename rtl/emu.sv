// Video-only MiSTer baseline for VGM MD bring-up.
//
// This file intentionally stays close to the official Template_MiSTer emu
// shape. The current goal is not sound yet; it is only to prove that the
// Template_MiSTer outer shell boots on real MiSTer hardware:
//
// - monitor keeps video sync
// - fixed color video appears
// - core name appears
// - MiSTer menu can return
//
// md_sound_module / JT12 / JT89 / vgm_region_player are not instantiated here.
// They remain available for the next phase after video-only baseline passes.

module emu (
    `include "sys/emu_ports.vh"
);

    ///////// Default values for ports not used in this baseline /////////

    assign ADC_BUS  = 'Z;
    assign USER_OUT = '1;
    assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
    assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
    assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE,
            SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS,
            SDRAM_nRAS, SDRAM_nCS} = 'Z;
    assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN,
            DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

`ifdef MISTER_DUAL_SDRAM
    assign {SDRAM2_CLK, SDRAM2_A, SDRAM2_BA, SDRAM2_DQ,
            SDRAM2_nWE, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nCS} = 'Z;
`endif

`ifdef MISTER_FB
    assign FB_EN = 1'b0;
    assign FB_FORMAT = 5'd0;
    assign FB_WIDTH = 12'd0;
    assign FB_HEIGHT = 12'd0;
    assign FB_BASE = 32'd0;
    assign FB_STRIDE = 14'd0;
    assign FB_FORCE_BLANK = 1'b0;
`ifdef MISTER_FB_PALETTE
    assign FB_PAL_CLK = clk_sys;
    assign FB_PAL_ADDR = 8'd0;
    assign FB_PAL_DOUT = 24'd0;
    assign FB_PAL_WR = 1'b0;
`endif
`endif

    assign VGA_SL = 2'b00;
    assign VGA_F1 = 1'b0;
    assign VGA_SCALER = 1'b0;
    assign VGA_DISABLE = 1'b0;
    assign HDMI_FREEZE = 1'b0;
    assign HDMI_BLACKOUT = 1'b0;
    assign HDMI_BOB_DEINT = 1'b0;

    assign AUDIO_S = 1'b1;
    assign AUDIO_L = 16'sd0;
    assign AUDIO_R = 16'sd0;
    assign AUDIO_MIX = 2'b00;

    assign LED_DISK = 2'b00;
    assign LED_POWER = 2'b00;
    assign BUTTONS = 2'b00;

    //////////////////////////////////////////////////////////////////

    localparam CONF_STR = {
        "VGM_MD;;",
        "-;",
        "T0,Reset;",
        "R0,Reset and close OSD;",
        "v,2;"
    };

    wire        forced_scandoubler;
    wire [1:0]  buttons;
    wire [127:0] status;
    wire [10:0] ps2_key;

    hps_io #(.CONF_STR(CONF_STR)) hps_io (
        .clk_sys            (clk_sys),
        .HPS_BUS            (HPS_BUS),
        .EXT_BUS            (),
        .gamma_bus          (),
        .forced_scandoubler (forced_scandoubler),
        .buttons            (buttons),
        .status             (status),
        .status_menumask    (16'd0),
        .ps2_key            (ps2_key)
    );

    ///////////////////////   CLOCKS   ///////////////////////////////

    // Keep Template_MiSTer's pattern: CLK_VIDEO is generated from the core PLL.
    // sys_top routes CLK_VIDEO to video clock select blocks where this must be
    // a PLL output, not raw CLK_50M.
    wire clk_sys;
    wire pll_locked;

    pll pll (
        .refclk   (CLK_50M),
        .rst      (1'b0),
        .outclk_0 (clk_sys),
        .locked   (pll_locked)
    );

    wire reset = RESET | status[0] | buttons[1] | !pll_locked;

    ///////////////////////   VIDEO   ////////////////////////////////

    // Simple 640x480-style debug raster. This replaces Template's mycore with
    // a fixed color generator, while keeping the Template emu/sys_top boundary.
    reg       ce_pix;
    reg [9:0] h_count;
    reg [9:0] v_count;
    reg [7:0] post_reset_frames;

    always @(posedge clk_sys) begin
        if (reset) begin
            ce_pix <= 1'b0;
            h_count <= 10'd0;
            v_count <= 10'd0;
            post_reset_frames <= 8'd0;
        end else begin
            ce_pix <= ~ce_pix;

            if (ce_pix) begin
                if (h_count == 10'd799) begin
                    h_count <= 10'd0;

                    if (v_count == 10'd524) begin
                        v_count <= 10'd0;
                        if (post_reset_frames != 8'hff) begin
                            post_reset_frames <= post_reset_frames + 8'd1;
                        end
                    end else begin
                        v_count <= v_count + 10'd1;
                    end
                end else begin
                    h_count <= h_count + 10'd1;
                end
            end
        end
    end

    wire hblank = (h_count >= 10'd640);
    wire vblank = (v_count >= 10'd480);
    wire active = !hblank && !vblank;

    wire hsync = ~((h_count >= 10'd656) && (h_count < 10'd752));
    wire vsync = ~((v_count >= 10'd490) && (v_count < 10'd492));

    // reset: black
    // first frames after reset: blue
    // stable running: teal/green, easy to distinguish from a black/no-signal
    wire [7:0] dbg_r = reset ? 8'h00 : (post_reset_frames < 8'd8 ? 8'h10 : 8'h00);
    wire [7:0] dbg_g = reset ? 8'h00 : (post_reset_frames < 8'd8 ? 8'h30 : 8'hb0);
    wire [7:0] dbg_b = reset ? 8'h00 : (post_reset_frames < 8'd8 ? 8'hc0 : 8'h80);

    assign CLK_VIDEO = clk_sys;
    assign CE_PIXEL = ce_pix;

    assign VGA_DE = active;
    assign VGA_HS = hsync;
    assign VGA_VS = vsync;
    assign VGA_R  = active ? dbg_r : 8'd0;
    assign VGA_G  = active ? dbg_g : 8'd0;
    assign VGA_B  = active ? dbg_b : 8'd0;

    assign VIDEO_ARX = 13'd4;
    assign VIDEO_ARY = 13'd3;

    reg [26:0] act_cnt;
    always @(posedge clk_sys) begin
        act_cnt <= reset ? 27'd0 : act_cnt + 27'd1;
    end

    assign LED_USER = act_cnt[25];

    wire unused_inputs = ^{
        forced_scandoubler,
        status,
        ps2_key,
        HDMI_WIDTH,
        HDMI_HEIGHT,
        CLK_AUDIO,
        SD_MISO,
        SD_CD,
        DDRAM_BUSY,
        DDRAM_DOUT,
        DDRAM_DOUT_READY,
        UART_CTS,
        UART_RXD,
        UART_DSR,
        USER_IN,
        OSD_STATUS
    };

endmodule

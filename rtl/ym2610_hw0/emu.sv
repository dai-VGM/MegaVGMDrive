`timescale 1ns/1ps

module emu (
    input CLK_50M,
    input RESET,
    inout [48:0] HPS_BUS,
    output CLK_VIDEO,
    output CE_PIXEL,
    output [12:0] VIDEO_ARX,
    output [12:0] VIDEO_ARY,
    output [7:0] VGA_R,
    output [7:0] VGA_G,
    output [7:0] VGA_B,
    output VGA_HS,
    output VGA_VS,
    output VGA_DE,
    output VGA_F1,
    output [1:0] VGA_SL,
    output VGA_SCALER,
    output VGA_DISABLE,
    input [11:0] HDMI_WIDTH,
    input [11:0] HDMI_HEIGHT,
    output HDMI_FREEZE,
    output HDMI_BLACKOUT,
`ifdef MISTER_FB
    output FB_EN,
    output [4:0] FB_FORMAT,
    output [11:0] FB_WIDTH,
    output [11:0] FB_HEIGHT,
    output [31:0] FB_BASE,
    output [13:0] FB_STRIDE,
    input FB_VBL,
    input FB_LL,
    output FB_FORCE_BLANK,
`ifdef MISTER_FB_PALETTE
    output FB_PAL_CLK,
    output [7:0] FB_PAL_ADDR,
    output [23:0] FB_PAL_DOUT,
    input [23:0] FB_PAL_DIN,
    output FB_PAL_WR,
`endif
`endif
    output LED_USER,
    output [1:0] LED_POWER,
    output [1:0] LED_DISK,
    output [1:0] BUTTONS,
    input CLK_AUDIO,
    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output AUDIO_S,
    output [1:0] AUDIO_MIX,
    inout [3:0] ADC_BUS,
    output SD_SCK,
    output SD_MOSI,
    input SD_MISO,
    output SD_CS,
    input SD_CD,
    output DDRAM_CLK,
    input DDRAM_BUSY,
    output [7:0] DDRAM_BURSTCNT,
    output [28:0] DDRAM_ADDR,
    input [63:0] DDRAM_DOUT,
    input DDRAM_DOUT_READY,
    output DDRAM_RD,
    output [63:0] DDRAM_DIN,
    output [7:0] DDRAM_BE,
    output DDRAM_WE,
    output SDRAM_CLK,
    output SDRAM_CKE,
    output [12:0] SDRAM_A,
    output [1:0] SDRAM_BA,
    inout [15:0] SDRAM_DQ,
    output SDRAM_DQML,
    output SDRAM_DQMH,
    output SDRAM_nCS,
    output SDRAM_nCAS,
    output SDRAM_nRAS,
    output SDRAM_nWE,
`ifdef MISTER_DUAL_SDRAM
    input SDRAM2_EN,
    output SDRAM2_CLK,
    output [12:0] SDRAM2_A,
    output [1:0] SDRAM2_BA,
    inout [15:0] SDRAM2_DQ,
    output SDRAM2_nCS,
    output SDRAM2_nCAS,
    output SDRAM2_nRAS,
    output SDRAM2_nWE,
`endif
    input UART_CTS,
    output UART_RTS,
    input UART_RXD,
    output UART_TXD,
    output UART_DTR,
    input UART_DSR,
    input [6:0] USER_IN,
    output [6:0] USER_OUT,
    output [1:0] VGM_PLAYER_STATE,
    input OSD_STATUS
);
    localparam CONF_STR = {
        "MegaVGMDrive YM2610 HW0;;",
        "R0,Reset;",
        "V,v", `BUILD_DATE
    };

    wire clk_sys;
    wire pll_locked;
    wire [31:0] status;
    wire [1:0] buttons;
    wire reset = RESET | status[0] | !pll_locked;
    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_sample;
    wire video_ce, video_hs, video_vs, video_de;
    wire [7:0] video_r, video_g, video_b;
    wire [3:0] phase;
    wire halted;

    pll pll (
        .refclk(CLK_50M), .rst(1'b0),
        .outclk_0(clk_sys), .locked(pll_locked)
    );

    hps_io #(.CONF_STR(CONF_STR)) hps_io (
        .clk_sys(clk_sys), .HPS_BUS(HPS_BUS),
        .buttons(buttons), .status(status),
        .status_menumask(1'b0), .forced_scandoubler(),
        .video_rotated(1'b0), .new_vmode(1'b0),
        .direct_video(), .gamma_bus()
    );

    ym2610_hw0_top u_hw0 (
        .clk_sys(clk_sys), .reset(reset),
        .audio_l(audio_l), .audio_r(audio_r),
        .audio_sample(audio_sample),
        .video_ce(video_ce), .video_hs(video_hs),
        .video_vs(video_vs), .video_de(video_de),
        .video_r(video_r), .video_g(video_g), .video_b(video_b),
        .debug_phase(phase), .debug_halted(halted)
    );

    assign CLK_VIDEO = clk_sys;
    assign CE_PIXEL = video_ce;
    assign VGA_R = video_r;
    assign VGA_G = video_g;
    assign VGA_B = video_b;
    assign VGA_HS = video_hs;
    assign VGA_VS = video_vs;
    assign VGA_DE = video_de;
    assign VIDEO_ARX = 13'd4;
    assign VIDEO_ARY = 13'd3;
    assign VGA_F1 = 1'b0;
    assign VGA_SL = 2'b00;
    assign VGA_SCALER = 1'b0;
    assign VGA_DISABLE = 1'b0;
    assign HDMI_FREEZE = 1'b0;
    assign HDMI_BLACKOUT = 1'b0;

    // JT10 already publishes signed 16-bit two's-complement samples.  The
    // MiSTer shell consumes that same width, so this is an exact bit mapping.
    assign AUDIO_L = audio_l;
    assign AUDIO_R = audio_r;
    assign AUDIO_S = 1'b1;
    assign AUDIO_MIX = 2'b00;

    assign LED_USER = halted;
    assign LED_POWER = 2'b00;
    assign LED_DISK = 2'b00;
    assign BUTTONS = 2'b00;
    assign ADC_BUS = 4'hz;
    assign USER_OUT = 7'h7f;
    assign VGM_PLAYER_STATE = halted ? 2'd0 : 2'd2;
    assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
    assign {SD_SCK, SD_MOSI, SD_CS} = 3'bzzz;
    assign DDRAM_CLK = clk_sys;
    assign DDRAM_BURSTCNT = 8'd0;
    assign DDRAM_ADDR = 29'd0;
    assign DDRAM_RD = 1'b0;
    assign DDRAM_DIN = 64'd0;
    assign DDRAM_BE = 8'd0;
    assign DDRAM_WE = 1'b0;
    assign {SDRAM_CLK, SDRAM_CKE, SDRAM_A, SDRAM_BA,
            SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nCAS,
            SDRAM_nRAS, SDRAM_nWE} = '0;
    assign SDRAM_DQ = 16'hzzzz;
`ifdef MISTER_DUAL_SDRAM
    assign {SDRAM2_CLK, SDRAM2_A, SDRAM2_BA,
            SDRAM2_nCS, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nWE} = '0;
    assign SDRAM2_DQ = 16'hzzzz;
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
endmodule

// VGM MD video-only baseline using the proven InputTest_MiSTer outer shape.
//
// This module intentionally mirrors InputTest_MiSTer's explicit emu port list
// and hps_io style. The sound module is not instantiated in this baseline.

module emu
(
    input         CLK_50M,
    input         RESET,

    inout  [48:0] HPS_BUS,

    output        CLK_VIDEO,
    output        CE_PIXEL,

    output [12:0] VIDEO_ARX,
    output [12:0] VIDEO_ARY,

    output  [7:0] VGA_R,
    output  [7:0] VGA_G,
    output  [7:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,
    output        VGA_F1,
    output [1:0]  VGA_SL,
    output        VGA_SCALER,
    output        VGA_DISABLE,

    input  [11:0] HDMI_WIDTH,
    input  [11:0] HDMI_HEIGHT,
    output        HDMI_FREEZE,
    output        HDMI_BLACKOUT,

`ifdef MISTER_FB
    output        FB_EN,
    output  [4:0] FB_FORMAT,
    output [11:0] FB_WIDTH,
    output [11:0] FB_HEIGHT,
    output [31:0] FB_BASE,
    output [13:0] FB_STRIDE,
    input         FB_VBL,
    input         FB_LL,
    output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
    output        FB_PAL_CLK,
    output  [7:0] FB_PAL_ADDR,
    output [23:0] FB_PAL_DOUT,
    input  [23:0] FB_PAL_DIN,
    output        FB_PAL_WR,
`endif
`endif

    output        LED_USER,
    output  [1:0] LED_POWER,
    output  [1:0] LED_DISK,
    output  [1:0] BUTTONS,

    input         CLK_AUDIO,
    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output        AUDIO_S,
    output  [1:0] AUDIO_MIX,

    inout   [3:0] ADC_BUS,

    output        SD_SCK,
    output        SD_MOSI,
    input         SD_MISO,
    output        SD_CS,
    input         SD_CD,

    output        DDRAM_CLK,
    input         DDRAM_BUSY,
    output  [7:0] DDRAM_BURSTCNT,
    output [28:0] DDRAM_ADDR,
    input  [63:0] DDRAM_DOUT,
    input         DDRAM_DOUT_READY,
    output        DDRAM_RD,
    output [63:0] DDRAM_DIN,
    output  [7:0] DDRAM_BE,
    output        DDRAM_WE,

    output        SDRAM_CLK,
    output        SDRAM_CKE,
    output [12:0] SDRAM_A,
    output  [1:0] SDRAM_BA,
    inout  [15:0] SDRAM_DQ,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output        SDRAM_nCS,
    output        SDRAM_nCAS,
    output        SDRAM_nRAS,
    output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
    input         SDRAM2_EN,
    output        SDRAM2_CLK,
    output [12:0] SDRAM2_A,
    output  [1:0] SDRAM2_BA,
    inout  [15:0] SDRAM2_DQ,
    output        SDRAM2_nCS,
    output        SDRAM2_nCAS,
    output        SDRAM2_nRAS,
    output        SDRAM2_nWE,
`endif

    input         UART_CTS,
    output        UART_RTS,
    input         UART_RXD,
    output        UART_TXD,
    output        UART_DTR,
    input         UART_DSR,

    input   [6:0] USER_IN,
    output  [6:0] USER_OUT,

    input         OSD_STATUS
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

    assign VGA_F1 = 1'b0;
    assign VGA_SL = 2'b00;
    assign VGA_SCALER = 1'b0;
    assign VGA_DISABLE = 1'b0;
    assign HDMI_FREEZE = 1'b0;
    assign HDMI_BLACKOUT = 1'b0;

    wire signed [15:0] md_audio_l;
    wire signed [15:0] md_audio_r;
    wire signed [15:0] audio_l_safe = md_audio_l >>> 2;
    wire signed [15:0] audio_r_safe = md_audio_r >>> 2;

    assign AUDIO_S = 1'b1;
    assign AUDIO_L = audio_l_safe;
    assign AUDIO_R = audio_r_safe;
    assign AUDIO_MIX = 2'b00;

    assign LED_DISK = 2'b00;
    assign LED_POWER = 2'b00;
    assign BUTTONS = 2'b00;

    //////////////////////////////////////////////////////////////////

    assign VIDEO_ARX = 13'd4;
    assign VIDEO_ARY = 13'd3;

    `include "build_id.v"
    localparam CONF_STR = {
        "VGM_MD;;",
        "-;",
        "R0,Reset;",
        "V,v",`BUILD_DATE
    };

    wire [31:0] status;
    wire  [1:0] buttons;
    wire        forced_scandoubler;
    wire        video_rotated;
    wire        direct_video;
    wire [21:0] gamma_bus;

    wire        ioctl_download;
    wire        ioctl_wr;
    wire [24:0] ioctl_addr;
    wire  [7:0] ioctl_dout;
    wire  [7:0] ioctl_index;

    wire [31:0] joystick_0;
    wire [31:0] joystick_1;
    wire [31:0] joystick_2;
    wire [31:0] joystick_3;
    wire [31:0] joystick_4;
    wire [31:0] joystick_5;
    wire [15:0] joystick_l_analog_0;
    wire [15:0] joystick_l_analog_1;
    wire [15:0] joystick_l_analog_2;
    wire [15:0] joystick_l_analog_3;
    wire [15:0] joystick_l_analog_4;
    wire [15:0] joystick_l_analog_5;
    wire [15:0] joystick_r_analog_0;
    wire [15:0] joystick_r_analog_1;
    wire [15:0] joystick_r_analog_2;
    wire [15:0] joystick_r_analog_3;
    wire [15:0] joystick_r_analog_4;
    wire [15:0] joystick_r_analog_5;
    wire  [7:0] paddle_0;
    wire  [7:0] paddle_1;
    wire  [7:0] paddle_2;
    wire  [7:0] paddle_3;
    wire  [7:0] paddle_4;
    wire  [7:0] paddle_5;
    wire  [8:0] spinner_0;
    wire  [8:0] spinner_1;
    wire  [8:0] spinner_2;
    wire  [8:0] spinner_3;
    wire  [8:0] spinner_4;
    wire  [8:0] spinner_5;
    wire [10:0] ps2_key;
    wire [24:0] ps2_mouse;
    wire [15:0] ps2_mouse_ext;
    wire [32:0] timestamp;

    hps_io #(.CONF_STR(CONF_STR)) hps_io (
        .clk_sys(clk_sys),
        .HPS_BUS(HPS_BUS),
        .buttons(buttons),
        .status(status),
        .status_menumask({direct_video}),
        .forced_scandoubler(forced_scandoubler),
        .video_rotated(video_rotated),
        .direct_video(direct_video),

        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index),

        .joystick_0(joystick_0),
        .joystick_1(joystick_1),
        .joystick_2(joystick_2),
        .joystick_3(joystick_3),
        .joystick_4(joystick_4),
        .joystick_5(joystick_5),

        .joystick_l_analog_0(joystick_l_analog_0),
        .joystick_l_analog_1(joystick_l_analog_1),
        .joystick_l_analog_2(joystick_l_analog_2),
        .joystick_l_analog_3(joystick_l_analog_3),
        .joystick_l_analog_4(joystick_l_analog_4),
        .joystick_l_analog_5(joystick_l_analog_5),

        .joystick_r_analog_0(joystick_r_analog_0),
        .joystick_r_analog_1(joystick_r_analog_1),
        .joystick_r_analog_2(joystick_r_analog_2),
        .joystick_r_analog_3(joystick_r_analog_3),
        .joystick_r_analog_4(joystick_r_analog_4),
        .joystick_r_analog_5(joystick_r_analog_5),

        .paddle_0(paddle_0),
        .paddle_1(paddle_1),
        .paddle_2(paddle_2),
        .paddle_3(paddle_3),
        .paddle_4(paddle_4),
        .paddle_5(paddle_5),

        .spinner_0(spinner_0),
        .spinner_1(spinner_1),
        .spinner_2(spinner_2),
        .spinner_3(spinner_3),
        .spinner_4(spinner_4),
        .spinner_5(spinner_5),

        .ps2_key(ps2_key),
        .ps2_mouse(ps2_mouse),
        .ps2_mouse_ext(ps2_mouse_ext),

        .TIMESTAMP(timestamp)
    );

    ////////////////////   CLOCKS   ///////////////////

    wire clk_sys;
    wire pll_locked;

    pll pll (
        .refclk(CLK_50M),
        .rst(1'b0),
        .outclk_0(clk_sys),
        .locked(pll_locked)
    );

    ///////////////////   CLOCK DIVIDER   ////////////////////

    wire ce_pix;
    wire ce_2;

    jtframe_cen24 divider (
        .clk(clk_sys),
        .cen6(ce_pix),
        .cen2(ce_2)
    );

    ///////////////////   VIDEO   ////////////////////

    wire reset = RESET | status[0] | !pll_locked;

    wire               audio_sample_valid;
    wire               player_busy;
    wire               player_done;
    wire         [9:0] player_pc_debug;
    wire         [7:0] player_last_cmd_debug;

    mister_vgm_md_top md_sound (
        .clk                   (clk_sys),
        .reset_n               (!reset),
        .audio_l               (md_audio_l),
        .audio_r               (md_audio_r),
        .audio_sample_valid    (audio_sample_valid),
        .player_busy           (player_busy),
        .player_done           (player_done),
        .player_pc_debug       (player_pc_debug),
        .player_last_cmd_debug (player_last_cmd_debug)
    );

    reg [8:0] h_count;
    reg [8:0] v_count;
    reg [7:0] frame_count;
    reg       done_latched;
    reg       audio_seen_latched;

    always @(posedge clk_sys) begin
        if (reset) begin
            h_count <= 9'd0;
            v_count <= 9'd0;
            frame_count <= 8'd0;
            done_latched <= 1'b0;
            audio_seen_latched <= 1'b0;
        end else if (ce_pix) begin
            if (h_count == 9'd383) begin
                h_count <= 9'd0;
                if (v_count == 9'd263) begin
                    v_count <= 9'd0;
                    if (frame_count != 8'hff) begin
                        frame_count <= frame_count + 8'd1;
                    end
                end else begin
                    v_count <= v_count + 9'd1;
                end
            end else begin
                h_count <= h_count + 9'd1;
            end
        end

        if (!reset) begin
            if (player_done) begin
                done_latched <= 1'b1;
            end

            if (audio_sample_valid) begin
                audio_seen_latched <= 1'b1;
            end
        end
    end

    wire hblank = (h_count >= 9'd320);
    wire vblank = (v_count >= 9'd240);
    wire active = !hblank && !vblank;

    wire hsync = ~((h_count >= 9'd336) && (h_count < 9'd368));
    wire vsync = ~((v_count >= 9'd244) && (v_count < 9'd248));

    // State colors:
    // idle/running background : green
    // player_busy             : red
    // done_latched            : blue
    // audio_seen_latched      : white
    //
    // audio_seen has highest priority because it proves md_sound_module is
    // producing sample ticks. AUDIO_L/R are now connected at a conservative
    // -12 dB style level by shifting md_audio_* right by two bits.
    wire [7:0] red =
        audio_seen_latched ? 8'hff :
        done_latched       ? 8'h00 :
        player_busy        ? 8'hd0 :
                             8'h00;

    wire [7:0] green =
        audio_seen_latched ? 8'hff :
        done_latched       ? 8'h20 :
        player_busy        ? 8'h00 :
                             8'hb0;

    wire [7:0] blue =
        audio_seen_latched ? 8'hff :
        done_latched       ? 8'hd0 :
        player_busy        ? 8'h00 :
                             8'h40;

    assign CLK_VIDEO = clk_sys;
    assign CE_PIXEL = ce_pix;
    assign VGA_DE = active;
    assign VGA_HS = hsync;
    assign VGA_VS = vsync;
    assign VGA_R = active ? red : 8'd0;
    assign VGA_G = active ? green : 8'd0;
    assign VGA_B = active ? blue : 8'd0;

    reg [26:0] act_cnt;
    always @(posedge clk_sys) begin
        act_cnt <= reset ? 27'd0 : act_cnt + 27'd1;
    end

    assign LED_USER = player_busy | done_latched | audio_seen_latched | act_cnt[25];

    wire unused_inputs = ^{
        forced_scandoubler,
        video_rotated,
        gamma_bus,
        ioctl_download,
        ioctl_wr,
        ioctl_addr,
        ioctl_dout,
        ioctl_index,
        joystick_0,
        joystick_1,
        joystick_2,
        joystick_3,
        joystick_4,
        joystick_5,
        joystick_l_analog_0,
        joystick_l_analog_1,
        joystick_l_analog_2,
        joystick_l_analog_3,
        joystick_l_analog_4,
        joystick_l_analog_5,
        joystick_r_analog_0,
        joystick_r_analog_1,
        joystick_r_analog_2,
        joystick_r_analog_3,
        joystick_r_analog_4,
        joystick_r_analog_5,
        paddle_0,
        paddle_1,
        paddle_2,
        paddle_3,
        paddle_4,
        paddle_5,
        spinner_0,
        spinner_1,
        spinner_2,
        spinner_3,
        spinner_4,
        spinner_5,
        ps2_key,
        ps2_mouse,
        ps2_mouse_ext,
        timestamp,
        ce_2,
        player_pc_debug,
        player_last_cmd_debug,
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

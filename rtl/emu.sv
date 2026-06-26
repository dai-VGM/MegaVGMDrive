// MegaVGMDrive video/audio shell using the proven InputTest_MiSTer outer shape.
//
// This module intentionally mirrors InputTest_MiSTer's explicit emu port list
// and hps_io style. The sound module is not instantiated in this baseline.

`include "rtl/fixed_region_mode.vh"

localparam bit FIXED_REAL_SNIPPET_MODE = (`FIXED_REGION_MODE == 2);
localparam bit FIXED_REAL_PHRASE_MODE  = (`FIXED_REGION_MODE == 3);
localparam bit FIXED_TIMING_CAL_MODE   = (`FIXED_REGION_MODE == 4);
localparam bit LOADED_VGM_MODE         = (`FIXED_REGION_MODE == 5);

`ifdef MD_AUDIO_OUTPUT_SHIFT_0_TEST
localparam bit MD_AUDIO_OUTPUT_SHIFT_0_BUILD = 1'b1;
localparam bit MD_AUDIO_OUTPUT_SHIFT_1_BUILD = 1'b0;
localparam bit MD_AUDIO_ATTENUATE_6DB_BUILD = 1'b0;
localparam int MD_AUDIO_OUTPUT_SHIFT = 0;
`elsif MD_AUDIO_OUTPUT_SHIFT_1_TEST
localparam bit MD_AUDIO_OUTPUT_SHIFT_0_BUILD = 1'b0;
localparam bit MD_AUDIO_OUTPUT_SHIFT_1_BUILD = 1'b1;
localparam bit MD_AUDIO_ATTENUATE_6DB_BUILD = 1'b0;
localparam int MD_AUDIO_OUTPUT_SHIFT = 1;
`elsif MD_AUDIO_FINAL_ATTENUATE_6DB
localparam bit MD_AUDIO_OUTPUT_SHIFT_0_BUILD = 1'b0;
localparam bit MD_AUDIO_OUTPUT_SHIFT_1_BUILD = 1'b0;
localparam bit MD_AUDIO_ATTENUATE_6DB_BUILD = 1'b1;
localparam int MD_AUDIO_OUTPUT_SHIFT = 3;
`else
localparam bit MD_AUDIO_OUTPUT_SHIFT_0_BUILD = 1'b0;
localparam bit MD_AUDIO_OUTPUT_SHIFT_1_BUILD = 1'b0;
localparam bit MD_AUDIO_ATTENUATE_6DB_BUILD = 1'b0;
localparam int MD_AUDIO_OUTPUT_SHIFT = 2;
`endif

`ifdef MD_YM_WRITE_SLOW_TEST
localparam bit MD_YM_WRITE_SLOW_BUILD = 1'b1;
`else
localparam bit MD_YM_WRITE_SLOW_BUILD = 1'b0;
`endif

`ifdef MD_YM_FORCE_LFO_OFF_TEST
localparam bit MD_YM_FORCE_LFO_OFF_BUILD = 1'b1;
`else
localparam bit MD_YM_FORCE_LFO_OFF_BUILD = 1'b0;
`endif

`ifdef MD_YM_MASK_PMS_AMS_TEST
localparam bit MD_YM_MASK_PMS_AMS_BUILD = 1'b1;
`else
localparam bit MD_YM_MASK_PMS_AMS_BUILD = 1'b0;
`endif

`ifdef MD_YM_CH3_NORMAL_TEST
localparam bit MD_YM_CH3_NORMAL_BUILD = 1'b1;
`else
localparam bit MD_YM_CH3_NORMAL_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FORCE_MUTE_TEST
localparam bit MD_AUDIO_FORCE_MUTE_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FORCE_MUTE_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_SYSOUT_ATTENUATE_6DB
localparam bit MD_AUDIO_SYSOUT_ATTENUATE_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_SYSOUT_ATTENUATE_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_SYSOUT_ATTENUATE_24DB
localparam bit MD_AUDIO_SYSOUT_ATTENUATE_24DB_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_SYSOUT_ATTENUATE_24DB_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_SYSOUT_FORCE_TONE_TEST
localparam bit MD_AUDIO_SYSOUT_FORCE_TONE_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_SYSOUT_FORCE_TONE_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_SYSOUT_GAIN_2X_SAT_TEST
localparam bit MD_AUDIO_SYSOUT_GAIN_2X_SAT_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_SYSOUT_GAIN_2X_SAT_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_SYSOUT_GAIN_4X_SAT_TEST
localparam bit MD_AUDIO_SYSOUT_GAIN_4X_SAT_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_SYSOUT_GAIN_4X_SAT_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_ONLY_TEST
localparam bit MD_AUDIO_FM_ONLY_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_ONLY_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_FORCE_MUTE_TEST
localparam bit MD_AUDIO_FM_FORCE_MUTE_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_FORCE_MUTE_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_PSG_ONLY_TEST
localparam bit MD_AUDIO_PSG_ONLY_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_PSG_ONLY_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_CH1_ONLY_TEST
localparam bit MD_AUDIO_FM_CH1_ONLY_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_CH1_ONLY_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_CH2_ONLY_TEST
localparam bit MD_AUDIO_FM_CH2_ONLY_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_CH2_ONLY_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_CH3_ONLY_TEST
localparam bit MD_AUDIO_FM_CH3_ONLY_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_CH3_ONLY_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_CH4_ONLY_TEST
localparam bit MD_AUDIO_FM_CH4_ONLY_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_CH4_ONLY_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_CH5_ONLY_TEST
localparam bit MD_AUDIO_FM_CH5_ONLY_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_CH5_ONLY_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_CH6_ONLY_TEST
localparam bit MD_AUDIO_FM_CH6_ONLY_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_CH6_ONLY_BUILD = 1'b0;
`endif

localparam bit MD_AUDIO_FM_CH_SOLO_BUILD =
    MD_AUDIO_FM_CH1_ONLY_BUILD || MD_AUDIO_FM_CH2_ONLY_BUILD ||
    MD_AUDIO_FM_CH3_ONLY_BUILD || MD_AUDIO_FM_CH4_ONLY_BUILD ||
    MD_AUDIO_FM_CH5_ONLY_BUILD || MD_AUDIO_FM_CH6_ONLY_BUILD;

`ifdef MD_AUDIO_PREMIX_ATTENUATE_FM_6DB
localparam bit MD_AUDIO_PREMIX_ATTENUATE_FM_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_PREMIX_ATTENUATE_FM_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_ADJUST_BYPASS_TEST
localparam bit MD_AUDIO_FM_ADJUST_BYPASS_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_ADJUST_BYPASS_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_ADJUST_LOW_GAIN_TEST
localparam bit MD_AUDIO_FM_ADJUST_LOW_GAIN_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_ADJUST_LOW_GAIN_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_ADJUST_SATURATE_TEST
localparam bit MD_AUDIO_FM_ADJUST_SATURATE_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_ADJUST_SATURATE_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_PREMIX_ATTENUATE_PSG_6DB
localparam bit MD_AUDIO_PREMIX_ATTENUATE_PSG_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_PREMIX_ATTENUATE_PSG_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_RAW_JT12_FM_TEST
localparam bit MD_AUDIO_RAW_JT12_FM_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_RAW_JT12_FM_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_RAW_JT12_SAMPLE_LATCH_TEST
localparam bit MD_AUDIO_RAW_JT12_SAMPLE_LATCH_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_RAW_JT12_SAMPLE_LATCH_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_NORMAL_SAMPLE_LATCH_TEST
localparam bit MD_AUDIO_NORMAL_SAMPLE_LATCH_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_NORMAL_SAMPLE_LATCH_BUILD = 1'b0;
`endif

`ifdef MD_JT12_CEN_NTSC_TEST
localparam bit MD_JT12_CEN_NTSC_BUILD = 1'b1;
`else
localparam bit MD_JT12_CEN_NTSC_BUILD = 1'b0;
`endif

`ifdef MD_JT12_CEN_EVERY_CLK_TEST
localparam bit MD_JT12_CEN_EVERY_CLK_BUILD = 1'b1;
`else
localparam bit MD_JT12_CEN_EVERY_CLK_BUILD = 1'b0;
`endif

`ifdef MD_JT12_CEN_UNIFORM_10MHZ_TEST
localparam bit MD_JT12_CEN_UNIFORM_10MHZ_BUILD = 1'b1;
`else
localparam bit MD_JT12_CEN_UNIFORM_10MHZ_BUILD = 1'b0;
`endif

`ifdef MD_JT12_CEN_UNIFORM_6P67MHZ_TEST
localparam bit MD_JT12_CEN_UNIFORM_6P67MHZ_BUILD = 1'b1;
`else
localparam bit MD_JT12_CEN_UNIFORM_6P67MHZ_BUILD = 1'b0;
`endif

`ifdef MD_JT12_LADDER_EFFECT_TEST
localparam bit MD_JT12_LADDER_EFFECT_BUILD = 1'b1;
`else
localparam bit MD_JT12_LADDER_EFFECT_BUILD = 1'b0;
`endif

`ifdef MD_JT12_FORCE_YM2612_TEST
localparam bit MD_JT12_FORCE_YM2612_BUILD = 1'b1;
`else
localparam bit MD_JT12_FORCE_YM2612_BUILD = 1'b0;
`endif

`ifdef MD_JT12_FORCE_YM3438_TEST
localparam bit MD_JT12_FORCE_YM3438_BUILD = 1'b1;
`else
localparam bit MD_JT12_FORCE_YM3438_BUILD = 1'b0;
`endif

`ifdef MD_JT12_FORCE_LADDER_ON_TEST
localparam bit MD_JT12_FORCE_LADDER_ON_BUILD = 1'b1;
`else
localparam bit MD_JT12_FORCE_LADDER_ON_BUILD = 1'b0;
`endif

`ifdef MD_JT12_FORCE_LADDER_OFF_TEST
localparam bit MD_JT12_FORCE_LADDER_OFF_BUILD = 1'b1;
`else
localparam bit MD_JT12_FORCE_LADDER_OFF_BUILD = 1'b0;
`endif

`ifdef MD_JT12_HIFI_PCM_TEST
localparam bit MD_JT12_HIFI_PCM_BUILD = 1'b1;
`else
localparam bit MD_JT12_HIFI_PCM_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_DC_BLOCK_TEST
localparam bit MD_AUDIO_FM_DC_BLOCK_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_FM_DC_BLOCK_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_PRE_GENMIX_FM_LPF_TEST
localparam bit MD_AUDIO_PRE_GENMIX_FM_LPF_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_PRE_GENMIX_FM_LPF_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_POST_FM_LPF_GAIN_TEST
localparam bit MD_AUDIO_POST_FM_LPF_GAIN_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_POST_FM_LPF_GAIN_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_GENMIX_OUTPUT_GAIN_2X_TEST
localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_2X_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_2X_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_GENMIX_OUTPUT_GAIN_4X_TEST
localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_4X_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_4X_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_GENMIX_OUTPUT_GAIN_6X_TEST
localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_6X_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_6X_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_GENMIX_OUTPUT_GAIN_8X_TEST
localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_8X_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_8X_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_LPF_MODEL1_TEST
localparam bit MD_AUDIO_LPF_TEST_BUILD = 1'b1;
`else
`ifdef MD_AUDIO_LPF_MODEL2_TEST
localparam bit MD_AUDIO_LPF_TEST_BUILD = 1'b1;
`else
`ifdef MD_AUDIO_LPF_MINIMAL_TEST
localparam bit MD_AUDIO_LPF_TEST_BUILD = 1'b1;
`else
localparam bit MD_AUDIO_LPF_TEST_BUILD = 1'b0;
`endif
`endif
`endif

`ifdef MODE5_DEBUG_OVERLAY_ALWAYS_ON
localparam bit MODE5_DEBUG_OVERLAY_FORCED = 1'b1;
`else
localparam bit MODE5_DEBUG_OVERLAY_FORCED = 1'b0;
`endif
`ifdef MEGAVGMDRIVE_YM2151_MODE_TEST
localparam bit YM2151_SEGAPCM_OBSERVER_BUILD = 1'b1;
`else
localparam bit YM2151_SEGAPCM_OBSERVER_BUILD = 1'b0;
`endif

`ifdef MODE5_REPEAT_ENABLE_TEST
localparam bit MODE5_REPEAT_ENABLE_BUILD = 1'b1;
`else
localparam bit MODE5_REPEAT_ENABLE_BUILD = 1'b0;
`endif

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
    output  [1:0] VGM_PLAYER_STATE,

    input         OSD_STATUS
);

    ///////// Default values for ports not used in this baseline /////////

    assign ADC_BUS  = 'Z;
    assign USER_OUT = '1;
    assign VGM_PLAYER_STATE =
        (LOADED_VGM_MODE && (ioctl_download || vgm_load_busy)) ? 2'd1 :
        (LOADED_VGM_MODE && segapcm_rom_scan_busy) ? 2'd2 :
        (LOADED_VGM_MODE &&
         vgm_scan_sticky_guard_debug[0] &&
         vgm_scan_term_be_debug[4] &&
         !vgm_scan_term_be_debug[3]) ? 2'd2 :
        (player_busy && audio_gate_open && !audio_muted && !vgm_player_error) ? 2'd2 :
                                                                              2'd0;
    assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
    assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
    assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE,
            SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS,
            SDRAM_nRAS, SDRAM_nCS} = 'Z;
    wire [7:0]  vgm_ddram_burstcnt;
    wire [28:0] vgm_ddram_addr;
    wire [63:0] vgm_ddram_din;
    wire [7:0]  vgm_ddram_be;
    wire        vgm_ddram_rd;
    wire        vgm_ddram_we;

    assign DDRAM_CLK      = clk_sys;
    assign DDRAM_BURSTCNT = vgm_ddram_burstcnt;
    assign DDRAM_ADDR     = vgm_ddram_addr;
    assign DDRAM_DIN      = vgm_ddram_din;
    assign DDRAM_BE       = vgm_ddram_be;
    assign DDRAM_RD       = vgm_ddram_rd;
    assign DDRAM_WE       = vgm_ddram_we;

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
    wire               audio_gate_open;
    wire               audio_muted;
    wire signed [15:0] audio_l_safe = md_audio_l >>> MD_AUDIO_OUTPUT_SHIFT;
    wire signed [15:0] audio_r_safe = md_audio_r >>> MD_AUDIO_OUTPUT_SHIFT;
    wire signed [15:0] audio_l_gated =
        (audio_gate_open && !audio_muted) ? audio_l_safe : 16'sd0;
    wire signed [15:0] audio_r_gated =
        (audio_gate_open && !audio_muted) ? audio_r_safe : 16'sd0;
    wire signed [15:0] audio_l_final =
        MD_AUDIO_FORCE_MUTE_BUILD ? 16'sd0 : audio_l_gated;
    wire signed [15:0] audio_r_final =
        MD_AUDIO_FORCE_MUTE_BUILD ? 16'sd0 : audio_r_gated;

    function automatic [15:0] audio_abs16(input logic signed [15:0] value);
        audio_abs16 = value[15] ? (~value + 16'd1) : value;
    endfunction

    (* keep = 1 *) wire signed [15:0] debug_md_sound_module_audio_l = md_audio_l;
    (* keep = 1 *) wire signed [15:0] debug_md_sound_module_audio_r = md_audio_r;
    (* keep = 1 *) wire signed [15:0] debug_emu_audio_l = audio_l_final;
    (* keep = 1 *) wire signed [15:0] debug_emu_audio_r = audio_r_final;

    localparam logic signed [15:0] AUDIO_POS_RAIL = 16'sh7fff;
    localparam logic signed [15:0] AUDIO_NEG_RAIL = 16'sh8000;

    wire [15:0] md_audio_l_abs = audio_abs16(md_audio_l);
    wire [15:0] md_audio_r_abs = audio_abs16(md_audio_r);
    wire [15:0] emu_audio_l_abs = audio_abs16(audio_l_final);
    wire [15:0] emu_audio_r_abs = audio_abs16(audio_r_final);
    wire               md_audio_l_at_rail =
        (md_audio_l == AUDIO_POS_RAIL) || (md_audio_l == AUDIO_NEG_RAIL);
    wire               md_audio_r_at_rail =
        (md_audio_r == AUDIO_POS_RAIL) || (md_audio_r == AUDIO_NEG_RAIL);
    wire               emu_audio_l_at_rail =
        (audio_l_final == AUDIO_POS_RAIL) || (audio_l_final == AUDIO_NEG_RAIL);
    wire               emu_audio_r_at_rail =
        (audio_r_final == AUDIO_POS_RAIL) || (audio_r_final == AUDIO_NEG_RAIL);
    (* keep = 1, noprune = 1 *) reg [15:0] md_audio_l_abs_peak = 16'd0;
    (* keep = 1, noprune = 1 *) reg [15:0] md_audio_r_abs_peak = 16'd0;
    (* keep = 1, noprune = 1 *) reg [15:0] emu_audio_l_abs_peak = 16'd0;
    (* keep = 1, noprune = 1 *) reg [15:0] emu_audio_r_abs_peak = 16'd0;
    (* keep = 1, noprune = 1 *) reg [15:0] md_audio_abs_avg = 16'd0;
    (* keep = 1, noprune = 1 *) reg [15:0] emu_audio_abs_avg = 16'd0;
    reg [27:0] md_audio_abs_sum = 28'd0;
    reg [27:0] emu_audio_abs_sum = 28'd0;
    reg [11:0] audio_abs_avg_count = 12'd0;
    reg         [15:0] md_audio_l_rail_count = 16'd0;
    reg         [15:0] md_audio_r_rail_count = 16'd0;
    (* keep = 1, noprune = 1 *) reg [15:0] emu_audio_l_rail_count = 16'd0;
    (* keep = 1, noprune = 1 *) reg [15:0] emu_audio_r_rail_count = 16'd0;

    always @(posedge clk_sys) begin
        if (reset) begin
            md_audio_l_abs_peak <= 16'd0;
            md_audio_r_abs_peak <= 16'd0;
            emu_audio_l_abs_peak <= 16'd0;
            emu_audio_r_abs_peak <= 16'd0;
            md_audio_abs_avg <= 16'd0;
            emu_audio_abs_avg <= 16'd0;
            md_audio_abs_sum <= 28'd0;
            emu_audio_abs_sum <= 28'd0;
            audio_abs_avg_count <= 12'd0;
            md_audio_l_rail_count <= 16'd0;
            md_audio_r_rail_count <= 16'd0;
            emu_audio_l_rail_count <= 16'd0;
            emu_audio_r_rail_count <= 16'd0;
        end else if (audio_gate_open && audio_sample_valid) begin
            logic [15:0] md_audio_abs_now;
            logic [15:0] emu_audio_abs_now;

            md_audio_abs_now =
                (md_audio_l_abs > md_audio_r_abs) ? md_audio_l_abs : md_audio_r_abs;
            emu_audio_abs_now =
                (emu_audio_l_abs > emu_audio_r_abs) ? emu_audio_l_abs : emu_audio_r_abs;

            if (md_audio_l_abs > md_audio_l_abs_peak) begin
                md_audio_l_abs_peak <= md_audio_l_abs;
            end
            if (md_audio_r_abs > md_audio_r_abs_peak) begin
                md_audio_r_abs_peak <= md_audio_r_abs;
            end
            if (emu_audio_l_abs > emu_audio_l_abs_peak) begin
                emu_audio_l_abs_peak <= emu_audio_l_abs;
            end
            if (emu_audio_r_abs > emu_audio_r_abs_peak) begin
                emu_audio_r_abs_peak <= emu_audio_r_abs;
            end
            if (&audio_abs_avg_count) begin
                md_audio_abs_avg <= (md_audio_abs_sum + md_audio_abs_now) >> 12;
                emu_audio_abs_avg <= (emu_audio_abs_sum + emu_audio_abs_now) >> 12;
                md_audio_abs_sum <= 28'd0;
                emu_audio_abs_sum <= 28'd0;
                audio_abs_avg_count <= 12'd0;
            end else begin
                md_audio_abs_sum <= md_audio_abs_sum + md_audio_abs_now;
                emu_audio_abs_sum <= emu_audio_abs_sum + emu_audio_abs_now;
                audio_abs_avg_count <= audio_abs_avg_count + 12'd1;
            end
            if (md_audio_l_at_rail && !(&md_audio_l_rail_count)) begin
                md_audio_l_rail_count <= md_audio_l_rail_count + 16'd1;
            end
            if (md_audio_r_at_rail && !(&md_audio_r_rail_count)) begin
                md_audio_r_rail_count <= md_audio_r_rail_count + 16'd1;
            end
            if (emu_audio_l_at_rail && !(&emu_audio_l_rail_count)) begin
                emu_audio_l_rail_count <= emu_audio_l_rail_count + 16'd1;
            end
            if (emu_audio_r_at_rail && !(&emu_audio_r_rail_count)) begin
                emu_audio_r_rail_count <= emu_audio_r_rail_count + 16'd1;
            end
        end
    end

    assign AUDIO_S = 1'b1;
    assign AUDIO_L = audio_l_final;
    assign AUDIO_R = audio_r_final;
    assign AUDIO_MIX = 2'b00;

    assign LED_DISK = 2'b00;
    assign LED_POWER = 2'b00;
    assign BUTTONS = 2'b00;

    //////////////////////////////////////////////////////////////////

    assign VIDEO_ARX = 13'd4;
    assign VIDEO_ARY = 13'd3;

    `include "build_id.v"
    localparam CONF_STR = {
        "MegaVGMDrive;;",
        "F1,VGM,Load VGM;",
        "O1,Audio Gain,Normal,Boost;",
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
        "O24,SegaPCM Smoke,0 Base,1 Slow,2 Step2,3 Step4,4 LowVol,5 Left,6 Right,7 Short;",
        "O5,SegaPCM Smoke Source,Preload,Loaded;",
`endif
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
    wire [26:0] ioctl_addr;
    wire  [7:0] ioctl_dout;
    wire [15:0] ioctl_index;
    wire        ioctl_wait;
    wire        vgm_load_busy;
    wire        vgm_load_done;
    wire        vgm_load_error;
    wire        vgm_load_overflow;
    wire        vgm_header_valid;
    wire        vgm_player_error;
    wire  [7:0] vgm_unsupported_opcode;
    wire [17:0] vgm_unsupported_pc;
    wire  [7:0] vgm_player_error_code;
    wire [17:0] vgm_error_pc_debug;
    wire  [7:0] vgm_error_cmd_debug;
    wire [31:0] vgm_error_session_id;
    wire  [6:0] vgm_player_state_debug;
    wire        vgm_mem_rd_req_debug;
    wire        vgm_mem_rd_ready_debug;
    wire        vgm_mem_rd_valid_debug;
    wire [17:0] vgm_mem_rd_addr_debug;
    wire [15:0] vgm_player_core_debug;
    wire [15:0] vgm_player_lifecycle_debug;
    wire  [7:0] vgm_player_last_read_byte_debug;
    wire [31:0] vgm_header_magic_read_debug;
    wire  [3:0] vgm_header_magic_fail_index_debug;
    wire [17:0] vgm_read_request_addr_debug;
    wire [17:0] vgm_read_response_addr_debug;
    wire        vgm_read_pending_debug;
    wire        vgm_read_valid_consumed_debug;
    wire  [6:0] vgm_final_state_debug;
    wire [17:0] vgm_final_pc_debug;
    wire  [7:0] vgm_final_cmd_debug;
    wire  [7:0] vgm_final_error_code_debug;
    wire [15:0] vgm_final_flags_debug;
    wire  [3:0] vgm_final_reason_debug;
    wire [15:0] vgm_final_progress_debug;
    wire  [7:0] vgm_first_playback_cmd_after_scan_debug;
    wire [31:0] vgm_first_playback_cmds_after_scan_debug;
    wire  [6:0] vgm_scan_state_debug;
    wire [17:0] vgm_scan_pc_debug;
    wire  [7:0] vgm_scan_last_cmd_debug;
    wire  [7:0] vgm_scan_block_type_debug;
    wire [15:0] vgm_scan_block_size_low_debug;
    wire [15:0] vgm_scan_remaining_low_debug;
    wire [15:0] vgm_scan_wait_debug;
    wire  [7:0] vgm_scan_abort_reason_debug;
    wire [15:0] vgm_scan_copy_last_index_low_debug;
    wire [15:0] vgm_scan_copy_req_count_debug;
    wire [15:0] vgm_scan_copy_ready_count_debug;
    wire [15:0] vgm_scan_copy_tail_debug;
    wire [15:0] vgm_scan_player_accept_count_debug;
    wire [15:0] vgm_scan_player_remaining_debug;
    wire [15:0] vgm_scan_payload_len_low_debug;
    wire        vgm_scan_remaining_zero_before_expected_accept_debug;
    wire [15:0] vgm_scan_zero_state_debug;
    wire [15:0] vgm_scan_zero_pc_debug;
    wire [15:0] vgm_scan_zero_cmd_debug;
    wire [15:0] vgm_scan_copy_accept_fire_count_debug;
    wire [15:0] vgm_scan_noncopy_advance_count_debug;
    wire        vgm_scan_used_noncopy_advance_debug;
    wire [15:0] vgm_scan_raw_copy_byte_count_debug;
    wire [15:0] vgm_scan_raw_event_debug;
    wire [15:0] vgm_scan_copy_exit_debug;
    wire [15:0] vgm_scan_copy_exit_pc_debug;
    wire [15:0] vgm_scan_copy_exit_count_debug;
    wire [15:0] vgm_scan_copy_phase_debug;
    wire [15:0] vgm_scan_copy_read_req_count_debug;
    wire [15:0] vgm_scan_copy_read_accept_count_debug;
    wire [15:0] vgm_scan_copy_read_accept_internal_debug;
    wire [15:0] vgm_scan_copy_read_valid_count_debug;
    wire [15:0] vgm_scan_copy_mem_req_cycle_count_debug;
    wire [15:0] vgm_scan_copy_mem_req_ready_cycle_count_debug;
    wire [15:0] vgm_scan_copy_request_state_debug;
    wire [15:0] vgm_scan_copy_state_lifetime_debug;
    wire [15:0] vgm_scan_copy_clear_reason_debug;
    wire [15:0] vgm_scan_copy_payload_pc_debug;
    wire [15:0] vgm_scan_copy_first01_debug;
    wire [15:0] vgm_scan_copy_first23_debug;
    wire [15:0] vgm_scan_copy_first45_debug;
    wire [15:0] vgm_scan_copy_first67_debug;
    wire [15:0] vgm_scan_copy_first8_phase_debug;
    wire [15:0] vgm_scan_copy_read_raw_valid_count_debug;
    wire [15:0] vgm_scan_copy_read_ignored_valid_count_debug;
    wire [15:0] vgm_scan_copy_read_handshake_debug;
    wire [15:0] vgm_scan_payload_o0_debug;
    wire [15:0] vgm_scan_payload_oh_debug;
    wire [15:0] vgm_scan_payload_bd_debug;
    wire [15:0] vgm_scan_payload_af_debug;
    wire [15:0] vgm_scan_payload_ah_debug;
    wire [15:0] vgm_scan_payload_oh2_debug;
    wire [15:0] vgm_scan_payload_as_debug;
    wire [15:0] vgm_scan_payload_vd_debug;
    wire [15:0] vgm_scan_payload_vh_debug;
    wire [15:0] vgm_scan_payload_vs_debug;
    wire [15:0] vgm_scan_payload_cp_debug;
    wire [15:0] vgm_scan_payload_ch_debug;
    wire [15:0] vgm_scan_payload_cs_debug;
    wire [15:0] vgm_scan_raw_player_accept_count_debug;
    wire [15:0] vgm_scan_raw_copy_accept_count_debug;
    wire [15:0] vgm_scan_raw_read_accept_count_debug;
    wire [15:0] vgm_scan_raw_read_valid_count_debug;
    wire [15:0] vgm_scan_max_player_accept_count_debug;
    wire [15:0] vgm_scan_max_copy_accept_count_debug;
    wire [15:0] vgm_scan_max_read_accept_count_debug;
    wire [15:0] vgm_scan_max_read_valid_count_debug;
    wire [15:0] vgm_scan_counter_latch_accept_debug;
    wire [15:0] vgm_scan_counter_latch_read_debug;
    wire [15:0] vgm_scan_counter_anomaly_debug;
    wire [15:0] vgm_scan_counter_reset_source_debug;
    wire [15:0] vgm_scan_stop_source_debug;
    wire [15:0] vgm_scan_term_pl_debug;
    wire [15:0] vgm_scan_term_rm_debug;
    wire [15:0] vgm_scan_term_cc_debug;
    wire [15:0] vgm_scan_term_nx_debug;
    wire [15:0] vgm_scan_term_be_debug;
    wire [15:0] vgm_scan_guard_debug;
    wire [15:0] vgm_scan_sticky_guard_debug;
    wire [15:0] vgm_scan_payload_qg_debug;
    wire [15:0] vgm_scan_payload_sf_debug;
    wire [15:0] mode5_backend_copy_accept_count_debug;
    wire [15:0] mode5_backend_copy_write_count_debug;
    wire [15:0] mode5_backend_copy_fifo_debug;
    wire [15:0] mode5_backend_copy_ready_debug;
    wire [15:0] mode5_backend_copy_write_req_debug;
    wire [15:0] mode5_backend_copy_word_debug;
    wire [15:0] mode5_backend_copy_flush_debug;
    wire [15:0] mode5_backend_copy_full_detect_count_debug;
    wire [15:0] mode5_backend_copy_push_req_count_debug;
    wire [15:0] mode5_backend_copy_push_fire_count_debug;
    wire [15:0] mode5_backend_copy_fifo_push_count_debug;
    wire [15:0] mode5_backend_copy_pack_ready_debug;
    wire [15:0] mode5_backend_copy_post_push_debug;
    wire [15:0] mode5_backend_read_gate_debug;
    wire [15:0] mode5_backend_read_after_copy_count_debug;
    wire [15:0] mode5_read_mux_debug;
    wire [15:0] mode5_read_ready_compare_debug;
    wire [15:0] mode5_read_ready_blocker_debug;
    wire [15:0] mode5_copy_mismatch_debug;
    wire [15:0] mode5_copy_max_ready_count_debug;
    wire [15:0] mode5_copy_min_remaining_debug;
    wire [15:0] mode5_restart_after_load_count_debug;
    wire [15:0] mode5_scan_start_count_debug;
    wire [15:0] mode5_direct_start_debug;
    wire [15:0] mode5_top_stop_snapshot_debug;
    wire [18:0] vgm_load_size;
    wire [31:0] vgm_load_magic;
    wire [17:0] vgm_data_start_debug;
    wire [17:0] vgm_current_pc_debug;
    wire [17:0] vgm_loop_pc_debug;
    wire        vgm_loop_valid_debug;
    wire        vgm_loop_taken_debug;
    wire        vgm_end_command_seen;
    wire        vgm_restarted_from_data_start;
    wire        vgm_pcm_oob;
    wire [31:0] vgm_pcm_oob_count;
    wire [31:0] vgm_wait_ticks_consumed_debug;
    wire [31:0] dac_stream_cmd_count;
    wire [31:0] dac_stream_wait_samples_total;
    wire [31:0] dac_stream_clk_cycles_total;
    wire [31:0] dac_stream_overhead_cycles_total;
    wire [31:0] max_dac_stream_cmd_cycles;
    wire [31:0] count_wait0_dac_stream_cmd;
    wire [31:0] count_wait0_overhead_nonzero;
    wire [31:0] segapcm_write_count;
    wire [15:0] segapcm_last_addr;
    wire  [7:0] segapcm_last_data;
    wire [15:0] segapcm_core_rom_addr_low;
    wire [15:0] segapcm_core_rom_addr_raw_high;
    wire [15:0] segapcm_core_rom_addr_raw_low;
    wire [15:0] segapcm_core_rom_addr_mapped_high;
    wire [15:0] segapcm_core_rom_addr_mapped_low;
    wire [15:0] segapcm_core_rom_addr_min_high;
    wire [15:0] segapcm_core_rom_addr_min_low;
    wire [15:0] segapcm_core_rom_addr_max_high;
    wire [15:0] segapcm_core_rom_addr_max_low;
    wire [15:0] segapcm_core_rom_audio_active_high;
    wire [15:0] segapcm_core_rom_audio_active_low;
    wire [15:0] segapcm_core_rom_first_after_ctrl_high;
    wire [15:0] segapcm_core_rom_first_after_ctrl_low;
    wire [15:0] segapcm_core_rom_range_group;
    wire [15:0] segapcm_core_rom_range_group2;
    wire [15:0] segapcm_core_rom_early_after_ctrl_high;
    wire [15:0] segapcm_core_rom_early_after_ctrl_low;
    wire [15:0] segapcm_core_rom_active_after_ctrl_high;
    wire [15:0] segapcm_core_rom_active_after_ctrl_low;
    wire [15:0] segapcm_core_rom_hit_miss_compact;
    wire [15:0] segapcm_core_rom_range_hit_count;
    wire [15:0] segapcm_core_rom_range_miss_count;
    wire [15:0] segapcm_core_rom_activity_count;
    wire [15:0] segapcm_core_rom_return_mapped_high;
    wire [15:0] segapcm_core_rom_return_mapped_low;
    wire [15:0] segapcm_core_rom_return_data;
    wire [15:0] segapcm_core_rom_return_last01;
    wire [15:0] segapcm_core_rom_return_last23;
    wire [15:0] segapcm_core_rom_return_nonzero_count;
    wire [15:0] segapcm_core_rom_return_change_count;
    wire [15:0] segapcm_core_rom_return_neutral_count;
    wire [15:0] segapcm_core_rom_preload_data;
    wire [15:0] segapcm_core_rom_core_ok_count;
    wire [15:0] segapcm_core_rom_fallback_count;
    wire [15:0] segapcm_core_rom_read_valid_count;
    wire [15:0] segapcm_core_rom_latency_debug;
    wire [15:0] segapcm_core_rom_payload_len_low;
    wire [15:0] segapcm_core_rom_payload_len_high;
    wire [15:0] segapcm_core_pcm_debug_bk;
    wire [15:0] segapcm_core_pcm_debug_cuh;
    wire [15:0] segapcm_core_pcm_debug_cul;
    wire [15:0] segapcm_core_known38686_flags;
    wire [15:0] segapcm_core_known38686_bank;
    wire [15:0] segapcm_core_known38686_channel;
    wire [15:0] segapcm_core_known38686_state;
    wire [15:0] segapcm_core_known38686_cur_high;
    wire [15:0] segapcm_core_known38686_cur_low;
    wire [15:0] segapcm_core_known38686_en_addr;
    wire [15:0] segapcm_core_known38686_en_value;
    wire [15:0] segapcm_core_known38686_d0_addr;
    wire [15:0] segapcm_core_known38686_d0_value;
    wire [15:0] segapcm_core_known38686_d1_addr;
    wire [15:0] segapcm_core_known38686_d1_value;
    wire [15:0] segapcm_core_known38686_d2_addr;
    wire [15:0] segapcm_core_known38686_d2_value;
    wire [15:0] segapcm_core_known38686_cfg_en;
    wire [15:0] segapcm_core_known38686_cur_23;
    wire [15:0] segapcm_core_known38686_cur_15;
    wire [15:0] segapcm_core_known38686_cur_07;
    wire [15:0] segapcm_core_ch3_evolution_flags;
    wire [15:0] segapcm_core_ch3_delta;
    wire [15:0] segapcm_core_ch1_first_high;
    wire [15:0] segapcm_core_ch1_first_low;
    wire [15:0] segapcm_core_ch1_first_raw_high;
    wire [15:0] segapcm_core_ch1_first_raw_low;
    wire [15:0] segapcm_core_ch3_first_high;
    wire [15:0] segapcm_core_ch3_first_low;
    wire [15:0] segapcm_core_ch3_first_raw_high;
    wire [15:0] segapcm_core_ch3_first_raw_low;
    wire [15:0] segapcm_core_ch3_r0_high;
    wire [15:0] segapcm_core_ch3_r0_low;
    wire [15:0] segapcm_core_ch3_r1_high;
    wire [15:0] segapcm_core_ch3_r1_low;
    wire [15:0] segapcm_core_ch3_r2_high;
    wire [15:0] segapcm_core_ch3_r2_low;
    wire [15:0] segapcm_core_update_state_channel;
    wire [15:0] segapcm_core_update_before_23;
    wire [15:0] segapcm_core_update_before_15;
    wire [15:0] segapcm_core_update_before_07;
    wire [15:0] segapcm_core_update_addend;
    wire [15:0] segapcm_core_update_after_23;
    wire [15:0] segapcm_core_update_after_15;
    wire [15:0] segapcm_core_update_after_07;
    wire [15:0] segapcm_core_update_reason;
    wire [15:0] segapcm_core_cpu_write_count;
    wire [15:0] segapcm_core_cpu_cen_write_count;
    wire [15:0] segapcm_core_cpu_addr_debug;
    wire [15:0] segapcm_core_shadow_decode_debug;
    wire [15:0] segapcm_core_shadow_ch0_vol_debug;
    wire [15:0] segapcm_core_shadow_ch0_end_delta_debug;
    wire [15:0] segapcm_core_shadow_ch0_start_debug;
    wire [15:0] segapcm_core_shadow_ch0_ctrl_debug;
    wire [15:0] segapcm_core_shadow_ch1_vol_debug;
    wire [15:0] segapcm_core_shadow_ch1_loop_debug;
    wire [15:0] segapcm_core_shadow_ch1_end_delta_debug;
    wire [15:0] segapcm_core_shadow_ch1_start_debug;
    wire [15:0] segapcm_core_shadow_ch1_ctrl_debug;
    wire [15:0] segapcm_core_shadow_ch3_loop_debug;
    wire [15:0] segapcm_core_shadow_ch3_end_delta_debug;
    wire [15:0] segapcm_core_shadow_ch3_start_debug;
    wire [15:0] segapcm_core_shadow_ch3_ctrl_debug;
    wire [15:0] segapcm_core_shadow_ch3_l0_debug;
    wire [15:0] segapcm_core_shadow_ch3_l2_debug;
    wire [15:0] segapcm_core_shadow_ch3_l4_debug;
    wire [15:0] segapcm_core_shadow_ch3_l6_debug;
    wire [15:0] segapcm_core_shadow_ch3_h0_debug;
    wire [15:0] segapcm_core_shadow_ch3_h2_debug;
    wire [15:0] segapcm_core_shadow_ch3_h4_debug;
    wire [15:0] segapcm_core_shadow_ch3_h6_debug;
    wire [15:0] segapcm_core_audio_nonzero_count;
    wire [15:0] segapcm_core_audio_abs_peak;
    wire signed [15:0] segapcm_core_last_audio_l;
    wire signed [15:0] segapcm_core_last_audio_r;
    wire [15:0] segapcm_core_status_debug;
    wire [31:0] data_block_count;
    wire  [7:0] last_data_block_type;
    wire [15:0] last_data_block_size_low;
    wire [31:0] segapcm_rom_block_count;
    wire [31:0] segapcm_last_rom_size;
    wire [31:0] segapcm_last_rom_start;
    wire [31:0] pcm_ram_write_skip_count;
    wire        segapcm_rom_scan_busy;
    wire        segapcm_rom_scan_done;
    wire        segapcm_rom_scan_overflow;
    wire [31:0] segapcm_rom_scan_block_count;
    wire [31:0] segapcm_rom_scan_byte_count;
    wire [31:0] segapcm_rom_scan_checksum32;
    wire [31:0] segapcm_rom_scan_total_size;
    wire [31:0] segapcm_rom_scan_last_start;
    wire [31:0] segapcm_rom_copy_byte_count;
    wire        segapcm_rom_copy_overflow;
    wire        segapcm_rom_copy_flush_done;
    wire        segapcm_copy_flush_req_debug;
    wire        mode5_sound_reset_active;
    wire        mode5_player_start_pulse_debug;
    wire [15:0] mode5_start_hold_debug;
    wire [31:0] mode5_load_begin_count;
    wire [31:0] mode5_load_done_edge_count;
    wire [31:0] mode5_sound_reset_start_count;
    wire [31:0] mode5_player_start_count;
    wire [31:0] mode5_player_reset_count;
    wire [31:0] mode5_playback_session_id;
    wire [31:0] mode5_duplicate_start_blocked_count;
    wire [31:0] mode5_player_end_count;
    wire [31:0] mode5_repeat_restart_count;
    wire        mode5_done_armed_debug;
    wire [31:0] mode5_repeat_session_id;
    wire [31:0] mode5_done_session_id;
    wire [31:0] mode5_cycles_since_start;
    wire [17:0] mode5_done_pc_debug;
    wire  [7:0] mode5_done_cmd_debug;
    wire [15:0] fm_adjust_clip_count_l;
    wire [15:0] fm_adjust_clip_count_r;
    wire [15:0] genmix_wrap_count_l;
    wire [15:0] genmix_wrap_count_r;
    wire [31:0] ym_write_requested_count;
    wire [31:0] ym_write_accepted_count;
    wire [31:0] ym_write_dropped_or_busy_count;
    wire [31:0] ym_port0_count;
    wire [31:0] ym_port1_count;
    wire        last_ym_port;
    wire  [7:0] last_ym_addr;
    wire  [7:0] last_ym_data;
    wire [15:0] jt12_cen_interval_1_count;
    wire [15:0] jt12_cen_interval_2_count;
    wire [15:0] jt12_cen_interval_3_count;
    wire [15:0] jt12_cen_interval_4_count;
    wire [15:0] jt12_cen_interval_ge5_count;
    wire  [7:0] jt12_cen_interval_min;
    wire  [7:0] jt12_cen_interval_max;
    wire  [7:0] jt12_cen_interval_last;
    wire [15:0] fm_raw_abs_peak;
    wire [15:0] fm_adjust_abs_peak;
    wire [15:0] fm_lpf_abs_peak;
    wire [15:0] genmix_abs_peak;
    wire [15:0] md_final_audio_abs_peak;
    reg   [7:0] mode5_last_error_code = 8'd0;

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
        .ioctl_wait(ioctl_wait),

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
    wire vgm_reset_req = RESET | status[0] | !pll_locked;
    reg [23:0] vgm_reset_hold_count = 24'd0;
    reg        vgm_reset_hold_active = 1'b1;

    always @(posedge clk_sys) begin
        if (vgm_reset_req) begin
            vgm_reset_hold_count <= 24'd0;
            vgm_reset_hold_active <= 1'b1;
        end else if (vgm_reset_hold_active) begin
            if (&vgm_reset_hold_count) begin
                vgm_reset_hold_active <= 1'b0;
            end else begin
                vgm_reset_hold_count <= vgm_reset_hold_count + 24'd1;
            end
        end
    end

    wire vgm_reset = vgm_reset_req | vgm_reset_hold_active;
    wire vgm_reset_n = !vgm_reset;
    // Public OSD keeps only the user-facing gain switch. The gold audio path
    // stays fixed at no LPF and PSG 0.75 unless a development build overrides
    // these through compile-time macros inside md_sound_module.
    wire [1:0] audio_lpf_mode = 2'd3;
    wire       audio_gain_boost = status[1];
    wire [1:0] audio_psg_level = 2'd0;
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
    wire [2:0] segapcm_smoke_variant = status[4:2];
    wire       segapcm_smoke_source_loaded = status[5];
`endif

    wire               audio_sample_valid;
    wire               player_busy;
    wire               player_done;
    wire         [9:0] player_pc_debug;
    wire         [7:0] player_last_cmd_debug;
    wire               startup_reset_active;
    wire               startup_waiting;
    wire               startup_done;

`ifdef MODE5_VGM_BACKEND
    localparam int VGM_MODE5_BACKEND_PARAM = `MODE5_VGM_BACKEND;
`else
    localparam int VGM_MODE5_BACKEND_PARAM = 0;
`endif

`ifdef MODE5_VGM_ADDR_WIDTH
    localparam int VGM_LOAD_ADDR_WIDTH_PARAM = `MODE5_VGM_ADDR_WIDTH;
`else
    // Keep the BRAM backend at the proven 256KiB size.
    // The DDRAM backend can safely use a wider VGM address space.
    localparam int VGM_LOAD_ADDR_WIDTH_PARAM =
        (VGM_MODE5_BACKEND_PARAM == 1) ? 22 : 18;
`endif

    mister_vgm_md_top #(
        .VGM_LOAD_ADDR_WIDTH(VGM_LOAD_ADDR_WIDTH_PARAM),
        .MODE5_REPEAT_ENABLE(MODE5_REPEAT_ENABLE_BUILD),
        .MODE5_VGM_BACKEND(VGM_MODE5_BACKEND_PARAM)
    ) md_sound (
        .clk                   (clk_sys),
        .reset_n               (vgm_reset_n),
        .audio_l               (md_audio_l),
        .audio_r               (md_audio_r),
        .audio_sample_valid    (audio_sample_valid),
        .audio_lpf_mode        (audio_lpf_mode),
        .audio_gain_boost      (audio_gain_boost),
        .audio_psg_level       (audio_psg_level),
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
        .segapcm_smoke_variant (segapcm_smoke_variant),
        .segapcm_smoke_variant_valid(1'b1),
        .segapcm_smoke_source_loaded(segapcm_smoke_source_loaded),
`endif
        .player_busy           (player_busy),
        .player_done           (player_done),
        .player_pc_debug       (player_pc_debug),
        .player_last_cmd_debug (player_last_cmd_debug),
        .startup_reset_active  (startup_reset_active),
        .startup_waiting       (startup_waiting),
        .startup_done          (startup_done),
        .audio_gate_open       (audio_gate_open),
        .audio_muted           (audio_muted),
        .ioctl_download        (ioctl_download),
        .ioctl_wr              (ioctl_wr),
        .ioctl_addr            (ioctl_addr),
        .ioctl_dout            (ioctl_dout),
        .ioctl_index           (ioctl_index),
        .ioctl_wait            (ioctl_wait),
        .vgm_load_busy         (vgm_load_busy),
        .vgm_load_done         (vgm_load_done),
        .vgm_load_error        (vgm_load_error),
        .vgm_load_overflow     (vgm_load_overflow),
        .vgm_header_valid      (vgm_header_valid),
        .vgm_player_error      (vgm_player_error),
        .vgm_unsupported_opcode(vgm_unsupported_opcode),
        .vgm_unsupported_pc    (vgm_unsupported_pc),
        .vgm_player_error_code (vgm_player_error_code),
        .vgm_error_pc_debug    (vgm_error_pc_debug),
        .vgm_error_cmd_debug   (vgm_error_cmd_debug),
        .vgm_error_session_id  (vgm_error_session_id),
        .vgm_player_state_debug(vgm_player_state_debug),
        .vgm_mem_rd_req_debug  (vgm_mem_rd_req_debug),
        .vgm_mem_rd_ready_debug(vgm_mem_rd_ready_debug),
        .vgm_mem_rd_valid_debug(vgm_mem_rd_valid_debug),
        .vgm_mem_rd_addr_debug (vgm_mem_rd_addr_debug),
        .vgm_player_core_debug (vgm_player_core_debug),
        .vgm_player_lifecycle_debug(vgm_player_lifecycle_debug),
        .vgm_player_last_read_byte_debug(vgm_player_last_read_byte_debug),
        .vgm_header_magic_read_debug(vgm_header_magic_read_debug),
        .vgm_header_magic_fail_index_debug(vgm_header_magic_fail_index_debug),
        .vgm_read_request_addr_debug(vgm_read_request_addr_debug),
        .vgm_read_response_addr_debug(vgm_read_response_addr_debug),
        .vgm_read_pending_debug(vgm_read_pending_debug),
        .vgm_read_valid_consumed_debug(vgm_read_valid_consumed_debug),
        .vgm_final_state_debug (vgm_final_state_debug),
        .vgm_final_pc_debug    (vgm_final_pc_debug),
        .vgm_final_cmd_debug   (vgm_final_cmd_debug),
        .vgm_final_error_code_debug(vgm_final_error_code_debug),
        .vgm_final_flags_debug (vgm_final_flags_debug),
        .vgm_final_reason_debug(vgm_final_reason_debug),
        .vgm_final_progress_debug(vgm_final_progress_debug),
        .vgm_first_playback_cmd_after_scan_debug(vgm_first_playback_cmd_after_scan_debug),
        .vgm_first_playback_cmds_after_scan_debug(vgm_first_playback_cmds_after_scan_debug),
        .vgm_scan_state_debug (vgm_scan_state_debug),
        .vgm_scan_pc_debug    (vgm_scan_pc_debug),
        .vgm_scan_last_cmd_debug(vgm_scan_last_cmd_debug),
        .vgm_scan_block_type_debug(vgm_scan_block_type_debug),
        .vgm_scan_block_size_low_debug(vgm_scan_block_size_low_debug),
        .vgm_scan_remaining_low_debug(vgm_scan_remaining_low_debug),
        .vgm_scan_wait_debug  (vgm_scan_wait_debug),
        .vgm_scan_abort_reason_debug(vgm_scan_abort_reason_debug),
        .vgm_scan_copy_last_index_low_debug(vgm_scan_copy_last_index_low_debug),
        .vgm_scan_copy_req_count_debug(vgm_scan_copy_req_count_debug),
        .vgm_scan_copy_ready_count_debug(vgm_scan_copy_ready_count_debug),
        .vgm_scan_copy_tail_debug(vgm_scan_copy_tail_debug),
        .vgm_scan_player_accept_count_debug(vgm_scan_player_accept_count_debug),
        .vgm_scan_player_remaining_debug(vgm_scan_player_remaining_debug),
        .vgm_scan_payload_len_low_debug(vgm_scan_payload_len_low_debug),
        .vgm_scan_remaining_zero_before_expected_accept_debug(vgm_scan_remaining_zero_before_expected_accept_debug),
        .vgm_scan_zero_state_debug(vgm_scan_zero_state_debug),
        .vgm_scan_zero_pc_debug(vgm_scan_zero_pc_debug),
        .vgm_scan_zero_cmd_debug(vgm_scan_zero_cmd_debug),
        .vgm_scan_copy_accept_fire_count_debug(vgm_scan_copy_accept_fire_count_debug),
        .vgm_scan_noncopy_advance_count_debug(vgm_scan_noncopy_advance_count_debug),
        .vgm_scan_used_noncopy_advance_debug(vgm_scan_used_noncopy_advance_debug),
        .vgm_scan_raw_copy_byte_count_debug(vgm_scan_raw_copy_byte_count_debug),
        .vgm_scan_raw_event_debug(vgm_scan_raw_event_debug),
        .vgm_scan_copy_exit_debug(vgm_scan_copy_exit_debug),
        .vgm_scan_copy_exit_pc_debug(vgm_scan_copy_exit_pc_debug),
        .vgm_scan_copy_exit_count_debug(vgm_scan_copy_exit_count_debug),
        .vgm_scan_copy_phase_debug(vgm_scan_copy_phase_debug),
        .vgm_scan_copy_read_req_count_debug(vgm_scan_copy_read_req_count_debug),
        .vgm_scan_copy_read_accept_count_debug(vgm_scan_copy_read_accept_count_debug),
        .vgm_scan_copy_read_accept_internal_debug(vgm_scan_copy_read_accept_internal_debug),
        .vgm_scan_copy_read_valid_count_debug(vgm_scan_copy_read_valid_count_debug),
        .vgm_scan_copy_mem_req_cycle_count_debug(vgm_scan_copy_mem_req_cycle_count_debug),
        .vgm_scan_copy_mem_req_ready_cycle_count_debug(vgm_scan_copy_mem_req_ready_cycle_count_debug),
        .vgm_scan_copy_request_state_debug(vgm_scan_copy_request_state_debug),
        .vgm_scan_copy_state_lifetime_debug(vgm_scan_copy_state_lifetime_debug),
        .vgm_scan_copy_clear_reason_debug(vgm_scan_copy_clear_reason_debug),
        .vgm_scan_copy_payload_pc_debug(vgm_scan_copy_payload_pc_debug),
        .vgm_scan_copy_first01_debug(vgm_scan_copy_first01_debug),
        .vgm_scan_copy_first23_debug(vgm_scan_copy_first23_debug),
        .vgm_scan_copy_first45_debug(vgm_scan_copy_first45_debug),
        .vgm_scan_copy_first67_debug(vgm_scan_copy_first67_debug),
        .vgm_scan_copy_first8_phase_debug(vgm_scan_copy_first8_phase_debug),
        .vgm_scan_copy_read_raw_valid_count_debug(vgm_scan_copy_read_raw_valid_count_debug),
        .vgm_scan_copy_read_ignored_valid_count_debug(vgm_scan_copy_read_ignored_valid_count_debug),
        .vgm_scan_copy_read_handshake_debug(vgm_scan_copy_read_handshake_debug),
        .vgm_scan_payload_o0_debug(vgm_scan_payload_o0_debug),
        .vgm_scan_payload_oh_debug(vgm_scan_payload_oh_debug),
        .vgm_scan_payload_bd_debug(vgm_scan_payload_bd_debug),
        .vgm_scan_payload_af_debug(vgm_scan_payload_af_debug),
        .vgm_scan_payload_ah_debug(vgm_scan_payload_ah_debug),
        .vgm_scan_payload_oh2_debug(vgm_scan_payload_oh2_debug),
        .vgm_scan_payload_as_debug(vgm_scan_payload_as_debug),
        .vgm_scan_payload_vd_debug(vgm_scan_payload_vd_debug),
        .vgm_scan_payload_vh_debug(vgm_scan_payload_vh_debug),
        .vgm_scan_payload_vs_debug(vgm_scan_payload_vs_debug),
        .vgm_scan_payload_cp_debug(vgm_scan_payload_cp_debug),
        .vgm_scan_payload_ch_debug(vgm_scan_payload_ch_debug),
        .vgm_scan_payload_cs_debug(vgm_scan_payload_cs_debug),
        .vgm_scan_raw_player_accept_count_debug(vgm_scan_raw_player_accept_count_debug),
        .vgm_scan_raw_copy_accept_count_debug(vgm_scan_raw_copy_accept_count_debug),
        .vgm_scan_raw_read_accept_count_debug(vgm_scan_raw_read_accept_count_debug),
        .vgm_scan_raw_read_valid_count_debug(vgm_scan_raw_read_valid_count_debug),
        .vgm_scan_max_player_accept_count_debug(vgm_scan_max_player_accept_count_debug),
        .vgm_scan_max_copy_accept_count_debug(vgm_scan_max_copy_accept_count_debug),
        .vgm_scan_max_read_accept_count_debug(vgm_scan_max_read_accept_count_debug),
        .vgm_scan_max_read_valid_count_debug(vgm_scan_max_read_valid_count_debug),
        .vgm_scan_counter_latch_accept_debug(vgm_scan_counter_latch_accept_debug),
        .vgm_scan_counter_latch_read_debug(vgm_scan_counter_latch_read_debug),
        .vgm_scan_counter_anomaly_debug(vgm_scan_counter_anomaly_debug),
        .vgm_scan_counter_reset_source_debug(vgm_scan_counter_reset_source_debug),
        .vgm_scan_stop_source_debug(vgm_scan_stop_source_debug),
        .vgm_scan_term_pl_debug(vgm_scan_term_pl_debug),
        .vgm_scan_term_rm_debug(vgm_scan_term_rm_debug),
        .vgm_scan_term_cc_debug(vgm_scan_term_cc_debug),
        .vgm_scan_term_nx_debug(vgm_scan_term_nx_debug),
        .vgm_scan_term_be_debug(vgm_scan_term_be_debug),
        .vgm_scan_guard_debug(vgm_scan_guard_debug),
        .vgm_scan_sticky_guard_debug(vgm_scan_sticky_guard_debug),
        .vgm_scan_payload_qg_debug(vgm_scan_payload_qg_debug),
        .vgm_scan_payload_sf_debug(vgm_scan_payload_sf_debug),
        .mode5_backend_copy_accept_count_debug(mode5_backend_copy_accept_count_debug),
        .mode5_backend_copy_write_count_debug(mode5_backend_copy_write_count_debug),
        .mode5_backend_copy_fifo_debug(mode5_backend_copy_fifo_debug),
        .mode5_backend_copy_ready_debug(mode5_backend_copy_ready_debug),
        .mode5_backend_copy_write_req_debug(mode5_backend_copy_write_req_debug),
        .mode5_backend_copy_word_debug(mode5_backend_copy_word_debug),
        .mode5_backend_copy_flush_debug(mode5_backend_copy_flush_debug),
        .mode5_backend_copy_full_detect_count_debug(mode5_backend_copy_full_detect_count_debug),
        .mode5_backend_copy_push_req_count_debug(mode5_backend_copy_push_req_count_debug),
        .mode5_backend_copy_push_fire_count_debug(mode5_backend_copy_push_fire_count_debug),
        .mode5_backend_copy_fifo_push_count_debug(mode5_backend_copy_fifo_push_count_debug),
        .mode5_backend_copy_pack_ready_debug(mode5_backend_copy_pack_ready_debug),
        .mode5_backend_copy_post_push_debug(mode5_backend_copy_post_push_debug),
        .mode5_backend_read_gate_debug(mode5_backend_read_gate_debug),
        .mode5_backend_read_after_copy_count_debug(mode5_backend_read_after_copy_count_debug),
        .mode5_read_mux_debug(mode5_read_mux_debug),
        .mode5_read_ready_compare_debug(mode5_read_ready_compare_debug),
        .mode5_read_ready_blocker_debug(mode5_read_ready_blocker_debug),
        .mode5_copy_mismatch_debug(mode5_copy_mismatch_debug),
        .mode5_copy_max_ready_count_debug(mode5_copy_max_ready_count_debug),
        .mode5_copy_min_remaining_debug(mode5_copy_min_remaining_debug),
        .mode5_restart_after_load_count_debug(mode5_restart_after_load_count_debug),
        .mode5_scan_start_count_debug(mode5_scan_start_count_debug),
        .mode5_direct_start_debug(mode5_direct_start_debug),
        .mode5_top_stop_snapshot_debug(mode5_top_stop_snapshot_debug),
        .vgm_load_size         (vgm_load_size),
        .vgm_load_magic        (vgm_load_magic),
        .vgm_data_start_debug  (vgm_data_start_debug),
        .vgm_current_pc_debug  (vgm_current_pc_debug),
        .vgm_loop_pc_debug     (vgm_loop_pc_debug),
        .vgm_loop_valid_debug  (vgm_loop_valid_debug),
        .vgm_loop_taken_debug  (vgm_loop_taken_debug),
        .vgm_end_command_seen  (vgm_end_command_seen),
        .vgm_restarted_from_data_start(vgm_restarted_from_data_start),
        .vgm_pcm_oob           (vgm_pcm_oob),
        .vgm_pcm_oob_count     (vgm_pcm_oob_count),
        .vgm_wait_ticks_consumed_debug(vgm_wait_ticks_consumed_debug),
        .dac_stream_cmd_count  (dac_stream_cmd_count),
        .dac_stream_wait_samples_total(dac_stream_wait_samples_total),
        .dac_stream_clk_cycles_total(dac_stream_clk_cycles_total),
        .dac_stream_overhead_cycles_total(dac_stream_overhead_cycles_total),
        .max_dac_stream_cmd_cycles(max_dac_stream_cmd_cycles),
        .count_wait0_dac_stream_cmd(count_wait0_dac_stream_cmd),
        .count_wait0_overhead_nonzero(count_wait0_overhead_nonzero),
        .segapcm_write_count   (segapcm_write_count),
        .segapcm_last_addr     (segapcm_last_addr),
        .segapcm_last_data     (segapcm_last_data),
        .segapcm_core_rom_addr_low(segapcm_core_rom_addr_low),
        .segapcm_core_rom_addr_raw_high(segapcm_core_rom_addr_raw_high),
        .segapcm_core_rom_addr_raw_low(segapcm_core_rom_addr_raw_low),
        .segapcm_core_rom_addr_mapped_high(segapcm_core_rom_addr_mapped_high),
        .segapcm_core_rom_addr_mapped_low(segapcm_core_rom_addr_mapped_low),
        .segapcm_core_rom_addr_min_high(segapcm_core_rom_addr_min_high),
        .segapcm_core_rom_addr_min_low(segapcm_core_rom_addr_min_low),
        .segapcm_core_rom_addr_max_high(segapcm_core_rom_addr_max_high),
        .segapcm_core_rom_addr_max_low(segapcm_core_rom_addr_max_low),
        .segapcm_core_rom_audio_active_high(segapcm_core_rom_audio_active_high),
        .segapcm_core_rom_audio_active_low(segapcm_core_rom_audio_active_low),
        .segapcm_core_rom_first_after_ctrl_high(segapcm_core_rom_first_after_ctrl_high),
        .segapcm_core_rom_first_after_ctrl_low(segapcm_core_rom_first_after_ctrl_low),
        .segapcm_core_rom_range_group(segapcm_core_rom_range_group),
        .segapcm_core_rom_range_group2(segapcm_core_rom_range_group2),
        .segapcm_core_rom_early_after_ctrl_high(segapcm_core_rom_early_after_ctrl_high),
        .segapcm_core_rom_early_after_ctrl_low(segapcm_core_rom_early_after_ctrl_low),
        .segapcm_core_rom_active_after_ctrl_high(segapcm_core_rom_active_after_ctrl_high),
        .segapcm_core_rom_active_after_ctrl_low(segapcm_core_rom_active_after_ctrl_low),
        .segapcm_core_rom_hit_miss_compact(segapcm_core_rom_hit_miss_compact),
        .segapcm_core_rom_range_hit_count(segapcm_core_rom_range_hit_count),
        .segapcm_core_rom_range_miss_count(segapcm_core_rom_range_miss_count),
        .segapcm_core_rom_activity_count(segapcm_core_rom_activity_count),
        .segapcm_core_rom_return_mapped_high(segapcm_core_rom_return_mapped_high),
        .segapcm_core_rom_return_mapped_low(segapcm_core_rom_return_mapped_low),
        .segapcm_core_rom_return_data(segapcm_core_rom_return_data),
        .segapcm_core_rom_return_last01(segapcm_core_rom_return_last01),
        .segapcm_core_rom_return_last23(segapcm_core_rom_return_last23),
        .segapcm_core_rom_return_nonzero_count(segapcm_core_rom_return_nonzero_count),
        .segapcm_core_rom_return_change_count(segapcm_core_rom_return_change_count),
        .segapcm_core_rom_return_neutral_count(segapcm_core_rom_return_neutral_count),
        .segapcm_core_rom_preload_data(segapcm_core_rom_preload_data),
        .segapcm_core_rom_core_ok_count(segapcm_core_rom_core_ok_count),
        .segapcm_core_rom_fallback_count(segapcm_core_rom_fallback_count),
        .segapcm_core_rom_read_valid_count(segapcm_core_rom_read_valid_count),
        .segapcm_core_rom_latency_debug(segapcm_core_rom_latency_debug),
        .segapcm_core_rom_payload_len_low(segapcm_core_rom_payload_len_low),
        .segapcm_core_rom_payload_len_high(segapcm_core_rom_payload_len_high),
        .segapcm_core_pcm_debug_bk(segapcm_core_pcm_debug_bk),
        .segapcm_core_pcm_debug_cuh(segapcm_core_pcm_debug_cuh),
        .segapcm_core_pcm_debug_cul(segapcm_core_pcm_debug_cul),
        .segapcm_core_known38686_flags(segapcm_core_known38686_flags),
        .segapcm_core_known38686_bank(segapcm_core_known38686_bank),
        .segapcm_core_known38686_channel(segapcm_core_known38686_channel),
        .segapcm_core_known38686_state(segapcm_core_known38686_state),
        .segapcm_core_known38686_cur_high(segapcm_core_known38686_cur_high),
        .segapcm_core_known38686_cur_low(segapcm_core_known38686_cur_low),
        .segapcm_core_known38686_en_addr(segapcm_core_known38686_en_addr),
        .segapcm_core_known38686_en_value(segapcm_core_known38686_en_value),
        .segapcm_core_known38686_d0_addr(segapcm_core_known38686_d0_addr),
        .segapcm_core_known38686_d0_value(segapcm_core_known38686_d0_value),
        .segapcm_core_known38686_d1_addr(segapcm_core_known38686_d1_addr),
        .segapcm_core_known38686_d1_value(segapcm_core_known38686_d1_value),
        .segapcm_core_known38686_d2_addr(segapcm_core_known38686_d2_addr),
        .segapcm_core_known38686_d2_value(segapcm_core_known38686_d2_value),
        .segapcm_core_known38686_cfg_en(segapcm_core_known38686_cfg_en),
        .segapcm_core_known38686_cur_23(segapcm_core_known38686_cur_23),
        .segapcm_core_known38686_cur_15(segapcm_core_known38686_cur_15),
        .segapcm_core_known38686_cur_07(segapcm_core_known38686_cur_07),
        .segapcm_core_ch3_evolution_flags(segapcm_core_ch3_evolution_flags),
        .segapcm_core_ch3_delta(segapcm_core_ch3_delta),
        .segapcm_core_ch1_first_high(segapcm_core_ch1_first_high),
        .segapcm_core_ch1_first_low(segapcm_core_ch1_first_low),
        .segapcm_core_ch1_first_raw_high(segapcm_core_ch1_first_raw_high),
        .segapcm_core_ch1_first_raw_low(segapcm_core_ch1_first_raw_low),
        .segapcm_core_ch3_first_high(segapcm_core_ch3_first_high),
        .segapcm_core_ch3_first_low(segapcm_core_ch3_first_low),
        .segapcm_core_ch3_first_raw_high(segapcm_core_ch3_first_raw_high),
        .segapcm_core_ch3_first_raw_low(segapcm_core_ch3_first_raw_low),
        .segapcm_core_ch3_r0_high(segapcm_core_ch3_r0_high),
        .segapcm_core_ch3_r0_low(segapcm_core_ch3_r0_low),
        .segapcm_core_ch3_r1_high(segapcm_core_ch3_r1_high),
        .segapcm_core_ch3_r1_low(segapcm_core_ch3_r1_low),
        .segapcm_core_ch3_r2_high(segapcm_core_ch3_r2_high),
        .segapcm_core_ch3_r2_low(segapcm_core_ch3_r2_low),
        .segapcm_core_update_state_channel(segapcm_core_update_state_channel),
        .segapcm_core_update_before_23(segapcm_core_update_before_23),
        .segapcm_core_update_before_15(segapcm_core_update_before_15),
        .segapcm_core_update_before_07(segapcm_core_update_before_07),
        .segapcm_core_update_addend(segapcm_core_update_addend),
        .segapcm_core_update_after_23(segapcm_core_update_after_23),
        .segapcm_core_update_after_15(segapcm_core_update_after_15),
        .segapcm_core_update_after_07(segapcm_core_update_after_07),
        .segapcm_core_update_reason(segapcm_core_update_reason),
        .segapcm_core_cpu_write_count(segapcm_core_cpu_write_count),
        .segapcm_core_cpu_cen_write_count(segapcm_core_cpu_cen_write_count),
        .segapcm_core_cpu_addr_debug(segapcm_core_cpu_addr_debug),
        .segapcm_core_shadow_decode_debug(segapcm_core_shadow_decode_debug),
        .segapcm_core_shadow_ch0_vol_debug(segapcm_core_shadow_ch0_vol_debug),
        .segapcm_core_shadow_ch0_end_delta_debug(segapcm_core_shadow_ch0_end_delta_debug),
        .segapcm_core_shadow_ch0_start_debug(segapcm_core_shadow_ch0_start_debug),
        .segapcm_core_shadow_ch0_ctrl_debug(segapcm_core_shadow_ch0_ctrl_debug),
        .segapcm_core_shadow_ch1_vol_debug(segapcm_core_shadow_ch1_vol_debug),
        .segapcm_core_shadow_ch1_loop_debug(segapcm_core_shadow_ch1_loop_debug),
        .segapcm_core_shadow_ch1_end_delta_debug(segapcm_core_shadow_ch1_end_delta_debug),
        .segapcm_core_shadow_ch1_start_debug(segapcm_core_shadow_ch1_start_debug),
        .segapcm_core_shadow_ch1_ctrl_debug(segapcm_core_shadow_ch1_ctrl_debug),
        .segapcm_core_shadow_ch3_loop_debug(segapcm_core_shadow_ch3_loop_debug),
        .segapcm_core_shadow_ch3_end_delta_debug(segapcm_core_shadow_ch3_end_delta_debug),
        .segapcm_core_shadow_ch3_start_debug(segapcm_core_shadow_ch3_start_debug),
        .segapcm_core_shadow_ch3_ctrl_debug(segapcm_core_shadow_ch3_ctrl_debug),
        .segapcm_core_shadow_ch3_l0_debug(segapcm_core_shadow_ch3_l0_debug),
        .segapcm_core_shadow_ch3_l2_debug(segapcm_core_shadow_ch3_l2_debug),
        .segapcm_core_shadow_ch3_l4_debug(segapcm_core_shadow_ch3_l4_debug),
        .segapcm_core_shadow_ch3_l6_debug(segapcm_core_shadow_ch3_l6_debug),
        .segapcm_core_shadow_ch3_h0_debug(segapcm_core_shadow_ch3_h0_debug),
        .segapcm_core_shadow_ch3_h2_debug(segapcm_core_shadow_ch3_h2_debug),
        .segapcm_core_shadow_ch3_h4_debug(segapcm_core_shadow_ch3_h4_debug),
        .segapcm_core_shadow_ch3_h6_debug(segapcm_core_shadow_ch3_h6_debug),
        .segapcm_core_audio_nonzero_count(segapcm_core_audio_nonzero_count),
        .segapcm_core_audio_abs_peak(segapcm_core_audio_abs_peak),
        .segapcm_core_last_audio_l(segapcm_core_last_audio_l),
        .segapcm_core_last_audio_r(segapcm_core_last_audio_r),
        .segapcm_core_status_debug(segapcm_core_status_debug),
        .data_block_count      (data_block_count),
        .last_data_block_type  (last_data_block_type),
        .last_data_block_size_low(last_data_block_size_low),
        .segapcm_rom_block_count(segapcm_rom_block_count),
        .segapcm_last_rom_size (segapcm_last_rom_size),
        .segapcm_last_rom_start(segapcm_last_rom_start),
        .pcm_ram_write_skip_count(pcm_ram_write_skip_count),
        .segapcm_rom_scan_busy (segapcm_rom_scan_busy),
        .segapcm_rom_scan_done (segapcm_rom_scan_done),
        .segapcm_rom_scan_overflow(segapcm_rom_scan_overflow),
        .segapcm_rom_scan_block_count(segapcm_rom_scan_block_count),
        .segapcm_rom_scan_byte_count(segapcm_rom_scan_byte_count),
        .segapcm_rom_scan_checksum32(segapcm_rom_scan_checksum32),
        .segapcm_rom_scan_total_size(segapcm_rom_scan_total_size),
        .segapcm_rom_scan_last_start(segapcm_rom_scan_last_start),
        .segapcm_rom_copy_byte_count(segapcm_rom_copy_byte_count),
        .segapcm_rom_copy_overflow(segapcm_rom_copy_overflow),
        .segapcm_rom_copy_flush_done(segapcm_rom_copy_flush_done),
        .segapcm_copy_flush_req_debug(segapcm_copy_flush_req_debug),
        .mode5_sound_reset_active(mode5_sound_reset_active),
        .mode5_player_start_pulse_debug(mode5_player_start_pulse_debug),
        .mode5_start_hold_debug(mode5_start_hold_debug),
        .mode5_load_begin_count(mode5_load_begin_count),
        .mode5_load_done_edge_count(mode5_load_done_edge_count),
        .mode5_sound_reset_start_count(mode5_sound_reset_start_count),
        .mode5_player_start_count(mode5_player_start_count),
        .mode5_player_reset_count(mode5_player_reset_count),
        .mode5_playback_session_id(mode5_playback_session_id),
        .mode5_duplicate_start_blocked_count(mode5_duplicate_start_blocked_count),
        .mode5_player_end_count(mode5_player_end_count),
        .mode5_repeat_restart_count(mode5_repeat_restart_count),
        .mode5_done_armed_debug(mode5_done_armed_debug),
        .mode5_repeat_session_id(mode5_repeat_session_id),
        .mode5_done_session_id(mode5_done_session_id),
        .mode5_cycles_since_start(mode5_cycles_since_start),
        .mode5_done_pc_debug(mode5_done_pc_debug),
        .mode5_done_cmd_debug(mode5_done_cmd_debug),
        .fm_adjust_clip_count_l(fm_adjust_clip_count_l),
        .fm_adjust_clip_count_r(fm_adjust_clip_count_r),
        .genmix_wrap_count_l   (genmix_wrap_count_l),
        .genmix_wrap_count_r   (genmix_wrap_count_r),
        .ym_write_requested_count(ym_write_requested_count),
        .ym_write_accepted_count(ym_write_accepted_count),
        .ym_write_dropped_or_busy_count(ym_write_dropped_or_busy_count),
        .ym_port0_count        (ym_port0_count),
        .ym_port1_count        (ym_port1_count),
        .last_ym_port          (last_ym_port),
        .last_ym_addr          (last_ym_addr),
        .last_ym_data          (last_ym_data),
        .jt12_cen_interval_1_count(jt12_cen_interval_1_count),
        .jt12_cen_interval_2_count(jt12_cen_interval_2_count),
        .jt12_cen_interval_3_count(jt12_cen_interval_3_count),
        .jt12_cen_interval_4_count(jt12_cen_interval_4_count),
        .jt12_cen_interval_ge5_count(jt12_cen_interval_ge5_count),
        .jt12_cen_interval_min(jt12_cen_interval_min),
        .jt12_cen_interval_max(jt12_cen_interval_max),
        .jt12_cen_interval_last(jt12_cen_interval_last),
        .fm_raw_abs_peak      (fm_raw_abs_peak),
        .fm_adjust_abs_peak   (fm_adjust_abs_peak),
        .fm_lpf_abs_peak      (fm_lpf_abs_peak),
        .genmix_abs_peak      (genmix_abs_peak),
        .md_final_audio_abs_peak(md_final_audio_abs_peak),

        .ddram_busy           (DDRAM_BUSY),
        .ddram_burstcnt       (vgm_ddram_burstcnt),
        .ddram_addr           (vgm_ddram_addr),
        .ddram_dout           (DDRAM_DOUT),
        .ddram_dout_ready     (DDRAM_DOUT_READY),
        .ddram_rd             (vgm_ddram_rd),
        .ddram_din            (vgm_ddram_din),
        .ddram_be             (vgm_ddram_be),
        .ddram_we             (vgm_ddram_we)
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

        if (reset || startup_reset_active) begin
            done_latched <= 1'b0;
            audio_seen_latched <= 1'b0;
        end else begin
            if (player_done) begin
                done_latched <= 1'b1;
            end

            if (audio_sample_valid) begin
                audio_seen_latched <= 1'b1;
            end
        end

        if (reset) begin
            mode5_last_error_code <= 8'd0;
        end else if (vgm_player_error) begin
            mode5_last_error_code <= vgm_player_error_code;
        end else if (vgm_load_overflow) begin
            mode5_last_error_code <= 8'hf2;
        end else if (vgm_load_error) begin
            mode5_last_error_code <= 8'hf1;
        end
    end

    wire hblank = (h_count >= 9'd320);
    wire vblank = (v_count >= 9'd240);
    wire active = !hblank && !vblank;
    wire [15:0] md_audio_abs_peak =
        (md_audio_l_abs_peak > md_audio_r_abs_peak) ?
        md_audio_l_abs_peak : md_audio_r_abs_peak;
    wire [15:0] emu_audio_abs_peak =
        (emu_audio_l_abs_peak > emu_audio_r_abs_peak) ?
        emu_audio_l_abs_peak : emu_audio_r_abs_peak;
    wire md_audio_rail_seen =
        (md_audio_l_rail_count != 16'd0) || (md_audio_r_rail_count != 16'd0);
    wire emu_audio_rail_seen =
        (emu_audio_l_rail_count != 16'd0) || (emu_audio_r_rail_count != 16'd0);

    wire [15:0] meter_x_level = h_count * 16'd102;
    wire meter_x_active = (h_count < 9'd320);
    wire meter_reference_marker = (h_count >= 9'd234) && (h_count < 9'd237);
    wire meter_rail_block = (h_count >= 9'd312) && (h_count < 9'd320);
    wire stage_fm_raw_row = (v_count >= 9'd184) && (v_count < 9'd188);
    wire stage_fm_adjust_row = (v_count >= 9'd190) && (v_count < 9'd194);
    wire stage_fm_lpf_row = (v_count >= 9'd196) && (v_count < 9'd200);
    wire stage_genmix_row = (v_count >= 9'd202) && (v_count < 9'd206);
    wire stage_final_row = (v_count >= 9'd208) && (v_count < 9'd212);
    wire md_avg_meter_row = (v_count >= 9'd214) && (v_count < 9'd218);
    wire md_meter_row = (v_count >= 9'd220) && (v_count < 9'd226);
    wire emu_meter_row = (v_count >= 9'd230) && (v_count < 9'd236);
    wire emu_avg_meter_row = (v_count >= 9'd236) && (v_count < 9'd240);
    wire stage_meter_pixel =
        meter_x_active &&
        (stage_fm_raw_row ||
         stage_fm_adjust_row ||
         stage_fm_lpf_row ||
         stage_genmix_row ||
         stage_final_row);
    wire md_meter_pixel = md_meter_row && meter_x_active;
    wire emu_meter_pixel = emu_meter_row && meter_x_active;
    wire md_avg_meter_pixel = md_avg_meter_row && meter_x_active;
    wire emu_avg_meter_pixel = emu_avg_meter_row && meter_x_active;
    wire stage_fm_raw_fill = fm_raw_abs_peak >= meter_x_level;
    wire stage_fm_adjust_fill = fm_adjust_abs_peak >= meter_x_level;
    wire stage_fm_lpf_fill = fm_lpf_abs_peak >= meter_x_level;
    wire stage_genmix_fill = genmix_abs_peak >= meter_x_level;
    wire stage_final_fill = md_final_audio_abs_peak >= meter_x_level;
    wire md_meter_fill = md_audio_abs_peak >= meter_x_level;
    wire emu_meter_fill = emu_audio_abs_peak >= meter_x_level;
    wire md_avg_meter_fill = md_audio_abs_avg >= meter_x_level;
    wire emu_avg_meter_fill = emu_audio_abs_avg >= meter_x_level;
    wire [23:0] stage_meter_rgb =
        meter_reference_marker ? 24'hffffff :
        stage_fm_raw_row ? (stage_fm_raw_fill ? 24'h00c8ff : 24'h081018) :
        stage_fm_adjust_row ? (stage_fm_adjust_fill ? 24'hff8000 : 24'h181000) :
        stage_fm_lpf_row ? (stage_fm_lpf_fill ? 24'hc080ff : 24'h140818) :
        stage_genmix_row ? (stage_genmix_fill ? 24'hff40c0 : 24'h180814) :
        stage_final_fill ? 24'hc0c0c0 :
                           24'h101010;
    wire [23:0] md_meter_rgb =
        (meter_rail_block && md_audio_rail_seen) ? 24'hff0000 :
        meter_reference_marker ? 24'hffffff :
        md_meter_fill ? 24'h2040ff :
                        24'h101018;
    wire [23:0] emu_meter_rgb =
        (meter_rail_block && emu_audio_rail_seen) ? 24'hff0000 :
        meter_reference_marker ? 24'hffffff :
        emu_meter_fill ? 24'h00d060 :
                         24'h101810;
    wire [23:0] md_avg_meter_rgb =
        meter_reference_marker ? 24'hffffff :
        md_avg_meter_fill ? 24'h4080ff :
                            24'h080c18;
    wire [23:0] emu_avg_meter_rgb =
        meter_reference_marker ? 24'hffffff :
        emu_avg_meter_fill ? 24'h40ff80 :
                             24'h081208;
    wire force_mute_build_marker = MD_AUDIO_FORCE_MUTE_BUILD && (v_count < 9'd12);
    wire ym_write_slow_build_marker = MD_YM_WRITE_SLOW_BUILD && (v_count < 9'd12);
    wire ym_force_lfo_off_build_marker =
        MD_YM_FORCE_LFO_OFF_BUILD && (v_count < 9'd12);
    wire ym_mask_pms_ams_build_marker =
        MD_YM_MASK_PMS_AMS_BUILD && (v_count < 9'd12);
    wire ym_ch3_normal_build_marker =
        MD_YM_CH3_NORMAL_BUILD && (v_count < 9'd12);
    wire sysout_attenuate_24db_build_marker =
        MD_AUDIO_SYSOUT_ATTENUATE_24DB_BUILD && (v_count < 9'd12);
    wire sysout_attenuate_build_marker =
        MD_AUDIO_SYSOUT_ATTENUATE_BUILD && (v_count < 9'd12);
    wire sysout_force_tone_build_marker =
        MD_AUDIO_SYSOUT_FORCE_TONE_BUILD && (v_count < 9'd12);
    wire sysout_gain_4x_sat_build_marker =
        MD_AUDIO_SYSOUT_GAIN_4X_SAT_BUILD && (v_count < 9'd12);
    wire sysout_gain_2x_sat_build_marker =
        MD_AUDIO_SYSOUT_GAIN_2X_SAT_BUILD && (v_count < 9'd12);
    wire attenuate_6db_build_marker = MD_AUDIO_ATTENUATE_6DB_BUILD && (v_count < 9'd12);
    wire output_shift_1_build_marker =
        MD_AUDIO_OUTPUT_SHIFT_1_BUILD && (v_count < 9'd12);
    wire output_shift_0_build_marker =
        MD_AUDIO_OUTPUT_SHIFT_0_BUILD && (v_count < 9'd12);
    wire fm_force_mute_build_marker =
        MD_AUDIO_FM_FORCE_MUTE_BUILD && (v_count < 9'd12);
    wire fm_only_build_marker = MD_AUDIO_FM_ONLY_BUILD && (v_count < 9'd12);
    wire psg_only_build_marker = MD_AUDIO_PSG_ONLY_BUILD && (v_count < 9'd12);
    wire fm_ch_solo_build_marker =
        MD_AUDIO_FM_CH_SOLO_BUILD && (v_count < 9'd12);
    wire premix_fm_attenuate_build_marker =
        MD_AUDIO_PREMIX_ATTENUATE_FM_BUILD && (v_count < 9'd12);
    wire fm_adjust_bypass_build_marker =
        MD_AUDIO_FM_ADJUST_BYPASS_BUILD && (v_count < 9'd12);
    wire fm_adjust_low_gain_build_marker =
        MD_AUDIO_FM_ADJUST_LOW_GAIN_BUILD && (v_count < 9'd12);
    wire fm_adjust_saturate_build_marker =
        MD_AUDIO_FM_ADJUST_SATURATE_BUILD && (v_count < 9'd12);
    wire premix_psg_attenuate_build_marker =
        MD_AUDIO_PREMIX_ATTENUATE_PSG_BUILD && (v_count < 9'd12);
    wire raw_jt12_fm_build_marker =
        MD_AUDIO_RAW_JT12_FM_BUILD && (v_count < 9'd12);
    wire raw_jt12_sample_latch_build_marker =
        MD_AUDIO_RAW_JT12_SAMPLE_LATCH_BUILD && (v_count < 9'd12);
    wire normal_sample_latch_build_marker =
        MD_AUDIO_NORMAL_SAMPLE_LATCH_BUILD && (v_count < 9'd12);
    wire jt12_cen_ntsc_build_marker =
        MD_JT12_CEN_NTSC_BUILD && (v_count < 9'd12);
    wire jt12_cen_every_clk_build_marker =
        MD_JT12_CEN_EVERY_CLK_BUILD && (v_count < 9'd12);
    wire jt12_cen_uniform_10mhz_build_marker =
        MD_JT12_CEN_UNIFORM_10MHZ_BUILD && (v_count < 9'd12);
    wire jt12_cen_uniform_6p67mhz_build_marker =
        MD_JT12_CEN_UNIFORM_6P67MHZ_BUILD && (v_count < 9'd12);
    wire jt12_ladder_effect_build_marker =
        MD_JT12_LADDER_EFFECT_BUILD && (v_count < 9'd12);
    wire jt12_force_ym2612_build_marker =
        MD_JT12_FORCE_YM2612_BUILD && (v_count < 9'd12);
    wire jt12_force_ym3438_build_marker =
        MD_JT12_FORCE_YM3438_BUILD && (v_count < 9'd12);
    wire jt12_force_ladder_on_build_marker =
        MD_JT12_FORCE_LADDER_ON_BUILD && (v_count < 9'd12);
    wire jt12_force_ladder_off_build_marker =
        MD_JT12_FORCE_LADDER_OFF_BUILD && (v_count < 9'd12);
    wire jt12_hifi_pcm_build_marker =
        MD_JT12_HIFI_PCM_BUILD && (v_count < 9'd12);
    wire fm_dc_block_build_marker =
        MD_AUDIO_FM_DC_BLOCK_BUILD && (v_count < 9'd12);
    wire pre_genmix_fm_lpf_build_marker =
        MD_AUDIO_PRE_GENMIX_FM_LPF_BUILD && (v_count < 9'd12);
    wire post_fm_lpf_gain_build_marker =
        MD_AUDIO_POST_FM_LPF_GAIN_BUILD && (v_count < 9'd12);
    wire genmix_output_gain_2x_build_marker =
        MD_AUDIO_GENMIX_OUTPUT_GAIN_2X_BUILD && (v_count < 9'd12);
    wire genmix_output_gain_4x_build_marker =
        MD_AUDIO_GENMIX_OUTPUT_GAIN_4X_BUILD && (v_count < 9'd12);
    wire genmix_output_gain_6x_build_marker =
        MD_AUDIO_GENMIX_OUTPUT_GAIN_6X_BUILD && (v_count < 9'd12);
    wire genmix_output_gain_8x_build_marker =
        MD_AUDIO_GENMIX_OUTPUT_GAIN_8X_BUILD && (v_count < 9'd12);
    wire lpf_test_build_marker = MD_AUDIO_LPF_TEST_BUILD && (v_count < 9'd12);
    wire mode5_debug_overlay_enable =
        LOADED_VGM_MODE && MODE5_DEBUG_OVERLAY_FORCED;
    wire [31:0] dac_stream_avg_cmd_cycles =
        (dac_stream_cmd_count == 32'd0) ? 32'd0 :
        (dac_stream_clk_cycles_total / dac_stream_cmd_count);
    wire [31:0] dac_stream_avg_overhead_cycles =
        (dac_stream_cmd_count == 32'd0) ? 32'd0 :
        (dac_stream_overhead_cycles_total / dac_stream_cmd_count);
    wire segapcm_debug_seen =
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
        1'b1 ||
`endif
        YM2151_SEGAPCM_OBSERVER_BUILD ||
        (segapcm_write_count != 32'd0) ||
        (segapcm_rom_block_count != 32'd0) ||
        (segapcm_rom_scan_block_count != 32'd0) ||
        (segapcm_rom_copy_byte_count != 32'd0) ||
        segapcm_rom_scan_busy ||
        segapcm_rom_scan_done ||
        (pcm_ram_write_skip_count != 32'd0);
    wire [15:0] segapcm_display_derived_remaining =
        (vgm_scan_payload_len_low_debug > vgm_scan_player_accept_count_debug) ?
        (vgm_scan_payload_len_low_debug - vgm_scan_player_accept_count_debug) :
        16'd0;

    function automatic [34:0] font5x7_bits(input logic [7:0] ch);
        begin
            unique case (ch)
                "0": font5x7_bits = 35'b01110_10001_10011_10101_11001_10001_01110;
                "1": font5x7_bits = 35'b00100_01100_00100_00100_00100_00100_01110;
                "2": font5x7_bits = 35'b01110_10001_00001_00010_00100_01000_11111;
                "3": font5x7_bits = 35'b11110_00001_00001_01110_00001_00001_11110;
                "4": font5x7_bits = 35'b00010_00110_01010_10010_11111_00010_00010;
                "5": font5x7_bits = 35'b11111_10000_11110_00001_00001_10001_01110;
                "6": font5x7_bits = 35'b00110_01000_10000_11110_10001_10001_01110;
                "7": font5x7_bits = 35'b11111_00001_00010_00100_01000_01000_01000;
                "8": font5x7_bits = 35'b01110_10001_10001_01110_10001_10001_01110;
                "9": font5x7_bits = 35'b01110_10001_10001_01111_00001_00010_01100;
                "A": font5x7_bits = 35'b01110_10001_10001_11111_10001_10001_10001;
                "B": font5x7_bits = 35'b11110_10001_10001_11110_10001_10001_11110;
                "C": font5x7_bits = 35'b01110_10001_10000_10000_10000_10001_01110;
                "D": font5x7_bits = 35'b11110_10001_10001_10001_10001_10001_11110;
                "E": font5x7_bits = 35'b11111_10000_10000_11110_10000_10000_11111;
                "F": font5x7_bits = 35'b11111_10000_10000_11110_10000_10000_10000;
                "H": font5x7_bits = 35'b10001_10001_10001_11111_10001_10001_10001;
                "I": font5x7_bits = 35'b01110_00100_00100_00100_00100_00100_01110;
                "K": font5x7_bits = 35'b10001_10010_10100_11000_10100_10010_10001;
                "L": font5x7_bits = 35'b10000_10000_10000_10000_10000_10000_11111;
                "M": font5x7_bits = 35'b10001_11011_10101_10101_10001_10001_10001;
                "N": font5x7_bits = 35'b10001_11001_10101_10011_10001_10001_10001;
                "O": font5x7_bits = 35'b01110_10001_10001_10001_10001_10001_01110;
                "P": font5x7_bits = 35'b11110_10001_10001_11110_10000_10000_10000;
                "Q": font5x7_bits = 35'b01110_10001_10001_10001_10101_10010_01101;
                "R": font5x7_bits = 35'b11110_10001_10001_11110_10100_10010_10001;
                "S": font5x7_bits = 35'b01111_10000_10000_01110_00001_00001_11110;
                "T": font5x7_bits = 35'b11111_00100_00100_00100_00100_00100_00100;
                "U": font5x7_bits = 35'b10001_10001_10001_10001_10001_10001_01110;
                "V": font5x7_bits = 35'b10001_10001_10001_10001_10001_01010_00100;
                "W": font5x7_bits = 35'b10001_10001_10001_10101_10101_10101_01010;
                "X": font5x7_bits = 35'b10001_10001_01010_00100_01010_10001_10001;
                "Y": font5x7_bits = 35'b10001_10001_01010_00100_00100_00100_00100;
                "Z": font5x7_bits = 35'b11111_00001_00010_00100_01000_10000_11111;
                default: font5x7_bits = 35'b00000_00000_00000_00000_00000_00000_00000;
            endcase
        end
    endfunction

    function automatic logic font5x7_pixel(
        input logic [7:0] ch,
        input logic [2:0] x,
        input logic [2:0] y
    );
        logic [34:0] bits;
        int idx;
        begin
            bits = font5x7_bits(ch);
            idx = 34 - ((y * 5) + x);
            font5x7_pixel = bits[idx];
        end
    endfunction

    function automatic [7:0] segapcm_debug_label_char(
        input logic [4:0] row,
        input logic [1:0] col
    );
        begin
            unique case (row)
                5'd0:  segapcm_debug_label_char = (col == 2'd0) ? "S" : (col == 2'd1) ? "K" : " ";
                5'd1: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "S" : (col == 2'd1) ? "C" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "L" : (col == 2'd1) ? "H" : " ";
`endif
                end
                5'd2: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "L" : (col == 2'd1) ? "P" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "L" : (col == 2'd1) ? "L" : " ";
`endif
                end
                5'd3: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "S" : (col == 2'd1) ? "V" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "Q" : (col == 2'd1) ? "H" : " ";
`endif
                end
                5'd4: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "P" : (col == 2'd1) ? "E" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "Q" : (col == 2'd1) ? "L" : " ";
`endif
                end
                5'd5: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "L" : (col == 2'd1) ? "L" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "L" : (col == 2'd1) ? "M" : " ";
`endif
                end
                5'd6: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "L" : (col == 2'd1) ? "H" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "S" : (col == 2'd1) ? "M" : " ";
`endif
                end
                5'd7: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "P" : (col == 2'd1) ? "S" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "B" : (col == 2'd1) ? "O" : " ";
`endif
                end
                5'd8: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "S" : (col == 2'd1) ? "V" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "M" : (col == 2'd1) ? "O" : " ";
`endif
                end
                5'd9:  segapcm_debug_label_char = (col == 2'd0) ? "P" : (col == 2'd1) ? "L" : " ";
                5'd10: segapcm_debug_label_char = (col == 2'd0) ? "D" : (col == 2'd1) ? "A" : " ";
                5'd11: segapcm_debug_label_char = (col == 2'd0) ? "M" : (col == 2'd1) ? "D" : " ";
                5'd12: segapcm_debug_label_char = (col == 2'd0) ? "A" : (col == 2'd1) ? "V" : " ";
                5'd13: segapcm_debug_label_char = (col == 2'd0) ? "I" : (col == 2'd1) ? "R" : " ";
                5'd14: segapcm_debug_label_char = (col == 2'd0) ? "C" : (col == 2'd1) ? "H" : " ";
                5'd15: segapcm_debug_label_char = (col == 2'd0) ? "C" : (col == 2'd1) ? "2" : " ";
                5'd16: segapcm_debug_label_char = (col == 2'd0) ? "C" : (col == 2'd1) ? "1" : " ";
                5'd17: segapcm_debug_label_char = (col == 2'd0) ? "C" : (col == 2'd1) ? "0" : " ";
                5'd18: segapcm_debug_label_char = (col == 2'd0) ? "A" : (col == 2'd1) ? "P" : " ";
                5'd19: segapcm_debug_label_char = (col == 2'd0) ? "O" : (col == 2'd1) ? "N" : " ";
                5'd20: segapcm_debug_label_char = (col == 2'd0) ? "D" : (col == 2'd1) ? "F" : " ";
                5'd21: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "S" : (col == 2'd1) ? "S" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "Q" : (col == 2'd1) ? "H" : " ";
`endif
                end
                5'd22: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "P" : (col == 2'd1) ? "E" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "Q" : (col == 2'd1) ? "L" : " ";
`endif
                end
                5'd23: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "P" : (col == 2'd1) ? "S" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "B" : (col == 2'd1) ? "O" : " ";
`endif
                end
                5'd24: segapcm_debug_label_char = (col == 2'd0) ? "S" : (col == 2'd1) ? "M" : " ";
                5'd25: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "S" : (col == 2'd1) ? "D" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "I" : (col == 2'd1) ? "R" : " ";
`endif
                end
                5'd26: segapcm_debug_label_char = (col == 2'd0) ? "P" : (col == 2'd1) ? "V" : " ";
                5'd27: segapcm_debug_label_char = (col == 2'd0) ? "F" : (col == 2'd1) ? "U" : " ";
                5'd28: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_label_char = (col == 2'd0) ? "S" : (col == 2'd1) ? "V" : " ";
`else
                    segapcm_debug_label_char = (col == 2'd0) ? "M" : (col == 2'd1) ? "O" : " ";
`endif
                end
                default: segapcm_debug_label_char = " ";
            endcase
        end
    endfunction

    function automatic [15:0] segapcm_debug_value(
        input logic [4:0] row
    );
        begin
            unique case (row)
                5'd0: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_value = 16'h5A5A;
`else
                    segapcm_debug_value = 16'hF519;
`endif
                end
                5'd1:  segapcm_debug_value = segapcm_core_rom_addr_raw_high;
                5'd2:  segapcm_debug_value = segapcm_core_rom_addr_raw_low;
                5'd3:  segapcm_debug_value = segapcm_core_rom_addr_mapped_high;
                5'd4:  segapcm_debug_value = segapcm_core_rom_addr_mapped_low;
                5'd5:  segapcm_debug_value = segapcm_core_rom_return_last01;
                5'd6: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_value = segapcm_core_rom_payload_len_high;
`else
                    segapcm_debug_value = segapcm_core_rom_return_last23;
`endif
                end
                5'd7:  segapcm_debug_value = segapcm_core_rom_addr_max_low;
                5'd8:  segapcm_debug_value = segapcm_core_rom_addr_max_high;
                5'd9:  segapcm_debug_value = segapcm_core_rom_payload_len_low;
                5'd10: segapcm_debug_value = segapcm_core_rom_return_data;
                5'd11: segapcm_debug_value = segapcm_core_rom_preload_data;
                5'd12: segapcm_debug_value = segapcm_core_rom_return_neutral_count;
                5'd13: segapcm_debug_value = segapcm_core_rom_core_ok_count;
                5'd14: segapcm_debug_value = segapcm_core_pcm_debug_bk;
                5'd15: segapcm_debug_value = {8'd0, segapcm_core_pcm_debug_cuh[15:8]};
                5'd16: segapcm_debug_value = {8'd0, segapcm_core_pcm_debug_cuh[7:0]};
                5'd17: segapcm_debug_value = {8'd0, segapcm_core_pcm_debug_cul[15:8]};
                5'd18: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_value = segapcm_core_known38686_d0_value;
`else
                    segapcm_debug_value = segapcm_core_known38686_d0_value;
`endif
                end
                5'd19: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_value = segapcm_core_known38686_d1_addr;
`else
                    segapcm_debug_value = segapcm_core_known38686_d1_addr;
`endif
                end
                5'd20: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_value = 16'h5A5A;
`elsif MEGAVGMDRIVE_SEGAPCM_START_INIT_TEST
                    segapcm_debug_value = 16'hF0CE;
`else
                    segapcm_debug_value = 16'd0;
`endif
                end
                5'd21: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_value = segapcm_core_known38686_d0_addr;
`else
                    segapcm_debug_value = segapcm_core_rom_addr_mapped_high;
`endif
                end
                5'd22: segapcm_debug_value = segapcm_core_rom_addr_mapped_low;
                5'd23: segapcm_debug_value = segapcm_core_rom_addr_max_low;
                5'd24: segapcm_debug_value = segapcm_core_rom_return_last23;
                5'd25: begin
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
                    segapcm_debug_value = segapcm_core_known38686_en_value;
`else
                    segapcm_debug_value = segapcm_core_rom_core_ok_count;
`endif
                end
                5'd26: segapcm_debug_value = segapcm_core_rom_fallback_count;
                5'd27: segapcm_debug_value = segapcm_core_rom_read_valid_count;
                5'd28: segapcm_debug_value = segapcm_core_rom_addr_max_high;
                default: segapcm_debug_value = 16'd0;
            endcase
        end
    endfunction

    function automatic [7:0] mode5_debug_label_char(
        input logic [4:0] row,
        input logic [1:0] col
    );
        begin
            if (segapcm_debug_seen) begin
                mode5_debug_label_char = segapcm_debug_label_char(row, col);
            end else begin
            unique case (row)
                5'd0:  mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "S" : (col == 2'd1) ? "I" : " ";
                5'd1:  mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "L" : (col == 2'd1) ? "B" : " ";
                5'd2:  mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "L" : (col == 2'd1) ? "D" : " ";
                5'd3:  mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "S" : (col == 2'd1) ? "R" : " ";
                5'd4:  mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "S" : (col == 2'd1) ? "T" : " ";
                5'd5:  mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "P" : (col == 2'd1) ? "R" : " ";
                5'd6:  mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "D" : (col == 2'd1) ? "U" : " ";
                5'd7:  mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "P" : (col == 2'd1) ? "E" : " ";
                5'd8:  mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "E" : (col == 2'd1) ? "R" : " ";
                5'd9:  mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "A" : (col == 2'd1) ? "M" : " ";
                5'd10: mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "P" : (col == 2'd1) ? "B" : " ";
                5'd11: mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "C" : (col == 2'd1) ? "P" : " ";
                5'd12: mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "L" : (col == 2'd1) ? "C" : " ";
                5'd13: mode5_debug_label_char = segapcm_debug_seen ? " " :
                    (col == 2'd0) ? "D" : (col == 2'd1) ? "P" : " ";
                5'd14: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "M" : (col == 2'd1) ? "K" : " ") :
                    ((col == 2'd0) ? "D" : (col == 2'd1) ? "C" : " ");
                5'd15: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "P" : (col == 2'd1) ? "A" : " ") :
                    ((col == 2'd0) ? "D" : (col == 2'd1) ? "S" : " ");
                5'd16: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "C" : (col == 2'd1) ? "A" : " ") :
                    ((col == 2'd0) ? "F" : (col == 2'd1) ? "S" : " ");
                5'd17: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "R" : (col == 2'd1) ? "Q" : " ") :
                    ((col == 2'd0) ? "W" : (col == 2'd1) ? "T" : " ");
                5'd18: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "R" : (col == 2'd1) ? "R" : " ") :
                    ((col == 2'd0) ? "C" : (col == 2'd1) ? "Y" : " ");
                5'd19: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "R" : (col == 2'd1) ? "V" : " ") :
                    ((col == 2'd0) ? "E" : (col == 2'd1) ? "C" : " ");
                5'd20: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "X" : (col == 2'd1) ? "0" : " ") :
                    ((col == 2'd0) ? "E" : (col == 2'd1) ? "P" : " ");
                5'd21: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "X" : (col == 2'd1) ? "1" : " ") :
                    ((col == 2'd0) ? "E" : (col == 2'd1) ? "X" : " ");
                5'd22: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "X" : (col == 2'd1) ? "2" : " ") :
                    ((col == 2'd0) ? "E" : (col == 2'd1) ? "S" : " ");
                5'd23: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "M" : (col == 2'd1) ? "M" : " ") :
                    ((col == 2'd0) ? "D" : (col == 2'd1) ? "C" : " ");
                5'd24: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "Q" : (col == 2'd1) ? "C" : " ") :
                    ((col == 2'd0) ? "A" : (col == 2'd1) ? "V" : " ");
                5'd25: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "O" : (col == 2'd1) ? "0" : " ") :
                    ((col == 2'd0) ? "O" : (col == 2'd1) ? "H" : " ");
                5'd26: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "O" : (col == 2'd1) ? "H" : " ") :
                    ((col == 2'd0) ? "W" : (col == 2'd1) ? "0" : " ");
                5'd27: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "B" : (col == 2'd1) ? "D" : " ") :
                    ((col == 2'd0) ? "M" : (col == 2'd1) ? "A" : " ");
                5'd28: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "A" : (col == 2'd1) ? "F" : " ") :
                    ((col == 2'd0) ? "R" : (col == 2'd1) ? "C" : " ");
                5'd29: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "H" : (col == 2'd1) ? "2" : " ") :
                    ((col == 2'd0) ? "D" : (col == 2'd1) ? "A" : " ");
                5'd30: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "A" : (col == 2'd1) ? "H" : " ") :
                    ((col == 2'd0) ? "R" : (col == 2'd1) ? "S" : " ");
                5'd31: mode5_debug_label_char =
                    segapcm_debug_seen ? ((col == 2'd0) ? "A" : (col == 2'd1) ? "S" : " ") :
                    " ";
                default: mode5_debug_label_char = " ";
            endcase
            end
        end
    endfunction

    function automatic [15:0] mode5_debug_value(
        input logic [4:0] row
    );
        begin
            if (segapcm_debug_seen) begin
                mode5_debug_value = segapcm_debug_value(row);
            end else begin
            unique case (row)
                5'd0:  mode5_debug_value = segapcm_debug_seen ? 16'd0 : mode5_playback_session_id[15:0];
                5'd1:  mode5_debug_value = segapcm_debug_seen ? 16'd0 : mode5_load_begin_count[15:0];
                5'd2:  mode5_debug_value = segapcm_debug_seen ? 16'd0 : mode5_load_done_edge_count[15:0];
                5'd3:  mode5_debug_value = segapcm_debug_seen ? 16'd0 : mode5_sound_reset_start_count[15:0];
                5'd4:  mode5_debug_value = segapcm_debug_seen ? 16'd0 : mode5_player_start_count[15:0];
                5'd5:  mode5_debug_value = segapcm_debug_seen ? 16'd0 : mode5_player_reset_count[15:0];
                5'd6:  mode5_debug_value = segapcm_debug_seen ? 16'd0 : mode5_duplicate_start_blocked_count[15:0];
                5'd7:  mode5_debug_value = segapcm_debug_seen ? 16'd0 : mode5_player_end_count[15:0];
                5'd8:  mode5_debug_value = segapcm_debug_seen ? 16'd0 : {8'd0, vgm_player_error_code};
                5'd9:  mode5_debug_value = segapcm_debug_seen ? 16'd0 : {15'd0, audio_muted};
                5'd10: mode5_debug_value = segapcm_debug_seen ? 16'd0 : {15'd0, player_busy};
                5'd11: mode5_debug_value = segapcm_debug_seen ? 16'd0 : vgm_current_pc_debug[15:0];
                5'd12: mode5_debug_value = segapcm_debug_seen ? 16'd0 : {8'd0, player_last_cmd_debug};
                5'd13: mode5_debug_value = segapcm_debug_seen ? 16'd0 : mode5_done_pc_debug[15:0];
                5'd14: mode5_debug_value =
                    segapcm_debug_seen ? 16'hF519 :
                    {8'd0, mode5_done_cmd_debug};
                5'd15: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_player_accept_count_debug :
                    mode5_done_session_id[15:0];
                5'd16: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_copy_accept_fire_count_debug :
                    vgm_load_size[15:0];
                5'd17: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_copy_read_req_count_debug :
                    vgm_wait_ticks_consumed_debug[15:0];
                5'd18: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_copy_read_accept_count_debug :
                    mode5_cycles_since_start[15:0];
                5'd19: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_copy_read_valid_count_debug :
                    {8'd0, vgm_player_error_code};
                5'd20: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_copy_request_state_debug :
                    vgm_error_pc_debug[15:0];
                5'd21: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_copy_state_lifetime_debug :
                    {8'd0, vgm_error_cmd_debug};
                5'd22: mode5_debug_value =
                    segapcm_debug_seen ? {
                        8'd0,
                        vgm_scan_copy_phase_debug[0],
                        vgm_scan_copy_phase_debug[1],
                        mode5_read_mux_debug[4],
                        vgm_scan_copy_phase_debug[3],
                        vgm_scan_copy_phase_debug[2],
                        (vgm_scan_copy_phase_debug[4] &
                         vgm_scan_copy_phase_debug[5]),
                        vgm_scan_copy_phase_debug[5],
                        vgm_scan_copy_phase_debug[4]
                    } :
                    vgm_error_session_id[15:0];
                5'd23: mode5_debug_value =
                    segapcm_debug_seen ? {
                        vgm_scan_copy_mem_req_cycle_count_debug[7:0],
                        vgm_scan_copy_mem_req_ready_cycle_count_debug[7:0]
                    } :
                    dac_stream_cmd_count[15:0];
                5'd24: mode5_debug_value =
                    segapcm_debug_seen ? {
                        8'hC0,
                        7'd0,
                        (vgm_scan_copy_read_req_count_debug >
                         vgm_scan_copy_read_accept_count_debug)
                    } :
                    dac_stream_avg_cmd_cycles[15:0];
                5'd25: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_payload_o0_debug :
                    dac_stream_avg_overhead_cycles[15:0];
                5'd26: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_payload_oh_debug :
                    count_wait0_dac_stream_cmd[15:0];
                5'd27: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_payload_bd_debug :
                    vgm_mem_rd_addr_debug[15:0];
                5'd28: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_payload_af_debug :
                    mode5_repeat_restart_count[15:0];
                5'd29: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_payload_oh2_debug :
                    {15'd0, mode5_done_armed_debug};
                5'd30: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_payload_ah_debug :
                    mode5_repeat_session_id[15:0];
                5'd31: mode5_debug_value =
                    segapcm_debug_seen ? vgm_scan_payload_as_debug :
                    16'd0;
                default: mode5_debug_value = 16'd0;
            endcase
            end
        end
    endfunction

    function automatic [7:0] hex_char(input logic [3:0] nibble);
        begin
            hex_char = (nibble < 4'd10) ?
                ("0" + {4'd0, nibble}) :
                ("A" + {4'd0, nibble - 4'd10});
        end
    endfunction

    function automatic [7:0] mode5_debug_char(
        input logic [4:0] row,
        input logic [3:0] col
    );
        logic [15:0] value;
        begin
            value = mode5_debug_value(row);
            unique case (col)
                4'd0: mode5_debug_char = mode5_debug_label_char(row, 2'd0);
                4'd1: mode5_debug_char = mode5_debug_label_char(row, 2'd1);
                4'd2: mode5_debug_char = " ";
                4'd3: mode5_debug_char = hex_char(value[15:12]);
                4'd4: mode5_debug_char = hex_char(value[11:8]);
                4'd5: mode5_debug_char = hex_char(value[7:4]);
                4'd6: mode5_debug_char = hex_char(value[3:0]);
                default: mode5_debug_char = " ";
            endcase
        end
    endfunction

    wire [8:0] mode5_dbg_x = h_count - 9'd8;
    wire [8:0] mode5_dbg_y = v_count - 9'd8;
    wire [4:0] mode5_dbg_row = mode5_dbg_y[7:3];
    wire [3:0] mode5_dbg_col = mode5_dbg_x[6:3];
    wire [2:0] mode5_dbg_char_x = mode5_dbg_x[2:0];
    wire [2:0] mode5_dbg_char_y = mode5_dbg_y[2:0];
    wire mode5_dbg_back =
        mode5_debug_overlay_enable &&
        (h_count >= 9'd8) && (h_count < 9'd64) &&
        (v_count >= 9'd8) && (v_count < 9'd256);
    wire mode5_dbg_region =
        mode5_dbg_back &&
        (mode5_dbg_row <= 5'd31) &&
        (mode5_dbg_col <= 4'd6) &&
        (mode5_dbg_char_x < 3'd5) &&
        (mode5_dbg_char_y < 3'd7);
    wire mode5_debug_pixel =
        mode5_dbg_region &&
        font5x7_pixel(mode5_debug_char(mode5_dbg_row,
                                       mode5_dbg_col),
                      mode5_dbg_char_x,
                      mode5_dbg_char_y);

    wire hsync = ~((h_count >= 9'd336) && (h_count < 9'd368));
    wire vsync = ~((v_count >= 9'd244) && (v_count < 9'd248));

    // State colors:
    // idle/running background : green
    // internal/retry reset    : yellow
    // init wait / start wait  : magenta
    // region mode 2 playing   : purple
    // region mode 3 playing   : orange
    // region mode 4 playing   : lime
    // region mode 5 loaded    : teal/blue
    // VGM file downloading    : blue
    // VGM file loaded         : cyan
    // VGM file load error     : red
    // audio gate open         : white
    // audio_seen_latched      : cyan
    // player_done latched     : green
    // player_busy             : red
    //
    // Color priority is reset > done > waiting > mode/gate > sample seen.
    // AUDIO debug build markers: MD_AUDIO_FORCE_MUTE_TEST paints yellow,
    // MD_YM_WRITE_SLOW_TEST paints a white/green stripe pattern,
    // YM LFO-off paints black/yellow stripes, PMS/AMS mask paints cyan/yellow
    // stripes, ch3-normal paints red/blue stripes.
    // MD_AUDIO_SYSOUT_ATTENUATE_24DB paints a red/cyan stripe pattern,
    // MD_AUDIO_SYSOUT_ATTENUATE_6DB paints yellow/magenta stripes,
    // sysout force tone paints white/black/red stripes,
    // sysout gain 2x paints green/white stripes, sysout gain 4x paints
    // orange/blue stripes,
    // MD_AUDIO_FINAL_ATTENUATE_6DB paints magenta, output shift=1 paints
    // cyan/white stripes, output shift=0 paints red/green stripes. Upstream A/B markers:
    // FM force mute white/black stripes, FM-only red, PSG-only blue, FM channel
    // solo uses ch1 red / ch2 green / ch3 blue / ch4 yellow / ch5 magenta /
    // ch6 cyan, premix FM orange stripes, fm_adjust bypass purple stripes, low-gain green/blue
    // stripes, saturate red/yellow stripes, premix PSG cyan stripes, raw JT12
    // blue/white stripes, raw sample-latched JT12 blue/yellow stripes,
    // normal sample-latched blue/green stripes, JT12 NTSC cen green/white
    // stripes, JT12 every-clk cen red/white stripes, JT12 uniform 10 MHz
    // yellow/blue stripes, JT12 uniform 6.67 MHz amber/green stripes,
    // JT12 forced YM2612 orange/white stripes, forced YM3438 cyan/blue
    // stripes, ladder-on magenta/white stripes, ladder-off green/black
    // stripes, hifi-PCM white/cyan stripes, FM DC-block yellow/green stripes,
    // pre-genmix FM LPF purple/green stripes, post-FM-LPF gain white/purple
    // stripes, genmix-output gain 2x green/purple stripes, genmix-output gain
    // 4x red/white/blue stripes, 6x amber/cyan stripes,
    // 8x green/red/black stripes, JT12 ladder-effect magenta/cyan stripes, LPF green.
    wire [7:0] red =
        mode5_debug_pixel ? 8'hff :
        mode5_dbg_back ? 8'h00 :
        stage_meter_pixel ? stage_meter_rgb[23:16] :
        md_avg_meter_pixel ? md_avg_meter_rgb[23:16] :
        md_meter_pixel ? md_meter_rgb[23:16] :
        emu_meter_pixel ? emu_meter_rgb[23:16] :
        emu_avg_meter_pixel ? emu_avg_meter_rgb[23:16] :
        force_mute_build_marker ? 8'hff :
        ym_write_slow_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        ym_force_lfo_off_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        ym_mask_pms_ams_build_marker ? 8'hff :
        ym_ch3_normal_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        sysout_attenuate_24db_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        sysout_attenuate_build_marker ? 8'hff :
        sysout_force_tone_build_marker ? (h_count[5] ? 8'hff : (h_count[4] ? 8'h00 : 8'hff)) :
        sysout_gain_4x_sat_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        sysout_gain_2x_sat_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        attenuate_6db_build_marker ? 8'hff :
        output_shift_1_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        output_shift_0_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        fm_force_mute_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        fm_only_build_marker ? 8'hff :
        psg_only_build_marker ? 8'h00 :
        fm_ch_solo_build_marker ?
            ((MD_AUDIO_FM_CH1_ONLY_BUILD || MD_AUDIO_FM_CH4_ONLY_BUILD || MD_AUDIO_FM_CH5_ONLY_BUILD) ? 8'hff : 8'h00) :
        premix_fm_attenuate_build_marker ? 8'hff :
        fm_adjust_bypass_build_marker ? (h_count[4] ? 8'hc0 : 8'h40) :
        fm_adjust_low_gain_build_marker ? 8'h00 :
        fm_adjust_saturate_build_marker ? 8'hff :
        premix_psg_attenuate_build_marker ? (h_count[4] ? 8'h00 : 8'h00) :
        jt12_cen_uniform_10mhz_build_marker ? 8'hff :
        jt12_cen_uniform_6p67mhz_build_marker ? (h_count[4] ? 8'hff : 8'h80) :
        jt12_cen_ntsc_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        jt12_cen_every_clk_build_marker ? 8'hff :
        jt12_force_ym2612_build_marker ? 8'hff :
        jt12_force_ym3438_build_marker ? 8'h00 :
        jt12_force_ladder_on_build_marker ? (h_count[4] ? 8'hff : 8'h80) :
        jt12_force_ladder_off_build_marker ? 8'h00 :
        jt12_hifi_pcm_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        fm_dc_block_build_marker ? (h_count[4] ? 8'hff : 8'h40) :
        pre_genmix_fm_lpf_build_marker ? (h_count[4] ? 8'h90 : 8'h00) :
        post_fm_lpf_gain_build_marker ? (h_count[4] ? 8'hff : 8'h80) :
        genmix_output_gain_8x_build_marker ? (h_count[5] ? 8'h00 : (h_count[4] ? 8'hff : 8'h00)) :
        genmix_output_gain_6x_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        genmix_output_gain_4x_build_marker ? (h_count[5] ? 8'hff : (h_count[4] ? 8'h00 : 8'hff)) :
        genmix_output_gain_2x_build_marker ? (h_count[4] ? 8'h20 : 8'h90) :
        jt12_ladder_effect_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        normal_sample_latch_build_marker ? 8'h00 :
        raw_jt12_sample_latch_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        raw_jt12_fm_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        lpf_test_build_marker ? (h_count[4] ? 8'h00 : 8'h00) :
        startup_reset_active ? 8'hff :
        mode5_sound_reset_active ? 8'hff :
        mode5_player_start_pulse_debug ? 8'hff :
        (vgm_load_error || vgm_load_overflow || vgm_player_error) ? 8'hff :
        (LOADED_VGM_MODE && vgm_header_valid && player_busy) ? 8'h00 :
        vgm_load_busy     ? 8'h00 :
        vgm_load_done     ? 8'h00 :
        done_latched       ? 8'h00 :
        startup_waiting    ? 8'hff :
        (audio_gate_open && FIXED_TIMING_CAL_MODE)   ? 8'h80 :
        (audio_gate_open && FIXED_REAL_PHRASE_MODE)  ? 8'hff :
        (audio_gate_open && FIXED_REAL_SNIPPET_MODE) ? 8'hc0 :
        audio_gate_open    ? 8'hff :
        audio_seen_latched ? 8'h00 :
        player_busy        ? 8'hd0 :
                             8'h00;

    wire [7:0] green =
        mode5_debug_pixel ? 8'hff :
        mode5_dbg_back ? 8'h00 :
        stage_meter_pixel ? stage_meter_rgb[15:8] :
        md_avg_meter_pixel ? md_avg_meter_rgb[15:8] :
        md_meter_pixel ? md_meter_rgb[15:8] :
        emu_meter_pixel ? emu_meter_rgb[15:8] :
        emu_avg_meter_pixel ? emu_avg_meter_rgb[15:8] :
        force_mute_build_marker ? 8'hff :
        ym_write_slow_build_marker ? 8'hff :
        ym_force_lfo_off_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        ym_mask_pms_ams_build_marker ? 8'hff :
        ym_ch3_normal_build_marker ? 8'h00 :
        sysout_attenuate_24db_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        sysout_attenuate_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        sysout_force_tone_build_marker ? (h_count[5] ? 8'hff : 8'h00) :
        sysout_gain_4x_sat_build_marker ? (h_count[4] ? 8'h80 : 8'h00) :
        sysout_gain_2x_sat_build_marker ? 8'hff :
        attenuate_6db_build_marker ? 8'h00 :
        output_shift_1_build_marker ? 8'hff :
        output_shift_0_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        fm_force_mute_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        fm_only_build_marker ? 8'h00 :
        psg_only_build_marker ? 8'h00 :
        fm_ch_solo_build_marker ?
            ((MD_AUDIO_FM_CH2_ONLY_BUILD || MD_AUDIO_FM_CH4_ONLY_BUILD || MD_AUDIO_FM_CH6_ONLY_BUILD) ? 8'hff : 8'h00) :
        premix_fm_attenuate_build_marker ? (h_count[4] ? 8'h80 : 8'h30) :
        fm_adjust_bypass_build_marker ? 8'h00 :
        fm_adjust_low_gain_build_marker ? (h_count[4] ? 8'hff : 8'h40) :
        fm_adjust_saturate_build_marker ? (h_count[4] ? 8'hff : 8'h60) :
        premix_psg_attenuate_build_marker ? (h_count[4] ? 8'hff : 8'h40) :
        jt12_cen_uniform_10mhz_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        jt12_cen_uniform_6p67mhz_build_marker ? (h_count[4] ? 8'hc0 : 8'hff) :
        jt12_cen_ntsc_build_marker ? 8'hff :
        jt12_cen_every_clk_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        jt12_force_ym2612_build_marker ? (h_count[4] ? 8'h80 : 8'hff) :
        jt12_force_ym3438_build_marker ? (h_count[4] ? 8'hff : 8'h80) :
        jt12_force_ladder_on_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        jt12_force_ladder_off_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        jt12_hifi_pcm_build_marker ? 8'hff :
        fm_dc_block_build_marker ? (h_count[4] ? 8'hff : 8'h40) :
        pre_genmix_fm_lpf_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        post_fm_lpf_gain_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        genmix_output_gain_8x_build_marker ? (h_count[5] ? 8'hff : 8'h00) :
        genmix_output_gain_6x_build_marker ? (h_count[4] ? 8'hc0 : 8'hff) :
        genmix_output_gain_4x_build_marker ? (h_count[5] ? 8'hff : 8'h00) :
        genmix_output_gain_2x_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        jt12_ladder_effect_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        normal_sample_latch_build_marker ? (h_count[4] ? 8'hff : 8'h40) :
        raw_jt12_sample_latch_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        raw_jt12_fm_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        lpf_test_build_marker ? (h_count[4] ? 8'hff : 8'h60) :
        startup_reset_active ? 8'hff :
        mode5_sound_reset_active ? 8'hff :
        mode5_player_start_pulse_debug ? 8'hff :
        (vgm_load_error || vgm_load_overflow || vgm_player_error) ? 8'h00 :
        (LOADED_VGM_MODE && vgm_header_valid && player_busy) ? 8'hc0 :
        vgm_load_busy     ? 8'h40 :
        vgm_load_done     ? 8'hff :
        done_latched       ? 8'hd0 :
        startup_waiting    ? 8'h00 :
        (audio_gate_open && FIXED_TIMING_CAL_MODE)   ? 8'hff :
        (audio_gate_open && FIXED_REAL_PHRASE_MODE)  ? 8'h80 :
        (audio_gate_open && FIXED_REAL_SNIPPET_MODE) ? 8'h00 :
        audio_gate_open    ? 8'hff :
        audio_seen_latched ? 8'hff :
        player_busy        ? 8'h00 :
                             8'hb0;

    wire [7:0] blue =
        mode5_debug_pixel ? 8'hff :
        mode5_dbg_back ? 8'h00 :
        stage_meter_pixel ? stage_meter_rgb[7:0] :
        md_avg_meter_pixel ? md_avg_meter_rgb[7:0] :
        md_meter_pixel ? md_meter_rgb[7:0] :
        emu_meter_pixel ? emu_meter_rgb[7:0] :
        emu_avg_meter_pixel ? emu_avg_meter_rgb[7:0] :
        force_mute_build_marker ? 8'h00 :
        ym_write_slow_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        ym_force_lfo_off_build_marker ? 8'h00 :
        ym_mask_pms_ams_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        ym_ch3_normal_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        sysout_attenuate_24db_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        sysout_attenuate_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        sysout_force_tone_build_marker ? (h_count[5] ? 8'hff : 8'h00) :
        sysout_gain_4x_sat_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        sysout_gain_2x_sat_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        attenuate_6db_build_marker ? 8'hff :
        output_shift_1_build_marker ? 8'hff :
        output_shift_0_build_marker ? 8'h00 :
        fm_force_mute_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        fm_only_build_marker ? 8'h00 :
        psg_only_build_marker ? 8'hff :
        fm_ch_solo_build_marker ?
            ((MD_AUDIO_FM_CH3_ONLY_BUILD || MD_AUDIO_FM_CH5_ONLY_BUILD || MD_AUDIO_FM_CH6_ONLY_BUILD) ? 8'hff : 8'h00) :
        premix_fm_attenuate_build_marker ? 8'h00 :
        fm_adjust_bypass_build_marker ? (h_count[4] ? 8'hff : 8'h80) :
        fm_adjust_low_gain_build_marker ? (h_count[4] ? 8'hff : 8'h60) :
        fm_adjust_saturate_build_marker ? 8'h00 :
        premix_psg_attenuate_build_marker ? (h_count[4] ? 8'hff : 8'h80) :
        jt12_cen_uniform_10mhz_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        jt12_cen_uniform_6p67mhz_build_marker ? 8'h00 :
        jt12_cen_ntsc_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        jt12_cen_every_clk_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        jt12_force_ym2612_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        jt12_force_ym3438_build_marker ? 8'hff :
        jt12_force_ladder_on_build_marker ? (h_count[4] ? 8'hff : 8'h00) :
        jt12_force_ladder_off_build_marker ? 8'h00 :
        jt12_hifi_pcm_build_marker ? (h_count[4] ? 8'hff : 8'h80) :
        fm_dc_block_build_marker ? 8'h00 :
        pre_genmix_fm_lpf_build_marker ? (h_count[4] ? 8'hff : 8'h40) :
        post_fm_lpf_gain_build_marker ? 8'hff :
        genmix_output_gain_8x_build_marker ? 8'h00 :
        genmix_output_gain_6x_build_marker ? (h_count[4] ? 8'h00 : 8'hff) :
        genmix_output_gain_4x_build_marker ? (h_count[5] ? 8'hff : (h_count[4] ? 8'hff : 8'h00)) :
        genmix_output_gain_2x_build_marker ? (h_count[4] ? 8'h40 : 8'hff) :
        jt12_ladder_effect_build_marker ? 8'hff :
        normal_sample_latch_build_marker ? (h_count[4] ? 8'hff : 8'h80) :
        raw_jt12_sample_latch_build_marker ? 8'hff :
        raw_jt12_fm_build_marker ? 8'hff :
        lpf_test_build_marker ? 8'h00 :
        startup_reset_active ? 8'h00 :
        mode5_sound_reset_active ? 8'h00 :
        mode5_player_start_pulse_debug ? 8'hff :
        (vgm_load_error || vgm_load_overflow || vgm_player_error) ? 8'h00 :
        (LOADED_VGM_MODE && vgm_header_valid && player_busy) ? 8'hff :
        vgm_load_busy     ? 8'hff :
        vgm_load_done     ? 8'hff :
        done_latched       ? 8'h00 :
        startup_waiting    ? 8'hff :
        (audio_gate_open && FIXED_TIMING_CAL_MODE)   ? 8'h00 :
        (audio_gate_open && FIXED_REAL_PHRASE_MODE)  ? 8'h00 :
        (audio_gate_open && FIXED_REAL_SNIPPET_MODE) ? 8'hff :
        audio_gate_open    ? 8'hff :
        audio_seen_latched ? 8'hff :
        player_busy        ? 8'h00 :
                             8'h40;

    assign CLK_VIDEO = clk_sys;
    assign CE_PIXEL = ce_pix;
    assign VGA_DE = active;
    assign VGA_HS = hsync;
    assign VGA_VS = vsync;
`ifdef MISTER_VGM_DEBUG_VIDEO_ENABLE
    wire [7:0] video_red   = red;
    wire [7:0] video_green = green;
    wire [7:0] video_blue  = blue;
`else
    // Keep the normal player screen quiet; the OSD is overlaid later in sys_top.
    // MODE5_DEBUG_OVERLAY_ALWAYS_ON is a special debug build escape hatch that
    // lets the text overlay reach video without restoring public OSD controls.
    wire [7:0] video_red   = mode5_debug_pixel ? 8'hff :
                             mode5_dbg_back ? 8'h00 : 8'h00;
    wire [7:0] video_green = mode5_debug_pixel ? 8'hff :
                             mode5_dbg_back ? 8'h00 : 8'h08;
    wire [7:0] video_blue  = mode5_debug_pixel ? 8'hff :
                             mode5_dbg_back ? 8'h00 : 8'h18;
`endif
    assign VGA_R = active ? video_red : 8'd0;
    assign VGA_G = active ? video_green : 8'd0;
    assign VGA_B = active ? video_blue : 8'd0;

    reg [26:0] act_cnt;
    always @(posedge clk_sys) begin
        act_cnt <= reset ? 27'd0 : act_cnt + 27'd1;
    end

    assign LED_USER = player_busy | done_latched | audio_seen_latched | act_cnt[25];

    wire unused_inputs = ^{
        forced_scandoubler,
        video_rotated,
        gamma_bus,
        vgm_load_overflow,
        vgm_load_size,
        vgm_load_magic,
        vgm_data_start_debug,
        vgm_current_pc_debug,
        vgm_loop_pc_debug,
        vgm_loop_valid_debug,
        vgm_loop_taken_debug,
        vgm_end_command_seen,
        vgm_restarted_from_data_start,
        vgm_pcm_oob,
        vgm_pcm_oob_count,
        vgm_wait_ticks_consumed_debug,
        dac_stream_wait_samples_total,
        max_dac_stream_cmd_cycles,
        count_wait0_overhead_nonzero,
        segapcm_last_addr,
        segapcm_last_data,
        data_block_count,
        last_data_block_type,
        last_data_block_size_low,
        segapcm_last_rom_size,
        segapcm_last_rom_start,
        pcm_ram_write_skip_count,
        segapcm_rom_scan_total_size,
        segapcm_rom_scan_byte_count,
        mode5_repeat_restart_count,
        mode5_done_armed_debug,
        mode5_repeat_session_id,
        mode5_done_session_id,
        mode5_cycles_since_start,
        mode5_done_pc_debug,
        mode5_done_cmd_debug,
        vgm_unsupported_opcode,
        vgm_unsupported_pc,
        vgm_player_error_code,
        MD_AUDIO_ATTENUATE_6DB_BUILD,
        MD_AUDIO_OUTPUT_SHIFT_0_BUILD,
        MD_AUDIO_OUTPUT_SHIFT_1_BUILD,
        MD_AUDIO_OUTPUT_SHIFT,
        MODE5_REPEAT_ENABLE_BUILD,
        MD_YM_WRITE_SLOW_BUILD,
        MD_YM_FORCE_LFO_OFF_BUILD,
        MD_YM_MASK_PMS_AMS_BUILD,
        MD_YM_CH3_NORMAL_BUILD,
        MD_AUDIO_FORCE_MUTE_BUILD,
        MD_AUDIO_SYSOUT_ATTENUATE_BUILD,
        MD_AUDIO_SYSOUT_ATTENUATE_24DB_BUILD,
        MD_AUDIO_SYSOUT_FORCE_TONE_BUILD,
        MD_AUDIO_SYSOUT_GAIN_2X_SAT_BUILD,
        MD_AUDIO_SYSOUT_GAIN_4X_SAT_BUILD,
        MD_AUDIO_FM_ONLY_BUILD,
        MD_AUDIO_FM_FORCE_MUTE_BUILD,
        MD_AUDIO_PSG_ONLY_BUILD,
        MD_AUDIO_PREMIX_ATTENUATE_FM_BUILD,
        MD_AUDIO_FM_ADJUST_BYPASS_BUILD,
        MD_AUDIO_FM_ADJUST_LOW_GAIN_BUILD,
        MD_AUDIO_FM_ADJUST_SATURATE_BUILD,
        MD_AUDIO_PREMIX_ATTENUATE_PSG_BUILD,
        MD_AUDIO_RAW_JT12_FM_BUILD,
        MD_AUDIO_RAW_JT12_SAMPLE_LATCH_BUILD,
        MD_AUDIO_NORMAL_SAMPLE_LATCH_BUILD,
        MD_JT12_CEN_NTSC_BUILD,
        MD_JT12_CEN_EVERY_CLK_BUILD,
        MD_JT12_CEN_UNIFORM_10MHZ_BUILD,
        MD_JT12_CEN_UNIFORM_6P67MHZ_BUILD,
        MD_JT12_LADDER_EFFECT_BUILD,
        MD_JT12_FORCE_YM2612_BUILD,
        MD_JT12_FORCE_YM3438_BUILD,
        MD_JT12_FORCE_LADDER_ON_BUILD,
        MD_JT12_FORCE_LADDER_OFF_BUILD,
        MD_JT12_HIFI_PCM_BUILD,
        MD_AUDIO_FM_DC_BLOCK_BUILD,
        MD_AUDIO_PRE_GENMIX_FM_LPF_BUILD,
        MD_AUDIO_POST_FM_LPF_GAIN_BUILD,
        MD_AUDIO_GENMIX_OUTPUT_GAIN_2X_BUILD,
        MD_AUDIO_GENMIX_OUTPUT_GAIN_4X_BUILD,
        MD_AUDIO_GENMIX_OUTPUT_GAIN_6X_BUILD,
        MD_AUDIO_GENMIX_OUTPUT_GAIN_8X_BUILD,
        MD_AUDIO_LPF_TEST_BUILD,
        debug_md_sound_module_audio_l,
        debug_md_sound_module_audio_r,
        debug_emu_audio_l,
        debug_emu_audio_r,
        fm_raw_abs_peak,
        fm_adjust_abs_peak,
        fm_lpf_abs_peak,
        genmix_abs_peak,
        md_final_audio_abs_peak,
        md_audio_l_abs_peak,
        md_audio_r_abs_peak,
        emu_audio_l_abs_peak,
        emu_audio_r_abs_peak,
        md_audio_l_at_rail,
        md_audio_r_at_rail,
        md_audio_l_rail_count,
        md_audio_r_rail_count,
        emu_audio_l_rail_count,
        emu_audio_r_rail_count,
        fm_adjust_clip_count_l,
        fm_adjust_clip_count_r,
        genmix_wrap_count_l,
        genmix_wrap_count_r,
        ym_write_requested_count,
        ym_write_accepted_count,
        ym_write_dropped_or_busy_count,
        ym_port0_count,
        ym_port1_count,
        last_ym_port,
        last_ym_addr,
        last_ym_data,
        jt12_cen_interval_1_count,
        jt12_cen_interval_2_count,
        jt12_cen_interval_3_count,
        jt12_cen_interval_4_count,
        jt12_cen_interval_ge5_count,
        jt12_cen_interval_min,
        jt12_cen_interval_max,
        jt12_cen_interval_last,
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

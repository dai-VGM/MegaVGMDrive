// Minimal MiSTer-facing emu wrapper for the fixed-region MD sound test.
//
// This is intentionally a small bring-up wrapper:
// - no SD card access
// - no OSD menu
// - no HPS-side VGM loading
// - fixed region auto-plays once after reset through mister_vgm_md_top
//
// A real MiSTer build should instantiate this module from the framework
// sys_top. The exact sys_top port list can vary by template version, so this
// wrapper exposes the common MiSTer ports used by current core templates and
// ties unused interfaces to harmless idle values.

module emu #(
    parameter CONF_STR = {
        "VGM_MD;;",
        "O1,Reset,No,Yes;",
        "T0,Reset;"
    }
) (
    // Master input clock and framework reset.
    input         CLK_50M,
    input         RESET,

    // HPS bus is not used yet. It is kept here so a future hps_io instance can
    // be added without changing the external emu shape.
    inout  [48:0] HPS_BUS,

    // Minimal video outputs. The first hardware test is audio-only, but MiSTer
    // still expects stable video-style signals.
    output        CLK_VIDEO,
    output logic  CE_PIXEL,
    output [12:0] VIDEO_ARX,
    output [12:0] VIDEO_ARY,
    output  [7:0] VGA_R,
    output  [7:0] VGA_G,
    output  [7:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,
    output        VGA_F1,
    output  [1:0] VGA_SL,
    output        VGA_SCALER,
    input  [11:0] HDMI_WIDTH,
    input  [11:0] HDMI_HEIGHT,
    output        HDMI_FREEZE,

    // MiSTer audio path. md_sound_module already produces signed 16-bit PCM.
    input         CLK_AUDIO,
    output signed [15:0] AUDIO_L,
    output signed [15:0] AUDIO_R,
    output        AUDIO_S,
    output  [1:0] AUDIO_MIX,

    // Status/debug outputs.
    output        LED_USER,
    output  [1:0] LED_POWER,
    output  [1:0] LED_DISK,
    output  [1:0] BUTTONS,

    // Unused external interfaces for this first audio-only bring-up.
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

    // First bring-up: run the MD sound logic directly from CLK_50M.
    // TODO: replace this with a template PLL named "pll" once the MiSTer
    // sys_top/qsf/sdc skeleton is copied in. md_sound_module has so far been
    // validated in simulation with this style of single system clock.
    wire clk_sys = CLK_50M;

    logic reset_sync_1;
    logic reset_sync_2;

    always_ff @(posedge clk_sys) begin
        reset_sync_1 <= RESET;
        reset_sync_2 <= reset_sync_1;
    end

    wire reset_n = !reset_sync_2;

    wire signed [15:0] md_audio_l;
    wire signed [15:0] md_audio_r;
    wire               audio_sample_valid;
    wire               player_busy;
    wire               player_done;
    wire         [9:0] player_pc_debug;
    wire         [7:0] player_last_cmd_debug;

    mister_vgm_md_top md_sound (
        .clk                   (clk_sys),
        .reset_n               (reset_n),
        .audio_l               (md_audio_l),
        .audio_r               (md_audio_r),
        .audio_sample_valid    (audio_sample_valid),
        .player_busy           (player_busy),
        .player_done           (player_done),
        .player_pc_debug       (player_pc_debug),
        .player_last_cmd_debug (player_last_cmd_debug)
    );

    assign AUDIO_L   = md_audio_l;
    assign AUDIO_R   = md_audio_r;
    assign AUDIO_S   = 1'b1;   // signed samples
    assign AUDIO_MIX = 2'b00;  // keep stereo, no forced mono mix

    // Tiny blank 640x480-ish video generator. CLK_VIDEO is 50 MHz and
    // CE_PIXEL pulses every other clock, giving a 25 MHz pixel cadence.
    assign CLK_VIDEO = CLK_50M;

    logic        pixel_phase;
    logic [9:0]  h_count;
    logic [9:0]  v_count;

    always_ff @(posedge CLK_VIDEO) begin
        if (RESET) begin
            pixel_phase <= 1'b0;
            CE_PIXEL    <= 1'b0;
            h_count     <= 10'd0;
            v_count     <= 10'd0;
        end else begin
            pixel_phase <= !pixel_phase;
            CE_PIXEL    <= !pixel_phase;

            if (!pixel_phase) begin
                if (h_count == 10'd799) begin
                    h_count <= 10'd0;
                    if (v_count == 10'd524) begin
                        v_count <= 10'd0;
                    end else begin
                        v_count <= v_count + 10'd1;
                    end
                end else begin
                    h_count <= h_count + 10'd1;
                end
            end
        end
    end

    wire video_active = (h_count < 10'd640) && (v_count < 10'd480);

    assign VGA_DE = video_active;
    assign VGA_HS = ~((h_count >= 10'd656) && (h_count < 10'd752));
    assign VGA_VS = ~((v_count >= 10'd490) && (v_count < 10'd492));
    assign VGA_R  = video_active ? 8'h08 : 8'h00;
    assign VGA_G  = video_active ? 8'h10 : 8'h00;
    assign VGA_B  = video_active ? 8'h18 : 8'h00;
    assign VGA_F1 = 1'b0;
    assign VGA_SL = 2'b00;
    assign VGA_SCALER = 1'b0;
    assign VIDEO_ARX = 13'd4;
    assign VIDEO_ARY = 13'd3;
    assign HDMI_FREEZE = 1'b0;

    // Debug/status: blink-style outputs are intentionally simple for the first
    // bench bring-up. player_busy shows activity, player_done shows completion.
    assign LED_USER  = player_busy || player_done;
    assign LED_POWER = 2'b00;
    assign LED_DISK  = {1'b0, audio_sample_valid};
    assign BUTTONS   = 2'b00;

    // Idle unused buses.
    assign HPS_BUS = {49{1'bZ}};
    assign ADC_BUS = 4'bZZZZ;
    assign SD_SCK  = 1'b0;
    assign SD_MOSI = 1'b0;
    assign SD_CS   = 1'b1;

    assign DDRAM_CLK      = clk_sys;
    assign DDRAM_BURSTCNT = 8'd0;
    assign DDRAM_ADDR     = 29'd0;
    assign DDRAM_RD       = 1'b0;
    assign DDRAM_DIN      = 64'd0;
    assign DDRAM_BE       = 8'd0;
    assign DDRAM_WE       = 1'b0;

    assign SDRAM_CLK  = clk_sys;
    assign SDRAM_CKE  = 1'b0;
    assign SDRAM_A    = 13'd0;
    assign SDRAM_BA   = 2'd0;
    assign SDRAM_DQ   = 16'hZZZZ;
    assign SDRAM_DQML = 1'b1;
    assign SDRAM_DQMH = 1'b1;
    assign SDRAM_nCS  = 1'b1;
    assign SDRAM_nCAS = 1'b1;
    assign SDRAM_nRAS = 1'b1;
    assign SDRAM_nWE  = 1'b1;

    assign UART_RTS = 1'b1;
    assign UART_TXD = 1'b1;
    assign UART_DTR = 1'b1;
    assign USER_OUT = 7'h7f;

    // Mark currently unused inputs as intentionally unused for lint/formality.
    wire unused_inputs = ^{
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
        OSD_STATUS,
        player_pc_debug,
        player_last_cmd_debug
    };

endmodule

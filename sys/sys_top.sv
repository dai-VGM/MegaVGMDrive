// Minimal Quartus top for the VGM MD fixed-region bring-up.
//
// This is a lightweight skeleton so the project has a concrete TOP_LEVEL_ENTITY
// before a full MiSTer framework/sys_top is imported. It instantiates the
// MiSTer-facing emu wrapper and exposes only the signals useful for early
// Quartus compile / board-level probing.
//
// TODO: Replace this file with a known-working MiSTer template sys_top before
// relying on the generated .rbf as a normal MiSTer core.

module sys_top (
    input  wire              CLK_50M,
    input  wire              RESET_N,

    output wire signed [15:0] AUDIO_L,
    output wire signed [15:0] AUDIO_R,
    output wire               AUDIO_S,
    output wire        [1:0]  AUDIO_MIX,

    output wire               CLK_VIDEO,
    output wire               CE_PIXEL,
    output wire        [7:0]  VGA_R,
    output wire        [7:0]  VGA_G,
    output wire        [7:0]  VGA_B,
    output wire               VGA_HS,
    output wire               VGA_VS,
    output wire               VGA_DE,

    output wire               LED_USER
);

    wire [48:0] hps_bus;
    wire [3:0]  adc_bus;
    wire [15:0] sdram_dq;

    wire [12:0] video_arx;
    wire [12:0] video_ary;
    wire        vga_f1;
    wire [1:0]  vga_sl;
    wire        vga_scaler;
    wire        hdmi_freeze;

    wire [1:0] led_power;
    wire [1:0] led_disk;
    wire [1:0] buttons;

    wire sd_sck;
    wire sd_mosi;
    wire sd_cs;

    wire        ddram_clk;
    wire [7:0]  ddram_burstcnt;
    wire [28:0] ddram_addr;
    wire        ddram_rd;
    wire [63:0] ddram_din;
    wire [7:0]  ddram_be;
    wire        ddram_we;

    wire        sdram_clk;
    wire        sdram_cke;
    wire [12:0] sdram_a;
    wire [1:0]  sdram_ba;
    wire        sdram_dqml;
    wire        sdram_dqmh;
    wire        sdram_ncs;
    wire        sdram_ncas;
    wire        sdram_nras;
    wire        sdram_nwe;

    wire uart_rts;
    wire uart_txd;
    wire uart_dtr;
    wire [6:0] user_out;

    emu emu_inst (
        .CLK_50M           (CLK_50M),
        .RESET             (!RESET_N),
        .HPS_BUS           (hps_bus),

        .CLK_VIDEO         (CLK_VIDEO),
        .CE_PIXEL          (CE_PIXEL),
        .VIDEO_ARX         (video_arx),
        .VIDEO_ARY         (video_ary),
        .VGA_R             (VGA_R),
        .VGA_G             (VGA_G),
        .VGA_B             (VGA_B),
        .VGA_HS            (VGA_HS),
        .VGA_VS            (VGA_VS),
        .VGA_DE            (VGA_DE),
        .VGA_F1            (vga_f1),
        .VGA_SL            (vga_sl),
        .VGA_SCALER        (vga_scaler),
        .HDMI_WIDTH        (12'd640),
        .HDMI_HEIGHT       (12'd480),
        .HDMI_FREEZE       (hdmi_freeze),

        .CLK_AUDIO         (CLK_50M),
        .AUDIO_L           (AUDIO_L),
        .AUDIO_R           (AUDIO_R),
        .AUDIO_S           (AUDIO_S),
        .AUDIO_MIX         (AUDIO_MIX),

        .LED_USER          (LED_USER),
        .LED_POWER         (led_power),
        .LED_DISK          (led_disk),
        .BUTTONS           (buttons),

        .ADC_BUS           (adc_bus),
        .SD_SCK            (sd_sck),
        .SD_MOSI           (sd_mosi),
        .SD_MISO           (1'b0),
        .SD_CS             (sd_cs),
        .SD_CD             (1'b1),

        .DDRAM_CLK         (ddram_clk),
        .DDRAM_BUSY        (1'b0),
        .DDRAM_BURSTCNT    (ddram_burstcnt),
        .DDRAM_ADDR        (ddram_addr),
        .DDRAM_DOUT        (64'd0),
        .DDRAM_DOUT_READY  (1'b0),
        .DDRAM_RD          (ddram_rd),
        .DDRAM_DIN         (ddram_din),
        .DDRAM_BE          (ddram_be),
        .DDRAM_WE          (ddram_we),

        .SDRAM_CLK         (sdram_clk),
        .SDRAM_CKE         (sdram_cke),
        .SDRAM_A           (sdram_a),
        .SDRAM_BA          (sdram_ba),
        .SDRAM_DQ          (sdram_dq),
        .SDRAM_DQML        (sdram_dqml),
        .SDRAM_DQMH        (sdram_dqmh),
        .SDRAM_nCS         (sdram_ncs),
        .SDRAM_nCAS        (sdram_ncas),
        .SDRAM_nRAS        (sdram_nras),
        .SDRAM_nWE         (sdram_nwe),

        .UART_CTS          (1'b1),
        .UART_RTS          (uart_rts),
        .UART_RXD          (1'b1),
        .UART_TXD          (uart_txd),
        .UART_DTR          (uart_dtr),
        .UART_DSR          (1'b1),

        .USER_IN           (7'd0),
        .USER_OUT          (user_out),
        .OSD_STATUS        (1'b0)
    );

endmodule

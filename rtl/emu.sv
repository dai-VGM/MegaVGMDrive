// MiSTer emu wrapper for the VGM MD fixed-region bring-up.
//
// This version follows the official Template_MiSTer structure:
// - sys/sys_top.v is the Quartus top.
// - sys_top instantiates a core-provided module named emu.
// - emu uses sys/emu_ports.vh for the standard MiSTer port list.
// - hps_io is instantiated only to expose CONF_STR/menu/reset basics.
//
// The current hardware goal is video/sys_top sanity first:
// - monitor keeps sync
// - MiSTer menu can return
// - core name appears
// - fixed debug colors show reset/running/player/audio state

module emu (
    `include "sys/emu_ports.vh"
);

    localparam CONF_STR = {
        "VGM_MD;;",
        "-;",
        "T0,Reset;",
        "R0,Reset and close OSD;",
        "v,1;"
    };

    // Template_MiSTer's sys_top routes CLK_VIDEO into clock select blocks as
    // inclk[3]. Quartus requires that path to be driven by a PLL output, not a
    // raw FPGA clock pin. Keep the same basic pattern as Template.sv: generate
    // the core/video clock with the core PLL and return that clock as
    // CLK_VIDEO.
    wire clk_sys;
    wire pll_locked;

    pll pll (
        .refclk   (CLK_50M),
        .rst      (1'b0),
        .outclk_0 (clk_sys),
        .locked   (pll_locked)
    );

    // ---------------------------------------------------------------------
    // MiSTer framework / HPS menu basics.
    // ---------------------------------------------------------------------

    wire        forced_scandoubler;
    wire [1:0]  buttons;
    wire [127:0] status;

    hps_io #(.CONF_STR(CONF_STR)) hps_io (
        .clk_sys            (clk_sys),
        .HPS_BUS            (HPS_BUS),
        .EXT_BUS            (),
        .gamma_bus          (),
        .forced_scandoubler (forced_scandoubler),
        .buttons            (buttons),
        .status             (status),
        .status_menumask    (16'd0)
    );

    // ---------------------------------------------------------------------
    // Clock/reset.
    // ---------------------------------------------------------------------

    wire reset   = RESET | status[0] | buttons[1] | !pll_locked;

    // ---------------------------------------------------------------------
    // Fixed-region MD sound experiment.
    // ---------------------------------------------------------------------

    wire signed [15:0] md_audio_l;
    wire signed [15:0] md_audio_r;
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

    assign AUDIO_L   = md_audio_l;
    assign AUDIO_R   = md_audio_r;
    assign AUDIO_S   = 1'b1;   // signed 16-bit samples
    assign AUDIO_MIX = 2'b00;  // keep stereo

    // ---------------------------------------------------------------------
    // Debug color video.
    // ---------------------------------------------------------------------
    //
    // reset              : black
    // running            : blue
    // audio_seen_latched : red
    // player_done_latched: green
    //
    // player_done has priority over audio_seen so the final visible state
    // confirms that the fixed region reached its end.

    assign CLK_VIDEO = clk_sys;

    reg       ce_pix;
    reg [9:0] h_count;
    reg [9:0] v_count;
    reg       player_done_latched;
    reg       audio_seen_latched;

    always @(posedge clk_sys) begin
        if (reset) begin
            ce_pix              <= 1'b0;
            h_count             <= 10'd0;
            v_count             <= 10'd0;
            player_done_latched <= 1'b0;
            audio_seen_latched  <= 1'b0;
        end else begin
            ce_pix <= ~ce_pix;

            if (ce_pix) begin
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

            if (player_done) begin
                player_done_latched <= 1'b1;
            end

            if (audio_sample_valid || (md_audio_l != 16'sd0) || (md_audio_r != 16'sd0)) begin
                audio_seen_latched <= 1'b1;
            end
        end
    end

    wire video_active = (h_count < 10'd640) && (v_count < 10'd480);

    reg [7:0] dbg_r;
    reg [7:0] dbg_g;
    reg [7:0] dbg_b;

    always @* begin
        if (reset) begin
            dbg_r = 8'h00;
            dbg_g = 8'h00;
            dbg_b = 8'h00;
        end else if (player_done_latched) begin
            dbg_r = 8'h00;
            dbg_g = 8'hc0;
            dbg_b = 8'h20;
        end else if (audio_seen_latched) begin
            dbg_r = 8'hc0;
            dbg_g = 8'h20;
            dbg_b = 8'h20;
        end else begin
            dbg_r = 8'h20;
            dbg_g = 8'h40;
            dbg_b = 8'hc0;
        end
    end

    assign CE_PIXEL = ce_pix;
    assign VGA_DE   = video_active;
    assign VGA_HS   = ~((h_count >= 10'd656) && (h_count < 10'd752));
    assign VGA_VS   = ~((v_count >= 10'd490) && (v_count < 10'd492));
    assign VGA_R    = video_active ? dbg_r : 8'h00;
    assign VGA_G    = video_active ? dbg_g : 8'h00;
    assign VGA_B    = video_active ? dbg_b : 8'h00;

    assign VIDEO_ARX = 13'd4;
    assign VIDEO_ARY = 13'd3;
    assign VGA_F1    = 1'b0;
    assign VGA_SL    = 2'b00;
    assign VGA_SCALER = forced_scandoubler;
    assign VGA_DISABLE = 1'b0;
    assign HDMI_FREEZE = 1'b0;
    assign HDMI_BLACKOUT = 1'b0;
    assign HDMI_BOB_DEINT = 1'b0;

    // ---------------------------------------------------------------------
    // Idle unused interfaces.
    // ---------------------------------------------------------------------

    assign ADC_BUS  = 4'bZZZZ;
    assign USER_OUT = 7'h7f;
    assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
    assign {SD_SCK, SD_MOSI, SD_CS} = 3'b111;
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

    assign LED_USER  = player_busy | player_done_latched | audio_seen_latched;
    assign LED_POWER = 2'b00;
    assign LED_DISK  = {1'b0, audio_sample_valid};
    assign BUTTONS   = 2'b00;

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

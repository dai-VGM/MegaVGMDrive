`timescale 1ns/1ps

// MiSTer Template-compatible NTSC native timing for the MegaVGMDrive screen.
//
// This reproduces rtl/mycore.v's non-scandoubled timing contract: the shared
// 20 MHz system/video clock produces one pixel enable every two clocks, the
// counters cover 638 x 262, and blank/sync transitions use the same counts.
// HSync and VSync remain positive for sys_top's existing sync_fix contract.
module megavgm_video_timing #(
    parameter logic [9:0] H_TOTAL       = 10'd638,
    parameter logic [9:0] H_BLANK_START = 10'd529,
    parameter logic [9:0] H_SYNC_START  = 10'd544,
    parameter logic [9:0] H_SYNC_END    = 10'd590,
    parameter logic [8:0] V_TOTAL       = 9'd262,
    parameter logic [8:0] V_BLANK_START = 9'd240,
    parameter logic [8:0] V_SYNC_START  = 9'd245,
    parameter logic [8:0] V_SYNC_END    = 9'd248
) (
    input  logic       clk_video,
    input  logic       reset,
    output logic       ce_pix,
    output logic [9:0] h_count,
    output logic [8:0] v_count,
    output logic       hblank,
    output logic       vblank,
    output logic       hsync,
    output logic       vsync,
    output logic       de,
    output logic       vblank_start
);
    logic pixel_phase;

    always_ff @(posedge clk_video) begin
        if (reset) begin
            pixel_phase <= 1'b0;
            h_count     <= 10'd0;
            v_count     <= 9'd0;
        end else begin
            pixel_phase <= ~pixel_phase;
            if (pixel_phase) begin
                if (h_count == H_TOTAL - 10'd1) begin
                    h_count <= 10'd0;
                    if (v_count == V_TOTAL - 9'd1) begin
                        v_count <= 9'd0;
                    end else begin
                        v_count <= v_count + 9'd1;
                    end
                end else begin
                    h_count <= h_count + 10'd1;
                end
            end
        end
    end

    always_comb begin
        ce_pix       = !reset && pixel_phase;
        hblank       = (h_count >= H_BLANK_START);
        vblank       = (v_count >= V_BLANK_START);
        hsync        = (h_count >= H_SYNC_START) &&
                       (h_count < H_SYNC_END);
        vsync        = (v_count >= V_SYNC_START) &&
                       (v_count < V_SYNC_END);
        de           = !hblank && !vblank;
        vblank_start = ce_pix &&
                       (h_count == 10'd0) &&
                       (v_count == V_BLANK_START);
    end

`ifndef SYNTHESIS
    initial begin
        if (H_TOTAL != 10'd638) $fatal(1, "MegaVGMDrive H_TOTAL must be 638");
        if (V_TOTAL != 9'd262) $fatal(1, "MegaVGMDrive V_TOTAL must be 262");
        if (H_BLANK_START != 10'd529)
            $fatal(1, "MegaVGMDrive H_BLANK_START must be 529");
        if (H_SYNC_START != 10'd544)
            $fatal(1, "MegaVGMDrive H_SYNC_START must be 544");
        if (H_SYNC_END != 10'd590)
            $fatal(1, "MegaVGMDrive H_SYNC_END must be 590");
        if (V_BLANK_START != 9'd240)
            $fatal(1, "MegaVGMDrive V_BLANK_START must be 240");
        if (V_SYNC_START != 9'd245)
            $fatal(1, "MegaVGMDrive V_SYNC_START must be 245");
        if (V_SYNC_END != 9'd248)
            $fatal(1, "MegaVGMDrive V_SYNC_END must be 248");
    end
`endif
endmodule

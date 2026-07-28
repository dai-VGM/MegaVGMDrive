`timescale 1ns/1ps

// Fixed MiSTer-native 240p timing for the MegaVGMDrive status screen.
//
// The shared 20 MHz system/video clock produces one pixel enable every three
// clocks. The 424 x 262 raster is 15.723270 kHz / 60.012483 Hz. HSync and
// VSync remain positive for sys_top's existing sync_fix contract.
module megavgm_video_timing #(
    parameter logic [8:0] H_ACTIVE = 9'd320,
    parameter logic [8:0] H_FRONT  = 9'd16,
    parameter logic [8:0] H_SYNC   = 9'd32,
    parameter logic [8:0] H_BACK   = 9'd56,
    parameter logic [8:0] V_ACTIVE = 9'd240,
    parameter logic [8:0] V_FRONT  = 9'd3,
    parameter logic [8:0] V_SYNC   = 9'd3,
    parameter logic [8:0] V_BACK   = 9'd16
) (
    input  logic       clk_video,
    input  logic       reset,
    output logic       ce_pix,
    output logic [8:0] h_count,
    output logic [8:0] v_count,
    output logic       hblank,
    output logic       vblank,
    output logic       hsync,
    output logic       vsync,
    output logic       de,
    output logic       vblank_start
);
    localparam logic [8:0] H_TOTAL      = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam logic [8:0] H_SYNC_START = H_ACTIVE + H_FRONT;
    localparam logic [8:0] H_SYNC_END   = H_SYNC_START + H_SYNC;
    localparam logic [8:0] V_TOTAL      = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;
    localparam logic [8:0] V_SYNC_START = V_ACTIVE + V_FRONT;
    localparam logic [8:0] V_SYNC_END   = V_SYNC_START + V_SYNC;

    logic [1:0] pixel_div;

    always_ff @(posedge clk_video) begin
        if (reset) begin
            pixel_div <= 2'd0;
            h_count   <= 9'd0;
            v_count   <= 9'd0;
        end else begin
            if (pixel_div == 2'd2) begin
                pixel_div <= 2'd0;
                if (h_count == H_TOTAL - 9'd1) begin
                    h_count <= 9'd0;
                    if (v_count == V_TOTAL - 9'd1) begin
                        v_count <= 9'd0;
                    end else begin
                        v_count <= v_count + 9'd1;
                    end
                end else begin
                    h_count <= h_count + 9'd1;
                end
            end else begin
                pixel_div <= pixel_div + 2'd1;
            end
        end
    end

    always_comb begin
        ce_pix       = !reset && (pixel_div == 2'd2);
        hblank       = (h_count >= H_ACTIVE);
        vblank       = (v_count >= V_ACTIVE);
        hsync        = (h_count >= H_SYNC_START) &&
                       (h_count < H_SYNC_END);
        vsync        = (v_count >= V_SYNC_START) &&
                       (v_count < V_SYNC_END);
        de           = !hblank && !vblank;
        vblank_start = ce_pix &&
                       (h_count == 9'd0) &&
                       (v_count == V_ACTIVE);
    end

`ifndef SYNTHESIS
    initial begin
        if (H_TOTAL != 9'd424) $fatal(1, "MegaVGMDrive H_TOTAL must be 424");
        if (V_TOTAL != 9'd262) $fatal(1, "MegaVGMDrive V_TOTAL must be 262");
    end
`endif
endmodule

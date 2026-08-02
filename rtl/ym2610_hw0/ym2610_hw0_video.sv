`timescale 1ns/1ps

// Stable 10 MHz native-video timing inherited from megavgm_video_timing.
module ym2610_hw0_video (
    input  logic       clk,
    input  logic       reset,
    input  logic [3:0] phase,
    input  logic       error,
    output logic       ce_pixel,
    output logic       hsync,
    output logic       vsync,
    output logic       de,
    output logic [7:0] r,
    output logic [7:0] g,
    output logic [7:0] b
);
    logic pixel_div;
    logic [9:0] h_count;
    logic [8:0] v_count;
    logic [23:0] color;

    always_ff @(posedge clk) begin
        if (reset) pixel_div <= 1'b0;
        else pixel_div <= ~pixel_div;
    end
    assign ce_pixel = pixel_div;

    always_ff @(posedge clk) begin
        if (reset) begin
            h_count <= 10'd0;
            v_count <= 9'd0;
        end else if (ce_pixel) begin
            if (h_count == 10'd637) begin
                h_count <= 10'd0;
                if (v_count == 9'd261) v_count <= 9'd0;
                else v_count <= v_count + 9'd1;
            end else h_count <= h_count + 10'd1;
        end
    end

    assign de = h_count < 10'd529 && v_count < 9'd240;
    assign hsync = !(h_count >= 10'd544 && h_count < 10'd590);
    assign vsync = !(v_count >= 9'd245 && v_count < 9'd248);

    always_comb begin
        if (error) color = 24'hff0000;
        else begin
            case (phase)
                4'd1: color = 24'h0030ff; // FM: blue
                4'd2: color = 24'h00d040; // SSG: green
                4'd3: color = 24'hffe000; // ADPCM-A voice 0: yellow
                4'd4: color = 24'hff7000; // ADPCM-A six voice: orange
                4'd5: color = 24'hff00b0; // ADPCM-B stereo: magenta
                4'd6: color = 24'h00d8e8; // ADPCM-B pan: cyan
                4'd7: color = 24'hffffff; // natural end/restart: white
                default: color = 24'h000030; // reset/silence: navy
            endcase
        end
        if (de) {r, g, b} = color;
        else {r, g, b} = 24'h000000;
    end
endmodule

`timescale 1ns/1ps

// Stable 10 MHz native-video timing inherited from megavgm_video_timing.
module ym2610_hw0_video (
    input  logic       clk,
    input  logic       reset,
    input  logic [3:0] phase,
    input  logic       error,
    input  logic [3:0] error_code,
    input  logic [6:0] diag_seen,
    input  logic [6:0] diag_fail,
    input  logic [2:0] diag_attempt,
    input  logic [2:0] diag_completed_attempts,
    input  logic       diag_attempt_active,
    input  logic [34:0] diag_summary,
    input  logic [4:0] diag_summary_valid,
    input  logic       summary_active,
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
    integer box_index;
    integer row_index;
    integer column_index;
    integer attempt_index;
    logic [23:0] row_color;

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
        color = 24'h000030;
        row_color = 24'h000000;
        box_index = 0;
        row_index = 0;
        column_index = 0;
        attempt_index = 0;
        {r, g, b} = 24'h000000;

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
                4'd8: color = 24'h000018; // diagnostic summary
                default: color = 24'h000030; // reset/silence: navy
            endcase
        end

        // Seven status boxes: RAW, capture, progress, source lane, JT10
        // final, HW output, and stop/restart.  Missing cells turn red only
        // after the attempt closes.
        if (!error && phase >= 4'd3 && phase <= 4'd7 &&
            v_count >= 9'd8 && v_count < 9'd40) begin
            for (box_index = 0; box_index < 7; box_index = box_index + 1) begin
                if (h_count >= 14 + box_index*68 &&
                    h_count < 74 + box_index*68) begin
                    if (diag_fail[box_index]) color = 24'hff2020;
                    else if (diag_seen[box_index]) color = 24'h20e060;
                    else color = 24'h303038;
                end
            end
        end

        // Six attempt indicators.  Natural/restart intentionally uses only
        // the first three; the remaining cells stay dark gray.
        if (!error && phase >= 4'd3 && phase <= 4'd7 &&
            v_count >= 9'd216 && v_count < 9'd232) begin
            for (attempt_index = 0; attempt_index < 6;
                 attempt_index = attempt_index + 1) begin
                if (h_count >= 70 + attempt_index*64 &&
                    h_count < 120 + attempt_index*64) begin
                    if (phase == 4'd7 && attempt_index >= 3)
                        color = 24'h303038;
                    else if (attempt_index < diag_completed_attempts)
                        color = 24'hffffff;
                    else if (attempt_index == diag_attempt &&
                             diag_attempt_active)
                        color = 24'h20e060;
                    else color = 24'h303038;
                end
            end
        end

        // Five-row by seven-column photo-readable final matrix.  The left
        // stripe identifies A0/A6/B/pan/restart by the established colors.
        if (!error && summary_active) begin
            color = 24'h000018;
            for (row_index = 0; row_index < 5; row_index = row_index + 1) begin
                if (v_count >= 40 + row_index*38 &&
                    v_count < 70 + row_index*38) begin
                    case (row_index)
                        0: row_color = 24'hffe000;
                        1: row_color = 24'hff7000;
                        2: row_color = 24'hff00b0;
                        3: row_color = 24'h00d8e8;
                        default: row_color = 24'hffffff;
                    endcase
                    if (h_count >= 10'd8 && h_count < 10'd40)
                        color = row_color;
                    for (column_index = 0; column_index < 7;
                         column_index = column_index + 1) begin
                        if (h_count >= 54 + column_index*60 &&
                            h_count < 106 + column_index*60) begin
                            if (!diag_summary_valid[row_index])
                                color = 24'h303038;
                            else if (diag_summary[row_index*7+column_index])
                                color = 24'h20e060;
                            else color = 24'hff2020;
                        end
                    end
                end
            end
        end

        // Fatal errors retain full red and expose the four-bit reason at the
        // bottom as white/black cells, MSB first.
        if (error && v_count >= 9'd192 && v_count < 9'd224) begin
            for (box_index = 0; box_index < 4; box_index = box_index + 1) begin
                if (h_count >= 160 + box_index*52 &&
                    h_count < 200 + box_index*52)
                    color = error_code[3-box_index] ? 24'hffffff : 24'h000000;
            end
        end

        // Permanent diagnostic-build marker: 16x16, white/magenta 2x2.
        if (h_count >= 10'd504 && h_count < 10'd520 &&
            v_count >= 9'd8 && v_count < 9'd24)
            color = (h_count[3] ^ v_count[3]) ? 24'hff00b0 : 24'hffffff;
        if (de) {r, g, b} = color;
        else {r, g, b} = 24'h000000;
    end
endmodule

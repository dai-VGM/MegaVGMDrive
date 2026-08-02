`timescale 1ns/1ps

// Zero-wait-state deterministic ADPCM-A ROM used only by the HW-0 lab RBF.
// This is the Phase 3A primary byte rule, written with shifts/adds so the
// synthesis result does not require a general multiplier.
module ym2610_hw0_adpcma_rom (
    input  logic [19:0] address,
    input  logic  [3:0] bank,
    output logic  [7:0] data
);
    logic [23:0] logical_address;
    logic [15:0] low_product;
    logic [12:0] high_product;

    always_comb begin
        logical_address = {bank, address};
        low_product = ({8'd0, logical_address[7:0]} << 6) +
                      ({8'd0, logical_address[7:0]} << 3) +
                       {8'd0, logical_address[7:0]};       // *73
        high_product = ({9'd0, logical_address[11:8]} << 5) -
                       ({9'd0, logical_address[11:8]} << 1) -
                        {9'd0, logical_address[11:8]}; // *29
        data = low_product[7:0] + high_product[7:0] + 8'd41;
    end
endmodule

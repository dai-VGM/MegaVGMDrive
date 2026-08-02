`timescale 1ns/1ps

// Zero-wait-state deterministic ADPCM-B ROM used only by the HW-0 lab RBF.
// This is the Phase 4A primary byte rule.  The upper address byte is ignored,
// exactly as in the verified fixture; the byte stream repeats every 64 KiB.
module ym2610_hw0_adpcmb_rom (
    input  logic [23:0] address,
    output logic  [7:0] data
);
    logic [15:0] low_product;
    logic [15:0] high_product;

    always_comb begin
        low_product = ({8'd0, address[7:0]} << 6) +
                      ({8'd0, address[7:0]} << 3) +
                       {8'd0, address[7:0]}; // *73
        high_product = ({8'd0, address[15:8]} << 5) -
                       ({8'd0, address[15:8]} << 1) -
                        {8'd0, address[15:8]}; // *29
        data = low_product[7:0] + high_product[7:0] + 8'd41;
    end
endmodule

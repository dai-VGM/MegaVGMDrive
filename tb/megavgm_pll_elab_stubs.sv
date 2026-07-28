`timescale 1ns/1ps

// Elaboration-only clock stub for open-source simulators. Product builds use
// rtl/pll.v with the Cyclone V altera_pll primitive.
module pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire locked
);
    assign outclk_0 = refclk;
    assign locked = !rst;
endmodule

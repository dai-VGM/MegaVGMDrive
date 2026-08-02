`timescale 1ns/1ps

// Elaboration-only substitutes for Quartus/MiSTer dependencies.  The real
// project manifest uses rtl/pll.qip and sys/hps_io.sv, never these stubs.
module pll (
    input  logic refclk,
    input  logic rst,
    output logic outclk_0,
    output logic locked
);
    assign outclk_0 = refclk;
    assign locked = !rst;
endmodule

module hps_io #(
    parameter CONF_STR = ""
) (
    input  logic        clk_sys,
    inout  wire [48:0]  HPS_BUS,
    output logic [1:0]  buttons,
    output logic [31:0] status,
    input  logic        status_menumask,
    output logic        forced_scandoubler,
    input  logic        video_rotated,
    input  logic        new_vmode,
    output logic        direct_video,
    output logic [21:0] gamma_bus
);
    assign HPS_BUS = 49'bz;
    assign buttons = 2'b00;
    assign status = 32'd0;
    assign forced_scandoubler = 1'b0;
    assign direct_video = 1'b0;
    assign gamma_bus = 22'd0;
endmodule

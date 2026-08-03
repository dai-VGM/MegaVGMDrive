`timescale 1ns/1ps

// Elaboration-only substitutes.  The QIP uses the real PLL and hps_io.
module pll (
    input logic refclk, input logic rst,
    output logic outclk_0, output logic locked
);
    assign outclk_0 = refclk;
    assign locked = !rst;
endmodule

module hps_io #(
    parameter CONF_STR = ""
) (
    input logic clk_sys,
    inout wire [48:0] HPS_BUS,
    output logic [1:0] buttons,
    output logic [31:0] status,
    input logic status_menumask,
    output logic forced_scandoubler,
    input logic video_rotated,
    input logic new_vmode,
    output logic direct_video,
    output logic [21:0] gamma_bus,
    output logic ioctl_download,
    output logic ioctl_wr,
    output logic [26:0] ioctl_addr,
    output logic [7:0] ioctl_dout,
    output logic [15:0] ioctl_index,
    input logic ioctl_wait
);
    assign HPS_BUS = 49'bz;
    assign buttons = 2'b00;
    assign status = 32'd0;
    assign forced_scandoubler = 1'b0;
    assign direct_video = 1'b0;
    assign gamma_bus = 22'd0;
    assign ioctl_download = 1'b0;
    assign ioctl_wr = 1'b0;
    assign ioctl_addr = 27'd0;
    assign ioctl_dout = 8'd0;
    assign ioctl_index = 16'd0;
endmodule

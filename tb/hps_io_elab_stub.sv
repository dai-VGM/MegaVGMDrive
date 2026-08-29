`timescale 1ns/1ps

// Elaboration-only subset of the MiSTer hps_io interface used by emu.sv.
// Product builds always use sys/hps_io.sv.
module hps_io #(
    parameter CONF_STR = "",
    parameter CONF_STR_BRAM = 1,
    parameter PS2DIV = 0,
    parameter WIDE = 0,
    parameter VDNUM = 1,
    parameter BLKSZ = 2,
    parameter PS2WE = 0
) (
    input  wire        clk_sys,
    inout  wire [48:0] HPS_BUS,
    output wire  [1:0] buttons,
    output wire [127:0] status,
    input  wire [127:0] status_in,
    input  wire        status_set,
    input  wire [15:0] status_menumask,
    output wire        forced_scandoubler,
    output wire        direct_video,
    input  wire        video_rotated,
    input  wire        new_vmode,
    inout  wire [21:0] gamma_bus,

    output wire        ioctl_download,
    output wire        ioctl_wr,
    output wire [26:0] ioctl_addr,
    output wire  [7:0] ioctl_dout,
    output wire [15:0] ioctl_index,
    input  wire        ioctl_wait,

    output wire [31:0] joystick_0,
    output wire [31:0] joystick_1,
    output wire [31:0] joystick_2,
    output wire [31:0] joystick_3,
    output wire [31:0] joystick_4,
    output wire [31:0] joystick_5,
    output wire [15:0] joystick_l_analog_0,
    output wire [15:0] joystick_l_analog_1,
    output wire [15:0] joystick_l_analog_2,
    output wire [15:0] joystick_l_analog_3,
    output wire [15:0] joystick_l_analog_4,
    output wire [15:0] joystick_l_analog_5,
    output wire [15:0] joystick_r_analog_0,
    output wire [15:0] joystick_r_analog_1,
    output wire [15:0] joystick_r_analog_2,
    output wire [15:0] joystick_r_analog_3,
    output wire [15:0] joystick_r_analog_4,
    output wire [15:0] joystick_r_analog_5,
    output wire  [7:0] paddle_0,
    output wire  [7:0] paddle_1,
    output wire  [7:0] paddle_2,
    output wire  [7:0] paddle_3,
    output wire  [7:0] paddle_4,
    output wire  [7:0] paddle_5,
    output wire  [8:0] spinner_0,
    output wire  [8:0] spinner_1,
    output wire  [8:0] spinner_2,
    output wire  [8:0] spinner_3,
    output wire  [8:0] spinner_4,
    output wire  [8:0] spinner_5,
    output wire [10:0] ps2_key,
    output wire [24:0] ps2_mouse,
    output wire [15:0] ps2_mouse_ext,
    output wire [32:0] TIMESTAMP
);
    assign HPS_BUS = 'z;
    assign gamma_bus = 'z;
    assign buttons = '0;
    assign status = '0;
    assign forced_scandoubler = 1'b0;
    assign direct_video = 1'b0;
    assign ioctl_download = 1'b0;
    assign ioctl_wr = 1'b0;
    assign ioctl_addr = '0;
    assign ioctl_dout = '0;
    assign ioctl_index = '0;
    assign {
        joystick_0, joystick_1, joystick_2, joystick_3, joystick_4,
        joystick_5
    } = '0;
    assign {
        joystick_l_analog_0, joystick_l_analog_1, joystick_l_analog_2,
        joystick_l_analog_3, joystick_l_analog_4, joystick_l_analog_5,
        joystick_r_analog_0, joystick_r_analog_1, joystick_r_analog_2,
        joystick_r_analog_3, joystick_r_analog_4, joystick_r_analog_5
    } = '0;
    assign {
        paddle_0, paddle_1, paddle_2, paddle_3, paddle_4, paddle_5
    } = '0;
    assign {
        spinner_0, spinner_1, spinner_2, spinner_3, spinner_4, spinner_5
    } = '0;
    assign ps2_key = '0;
    assign ps2_mouse = '0;
    assign ps2_mouse_ext = '0;
    assign TIMESTAMP = '0;

    wire unused = ^{
        clk_sys, status_menumask, video_rotated, new_vmode, ioctl_wait,
        CONF_STR_BRAM, PS2DIV, WIDE, VDNUM, BLKSZ, PS2WE
    };
endmodule

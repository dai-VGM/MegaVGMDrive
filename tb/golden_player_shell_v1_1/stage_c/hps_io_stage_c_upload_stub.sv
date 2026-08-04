`timescale 1ns/1ps

// Simulation-only hps_io surface that performs one ordinary file-index 1
// upload through the unchanged emu/shim/upload path. It is never in the QIP.
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
    output logic [1:0] buttons,
    output logic [31:0] status,
    input  wire [15:0] status_menumask,
    output logic       forced_scandoubler,
    output logic       direct_video,
    input  wire        video_rotated,
    input  wire        new_vmode,
    inout  wire [21:0] gamma_bus,
    output logic       ioctl_download,
    output logic       ioctl_wr,
    output logic [26:0] ioctl_addr,
    output logic [7:0] ioctl_dout,
    output logic [15:0] ioctl_index,
    input  wire        ioctl_wait,
    output logic [31:0] joystick_0,
    output logic [31:0] joystick_1,
    output logic [31:0] joystick_2,
    output logic [31:0] joystick_3,
    output logic [31:0] joystick_4,
    output logic [31:0] joystick_5,
    output logic [15:0] joystick_l_analog_0,
    output logic [15:0] joystick_l_analog_1,
    output logic [15:0] joystick_l_analog_2,
    output logic [15:0] joystick_l_analog_3,
    output logic [15:0] joystick_l_analog_4,
    output logic [15:0] joystick_l_analog_5,
    output logic [15:0] joystick_r_analog_0,
    output logic [15:0] joystick_r_analog_1,
    output logic [15:0] joystick_r_analog_2,
    output logic [15:0] joystick_r_analog_3,
    output logic [15:0] joystick_r_analog_4,
    output logic [15:0] joystick_r_analog_5,
    output logic [7:0] paddle_0,
    output logic [7:0] paddle_1,
    output logic [7:0] paddle_2,
    output logic [7:0] paddle_3,
    output logic [7:0] paddle_4,
    output logic [7:0] paddle_5,
    output logic [8:0] spinner_0,
    output logic [8:0] spinner_1,
    output logic [8:0] spinner_2,
    output logic [8:0] spinner_3,
    output logic [8:0] spinner_4,
    output logic [8:0] spinner_5,
    output logic [10:0] ps2_key,
    output logic [24:0] ps2_mouse,
    output logic [15:0] ps2_mouse_ext,
    output logic [32:0] TIMESTAMP
);
    localparam int MAX_FILE = 1 << 20;
    logic [7:0] source [0:MAX_FILE-1];
    string filename;
    integer fd;
    integer file_size;
    integer address;
    integer start_cycles;

    assign HPS_BUS = 'z;
    assign gamma_bus = 'z;

    initial begin
        buttons = '0;
        status = '0;
        forced_scandoubler = 1'b0;
        direct_video = 1'b0;
        ioctl_download = 1'b0;
        ioctl_wr = 1'b0;
        ioctl_addr = '0;
        ioctl_dout = '0;
        ioctl_index = 16'd1;
        joystick_0 = '0; joystick_1 = '0; joystick_2 = '0;
        joystick_3 = '0; joystick_4 = '0; joystick_5 = '0;
        joystick_l_analog_0 = '0; joystick_l_analog_1 = '0;
        joystick_l_analog_2 = '0; joystick_l_analog_3 = '0;
        joystick_l_analog_4 = '0; joystick_l_analog_5 = '0;
        joystick_r_analog_0 = '0; joystick_r_analog_1 = '0;
        joystick_r_analog_2 = '0; joystick_r_analog_3 = '0;
        joystick_r_analog_4 = '0; joystick_r_analog_5 = '0;
        paddle_0 = '0; paddle_1 = '0; paddle_2 = '0;
        paddle_3 = '0; paddle_4 = '0; paddle_5 = '0;
        spinner_0 = '0; spinner_1 = '0; spinner_2 = '0;
        spinner_3 = '0; spinner_4 = '0; spinner_5 = '0;
        ps2_key = '0;
        ps2_mouse = '0;
        ps2_mouse_ext = '0;
        TIMESTAMP = '0;

        if (!$value$plusargs("VGM=%s", filename))
            $fatal(1, "use +VGM=/path/file.vgm");
        if (!$value$plusargs("UPLOAD_START_CYCLES=%d", start_cycles))
            start_cycles = 16_800_000;
        fd = $fopen(filename, "rb");
        if (!fd) $fatal(1, "cannot open %s", filename);
        file_size = $fread(source, fd);
        $fclose(fd);
        if (file_size <= 0 || file_size > MAX_FILE)
            $fatal(1, "invalid upload size %0d", file_size);

        repeat (start_cycles) @(posedge clk_sys);
        @(negedge clk_sys);
        ioctl_download = 1'b1;
        @(negedge clk_sys);
        for (address = 0; address < file_size; address = address + 1) begin
            while (ioctl_wait) begin
                ioctl_wr = 1'b0;
                @(negedge clk_sys);
            end
            ioctl_addr = address;
            ioctl_dout = source[address];
            ioctl_wr = 1'b1;
            @(negedge clk_sys);
            ioctl_wr = 1'b0;
        end
        ioctl_download = 1'b0;
        $display("V1_1_STAGE_C_FULL_EMU_UPLOAD bytes=%0d", file_size);
        $fflush();
    end

    wire unused = ^{
        status_menumask, video_rotated, new_vmode, CONF_STR_BRAM,
        PS2DIV, WIDE, VDNUM, BLKSZ, PS2WE
    };
endmodule

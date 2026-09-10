// SPDX-License-Identifier: GPL-2.0-or-later
//
// Thin Stage A owner for the stable MegaVGMPlayer physical DDR upload path.
// The implementation is the unchanged production vgm_ddram_backend.  This
// wrapper only adapts its shell-width ioctl ports and exposes one inert read
// client boundary for later Golden Profile stages.

`timescale 1ns/1ps

module golden_player_shell_upload #(
    parameter int VGM_ADDR_WIDTH = 23,
    parameter logic [15:0] FILE_INDEX = 16'd1
) (
    input  logic                      clk,
    input  logic                      reset,
    input  logic                      ioctl_download,
    input  logic                      ioctl_wr,
    input  logic [26:0]               ioctl_addr,
    input  logic [7:0]                ioctl_dout,
    input  logic [15:0]               ioctl_index,
    output logic                      ioctl_wait,

    input  logic                      file_read_request,
    input  logic [VGM_ADDR_WIDTH-1:0] file_read_address,
    output logic                      file_read_ready,
    output logic                      file_read_valid,
    output logic [7:0]                file_read_data,

    output logic                      load_busy,
    output logic                      load_done,
    output logic                      load_done_pulse,
    output logic                      load_error,
    output logic                      load_overflow,
    output logic [31:0]               uploaded_physical_size,
    output logic [31:0]               upload_magic,

    input  logic                      ddram_busy,
    output logic [7:0]                ddram_burstcnt,
    output logic [28:0]               ddram_addr,
    input  logic [63:0]               ddram_dout,
    input  logic                      ddram_dout_ready,
    output logic                      ddram_rd,
    output logic [63:0]               ddram_din,
    output logic [7:0]                ddram_be,
    output logic                      ddram_we
);

    logic play_ready_pulse;
    logic copy_write_ready;
    logic copy_flush_done;
    logic [15:0] copy_accept_count;
    logic [15:0] copy_write_count;
    logic [15:0] copy_fifo;
    logic [15:0] copy_ready;
    logic [15:0] copy_write_req;
    logic [15:0] copy_word;
    logic [15:0] copy_flush;
    logic [15:0] copy_full_detect_count;
    logic [15:0] copy_push_req_count;
    logic [15:0] copy_push_fire_count;
    logic [15:0] copy_fifo_push_count;
    logic [15:0] copy_pack_ready;
    logic [15:0] copy_post_push;
    logic [15:0] read_gate;
    logic [15:0] read_after_copy_count;

`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
    logic        smoke_read_ready;
    logic        smoke_read_valid;
    logic [7:0]  smoke_read_data;
    logic        smoke_payload_present;
    logic [18:0] smoke_payload_length;
    logic [15:0] smoke_debug [0:22];
    logic [7:0]  smoke_last_write_data;
    logic [7:0]  smoke_last_read_data;
`endif

    vgm_ddram_backend #(
        .ADDR_WIDTH(VGM_ADDR_WIDTH),
        .ACCEPT_ANY_INDEX(1'b0),
        .FILE_INDEX(FILE_INDEX[7:0]),
        .WRITE_FIFO_DEPTH(256),
        .DDRAM_BASE_ADDR({4'b0011, 25'd0}),
        .SEGAPCM_ROM_BASE_ADDR({4'b0011, 25'd0} + 29'h0010_0000)
    ) stable_upload_backend (
        .clk(clk),
        .reset(reset),
        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr({5'd0, ioctl_addr}),
        .ioctl_dout(ioctl_dout),
        .ioctl_index(ioctl_index[7:0]),
        .ioctl_wait(ioctl_wait),

        .mem_rd_req(file_read_request),
        .mem_rd_addr(file_read_address),
        .mem_rd_ready(file_read_ready),
        .mem_rd_valid(file_read_valid),
        .mem_rd_data(file_read_data),

        .segapcm_copy_wr_req(1'b0),
        .segapcm_copy_wr_ready(copy_write_ready),
        .segapcm_copy_wr_addr(19'd0),
        .segapcm_copy_wr_data(8'd0),
        .segapcm_copy_flush_req(1'b0),
        .segapcm_copy_flush_done(copy_flush_done),
        .segapcm_copy_accept_count_debug(copy_accept_count),
        .segapcm_copy_write_count_debug(copy_write_count),
        .segapcm_copy_fifo_debug(copy_fifo),
        .segapcm_copy_ready_debug(copy_ready),
        .segapcm_copy_write_req_debug(copy_write_req),
        .segapcm_copy_word_debug(copy_word),
        .segapcm_copy_flush_debug(copy_flush),
        .segapcm_copy_full_detect_count_debug(copy_full_detect_count),
        .segapcm_copy_push_req_count_debug(copy_push_req_count),
        .segapcm_copy_push_fire_count_debug(copy_push_fire_count),
        .segapcm_copy_fifo_push_count_debug(copy_fifo_push_count),
        .segapcm_copy_pack_ready_debug(copy_pack_ready),
        .segapcm_copy_post_push_debug(copy_post_push),
        .segapcm_read_gate_debug(read_gate),
        .segapcm_read_after_copy_count_debug(read_after_copy_count),

`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
        .smoke_ddr_payload_tap_valid(1'b0),
        .smoke_ddr_payload_tap_addr(19'd0),
        .smoke_ddr_payload_tap_data(8'd0),
        .smoke_ddr_capture_limit(19'd0),
        .smoke_ddr_rd_req(1'b0),
        .smoke_ddr_rd_ready(smoke_read_ready),
        .smoke_ddr_rd_addr(19'd0),
        .smoke_ddr_rd_valid(smoke_read_valid),
        .smoke_ddr_rd_data(smoke_read_data),
        .smoke_ddr_payload_present(smoke_payload_present),
        .smoke_ddr_payload_length(smoke_payload_length),
        .smoke_ddr_write_req_count_debug(smoke_debug[0]),
        .smoke_ddr_write_count_debug(smoke_debug[1]),
        .smoke_ddr_write_blocked_count_debug(smoke_debug[2]),
        .smoke_ddr_write_status_debug(smoke_debug[3]),
        .smoke_ddr_header_skip_count_debug(smoke_debug[4]),
        .smoke_ddr_last_write_index_debug(smoke_debug[5]),
        .smoke_ddr_last_write_addr_debug(smoke_debug[6]),
        .smoke_ddr_last_write_lane_debug(smoke_debug[7]),
        .smoke_ddr_last_write_data_debug(smoke_last_write_data),
        .smoke_ddr_read_count_debug(smoke_debug[8]),
        .smoke_ddr_last_read_index_debug(smoke_debug[9]),
        .smoke_ddr_last_read_addr_debug(smoke_debug[10]),
        .smoke_ddr_last_read_lane_debug(smoke_debug[11]),
        .smoke_ddr_last_read_word0_debug(smoke_debug[12]),
        .smoke_ddr_last_read_word1_debug(smoke_debug[13]),
        .smoke_ddr_last_read_data_debug(smoke_last_read_data),
        .smoke_ddr_base_addr_debug(smoke_debug[14]),
        .smoke_ddr_probe_write_index_debug(smoke_debug[15]),
        .smoke_ddr_probe_write_word_debug(smoke_debug[16]),
        .smoke_ddr_probe_write_lane_debug(smoke_debug[17]),
        .smoke_ddr_probe_write_addr_debug(smoke_debug[18]),
        .smoke_ddr_probe_write_count_debug(smoke_debug[19]),
        .smoke_ddr_probe_write_flags_debug(smoke_debug[20]),
        .smoke_ddr_probe_write_word0_debug(smoke_debug[21]),
        .smoke_ddr_probe_write_word6_debug(smoke_debug[22]),
`endif

        .load_busy(load_busy),
        .load_done(load_done),
        .load_done_pulse(load_done_pulse),
        .play_ready_pulse(play_ready_pulse),
        .load_error(load_error),
        .overflow_error(load_overflow),
        .file_size(uploaded_physical_size),
        .magic_debug(upload_magic),

        .ddram_busy(ddram_busy),
        .ddram_burstcnt(ddram_burstcnt),
        .ddram_addr(ddram_addr),
        .ddram_dout(ddram_dout),
        .ddram_dout_ready(ddram_dout_ready),
        .ddram_rd(ddram_rd),
        .ddram_din(ddram_din),
        .ddram_be(ddram_be),
        .ddram_we(ddram_we)
    );

    wire unused_backend_status = ^{
        play_ready_pulse,
        copy_write_ready,
        copy_flush_done,
        copy_accept_count,
        copy_write_count,
        copy_fifo,
        copy_ready,
        copy_write_req,
        copy_word,
        copy_flush,
        copy_full_detect_count,
        copy_push_req_count,
        copy_push_fire_count,
        copy_fifo_push_count,
        copy_pack_ready,
        copy_post_push,
        read_gate,
        read_after_copy_count
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
        , smoke_read_ready,
        smoke_read_valid,
        smoke_read_data,
        smoke_payload_present,
        smoke_payload_length,
        smoke_last_write_data,
        smoke_last_read_data,
        smoke_debug[0], smoke_debug[1], smoke_debug[2], smoke_debug[3],
        smoke_debug[4], smoke_debug[5], smoke_debug[6], smoke_debug[7],
        smoke_debug[8], smoke_debug[9], smoke_debug[10], smoke_debug[11],
        smoke_debug[12], smoke_debug[13], smoke_debug[14], smoke_debug[15],
        smoke_debug[16], smoke_debug[17], smoke_debug[18], smoke_debug[19],
        smoke_debug[20], smoke_debug[21], smoke_debug[22]
`endif
    };

endmodule

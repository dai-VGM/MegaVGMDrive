// Lightweight Mode5 backend for the SegaPCM C0-only lab build.
//
// This keeps DDRAM only as the OSD-loaded VGM byte store used by
// vgm_loaded_player. SegaPCM type80 payload debug uses a tiny local RAM that
// captures only the Stage Clear block2 payload at dest 0x17100.

module vgm_c0_lab_backend #(
    parameter int ADDR_WIDTH = 23,
    parameter bit ACCEPT_ANY_INDEX = 1'b0,
    parameter logic [7:0] FILE_INDEX = 8'd1,
    parameter int DDRAM_ADDR_WIDTH = 29,
    parameter logic [28:0] DDRAM_BASE_ADDR = 29'd0,
    parameter logic [20:0] TARGET_DEST = 21'h17100,
    parameter logic [18:0] TARGET_LEN = 19'h01200,
    parameter int PAYLOAD_ADDR_WIDTH = 13
) (
    input  logic                         clk,
    input  logic                         reset,

    input  logic                         ioctl_download,
    input  logic                         ioctl_wr,
    input  logic [31:0]                  ioctl_addr,
    input  logic [7:0]                   ioctl_dout,
    input  logic [7:0]                   ioctl_index,
    output logic                         ioctl_wait,

    input  logic                         mem_rd_req,
    input  logic [ADDR_WIDTH-1:0]        mem_rd_addr,
    output logic                         mem_rd_ready,
    output logic                         mem_rd_valid,
    output logic [7:0]                   mem_rd_data,

    input  logic                         payload_tap_valid,
    input  logic [18:0]                  payload_tap_addr,
    input  logic [7:0]                   payload_tap_data,
    input  logic [31:0]                  type80_block_dest,
    input  logic [31:0]                  type80_block_size,

    input  logic                         smoke_rd_req,
    output logic                         smoke_rd_ready,
    input  logic [18:0]                  smoke_rd_addr,
    output logic                         smoke_rd_valid,
    output logic [7:0]                   smoke_rd_data,
    output logic                         smoke_payload_present,
    output logic [18:0]                  smoke_payload_length,

    output logic [15:0]                  smoke_write_req_count_debug,
    output logic [15:0]                  smoke_write_count_debug,
    output logic [15:0]                  smoke_write_blocked_count_debug,
    output logic [15:0]                  smoke_write_status_debug,
    output logic [15:0]                  smoke_header_skip_count_debug,
    output logic [15:0]                  smoke_last_write_index_debug,
    output logic [15:0]                  smoke_last_write_addr_debug,
    output logic [15:0]                  smoke_last_write_lane_debug,
    output logic [7:0]                   smoke_last_write_data_debug,
    output logic [15:0]                  smoke_read_count_debug,
    output logic [15:0]                  smoke_last_read_index_debug,
    output logic [15:0]                  smoke_last_read_addr_debug,
    output logic [15:0]                  smoke_last_read_lane_debug,
    output logic [15:0]                  smoke_last_read_word0_debug,
    output logic [15:0]                  smoke_last_read_word1_debug,
    output logic [7:0]                   smoke_last_read_data_debug,
    output logic [15:0]                  smoke_base_addr_debug,
    output logic [15:0]                  smoke_probe_write_index_debug,
    output logic [15:0]                  smoke_probe_write_word_debug,
    output logic [15:0]                  smoke_probe_write_lane_debug,
    output logic [15:0]                  smoke_probe_write_addr_debug,
    output logic [15:0]                  smoke_probe_write_count_debug,
    output logic [15:0]                  smoke_probe_write_flags_debug,
    output logic [15:0]                  smoke_probe_write_word0_debug,
    output logic [15:0]                  smoke_probe_write_word6_debug,

    output logic                         load_busy,
    output logic                         load_done,
    output logic                         load_done_pulse,
    output logic                         play_ready_pulse,
    output logic                         load_error,
    output logic                         overflow_error,
    output logic [31:0]                  file_size,
    output logic [31:0]                  magic_debug,

    input  logic                         ddram_busy,
    output logic [7:0]                   ddram_burstcnt,
    output logic [DDRAM_ADDR_WIDTH-1:0]  ddram_addr,
    input  logic [63:0]                  ddram_dout,
    input  logic                         ddram_dout_ready,
    output logic                         ddram_rd,
    output logic [63:0]                  ddram_din,
    output logic [7:0]                   ddram_be,
    output logic                         ddram_we
);

    localparam int BYTE_ADDR_WIDTH = DDRAM_ADDR_WIDTH + 3;
    localparam logic [18:0] TARGET_LAST = TARGET_LEN - 19'd1;

    (* ramstyle = "M9K" *) logic [7:0] payload_ram [0:TARGET_LEN-1];

    logic ioctl_download_q;
    logic download_active;
    logic file_accept_q;
    logic read_pending;
    logic [2:0] read_lane;
    logic [18:0] smoke_read_addr_q;
    logic smoke_read_pending;
    logic [7:0] first_byte0;
    logic [7:0] first_byte1;
    logic [7:0] first_byte2;
    logic [7:0] first_byte3;
    logic [7:0] first_byte0_next;
    logic [7:0] first_byte1_next;
    logic [7:0] first_byte2_next;
    logic [7:0] first_byte3_next;

    wire download_start = ioctl_download && !ioctl_download_q;
    wire download_end = !ioctl_download && ioctl_download_q;
    wire file_accept = ACCEPT_ANY_INDEX || (ioctl_index == FILE_INDEX);
    wire ioctl_addr_in_range = ioctl_addr < (32'd1 << ADDR_WIDTH);
    wire accept_wr =
        download_active && ioctl_wr && !ddram_busy && ioctl_addr_in_range;
    wire [DDRAM_ADDR_WIDTH-1:0] ioctl_word_addr =
        DDRAM_BASE_ADDR + ioctl_addr[BYTE_ADDR_WIDTH-1:3];
    wire [DDRAM_ADDR_WIDTH-1:0] mem_read_word_addr =
        DDRAM_BASE_ADDR +
        {{(DDRAM_ADDR_WIDTH-ADDR_WIDTH){1'b0}}, mem_rd_addr[ADDR_WIDTH-1:3]};
    wire [31:0] ioctl_addr_plus_one = ioctl_addr + 32'd1;
    wire target_block_active =
        (type80_block_dest[20:0] == TARGET_DEST) &&
        (type80_block_size >= {13'd0, TARGET_LEN} + 32'd8);
    wire payload_write_live =
        payload_tap_valid &&
        target_block_active &&
        (payload_tap_addr < TARGET_LEN);
    // WR/capture status bit layout:
    // [15:8]=A0 marker, [7]=payload present, [6]=target block active,
    // [5]=read request, [4]=read ready, [3]=read valid,
    // [2]=payload tap valid, [1]=local write live, [0]=overflow.
    wire [15:0] capture_status_debug = {
        8'hA0,
        smoke_payload_present,
        target_block_active,
        smoke_rd_req,
        smoke_rd_ready,
        smoke_rd_valid,
        payload_tap_valid,
        payload_write_live,
        overflow_error
    };

    function automatic [63:0] lane_din(
        input logic [7:0] data,
        input logic [2:0] lane
    );
        begin
            lane_din = 64'd0;
            lane_din[lane * 8 +: 8] = data;
        end
    endfunction

    function automatic [7:0] lane_be(input logic [2:0] lane);
        begin
            lane_be = 8'b0000_0001 << lane;
        end
    endfunction

    function automatic [7:0] lane_dout(
        input logic [63:0] word,
        input logic [2:0] lane
    );
        begin
            lane_dout = word[lane * 8 +: 8];
        end
    endfunction

    always_comb begin
        mem_rd_ready = !download_active && !read_pending && !ddram_busy;
        smoke_rd_ready = smoke_payload_present && !smoke_read_pending;
        ioctl_wait = download_active && ddram_busy;

        first_byte0_next = first_byte0;
        first_byte1_next = first_byte1;
        first_byte2_next = first_byte2;
        first_byte3_next = first_byte3;
        if (payload_write_live) begin
            unique case (payload_tap_addr)
                19'd0: first_byte0_next = payload_tap_data;
                19'd1: first_byte1_next = payload_tap_data;
                19'd2: first_byte2_next = payload_tap_data;
                19'd3: first_byte3_next = payload_tap_data;
                default: begin end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            ioctl_download_q <= 1'b0;
            download_active <= 1'b0;
            file_accept_q <= 1'b0;
            read_pending <= 1'b0;
            read_lane <= 3'd0;
            smoke_read_pending <= 1'b0;
            smoke_read_addr_q <= 19'd0;
            mem_rd_valid <= 1'b0;
            mem_rd_data <= 8'd0;
            smoke_rd_valid <= 1'b0;
            smoke_rd_data <= 8'h80;
            smoke_payload_present <= 1'b0;
            smoke_payload_length <= 19'd0;
            smoke_write_req_count_debug <= 16'd0;
            smoke_write_count_debug <= 16'd0;
            smoke_write_blocked_count_debug <= 16'd0;
            smoke_write_status_debug <= 16'd0;
            smoke_header_skip_count_debug <= 16'd0;
            smoke_last_write_index_debug <= 16'd0;
            smoke_last_write_addr_debug <= 16'd0;
            smoke_last_write_lane_debug <= 16'd0;
            smoke_last_write_data_debug <= 8'd0;
            smoke_read_count_debug <= 16'd0;
            smoke_last_read_index_debug <= 16'd0;
            smoke_last_read_addr_debug <= 16'd0;
            smoke_last_read_lane_debug <= 16'd0;
            smoke_last_read_word0_debug <= 16'd0;
            smoke_last_read_word1_debug <= 16'd0;
            smoke_last_read_data_debug <= 8'd0;
            smoke_base_addr_debug <= 16'd0;
            smoke_probe_write_index_debug <= 16'd0;
            smoke_probe_write_word_debug <= 16'd0;
            smoke_probe_write_lane_debug <= 16'd0;
            smoke_probe_write_addr_debug <= 16'd0;
            smoke_probe_write_count_debug <= 16'd0;
            smoke_probe_write_flags_debug <= 16'd0;
            smoke_probe_write_word0_debug <= 16'd0;
            smoke_probe_write_word6_debug <= 16'd0;
            first_byte0 <= 8'd0;
            first_byte1 <= 8'd0;
            first_byte2 <= 8'd0;
            first_byte3 <= 8'd0;
            load_busy <= 1'b0;
            load_done <= 1'b0;
            load_done_pulse <= 1'b0;
            play_ready_pulse <= 1'b0;
            load_error <= 1'b0;
            overflow_error <= 1'b0;
            file_size <= 32'd0;
            magic_debug <= 32'd0;
            ddram_burstcnt <= 8'd0;
            ddram_addr <= '0;
            ddram_rd <= 1'b0;
            ddram_din <= 64'd0;
            ddram_be <= 8'd0;
            ddram_we <= 1'b0;
        end else begin
            ioctl_download_q <= ioctl_download;
            mem_rd_valid <= 1'b0;
            smoke_rd_valid <= 1'b0;
            load_done_pulse <= 1'b0;
            play_ready_pulse <= 1'b0;
            ddram_burstcnt <= 8'd0;
            ddram_rd <= 1'b0;
            ddram_we <= 1'b0;
            ddram_be <= 8'd0;

            if (download_start) begin
                download_active <= file_accept;
                file_accept_q <= file_accept;
                load_busy <= file_accept;
                load_done <= 1'b0;
                load_done_pulse <= 1'b0;
                play_ready_pulse <= 1'b0;
                load_error <= 1'b0;
                overflow_error <= 1'b0;
                file_size <= 32'd0;
                magic_debug <= 32'd0;
                read_pending <= 1'b0;
                smoke_read_pending <= 1'b0;
                smoke_payload_present <= 1'b0;
                smoke_payload_length <= 19'd0;
                smoke_write_req_count_debug <= 16'd0;
                smoke_write_count_debug <= 16'd0;
                smoke_write_blocked_count_debug <= 16'd0;
                smoke_write_status_debug <= 16'd0;
                smoke_header_skip_count_debug <= 16'd0;
                smoke_last_write_index_debug <= 16'd0;
                smoke_last_write_addr_debug <= 16'd0;
                smoke_last_write_lane_debug <= 16'd0;
                smoke_last_write_data_debug <= 8'd0;
                smoke_read_count_debug <= 16'd0;
                smoke_last_read_index_debug <= 16'd0;
                smoke_last_read_addr_debug <= 16'd0;
                smoke_last_read_lane_debug <= 16'd0;
                smoke_last_read_data_debug <= 8'd0;
                smoke_probe_write_index_debug <= 16'd0;
                smoke_probe_write_word_debug <= 16'd0;
                smoke_probe_write_lane_debug <= 16'd0;
                smoke_probe_write_addr_debug <= 16'd0;
                smoke_probe_write_count_debug <= 16'd0;
                smoke_probe_write_flags_debug <= 16'hC000;
                first_byte0 <= 8'd0;
                first_byte1 <= 8'd0;
                first_byte2 <= 8'd0;
                first_byte3 <= 8'd0;
                smoke_probe_write_word0_debug <= 16'd0;
                smoke_probe_write_word6_debug <= 16'd0;
                smoke_last_read_word0_debug <= 16'd0;
                smoke_last_read_word1_debug <= 16'd0;
            end else if (download_end && download_active) begin
                download_active <= 1'b0;
                load_busy <= 1'b0;
                load_done <= 1'b1;
                load_done_pulse <= 1'b1;
                play_ready_pulse <= 1'b1;
            end else if (download_end && file_accept_q) begin
                file_accept_q <= 1'b0;
            end

            if (accept_wr) begin
                ddram_burstcnt <= 8'd1;
                ddram_addr <= ioctl_word_addr;
                ddram_din <= lane_din(ioctl_dout, ioctl_addr[2:0]);
                ddram_be <= lane_be(ioctl_addr[2:0]);
                ddram_we <= 1'b1;
                if (ioctl_addr_plus_one > file_size) begin
                    file_size <= ioctl_addr_plus_one;
                end
                unique case (ioctl_addr[1:0])
                    2'd0: magic_debug[7:0] <= ioctl_dout;
                    2'd1: magic_debug[15:8] <= ioctl_dout;
                    2'd2: magic_debug[23:16] <= ioctl_dout;
                    2'd3: magic_debug[31:24] <= ioctl_dout;
                endcase
            end else if (download_active && ioctl_wr && !ddram_busy) begin
                overflow_error <= 1'b1;
            end

            if (!download_active && !read_pending && mem_rd_req &&
                !ddram_busy) begin
                ddram_burstcnt <= 8'd1;
                ddram_addr <= mem_read_word_addr;
                ddram_rd <= 1'b1;
                read_lane <= mem_rd_addr[2:0];
                read_pending <= 1'b1;
            end
            if (read_pending && ddram_dout_ready) begin
                mem_rd_valid <= 1'b1;
                mem_rd_data <= lane_dout(ddram_dout, read_lane);
                read_pending <= 1'b0;
            end

            if (payload_tap_valid && target_block_active &&
                (payload_tap_addr >= TARGET_LEN) &&
                (smoke_write_blocked_count_debug != 16'hffff)) begin
                smoke_write_blocked_count_debug <=
                    smoke_write_blocked_count_debug + 16'd1;
            end
            if (payload_tap_valid &&
                (smoke_write_req_count_debug != 16'hffff)) begin
                smoke_write_req_count_debug <= smoke_write_req_count_debug + 16'd1;
            end
            if (payload_write_live) begin
                payload_ram[payload_tap_addr[PAYLOAD_ADDR_WIDTH-1:0]] <=
                    payload_tap_data;
                smoke_payload_present <= 1'b1;
                smoke_payload_length <= TARGET_LEN;
                smoke_last_write_index_debug <= payload_tap_addr[15:0];
                smoke_last_write_addr_debug <= payload_tap_addr[15:0];
                smoke_last_write_lane_debug <= {13'd0, payload_tap_addr[2:0]};
                smoke_last_write_data_debug <= payload_tap_data;
                smoke_probe_write_addr_debug <= payload_tap_addr[15:0];
                smoke_probe_write_lane_debug <= {13'd0, payload_tap_addr[2:0]};
                smoke_probe_write_count_debug <= smoke_write_count_debug + 16'd1;
                smoke_probe_write_word_debug <= {8'd0, payload_tap_data};
                smoke_write_count_debug <= smoke_write_count_debug + 16'd1;
                first_byte0 <= first_byte0_next;
                first_byte1 <= first_byte1_next;
                first_byte2 <= first_byte2_next;
                first_byte3 <= first_byte3_next;
            end

            smoke_probe_write_index_debug <= 16'd0;
            smoke_base_addr_debug <= 16'd0;
            smoke_probe_write_word0_debug <= {first_byte0_next, first_byte1_next};
            smoke_probe_write_word6_debug <= {first_byte2_next, first_byte3_next};
            smoke_last_read_word0_debug <= {first_byte0_next, first_byte1_next};
            smoke_last_read_word1_debug <= {first_byte2_next, first_byte3_next};
            smoke_probe_write_flags_debug <= capture_status_debug;
            smoke_write_status_debug <= capture_status_debug;
            smoke_header_skip_count_debug <= {8'd0, type80_block_dest[7:0]};

            if (smoke_payload_present && !smoke_read_pending &&
                smoke_rd_req) begin
                smoke_read_pending <= 1'b1;
                smoke_read_addr_q <= smoke_rd_addr;
            end
            if (smoke_read_pending) begin
                smoke_read_pending <= 1'b0;
                smoke_rd_valid <= 1'b1;
                if (smoke_read_addr_q < TARGET_LEN) begin
                    smoke_rd_data <=
                        payload_ram[smoke_read_addr_q[PAYLOAD_ADDR_WIDTH-1:0]];
                    smoke_last_read_data_debug <=
                        payload_ram[smoke_read_addr_q[PAYLOAD_ADDR_WIDTH-1:0]];
                end else begin
                    smoke_rd_data <= 8'h80;
                    smoke_last_read_data_debug <= 8'h80;
                end
                smoke_last_read_index_debug <= smoke_read_addr_q[15:0];
                smoke_last_read_addr_debug <= smoke_read_addr_q[15:0];
                smoke_last_read_lane_debug <= {13'd0, smoke_read_addr_q[2:0]};
                smoke_last_read_word0_debug <= {first_byte0_next, first_byte1_next};
                smoke_last_read_word1_debug <= {first_byte2_next, first_byte3_next};
                smoke_read_count_debug <= smoke_read_count_debug + 16'd1;
            end
        end
    end

endmodule

// Minimal DDRAM backend for mode5 VGM loading/playback.
//
// This first version intentionally uses byte-write FIFO entries instead of
// 8-byte packing. It is simple and keeps parser/audio/session semantics out of
// scope. Later optimization can coalesce writes into full 64-bit words.

module vgm_ddram_backend #(
    parameter int ADDR_WIDTH        = 18,
    parameter bit ACCEPT_ANY_INDEX  = 1'b0,
    parameter logic [7:0] FILE_INDEX = 8'd0,
    parameter int DDRAM_ADDR_WIDTH  = 29,
    parameter logic [28:0] DDRAM_BASE_ADDR = 29'd0,
    parameter int WRITE_FIFO_DEPTH  = 64
) (
    input  logic                     clk,
    input  logic                     reset,

    input  logic                     ioctl_download,
    input  logic                     ioctl_wr,
    input  logic [31:0]              ioctl_addr,
    input  logic [7:0]               ioctl_dout,
    input  logic [7:0]               ioctl_index,

    input  logic                     mem_rd_req,
    input  logic [ADDR_WIDTH-1:0]    mem_rd_addr,
    output logic                     mem_rd_ready,
    output logic                     mem_rd_valid,
    output logic [7:0]               mem_rd_data,

    output logic                     load_busy,
    output logic                     load_done,
    output logic                     load_done_pulse,
    output logic                     load_error,
    output logic                     overflow_error,
    output logic [31:0]              file_size,
    output logic [31:0]              magic_debug,

    input  logic                     ddram_busy,
    output logic [7:0]               ddram_burstcnt,
    output logic [DDRAM_ADDR_WIDTH-1:0] ddram_addr,
    input  logic [63:0]              ddram_dout,
    input  logic                     ddram_dout_ready,
    output logic                     ddram_rd,
    output logic [63:0]              ddram_din,
    output logic [7:0]               ddram_be,
    output logic                     ddram_we
);

    localparam int FIFO_AW = (WRITE_FIFO_DEPTH <= 2) ? 1 : $clog2(WRITE_FIFO_DEPTH);
    localparam logic [FIFO_AW:0] FIFO_DEPTH_COUNT = WRITE_FIFO_DEPTH[FIFO_AW:0];
    localparam int BYTE_ADDR_WIDTH = DDRAM_ADDR_WIDTH + 3;

    typedef enum logic [0:0] {
        RD_IDLE = 1'b0,
        RD_WAIT = 1'b1
    } rd_state_t;

    logic ioctl_download_q;
    logic download_active;
    logic finish_pending;

    logic [DDRAM_ADDR_WIDTH-1:0] fifo_addr [0:WRITE_FIFO_DEPTH-1];
    logic [63:0]                 fifo_din  [0:WRITE_FIFO_DEPTH-1];
    logic [7:0]                  fifo_be   [0:WRITE_FIFO_DEPTH-1];
    logic [FIFO_AW-1:0]          fifo_wr_ptr;
    logic [FIFO_AW-1:0]          fifo_rd_ptr;
    logic [FIFO_AW:0]            fifo_count;

    logic [2:0]                  read_lane;
    rd_state_t                   rd_state;

    wire file_accept = ACCEPT_ANY_INDEX || (ioctl_index == FILE_INDEX);
    wire download_start = ioctl_download && !ioctl_download_q;
    wire download_end   = !ioctl_download && ioctl_download_q;

    wire fifo_empty = (fifo_count == '0);
    wire fifo_full  = (fifo_count >= FIFO_DEPTH_COUNT);

    wire accept_wr = ioctl_download && ioctl_wr && file_accept && download_active;
    wire write_pop = !fifo_empty && !ddram_busy;

    wire [31:0] ioctl_addr_plus_one = ioctl_addr + 32'd1;

    wire [DDRAM_ADDR_WIDTH-1:0] ioctl_word_addr =
        DDRAM_BASE_ADDR + ioctl_addr[BYTE_ADDR_WIDTH-1:3];

    wire [31:0] mem_rd_addr32 =
        {{(32-ADDR_WIDTH){1'b0}}, mem_rd_addr};

    wire [DDRAM_ADDR_WIDTH-1:0] read_word_addr =
        DDRAM_BASE_ADDR + mem_rd_addr32[BYTE_ADDR_WIDTH-1:3];

    wire read_can_accept =
        (rd_state == RD_IDLE) &&
        !ioctl_download &&
        !download_active &&
        !finish_pending &&
        fifo_empty &&
        !ddram_busy;

    assign mem_rd_ready = read_can_accept;
    assign load_busy = download_active || finish_pending || !fifo_empty;

    function automatic [7:0] lane_be(input logic [2:0] lane);
        begin
            case (lane)
                3'd0: lane_be = 8'h01;
                3'd1: lane_be = 8'h02;
                3'd2: lane_be = 8'h04;
                3'd3: lane_be = 8'h08;
                3'd4: lane_be = 8'h10;
                3'd5: lane_be = 8'h20;
                3'd6: lane_be = 8'h40;
                default: lane_be = 8'h80;
            endcase
        end
    endfunction

    function automatic [63:0] lane_din(
        input logic [7:0] byte_data,
        input logic [2:0] lane
    );
        begin
            lane_din = 64'd0;
            case (lane)
                3'd0: lane_din[7:0]   = byte_data;
                3'd1: lane_din[15:8]  = byte_data;
                3'd2: lane_din[23:16] = byte_data;
                3'd3: lane_din[31:24] = byte_data;
                3'd4: lane_din[39:32] = byte_data;
                3'd5: lane_din[47:40] = byte_data;
                3'd6: lane_din[55:48] = byte_data;
                default: lane_din[63:56] = byte_data;
            endcase
        end
    endfunction

    function automatic [7:0] lane_dout(
        input logic [63:0] word_data,
        input logic [2:0] lane
    );
        begin
            case (lane)
                3'd0: lane_dout = word_data[7:0];
                3'd1: lane_dout = word_data[15:8];
                3'd2: lane_dout = word_data[23:16];
                3'd3: lane_dout = word_data[31:24];
                3'd4: lane_dout = word_data[39:32];
                3'd5: lane_dout = word_data[47:40];
                3'd6: lane_dout = word_data[55:48];
                default: lane_dout = word_data[63:56];
            endcase
        end
    endfunction

    function automatic [FIFO_AW-1:0] fifo_ptr_inc(input logic [FIFO_AW-1:0] ptr);
        begin
            if (ptr == WRITE_FIFO_DEPTH[FIFO_AW-1:0] - {{(FIFO_AW-1){1'b0}}, 1'b1}) begin
                fifo_ptr_inc = '0;
            end else begin
                fifo_ptr_inc = ptr + {{(FIFO_AW-1){1'b0}}, 1'b1};
            end
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            ioctl_download_q <= 1'b0;
            download_active <= 1'b0;
            finish_pending <= 1'b0;

            fifo_wr_ptr <= '0;
            fifo_rd_ptr <= '0;
            fifo_count <= '0;

            rd_state <= RD_IDLE;
            read_lane <= 3'd0;

            mem_rd_valid <= 1'b0;
            mem_rd_data <= 8'd0;

            load_done <= 1'b0;
            load_done_pulse <= 1'b0;
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
            load_done_pulse <= 1'b0;

            ddram_burstcnt <= 8'd0;
            ddram_rd <= 1'b0;
            ddram_we <= 1'b0;
            ddram_be <= 8'd0;

            if (download_start) begin
                download_active <= file_accept;
                finish_pending <= 1'b0;

                fifo_wr_ptr <= '0;
                fifo_rd_ptr <= '0;
                fifo_count <= '0;

                rd_state <= RD_IDLE;
                read_lane <= 3'd0;

                mem_rd_valid <= 1'b0;
                mem_rd_data <= 8'd0;

                load_done <= 1'b0;
                load_done_pulse <= 1'b0;
                load_error <= 1'b0;
                overflow_error <= 1'b0;
                file_size <= 32'd0;
                magic_debug <= 32'd0;
            end else begin
                if (download_end && download_active) begin
                    download_active <= 1'b0;
                    finish_pending <= 1'b1;
                end

                if (write_pop) begin
                    ddram_burstcnt <= 8'd1;
                    ddram_addr <= fifo_addr[fifo_rd_ptr];
                    ddram_din <= fifo_din[fifo_rd_ptr];
                    ddram_be <= fifo_be[fifo_rd_ptr];
                    ddram_we <= 1'b1;
                    fifo_rd_ptr <= fifo_ptr_inc(fifo_rd_ptr);
                end

                if (accept_wr) begin
                    if (ioctl_addr >= (32'd1 << ADDR_WIDTH)) begin
                        overflow_error <= 1'b1;
                    end else if (fifo_full) begin
                        overflow_error <= 1'b1;
                    end else begin
                        fifo_addr[fifo_wr_ptr] <= ioctl_word_addr;
                        fifo_din[fifo_wr_ptr] <= lane_din(ioctl_dout, ioctl_addr[2:0]);
                        fifo_be[fifo_wr_ptr] <= lane_be(ioctl_addr[2:0]);
                        fifo_wr_ptr <= fifo_ptr_inc(fifo_wr_ptr);

                        if (ioctl_addr_plus_one > file_size) begin
                            file_size <= ioctl_addr_plus_one;
                        end

                        case (ioctl_addr[1:0])
                            2'd0: magic_debug[7:0] <= ioctl_dout;
                            2'd1: magic_debug[15:8] <= ioctl_dout;
                            2'd2: magic_debug[23:16] <= ioctl_dout;
                            2'd3: magic_debug[31:24] <= ioctl_dout;
                            default: begin end
                        endcase
                    end
                end

                case ({(accept_wr && !fifo_full &&
                        (ioctl_addr < (32'd1 << ADDR_WIDTH))), write_pop})
                    2'b10: fifo_count <= fifo_count + {{FIFO_AW{1'b0}}, 1'b1};
                    2'b01: fifo_count <= fifo_count - {{FIFO_AW{1'b0}}, 1'b1};
                    default: fifo_count <= fifo_count;
                endcase

                if (read_can_accept && mem_rd_req) begin
                    ddram_burstcnt <= 8'd1;
                    ddram_addr <= read_word_addr;
                    ddram_rd <= 1'b1;
                    read_lane <= mem_rd_addr[2:0];
                    rd_state <= RD_WAIT;
                end else if (rd_state == RD_WAIT && ddram_dout_ready) begin
                    mem_rd_data <= lane_dout(ddram_dout, read_lane);
                    mem_rd_valid <= 1'b1;
                    rd_state <= RD_IDLE;
                end

                if (finish_pending && fifo_empty) begin
                    finish_pending <= 1'b0;
                    load_done <= !overflow_error && !load_error;
                    load_done_pulse <= !overflow_error && !load_error;
                end
            end
        end
    end

endmodule

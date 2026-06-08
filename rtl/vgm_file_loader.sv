// BRAM-backed receiver for MiSTer hps_io file downloads.
//
// This is the first uncompressed VGM loading step. It only captures bytes and
// reports load status; playback continues to use the fixed-region path until a
// separate file player is added.

module vgm_file_loader #(
    parameter int ADDR_WIDTH = 18,
    parameter bit ACCEPT_ANY_INDEX = 1'b1,
    parameter logic [15:0] FILE_INDEX = 16'd0
) (
    input  logic                      clk,
    input  logic                      reset,

    input  logic                      ioctl_download,
    input  logic                      ioctl_wr,
    input  logic [26:0]               ioctl_addr,
    input  logic [7:0]                ioctl_dout,
    input  logic [15:0]               ioctl_index,

    input  logic [ADDR_WIDTH-1:0]     rd_addr,
    output logic [7:0]                rd_data,

    output logic                      load_busy,
    output logic                      load_done,
    output logic                      load_done_pulse,
    output logic                      load_error,
    output logic                      overflow_error,
    output logic [ADDR_WIDTH:0]       file_size,
    output logic [31:0]               magic_debug
);

    localparam int MEM_BYTES = 1 << ADDR_WIDTH;

    (* ramstyle = "M10K" *) logic [7:0] mem [0:MEM_BYTES-1];

    logic ioctl_download_d = 1'b0;
    logic active_download = 1'b0;
    logic selected_download = 1'b0;
    logic [ADDR_WIDTH:0] highest_written_plus_one = '0;
    logic [7:0] magic0 = 8'd0;
    logic [7:0] magic1 = 8'd0;
    logic [7:0] magic2 = 8'd0;
    logic [7:0] magic3 = 8'd0;

    wire download_start = ioctl_download && !ioctl_download_d;
    wire download_end = !ioctl_download && ioctl_download_d;
    wire index_matches = ACCEPT_ANY_INDEX || (ioctl_index == FILE_INDEX);
    wire addr_in_range = ioctl_addr[26:ADDR_WIDTH] == '0;
    wire [ADDR_WIDTH-1:0] wr_addr = ioctl_addr[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH:0] wr_next_size = {1'b0, wr_addr} + {{ADDR_WIDTH{1'b0}}, 1'b1};

    always_ff @(posedge clk) begin
        rd_data <= mem[rd_addr];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            ioctl_download_d <= 1'b0;
            active_download <= 1'b0;
            selected_download <= 1'b0;
            load_busy <= 1'b0;
            load_done <= 1'b0;
            load_done_pulse <= 1'b0;
            load_error <= 1'b0;
            overflow_error <= 1'b0;
            file_size <= '0;
            highest_written_plus_one <= '0;
            magic0 <= 8'd0;
            magic1 <= 8'd0;
            magic2 <= 8'd0;
            magic3 <= 8'd0;
        end else begin
            ioctl_download_d <= ioctl_download;
            load_done_pulse <= 1'b0;

            if (download_start) begin
                active_download <= 1'b1;
                selected_download <= index_matches;
                load_busy <= index_matches;
                load_done <= 1'b0;
                load_error <= 1'b0;
                overflow_error <= 1'b0;
                file_size <= '0;
                highest_written_plus_one <= '0;
                magic0 <= 8'd0;
                magic1 <= 8'd0;
                magic2 <= 8'd0;
                magic3 <= 8'd0;
            end

            if (active_download && selected_download && ioctl_download && ioctl_wr) begin
                if (addr_in_range) begin
                    mem[wr_addr] <= ioctl_dout;

                    if (wr_next_size > highest_written_plus_one) begin
                        highest_written_plus_one <= wr_next_size;
                    end

                    case (ioctl_addr)
                        27'd0: magic0 <= ioctl_dout;
                        27'd1: magic1 <= ioctl_dout;
                        27'd2: magic2 <= ioctl_dout;
                        27'd3: magic3 <= ioctl_dout;
                        default: begin
                        end
                    endcase
                end else begin
                    overflow_error <= 1'b1;
                    load_error <= 1'b1;
                end
            end

            if (download_end) begin
                active_download <= 1'b0;
                load_busy <= 1'b0;

                if (selected_download) begin
                    file_size <= highest_written_plus_one;
                    load_done <= (highest_written_plus_one != '0) && !overflow_error;
                    load_done_pulse <= (highest_written_plus_one != '0) && !overflow_error;
                    load_error <= (highest_written_plus_one == '0) || overflow_error;
                end

                selected_download <= 1'b0;
            end
        end
    end

    assign magic_debug = {magic3, magic2, magic1, magic0};

endmodule

`timescale 1ns/1ps

module tb_vgm_ddram_backend_segapcm_copy;
    localparam int ADDR_WIDTH = 8;
    localparam logic [28:0] VGM_BASE = {4'b0011, 25'd0};
    localparam logic [28:0] SEGAPCM_BASE = VGM_BASE + 29'h0010_0000;

    logic clk = 1'b0;
    logic reset = 1'b1;

    logic segapcm_copy_wr_req = 1'b0;
    wire segapcm_copy_wr_ready;
    logic [18:0] segapcm_copy_wr_addr = 19'd0;
    logic [7:0] segapcm_copy_wr_data = 8'd0;
    logic segapcm_copy_flush_req = 1'b0;
    wire segapcm_copy_flush_done;

    wire [7:0] ddram_burstcnt;
    wire [28:0] ddram_addr;
    wire [63:0] ddram_din;
    wire [7:0] ddram_be;
    wire ddram_rd;
    wire ddram_we;

    integer write_count = 0;
    integer timeout;

    vgm_ddram_backend #(
        .ADDR_WIDTH            (ADDR_WIDTH),
        .ACCEPT_ANY_INDEX      (1'b0),
        .FILE_INDEX            (8'd1),
        .DDRAM_BASE_ADDR       (VGM_BASE),
        .SEGAPCM_ROM_BASE_ADDR (SEGAPCM_BASE),
        .WRITE_FIFO_DEPTH      (8)
    ) dut (
        .clk                       (clk),
        .reset                     (reset),
        .ioctl_download            (1'b0),
        .ioctl_wr                  (1'b0),
        .ioctl_addr                (32'd0),
        .ioctl_dout                (8'd0),
        .ioctl_index               (8'd0),
        .ioctl_wait                (),
        .mem_rd_req                (1'b0),
        .mem_rd_addr               ({ADDR_WIDTH{1'b0}}),
        .mem_rd_ready              (),
        .mem_rd_valid              (),
        .mem_rd_data               (),
        .segapcm_copy_wr_req       (segapcm_copy_wr_req),
        .segapcm_copy_wr_ready     (segapcm_copy_wr_ready),
        .segapcm_copy_wr_addr      (segapcm_copy_wr_addr),
        .segapcm_copy_wr_data      (segapcm_copy_wr_data),
        .segapcm_copy_flush_req    (segapcm_copy_flush_req),
        .segapcm_copy_flush_done   (segapcm_copy_flush_done),
        .load_busy                 (),
        .load_done                 (),
        .load_done_pulse           (),
        .play_ready_pulse          (),
        .load_error                (),
        .overflow_error            (),
        .file_size                 (),
        .magic_debug               (),
        .ddram_busy                (1'b0),
        .ddram_burstcnt            (ddram_burstcnt),
        .ddram_addr                (ddram_addr),
        .ddram_dout                (64'd0),
        .ddram_dout_ready          (1'b0),
        .ddram_rd                  (ddram_rd),
        .ddram_din                 (ddram_din),
        .ddram_be                  (ddram_be),
        .ddram_we                  (ddram_we)
    );

    always #5 clk = ~clk;

    task automatic copy_byte(input logic [18:0] addr, input logic [7:0] data);
        begin
            segapcm_copy_wr_addr <= addr;
            segapcm_copy_wr_data <= data;
            segapcm_copy_wr_req <= 1'b1;
            do begin
                @(posedge clk);
            end while (!segapcm_copy_wr_ready);
            segapcm_copy_wr_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    always_ff @(posedge clk) begin
        if (reset) begin
            write_count <= 0;
        end else if (ddram_we) begin
            case (write_count)
                0: begin
                    if (ddram_addr != (SEGAPCM_BASE + 29'd2) ||
                        ddram_be != 8'h03 ||
                        ddram_din[15:0] != 16'hbbaa) begin
                        $display("FAIL first write addr=%08h be=%02h din=%016h",
                                 ddram_addr, ddram_be, ddram_din);
                        $finish;
                    end
                end
                1: begin
                    if (ddram_addr != (SEGAPCM_BASE + 29'd3) ||
                        ddram_be != 8'h01 ||
                        ddram_din[7:0] != 8'hcc) begin
                        $display("FAIL second write addr=%08h be=%02h din=%016h",
                                 ddram_addr, ddram_be, ddram_din);
                        $finish;
                    end
                end
                default: begin
                    $display("FAIL unexpected write addr=%08h be=%02h din=%016h",
                             ddram_addr, ddram_be, ddram_din);
                    $finish;
                end
            endcase
            write_count <= write_count + 1;
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        reset <= 1'b0;
        repeat (2) @(posedge clk);

        copy_byte(19'h00010, 8'haa);
        copy_byte(19'h00011, 8'hbb);
        copy_byte(19'h00018, 8'hcc);

        segapcm_copy_flush_req <= 1'b1;
        timeout = 0;
        while (!segapcm_copy_flush_done && timeout < 1000) begin
            timeout++;
            @(posedge clk);
        end
        segapcm_copy_flush_req <= 1'b0;

        if (!segapcm_copy_flush_done || write_count != 2) begin
            $display("FAIL flush_done=%0b writes=%0d",
                     segapcm_copy_flush_done, write_count);
            $finish;
        end

        $display("PASS tb_vgm_ddram_backend_segapcm_copy");
        $finish;
    end
endmodule

`timescale 1ns/1ps

module tb_vgm_ddram_backend_segapcm_copy_backpressure;
    localparam int ADDR_WIDTH = 8;
    localparam logic [28:0] VGM_BASE = {4'b0011, 25'd0};
    localparam logic [28:0] SEGAPCM_BASE = VGM_BASE + 29'h0010_0000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ddram_busy = 1'b1;

    logic segapcm_copy_wr_req = 1'b0;
    wire segapcm_copy_wr_ready;
    logic [18:0] segapcm_copy_wr_addr = 19'd0;
    logic [7:0] segapcm_copy_wr_data = 8'd0;
    logic segapcm_copy_flush_req = 1'b0;
    wire segapcm_copy_flush_done;
    wire overflow_error;
    wire ddram_we;

    int timeout;
    int writes_seen = 0;

    vgm_ddram_backend #(
        .ADDR_WIDTH            (ADDR_WIDTH),
        .ACCEPT_ANY_INDEX      (1'b0),
        .FILE_INDEX            (8'd1),
        .DDRAM_BASE_ADDR       (VGM_BASE),
        .SEGAPCM_ROM_BASE_ADDR (SEGAPCM_BASE),
        .WRITE_FIFO_DEPTH      (4)
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
        .overflow_error            (overflow_error),
        .file_size                 (),
        .magic_debug               (),
        .ddram_busy                (ddram_busy),
        .ddram_burstcnt            (),
        .ddram_addr                (),
        .ddram_dout                (64'd0),
        .ddram_dout_ready          (1'b0),
        .ddram_rd                  (),
        .ddram_din                 (),
        .ddram_be                  (),
        .ddram_we                  (ddram_we)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (reset) begin
            writes_seen <= 0;
        end else if (ddram_we) begin
            writes_seen <= writes_seen + 1;
        end
    end

    task automatic copy_byte(input logic [18:0] addr, input logic [7:0] data);
        begin
            segapcm_copy_wr_addr <= addr;
            segapcm_copy_wr_data <= data;
            segapcm_copy_wr_req <= 1'b1;
            timeout = 0;
            do begin
                timeout++;
                if (timeout == 1000) begin
                    $display("FAIL ready timeout addr=%05h overflow=%0b",
                             addr, overflow_error);
                    $finish;
                end
                @(posedge clk);
            end while (!segapcm_copy_wr_ready);
            segapcm_copy_wr_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset <= 1'b0;
        repeat (2) @(posedge clk);

        fork
            begin
                repeat (160) @(posedge clk);
                ddram_busy <= 1'b0;
            end
            begin
                for (int i = 0; i < 64; i++) begin
                    copy_byte(i[18:0], i[7:0]);
                    if (overflow_error) begin
                        $display("FAIL overflow during copy i=%0d", i);
                        $finish;
                    end
                end
            end
        join

        segapcm_copy_flush_req <= 1'b1;
        timeout = 0;
        while (!segapcm_copy_flush_done && timeout < 1000) begin
            timeout++;
            @(posedge clk);
        end
        segapcm_copy_flush_req <= 1'b0;

        if (!segapcm_copy_flush_done || overflow_error || writes_seen == 0) begin
            $display("FAIL flush=%0b overflow=%0b writes=%0d",
                     segapcm_copy_flush_done, overflow_error, writes_seen);
            $finish;
        end

        $display("PASS tb_vgm_ddram_backend_segapcm_copy_backpressure writes=%0d",
                 writes_seen);
        $finish;
    end
endmodule

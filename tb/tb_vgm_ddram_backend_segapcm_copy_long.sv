`timescale 1ns/1ps

module tb_vgm_ddram_backend_segapcm_copy_long;
    localparam int ADDR_WIDTH = 8;
    localparam int PAYLOAD_LEN = 32'h5a00;
    localparam int EXPECTED_WORDS = PAYLOAD_LEN / 8;
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
    wire [15:0] segapcm_copy_accept_count_debug;
    wire [15:0] segapcm_copy_write_count_debug;
    wire overflow_error;
    wire ddram_we;

    int timeout;
    int accepts_seen = 0;
    int writes_seen = 0;

    vgm_ddram_backend #(
        .ADDR_WIDTH            (ADDR_WIDTH),
        .ACCEPT_ANY_INDEX      (1'b0),
        .FILE_INDEX            (8'd1),
        .DDRAM_BASE_ADDR       (VGM_BASE),
        .SEGAPCM_ROM_BASE_ADDR (SEGAPCM_BASE),
        .WRITE_FIFO_DEPTH      (64)
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
        .segapcm_copy_accept_count_debug(segapcm_copy_accept_count_debug),
        .segapcm_copy_write_count_debug(segapcm_copy_write_count_debug),
        .segapcm_copy_fifo_debug   (),
        .segapcm_copy_ready_debug  (),
        .segapcm_copy_write_req_debug(),
        .segapcm_copy_word_debug   (),
        .segapcm_copy_flush_debug  (),
        .load_busy                 (),
        .load_done                 (),
        .load_done_pulse           (),
        .play_ready_pulse          (),
        .load_error                (),
        .overflow_error            (overflow_error),
        .file_size                 (),
        .magic_debug               (),
        .ddram_busy                (1'b0),
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
                    $display("FAIL ready timeout addr=%05h accepts=%0d writes=%0d overflow=%0b",
                             addr, accepts_seen, writes_seen, overflow_error);
                    $finish;
                end
                @(posedge clk);
            end while (!segapcm_copy_wr_ready);
            accepts_seen++;
            segapcm_copy_wr_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset <= 1'b0;
        repeat (2) @(posedge clk);

        for (int i = 0; i < PAYLOAD_LEN; i++) begin
            copy_byte(19'h32600 + i[18:0], i[7:0]);
        end

        segapcm_copy_flush_req <= 1'b1;
        timeout = 0;
        while (!segapcm_copy_flush_done && timeout < 1000) begin
            timeout++;
            @(posedge clk);
        end
        segapcm_copy_flush_req <= 1'b0;

        if (!segapcm_copy_flush_done ||
            overflow_error ||
            accepts_seen != PAYLOAD_LEN ||
            segapcm_copy_accept_count_debug != PAYLOAD_LEN[15:0] ||
            writes_seen != EXPECTED_WORDS ||
            segapcm_copy_write_count_debug != EXPECTED_WORDS[15:0]) begin
            $display("FAIL long copy flush=%0b overflow=%0b accepts=%0d/%0d dbg=%04h writes=%0d/%0d wdbg=%04h",
                     segapcm_copy_flush_done, overflow_error,
                     accepts_seen, PAYLOAD_LEN,
                     segapcm_copy_accept_count_debug,
                     writes_seen, EXPECTED_WORDS,
                     segapcm_copy_write_count_debug);
            $finish;
        end

        $display("PASS tb_vgm_ddram_backend_segapcm_copy_long accepts=%0d writes=%0d",
                 accepts_seen, writes_seen);
        $finish;
    end
endmodule

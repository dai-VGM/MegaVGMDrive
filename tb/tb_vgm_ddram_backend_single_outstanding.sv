`timescale 1ns/1ps

module tb_vgm_ddram_backend_single_outstanding;
    localparam int ADDR_WIDTH = 8;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic mem_rd_req = 1'b0;
    logic [ADDR_WIDTH-1:0] mem_rd_addr = '0;
    wire mem_rd_ready;
    wire mem_rd_valid;
    wire [7:0] mem_rd_data;
    logic ddram_dout_ready = 1'b0;
    logic [63:0] ddram_dout = 64'h8877665544332211;
    wire ddram_rd;

    integer accepted = 0;
    integer returned = 0;
    integer outstanding = 0;
    integer max_outstanding = 0;

    vgm_ddram_backend #(.ADDR_WIDTH(ADDR_WIDTH)) dut (
        .clk(clk), .reset(reset),
        .ioctl_download(1'b0), .ioctl_wr(1'b0), .ioctl_addr(32'd0),
        .ioctl_dout(8'd0), .ioctl_index(8'd0), .ioctl_wait(),
        .mem_rd_req(mem_rd_req), .mem_rd_addr(mem_rd_addr),
        .mem_rd_ready(mem_rd_ready), .mem_rd_valid(mem_rd_valid),
        .mem_rd_data(mem_rd_data),
        .segapcm_copy_wr_req(1'b0), .segapcm_copy_wr_ready(),
        .segapcm_copy_wr_addr(19'd0), .segapcm_copy_wr_data(8'd0),
        .segapcm_copy_flush_req(1'b0), .segapcm_copy_flush_done(),
        .load_busy(), .load_done(), .load_done_pulse(), .play_ready_pulse(),
        .load_error(), .overflow_error(), .file_size(), .magic_debug(),
        .ddram_busy(1'b0), .ddram_burstcnt(), .ddram_addr(),
        .ddram_dout(ddram_dout), .ddram_dout_ready(ddram_dout_ready),
        .ddram_rd(ddram_rd), .ddram_din(), .ddram_be(), .ddram_we()
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        integer next_outstanding;
        next_outstanding = outstanding;
        if (mem_rd_req && mem_rd_ready) begin
            accepted <= accepted + 1;
            next_outstanding = next_outstanding + 1;
        end
        if (mem_rd_valid) begin
            returned <= returned + 1;
            next_outstanding = next_outstanding - 1;
        end
        outstanding <= next_outstanding;
        if (next_outstanding > max_outstanding)
            max_outstanding <= next_outstanding;
        if (next_outstanding < 0 || next_outstanding > 1)
            $fatal(1, "backend outstanding=%0d", next_outstanding);
    end

    initial begin
        repeat (4) @(posedge clk);
        reset <= 1'b0;
        @(negedge clk);
        // The test bypasses downloading; make addresses 0x10/0x20 in-range.
        dut.file_size = 32'h0000_0100;
        mem_rd_addr = 8'h10;
        mem_rd_req = 1'b1;
        wait (mem_rd_ready);
        @(posedge clk);

        // Present a second request while the first DDR read is waiting.
        @(negedge clk);
        mem_rd_addr = 8'h20;
        repeat (5) begin
            @(posedge clk);
            if (mem_rd_ready)
                $fatal(1, "backend accepted a second outstanding request");
        end
        if (accepted != 1 || outstanding != 1)
            $fatal(1, "first request ownership lost accepted=%0d outstanding=%0d",
                   accepted, outstanding);

        @(negedge clk);
        ddram_dout_ready = 1'b1;
        @(negedge clk);
        ddram_dout_ready = 1'b0;
        wait (mem_rd_valid);
        @(posedge clk);
        wait (mem_rd_ready);
        @(posedge clk);

        if (accepted != 2 || returned != 1 || max_outstanding != 1)
            $fatal(1, "unexpected handshake accepted=%0d returned=%0d max=%0d",
                   accepted, returned, max_outstanding);
        $display("PASS tb_vgm_ddram_backend_single_outstanding max_outstanding=%0d",
                 max_outstanding);
        $finish;
    end
endmodule

`timescale 1ns/1ps

module tb_vgm_loaded_player_stale_valid;
    localparam int ADDR_WIDTH = 8;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic mem_rd_ready = 1'b1;
    logic mem_rd_valid = 1'b1;
    logic [7:0] mem_rd_data = 8'h83;

    wire mem_rd_req;
    wire [ADDR_WIDTH-1:0] mem_rd_addr;
    wire header_valid;
    wire player_error;
    wire [31:0] header_magic_read_debug;
    wire [3:0] header_magic_fail_index_debug;

    logic first_accept_seen = 1'b0;
    logic [ADDR_WIDTH-1:0] accepted_addr = '0;
    logic [1:0] response_delay = 2'd0;
    logic response_pending = 1'b0;

    always #5 clk = ~clk;

    vgm_loaded_player #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .YM2151_MODE  (1'b1)
    ) dut (
        .clk                   (clk),
        .reset                 (reset),
        .start                 (start),
        .load_done             (1'b1),
        .load_done_pulse       (1'b0),
        .load_error            (1'b0),
        .overflow_error        (1'b0),
        .file_size             (9'd128),
        .vgm_wait_tick         (1'b0),
        .mem_rd_req            (mem_rd_req),
        .mem_rd_addr           (mem_rd_addr),
        .mem_rd_ready          (mem_rd_ready),
        .mem_rd_valid          (mem_rd_valid),
        .mem_rd_data           (mem_rd_data),
        .segapcm_copy_wr_ready (1'b1),
        .segapcm_copy_flush_done(1'b1),
        .ym_cmd_ready          (1'b1),
        .psg_cmd_ready         (1'b1),
        .ym2151_cmd_ready      (1'b1),
        .header_valid          (header_valid),
        .player_error          (player_error),
        .header_magic_read_debug(header_magic_read_debug),
        .header_magic_fail_index_debug(header_magic_fail_index_debug)
    );

    function automatic [7:0] mem_byte(input logic [ADDR_WIDTH-1:0] addr);
        begin
            case (addr)
                8'h00: mem_byte = 8'h56;
                8'h01: mem_byte = 8'h67;
                8'h02: mem_byte = 8'h6d;
                8'h03: mem_byte = 8'h20;
                8'h1c: mem_byte = 8'h00;
                8'h1d: mem_byte = 8'h00;
                8'h1e: mem_byte = 8'h00;
                8'h1f: mem_byte = 8'h00;
                8'h34: mem_byte = 8'h00;
                8'h35: mem_byte = 8'h00;
                8'h36: mem_byte = 8'h00;
                8'h37: mem_byte = 8'h00;
                8'h40: mem_byte = 8'h66;
                default: mem_byte = 8'h00;
            endcase
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            mem_rd_valid <= 1'b1;
            mem_rd_data <= 8'h83;
            first_accept_seen <= 1'b0;
            response_pending <= 1'b0;
            response_delay <= 2'd0;
            accepted_addr <= '0;
        end else begin
            mem_rd_valid <= 1'b0;

            if (!first_accept_seen) begin
                mem_rd_valid <= 1'b1;
                mem_rd_data <= 8'h83;
            end

            if (mem_rd_req && mem_rd_ready) begin
                first_accept_seen <= 1'b1;
                accepted_addr <= mem_rd_addr;
                response_pending <= 1'b1;
                response_delay <= 2'd2;
            end

            if (response_pending) begin
                if (response_delay == 2'd0) begin
                    mem_rd_valid <= 1'b1;
                    mem_rd_data <= mem_byte(accepted_addr);
                    response_pending <= 1'b0;
                end else begin
                    response_delay <= response_delay - 2'd1;
                end
            end
        end
    end

    integer timeout;

    initial begin
        repeat (4) @(posedge clk);
        reset <= 1'b0;
        repeat (2) @(posedge clk);

        start <= 1'b1;
        timeout = 0;
        while (!header_valid && !player_error && (timeout < 1000)) begin
            @(posedge clk);
            timeout++;
        end
        start <= 1'b0;

        if (!header_valid) begin
            $display("FAIL header_valid=%0b error=%0b magic=%08h mf=%0d",
                     header_valid,
                     player_error,
                     header_magic_read_debug,
                     header_magic_fail_index_debug);
            $finish;
        end

        if (header_magic_read_debug != 32'h206d_6756) begin
            $display("FAIL stale valid consumed magic=%08h",
                     header_magic_read_debug);
            $finish;
        end

        $display("PASS tb_vgm_loaded_player_stale_valid magic=%08h",
                 header_magic_read_debug);
        $finish;
    end
endmodule

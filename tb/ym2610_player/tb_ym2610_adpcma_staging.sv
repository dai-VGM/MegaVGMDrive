`timescale 1ns/1ps

// Directed MMR staging matrix for the per-channel ADPCM-A address contract.
module tb_ym2610_adpcma_staging;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [7:0] din = 8'd0;
    reg write = 1'b0;
    reg [1:0] addr = 2'd0;
    wire [95:0] start_addr_a, end_addr_a;
    wire [5:0] up_start, up_end;

    always #5 clk = ~clk;

    ym2610_hw0_jt12_mmr #(.use_adpcm(1)) dut (
        .rst(rst), .clk(clk), .cen(1'b1), .din(din), .write(write),
        .addr(addr), .start_addr_a(start_addr_a), .end_addr_a(end_addr_a),
        .up_start(up_start), .up_end(up_end), .flag_A(1'b0),
        .overflow_A(1'b0), .aon_accept(1'b0)
    );

    task write_reg;
        input [7:0] reg_addr;
        input [7:0] value;
        begin
            @(negedge clk);
            write = 1'b1; addr = 2'd2; din = reg_addr;
            @(negedge clk);
            addr = 2'd3; din = value;
            @(negedge clk);
            write = 1'b0; addr = 2'd0; din = 8'd0;
        end
    endtask

    task check_hazard;
        input [7:0] end_high;
        input [15:0] expected;
        input [127:0] label;
        begin
            // ch2 start high, unrelated end high, then ch2 start low.
            write_reg(8'h1a, 8'h0a);
            write_reg(8'h2a, end_high);
            write_reg(8'h12, 8'he9);
            #1;
            if (!(up_start[2] && start_addr_a[47:32] == expected))
                $fatal(1, "%0s start=%h start_valid=%b end_valid=%b", label,
                       start_addr_a[47:32], up_start, up_end);
            $display("STAGING_%0s addr=%h", label, start_addr_a[47:32]);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;
        // Gun Frontier: previous end high must not corrupt ch2 start.
        check_hazard(8'h0b, 16'h0ae9, "GUN_FRONTIER");
        // The former masking case remains correct.
        check_hazard(8'h0a, 16'h0ae9, "MASKING_CONTROL");

        // Reverse interleave and distinct channels.  Both update classes stay
        // valid independently; no shared target or byte state remains.
        write_reg(8'h11, 8'h34); write_reg(8'h19, 8'h01);
        write_reg(8'h23, 8'h78); write_reg(8'h2b, 8'h02);
        if (!(up_start[1] && up_end[3] && start_addr_a[31:16] == 16'h0134 &&
              end_addr_a[63:48] == 16'h0278))
            $fatal(1, "INTERLEAVE start1=%h end3=%h valid=%b/%b",
                   start_addr_a[31:16], end_addr_a[63:48], up_start, up_end);

        @(negedge clk); rst = 1'b1;
        repeat (2) @(negedge clk);
        if (up_start != 6'd0 || up_end != 6'd0 || start_addr_a != 96'd0 ||
            end_addr_a != 96'd0)
            $fatal(1, "RESET_PENDING_STATE");
        $display("STAGING_MATRIX_PASS");
        $finish;
    end
endmodule

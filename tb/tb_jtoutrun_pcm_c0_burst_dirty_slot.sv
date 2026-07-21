`timescale 1ns/1ps

// A same-time C0 burst is serialized one write per SYS clock.  If the burst
// crosses a channel's state-0 config snapshot, the in-flight slot must not use
// a mixture of the old and new register image.
module tb_jtoutrun_pcm_c0_burst_dirty_slot;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg cen = 1'b1;
    reg [7:0] cpu_addr = 8'd0;
    reg [7:0] cpu_dout = 8'd0;
    reg cpu_cs = 1'b0;
    wire [18:0] rom_addr;
    wire rom_cs;
    integer timeout;
    integer request_count = 0;
    integer dirty_request_count = 0;
    integer dirty_writeback_count = 0;
    integer dirty_contribution_count = 0;
    integer burst_start_state = 0;
    reg dirty_window = 1'b0;
    reg signed [15:0] acc_l_before;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && rom_cs) begin
            request_count <= request_count + 1;
            if (dirty_window && dut.cur_ch == 4'd0)
                dirty_request_count <= dirty_request_count + 1;
        end
        if (!reset && dirty_window && dut.cur_ch == 4'd0 &&
            dut.cfg_we && dut.st >= 4'd8 && dut.st <= 4'd11)
            dirty_writeback_count <= dirty_writeback_count + 1;
        if (!reset && dirty_window && dut.cur_ch == 4'd0 &&
            dut.st == 4'd15 && dut.acc_l != acc_l_before)
            dirty_contribution_count <= dirty_contribution_count + 1;
    end

    task automatic cpu_write(input [7:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            cpu_addr = addr;
            cpu_dout = data;
            cpu_cs = 1'b1;
            @(negedge clk);
            cpu_cs = 1'b0;
        end
    endtask

    task automatic cpu_write_now(input [7:0] addr, input [7:0] data);
        begin
            cpu_addr = addr;
            cpu_dout = data;
            cpu_cs = 1'b1;
            @(negedge clk);
            cpu_cs = 1'b0;
        end
    endtask

    task automatic wait_ch0_state(input [3:0] wanted);
        begin : wait_loop
            for (timeout = 0; timeout < 10000; timeout = timeout + 1) begin
                @(negedge clk);
                if (dut.cur_ch == 4'd0 && dut.st == wanted)
                    disable wait_loop;
            end
            $fatal(1, "timeout waiting ch0 state %0d", wanted);
        end
    endtask

    task automatic wait_ch0_active;
        begin : wait_loop
            for (timeout = 0; timeout < 10000; timeout = timeout + 1) begin
                @(negedge clk);
                if (dut.active[0]) disable wait_loop;
            end
            $fatal(1, "timeout waiting ch0 active");
        end
    endtask

    jtoutrun_pcm #(
        .REQUIRE_CONTROL_WRITE_BEFORE_ENABLE(1'b1),
        .MAME_SCRATCH_CURRENT(1'b1),
        .MAME_NONLOOP_END(1'b1)
    ) dut (
        .rst(reset), .clk(clk), .cen(cen), .debug_bus(8'd0),
        .cpu_addr(cpu_addr), .cpu_dout(cpu_dout), .cpu_rnw(1'b0),
        .cpu_cs(cpu_cs),
        .smoke_variant(3'd0), .smoke_ddr_follow_mode(1'b0),
        .smoke_ddr_follow_init_enable(1'b0),
        .smoke_ddr_follow_delta_sel(3'd0),
        .smoke_c0_use_sel(2'd0), .smoke_c0_sample_mode(2'd0),
        .smoke_c0_delta(8'd0), .smoke_c0_vol_l(7'd0),
        .smoke_c0_vol_r(7'd0), .smoke_c0_raw_audible(1'b0),
        .smoke_c0_drive_sel(2'd0), .smoke_c0_seed_pulse(1'b0),
        .smoke_c0_endcmp_sel(2'd0), .smoke_c0_loopsrc_sel(2'd0),
        .smoke_c0_current_seed(24'd0), .smoke_c0_loop_seed(24'd0),
        .smoke_c0_end_addr(8'd0), .smoke_c0_ctrl(8'd0),
        .rom_addr(rom_addr), .rom_data(8'h7a), .rom_ok(1'b1),
        .rom_prefetch_clear(1'b0), .rom_cs(rom_cs)
    );

    initial begin
        if ($value$plusargs("BURST_START_STATE=%d", burst_start_state)) begin
        end

        // Old voice: active, non-loop, safely below its end page.
        cpu_write(8'h02, 8'h20);
        cpu_write(8'h03, 8'h20);
        cpu_write(8'h04, 8'h00);
        cpu_write(8'h05, 8'h40);
        cpu_write(8'h06, 8'h70);
        cpu_write(8'h07, 8'h80);
        cpu_write(8'h84, 8'h00);
        cpu_write(8'h85, 8'h40);
        cpu_write(8'h86, 8'h02);
        @(negedge clk);
        reset = 1'b0;
        cpu_write_now(8'h86, 8'h02);
        wait_ch0_active();

        wait_ch0_state(burst_start_state[3:0]);
        dirty_window = 1'b1;
        acc_l_before = dut.acc_l;
        // One serialized same-time burst.  Starting at state 0 makes the old
        // implementation load a mixed register image and still request/write.
        cpu_write_now(8'h02, 8'h30);
        cpu_write_now(8'h03, 8'h30);
        cpu_write_now(8'h84, 8'h00);
        cpu_write_now(8'h85, 8'h22);
        cpu_write_now(8'h06, 8'h30);
        cpu_write_now(8'h07, 8'h90);
        cpu_write_now(8'h86, 8'h02);
        wait_ch0_state(4'd15);
        @(negedge clk);
        dirty_window = 1'b0;

`ifdef EXPECT_DIRTY_SLOT_SUPPRESSED
        if (dirty_request_count != 0 || dirty_writeback_count != 0 ||
            dirty_contribution_count != 0)
            $fatal(1,
                "dirty slot leaked request=%0d writeback=%0d contribution=%0d phase=%0d",
                dirty_request_count, dirty_writeback_count,
                dirty_contribution_count, burst_start_state);
        wait_ch0_state(4'd8);
        #1;
        if (!rom_cs || rom_addr !== 19'h02200)
            $fatal(1,
                "clean next slot did not request new image phase=%0d cs=%0b addr=%05h",
                burst_start_state, rom_cs, rom_addr);
        $display("PASS dirty burst phase=%0d suppressed=%0d/%0d/%0d next=%05h",
            burst_start_state, dirty_request_count, dirty_writeback_count,
            dirty_contribution_count, rom_addr);
`else
        $display("DIRTY_BEFORE phase=%0d request=%0d writeback=%0d contribution=%0d cur=%06h cfg=%02h",
            burst_start_state, dirty_request_count, dirty_writeback_count,
            dirty_contribution_count, dut.cur_addr, dut.cfg_en);
        if (dirty_request_count == 0 && dirty_writeback_count == 0 &&
            dirty_contribution_count == 0)
            $fatal(1, "test failed to expose dirty-slot side effects");
`endif
        $finish;
    end
endmodule

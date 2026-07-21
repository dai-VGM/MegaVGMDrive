`timescale 1ns/1ps

// Reproduce CPU-next-config versus old-slot deferred writeback collisions.
// The CPU writes a new current/control while ch0's previous slot is still in
// states 0..7.  Those bytes must survive the old slot's states 8..11.
module tb_jtoutrun_pcm_c0_lifecycle_collision;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg cen = 1'b1;
    reg prefetch_clear = 1'b0;
    reg [7:0] cpu_addr = 8'd0;
    reg [7:0] cpu_dout = 8'd0;
    reg cpu_cs = 1'b0;
    wire [18:0] rom_addr;
    wire rom_cs;
    integer timeout;
    integer write_start_state = 5;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && cpu_cs) begin
            $display("LIFECYCLE_CPU st=%0d ch=%0d addr=%02h data=%02h ram_before=%02h",
                dut.st, dut.cur_ch, cpu_addr, cpu_dout,
                dut.u_ram.mem[{1'b0, cpu_addr}]);
        end
        if (!reset && dut.cur_ch == 4'd0 &&
            (dut.st == 4'd7 || dut.st == 4'd8)) begin
            $display("LIFECYCLE_STATE st=%0d cur=%06h end_data=%02h cfg=%02h match=%0b cpu=%0b/%02h/%02h pending=%0b cfg_we=%0b cfg_addr=%03h cfg_din=%02h",
                dut.st, dut.cur_addr, dut.cfg_data, dut.cfg_en,
                dut.normal_end_match, cpu_cs, cpu_addr, cpu_dout,
                dut.c0_ctrl_write_pending_i, dut.cfg_we,
                dut.cfg_ram_addr, dut.cfg_din);
        end
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
            for (timeout = 0; timeout < 2000; timeout = timeout + 1) begin
                @(negedge clk);
                if (dut.cur_ch == 4'd0 && dut.st == wanted)
                    disable wait_loop;
            end
            $fatal(1, "timeout waiting ch0 state %0d", wanted);
        end
    endtask

    task automatic wait_ch0_active;
        begin : wait_active_loop
            for (timeout = 0; timeout < 4000; timeout = timeout + 1) begin
                @(negedge clk);
                if (dut.active[0])
                    disable wait_active_loop;
            end
            $fatal(1, "timeout waiting ch0 active");
        end
    endtask

    jtoutrun_pcm #(
        .REQUIRE_CONTROL_WRITE_BEFORE_ENABLE(1'b1)
    ) dut (
        .rst(reset), .clk(clk), .cen(cen), .debug_bus(8'd0),
        .cpu_addr(cpu_addr), .cpu_dout(cpu_dout), .cpu_rnw(1'b0),
        .cpu_cs(cpu_cs),
        .smoke_variant(3'd0),
        .smoke_ddr_follow_mode(1'b0),
        .smoke_ddr_follow_init_enable(1'b0),
        .smoke_ddr_follow_delta_sel(3'd0),
        .smoke_c0_use_sel(2'd0), .smoke_c0_sample_mode(2'd0),
        .smoke_c0_delta(8'd0), .smoke_c0_vol_l(7'd0),
        .smoke_c0_vol_r(7'd0), .smoke_c0_raw_audible(1'b0),
        .smoke_c0_drive_sel(2'd0), .smoke_c0_seed_pulse(1'b0),
        .smoke_c0_endcmp_sel(2'd0), .smoke_c0_loopsrc_sel(2'd0),
        .smoke_c0_current_seed(24'd0), .smoke_c0_loop_seed(24'd0),
        .smoke_c0_end_addr(8'd0), .smoke_c0_ctrl(8'd0),
        .rom_addr(rom_addr), .rom_data(8'h7f), .rom_ok(1'b1),
        .rom_prefetch_clear(prefetch_clear), .rom_cs(rom_cs)
    );

    initial begin
        if ($value$plusargs("WRITE_START_STATE=%d", write_start_state)) begin
        end
        // Initialize the complete ch0 voice while reset holds the scanner.
        cpu_write(8'h00, 8'h00);
        cpu_write(8'h02, 8'h20);
        cpu_write(8'h03, 8'h20);
        cpu_write(8'h04, 8'h00);
        cpu_write(8'h05, 8'h40);
        cpu_write(8'h06, 8'h40);
        cpu_write(8'h07, 8'h80);
        cpu_write(8'h84, 8'h00);
        cpu_write(8'h85, 8'h40);
        cpu_write(8'h86, 8'h02); // enabled, non-loop
        @(negedge clk);
        reset = 1'b0;
        cpu_write_now(8'h86, 8'h02);
        wait_ch0_active();

        // Old ch0 slot starts exactly on its non-loop end page.  Arrange the
        // new control write on old-slot state 7, the cycle which also queues
        // the deferred internal disable for state 8.
        wait_ch0_state(write_start_state[3:0]);
        cpu_write_now(8'h84, 8'h00);
        cpu_write_now(8'h85, 8'h22);
        cpu_write_now(8'h86, 8'h02);

        // Inspect immediately after the old slot's deferred writeback window.
        wait_ch0_state(4'd12);
        #1;
        $display("LIFECYCLE_COLLISION current_ram=%02h%02h control=%02h cur=%06h wb_valid=%0b wb_ch=%0d ctrl_pending=%0b",
            dut.u_ram.mem[9'h085], dut.u_ram.mem[9'h084],
            dut.u_ram.mem[9'h086], dut.cur_addr,
            dut.wb_cur_valid_i, dut.wb_cur_ch_i,
            dut.c0_ctrl_write_pending_i);
        if ({dut.u_ram.mem[9'h085], dut.u_ram.mem[9'h084]} !== 16'h2200)
            $fatal(1, "old-slot writeback overwrote CPU current at phase %0d",
                   write_start_state);
        if (dut.u_ram.mem[9'h086] !== 8'h02)
            $fatal(1, "old-slot end writeback overwrote CPU control at phase %0d",
                   write_start_state);

        wait_ch0_state(4'd8);
        #1;
        if (dut.cfg_en[0] || dut.cur_addr[23:8] !== 16'h2200)
            $fatal(1,
                "restart did not load CPU config phase=%0d cfg=%02h cur=%06h",
                write_start_state, dut.cfg_en, dut.cur_addr);
        $display("PASS lifecycle phase=%0d current=2200 control=02 restart_cur=%06h",
            write_start_state, dut.cur_addr);
        $finish;
    end
endmodule

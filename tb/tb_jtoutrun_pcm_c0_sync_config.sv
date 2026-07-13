`timescale 1ns/1ps

// Focused RV0070 regression.  This deliberately instantiates the real
// jtframe dual-RAM implementation, whose q outputs are registered.
module tb_jtoutrun_pcm_c0_sync_config;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg cen = 1'b0;
    reg [2:0] cen_phase = 3'd0;
    reg [7:0] cpu_addr = 8'd0;
    reg [7:0] cpu_dout = 8'd0;
    reg cpu_cs = 1'b0;

    wire [18:0] rom_addr;
    wire rom_cs;
    wire normal_state8;
    wire normal_state14;
    wire [23:0] current_before;
    wire [7:0] current_delta;
    wire [15:0] active_cfg;
    wire [15:0] volume_lr;
    wire [15:0] loop_addr;
    wire [7:0] end_addr;
    wire internal_we;
    wire [8:0] internal_addr;

    integer timeout;
    integer control_overwrite_count = 0;
    reg [23:0] state8_current;
    reg [7:0] state8_delta;
    reg [7:0] state8_control;
    reg [15:0] state8_loop;
    reg [7:0] state8_end;

    always #25 clk = ~clk;

    // 20 MHz system clock with a repeating 4-high/1-low 16 MHz enable.
    // Consecutive cen cycles reproduce the hardware condition which exposed
    // the original one-state-early registered-RAM consumption.
    always @(negedge clk) begin
        if (reset) begin
            cen_phase = 3'd0;
            cen = 1'b0;
        end else begin
            cen = (cen_phase != 3'd4);
            cen_phase = (cen_phase == 3'd4) ? 3'd0 : cen_phase + 3'd1;
        end
    end

    always @(posedge clk) begin
        if (!reset && internal_we && internal_addr == 9'h09e) begin
            control_overwrite_count = control_overwrite_count + 1;
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

    task automatic expect_mem(input [8:0] addr, input [7:0] data);
        begin
            if (dut.u_ram.mem[addr] !== data) begin
                $display("FAIL RAM[%03h]: got %02h expected %02h",
                         addr, dut.u_ram.mem[addr], data);
                $fatal(1);
            end
        end
    endtask

    jtoutrun_pcm dut (
        .rst(reset),
        .clk(clk),
        .cen(cen),
        .debug_bus(8'd0),
        .cpu_addr(cpu_addr),
        .cpu_dout(cpu_dout),
        .cpu_rnw(1'b0),
        .cpu_cs(cpu_cs),
        .smoke_variant(3'd0),
        .smoke_ddr_follow_mode(1'b0),
        .smoke_ddr_follow_init_enable(1'b0),
        .smoke_ddr_follow_delta_sel(3'd0),
        .smoke_c0_use_sel(2'd0),
        .smoke_c0_sample_mode(2'd0),
        .smoke_c0_delta(8'd0),
        .smoke_c0_vol_l(7'd0),
        .smoke_c0_vol_r(7'd0),
        .smoke_c0_raw_audible(1'b0),
        .smoke_c0_drive_sel(2'd0),
        .smoke_c0_seed_pulse(1'b0),
        .smoke_c0_endcmp_sel(2'd0),
        .smoke_c0_loopsrc_sel(2'd0),
        .smoke_c0_current_seed(24'd0),
        .smoke_c0_loop_seed(24'd0),
        .smoke_c0_end_addr(8'd0),
        .smoke_c0_ctrl(8'd0),
        .rom_addr(rom_addr),
        .rom_data(8'h80),
        .rom_ok(1'b1),
        .rom_cs(rom_cs),
        .dbg_rv63_normal_state8_request_strobe(normal_state8),
        .dbg_rv63_normal_state14_consume_strobe(normal_state14),
        .dbg_rv65_normal_current_before(current_before),
        .dbg_rv65_normal_delta(current_delta),
        .dbg_active_cfg(active_cfg),
        .dbg_vol_lr(volume_lr),
        .dbg_rv68_loop_addr(loop_addr),
        .dbg_rv68_end_addr(end_addr),
        .dbg_rv69_internal_write_enable(internal_we),
        .dbg_rv69_internal_write_addr(internal_addr)
    );

    initial begin
        // Exact ch3 bytes reported by RV0069.  Port 0 writes remain active
        // during reset, while the PCM state machine stays at state 0.
        cpu_write(8'h18, 8'h0b); // current fraction/low
        cpu_write(8'h1a, 8'h09); // volume left
        cpu_write(8'h1b, 8'h09); // volume right
        cpu_write(8'h1c, 8'h00); // loop mid
        cpu_write(8'h1d, 8'h71); // loop high
        cpu_write(8'h1e, 8'h82); // end
        cpu_write(8'h1f, 8'ha0); // delta
        cpu_write(8'h9c, 8'h00); // current mid
        cpu_write(8'h9d, 8'h71); // current high
        cpu_write(8'h9e, 8'h12); // control: bank 1, enabled, no loop

        expect_mem(9'h018, 8'h0b);
        expect_mem(9'h01a, 8'h09);
        expect_mem(9'h01b, 8'h09);
        expect_mem(9'h01c, 8'h00);
        expect_mem(9'h01d, 8'h71);
        expect_mem(9'h01e, 8'h82);
        expect_mem(9'h01f, 8'ha0);
        expect_mem(9'h09c, 8'h00);
        expect_mem(9'h09d, 8'h71);
        expect_mem(9'h09e, 8'h12);

        @(negedge clk);
        reset = 1'b0;

        begin : wait_state8
            for (timeout = 0; timeout < 2000; timeout = timeout + 1) begin
                @(negedge clk);
                #1;
                if (normal_state8) begin
                    state8_current = current_before;
                    state8_delta = current_delta;
                    state8_control = active_cfg[7:0];
                    state8_loop = loop_addr;
                    state8_end = end_addr;
                    disable wait_state8;
                end
            end
            $display("FAIL: timed out waiting for normal ch3 state 8");
            $fatal(1);
        end

        if (state8_current !== 24'h71000b || state8_delta !== 8'ha0 ||
            state8_control !== 8'h12 || state8_loop !== 16'h7100 ||
            state8_end !== 8'h82) begin
            $display("FAIL state8 cur=%06h delta=%02h ctrl=%02h loop=%04h end=%02h",
                     state8_current, state8_delta, state8_control,
                     state8_loop, state8_end);
            $fatal(1);
        end

        @(posedge clk);
        #1;
        if (!rom_cs || rom_addr !== 19'h17100) begin
            $display("FAIL first ROM request cs=%b addr=%05h expected=17100",
                     rom_cs, rom_addr);
            $fatal(1);
        end

        begin : wait_state14
            for (timeout = 0; timeout < 200; timeout = timeout + 1) begin
                @(negedge clk);
                #1;
                if (normal_state14) begin
                    disable wait_state14;
                end
            end
            $display("FAIL: timed out waiting for normal ch3 state 14");
            $fatal(1);
        end

        if (volume_lr !== 16'h0909) begin
            $display("FAIL volumes=%04h expected=0909", volume_lr);
            $fatal(1);
        end
        if (control_overwrite_count != 0) begin
            $display("FAIL control overwrite count=%0d", control_overwrite_count);
            $fatal(1);
        end
        // States 9/10/11 must retain the already-proven current writeback:
        // 0x71000b + 0xa0 = 0x7100ab.
        expect_mem(9'h118, 8'hab);
        expect_mem(9'h09c, 8'h00);
        expect_mem(9'h09d, 8'h71);
        expect_mem(9'h09e, 8'h12);

        $display("PASS tb_jtoutrun_pcm_c0_sync_config");
        $finish;
    end
endmodule

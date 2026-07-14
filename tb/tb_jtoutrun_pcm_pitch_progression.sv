`timescale 1ns/1ps

module tb_jtoutrun_pcm_pitch_progression;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cen = 1'b0;
    logic [2:0] cen_phase = 3'd0;
    logic [7:0] cpu_addr = 8'd0;
    logic [7:0] cpu_dout = 8'd0;
    logic cpu_cs = 1'b0;
    logic rom_ok = 1'b1;

    wire [18:0] rom_addr;
    wire rom_cs;
    wire internal_we;

    integer i;
    integer timeout;
    integer update_count [0:3];
    integer request_count [0:3];
    reg [23:0] expected_addr [0:3];
    reg [7:0] expected_delta [0:3];
    reg [3:0] held_st;
    reg [3:0] held_ch;
    reg [23:0] held_addr;
    reg hold_valid = 1'b0;

    always #25 clk = ~clk;

    // Irregular enable stream also provides non-cen clocks on which every
    // playback state element must remain unchanged.
    always @(negedge clk) begin
        if (reset) begin
            cen_phase = 3'd0;
            cen = 1'b0;
        end else begin
            cen = (cen_phase != 3'd4);
            cen_phase = (cen_phase == 3'd4) ? 3'd0 : cen_phase + 3'd1;
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

    task automatic configure_channel(
        input [3:0] ch,
        input [23:0] start_addr,
        input [7:0] delta
    );
        reg [7:0] base;
        begin
            base = {ch, 3'b000};
            cpu_write(base + 8'h00, start_addr[7:0]);
            cpu_write(base + 8'h02, 8'h20);
            cpu_write(base + 8'h03, 8'h20);
            cpu_write(base + 8'h04, 8'h00);
            cpu_write(base + 8'h05, start_addr[23:16]);
            cpu_write(base + 8'h06, 8'hfe);
            cpu_write(base + 8'h07, delta);
            cpu_write(8'h84 + base, start_addr[15:8]);
            cpu_write(8'h85 + base, start_addr[23:16]);
            cpu_write(8'h86 + base, 8'h00);
        end
    endtask

    // Check the address immediately before every normal state-8 increment.
    // An unexpected second addition, including during a delayed ROM response,
    // is detected by the next expected-address comparison.
    always @(posedge clk) begin
        if (!reset && cen && dut.st == 4'd8 && dut.cur_ch < 4 &&
            !dut.cfg_en[0]) begin
            if (dut.cur_addr !== expected_addr[dut.cur_ch]) begin
                $display("FAIL ch%0d update%0d cur=%06h expected=%06h",
                         dut.cur_ch, update_count[dut.cur_ch], dut.cur_addr,
                         expected_addr[dut.cur_ch]);
                $fatal(1);
            end
            if (dut.delta !== expected_delta[dut.cur_ch]) begin
                $display("FAIL ch%0d delta=%02h expected=%02h",
                         dut.cur_ch, dut.delta, expected_delta[dut.cur_ch]);
                $fatal(1);
            end
            expected_addr[dut.cur_ch] =
                expected_addr[dut.cur_ch] + expected_delta[dut.cur_ch];
            update_count[dut.cur_ch] = update_count[dut.cur_ch] + 1;
        end
    end

    // Count the actual request edge independently from the state/address
    // monitor above. Every address increment must produce exactly one request.
    always @(posedge rom_cs) begin
        if (!reset && dut.cur_ch < 4)
            request_count[dut.cur_ch] = request_count[dut.cur_ch] + 1;
    end

    // Sample after nonblocking assignments. State, channel, and current
    // address are not allowed to move on a system-clock edge with cen low.
    always @(posedge clk) begin
        #1;
        if (!reset && hold_valid && !cen) begin
            if (dut.st !== held_st || dut.cur_ch !== held_ch ||
                dut.cur_addr !== held_addr || internal_we) begin
                $display("FAIL non-cen progress st=%0d/%0d ch=%0d/%0d cur=%06h/%06h we=%b",
                         dut.st, held_st, dut.cur_ch, held_ch,
                         dut.cur_addr, held_addr, internal_we);
                $fatal(1);
            end
        end
        held_st = dut.st;
        held_ch = dut.cur_ch;
        held_addr = dut.cur_addr;
        hold_valid = !reset;
    end

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
        .rom_ok(rom_ok),
        .rom_cs(rom_cs),
        .dbg_rv69_internal_write_enable(internal_we)
    );

    initial begin
        for (i = 0; i < 512; i = i + 1)
            dut.u_ram.mem[i] = 8'hff;
        for (i = 0; i < 4; i = i + 1) begin
            update_count[i] = 0;
            request_count[i] = 0;
        end

        expected_addr[0] = 24'h100000;
        expected_addr[1] = 24'h200000;
        expected_addr[2] = 24'h300000;
        expected_addr[3] = 24'h400000;
        expected_delta[0] = 8'h7d; // Stage Clear ch0
        expected_delta[1] = 8'h8a; // Stage Clear ch1
        expected_delta[2] = 8'h80; // rate reference
        expected_delta[3] = 8'ha0; // Stage Clear ch3

        configure_channel(4'd0, expected_addr[0], expected_delta[0]);
        configure_channel(4'd1, expected_addr[1], expected_delta[1]);
        configure_channel(4'd2, expected_addr[2], expected_delta[2]);
        configure_channel(4'd3, expected_addr[3], expected_delta[3]);

        @(negedge clk);
        reset = 1'b0;

        // Hold the response unavailable across more than one channel frame.
        // The normal JT request schedule must still add delta only at its one
        // state-8 update point, never on intervening system clocks.
        repeat (300) @(posedge clk);
        rom_ok = 1'b0;
        repeat (500) @(posedge clk);
        rom_ok = 1'b1;

        begin : wait_updates
            for (timeout = 0; timeout < 20000; timeout = timeout + 1) begin
                @(negedge clk);
                if (update_count[0] >= 16 && update_count[1] >= 16 &&
                    update_count[2] >= 16 && update_count[3] >= 16)
                    disable wait_updates;
            end
            $display("FAIL timeout counts=%0d,%0d,%0d,%0d",
                     update_count[0], update_count[1],
                     update_count[2], update_count[3]);
            $fatal(1);
        end

        for (i = 0; i < 4; i = i + 1) begin
            if (update_count[i] != request_count[i]) begin
                $display("FAIL ch%0d updates=%0d requests=%0d", i,
                         update_count[i], request_count[i]);
                $fatal(1);
            end
        end
        if (update_count[0] != update_count[1] ||
            update_count[0] != update_count[2] ||
            update_count[0] != update_count[3]) begin
            $display("FAIL unequal time scale counts=%0d,%0d,%0d,%0d",
                     update_count[0], update_count[1],
                     update_count[2], update_count[3]);
            $fatal(1);
        end

        $display("PASS tb_jtoutrun_pcm_pitch_progression updates=%0d advances=%0d,%0d,%0d,%0d",
                 update_count[0],
                 update_count[0] * expected_delta[0],
                 update_count[1] * expected_delta[1],
                 update_count[2] * expected_delta[2],
                 update_count[3] * expected_delta[3]);
        $finish;
    end
endmodule

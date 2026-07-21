`timescale 1ns/1ps

module tb_jtoutrun_pcm_after_burner_delta_cases;
    logic clk = 0, reset = 1, cen = 0;
    logic [2:0] cen_phase = 0;
    logic [7:0] cpu_addr = 0, cpu_dout = 0;
    logic cpu_cs = 0;
    wire [18:0] rom_addr;
    wire rom_cs;

    integer active_case = -1;
    integer count [0:1];
    integer precontrol_updates [0:1];
    logic capture [0:1];
    logic between_current_and_control [0:1];
    logic [18:0] captured [0:1][0:63];
    logic [7:0] case_delta;
    logic [23:0] case_current;
    logic [18:0] case_bank;
    integer timeout;

    always #25 clk = ~clk;
    always @(negedge clk) begin
        if (reset) begin
            cen_phase = 0;
            cen = 0;
        end else begin
            cen = cen_phase != 4;
            cen_phase = cen_phase == 4 ? 0 : cen_phase + 1;
        end
    end

    task automatic cpu_write(input [7:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            cpu_addr = addr;
            cpu_dout = data;
            cpu_cs = 1;
            @(negedge clk);
            cpu_cs = 0;
        end
    endtask

    task automatic configure_old(input integer ch);
        reg [7:0] base;
        begin
            base = ch << 3;
            cpu_write(base + 0, 8'h00);
            cpu_write(base + 2, ch == 0 ? 8'h20 : 8'h02);
            cpu_write(base + 3, ch == 0 ? 8'h02 : 8'h20);
            cpu_write(base + 4, 8'h00);
            cpu_write(base + 5, 8'h00);
            cpu_write(base + 6, 8'h03);
            cpu_write(base + 7, 8'h4a);
            cpu_write(8'h84 + base, 8'h00);
            cpu_write(8'h85 + base, 8'h00);
            cpu_write(8'h86 + base, 8'h52);
        end
    endtask

    task automatic trigger_channel(
        input integer ch,
        input [23:0] current,
        input [7:0] end_addr,
        input [7:0] delta,
        input [7:0] control
    );
        reg [7:0] base;
        begin
            base = ch << 3;
            cpu_write(base + 0, current[7:0]);
            cpu_write(base + 4, current[15:8]);
            cpu_write(8'h84 + base, current[15:8]);
            cpu_write(base + 5, current[23:16]);
            cpu_write(8'h85 + base, current[23:16]);
            between_current_and_control[ch] = 1;
            cpu_write(base + 6, end_addr);
            cpu_write(base + 7, delta);
            cpu_write(8'h86 + base, control);
            between_current_and_control[ch] = 0;
            capture[ch] = 1;
        end
    endtask

    always @(posedge clk) begin
        if (!reset && cen && dut.st == 8 && dut.cur_ch < 2 &&
            between_current_and_control[dut.cur_ch]) begin
            precontrol_updates[dut.cur_ch] =
                precontrol_updates[dut.cur_ch] + 1;
        end
    end

    always @(posedge rom_cs) begin
        integer ch;
        // Look-ahead requests are emitted at state 15 while cur_ch advances
        // to the next voice on the same edge. dbg_last_ch is the request tag.
        ch = dut.dbg_last_ch;
        if (!reset && ch < 2 && capture[ch] && count[ch] < 64) begin
            captured[ch][count[ch]] = rom_addr;
            if (dut.delta !== case_delta) begin
                $fatal(1, "case%0d ch%0d request%0d stale delta=%02h expected=%02h",
                       active_case, ch, count[ch], dut.delta, case_delta);
            end
            count[ch] = count[ch] + 1;
        end
    end

    task automatic run_case(
        input integer id,
        input [23:0] current,
        input [7:0] end_addr,
        input [7:0] delta,
        input [7:0] control,
        input [18:0] bank
    );
        logic [18:0] expected;
        begin
            reset = 1;
            capture[0] = 0; capture[1] = 0;
            between_current_and_control[0] = 0;
            between_current_and_control[1] = 0;
            count[0] = 0; count[1] = 0;
            precontrol_updates[0] = 0; precontrol_updates[1] = 0;
            active_case = id;
            case_current = current;
            case_delta = delta;
            case_bank = bank;
            for (integer i = 0; i < 512; i = i + 1)
                dut.u_ram.mem[i] = 8'hff;
            configure_old(0);
            configure_old(1);
            @(negedge clk);
            reset = 0;
            repeat (700) @(posedge clk);

            trigger_channel(0, current, end_addr, delta, control);
            trigger_channel(1, current, end_addr, delta, control);

            timeout = 0;
            while ((count[0] < 64 || count[1] < 64) && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (count[0] != 64 || count[1] != 64)
                $fatal(1, "case%0d request timeout count=%0d/%0d", id,
                       count[0], count[1]);
            if (dut.u_ram.mem[9'h007] !== delta ||
                dut.u_ram.mem[9'h00f] !== delta)
                $fatal(1, "case%0d delta RAM mismatch %02h/%02h expected=%02h",
                       id, dut.u_ram.mem[9'h007], dut.u_ram.mem[9'h00f], delta);

            for (integer ch = 0; ch < 2; ch = ch + 1) begin
                for (integer i = 0; i < 64; i = i + 1) begin
                    expected = bank | ((current + i * delta) >> 8);
                    if (captured[ch][i] !== expected)
                        $fatal(1, "case%0d ch%0d request%0d addr=%05h expected=%05h",
                               id, ch, i, captured[ch][i], expected);
                end
            end
            $display("CASE%0d delta=%02h ram=%02h/%02h precontrol_updates=%0d/%0d first=%05h last=%05h ch01_match=1",
                     id, delta, dut.u_ram.mem[9'h007], dut.u_ram.mem[9'h00f],
                     precontrol_updates[0], precontrol_updates[1],
                     captured[0][0], captured[0][63]);
        end
    endtask

    jtoutrun_pcm dut (
        .rst(reset), .clk(clk), .cen(cen), .debug_bus(8'd0),
        .cpu_addr(cpu_addr), .cpu_dout(cpu_dout), .cpu_rnw(1'b0),
        .cpu_cs(cpu_cs), .smoke_variant(3'd0),
        .smoke_ddr_follow_mode(1'b0), .smoke_ddr_follow_init_enable(1'b0),
        .smoke_ddr_follow_delta_sel(3'd0), .smoke_c0_use_sel(2'd0),
        .smoke_c0_sample_mode(2'd0), .smoke_c0_delta(8'd0),
        .smoke_c0_vol_l(7'd0), .smoke_c0_vol_r(7'd0),
        .smoke_c0_raw_audible(1'b0), .smoke_c0_drive_sel(2'd0),
        .smoke_c0_seed_pulse(1'b0), .smoke_c0_endcmp_sel(2'd0),
        .smoke_c0_loopsrc_sel(2'd0), .smoke_c0_current_seed(24'd0),
        .smoke_c0_loop_seed(24'd0), .smoke_c0_end_addr(8'd0),
        .smoke_c0_ctrl(8'd0), .rom_addr(rom_addr), .rom_data(8'h80),
        .rom_ok(1'b1), .rom_cs(rom_cs)
    );

    initial begin
        run_case(0, 24'hc00017, 8'hff, 8'h5a, 8'h22, 19'h20000);
        run_case(1, 24'h96001c, 8'hd5, 8'h5a, 8'h52, 19'h50000);
        run_case(2, 24'h96001c, 8'hd5, 8'h87, 8'h52, 19'h50000);
        $display("PASS tb_jtoutrun_pcm_after_burner_delta_cases");
        $finish;
    end
endmodule

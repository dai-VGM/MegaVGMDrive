`timescale 1ns/1ps

module tb_ym2203_sound_module;
    localparam logic [31:0] CLK_SYS_HZ = 32'd20_000_000;
    localparam integer CLOCK_WINDOW_CYCLES = 200_000;
    localparam integer WRITE_COUNT = 4;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] ym2203_clock = 32'd0;
    logic ym2203_clock_load = 1'b0;
    logic write_valid = 1'b0;
    logic [7:0] write_reg = 8'd0;
    logic [7:0] write_data = 8'd0;

    wire [31:0] clock_raw_debug;
    wire [31:0] effective_clock_hz_debug;
    wire clock_present_debug;
    wire chip_cen_debug;
    wire write_ready;
    wire write_accepted;
    wire write_completed;
    wire [31:0] write_accepted_count;
    wire [31:0] write_completed_count;
    wire transport_busy;
    wire core_busy;
    wire signed [15:0] raw_audio_l;
    wire signed [15:0] raw_audio_r;
    wire signed [15:0] raw_fm_audio;
    wire [9:0] raw_psg_audio;
    wire raw_sample_valid;

    logic [7:0] expected_reg [0:WRITE_COUNT-1];
    logic [7:0] expected_data [0:WRITE_COUNT-1];
    integer sys_cycle = 0;
    integer address_write_count = 0;
    integer data_write_count = 0;
    integer bus_pair_index = 0;
    integer last_bus_write_cycle = -100;
    integer busy_assert_count = 0;
    integer completion_count_seen = 0;
    logic waiting_for_busy = 1'b0;
    logic busy_seen_for_write = 1'b0;
    logic monitor_raw = 1'b0;
    logic cen_previous = 1'b0;

    always #25 clk = ~clk;

    ym2203_sound_module #(
        .CLK_SYS_HZ (CLK_SYS_HZ),
        .BUSY_TIMEOUT_CYCLES (100_000)
    ) dut (
        .clk                        (clk),
        .reset                      (reset),
        .ym2203_clock               (ym2203_clock),
        .ym2203_clock_load          (ym2203_clock_load),
        .clock_raw_debug            (clock_raw_debug),
        .effective_clock_hz_debug   (effective_clock_hz_debug),
        .clock_present_debug        (clock_present_debug),
        .chip_cen_debug             (chip_cen_debug),
        .write_valid                (write_valid),
        .write_reg                  (write_reg),
        .write_data                 (write_data),
        .write_ready                (write_ready),
        .write_accepted             (write_accepted),
        .write_completed            (write_completed),
        .write_accepted_count       (write_accepted_count),
        .write_completed_count      (write_completed_count),
        .transport_busy             (transport_busy),
        .core_busy                  (core_busy),
        .raw_audio_l                (raw_audio_l),
        .raw_audio_r                (raw_audio_r),
        .raw_fm_audio               (raw_fm_audio),
        .raw_psg_audio              (raw_psg_audio),
        .raw_sample_valid           (raw_sample_valid)
    );

    task automatic fail_now(input string reason);
        begin
            $display("FAIL cycle=%0d reason=%s", sys_cycle, reason);
            $fatal(1);
        end
    endtask

    task automatic load_clock(input logic [31:0] value);
        begin
            @(negedge clk);
            ym2203_clock = value;
            ym2203_clock_load = 1'b1;
            @(posedge clk);
            #1;
            if (chip_cen_debug !== 1'b0)
                fail_now("CEN was not cleared by clock_load");
            @(negedge clk);
            ym2203_clock_load = 1'b0;
        end
    endtask

    task automatic measure_clock(
        input logic [31:0] raw_clock,
        input logic [31:0] expected_effective
    );
        integer pulses;
        integer i;
        longint expected_pulses;
        begin
            load_clock(raw_clock);
            if (clock_raw_debug !== raw_clock)
                fail_now("raw clock latch mismatch");
            if (effective_clock_hz_debug !== expected_effective)
                fail_now("effective clock mismatch");
            if (clock_present_debug !== (expected_effective != 0))
                fail_now("clock present mismatch");

            pulses = 0;
            for (i = 0; i < CLOCK_WINDOW_CYCLES; i = i + 1) begin
                @(posedge clk);
                #1;
                if (chip_cen_debug)
                    pulses = pulses + 1;
            end
            expected_pulses =
                (longint'(CLOCK_WINDOW_CYCLES) * expected_effective) /
                CLK_SYS_HZ;
            if (pulses != expected_pulses)
                fail_now("fractional CEN pulse count mismatch");
            $display("CLOCK raw=%0d effective=%0d cycles=%0d pulses=%0d ideal_num_remainder=%0d",
                     raw_clock, expected_effective, CLOCK_WINDOW_CYCLES,
                     pulses,
                     (longint'(CLOCK_WINDOW_CYCLES) * expected_effective) %
                     CLK_SYS_HZ);
        end
    endtask

    task automatic send_absent_write;
        begin
            @(negedge clk);
            write_reg = 8'h22;
            write_data = 8'h00;
            write_valid = 1'b1;
            @(posedge clk);
            #1;
            if (!write_accepted || !write_completed)
                fail_now("absent-chip write was not consumed immediately");
            @(negedge clk);
            write_valid = 1'b0;
            if (!write_ready || transport_busy)
                fail_now("absent-chip write left transport stalled");
        end
    endtask

    task automatic send_continuous_writes;
        integer next_write;
        integer timeout;
        begin
            next_write = 0;
            timeout = 0;
            @(negedge clk);
            write_reg = expected_reg[0];
            write_data = expected_data[0];
            write_valid = 1'b1;
            while (next_write < WRITE_COUNT) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
                if (timeout > 500_000)
                    fail_now("continuous write producer timeout");
                if (write_accepted) begin
                    next_write = next_write + 1;
                    @(negedge clk);
                    if (next_write < WRITE_COUNT) begin
                        write_reg = expected_reg[next_write];
                        write_data = expected_data[next_write];
                    end else begin
                        write_valid = 1'b0;
                    end
                end
            end
            timeout = 0;
            while (write_completed_count != WRITE_COUNT + 1) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 100_000)
                    fail_now("final write completion timeout");
            end
        end
    endtask

    task automatic measure_audio_activity;
        integer samples;
        integer changes;
        integer timeout;
        logic signed [15:0] previous;
        logic have_previous;
        begin
            samples = 0;
            changes = 0;
            timeout = 0;
            previous = 16'sd0;
            have_previous = 1'b0;
            while (samples < 100_000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
                if (timeout > 200_000)
                    fail_now("raw audio sample timeout");
                if (have_previous && raw_audio_l != previous)
                    changes = changes + 1;
                previous = raw_audio_l;
                have_previous = 1'b1;
                samples = samples + 1;
            end
            $display("AUDIO samples=%0d changes=%0d last=%0d psg=%0d",
                     samples, changes, raw_audio_l, raw_psg_audio);
            if (changes == 0)
                fail_now("SSG tone produced no public raw-audio activity");
        end
    endtask

    // Observe the bus at the active edge, before the transport advances its
    // registered state. This is the exact bus image sampled by jt12_top.
    always @(posedge clk) begin
        sys_cycle <= sys_cycle + 1;
        if (!reset && !dut.jt12_cs_n && !dut.jt12_wr_n) begin
            if (sys_cycle - last_bus_write_cycle < 2)
                fail_now("missing full idle cycle between bus writes");
            last_bus_write_cycle = sys_cycle;
            if (dut.jt12_addr == 2'b00) begin
                if (bus_pair_index >= WRITE_COUNT ||
                    dut.jt12_din !== expected_reg[bus_pair_index])
                    fail_now("address write order/data mismatch");
                address_write_count = address_write_count + 1;
            end else if (dut.jt12_addr == 2'b01) begin
                if (bus_pair_index >= WRITE_COUNT ||
                    dut.jt12_din !== expected_data[bus_pair_index])
                    fail_now("data write order/data mismatch");
                data_write_count = data_write_count + 1;
                bus_pair_index = bus_pair_index + 1;
                waiting_for_busy = 1'b1;
                busy_seen_for_write = 1'b0;
            end else begin
                fail_now("unexpected YM2203 bus address");
            end
        end
    end

    always @(posedge clk) begin
        #1;
        if (reset || ym2203_clock_load) begin
            cen_previous = 1'b0;
        end else begin
            if (chip_cen_debug && cen_previous)
                fail_now("consecutive CEN pulses");
            cen_previous = chip_cen_debug;
        end

        if (!reset && waiting_for_busy && core_busy && !busy_seen_for_write) begin
            busy_seen_for_write = 1'b1;
            busy_assert_count = busy_assert_count + 1;
        end
        if (!reset && write_completed && waiting_for_busy) begin
            if (!busy_seen_for_write)
                fail_now("write completed without observing busy assert");
            waiting_for_busy = 1'b0;
            completion_count_seen = completion_count_seen + 1;
        end
        if (!reset && monitor_raw) begin
            if ((^{core_busy, raw_audio_l, raw_audio_r,
                   raw_fm_audio, raw_psg_audio, raw_sample_valid}) === 1'bx)
                begin
                    $display("RAW_X core_busy=%b left=%h right=%h fm=%h psg=%h sample=%b",
                             core_busy, raw_audio_l, raw_audio_r,
                             raw_fm_audio, raw_psg_audio, raw_sample_valid);
                    fail_now("X/Z on public raw audio or status");
                end
            if (raw_audio_l !== raw_audio_r)
                fail_now("YM2203 public raw left/right mismatch");
        end
    end

    initial begin
        expected_reg[0] = 8'h00;
        expected_data[0] = 8'h20;
        expected_reg[1] = 8'h01;
        expected_data[1] = 8'h00;
        expected_reg[2] = 8'h07;
        expected_data[2] = 8'h3e;
        expected_reg[3] = 8'h08;
        expected_data[3] = 8'h0f;

        repeat (8) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        measure_clock(32'd4_000_000, 32'd4_000_000);
        measure_clock(32'd3_579_545, 32'd3_579_545);
        measure_clock(32'd3_123_457, 32'd3_123_457);
        measure_clock(32'd25_000_000, 32'd10_000_000);
        measure_clock(32'd0, 32'd0);
        repeat (100) @(posedge clk);
        if (chip_cen_debug !== 1'b0)
            fail_now("clock zero did not stop CEN");
        send_absent_write();
        if (address_write_count != 0 || data_write_count != 0)
            fail_now("absent-chip write reached core bus");

        // The upper two VGM flag bits are not part of the chip frequency.
        load_clock(32'hc03d_0900);
        if (clock_raw_debug !== 32'hc03d_0900 ||
            effective_clock_hz_debug !== 32'd4_000_000)
            fail_now("VGM clock flag masking mismatch");
        repeat (128) @(posedge clk);
        monitor_raw = 1'b1;
        send_continuous_writes();
        repeat (4000) @(posedge clk);
        measure_audio_activity();

        if (write_accepted_count != WRITE_COUNT + 1 ||
            write_completed_count != WRITE_COUNT + 1)
            fail_now("accepted/completed count mismatch");
        if (address_write_count != WRITE_COUNT ||
            data_write_count != WRITE_COUNT || bus_pair_index != WRITE_COUNT)
            fail_now("bus write loss or duplicate");
        if (busy_assert_count != WRITE_COUNT ||
            completion_count_seen != WRITE_COUNT)
            fail_now("busy/completion observation count mismatch");
        if (!write_ready || transport_busy || core_busy)
            fail_now("transport/core not idle at end of test");

        $display("PASS tb_ym2203_sound_module accepted=%0d completed=%0d address=%0d data=%0d busy=%0d",
                 write_accepted_count, write_completed_count,
                 address_write_count, data_write_count, busy_assert_count);
        $finish;
    end
endmodule

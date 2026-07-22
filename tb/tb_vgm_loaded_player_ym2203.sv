`timescale 1ns/1ps

module tb_vgm_loaded_player_ym2203 #(
    parameter logic [31:0] CHIP_CLK_HZ = 32'd4_000_000
);
    localparam int ADDR_WIDTH = 10;
    localparam logic [31:0] CLK_SYS_HZ = 32'd20_000_000;
    localparam int DATA_START = 16'h0080;
    localparam int MAX_WRITES = 64;
    localparam int EXPECTED_WAIT_TICKS = 5_500;
    localparam int EXPECTED_WAIT_COMMANDS = 4;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic load_done = 1'b0;
    logic load_done_pulse = 1'b0;
    logic vgm_wait_tick = 1'b0;
    logic [5:0] wait_divider = 6'd0;
    logic [ADDR_WIDTH:0] file_size;

    wire mem_rd_req;
    wire [ADDR_WIDTH-1:0] mem_rd_addr;
    logic mem_rd_ready = 1'b1;
    logic mem_rd_valid = 1'b0;
    logic [7:0] mem_rd_data = 8'd0;
    logic pending = 1'b0;
    logic [7:0] pending_data = 8'd0;
    logic [7:0] mem [0:(1 << ADDR_WIDTH)-1];

    wire ym2203_cmd_valid;
    wire ym2203_cmd_ready;
    wire [7:0] ym2203_cmd_reg;
    wire [7:0] ym2203_cmd_data;
    wire [31:0] ym2203_clock;
    wire ym2203_clock_load;
    wire [31:0] ym2203_write_count;
    wire [7:0] ym2203_last_reg;
    wire [7:0] ym2203_last_data;
    wire busy;
    wire done;
    wire header_valid;
    wire player_error;
    wire end_command_seen;
    wire [31:0] parser_command_count_debug;
    wire [31:0] wait_ticks_consumed_debug;
    wire [ADDR_WIDTH-1:0] current_pc_debug;
    wire [ADDR_WIDTH-1:0] done_pc_debug;

    wire [31:0] clock_raw_debug;
    wire [31:0] effective_clock_hz_debug;
    wire clock_present_debug;
    wire chip_cen_debug;
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

    logic [7:0] expected_reg [0:MAX_WRITES-1];
    logic [7:0] expected_data [0:MAX_WRITES-1];
    integer build_pc;
    integer expected_write_count;
    integer expected_end_pc;
    integer sys_cycle = 0;
    integer address_write_count = 0;
    integer data_write_count = 0;
    integer bus_pair_index = 0;
    integer busy_assert_count = 0;
    integer busy_clear_count = 0;
    integer busy_assert_delay_sum = 0;
    integer busy_clear_delay_sum = 0;
    integer data_write_cycle = 0;
    logic waiting_for_busy = 1'b0;
    logic busy_seen_for_write = 1'b0;
    integer parser_stall_cycles = 0;
    integer transport_busy_cycles = 0;
    integer cen_active_cycles = 0;
    integer cen_pulse_count = 0;
    logic cen_previous = 1'b0;
    logic raw_monitor_enable = 1'b0;

    typedef enum integer {
        AUDIO_IDLE,
        AUDIO_SSG_ON,
        AUDIO_SSG_MUTED,
        AUDIO_FM_ON,
        AUDIO_FM_OFF
    } audio_phase_t;
    audio_phase_t audio_phase = AUDIO_IDLE;

    integer ssg_on_samples = 0;
    integer ssg_on_changes = 0;
    integer ssg_muted_samples = 0;
    integer ssg_muted_changes = 0;
    integer fm_on_samples = 0;
    integer fm_on_changes = 0;
    integer fm_off_samples = 0;
    integer fm_off_changes = 0;
    logic signed [15:0] phase_previous = 16'sd0;
    logic phase_has_previous = 1'b0;

    always #25 clk = ~clk;

    task automatic fail_now(input string reason);
        begin
            $display("FAIL clock=%0d cycle=%0d pc=%0h reason=%s",
                     CHIP_CLK_HZ, sys_cycle, current_pc_debug, reason);
            $fatal(1);
        end
    endtask

    task automatic emit_byte(input logic [7:0] value);
        begin
            mem[build_pc] = value;
            build_pc = build_pc + 1;
        end
    endtask

    task automatic emit_ym2203_write(
        input logic [7:0] reg_addr,
        input logic [7:0] reg_data
    );
        begin
            if (expected_write_count >= MAX_WRITES)
                fail_now("synthetic write list overflow");
            expected_reg[expected_write_count] = reg_addr;
            expected_data[expected_write_count] = reg_data;
            expected_write_count = expected_write_count + 1;
            emit_byte(8'h55);
            emit_byte(reg_addr);
            emit_byte(reg_data);
        end
    endtask

    task automatic emit_wait(input integer samples);
        begin
            emit_byte(8'h61);
            emit_byte(samples[7:0]);
            emit_byte(samples[15:8]);
        end
    endtask

    vgm_loaded_player #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .YM2151_MODE (1'b0)
    ) parser (
        .clk                         (clk),
        .reset                       (reset),
        .start                       (1'b0),
        .load_done                   (load_done),
        .load_done_pulse             (load_done_pulse),
        .load_error                  (1'b0),
        .overflow_error              (1'b0),
        .file_size                   (file_size),
        .vgm_wait_tick               (vgm_wait_tick),
        .mem_rd_req                  (mem_rd_req),
        .mem_rd_addr                 (mem_rd_addr),
        .mem_rd_ready                (mem_rd_ready),
        .mem_rd_valid                (mem_rd_valid),
        .mem_rd_data                 (mem_rd_data),
        .segapcm_copy_wr_ready       (1'b1),
        .segapcm_copy_flush_done     (1'b1),
        .ym_cmd_ready                (1'b1),
        .psg_cmd_ready               (1'b1),
        .ym2151_cmd_ready            (1'b1),
        .ym2203_cmd_ready            (ym2203_cmd_ready),
        .ym2203_cmd_valid            (ym2203_cmd_valid),
        .ym2203_cmd_reg              (ym2203_cmd_reg),
        .ym2203_cmd_data             (ym2203_cmd_data),
        .busy                        (busy),
        .done                        (done),
        .header_valid                (header_valid),
        .ym2203_clock                (ym2203_clock),
        .ym2203_clock_load           (ym2203_clock_load),
        .player_error                (player_error),
        .current_pc_debug            (current_pc_debug),
        .end_command_seen            (end_command_seen),
        .wait_ticks_consumed_debug   (wait_ticks_consumed_debug),
        .ym2203_write_count          (ym2203_write_count),
        .ym2203_last_reg             (ym2203_last_reg),
        .ym2203_last_data            (ym2203_last_data),
        .parser_command_count_debug  (parser_command_count_debug),
        .done_pc_debug               (done_pc_debug)
    );

    ym2203_sound_module #(
        .CLK_SYS_HZ (CLK_SYS_HZ),
        .BUSY_TIMEOUT_CYCLES (100_000)
    ) sound (
        .clk                        (clk),
        .reset                      (reset),
        .ym2203_clock               (ym2203_clock),
        .ym2203_clock_load          (ym2203_clock_load),
        .clock_raw_debug            (clock_raw_debug),
        .effective_clock_hz_debug   (effective_clock_hz_debug),
        .clock_present_debug        (clock_present_debug),
        .chip_cen_debug             (chip_cen_debug),
        .write_valid                (ym2203_cmd_valid),
        .write_reg                  (ym2203_cmd_reg),
        .write_data                 (ym2203_cmd_data),
        .write_ready                (ym2203_cmd_ready),
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

    always_ff @(posedge clk) begin
        if (reset) begin
            wait_divider <= 6'd0;
            vgm_wait_tick <= 1'b0;
        end else if (wait_divider == 6'd63) begin
            wait_divider <= 6'd0;
            vgm_wait_tick <= 1'b1;
        end else begin
            wait_divider <= wait_divider + 6'd1;
            vgm_wait_tick <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            pending <= 1'b0;
            pending_data <= 8'd0;
            mem_rd_ready <= 1'b1;
            mem_rd_valid <= 1'b0;
            mem_rd_data <= 8'd0;
        end else begin
            mem_rd_valid <= 1'b0;
            mem_rd_ready <= !pending;
            if (pending) begin
                mem_rd_data <= pending_data;
                mem_rd_valid <= 1'b1;
                pending <= 1'b0;
            end
            if (mem_rd_req && mem_rd_ready) begin
                pending_data <= mem[mem_rd_addr];
                pending <= 1'b1;
            end
        end
    end

    // Observe the exact bus values sampled by jt12_top at this active edge.
    always @(posedge clk) begin
        sys_cycle <= sys_cycle + 1;
        if (!reset && !sound.jt12_cs_n && !sound.jt12_wr_n) begin
            if (sound.jt12_addr == 2'b00) begin
                if (bus_pair_index >= expected_write_count ||
                    sound.jt12_din !== expected_reg[bus_pair_index])
                    fail_now("core address write order mismatch");
                address_write_count = address_write_count + 1;
            end else if (sound.jt12_addr == 2'b01) begin
                if (bus_pair_index >= expected_write_count ||
                    sound.jt12_din !== expected_data[bus_pair_index])
                    fail_now("core data write order mismatch");
                data_write_count = data_write_count + 1;
                bus_pair_index = bus_pair_index + 1;
                data_write_cycle = sys_cycle;
                waiting_for_busy = 1'b1;
                busy_seen_for_write = 1'b0;
            end else begin
                fail_now("unexpected core bus address");
            end
        end
    end

    always @(posedge clk) begin
        #1;
        if (reset || ym2203_clock_load) begin
            cen_active_cycles = 0;
            cen_pulse_count = 0;
            cen_previous = 1'b0;
        end else if (clock_present_debug) begin
            cen_active_cycles = cen_active_cycles + 1;
            if (chip_cen_debug)
                cen_pulse_count = cen_pulse_count + 1;
            if (chip_cen_debug && cen_previous)
                fail_now("consecutive chip CEN pulses");
            cen_previous = chip_cen_debug;
        end

        if (!reset && transport_busy)
            transport_busy_cycles = transport_busy_cycles + 1;
        if (!reset && (ym2203_write_count > write_accepted_count) &&
            !ym2203_cmd_ready)
            parser_stall_cycles = parser_stall_cycles + 1;

        if (!reset && waiting_for_busy && core_busy && !busy_seen_for_write) begin
            busy_seen_for_write = 1'b1;
            busy_assert_count = busy_assert_count + 1;
            busy_assert_delay_sum = busy_assert_delay_sum +
                                    (sys_cycle - data_write_cycle);
        end
        if (!reset && waiting_for_busy && busy_seen_for_write && !core_busy) begin
            busy_clear_count = busy_clear_count + 1;
            busy_clear_delay_sum = busy_clear_delay_sum +
                                   (sys_cycle - data_write_cycle);
            waiting_for_busy = 1'b0;
        end

        if (!reset && write_accepted) begin
            phase_has_previous = 1'b0;
            if (ym2203_cmd_reg == 8'h08 && ym2203_cmd_data == 8'h0f)
                audio_phase = AUDIO_SSG_ON;
            else if (ym2203_cmd_reg == 8'h08 && ym2203_cmd_data == 8'h00)
                audio_phase = AUDIO_SSG_MUTED;
            else if (ym2203_cmd_reg == 8'h28 && ym2203_cmd_data == 8'hf0)
                audio_phase = AUDIO_FM_ON;
            else if (ym2203_cmd_reg == 8'h28 && ym2203_cmd_data == 8'h00 &&
                     write_accepted_count > 32'd30)
                audio_phase = AUDIO_FM_OFF;
        end

        if (!reset && raw_monitor_enable) begin
            if ((^{core_busy, raw_audio_l, raw_audio_r, raw_fm_audio,
                   raw_psg_audio, raw_sample_valid}) === 1'bx)
                fail_now("X/Z on YM2203 raw audio/status");
            if (raw_audio_l !== raw_audio_r)
                fail_now("YM2203 mono left/right mismatch");
            if (raw_sample_valid) begin
                case (audio_phase)
                    AUDIO_SSG_ON: begin
                        ssg_on_samples = ssg_on_samples + 1;
                        if (phase_has_previous && raw_audio_l != phase_previous)
                            ssg_on_changes = ssg_on_changes + 1;
                    end
                    AUDIO_SSG_MUTED: begin
                        ssg_muted_samples = ssg_muted_samples + 1;
                        if (phase_has_previous && raw_audio_l != phase_previous)
                            ssg_muted_changes = ssg_muted_changes + 1;
                    end
                    AUDIO_FM_ON: begin
                        fm_on_samples = fm_on_samples + 1;
                        if (phase_has_previous && raw_audio_l != phase_previous)
                            fm_on_changes = fm_on_changes + 1;
                    end
                    AUDIO_FM_OFF: begin
                        fm_off_samples = fm_off_samples + 1;
                        if (phase_has_previous && raw_audio_l != phase_previous)
                            fm_off_changes = fm_off_changes + 1;
                    end
                    default: begin
                    end
                endcase
                phase_previous = raw_audio_l;
                phase_has_previous = 1'b1;
            end
        end
    end

    initial begin
        longint cen_error_numerator;
        integer timeout;

        for (int i = 0; i < (1 << ADDR_WIDTH); i = i + 1)
            mem[i] = 8'd0;
        expected_write_count = 0;
        mem[8'h00] = "V";
        mem[8'h01] = "g";
        mem[8'h02] = "m";
        mem[8'h03] = " ";
        mem[8'h08] = 8'h51;
        mem[8'h09] = 8'h01;
        mem[8'h44] = CHIP_CLK_HZ[7:0];
        mem[8'h45] = CHIP_CLK_HZ[15:8];
        mem[8'h46] = CHIP_CLK_HZ[23:16];
        mem[8'h47] = CHIP_CLK_HZ[31:24];
        mem[8'h34] = 8'h4c;

        build_pc = DATA_START;
        // JT49 channel A fixed tone, B/C and all noise muted.
        emit_ym2203_write(8'h00, 8'h20);
        emit_ym2203_write(8'h01, 8'h00);
        emit_ym2203_write(8'h07, 8'h3e);
        emit_ym2203_write(8'h08, 8'h0f);
        emit_wait(1000);
        emit_ym2203_write(8'h08, 8'h00);
        emit_wait(500);

        // Known-good OPN channel-0 patch from tb_jt2203_bus_smoke.sv.
        // YM2612-only LFO, DAC and pan writes are intentionally absent.
        emit_ym2203_write(8'h27, 8'h00);
        emit_ym2203_write(8'h28, 8'h00);
        emit_ym2203_write(8'h30, 8'h01);
        emit_ym2203_write(8'h34, 8'h01);
        emit_ym2203_write(8'h38, 8'h01);
        emit_ym2203_write(8'h3c, 8'h01);
        emit_ym2203_write(8'h40, 8'h28);
        emit_ym2203_write(8'h44, 8'h28);
        emit_ym2203_write(8'h48, 8'h28);
        emit_ym2203_write(8'h4c, 8'h28);
        emit_ym2203_write(8'h50, 8'h1f);
        emit_ym2203_write(8'h54, 8'h1f);
        emit_ym2203_write(8'h58, 8'h1f);
        emit_ym2203_write(8'h5c, 8'h1f);
        emit_ym2203_write(8'h60, 8'h00);
        emit_ym2203_write(8'h64, 8'h00);
        emit_ym2203_write(8'h68, 8'h00);
        emit_ym2203_write(8'h6c, 8'h00);
        emit_ym2203_write(8'h70, 8'h00);
        emit_ym2203_write(8'h74, 8'h00);
        emit_ym2203_write(8'h78, 8'h00);
        emit_ym2203_write(8'h7c, 8'h00);
        emit_ym2203_write(8'h80, 8'h0f);
        emit_ym2203_write(8'h84, 8'h0f);
        emit_ym2203_write(8'h88, 8'h0f);
        emit_ym2203_write(8'h8c, 8'h0f);
        emit_ym2203_write(8'h90, 8'h00);
        emit_ym2203_write(8'h94, 8'h00);
        emit_ym2203_write(8'h98, 8'h00);
        emit_ym2203_write(8'h9c, 8'h00);
        emit_ym2203_write(8'ha4, 8'h22);
        emit_ym2203_write(8'ha0, 8'h69);
        emit_ym2203_write(8'hb0, 8'h07);
        emit_ym2203_write(8'h28, 8'hf0);
        emit_wait(2000);
        emit_ym2203_write(8'h28, 8'h00);
        emit_wait(2000);
        expected_end_pc = build_pc;
        emit_byte(8'h66);
        file_size = build_pc;
        mem[8'h04] = (build_pc - 4) & 8'hff;
        mem[8'h05] = ((build_pc - 4) >> 8) & 8'hff;

        if (expected_write_count != 40)
            fail_now("test construction write count mismatch");

        repeat (8) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        @(posedge clk);
        load_done <= 1'b1;
        load_done_pulse <= 1'b1;
        @(posedge clk);
        load_done_pulse <= 1'b0;

        timeout = 0;
        while (!ym2203_clock_load && !player_error && timeout < 2000) begin
            timeout = timeout + 1;
            @(posedge clk);
        end
        if (!ym2203_clock_load || player_error)
            fail_now("YM2203 header clock was not loaded");
        @(negedge clk);
        if (ym2203_clock !== CHIP_CLK_HZ ||
            clock_raw_debug !== CHIP_CLK_HZ ||
            effective_clock_hz_debug !== CHIP_CLK_HZ ||
            !clock_present_debug)
            fail_now("YM2203 header/effective clock mismatch");
        raw_monitor_enable = 1'b1;

        timeout = 0;
        while (!done && !player_error && timeout < 1_500_000) begin
            timeout = timeout + 1;
            @(posedge clk);
        end
        if (!done || player_error || busy || !end_command_seen)
            fail_now("parser did not reach clean 0x66 END");
        repeat (4) @(posedge clk);

        if (ym2203_write_count != expected_write_count ||
            write_accepted_count != expected_write_count ||
            write_completed_count != expected_write_count)
            fail_now("decode/accepted/completed count mismatch");
        if (address_write_count != expected_write_count ||
            data_write_count != expected_write_count ||
            bus_pair_index != expected_write_count)
            fail_now("core bus duplicate or loss");
        if (busy_assert_count != expected_write_count ||
            busy_clear_count != expected_write_count)
            fail_now("busy assert/clear count mismatch");
        if (parser_command_count_debug !=
            expected_write_count + EXPECTED_WAIT_COMMANDS + 1)
            fail_now("parser command decode count mismatch");
        if (wait_ticks_consumed_debug != EXPECTED_WAIT_TICKS)
            fail_now("VGM wait tick count mismatch");
        if (done_pc_debug != expected_end_pc ||
            current_pc_debug != expected_end_pc)
            fail_now("parser END PC mismatch");
        if (ym2203_last_reg != 8'h28 || ym2203_last_data != 8'h00)
            fail_now("last YM2203 command mismatch");
        if (ssg_on_samples == 0 || ssg_on_changes == 0 ||
            ssg_muted_changes >= ssg_on_changes)
            fail_now("SSG activity/mute self-check failed");
        if (fm_on_samples == 0 || fm_on_changes == 0 ||
            fm_off_changes >= fm_on_changes)
            fail_now("FM activity/key-off self-check failed");
        if (parser_stall_cycles == 0 || transport_busy_cycles == 0)
            fail_now("parser/transport busy stall was not observed");

        cen_error_numerator =
            longint'(cen_pulse_count) * CLK_SYS_HZ -
            longint'(cen_active_cycles) * CHIP_CLK_HZ;
        if (cen_error_numerator < 0)
            cen_error_numerator = -cen_error_numerator;
        if (cen_error_numerator >= CLK_SYS_HZ)
            fail_now("CEN long-term frequency error exceeded one pulse");

        $display("CLOCK_STATS header=%0d active_cycles=%0d pulses=%0d error_numerator=%0d",
                 CHIP_CLK_HZ, cen_active_cycles, cen_pulse_count,
                 cen_error_numerator);
        $display("BUS_STATS writes=%0d busy_assert_avg=%0d busy_clear_avg=%0d parser_stall=%0d transport_busy=%0d",
                 expected_write_count,
                 busy_assert_delay_sum / expected_write_count,
                 busy_clear_delay_sum / expected_write_count,
                 parser_stall_cycles, transport_busy_cycles);
        $display("AUDIO_STATS ssg_on_samples=%0d ssg_on_changes=%0d ssg_muted_samples=%0d ssg_muted_changes=%0d fm_on_samples=%0d fm_on_changes=%0d fm_off_samples=%0d fm_off_changes=%0d",
                 ssg_on_samples, ssg_on_changes,
                 ssg_muted_samples, ssg_muted_changes,
                 fm_on_samples, fm_on_changes,
                 fm_off_samples, fm_off_changes);
        $display("PASS tb_vgm_loaded_player_ym2203 clock=%0d commands=%0d writes=%0d waits=%0d end_pc=%0h",
                 CHIP_CLK_HZ, parser_command_count_debug,
                 write_completed_count, wait_ticks_consumed_debug,
                 done_pc_debug);
        $finish;
    end
endmodule

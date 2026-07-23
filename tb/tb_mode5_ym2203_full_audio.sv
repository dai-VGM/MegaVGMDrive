`timescale 1ns/1ps

// Actual mode-5 top integration for the synthetic YM2203 VGM used by
// tb_vgm_loaded_player_ym2203. This observes the production C0/JT51/SegaPCM
// selector and final audio output rather than reproducing the mix in the TB.
module tb_mode5_ym2203_full_audio #(
    parameter logic [31:0] CHIP_CLK_HZ = 32'd4_000_000,
    // Existing top-level selector encoding: 0=Normal, 3=PCM Only, 1=FM Only.
    parameter logic [1:0] AUDIO_SELECT = 2'd0
);
    localparam int ADDR_WIDTH = 10;
    localparam logic [31:0] CLK_SYS_HZ = 32'd20_000_000;
    localparam int DATA_START = 16'h0080;
    localparam int EXPECTED_WRITES = 40;
    localparam int EXPECTED_COMMANDS = 45;
    localparam int EXPECTED_WAIT_TICKS = 5_500;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;
    logic [7:0] mem [0:(1 << ADDR_WIDTH)-1];
    integer build_pc;
    integer expected_end_pc;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_sample_valid;
    wire player_busy;
    wire player_done;
    wire audio_muted;
    wire ioctl_wait;
    wire vgm_load_done;
    wire vgm_header_valid;
    wire vgm_player_error;
    wire [31:0] wait_ticks_consumed;
    wire [31:0] parser_command_count;
    wire [ADDR_WIDTH-1:0] current_pc;
    wire [ADDR_WIDTH-1:0] done_pc;

    integer sys_cycle = 0;
    integer raw_sample_count = 0;
    integer final_sample_count = 0;
    integer final_nonzero_count = 0;
    integer sign_relation_checks = 0;
    integer load_reset_without_ym_reset_checks = 0;
    integer cen_active_cycles = 0;
    integer cen_pulse_count = 0;
    logic cen_previous = 1'b0;
    longint unsigned raw_hash = 64'hcbf29ce484222325;
    longint unsigned final_hash = 64'hcbf29ce484222325;

    typedef enum integer {
        AUDIO_IDLE,
        AUDIO_SSG_ON,
        AUDIO_SSG_MUTED,
        AUDIO_FM_ON,
        AUDIO_FM_OFF
    } audio_phase_t;
    audio_phase_t audio_phase = AUDIO_IDLE;

    integer raw_ssg_on_samples = 0;
    integer raw_ssg_on_changes = 0;
    integer raw_ssg_muted_samples = 0;
    integer raw_ssg_muted_changes = 0;
    integer raw_fm_on_samples = 0;
    integer raw_fm_on_changes = 0;
    integer raw_fm_off_samples = 0;
    integer raw_fm_off_changes = 0;
    integer final_ssg_on_samples = 0;
    integer final_ssg_on_changes = 0;
    integer final_ssg_muted_samples = 0;
    integer final_ssg_muted_changes = 0;
    integer final_fm_on_samples = 0;
    integer final_fm_on_changes = 0;
    integer final_fm_off_samples = 0;
    integer final_fm_off_changes = 0;
    logic signed [15:0] raw_previous = 16'sd0;
    logic signed [15:0] final_previous = 16'sd0;
    logic raw_previous_valid = 1'b0;
    logic final_previous_valid = 1'b0;

    always #25 clk = ~clk;

    task automatic fail_now(input string reason);
        begin
            $display("FAIL clock=%0d selector=%0d cycle=%0d pc=%0h reason=%s busy=%0b done=%0b load_done=%0b header=%0b player_error=%0b error_code=%02h error_pc=%0h error_cmd=%02h load_size=%0d magic=%08h load_busy=%0b load_error=%0b load_overflow=%0b start=%0b reset=%0b",
                     CHIP_CLK_HZ, AUDIO_SELECT, sys_cycle, current_pc, reason,
                     player_busy, player_done, vgm_load_done, vgm_header_valid,
                     vgm_player_error, dut.vgm_player_error_code,
                     dut.vgm_error_pc_debug, dut.vgm_error_cmd_debug,
                     dut.vgm_load_size, dut.vgm_load_magic,
                     dut.vgm_load_busy, dut.vgm_load_error,
                     dut.vgm_load_overflow,
                     dut.mode5_player_start_pulse_debug,
                     dut.mode5_sound_reset_active);
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

    task automatic load_vgm;
        begin
            @(negedge clk);
            ioctl_download = 1'b1;
            // Let the loader observe the download edge before the first byte.
            @(negedge clk);
            for (int i = 0; i < build_pc; i = i + 1) begin
                while (ioctl_wait) @(negedge clk);
                ioctl_addr = i;
                ioctl_dout = mem[i];
                ioctl_wr = 1'b1;
                @(negedge clk);
                ioctl_wr = 1'b0;
            end
            ioctl_download = 1'b0;
            ioctl_addr = 27'd0;
            ioctl_dout = 8'd0;
        end
    endtask

    mister_vgm_md_top #(
        .REGION_MODE                     (5),
        .VGM_LOAD_ADDR_WIDTH             (ADDR_WIDTH),
        .MODE5_VGM_BACKEND               (0),
        .POWER_ON_RESET_CYCLES           (32'd0),
        .START_DELAY_CYCLES              (32'd0),
        .INIT_AUDIO_SAMPLE_EDGES          (16'd0),
        .AUDIO_WARMUP_SAMPLES            (16'd0),
        .GATE_TO_START_CYCLES             (16'd0),
        .CLK_SYS_HZ                      (CLK_SYS_HZ),
        // Match the existing standalone integration's one tick per 64 cycles.
        .VGM_WAIT_HZ                     (32'd312_500),
        .MODE5_SOUND_RESET_CYCLES        (32'd8),
        .MODE5_AUDIO_UNMUTE_DELAY_CYCLES (32'd0),
        .REPLAY_ENABLE                   (1'b0)
    ) dut (
        .clk                              (clk),
        .reset_n                          (reset_n),
        .audio_l                          (audio_l),
        .audio_r                          (audio_r),
        .audio_sample_valid               (audio_sample_valid),
        .audio_lpf_mode                   (2'b00),
        .audio_gain_boost                 (1'b0),
        .audio_psg_level                  (2'b00),
        .segapcm_smoke_variant            (3'd0),
        .segapcm_smoke_variant_valid      (1'b0),
        .segapcm_smoke_source_loaded      (1'b0),
        .segapcm_smoke_ddr_follow         (1'b0),
        .segapcm_smoke_ddr_offset         (3'd0),
        .segapcm_smoke_ddr_delta          (3'd0),
        .segapcm_smoke_c0_use             (2'd0),
        .segapcm_smoke_c0_sample_mode     (3'd3),
        .segapcm_smoke_c0_delta_speed     (2'd0),
        .segapcm_smoke_c0_hit_window      (3'd0),
        .segapcm_smoke_c0_format          (2'd0),
        .segapcm_smoke_c0_mame_tick_div   (3'd0),
        .segapcm_smoke_c0_vol_map         (3'd0),
        .segapcm_smoke_c0_drive           (2'd0),
        .segapcm_c0_pm3_audio_mask        (16'hffff),
        .segapcm_c0_top_audio_test        (AUDIO_SELECT),
        .segapcm_c0_pm3_mix_mode          (2'd0),
        .segapcm_c0_pm3_start_policy      (3'd0),
        .segapcm_c0_jt_backend            (1'b1),
        .segapcm_smoke_ddr_dest_map       (1'b0),
        .segapcm_smoke_ddr_dest_basis     (2'd1),
        .segapcm_smoke_ddr_full_capture   (1'b0),
        .segapcm_smoke_ddr_dest_loop_wrap (1'b0),
        .player_busy                      (player_busy),
        .player_done                      (player_done),
        .audio_muted                      (audio_muted),
        .ioctl_download                   (ioctl_download),
        .ioctl_wr                         (ioctl_wr),
        .ioctl_addr                       (ioctl_addr),
        .ioctl_dout                       (ioctl_dout),
        .ioctl_index                      (16'd1),
        .ioctl_wait                       (ioctl_wait),
        .vgm_load_done                    (vgm_load_done),
        .vgm_header_valid                 (vgm_header_valid),
        .vgm_player_error                 (vgm_player_error),
        .vgm_current_pc_debug             (current_pc),
        .vgm_wait_ticks_consumed_debug    (wait_ticks_consumed),
        .parser_command_count_debug       (parser_command_count),
        .mode5_done_pc_debug              (done_pc),
        .ddram_busy                       (1'b0),
        .ddram_dout                       (64'd0),
        .ddram_dout_ready                 (1'b0)
    );

    always @(posedge clk) begin
        sys_cycle = sys_cycle + 1;
        #1;
        if (!reset_n)
            cen_previous = 1'b0;
        else if (dut.loaded_vgm_mode.ym2203_header_clock_load) begin
            cen_active_cycles = 0;
            cen_pulse_count = 0;
            cen_previous = 1'b0;
        end else if (dut.loaded_vgm_mode.ym2203_clock_present_debug) begin
            cen_active_cycles = cen_active_cycles + 1;
            if (dut.loaded_vgm_mode.ym2203_chip_cen_debug)
                cen_pulse_count = cen_pulse_count + 1;
            if (dut.loaded_vgm_mode.ym2203_chip_cen_debug && cen_previous)
                fail_now("consecutive YM2203 CEN");
            cen_previous = dut.loaded_vgm_mode.ym2203_chip_cen_debug;
        end

        if (reset_n && dut.loaded_vgm_mode.mode5_sound_core_reset &&
            !dut.reset) begin
            if (dut.loaded_vgm_mode.ym2203_sound.reset !== 1'b0)
                fail_now("mode5 sound reset reached YM2203 core");
            load_reset_without_ym_reset_checks =
                load_reset_without_ym_reset_checks + 1;
        end

        if (dut.loaded_vgm_mode.ym2203_write_accepted) begin
            raw_previous_valid = 1'b0;
            final_previous_valid = 1'b0;
            if (dut.loaded_vgm_mode.ym2203_cmd_reg == 8'h08 &&
                dut.loaded_vgm_mode.ym2203_cmd_data == 8'h0f)
                audio_phase = AUDIO_SSG_ON;
            else if (dut.loaded_vgm_mode.ym2203_cmd_reg == 8'h08 &&
                     dut.loaded_vgm_mode.ym2203_cmd_data == 8'h00)
                audio_phase = AUDIO_SSG_MUTED;
            else if (dut.loaded_vgm_mode.ym2203_cmd_reg == 8'h28 &&
                     dut.loaded_vgm_mode.ym2203_cmd_data == 8'hf0)
                audio_phase = AUDIO_FM_ON;
            else if (dut.loaded_vgm_mode.ym2203_cmd_reg == 8'h28 &&
                     dut.loaded_vgm_mode.ym2203_cmd_data == 8'h00 &&
                     dut.loaded_vgm_mode.ym2203_write_accepted_count > 32'd30)
                audio_phase = AUDIO_FM_OFF;
        end

        if (reset_n && dut.loaded_vgm_mode.ym2203_clock_present_debug) begin
            if ((^{dut.loaded_vgm_mode.ym2203_raw_audio_l,
                   dut.loaded_vgm_mode.ym2203_raw_audio_r,
                   dut.loaded_vgm_mode.ym2203_raw_sample_valid,
                   dut.loaded_vgm_mode.ym2203_audio_l_held,
                   dut.loaded_vgm_mode.ym2203_audio_r_held,
                   dut.loaded_vgm_mode.ym2203_audio_l_selected,
                   dut.loaded_vgm_mode.ym2203_audio_r_selected}) === 1'bx)
                fail_now("X/Z on YM2203 raw/hold path");
            if (dut.loaded_vgm_mode.ym2203_raw_audio_l !==
                dut.loaded_vgm_mode.ym2203_raw_audio_r)
                fail_now("YM2203 raw mono mismatch");

            if (dut.loaded_vgm_mode.ym2203_raw_sample_valid) begin
                raw_sample_count = raw_sample_count + 1;
                raw_hash = (raw_hash ^
                            {32'd0, dut.loaded_vgm_mode.ym2203_raw_audio_l,
                             dut.loaded_vgm_mode.ym2203_raw_audio_r}) *
                           64'h00000100000001b3;
                case (audio_phase)
                    AUDIO_SSG_ON: begin
                        raw_ssg_on_samples = raw_ssg_on_samples + 1;
                        if (raw_previous_valid &&
                            dut.loaded_vgm_mode.ym2203_raw_audio_l != raw_previous)
                            raw_ssg_on_changes = raw_ssg_on_changes + 1;
                    end
                    AUDIO_SSG_MUTED: begin
                        raw_ssg_muted_samples = raw_ssg_muted_samples + 1;
                        if (raw_previous_valid &&
                            dut.loaded_vgm_mode.ym2203_raw_audio_l != raw_previous)
                            raw_ssg_muted_changes = raw_ssg_muted_changes + 1;
                    end
                    AUDIO_FM_ON: begin
                        raw_fm_on_samples = raw_fm_on_samples + 1;
                        if (raw_previous_valid &&
                            dut.loaded_vgm_mode.ym2203_raw_audio_l != raw_previous)
                            raw_fm_on_changes = raw_fm_on_changes + 1;
                    end
                    AUDIO_FM_OFF: begin
                        raw_fm_off_samples = raw_fm_off_samples + 1;
                        if (raw_previous_valid &&
                            dut.loaded_vgm_mode.ym2203_raw_audio_l != raw_previous)
                            raw_fm_off_changes = raw_fm_off_changes + 1;
                    end
                    default: begin end
                endcase
                raw_previous = dut.loaded_vgm_mode.ym2203_raw_audio_l;
                raw_previous_valid = 1'b1;
            end
        end

        if (reset_n && !audio_muted) begin
            if ((^{audio_l, audio_r, audio_sample_valid, dut.raw_audio_l,
                   dut.raw_audio_r}) === 1'bx)
                fail_now("X/Z on final mode5 audio");
            if (AUDIO_SELECT == 2'd3 &&
                (audio_l != 16'sd0 || audio_r != 16'sd0))
                fail_now("PCM Only leaked non-PCM audio");
            if (audio_sample_valid) begin
                final_sample_count = final_sample_count + 1;
                final_hash = (final_hash ^ {32'd0, audio_l, audio_r}) *
                             64'h00000100000001b3;
                if (audio_l != 16'sd0 || audio_r != 16'sd0)
                    final_nonzero_count = final_nonzero_count + 1;
                if (AUDIO_SELECT != 2'd3 &&
                    dut.loaded_vgm_mode.lab_fm_l_selected == 16'sd0 &&
                    dut.loaded_vgm_mode.lab_pcm_mix_l_selected == 16'sd0) begin
                    if (audio_l !==
                            ($signed(dut.loaded_vgm_mode.
                                ym2203_audio_l_selected) >>> 2) ||
                        audio_r !==
                            ($signed(dut.loaded_vgm_mode.
                                ym2203_audio_r_selected) >>> 2) ||
                        audio_l !== dut.loaded_vgm_mode.
                            arcade_audio_l_normalized ||
                        audio_r !== dut.loaded_vgm_mode.
                            arcade_audio_r_normalized)
                        fail_now("YM2203 hold did not reach normalized arcade lane");
                    sign_relation_checks = sign_relation_checks + 1;
                end
                if (audio_l !== audio_r)
                    fail_now("final YM2203-only left/right mismatch");
                case (audio_phase)
                    AUDIO_SSG_ON: begin
                        final_ssg_on_samples = final_ssg_on_samples + 1;
                        if (final_previous_valid && audio_l != final_previous)
                            final_ssg_on_changes = final_ssg_on_changes + 1;
                    end
                    AUDIO_SSG_MUTED: begin
                        final_ssg_muted_samples = final_ssg_muted_samples + 1;
                        if (final_previous_valid && audio_l != final_previous)
                            final_ssg_muted_changes = final_ssg_muted_changes + 1;
                    end
                    AUDIO_FM_ON: begin
                        final_fm_on_samples = final_fm_on_samples + 1;
                        if (final_previous_valid && audio_l != final_previous)
                            final_fm_on_changes = final_fm_on_changes + 1;
                    end
                    AUDIO_FM_OFF: begin
                        final_fm_off_samples = final_fm_off_samples + 1;
                        if (final_previous_valid && audio_l != final_previous)
                            final_fm_off_changes = final_fm_off_changes + 1;
                    end
                    default: begin end
                endcase
                final_previous = audio_l;
                final_previous_valid = 1'b1;
            end
        end
    end

    initial begin
        integer timeout;
        longint cen_error_numerator;

        for (int i = 0; i < (1 << ADDR_WIDTH); i = i + 1)
            mem[i] = 8'd0;
        mem[0] = "V";
        mem[1] = "g";
        mem[2] = "m";
        mem[3] = " ";
        mem[8'h08] = 8'h51;
        mem[8'h09] = 8'h01;
        mem[8'h34] = 8'h4c;
        mem[8'h44] = CHIP_CLK_HZ[7:0];
        mem[8'h45] = CHIP_CLK_HZ[15:8];
        mem[8'h46] = CHIP_CLK_HZ[23:16];
        mem[8'h47] = CHIP_CLK_HZ[31:24];

        build_pc = DATA_START;
        emit_ym2203_write(8'h00, 8'h20);
        emit_ym2203_write(8'h01, 8'h00);
        emit_ym2203_write(8'h07, 8'h3e);
        emit_ym2203_write(8'h08, 8'h0f);
        emit_wait(1000);
        emit_ym2203_write(8'h08, 8'h00);
        emit_wait(500);
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
        mem[8'h04] = (build_pc - 4) & 8'hff;
        mem[8'h05] = ((build_pc - 4) >> 8) & 8'hff;

        repeat (8) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        repeat (8) @(posedge clk);
        load_vgm();

        timeout = 0;
        while (!(player_busy && vgm_header_valid) && !vgm_player_error &&
               timeout < 20_000) begin
            timeout = timeout + 1;
            @(posedge clk);
        end
        if (!(player_busy && vgm_header_valid) || vgm_player_error)
            fail_now("mode5 parser did not start loaded VGM");

        timeout = 0;
        while (!player_done && !vgm_player_error && timeout < 1_500_000) begin
            timeout = timeout + 1;
            @(posedge clk);
        end
        if (!player_done || vgm_player_error || player_busy)
            fail_now("mode5 parser did not reach clean END");
        repeat (4) @(posedge clk);

        if (!vgm_load_done || !vgm_header_valid)
            fail_now("load/header state mismatch");
        if (load_reset_without_ym_reset_checks == 0)
            fail_now("file-load reset isolation was not observed");
        if (dut.loaded_vgm_mode.ym2203_header_clock !== CHIP_CLK_HZ ||
            dut.loaded_vgm_mode.ym2203_clock_raw_debug !== CHIP_CLK_HZ ||
            dut.loaded_vgm_mode.ym2203_effective_clock_debug !== CHIP_CLK_HZ)
            fail_now("YM2203 header/effective clock mismatch");
        if (dut.loaded_vgm_mode.ym2203_write_count != EXPECTED_WRITES ||
            dut.loaded_vgm_mode.ym2203_write_accepted_count != EXPECTED_WRITES ||
            dut.loaded_vgm_mode.ym2203_write_completed_count != EXPECTED_WRITES)
            fail_now("decode/accepted/completed mismatch");
        if (parser_command_count != EXPECTED_COMMANDS ||
            wait_ticks_consumed != EXPECTED_WAIT_TICKS ||
            done_pc != expected_end_pc || current_pc != expected_end_pc)
            fail_now("parser count/wait/END PC mismatch");
        if (raw_ssg_on_changes == 0 ||
            raw_ssg_muted_changes >= raw_ssg_on_changes ||
            raw_fm_on_changes == 0 || raw_fm_off_changes >= raw_fm_on_changes)
            fail_now("raw YM2203 activity regression");
        if (final_sample_count == 0)
            fail_now("no final mode5 sample timing observed");

        if (AUDIO_SELECT == 2'd3) begin
            if (final_nonzero_count != 0 || final_ssg_on_changes != 0 ||
                final_fm_on_changes != 0)
                fail_now("PCM Only final output was not silent");
        end else begin
            if (final_ssg_on_changes == 0 ||
                final_ssg_muted_changes >= final_ssg_on_changes ||
                final_fm_on_changes == 0 ||
                final_fm_off_changes >= final_fm_on_changes ||
                sign_relation_checks == 0)
                fail_now("Normal/FM Only final activity regression");
        end

        cen_error_numerator =
            longint'(cen_pulse_count) * CLK_SYS_HZ -
            // clock_present becomes visible on the load edge; phase
            // accumulation begins on the following system-clock interval.
            longint'(cen_active_cycles - 1) * CHIP_CLK_HZ;
        if (cen_error_numerator < 0)
            cen_error_numerator = -cen_error_numerator;
        if (cen_error_numerator >= CLK_SYS_HZ) begin
            $display("CEN_FAIL cycles=%0d pulses=%0d error=%0d",
                     cen_active_cycles, cen_pulse_count,
                     cen_error_numerator);
            fail_now("CEN frequency error exceeded one pulse");
        end

        $display("FULL_AUDIO_STATS clock=%0d selector=%0d raw_samples=%0d final_samples=%0d final_nonzero=%0d raw_hash=%016h final_hash=%016h sign_checks=%0d reset_isolation=%0d cen_cycles=%0d cen_pulses=%0d cen_error=%0d",
                 CHIP_CLK_HZ, AUDIO_SELECT, raw_sample_count,
                 final_sample_count, final_nonzero_count, raw_hash, final_hash,
                 sign_relation_checks, load_reset_without_ym_reset_checks,
                 cen_active_cycles, cen_pulse_count, cen_error_numerator);
        $display("FULL_PHASE_STATS clock=%0d selector=%0d raw_ssg=%0d/%0d->%0d/%0d raw_fm=%0d/%0d->%0d/%0d final_ssg=%0d/%0d->%0d/%0d final_fm=%0d/%0d->%0d/%0d",
                 CHIP_CLK_HZ, AUDIO_SELECT,
                 raw_ssg_on_samples, raw_ssg_on_changes,
                 raw_ssg_muted_samples, raw_ssg_muted_changes,
                 raw_fm_on_samples, raw_fm_on_changes,
                 raw_fm_off_samples, raw_fm_off_changes,
                 final_ssg_on_samples, final_ssg_on_changes,
                 final_ssg_muted_samples, final_ssg_muted_changes,
                 final_fm_on_samples, final_fm_on_changes,
                 final_fm_off_samples, final_fm_off_changes);
        $display("PASS tb_mode5_ym2203_full_audio clock=%0d selector=%0d commands=%0d writes=%0d waits=%0d end_pc=%0h",
                 CHIP_CLK_HZ, AUDIO_SELECT, parser_command_count,
                 dut.loaded_vgm_mode.ym2203_write_completed_count,
                 wait_ticks_consumed, done_pc);
        $finish;
    end
endmodule

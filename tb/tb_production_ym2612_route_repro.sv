`timescale 1ns/1ps

// Production-QSF regression for the actual mode-5 top.  Genesis commands and
// the MD sound core must remain active beside the arcade command/audio path.
/* verilator lint_off PROCASSINIT */
/* verilator lint_off BLKSEQ */
module tb_production_ym2612_route_repro;
    localparam integer ADDR_WIDTH = 12;
    localparam integer CLK_SYS_HZ = 20_000_000;
    localparam integer VGM_WAIT_HZ = 1_000_000;
    localparam integer DATA_START = 8'h80;
    localparam logic [28:0] DDR_BASE = {4'b0011, 25'd0};
    localparam integer DDR_WORDS = 1024;

`ifdef MEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD
    localparam integer PROFILE_PRODUCTION = 1;
`else
    localparam integer PROFILE_PRODUCTION = 0;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
    localparam integer PROFILE_C0_LAB = 1;
`else
    localparam integer PROFILE_C0_LAB = 0;
`endif
`ifdef MEGAVGMDRIVE_SEGAPCM_AUDIO_STUB_BUILD
    localparam integer PROFILE_MD_AUDIO_STUB = 1;
`else
    localparam integer PROFILE_MD_AUDIO_STUB = 0;
`endif
`ifdef MEGAVGMDRIVE_DEV_OSD
    localparam integer PROFILE_DEV_OSD = 1;
`else
    localparam integer PROFILE_DEV_OSD = 0;
`endif
`ifdef MD_JT12_CEN_NTSC_TEST
    localparam integer PROFILE_JT12_NTSC_CEN = 1;
`else
    localparam integer PROFILE_JT12_NTSC_CEN = 0;
`endif
`ifdef MEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD
    localparam integer PROFILE_OUTPUT_SHIFT = 0;
`elsif MD_AUDIO_OUTPUT_SHIFT_0_TEST
    localparam integer PROFILE_OUTPUT_SHIFT = 0;
`else
    localparam integer PROFILE_OUTPUT_SHIFT = 2;
`endif

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;
    wire ioctl_wait;
    wire player_busy;
    wire player_done;
    wire player_error;
    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_sample_valid;
    wire [28:0] ddram_addr;
    logic [63:0] ddram_dout = 64'd0;
    logic ddram_dout_ready = 1'b0;
    wire [63:0] ddram_din;
    wire [7:0] ddram_be;
    wire ddram_rd;
    wire ddram_we;

    logic [7:0] vgm_mem [0:(1 << ADDR_WIDTH)-1];
    logic [63:0] ddram_mem [0:DDR_WORDS-1];
    logic [28:0] read_addr_q = 29'd0;
    integer read_delay = 0;
    integer build_pc = DATA_START;
    integer parser_ym_pulses = 0;
    integer parser_psg_pulses = 0;
    integer md_valid_count = 0;
    integer md_nonzero_count = 0;
    integer fm_raw_nonzero_count = 0;
    integer psg_raw_nonzero_count = 0;
    integer jt51_raw_nonzero_count = 0;
    integer ym2203_raw_nonzero_count = 0;
    integer md_selected_nonzero_count = 0;
    integer jt51_valid_count = 0;
    integer ym2203_valid_count = 0;
    integer segapcm_valid_count = 0;
    integer fm_cen_count = 0;
    integer psg_cen_count = 0;
    integer wait_tick_count = 0;
    integer raw_valid_count = 0;
    integer raw_nonzero_count = 0;
    integer final_valid_count = 0;
    integer final_nonzero_count = 0;
    integer xz_count = 0;
    integer md_raw_value_mismatch_count = 0;
    integer final_raw_value_mismatch_count = 0;
    integer arcade_normalization_mismatch_count = 0;
    integer family_sum_mismatch_count = 0;
    integer family_output_mismatch_count = 0;
    integer family_clip_count = 0;
    longint unsigned system_cycle = 0;
    longint unsigned first_ym_cycle = 0;
    longint unsigned last_ym_cycle = 0;
    longint unsigned done_cycle = 0;
    logic [63:0] md_sample_hash = 64'hcbf29ce484222325;
    logic [63:0] raw_on_md_valid_hash = 64'hcbf29ce484222325;
    logic [63:0] final_on_md_valid_hash = 64'hcbf29ce484222325;
    integer fixture = 2;
    integer audio_select = 0;

    function automatic logic signed [15:0] sat17(
        input logic signed [16:0] value
    );
        begin
            sat17 = (value[16] == value[15]) ? value[15:0] :
                    (value[16] ? 16'sh8000 : 16'sh7fff);
        end
    endfunction

    always #25 clk = ~clk;

    task automatic emit_byte(input logic [7:0] value);
        begin
            vgm_mem[build_pc] = value;
            build_pc = build_pc + 1;
        end
    endtask

    task automatic emit_ym(input logic [7:0] reg_addr,
                           input logic [7:0] reg_data);
        begin
            emit_byte(8'h52);
            emit_byte(reg_addr);
            emit_byte(reg_data);
        end
    endtask

    task automatic emit_psg(input logic [7:0] data);
        begin
            emit_byte(8'h50);
            emit_byte(data);
        end
    endtask

    task automatic emit_ym2203(input logic [7:0] reg_addr,
                               input logic [7:0] reg_data);
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

    task automatic emit_u32(input integer value);
        begin
            emit_byte(value[7:0]);
            emit_byte(value[15:8]);
            emit_byte(value[23:16]);
            emit_byte(value[31:24]);
        end
    endtask

    task automatic emit_dac_stream_fixture;
        integer sample_count;
        logic [7:0] sample_value;
        begin
            sample_count = 64;
            sample_value = 8'h20;
            emit_ym(8'h2b, 8'h80);
            emit_byte(8'h67);
            emit_byte(8'h66);
            emit_byte(8'h00);
            emit_u32(sample_count);
            for (integer i = 0; i < sample_count; i = i + 1) begin
                emit_byte(sample_value);
                sample_value = sample_value + 8'h05;
            end
            emit_byte(8'he0);
            emit_u32(0);
            for (integer i = 0; i < sample_count; i = i + 1)
                emit_byte(8'h80);
        end
    endtask

    task automatic load_vgm;
        begin
            @(negedge clk);
            ioctl_download = 1'b1;
            @(negedge clk);
            for (integer i = 0; i < build_pc; i = i + 1) begin
                while (ioctl_wait) @(negedge clk);
                ioctl_addr = i;
                ioctl_dout = vgm_mem[i];
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
        .MODE5_VGM_BACKEND               (1),
        .CLK_SYS_HZ                      (CLK_SYS_HZ),
        .VGM_WAIT_HZ                     (VGM_WAIT_HZ),
        .POWER_ON_RESET_CYCLES           (32'd0),
        .START_DELAY_CYCLES              (32'd0),
        .INIT_AUDIO_SAMPLE_EDGES          (16'd0),
        .AUDIO_WARMUP_SAMPLES            (16'd0),
        .GATE_TO_START_CYCLES             (16'd0),
        .MODE5_SOUND_RESET_CYCLES        (32'd0),
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
        .segapcm_smoke_c0_delta_speed     (2'd2),
        .segapcm_smoke_c0_hit_window      (3'd0),
        .segapcm_smoke_c0_format          (2'd0),
        .segapcm_smoke_c0_mame_tick_div   (3'd0),
        .segapcm_smoke_c0_vol_map         (3'd0),
        .segapcm_smoke_c0_drive           (2'd0),
        .segapcm_c0_pm3_audio_mask        (16'hffff),
        .segapcm_c0_top_audio_test        (audio_select[1:0]),
        .segapcm_c0_pm3_mix_mode          (2'd1),
        .segapcm_c0_pm3_start_policy      (3'd0),
        .segapcm_c0_jt_backend            (1'b1),
        .segapcm_smoke_ddr_dest_map       (1'b0),
        .segapcm_smoke_ddr_dest_basis     (2'd1),
        .segapcm_smoke_ddr_full_capture   (1'b0),
        .segapcm_smoke_ddr_dest_loop_wrap (1'b0),
        .player_busy                      (player_busy),
        .player_done                      (player_done),
        .vgm_player_error                 (player_error),
        .ioctl_download                   (ioctl_download),
        .ioctl_wr                         (ioctl_wr),
        .ioctl_addr                       (ioctl_addr),
        .ioctl_dout                       (ioctl_dout),
        .ioctl_index                      (16'd1),
        .ioctl_wait                       (ioctl_wait),
        .ddram_busy                       (1'b0),
        .ddram_addr                       (ddram_addr),
        .ddram_dout                       (ddram_dout),
        .ddram_dout_ready                 (ddram_dout_ready),
        .ddram_din                        (ddram_din),
        .ddram_be                         (ddram_be),
        .ddram_rd                         (ddram_rd),
        .ddram_we                         (ddram_we)
    );

    always @(posedge clk) begin
        system_cycle <= system_cycle + 1;
        ddram_dout_ready <= 1'b0;
        if (ddram_we) begin
            if (ddram_addr < DDR_BASE || ddram_addr >= DDR_BASE + DDR_WORDS)
                $fatal(1, "DDRAM write out of range: %08h", ddram_addr);
            for (integer lane = 0; lane < 8; lane = lane + 1)
                if (ddram_be[lane])
                    ddram_mem[ddram_addr-DDR_BASE][lane*8 +: 8] <=
                        ddram_din[lane*8 +: 8];
        end
        if (ddram_rd && read_delay == 0) begin
            if (ddram_addr < DDR_BASE || ddram_addr >= DDR_BASE + DDR_WORDS)
                $fatal(1, "DDRAM read out of range: %08h", ddram_addr);
            read_addr_q <= ddram_addr;
            read_delay <= 2;
        end else if (read_delay != 0) begin
            read_delay <= read_delay - 1;
            if (read_delay == 1) begin
                ddram_dout <= ddram_mem[read_addr_q-DDR_BASE];
                ddram_dout_ready <= 1'b1;
            end
        end

        if (reset_n && player_busy) begin
            if (dut.loaded_vgm_mode.ym_cmd_valid) begin
                parser_ym_pulses++;
                if (first_ym_cycle == 0) first_ym_cycle = system_cycle;
                last_ym_cycle = system_cycle;
            end
            if (dut.loaded_vgm_mode.psg_cmd_valid) parser_psg_pulses++;
        end
        if (reset_n && dut.audio_runtime_open) begin
            if (dut.loaded_vgm_mode.sound.fm_clken) fm_cen_count++;
            if (dut.loaded_vgm_mode.sound.psg_clken) psg_cen_count++;
            if (dut.vgm_wait_tick) wait_tick_count++;
            if (dut.loaded_vgm_mode.md_audio_sample_valid) md_valid_count++;
            if (dut.loaded_vgm_mode.ym2151_audio_sample_valid)
                jt51_valid_count++;
            if (dut.loaded_vgm_mode.ym2203_raw_sample_valid)
                ym2203_valid_count++;
            if (dut.loaded_vgm_mode.segapcm_audio_sample_valid)
                segapcm_valid_count++;
            if (dut.loaded_vgm_mode.md_audio_l != 0 ||
                dut.loaded_vgm_mode.md_audio_r != 0) md_nonzero_count++;
            if (dut.loaded_vgm_mode.sound.fm_left != 0 ||
                dut.loaded_vgm_mode.sound.fm_right != 0)
                fm_raw_nonzero_count++;
            if (dut.loaded_vgm_mode.sound.psg_sound != 0)
                psg_raw_nonzero_count++;
            if (dut.loaded_vgm_mode.ym2151_audio_l != 0 ||
                dut.loaded_vgm_mode.ym2151_audio_r != 0)
                jt51_raw_nonzero_count++;
            if (dut.loaded_vgm_mode.ym2203_raw_audio_l != 0 ||
                dut.loaded_vgm_mode.ym2203_raw_audio_r != 0)
                ym2203_raw_nonzero_count++;
            if (dut.loaded_vgm_mode.md_audio_l_selected != 0 ||
                dut.loaded_vgm_mode.md_audio_r_selected != 0)
                md_selected_nonzero_count++;
            if (dut.raw_audio_sample_valid) raw_valid_count++;
            if (dut.raw_audio_l != 0 || dut.raw_audio_r != 0)
                raw_nonzero_count++;
            if (audio_sample_valid) final_valid_count++;
            if (audio_l != 0 || audio_r != 0) final_nonzero_count++;
            if (dut.loaded_vgm_mode.md_audio_session_active &&
                audio_select != 3 &&
                ({dut.raw_audio_l, dut.raw_audio_r} !==
                 {dut.loaded_vgm_mode.md_audio_l,
                  dut.loaded_vgm_mode.md_audio_r}))
                md_raw_value_mismatch_count++;
            if ({audio_l, audio_r} !== {dut.raw_audio_l, dut.raw_audio_r})
                final_raw_value_mismatch_count++;
            if ({dut.loaded_vgm_mode.arcade_audio_l_normalized,
                 dut.loaded_vgm_mode.arcade_audio_r_normalized} !==
                {$signed(dut.loaded_vgm_mode.ym2151_segapcm_audio_l) >>> 2,
                 $signed(dut.loaded_vgm_mode.ym2151_segapcm_audio_r) >>> 2})
                arcade_normalization_mismatch_count++;
            if (dut.loaded_vgm_mode.production_family_audio_l_sum !==
                    ($signed({dut.loaded_vgm_mode.md_audio_l_selected[15],
                              dut.loaded_vgm_mode.md_audio_l_selected}) +
                     $signed({dut.loaded_vgm_mode.arcade_audio_l_normalized[15],
                              dut.loaded_vgm_mode.arcade_audio_l_normalized})) ||
                dut.loaded_vgm_mode.production_family_audio_r_sum !==
                    ($signed({dut.loaded_vgm_mode.md_audio_r_selected[15],
                              dut.loaded_vgm_mode.md_audio_r_selected}) +
                     $signed({dut.loaded_vgm_mode.arcade_audio_r_normalized[15],
                              dut.loaded_vgm_mode.arcade_audio_r_normalized})))
                family_sum_mismatch_count++;
            if (dut.raw_audio_l !==
                    sat17(dut.loaded_vgm_mode.production_family_audio_l_sum) ||
                dut.raw_audio_r !==
                    sat17(dut.loaded_vgm_mode.production_family_audio_r_sum))
                family_output_mismatch_count++;
            if (dut.loaded_vgm_mode.production_family_audio_l_clipped ||
                dut.loaded_vgm_mode.production_family_audio_r_clipped)
                family_clip_count++;
            if (dut.loaded_vgm_mode.md_audio_sample_valid) begin
                md_sample_hash <=
                    (md_sample_hash ^
                     {32'd0, dut.loaded_vgm_mode.md_audio_l,
                      dut.loaded_vgm_mode.md_audio_r}) * 64'h00000100000001b3;
                raw_on_md_valid_hash <=
                    (raw_on_md_valid_hash ^
                     {32'd0, dut.raw_audio_l, dut.raw_audio_r}) *
                    64'h00000100000001b3;
                final_on_md_valid_hash <=
                    (final_on_md_valid_hash ^ {32'd0, audio_l, audio_r}) *
                    64'h00000100000001b3;
            end
            if ((^{dut.loaded_vgm_mode.md_audio_l,
                   dut.loaded_vgm_mode.md_audio_r,
                   dut.loaded_vgm_mode.md_audio_l_selected,
                   dut.loaded_vgm_mode.md_audio_r_selected,
                   dut.raw_audio_l, dut.raw_audio_r,
                   audio_l, audio_r, audio_sample_valid}) === 1'bx)
                xz_count++;
        end
    end

    initial begin
        integer timeout;
        integer expected_ym;
        integer expected_psg;
        if (!$value$plusargs("FIXTURE=%d", fixture)) fixture = 2;
        if (!$value$plusargs("AUDIO_SELECT=%d", audio_select)) audio_select = 0;
        if (fixture < 0 || fixture > 4)
            $fatal(1, "invalid FIXTURE=%0d", fixture);
        if (audio_select != 0 && audio_select != 1 && audio_select != 3)
            $fatal(1, "invalid AUDIO_SELECT=%0d", audio_select);
        for (integer i = 0; i < (1 << ADDR_WIDTH); i = i + 1)
            vgm_mem[i] = 8'd0;
        for (integer i = 0; i < DDR_WORDS; i = i + 1)
            ddram_mem[i] = 64'd0;

        vgm_mem[0] = "V"; vgm_mem[1] = "g";
        vgm_mem[2] = "m"; vgm_mem[3] = " ";
        vgm_mem[8'h08] = 8'h51; vgm_mem[8'h09] = 8'h01;
        vgm_mem[8'h2c] = 8'h53; vgm_mem[8'h2d] = 8'h67;
        vgm_mem[8'h2e] = 8'h7a; vgm_mem[8'h2f] = 8'h00;
        vgm_mem[8'h34] = 8'h4c;
        if (fixture == 3) begin
            vgm_mem[8'h44] = 8'h00;
            vgm_mem[8'h45] = 8'h09;
            vgm_mem[8'h46] = 8'h3d;
            vgm_mem[8'h47] = 8'h00;
        end

        if (fixture != 1 && fixture != 4) begin
            emit_ym(8'h22, 8'h00);
            emit_ym(8'h27, 8'h00);
            emit_ym(8'h2b, 8'h00);
            emit_ym(8'h30, 8'h01);
            emit_ym(8'h34, 8'h01);
            emit_ym(8'h38, 8'h01);
            emit_ym(8'h3c, 8'h01);
            emit_ym(8'h40, 8'h28);
            emit_ym(8'h44, 8'h28);
            emit_ym(8'h48, 8'h28);
            emit_ym(8'h4c, 8'h28);
            emit_ym(8'h50, 8'h1f);
            emit_ym(8'h54, 8'h1f);
            emit_ym(8'h58, 8'h1f);
            emit_ym(8'h5c, 8'h1f);
            emit_ym(8'ha4, 8'h22);
            emit_ym(8'ha0, 8'h69);
            emit_ym(8'hb0, 8'h07);
            emit_ym(8'hb4, 8'hc0);
            emit_ym(8'h28, 8'hf0);
        end
        if (fixture == 1 || fixture == 2 || fixture == 3) begin
            emit_psg(8'h80);
            emit_psg(8'h10);
            emit_psg(8'h90);
        end
        if (fixture == 3) begin
            // Known-good YM2203/JT49 channel-A fixed-volume tone.
            emit_ym2203(8'h00, 8'h20);
            emit_ym2203(8'h01, 8'h00);
            emit_ym2203(8'h07, 8'h3e);
            emit_ym2203(8'h08, 8'h0f);
        end
        if (fixture == 4)
            emit_dac_stream_fixture();
        emit_wait((fixture == 4) ? 64 : 2000);
        emit_byte(8'h66);
        vgm_mem[8'h04] = (build_pc - 4) & 8'hff;
        vgm_mem[8'h05] = ((build_pc - 4) >> 8) & 8'hff;

        repeat (8) @(posedge clk);
        reset_n = 1'b1;
        repeat (8) @(posedge clk);
        load_vgm();

        timeout = 0;
        while (!player_done && !player_error && timeout < 200_000) begin
            timeout++;
            @(posedge clk);
        end
        if (!player_done || player_error)
            $fatal(1, "production parser did not reach END timeout=%0d error=%0b",
                   timeout, player_error);
        done_cycle = system_cycle;
        if (dut.YM2151_EXPERIMENTAL_MODE !== 1'b1)
            $fatal(1, "production QSF did not select YM2151 mode");
        if (dut.MD_COMMANDS_ENABLED !== 1'b1)
            $fatal(1, "production QSF did not enable MD command decode");
        if (dut.loaded_vgm_mode.md_audio_session_active !== 1'b1)
            $fatal(1, "MD command activity did not enable the MD audio lane");
        expected_ym = (fixture == 1) ? 0 :
                      (fixture == 4) ? 65 : 20;
        expected_psg = (fixture == 1 || fixture == 2 || fixture == 3) ? 3 : 0;
        $display("BUILD_PROFILE production=%0d PSG=%0d YM2612=%0d JT51=%0d YM2203=%0d SEGAPCM=%0d MD_COMMANDS_ENABLED=%0d MD_AUDIO_STUB=%0d YM2151_EXPERIMENTAL_MODE=%0d C0_LAB=%0d DEV_OSD=%0d JT12_NTSC_CEN=%0d OUTPUT_SHIFT=%0d",
                 PROFILE_PRODUCTION, dut.MD_COMMANDS_ENABLED,
                 dut.MD_COMMANDS_ENABLED, dut.YM2151_EXPERIMENTAL_MODE,
                 dut.YM2151_EXPERIMENTAL_MODE,
                 dut.YM2151_EXPERIMENTAL_MODE, dut.MD_COMMANDS_ENABLED,
                 PROFILE_MD_AUDIO_STUB, dut.YM2151_EXPERIMENTAL_MODE,
                 PROFILE_C0_LAB, PROFILE_DEV_OSD,
                 PROFILE_JT12_NTSC_CEN, PROFILE_OUTPUT_SHIFT);
        $display("PRODUCTION_MD_TIMING fixture=%0d cycles=%0d first_ym=%0d last_ym=%0d done=%0d fm_cen=%0d psg_cen=%0d wait_ticks=%0d cen_i1=%0d cen_i2=%0d cen_i3=%0d cen_i4=%0d cen_ige5=%0d cen_min=%0d cen_max=%0d jt51_valid=%0d ym2203_valid=%0d segapcm_valid=%0d md_valid=%0d raw_valid=%0d valid_extra=%0d value_mismatch=%0d final_mismatch=%0d md_hash=%016h raw_hash=%016h final_hash=%016h",
                 fixture, system_cycle, first_ym_cycle, last_ym_cycle,
                 done_cycle, fm_cen_count, psg_cen_count, wait_tick_count,
                 dut.jt12_cen_interval_1_count,
                 dut.jt12_cen_interval_2_count,
                 dut.jt12_cen_interval_3_count,
                 dut.jt12_cen_interval_4_count,
                 dut.jt12_cen_interval_ge5_count,
                 dut.jt12_cen_interval_min, dut.jt12_cen_interval_max,
                 jt51_valid_count, ym2203_valid_count, segapcm_valid_count,
                 md_valid_count, raw_valid_count,
                 raw_valid_count - md_valid_count,
                 md_raw_value_mismatch_count,
                 final_raw_value_mismatch_count, md_sample_hash,
                 raw_on_md_valid_hash, final_on_md_valid_hash);
        $display("PRODUCTION_MD_ROUTE fixture=%0d select=%0d ym_parser=%0d psg_parser=%0d md_valid=%0d md_nonzero=%0d fm_raw_nonzero=%0d psg_raw_nonzero=%0d jt51_raw_nonzero=%0d ym2203_raw_nonzero=%0d selected_nonzero=%0d raw_valid=%0d raw_nonzero=%0d final_valid=%0d final_nonzero=%0d dropped=%0d xz=%0d",
                 fixture, audio_select,
                 parser_ym_pulses, parser_psg_pulses, md_valid_count,
                 md_nonzero_count, fm_raw_nonzero_count,
                 psg_raw_nonzero_count, jt51_raw_nonzero_count,
                 ym2203_raw_nonzero_count, md_selected_nonzero_count,
                 raw_valid_count, raw_nonzero_count,
                 final_valid_count, final_nonzero_count,
                 dut.ym_write_dropped_or_busy_count, xz_count);
        $display("PRODUCTION_FAMILY_NORMALIZATION fixture=%0d select=%0d arcade_mismatch=%0d sum_mismatch=%0d output_mismatch=%0d clips=%0d",
                 fixture, audio_select,
                 arcade_normalization_mismatch_count,
                 family_sum_mismatch_count, family_output_mismatch_count,
                 family_clip_count);
        if (fixture == 4)
            $display("PRODUCTION_MD_DAC_STREAM commands=%0d wait_samples=%0d cycles=%0d overhead=%0d max_cycles=%0d wait0=%0d",
                     dut.dac_stream_cmd_count,
                     dut.dac_stream_wait_samples_total,
                     dut.dac_stream_clk_cycles_total,
                     dut.dac_stream_overhead_cycles_total,
                     dut.max_dac_stream_cmd_cycles,
                     dut.count_wait0_dac_stream_cmd);
        if (parser_ym_pulses != expected_ym ||
            parser_psg_pulses != expected_psg ||
            dut.ym_write_requested_count != expected_ym ||
            dut.ym_write_accepted_count != expected_ym ||
            dut.ym_write_dropped_or_busy_count != 0 ||
            md_valid_count == 0 || md_nonzero_count == 0 ||
            raw_valid_count == 0 || final_valid_count == 0 || xz_count != 0 ||
            arcade_normalization_mismatch_count != 0 ||
            family_sum_mismatch_count != 0 ||
            family_output_mismatch_count != 0)
            $fatal(1, "production MD route counters failed");
        if (fixture != 1 && fm_raw_nonzero_count == 0)
            $fatal(1, "YM2612 fixture had no raw FM activity");
        if (expected_psg != 0 && psg_raw_nonzero_count == 0)
            $fatal(1, "PSG fixture had no raw PSG activity");
        if (fixture == 4 &&
            (dut.dac_stream_cmd_count != 64 ||
             dut.dac_stream_wait_samples_total != 0 ||
             dut.count_wait0_dac_stream_cmd != 64))
            $fatal(1, "YM2612 DAC stream accounting failed");
        if (fixture == 3 &&
            (dut.loaded_vgm_mode.ym2151_write_count != 0 ||
             dut.loaded_vgm_mode.ym2203_write_count != 4 ||
             ym2203_raw_nonzero_count == 0))
            $fatal(1, "combined fixture lost an arcade command/audio lane");
        if (audio_select == 3) begin
            if (md_selected_nonzero_count != 0 || raw_nonzero_count != 0 ||
                final_nonzero_count != 0)
                $fatal(1, "PCM Only did not mute the MD lane");
        end else if (md_selected_nonzero_count == 0 ||
                     raw_nonzero_count == 0 || final_nonzero_count == 0) begin
            $fatal(1, "Normal/FM Only lost the MD lane");
        end
        if (fixture != 3 && audio_select != 3 &&
            (md_raw_value_mismatch_count != 0 ||
             final_raw_value_mismatch_count != 0 ||
             md_sample_hash != raw_on_md_valid_hash ||
             raw_on_md_valid_hash != final_on_md_valid_hash))
            $fatal(1, "MD-only value route is not bit-identical");

        $display("PASS tb_production_ym2612_route_repro fixture=%0d select=%0d",
                 fixture, audio_select);
        $finish;
    end
endmodule
/* verilator lint_on BLKSEQ */
/* verilator lint_on PROCASSINIT */

`timescale 1ns/1ps

import jt10_phase4a_adpcmb_reference::*;

module tb_jt10_phase4a_adpcmb_single_shot;
    localparam logic [63:0] ANCHOR_RAW    = 64'he60907109cc90925;
    localparam logic [63:0] ANCHOR_LOGICAL=64'hd3f50a660ff4da1a;
    localparam logic [63:0] ANCHOR_DELTA  = 64'h3ef011c519a87325;
    localparam logic [63:0] ANCHOR_DECODER= 64'h46ce068d48f530a5;
    localparam logic [63:0] ANCHOR_INTERPOL=64'h977cceaa11432cb1;
    localparam logic [63:0] ANCHOR_GAIN_FULL=64'hc44dda0e59862d8a;
    localparam logic [63:0] ANCHOR_LANE_FULL=64'h16e284660dfd24e1;
    localparam logic [63:0] ANCHOR_ACTIVE_GAIN=64'ha009ad964647c074;
    localparam logic [63:0] ANCHOR_ACTIVE_LANE=64'ha9a4d74927a92055;
    localparam logic [63:0] ANCHOR_FINAL=64'he142f7da424b1531;
    localparam logic [15:0] SHORT_START = 16'h0020;
    localparam logic [15:0] SHORT_END   = 16'h0020;
    localparam logic [15:0] LONG_START  = 16'h0020;
    localparam logic [15:0] LONG_END    = 16'h004f;
    localparam logic [15:0] SHIFT_START = 16'h0021;
    localparam logic [15:0] SHIFT_END   = 16'h0050;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cen = 1'b1;
    logic session_start = 1'b1;
    logic loop_event = 1'b0;
    logic changed_pattern = 1'b0;
    integer run_id = 1;
    integer quick_mode = 0;
    integer failures = 0;
    integer system_cycle = 0;

    wire [1:0] bus_addr;
    wire [7:0] bus_din;
    wire bus_cs_n;
    wire bus_wr_n;
    wire [7:0] dout;
    wire irq_n;
    wire [19:0] adpcma_addr;
    wire [3:0] adpcma_bank;
    wire adpcma_roe_n;
    wire [7:0] adpcma_data = 8'h00;
    wire [23:0] adpcmb_addr;
    wire adpcmb_roe_n;
    wire [7:0] adpcmb_data;
    wire [7:0] psg_A, psg_B, psg_C;
    wire [9:0] psg_snd;
    wire signed [15:0] snd_left, snd_right;
    wire snd_sample;
    wire signed [15:0] internal_snd_left, internal_snd_right;
    wire internal_snd_sample;
    wire signed [15:0] internal_fm_snd;
    wire [2:0] warmup_count, reset_cen_count;
    wire warmup_ready, reset_cen_valid;

    wire clk_en = dut.u_jt10.u_jt12.clk_en;
    wire clk_en_55 = dut.u_jt10.u_jt12.clk_en_55;
    wire b_on = dut.u_jt10.u_jt12.acmd_on_b;
    wire b_repeat = dut.u_jt10.u_jt12.acmd_rep_b;
    wire b_reset = dut.u_jt10.u_jt12.acmd_rst_b;
    wire b_update = dut.u_jt10.u_jt12.acmd_up_b;
    wire [1:0] b_pan = dut.u_jt10.u_jt12.alr_b;
    wire [15:0] b_start = dut.u_jt10.u_jt12.astart_b;
    wire [15:0] b_end = dut.u_jt10.u_jt12.aend_b;
    wire [15:0] b_delta = dut.u_jt10.u_jt12.adeltan_b;
    wire [7:0] b_level = dut.u_jt10.u_jt12.aeg_b;
    wire b_flag = dut.u_jt10.u_jt12.adpcmb_flag;
    wire b_chon = dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.chon;
    wire b_restart = dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.restart;
    wire b_adv = dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.adv;
    wire b_nibble = dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.nibble_sel;
    wire [15:0] b_delta_count =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.u_cnt.cnt;
    wire [3:0] b_present = dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.din;
    wire signed [15:0] b_decoder =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.pcmdec;
    wire signed [15:0] b_interpolation =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.pcminter;
    wire signed [15:0] b_gain =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.pcmgain;
    wire signed [15:0] b_lane_l = dut.u_jt10.u_jt12.adpcmB_l;
    wire signed [15:0] b_lane_r = dut.u_jt10.u_jt12.adpcmB_r;
    wire signed [15:0] decoder_x =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.u_decoder.x1;
    wire [14:0] decoder_step =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.u_decoder.step1;
    wire [3:0] decoder_adv_pipe =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.u_decoder.adv2;
    wire decoder_need_clear =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.u_decoder.need_clr;
    wire signed [15:0] interpolation_last =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.u_interpol.pcmlast;
    wire [15:0] interpolation_step =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.u_interpol.step;
    wire interpolation_step_sign =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.u_interpol.step_sign;
    wire signed [15:0] acc_input_l =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_input_l;
    wire signed [15:0] acc_input_r =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_input_r;
    wire [2:0] final_cur_ch = dut.u_jt10.u_jt12.cur_ch;
    wire [1:0] final_cur_op = dut.u_jt10.u_jt12.cur_op;
    wire final_zero = dut.u_jt10.u_jt12.zero;
    wire [5:0] adpcma_active = {
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on6,
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on5,
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on4,
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on3,
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on2,
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on1
    };

    wire [31:0] accepted_write_count, port0_write_count, port1_write_count;
    wire [31:0] busy_timeout_count, busy_while_write_count;
    wire [31:0] busy_min_cycles, busy_max_cycles;
    wire [31:0] last_issue_cycle, last_busy_assert_cycle;
    wire [31:0] last_busy_clear_cycle;
    wire [63:0] busy_duration_hash;

    reg [8*32-1:0] case_name = "BOOT";
    logic monitor_on = 1'b0;
    logic inactive_on = 1'b0;
    logic engines_configured = 1'b0;
    logic previous_public = 1'b0;
    logic previous_internal = 1'b0;
    logic previous_chon = 1'b0;
    logic previous_flag = 1'b0;
    integer public_samples = 0;
    integer internal_pulses = 0;
    integer first_public_internal = -1;
    integer last_public_cycle = -1;
    integer public_width = 0;
    integer cadence_errors = 0;
    integer width_errors = 0;
    integer drops = 0;
    integer duplicates = 0;
    integer global_x = 0;
    integer idle_adpcma_active = 0;
    integer idle_adpcma_raw = 0;
    integer idle_adpcma_logical = 0;
    integer idle_adpcma_lane = 0;
    integer idle_fm = 0;
    integer idle_ssg = 0;
    integer idle_ssg_control = 0;

    integer case_start_cycle, case_public, case_raw, case_capture;
    integer case_logical, case_high, case_low, case_decoder;
    integer case_delta_commits, case_delta_carries, case_cursor;
    integer case_interpolation, case_gain, case_lane, case_acc, case_final;
    integer case_x, case_range, case_arith_compares, case_arith_mismatch;
    integer case_first_raw, case_first_capture, case_first_logical;
    integer case_first_carry, case_first_decoder, case_first_interpolation;
    integer case_first_gain, case_first_lane, case_first_final;
    integer case_start_accept, case_reset_accept, case_active_assert;
    integer case_active_clear, case_eos_set, case_eos_clear;
    integer case_nonzero_l, case_nonzero_r, case_pan_leak;
    integer case_zero_cross_l, case_zero_cross_r;
    integer case_min_l, case_max_l, case_min_r, case_max_r;
    integer case_peak, case_stale_prefix, case_repeat_restart;
    integer signed case_dc_l, case_dc_r;
    integer last_logical_cycle, interval_144, interval_288;
    integer interval_432, interval_576, interval_other;
    integer unique_addresses;
    logic [23:0] last_unique_address;
    logic [23:0] case_first_raw_address, case_first_logical_address;
    logic seen_unique_address;
    logic signed [15:0] prior_l, prior_r;
    logic [63:0] case_raw_hash, case_raw_cycle_hash;
    logic [63:0] case_logical_hash, case_rom_hash, case_delta_hash;
    logic [63:0] case_decoder_hash, case_interpolation_hash;
    logic [63:0] case_gain_hash, case_lane_hash;
    logic [63:0] case_left_hash, case_right_hash, case_stereo_hash;
    logic [63:0] case_full_gain_hash, case_full_lane_hash;
    logic [63:0] case_all_stereo_hash, case_address_hash;

    logic [63:0] anchor_raw_hash, anchor_logical_hash, anchor_rom_hash;
    logic [63:0] anchor_delta_hash, anchor_decoder_hash;
    logic [63:0] anchor_interpolation_hash, anchor_gain_hash;
    logic [63:0] anchor_lane_hash, anchor_stereo_hash;
    integer anchor_rel_raw, anchor_rel_logical, anchor_rel_assert;
    integer anchor_rel_clear, anchor_rel_eos;

    logic [63:0] primary_raw_hash, primary_raw_cycle_hash;
    logic [63:0] primary_logical_hash, primary_rom_hash;
    logic [63:0] primary_decoder_hash, primary_interpolation_hash;
    logic [63:0] primary_gain_hash, primary_lane_hash;
    logic [63:0] primary_left_hash, primary_right_hash;
    logic [63:0] primary_stereo_hash;
    integer primary_logical_count;
    logic signed [15:0] stale_l, stale_r;
    logic stale_open;

    always #5 clk = ~clk;

    task automatic check(input logic condition,
                         input [8*112-1:0] message);
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("PHASE4A_FAIL run=%0d case=%0s cycle=%0d reason=%0s",
                    run_id, case_name, system_cycle, message);
            end
        end
    endtask

    task automatic wait_public(input integer count);
        integer target;
        begin
            target = public_samples + count;
            wait (public_samples >= target);
        end
    endtask

    task automatic align_start;
        begin
            while ((system_cycle % 432) != 50)
                @(posedge clk);
        end
    endtask

    task automatic keyoff_fm;
        begin
            bus.jt10_write_port0(8'h28, 8'h00);
            bus.jt10_write_port0(8'h28, 8'h01);
            bus.jt10_write_port0(8'h28, 8'h02);
            bus.jt10_write_port0(8'h28, 8'h04);
            bus.jt10_write_port0(8'h28, 8'h05);
            bus.jt10_write_port0(8'h28, 8'h06);
        end
    endtask

    task automatic reset_metrics(input [8*32-1:0] label);
        begin
            case_name = label;
            case_start_cycle = system_cycle;
            case_public = 0; case_raw = 0; case_capture = 0;
            case_logical = 0; case_high = 0; case_low = 0;
            case_decoder = 0; case_delta_commits = 0;
            case_delta_carries = 0; case_cursor = 0;
            case_interpolation = 0; case_gain = 0; case_lane = 0;
            case_acc = 0; case_final = 0; case_x = 0; case_range = 0;
            case_arith_compares = 0; case_arith_mismatch = 0;
            case_first_raw = -1; case_first_capture = -1;
            case_first_logical = -1; case_first_carry = -1;
            case_first_decoder = -1; case_first_interpolation = -1;
            case_first_gain = -1; case_first_lane = -1;
            case_first_final = -1; case_start_accept = -1;
            case_reset_accept = -1; case_active_assert = -1;
            case_active_clear = -1; case_eos_set = -1;
            case_eos_clear = -1; case_nonzero_l = 0;
            case_nonzero_r = 0; case_pan_leak = 0;
            case_zero_cross_l = 0; case_zero_cross_r = 0;
            case_min_l = 32767; case_max_l = -32768;
            case_min_r = 32767; case_max_r = -32768;
            case_peak = 0; case_dc_l = 0; case_dc_r = 0;
            case_stale_prefix = 0; case_repeat_restart = 0;
            last_logical_cycle = -1; interval_144 = 0;
            interval_288 = 0; interval_432 = 0; interval_576 = 0;
            interval_other = 0; unique_addresses = 0;
            seen_unique_address = 1'b0; last_unique_address = 24'd0;
            case_first_raw_address = 24'hffffff;
            case_first_logical_address = 24'hffffff;
            prior_l = 16'sd0; prior_r = 16'sd0;
            stale_l = snd_left; stale_r = snd_right;
            stale_open = stale_l != 0 || stale_r != 0;
            case_raw_hash = FNV_OFFSET;
            case_raw_cycle_hash = FNV_OFFSET;
            case_logical_hash = FNV_OFFSET;
            case_rom_hash = FNV_OFFSET;
            case_delta_hash = FNV_OFFSET;
            case_decoder_hash = FNV_OFFSET;
            case_interpolation_hash = FNV_OFFSET;
            case_gain_hash = FNV_OFFSET;
            case_lane_hash = FNV_OFFSET;
            case_left_hash = FNV_OFFSET;
            case_right_hash = FNV_OFFSET;
            case_stereo_hash = FNV_OFFSET;
            case_full_gain_hash = FNV_OFFSET;
            case_full_lane_hash = FNV_OFFSET;
            case_all_stereo_hash = FNV_OFFSET;
            case_address_hash = FNV_OFFSET;
        end
    endtask

    task automatic global_reset;
        begin
            monitor_on = 1'b0;
            inactive_on = 1'b0;
            engines_configured = 1'b0;
            while ((system_cycle % 432) != 0)
                @(posedge clk);
            @(negedge clk);
            rst = 1'b1;
            session_start = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            session_start = 1'b0;
            repeat (64) @(posedge clk);
            check(reset_cen_count === 3'd6 && reset_cen_valid,
                  "RESET_CEN_CONTRACT");
            @(negedge clk);
            rst = 1'b0;
            wait (warmup_ready === 1'b1);
            wait (snd_sample === 1'b1);
        end
    endtask

    task automatic explicit_silence;
        begin
            keyoff_fm();
            bus.jt10_write_port0(8'h22, 8'h00);
            bus.jt10_write_port0(8'h27, 8'h00);
            bus.jt10_write_port0(8'h2b, 8'h00);
            bus.jt10_write_port0(8'h08, 8'h00);
            bus.jt10_write_port0(8'h09, 8'h00);
            bus.jt10_write_port0(8'h0a, 8'h00);
            bus.jt10_write_port0(8'h06, 8'h00);
            bus.jt10_write_port0(8'h07, 8'h3f);
            bus.jt10_write_port1(8'h00, 8'hbf);
            // Let the ADPCM-A request pipeline and the keyed-off FM path
            // drain before any scenario observer is enabled.
            repeat (2304) @(posedge clk);
            bus.jt10_write_port0(8'h10, 8'h01);
            bus.jt10_write_port0(8'h1c, 8'h80);
            bus.jt10_write_port0(8'h10, 8'h00);
            engines_configured = 1'b1;
        end
    endtask

    task automatic fresh_silence(input [8*32-1:0] label);
        begin
            global_reset();
            explicit_silence();
            changed_pattern = 1'b0;
            reset_metrics(label);
            monitor_on = 1'b0;
        end
    endtask

    task automatic configure_b(
        input logic [15:0] start_value,
        input logic [15:0] end_value,
        input logic [15:0] delta_value,
        input logic [7:0] pan_value,
        input logic [7:0] level_value,
        input integer order
    );
        begin
            if (order == 1) begin
                bus.jt10_write_port0(8'h1b, level_value);
                bus.jt10_write_port0(8'h11, pan_value);
            end else begin
                bus.jt10_write_port0(8'h11, pan_value);
                if (order == 0)
                    bus.jt10_write_port0(8'h1b, level_value);
            end
            bus.jt10_write_port0(8'h12, start_value[7:0]);
            bus.jt10_write_port0(8'h13, start_value[15:8]);
            bus.jt10_write_port0(8'h14, end_value[7:0]);
            bus.jt10_write_port0(8'h15, end_value[15:8]);
            bus.jt10_write_port0(8'h19, delta_value[7:0]);
            bus.jt10_write_port0(8'h1a, delta_value[15:8]);
            if (order == 2)
                bus.jt10_write_port0(8'h1b, level_value);
            check(b_start === start_value && b_end === end_value,
                  "ADDRESS_REGISTER_CAPTURE");
            check(b_delta === delta_value, "DELTA_REGISTER_CAPTURE");
            check(b_pan === pan_value[7:6], "PAN_REGISTER_CAPTURE");
            check(b_level === level_value, "LEVEL_REGISTER_CAPTURE");
            check(b_repeat === 1'b0, "REPEAT_NOT_DISABLED");
        end
    endtask

    task automatic start_b;
        begin
            align_start();
            bus.jt10_write_port0(8'h10, 8'h80);
            wait (b_chon === 1'b1);
            check(b_repeat === 1'b0 && b_reset === 1'b0 && b_on === 1'b1,
                  "START_CONTROL_BITS");
        end
    endtask

    task automatic reset_b;
        begin
            bus.jt10_write_port0(8'h10, 8'h01);
            wait (b_chon === 1'b0);
            wait (adpcmb_roe_n === 1'b1);
        end
    endtask

    task automatic print_metrics(input [8*32-1:0] label);
        begin
            $display("PHASE4A_CASE run=%0d stage=%0s public=%0d raw=%0d capture=%0d logical=%0d high=%0d low=%0d unique=%0d decoder=%0d delta=%0d carry=%0d cursor=%0d interpolation=%0d gain=%0d lane=%0d acc=%0d final=%0d first=%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d start=%0d assert=%0d clear=%0d eos_set=%0d eos_clear=%0d intervals=%0d/%0d/%0d/%0d/%0d raw_hash=%016h raw_cycle_hash=%016h logical_hash=%016h rom_hash=%016h delta_hash=%016h decoder_hash=%016h interpolation_hash=%016h gain_hash=%016h lane_hash=%016h left_hash=%016h right_hash=%016h stereo_hash=%016h full_gain=%016h full_lane=%016h nonzero=%0d/%0d peak=%0d minmax=%0d/%0d/%0d/%0d crossing=%0d/%0d dc=%0d/%0d range=%0d stale=%0d repeat=%0d arithmetic=%0d/%0d x=%0d",
                run_id, label, case_public, case_raw, case_capture,
                case_logical, case_high, case_low, unique_addresses,
                case_decoder, case_delta_commits, case_delta_carries,
                case_cursor, case_interpolation, case_gain, case_lane,
                case_acc, case_final, case_first_raw, case_first_capture,
                case_first_logical, case_first_carry, case_first_decoder,
                case_first_interpolation, case_first_gain, case_first_lane,
                case_first_final, case_start_accept, case_active_assert,
                case_active_clear, case_eos_set, case_eos_clear,
                interval_144, interval_288, interval_432, interval_576,
                interval_other, case_raw_hash, case_raw_cycle_hash,
                case_logical_hash, case_rom_hash, case_delta_hash,
                case_decoder_hash, case_interpolation_hash,
                case_gain_hash, case_lane_hash, case_left_hash,
                case_right_hash, case_stereo_hash, case_full_gain_hash,
                case_full_lane_hash, case_nonzero_l, case_nonzero_r,
                case_peak, case_min_l, case_max_l, case_min_r, case_max_r,
                case_zero_cross_l, case_zero_cross_r, case_dc_l, case_dc_r,
                case_range, case_stale_prefix, case_repeat_restart,
                case_arith_compares, case_arith_mismatch, case_x);
            $display("PHASE4A_AUX run=%0d stage=%0s address_hash=%016h all_stereo_hash=%016h",
                run_id, label, case_address_hash, case_all_stereo_hash);
        end
    endtask

    always @(posedge clk) begin : phase4a_monitor
        logic pre_clk55, pre_clk, pre_raw, pre_owned_raw;
        logic pre_logical, pre_decoder_commit, pre_cursor_commit;
        logic pre_start_accept, pre_reset_accept, pre_natural_end;
        logic [15:0] pre_count;
        logic [23:0] pre_address;
        logic pre_nibble;
        logic [3:0] pre_present;
        logic pre_adv;
        logic [16:0] expected_delta;
        logic signed [15:0] pre_decoder_candidate;
        logic signed [15:0] pre_decoder_x;
        logic pre_decoder_sign;
        logic [16:0] pre_decoder_step_candidate;
        logic signed [15:0] pre_interpolation, pre_interpolation_last;
        logic [15:0] pre_interpolation_step;
        logic pre_interpolation_sign;
        logic signed [15:0] pre_gain;
        logic pre_chon;
        logic [1:0] pre_pan;
        logic [7:0] pre_level;
        logic signed [15:0] pre_acc_l, pre_acc_r;
        logic signed [15:0] pre_current_l, pre_current_r;
        logic signed [15:0] pre_snd_l, pre_snd_r;
        logic pre_zero;
        logic internal_rise, public_rise;
        logic [7:0] expected_byte;
        logic [7:0] expected_raw_byte;
        logic [3:0] expected_nibble;
        logic signed [15:0] expected_value;
        logic signed [15:0] expected_value_r;
        integer logical_interval;
        integer abs_value;

        system_cycle = system_cycle + 1;
        pre_clk55 = cen && clk_en_55;
        pre_clk = cen && clk_en;
        pre_raw = adpcmb_roe_n === 1'b0;
        pre_owned_raw = pre_raw && (b_chon || b_restart);
        pre_logical = pre_clk55 && b_adv && b_chon &&
                      !b_restart && !b_flag;
        pre_decoder_commit = cen && decoder_adv_pipe[0] && b_chon &&
                             !decoder_need_clear;
        pre_cursor_commit = pre_clk55 &&
                            ((b_restart && b_adv) || (b_chon && b_adv));
        pre_start_accept = b_update && b_on;
        pre_reset_accept = b_update && b_reset;
        pre_natural_end = pre_clk55 && b_chon && b_adv && !b_repeat &&
                          {adpcmb_addr, b_nibble} ==
                          {b_end, 8'hff, 1'b1};
        pre_count = b_delta_count;
        pre_address = adpcmb_addr;
        pre_nibble = b_nibble;
        pre_present = b_present;
        pre_adv = b_adv;
        expected_delta = delta_sum(pre_count, b_delta);
        pre_decoder_candidate =
            dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.u_decoder.next_x5;
        pre_decoder_x = decoder_x;
        pre_decoder_sign =
            dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.u_decoder.sign_data5;
        pre_decoder_step_candidate =
            dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.u_decoder.next_step3;
        pre_interpolation = b_interpolation;
        pre_interpolation_last = interpolation_last;
        pre_interpolation_step = interpolation_step;
        pre_interpolation_sign = interpolation_step_sign;
        pre_gain = b_gain;
        pre_chon = b_chon;
        pre_pan = b_pan;
        pre_level = b_level;
        pre_acc_l = dut.u_jt10.u_jt12.gen_adpcm.u_acc.u_left.acc;
        pre_acc_r = dut.u_jt10.u_jt12.gen_adpcm.u_acc.u_right.acc;
        pre_current_l = dut.u_jt10.u_jt12.gen_adpcm.u_acc.u_left.current;
        pre_current_r = dut.u_jt10.u_jt12.gen_adpcm.u_acc.u_right.current;
        pre_snd_l = dut.u_jt10.u_jt12.gen_adpcm.u_acc.u_left.snd;
        pre_snd_r = dut.u_jt10.u_jt12.gen_adpcm.u_acc.u_right.snd;
        pre_zero = final_zero;
        expected_byte = changed_pattern ?
            rom_changed(pre_address) : rom_primary(pre_address);
        expected_nibble = pre_nibble ? expected_byte[3:0] :
                                      expected_byte[7:4];

        #1;
        expected_raw_byte = changed_pattern ?
            rom_changed(adpcmb_addr) : rom_primary(adpcmb_addr);
        internal_rise = internal_snd_sample && !previous_internal;
        public_rise = snd_sample && !previous_public;

        if (rst || session_start) begin
            previous_public = 1'b0;
            previous_internal = 1'b0;
            previous_chon = 1'b0;
            previous_flag = 1'b0;
            public_width = 0;
            last_public_cycle = -1;
            internal_pulses = 0;
        end else begin
            if (internal_rise)
                internal_pulses = internal_pulses + 1;
            if (public_rise) begin
                public_samples = public_samples + 1;
                if (first_public_internal < 0)
                    first_public_internal = internal_pulses + 1;
                if (!internal_rise)
                    duplicates = duplicates + 1;
                if (last_public_cycle >= 0 &&
                    system_cycle - last_public_cycle != 144)
                    cadence_errors = cadence_errors + 1;
                last_public_cycle = system_cycle;
            end
            if (internal_rise && warmup_ready && !snd_sample)
                drops = drops + 1;
            if (snd_sample)
                public_width = public_width + 1;
            else if (previous_public) begin
                if (public_width != 6)
                    width_errors = width_errors + 1;
                public_width = 0;
            end
        end

        if (monitor_on) begin
            if (pre_start_accept && case_start_accept < 0)
                case_start_accept = system_cycle;
            if (pre_reset_accept && case_reset_accept < 0)
                case_reset_accept = system_cycle;
            if (b_chon && !previous_chon && case_active_assert < 0)
                case_active_assert = system_cycle;
            if (!b_chon && previous_chon) begin
                if (case_active_clear < 0)
                    case_active_clear = system_cycle;
                else
                    case_repeat_restart = case_repeat_restart + 1;
            end
            if (b_flag && !previous_flag && case_eos_set < 0)
                case_eos_set = system_cycle;
            if (!b_flag && previous_flag && case_eos_clear < 0)
                case_eos_clear = system_cycle;

            if (pre_owned_raw) begin
                case_raw = case_raw + 1;
                case_capture = case_capture + 1;
                if (case_first_raw < 0) begin
                    case_first_raw = system_cycle;
                    case_first_raw_address = adpcmb_addr;
                end
                if (case_first_capture < 0)
                    case_first_capture = system_cycle;
                case_raw_hash = hash_u24(case_raw_hash, adpcmb_addr);
                case_raw_hash = hash_byte(case_raw_hash, adpcmb_data);
                case_raw_cycle_hash = hash_u16(case_raw_cycle_hash,
                    system_cycle - case_start_cycle);
                if (case_raw <= 64 && case_name == "E_PRIMARY")
                    $display("PHASE4A_RAW64 run=%0d case=%0s index=%0d cycle=%0d address=%06h data=%02h",
                        run_id, case_name, case_raw, system_cycle,
                        adpcmb_addr, adpcmb_data);
                if (adpcmb_data !== expected_raw_byte) begin
                    case_arith_mismatch = case_arith_mismatch + 1;
                    $display("PHASE4A_ARITH_FAIL case=%0s kind=ROM address=%06h expected=%02h actual=%02h",
                        case_name, adpcmb_addr, expected_raw_byte,
                        adpcmb_data);
                end
                case_arith_compares = case_arith_compares + 1;
                if ($isunknown(adpcmb_addr) ||
                    $isunknown(adpcmb_data) ||
                    $isunknown(adpcmb_roe_n))
                    case_x = case_x + 1;
            end

            if (pre_logical) begin
                case_logical = case_logical + 1;
                if (case_first_logical < 0) begin
                    case_first_logical = system_cycle;
                    case_first_logical_address = pre_address;
                end
                if (pre_nibble)
                    case_low = case_low + 1;
                else
                    case_high = case_high + 1;
                if (!seen_unique_address ||
                    pre_address != last_unique_address) begin
                    unique_addresses = unique_addresses + 1;
                    last_unique_address = pre_address;
                    seen_unique_address = 1'b1;
                end
                if (pre_address < {b_start, 8'h00} ||
                    pre_address > {b_end, 8'hff})
                    case_range = case_range + 1;
                case_logical_hash = hash_u24(case_logical_hash,
                                             adpcmb_addr);
                case_address_hash = hash_u24(case_address_hash,
                                             adpcmb_addr);
                case_logical_hash = hash_byte(case_logical_hash,
                    {3'd0, b_nibble, b_present});
                case_rom_hash = hash_byte(case_rom_hash, expected_byte);
                case_rom_hash = hash_byte(case_rom_hash,
                    {4'd0, expected_nibble});
                case_delta_hash = hash_u16(case_delta_hash, b_delta_count);
                if (last_logical_cycle >= 0) begin
                    logical_interval = system_cycle - last_logical_cycle;
                    case (logical_interval)
                        144: interval_144 = interval_144 + 1;
                        288: interval_288 = interval_288 + 1;
                        432: interval_432 = interval_432 + 1;
                        576: interval_576 = interval_576 + 1;
                        default: interval_other = interval_other + 1;
                    endcase
                end
                last_logical_cycle = system_cycle;
                if (case_logical <= 64 && case_name == "E_PRIMARY")
                    $display("PHASE4A_LOGICAL64 run=%0d case=%0s index=%0d cycle=%0d address=%06h nibble=%0d byte=%02h value=%x",
                        run_id, case_name, case_logical, system_cycle,
                        pre_address, pre_nibble, expected_byte, pre_present);
                case_arith_compares = case_arith_compares + 1;
                if (pre_present !== expected_nibble) begin
                    case_arith_mismatch = case_arith_mismatch + 1;
                    $display("PHASE4A_ARITH_FAIL case=%0s kind=NIBBLE address=%06h select=%0d expected=%x actual=%x",
                        case_name, pre_address, pre_nibble,
                        expected_nibble, pre_present);
                end
                if ($isunknown(pre_address) || $isunknown(pre_nibble) ||
                    $isunknown(pre_present) || $isunknown(b_delta_count))
                    case_x = case_x + 1;
            end

            if (pre_clk55) begin
                case_delta_commits = case_delta_commits + 1;
                case_full_gain_hash = hash_u16(case_full_gain_hash, b_gain);
                case_full_lane_hash = hash_stereo(case_full_lane_hash,
                                                  b_lane_l, b_lane_r);
                if (!pre_start_accept) begin
                    case_arith_compares = case_arith_compares + 1;
                    if (b_reset) begin
                        if (b_delta_count !== 16'd0 || b_adv !== 1'b0)
                            case_arith_mismatch = case_arith_mismatch + 1;
                    end else if (b_on) begin
                        if ({b_adv, b_delta_count} !== expected_delta)
                            case_arith_mismatch = case_arith_mismatch + 1;
                    end else if (b_delta_count !== 16'd0 || b_adv !== 1'b1)
                        case_arith_mismatch = case_arith_mismatch + 1;
                end
                if (b_on && !b_reset && expected_delta[16]) begin
                    case_delta_carries = case_delta_carries + 1;
                    if (case_first_carry < 0)
                        case_first_carry = system_cycle;
                end
                if ($isunknown(b_delta_count) || $isunknown(b_adv))
                    case_x = case_x + 1;
            end

            if (pre_cursor_commit)
                case_cursor = case_cursor + 1;

            if (pre_decoder_commit) begin
                case_decoder = case_decoder + 1;
                if (case_first_decoder < 0)
                    case_first_decoder = system_cycle;
                case_decoder_hash = hash_u16(case_decoder_hash, decoder_x);
                case_decoder_hash = hash_u16(case_decoder_hash,
                                              decoder_step);
                case_arith_compares = case_arith_compares + 2;
                expected_value = decoder_next_sample(
                    pre_decoder_x,
                    pre_decoder_candidate, pre_decoder_sign);
                if (decoder_x !== expected_value)
                    case_arith_mismatch = case_arith_mismatch + 1;
                if (decoder_step !==
                    decoder_next_step(pre_decoder_step_candidate))
                    case_arith_mismatch = case_arith_mismatch + 1;
                if ($isunknown(decoder_x) || $isunknown(decoder_step) ||
                    $isunknown(decoder_adv_pipe))
                    case_x = case_x + 1;
            end

            if (pre_clk55 && b_chon && !pre_start_accept) begin
                case_interpolation = case_interpolation + 1;
                if (case_first_interpolation < 0)
                    case_first_interpolation = system_cycle;
                case_interpolation_hash = hash_u16(
                    case_interpolation_hash, b_interpolation);
                expected_value = interpolation_next(pre_interpolation,
                    pre_interpolation_last, pre_interpolation_step,
                    pre_interpolation_sign, pre_adv);
                case_arith_compares = case_arith_compares + 1;
                if (b_interpolation !== expected_value)
                    case_arith_mismatch = case_arith_mismatch + 1;
                if ($isunknown(b_interpolation) ||
                    $isunknown(interpolation_last) ||
                    $isunknown(interpolation_step))
                    case_x = case_x + 1;
            end

            if (pre_clk55 && !pre_start_accept) begin
                case_gain = case_gain + 1;
                case_lane = case_lane + 1;
                if (case_first_gain < 0)
                    case_first_gain = system_cycle;
                if (case_first_lane < 0)
                    case_first_lane = system_cycle;
                if (b_chon) begin
                    case_gain_hash = hash_u16(case_gain_hash, b_gain);
                    case_lane_hash = hash_stereo(case_lane_hash,
                                                 b_lane_l, b_lane_r);
                end
                expected_value = gain_next(pre_interpolation, pre_level);
                case_arith_compares = case_arith_compares + 3;
                if (b_gain !== expected_value)
                    case_arith_mismatch = case_arith_mismatch + 1;
                expected_value = lane_next(pre_chon, pre_pan[1], pre_gain);
                expected_value_r = lane_next(pre_chon, pre_pan[0], pre_gain);
                if (b_lane_l !== expected_value)
                    case_arith_mismatch = case_arith_mismatch + 1;
                if (b_lane_r !== expected_value_r)
                    case_arith_mismatch = case_arith_mismatch + 1;
                if ($isunknown(b_gain) || $isunknown(b_lane_l) ||
                    $isunknown(b_lane_r))
                    case_x = case_x + 1;
            end

            if (pre_clk && final_cur_op == 2'd0 &&
                final_cur_ch == 3'd4) begin
                case_acc = case_acc + 1;
                case_arith_compares = case_arith_compares + 2;
                if (acc_input_l !== accumulator_b_input(b_lane_l))
                    case_arith_mismatch = case_arith_mismatch + 1;
                if (acc_input_r !== accumulator_b_input(b_lane_r))
                    case_arith_mismatch = case_arith_mismatch + 1;
                if ($isunknown(acc_input_l) || $isunknown(acc_input_r))
                    case_x = case_x + 1;
            end

            if (pre_clk) begin
                case_arith_compares = case_arith_compares + 2;
                expected_value = accumulator_next(pre_acc_l,
                                                   pre_current_l, pre_zero);
                expected_value_r = accumulator_next(pre_acc_r,
                                                     pre_current_r, pre_zero);
                if ($signed(dut.u_jt10.u_jt12.gen_adpcm.u_acc.u_left.acc)
                    !== expected_value)
                    case_arith_mismatch = case_arith_mismatch + 1;
                if ($signed(dut.u_jt10.u_jt12.gen_adpcm.u_acc.u_right.acc)
                    !== expected_value_r)
                    case_arith_mismatch = case_arith_mismatch + 1;
                if (pre_zero) begin
                    case_arith_compares = case_arith_compares + 2;
                    if (internal_snd_left !== pre_acc_l)
                        case_arith_mismatch = case_arith_mismatch + 1;
                    if (internal_snd_right !== pre_acc_r)
                        case_arith_mismatch = case_arith_mismatch + 1;
                end else begin
                    if (internal_snd_left !== pre_snd_l ||
                        internal_snd_right !== pre_snd_r)
                        case_arith_mismatch = case_arith_mismatch + 1;
                end
            end

            if (pre_clk && pre_zero) begin
                case_final = case_final + 1;
                if (case_first_final < 0)
                    case_first_final = system_cycle;
                if ($isunknown(internal_snd_left) ||
                    $isunknown(internal_snd_right))
                    case_x = case_x + 1;
            end

            if (public_rise) begin
                case_public = case_public + 1;
                case_all_stereo_hash = hash_stereo(case_all_stereo_hash,
                                                   snd_left, snd_right);
                if (b_chon) begin
                    case_left_hash = hash_u16(case_left_hash, snd_left);
                    case_right_hash = hash_u16(case_right_hash, snd_right);
                    case_stereo_hash = hash_stereo(case_stereo_hash,
                                                   snd_left, snd_right);
                end
                if (snd_left != 0) case_nonzero_l = case_nonzero_l + 1;
                if (snd_right != 0) case_nonzero_r = case_nonzero_r + 1;
                if ((b_pan == 2'b10 && snd_right != 0) ||
                    (b_pan == 2'b01 && snd_left != 0))
                    case_pan_leak = case_pan_leak + 1;
                if ($signed(snd_left) < case_min_l) case_min_l = $signed(snd_left);
                if ($signed(snd_left) > case_max_l) case_max_l = $signed(snd_left);
                if ($signed(snd_right) < case_min_r) case_min_r = $signed(snd_right);
                if ($signed(snd_right) > case_max_r) case_max_r = $signed(snd_right);
                abs_value = $signed(snd_left) < 0 ? -$signed(snd_left) :
                                                   $signed(snd_left);
                if (abs_value > case_peak) case_peak = abs_value;
                abs_value = $signed(snd_right) < 0 ? -$signed(snd_right) :
                                                    $signed(snd_right);
                if (abs_value > case_peak) case_peak = abs_value;
                case_dc_l = case_dc_l + $signed(snd_left);
                case_dc_r = case_dc_r + $signed(snd_right);
                if ((prior_l < 0 && $signed(snd_left) >= 0) ||
                    (prior_l >= 0 && $signed(snd_left) < 0))
                    case_zero_cross_l = case_zero_cross_l + 1;
                if ((prior_r < 0 && $signed(snd_right) >= 0) ||
                    (prior_r >= 0 && $signed(snd_right) < 0))
                    case_zero_cross_r = case_zero_cross_r + 1;
                prior_l = snd_left;
                prior_r = snd_right;
                if (stale_open) begin
                    if (snd_left === stale_l && snd_right === stale_r)
                        case_stale_prefix = case_stale_prefix + 1;
                    else
                        stale_open = 1'b0;
                end
                if ($isunknown(snd_left) || $isunknown(snd_right) ||
                    $isunknown(b_interpolation) || $isunknown(b_gain) ||
                    $isunknown(b_lane_l) || $isunknown(b_lane_r))
                    case_x = case_x + 1;
            end
        end

        if ((monitor_on || inactive_on) && engines_configured) begin
            if (adpcma_active !== 6'd0)
                idle_adpcma_active = idle_adpcma_active + 1;
            if (adpcma_roe_n !== 1'b1)
                idle_adpcma_raw = idle_adpcma_raw + 1;
            if (dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.decon !== 1'b0)
                idle_adpcma_logical = idle_adpcma_logical + 1;
            if (dut.u_jt10.u_jt12.adpcmA_l !== 16'sd0 ||
                dut.u_jt10.u_jt12.adpcmA_r !== 16'sd0)
                idle_adpcma_lane = idle_adpcma_lane + 1;
            if (pre_clk &&
                !((final_cur_op == 2'd0 && final_cur_ch == 3'd0) ||
                  (final_cur_op == 2'd0 && final_cur_ch == 3'd4)) &&
                ((dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_en_l &&
                  acc_input_l !== 16'sd0) ||
                 (dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_en_r &&
                  acc_input_r !== 16'sd0)))
                idle_fm = idle_fm + 1;
            if (psg_A !== 0 || psg_B !== 0 || psg_C !== 0 ||
                psg_snd !== 0)
                idle_ssg = idle_ssg + 1;
            if (dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[7] !== 8'h3f ||
                dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[8] !== 8'h00 ||
                dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[9] !== 8'h00 ||
                dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[10] !== 8'h00)
                idle_ssg_control = idle_ssg_control + 1;
        end

        if (inactive_on) begin
            if (pre_raw || pre_logical || pre_decoder_commit)
                failures = failures + 1;
            if (public_rise &&
                (b_lane_l !== 0 || b_lane_r !== 0 ||
                 snd_left !== 0 || snd_right !== 0))
                failures = failures + 1;
            if ($isunknown(adpcmb_roe_n) || $isunknown(b_chon) ||
                $isunknown(b_flag) || $isunknown(b_lane_l) ||
                $isunknown(b_lane_r) || $isunknown(snd_left) ||
                $isunknown(snd_right))
                global_x = global_x + 1;
        end

        previous_public = snd_sample;
        previous_internal = internal_snd_sample;
        previous_chon = b_chon;
        previous_flag = b_flag;
    end

    jt10_phase4a_adpcmb_rom rom (
        .address(adpcmb_addr),
        .changed_pattern(changed_pattern),
        .data(adpcmb_data)
    );

    jt10_cpu_bus_bfm bus (
        .rst(rst), .clk(clk), .dout(dout),
        .addr(bus_addr), .din(bus_din), .cs_n(bus_cs_n),
        .wr_n(bus_wr_n),
        .accepted_write_count(accepted_write_count),
        .port0_write_count(port0_write_count),
        .port1_write_count(port1_write_count),
        .busy_timeout_count(busy_timeout_count),
        .busy_while_write_count(busy_while_write_count),
        .busy_min_cycles(busy_min_cycles),
        .busy_max_cycles(busy_max_cycles),
        .last_issue_cycle(last_issue_cycle),
        .last_busy_assert_cycle(last_busy_assert_cycle),
        .last_busy_clear_cycle(last_busy_clear_cycle),
        .busy_duration_hash(busy_duration_hash)
    );

    jt10_phase0_warmup_wrapper dut (
        .rst(rst), .clk(clk), .cen(cen),
        .session_start(session_start), .loop_event(loop_event),
        .addr(bus_addr), .din(bus_din), .cs_n(bus_cs_n),
        .wr_n(bus_wr_n), .irq_n(irq_n), .dout(dout),
        .snd_left(snd_left), .snd_right(snd_right),
        .snd_sample(snd_sample), .psg_A(psg_A), .psg_B(psg_B),
        .psg_C(psg_C), .psg_snd(psg_snd),
        .adpcma_addr(adpcma_addr), .adpcma_bank(adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n), .adpcma_data(adpcma_data),
        .adpcmb_addr(adpcmb_addr), .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(adpcmb_data),
        .internal_snd_left(internal_snd_left),
        .internal_snd_right(internal_snd_right),
        .internal_snd_sample(internal_snd_sample),
        .internal_fm_snd(internal_fm_snd),
        .warmup_count(warmup_count), .warmup_ready(warmup_ready),
        .reset_cen_count(reset_cen_count),
        .reset_cen_valid(reset_cen_valid)
    );

    task automatic begin_configured_case(
        input [8*32-1:0] label,
        input logic [15:0] start_value,
        input logic [15:0] end_value,
        input logic [15:0] delta_value,
        input logic [7:0] pan_value,
        input logic [7:0] level_value,
        input logic changed,
        input integer order
    );
        begin
            fresh_silence(label);
            changed_pattern = changed;
            configure_b(start_value, end_value, delta_value,
                        pan_value, level_value, order);
            reset_metrics(label);
            monitor_on = 1'b1;
        end
    endtask

    task automatic wait_zero_after_stop(output integer latency);
        integer start_public;
        begin
            latency = 0;
            start_public = public_samples;
            while ((b_lane_l !== 16'sd0 || b_lane_r !== 16'sd0 ||
                    snd_left !== 16'sd0 || snd_right !== 16'sd0) &&
                   latency < 32) begin
                wait (public_samples > start_public + latency);
                latency = latency + 1;
            end
        end
    endtask

    task automatic inactive_soak(input integer samples,
                                 input [8*32-1:0] label);
        integer target;
        begin
            wait (adpcmb_roe_n === 1'b1);
            repeat (2) @(posedge clk);
            monitor_on = 1'b0;
            inactive_on = 1'b1;
            target = public_samples + samples;
            wait (public_samples >= target);
            inactive_on = 1'b0;
            $display("PHASE4A_INACTIVE run=%0d stage=%0s samples=%0d active=%0d eos=%0d raw=%0d lane=%0d/%0d final=%0d/%0d x=%0d",
                run_id, label, samples, b_chon, b_flag,
                adpcmb_roe_n === 1'b0, b_lane_l, b_lane_r,
                snd_left, snd_right, global_x);
        end
    endtask

    task automatic save_anchor_metrics;
        begin
            anchor_raw_hash = case_raw_hash;
            anchor_logical_hash = case_logical_hash;
            anchor_rom_hash = case_rom_hash;
            anchor_delta_hash = case_delta_hash;
            anchor_decoder_hash = case_decoder_hash;
            anchor_interpolation_hash = case_interpolation_hash;
            anchor_gain_hash = case_gain_hash;
            anchor_lane_hash = case_lane_hash;
            anchor_stereo_hash = case_stereo_hash;
            anchor_rel_assert = case_active_assert - case_start_accept;
            anchor_rel_raw = case_first_raw - case_start_accept;
            anchor_rel_logical = case_first_logical - case_start_accept;
            anchor_rel_clear = case_active_clear - case_start_accept;
            anchor_rel_eos = case_eos_set - case_start_accept;
        end
    endtask

    task automatic check_anchor_metrics(input [8*32-1:0] label);
        begin
            check(case_raw_hash == anchor_raw_hash,
                  "RETRIGGER_RAW_HASH");
            check(case_logical_hash == anchor_logical_hash,
                  "RETRIGGER_LOGICAL_HASH");
            check(case_rom_hash == anchor_rom_hash,
                  "RETRIGGER_ROM_HASH");
            check(case_delta_hash == anchor_delta_hash,
                  "RETRIGGER_DELTA_HASH");
            check(case_decoder_hash == anchor_decoder_hash,
                  "RETRIGGER_DECODER_HASH");
            check(case_interpolation_hash == anchor_interpolation_hash,
                  "RETRIGGER_INTERPOLATION_HASH");
            check(case_gain_hash == anchor_gain_hash,
                  "RETRIGGER_GAIN_HASH");
            check(case_lane_hash == anchor_lane_hash,
                  "RETRIGGER_LANE_HASH");
            check(case_stereo_hash == anchor_stereo_hash,
                  "RETRIGGER_FINAL_HASH");
            check(case_active_assert - case_start_accept ==
                  anchor_rel_assert, "RETRIGGER_ACTIVE_LANDMARK");
            check(case_first_raw - case_start_accept ==
                  anchor_rel_raw, "RETRIGGER_RAW_LANDMARK");
            check(case_first_logical - case_start_accept ==
                  anchor_rel_logical, "RETRIGGER_LOGICAL_LANDMARK");
            check(case_active_clear - case_start_accept ==
                  anchor_rel_clear, "RETRIGGER_CLEAR_LANDMARK");
            check(case_eos_set - case_start_accept ==
                  anchor_rel_eos, "RETRIGGER_EOS_LANDMARK");
            check(case_stale_prefix == 0, "RETRIGGER_STALE_PREFIX");
            $display("PHASE4A_RETRIGGER run=%0d stage=%0s hash_match=%0d landmark_match=%0d stale=%0d",
                run_id, label,
                case_raw_hash == anchor_raw_hash &&
                case_logical_hash == anchor_logical_hash &&
                case_rom_hash == anchor_rom_hash &&
                case_delta_hash == anchor_delta_hash &&
                case_decoder_hash == anchor_decoder_hash &&
                case_interpolation_hash == anchor_interpolation_hash &&
                case_gain_hash == anchor_gain_hash &&
                case_lane_hash == anchor_lane_hash &&
                case_stereo_hash == anchor_stereo_hash,
                case_active_assert - case_start_accept ==
                    anchor_rel_assert &&
                case_first_raw - case_start_accept == anchor_rel_raw &&
                case_first_logical - case_start_accept ==
                    anchor_rel_logical &&
                case_active_clear - case_start_accept ==
                    anchor_rel_clear &&
                case_eos_set - case_start_accept == anchor_rel_eos,
                case_stale_prefix);
        end
    endtask

    task automatic play_short_to_end(
        input [8*32-1:0] label,
        input logic compare_anchor,
        output integer zero_latency
    );
        begin
            reset_metrics(label);
            monitor_on = 1'b1;
            start_b();
            wait (b_chon === 1'b0);
            wait (b_flag === 1'b1);
            wait_zero_after_stop(zero_latency);
            wait (adpcmb_roe_n === 1'b1);
            repeat (2) @(posedge clk);
            monitor_on = 1'b0;
            print_metrics(label);
            check(case_logical == 512, "SHORT_LOGICAL_NOT_512");
            check(case_high == 256 && case_low == 256,
                  "SHORT_NIBBLE_COUNTS");
            check(adpcmb_addr == 24'h0020ff && b_nibble === 1'b1,
                  "SHORT_FINAL_CURSOR");
            check(case_range == 0, "SHORT_RANGE");
            check(b_chon === 1'b0 && b_flag === 1'b1,
                  "SHORT_END_STATUS");
            check(case_repeat_restart == 0, "SHORT_REPEAT_RESTART");
            check(case_arith_mismatch == 0, "SHORT_ARITHMETIC");
            check(case_x == 0, "SHORT_X");
            check(zero_latency == 4, "NATURAL_ZERO_LATENCY");
            if (compare_anchor)
                check_anchor_metrics(label);
        end
    endtask

    task automatic run_long_playback(
        input [8*32-1:0] label,
        input logic [15:0] start_value,
        input logic [15:0] end_value,
        input logic [15:0] delta_value,
        input logic [7:0] pan_value,
        input logic changed
    );
        integer start_public;
        integer goal;
        begin
            begin_configured_case(label, start_value, end_value,
                delta_value, pan_value, 8'hff, changed, 2);
            start_b();
            start_public = case_public;
            goal = quick_mode ? 64 : 4096;
            wait (case_public >= start_public + goal);
            monitor_on = 1'b0;
            print_metrics(label);
            check(b_chon === 1'b1, "LONG_ENDED_EARLY");
            check(case_raw > 0 && case_capture == case_raw,
                  "LONG_REQUEST_CAPTURE");
            check(case_logical > 0 && case_decoder > 0,
                  "LONG_LOGICAL_DECODER");
            check(case_high > 0 && case_low > 0,
                  "LONG_NIBBLE_ORDER");
            check(case_range == 0, "LONG_RANGE");
            check(case_arith_mismatch == 0, "LONG_ARITHMETIC");
            check(case_x == 0, "LONG_X");
            reset_b();
        end
    endtask

    task automatic save_primary_metrics;
        begin
            primary_raw_hash = case_raw_hash;
            primary_raw_cycle_hash = case_raw_cycle_hash;
            primary_logical_hash = case_address_hash;
            primary_rom_hash = case_rom_hash;
            primary_decoder_hash = case_decoder_hash;
            primary_interpolation_hash = case_interpolation_hash;
            primary_gain_hash = case_gain_hash;
            primary_lane_hash = case_lane_hash;
            primary_left_hash = case_left_hash;
            primary_right_hash = case_right_hash;
            primary_stereo_hash = case_stereo_hash;
            primary_logical_count = case_logical;
        end
    endtask

    task automatic check_core_against_primary(input logic compare_rom);
        begin
            check(case_raw_cycle_hash == primary_raw_cycle_hash,
                  "PRIMARY_RAW_CYCLE_MISMATCH");
            check(case_address_hash == primary_logical_hash,
                  "PRIMARY_ADDRESS_HASH_MISMATCH");
            if (compare_rom) begin
                check(case_raw_hash == primary_raw_hash,
                      "PRIMARY_RAW_HASH_MISMATCH");
                check(case_rom_hash == primary_rom_hash,
                      "PRIMARY_ROM_HASH_MISMATCH");
                check(case_decoder_hash == primary_decoder_hash,
                      "PRIMARY_DECODER_HASH_MISMATCH");
                check(case_interpolation_hash ==
                      primary_interpolation_hash,
                      "PRIMARY_INTERPOLATION_HASH_MISMATCH");
            end
            check(case_logical == primary_logical_count,
                  "PRIMARY_LOGICAL_COUNT_MISMATCH");
        end
    endtask

    task automatic command_reset_case(
        input [8*32-1:0] label,
        input logic write_zero,
        input logic keep_config,
        output integer zero_latency
    );
        integer issue_logical;
        begin
            if (!keep_config)
                begin_configured_case(label, SHORT_START, SHORT_END,
                    16'h8000, 8'hc0, 8'hff, 1'b0, 2);
            else begin
                reset_metrics(label);
                monitor_on = 1'b1;
            end
            start_b();
            wait (case_logical >= 100);
            issue_logical = case_logical;
            bus.jt10_write_port0(8'h10, 8'h01);
            wait (b_chon === 1'b0);
            wait_zero_after_stop(zero_latency);
            if (write_zero)
                bus.jt10_write_port0(8'h10, 8'h00);
            wait (adpcmb_roe_n === 1'b1);
            repeat (2) @(posedge clk);
            monitor_on = 1'b0;
            print_metrics(label);
            check(issue_logical == 100, "RESET_ISSUE_NOT_100");
            check(zero_latency == 3, "RESET_ZERO_LATENCY");
            check(case_arith_mismatch == 0, "RESET_ARITHMETIC");
            check(case_x == 0, "RESET_X");
            check(b_chon === 1'b0, "RESET_ACTIVE");
        end
    endtask

    initial begin : phase4a_sequence
        integer goal_c;
        integer zero_latency;
        integer recovery_samples;
        integer base_public;
        integer changed_logical_count;
        logic [63:0] changed_delta_hash;
        logic [63:0] shifted_address_hash;
        logic [63:0] mute_hash;

        if (!$value$plusargs("RUN_ID=%d", run_id))
            run_id = 1;
        if ($test$plusargs("QUICK"))
            quick_mode = 1;
        $display("PHASE4A_BEGIN run=%0d quick=%0d", run_id, quick_mode);
        repeat (8) @(posedge clk);

        // Stage A: global reset and warm-up publication contract.
        global_reset();
        reset_metrics("A_RESET_WARMUP");
        monitor_on = 1'b1;
        wait_public(16);
        monitor_on = 1'b0;
        print_metrics("A_RESET_WARMUP");
        check(first_public_internal == 6, "FIRST_PUBLIC_NOT_INTERNAL_6");
        check(snd_left === 16'sd0 && snd_right === 16'sd0,
              "RESET_NOT_SILENT");
        check(case_x == 0, "RESET_X");

        // Stage B: explicit all-engine silence and STOP/RESET.
        explicit_silence();
        reset_metrics("B_EXPLICIT_SILENCE");
        monitor_on = 1'b1;
        wait_public(16);
        monitor_on = 1'b0;
        print_metrics("B_EXPLICIT_SILENCE");
        check(b_chon === 1'b0 && case_raw == 0 &&
              case_capture == 0 && case_logical == 0,
              "EXPLICIT_SILENCE_ACTIVITY");
        check(b_lane_l === 0 && b_lane_r === 0 &&
              snd_left === 0 && snd_right === 0,
              "EXPLICIT_SILENCE_OUTPUT");
        check(case_x == 0, "EXPLICIT_SILENCE_X");

        // Stage C: every supported write order must remain inert without
        // START.  The public 16384-sample soak is shortened only by +QUICK.
        goal_c = quick_mode ? 32 : 16384;
        begin_configured_case("C_PAN_LEVEL", LONG_START, LONG_END,
            16'h8000, 8'hc0, 8'hff, 1'b0, 0);
        wait (case_public >= goal_c);
        monitor_on = 1'b0;
        print_metrics("C_PAN_LEVEL");
        check(b_chon === 0 && b_flag === 0 && case_raw == 0 &&
              case_capture == 0 && case_logical == 0 &&
              case_decoder == 0, "CONFIG_PAN_LEVEL_ACTIVITY");
        check(b_interpolation === 0 && b_gain === 0 &&
              b_lane_l === 0 && b_lane_r === 0 &&
              snd_left === 0 && snd_right === 0,
              "CONFIG_PAN_LEVEL_OUTPUT");

        begin_configured_case("C_LEVEL_PAN", LONG_START, LONG_END,
            16'h8000, 8'hc0, 8'hff, 1'b0, 1);
        wait (case_public >= goal_c);
        monitor_on = 1'b0;
        print_metrics("C_LEVEL_PAN");
        check(b_chon === 0 && case_raw == 0 && case_logical == 0 &&
              b_interpolation === 0 && b_gain === 0 &&
              b_lane_l === 0 && b_lane_r === 0,
              "CONFIG_LEVEL_PAN_ACTIVITY");

        begin_configured_case("C_ADDR_DELTA_PAN_LEVEL", LONG_START,
            LONG_END, 16'h8000, 8'hc0, 8'hff, 1'b0, 2);
        wait (case_public >= goal_c);
        monitor_on = 1'b0;
        print_metrics("C_ADDR_DELTA_PAN_LEVEL");
        check(b_chon === 0 && case_raw == 0 && case_logical == 0 &&
              b_interpolation === 0 && b_gain === 0 &&
              b_lane_l === 0 && b_lane_r === 0,
              "CONFIG_FULL_ORDER_ACTIVITY");

        // Stage D: exact Phase 4A-FIX short lifecycle anchor.
        begin_configured_case("D_ANCHOR", SHORT_START, SHORT_END,
            16'h8000, 8'hc0, 8'hff, 1'b0, 2);
        play_short_to_end("D_ANCHOR", 1'b0, zero_latency);
        check(case_raw_hash == ANCHOR_RAW, "ANCHOR_RAW_HASH");
        check(case_logical_hash == ANCHOR_LOGICAL,
              "ANCHOR_LOGICAL_HASH");
        check(case_delta_hash == ANCHOR_DELTA, "ANCHOR_DELTA_HASH");
        check(case_decoder_hash == ANCHOR_DECODER,
              "ANCHOR_DECODER_HASH");
        check(case_interpolation_hash == ANCHOR_INTERPOL,
              "ANCHOR_INTERPOLATION_HASH");
        check(case_gain_hash == ANCHOR_ACTIVE_GAIN,
              "ANCHOR_ACTIVE_GAIN_HASH");
        check(case_lane_hash == ANCHOR_ACTIVE_LANE,
              "ANCHOR_ACTIVE_LANE_HASH");
        check(case_stereo_hash == ANCHOR_FINAL, "ANCHOR_FINAL_HASH");
        save_anchor_metrics();
        inactive_soak(quick_mode ? 32 : 4096, "D_ANCHOR_END");

        command_reset_case("D_ANCHOR_RESET", 1'b0, 1'b0,
                           zero_latency);
        check(b_flag === 1'b0, "RESET_EOS_STATE");
        inactive_soak(quick_mode ? 32 : 4096, "D_ANCHOR_RESET");
        if ($test$plusargs("STOP_AFTER_D")) begin
            $display("PHASE4A_DEBUG_STOP failures=%0d", failures);
            $finish;
        end

        // Stage E: long primary stereo playback.
        run_long_playback("E_PRIMARY", LONG_START, LONG_END,
            16'h8000, 8'hc0, 1'b0);
        check(case_nonzero_l > 0 && case_nonzero_r > 0,
              "PRIMARY_AUDIO_ZERO");
        check(case_left_hash == case_right_hash,
              "PRIMARY_STEREO_MISMATCH");
        check(case_first_raw_address == 24'h002000 &&
              case_first_logical_address == 24'h002000,
              "PRIMARY_FIRST_ADDRESS");
        save_primary_metrics();

        // Stages F/G: pan isolation must not perturb the source/decode path.
        run_long_playback("F_LEFT", LONG_START, LONG_END,
            16'h8000, 8'h80, 1'b0);
        check_core_against_primary(1'b1);
        check(case_nonzero_l > 0 && case_nonzero_r == 0 &&
              case_pan_leak == 0, "LEFT_PAN_LEAK");
        check(case_left_hash == primary_left_hash,
              "LEFT_WAVEFORM_MISMATCH");

        run_long_playback("G_RIGHT", LONG_START, LONG_END,
            16'h8000, 8'h40, 1'b0);
        check_core_against_primary(1'b1);
        check(case_nonzero_l == 0 && case_nonzero_r > 0 &&
              case_pan_leak == 0, "RIGHT_PAN_LEAK");
        check(case_right_hash == primary_right_hash,
              "RIGHT_WAVEFORM_MISMATCH");

        // Stage H: level zero mutes only the gain/lane; playback continues.
        begin_configured_case("H_MUTE_PREROLL", LONG_START, LONG_END,
            16'h8000, 8'hc0, 8'hff, 1'b0, 2);
        start_b();
        wait (case_logical >= 256);
        monitor_on = 1'b0;
        bus.jt10_write_port0(8'h1b, 8'h00);
        recovery_samples = 0;
        while ((snd_left !== 0 || snd_right !== 0) &&
               recovery_samples < 64) begin
            wait_public(1);
            recovery_samples = recovery_samples + 1;
        end
        check(recovery_samples < 64, "MUTE_ZERO_TIMEOUT");
        reset_metrics("H_LEVEL_MUTE");
        monitor_on = 1'b1;
        wait (case_public >= (quick_mode ? 32 : 512));
        monitor_on = 1'b0;
        print_metrics("H_LEVEL_MUTE");
        mute_hash = case_all_stereo_hash;
        check(b_chon === 1'b1 && case_raw > 0 && case_logical > 0 &&
              case_decoder > 0 && case_interpolation > 0,
              "MUTE_STOPPED_PLAYBACK");
        check(case_nonzero_l == 0 && case_nonzero_r == 0 &&
              b_lane_l === 0 && b_lane_r === 0,
              "MUTE_NOT_ZERO");
        bus.jt10_write_port0(8'h1b, 8'hff);
        recovery_samples = 0;
        while ((snd_left === 0 && snd_right === 0) &&
               recovery_samples < 64) begin
            wait_public(1);
            recovery_samples = recovery_samples + 1;
        end
        check(recovery_samples < 64 && b_chon === 1'b1,
              "MUTE_RESTORE_TIMEOUT");
        reset_b();

        // Stage I: changed Delta-N must alter carry/consume cadence.
        run_long_playback("I_DELTA_4000", LONG_START, LONG_END,
            16'h4000, 8'hc0, 1'b0);
        changed_logical_count = case_logical;
        changed_delta_hash = case_delta_hash;
        check(changed_logical_count < primary_logical_count,
              "DELTA_CONSUME_COUNT_UNCHANGED");
        check(case_delta_hash != anchor_delta_hash &&
              case_decoder_hash != primary_decoder_hash &&
              case_stereo_hash != primary_stereo_hash,
              "DELTA_HASH_UNCHANGED");
        check(interval_576 > 0, "DELTA_4000_CADENCE");

        // Stage J: one start-register unit is 256 bytes.
        run_long_playback("J_SHIFT_START", SHIFT_START, SHIFT_END,
            16'h8000, 8'hc0, 1'b0);
        shifted_address_hash = case_address_hash;
        check(case_first_raw_address == 24'h002100 &&
              case_first_logical_address == 24'h002100,
              "SHIFT_FIRST_ADDRESS");
        check(case_address_hash != primary_logical_hash &&
              case_rom_hash != primary_rom_hash &&
              case_decoder_hash != primary_decoder_hash &&
              case_stereo_hash != primary_stereo_hash,
              "SHIFT_HASH_UNCHANGED");

        // Stage K: only ROM contents change; schedule/address stays fixed.
        run_long_playback("K_CHANGED_ROM", LONG_START, LONG_END,
            16'h8000, 8'hc0, 1'b1);
        check_core_against_primary(1'b0);
        check(case_rom_hash != primary_rom_hash &&
              case_decoder_hash != primary_decoder_hash &&
              case_interpolation_hash != primary_interpolation_hash &&
              case_stereo_hash != primary_stereo_hash,
              "ROM_CHANGE_NOT_VISIBLE");

        // Stage L: mid-stream command RESET and long quiescent window.
        command_reset_case("L_MID_RESET", 1'b0, 1'b0, zero_latency);
        inactive_soak(quick_mode ? 64 : 4096, "L_MID_RESET");

        // Stages M/N: natural end followed by same-session START.
        begin_configured_case("M_NATURAL", SHORT_START, SHORT_END,
            16'h8000, 8'hc0, 8'hff, 1'b0, 2);
        play_short_to_end("M_NATURAL", 1'b1, zero_latency);
        inactive_soak(quick_mode ? 64 : 4096, "M_NATURAL");
        play_short_to_end("N_NATURAL_RETRIGGER", 1'b1, zero_latency);

        // Stage O: RESET=01 -> START=80, without Control 00.
        command_reset_case("O_RESET", 1'b0, 1'b0, zero_latency);
        play_short_to_end("O_RESET_RETRIGGER", 1'b1, zero_latency);

        // Stage P: RESET=01 -> Control 00 -> START=80.
        command_reset_case("P_RESET_00", 1'b1, 1'b0, zero_latency);
        play_short_to_end("P_RESET_00_RETRIGGER", 1'b1, zero_latency);

        // Stage Q: long inactive natural-end soak and deterministic replay.
        begin_configured_case("Q_NATURAL", SHORT_START, SHORT_END,
            16'h8000, 8'hc0, 8'hff, 1'b0, 2);
        play_short_to_end("Q_NATURAL", 1'b1, zero_latency);
        inactive_soak(quick_mode ? 128 : 65536, "Q_LONG_SOAK");
        play_short_to_end("Q_LONG_RETRIGGER", 1'b1, zero_latency);

        check(busy_timeout_count == 0, "BUSY_TIMEOUT");
        check(busy_while_write_count == 0, "BUSY_WRITE");
        check(cadence_errors == 0, "SAMPLE_CADENCE");
        check(width_errors == 0, "SAMPLE_WIDTH");
        check(drops == 0, "SAMPLE_DROP");
        check(duplicates == 0, "SAMPLE_DUPLICATE");
        check(global_x == 0, "INACTIVE_X");
        check(idle_adpcma_active == 0 && idle_adpcma_raw == 0 &&
              idle_adpcma_logical == 0 && idle_adpcma_lane == 0,
              "ADPCMA_NOT_IDLE");
        check(idle_fm == 0, "FM_NOT_IDLE");
        check(idle_ssg == 0 && idle_ssg_control == 0,
              "SSG_NOT_IDLE");

        $display("PHASE4A_PRIMARY run=%0d delta=8000 changed_delta=4000 logical=%0d/%0d raw=%016h raw_cycle=%016h address=%016h rom=%016h decoder=%016h interpolation=%016h gain=%016h lane=%016h left=%016h right=%016h stereo=%016h mute=%016h shifted_address=%016h changed_delta_hash=%016h",
            run_id, primary_logical_count, changed_logical_count,
            primary_raw_hash, primary_raw_cycle_hash,
            primary_logical_hash, primary_rom_hash,
            primary_decoder_hash, primary_interpolation_hash,
            primary_gain_hash, primary_lane_hash, primary_left_hash,
            primary_right_hash, primary_stereo_hash, mute_hash,
            shifted_address_hash, changed_delta_hash);
        $display("PHASE4A_ANCHOR run=%0d raw=%016h logical=%016h rom=%016h delta=%016h decoder=%016h interpolation=%016h gain=%016h lane=%016h final=%016h relative=%0d/%0d/%0d/%0d/%0d",
            run_id, anchor_raw_hash, anchor_logical_hash,
            anchor_rom_hash, anchor_delta_hash, anchor_decoder_hash,
            anchor_interpolation_hash, anchor_gain_hash,
            anchor_lane_hash, anchor_stereo_hash, anchor_rel_assert,
            anchor_rel_raw, anchor_rel_logical, anchor_rel_clear,
            anchor_rel_eos);
        $display("PHASE4A_TRANSPORT run=%0d writes=%0d port0=%0d port1=%0d busy_min=%0d busy_max=%0d busy_hash=%016h timeout=%0d busy_write=%0d",
            run_id, accepted_write_count, port0_write_count,
            port1_write_count, busy_min_cycles, busy_max_cycles,
            busy_duration_hash, busy_timeout_count,
            busy_while_write_count);
        $display("PHASE4A_SAMPLE run=%0d ready_internal=%0d cadence=144 width=6 cadence_errors=%0d width_errors=%0d drops=%0d duplicates=%0d x=%0d adpcma=%0d/%0d/%0d/%0d fm=%0d ssg=%0d/%0d",
            run_id, first_public_internal, cadence_errors, width_errors,
            drops, duplicates, global_x, idle_adpcma_active,
            idle_adpcma_raw, idle_adpcma_logical, idle_adpcma_lane,
            idle_fm, idle_ssg, idle_ssg_control);
        $display("PHASE4A_STATUS run=%0d cold_eos=0 start_clear=PASS natural_set=PASS reset_clear=PASS repeat=OFF stale=0",
            run_id);

        if (failures == 0) begin
            $display("PHASE4A_PASS run=%0d", run_id);
            $finish;
        end
        $fatal(1, "PHASE4A_RESULT run=%0d failures=%0d",
               run_id, failures);
    end
endmodule

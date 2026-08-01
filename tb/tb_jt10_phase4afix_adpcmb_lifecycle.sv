`timescale 1ns/1ps

// Phase 4A-FIX lifecycle regression for the formal PC-GATE overlay.
//
// The copied Phase 4A-R microscope supplies the standalone JT10 instance,
// ROM model, BUSY-aware BFM, cadence monitor, and source-level observation
// points.  Its original sequence is disabled; this wrapper only observes and
// drives documented CPU/ROM interfaces.  No DUT signal is forced or gated.
`include "tb_jt10_phase4afix_adpcmb_audit_base.sv"

module tb_jt10_phase4afix_adpcmb_lifecycle;
    localparam logic [63:0] FNV_OFFSET = 64'hcbf29ce484222325;
    localparam logic [63:0] BASE_LOGICAL = 64'hd3f50a660ff4da1a;
    localparam logic [63:0] BASE_DELTA = 64'h3ef011c519a87325;
    localparam logic [63:0] BASE_DECODER = 64'h46ce068d48f530a5;
    localparam logic [63:0] BASE_INTERPOL = 64'h977cceaa11432cb1;
    localparam logic [63:0] BASE_GAIN = 64'hc44dda0e59862d8a;
    localparam logic [63:0] BASE_LANE = 64'h16e284660dfd24e1;
    localparam logic [63:0] BASE_FINAL = 64'he142f7da424b1531;
    localparam logic [63:0] BASE_ACTIVE_RAW = 64'he60907109cc90925;
    localparam logic [63:0] BASE_ACTIVE_GAIN = 64'ha009ad964647c074;
    localparam logic [63:0] BASE_ACTIVE_LANE = 64'ha9a4d74927a92055;

    tb_jt10_phase4afix_adpcmb_audit_base audit();

    integer variant_id = 6;
    integer run_id = 1;
    integer quick_mode = 0;
    integer failures = 0;
    integer inactive_samples_goal = 32768;
    integer long_samples_goal = 65536;
    reg [8*16-1:0] variant_name = "PC_GATE";

    logic active_monitor = 1'b0;
    logic inactive_monitor = 1'b0;
    logic cold_monitor = 1'b0;
    logic prior_public = 1'b0;
    logic prior_chon = 1'b0;
    logic prior_flag = 1'b0;

    integer active_raw = 0;
    integer active_logical = 0;
    integer active_decoder = 0;
    integer active_interpol = 0;
    integer active_gain = 0;
    integer active_lane = 0;
    integer active_x = 0;
    integer active_start_cycle = -1;
    integer active_assert_cycle = -1;
    integer active_first_raw_cycle = -1;
    integer active_first_logical_cycle = -1;
    integer active_clear_cycle = -1;
    integer active_eos_cycle = -1;
    integer active_final_align_logical = -1;
    integer active_final_samples = 0;
    integer active_stale_prefix = 0;
    logic active_stale_open = 1'b0;
    logic signed [15:0] active_stale_l = 16'sd0;
    logic signed [15:0] active_stale_r = 16'sd0;
    logic [63:0] active_raw_hash = FNV_OFFSET;
    logic [63:0] active_logical_hash = FNV_OFFSET;
    logic [63:0] active_delta_hash = FNV_OFFSET;
    logic [63:0] active_decoder_hash = FNV_OFFSET;
    logic [63:0] active_interpol_hash = FNV_OFFSET;
    logic [63:0] active_gain_hash = FNV_OFFSET;
    logic [63:0] active_lane_hash = FNV_OFFSET;
    logic [63:0] active_final_hash = FNV_OFFSET;
    logic active_final_aligned = 1'b0;

    integer inactive_samples = 0;
    integer inactive_raw = 0;
    integer inactive_capture = 0;
    integer inactive_logical = 0;
    integer inactive_decoder = 0;
    integer inactive_cursor_moves = 0;
    integer inactive_x = 0;
    integer inactive_nonzero = 0;
    integer inactive_nonzero_after_zero = 0;
    integer inactive_zero_sample = -1;
    integer inactive_last_raw_cycle = -1;
    integer inactive_i144 = 0;
    integer inactive_i288 = 0;
    integer inactive_iother = 0;
    integer inactive_out_of_range = 0;
    logic [23:0] inactive_previous_addr = 24'd0;
    logic inactive_zero_seen = 1'b0;
    logic [63:0] inactive_hash = FNV_OFFSET;

    integer idle_adpcma_active = 0;
    integer idle_adpcma_raw = 0;
    integer idle_adpcma_logical = 0;
    integer idle_adpcma_lane = 0;
    integer idle_fm = 0;
    integer idle_ssg = 0;
    integer idle_ssg_control = 0;
    integer pc_clear_reject_seen = 0;

    logic [63:0] primary_raw_hash = FNV_OFFSET;
    logic [63:0] primary_logical_hash = FNV_OFFSET;
    logic [63:0] primary_delta_hash = FNV_OFFSET;
    logic [63:0] primary_decoder_hash = FNV_OFFSET;
    logic [63:0] primary_interpol_hash = FNV_OFFSET;
    logic [63:0] primary_gain_hash = FNV_OFFSET;
    logic [63:0] primary_lane_hash = FNV_OFFSET;
    logic [63:0] primary_final_hash = FNV_OFFSET;
    integer primary_rel_raw = -1;
    integer primary_rel_logical = -1;
    integer primary_rel_assert = -1;
    integer primary_rel_clear = -1;
    integer primary_rel_eos = -1;

    function automatic [63:0] hash_byte(
        input [63:0] hash_in,
        input [7:0] value
    );
        hash_byte = (hash_in ^ value) * 64'h00000100000001b3;
    endfunction

    function automatic [63:0] hash_u16(
        input [63:0] hash_in,
        input [15:0] value
    );
        logic [63:0] work;
        begin
            work = hash_byte(hash_in, value[7:0]);
            hash_u16 = hash_byte(work, value[15:8]);
        end
    endfunction

    function automatic [63:0] hash_u24(
        input [63:0] hash_in,
        input [23:0] value
    );
        logic [63:0] work;
        begin
            work = hash_byte(hash_in, value[7:0]);
            work = hash_byte(work, value[15:8]);
            hash_u24 = hash_byte(work, value[23:16]);
        end
    endfunction

    function automatic [63:0] hash_stereo(
        input [63:0] hash_in,
        input [15:0] left_value,
        input [15:0] right_value
    );
        logic [63:0] work;
        begin
            work = hash_u16(hash_in, left_value);
            hash_stereo = hash_u16(work, right_value);
        end
    endfunction

    function automatic integer has_output_fix;
        has_output_fix =
            variant_id == 1 || variant_id == 2 ||
            variant_id == 6 || variant_id == 7;
    endfunction

    function automatic integer has_request_fix;
        has_request_fix =
            variant_id == 3 || variant_id == 6 || variant_id == 7;
    endfunction

    function automatic integer has_restart_fix;
        has_restart_fix =
            variant_id == 5 || variant_id == 6 || variant_id == 7;
    endfunction

    function automatic integer has_eos_fix;
        has_eos_fix =
            variant_id == 4 || variant_id == 5 ||
            variant_id == 6 || variant_id == 7;
    endfunction

    function automatic integer is_integrated;
        is_integrated = variant_id == 6 || variant_id == 7;
    endfunction

    task automatic check(input logic condition,
                         input [8*96-1:0] message);
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("PHASE4AFIX_FAIL variant=%0s run=%0d cycle=%0d reason=%0s",
                    variant_name, run_id, audit.system_cycle, message);
            end
        end
    endtask

    task automatic reset_active;
        begin
            active_monitor = 1'b0;
            active_raw = 0;
            active_logical = 0;
            active_decoder = 0;
            active_interpol = 0;
            active_gain = 0;
            active_lane = 0;
            active_x = 0;
            active_start_cycle = -1;
            active_assert_cycle = -1;
            active_first_raw_cycle = -1;
            active_first_logical_cycle = -1;
            active_clear_cycle = -1;
            active_eos_cycle = -1;
            active_final_align_logical = -1;
            active_final_samples = 0;
            active_stale_prefix = 0;
            active_stale_open = 1'b0;
            active_stale_l = 16'sd0;
            active_stale_r = 16'sd0;
            active_raw_hash = FNV_OFFSET;
            active_logical_hash = FNV_OFFSET;
            active_delta_hash = FNV_OFFSET;
            active_decoder_hash = FNV_OFFSET;
            active_interpol_hash = FNV_OFFSET;
            active_gain_hash = FNV_OFFSET;
            active_lane_hash = FNV_OFFSET;
            active_final_hash = FNV_OFFSET;
            active_final_aligned = 1'b0;
        end
    endtask

    task automatic reset_inactive(input logic cold);
        begin
            inactive_monitor = 1'b0;
            cold_monitor = cold;
            inactive_samples = 0;
            inactive_raw = 0;
            inactive_capture = 0;
            inactive_logical = 0;
            inactive_decoder = 0;
            inactive_cursor_moves = 0;
            inactive_x = 0;
            inactive_nonzero = 0;
            inactive_nonzero_after_zero = 0;
            inactive_zero_sample = -1;
            inactive_last_raw_cycle = -1;
            inactive_i144 = 0;
            inactive_i288 = 0;
            inactive_iother = 0;
            inactive_out_of_range = 0;
            inactive_previous_addr = audit.adpcmb_addr;
            inactive_zero_seen = 1'b0;
            inactive_hash = FNV_OFFSET;
        end
    endtask

    task automatic matrix_global_reset_and_silence;
        begin
            // jt12_div intentionally free-runs.  Use the frozen Phase 4A-X
            // reset phase so the published primary hashes remain exact.
            while ((audit.system_cycle % 432) != 0)
                @(posedge audit.clk);
            active_monitor = 1'b0;
            inactive_monitor = 1'b0;
            @(negedge audit.clk);
            audit.rst = 1'b1;
            audit.session_start = 1'b1;
            audit.cen = 1'b1;
            repeat (2) @(posedge audit.clk);
            @(negedge audit.clk);
            audit.session_start = 1'b0;
            repeat (64) @(posedge audit.clk);
            check(audit.reset_cen_count === 3'd6 &&
                  audit.reset_cen_valid === 1'b1,
                  "RESET_CEN_CONTRACT");
            @(negedge audit.clk);
            audit.rst = 1'b0;
            audit.pattern_mode = audit.PATTERN_P;
            wait (audit.warmup_ready === 1'b1);
            wait (audit.snd_sample === 1'b1);
            audit.keyoff_fm();
            audit.bus.jt10_write_port0(8'h22, 8'h00);
            audit.bus.jt10_write_port0(8'h27, 8'h00);
            audit.bus.jt10_write_port0(8'h2b, 8'h00);
            audit.bus.jt10_write_port0(8'h08, 8'h00);
            audit.bus.jt10_write_port0(8'h09, 8'h00);
            audit.bus.jt10_write_port0(8'h0a, 8'h00);
            audit.bus.jt10_write_port0(8'h06, 8'h00);
            audit.bus.jt10_write_port0(8'h07, 8'h3f);
            audit.bus.jt10_write_port1(8'h00, 8'hbf);
            repeat (2304) @(posedge audit.clk);
            audit.bus.jt10_write_port0(8'h10, 8'h01);
            audit.bus.jt10_write_port0(8'h1c, 8'h80);
            audit.bus.jt10_write_port0(8'h10, 8'h00);
        end
    endtask

    task automatic prepare_session(input [8*32-1:0] label);
        begin
            matrix_global_reset_and_silence();
            audit.reset_case_statistics(label);
            audit.case_audit = 1'b1;
            audit.configure_b(16'h0020, 16'h0020);
            check(audit.b_repeat === 1'b0, "REPEAT_NOT_OFF");
            check(audit.b_pan === 2'b11, "PAN_NOT_C0");
            check(audit.b_level === 8'hff, "LEVEL_NOT_FF");
            check(audit.b_delta === 16'h8000, "DELTA_NOT_8000");
        end
    endtask

    task automatic prepare_cold_write_order(
        input [8*32-1:0] label,
        input logic level_first
    );
        begin
            matrix_global_reset_and_silence();
            audit.reset_case_statistics(label);
            audit.case_audit = 1'b1;
            if (level_first) begin
                audit.bus.jt10_write_port0(8'h1b, 8'hff);
                audit.bus.jt10_write_port0(8'h11, 8'hc0);
            end else begin
                audit.bus.jt10_write_port0(8'h11, 8'hc0);
                audit.bus.jt10_write_port0(8'h1b, 8'hff);
            end
            audit.bus.jt10_write_port0(8'h12, 8'h20);
            audit.bus.jt10_write_port0(8'h13, 8'h00);
            audit.bus.jt10_write_port0(8'h14, 8'h20);
            audit.bus.jt10_write_port0(8'h15, 8'h00);
            audit.bus.jt10_write_port0(8'h19, 8'h00);
            audit.bus.jt10_write_port0(8'h1a, 8'h80);
            check(audit.b_chon === 1'b0, "COLD_ORDER_ACTIVE");
            check(audit.b_start === 16'h0020 &&
                  audit.b_end === 16'h0020 &&
                  audit.b_delta === 16'h8000 &&
                  audit.b_pan === 2'b11 &&
                  audit.b_level === 8'hff &&
                  audit.b_repeat === 1'b0,
                  "COLD_ORDER_CAPTURE");
        end
    endtask

    task automatic start_active(input [8*32-1:0] label);
        begin
            audit.case_name = label;
            reset_active();
            active_monitor = 1'b1;
            audit.align_start();
            audit.bus.jt10_write_port0(8'h10, 8'h80);
            wait (audit.b_chon === 1'b1);
            if (has_eos_fix())
                check(audit.b_flag === 1'b0, "START_EOS_NOT_CLEAR");
        end
    endtask

    task automatic stop_active;
        begin
            wait (audit.b_chon === 1'b0);
            repeat (2) @(posedge audit.clk);
            active_monitor = 1'b0;
        end
    endtask

    task automatic print_active(input [8*32-1:0] label);
        begin
            $display("PHASE4AFIX_ACTIVE variant=%0s run=%0d case=%0s raw=%0d logical=%0d decoder=%0d interpolation=%0d gain=%0d lane=%0d raw_hash=%016h logical_hash=%016h delta_hash=%016h decoder_hash=%016h interpolation_hash=%016h gain_hash=%016h lane_hash=%016h final_hash=%016h final_samples=%0d cursor=%06h/%0d active=%0d eos=%0d relative=%0d/%0d/%0d/%0d/%0d stale_prefix=%0d x=%0d",
                variant_name, run_id, label, active_raw, active_logical,
                active_decoder, active_interpol, active_gain, active_lane,
                active_raw_hash, active_logical_hash, active_delta_hash,
                active_decoder_hash, active_interpol_hash,
                active_gain_hash, active_lane_hash, active_final_hash,
                active_final_samples, audit.adpcmb_addr, audit.b_nibble,
                audit.b_chon, audit.b_flag,
                active_assert_cycle - active_start_cycle,
                active_first_raw_cycle - active_start_cycle,
                active_first_logical_cycle - active_start_cycle,
                active_clear_cycle - active_start_cycle,
                active_eos_cycle - active_start_cycle,
                active_stale_prefix, active_x);
        end
    endtask

    task automatic save_primary;
        begin
            primary_raw_hash = active_raw_hash;
            primary_logical_hash = active_logical_hash;
            primary_delta_hash = active_delta_hash;
            primary_decoder_hash = active_decoder_hash;
            primary_interpol_hash = active_interpol_hash;
            primary_gain_hash = active_gain_hash;
            primary_lane_hash = active_lane_hash;
            primary_final_hash = active_final_hash;
            primary_rel_assert = active_assert_cycle - active_start_cycle;
            primary_rel_raw = active_first_raw_cycle - active_start_cycle;
            primary_rel_logical =
                active_first_logical_cycle - active_start_cycle;
            primary_rel_clear = active_clear_cycle - active_start_cycle;
            primary_rel_eos = active_eos_cycle - active_start_cycle;
        end
    endtask

    task automatic check_primary(input [8*32-1:0] label);
        integer core_hash_match;
        integer final_hash_match;
        integer hash_match;
        integer landmark_match;
        begin
            core_hash_match =
                active_raw_hash == primary_raw_hash &&
                active_logical_hash == primary_logical_hash &&
                active_delta_hash == primary_delta_hash &&
                active_decoder_hash == primary_decoder_hash &&
                active_interpol_hash == primary_interpol_hash &&
                active_gain_hash == primary_gain_hash &&
                active_lane_hash == primary_lane_hash;
            final_hash_match =
                active_final_hash == primary_final_hash;
            hash_match = core_hash_match && final_hash_match;
            landmark_match =
                active_assert_cycle - active_start_cycle ==
                    primary_rel_assert &&
                active_first_raw_cycle - active_start_cycle ==
                    primary_rel_raw &&
                active_first_logical_cycle - active_start_cycle ==
                    primary_rel_logical &&
                active_clear_cycle - active_start_cycle ==
                    primary_rel_clear &&
                active_eos_cycle - active_start_cycle ==
                    primary_rel_eos;
            $display("PHASE4AFIX_RESTART variant=%0s run=%0d case=%0s replay=%0d core_hash_match=%0d final_hash_match=%0d hash_match=%0d landmark_match=%0d eos=%0d logical=%0d stale_prefix=%0d final_hash=%016h",
                variant_name, run_id, label,
                active_logical == 512, core_hash_match,
                final_hash_match, hash_match, landmark_match,
                audit.b_flag, active_logical, active_stale_prefix,
                active_final_hash);
            if (has_restart_fix()) begin
                check(active_logical == 512, "RESTART_LOGICAL_NOT_512");
                check(core_hash_match, "RESTART_CORE_HASH_MISMATCH");
                check(landmark_match, "RESTART_LANDMARK_MISMATCH");
                // PS owns restart state, not the independently classified
                // stop/output hold.  Full final equality and zero stale
                // prefix are integrated-candidate requirements.
                if (is_integrated())
                    check(final_hash_match,
                          "INTEGRATED_FINAL_HASH_MISMATCH");
                if (variant_id == 6)
                    check(active_stale_prefix == 0,
                          "INTEGRATED_STALE_PREFIX");
                if (variant_id == 7 && active_stale_prefix != 0)
                    pc_clear_reject_seen = pc_clear_reject_seen + 1;
                check(active_x == 0, "RESTART_X");
            end
        end
    endtask

    task automatic run_inactive_window(
        input [8*32-1:0] label,
        input integer goal,
        input logic cold
    );
        begin
            reset_inactive(cold);
            inactive_monitor = 1'b1;
            wait (inactive_samples >= goal);
            inactive_monitor = 1'b0;
            $display("PHASE4AFIX_INACTIVE variant=%0s run=%0d case=%0s samples=%0d raw=%0d capture=%0d logical=%0d decoder=%0d cursor_moves=%0d range=%0d intervals=%0d/%0d/%0d zero_sample=%0d nonzero=%0d after_zero=%0d interpolation=%0d gain=%0d lane=%0d/%0d final=%0d/%0d hash=%016h x=%0d",
                variant_name, run_id, label, inactive_samples,
                inactive_raw, inactive_capture, inactive_logical,
                inactive_decoder, inactive_cursor_moves,
                inactive_out_of_range, inactive_i144, inactive_i288,
                inactive_iother, inactive_zero_sample, inactive_nonzero,
                inactive_nonzero_after_zero, audit.b_interpolation,
                audit.b_gain, audit.b_lane_l, audit.b_lane_r,
                audit.snd_left, audit.snd_right, inactive_hash,
                inactive_x);
            check(inactive_logical == 0, "INACTIVE_LOGICAL");
            check(inactive_decoder == 0, "INACTIVE_DECODER");
            check(inactive_out_of_range == 0, "INACTIVE_RANGE");
            check(inactive_x == 0, "INACTIVE_X");
            if (cold) begin
                check(inactive_nonzero == 0, "COLD_NONZERO");
                check(audit.b_interpolation === 16'sd0,
                      "COLD_INTERPOL_NOT_ZERO");
                check(audit.b_gain === 16'sd0, "COLD_GAIN_NOT_ZERO");
                check(audit.b_lane_l === 16'sd0 &&
                      audit.b_lane_r === 16'sd0, "COLD_LANE_NOT_ZERO");
                check(audit.snd_left === 16'sd0 &&
                      audit.snd_right === 16'sd0, "COLD_FINAL_NOT_ZERO");
            end
            if (has_request_fix()) begin
                check(inactive_raw == 0, "INACTIVE_RAW_NOT_ZERO");
                check(inactive_capture == 0, "INACTIVE_CAPTURE_NOT_ZERO");
            end else if (cold || label == "M2_NATURAL") begin
                check(inactive_raw > 0, "CONTROL_RAW_NOT_REPRODUCED");
            end
            if (!cold && has_output_fix()) begin
                check(inactive_zero_sample >= 0,
                      "OUTPUT_DID_NOT_CONVERGE_ZERO");
                check(inactive_nonzero_after_zero == 0,
                      "OUTPUT_NONZERO_AFTER_ZERO");
                check(audit.b_lane_l === 16'sd0 &&
                      audit.b_lane_r === 16'sd0 &&
                      audit.snd_left === 16'sd0 &&
                      audit.snd_right === 16'sd0,
                      "OUTPUT_FINAL_NOT_ZERO");
                if (label == "F3_NATURAL")
                    check(inactive_zero_sample == 4,
                          "NATURAL_ZERO_NOT_4");
                if (label == "F4_RESET")
                    check(inactive_zero_sample == 3,
                          "RESET_ZERO_NOT_3");
            end
        end
    endtask

    task automatic drain_request;
        begin
            wait (audit.adpcmb_roe_n === 1'b1);
            repeat (2) @(posedge audit.clk);
        end
    endtask

    task automatic verify_primary_baseline;
        begin
            check(active_logical == 512, "PRIMARY_LOGICAL_NOT_512");
            check(audit.adpcmb_addr == 24'h0020ff,
                  "PRIMARY_CURSOR_NOT_0020FF");
            check(audit.b_nibble === 1'b1, "PRIMARY_CURSOR_NOT_LOW");
            check(audit.b_flag === 1'b1, "PRIMARY_EOS_NOT_SET");
            check(active_logical_hash == BASE_LOGICAL,
                  "PRIMARY_LOGICAL_HASH");
            check(active_delta_hash == BASE_DELTA, "PRIMARY_DELTA_HASH");
            check(active_decoder_hash == BASE_DECODER,
                  "PRIMARY_DECODER_HASH");
            check(active_interpol_hash == BASE_INTERPOL,
                  "PRIMARY_INTERPOL_HASH");
            check(active_raw_hash == BASE_ACTIVE_RAW,
                  "PRIMARY_ACTIVE_RAW_HASH");
            check(active_gain_hash == BASE_ACTIVE_GAIN,
                  "PRIMARY_ACTIVE_GAIN_HASH");
            check(active_lane_hash == BASE_ACTIVE_LANE,
                  "PRIMARY_ACTIVE_LANE_HASH");
            check(active_final_hash == BASE_FINAL, "PRIMARY_FINAL_HASH");
            check(active_x == 0, "PRIMARY_X");
        end
    endtask

    task automatic command_reset_after_100(
        input [8*32-1:0] label,
        input logic write_zero
    );
        begin
            prepare_session(label);
            start_active(label);
            wait (active_logical >= 100);
            audit.bus.jt10_write_port0(8'h10, 8'h01);
            if (write_zero)
                audit.bus.jt10_write_port0(8'h10, 8'h00);
            stop_active();
        end
    endtask

    task automatic functional_global_reset;
        begin
            while ((audit.system_cycle % 432) != 0)
                @(posedge audit.clk);
            active_monitor = 1'b0;
            inactive_monitor = 1'b0;
            @(negedge audit.clk);
            audit.rst = 1'b1;
            audit.session_start = 1'b1;
            repeat (2) @(posedge audit.clk);
            @(negedge audit.clk);
            audit.session_start = 1'b0;
            repeat (64) @(posedge audit.clk);
            @(negedge audit.clk);
            audit.rst = 1'b0;
            wait (audit.warmup_ready === 1'b1);
            wait (audit.snd_sample === 1'b1);
        end
    endtask

    // Candidate-independent active, inactive, X/Z, and idle observers.
    always @(posedge audit.clk) begin : phase4afix_monitor
        logic pre_clk55;
        logic pre_clk;
        logic pre_raw;
        logic pre_owned_raw;
        logic pre_logical;
        logic pre_decoder;
        logic public_rise;
        integer raw_delta;
        logic [63:0] work_hash;

        pre_clk55 = audit.cen && audit.clk_en_55;
        pre_clk = audit.cen && audit.clk_en;
        pre_raw = audit.adpcmb_roe_n === 1'b0;
        pre_owned_raw = pre_raw &&
                        (audit.b_chon || audit.b_restart);
        pre_logical = pre_clk55 && audit.b_adv && audit.b_chon &&
                      !audit.b_restart && !audit.b_flag;
        pre_decoder = audit.cen && audit.decoder_adv_pipe[0] &&
                      audit.b_chon && !audit.decoder_need_clear;
        #1;
        public_rise = audit.snd_sample && !prior_public;

        if (audit.rst || audit.session_start) begin
            prior_public = 1'b0;
            prior_chon = 1'b0;
            prior_flag = 1'b0;
        end else begin
            if (active_monitor) begin
                if (audit.b_update && audit.b_on)
                    begin
                        active_start_cycle = audit.system_cycle;
                        active_stale_l = audit.snd_left;
                        active_stale_r = audit.snd_right;
                        active_stale_open =
                            active_stale_l != 0 || active_stale_r != 0;
                    end
                if (audit.b_chon && !prior_chon)
                    active_assert_cycle = audit.system_cycle;
                if (!audit.b_chon && prior_chon)
                    active_clear_cycle = audit.system_cycle;
                if (audit.b_flag && !prior_flag)
                    active_eos_cycle = audit.system_cycle;
                if (pre_owned_raw) begin
                    active_raw = active_raw + 1;
                    if (active_first_raw_cycle < 0)
                        active_first_raw_cycle = audit.system_cycle;
                    active_raw_hash =
                        hash_u24(active_raw_hash, audit.adpcmb_addr);
                    active_raw_hash =
                        hash_byte(active_raw_hash, audit.adpcmb_data);
                    if ($isunknown(audit.adpcmb_addr) ||
                        $isunknown(audit.adpcmb_data))
                        active_x = active_x + 1;
                end
                if (pre_logical) begin
                    active_logical = active_logical + 1;
                    if (active_first_logical_cycle < 0)
                        active_first_logical_cycle = audit.system_cycle;
                    active_logical_hash =
                        hash_u24(active_logical_hash, audit.adpcmb_addr);
                    active_logical_hash = hash_byte(
                        active_logical_hash,
                        {3'd0, audit.b_nibble, audit.b_present});
                    active_delta_hash =
                        hash_u16(active_delta_hash, audit.b_delta_count);
                    if ($isunknown(audit.b_present) ||
                        $isunknown(audit.b_delta_count))
                        active_x = active_x + 1;
                end
                if (pre_decoder) begin
                    active_decoder = active_decoder + 1;
                    active_decoder_hash =
                        hash_u16(active_decoder_hash, audit.decoder_x);
                    active_decoder_hash =
                        hash_u16(active_decoder_hash, audit.decoder_step);
                    if ($isunknown(audit.decoder_x) ||
                        $isunknown(audit.decoder_step))
                        active_x = active_x + 1;
                end
                if (pre_clk55 && audit.b_chon) begin
                    active_interpol = active_interpol + 1;
                    active_interpol_hash = hash_u16(
                        active_interpol_hash, audit.b_interpolation);
                    if ($isunknown(audit.b_interpolation) ||
                        $isunknown(audit.interpolation_last) ||
                        $isunknown(audit.interpolation_step))
                        active_x = active_x + 1;
                end
                if (pre_clk55 && audit.b_chon) begin
                    active_gain = active_gain + 1;
                    active_lane = active_lane + 1;
                    active_gain_hash =
                        hash_u16(active_gain_hash, audit.b_gain);
                    active_lane_hash = hash_stereo(
                        active_lane_hash, audit.b_lane_l, audit.b_lane_r);
                    if ($isunknown(audit.b_gain) ||
                        $isunknown(audit.b_lane_l) ||
                        $isunknown(audit.b_lane_r))
                        active_x = active_x + 1;
                end
                if (public_rise && audit.b_chon &&
                    !$isunknown(audit.snd_left) &&
                    !$isunknown(audit.snd_right)) begin
                    active_final_hash = hash_stereo(
                        active_final_hash,
                        audit.snd_left, audit.snd_right);
                    active_final_samples = active_final_samples + 1;
                    if (active_logical >= 8 &&
                        (audit.b_lane_l != 0 || audit.b_lane_r != 0) &&
                        !active_final_aligned) begin
                        active_final_aligned = 1'b1;
                        active_final_align_logical = active_logical;
                    end
                end
                if (public_rise && active_stale_open) begin
                    if (audit.snd_left === active_stale_l &&
                        audit.snd_right === active_stale_r)
                        active_stale_prefix =
                            active_stale_prefix + 1;
                    else
                        active_stale_open = 1'b0;
                end
                if (public_rise &&
                    ($isunknown(audit.snd_left) ||
                     $isunknown(audit.snd_right)))
                    active_x = active_x + 1;
            end

            if (inactive_monitor) begin
                if (pre_raw) begin
                    inactive_raw = inactive_raw + 1;
                    inactive_capture = inactive_capture + 1;
                    if (inactive_last_raw_cycle >= 0) begin
                        raw_delta =
                            audit.system_cycle - inactive_last_raw_cycle;
                        if (raw_delta == 144)
                            inactive_i144 = inactive_i144 + 1;
                        else if (raw_delta == 288)
                            inactive_i288 = inactive_i288 + 1;
                        else
                            inactive_iother = inactive_iother + 1;
                    end
                    inactive_last_raw_cycle = audit.system_cycle;
                    if ($isunknown(audit.adpcmb_addr) ||
                        $isunknown(audit.adpcmb_data))
                        inactive_x = inactive_x + 1;
                end
                if (pre_logical) begin
                    inactive_logical = inactive_logical + 1;
                    if (audit.adpcmb_addr < 24'h002000 ||
                        audit.adpcmb_addr > 24'h0020ff)
                        inactive_out_of_range =
                            inactive_out_of_range + 1;
                end
                if (pre_decoder)
                    inactive_decoder = inactive_decoder + 1;
                if (audit.adpcmb_addr != inactive_previous_addr) begin
                    inactive_cursor_moves =
                        inactive_cursor_moves + 1;
                    inactive_previous_addr = audit.adpcmb_addr;
                end
                if (public_rise) begin
                    inactive_samples = inactive_samples + 1;
                    work_hash = hash_stereo(
                        hash_stereo(inactive_hash,
                            audit.b_interpolation, audit.b_gain),
                        audit.snd_left, audit.snd_right);
                    inactive_hash = work_hash;
                    if ($isunknown(audit.b_interpolation) ||
                        $isunknown(audit.b_gain) ||
                        $isunknown(audit.b_lane_l) ||
                        $isunknown(audit.b_lane_r) ||
                        $isunknown(audit.snd_left) ||
                        $isunknown(audit.snd_right)) begin
                        inactive_x = inactive_x + 1;
                    end else if (audit.b_lane_l == 0 &&
                                 audit.b_lane_r == 0 &&
                                 audit.snd_left == 0 &&
                                 audit.snd_right == 0) begin
                        if (!inactive_zero_seen) begin
                            inactive_zero_seen = 1'b1;
                            inactive_zero_sample = inactive_samples;
                        end
                    end else begin
                        inactive_nonzero = inactive_nonzero + 1;
                        if (inactive_zero_seen)
                            inactive_nonzero_after_zero =
                                inactive_nonzero_after_zero + 1;
                    end
                end
            end

            if (active_monitor || inactive_monitor) begin
                if ({audit.dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on6,
                     audit.dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on5,
                     audit.dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on4,
                     audit.dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on3,
                     audit.dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on2,
                     audit.dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on1}
                    !== 6'd0)
                    idle_adpcma_active = idle_adpcma_active + 1;
                if (audit.adpcma_roe_n !== 1'b1)
                    idle_adpcma_raw = idle_adpcma_raw + 1;
                if (audit.dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.decon
                    !== 1'b0)
                    idle_adpcma_logical = idle_adpcma_logical + 1;
                if (audit.dut.u_jt10.u_jt12.adpcmA_l !== 16'sd0 ||
                    audit.dut.u_jt10.u_jt12.adpcmA_r !== 16'sd0)
                    idle_adpcma_lane = idle_adpcma_lane + 1;
                if (pre_clk &&
                    !((audit.final_cur_op == 2'd0 &&
                       audit.final_cur_ch == 3'd0) ||
                      (audit.final_cur_op == 2'd0 &&
                       audit.final_cur_ch == 3'd4)) &&
                    ((audit.dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_en_l &&
                      audit.acc_input_l !== 16'sd0) ||
                     (audit.dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_en_r &&
                      audit.acc_input_r !== 16'sd0)))
                    idle_fm = idle_fm + 1;
                if (audit.psg_A !== 0 || audit.psg_B !== 0 ||
                    audit.psg_C !== 0 || audit.psg_snd !== 0)
                    idle_ssg = idle_ssg + 1;
                if (audit.dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[7]
                        !== 8'h3f ||
                    audit.dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[8]
                        !== 8'h00 ||
                    audit.dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[9]
                        !== 8'h00 ||
                    audit.dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[10]
                        !== 8'h00)
                    idle_ssg_control = idle_ssg_control + 1;
            end
        end
        prior_public = audit.snd_sample;
        prior_chon = audit.b_chon;
        prior_flag = audit.b_flag;
    end

    initial begin : phase4afix_sequence
        // Stop only the inherited diagnostic sequence.  The DUT, monitors,
        // BFM, clock, and ROM model continue normally.
        #0 disable audit.phase4afix_inherited_sequence;
        if (!$value$plusargs("VARIANT_ID=%d", variant_id))
            variant_id = 6;
        if (!$value$plusargs("VARIANT=%s", variant_name))
            variant_name = "PC_GATE";
        if (!$value$plusargs("RUN_ID=%d", run_id))
            run_id = 1;
        audit.run_id = run_id;
        if ($test$plusargs("QUICK")) begin
            quick_mode = 1;
            inactive_samples_goal = 32;
            long_samples_goal = 64;
        end
        $display("PHASE4AFIX_BEGIN variant=%0s id=%0d run=%0d quick=%0d",
            variant_name, variant_id, run_id, quick_mode);
        check(variant_id == 6 && variant_name == "PC_GATE",
              "PC_GATE_ONLY");
        repeat (8) @(posedge audit.clk);

        // F1: both pan/level write orders and full configure without START.
        prepare_cold_write_order("F1_PAN_LEVEL", 1'b0);
        run_inactive_window("F1_PAN_LEVEL",
            quick_mode ? 32 : 16384, 1'b1);
        prepare_cold_write_order("F1_LEVEL_PAN", 1'b1);
        run_inactive_window("F1_LEVEL_PAN",
            quick_mode ? 32 : 16384, 1'b1);
        prepare_session("F1_CONFIG");
        run_inactive_window("F1_CONFIG", inactive_samples_goal, 1'b1);

        // F2/F3/F5: primary single-shot plus natural-end inactive soak.
        prepare_session("F2_PRIMARY");
        start_active("F2_PRIMARY");
        stop_active();
        wait (audit.b_flag === 1'b1);
        print_active("F2_PRIMARY");
        verify_primary_baseline();
        save_primary();
        drain_request();
        run_inactive_window("F3_NATURAL", inactive_samples_goal, 1'b0);
        if (!has_output_fix()) begin
            check(audit.snd_left === 16'sd16319 &&
                  audit.snd_right === 16'sd16319,
                  "V1_NATURAL_HOLD_CHANGED");
        end

        // F6: same-session natural-end restart.
        start_active("F6_NATURAL_RESTART");
        stop_active();
        wait (audit.b_flag === 1'b1);
        print_active("F6_NATURAL_RESTART");
        check_primary("F6_NATURAL_RESTART");

        // F4/F5: command RESET after 100 consumes, then inactive soak.
        command_reset_after_100("F4_RESET", 1'b0);
        drain_request();
        run_inactive_window("F4_RESET", inactive_samples_goal, 1'b0);
        if (!has_output_fix()) begin
            check(audit.snd_left === -16'sd2707 &&
                  audit.snd_right === -16'sd2707,
                  "V1_RESET_HOLD_CHANGED");
        end

        // F7: START directly after RESET, no intervening 00.
        start_active("F7_RESET_RESTART");
        stop_active();
        wait (audit.b_flag === 1'b1);
        print_active("F7_RESET_RESTART");
        check_primary("F7_RESET_RESTART");

        // F8: RESET -> 00 -> START compatibility sequence.
        command_reset_after_100("F8_RESET_00", 1'b1);
        drain_request();
        start_active("F8_RESET_00_RESTART");
        stop_active();
        wait (audit.b_flag === 1'b1);
        print_active("F8_RESET_00_RESTART");
        check_primary("F8_RESET_00_RESTART");

        // F9: all-off long soak and restart.
        if (is_integrated()) begin
            drain_request();
            run_inactive_window("F9_LONG", long_samples_goal, 1'b0);
            start_active("F9_LONG_RESTART");
            stop_active();
            wait (audit.b_flag === 1'b1);
            print_active("F9_LONG_RESTART");
            check_primary("F9_LONG_RESTART");
        end

        // F10: V1 global reset while active and after stop, then restart.
        // after a stopped playback, followed by cold/restart checks.
        if (variant_id == 0 || is_integrated()) begin
            prepare_session("F10_ACTIVE_RESET");
            start_active("F10_ACTIVE_RESET");
            wait (active_logical >= 100);
            functional_global_reset();
            check(audit.b_chon === 1'b0, "GLOBAL_ACTIVE_CHON");
            check(audit.b_interpolation === 16'sd0 &&
                  audit.b_gain === 16'sd0 &&
                  audit.b_lane_l === 16'sd0 &&
                  audit.b_lane_r === 16'sd0 &&
                  audit.snd_left === 16'sd0 &&
                  audit.snd_right === 16'sd0,
                  "GLOBAL_ACTIVE_STATE");
            audit.keyoff_fm();
            audit.bus.jt10_write_port0(8'h08, 8'h00);
            audit.bus.jt10_write_port0(8'h09, 8'h00);
            audit.bus.jt10_write_port0(8'h0a, 8'h00);
            audit.bus.jt10_write_port0(8'h07, 8'h3f);
            audit.bus.jt10_write_port1(8'h00, 8'hbf);
            audit.configure_b(16'h0020, 16'h0020);
            start_active("F10_ACTIVE_RESET_RESTART");
            stop_active();
            wait (audit.b_flag === 1'b1);
            check_primary("F10_ACTIVE_RESET_RESTART");

            functional_global_reset();
            check(audit.b_interpolation === 16'sd0 &&
                  audit.b_gain === 16'sd0 &&
                  audit.b_lane_l === 16'sd0 &&
                  audit.b_lane_r === 16'sd0 &&
                  audit.snd_left === 16'sd0 &&
                  audit.snd_right === 16'sd0,
                  "GLOBAL_STOP_STATE");
        end

        check(audit.busy_timeout_count == 0, "BUSY_TIMEOUT");
        check(audit.busy_while_write_count == 0, "BUSY_WHILE_WRITE");
        check(audit.cadence_errors == 0, "CADENCE");
        check(audit.width_errors == 0, "WIDTH");
        check(audit.drops == 0, "SAMPLE_DROP");
        check(audit.duplicates == 0, "SAMPLE_DUPLICATE");
        check(idle_adpcma_active == 0, "ADPCMA_ACTIVE");
        check(idle_adpcma_raw == 0, "ADPCMA_RAW");
        check(idle_adpcma_logical == 0, "ADPCMA_LOGICAL");
        check(idle_adpcma_lane == 0, "ADPCMA_LANE");
        check(idle_fm == 0, "FM_NOT_IDLE");
        check(idle_ssg == 0, "SSG_NOT_IDLE");
        check(idle_ssg_control == 0, "SSG_CONTROL_NOT_IDLE");
        if (variant_id == 7)
            check(pc_clear_reject_seen > 0,
                  "PC_CLEAR_REJECTION_NOT_REPRODUCED");

        $display("PHASE4AFIX_TRANSPORT variant=%0s run=%0d writes=%0d busy_min=%0d busy_max=%0d busy_hash=%016h timeout=%0d busy_write=%0d",
            variant_name, run_id, audit.accepted_write_count,
            audit.busy_min_cycles, audit.busy_max_cycles,
            audit.busy_duration_hash, audit.busy_timeout_count,
            audit.busy_while_write_count);
        $display("PHASE4AFIX_SAMPLE variant=%0s run=%0d cadence=%0d width=%0d drops=%0d duplicates=%0d adpcma=%0d/%0d/%0d/%0d fm=%0d ssg=%0d control=%0d",
            variant_name, run_id, audit.cadence_errors,
            audit.width_errors, audit.drops, audit.duplicates,
            idle_adpcma_active, idle_adpcma_raw,
            idle_adpcma_logical, idle_adpcma_lane,
            idle_fm, idle_ssg, idle_ssg_control);
        $display("PHASE4AFIX_CLASS variant=%0s run=%0d output=%0s request=%0s restart=%0s integrated=%0d selected=%0d rejected=%0d failures=%0d",
            variant_name, run_id,
            has_output_fix() ? "ZERO" : "HOLD",
            has_request_fix() ? "GATED" : "RAW_ONLY",
            has_restart_fix() ? "REPLAY" : "DEFECT",
            is_integrated(), variant_id == 6,
            variant_id == 7 && pc_clear_reject_seen > 0, failures);
        if (failures == 0) begin
            $display("PHASE4AFIX_PASS variant=%0s run=%0d",
                variant_name, run_id);
            $finish;
        end
        $fatal(1, "PHASE4AFIX_RESULT variant=%0s run=%0d failures=%0d",
            variant_name, run_id, failures);
    end
endmodule

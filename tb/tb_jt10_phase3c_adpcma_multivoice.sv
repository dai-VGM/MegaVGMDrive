`timescale 1ns/1ps

module tb_jt10_phase3c_adpcma_multivoice;
    localparam [63:0] FNV_OFFSET = 64'hcbf29ce484222325;
    localparam integer SCHEDULER_PERIOD = 432;
    localparam integer KEYON_ISSUE_PIPELINE = 7;
    localparam integer CANONICAL_PHASE = 230;
    localparam integer TAG_DEPTH = 48;
    localparam integer STATE_TAG = 2;
    localparam integer CONTRIB_TAG = 35;
    localparam [7:0] SAFE_STEREO = 8'hc0;
    localparam [7:0] SAFE_LEFT = 8'h80;
    localparam [7:0] SAFE_RIGHT = 8'h40;
    localparam [7:0] PRIMARY_STEREO = 8'hf5;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cen = 1'b0;
    logic session_start = 1'b1;
    logic loop_event = 1'b0;
    logic changed_pattern = 1'b0;
    logic [7:0] adpcmb_data = 8'h00;

    wire [1:0] addr;
    wire [7:0] din;
    wire cs_n;
    wire wr_n;
    wire [7:0] dout;
    wire irq_n;
    wire [19:0] adpcma_addr;
    wire [3:0] adpcma_bank;
    wire adpcma_roe_n;
    wire [7:0] adpcma_data;
    wire [23:0] adpcmb_addr;
    wire adpcmb_roe_n;
    wire [7:0] psg_A;
    wire [7:0] psg_B;
    wire [7:0] psg_C;
    wire [9:0] psg_snd;
    wire signed [15:0] snd_left;
    wire signed [15:0] snd_right;
    wire snd_sample;
    wire signed [15:0] internal_snd_left;
    wire signed [15:0] internal_snd_right;
    wire internal_snd_sample;
    wire signed [15:0] internal_fm_snd;
    wire [2:0] warmup_count;
    wire warmup_ready;
    wire [2:0] reset_cen_count;
    wire reset_cen_valid;

    wire signed [15:0] adpcma_l = dut.u_jt10.u_jt12.adpcmA_l;
    wire signed [15:0] adpcma_r = dut.u_jt10.u_jt12.adpcmA_r;
    wire signed [15:0] adpcmb_l = dut.u_jt10.u_jt12.adpcmB_l;
    wire signed [15:0] adpcmb_r = dut.u_jt10.u_jt12.adpcmB_r;
    wire clk_en = dut.u_jt10.u_jt12.clk_en;
    wire clk_en_666 = dut.u_jt10.u_jt12.clk_en_666;
    wire adpcma_rst_n = dut.u_jt10.u_jt12.gen_adpcm.rst_n;
    wire [5:0] adpcma_cur_ch =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.cur_ch;
    wire [5:0] adpcma_en_ch =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.en_ch;
    wire adpcma_match =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.match;
    wire [3:0] captured_nibble =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.data;
    wire nibble_select =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.nibble_sel;
    wire adpcma_decon =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.decon;
    wire adpcma_clr_dec =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.clr;
    wire decoder_state_commit =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_decoder.chon4;
    wire physical_cursor_commit =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.sumup6 &&
        !dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.skip6 &&
        !(dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.clr6 &&
          dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on6);
    wire signed [15:0] decoded_pcm =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.pcmdec;
    wire signed [15:0] gain_pcm =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.pcm_att;
    wire [1:0] gain_pan =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.lr;
    wire adpcma_on1 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on1;
    wire adpcma_on2 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on2;
    wire adpcma_on3 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on3;
    wire adpcma_on4 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on4;
    wire adpcma_on5 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on5;
    wire adpcma_on6 =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.on6;
    wire [5:0] active_mask =
        (adpcma_on1 ? adpcma_cur_ch : 6'd0) |
        (adpcma_on2 ?
            {adpcma_cur_ch[0], adpcma_cur_ch[5:1]} : 6'd0) |
        (adpcma_on3 ?
            {adpcma_cur_ch[1:0], adpcma_cur_ch[5:2]} : 6'd0) |
        (adpcma_on4 ?
            {adpcma_cur_ch[2:0], adpcma_cur_ch[5:3]} : 6'd0) |
        (adpcma_on5 ?
            {adpcma_cur_ch[3:0], adpcma_cur_ch[5:4]} : 6'd0) |
        (adpcma_on6 ?
            {adpcma_cur_ch[4:0], adpcma_cur_ch[5]} : 6'd0);
    wire adpcma_active_any = |active_mask;
    wire [7:0] adpcma_command = dut.u_jt10.u_jt12.aon_a;
    wire adpcma_command_update = dut.u_jt10.u_jt12.up_aon;
    wire [5:0] adpcma_total_level = dut.u_jt10.u_jt12.atl_a;
    wire [7:0] adpcma_pan_level = dut.u_jt10.u_jt12.lracl;
    wire [15:0] adpcma_address_latch = dut.u_jt10.u_jt12.addr_a;
    wire [5:0] adpcma_flags = dut.u_jt10.u_jt12.adpcma_flags;
    wire signed [15:0] actual_acc_input_l =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_input_l;
    wire signed [15:0] actual_acc_input_r =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_input_r;
    wire actual_acc_enable_l =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_en_l;
    wire actual_acc_enable_r =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_en_r;
    wire [2:0] final_cur_ch = dut.u_jt10.u_jt12.cur_ch;
    wire [1:0] final_cur_op = dut.u_jt10.u_jt12.cur_op;
    wire [2:0] final_alg = dut.u_jt10.u_jt12.alg_I;
    wire [1:0] final_rl = dut.u_jt10.u_jt12.rl;
    wire final_zero = dut.u_jt10.u_jt12.zero;
    wire final_s1 = dut.u_jt10.u_jt12.s2_enters;
    wire final_s2 = dut.u_jt10.u_jt12.s1_enters;
    wire final_s3 = dut.u_jt10.u_jt12.s4_enters;
    wire final_s4 = dut.u_jt10.u_jt12.s3_enters;
    wire signed [13:0] fm_operator = dut.u_jt10.u_jt12.op_result_hd;
    wire adpcmb_active =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.chon;
    wire adpcmb_start = dut.u_jt10.u_jt12.acmd_on_b;
    wire [7:0] ssg_mixer =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[7];
    wire [7:0] ssg_volume_a =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[8];
    wire [7:0] ssg_volume_b =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[9];
    wire [7:0] ssg_volume_c =
        dut.u_jt10.u_jt12.gen_ssg.u_psg.regarray[10];

    wire [31:0] accepted_write_count;
    wire [31:0] port0_write_count;
    wire [31:0] port1_write_count;
    wire [31:0] busy_timeout_count;
    wire [31:0] busy_while_write_count;
    wire [31:0] busy_min_cycles;
    wire [31:0] busy_max_cycles;
    wire [31:0] last_issue_cycle;
    wire [31:0] last_busy_assert_cycle;
    wire [31:0] last_busy_clear_cycle;
    wire [63:0] busy_duration_hash;

    wire signed [15:0] ref_adpcma_l;
    wire signed [15:0] ref_adpcma_r;
    wire signed [17:0] ref_acc_l;
    wire signed [17:0] ref_acc_r;
    wire signed [17:0] ref_last_l;
    wire signed [17:0] ref_last_r;
    wire signed [17:0] ref_step_l;
    wire signed [17:0] ref_step_r;
    wire signed [17:0] ref_full_l;
    wire signed [17:0] ref_full_r;
    wire ref_adpcma_overflow_l;
    wire ref_adpcma_overflow_r;
    wire signed [15:0] ref_final_input_l;
    wire signed [15:0] ref_final_input_r;
    wire ref_final_enable_l;
    wire ref_final_enable_r;
    wire signed [15:0] ref_final_l;
    wire signed [15:0] ref_final_r;
    wire ref_final_overflow_l;
    wire ref_final_overflow_r;
    wire ref_final_wrap_l;
    wire ref_final_wrap_r;

    integer run_id = 1;
    integer scenario_id = 1;
    integer quick_mode = 0;
    integer command_phase = CANONICAL_PHASE;
    logic command_phase_override = 1'b0;
    reg [8*12-1:0] scenario_name = "A";
    integer failures = 0;
    integer system_cycle = 0;
    integer warmup_ready_cycle = -1;
    integer first_public_cycle = -1;
    integer public_sample_count = 0;
    integer internal_sample_count = 0;
    integer cadence_errors = 0;
    integer width_errors = 0;
    integer drop_count = 0;
    integer duplicate_count = 0;
    integer x_count = 0;
    integer last_public_rise = -1;
    integer public_width = 0;
    logic previous_public_sample = 1'b0;
    logic previous_internal_sample = 1'b0;
    logic previous_ready = 1'b0;
    logic previous_command_update = 1'b0;

    integer adpcma_register_writes = 0;
    integer adpcma_command_writes = 0;
    integer adpcma_command_updates = 0;
    integer command_duplicate_count = 0;
    integer command_missed_count = 0;
    integer command_mask_errors = 0;
    integer active_mask_errors = 0;
    integer command_seen [0:11];
    reg [7:0] last_expected_command = 8'hbf;

    integer cfg_start [0:5];
    integer cfg_end [0:5];
    reg [7:0] cfg_level [0:5];

    logic measure_active = 1'b0;
    logic audit_active = 1'b0;
    integer measure_start_cycle = 0;
    integer measure_samples = 0;
    integer measure_goal = 0;
    reg [5:0] measure_target_mask = 6'd0;
    reg [5:0] stable_expected_mask = 6'd0;
    logic stable_mask_check = 1'b0;
    integer global_fetch_count = 0;
    integer owner_unknown_count = 0;
    integer owner_inactive_count = 0;
    integer owner_duplicate_cycle_count = 0;
    integer capture_mismatch_count = 0;
    integer ownership_mismatch_count = 0;
    integer range_error_count = 0;
    integer progression_error_count = 0;
    integer missed_slot_count = 0;
    integer duplicate_slot_count = 0;
    integer starvation_count = 0;
    integer pan_leak_count = 0;
    integer last_fetch_cycle_global = -1;
    reg [5:0] owner_round_seen = 6'd0;
    integer owner_round_count = 0;

    integer voice_fetch_count [0:5];
    integer voice_raw_count [0:5];
    integer voice_dummy_raw_count [0:5];
    integer voice_capture_count [0:5];
    integer voice_decoder_input_count [0:5];
    integer voice_decode_count [0:5];
    integer voice_physical_cursor_count [0:5];
    integer voice_logical_cursor_count [0:5];
    integer voice_gain_count [0:5];
    integer voice_physical_contribution_count [0:5];
    integer voice_logical_contribution_count [0:5];
    integer voice_audible_nonzero_count [0:5];
    integer voice_unique_count [0:5];
    integer voice_repeated_count [0:5];
    integer voice_high_count [0:5];
    integer voice_low_count [0:5];
    integer voice_out_of_range_count [0:5];
    integer voice_owner_mismatch_count [0:5];
    integer voice_cross_owner_count [0:5];
    integer voice_dummy_audible_count [0:5];
    integer voice_first_fetch_cycle [0:5];
    integer voice_last_fetch_cycle [0:5];
    integer voice_first_address [0:5];
    integer voice_last_address [0:5];
    integer voice_last_nibble [0:5];
    integer voice_peak [0:5];
    logic voice_seen_fetch [0:5];
    logic [63:0] voice_raw_hash [0:5];
    logic [63:0] voice_dummy_hash [0:5];
    logic [63:0] voice_fetch_hash [0:5];
    logic [63:0] voice_address_hash [0:5];
    logic [63:0] voice_rom_hash [0:5];
    logic [63:0] voice_decode_hash [0:5];
    logic [63:0] voice_cursor_hash [0:5];
    logic [63:0] voice_gain_hash [0:5];
    logic [63:0] voice_left_hash [0:5];
    logic [63:0] voice_right_hash [0:5];
    logic [63:0] control_fetch_hash [0:5];
    logic [63:0] control_raw_hash [0:5];
    logic [63:0] control_dummy_hash [0:5];
    logic [63:0] control_address_hash [0:5];
    logic [63:0] control_rom_hash [0:5];
    logic [63:0] control_decode_hash [0:5];
    logic [63:0] control_gain_hash [0:5];
    logic [63:0] control_left_hash [0:5];
    logic [63:0] control_right_hash [0:5];
    integer control_fetch_count [0:5];
    integer control_raw_count [0:5];
    integer control_dummy_raw_count [0:5];
    integer control_decode_count [0:5];
    integer control_physical_cursor_count [0:5];
    integer control_logical_contribution_count [0:5];
    logic [63:0] control_cursor_hash [0:5];

    logic [63:0] active_mask_hash = FNV_OFFSET;
    logic [63:0] raw_owner_hash = FNV_OFFSET;
    logic [63:0] raw_request_hash = FNV_OFFSET;
    logic [63:0] dummy_request_hash = FNV_OFFSET;
    logic [63:0] owner_hash = FNV_OFFSET;
    logic [63:0] aggregate_fetch_hash = FNV_OFFSET;
    logic [63:0] physical_cursor_hash = FNV_OFFSET;
    logic [63:0] logical_contribution_hash = FNV_OFFSET;
    logic [63:0] aggregate_l_hash = FNV_OFFSET;
    logic [63:0] aggregate_r_hash = FNV_OFFSET;
    logic [63:0] final_l_hash = FNV_OFFSET;
    logic [63:0] final_r_hash = FNV_OFFSET;
    logic [63:0] stereo_hash = FNV_OFFSET;
    logic [63:0] stop_hash = FNV_OFFSET;
    integer sample_nonzero = 0;
    integer sample_peak = 0;
    integer sample_min = 32767;
    integer sample_max = -32768;
    integer zero_crossings = 0;
    integer previous_sign = 0;
    integer previous_sign_valid = 0;
    longint signed dc_sum_l = 0;
    longint signed dc_sum_r = 0;

    integer arithmetic_compare_count = 0;
    integer arithmetic_mismatch_count = 0;
    integer aggregate_saturation_count = 0;
    integer aggregate_wrap_count = 0;
    integer gain_truncation_count = 0;
    integer interpolation_truncation_count = 0;
    integer decoder_wrap_count = 0;
    integer final_saturation_count = 0;
    integer final_wrap_count = 0;
    integer mathematical_sum_peak = 0;
    integer aggregate_peak = 0;

    integer raw_request_count = 0;
    integer dummy_request_count = 0;
    integer logical_consume_count = 0;
    integer decoder_input_count = 0;
    integer decoder_state_commit_count = 0;
    integer physical_cursor_commit_count = 0;
    integer logical_cursor_commit_count = 0;
    integer physical_contribution_count = 0;
    integer logical_contribution_count = 0;
    integer audible_nonzero_contribution_count = 0;
    integer aggregate_commit_count = 0;
    integer standard_acc_insert_count = 0;
    integer final_publish_count = 0;
    integer raw_owner_unknown_count = 0;
    integer capture_owner_mismatch_count = 0;
    integer logical_owner_unknown_count = 0;
    integer logical_decoder_owner_mismatch_count = 0;
    integer cursor_cross_update_count = 0;
    integer rom_contamination_count = 0;
    integer contribution_owner_mismatch_count = 0;
    integer clear_decoder_gate_count = 0;
    integer clear_state_commit_count = 0;
    integer clear_logical_cursor_count = 0;
    integer clear_physical_contribution_count = 0;
    integer clear_logical_contribution_count = 0;
    integer dummy_audible_effect_count = 0;
    integer class_c_violation_count = 0;
    integer accepted_state_mismatch_count = 0;
    integer accepted_contribution_mismatch_count = 0;
    integer tag_age_error_count = 0;

    logic tag_valid [0:TAG_DEPTH];
    logic tag_clr [0:TAG_DEPTH];
    integer tag_owner [0:TAG_DEPTH];
    integer tag_address [0:TAG_DEPTH];
    integer tag_nibble [0:TAG_DEPTH];
    logic [3:0] tag_data [0:TAG_DEPTH];
    integer tag_cycle [0:TAG_DEPTH];

    integer adpcmb_fetch_count = 0;
    integer adpcmb_nonidle_count = 0;
    integer fm_nonidle_count = 0;
    integer ssg_nonidle_count = 0;
    integer noise_enable_count = 0;
    integer envelope_enable_count = 0;

    integer event_cycle [0:15];
    integer event_value [0:15];
    integer event_count = 0;
    reg [5:0] clear_sequence [0:7];
    integer clear_sequence_count = 0;
    logic track_clear_sequence = 1'b0;
    reg [5:0] previous_tracked_mask = 6'd0;
    integer retrigger_delay = 0;

    reg pre_clk_en;
    reg pre_clk_en_666;
    reg pre_valid_fetch;
    reg pre_logical_consume;
    reg pre_decoder_state_commit;
    reg pre_physical_cursor_commit;
    reg [20:0] pre_physical_cursor_address;
    reg [5:0] pre_cur_ch;
    reg [5:0] pre_en_ch;
    reg [5:0] pre_active_mask;
    reg pre_match;
    reg [19:0] pre_fetch_address;
    reg [3:0] pre_fetch_bank;
    reg pre_fetch_nibble;
    reg pre_fetch_clr;
    reg [7:0] pre_fetch_data;
    reg signed [15:0] pre_gain_pcm;
    reg [1:0] pre_gain_pan;
    reg pre_public_rise;
    reg pre_internal_rise;

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
        reg [63:0] work;
        begin
            work = hash_byte(hash_in, value[7:0]);
            hash_u16 = hash_byte(work, value[15:8]);
        end
    endfunction

    function automatic [63:0] hash_u24(
        input [63:0] hash_in,
        input [23:0] value
    );
        reg [63:0] work;
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
        reg [63:0] work;
        begin
            work = hash_u16(hash_in, left_value);
            hash_stereo = hash_u16(work, right_value);
        end
    endfunction

    function automatic integer onehot_index(input [5:0] value);
        begin
            case (value)
                6'b000001: onehot_index = 0;
                6'b000010: onehot_index = 1;
                6'b000100: onehot_index = 2;
                6'b001000: onehot_index = 3;
                6'b010000: onehot_index = 4;
                6'b100000: onehot_index = 5;
                default: onehot_index = -1;
            endcase
        end
    endfunction

    function automatic [5:0] rotate_right(
        input [5:0] value,
        input integer count
    );
        integer index;
        reg [5:0] work;
        begin
            work = value;
            for (index = 0; index < count; index = index + 1)
                work = {work[0], work[5:1]};
            rotate_right = work;
        end
    endfunction

    function automatic integer abs16(input signed [15:0] value);
        integer signed extended;
        begin
            extended = value;
            abs16 = extended < 0 ? -extended : extended;
        end
    endfunction

    function automatic [7:0] expected_rom(input [23:0] logical_address);
        reg [7:0] low_term;
        reg [7:0] high_term;
        begin
            low_term = logical_address[7:0] * 8'd73;
            high_term = {4'd0, logical_address[11:8]} * 8'd29;
            expected_rom = low_term + high_term + 8'd41;
        end
    endfunction

    always #5 clk = ~clk;

    jt10_phase3a_adpcma_rom rom (
        .address(adpcma_addr),
        .bank(adpcma_bank),
        .changed_pattern(changed_pattern),
        .data(adpcma_data)
    );

    jt10_cpu_bus_bfm bus (
        .rst(rst), .clk(clk), .dout(dout),
        .addr(addr), .din(din), .cs_n(cs_n), .wr_n(wr_n),
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
        .addr(addr), .din(din), .cs_n(cs_n), .wr_n(wr_n),
        .irq_n(irq_n), .dout(dout),
        .snd_left(snd_left), .snd_right(snd_right),
        .snd_sample(snd_sample),
        .psg_A(psg_A), .psg_B(psg_B), .psg_C(psg_C),
        .psg_snd(psg_snd),
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

    jt10_phase3c_adpcma_acc_reference ref_acc_left (
        .rst_n(adpcma_rst_n), .clk(clk), .cen(clk_en_666),
        .cur_ch(adpcma_cur_ch), .en_ch(adpcma_en_ch),
        .match(adpcma_match), .en_sum(gain_pan[1]),
        .pcm_in(gain_pcm), .pcm_out(ref_adpcma_l),
        .acc_state(ref_acc_l), .last_state(ref_last_l),
        .step_state(ref_step_l), .full_state(ref_full_l),
        .full_overflow(ref_adpcma_overflow_l)
    );

    jt10_phase3c_adpcma_acc_reference ref_acc_right (
        .rst_n(adpcma_rst_n), .clk(clk), .cen(clk_en_666),
        .cur_ch(adpcma_cur_ch), .en_ch(adpcma_en_ch),
        .match(adpcma_match), .en_sum(gain_pan[0]),
        .pcm_in(gain_pcm), .pcm_out(ref_adpcma_r),
        .acc_state(ref_acc_r), .last_state(ref_last_r),
        .step_state(ref_step_r), .full_state(ref_full_r),
        .full_overflow(ref_adpcma_overflow_r)
    );

    jt10_phase3c_final_acc_reference ref_final (
        .rst(rst), .clk(clk), .clk_en(clk_en),
        .op_result(fm_operator), .rl(final_rl), .zero(final_zero),
        .s1_enters(final_s1), .s2_enters(final_s2),
        .s3_enters(final_s3), .s4_enters(final_s4),
        .cur_ch(final_cur_ch), .cur_op(final_cur_op), .alg(final_alg),
        .adpcma_l(adpcma_l), .adpcma_r(adpcma_r),
        .adpcmb_l(adpcmb_l), .adpcmb_r(adpcmb_r),
        .expected_input_l(ref_final_input_l),
        .expected_input_r(ref_final_input_r),
        .expected_enable_l(ref_final_enable_l),
        .expected_enable_r(ref_final_enable_r),
        .expected_left(ref_final_l), .expected_right(ref_final_r),
        .overflow_l(ref_final_overflow_l),
        .overflow_r(ref_final_overflow_r),
        .adpcma_wrap_l(ref_final_wrap_l),
        .adpcma_wrap_r(ref_final_wrap_r)
    );

    task automatic fail(input [8*96-1:0] message);
        begin
            failures = failures + 1;
            $display("FAIL scenario=%0s cycle=%0d %0s",
                     scenario_name, system_cycle, message);
        end
    endtask

    task automatic wait_clocks(input integer count);
        repeat (count) @(posedge clk);
    endtask

    task automatic write_adpcma(
        input [7:0] register_address,
        input [7:0] register_data
    );
        begin
            if (register_address == 8'h00) begin
                last_expected_command = register_data;
                adpcma_command_writes = adpcma_command_writes + 1;
                case (register_data)
                    8'h03: command_seen[0] = 1;
                    8'h07: command_seen[1] = 1;
                    8'h0f: command_seen[2] = 1;
                    8'h3f: command_seen[3] = 1;
                    8'h81: command_seen[4] = 1;
                    8'h82: command_seen[5] = 1;
                    8'h84: command_seen[6] = 1;
                    8'h88: command_seen[7] = 1;
                    8'h90: command_seen[8] = 1;
                    8'ha0: command_seen[9] = 1;
                    8'hbf: command_seen[10] = 1;
                    8'h40,
                    8'hc0: command_seen[11] = 1;
                    default: ;
                endcase
            end
            bus.jt10_write_port1(register_address, register_data);
            adpcma_register_writes = adpcma_register_writes + 1;
            #1;
            if (dut.u_jt10.u_jt12.u_mmr.part !== 1'b1 ||
                dut.u_jt10.u_jt12.u_mmr.selected_register !==
                    register_address ||
                dut.u_jt10.u_jt12.u_mmr.din_copy !== register_data)
                fail("ADPCM-A transport capture mismatch");
        end
    endtask

    task automatic keyoff_all_fm;
        begin
            bus.jt10_write_port0(8'h28, 8'h00);
            bus.jt10_write_port0(8'h28, 8'h01);
            bus.jt10_write_port0(8'h28, 8'h02);
            bus.jt10_write_port0(8'h28, 8'h04);
            bus.jt10_write_port0(8'h28, 8'h05);
            bus.jt10_write_port0(8'h28, 8'h06);
        end
    endtask

    task automatic wait_mask(input [5:0] expected_mask);
        integer timeout;
        begin
            stable_mask_check = 1'b0;
            timeout = 0;
            while (active_mask !== expected_mask && timeout < 20000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (active_mask !== expected_mask)
                fail("active-mask transition timeout");
            stable_expected_mask = expected_mask;
            stable_mask_check = 1'b1;
        end
    endtask

    task automatic align_command_phase;
        integer before_cycle;
        begin
            before_cycle = system_cycle;
            do begin
                @(posedge clk);
                #1;
            end while ((system_cycle + KEYON_ISSUE_PIPELINE) %
                       SCHEDULER_PERIOD != command_phase);
            retrigger_delay = system_cycle - before_cycle;
        end
    endtask

    task automatic select_mask_phase(input [5:0] mask);
        begin
            if (!command_phase_override) begin
                case (mask)
                    6'h07: command_phase = 170;
                    6'h0f: command_phase = 110;
                    6'h3f: command_phase = 50;
                    default: command_phase = CANONICAL_PHASE;
                endcase
            end
        end
    endtask

    task automatic issue_keyon(input [5:0] mask);
        begin
            stable_mask_check = 1'b0;
            write_adpcma(8'h00, {2'b00, mask});
            wait_mask(mask);
        end
    endtask

    task automatic issue_keyoff(
        input [5:0] bits,
        input [5:0] expected_mask
    );
        begin
            stable_mask_check = 1'b0;
            write_adpcma(8'h00, {2'b10, bits});
            wait_mask(expected_mask);
        end
    endtask

    task automatic program_voice(
        input integer voice,
        input integer start_page,
        input integer end_page,
        input [7:0] level
    );
        begin
            cfg_start[voice] = start_page;
            cfg_end[voice] = end_page;
            cfg_level[voice] = level;
            write_adpcma(8'h10 + voice, start_page[7:0]);
            write_adpcma(8'h18 + voice, start_page[15:8]);
            write_adpcma(8'h20 + voice, end_page[7:0]);
            write_adpcma(8'h28 + voice, end_page[15:8]);
            write_adpcma(8'h08 + voice, level);
        end
    endtask

    task automatic measurement_begin(
        input [5:0] target_mask,
        input integer sample_goal
    );
        integer voice;
        integer tag_index;
        begin
            @(negedge clk);
            measure_active = 1'b0;
            measure_target_mask = target_mask;
            measure_goal = sample_goal;
            measure_samples = 0;
            measure_start_cycle = system_cycle;
            global_fetch_count = 0;
            owner_unknown_count = 0;
            owner_inactive_count = 0;
            owner_duplicate_cycle_count = 0;
            capture_mismatch_count = 0;
            ownership_mismatch_count = 0;
            range_error_count = 0;
            progression_error_count = 0;
            missed_slot_count = 0;
            duplicate_slot_count = 0;
            starvation_count = 0;
            pan_leak_count = 0;
            last_fetch_cycle_global = -1;
            owner_round_seen = 6'd0;
            owner_round_count = 0;
            active_mask_hash = FNV_OFFSET;
            raw_owner_hash = FNV_OFFSET;
            raw_request_hash = FNV_OFFSET;
            dummy_request_hash = FNV_OFFSET;
            owner_hash = FNV_OFFSET;
            aggregate_fetch_hash = FNV_OFFSET;
            physical_cursor_hash = FNV_OFFSET;
            logical_contribution_hash = FNV_OFFSET;
            aggregate_l_hash = FNV_OFFSET;
            aggregate_r_hash = FNV_OFFSET;
            final_l_hash = FNV_OFFSET;
            final_r_hash = FNV_OFFSET;
            stereo_hash = FNV_OFFSET;
            sample_nonzero = 0;
            sample_peak = 0;
            sample_min = 32767;
            sample_max = -32768;
            zero_crossings = 0;
            previous_sign = 0;
            previous_sign_valid = 0;
            dc_sum_l = 0;
            dc_sum_r = 0;
            arithmetic_compare_count = 0;
            arithmetic_mismatch_count = 0;
            aggregate_saturation_count = 0;
            aggregate_wrap_count = 0;
            gain_truncation_count = 0;
            interpolation_truncation_count = 0;
            decoder_wrap_count = 0;
            final_saturation_count = 0;
            final_wrap_count = 0;
            mathematical_sum_peak = 0;
            aggregate_peak = 0;
            raw_request_count = 0;
            dummy_request_count = 0;
            logical_consume_count = 0;
            decoder_input_count = 0;
            decoder_state_commit_count = 0;
            physical_cursor_commit_count = 0;
            logical_cursor_commit_count = 0;
            physical_contribution_count = 0;
            logical_contribution_count = 0;
            audible_nonzero_contribution_count = 0;
            aggregate_commit_count = 0;
            standard_acc_insert_count = 0;
            final_publish_count = 0;
            raw_owner_unknown_count = 0;
            capture_owner_mismatch_count = 0;
            logical_owner_unknown_count = 0;
            logical_decoder_owner_mismatch_count = 0;
            cursor_cross_update_count = 0;
            rom_contamination_count = 0;
            contribution_owner_mismatch_count = 0;
            clear_decoder_gate_count = 0;
            clear_state_commit_count = 0;
            clear_logical_cursor_count = 0;
            clear_physical_contribution_count = 0;
            clear_logical_contribution_count = 0;
            dummy_audible_effect_count = 0;
            class_c_violation_count = 0;
            accepted_state_mismatch_count = 0;
            accepted_contribution_mismatch_count = 0;
            tag_age_error_count = 0;
            clear_sequence_count = 0;
            track_clear_sequence = 1'b0;
            for (voice = 0; voice < 6; voice = voice + 1) begin
                voice_raw_count[voice] = 0;
                voice_dummy_raw_count[voice] = 0;
                voice_capture_count[voice] = 0;
                voice_decoder_input_count[voice] = 0;
                voice_fetch_count[voice] = 0;
                voice_decode_count[voice] = 0;
                voice_physical_cursor_count[voice] = 0;
                voice_logical_cursor_count[voice] = 0;
                voice_gain_count[voice] = 0;
                voice_physical_contribution_count[voice] = 0;
                voice_logical_contribution_count[voice] = 0;
                voice_audible_nonzero_count[voice] = 0;
                voice_unique_count[voice] = 0;
                voice_repeated_count[voice] = 0;
                voice_high_count[voice] = 0;
                voice_low_count[voice] = 0;
                voice_out_of_range_count[voice] = 0;
                voice_owner_mismatch_count[voice] = 0;
                voice_cross_owner_count[voice] = 0;
                voice_dummy_audible_count[voice] = 0;
                voice_first_fetch_cycle[voice] = -1;
                voice_last_fetch_cycle[voice] = -1;
                voice_first_address[voice] = -1;
                voice_last_address[voice] = -1;
                voice_last_nibble[voice] = -1;
                voice_peak[voice] = 0;
                voice_seen_fetch[voice] = 1'b0;
                voice_raw_hash[voice] = FNV_OFFSET;
                voice_dummy_hash[voice] = FNV_OFFSET;
                voice_fetch_hash[voice] = FNV_OFFSET;
                voice_address_hash[voice] = FNV_OFFSET;
                voice_rom_hash[voice] = FNV_OFFSET;
                voice_decode_hash[voice] = FNV_OFFSET;
                voice_cursor_hash[voice] = FNV_OFFSET;
                voice_gain_hash[voice] = FNV_OFFSET;
                voice_left_hash[voice] = FNV_OFFSET;
                voice_right_hash[voice] = FNV_OFFSET;
            end
            for (tag_index = 0; tag_index <= TAG_DEPTH;
                 tag_index = tag_index + 1) begin
                tag_valid[tag_index] = 1'b0;
                tag_clr[tag_index] = 1'b0;
                tag_owner[tag_index] = -1;
                tag_address[tag_index] = 0;
                tag_nibble[tag_index] = 0;
                tag_data[tag_index] = 4'd0;
                tag_cycle[tag_index] = -1;
            end
            measure_active = 1'b1;
        end
    endtask

    task automatic wait_measurement_samples(input integer goal);
        integer timeout;
        begin
            timeout = 0;
            while (measure_samples < goal && timeout < goal * 200) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (measure_samples < goal)
                fail("public-sample measurement timeout");
        end
    endtask

    task automatic measurement_end;
        begin
            @(negedge clk);
            measure_active = 1'b0;
            stable_mask_check = 1'b0;
        end
    endtask

    task automatic save_control;
        integer voice;
        begin
            for (voice = 0; voice < 6; voice = voice + 1) begin
                control_raw_count[voice] = voice_raw_count[voice];
                control_dummy_raw_count[voice] =
                    voice_dummy_raw_count[voice];
                control_fetch_count[voice] = voice_fetch_count[voice];
                control_decode_count[voice] = voice_decode_count[voice];
                control_physical_cursor_count[voice] =
                    voice_physical_cursor_count[voice];
                control_logical_contribution_count[voice] =
                    voice_logical_contribution_count[voice];
                control_raw_hash[voice] = voice_raw_hash[voice];
                control_dummy_hash[voice] = voice_dummy_hash[voice];
                control_fetch_hash[voice] = voice_fetch_hash[voice];
                control_address_hash[voice] = voice_address_hash[voice];
                control_rom_hash[voice] = voice_rom_hash[voice];
                control_decode_hash[voice] = voice_decode_hash[voice];
                control_cursor_hash[voice] = voice_cursor_hash[voice];
                control_gain_hash[voice] = voice_gain_hash[voice];
                control_left_hash[voice] = voice_left_hash[voice];
                control_right_hash[voice] = voice_right_hash[voice];
            end
        end
    endtask

    task automatic compare_voice_to_control(input integer voice);
        begin
            if (voice_raw_count[voice] != control_raw_count[voice] ||
                voice_dummy_raw_count[voice] !=
                    control_dummy_raw_count[voice] ||
                voice_fetch_count[voice] != control_fetch_count[voice] ||
                voice_decode_count[voice] != control_decode_count[voice] ||
                voice_physical_cursor_count[voice] !=
                    control_physical_cursor_count[voice] ||
                voice_logical_contribution_count[voice] !=
                    control_logical_contribution_count[voice] ||
                voice_raw_hash[voice] != control_raw_hash[voice] ||
                voice_dummy_hash[voice] != control_dummy_hash[voice] ||
                voice_fetch_hash[voice] != control_fetch_hash[voice] ||
                voice_address_hash[voice] != control_address_hash[voice] ||
                voice_rom_hash[voice] != control_rom_hash[voice] ||
                voice_decode_hash[voice] != control_decode_hash[voice] ||
                voice_cursor_hash[voice] != control_cursor_hash[voice] ||
                voice_gain_hash[voice] != control_gain_hash[voice] ||
                voice_left_hash[voice] != control_left_hash[voice] ||
                voice_right_hash[voice] != control_right_hash[voice])
                fail("surviving voice differs from single-voice control");
        end
    endtask

    task automatic wait_lane_idle;
        integer consecutive;
        integer timeout;
        begin
            consecutive = 0;
            timeout = 0;
            while (consecutive < 16 && timeout < 512) begin
                @(posedge snd_sample);
                #1;
                timeout = timeout + 1;
                if (active_mask == 0 && adpcma_l == 0 && adpcma_r == 0 &&
                    snd_left == 0 && snd_right == 0)
                    consecutive = consecutive + 1;
                else
                    consecutive = 0;
            end
            if (consecutive < 16)
                fail("ADPCM-A pipeline did not drain");
        end
    endtask

    task automatic capture_zero_512;
        integer index;
        integer fetch_before;
        integer zero_goal;
        begin
            stop_hash = FNV_OFFSET;
            fetch_before = global_fetch_count;
            zero_goal = quick_mode ? 16 : 512;
            for (index = 0; index < zero_goal; index = index + 1) begin
                @(posedge snd_sample);
                #1;
                stop_hash = hash_stereo(stop_hash, snd_left, snd_right);
                if ($isunknown(snd_left) || $isunknown(snd_right) ||
                    snd_left != 0 || snd_right != 0 ||
                    adpcma_l != 0 || adpcma_r != 0)
                    fail("post-stop sample is not zero");
            end
            if (global_fetch_count != fetch_before)
                fail("fetch observed in post-stop zero window");
            if (!quick_mode && stop_hash != 64'h28c31cf8df2ec325)
                fail("post-stop zero hash changed");
        end
    endtask

    task automatic stop_all_and_verify;
        begin
            stable_mask_check = 1'b0;
            write_adpcma(8'h00, 8'hbf);
            wait_mask(6'h00);
            measurement_end();
            wait_lane_idle();
            capture_zero_512();
        end
    endtask

    task automatic prepare_common;
        integer voice;
        integer zero_index;
        begin
            for (voice = 0; voice < 6; voice = voice + 1) begin
                cfg_start[voice] = 0;
                cfg_end[voice] = 0;
                cfg_level[voice] = 0;
            end
            for (zero_index = 0; zero_index < 12;
                 zero_index = zero_index + 1)
                command_seen[zero_index] = 0;

            wait_clocks(4);
            @(negedge clk);
            session_start = 1'b0;
            wait_clocks(12);
            @(negedge clk);
            cen = 1'b1;
            wait_clocks(64);
            @(negedge clk);
            cen = 1'b0;
            #1;
            if (reset_cen_count !== 3'd6 || !reset_cen_valid)
                fail("six-CEN reset contract mismatch");
            rst = 1'b0;
            cen = 1'b1;
            zero_index = 0;
            while (warmup_ready !== 1'b1 && zero_index < 20000) begin
                @(posedge clk);
                zero_index = zero_index + 1;
            end
            if (warmup_ready !== 1'b1) begin
                $display("FAIL WARMUP_TIMEOUT internal_sample=%b count=%0d reset_count=%0d reset_valid=%b",
                         internal_snd_sample, warmup_count,
                         reset_cen_count, reset_cen_valid);
                fail("warm-up ready timeout");
            end
            zero_index = 0;
            while (public_sample_count < 1 && zero_index < 20000) begin
                @(posedge clk);
                zero_index = zero_index + 1;
            end
            if (public_sample_count < 1)
                fail("first public sample timeout");
            for (zero_index = 0; zero_index < 16;
                 zero_index = zero_index + 1) begin
                @(posedge snd_sample);
                #1;
                if (snd_left != 0 || snd_right != 0)
                    fail("startup silence mismatch");
            end

            keyoff_all_fm();
            bus.jt10_write_port0(8'h22, 8'h00);
            bus.jt10_write_port0(8'h27, 8'h00);
            bus.jt10_write_port0(8'h2b, 8'h00);
            write_adpcma(8'h00, 8'hbf);
            wait_mask(6'h00);
            bus.jt10_write_port0(8'h10, 8'h01);
            bus.jt10_write_port0(8'h10, 8'h00);
            bus.jt10_write_port0(8'h08, 8'h00);
            bus.jt10_write_port0(8'h09, 8'h00);
            bus.jt10_write_port0(8'h0a, 8'h00);
            bus.jt10_write_port0(8'h06, 8'h00);
            bus.jt10_write_port0(8'h07, 8'h3f);
            for (zero_index = 0; zero_index < 16;
                 zero_index = zero_index + 1) begin
                @(posedge snd_sample);
                #1;
                if (snd_left != 0 || snd_right != 0 ||
                    psg_A != 0 || psg_B != 0 || psg_C != 0 ||
                    psg_snd != 0)
                    fail("explicit common silence mismatch");
            end
            audit_active = 1'b1;
        end
    endtask

    task automatic command_matrix;
        begin
            align_command_phase();
            issue_keyon(6'h03);
            issue_keyoff(6'h3f, 6'h00);
            issue_keyon(6'h07);
            issue_keyoff(6'h3f, 6'h00);
            issue_keyon(6'h0f);
            issue_keyoff(6'h3f, 6'h00);
            issue_keyon(6'h3f);
            issue_keyoff(6'h01, 6'h3e);
            issue_keyoff(6'h02, 6'h3c);
            issue_keyoff(6'h04, 6'h38);
            issue_keyoff(6'h08, 6'h30);
            issue_keyoff(6'h10, 6'h20);
            issue_keyoff(6'h20, 6'h00);
            write_adpcma(8'h00, 8'h40);
            wait_mask(6'h00);
            write_adpcma(8'h00, 8'hc0);
            wait_mask(6'h00);
            wait_lane_idle();
            capture_zero_512();
        end
    endtask

    task automatic program_standard(
        input [5:0] mask,
        input integer unique_starts,
        input [7:0] level
    );
        integer voice;
        integer start_page;
        begin
            write_adpcma(8'h01, 8'h3f);
            for (voice = 0; voice < 6; voice = voice + 1) begin
                start_page = unique_starts ? voice : 0;
                program_voice(
                    voice, start_page, start_page + 15,
                    mask[voice] ? level : 8'h00
                );
            end
        end
    endtask

    task automatic begin_keyon_measurement(
        input [5:0] mask,
        input integer samples
    );
        begin
            select_mask_phase(mask);
            align_command_phase();
            measurement_begin(mask, samples);
            issue_keyon(mask);
        end
    endtask

    task automatic validate_basic_measurement;
        integer voice;
        integer minimum_count;
        integer maximum_count;
        begin
            if (arithmetic_mismatch_count != 0 ||
                ownership_mismatch_count != 0 ||
                owner_unknown_count != 0 ||
                owner_inactive_count != 0 ||
                capture_mismatch_count != 0 ||
                range_error_count != 0 ||
                progression_error_count != 0 ||
                pan_leak_count != 0 || x_count != 0 ||
                raw_owner_unknown_count != 0 ||
                capture_owner_mismatch_count != 0 ||
                logical_owner_unknown_count != 0 ||
                logical_decoder_owner_mismatch_count != 0 ||
                cursor_cross_update_count != 0 ||
                rom_contamination_count != 0 ||
                contribution_owner_mismatch_count != 0 ||
                accepted_state_mismatch_count != 0 ||
                accepted_contribution_mismatch_count != 0 ||
                tag_age_error_count != 0 ||
                class_c_violation_count != 0 ||
                clear_state_commit_count != 0 ||
                clear_logical_cursor_count != 0 ||
                clear_logical_contribution_count != 0 ||
                dummy_audible_effect_count != 0)
                fail("measurement invariant mismatch");
            minimum_count = 32'h7fffffff;
            maximum_count = 0;
            for (voice = 0; voice < 6; voice = voice + 1) begin
                if (measure_target_mask[voice]) begin
                    if (voice_fetch_count[voice] == 0)
                        starvation_count = starvation_count + 1;
                    if (voice_capture_count[voice] !=
                            voice_raw_count[voice] ||
                        voice_decoder_input_count[voice] !=
                            voice_raw_count[voice] ||
                        voice_raw_count[voice] <
                            voice_fetch_count[voice] ||
                        voice_logical_cursor_count[voice] !=
                            voice_fetch_count[voice] ||
                        voice_unique_count[voice] !=
                            voice_fetch_count[voice] ||
                        voice_repeated_count[voice] != 0 ||
                        voice_high_count[voice] +
                            voice_low_count[voice] !=
                            voice_fetch_count[voice] ||
                        voice_high_count[voice] -
                            voice_low_count[voice] > 1 ||
                        voice_low_count[voice] -
                            voice_high_count[voice] > 1 ||
                        voice_out_of_range_count[voice] != 0 ||
                        voice_owner_mismatch_count[voice] != 0 ||
                        voice_cross_owner_count[voice] != 0 ||
                        voice_dummy_audible_count[voice] != 0)
                        fail("per-voice event taxonomy mismatch");
                    if (voice_fetch_count[voice] < minimum_count)
                        minimum_count = voice_fetch_count[voice];
                    if (voice_fetch_count[voice] > maximum_count)
                        maximum_count = voice_fetch_count[voice];
                end else if (voice_fetch_count[voice] != 0 ||
                             voice_raw_count[voice] != 0) begin
                    ownership_mismatch_count =
                        ownership_mismatch_count + 1;
                end
            end
            if (starvation_count != 0 || ownership_mismatch_count != 0)
                fail("target/idle voice ownership mismatch");
            if (measure_target_mask == 6'h3f &&
                stable_expected_mask == 6'h3f &&
                active_mask == 6'h3f &&
                maximum_count - minimum_count > 1)
                fail("six-voice owner counts are not balanced");
        end
    endtask

    task automatic run_scenario_a;
        integer voice;
        integer goal;
        begin
            goal = quick_mode ? 64 : 4096;
            command_matrix();
            program_standard(6'h03, 0, SAFE_STEREO);
            begin_keyon_measurement(6'h03, goal);
            wait_measurement_samples(goal);
            validate_basic_measurement();
            for (voice = 2; voice < 6; voice = voice + 1)
                if (voice_fetch_count[voice] != 0)
                    fail("Scenario A non-target voice fetched");
            stop_all_and_verify();
        end
    endtask

    task automatic run_scenario_b;
        begin
            program_standard(6'h03, 1, SAFE_STEREO);
            program_voice(0, 0, 15, SAFE_LEFT);
            program_voice(1, 1, 16, SAFE_RIGHT);
            begin_keyon_measurement(6'h03, 4096);
            wait_measurement_samples(4096);
            validate_basic_measurement();
            if (voice_right_hash[0] != 64'h28c31cf8df2ec325 &&
                voice_gain_count[0] == 512)
                fail("Scenario B voice 0 right leak");
            stop_all_and_verify();
        end
    endtask

    task automatic run_scenario_c;
        integer voice0_fetch_at_stop;
        integer voice1_fetch_at_stop;
        begin
            program_standard(6'h02, 1, SAFE_STEREO);
            begin_keyon_measurement(6'h02, 4096);
            wait_measurement_samples(4096);
            measurement_end();
            save_control();
            stop_all_and_verify();

            program_standard(6'h03, 1, SAFE_STEREO);
            begin_keyon_measurement(6'h03, 4096);
            wait_measurement_samples(2048);
            voice0_fetch_at_stop = voice_fetch_count[0];
            voice1_fetch_at_stop = voice_fetch_count[1];
            issue_keyoff(6'h01, 6'h02);
            wait_measurement_samples(4096);
            if (voice_fetch_count[0] - voice0_fetch_at_stop > 2)
                fail("Scenario C stopped voice kept fetching");
            if (voice_fetch_count[1] <= voice1_fetch_at_stop)
                fail("Scenario C surviving voice stopped");
            compare_voice_to_control(1);
            validate_basic_measurement();
            stop_all_and_verify();
        end
    endtask

    task automatic wait_all_natural_end(input integer timeout_samples);
        integer start_samples;
        begin
            start_samples = public_sample_count;
            while (active_mask != 0 &&
                   public_sample_count - start_samples < timeout_samples)
                @(posedge clk);
            if (active_mask != 0)
                fail("natural-end timeout");
        end
    endtask

    task automatic run_scenario_d;
        begin
            write_adpcma(8'h01, 8'h3f);
            program_voice(0, 0, 0, 8'h00);
            program_voice(1, 1, 2, SAFE_RIGHT);
            program_voice(2, 0, 0, 8'h00);
            program_voice(3, 0, 0, 8'h00);
            program_voice(4, 0, 0, 8'h00);
            program_voice(5, 0, 0, 8'h00);
            begin_keyon_measurement(6'h02, 4096);
            wait_all_natural_end(8192);
            measurement_end();
            save_control();
            stop_all_and_verify();

            write_adpcma(8'h01, 8'h3f);
            program_voice(0, 0, 0, SAFE_LEFT);
            program_voice(1, 1, 2, SAFE_RIGHT);
            begin_keyon_measurement(6'h03, 4096);
            track_clear_sequence = 1'b1;
            previous_tracked_mask = 6'h03;
            wait_all_natural_end(8192);
            measurement_end();
            if (voice_fetch_count[0] != 512 ||
                voice_fetch_count[1] != 1024)
                fail("Scenario D natural nibble count mismatch");
            compare_voice_to_control(1);
            validate_basic_measurement();
            wait_lane_idle();
            capture_zero_512();
        end
    endtask

    task automatic run_scenario_e;
        integer goal;
        begin
            goal = quick_mode ? 64 : 4096;
            program_standard(6'h07, 1, SAFE_STEREO);
            begin_keyon_measurement(6'h07, goal);
            wait_measurement_samples(goal);
            validate_basic_measurement();
            stop_all_and_verify();
        end
    endtask

    task automatic run_scenario_f;
        begin
            program_standard(6'h0f, 1, SAFE_STEREO);
            program_voice(0, 0, 15, SAFE_LEFT);
            program_voice(1, 1, 16, SAFE_RIGHT);
            begin_keyon_measurement(6'h0f, 4096);
            wait_measurement_samples(4096);
            validate_basic_measurement();
            stop_all_and_verify();
        end
    endtask

    task automatic run_scenario_g;
        integer goal;
        integer voice;
        begin
            goal = quick_mode ? 128 : 8192;
            program_standard(6'h3f, 1, SAFE_STEREO);
            begin_keyon_measurement(6'h3f, goal);
            wait_measurement_samples(goal);
            if (aggregate_saturation_count != 0 ||
                aggregate_wrap_count != 0 || final_wrap_count != 0 ||
                final_saturation_count != 0)
                fail("Scenario G safe-level arithmetic boundary reached");
            if (duplicate_slot_count != 0 || missed_slot_count != 0)
                fail("Scenario G owner round mismatch");
            validate_basic_measurement();
            if (dummy_request_count != 1 ||
                raw_request_count != logical_consume_count + 1)
                fail("Scenario G Class C raw/logical count mismatch");
            for (voice = 0; voice < 6; voice = voice + 1)
                if (voice_first_address[voice] != voice * 256)
                    fail("Scenario G first logical address mismatch");
            stop_all_and_verify();
        end
    endtask

    task automatic run_scenario_h;
        begin
            program_standard(6'h3f, 1, SAFE_STEREO);
            program_voice(0, 0, 15, SAFE_LEFT);
            program_voice(1, 1, 16, SAFE_RIGHT);
            program_voice(2, 2, 17, SAFE_STEREO);
            program_voice(3, 3, 18, SAFE_LEFT);
            program_voice(4, 4, 19, SAFE_RIGHT);
            program_voice(5, 5, 20, SAFE_STEREO);
            begin_keyon_measurement(6'h3f, 4096);
            wait_measurement_samples(4096);
            validate_basic_measurement();
            stop_all_and_verify();
        end
    endtask

    task automatic run_scenario_i;
        begin
            program_standard(6'h3f, 1, PRIMARY_STEREO);
            begin_keyon_measurement(6'h3f, 8192);
            wait_measurement_samples(8192);
            validate_basic_measurement();
            stop_all_and_verify();
        end
    endtask

    task automatic run_scenario_j;
        integer before_count [0:5];
        integer voice;
        begin
            program_standard(6'h3f, 1, SAFE_STEREO);
            begin_keyon_measurement(6'h3f, 4096);
            wait_measurement_samples(1024);
            for (voice = 0; voice < 6; voice = voice + 1)
                before_count[voice] = voice_fetch_count[voice];
            issue_keyoff(6'h01, 6'h3e);
            wait_measurement_samples(2048);
            if (voice_fetch_count[0] - before_count[0] > 2)
                fail("Scenario J voice 0 did not stop independently");
            issue_keyoff(6'h04, 6'h3a);
            wait_measurement_samples(3072);
            issue_keyoff(6'h10, 6'h2a);
            wait_measurement_samples(4096);
            if (active_mask != 6'h2a)
                fail("Scenario J surviving mask is not 1/3/5");
            validate_basic_measurement();
            stop_all_and_verify();
        end
    endtask

    task automatic run_scenario_k;
        integer voice;
        integer expected_counts [0:5];
        begin
            write_adpcma(8'h01, 8'h3f);
            program_voice(0, 0, 0, SAFE_STEREO);
            program_voice(1, 1, 2, SAFE_STEREO);
            program_voice(2, 3, 5, SAFE_STEREO);
            program_voice(3, 6, 9, SAFE_STEREO);
            program_voice(4, 10, 14, SAFE_STEREO);
            program_voice(5, 15, 20, SAFE_STEREO);
            expected_counts[0] = 512;
            expected_counts[1] = 1024;
            expected_counts[2] = 1536;
            expected_counts[3] = 2048;
            expected_counts[4] = 2560;
            expected_counts[5] = 3072;
            select_mask_phase(6'h3f);
            align_command_phase();
            measurement_begin(6'h3f, 1000000);
            issue_keyon(6'h3f);
            track_clear_sequence = 1'b1;
            previous_tracked_mask = 6'h3f;
            wait_all_natural_end(16384);
            measurement_end();
            for (voice = 0; voice < 6; voice = voice + 1)
                if (voice_fetch_count[voice] != expected_counts[voice] ||
                    voice_unique_count[voice] != expected_counts[voice] ||
                    voice_repeated_count[voice] != 0 ||
                    voice_high_count[voice] != expected_counts[voice] / 2 ||
                    voice_low_count[voice] != expected_counts[voice] / 2 ||
                    voice_last_address[voice] !=
                        (cfg_end[voice] + 1) * 256 - 1 ||
                    voice_last_nibble[voice] != 1)
                    fail("Scenario K natural nibble count mismatch");
            if (dummy_request_count != 1 ||
                voice_dummy_raw_count[5] != 1)
                fail("Scenario K Class C dummy request mismatch");
            if (clear_sequence_count != 6 ||
                clear_sequence[0] != 6'h3e ||
                clear_sequence[1] != 6'h3c ||
                clear_sequence[2] != 6'h38 ||
                clear_sequence[3] != 6'h30 ||
                clear_sequence[4] != 6'h20 ||
                clear_sequence[5] != 6'h00)
                fail("Scenario K active-mask clear order mismatch");
            validate_basic_measurement();
            wait_lane_idle();
            capture_zero_512();
        end
    endtask

    task automatic run_scenario_l;
        integer voice;
        integer first_relative [0:5];
        logic [63:0] saved_active;
        logic [63:0] saved_raw_owner;
        logic [63:0] saved_raw_request;
        logic [63:0] saved_dummy_request;
        logic [63:0] saved_owner;
        logic [63:0] saved_logical;
        logic [63:0] saved_cursor;
        logic [63:0] saved_contribution;
        logic [63:0] saved_aggregate_l;
        logic [63:0] saved_aggregate_r;
        logic [63:0] saved_final_l;
        logic [63:0] saved_final_r;
        logic [63:0] saved_stereo;
        begin
            program_standard(6'h3f, 1, SAFE_STEREO);
            begin_keyon_measurement(6'h3f, 8192);
            wait_measurement_samples(8192);
            validate_basic_measurement();
            save_control();
            saved_active = active_mask_hash;
            saved_raw_owner = raw_owner_hash;
            saved_raw_request = raw_request_hash;
            saved_dummy_request = dummy_request_hash;
            saved_owner = owner_hash;
            saved_logical = aggregate_fetch_hash;
            saved_cursor = physical_cursor_hash;
            saved_contribution = logical_contribution_hash;
            saved_aggregate_l = aggregate_l_hash;
            saved_aggregate_r = aggregate_r_hash;
            saved_final_l = final_l_hash;
            saved_final_r = final_r_hash;
            saved_stereo = stereo_hash;
            for (voice = 0; voice < 6; voice = voice + 1)
                first_relative[voice] =
                    voice_first_fetch_cycle[voice] - measure_start_cycle;
            stop_all_and_verify();

            select_mask_phase(6'h3f);
            align_command_phase();
            measurement_begin(6'h3f, 8192);
            issue_keyon(6'h3f);
            wait_measurement_samples(8192);
            validate_basic_measurement();
            for (voice = 0; voice < 6; voice = voice + 1) begin
                compare_voice_to_control(voice);
                if (voice_first_fetch_cycle[voice] -
                    measure_start_cycle != first_relative[voice])
                    fail("Scenario L first-fetch landmark changed");
            end
            if (active_mask_hash != saved_active ||
                raw_owner_hash != saved_raw_owner ||
                raw_request_hash != saved_raw_request ||
                dummy_request_hash != saved_dummy_request ||
                owner_hash != saved_owner ||
                aggregate_fetch_hash != saved_logical ||
                physical_cursor_hash != saved_cursor ||
                logical_contribution_hash != saved_contribution ||
                aggregate_l_hash != saved_aggregate_l ||
                aggregate_r_hash != saved_aggregate_r ||
                final_l_hash != saved_final_l ||
                final_r_hash != saved_final_r ||
                stereo_hash != saved_stereo)
                fail("Scenario L retrigger hash mismatch");
            stop_all_and_verify();
        end
    endtask

    always @(posedge clk) begin : monitor
        integer voice;
        integer owner;
        integer state_owner;
        integer cursor_owner;
        integer tag_index;
        integer logical_address;
        integer expected_address;
        integer expected_nibble;
        integer magnitude;
        integer sample_value;
        integer sign_value;
        integer math_sum;
        reg [3:0] expected_capture;
        reg [3:0] selected_nibble;
        reg signed [15:0] left_contribution;
        reg signed [15:0] right_contribution;

        system_cycle = system_cycle + 1;
        pre_clk_en = clk_en;
        pre_clk_en_666 = clk_en_666;
        pre_valid_fetch = clk_en_666 && !adpcma_roe_n && adpcma_decon;
        pre_decoder_state_commit = clk_en_666 && decoder_state_commit;
        pre_physical_cursor_commit =
            clk_en_666 && physical_cursor_commit;
        pre_physical_cursor_address =
            dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_cnt.addr6;
        pre_cur_ch = adpcma_cur_ch;
        pre_en_ch = adpcma_en_ch;
        pre_active_mask = active_mask;
        pre_match = adpcma_match;
        pre_fetch_address = adpcma_addr;
        pre_fetch_bank = adpcma_bank;
        pre_fetch_nibble = nibble_select;
        pre_fetch_clr = adpcma_clr_dec;
        pre_logical_consume = pre_valid_fetch && !pre_fetch_clr;
        pre_fetch_data = adpcma_data;
        pre_gain_pcm = gain_pcm;
        pre_gain_pan = gain_pan;
        pre_public_rise = 1'b0;
        pre_internal_rise = 1'b0;

        if (track_clear_sequence && active_mask != previous_tracked_mask) begin
            if (clear_sequence_count < 8) begin
                clear_sequence[clear_sequence_count] = active_mask;
                clear_sequence_count = clear_sequence_count + 1;
            end
            previous_tracked_mask = active_mask;
        end

        #1;

        if (audit_active && pre_clk_en_666 &&
            !$isunknown({adpcma_l, adpcma_r,
                         ref_adpcma_l, ref_adpcma_r})) begin
            arithmetic_compare_count = arithmetic_compare_count + 2;
            if (adpcma_l !== ref_adpcma_l) begin
                arithmetic_mismatch_count =
                    arithmetic_mismatch_count + 1;
                $display("FAIL ARITH_AGG_L cycle=%0d expected=%0d actual=%0d",
                         system_cycle, ref_adpcma_l, adpcma_l);
            end
            if (adpcma_r !== ref_adpcma_r) begin
                arithmetic_mismatch_count =
                    arithmetic_mismatch_count + 1;
                $display("FAIL ARITH_AGG_R cycle=%0d expected=%0d actual=%0d",
                         system_cycle, ref_adpcma_r, adpcma_r);
            end
        end
        if (audit_active && pre_clk_en) begin
            arithmetic_compare_count = arithmetic_compare_count + 6;
            if (actual_acc_input_l !== ref_final_input_l ||
                actual_acc_input_r !== ref_final_input_r ||
                actual_acc_enable_l !== ref_final_enable_l ||
                actual_acc_enable_r !== ref_final_enable_r ||
                internal_snd_left !== ref_final_l ||
                internal_snd_right !== ref_final_r) begin
                arithmetic_mismatch_count =
                    arithmetic_mismatch_count + 1;
                $display("FAIL ARITH_FINAL cycle=%0d in=%0d/%0d ref=%0d/%0d out=%0d/%0d refout=%0d/%0d",
                         system_cycle, actual_acc_input_l,
                         actual_acc_input_r, ref_final_input_l,
                         ref_final_input_r, internal_snd_left,
                         internal_snd_right, ref_final_l, ref_final_r);
            end
        end

        if (measure_active && pre_clk_en_666) begin
            active_mask_hash = hash_byte(active_mask_hash,
                                         {2'd0, pre_active_mask});
            if (pre_cur_ch[0])
                aggregate_commit_count = aggregate_commit_count + 1;
            if (stable_mask_check &&
                (pre_active_mask & ~stable_expected_mask) != 0)
                active_mask_errors = active_mask_errors + 1;

            if (pre_match) begin
                if ($isunknown(pre_cur_ch) ||
                    $isunknown(pre_match) ||
                    $isunknown(pre_gain_pcm) ||
                    $isunknown(pre_gain_pan))
                    x_count = x_count + 1;
                owner = onehot_index(pre_cur_ch);
                if (owner < 0) begin
                    ownership_mismatch_count =
                        ownership_mismatch_count + 1;
                end else begin
                    physical_contribution_count =
                        physical_contribution_count + 1;
                    voice_physical_contribution_count[owner] =
                        voice_physical_contribution_count[owner] + 1;
                end
            end

            if (dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_gain.match2 &&
                dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_gain.pcm2_mul[8:0]
                    != 0)
                gain_truncation_count = gain_truncation_count + 1;
            if (adpcma_en_ch[0] && adpcma_cur_ch[0] &&
                dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_acc_left.step_full[6:0]
                    != 0)
                interpolation_truncation_count =
                    interpolation_truncation_count + 1;
            if (ref_adpcma_overflow_l)
                aggregate_saturation_count =
                    aggregate_saturation_count + 1;
            if (ref_adpcma_overflow_r)
                aggregate_saturation_count =
                    aggregate_saturation_count + 1;
        end

        if (measure_active && pre_clk_en &&
            final_cur_op == 0 && final_cur_ch == 0) begin
            standard_acc_insert_count = standard_acc_insert_count + 1;
            if (ref_final_wrap_l)
                final_wrap_count = final_wrap_count + 1;
            if (ref_final_wrap_r)
                final_wrap_count = final_wrap_count + 1;
        end
        if (measure_active && pre_clk_en) begin
            if (final_zero)
                final_publish_count = final_publish_count + 1;
            if (ref_final_overflow_l)
                final_saturation_count = final_saturation_count + 1;
            if (ref_final_overflow_r)
                final_saturation_count = final_saturation_count + 1;
        end

        selected_nibble = pre_fetch_nibble ?
            pre_fetch_data[3:0] : pre_fetch_data[7:4];
        logical_address = {pre_fetch_bank, pre_fetch_address};

        if (measure_active && pre_valid_fetch) begin
            global_fetch_count = global_fetch_count + 1;
            raw_request_count = raw_request_count + 1;
            decoder_input_count = decoder_input_count + 1;
            if (last_fetch_cycle_global == system_cycle)
                owner_duplicate_cycle_count =
                    owner_duplicate_cycle_count + 1;
            last_fetch_cycle_global = system_cycle;
            owner = onehot_index(pre_cur_ch);
            if ($isunknown(pre_cur_ch) ||
                $isunknown(pre_active_mask) ||
                $isunknown(pre_fetch_clr) ||
                $isunknown(pre_fetch_bank) ||
                $isunknown(pre_fetch_address) ||
                $isunknown(pre_fetch_nibble) ||
                $isunknown(pre_fetch_data) ||
                $isunknown(captured_nibble))
                x_count = x_count + 1;
            if (owner < 0) begin
                owner_unknown_count = owner_unknown_count + 1;
                raw_owner_unknown_count = raw_owner_unknown_count + 1;
                capture_owner_mismatch_count =
                    capture_owner_mismatch_count + 1;
            end else begin
                voice_raw_count[owner] = voice_raw_count[owner] + 1;
                voice_capture_count[owner] =
                    voice_capture_count[owner] + 1;
                voice_decoder_input_count[owner] =
                    voice_decoder_input_count[owner] + 1;
                if (pre_fetch_clr) begin
                    dummy_request_count = dummy_request_count + 1;
                    voice_dummy_raw_count[owner] =
                        voice_dummy_raw_count[owner] + 1;
                end
                if (!pre_active_mask[owner])
                    owner_inactive_count = owner_inactive_count + 1;
                if (!measure_target_mask[owner]) begin
                    ownership_mismatch_count =
                        ownership_mismatch_count + 1;
                    voice_owner_mismatch_count[owner] =
                        voice_owner_mismatch_count[owner] + 1;
                end
                expected_capture = selected_nibble;
                if (captured_nibble !== expected_capture) begin
                    capture_mismatch_count =
                        capture_mismatch_count + 1;
                    capture_owner_mismatch_count =
                        capture_owner_mismatch_count + 1;
                end
                if (pre_fetch_data !==
                    expected_rom(logical_address[23:0])) begin
                    capture_mismatch_count =
                        capture_mismatch_count + 1;
                    rom_contamination_count =
                        rom_contamination_count + 1;
                end
                voice_raw_hash[owner] =
                    hash_u16(voice_raw_hash[owner],
                             system_cycle - measure_start_cycle);
                voice_raw_hash[owner] =
                    hash_u24(voice_raw_hash[owner],
                             logical_address[23:0]);
                voice_raw_hash[owner] =
                    hash_byte(voice_raw_hash[owner],
                              {6'd0, pre_fetch_nibble, pre_fetch_clr});
                voice_raw_hash[owner] =
                    hash_byte(voice_raw_hash[owner], selected_nibble);
                raw_owner_hash =
                    hash_byte(raw_owner_hash, {5'd0, owner[2:0]});
                raw_request_hash =
                    hash_byte(raw_request_hash, {5'd0, owner[2:0]});
                raw_request_hash =
                    hash_u24(raw_request_hash, logical_address[23:0]);
                raw_request_hash =
                    hash_byte(raw_request_hash,
                              {6'd0, pre_fetch_nibble, pre_fetch_clr});
                if (pre_fetch_clr) begin
                    voice_dummy_hash[owner] =
                        hash_u24(voice_dummy_hash[owner],
                                 logical_address[23:0]);
                    voice_dummy_hash[owner] =
                        hash_byte(voice_dummy_hash[owner],
                                  {7'd0, pre_fetch_nibble});
                    voice_dummy_hash[owner] =
                        hash_byte(voice_dummy_hash[owner], selected_nibble);
                    dummy_request_hash =
                        hash_byte(dummy_request_hash,
                                  {5'd0, owner[2:0]});
                    dummy_request_hash =
                        hash_u24(dummy_request_hash,
                                 logical_address[23:0]);
                    dummy_request_hash =
                        hash_byte(dummy_request_hash,
                                  {7'd0, pre_fetch_nibble});
                end
            end
        end

        if (measure_active && pre_logical_consume) begin
            logical_consume_count = logical_consume_count + 1;
            logical_cursor_commit_count =
                logical_cursor_commit_count + 1;
            owner = onehot_index(pre_cur_ch);
            if (owner < 0) begin
                logical_owner_unknown_count =
                    logical_owner_unknown_count + 1;
            end else begin
                if (!pre_active_mask[owner] ||
                    !measure_target_mask[owner]) begin
                    ownership_mismatch_count =
                        ownership_mismatch_count + 1;
                    voice_owner_mismatch_count[owner] =
                        voice_owner_mismatch_count[owner] + 1;
                end
                if (logical_address < cfg_start[owner] * 256 ||
                    logical_address > (cfg_end[owner] + 1) * 256 - 1) begin
                    range_error_count = range_error_count + 1;
                    voice_out_of_range_count[owner] =
                        voice_out_of_range_count[owner] + 1;
                end

                if (!voice_seen_fetch[owner]) begin
                    expected_address = cfg_start[owner] * 256;
                    expected_nibble = 0;
                    voice_first_fetch_cycle[owner] = system_cycle;
                    voice_first_address[owner] = logical_address;
                    voice_seen_fetch[owner] = 1'b1;
                    voice_unique_count[owner] = 1;
                end else begin
                    if (voice_last_nibble[owner] == 0) begin
                        expected_address = voice_last_address[owner];
                        expected_nibble = 1;
                    end else begin
                        expected_address = voice_last_address[owner] + 1;
                        expected_nibble = 0;
                    end
                    if (logical_address == voice_last_address[owner] &&
                        pre_fetch_nibble == voice_last_nibble[owner])
                        voice_repeated_count[owner] =
                            voice_repeated_count[owner] + 1;
                    else
                        voice_unique_count[owner] =
                            voice_unique_count[owner] + 1;
                end
                if (logical_address != expected_address ||
                    pre_fetch_nibble != expected_nibble) begin
                    progression_error_count =
                        progression_error_count + 1;
                    if (progression_error_count <= 4)
                        $display("FAIL LOGICAL_PROGRESSION cycle=%0d owner=%0d expected=%06h/%0d actual=%06h/%0d prior=%06h/%0d",
                                 system_cycle, owner, expected_address,
                                 expected_nibble, logical_address,
                                 pre_fetch_nibble,
                                 voice_last_address[owner],
                                 voice_last_nibble[owner]);
                end
                if (voice_last_fetch_cycle[owner] >= 0 &&
                    system_cycle - voice_last_fetch_cycle[owner] !=
                        SCHEDULER_PERIOD)
                    missed_slot_count = missed_slot_count + 1;
                voice_last_fetch_cycle[owner] = system_cycle;
                voice_last_address[owner] = logical_address;
                voice_last_nibble[owner] = pre_fetch_nibble;
                if (pre_fetch_nibble)
                    voice_low_count[owner] =
                        voice_low_count[owner] + 1;
                else
                    voice_high_count[owner] =
                        voice_high_count[owner] + 1;

                voice_fetch_count[owner] =
                    voice_fetch_count[owner] + 1;
                voice_logical_cursor_count[owner] =
                    voice_logical_cursor_count[owner] + 1;
                if (voice_fetch_count[owner] <= 2 && quick_mode)
                    $display("LOGICAL_START cycle=%0d owner=%0d index=%0d address=%06h nibble=%0d",
                             system_cycle, owner,
                             voice_fetch_count[owner], logical_address,
                             pre_fetch_nibble);
                voice_fetch_hash[owner] =
                    hash_u16(voice_fetch_hash[owner],
                             system_cycle - measure_start_cycle);
                voice_fetch_hash[owner] =
                    hash_byte(voice_fetch_hash[owner],
                              {5'd0, owner[2:0]});
                voice_address_hash[owner] =
                    hash_u24(voice_address_hash[owner],
                             logical_address[23:0]);
                voice_address_hash[owner] =
                    hash_byte(voice_address_hash[owner],
                              {7'd0, pre_fetch_nibble});
                voice_rom_hash[owner] =
                    hash_byte(voice_rom_hash[owner], pre_fetch_data);
                voice_rom_hash[owner] =
                    hash_byte(voice_rom_hash[owner], selected_nibble);
                voice_cursor_hash[owner] =
                    hash_u24(voice_cursor_hash[owner],
                             logical_address[23:0]);
                voice_cursor_hash[owner] =
                    hash_byte(voice_cursor_hash[owner],
                              {7'd0, pre_fetch_nibble});
                owner_hash = hash_byte(owner_hash, {5'd0, owner[2:0]});
                aggregate_fetch_hash =
                    hash_byte(aggregate_fetch_hash,
                              {5'd0, owner[2:0]});
                aggregate_fetch_hash =
                    hash_u24(aggregate_fetch_hash,
                             logical_address[23:0]);
                aggregate_fetch_hash =
                    hash_byte(aggregate_fetch_hash,
                              {7'd0, pre_fetch_nibble});
                if (measure_target_mask == 6'h3f &&
                    pre_active_mask == 6'h3f) begin
                    if (owner_round_seen[owner])
                        duplicate_slot_count =
                            duplicate_slot_count + 1;
                    owner_round_seen[owner] = 1'b1;
                    if (owner_round_seen == 6'h3f) begin
                        owner_round_count = owner_round_count + 1;
                        owner_round_seen = 6'd0;
                    end
                end
            end
        end

        if (measure_active && pre_physical_cursor_commit) begin
            if ($isunknown(pre_cur_ch) ||
                $isunknown(pre_physical_cursor_address))
                x_count = x_count + 1;
            cursor_owner = onehot_index(rotate_right(pre_cur_ch, 5));
            physical_cursor_commit_count =
                physical_cursor_commit_count + 1;
            if (cursor_owner < 0) begin
                cursor_cross_update_count = cursor_cross_update_count + 1;
            end else begin
                voice_physical_cursor_count[cursor_owner] =
                    voice_physical_cursor_count[cursor_owner] + 1;
                physical_cursor_hash =
                    hash_byte(physical_cursor_hash,
                              {5'd0, cursor_owner[2:0]});
                physical_cursor_hash =
                    hash_u24(physical_cursor_hash,
                             {3'd0, pre_physical_cursor_address});
                if (!measure_target_mask[cursor_owner]) begin
                    cursor_cross_update_count =
                        cursor_cross_update_count + 1;
                    voice_cross_owner_count[cursor_owner] =
                        voice_cross_owner_count[cursor_owner] + 1;
                end
            end
        end

        state_owner = tag_valid[STATE_TAG] ?
            tag_owner[STATE_TAG] : -1;
        if (measure_active && pre_decoder_state_commit) begin
            decoder_state_commit_count =
                decoder_state_commit_count + 1;
            if (!tag_valid[STATE_TAG] || state_owner < 0) begin
                accepted_state_mismatch_count =
                    accepted_state_mismatch_count + 1;
                logical_decoder_owner_mismatch_count =
                    logical_decoder_owner_mismatch_count + 1;
            end else if (tag_clr[STATE_TAG]) begin
                clear_state_commit_count =
                    clear_state_commit_count + 1;
                class_c_violation_count =
                    class_c_violation_count + 1;
            end else begin
                voice_decode_count[state_owner] =
                    voice_decode_count[state_owner] + 1;
                voice_decode_hash[state_owner] =
                    hash_byte(voice_decode_hash[state_owner],
                              tag_data[STATE_TAG]);
                voice_decode_hash[state_owner] =
                    hash_u16(voice_decode_hash[state_owner],
                        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_decoder.x5);
                voice_decode_hash[state_owner] =
                    hash_byte(voice_decode_hash[state_owner],
                        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_decoder.step5);
                if ($isunknown(
                    dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_decoder.x5) ||
                    $isunknown(
                    dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.u_decoder.step5))
                    x_count = x_count + 1;
            end
        end else if (measure_active && pre_clk_en_666 &&
                     tag_valid[STATE_TAG] && !tag_clr[STATE_TAG]) begin
            accepted_state_mismatch_count =
                accepted_state_mismatch_count + 1;
        end else if (measure_active && pre_clk_en_666 &&
                     tag_valid[STATE_TAG] && tag_clr[STATE_TAG]) begin
            clear_decoder_gate_count = clear_decoder_gate_count + 1;
        end

        if (measure_active && pre_clk_en_666 &&
            tag_valid[CONTRIB_TAG]) begin
            owner = onehot_index(pre_cur_ch);
            if (!pre_match) begin
                accepted_contribution_mismatch_count =
                    accepted_contribution_mismatch_count + 1;
            end else if (tag_owner[CONTRIB_TAG] != owner || owner < 0) begin
                accepted_contribution_mismatch_count =
                    accepted_contribution_mismatch_count + 1;
                contribution_owner_mismatch_count =
                    contribution_owner_mismatch_count + 1;
                if (tag_owner[CONTRIB_TAG] >= 0)
                    voice_cross_owner_count[tag_owner[CONTRIB_TAG]] =
                        voice_cross_owner_count[tag_owner[CONTRIB_TAG]] + 1;
            end else if (tag_clr[CONTRIB_TAG]) begin
                clear_physical_contribution_count =
                    clear_physical_contribution_count + 1;
                if (pre_gain_pcm != 0) begin
                    dummy_audible_effect_count =
                        dummy_audible_effect_count + 1;
                    voice_dummy_audible_count[owner] =
                        voice_dummy_audible_count[owner] + 1;
                    class_c_violation_count =
                        class_c_violation_count + 1;
                end
            end else begin
                left_contribution = pre_gain_pan[1] ?
                    pre_gain_pcm : 16'sd0;
                right_contribution = pre_gain_pan[0] ?
                    pre_gain_pcm : 16'sd0;
                logical_contribution_count =
                    logical_contribution_count + 1;
                voice_logical_contribution_count[owner] =
                    voice_logical_contribution_count[owner] + 1;
                voice_gain_count[owner] =
                    voice_gain_count[owner] + 1;
                voice_gain_hash[owner] =
                    hash_u16(voice_gain_hash[owner], pre_gain_pcm);
                voice_left_hash[owner] =
                    hash_u16(voice_left_hash[owner], left_contribution);
                voice_right_hash[owner] =
                    hash_u16(voice_right_hash[owner], right_contribution);
                logical_contribution_hash =
                    hash_byte(logical_contribution_hash,
                              {5'd0, owner[2:0]});
                logical_contribution_hash =
                    hash_u16(logical_contribution_hash,
                             left_contribution);
                logical_contribution_hash =
                    hash_u16(logical_contribution_hash,
                             right_contribution);
                if (left_contribution != 0 || right_contribution != 0) begin
                    audible_nonzero_contribution_count =
                        audible_nonzero_contribution_count + 1;
                    voice_audible_nonzero_count[owner] =
                        voice_audible_nonzero_count[owner] + 1;
                end
                magnitude = abs16(pre_gain_pcm);
                if (magnitude > voice_peak[owner])
                    voice_peak[owner] = magnitude;
                if (pre_gain_pan !== cfg_level[owner][7:6])
                    pan_leak_count = pan_leak_count + 1;
            end
        end

        if (measure_active && pre_clk_en_666) begin
            for (tag_index = TAG_DEPTH; tag_index > 0;
                 tag_index = tag_index - 1) begin
                tag_valid[tag_index] = tag_valid[tag_index-1];
                tag_clr[tag_index] = tag_clr[tag_index-1];
                tag_owner[tag_index] = tag_owner[tag_index-1];
                tag_address[tag_index] = tag_address[tag_index-1];
                tag_nibble[tag_index] = tag_nibble[tag_index-1];
                tag_data[tag_index] = tag_data[tag_index-1];
                tag_cycle[tag_index] = tag_cycle[tag_index-1];
            end
            tag_valid[0] = pre_valid_fetch;
            tag_clr[0] = pre_fetch_clr;
            tag_owner[0] = onehot_index(pre_cur_ch);
            tag_address[0] = logical_address;
            tag_nibble[0] = pre_fetch_nibble;
            tag_data[0] = selected_nibble;
            tag_cycle[0] = system_cycle;
            if (tag_valid[STATE_TAG] &&
                tag_cycle[STATE_TAG] >= system_cycle)
                tag_age_error_count = tag_age_error_count + 1;
            if (tag_valid[CONTRIB_TAG] &&
                tag_cycle[CONTRIB_TAG] >= system_cycle)
                tag_age_error_count = tag_age_error_count + 1;
        end

        previous_public_sample = snd_sample;
        previous_internal_sample = internal_snd_sample;
        previous_ready = warmup_ready;
        previous_command_update = adpcma_command_update;
    end

    always @(posedge warmup_ready) begin
        if (warmup_ready_cycle < 0)
            warmup_ready_cycle = system_cycle;
    end

    always @(posedge adpcma_command_update) begin
        adpcma_command_updates = adpcma_command_updates + 1;
        #1;
        if (adpcma_command !== last_expected_command)
            command_mask_errors = command_mask_errors + 1;
    end

    always @(posedge internal_snd_sample) begin
        internal_sample_count = internal_sample_count + 1;
        if (warmup_ready) begin
            #1;
            if (!snd_sample)
                drop_count = drop_count + 1;
        end
    end

    always @(posedge snd_sample) begin : public_sample_monitor
        integer magnitude;
        integer sample_value;
        integer sign_value;
        integer math_sum;

        public_sample_count = public_sample_count + 1;
        if (first_public_cycle < 0)
            first_public_cycle = system_cycle;
        if (last_public_rise >= 0 &&
            system_cycle - last_public_rise != 144)
            cadence_errors = cadence_errors + 1;
        if (last_public_rise == system_cycle)
            duplicate_count = duplicate_count + 1;
        last_public_rise = system_cycle;
        public_width = system_cycle;
        #1;

        if (measure_active && measure_samples < measure_goal) begin
            if ($isunknown(snd_left) || $isunknown(snd_right) ||
                $isunknown(adpcma_l) || $isunknown(adpcma_r) ||
                $isunknown(adpcmb_l) || $isunknown(adpcmb_r) ||
                $isunknown(psg_A) || $isunknown(psg_B) ||
                $isunknown(psg_C) || $isunknown(psg_snd)) begin
                x_count = x_count + 1;
                if (x_count == 1)
                    $display("FAIL PUBLIC_X cycle=%0d snd=%h/%h adpcma=%h/%h adpcmb=%h/%h psg=%h/%h/%h/%h",
                             system_cycle, snd_left, snd_right,
                             adpcma_l, adpcma_r, adpcmb_l, adpcmb_r,
                             psg_A, psg_B, psg_C, psg_snd);
            end else begin
                aggregate_l_hash = hash_u16(aggregate_l_hash, adpcma_l);
                aggregate_r_hash = hash_u16(aggregate_r_hash, adpcma_r);
                final_l_hash = hash_u16(final_l_hash, snd_left);
                final_r_hash = hash_u16(final_r_hash, snd_right);
                stereo_hash = hash_stereo(stereo_hash, snd_left, snd_right);
                dc_sum_l = dc_sum_l + snd_left;
                dc_sum_r = dc_sum_r + snd_right;
                if (snd_left != 0 || snd_right != 0)
                    sample_nonzero = sample_nonzero + 1;
                magnitude = abs16(snd_left);
                if (abs16(snd_right) > magnitude)
                    magnitude = abs16(snd_right);
                if (magnitude > sample_peak)
                    sample_peak = magnitude;
                magnitude = abs16(adpcma_l);
                if (abs16(adpcma_r) > magnitude)
                    magnitude = abs16(adpcma_r);
                if (magnitude > aggregate_peak)
                    aggregate_peak = magnitude;
                sample_value = snd_left;
                if (sample_value < sample_min)
                    sample_min = sample_value;
                if (sample_value > sample_max)
                    sample_max = sample_value;
                sample_value = snd_right;
                if (sample_value < sample_min)
                    sample_min = sample_value;
                if (sample_value > sample_max)
                    sample_max = sample_value;
                sign_value = snd_left != 0 ?
                    (snd_left < 0 ? -1 : 1) :
                    (snd_right != 0 ? (snd_right < 0 ? -1 : 1) : 0);
                if (sign_value != 0) begin
                    if (previous_sign_valid && sign_value != previous_sign)
                        zero_crossings = zero_crossings + 1;
                    previous_sign = sign_value;
                    previous_sign_valid = 1;
                end
                math_sum = abs16(ref_acc_l[15:0]);
                if (abs16(ref_acc_r[15:0]) > math_sum)
                    math_sum = abs16(ref_acc_r[15:0]);
                if (math_sum > mathematical_sum_peak)
                    mathematical_sum_peak = math_sum;
            end
            measure_samples = measure_samples + 1;
        end

        if (audit_active) begin
            if (adpcmb_active || adpcmb_start || adpcmb_l != 0 ||
                adpcmb_r != 0)
                adpcmb_nonidle_count = adpcmb_nonidle_count + 1;
            if (!adpcmb_roe_n && adpcmb_active)
                adpcmb_fetch_count = adpcmb_fetch_count + 1;
            if (fm_operator != 0)
                fm_nonidle_count = fm_nonidle_count + 1;
            if (psg_A != 0 || psg_B != 0 || psg_C != 0 || psg_snd != 0)
                ssg_nonidle_count = ssg_nonidle_count + 1;
            if (ssg_mixer[5:3] != 3'b111)
                noise_enable_count = noise_enable_count + 1;
            if (ssg_volume_a[4] || ssg_volume_b[4] || ssg_volume_c[4])
                envelope_enable_count = envelope_enable_count + 1;
        end
    end

    always @(negedge snd_sample) begin
        if (warmup_ready && system_cycle - public_width != 6)
            width_errors = width_errors + 1;
    end

    task automatic report_result;
        integer voice;
        begin
            command_missed_count =
                adpcma_command_writes - adpcma_command_updates;
            if (busy_timeout_count != 0 || busy_while_write_count != 0 ||
                busy_min_cycles < 190 || busy_max_cycles > 192 ||
                cadence_errors != 0 || width_errors != 0 ||
                drop_count != 0 || duplicate_count != 0 ||
                command_missed_count != 0 ||
                command_duplicate_count != 0 ||
                command_mask_errors != 0 || active_mask_errors != 0 ||
                arithmetic_mismatch_count != 0 ||
                ownership_mismatch_count != 0 || x_count != 0 ||
                raw_owner_unknown_count != 0 ||
                capture_owner_mismatch_count != 0 ||
                logical_owner_unknown_count != 0 ||
                logical_decoder_owner_mismatch_count != 0 ||
                cursor_cross_update_count != 0 ||
                rom_contamination_count != 0 ||
                contribution_owner_mismatch_count != 0 ||
                accepted_state_mismatch_count != 0 ||
                accepted_contribution_mismatch_count != 0 ||
                tag_age_error_count != 0 ||
                class_c_violation_count != 0 ||
                clear_state_commit_count != 0 ||
                clear_logical_cursor_count != 0 ||
                clear_logical_contribution_count != 0 ||
                dummy_audible_effect_count != 0 ||
                adpcmb_fetch_count != 0 || adpcmb_nonidle_count != 0 ||
                fm_nonidle_count != 0 || ssg_nonidle_count != 0 ||
                noise_enable_count != 0 || envelope_enable_count != 0 ||
                ssg_volume_a != 0 || ssg_volume_b != 0 ||
                ssg_volume_c != 0 || ssg_mixer != 8'h3f)
                fail("final Phase 3C audit mismatch");

            $display("PHASE3C_TRANSPORT scenario=%0s run=%0d accepted=%0d port0=%0d port1=%0d adpcma=%0d commands=%0d updates=%0d busy_min=%0d busy_max=%0d busy_hash=%016h timeout=%0d busy_write=%0d",
                     scenario_name, run_id, accepted_write_count,
                     port0_write_count, port1_write_count,
                     adpcma_register_writes, adpcma_command_writes,
                     adpcma_command_updates, busy_min_cycles,
                     busy_max_cycles, busy_duration_hash,
                     busy_timeout_count, busy_while_write_count);
            $display("PHASE3C_SAMPLE scenario=%0s run=%0d ready_cycle=%0d first_public=%0d cadence=144 width=6 cadence_errors=%0d width_errors=%0d drops=%0d duplicates=%0d x=%0d",
                     scenario_name, run_id, warmup_ready_cycle,
                     first_public_cycle, cadence_errors, width_errors,
                     drop_count, duplicate_count, x_count);
            for (voice = 0; voice < 6; voice = voice + 1)
                $display("PHASE3C_VOICE scenario=%0s run=%0d voice=%0d raw=%0d dummy=%0d capture=%0d decoder_input=%0d fetch_count=%0d state=%0d cursor_physical=%0d cursor_logical=%0d gain_count=%0d contribution_physical=%0d contribution_logical=%0d audible_nonzero=%0d unique=%0d repeated=%0d high=%0d low=%0d range=%0d owner_mismatch=%0d cross_owner=%0d dummy_audible=%0d first_cycle=%0d first_address=%06h last_address=%06h last_nibble=%0d raw_hash=%016h dummy_hash=%016h fetch_hash=%016h address_hash=%016h rom_hash=%016h decode_hash=%016h cursor_hash=%016h gain_hash=%016h left_hash=%016h right_hash=%016h peak=%0d",
                         scenario_name, run_id, voice,
                         voice_raw_count[voice],
                         voice_dummy_raw_count[voice],
                         voice_capture_count[voice],
                         voice_decoder_input_count[voice],
                         voice_fetch_count[voice],
                         voice_decode_count[voice],
                         voice_physical_cursor_count[voice],
                         voice_logical_cursor_count[voice],
                         voice_gain_count[voice],
                         voice_physical_contribution_count[voice],
                         voice_logical_contribution_count[voice],
                         voice_audible_nonzero_count[voice],
                         voice_unique_count[voice],
                         voice_repeated_count[voice],
                         voice_high_count[voice], voice_low_count[voice],
                         voice_out_of_range_count[voice],
                         voice_owner_mismatch_count[voice],
                         voice_cross_owner_count[voice],
                         voice_dummy_audible_count[voice],
                         voice_first_fetch_cycle[voice],
                         voice_first_address[voice],
                         voice_last_address[voice],
                         voice_last_nibble[voice],
                         voice_raw_hash[voice],
                         voice_dummy_hash[voice],
                         voice_fetch_hash[voice],
                         voice_address_hash[voice],
                         voice_rom_hash[voice],
                         voice_decode_hash[voice],
                         voice_cursor_hash[voice],
                         voice_gain_hash[voice],
                         voice_left_hash[voice],
                         voice_right_hash[voice], voice_peak[voice]);
            $display("PHASE3C_MIX scenario=%0s run=%0d aggregate_l=%016h aggregate_r=%016h final_l=%016h final_r=%016h stereo=%016h stop=%016h nonzero=%0d peak=%0d min=%0d max=%0d zero_crossings=%0d dc_l=%0d dc_r=%0d aggregate_peak=%0d math_sum_peak=%0d",
                     scenario_name, run_id, aggregate_l_hash,
                     aggregate_r_hash, final_l_hash, final_r_hash,
                     stereo_hash, stop_hash, sample_nonzero, sample_peak,
                     sample_min, sample_max, zero_crossings,
                     dc_sum_l, dc_sum_r, aggregate_peak,
                     mathematical_sum_peak);
            $display("PHASE3C_EVENTS scenario=%0s run=%0d raw=%0d dummy=%0d logical=%0d decoder_input=%0d state=%0d cursor_physical=%0d cursor_logical=%0d contribution_physical=%0d contribution_logical=%0d audible_nonzero=%0d aggregate_commit=%0d standard_insert=%0d final_publish=%0d public_valid=%0d raw_hash=%016h dummy_hash=%016h logical_hash=%016h cursor_hash=%016h contribution_hash=%016h raw_owner_hash=%016h logical_owner_hash=%016h active_hash=%016h zero_hash=%016h",
                     scenario_name, run_id, raw_request_count,
                     dummy_request_count, logical_consume_count,
                     decoder_input_count, decoder_state_commit_count,
                     physical_cursor_commit_count,
                     logical_cursor_commit_count,
                     physical_contribution_count,
                     logical_contribution_count,
                     audible_nonzero_contribution_count,
                     aggregate_commit_count, standard_acc_insert_count,
                     final_publish_count, measure_samples,
                     raw_request_hash, dummy_request_hash,
                     aggregate_fetch_hash, physical_cursor_hash,
                     logical_contribution_hash, raw_owner_hash,
                     owner_hash, active_mask_hash, stop_hash);
            $display("PHASE3C_ARITH scenario=%0s run=%0d compare=%0d mismatch=%0d aggregate_saturation=%0d aggregate_wrap=%0d gain_truncation=%0d interpolation_truncation=%0d decoder_wrap=%0d final_saturation=%0d final_wrap=%0d",
                     scenario_name, run_id, arithmetic_compare_count,
                     arithmetic_mismatch_count,
                     aggregate_saturation_count, aggregate_wrap_count,
                     gain_truncation_count, interpolation_truncation_count,
                     decoder_wrap_count, final_saturation_count,
                     final_wrap_count);
            $display("PHASE3C_OWNERSHIP scenario=%0s run=%0d fetches=%0d active_hash=%016h owner_hash=%016h fetch_hash=%016h owner_unknown=%0d owner_inactive=%0d duplicate_cycle=%0d capture_mismatch=%0d ownership_mismatch=%0d range=%0d progression=%0d missed_slot=%0d duplicate_slot=%0d starvation=%0d rounds=%0d pan_leak=%0d raw_owner_unknown=%0d capture_owner_mismatch=%0d logical_owner_unknown=%0d decoder_owner_mismatch=%0d cursor_cross=%0d rom_contamination=%0d contribution_owner_mismatch=%0d",
                     scenario_name, run_id, global_fetch_count,
                     active_mask_hash, owner_hash, aggregate_fetch_hash,
                     owner_unknown_count, owner_inactive_count,
                     owner_duplicate_cycle_count, capture_mismatch_count,
                     ownership_mismatch_count, range_error_count,
                     progression_error_count, missed_slot_count,
                     duplicate_slot_count, starvation_count,
                     owner_round_count, pan_leak_count,
                     raw_owner_unknown_count,
                     capture_owner_mismatch_count,
                     logical_owner_unknown_count,
                     logical_decoder_owner_mismatch_count,
                     cursor_cross_update_count, rom_contamination_count,
                     contribution_owner_mismatch_count);
            $display("PHASE3C_CLASS scenario=%0s run=%0d class=%0s raw_clr=%0d capture_clr=%0d decoder_input_clr=%0d decoder_accept_clr=0 decoder_gate_clr=%0d state_commit_clr=%0d logical_cursor_clr=%0d contribution_write_clr=%0d logical_contribution_clr=%0d dummy_audible=%0d violations=%0d state_tag_mismatch=%0d contribution_tag_mismatch=%0d tag_age_errors=%0d",
                     scenario_name, run_id,
                     class_c_violation_count == 0 ? "C" : "FAIL",
                     dummy_request_count, dummy_request_count,
                     dummy_request_count, clear_decoder_gate_count,
                     clear_state_commit_count,
                     clear_logical_cursor_count,
                     clear_physical_contribution_count,
                     clear_logical_contribution_count,
                     dummy_audible_effect_count,
                     class_c_violation_count,
                     accepted_state_mismatch_count,
                     accepted_contribution_mismatch_count,
                     tag_age_error_count);
            $display("PHASE3C_COMMANDS scenario=%0s run=%0d seen_03=%0d seen_07=%0d seen_0f=%0d seen_3f=%0d seen_81=%0d seen_82=%0d seen_84=%0d seen_88=%0d seen_90=%0d seen_a0=%0d seen_bf=%0d seen_reserved=%0d missed=%0d duplicate=%0d mask_errors=%0d active_errors=%0d",
                     scenario_name, run_id, command_seen[0],
                     command_seen[1], command_seen[2], command_seen[3],
                     command_seen[4], command_seen[5], command_seen[6],
                     command_seen[7], command_seen[8], command_seen[9],
                     command_seen[10], command_seen[11],
                     command_missed_count, command_duplicate_count,
                     command_mask_errors, active_mask_errors);
            $display("PHASE3C_IDLE scenario=%0s run=%0d adpcmb_fetch=%0d adpcmb_nonidle=%0d fm_nonidle=%0d ssg_nonidle=%0d noise_enable=%0d envelope_enable=%0d",
                     scenario_name, run_id, adpcmb_fetch_count,
                     adpcmb_nonidle_count, fm_nonidle_count,
                     ssg_nonidle_count, noise_enable_count,
                     envelope_enable_count);
            $display("PHASE3C_SCENARIO scenario=%0s run=%0d failures=%0d samples=%0d target_mask=%02h safe_level=c0 primary_level=f5 clear_count=%0d retrigger_delay=%0d result=%0s",
                     scenario_name, run_id, failures, measure_samples,
                     measure_target_mask, clear_sequence_count,
                     retrigger_delay, failures == 0 ? "PASS" : "FAIL");
            if (failures != 0)
                $fatal(1, "Phase 3C scenario %0s failed (%0d)",
                       scenario_name, failures);
            $display("PHASE3C_PASS scenario=%0s run=%0d",
                     scenario_name, run_id);
        end
    endtask

    initial begin : phase3c_sequence
        if (!$value$plusargs("RUN_ID=%d", run_id))
            run_id = 1;
        if (!$value$plusargs("SCENARIO=%d", scenario_id))
            scenario_id = 1;
        if (!$value$plusargs("QUICK=%d", quick_mode))
            quick_mode = 0;
        command_phase_override =
            $value$plusargs("COMMAND_PHASE=%d", command_phase);
        if (!command_phase_override)
            command_phase = CANONICAL_PHASE;
        case (scenario_id)
            1: scenario_name = "A";
            2: scenario_name = "B";
            3: scenario_name = "C";
            4: scenario_name = "D";
            5: scenario_name = "E";
            6: scenario_name = "F";
            7: scenario_name = "G";
            8: scenario_name = "H";
            9: scenario_name = "I";
            10: scenario_name = "J";
            11: scenario_name = "K";
            12: scenario_name = "L";
            default: begin
                $fatal(1, "unknown Phase 3C scenario %0d", scenario_id);
            end
        endcase
        $display("PHASE3C_BEGIN scenario=%0s run=%0d",
                 scenario_name, run_id);
        prepare_common();
        case (scenario_id)
            1: run_scenario_a();
            2: run_scenario_b();
            3: run_scenario_c();
            4: run_scenario_d();
            5: run_scenario_e();
            6: run_scenario_f();
            7: run_scenario_g();
            8: run_scenario_h();
            9: run_scenario_i();
            10: run_scenario_j();
            11: run_scenario_k();
            12: run_scenario_l();
        endcase
        report_result();
        $finish;
    end
endmodule

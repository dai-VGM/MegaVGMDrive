`timescale 1ns/1ps

// Phase 4A-R is a read-only behavioral microscope for the pinned ADPCM-B
// source.  The ROM and all observations are test-only; no signal feeds back
// into JT10 apart from the documented CPU and ROM interfaces.
module tb_jt10_phase4afix_adpcmb_audit_base;
    localparam [63:0] FNV_OFFSET = 64'hcbf29ce484222325;
    localparam integer PATTERN_P = 0;
    localparam integer PATTERN_N = 1;
    localparam integer PATTERN_Z = 2;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cen = 1'b0;
    logic session_start = 1'b1;
    logic loop_event = 1'b0;
    logic status_port1_select = 1'b0;
    integer pattern_mode = PATTERN_P;

    wire [1:0] bus_addr;
    wire [1:0] dut_addr = status_port1_select ? 2'b10 : bus_addr;
    wire [7:0] din;
    wire cs_n;
    wire wr_n;
    wire [7:0] dout;
    wire irq_n;
    wire [19:0] adpcma_addr;
    wire [3:0] adpcma_bank;
    wire adpcma_roe_n;
    wire [7:0] adpcma_data = 8'h00;
    wire [23:0] adpcmb_addr;
    wire adpcmb_roe_n;
    logic [7:0] adpcmb_data;
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

    wire clk_en = dut.u_jt10.u_jt12.clk_en;
    wire clk_en_55 = dut.u_jt10.u_jt12.clk_en_55;
    wire clk_en_666 = dut.u_jt10.u_jt12.clk_en_666;
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
    wire [3:0] b_present =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_b.din;
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
    wire signed [15:0] acc_input_l =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_input_l;
    wire signed [15:0] acc_input_r =
        dut.u_jt10.u_jt12.gen_adpcm.u_acc.acc_input_r;
    wire [2:0] final_cur_ch = dut.u_jt10.u_jt12.cur_ch;
    wire [1:0] final_cur_op = dut.u_jt10.u_jt12.cur_op;
    wire final_zero = dut.u_jt10.u_jt12.zero;
    wire [5:0] adpcma_active =
        dut.u_jt10.u_jt12.gen_adpcm.u_adpcm_a.en_ch;

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

    integer run_id = 1;
    integer quick_mode = 0;
    integer failures = 0;
    integer system_cycle = 0;
    integer public_samples = 0;
    integer case_public_samples = 0;
    integer case_raw = 0;
    integer case_capture = 0;
    integer case_logical = 0;
    integer case_decoder_commit = 0;
    integer case_delta_commit = 0;
    integer case_cursor_commit = 0;
    integer case_interpolation_commit = 0;
    integer case_gain_commit = 0;
    integer case_lane_commit = 0;
    integer case_acc_commit = 0;
    integer case_final_publish = 0;
    integer case_natural_end = 0;
    integer case_x = 0;
    integer x_raw = 0;
    integer x_logical = 0;
    integer x_decoder = 0;
    integer x_delta = 0;
    integer x_interpolation = 0;
    integer x_gain = 0;
    integer x_lane = 0;
    integer x_accumulator = 0;
    integer x_final = 0;
    integer x_public = 0;
    integer post_samples = 0;
    integer post_raw = 0;
    integer post_capture = 0;
    integer post_logical = 0;
    integer post_decoder_commit = 0;
    integer post_cursor_commit = 0;
    integer post_interpolation_commit = 0;
    integer post_gain_commit = 0;
    integer post_lane_commit = 0;
    integer post_x = 0;
    integer active_assert_cycle = -1;
    integer active_clear_cycle = -1;
    integer eos_cycle = -1;
    integer start_accept_cycle = -1;
    integer reset_accept_cycle = -1;
    integer last_raw_cycle = -1;
    integer last_logical_cycle = -1;
    integer last_decoder_cycle = -1;
    integer last_interpolation_cycle = -1;
    integer first_raw_cycle = -1;
    integer first_logical_cycle = -1;
    integer raw_interval_144 = 0;
    integer raw_interval_288 = 0;
    integer raw_interval_other = 0;
    integer last_post_raw_cycle = -1;
    integer out_of_range_raw = 0;
    integer cadence_errors = 0;
    integer width_errors = 0;
    integer drops = 0;
    integer duplicates = 0;
    integer last_public_cycle = -1;
    integer public_width = 0;
    integer internal_pulses = 0;
    integer first_public_internal = -1;
    integer idle_adpcma = 0;
    integer idle_fm = 0;
    integer idle_ssg = 0;
    integer logical_at_stop = 0;
    integer decoder_at_stop = 0;
    integer restart_stale_samples = 0;
    integer restart_first_nonzero = -1;
    integer checkpoint_1_interpolation = 0;
    integer checkpoint_16_interpolation = 0;
    integer checkpoint_256_interpolation = 0;
    integer checkpoint_512_interpolation = 0;
    integer checkpoint_4096_interpolation = 0;
    integer checkpoint_4096_gain = 0;
    integer checkpoint_4096_lane_l = 0;
    integer checkpoint_4096_lane_r = 0;
    integer checkpoint_4096_final_l = 0;
    integer checkpoint_4096_final_r = 0;
    integer restore_interpolation = 0;
    integer restore_gain = 0;
    integer restore_lane_l = 0;
    integer restore_lane_r = 0;
    integer restore_final_l = 0;
    integer restore_final_r = 0;
    logic previous_public = 1'b0;
    logic previous_internal = 1'b0;
    logic previous_chon = 1'b0;
    logic previous_flag = 1'b0;
    logic case_audit = 1'b0;
    logic post_stop_audit = 1'b0;
    logic playback_hash_active = 1'b0;
    logic [63:0] playback_hash = FNV_OFFSET;
    logic [63:0] post_hash = FNV_OFFSET;
    logic [63:0] raw_hash = FNV_OFFSET;
    logic [63:0] logical_hash = FNV_OFFSET;
    logic [63:0] state_hash = FNV_OFFSET;
    logic [63:0] s0_first_hash = FNV_OFFSET;
    logic [63:0] s0_restart_hash = FNV_OFFSET;
    integer s0_first_samples = 0;
    integer s0_restart_samples = 0;
    reg [8*32-1:0] case_name = "idle";

    function automatic [7:0] rom_byte(
        input integer mode,
        input [23:0] address
    );
        reg [17:0] mixed;
        begin
            case (mode)
                PATTERN_N: rom_byte = 8'hf8;
                PATTERN_Z: rom_byte = 8'h08;
                default: begin
                    mixed = address[7:0] * 18'd73 +
                            address[15:8] * 18'd29 + 18'd41;
                    rom_byte = mixed[7:0];
                end
            endcase
        end
    endfunction

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

    always @(*) adpcmb_data = rom_byte(pattern_mode, adpcmb_addr);
    always #5 clk = ~clk;

    task automatic fail(input [8*96-1:0] message);
        begin
            failures = failures + 1;
            $display("FAIL case=%0s cycle=%0d %0s",
                     case_name, system_cycle, message);
        end
    endtask

    task automatic wait_public(input integer count);
        integer target;
        begin
            target = public_samples + count;
            wait (public_samples >= target);
        end
    endtask

    task automatic wait_post(input integer count);
        begin
            wait (post_samples >= count);
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

    task automatic reset_case_statistics(input [8*32-1:0] label);
        begin
            case_name = label;
            case_public_samples = 0;
            case_raw = 0;
            case_capture = 0;
            case_logical = 0;
            case_decoder_commit = 0;
            case_delta_commit = 0;
            case_cursor_commit = 0;
            case_interpolation_commit = 0;
            case_gain_commit = 0;
            case_lane_commit = 0;
            case_acc_commit = 0;
            case_final_publish = 0;
            case_natural_end = 0;
            case_x = 0;
            x_raw = 0;
            x_logical = 0;
            x_decoder = 0;
            x_delta = 0;
            x_interpolation = 0;
            x_gain = 0;
            x_lane = 0;
            x_accumulator = 0;
            x_final = 0;
            x_public = 0;
            post_samples = 0;
            post_raw = 0;
            post_capture = 0;
            post_logical = 0;
            post_decoder_commit = 0;
            post_cursor_commit = 0;
            post_interpolation_commit = 0;
            post_gain_commit = 0;
            post_lane_commit = 0;
            post_x = 0;
            active_assert_cycle = -1;
            active_clear_cycle = -1;
            eos_cycle = -1;
            start_accept_cycle = -1;
            reset_accept_cycle = -1;
            last_raw_cycle = -1;
            last_logical_cycle = -1;
            last_decoder_cycle = -1;
            last_interpolation_cycle = -1;
            first_raw_cycle = -1;
            first_logical_cycle = -1;
            raw_interval_144 = 0;
            raw_interval_288 = 0;
            raw_interval_other = 0;
            last_post_raw_cycle = -1;
            out_of_range_raw = 0;
            logical_at_stop = 0;
            decoder_at_stop = 0;
            restart_stale_samples = 0;
            restart_first_nonzero = -1;
            checkpoint_1_interpolation = 0;
            checkpoint_16_interpolation = 0;
            checkpoint_256_interpolation = 0;
            checkpoint_512_interpolation = 0;
            checkpoint_4096_interpolation = 0;
            checkpoint_4096_gain = 0;
            checkpoint_4096_lane_l = 0;
            checkpoint_4096_lane_r = 0;
            checkpoint_4096_final_l = 0;
            checkpoint_4096_final_r = 0;
            restore_interpolation = 0;
            restore_gain = 0;
            restore_lane_l = 0;
            restore_lane_r = 0;
            restore_final_l = 0;
            restore_final_r = 0;
            playback_hash = FNV_OFFSET;
            post_hash = FNV_OFFSET;
            raw_hash = FNV_OFFSET;
            logical_hash = FNV_OFFSET;
            state_hash = FNV_OFFSET;
        end
    endtask

    task automatic full_reset_and_silence(
        input [8*32-1:0] label,
        input integer mode
    );
        integer zero_start;
        begin
            case_audit = 1'b0;
            post_stop_audit = 1'b0;
            playback_hash_active = 1'b0;
            @(negedge clk);
            rst = 1'b1;
            session_start = 1'b1;
            cen = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            session_start = 1'b0;
            repeat (64) @(posedge clk);
            if (reset_cen_count !== 3'd6 || !reset_cen_valid)
                fail("RESET_CEN_CONTRACT");
            @(negedge clk);
            rst = 1'b0;
            pattern_mode = mode;
            wait (warmup_ready === 1'b1);
            wait (snd_sample === 1'b1);
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
            bus.jt10_write_port0(8'h10, 8'h01);
            bus.jt10_write_port0(8'h1c, 8'h80);
            bus.jt10_write_port0(8'h10, 8'h00);
            reset_case_statistics(label);
            zero_start = public_samples;
            wait_public(16);
            if (b_chon !== 1'b0 || b_flag !== 1'b0 ||
                b_lane_l !== 16'sd0 || b_lane_r !== 16'sd0 ||
                snd_left !== 16'sd0 || snd_right !== 16'sd0 ||
                public_samples - zero_start < 16)
                fail("COMMON_INITIAL_SILENCE");
            case_audit = 1'b1;
        end
    endtask

    task automatic configure_b(
        input [15:0] start_value,
        input [15:0] end_value
    );
        begin
            bus.jt10_write_port0(8'h11, 8'hc0);
            bus.jt10_write_port0(8'h12, start_value[7:0]);
            bus.jt10_write_port0(8'h13, start_value[15:8]);
            bus.jt10_write_port0(8'h14, end_value[7:0]);
            bus.jt10_write_port0(8'h15, end_value[15:8]);
            bus.jt10_write_port0(8'h19, 8'h00);
            bus.jt10_write_port0(8'h1a, 8'h80);
            bus.jt10_write_port0(8'h1b, 8'hff);
            if (b_start !== start_value || b_end !== end_value ||
                b_delta !== 16'h8000 || b_pan !== 2'b11 ||
                b_level !== 8'hff || b_repeat !== 1'b0)
                fail("REGISTER_CAPTURE");
        end
    endtask

    task automatic start_b;
        begin
            align_start();
            playback_hash_active = 1'b1;
            bus.jt10_write_port0(8'h10, 8'h80);
            wait (b_chon === 1'b1);
        end
    endtask

    task automatic arm_post_window;
        begin
            logical_at_stop = case_logical;
            decoder_at_stop = case_decoder_commit;
            post_samples = 0;
            post_raw = 0;
            post_capture = 0;
            post_logical = 0;
            post_decoder_commit = 0;
            post_cursor_commit = 0;
            post_interpolation_commit = 0;
            post_gain_commit = 0;
            post_lane_commit = 0;
            post_x = 0;
            last_post_raw_cycle = -1;
            post_hash = FNV_OFFSET;
            post_stop_audit = 1'b1;
        end
    endtask

    task automatic print_case(input integer soak_samples);
        begin
            if (case_x != 0 || post_x != 0)
                fail("RELEVANT_EVENT_X");
            $display("PHASE4AFIX_BASE_CASE case=%0s run=%0d pattern=%0d soak=%0d active=%0d eos=%0d start_accept=%0d reset_accept=%0d active_assert=%0d active_clear=%0d eos_cycle=%0d raw=%0d capture=%0d logical=%0d decoder=%0d delta=%0d cursor=%0d interpolation_commits=%0d gain_commits=%0d lane_commits=%0d acc_commits=%0d final_publish=%0d natural_end=%0d post_raw=%0d post_capture=%0d post_logical=%0d post_decoder=%0d post_cursor=%0d post_interpolation=%0d post_gain=%0d post_lane=%0d range=%0d raw_i144=%0d raw_i288=%0d raw_iother=%0d hold_i=%0d/%0d/%0d/%0d/%0d hold_gain=%0d hold_lane=%0d/%0d hold_final=%0d/%0d restore=%0d/%0d/%0d/%0d/%0d/%0d raw_hash=%016h logical_hash=%016h state_hash=%016h playback_hash=%016h hold_hash=%016h x=%0d post_x=%0d x_events=%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d",
                case_name, run_id, pattern_mode, soak_samples,
                b_chon, b_flag, start_accept_cycle,
                reset_accept_cycle, active_assert_cycle,
                active_clear_cycle, eos_cycle, case_raw, case_capture,
                case_logical, case_decoder_commit, case_delta_commit,
                case_cursor_commit, case_interpolation_commit,
                case_gain_commit, case_lane_commit, case_acc_commit,
                case_final_publish, case_natural_end, post_raw,
                post_capture, post_logical, post_decoder_commit,
                post_cursor_commit, post_interpolation_commit,
                post_gain_commit, post_lane_commit, out_of_range_raw,
                raw_interval_144, raw_interval_288, raw_interval_other,
                checkpoint_1_interpolation,
                checkpoint_16_interpolation,
                checkpoint_256_interpolation,
                checkpoint_512_interpolation,
                checkpoint_4096_interpolation,
                checkpoint_4096_gain, checkpoint_4096_lane_l,
                checkpoint_4096_lane_r, checkpoint_4096_final_l,
                checkpoint_4096_final_r, restore_interpolation,
                restore_gain, restore_lane_l, restore_lane_r,
                restore_final_l, restore_final_r, raw_hash,
                logical_hash, state_hash, playback_hash, post_hash,
                case_x, post_x, x_raw, x_logical, x_decoder,
                x_delta, x_interpolation, x_gain, x_lane,
                x_accumulator, x_final, x_public);
        end
    endtask

    task automatic run_natural(
        input [8*32-1:0] label,
        input integer mode,
        input integer action,
        input integer soak_samples
    );
        begin
            full_reset_and_silence(label, mode);
            configure_b(16'h0020, 16'h0020);
            start_b();
            wait (b_chon === 1'b0);
            playback_hash_active = 1'b0;
            wait (b_flag === 1'b1);
            case (action)
                1: bus.jt10_write_port0(8'h10, 8'h00);
                2: bus.jt10_write_port0(8'h10, 8'h01);
                3: begin
                    bus.jt10_write_port0(8'h10, 8'h01);
                    bus.jt10_write_port0(8'h10, 8'h00);
                end
                4: bus.jt10_write_port0(8'h1b, 8'h00);
                5: bus.jt10_write_port0(8'h11, 8'h00);
                default: ;
            endcase
            arm_post_window();
            wait_post(soak_samples);
            if (action == 4) begin
                bus.jt10_write_port0(8'h1b, 8'hff);
                wait_public(16);
                restore_interpolation = b_interpolation;
                restore_gain = b_gain;
                restore_lane_l = b_lane_l;
                restore_lane_r = b_lane_r;
                restore_final_l = snd_left;
                restore_final_r = snd_right;
            end
            if (action == 5) begin
                bus.jt10_write_port0(8'h11, 8'hc0);
                wait_public(16);
                restore_interpolation = b_interpolation;
                restore_gain = b_gain;
                restore_lane_l = b_lane_l;
                restore_lane_r = b_lane_r;
                restore_final_l = snd_left;
                restore_final_r = snd_right;
            end
            print_case(soak_samples);
            case_audit = 1'b0;
            post_stop_audit = 1'b0;
        end
    endtask

    task automatic run_midstream(
        input [8*32-1:0] label,
        input integer action,
        input integer soak_samples
    );
        begin
            full_reset_and_silence(label, PATTERN_P);
            configure_b(16'h0020, 16'h003f);
            start_b();
            wait (case_logical >= 100);
            arm_post_window();
            case (action)
                0: bus.jt10_write_port0(8'h10, 8'h01);
                1: begin
                    bus.jt10_write_port0(8'h10, 8'h01);
                    bus.jt10_write_port0(8'h10, 8'h00);
                end
                2: bus.jt10_write_port0(8'h10, 8'h00);
                3: bus.jt10_write_port0(8'h1b, 8'h00);
                4: bus.jt10_write_port0(8'h11, 8'h00);
                default: ;
            endcase
            if (action <= 2)
                wait (b_chon === 1'b0);
            wait_post(soak_samples);
            if (action == 3) begin
                bus.jt10_write_port0(8'h1b, 8'hff);
                wait_public(512);
                restore_interpolation = b_interpolation;
                restore_gain = b_gain;
                restore_lane_l = b_lane_l;
                restore_lane_r = b_lane_r;
                restore_final_l = snd_left;
                restore_final_r = snd_right;
            end
            if (action == 4) begin
                bus.jt10_write_port0(8'h11, 8'hc0);
                wait_public(512);
                restore_interpolation = b_interpolation;
                restore_gain = b_gain;
                restore_lane_l = b_lane_l;
                restore_lane_r = b_lane_r;
                restore_final_l = snd_left;
                restore_final_r = snd_right;
            end
            print_case(soak_samples);
            case_audit = 1'b0;
            post_stop_audit = 1'b0;
        end
    endtask

    task automatic run_restart(
        input [8*32-1:0] label,
        input integer preparation
    );
        logic [63:0] first_hash;
        integer first_count;
        begin
            full_reset_and_silence(label, PATTERN_P);
            configure_b(16'h0020,
                        preparation == 0 ? 16'h0020 : 16'h003f);
            start_b();
            if (preparation == 0) begin
                wait (b_chon === 1'b0);
                playback_hash_active = 1'b0;
                wait (b_flag === 1'b1);
                first_hash = playback_hash;
                first_count = case_public_samples;
                wait_public(16);
            end else begin
                wait (case_logical >= 100);
                if (preparation == 1)
                    bus.jt10_write_port0(8'h10, 8'h01);
                if (preparation == 2) begin
                    bus.jt10_write_port0(8'h10, 8'h01);
                    bus.jt10_write_port0(8'h10, 8'h00);
                end
                if (preparation == 3) begin
                    bus.jt10_write_port0(8'h1b, 8'h00);
                    wait_public(64);
                    bus.jt10_write_port0(8'h1b, 8'hff);
                end
                if (preparation != 3)
                    wait (b_chon === 1'b0);
                playback_hash_active = 1'b0;
                first_hash = playback_hash;
                first_count = case_public_samples;
                wait_public(16);
            end
            playback_hash = FNV_OFFSET;
            case_public_samples = 0;
            align_start();
            playback_hash_active = 1'b1;
            bus.jt10_write_port0(8'h10, 8'h80);
            wait (b_chon === 1'b1);
            wait_public(512);
            playback_hash_active = 1'b0;
            s0_first_hash = first_hash;
            s0_restart_hash = playback_hash;
            s0_first_samples = first_count;
            s0_restart_samples = case_public_samples;
            $display("PHASE4AFIX_BASE_RESTART case=%0s run=%0d preparation=%0d first_hash=%016h restart_hash=%016h first_samples=%0d restart_samples=%0d active=%0d eos=%0d decoder=%0d step=%0d interpolation=%0d gain=%0d lane=%0d/%0d final=%0d/%0d stale_samples=%0d first_nonzero=%0d x=%0d",
                case_name, run_id, preparation, first_hash,
                playback_hash, first_count, case_public_samples,
                b_chon, b_flag, decoder_x, decoder_step,
                b_interpolation, b_gain, b_lane_l, b_lane_r,
                snd_left, snd_right, restart_stale_samples,
                restart_first_nonzero, case_x);
            case_audit = 1'b0;
        end
    endtask

    always @(posedge clk) begin : audit_monitor
        logic pre_clk55;
        logic pre_clk;
        logic pre_raw;
        logic pre_logical;
        logic pre_decoder_commit;
        logic pre_cursor_commit;
        logic pre_natural_end;
        logic [23:0] pre_address;
        logic pre_nibble;
        logic [7:0] pre_data;
        logic [3:0] expected_present;
        logic internal_rise;
        logic public_rise;
        integer raw_delta;

        system_cycle = system_cycle + 1;
        pre_clk55 = cen && clk_en_55;
        pre_clk = cen && clk_en;
        pre_raw = adpcmb_roe_n === 1'b0;
        pre_logical = pre_clk55 && b_adv && b_chon &&
                      !b_restart && !b_flag;
        pre_decoder_commit = cen && decoder_adv_pipe[0] && b_chon &&
                             !decoder_need_clear;
        pre_cursor_commit = pre_clk55 &&
                            ((b_restart && b_adv) || (b_chon && b_adv));
        pre_natural_end = pre_clk55 && b_chon && b_adv && !b_repeat &&
                          {adpcmb_addr, b_nibble} ==
                          {b_end, 8'hff, 1'b1};
        pre_address = adpcmb_addr;
        pre_nibble = b_nibble;
        pre_data = adpcmb_data;
        expected_present = pre_nibble ? pre_data[3:0] : pre_data[7:4];

        #1;
        internal_rise = internal_snd_sample && !previous_internal;
        public_rise = snd_sample && !previous_public;

        if (rst || session_start) begin
            previous_public = 1'b0;
            previous_internal = 1'b0;
            previous_chon = 1'b0;
            previous_flag = 1'b0;
            internal_pulses = 0;
            public_width = 0;
            last_public_cycle = -1;
        end else begin
            if (internal_rise)
                internal_pulses = internal_pulses + 1;
            if (public_rise) begin
                public_samples = public_samples + 1;
                if (first_public_internal < 0)
                    first_public_internal = internal_pulses;
                if (!internal_rise)
                    duplicates = duplicates + 1;
                if (last_public_cycle >= 0 &&
                    system_cycle - last_public_cycle != 144)
                    cadence_errors = cadence_errors + 1;
                last_public_cycle = system_cycle;
                if (case_audit) begin
                    case_public_samples = case_public_samples + 1;
                    if ($isunknown(snd_left) ||
                        $isunknown(snd_right) ||
                        $isunknown(internal_snd_left) ||
                        $isunknown(internal_snd_right)) begin
                        if (x_public == 0)
                            $display("PHASE4AFIX_BASE_X_PUBLIC case=%0s cycle=%0d sample=%0d snd=%b/%b internal=%b/%b",
                                case_name, system_cycle,
                                case_public_samples, snd_left, snd_right,
                                internal_snd_left, internal_snd_right);
                        case_x = case_x + 1;
                        x_public = x_public + 1;
                    end
                    if (playback_hash_active)
                        playback_hash = hash_stereo(
                            playback_hash, snd_left, snd_right);
                    if (post_stop_audit) begin
                        post_samples = post_samples + 1;
                        post_hash = hash_stereo(
                            hash_stereo(post_hash,
                                b_interpolation, b_gain),
                            snd_left, snd_right);
                        if (post_samples == 1)
                            checkpoint_1_interpolation = b_interpolation;
                        if (post_samples == 16)
                            checkpoint_16_interpolation = b_interpolation;
                        if (post_samples == 256)
                            checkpoint_256_interpolation = b_interpolation;
                        if (post_samples == 512)
                            checkpoint_512_interpolation = b_interpolation;
                        if (post_samples == 4096) begin
                            checkpoint_4096_interpolation = b_interpolation;
                            checkpoint_4096_gain = b_gain;
                            checkpoint_4096_lane_l = b_lane_l;
                            checkpoint_4096_lane_r = b_lane_r;
                            checkpoint_4096_final_l = snd_left;
                            checkpoint_4096_final_r = snd_right;
                        end
                    end
                end
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

        if (case_audit) begin
            if (b_update && b_on) begin
                start_accept_cycle = system_cycle;
                if ($isunknown(b_update) || $isunknown(b_on) ||
                    $isunknown(b_repeat) || $isunknown(b_reset))
                    case_x = case_x + 1;
            end
            if (b_update && b_reset) begin
                reset_accept_cycle = system_cycle;
                if ($isunknown(b_update) || $isunknown(b_on) ||
                    $isunknown(b_reset))
                    case_x = case_x + 1;
            end
            if (b_chon && !previous_chon)
                active_assert_cycle = system_cycle;
            if (!b_chon && previous_chon)
                active_clear_cycle = system_cycle;
            if (b_flag && !previous_flag)
                eos_cycle = system_cycle;

            if (pre_raw) begin
                case_raw = case_raw + 1;
                case_capture = case_capture + 1;
                last_raw_cycle = system_cycle;
                if (first_raw_cycle < 0)
                    first_raw_cycle = system_cycle;
                raw_hash = hash_u24(raw_hash, pre_address);
                raw_hash = hash_byte(raw_hash, pre_data);
                if ($isunknown(pre_address) || $isunknown(pre_data) ||
                    $isunknown(b_present)) begin
                    case_x = case_x + 1;
                    x_raw = x_raw + 1;
                end
                if (post_stop_audit) begin
                    post_raw = post_raw + 1;
                    post_capture = post_capture + 1;
                    if (last_post_raw_cycle >= 0) begin
                        raw_delta = system_cycle - last_post_raw_cycle;
                        if (raw_delta == 144)
                            raw_interval_144 = raw_interval_144 + 1;
                        else if (raw_delta == 288)
                            raw_interval_288 = raw_interval_288 + 1;
                        else
                            raw_interval_other = raw_interval_other + 1;
                    end
                    last_post_raw_cycle = system_cycle;
                    if (pre_address < {b_start, 8'h00} ||
                        pre_address > {b_end, 8'hff})
                        out_of_range_raw = out_of_range_raw + 1;
                end
            end
            if (pre_raw && b_present !== expected_present) begin
                // din is an always-captured latch.  A mismatch on a raw
                // request is recorded, but never reclassified as consume.
                state_hash = hash_byte(state_hash,
                    {4'hf, b_present});
            end
            if (pre_logical) begin
                case_logical = case_logical + 1;
                last_logical_cycle = system_cycle;
                if (first_logical_cycle < 0)
                    first_logical_cycle = system_cycle;
                logical_hash = hash_u24(logical_hash, pre_address);
                logical_hash = hash_byte(logical_hash,
                    {3'd0, pre_nibble, b_present});
                if ($isunknown(pre_address) ||
                    $isunknown(pre_nibble) || $isunknown(b_present) ||
                    $isunknown(b_delta_count) || $isunknown(b_adv)) begin
                    case_x = case_x + 1;
                    x_logical = x_logical + 1;
                end
                if (post_stop_audit)
                    post_logical = post_logical + 1;
            end
            if (pre_decoder_commit) begin
                case_decoder_commit = case_decoder_commit + 1;
                last_decoder_cycle = system_cycle;
                state_hash = hash_u16(state_hash, decoder_x);
                state_hash = hash_u16(state_hash, decoder_step);
                if ($isunknown(decoder_x) ||
                    $isunknown(decoder_step) ||
                    $isunknown(decoder_adv_pipe)) begin
                    case_x = case_x + 1;
                    x_decoder = x_decoder + 1;
                end
                if (post_stop_audit)
                    post_decoder_commit = post_decoder_commit + 1;
            end
            if (pre_clk55) begin
                case_delta_commit = case_delta_commit + 1;
                case_gain_commit = case_gain_commit + 1;
                case_lane_commit = case_lane_commit + 1;
                if ($isunknown(b_delta_count) || $isunknown(b_adv)) begin
                    case_x = case_x + 1;
                    x_delta = x_delta + 1;
                end
                if ($isunknown(b_gain)) begin
                    case_x = case_x + 1;
                    x_gain = x_gain + 1;
                end
                if ($isunknown(b_lane_l) || $isunknown(b_lane_r)) begin
                    case_x = case_x + 1;
                    x_lane = x_lane + 1;
                end
                if (post_stop_audit) begin
                    post_gain_commit = post_gain_commit + 1;
                    post_lane_commit = post_lane_commit + 1;
                end
            end
            if (pre_clk55 && b_chon) begin
                case_interpolation_commit =
                    case_interpolation_commit + 1;
                last_interpolation_cycle = system_cycle;
                if ($isunknown(b_interpolation) ||
                    $isunknown(interpolation_last) ||
                    $isunknown(interpolation_step)) begin
                    case_x = case_x + 1;
                    x_interpolation = x_interpolation + 1;
                end
                if (post_stop_audit)
                    post_interpolation_commit =
                        post_interpolation_commit + 1;
            end
            if (pre_cursor_commit) begin
                case_cursor_commit = case_cursor_commit + 1;
                if ($isunknown(pre_address) || $isunknown(pre_nibble))
                    case_x = case_x + 1;
                if (post_stop_audit)
                    post_cursor_commit = post_cursor_commit + 1;
            end
            if (pre_natural_end)
                case_natural_end = case_natural_end + 1;
            if (pre_clk && final_cur_op == 2'd0 &&
                final_cur_ch == 3'd4) begin
                case_acc_commit = case_acc_commit + 1;
                if ($isunknown(acc_input_l) || $isunknown(acc_input_r)) begin
                    case_x = case_x + 1;
                    x_accumulator = x_accumulator + 1;
                end
            end
            if (pre_clk && final_zero) begin
                case_final_publish = case_final_publish + 1;
                if ($isunknown(internal_snd_left) ||
                    $isunknown(internal_snd_right)) begin
                    case_x = case_x + 1;
                    x_final = x_final + 1;
                end
            end
            if (post_stop_audit &&
                ($isunknown(b_chon) || $isunknown(b_flag) ||
                 $isunknown(b_interpolation) || $isunknown(b_gain) ||
                 $isunknown(b_lane_l) || $isunknown(b_lane_r) ||
                 $isunknown(snd_left) || $isunknown(snd_right))) begin
                if (post_x == 0)
                    $display("PHASE4AFIX_BASE_X_POST case=%0s cycle=%0d active=%b eos=%b interpolation=%b gain=%b lane=%b/%b final=%b/%b unknown=%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d",
                        case_name, system_cycle, b_chon, b_flag,
                        b_interpolation, b_gain, b_lane_l, b_lane_r,
                        snd_left, snd_right, $isunknown(b_chon),
                        $isunknown(b_flag), $isunknown(b_interpolation),
                        $isunknown(b_gain), $isunknown(b_lane_l),
                        $isunknown(b_lane_r), $isunknown(snd_left),
                        $isunknown(snd_right));
                post_x = post_x + 1;
            end
            if (adpcma_active != 0 || adpcma_roe_n == 1'b0 ||
                dut.u_jt10.u_jt12.adpcmA_l != 0 ||
                dut.u_jt10.u_jt12.adpcmA_r != 0)
                idle_adpcma = idle_adpcma + 1;
            if (internal_fm_snd != 0)
                idle_fm = idle_fm + 1;
            if (psg_A != 0 || psg_B != 0 || psg_C != 0 || psg_snd != 0)
                idle_ssg = idle_ssg + 1;
        end

        previous_public = snd_sample;
        previous_internal = internal_snd_sample;
        previous_chon = b_chon;
        previous_flag = b_flag;
    end

    jt10_cpu_bus_bfm bus (
        .rst(rst), .clk(clk), .dout(dout),
        .addr(bus_addr), .din(din), .cs_n(cs_n), .wr_n(wr_n),
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
        .addr(dut_addr), .din(din), .cs_n(cs_n), .wr_n(wr_n),
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

    initial begin : phase4afix_inherited_sequence
        if (!$value$plusargs("RUN_ID=%d", run_id))
            run_id = 1;
        if ($test$plusargs("QUICK"))
            quick_mode = 1;
        $display("PHASE4AFIX_BASE_BEGIN run=%0d", run_id);

        repeat (4) @(posedge clk);
        if (quick_mode) begin
            run_natural("N0_P", PATTERN_P, 0, 512);
        end else begin
            run_natural("N0_P", PATTERN_P, 0, 16384);
            run_natural("N0_N", PATTERN_N, 0, 4096);
            run_natural("N0_Z", PATTERN_Z, 0, 4096);
            run_natural("N1_00", PATTERN_P, 1, 4096);
            run_natural("N2_01", PATTERN_P, 2, 16384);
            run_natural("N3_01_00", PATTERN_P, 3, 4096);
            run_natural("N4_LEVEL", PATTERN_P, 4, 4096);
            run_natural("N5_PAN", PATTERN_P, 5, 4096);

            run_midstream("R0_RESET", 0, 16384);
            run_midstream("R1_RESET_00", 1, 4096);
            run_midstream("R2_00", 2, 4096);
            run_midstream("R3_LEVEL", 3, 4096);
            run_midstream("R4_PAN", 4, 4096);

            run_restart("S0_NATURAL", 0);
            run_restart("S1_RESET", 1);
            run_restart("S2_RESET_00", 2);
            run_restart("S3_LEVEL", 3);
        end

        $display("PHASE4AFIX_BASE_TRANSPORT run=%0d writes=%0d port0=%0d port1=%0d busy_min=%0d busy_max=%0d busy_hash=%016h timeout=%0d busy_write=%0d",
            run_id, accepted_write_count, port0_write_count,
            port1_write_count, busy_min_cycles, busy_max_cycles,
            busy_duration_hash, busy_timeout_count,
            busy_while_write_count);
        $display("PHASE4AFIX_BASE_SAMPLE run=%0d first_public_internal=%0d cadence_errors=%0d width_errors=%0d drops=%0d duplicates=%0d idle_adpcma=%0d idle_fm=%0d idle_ssg=%0d",
            run_id, first_public_internal, cadence_errors,
            width_errors, drops, duplicates, idle_adpcma,
            idle_fm, idle_ssg);
        $display("PHASE4AFIX_BASE_CLASS run=%0d local_output=HOLD local_request=RAW_ONLY output_disable=NONE failures=%0d",
            run_id, failures);
        if (failures == 0 && busy_timeout_count == 0 &&
            busy_while_write_count == 0 && cadence_errors == 0 &&
            width_errors == 0 && drops == 0 && duplicates == 0) begin
            $display("PHASE4AFIX_BASE_PASS run=%0d", run_id);
            $finish;
        end
        $fatal(1, "PHASE4AFIX_BASE_FAIL run=%0d failures=%0d", run_id,
               failures);
    end
endmodule

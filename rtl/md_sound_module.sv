// Minimal Mega Drive sound module experiment.
//
// This module is intended to sit between a VGM sequencer and the
// Genesis_MiSTer sound cores:
//
//   VGM 0x52 / 0x53 commands -> jt12 YM2612/YM3438 bus
//   VGM 0x50 commands        -> jt89 SN76489/PSG bus
//
// It deliberately does not include HPS, OSD, file loading, or a VGM parser.
// The caller is expected to decode VGM commands and present one command at a
// time through the simple valid/data inputs below.
//
// External HDL dependencies from Genesis_MiSTer:
//   - rtl/jt12/jt12.v and its jt12.qip dependencies
//   - rtl/jt89/jt89.v and its jt89.qip dependencies
//   - rtl/jt12/mixer/jt12_genmix.v and mixer dependencies
//   - rtl/genesis_lpf.v and rtl/audio_iir_filter.v
//
// TODO: Add small FIFOs if the VGM sequencer can issue commands while ready is
// low. For now, the caller should only assert *_cmd_valid when *_cmd_ready is 1.

module md_sound_module
(
    input  logic              clk,
    input  logic              reset,

    // YM2612 command input.
    //
    // ym_cmd_port maps directly from the VGM command:
    //   0: VGM 0x52, YM2612 port 0
    //   1: VGM 0x53, YM2612 port 1
    //
    // Each command becomes two jt12 writes:
    //   address write, then data write.
    input  logic              ym_cmd_valid,
    input  logic              ym_cmd_port,
    input  logic        [7:0] ym_cmd_reg,
    input  logic        [7:0] ym_cmd_data,

    // SN76489 command input.
    //
    // This maps from VGM 0x50. The command byte is written directly to jt89.
    input  logic              psg_cmd_valid,
    input  logic        [7:0] psg_cmd_data,

    // The sequencer should only present a new command when the matching ready
    // signal is high. No command FIFO is implemented in this minimal version.
    output logic              ym_cmd_ready,
    output logic              psg_cmd_ready,

	    // Signed 16-bit stereo audio, suitable for MiSTer-style AUDIO_L/R.
	    output signed      [15:0] audio_l,
	    output signed      [15:0] audio_r,

	    // Pulses when a new jt12 FM sample is available after the startup guard.
	    // Testbenches can use this as a practical audio dump strobe.
	    output logic              audio_sample_valid,
	    input  logic        [1:0] audio_lpf_mode,
	    input  logic              audio_gain_boost,
	    input  logic        [1:0] audio_psg_level,

	    // Upstream mix diagnostics. These counters saturate at 16'hffff.
	    output logic       [15:0] fm_adjust_clip_count_l,
	    output logic       [15:0] fm_adjust_clip_count_r,
	    output logic       [15:0] genmix_wrap_count_l,
	    output logic       [15:0] genmix_wrap_count_r,
	    output logic       [31:0] ym_write_requested_count,
	    output logic       [31:0] ym_write_accepted_count,
	    output logic       [31:0] ym_write_dropped_or_busy_count,
	    output logic       [31:0] ym_port0_count,
	    output logic       [31:0] ym_port1_count,
	    output logic              last_ym_port,
	    output logic        [7:0] last_ym_addr,
	    output logic        [7:0] last_ym_data,
	    output logic       [15:0] jt12_cen_interval_1_count,
	    output logic       [15:0] jt12_cen_interval_2_count,
	    output logic       [15:0] jt12_cen_interval_3_count,
	    output logic       [15:0] jt12_cen_interval_4_count,
	    output logic       [15:0] jt12_cen_interval_ge5_count,
	    output logic        [7:0] jt12_cen_interval_min,
	    output logic        [7:0] jt12_cen_interval_max,
	    output logic        [7:0] jt12_cen_interval_last,
	    output logic       [15:0] fm_raw_abs_peak,
	    output logic       [15:0] fm_adjust_abs_peak,
	    output logic       [15:0] fm_lpf_abs_peak,
	    output logic       [15:0] genmix_abs_peak,
	    output logic       [15:0] final_audio_abs_peak
	);

`ifdef MD_YM_WRITE_SLOW_TEST
    localparam bit MD_YM_WRITE_SLOW_BUILD = 1'b1;
    localparam logic [7:0] YM_EXTRA_WRITE_GAP_CYCLES = 8'd32;
`else
    localparam bit MD_YM_WRITE_SLOW_BUILD = 1'b0;
    localparam logic [7:0] YM_EXTRA_WRITE_GAP_CYCLES = 8'd0;
`endif

    function automatic [15:0] md_audio_abs16(input logic signed [15:0] value);
        md_audio_abs16 = value[15] ? (~value + 16'd1) : value;
    endfunction

    function automatic [15:0] md_audio_abs_max16(
        input logic signed [15:0] left,
        input logic signed [15:0] right
    );
        logic [15:0] left_abs;
        logic [15:0] right_abs;
        begin
            left_abs = md_audio_abs16(left);
            right_abs = md_audio_abs16(right);
            md_audio_abs_max16 = (left_abs > right_abs) ? left_abs : right_abs;
        end
    endfunction

    function automatic signed [15:0] md_audio_sat21(input logic signed [20:0] value);
        begin
            if (value > 21'sd32767) begin
                md_audio_sat21 = 16'sd32767;
            end else if (value < -21'sd32768) begin
                md_audio_sat21 = -16'sd32768;
            end else begin
                md_audio_sat21 = value[15:0];
            end
        end
    endfunction

`ifdef MD_YM_FORCE_LFO_OFF_TEST
    localparam bit MD_YM_FORCE_LFO_OFF_BUILD = 1'b1;
`else
    localparam bit MD_YM_FORCE_LFO_OFF_BUILD = 1'b0;
`endif

`ifdef MD_YM_MASK_PMS_AMS_TEST
    localparam bit MD_YM_MASK_PMS_AMS_BUILD = 1'b1;
`else
    localparam bit MD_YM_MASK_PMS_AMS_BUILD = 1'b0;
`endif

`ifdef MD_YM_CH3_NORMAL_TEST
    localparam bit MD_YM_CH3_NORMAL_BUILD = 1'b1;
`else
    localparam bit MD_YM_CH3_NORMAL_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_ONLY_TEST
    localparam bit MD_AUDIO_FM_ONLY_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_FM_ONLY_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_FORCE_MUTE_TEST
    localparam bit MD_AUDIO_FM_FORCE_MUTE_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_FM_FORCE_MUTE_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_PSG_ONLY_TEST
    localparam bit MD_AUDIO_PSG_ONLY_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_PSG_ONLY_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_CH1_ONLY_TEST
    localparam bit MD_AUDIO_FM_CH_SOLO_BUILD = 1'b1;
    localparam logic [2:0] MD_AUDIO_FM_CH_SOLO_KEYON_CH = 3'd0;
`elsif MD_AUDIO_FM_CH2_ONLY_TEST
    localparam bit MD_AUDIO_FM_CH_SOLO_BUILD = 1'b1;
    localparam logic [2:0] MD_AUDIO_FM_CH_SOLO_KEYON_CH = 3'd1;
`elsif MD_AUDIO_FM_CH3_ONLY_TEST
    localparam bit MD_AUDIO_FM_CH_SOLO_BUILD = 1'b1;
    localparam logic [2:0] MD_AUDIO_FM_CH_SOLO_KEYON_CH = 3'd2;
`elsif MD_AUDIO_FM_CH4_ONLY_TEST
    localparam bit MD_AUDIO_FM_CH_SOLO_BUILD = 1'b1;
    localparam logic [2:0] MD_AUDIO_FM_CH_SOLO_KEYON_CH = 3'd4;
`elsif MD_AUDIO_FM_CH5_ONLY_TEST
    localparam bit MD_AUDIO_FM_CH_SOLO_BUILD = 1'b1;
    localparam logic [2:0] MD_AUDIO_FM_CH_SOLO_KEYON_CH = 3'd5;
`elsif MD_AUDIO_FM_CH6_ONLY_TEST
    localparam bit MD_AUDIO_FM_CH_SOLO_BUILD = 1'b1;
    localparam logic [2:0] MD_AUDIO_FM_CH_SOLO_KEYON_CH = 3'd6;
`else
    localparam bit MD_AUDIO_FM_CH_SOLO_BUILD = 1'b0;
    localparam logic [2:0] MD_AUDIO_FM_CH_SOLO_KEYON_CH = 3'd0;
`endif

`ifdef MD_AUDIO_PREMIX_ATTENUATE_FM_6DB
    localparam bit MD_AUDIO_PREMIX_ATTENUATE_FM_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_PREMIX_ATTENUATE_FM_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_ADJUST_BYPASS_TEST
    localparam bit MD_AUDIO_FM_ADJUST_BYPASS_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_FM_ADJUST_BYPASS_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_ADJUST_LOW_GAIN_TEST
    localparam bit MD_AUDIO_FM_ADJUST_LOW_GAIN_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_FM_ADJUST_LOW_GAIN_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_ADJUST_SATURATE_TEST
    localparam bit MD_AUDIO_FM_ADJUST_SATURATE_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_FM_ADJUST_SATURATE_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_PREMIX_ATTENUATE_PSG_6DB
    localparam bit MD_AUDIO_PREMIX_ATTENUATE_PSG_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_PREMIX_ATTENUATE_PSG_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_PSG_MEGADRIVE_GAIN_TEST
    localparam bit MD_AUDIO_PSG_MEGADRIVE_GAIN_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_PSG_MEGADRIVE_GAIN_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_PSG_ATTEN_075_TEST
    localparam bit MD_AUDIO_PSG_ATTEN_075_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_PSG_ATTEN_075_BUILD = 1'b0;
`endif

`ifdef MD_PSG_CEN_LEGACY_DIV15_TEST
    localparam bit MD_PSG_CEN_LEGACY_DIV15_BUILD = 1'b1;
`else
    localparam bit MD_PSG_CEN_LEGACY_DIV15_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_RAW_JT12_FM_TEST
    localparam bit MD_AUDIO_RAW_JT12_FM_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_RAW_JT12_FM_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_RAW_JT12_SAMPLE_LATCH_TEST
    localparam bit MD_AUDIO_RAW_JT12_SAMPLE_LATCH_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_RAW_JT12_SAMPLE_LATCH_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_NORMAL_SAMPLE_LATCH_TEST
    localparam bit MD_AUDIO_NORMAL_SAMPLE_LATCH_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_NORMAL_SAMPLE_LATCH_BUILD = 1'b0;
`endif

`ifdef MD_JT12_CEN_NTSC_TEST
    localparam bit MD_JT12_CEN_NTSC_BUILD = 1'b1;
`else
    localparam bit MD_JT12_CEN_NTSC_BUILD = 1'b0;
`endif

`ifdef MD_JT12_CEN_EVERY_CLK_TEST
    localparam bit MD_JT12_CEN_EVERY_CLK_BUILD = 1'b1;
`else
    localparam bit MD_JT12_CEN_EVERY_CLK_BUILD = 1'b0;
`endif

`ifdef MD_JT12_CEN_UNIFORM_10MHZ_TEST
    localparam bit MD_JT12_CEN_UNIFORM_10MHZ_BUILD = 1'b1;
`else
    localparam bit MD_JT12_CEN_UNIFORM_10MHZ_BUILD = 1'b0;
`endif

`ifdef MD_JT12_CEN_UNIFORM_6P67MHZ_TEST
    localparam bit MD_JT12_CEN_UNIFORM_6P67MHZ_BUILD = 1'b1;
`else
    localparam bit MD_JT12_CEN_UNIFORM_6P67MHZ_BUILD = 1'b0;
`endif

`ifdef MD_JT12_LADDER_EFFECT_TEST
    localparam bit MD_JT12_LADDER_EFFECT_BUILD = 1'b1;
`else
    localparam bit MD_JT12_LADDER_EFFECT_BUILD = 1'b0;
`endif

`ifdef MD_JT12_FORCE_YM2612_TEST
    localparam bit MD_JT12_FORCE_YM2612_BUILD = 1'b1;
`else
    localparam bit MD_JT12_FORCE_YM2612_BUILD = 1'b0;
`endif

`ifdef MD_JT12_FORCE_YM3438_TEST
    localparam bit MD_JT12_FORCE_YM3438_BUILD = 1'b1;
`else
    localparam bit MD_JT12_FORCE_YM3438_BUILD = 1'b0;
`endif

`ifdef MD_JT12_FORCE_LADDER_ON_TEST
    localparam bit MD_JT12_FORCE_LADDER_ON_BUILD = 1'b1;
`else
    localparam bit MD_JT12_FORCE_LADDER_ON_BUILD = 1'b0;
`endif

`ifdef MD_JT12_FORCE_LADDER_OFF_TEST
    localparam bit MD_JT12_FORCE_LADDER_OFF_BUILD = 1'b1;
`else
    localparam bit MD_JT12_FORCE_LADDER_OFF_BUILD = 1'b0;
`endif

`ifdef MD_JT12_HIFI_PCM_TEST
    localparam bit MD_JT12_HIFI_PCM_BUILD = 1'b1;
`else
    localparam bit MD_JT12_HIFI_PCM_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_FM_DC_BLOCK_TEST
    localparam bit MD_AUDIO_FM_DC_BLOCK_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_FM_DC_BLOCK_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_PRE_GENMIX_FM_LPF_TEST
    localparam bit MD_AUDIO_PRE_GENMIX_FM_LPF_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_PRE_GENMIX_FM_LPF_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_POST_FM_LPF_GAIN_TEST
    localparam bit MD_AUDIO_POST_FM_LPF_GAIN_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_POST_FM_LPF_GAIN_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_GENMIX_OUTPUT_GAIN_2X_TEST
    localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_2X_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_2X_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_GENMIX_OUTPUT_GAIN_4X_TEST
    localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_4X_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_4X_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_GENMIX_OUTPUT_GAIN_6X_TEST
    localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_6X_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_6X_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_GENMIX_OUTPUT_GAIN_8X_TEST
    localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_8X_BUILD = 1'b1;
`else
    localparam bit MD_AUDIO_GENMIX_OUTPUT_GAIN_8X_BUILD = 1'b0;
`endif

`ifdef MD_AUDIO_LPF_MODEL1_TEST
    localparam logic [1:0] MD_AUDIO_LPF_MODE = 2'b00;
`elsif MD_AUDIO_LPF_MODEL2_TEST
    localparam logic [1:0] MD_AUDIO_LPF_MODE = 2'b01;
`elsif MD_AUDIO_LPF_MINIMAL_TEST
    localparam logic [1:0] MD_AUDIO_LPF_MODE = 2'b10;
`else
    localparam logic [1:0] MD_AUDIO_LPF_MODE = 2'b11;
`endif

`ifdef MD_AUDIO_LPF_OSD_TEST
    wire [1:0] md_audio_lpf_mode_selected = audio_lpf_mode;
`else
    wire [1:0] md_audio_lpf_mode_selected = MD_AUDIO_LPF_MODE;
`endif

    //----------------------------------------------------------------------
    // Clock enables
    //----------------------------------------------------------------------
    // Genesis_MiSTer uses a master clock around 53.693 MHz for NTSC and then
    // derives audio chip enables from it:
    //
    //   FM_CLKEN  ~= MCLK / 7   -> about 7.67 MHz, YM2612/YM3438
    //   PSG_CLKEN ~= MCLK / 15  -> about 3.58 MHz, SN76489
    //
    // This module assumes clk is the same kind of master clock. If clk is a
    // different frequency, these enables will no longer represent real Mega
    // Drive chip timing.

    logic [2:0]  fm_clk_cnt;
    logic        fm_clken;
    logic [23:0] fm_cen_accum;

    // Hardware A/B only: approximate the Mega Drive NTSC YM2612 input enable
    // from the current 20 MHz clk_sys. 53.693175 MHz / 7 ~= 7.670454 MHz.
    localparam logic [24:0] JT12_NTSC_CEN_INC = 25'd6434443;
    wire [24:0] jt12_ntsc_cen_sum =
        {1'b0, fm_cen_accum} + JT12_NTSC_CEN_INC;

    always_ff @(posedge clk) begin
        if (reset) begin
            fm_clk_cnt <= 3'd0;
            fm_clken   <= 1'b1;
            fm_cen_accum <= 24'd0;
        end else begin
            fm_clken <= 1'b0;
            if (MD_JT12_CEN_EVERY_CLK_BUILD) begin
                fm_clken   <= 1'b1;
            end else if (MD_JT12_CEN_UNIFORM_10MHZ_BUILD) begin
                if (fm_clk_cnt == 3'd1) begin
                    fm_clk_cnt <= 3'd0;
                    fm_clken   <= 1'b1;
                end else begin
                    fm_clk_cnt <= fm_clk_cnt + 3'd1;
                end
            end else if (MD_JT12_CEN_UNIFORM_6P67MHZ_BUILD) begin
                if (fm_clk_cnt == 3'd2) begin
                    fm_clk_cnt <= 3'd0;
                    fm_clken   <= 1'b1;
                end else begin
                    fm_clk_cnt <= fm_clk_cnt + 3'd1;
                end
            end else if (MD_JT12_CEN_NTSC_BUILD) begin
                fm_cen_accum <= jt12_ntsc_cen_sum[23:0];
                fm_clken     <= jt12_ntsc_cen_sum[24];
            end else begin
                if (fm_clk_cnt == 3'd6) begin
                    fm_clk_cnt <= 3'd0;
                    fm_clken   <= 1'b1;
                end else begin
                    fm_clk_cnt <= fm_clk_cnt + 3'd1;
                end
            end
        end
    end

    logic [7:0] jt12_cen_interval_counter;
    logic       jt12_cen_seen_first;

    always_ff @(posedge clk) begin
        if (reset) begin
            jt12_cen_interval_counter <= 8'd0;
            jt12_cen_seen_first       <= 1'b0;
            jt12_cen_interval_1_count <= 16'd0;
            jt12_cen_interval_2_count <= 16'd0;
            jt12_cen_interval_3_count <= 16'd0;
            jt12_cen_interval_4_count <= 16'd0;
            jt12_cen_interval_ge5_count <= 16'd0;
            jt12_cen_interval_min     <= 8'hff;
            jt12_cen_interval_max     <= 8'd0;
            jt12_cen_interval_last    <= 8'd0;
        end else if (fm_clken) begin
            jt12_cen_interval_last <= jt12_cen_interval_counter;
            jt12_cen_interval_counter <= 8'd1;

            if (!jt12_cen_seen_first) begin
                jt12_cen_seen_first <= 1'b1;
            end else begin
                if (jt12_cen_interval_counter < jt12_cen_interval_min) begin
                    jt12_cen_interval_min <= jt12_cen_interval_counter;
                end
                if (jt12_cen_interval_counter > jt12_cen_interval_max) begin
                    jt12_cen_interval_max <= jt12_cen_interval_counter;
                end

                unique case (jt12_cen_interval_counter)
                    8'd1: if (!(&jt12_cen_interval_1_count)) jt12_cen_interval_1_count <= jt12_cen_interval_1_count + 16'd1;
                    8'd2: if (!(&jt12_cen_interval_2_count)) jt12_cen_interval_2_count <= jt12_cen_interval_2_count + 16'd1;
                    8'd3: if (!(&jt12_cen_interval_3_count)) jt12_cen_interval_3_count <= jt12_cen_interval_3_count + 16'd1;
                    8'd4: if (!(&jt12_cen_interval_4_count)) jt12_cen_interval_4_count <= jt12_cen_interval_4_count + 16'd1;
                    default: if (!(&jt12_cen_interval_ge5_count)) jt12_cen_interval_ge5_count <= jt12_cen_interval_ge5_count + 16'd1;
                endcase
            end
        end else if (jt12_cen_interval_counter != 8'hff) begin
            jt12_cen_interval_counter <= jt12_cen_interval_counter + 8'd1;
        end
    end

    //----------------------------------------------------------------------
    // jt12 reset stretcher
    //----------------------------------------------------------------------
    // jt12.v documents that reset must remain asserted for at least
    // 6 clk&cen cycles. The external reset may be shorter than that, so after
    // external reset is released we keep jt12 in reset for 8 FM_CLKEN pulses.

    logic       jt12_reset;
    logic [3:0] jt12_reset_cen_count;

    always_ff @(posedge clk) begin
        if (reset) begin
            jt12_reset           <= 1'b1;
            jt12_reset_cen_count <= 4'd0;
        end else if (jt12_reset) begin
            if (fm_clken) begin
                if (jt12_reset_cen_count == 4'd7) begin
                    jt12_reset <= 1'b0;
                end else begin
                    jt12_reset_cen_count <= jt12_reset_cen_count + 4'd1;
                end
            end
        end
    end

    logic [3:0]  psg_clk_cnt;
    logic        psg_clken;
    logic [23:0] psg_cen_accum;

    // Approximate the Mega Drive NTSC SN76489 input enable from the current
    // 20 MHz clk_sys. Target: 3,579,545 Hz.
    localparam logic [24:0] JT89_NTSC_CEN_INC = 25'd3002740;
    wire [24:0] jt89_ntsc_cen_sum =
        {1'b0, psg_cen_accum} + JT89_NTSC_CEN_INC;

    always_ff @(posedge clk) begin
        if (reset) begin
            psg_clk_cnt   <= 4'd0;
            psg_clken     <= 1'b0;
            psg_cen_accum <= 24'd0;
        end else begin
            psg_clken <= 1'b0;
            if (MD_PSG_CEN_LEGACY_DIV15_BUILD) begin
                if (psg_clk_cnt == 4'd14) begin
                    psg_clk_cnt <= 4'd0;
                    psg_clken   <= 1'b1;
                end else begin
                    psg_clk_cnt <= psg_clk_cnt + 4'd1;
                end
            end else begin
                psg_cen_accum <= jt89_ntsc_cen_sum[23:0];
                psg_clken     <= jt89_ntsc_cen_sum[24];
            end
        end
    end

    //----------------------------------------------------------------------
    // YM2612/YM3438 command adapter
    //----------------------------------------------------------------------
    // jt12 exposes a simple 8-bit bus:
    //
    //   addr 0: port 0 address
    //   addr 1: port 0 data
    //   addr 2: port 1 address
    //   addr 3: port 1 data
    //
    // A VGM YM command already contains "port, register, data", so this FSM
    // converts one VGM command into the two required jt12 bus writes.

	    typedef enum logic [3:0] {
	        YM_IDLE,
	        YM_ADDR_SETUP,
	        YM_ADDR_WAIT_CEN,
	        YM_ADDR_RELEASE,
	        YM_ADDR_GAP,
	        YM_DATA_SETUP,
	        YM_DATA_WAIT_CEN,
	        YM_DATA_RELEASE,
        YM_BUSY_WAIT
    } ym_state_t;

    ym_state_t ym_state;

	    logic       ym_pending_port;
	    logic [7:0] ym_pending_reg;
	    logic [7:0] ym_pending_data;
	    logic [7:0] ym_extra_gap_count;

    logic [1:0] jt12_addr;
    logic [7:0] jt12_din;
    logic       jt12_wr_n;
    wire  [7:0] jt12_dout;

    wire ym_filter_lfo_off =
        MD_YM_FORCE_LFO_OFF_BUILD && !ym_cmd_port && (ym_cmd_reg == 8'h22);
    wire ym_filter_pms_ams =
        MD_YM_MASK_PMS_AMS_BUILD &&
        ((ym_cmd_reg == 8'hB4) || (ym_cmd_reg == 8'hB5) ||
         (ym_cmd_reg == 8'hB6));
    wire ym_filter_ch3_mode =
        MD_YM_CH3_NORMAL_BUILD && !ym_cmd_port && (ym_cmd_reg == 8'h27);
    wire ym_filter_fm_ch_solo_keyon =
        MD_AUDIO_FM_CH_SOLO_BUILD && !ym_cmd_port && (ym_cmd_reg == 8'h28) &&
        (ym_cmd_data[2:0] != MD_AUDIO_FM_CH_SOLO_KEYON_CH);
    wire [7:0] ym_cmd_data_filtered =
        ym_filter_lfo_off ? 8'h00 :
        ym_filter_pms_ams ? (ym_cmd_data & 8'hC0) :
        ym_filter_ch3_mode ? (ym_cmd_data & 8'h3F) :
        ym_filter_fm_ch_solo_keyon ? {4'h0, ym_cmd_data[3:0]} :
                              ym_cmd_data;

`ifdef SIMULATION
    logic [15:0] ym_wait_cen_count;
`endif

    assign ym_cmd_ready = (ym_state == YM_IDLE) && !jt12_reset;

    always_ff @(posedge clk) begin
        if (reset || jt12_reset) begin
            ym_state        <= YM_IDLE;
	            ym_pending_port <= 1'b0;
	            ym_pending_reg  <= 8'h00;
	            ym_pending_data <= 8'h00;
	            ym_extra_gap_count <= 8'd0;
	            jt12_addr       <= 2'd0;
	            jt12_din        <= 8'h00;
	            jt12_wr_n       <= 1'b1;
	            ym_write_requested_count <= 32'd0;
	            ym_write_accepted_count <= 32'd0;
	            ym_write_dropped_or_busy_count <= 32'd0;
	            ym_port0_count <= 32'd0;
	            ym_port1_count <= 32'd0;
	            last_ym_port <= 1'b0;
	            last_ym_addr <= 8'd0;
	            last_ym_data <= 8'd0;
`ifdef SIMULATION
	            ym_wait_cen_count <= 16'd0;
`endif
	        end else begin
	            if (ym_cmd_valid) begin
	                ym_write_requested_count <= ym_write_requested_count + 32'd1;
	                if (ym_cmd_ready) begin
	                    ym_write_accepted_count <= ym_write_accepted_count + 32'd1;
	                    if (ym_cmd_port) begin
	                        ym_port1_count <= ym_port1_count + 32'd1;
	                    end else begin
	                        ym_port0_count <= ym_port0_count + 32'd1;
	                    end
	                    last_ym_port <= ym_cmd_port;
	                    last_ym_addr <= ym_cmd_reg;
	                    last_ym_data <= ym_cmd_data;
	                end else begin
	                    ym_write_dropped_or_busy_count <=
	                        ym_write_dropped_or_busy_count + 32'd1;
	                end
	            end

	            unique case (ym_state)
                YM_IDLE: begin
                    jt12_wr_n <= 1'b1;
                    if (ym_cmd_valid && ym_cmd_ready) begin
                        ym_pending_port <= ym_cmd_port;
                        ym_pending_reg  <= ym_cmd_reg;
                        ym_pending_data <= ym_cmd_data_filtered;

                        // First write: select register on the chosen port.
                        // Keep addr/din stable before asserting wr_n, matching the
                        // official JT12 Verilator writer's bus ordering.
                        jt12_addr <= ym_cmd_port ? 2'd2 : 2'd0;
                        jt12_din  <= ym_cmd_reg;
                        ym_state  <= YM_ADDR_SETUP;
`ifdef SIMULATION
`ifdef VERBOSE_TB_LOG
                        ym_wait_cen_count <= 16'd0;
                        $display("YM_CMD_ACCEPT time=%0t port=%0d reg=%02h data=%02h filtered=%02h",
                                 $time, ym_cmd_port, ym_cmd_reg, ym_cmd_data,
                                 ym_cmd_data_filtered);
`endif
`endif
                    end
                end

                YM_ADDR_SETUP: begin
                    jt12_wr_n <= 1'b0;
                    ym_state  <= YM_ADDR_WAIT_CEN;
                end

                // Hold wr_n low until a JT12 input cen pulse has occurred. This
                // prevents a one-master-clock write from being missed by internal
                // JT12 logic that advances on its generated enables.
                YM_ADDR_WAIT_CEN: begin
                    jt12_wr_n <= 1'b0;
                    if (fm_clken) begin
                        ym_state <= YM_ADDR_RELEASE;
`ifdef SIMULATION
`ifdef VERBOSE_TB_LOG
                        $display("YM_BUS_WRITE time=%0t phase=addr port=%0d addr=%0d din=%02h wait_cen_cycles=%0d",
                                 $time, ym_pending_port, jt12_addr, jt12_din,
                                 ym_wait_cen_count);
`endif
                        ym_wait_cen_count <= 16'd0;
`endif
                    end else begin
`ifdef SIMULATION
                        ym_wait_cen_count <= ym_wait_cen_count + 16'd1;
`endif
                    end
                end

	                YM_ADDR_RELEASE: begin
	                    jt12_wr_n <= 1'b1;
	                    jt12_addr <= ym_pending_port ? 2'd3 : 2'd1;
	                    jt12_din  <= ym_pending_data;
	                    if (MD_YM_WRITE_SLOW_BUILD) begin
	                        ym_extra_gap_count <= YM_EXTRA_WRITE_GAP_CYCLES;
	                        ym_state <= YM_ADDR_GAP;
	                    end else begin
	                        ym_state <= YM_DATA_SETUP;
	                    end
	                end

	                YM_ADDR_GAP: begin
	                    jt12_wr_n <= 1'b1;
	                    if (ym_extra_gap_count == 8'd0) begin
	                        ym_state <= YM_DATA_SETUP;
	                    end else begin
	                        ym_extra_gap_count <= ym_extra_gap_count - 8'd1;
	                    end
	                end

	                YM_DATA_SETUP: begin
                    jt12_wr_n <= 1'b0;
                    ym_state  <= YM_DATA_WAIT_CEN;
                end

                YM_DATA_WAIT_CEN: begin
                    jt12_wr_n <= 1'b0;
                    if (fm_clken) begin
                        ym_state <= YM_DATA_RELEASE;
`ifdef SIMULATION
`ifdef VERBOSE_TB_LOG
                        $display("YM_BUS_WRITE time=%0t phase=data port=%0d addr=%0d din=%02h wait_cen_cycles=%0d",
                                 $time, ym_pending_port, jt12_addr, jt12_din,
                                 ym_wait_cen_count);
                        if (ym_pending_reg == 8'h28) begin
                            $display("YM_KEYON_WRITE time=%0t data=%02h", $time,
                                     ym_pending_data);
                        end
`endif
                        ym_wait_cen_count <= 16'd0;
`endif
                    end else begin
`ifdef SIMULATION
                        ym_wait_cen_count <= ym_wait_cen_count + 16'd1;
`endif
                    end
                end

                YM_DATA_RELEASE: begin
                    jt12_wr_n <= 1'b1;
                    jt12_addr <= 2'd0; // official testbench reads status here
                    ym_state  <= YM_BUSY_WAIT;
                end

                YM_BUSY_WAIT: begin
                    jt12_wr_n <= 1'b1;
                    jt12_addr <= 2'd0;
                    if (!jt12_dout[7]) begin
                        ym_state <= YM_IDLE;
`ifdef SIMULATION
`ifdef VERBOSE_TB_LOG
                        $display("YM_BUSY_CLEAR time=%0t", $time);
`endif
`endif
                    end
                end

                default: begin
                    ym_state  <= YM_IDLE;
                    jt12_wr_n <= 1'b1;
                end
            endcase
        end
    end

    //----------------------------------------------------------------------
    // SN76489/PSG command adapter
    //----------------------------------------------------------------------
    // jt89 only needs a data byte and an active-low write pulse.
    //
    // TODO: Add psg_ready or a FIFO if psg_cmd_valid can arrive every cycle.
    // The current version accepts a write when the previous write pulse is not
    // being stretched.

    logic [7:0] jt89_din;
    logic       jt89_wr_n;
    logic       psg_release_pending;

    assign psg_cmd_ready = !reset && !psg_release_pending && jt89_wr_n;

    always_ff @(posedge clk) begin
        if (reset) begin
            jt89_din            <= 8'h00;
            jt89_wr_n           <= 1'b1;
            psg_release_pending <= 1'b0;
        end else begin
            jt89_wr_n <= 1'b1;

            if (psg_release_pending) begin
                psg_release_pending <= 1'b0;
            end else if (psg_cmd_valid && psg_cmd_ready) begin
                jt89_din            <= psg_cmd_data;
                jt89_wr_n           <= 1'b0;
                psg_release_pending <= 1'b1;
            end
        end
    end

    //----------------------------------------------------------------------
    // Sound cores
    //----------------------------------------------------------------------

    wire       jt12_irq_n;
    wire       jt12_sample;

    wire signed [15:0] fm_left;
    wire signed [15:0] fm_right;

    wire jt12_ladder_config =
        MD_JT12_FORCE_LADDER_OFF_BUILD ? 1'b0 :
        MD_JT12_FORCE_LADDER_ON_BUILD  ? 1'b1 :
        MD_JT12_FORCE_YM3438_BUILD     ? 1'b0 :
        MD_JT12_FORCE_YM2612_BUILD     ? 1'b1 :
                                          MD_JT12_LADDER_EFFECT_BUILD;

    wire jt12_hifi_pcm_config = MD_JT12_HIFI_PCM_BUILD;

    jt12 fm
    (
        .rst          (jt12_reset),
        .clk          (clk),
        .cen          (fm_clken),
        .din          (jt12_din),
        .addr         (jt12_addr),
        .cs_n         (1'b0),
        .wr_n         (jt12_wr_n),
        .dout         (jt12_dout),
        .irq_n        (jt12_irq_n),
        .en_hifi_pcm  (jt12_hifi_pcm_config),

        // Local JT12 exposes YM2612/YM3438-style character mainly through the
        // ladder-effect input; explicit A/B macros above make the polarity easy
        // to verify against Genesis_MiSTer.
        .ladder       (jt12_ladder_config),

        .snd_right    (fm_right),
        .snd_left     (fm_left),
        .snd_sample   (jt12_sample)
    );

    wire signed [10:0] psg_sound;
    wire               psg_ready;

    jt89 psg
    (
        .clk    (clk),
        .clk_en (psg_clken),
        .rst    (reset),
        .wr_n   (jt89_wr_n),
        .din    (jt89_din),
        .sound  (psg_sound),
        .ready  (psg_ready)
    );

    //----------------------------------------------------------------------
    // Mix and output filtering
    //----------------------------------------------------------------------
    // The gain adjustment mirrors Genesis_MiSTer system.sv before genmix.

	    logic signed [15:0] fm_dc_prev_l;
	    logic signed [15:0] fm_dc_prev_r;
	    wire signed [16:0] fm_dc_diff_l =
	        {fm_left[15], fm_left} - {fm_dc_prev_l[15], fm_dc_prev_l};
	    wire signed [16:0] fm_dc_diff_r =
	        {fm_right[15], fm_right} - {fm_dc_prev_r[15], fm_dc_prev_r};
	    wire signed [15:0] fm_dc_block_l = fm_dc_diff_l >>> 1;
	    wire signed [15:0] fm_dc_block_r = fm_dc_diff_r >>> 1;

	    always_ff @(posedge clk) begin
	        if (reset) begin
	            fm_dc_prev_l <= 16'sd0;
	            fm_dc_prev_r <= 16'sd0;
	        end else if (jt12_sample) begin
	            fm_dc_prev_l <= fm_left;
	            fm_dc_prev_r <= fm_right;
	        end
	    end

	    wire signed [15:0] fm_dc_source_l =
	        MD_AUDIO_FM_DC_BLOCK_BUILD ? fm_dc_block_l : fm_left;
	    wire signed [15:0] fm_dc_source_r =
	        MD_AUDIO_FM_DC_BLOCK_BUILD ? fm_dc_block_r : fm_right;

	    wire signed [15:0] fm_pre_l =
	        MD_AUDIO_PREMIX_ATTENUATE_FM_BUILD ? (fm_dc_source_l >>> 1) : fm_dc_source_l;
	    wire signed [15:0] fm_pre_r =
	        MD_AUDIO_PREMIX_ATTENUATE_FM_BUILD ? (fm_dc_source_r >>> 1) : fm_dc_source_r;
	    wire signed [10:0] psg_pre =
	        MD_AUDIO_PREMIX_ATTENUATE_PSG_BUILD ? (psg_sound >>> 1) : psg_sound;
	    wire signed [21:0] fm_pre_l_wide = {{6{fm_pre_l[15]}}, fm_pre_l};
	    wire signed [21:0] fm_pre_r_wide = {{6{fm_pre_r[15]}}, fm_pre_r};

	    wire signed [21:0] fm_adjust_l_wide =
	        (fm_pre_l_wide <<< 4) +
	        (fm_pre_l_wide <<< 2) +
	        (fm_pre_l_wide <<< 1) +
	        (fm_pre_l_wide >>> 2);
	    wire signed [21:0] fm_adjust_r_wide =
	        (fm_pre_r_wide <<< 4) +
	        (fm_pre_r_wide <<< 2) +
	        (fm_pre_r_wide <<< 1) +
	        (fm_pre_r_wide >>> 2);

	    localparam signed [21:0] MIX_INT16_MAX = 22'sd32767;
	    localparam signed [21:0] MIX_INT16_MIN = -22'sd32768;

	    wire fm_adjust_clip_l =
	        (fm_adjust_l_wide > MIX_INT16_MAX) ||
	        (fm_adjust_l_wide < MIX_INT16_MIN);
	    wire fm_adjust_clip_r =
	        (fm_adjust_r_wide > MIX_INT16_MAX) ||
	        (fm_adjust_r_wide < MIX_INT16_MIN);

	    wire signed [15:0] fm_adjust_l_trunc = fm_adjust_l_wide[15:0];
	    wire signed [15:0] fm_adjust_r_trunc = fm_adjust_r_wide[15:0];
	    wire signed [15:0] fm_adjust_l_sat =
	        (fm_adjust_l_wide > MIX_INT16_MAX) ? 16'sd32767 :
	        (fm_adjust_l_wide < MIX_INT16_MIN) ? -16'sd32768 :
	                                             fm_adjust_l_wide[15:0];
	    wire signed [15:0] fm_adjust_r_sat =
	        (fm_adjust_r_wide > MIX_INT16_MAX) ? 16'sd32767 :
	        (fm_adjust_r_wide < MIX_INT16_MIN) ? -16'sd32768 :
	                                             fm_adjust_r_wide[15:0];
	    wire signed [15:0] fm_adjust_l =
	        MD_AUDIO_FM_ADJUST_BYPASS_BUILD ? fm_pre_l :
	        MD_AUDIO_FM_ADJUST_LOW_GAIN_BUILD ? (fm_pre_l >>> 1) :
	        MD_AUDIO_FM_ADJUST_SATURATE_BUILD ? fm_adjust_l_sat :
	                                            fm_adjust_l_trunc;
	    wire signed [15:0] fm_adjust_r =
	        MD_AUDIO_FM_ADJUST_BYPASS_BUILD ? fm_pre_r :
	        MD_AUDIO_FM_ADJUST_LOW_GAIN_BUILD ? (fm_pre_r >>> 1) :
	        MD_AUDIO_FM_ADJUST_SATURATE_BUILD ? fm_adjust_r_sat :
	                                            fm_adjust_r_trunc;

	    wire signed [15:0] fm_pre_genmix_lpf_l;
	    wire signed [15:0] fm_pre_genmix_lpf_r;

	    genesis_fm_lpf pre_genmix_fm_lpf_left
	    (
	        .clk   (clk),
	        .reset (reset),
	        .in    (fm_adjust_l),
	        .out   (fm_pre_genmix_lpf_l)
	    );

	    genesis_fm_lpf pre_genmix_fm_lpf_right
	    (
	        .clk   (clk),
	        .reset (reset),
	        .in    (fm_adjust_r),
	        .out   (fm_pre_genmix_lpf_r)
	    );

	    wire signed [16:0] fm_post_lpf_gain_l_wide =
	        {fm_pre_genmix_lpf_l[15], fm_pre_genmix_lpf_l} <<< 1;
	    wire signed [16:0] fm_post_lpf_gain_r_wide =
	        {fm_pre_genmix_lpf_r[15], fm_pre_genmix_lpf_r} <<< 1;
	    wire signed [15:0] fm_post_lpf_gain_l =
	        (fm_post_lpf_gain_l_wide > 17'sd32767)  ? 16'sd32767  :
	        (fm_post_lpf_gain_l_wide < -17'sd32768) ? -16'sd32768 :
	                                                   fm_post_lpf_gain_l_wide[15:0];
	    wire signed [15:0] fm_post_lpf_gain_r =
	        (fm_post_lpf_gain_r_wide > 17'sd32767)  ? 16'sd32767  :
	        (fm_post_lpf_gain_r_wide < -17'sd32768) ? -16'sd32768 :
	                                                   fm_post_lpf_gain_r_wide[15:0];
	    wire signed [15:0] fm_pre_genmix_lpf_selected_l =
	        MD_AUDIO_POST_FM_LPF_GAIN_BUILD ? fm_post_lpf_gain_l :
	                                          fm_pre_genmix_lpf_l;
	    wire signed [15:0] fm_pre_genmix_lpf_selected_r =
	        MD_AUDIO_POST_FM_LPF_GAIN_BUILD ? fm_post_lpf_gain_r :
	                                          fm_pre_genmix_lpf_r;

	    wire signed [15:0] fm_pre_genmix_l =
	        MD_AUDIO_PRE_GENMIX_FM_LPF_BUILD ? fm_pre_genmix_lpf_selected_l : fm_adjust_l;
	    wire signed [15:0] fm_pre_genmix_r =
	        MD_AUDIO_PRE_GENMIX_FM_LPF_BUILD ? fm_pre_genmix_lpf_selected_r : fm_adjust_r;

	    wire signed [10:0] psg_adjust =
`ifdef MD_AUDIO_PSG_LEVEL_OSD_TEST
	        (audio_psg_level == 2'd0) ? (psg_pre - (psg_pre >>> 2)) :
	        (audio_psg_level == 2'd2) ? (psg_pre + (psg_pre >>> 1)) :
	                                    (psg_pre - (psg_pre >>> 5));
`else
	        MD_AUDIO_PSG_ATTEN_075_BUILD ? (psg_pre - (psg_pre >>> 2)) :
	        MD_AUDIO_PSG_MEGADRIVE_GAIN_BUILD ? (psg_pre + (psg_pre >>> 1)) :
	                                            (psg_pre - (psg_pre >>> 5));
`endif

	    wire fm_path_enabled =
	        !MD_AUDIO_PSG_ONLY_BUILD && !MD_AUDIO_FM_FORCE_MUTE_BUILD;
	    wire psg_path_enabled = !MD_AUDIO_FM_ONLY_BUILD;
	    wire signed [10:0] psg_mixer_snd =
	        psg_path_enabled ? psg_adjust : 11'sd0;

	    //----------------------------------------------------------------------
	    // Audio path startup guard
	    //----------------------------------------------------------------------
	    // jt12 can produce unknown simulation values for a short time while its
	    // internal audio pipeline settles. If those X values enter jt12_genmix,
	    // the interpolation filters keep propagating them. During bring-up, hold
	    // only the FM input to the mixer at zero for a conservative startup delay.

	    localparam int          AUDIO_PATH_ENABLE_DELAY = 4096;
	    localparam logic [12:0] AUDIO_PATH_ENABLE_LAST  = 13'd4095;
	    logic [12:0] audio_path_enable_count;
	    logic        audio_path_enable;

	    always_ff @(posedge clk) begin
	        if (reset) begin
	            audio_path_enable_count <= 13'd0;
	            audio_path_enable       <= 1'b0;
	        end else if (!audio_path_enable) begin
	            if (audio_path_enable_count == AUDIO_PATH_ENABLE_LAST) begin
	                audio_path_enable <= 1'b1;
	            end else begin
	                audio_path_enable_count <= audio_path_enable_count + 13'd1;
	            end
	        end
	    end

	    always_ff @(posedge clk) begin
	        if (reset) begin
	            fm_adjust_clip_count_l <= 16'd0;
	            fm_adjust_clip_count_r <= 16'd0;
	        end else if (audio_path_enable && jt12_sample) begin
	            if (fm_adjust_clip_l && !(&fm_adjust_clip_count_l)) begin
	                fm_adjust_clip_count_l <= fm_adjust_clip_count_l + 16'd1;
	            end
	            if (fm_adjust_clip_r && !(&fm_adjust_clip_count_r)) begin
	                fm_adjust_clip_count_r <= fm_adjust_clip_count_r + 16'd1;
	            end
	        end
	    end

`ifdef SIMULATION
`ifdef VERBOSE_TB_LOG
	    always @(posedge clk) begin
	        if (!reset && !audio_path_enable &&
	            (audio_path_enable_count == AUDIO_PATH_ENABLE_LAST)) begin
	            $display("AUDIO_PATH_ENABLE time=%0t delay_clks=%0d", $time,
	                     AUDIO_PATH_ENABLE_DELAY);
	        end
	    end
`endif
`endif

	    wire signed [15:0] fm_mixer_l =
	        (audio_path_enable && fm_path_enabled) ? fm_pre_genmix_l : 16'sd0;
	    wire signed [15:0] fm_mixer_r =
	        (audio_path_enable && fm_path_enabled) ? fm_pre_genmix_r : 16'sd0;

	    assign audio_sample_valid = audio_path_enable && jt12_sample;

	    wire signed [15:0] pre_lpf_l;
	    wire signed [15:0] pre_lpf_r;
	    wire signed [15:0] pre_lpf_gain_2x_l;
	    wire signed [15:0] pre_lpf_gain_2x_r;
	    wire signed [15:0] pre_lpf_gain_4x_l;
	    wire signed [15:0] pre_lpf_gain_4x_r;
	    wire signed [15:0] pre_lpf_gain_6x_l;
	    wire signed [15:0] pre_lpf_gain_6x_r;
	    wire signed [15:0] pre_lpf_gain_8x_l;
	    wire signed [15:0] pre_lpf_gain_8x_r;
	    wire signed [15:0] pre_lpf_selected_l;
	    wire signed [15:0] pre_lpf_selected_r;
	    wire signed [15:0] lpf_audio_l;
	    wire signed [15:0] lpf_audio_r;
	    logic signed [15:0] normal_latched_l;
	    logic signed [15:0] normal_latched_r;
	    logic signed [15:0] raw_jt12_latched_l;
	    logic signed [15:0] raw_jt12_latched_r;

	    always_ff @(posedge clk) begin
	        if (reset || !audio_path_enable) begin
	            raw_jt12_latched_l <= 16'sd0;
	            raw_jt12_latched_r <= 16'sd0;
	        end else if (jt12_sample) begin
	            raw_jt12_latched_l <= fm_left >>> 2;
	            raw_jt12_latched_r <= fm_right >>> 2;
	        end
	    end

	    always_ff @(posedge clk) begin
	        if (reset || !audio_path_enable) begin
	            normal_latched_l <= 16'sd0;
	            normal_latched_r <= 16'sd0;
	        end else if (jt12_sample) begin
	            normal_latched_l <= lpf_audio_l;
	            normal_latched_r <= lpf_audio_r;
	        end
	    end

	    wire signed [15:0] raw_jt12_live_l =
	        audio_path_enable ? (fm_left >>> 2) : 16'sd0;
	    wire signed [15:0] raw_jt12_live_r =
	        audio_path_enable ? (fm_right >>> 2) : 16'sd0;
	    wire signed [15:0] raw_jt12_audio_l =
	        MD_AUDIO_RAW_JT12_SAMPLE_LATCH_BUILD ? raw_jt12_latched_l :
	                                                raw_jt12_live_l;
	    wire signed [15:0] raw_jt12_audio_r =
	        MD_AUDIO_RAW_JT12_SAMPLE_LATCH_BUILD ? raw_jt12_latched_r :
	                                                raw_jt12_live_r;

	    jt12_genmix genmix
	    (
	        .rst       (reset),
	        .clk       (clk),
	        .fm_left   (fm_mixer_l),
	        .fm_right  (fm_mixer_r),
	        .psg_snd   (psg_mixer_snd),
	        .fm_en     (fm_path_enabled),
        .psg_en    (psg_path_enabled),
        .snd_left  (pre_lpf_l),
        .snd_right (pre_lpf_r),
        .mixed_wrap_count_left  (genmix_wrap_count_l),
        .mixed_wrap_count_right (genmix_wrap_count_r)
    );

    assign pre_lpf_gain_2x_l =
        md_audio_sat21({{5{pre_lpf_l[15]}}, pre_lpf_l} <<< 1);
    assign pre_lpf_gain_2x_r =
        md_audio_sat21({{5{pre_lpf_r[15]}}, pre_lpf_r} <<< 1);
    assign pre_lpf_gain_4x_l =
        md_audio_sat21({{5{pre_lpf_l[15]}}, pre_lpf_l} <<< 2);
    assign pre_lpf_gain_4x_r =
        md_audio_sat21({{5{pre_lpf_r[15]}}, pre_lpf_r} <<< 2);
    assign pre_lpf_gain_6x_l =
        md_audio_sat21(({{5{pre_lpf_l[15]}}, pre_lpf_l} <<< 2) +
                       ({{5{pre_lpf_l[15]}}, pre_lpf_l} <<< 1));
    assign pre_lpf_gain_6x_r =
        md_audio_sat21(({{5{pre_lpf_r[15]}}, pre_lpf_r} <<< 2) +
                       ({{5{pre_lpf_r[15]}}, pre_lpf_r} <<< 1));
    assign pre_lpf_gain_8x_l =
        md_audio_sat21({{5{pre_lpf_l[15]}}, pre_lpf_l} <<< 3);
    assign pre_lpf_gain_8x_r =
        md_audio_sat21({{5{pre_lpf_r[15]}}, pre_lpf_r} <<< 3);
    assign pre_lpf_selected_l =
`ifdef MD_AUDIO_GAIN_OSD_TEST
        audio_gain_boost ? pre_lpf_gain_2x_l :
                           pre_lpf_l;
`else
        MD_AUDIO_GENMIX_OUTPUT_GAIN_8X_BUILD ? pre_lpf_gain_8x_l :
        MD_AUDIO_GENMIX_OUTPUT_GAIN_6X_BUILD ? pre_lpf_gain_6x_l :
        MD_AUDIO_GENMIX_OUTPUT_GAIN_4X_BUILD ? pre_lpf_gain_4x_l :
        MD_AUDIO_GENMIX_OUTPUT_GAIN_2X_BUILD ? pre_lpf_gain_2x_l :
                                               pre_lpf_l;
`endif
    assign pre_lpf_selected_r =
`ifdef MD_AUDIO_GAIN_OSD_TEST
        audio_gain_boost ? pre_lpf_gain_2x_r :
                           pre_lpf_r;
`else
        MD_AUDIO_GENMIX_OUTPUT_GAIN_8X_BUILD ? pre_lpf_gain_8x_r :
        MD_AUDIO_GENMIX_OUTPUT_GAIN_6X_BUILD ? pre_lpf_gain_6x_r :
        MD_AUDIO_GENMIX_OUTPUT_GAIN_4X_BUILD ? pre_lpf_gain_4x_r :
        MD_AUDIO_GENMIX_OUTPUT_GAIN_2X_BUILD ? pre_lpf_gain_2x_r :
                                               pre_lpf_r;
`endif

    // LPF mode from Genesis_MiSTer genesis_lpf.v:
    //   2'b00: Model 1 low-pass
    //   2'b01: Model 2 low-pass
    //   2'b10: minimal 8.5 kHz low-pass
    //   2'b11: bypass
    //
    genesis_lpf lpf_left
    (
	        .clk      (clk),
	        .reset    (reset),
	        .lpf_mode (md_audio_lpf_mode_selected),
	        .in       (pre_lpf_selected_l),
	        .out      (lpf_audio_l)
	    );

    genesis_lpf lpf_right
    (
	        .clk      (clk),
	        .reset    (reset),
	        .lpf_mode (md_audio_lpf_mode_selected),
	        .in       (pre_lpf_selected_r),
	        .out      (lpf_audio_r)
	    );

	    wire raw_jt12_output_build =
	        MD_AUDIO_RAW_JT12_FM_BUILD || MD_AUDIO_RAW_JT12_SAMPLE_LATCH_BUILD;
	    wire signed [15:0] normal_audio_l =
	        MD_AUDIO_NORMAL_SAMPLE_LATCH_BUILD ? normal_latched_l : lpf_audio_l;
	    wire signed [15:0] normal_audio_r =
	        MD_AUDIO_NORMAL_SAMPLE_LATCH_BUILD ? normal_latched_r : lpf_audio_r;
	    wire signed [15:0] selected_audio_l =
	        raw_jt12_output_build ? raw_jt12_audio_l : normal_audio_l;
	    wire signed [15:0] selected_audio_r =
	        raw_jt12_output_build ? raw_jt12_audio_r : normal_audio_r;

	    wire [15:0] fm_raw_abs_now = md_audio_abs_max16(fm_left, fm_right);
	    wire [15:0] fm_adjust_abs_now = md_audio_abs_max16(fm_adjust_l, fm_adjust_r);
	    wire [15:0] fm_lpf_abs_now =
	        md_audio_abs_max16(fm_pre_genmix_lpf_selected_l, fm_pre_genmix_lpf_selected_r);
	    wire [15:0] genmix_abs_now = md_audio_abs_max16(pre_lpf_l, pre_lpf_r);
	    wire [15:0] final_audio_abs_now =
	        md_audio_abs_max16(selected_audio_l, selected_audio_r);

	    always_ff @(posedge clk) begin
	        if (reset) begin
	            fm_raw_abs_peak <= 16'd0;
	            fm_adjust_abs_peak <= 16'd0;
	            fm_lpf_abs_peak <= 16'd0;
	            genmix_abs_peak <= 16'd0;
	            final_audio_abs_peak <= 16'd0;
	        end else if (audio_sample_valid) begin
	            if (fm_raw_abs_now > fm_raw_abs_peak) begin
	                fm_raw_abs_peak <= fm_raw_abs_now;
	            end
	            if (fm_adjust_abs_now > fm_adjust_abs_peak) begin
	                fm_adjust_abs_peak <= fm_adjust_abs_now;
	            end
	            if (fm_lpf_abs_now > fm_lpf_abs_peak) begin
	                fm_lpf_abs_peak <= fm_lpf_abs_now;
	            end
	            if (genmix_abs_now > genmix_abs_peak) begin
	                genmix_abs_peak <= genmix_abs_now;
	            end
	            if (final_audio_abs_now > final_audio_abs_peak) begin
	                final_audio_abs_peak <= final_audio_abs_now;
	            end
	        end
	    end

	    assign audio_l = selected_audio_l;
	    assign audio_r = selected_audio_r;

endmodule

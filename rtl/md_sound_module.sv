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
	    output logic              audio_sample_valid
	);

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

    logic [2:0] fm_clk_cnt;
    logic       fm_clken;

    always_ff @(posedge clk) begin
        if (reset) begin
            fm_clk_cnt <= 3'd0;
            fm_clken   <= 1'b1;
        end else begin
            fm_clken <= 1'b0;
            if (fm_clk_cnt == 3'd6) begin
                fm_clk_cnt <= 3'd0;
                fm_clken   <= 1'b1;
            end else begin
                fm_clk_cnt <= fm_clk_cnt + 3'd1;
            end
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

    logic [3:0] psg_clk_cnt;
    logic       psg_clken;

    always_ff @(posedge clk) begin
        if (reset) begin
            psg_clk_cnt <= 4'd0;
            psg_clken   <= 1'b0;
        end else begin
            psg_clken <= 1'b0;
            if (psg_clk_cnt == 4'd14) begin
                psg_clk_cnt <= 4'd0;
                psg_clken   <= 1'b1;
            end else begin
                psg_clk_cnt <= psg_clk_cnt + 4'd1;
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
        YM_DATA_SETUP,
        YM_DATA_WAIT_CEN,
        YM_DATA_RELEASE,
        YM_BUSY_WAIT
    } ym_state_t;

    ym_state_t ym_state;

    logic       ym_pending_port;
    logic [7:0] ym_pending_reg;
    logic [7:0] ym_pending_data;

    logic [1:0] jt12_addr;
    logic [7:0] jt12_din;
    logic       jt12_wr_n;
    wire  [7:0] jt12_dout;

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
            jt12_addr       <= 2'd0;
            jt12_din        <= 8'h00;
            jt12_wr_n       <= 1'b1;
`ifdef SIMULATION
            ym_wait_cen_count <= 16'd0;
`endif
        end else begin
            unique case (ym_state)
                YM_IDLE: begin
                    jt12_wr_n <= 1'b1;
                    if (ym_cmd_valid && ym_cmd_ready) begin
                        ym_pending_port <= ym_cmd_port;
                        ym_pending_reg  <= ym_cmd_reg;
                        ym_pending_data <= ym_cmd_data;

                        // First write: select register on the chosen port.
                        // Keep addr/din stable before asserting wr_n, matching the
                        // official JT12 Verilator writer's bus ordering.
                        jt12_addr <= ym_cmd_port ? 2'd2 : 2'd0;
                        jt12_din  <= ym_cmd_reg;
                        ym_state  <= YM_ADDR_SETUP;
`ifdef SIMULATION
`ifdef VERBOSE_TB_LOG
                        ym_wait_cen_count <= 16'd0;
                        $display("YM_CMD_ACCEPT time=%0t port=%0d reg=%02h data=%02h",
                                 $time, ym_cmd_port, ym_cmd_reg, ym_cmd_data);
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
                    ym_state  <= YM_DATA_SETUP;
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
        .en_hifi_pcm  (1'b0),

        // 1'b0 follows Genesis_MiSTer default option wiring for YM2612 style
        // ladder effect. Make this an input later if the front end needs to
        // switch between YM2612-like and YM3438-like behavior.
        .ladder       (1'b0),

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

	    wire signed [15:0] fm_adjust_l =
	        (fm_left  <<< 4) + (fm_left  <<< 2) + (fm_left  <<< 1) + (fm_left  >>> 2);
	    wire signed [15:0] fm_adjust_r =
	        (fm_right <<< 4) + (fm_right <<< 2) + (fm_right <<< 1) + (fm_right >>> 2);

	    wire signed [10:0] psg_adjust = psg_sound - (psg_sound >>> 5);

`ifdef MUTE_PSG
	    wire signed [10:0] psg_mixer_snd = 11'sd0;
`else
	    wire signed [10:0] psg_mixer_snd = psg_adjust;
`endif

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
	        audio_path_enable ? fm_adjust_l : 16'sd0;
	    wire signed [15:0] fm_mixer_r =
	        audio_path_enable ? fm_adjust_r : 16'sd0;

	    assign audio_sample_valid = audio_path_enable && jt12_sample;

	    wire signed [15:0] pre_lpf_l;
	    wire signed [15:0] pre_lpf_r;

	    jt12_genmix genmix
	    (
	        .rst       (reset),
	        .clk       (clk),
	        .fm_left   (fm_mixer_l),
	        .fm_right  (fm_mixer_r),
	        .psg_snd   (psg_mixer_snd),
	        .fm_en     (1'b1),
        .psg_en    (1'b1),
        .snd_left  (pre_lpf_l),
        .snd_right (pre_lpf_r)
    );

    // LPF mode from Genesis_MiSTer genesis_lpf.v:
    //   2'b00: Model 1 low-pass
    //   2'b01: Model 2 low-pass
    //   2'b10: minimal 8.5 kHz low-pass
    //   2'b11: bypass
    //
    // Use bypass for the first bring-up so we can verify that sound appears
    // before tuning the final Genesis-style filter response.
    // TODO: Expose lpf_mode as an input if this module becomes a real core.

    genesis_lpf lpf_left
    (
        .clk      (clk),
        .reset    (reset),
        .lpf_mode (2'b11),
        .in       (pre_lpf_l),
        .out      (audio_l)
    );

    genesis_lpf lpf_right
    (
        .clk      (clk),
        .reset    (reset),
        .lpf_mode (2'b11),
        .in       (pre_lpf_r),
        .out      (audio_r)
    );

endmodule

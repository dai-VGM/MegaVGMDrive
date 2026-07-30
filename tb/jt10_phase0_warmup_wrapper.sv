`timescale 1ns/1ps

// Test-only JT10 startup compatibility wrapper.
//
// The JT10 instance always runs normally.  Only the final sample-qualified
// stereo interface is hidden while the first five internal sample pulses pass.
// The sixth internal pulse is the first public pulse.
module jt10_phase0_warmup_wrapper (
    input                         rst,
    input                         clk,
    input                         cen,
    input                         session_start,
    input                         loop_event,
    input                  [1:0]  addr,
    input                  [7:0]  din,
    input                         cs_n,
    input                         wr_n,

    output                        irq_n,
    output                 [7:0]  dout,
    output signed         [15:0]  snd_left,
    output signed         [15:0]  snd_right,
    output                        snd_sample,
    output                 [7:0]  psg_A,
    output                 [7:0]  psg_B,
    output                 [7:0]  psg_C,
    output                 [9:0]  psg_snd,

    output                [19:0]  adpcma_addr,
    output                 [3:0]  adpcma_bank,
    output                        adpcma_roe_n,
    input                  [7:0]  adpcma_data,
    output                [23:0]  adpcmb_addr,
    output                        adpcmb_roe_n,
    input                  [7:0]  adpcmb_data,

    output signed         [15:0]  internal_snd_left,
    output signed         [15:0]  internal_snd_right,
    output                        internal_snd_sample,
    output signed         [15:0]  internal_fm_snd,
    output                 [2:0]  warmup_count,
    output                        warmup_ready,
    output                 [2:0]  reset_cen_count,
    output                        reset_cen_valid
);

    wire signed [15:0] core_snd_left;
    wire signed [15:0] core_snd_right;
    wire               core_snd_sample;
    wire signed [15:0] core_fm_snd;

    reg           [2:0] warmup_count_r = 3'd0;
    reg                 warmup_ready_r = 1'b0;
    reg                 sample_d = 1'b0;
    reg           [2:0] reset_cen_count_r = 3'd0;
    reg                 reset_tracking = 1'b0;

    assign internal_snd_left   = core_snd_left;
    assign internal_snd_right  = core_snd_right;
    assign internal_snd_sample = core_snd_sample;
    assign internal_fm_snd     = core_fm_snd;

    assign warmup_count   = warmup_count_r;
    assign warmup_ready   = warmup_ready_r;
    assign reset_cen_count = reset_cen_count_r;
    assign reset_cen_valid = reset_cen_count_r == 3'd6;

    // loop_event is intentionally absent from the rearm expression.
    wire gate_open = warmup_ready_r && !rst && !session_start;
    assign snd_left   = gate_open ? core_snd_left   : 16'sd0;
    assign snd_right  = gate_open ? core_snd_right  : 16'sd0;
    assign snd_sample = gate_open ? core_snd_sample : 1'b0;

    // Count rising edges, then open the gate after the fifth falling edge.
    // That keeps all of pulse five private and arms the mux well before pulse
    // six.  A sample level already high at reset release is counted once.
    always @(posedge clk) begin
        if (rst || session_start) begin
            warmup_count_r <= 3'd0;
            warmup_ready_r <= 1'b0;
            sample_d       <= 1'b0;
        end else if (!reset_cen_valid) begin
            warmup_count_r <= 3'd0;
            warmup_ready_r <= 1'b0;
            sample_d       <= core_snd_sample;
        end else begin
            sample_d <= core_snd_sample;
            if (!warmup_ready_r && core_snd_sample && !sample_d &&
                warmup_count_r < 3'd5)
                warmup_count_r <= warmup_count_r + 3'd1;
            if (!warmup_ready_r && !core_snd_sample && sample_d &&
                warmup_count_r == 3'd5)
                warmup_ready_r <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            // session_start establishes a deterministic beginning for the
            // first reset window.  Later functional-reset windows are found
            // by reset_tracking returning low during normal operation.
            if (session_start || !reset_tracking)
                reset_cen_count_r <= cen ? 3'd1 : 3'd0;
            else if (cen && reset_cen_count_r < 3'd6)
                reset_cen_count_r <= reset_cen_count_r + 3'd1;
            reset_tracking <= 1'b1;
        end else begin
            reset_tracking <= 1'b0;
        end
    end

    jt10 u_jt10 (
        .rst            (rst),
        .clk            (clk),
        .cen            (cen),
        .addr           (addr),
        .din            (din),
        .cs_n           (cs_n),
        .wr_n           (wr_n),
        .irq_n          (irq_n),
        .dout           (dout),
        .snd_left       (core_snd_left),
        .snd_right      (core_snd_right),
        .snd_sample     (core_snd_sample),
        .fm_snd         (core_fm_snd),
        .psg_A          (psg_A),
        .psg_B          (psg_B),
        .psg_C          (psg_C),
        .psg_snd        (psg_snd),
        .adpcma_addr    (adpcma_addr),
        .adpcma_bank    (adpcma_bank),
        .adpcma_roe_n   (adpcma_roe_n),
        .adpcma_data    (adpcma_data),
        .adpcmb_addr    (adpcmb_addr),
        .adpcmb_roe_n   (adpcmb_roe_n),
        .adpcmb_data    (adpcmb_data)
    );

endmodule

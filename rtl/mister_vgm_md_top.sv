// Minimal MiSTer-facing top wrapper for the fixed-region MD sound test.
//
// This is not a complete MiSTer "emu" core yet. It is a small bridge intended
// to be instantiated from a future MiSTer core skeleton:
//
//   MiSTer/core clock + reset
//       -> mister_vgm_md_top
//       -> md_sound_fixed_region_test
//       -> audio_l/audio_r
//
// The fixed region auto-starts once after reset is released. No SD card, HPS,
// OSD, file loading, or VGM selection is implemented here.

module mister_vgm_md_top #(
    // Internal reset hold after FPGA configuration or external core reset.
    // With a 50 MHz clk_sys, 25,000,000 cycles is about 0.5 seconds.
    parameter logic [31:0] POWER_ON_RESET_CYCLES = 32'd25_000_000,

    // Hardware bring-up delay before the fixed VGM region starts.
    // With a 50 MHz clk_sys, 25,000,000 cycles is about 0.5 seconds.
    parameter logic [31:0] START_DELAY_CYCLES = 32'd25_000_000,

    // After reset is released, wait for a few audio sample strobes before
    // opening the external audio gate and starting the fixed region. This lets
    // JT12/JT89/mixer output settle while the board output is still muted.
    parameter logic [15:0] INIT_AUDIO_SAMPLE_EDGES = 16'd64,

    // Additional output warmup before starting the snippet. During this period
    // md_sound_module is running and producing sample strobes, but emu.sv still
    // keeps AUDIO_L/R at zero. 22050 samples is about 0.5 seconds at 44.1 kHz.
    parameter logic [15:0] AUDIO_WARMUP_SAMPLES = 16'd22050,
    parameter logic [15:0] GATE_TO_START_CYCLES = 16'd1024,

    // VGM waits are specified in 44100 Hz sample units. Generate a dedicated
    // average-44100 Hz tick for the fixed VGM player instead of using the JT12
    // audio sample strobe.
    parameter logic [31:0] CLK_SYS_HZ = 32'd50_000_000,
    parameter logic [31:0] VGM_WAIT_HZ = 32'd44_100
) (
    input  logic              clk,

    // Active-low reset is convenient for many board/top-level wrappers. It is
    // synchronized locally and converted to the active-high reset expected by
    // md_sound_fixed_region_test / md_sound_module.
    input  logic              reset_n,

    // Signed stereo PCM from md_sound_module. A future MiSTer core skeleton
    // should route these to the platform AUDIO_L/AUDIO_R path with the expected
    // width/sign convention.
    output signed      [15:0] audio_l,
    output signed      [15:0] audio_r,
    output logic              audio_sample_valid,

    // Optional debug/status pins for early bring-up.
    output logic              player_busy,
    output logic              player_done,
    output logic        [9:0] player_pc_debug,
    output logic        [7:0] player_last_cmd_debug,

    // Startup/debug status for MiSTer bring-up color checks.
    output logic              startup_reset_active,
    output logic              startup_waiting,
    output logic              startup_done,
    output logic              audio_gate_open
);

    logic        reset;
    logic [2:0]  reset_sync = 3'b111;
    logic        external_reset;

    // These initialization values are intentional for hardware bring-up:
    // when reset_n is already high at FPGA configuration completion, the
    // startup sequence still begins from a known "POR not done / not started"
    // state without waiting for a reset_n edge.
    logic [31:0] por_counter = 32'd0;
    logic        por_done = 1'b0;
    logic [31:0] start_delay_counter = 32'd0;
    logic [15:0] init_audio_edge_count = 16'd0;
    logic [15:0] audio_warmup_count = 16'd0;
    logic [15:0] gate_to_start_count = 16'd0;
    logic        start_sent = 1'b0;
    logic        start_pulse = 1'b0;
    logic        audio_sample_valid_d = 1'b0;
    logic [31:0] vgm_wait_accum = 32'd0;
    logic        vgm_wait_tick = 1'b0;

    typedef enum logic [2:0] {
        STARTUP_RESET,
        STARTUP_AUDIO_MUTED,
        STARTUP_SOUND_INIT_WAIT,
        STARTUP_AUDIO_WARMUP,
        STARTUP_GATE_OPEN_WAIT,
        STARTUP_SNIPPET_STARTED
    } startup_state_t;

    startup_state_t startup_state = STARTUP_RESET;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            reset_sync <= 3'b111;
        end else begin
            reset_sync <= {reset_sync[1:0], 1'b0};
        end
    end

    assign external_reset = reset_sync[2];

    assign reset = external_reset | !por_done;

    assign startup_reset_active = !por_done || (startup_state == STARTUP_RESET);
    assign startup_waiting = (startup_state == STARTUP_AUDIO_MUTED) ||
                             (startup_state == STARTUP_SOUND_INIT_WAIT) ||
                             (startup_state == STARTUP_AUDIO_WARMUP) ||
                             (startup_state == STARTUP_GATE_OPEN_WAIT);
    assign startup_done = (startup_state == STARTUP_SNIPPET_STARTED);

    always_ff @(posedge clk) begin
        if (reset) begin
            vgm_wait_accum <= 32'd0;
            vgm_wait_tick  <= 1'b0;
        end else begin
            if (vgm_wait_accum >= (CLK_SYS_HZ - VGM_WAIT_HZ)) begin
                vgm_wait_accum <= vgm_wait_accum + VGM_WAIT_HZ - CLK_SYS_HZ;
                vgm_wait_tick  <= 1'b1;
            end else begin
                vgm_wait_accum <= vgm_wait_accum + VGM_WAIT_HZ;
                vgm_wait_tick  <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (external_reset) begin
            por_counter <= 32'd0;
            por_done <= 1'b0;
            start_delay_counter <= 32'd0;
            init_audio_edge_count <= 16'd0;
            audio_warmup_count <= 16'd0;
            gate_to_start_count <= 16'd0;
            start_sent <= 1'b0;
            start_pulse <= 1'b0;
            audio_gate_open <= 1'b0;
            audio_sample_valid_d <= 1'b0;
            startup_state <= STARTUP_RESET;
        end else begin
            start_pulse <= 1'b0;
            audio_sample_valid_d <= audio_sample_valid;

            unique case (startup_state)
                STARTUP_RESET: begin
                    audio_gate_open <= 1'b0;
                    start_delay_counter <= 32'd0;
                    init_audio_edge_count <= 16'd0;
                    audio_warmup_count <= 16'd0;
                    gate_to_start_count <= 16'd0;
                    start_sent <= 1'b0;

                    if (!por_done) begin
                        if (por_counter >= POWER_ON_RESET_CYCLES) begin
                            por_done <= 1'b1;
                        end else begin
                            por_counter <= por_counter + 32'd1;
                        end
                    end else begin
                        startup_state <= STARTUP_AUDIO_MUTED;
                    end
                end

                STARTUP_AUDIO_MUTED: begin
                    audio_gate_open <= 1'b0;
                    if (start_delay_counter >= START_DELAY_CYCLES) begin
                        startup_state <= STARTUP_SOUND_INIT_WAIT;
                    end else begin
                        start_delay_counter <= start_delay_counter + 32'd1;
                    end
                end

                STARTUP_SOUND_INIT_WAIT: begin
                    audio_gate_open <= 1'b0;
                    if (audio_sample_valid && !audio_sample_valid_d) begin
                        if (init_audio_edge_count >= INIT_AUDIO_SAMPLE_EDGES) begin
                            startup_state <= STARTUP_AUDIO_WARMUP;
                        end else begin
                            init_audio_edge_count <= init_audio_edge_count + 16'd1;
                        end
                    end
                end

                STARTUP_AUDIO_WARMUP: begin
                    audio_gate_open <= 1'b0;
                    if (audio_sample_valid && !audio_sample_valid_d) begin
                        if (audio_warmup_count >= AUDIO_WARMUP_SAMPLES) begin
                            startup_state <= STARTUP_GATE_OPEN_WAIT;
                        end else begin
                            audio_warmup_count <= audio_warmup_count + 16'd1;
                        end
                    end
                end

                STARTUP_GATE_OPEN_WAIT: begin
                    audio_gate_open <= 1'b1;
                    if (gate_to_start_count >= GATE_TO_START_CYCLES) begin
                        start_pulse <= 1'b1;
                        start_sent <= 1'b1;
                        startup_state <= STARTUP_SNIPPET_STARTED;
                    end else begin
                        gate_to_start_count <= gate_to_start_count + 16'd1;
                    end
                end

                STARTUP_SNIPPET_STARTED: begin
                    audio_gate_open <= 1'b1;
                    startup_state <= STARTUP_SNIPPET_STARTED;
                end

                default: begin
                    audio_gate_open <= 1'b0;
                    startup_state <= STARTUP_RESET;
                end
            endcase
        end
    end

    md_sound_fixed_region_test fixed_region (
        .clk                   (clk),
        .reset                 (reset),
        .start                 (start_pulse),
        .vgm_wait_tick         (vgm_wait_tick),
        .audio_l               (audio_l),
        .audio_r               (audio_r),
        .audio_sample_valid    (audio_sample_valid),
        .player_busy           (player_busy),
        .player_done           (player_done),
        .player_pc_debug       (player_pc_debug),
        .player_last_cmd_debug (player_last_cmd_debug)
    );

endmodule

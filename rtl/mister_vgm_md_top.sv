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
    parameter logic [31:0] START_DELAY_CYCLES = 32'd25_000_000
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
    output logic              startup_done
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
    logic        start_sent = 1'b0;
    logic        start_pulse = 1'b0;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            reset_sync <= 3'b111;
        end else begin
            reset_sync <= {reset_sync[1:0], 1'b0};
        end
    end

    assign external_reset = reset_sync[2];

    assign reset = external_reset | !por_done;

    assign startup_reset_active = !por_done;
    assign startup_waiting = por_done && !start_sent;
    assign startup_done = por_done && start_sent;

    always_ff @(posedge clk) begin
        if (external_reset) begin
            por_counter <= 32'd0;
            por_done <= 1'b0;
            start_delay_counter <= 32'd0;
            start_sent <= 1'b0;
            start_pulse <= 1'b0;
        end else begin
            start_pulse <= 1'b0;

            if (!por_done) begin
                start_delay_counter <= 32'd0;
                start_sent <= 1'b0;

                if (por_counter >= POWER_ON_RESET_CYCLES) begin
                    por_done <= 1'b1;
                end else begin
                    por_counter <= por_counter + 32'd1;
                end
            end else if (!start_sent) begin
                if (start_delay_counter >= START_DELAY_CYCLES) begin
                    start_pulse <= 1'b1;
                    start_sent <= 1'b1;
                end else begin
                    start_delay_counter <= start_delay_counter + 32'd1;
                end
            end
        end
    end

    md_sound_fixed_region_test fixed_region (
        .clk                   (clk),
        .reset                 (reset),
        .start                 (start_pulse),
        .audio_l               (audio_l),
        .audio_r               (audio_r),
        .audio_sample_valid    (audio_sample_valid),
        .player_busy           (player_busy),
        .player_done           (player_done),
        .player_pc_debug       (player_pc_debug),
        .player_last_cmd_debug (player_last_cmd_debug)
    );

endmodule

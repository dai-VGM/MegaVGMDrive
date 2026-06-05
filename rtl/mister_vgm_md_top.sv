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

    logic [2:0]  reset_sync = 3'b111;
    logic        external_reset;
    logic        reset;
    logic [31:0] power_on_reset_count = 32'd0;
    logic        power_on_reset_active = 1'b1;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            reset_sync <= 3'b111;
        end else begin
            reset_sync <= {reset_sync[1:0], 1'b0};
        end
    end

    assign external_reset = reset_sync[2];

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            power_on_reset_active <= 1'b1;
            power_on_reset_count <= 32'd0;
        end else if (external_reset) begin
            power_on_reset_active <= 1'b1;
            power_on_reset_count <= 32'd0;
        end else if (power_on_reset_active) begin
            if (power_on_reset_count >= POWER_ON_RESET_CYCLES) begin
                power_on_reset_active <= 1'b0;
            end else begin
                power_on_reset_count <= power_on_reset_count + 32'd1;
            end
        end
    end

    assign reset = external_reset | power_on_reset_active;

    typedef enum logic [1:0] {
        START_WAIT_RESET,
        START_PULSE,
        START_DONE
    } start_state_t;

    start_state_t start_state;
    logic         start_pulse;
    logic [31:0]  start_delay_count;

    assign startup_reset_active = power_on_reset_active;
    assign startup_waiting = !reset && (start_state == START_WAIT_RESET);
    assign startup_done = !reset && (start_state == START_DONE);

    always_ff @(posedge clk) begin
        if (reset) begin
            start_state <= START_WAIT_RESET;
            start_pulse <= 1'b0;
            start_delay_count <= 32'd0;
        end else begin
            start_pulse <= 1'b0;

            unique case (start_state)
                START_WAIT_RESET: begin
                    if (start_delay_count >= START_DELAY_CYCLES) begin
                        start_state <= START_PULSE;
                    end else begin
                        start_delay_count <= start_delay_count + 32'd1;
                    end
                end

                START_PULSE: begin
                    start_pulse <= 1'b1;
                    start_state <= START_DONE;
                end

                START_DONE: begin
                    start_state <= START_DONE;
                end

                default: begin
                    start_state <= START_DONE;
                end
            endcase
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

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
// REGION_MODE=0..4 keep the fixed-region path. REGION_MODE=5 adds the first
// small BRAM-backed HPS/OSD-loaded VGM path.
`include "rtl/fixed_region_mode.vh"

module mister_vgm_md_top #(
    parameter int REGION_MODE = `FIXED_REGION_MODE,
    parameter int VGM_LOAD_ADDR_WIDTH = 16,
    parameter logic [15:0] VGM_LOAD_FILE_INDEX = 16'd1,

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
    parameter logic [31:0] CLK_SYS_HZ = 32'd12_500_000,
    parameter logic [31:0] VGM_WAIT_HZ = 32'd44_100,

    // Bring-up replay/retry support. If the fixed-region player misses the
    // first start or stalls before END, reset only the player wrapper and try
    // again without disturbing the JT12/JT89 audio path.
    parameter bit          REPLAY_ENABLE = 1'b1,
    parameter logic [31:0] PLAYER_RESET_CYCLES = 32'd4096,
    parameter logic [31:0] START_ACCEPT_TIMEOUT_CYCLES = 32'd1_000_000,
    parameter logic [31:0] PLAYER_DONE_TIMEOUT_TICKS = 32'd264_600,
    parameter logic [31:0] REPLAY_DELAY_TICKS = 32'd88_200
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
    output logic              audio_gate_open,

    // MiSTer file download bus. Used only by REGION_MODE=5.
    input  logic              ioctl_download,
    input  logic              ioctl_wr,
    input  logic [26:0]       ioctl_addr,
    input  logic [7:0]        ioctl_dout,
    input  logic [15:0]       ioctl_index,

    // REGION_MODE=5 loader/player status for hardware debug colors.
    output logic              vgm_load_busy,
    output logic              vgm_load_done,
    output logic              vgm_load_error,
    output logic              vgm_load_overflow,
    output logic              vgm_header_valid,
    output logic              vgm_player_error,
    output logic [VGM_LOAD_ADDR_WIDTH:0] vgm_load_size,
    output logic [31:0]       vgm_load_magic,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_data_start_debug
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
    logic        player_reset_active = 1'b0;
    logic [31:0] player_reset_counter = 32'd0;
    logic [31:0] start_accept_counter = 32'd0;
    logic [31:0] player_done_timeout_ticks = 32'd0;
    logic [31:0] replay_delay_ticks = 32'd0;

    typedef enum logic [3:0] {
        STARTUP_RESET,
        STARTUP_AUDIO_MUTED,
        STARTUP_SOUND_INIT_WAIT,
        STARTUP_AUDIO_WARMUP,
        STARTUP_GATE_OPEN_WAIT,
        STARTUP_WAIT_PLAYER_BUSY,
        STARTUP_PLAYING,
        STARTUP_REPLAY_WAIT,
        STARTUP_RETRY_RESET
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

    assign startup_reset_active = !por_done ||
                                  player_reset_active ||
                                  (startup_state == STARTUP_RESET) ||
                                  (startup_state == STARTUP_RETRY_RESET);
    assign startup_waiting = (startup_state == STARTUP_AUDIO_MUTED) ||
                             (startup_state == STARTUP_SOUND_INIT_WAIT) ||
                             (startup_state == STARTUP_AUDIO_WARMUP) ||
                             (startup_state == STARTUP_GATE_OPEN_WAIT) ||
                             (startup_state == STARTUP_WAIT_PLAYER_BUSY) ||
                             (startup_state == STARTUP_REPLAY_WAIT);
    assign startup_done = (startup_state == STARTUP_PLAYING) ||
                          (startup_state == STARTUP_REPLAY_WAIT);

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
            player_reset_active <= 1'b0;
            player_reset_counter <= 32'd0;
            start_accept_counter <= 32'd0;
            player_done_timeout_ticks <= 32'd0;
            replay_delay_ticks <= 32'd0;
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
                    player_reset_active <= 1'b0;
                    player_reset_counter <= 32'd0;
                    start_accept_counter <= 32'd0;
                    player_done_timeout_ticks <= 32'd0;
                    replay_delay_ticks <= 32'd0;
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
                        start_accept_counter <= 32'd0;
                        player_done_timeout_ticks <= 32'd0;
                        startup_state <= STARTUP_WAIT_PLAYER_BUSY;
                    end else begin
                        gate_to_start_count <= gate_to_start_count + 16'd1;
                    end
                end

                STARTUP_WAIT_PLAYER_BUSY: begin
                    audio_gate_open <= 1'b1;

                    if (player_busy) begin
                        player_done_timeout_ticks <= 32'd0;
                        startup_state <= STARTUP_PLAYING;
                    end else if (start_accept_counter >= START_ACCEPT_TIMEOUT_CYCLES) begin
                        player_reset_active <= 1'b1;
                        player_reset_counter <= 32'd0;
                        startup_state <= STARTUP_RETRY_RESET;
                    end else begin
                        start_accept_counter <= start_accept_counter + 32'd1;
                    end
                end

                STARTUP_PLAYING: begin
                    audio_gate_open <= 1'b1;

                    if (player_done) begin
                        if (REPLAY_ENABLE) begin
                            replay_delay_ticks <= 32'd0;
                            startup_state <= STARTUP_REPLAY_WAIT;
                        end
                    end else if (vgm_wait_tick) begin
                        if (player_done_timeout_ticks >= PLAYER_DONE_TIMEOUT_TICKS) begin
                            player_reset_active <= 1'b1;
                            player_reset_counter <= 32'd0;
                            startup_state <= STARTUP_RETRY_RESET;
                        end else begin
                            player_done_timeout_ticks <= player_done_timeout_ticks + 32'd1;
                        end
                    end
                end

                STARTUP_REPLAY_WAIT: begin
                    audio_gate_open <= 1'b1;

                    if (!REPLAY_ENABLE) begin
                        startup_state <= STARTUP_REPLAY_WAIT;
                    end else if (vgm_wait_tick) begin
                        if (replay_delay_ticks >= REPLAY_DELAY_TICKS) begin
                            player_reset_active <= 1'b1;
                            player_reset_counter <= 32'd0;
                            startup_state <= STARTUP_RETRY_RESET;
                        end else begin
                            replay_delay_ticks <= replay_delay_ticks + 32'd1;
                        end
                    end
                end

                STARTUP_RETRY_RESET: begin
                    audio_gate_open <= 1'b0;
                    player_reset_active <= 1'b1;
                    start_sent <= 1'b0;
                    start_accept_counter <= 32'd0;
                    player_done_timeout_ticks <= 32'd0;
                    replay_delay_ticks <= 32'd0;
                    gate_to_start_count <= 16'd0;

                    if (player_reset_counter >= PLAYER_RESET_CYCLES) begin
                        player_reset_active <= 1'b0;
                        player_reset_counter <= 32'd0;
                        startup_state <= STARTUP_GATE_OPEN_WAIT;
                    end else begin
                        player_reset_counter <= player_reset_counter + 32'd1;
                    end
                end

                default: begin
                    audio_gate_open <= 1'b0;
                    startup_state <= STARTUP_RESET;
                end
            endcase
        end
    end

    generate
        if (REGION_MODE == 5) begin : loaded_vgm_mode
            logic [VGM_LOAD_ADDR_WIDTH-1:0] ram_rd_addr;
            logic [7:0] ram_rd_data;
            logic load_done_pulse;
            logic ym_cmd_valid;
            logic ym_cmd_port;
            logic [7:0] ym_cmd_reg;
            logic [7:0] ym_cmd_data;
            logic psg_cmd_valid;
            logic [7:0] psg_cmd_data;
            logic ym_cmd_ready;
            logic psg_cmd_ready;

            vgm_file_loader #(
                .ADDR_WIDTH       (VGM_LOAD_ADDR_WIDTH),
                .ACCEPT_ANY_INDEX (1'b0),
                .FILE_INDEX       (VGM_LOAD_FILE_INDEX)
            ) loader (
                .clk              (clk),
                .reset            (reset),
                .ioctl_download   (ioctl_download),
                .ioctl_wr         (ioctl_wr),
                .ioctl_addr       (ioctl_addr),
                .ioctl_dout       (ioctl_dout),
                .ioctl_index      (ioctl_index),
                .rd_addr          (ram_rd_addr),
                .rd_data          (ram_rd_data),
                .load_busy        (vgm_load_busy),
                .load_done        (vgm_load_done),
                .load_done_pulse  (load_done_pulse),
                .load_error       (vgm_load_error),
                .overflow_error   (vgm_load_overflow),
                .file_size        (vgm_load_size),
                .magic_debug      (vgm_load_magic)
            );

            vgm_loaded_player #(
                .ADDR_WIDTH (VGM_LOAD_ADDR_WIDTH)
            ) loaded_player (
                .clk                   (clk),
                .reset                 (reset | player_reset_active),
                .start                 (start_pulse),
                .load_done             (vgm_load_done),
                .load_done_pulse       (load_done_pulse),
                .load_error            (vgm_load_error),
                .overflow_error        (vgm_load_overflow),
                .file_size             (vgm_load_size),
                .vgm_wait_tick         (vgm_wait_tick),
                .rd_addr               (ram_rd_addr),
                .rd_data               (ram_rd_data),
                .ym_cmd_ready          (ym_cmd_ready),
                .psg_cmd_ready         (psg_cmd_ready),
                .ym_cmd_valid          (ym_cmd_valid),
                .ym_cmd_port           (ym_cmd_port),
                .ym_cmd_reg            (ym_cmd_reg),
                .ym_cmd_data           (ym_cmd_data),
                .psg_cmd_valid         (psg_cmd_valid),
                .psg_cmd_data          (psg_cmd_data),
                .busy                  (player_busy),
                .done                  (player_done),
                .header_valid          (vgm_header_valid),
                .player_error          (vgm_player_error),
                .data_start_debug      (vgm_data_start_debug),
                .pc_debug              (player_pc_debug),
                .last_cmd_debug        (player_last_cmd_debug)
            );

            md_sound_module sound (
                .clk                   (clk),
                .reset                 (reset),
                .ym_cmd_valid          (ym_cmd_valid),
                .ym_cmd_port           (ym_cmd_port),
                .ym_cmd_reg            (ym_cmd_reg),
                .ym_cmd_data           (ym_cmd_data),
                .psg_cmd_valid         (psg_cmd_valid),
                .psg_cmd_data          (psg_cmd_data),
                .ym_cmd_ready          (ym_cmd_ready),
                .psg_cmd_ready         (psg_cmd_ready),
                .audio_l               (audio_l),
                .audio_r               (audio_r),
                .audio_sample_valid    (audio_sample_valid)
            );
        end else begin : fixed_region_mode
            assign vgm_load_busy = 1'b0;
            assign vgm_load_done = 1'b0;
            assign vgm_load_error = 1'b0;
            assign vgm_load_overflow = 1'b0;
            assign vgm_header_valid = 1'b0;
            assign vgm_player_error = 1'b0;
            assign vgm_load_size = '0;
            assign vgm_load_magic = 32'd0;
            assign vgm_data_start_debug = '0;

            md_sound_fixed_region_test #(
                .REGION_MODE (REGION_MODE)
            ) fixed_region (
                .clk                   (clk),
                .reset                 (reset),
                .player_reset          (player_reset_active),
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
        end
    endgenerate

endmodule

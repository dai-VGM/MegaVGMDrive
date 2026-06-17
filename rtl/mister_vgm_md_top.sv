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
    parameter int VGM_LOAD_ADDR_WIDTH = 18,
    parameter logic [15:0] VGM_LOAD_FILE_INDEX = 16'd1,
    parameter int MODE5_VGM_BACKEND = 0,

    // Internal reset hold after FPGA configuration or external core reset.
    // The current MiSTer shell PLL drives clk_sys at 20 MHz
    // (rtl/pll/pll_0002.v output_clock_frequency0).
    parameter logic [31:0] POWER_ON_RESET_CYCLES = 32'd25_000_000,

    // Hardware bring-up delay before the fixed VGM region starts.
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

    // VGM waits are specified in 44100 Hz sample units. The active PLL output
    // feeding emu.clk_sys is 20 MHz, so this must match that hardware clock.
    // A stale 12.5 MHz value makes VGM playback about 20/12.5 = 1.6x fast.
    parameter logic [31:0] CLK_SYS_HZ = 32'd20_000_000,
    parameter logic [31:0] VGM_WAIT_HZ = 32'd44_100,

    // REGION_MODE=5 reload hygiene. After a valid OSD file download finishes,
    // hold the MD sound core in reset before starting the loaded player so
    // stale YM2612/JT12 and PSG state cannot bleed into the next VGM.
    parameter logic [31:0] MODE5_SOUND_RESET_CYCLES = 32'd32_768,

    // REGION_MODE=5 final-output mute release delay. This keeps the MiSTer
    // audio pins silent while the loaded player and sound core settle after a
    // completed OSD load. 1,000,000 cycles is about 50 ms at 20 MHz.
    parameter logic [31:0] MODE5_AUDIO_UNMUTE_DELAY_CYCLES = 32'd1_000_000,

    // REGION_MODE=5 explicit END repeat policy. This is intentionally separate
    // from the one-shot load-session start path: disabled means END stays
    // stopped/muted, enabled means a player_done edge schedules one reset/start
    // through the dedicated repeat path.
    parameter bit          MODE5_REPEAT_ENABLE = 1'b0,

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
    output logic signed [15:0] audio_l,
    output logic signed [15:0] audio_r,
    output logic              audio_sample_valid,
    input  logic        [1:0] audio_lpf_mode,
    input  logic              audio_gain_boost,
    input  logic        [1:0] audio_psg_level,

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
    output logic              audio_muted,

    // MiSTer file download bus. Used only by REGION_MODE=5.
    input  logic              ioctl_download,
    input  logic              ioctl_wr,
    input  logic [26:0]       ioctl_addr,
    input  logic [7:0]        ioctl_dout,
    input  logic [15:0]       ioctl_index,
    output logic              ioctl_wait,

    // REGION_MODE=5 loader/player status for hardware debug colors.
    output logic              vgm_load_busy,
    output logic              vgm_load_done,
    output logic              vgm_load_error,
    output logic              vgm_load_overflow,
    output logic              vgm_header_valid,
    output logic              vgm_player_error,
    output logic        [7:0] vgm_unsupported_opcode,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_unsupported_pc,
    output logic        [7:0] vgm_player_error_code,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_error_pc_debug,
    output logic        [7:0] vgm_error_cmd_debug,
    output logic        [31:0] vgm_error_session_id,
    output logic        [5:0] vgm_player_state_debug,
    output logic              vgm_mem_rd_req_debug,
    output logic              vgm_mem_rd_ready_debug,
    output logic              vgm_mem_rd_valid_debug,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_mem_rd_addr_debug,
    output logic [VGM_LOAD_ADDR_WIDTH:0] vgm_load_size,
    output logic [31:0]       vgm_load_magic,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_data_start_debug,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_current_pc_debug,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] vgm_loop_pc_debug,
    output logic              vgm_loop_valid_debug,
    output logic              vgm_loop_taken_debug,
    output logic              vgm_end_command_seen,
    output logic              vgm_restarted_from_data_start,
    output logic              vgm_pcm_oob,
    output logic [31:0]       vgm_pcm_oob_count,
    output logic [31:0]       vgm_wait_ticks_consumed_debug,
    output logic              mode5_sound_reset_active,
    output logic              mode5_player_start_pulse_debug,
    output logic [31:0]       mode5_load_begin_count,
    output logic [31:0]       mode5_load_done_edge_count,
    output logic [31:0]       mode5_sound_reset_start_count,
    output logic [31:0]       mode5_player_start_count,
    output logic [31:0]       mode5_player_reset_count,
    output logic [31:0]       mode5_playback_session_id,
    output logic [31:0]       mode5_duplicate_start_blocked_count,
    output logic [31:0]       mode5_player_end_count,
    output logic [31:0]       mode5_repeat_restart_count,
    output logic              mode5_done_armed_debug,
    output logic [31:0]       mode5_repeat_session_id,
    output logic [31:0]       mode5_done_session_id,
    output logic [31:0]       mode5_cycles_since_start,
    output logic [VGM_LOAD_ADDR_WIDTH-1:0] mode5_done_pc_debug,
    output logic [7:0]        mode5_done_cmd_debug,
    output logic [15:0]       fm_adjust_clip_count_l,
    output logic [15:0]       fm_adjust_clip_count_r,
    output logic [15:0]       genmix_wrap_count_l,
    output logic [15:0]       genmix_wrap_count_r,
    output logic [31:0]       ym_write_requested_count,
    output logic [31:0]       ym_write_accepted_count,
    output logic [31:0]       ym_write_dropped_or_busy_count,
    output logic [31:0]       ym_port0_count,
    output logic [31:0]       ym_port1_count,
    output logic              last_ym_port,
    output logic [7:0]        last_ym_addr,
    output logic [7:0]        last_ym_data,
    output logic [15:0]       jt12_cen_interval_1_count,
    output logic [15:0]       jt12_cen_interval_2_count,
    output logic [15:0]       jt12_cen_interval_3_count,
    output logic [15:0]       jt12_cen_interval_4_count,
    output logic [15:0]       jt12_cen_interval_ge5_count,
    output logic [7:0]        jt12_cen_interval_min,
    output logic [7:0]        jt12_cen_interval_max,
    output logic [7:0]        jt12_cen_interval_last,
    output logic [15:0]       fm_raw_abs_peak,
    output logic [15:0]       fm_adjust_abs_peak,
    output logic [15:0]       fm_lpf_abs_peak,
    output logic [15:0]       genmix_abs_peak,
    output logic [15:0]       md_final_audio_abs_peak,

    // DDRAM interface for future mode5 backend.
    // Backend 0 (BRAM) keeps these inactive.
    input  logic              ddram_busy,
    output logic [7:0]        ddram_burstcnt,
    output logic [28:0]       ddram_addr,
    input  logic [63:0]       ddram_dout,
    input  logic              ddram_dout_ready,
    output logic              ddram_rd,
    output logic [63:0]       ddram_din,
    output logic [7:0]        ddram_be,
    output logic              ddram_we
);

    localparam int MODE5_BACKEND_BRAM  = 0;
    localparam int MODE5_BACKEND_DDRAM = 1;

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
    logic signed [15:0] raw_audio_l;
    logic signed [15:0] raw_audio_r;
    logic               raw_audio_sample_valid;
    logic               audio_runtime_open;

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

    assign audio_sample_valid = raw_audio_sample_valid;
    assign audio_muted = !audio_runtime_open;
    assign audio_l = audio_runtime_open ? raw_audio_l : 16'sd0;
    assign audio_r = audio_runtime_open ? raw_audio_r : 16'sd0;

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

                    if ((REGION_MODE != 5) && player_done) begin
                        if (REPLAY_ENABLE) begin
                            replay_delay_ticks <= 32'd0;
                            startup_state <= STARTUP_REPLAY_WAIT;
                        end
                    end else if ((REGION_MODE != 5) && vgm_wait_tick) begin
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
            logic mem_rd_req;
            logic [VGM_LOAD_ADDR_WIDTH-1:0] mem_rd_addr;
            logic mem_rd_ready;
            logic mem_rd_valid;
            logic [7:0] mem_rd_data;
            logic load_done_pulse;
            logic play_ready_pulse;
            logic ym_cmd_valid;
            logic ym_cmd_port;
            logic [7:0] ym_cmd_reg;
            logic [7:0] ym_cmd_data;
            logic psg_cmd_valid;
            logic [7:0] psg_cmd_data;
            logic ym_cmd_ready;
            logic psg_cmd_ready;
            logic mode5_sound_reset_active_i = 1'b0;
            logic mode5_sound_core_reset;
            logic mode5_player_start_pulse = 1'b0;
            logic [31:0] mode5_sound_reset_counter = 32'd0;
            logic ioctl_download_d = 1'b0;
            logic mode5_load_begin_pulse;
            logic mode5_load_session_active = 1'b0;
            logic mode5_playback_armed = 1'b0;
            logic mode5_playback_started = 1'b0;
            logic mode5_player_session_reset = 1'b0;
            logic [31:0] mode5_audio_unmute_counter = 32'd0;
            logic mode5_audio_unmute_ready = 1'b0;
            logic mode5_audio_pre_unmute;
            logic [31:0] mode5_load_begin_count_i = 32'd0;
            logic [31:0] mode5_load_done_edge_count_i = 32'd0;
            logic [31:0] mode5_sound_reset_start_count_i = 32'd0;
            logic [31:0] mode5_player_start_count_i = 32'd0;
            logic [31:0] mode5_player_reset_count_i = 32'd0;
            logic [31:0] mode5_playback_session_id_i = 32'd0;
            logic [31:0] mode5_duplicate_start_blocked_count_i = 32'd0;
            logic [31:0] mode5_player_end_count_i = 32'd0;
            logic [31:0] mode5_repeat_restart_count_i = 32'd0;
            logic mode5_done_armed_i = 1'b0;
            logic [31:0] mode5_done_armed_session_id_i = 32'd0;
            logic [31:0] mode5_repeat_session_id_i = 32'd0;
            logic [31:0] mode5_done_session_id_i = 32'd0;
            logic [31:0] mode5_cycles_since_start_i = 32'd0;
            logic [VGM_LOAD_ADDR_WIDTH-1:0] mode5_done_pc_debug_i = '0;
            logic [7:0] mode5_done_cmd_debug_i = 8'd0;
            logic [VGM_LOAD_ADDR_WIDTH-1:0] player_done_pc_debug;
            logic [7:0] player_done_cmd_debug;
            logic loaded_player_done;
            logic player_done_d = 1'b0;
            logic mode5_player_done_latched = 1'b0;
            logic vgm_player_error_d = 1'b0;
            logic [31:0] mode5_error_session_id_i = 32'd0;
            logic mode5_done_edge;
            logic mode5_player_error_edge;
            localparam logic [1:0] MODE5_REPEAT_IDLE       = 2'd0;
            localparam logic [1:0] MODE5_REPEAT_RESET      = 2'd1;
            localparam logic [1:0] MODE5_REPEAT_WAIT_CLEAR = 2'd2;
            logic [1:0] mode5_repeat_state = MODE5_REPEAT_IDLE;

            assign mode5_load_begin_pulse =
                ioctl_download && !ioctl_download_d &&
                (ioctl_index == VGM_LOAD_FILE_INDEX);
            assign mode5_done_edge =
                loaded_player_done &&
                !player_done_d &&
                mode5_playback_started &&
                mode5_done_armed_i &&
                (mode5_done_armed_session_id_i == mode5_playback_session_id_i) &&
                !mode5_load_session_active &&
                !vgm_load_busy &&
                !vgm_load_error &&
                !vgm_load_overflow &&
                !vgm_player_error;
            assign mode5_player_error_edge =
                vgm_player_error && !vgm_player_error_d;

            always_ff @(posedge clk) begin
                if (reset) begin
                    ioctl_download_d <= 1'b0;
                    mode5_sound_reset_active_i <= 1'b0;
                    mode5_player_start_pulse <= 1'b0;
                    mode5_sound_reset_counter <= 32'd0;
                    mode5_load_session_active <= 1'b0;
                    mode5_playback_armed <= 1'b0;
                    mode5_playback_started <= 1'b0;
                    mode5_player_session_reset <= 1'b0;
                    mode5_load_begin_count_i <= 32'd0;
                    mode5_load_done_edge_count_i <= 32'd0;
                    mode5_sound_reset_start_count_i <= 32'd0;
                    mode5_player_start_count_i <= 32'd0;
                    mode5_player_reset_count_i <= 32'd0;
                    mode5_playback_session_id_i <= 32'd0;
                    mode5_duplicate_start_blocked_count_i <= 32'd0;
                    mode5_player_end_count_i <= 32'd0;
                    mode5_repeat_restart_count_i <= 32'd0;
                    mode5_done_armed_i <= 1'b0;
                    mode5_done_armed_session_id_i <= 32'd0;
                    mode5_repeat_session_id_i <= 32'd0;
                    mode5_done_session_id_i <= 32'd0;
                    mode5_cycles_since_start_i <= 32'd0;
                    mode5_done_pc_debug_i <= '0;
                    mode5_done_cmd_debug_i <= 8'd0;
                    mode5_player_done_latched <= 1'b0;
                    player_done_d <= 1'b0;
                    vgm_player_error_d <= 1'b0;
                    mode5_error_session_id_i <= 32'd0;
                    mode5_repeat_state <= MODE5_REPEAT_IDLE;
                end else begin
                    ioctl_download_d <= ioctl_download;
                    player_done_d <= loaded_player_done;
                    vgm_player_error_d <= vgm_player_error;
                    mode5_player_start_pulse <= 1'b0;
                    mode5_player_session_reset <= 1'b0;

                    if (mode5_playback_started && player_busy && !loaded_player_done) begin
                        mode5_done_armed_i <= 1'b1;
                        mode5_done_armed_session_id_i <= mode5_playback_session_id_i;
                    end

                    if (mode5_playback_started && !loaded_player_done) begin
                        mode5_cycles_since_start_i <=
                            mode5_cycles_since_start_i + 32'd1;
                    end

                    if (mode5_done_edge) begin
                        mode5_player_end_count_i <=
                            mode5_player_end_count_i + 32'd1;
                        mode5_done_armed_i <= 1'b0;
                        mode5_done_armed_session_id_i <= 32'd0;
                        mode5_done_session_id_i <= mode5_playback_session_id_i;
                        mode5_done_pc_debug_i <= player_done_pc_debug;
                        mode5_done_cmd_debug_i <= player_done_cmd_debug;
                        mode5_player_done_latched <= 1'b1;
                    end

                    if (mode5_player_error_edge) begin
                        mode5_error_session_id_i <= mode5_playback_session_id_i;
                        mode5_playback_armed <= 1'b0;
                        mode5_playback_started <= 1'b0;
                        mode5_done_armed_i <= 1'b0;
                        mode5_done_armed_session_id_i <= 32'd0;
                        mode5_player_done_latched <= 1'b0;
                        mode5_repeat_state <= MODE5_REPEAT_IDLE;
                        mode5_sound_reset_active_i <= 1'b0;
                        mode5_sound_reset_counter <= 32'd0;
                    end

                    if (mode5_load_begin_pulse) begin
                        mode5_load_begin_count_i <= mode5_load_begin_count_i + 32'd1;
                        mode5_playback_session_id_i <= mode5_playback_session_id_i + 32'd1;
                        mode5_load_session_active <= 1'b1;
                        mode5_playback_armed <= 1'b0;
                        mode5_playback_started <= 1'b0;
                        mode5_done_armed_i <= 1'b0;
                        mode5_done_armed_session_id_i <= 32'd0;
                        mode5_player_done_latched <= 1'b0;
                        mode5_repeat_state <= MODE5_REPEAT_IDLE;
                        player_done_d <= loaded_player_done;
                        mode5_cycles_since_start_i <= 32'd0;
                        mode5_player_session_reset <= 1'b1;
                        mode5_player_reset_count_i <= mode5_player_reset_count_i + 32'd1;
                        mode5_sound_reset_active_i <= 1'b0;
                        mode5_sound_reset_counter <= 32'd0;
                    end else if (mode5_done_edge &&
                                 MODE5_REPEAT_ENABLE &&
                                 vgm_load_done &&
                                 vgm_header_valid &&
                                 !vgm_load_busy &&
                                 !vgm_load_error &&
                                 !vgm_load_overflow &&
                                 !vgm_player_error &&
                                 !mode5_load_session_active) begin
                        mode5_playback_armed <= 1'b0;
                        mode5_playback_started <= 1'b0;
                        mode5_done_armed_i <= 1'b0;
                        mode5_done_armed_session_id_i <= 32'd0;
                        mode5_player_done_latched <= 1'b0;
                        mode5_cycles_since_start_i <= 32'd0;
                        mode5_repeat_restart_count_i <=
                            mode5_repeat_restart_count_i + 32'd1;
                        mode5_playback_session_id_i <=
                            mode5_playback_session_id_i + 32'd1;
                        mode5_repeat_session_id_i <=
                            mode5_playback_session_id_i + 32'd1;
                        mode5_player_reset_count_i <=
                            mode5_player_reset_count_i + 32'd1;
                        mode5_sound_reset_counter <= 32'd0;
                        mode5_sound_reset_active_i <= 1'b0;
                        mode5_repeat_state <= MODE5_REPEAT_RESET;
                    end else if (play_ready_pulse) begin
                        mode5_load_done_edge_count_i <= mode5_load_done_edge_count_i + 32'd1;
                        mode5_load_session_active <= 1'b0;
                        mode5_playback_armed <= 1'b1;
                        mode5_playback_started <= 1'b0;
                        mode5_done_armed_i <= 1'b0;
                        mode5_done_armed_session_id_i <= 32'd0;
                        mode5_player_done_latched <= 1'b0;
                        mode5_repeat_state <= MODE5_REPEAT_IDLE;
                        mode5_repeat_session_id_i <= mode5_playback_session_id_i;
                        player_done_d <= loaded_player_done;
                        mode5_cycles_since_start_i <= 32'd0;
                        mode5_sound_reset_counter <= 32'd0;

                        if (MODE5_SOUND_RESET_CYCLES == 32'd0) begin
                            mode5_sound_reset_active_i <= 1'b0;
                            mode5_player_start_pulse <= 1'b1;
                            mode5_playback_started <= 1'b1;
                            mode5_done_armed_i <= 1'b0;
                            mode5_done_armed_session_id_i <= 32'd0;
                            mode5_cycles_since_start_i <= 32'd0;
                            mode5_player_start_count_i <= mode5_player_start_count_i + 32'd1;
                        end else begin
                            mode5_sound_reset_active_i <= 1'b1;
                            mode5_sound_reset_start_count_i <=
                                mode5_sound_reset_start_count_i + 32'd1;
                        end
                    end else if (vgm_load_busy || vgm_load_error || vgm_load_overflow) begin
                        mode5_sound_reset_active_i <= 1'b0;
                        mode5_sound_reset_counter <= 32'd0;
                        if (vgm_load_error || vgm_load_overflow) begin
                            mode5_load_session_active <= 1'b0;
                            mode5_playback_armed <= 1'b0;
                            mode5_playback_started <= 1'b0;
                            mode5_done_armed_i <= 1'b0;
                            mode5_done_armed_session_id_i <= 32'd0;
                            mode5_repeat_state <= MODE5_REPEAT_IDLE;
                            mode5_player_session_reset <= 1'b1;
                            mode5_player_reset_count_i <= mode5_player_reset_count_i + 32'd1;
                        end
                    end else if (mode5_repeat_state == MODE5_REPEAT_RESET) begin
                        mode5_player_session_reset <= 1'b1;
                        mode5_sound_reset_active_i <= 1'b0;
                        mode5_sound_reset_counter <= 32'd0;
                        mode5_repeat_state <= MODE5_REPEAT_WAIT_CLEAR;
                    end else if (mode5_repeat_state == MODE5_REPEAT_WAIT_CLEAR) begin
                        if (!loaded_player_done && !player_busy) begin
                            mode5_playback_armed <= 1'b1;
                            mode5_playback_started <= 1'b0;
                            mode5_cycles_since_start_i <= 32'd0;
                            if (MODE5_SOUND_RESET_CYCLES == 32'd0) begin
                                mode5_sound_reset_active_i <= 1'b0;
                                mode5_player_start_pulse <= 1'b1;
                                mode5_playback_started <= 1'b1;
                                mode5_done_armed_i <= 1'b0;
                                mode5_done_armed_session_id_i <= 32'd0;
                                mode5_player_start_count_i <=
                                    mode5_player_start_count_i + 32'd1;
                            end else begin
                                mode5_sound_reset_active_i <= 1'b1;
                                mode5_sound_reset_start_count_i <=
                                    mode5_sound_reset_start_count_i + 32'd1;
                            end
                            mode5_repeat_state <= MODE5_REPEAT_IDLE;
                        end
                    end else if (mode5_sound_reset_active_i) begin
                        if (mode5_sound_reset_counter >= (MODE5_SOUND_RESET_CYCLES - 32'd1)) begin
                            mode5_sound_reset_active_i <= 1'b0;
                            mode5_sound_reset_counter <= 32'd0;
                            if (mode5_playback_armed &&
                                !mode5_playback_started &&
                                vgm_load_done &&
                                !vgm_load_error &&
                                !vgm_load_overflow) begin
                                mode5_player_start_pulse <= 1'b1;
                                mode5_playback_started <= 1'b1;
                                mode5_done_armed_i <= 1'b0;
                                mode5_done_armed_session_id_i <= 32'd0;
                                mode5_cycles_since_start_i <= 32'd0;
                                mode5_player_start_count_i <=
                                    mode5_player_start_count_i + 32'd1;
                            end else if (mode5_playback_started) begin
                                mode5_duplicate_start_blocked_count_i <=
                                    mode5_duplicate_start_blocked_count_i + 32'd1;
                            end
                        end else begin
                            mode5_sound_reset_counter <= mode5_sound_reset_counter + 32'd1;
                        end
                    end else if (mode5_playback_armed &&
                                 mode5_playback_started &&
                                 vgm_load_done &&
                                 vgm_header_valid &&
                                 !player_busy &&
                                 !loaded_player_done) begin
                        mode5_duplicate_start_blocked_count_i <=
                            mode5_duplicate_start_blocked_count_i + 32'd1;
                    end
                end
            end

            assign mode5_sound_core_reset = mode5_sound_reset_active_i |
                                            vgm_load_busy |
                                            mode5_load_session_active |
                                            mode5_player_session_reset |
                                            vgm_load_error |
                                            vgm_load_overflow;
            assign mode5_sound_reset_active = mode5_sound_reset_active_i;
            assign mode5_player_start_pulse_debug = mode5_player_start_pulse;
            assign mode5_load_begin_count = mode5_load_begin_count_i;
            assign mode5_load_done_edge_count = mode5_load_done_edge_count_i;
            assign mode5_sound_reset_start_count = mode5_sound_reset_start_count_i;
            assign mode5_player_start_count = mode5_player_start_count_i;
            assign mode5_player_reset_count = mode5_player_reset_count_i;
            assign mode5_playback_session_id = mode5_playback_session_id_i;
            assign mode5_duplicate_start_blocked_count =
                mode5_duplicate_start_blocked_count_i;
            assign mode5_player_end_count = mode5_player_end_count_i;
            assign mode5_repeat_restart_count = mode5_repeat_restart_count_i;
            assign mode5_done_armed_debug = mode5_done_armed_i;
            assign mode5_repeat_session_id = mode5_repeat_session_id_i;
            assign mode5_done_session_id = mode5_done_session_id_i;
            assign mode5_cycles_since_start = mode5_cycles_since_start_i;
            assign mode5_done_pc_debug = mode5_done_pc_debug_i;
            assign mode5_done_cmd_debug = mode5_done_cmd_debug_i;
            assign vgm_error_session_id = mode5_error_session_id_i;
            assign player_done = mode5_player_done_latched;
            assign mode5_audio_pre_unmute = audio_gate_open &&
                                            vgm_load_done &&
                                            vgm_header_valid &&
                                            !vgm_load_busy &&
                                            !vgm_load_error &&
                                            !vgm_load_overflow &&
                                            !vgm_player_error &&
                                            !mode5_sound_core_reset &&
                                            player_busy;
            assign audio_runtime_open = mode5_audio_pre_unmute &&
                                        mode5_audio_unmute_ready;

            always_ff @(posedge clk) begin
                if (reset || !mode5_audio_pre_unmute) begin
                    mode5_audio_unmute_counter <= 32'd0;
                    mode5_audio_unmute_ready <= 1'b0;
                end else if (MODE5_AUDIO_UNMUTE_DELAY_CYCLES == 32'd0) begin
                    mode5_audio_unmute_counter <= 32'd0;
                    mode5_audio_unmute_ready <= 1'b1;
                end else if (mode5_audio_unmute_counter >= (MODE5_AUDIO_UNMUTE_DELAY_CYCLES - 32'd1)) begin
                    mode5_audio_unmute_ready <= 1'b1;
                end else begin
                    mode5_audio_unmute_counter <= mode5_audio_unmute_counter + 32'd1;
                    mode5_audio_unmute_ready <= 1'b0;
                end
            end

            if (MODE5_VGM_BACKEND == MODE5_BACKEND_BRAM) begin : backend_bram
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

                assign play_ready_pulse = load_done_pulse;
                assign ioctl_wait = 1'b0;

                vgm_bram_read_adapter #(
                    .ADDR_WIDTH       (VGM_LOAD_ADDR_WIDTH)
                ) bram_read_adapter (
                    .clk              (clk),
                    .reset            (reset),
                    .mem_rd_req       (mem_rd_req),
                    .mem_rd_addr      (mem_rd_addr),
                    .mem_rd_ready     (mem_rd_ready),
                    .mem_rd_valid     (mem_rd_valid),
                    .mem_rd_data      (mem_rd_data),
                    .bram_rd_addr     (ram_rd_addr),
                    .bram_rd_data     (ram_rd_data)
                );

                assign ddram_burstcnt = 8'd0;
                assign ddram_addr     = 29'd0;
                assign ddram_rd       = 1'b0;
                assign ddram_din      = 64'd0;
                assign ddram_be       = 8'd0;
                assign ddram_we       = 1'b0;
            end else if (MODE5_VGM_BACKEND == MODE5_BACKEND_DDRAM) begin : backend_ddram
                vgm_ddram_backend #(
                    .ADDR_WIDTH       (VGM_LOAD_ADDR_WIDTH),
                    .ACCEPT_ANY_INDEX (1'b0),
                    .FILE_INDEX       (VGM_LOAD_FILE_INDEX),
                    .WRITE_FIFO_DEPTH (1024),
                    // Match the common MiSTer DDRAM window used by PSX/GBA:
                    // DDRAM_ADDR[28:25] = 4'b0011 maps to 0x30000000.
                    .DDRAM_BASE_ADDR  ({4'b0011, 25'd0})
                ) ddram_backend (
                    .clk              (clk),
                    .reset            (reset),
                    .ioctl_download   (ioctl_download),
                    .ioctl_wr         (ioctl_wr),
                    .ioctl_addr       (ioctl_addr),
                    .ioctl_dout       (ioctl_dout),
                    .ioctl_index      (ioctl_index),
                    .ioctl_wait       (ioctl_wait),

                    .mem_rd_req       (mem_rd_req),
                    .mem_rd_addr      (mem_rd_addr),
                    .mem_rd_ready     (mem_rd_ready),
                    .mem_rd_valid     (mem_rd_valid),
                    .mem_rd_data      (mem_rd_data),

                    .load_busy        (vgm_load_busy),
                    .load_done        (vgm_load_done),
                    .load_done_pulse  (load_done_pulse),
                    .play_ready_pulse (play_ready_pulse),
                    .load_error       (vgm_load_error),
                    .overflow_error   (vgm_load_overflow),
                    .file_size        (vgm_load_size),
                    .magic_debug      (vgm_load_magic),

                    .ddram_busy       (ddram_busy),
                    .ddram_burstcnt   (ddram_burstcnt),
                    .ddram_addr       (ddram_addr),
                    .ddram_dout       (ddram_dout),
                    .ddram_dout_ready (ddram_dout_ready),
                    .ddram_rd         (ddram_rd),
                    .ddram_din        (ddram_din),
                    .ddram_be         (ddram_be),
                    .ddram_we         (ddram_we)
                );
            end else begin : backend_reserved
                assign mem_rd_ready = 1'b0;
                assign mem_rd_valid = 1'b0;
                assign mem_rd_data = 8'd0;
                assign load_done_pulse = 1'b0;
                assign play_ready_pulse = 1'b0;
                assign ioctl_wait = 1'b0;
                assign vgm_load_busy = 1'b0;
                assign vgm_load_done = 1'b0;
                assign vgm_load_error = 1'b1;
                assign vgm_load_overflow = 1'b1;
                assign vgm_load_size = '0;
                assign vgm_load_magic = 32'd0;

                assign ddram_burstcnt = 8'd0;
                assign ddram_addr     = 29'd0;
                assign ddram_rd       = 1'b0;
                assign ddram_din      = 64'd0;
                assign ddram_be       = 8'd0;
                assign ddram_we       = 1'b0;
            end

            vgm_loaded_player #(
                .ADDR_WIDTH (VGM_LOAD_ADDR_WIDTH)
            ) loaded_player (
                .clk                   (clk),
                .reset                 (reset |
                                         player_reset_active |
                                         mode5_sound_core_reset),
                .start                 (mode5_player_start_pulse),
                .load_done             (vgm_load_done),
                .load_done_pulse       (1'b0),
                .load_error            (vgm_load_error),
                .overflow_error        (vgm_load_overflow),
                .file_size             (vgm_load_size),
                .vgm_wait_tick         (vgm_wait_tick),
                .mem_rd_req            (mem_rd_req),
                .mem_rd_addr           (mem_rd_addr),
                .mem_rd_ready          (mem_rd_ready),
                .mem_rd_valid          (mem_rd_valid),
                .mem_rd_data           (mem_rd_data),
                .ym_cmd_ready          (ym_cmd_ready),
                .psg_cmd_ready         (psg_cmd_ready),
                .ym_cmd_valid          (ym_cmd_valid),
                .ym_cmd_port           (ym_cmd_port),
                .ym_cmd_reg            (ym_cmd_reg),
                .ym_cmd_data           (ym_cmd_data),
                .psg_cmd_valid         (psg_cmd_valid),
                .psg_cmd_data          (psg_cmd_data),
                .busy                  (player_busy),
                .done                  (loaded_player_done),
                .header_valid          (vgm_header_valid),
                .player_error          (vgm_player_error),
                .unsupported_opcode    (vgm_unsupported_opcode),
                .unsupported_pc        (vgm_unsupported_pc),
                .player_error_code     (vgm_player_error_code),
                .error_pc_debug        (vgm_error_pc_debug),
                .error_cmd_debug       (vgm_error_cmd_debug),
                .state_debug           (vgm_player_state_debug),
                .mem_rd_req_debug      (vgm_mem_rd_req_debug),
                .mem_rd_ready_debug    (vgm_mem_rd_ready_debug),
                .mem_rd_valid_debug    (vgm_mem_rd_valid_debug),
                .mem_rd_addr_debug     (vgm_mem_rd_addr_debug),
                .data_start_debug      (vgm_data_start_debug),
                .current_pc_debug      (vgm_current_pc_debug),
                .loop_pc_debug         (vgm_loop_pc_debug),
                .loop_valid_debug      (vgm_loop_valid_debug),
                .loop_taken_debug      (vgm_loop_taken_debug),
                .end_command_seen      (vgm_end_command_seen),
                .restarted_from_data_start(vgm_restarted_from_data_start),
                .pcm_oob               (vgm_pcm_oob),
                .pcm_oob_count         (vgm_pcm_oob_count),
                .wait_ticks_consumed_debug(vgm_wait_ticks_consumed_debug),
                .done_pc_debug         (player_done_pc_debug),
                .done_cmd_debug        (player_done_cmd_debug),
                .pc_debug              (player_pc_debug),
                .last_cmd_debug        (player_last_cmd_debug)
            );

            md_sound_module sound (
                .clk                   (clk),
                .reset                 (reset | mode5_sound_core_reset),
                .ym_cmd_valid          (ym_cmd_valid),
                .ym_cmd_port           (ym_cmd_port),
                .ym_cmd_reg            (ym_cmd_reg),
                .ym_cmd_data           (ym_cmd_data),
                .psg_cmd_valid         (psg_cmd_valid),
                .psg_cmd_data          (psg_cmd_data),
                .ym_cmd_ready          (ym_cmd_ready),
                .psg_cmd_ready         (psg_cmd_ready),
                .audio_l               (raw_audio_l),
                .audio_r               (raw_audio_r),
                .audio_sample_valid    (raw_audio_sample_valid),
                .audio_lpf_mode        (audio_lpf_mode),
                .audio_gain_boost      (audio_gain_boost),
                .audio_psg_level       (audio_psg_level),
                .fm_adjust_clip_count_l(fm_adjust_clip_count_l),
                .fm_adjust_clip_count_r(fm_adjust_clip_count_r),
                .genmix_wrap_count_l   (genmix_wrap_count_l),
                .genmix_wrap_count_r   (genmix_wrap_count_r),
                .ym_write_requested_count(ym_write_requested_count),
                .ym_write_accepted_count(ym_write_accepted_count),
                .ym_write_dropped_or_busy_count(ym_write_dropped_or_busy_count),
                .ym_port0_count        (ym_port0_count),
                .ym_port1_count        (ym_port1_count),
                .last_ym_port          (last_ym_port),
                .last_ym_addr          (last_ym_addr),
                .last_ym_data          (last_ym_data),
                .jt12_cen_interval_1_count(jt12_cen_interval_1_count),
                .jt12_cen_interval_2_count(jt12_cen_interval_2_count),
                .jt12_cen_interval_3_count(jt12_cen_interval_3_count),
                .jt12_cen_interval_4_count(jt12_cen_interval_4_count),
                .jt12_cen_interval_ge5_count(jt12_cen_interval_ge5_count),
                .jt12_cen_interval_min(jt12_cen_interval_min),
                .jt12_cen_interval_max(jt12_cen_interval_max),
                .jt12_cen_interval_last(jt12_cen_interval_last),
                .fm_raw_abs_peak      (fm_raw_abs_peak),
                .fm_adjust_abs_peak   (fm_adjust_abs_peak),
                .fm_lpf_abs_peak      (fm_lpf_abs_peak),
                .genmix_abs_peak      (genmix_abs_peak),
                .final_audio_abs_peak (md_final_audio_abs_peak)
            );
        end else begin : fixed_region_mode
            assign vgm_load_busy = 1'b0;
            assign vgm_load_done = 1'b0;
            assign vgm_load_error = 1'b0;
            assign vgm_load_overflow = 1'b0;
            assign vgm_header_valid = 1'b0;
            assign vgm_player_error = 1'b0;
            assign vgm_unsupported_opcode = 8'd0;
            assign vgm_unsupported_pc = '0;
            assign vgm_player_error_code = 8'd0;
            assign vgm_error_pc_debug = '0;
            assign vgm_error_cmd_debug = 8'd0;
            assign vgm_error_session_id = 32'd0;
            assign vgm_player_state_debug = 6'd0;
            assign vgm_mem_rd_req_debug = 1'b0;
            assign vgm_mem_rd_ready_debug = 1'b0;
            assign vgm_mem_rd_valid_debug = 1'b0;
            assign vgm_mem_rd_addr_debug = '0;
            assign vgm_load_size = '0;
            assign vgm_load_magic = 32'd0;
            assign vgm_data_start_debug = '0;
            assign vgm_current_pc_debug = '0;
            assign vgm_loop_pc_debug = '0;
            assign vgm_loop_valid_debug = 1'b0;
            assign vgm_loop_taken_debug = 1'b0;
            assign vgm_end_command_seen = 1'b0;
            assign vgm_restarted_from_data_start = 1'b0;
            assign vgm_pcm_oob = 1'b0;
            assign vgm_pcm_oob_count = 32'd0;
            assign vgm_wait_ticks_consumed_debug = 32'd0;
            assign mode5_sound_reset_active = 1'b0;
            assign mode5_player_start_pulse_debug = 1'b0;
            assign mode5_load_begin_count = 32'd0;
            assign mode5_load_done_edge_count = 32'd0;
            assign mode5_sound_reset_start_count = 32'd0;
            assign mode5_player_start_count = 32'd0;
            assign mode5_player_reset_count = 32'd0;
            assign mode5_playback_session_id = 32'd0;
            assign mode5_duplicate_start_blocked_count = 32'd0;
            assign mode5_player_end_count = 32'd0;
            assign mode5_repeat_restart_count = 32'd0;
            assign mode5_done_armed_debug = 1'b0;
            assign mode5_repeat_session_id = 32'd0;
            assign mode5_done_session_id = 32'd0;
            assign mode5_cycles_since_start = 32'd0;
            assign mode5_done_pc_debug = '0;
            assign mode5_done_cmd_debug = 8'd0;
            assign audio_runtime_open = audio_gate_open;
            assign ioctl_wait = 1'b0;

            md_sound_fixed_region_test #(
                .REGION_MODE (REGION_MODE)
            ) fixed_region (
                .clk                   (clk),
                .reset                 (reset),
                .player_reset          (player_reset_active),
                .start                 (start_pulse),
                .vgm_wait_tick         (vgm_wait_tick),
                .audio_l               (raw_audio_l),
                .audio_r               (raw_audio_r),
                .audio_sample_valid    (raw_audio_sample_valid),
                .audio_lpf_mode        (audio_lpf_mode),
                .audio_gain_boost      (audio_gain_boost),
                .audio_psg_level       (audio_psg_level),
                .player_busy           (player_busy),
                .player_done           (player_done),
                .player_pc_debug       (player_pc_debug),
                .player_last_cmd_debug (player_last_cmd_debug),
                .fm_adjust_clip_count_l(fm_adjust_clip_count_l),
                .fm_adjust_clip_count_r(fm_adjust_clip_count_r),
                .genmix_wrap_count_l   (genmix_wrap_count_l),
                .genmix_wrap_count_r   (genmix_wrap_count_r),
                .ym_write_requested_count(ym_write_requested_count),
                .ym_write_accepted_count(ym_write_accepted_count),
                .ym_write_dropped_or_busy_count(ym_write_dropped_or_busy_count),
                .ym_port0_count        (ym_port0_count),
                .ym_port1_count        (ym_port1_count),
                .last_ym_port          (last_ym_port),
                .last_ym_addr          (last_ym_addr),
                .last_ym_data          (last_ym_data),
                .jt12_cen_interval_1_count(jt12_cen_interval_1_count),
                .jt12_cen_interval_2_count(jt12_cen_interval_2_count),
                .jt12_cen_interval_3_count(jt12_cen_interval_3_count),
                .jt12_cen_interval_4_count(jt12_cen_interval_4_count),
                .jt12_cen_interval_ge5_count(jt12_cen_interval_ge5_count),
                .jt12_cen_interval_min(jt12_cen_interval_min),
                .jt12_cen_interval_max(jt12_cen_interval_max),
                .jt12_cen_interval_last(jt12_cen_interval_last),
                .fm_raw_abs_peak      (fm_raw_abs_peak),
                .fm_adjust_abs_peak   (fm_adjust_abs_peak),
                .fm_lpf_abs_peak      (fm_lpf_abs_peak),
                .genmix_abs_peak      (genmix_abs_peak),
                .final_audio_abs_peak (md_final_audio_abs_peak)
            );
        end
    endgenerate

endmodule

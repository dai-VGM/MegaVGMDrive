`timescale 1ns/1ps

module ym2610_hw0_top #(
    parameter bit FAST_SIM = 1'b0,
    parameter integer BOOT_SAMPLES = 159801,
    parameter integer COLOR_PREROLL_SAMPLES = 53267,
    parameter integer SOUND_DWELL_SAMPLES = 213068,
    parameter integer INTER_SILENCE_SAMPLES = 79901,
    parameter integer PAN_DWELL_SAMPLES = 159801,
    parameter integer PAN_INTER_SAMPLES = 53267,
    parameter integer NATURAL_SILENCE_SAMPLES = 79901,
    parameter integer FINAL_SILENCE_SAMPLES = 159801,
    parameter integer ZERO_TIMEOUT_SAMPLES = 8192,
    parameter integer ZERO_CONFIRM_SAMPLES = 32,
    parameter integer REFERENCE_DWELL_SAMPLES = 159801,
    parameter integer REFERENCE_GAP_SAMPLES = 53267,
    parameter integer PCM_ATTEMPT_SAMPLES = 53267,
    parameter integer A0_ATTEMPT_SAMPLES = PCM_ATTEMPT_SAMPLES,
    parameter integer A6_ATTEMPT_SAMPLES = PCM_ATTEMPT_SAMPLES,
    parameter integer B_ATTEMPT_SAMPLES = PCM_ATTEMPT_SAMPLES,
    parameter integer PCM_ATTEMPT_GAP_SAMPLES = 26634,
    parameter integer PCM_RESULT_SAMPLES = 159801,
    parameter integer SUMMARY_SAMPLES = 532670
) (
    input  logic               clk_sys,
    input  logic               reset,
    input  logic               video_reset,
    output logic signed [15:0] audio_l,
    output logic signed [15:0] audio_r,
    output logic               audio_sample,
    output logic               video_ce,
    output logic               video_hs,
    output logic               video_vs,
    output logic               video_de,
    output logic         [7:0] video_r,
    output logic         [7:0] video_g,
    output logic         [7:0] video_b,
    output logic         [3:0] debug_phase,
    output logic         [6:0] debug_segment_state,
    output logic         [2:0] debug_startup_state,
    output logic               debug_external_mute,
    output logic               debug_sample_tick,
    output logic        [31:0] debug_sample_tick_count,
    output logic               debug_sample_cadence_error,
    output logic               debug_sample_width_error,
    output logic         [7:0] debug_microcode_index,
    output logic        [31:0] debug_accepted_writes,
    output logic               debug_busy_timeout,
    output logic               debug_write_while_busy,
    output logic               debug_zero_timeout,
    output logic               debug_phase_error,
    output logic        [15:0] debug_restart_count,
    output logic               debug_measurement_active,
    output logic         [3:0] debug_measurement_phase,
    output logic               debug_adpcma_request,
    output logic               debug_adpcmb_request,
    output logic         [5:0] debug_adpcma_eos,
    output logic               debug_adpcmb_eos,
    output logic               debug_adpcmb_active,
    output logic        [19:0] debug_adpcma_addr,
    output logic         [3:0] debug_adpcma_bank,
    output logic        [23:0] debug_adpcmb_addr,
    output logic         [7:0] debug_psg_a,
    output logic         [7:0] debug_psg_b,
    output logic         [7:0] debug_psg_c,
    output logic         [9:0] debug_psg_snd,
    output logic               debug_core_ready,
    output logic         [2:0] debug_reset_cen_count,
    output logic signed [15:0] debug_adpcma_left,
    output logic signed [15:0] debug_adpcma_right,
    output logic signed [15:0] debug_adpcmb_left,
    output logic signed [15:0] debug_adpcmb_right,
    output logic signed [15:0] debug_jt10_final_left,
    output logic signed [15:0] debug_jt10_final_right,
    output logic signed [15:0] debug_premute_left,
    output logic signed [15:0] debug_premute_right,
    output logic         [2:0] debug_diag_phase,
    output logic         [2:0] debug_diag_attempt,
    output logic         [2:0] debug_diag_completed_attempts,
    output logic               debug_diag_attempt_active,
    output logic         [6:0] debug_diag_seen,
    output logic         [6:0] debug_diag_fail,
    output logic        [34:0] debug_diag_summary,
    output logic         [4:0] debug_diag_summary_valid,
    output logic        [27:0] debug_diag_event_counts,
    output logic       [111:0] debug_diag_first_ticks,
    output logic         [7:0] debug_diag_request_count,
    output logic        [23:0] debug_diag_first_addr,
    output logic        [23:0] debug_diag_last_addr,
    output logic         [7:0] debug_diag_address_changes,
    output logic         [7:0] debug_diag_distinct_addresses,
    output logic         [3:0] debug_last_error_code,
    output logic               debug_summary_active,
    output logic               debug_halted
);
    localparam logic [24:0] JT10_NTSC_CEN_INC = 25'd6434443;

    logic [23:0] cen_accum;
    logic [24:0] cen_sum;
    logic        jt10_cen;
    logic [8:0]  chip_cycle_mod432;

    logic [1:0] bus_addr;
    logic [7:0] bus_din;
    logic       bus_cs_n;
    logic       bus_wr_n;
    logic [7:0] bus_dout;
    logic       irq_n;
    logic signed [15:0] core_left;
    logic signed [15:0] core_right;
    logic       core_sample;
    logic signed [15:0] internal_left;
    logic signed [15:0] internal_right;
    logic       internal_sample;
    logic [5:0] adpcma_command;
    logic       adpcmb_command_update;
    logic signed [15:0] adpcma_left;
    logic signed [15:0] adpcma_right;
    logic signed [15:0] adpcmb_left;
    logic signed [15:0] adpcmb_right;
    logic [7:0] adpcma_data;
    logic [7:0] adpcmb_data;
    logic       adpcma_roe_n;
    logic       adpcmb_roe_n;
    logic [2:0] test_reset_pipe;
    logic [2:0] video_reset_pipe;
    logic       test_reset;
    logic       video_timing_reset;
    logic       sequencer_mute;
    logic       sample_valid_d;
    logic       sample_valid_cen_d;
    logic       sample_seen;
    logic [7:0] sample_period_cen;
    logic [3:0] sample_width_cen;
    logic [3:0] sequencer_error_code;
    logic [2:0] diag_phase_index;
    logic [2:0] diag_attempt_index;
    logic       diag_phase_begin;
    logic       diag_attempt_begin;
    logic       diag_attempt_end;
    logic       diag_stop_pass;
    logic       diag_pan_right;
    logic       diag_summary_active;
    logic       diag_attempt_active;
    logic       diag_rom_range_error;
    logic       diag_raw_request;
    logic       diag_capture_event;
    logic [3:0] diag_last_error_code;
    logic [23:0] diag_rom_address;
    logic [7:0] diag_rom_data;
    logic signed [15:0] diag_lane_left;
    logic signed [15:0] diag_lane_right;

    always_ff @(posedge clk_sys or posedge reset) begin
        if (reset) test_reset_pipe <= 3'b111;
        else test_reset_pipe <= {test_reset_pipe[1:0], 1'b0};
    end
    assign test_reset = test_reset_pipe[2];

    always_ff @(posedge clk_sys or posedge video_reset) begin
        if (video_reset) video_reset_pipe <= 3'b111;
        else video_reset_pipe <= {video_reset_pipe[1:0], 1'b0};
    end
    assign video_timing_reset = video_reset_pipe[2];

    assign cen_sum = {1'b0, cen_accum} + JT10_NTSC_CEN_INC;

    always_ff @(posedge clk_sys) begin
        if (test_reset) begin
            cen_accum <= 24'd0;
            jt10_cen <= 1'b1;
        end else if (FAST_SIM) begin
            cen_accum <= 24'd0;
            jt10_cen <= 1'b1;
        end else begin
            cen_accum <= cen_sum[23:0];
            jt10_cen <= cen_sum[24];
        end
    end

    always_ff @(posedge clk_sys) begin
        if (test_reset) chip_cycle_mod432 <= 9'd0;
        else if (jt10_cen) begin
            if (chip_cycle_mod432 == 9'd431)
                chip_cycle_mod432 <= 9'd0;
            else chip_cycle_mod432 <= chip_cycle_mod432 + 9'd1;
        end
    end

    ym2610_hw0_adpcma_rom u_rom_a (
        .address(debug_adpcma_addr), .bank(debug_adpcma_bank),
        .data(adpcma_data)
    );
    ym2610_hw0_adpcmb_rom u_rom_b (
        .address(debug_adpcmb_addr), .data(adpcmb_data)
    );

    ym2610_hw0_jt10_wrapper u_jt10 (
        .clk(clk_sys), .rst(test_reset), .cen(jt10_cen),
        .bus_addr(bus_addr), .bus_din(bus_din),
        .bus_cs_n(bus_cs_n), .bus_wr_n(bus_wr_n),
        .bus_dout(bus_dout), .irq_n(irq_n),
        .snd_left(core_left), .snd_right(core_right),
        .snd_sample(core_sample),
        .psg_a(debug_psg_a), .psg_b(debug_psg_b),
        .psg_c(debug_psg_c), .psg_snd(debug_psg_snd),
        .adpcma_addr(debug_adpcma_addr),
        .adpcma_bank(debug_adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n),
        .adpcma_data(adpcma_data),
        .adpcmb_addr(debug_adpcmb_addr),
        .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(adpcmb_data),
        .ready(debug_core_ready),
        .reset_cen_count(debug_reset_cen_count),
        .adpcma_eos(debug_adpcma_eos),
        .adpcma_command(adpcma_command),
        .adpcma_left(adpcma_left), .adpcma_right(adpcma_right),
        .adpcmb_eos(debug_adpcmb_eos),
        .adpcmb_active(debug_adpcmb_active),
        .adpcmb_command_update(adpcmb_command_update),
        .adpcmb_left(adpcmb_left), .adpcmb_right(adpcmb_right),
        .internal_left(internal_left), .internal_right(internal_right),
        .internal_sample(internal_sample)
    );

    assign debug_adpcma_left = adpcma_left;
    assign debug_adpcma_right = adpcma_right;
    assign debug_adpcmb_left = adpcmb_left;
    assign debug_adpcmb_right = adpcmb_right;
    assign debug_jt10_final_left = internal_left;
    assign debug_jt10_final_right = internal_right;
    assign debug_premute_left = core_left;
    assign debug_premute_right = core_right;

    // ROM output-enable pins are active low; expose active-high requests.
    always_comb begin
        debug_adpcma_request = !adpcma_roe_n;
        debug_adpcmb_request = !adpcmb_roe_n;
    end

    // JT10's public sample-valid stays high for six CENs.  Collapse only its
    // 0->1 transition into the single system-clock pulse used by every HW-0
    // duration counter; the audio-valid level itself remains unchanged.
    assign debug_sample_tick = !test_reset && core_sample && !sample_valid_d;

    always_ff @(posedge clk_sys) begin
        if (test_reset || !debug_core_ready) begin
            sample_valid_d <= 1'b0;
            sample_valid_cen_d <= 1'b0;
            sample_seen <= 1'b0;
            sample_period_cen <= 8'd0;
            sample_width_cen <= 4'd0;
            debug_sample_cadence_error <= 1'b0;
            debug_sample_width_error <= 1'b0;
        end else begin
            sample_valid_d <= core_sample;
            if (jt10_cen) begin
                if (core_sample && !sample_valid_cen_d) begin
                    if (sample_seen && sample_period_cen != 8'd144)
                        debug_sample_cadence_error <= 1'b1;
                    sample_seen <= 1'b1;
                    sample_period_cen <= 8'd1;
                    sample_width_cen <= 4'd1;
                end else begin
                    if (sample_seen && sample_period_cen < 8'hff)
                        sample_period_cen <= sample_period_cen + 8'd1;
                    if (sample_seen && sample_period_cen >= 8'd144)
                        debug_sample_cadence_error <= 1'b1;
                    if (core_sample)
                        sample_width_cen <= sample_width_cen + 4'd1;
                    else if (sample_valid_cen_d) begin
                        if (sample_width_cen != 4'd6)
                            debug_sample_width_error <= 1'b1;
                        sample_width_cen <= 4'd0;
                    end
                end
                sample_valid_cen_d <= core_sample;
            end
        end
    end

    ym2610_hw0_sequencer #(
        .BOOT_SAMPLES(BOOT_SAMPLES),
        .COLOR_PREROLL_SAMPLES(COLOR_PREROLL_SAMPLES),
        .SOUND_DWELL_SAMPLES(SOUND_DWELL_SAMPLES),
        .INTER_SILENCE_SAMPLES(INTER_SILENCE_SAMPLES),
        .PAN_DWELL_SAMPLES(PAN_DWELL_SAMPLES),
        .PAN_INTER_SAMPLES(PAN_INTER_SAMPLES),
        .NATURAL_SILENCE_SAMPLES(NATURAL_SILENCE_SAMPLES),
        .FINAL_SILENCE_SAMPLES(FINAL_SILENCE_SAMPLES),
        .ZERO_TIMEOUT_SAMPLES(ZERO_TIMEOUT_SAMPLES),
        .ZERO_CONFIRM_SAMPLES(ZERO_CONFIRM_SAMPLES),
        .REFERENCE_DWELL_SAMPLES(REFERENCE_DWELL_SAMPLES),
        .REFERENCE_GAP_SAMPLES(REFERENCE_GAP_SAMPLES),
        .PCM_ATTEMPT_SAMPLES(PCM_ATTEMPT_SAMPLES),
        .A0_ATTEMPT_SAMPLES(A0_ATTEMPT_SAMPLES),
        .A6_ATTEMPT_SAMPLES(A6_ATTEMPT_SAMPLES),
        .B_ATTEMPT_SAMPLES(B_ATTEMPT_SAMPLES),
        .PCM_ATTEMPT_GAP_SAMPLES(PCM_ATTEMPT_GAP_SAMPLES),
        .PCM_RESULT_SAMPLES(PCM_RESULT_SAMPLES),
        .SUMMARY_SAMPLES(SUMMARY_SAMPLES)
    ) u_sequencer (
        .clk(clk_sys), .reset(test_reset), .core_ready(debug_core_ready),
        .audio_zero(internal_left == 16'sd0 &&
                    internal_right == 16'sd0),
        .sample_tick(debug_sample_tick),
        .sample_contract_error(debug_sample_cadence_error ||
                               debug_sample_width_error),
        .chip_cycle_mod432(chip_cycle_mod432), .bus_dout(bus_dout),
        .adpcmb_eos(debug_adpcmb_eos),
        .adpcmb_active(debug_adpcmb_active),
        .adpcma_request(debug_adpcma_request),
        .adpcmb_request(debug_adpcmb_request),
        .diag_rom_range_error(diag_rom_range_error),
        .bus_addr(bus_addr), .bus_din(bus_din),
        .bus_cs_n(bus_cs_n), .bus_wr_n(bus_wr_n),
        .display_phase(debug_phase),
        .segment_state(debug_segment_state),
        .startup_state(debug_startup_state),
        .audio_mute(sequencer_mute),
        .sample_tick_count(debug_sample_tick_count),
        .microcode_index(debug_microcode_index),
        .accepted_write_count(debug_accepted_writes),
        .busy_timeout(debug_busy_timeout),
        .write_while_busy(debug_write_while_busy),
        .zero_timeout(debug_zero_timeout),
        .phase_error(debug_phase_error),
        .sequence_restart_count(debug_restart_count),
        .measurement_active(debug_measurement_active),
        .measurement_phase(debug_measurement_phase),
        .diag_phase_index(diag_phase_index),
        .diag_attempt_index(diag_attempt_index),
        .diag_phase_begin(diag_phase_begin),
        .diag_attempt_begin(diag_attempt_begin),
        .diag_attempt_end(diag_attempt_end),
        .diag_stop_pass(diag_stop_pass),
        .diag_pan_right(diag_pan_right),
        .summary_active(diag_summary_active),
        .fatal_error_code(sequencer_error_code),
        .halted(debug_halted)
    );

    assign debug_external_mute = reset || test_reset || !debug_core_ready ||
                                 sequencer_mute || debug_halted;
    assign audio_l = debug_external_mute ? 16'sd0 : core_left;
    assign audio_r = debug_external_mute ? 16'sd0 : core_right;
    assign audio_sample = (reset || test_reset || debug_halted) ?
                          1'b0 : core_sample;

    always_comb begin
        if (diag_phase_index <= 3'd1) begin
            diag_raw_request = debug_adpcma_request;
            diag_rom_address = {debug_adpcma_bank, debug_adpcma_addr};
            diag_rom_data = adpcma_data;
            diag_lane_left = adpcma_left;
            diag_lane_right = adpcma_right;
        end else begin
            diag_raw_request = debug_adpcmb_request;
            diag_rom_address = debug_adpcmb_addr;
            diag_rom_data = adpcmb_data;
            diag_lane_left = adpcmb_left;
            diag_lane_right = adpcmb_right;
        end
        // Both HW-0 ROMs are zero-wait-state combinational fixtures, so a
        // request with the public address/data pins present is the qualified
        // capture transaction.  Simulation separately rejects X/Z.
        diag_capture_event = diag_attempt_active && diag_raw_request;
        diag_rom_range_error = 1'b0;
        if (diag_capture_event) begin
            case (diag_phase_index)
                3'd0: diag_rom_range_error =
                    debug_adpcma_bank != 4'd0 ||
                    debug_adpcma_addr > 20'h00fff;
                3'd1: diag_rom_range_error =
                    debug_adpcma_bank > 4'd5 ||
                    debug_adpcma_addr > 20'h014ff;
                3'd2, 3'd3: diag_rom_range_error =
                    debug_adpcmb_addr[23:16] != 8'd0 ||
                    debug_adpcmb_addr[15:8] < 8'h20 ||
                    debug_adpcmb_addr[15:8] > 8'h4f;
                default: diag_rom_range_error =
                    debug_adpcmb_addr[23:16] != 8'd0 ||
                    debug_adpcmb_addr[15:8] != 8'h20;
            endcase
        end
    end

    ym2610_hw0_pcm_diag_monitor u_pcm_diag (
        .clk(clk_sys), .reset(test_reset),
        .sample_tick(debug_sample_tick),
        .sample_tick_count(debug_sample_tick_count),
        .phase_index(diag_phase_index),
        .attempt_index(diag_attempt_index),
        .phase_begin(diag_phase_begin),
        .attempt_begin(diag_attempt_begin),
        .attempt_end(diag_attempt_end),
        .stop_pass(diag_stop_pass), .pan_right(diag_pan_right),
        .raw_request(diag_raw_request),
        .capture_event(diag_capture_event),
        .rom_address(diag_rom_address), .rom_data(diag_rom_data),
        .lane_left(diag_lane_left), .lane_right(diag_lane_right),
        .final_left(internal_left), .final_right(internal_right),
        .output_left(audio_l), .output_right(audio_r),
        .attempt_active(diag_attempt_active),
        .status_seen(debug_diag_seen), .status_fail(debug_diag_fail),
        .summary_pass(debug_diag_summary),
        .summary_valid(debug_diag_summary_valid),
        .event_counts(debug_diag_event_counts),
        .first_event_ticks(debug_diag_first_ticks),
        .request_count(debug_diag_request_count),
        .first_address(debug_diag_first_addr),
        .last_address(debug_diag_last_addr),
        .address_change_count(debug_diag_address_changes),
        .distinct_address_count(debug_diag_distinct_addresses),
        .completed_attempt_count(debug_diag_completed_attempts),
        .last_error_code(diag_last_error_code)
    );

    assign debug_diag_phase = diag_phase_index;
    assign debug_diag_attempt = diag_attempt_index;
    assign debug_diag_attempt_active = diag_attempt_active;
    assign debug_summary_active = diag_summary_active;

    assign debug_last_error_code = debug_halted ? sequencer_error_code :
                                                   diag_last_error_code;

    ym2610_hw0_video u_video (
        .clk(clk_sys), .reset(video_timing_reset),
        .phase(reset ? 4'd0 : debug_phase),
        .error(reset ? 1'b0 : debug_halted),
        .error_code(debug_last_error_code),
        .diag_seen(debug_diag_seen), .diag_fail(debug_diag_fail),
        .diag_attempt(diag_attempt_index),
        .diag_completed_attempts(debug_diag_completed_attempts),
        .diag_attempt_active(diag_attempt_active),
        .diag_summary(debug_diag_summary),
        .diag_summary_valid(debug_diag_summary_valid),
        .summary_active(diag_summary_active), .ce_pixel(video_ce),
        .hsync(video_hs), .vsync(video_vs), .de(video_de),
        .r(video_r), .g(video_g), .b(video_b)
    );
endmodule

// HW-0-only synthesizable PCM path observer.  It consumes only explicitly
// routed/public signals; it never controls JT10, ROM data, gain, or audio.
module ym2610_hw0_pcm_diag_monitor (
    input  logic               clk,
    input  logic               reset,
    input  logic               sample_tick,
    input  logic        [31:0] sample_tick_count,
    input  logic         [2:0] phase_index,
    input  logic         [2:0] attempt_index,
    input  logic               phase_begin,
    input  logic               attempt_begin,
    input  logic               attempt_end,
    input  logic               stop_pass,
    input  logic               pan_right,
    input  logic               raw_request,
    input  logic               capture_event,
    input  logic        [23:0] rom_address,
    input  logic         [7:0] rom_data,
    input  logic signed [15:0] lane_left,
    input  logic signed [15:0] lane_right,
    input  logic signed [15:0] final_left,
    input  logic signed [15:0] final_right,
    input  logic signed [15:0] output_left,
    input  logic signed [15:0] output_right,
    output logic               attempt_active,
    output logic         [6:0] status_seen,
    output logic         [6:0] status_fail,
    output logic        [34:0] summary_pass,
    output logic         [4:0] summary_valid,
    output logic        [27:0] event_counts,
    output logic       [111:0] first_event_ticks,
    output logic         [7:0] request_count,
    output logic        [23:0] first_address,
    output logic        [23:0] last_address,
    output logic         [7:0] address_change_count,
    output logic         [7:0] distinct_address_count,
    output logic         [2:0] completed_attempt_count,
    output logic         [3:0] last_error_code
);
    logic first_capture_valid;
    logic [7:0] first_data;
    logic address_progress_seen;
    logic data_changed_seen;
    logic expected_output_seen;
    logic opposite_output_seen;
    wire pan_stop_pass = phase_index != 3'd3 ||
                         (expected_output_seen && !opposite_output_seen);
    wire completed_stop = stop_pass && pan_stop_pass;
    wire [6:0] completed_result = {completed_stop, status_seen[5:0]};

    task automatic mark_event(input integer index);
        begin
            status_seen[index] <= 1'b1;
            if (event_counts[index*4 +: 4] != 4'hf)
                event_counts[index*4 +: 4] <=
                    event_counts[index*4 +: 4] + 4'd1;
            if (!status_seen[index])
                first_event_ticks[index*16 +: 16] <=
                    sample_tick_count[15:0];
        end
    endtask

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            attempt_active <= 1'b0;
            status_seen <= 7'd0;
            status_fail <= 7'd0;
            summary_pass <= 35'd0;
            summary_valid <= 5'd0;
            event_counts <= 28'd0;
            first_event_ticks <= {112{1'b1}};
            request_count <= 8'd0;
            first_address <= 24'd0;
            last_address <= 24'd0;
            address_change_count <= 8'd0;
            distinct_address_count <= 8'd0;
            completed_attempt_count <= 3'd0;
            last_error_code <= 4'd0;
            first_capture_valid <= 1'b0;
            first_data <= 8'd0;
            address_progress_seen <= 1'b0;
            data_changed_seen <= 1'b0;
            expected_output_seen <= 1'b0;
            opposite_output_seen <= 1'b0;
        end else begin
            if (phase_begin) begin
                if (phase_index == 3'd0) begin
                    summary_pass <= 35'd0;
                    summary_valid <= 5'd0;
                    last_error_code <= 4'd0;
                end else begin
                    summary_pass[phase_index*7 +: 7] <= 7'd0;
                    summary_valid[phase_index] <= 1'b0;
                end
                status_seen <= 7'd0;
                status_fail <= 7'd0;
                completed_attempt_count <= 3'd0;
            end

            if (attempt_begin) begin
                attempt_active <= 1'b1;
                status_seen <= 7'd0;
                status_fail <= 7'd0;
                event_counts <= 28'd0;
                first_event_ticks <= {112{1'b1}};
                request_count <= 8'd0;
                first_address <= 24'd0;
                last_address <= 24'd0;
                address_change_count <= 8'd0;
                distinct_address_count <= 8'd0;
                first_capture_valid <= 1'b0;
                first_data <= 8'd0;
                address_progress_seen <= 1'b0;
                data_changed_seen <= 1'b0;
                expected_output_seen <= 1'b0;
                opposite_output_seen <= 1'b0;
            end

            if (attempt_active) begin
                if (raw_request) begin
                    mark_event(0);
                    if (request_count != 8'hff)
                        request_count <= request_count + 8'd1;
                end
                if (capture_event) begin
                    if (!first_capture_valid || rom_address != last_address)
                        mark_event(1);
                    if (!first_capture_valid) begin
                        first_capture_valid <= 1'b1;
                        first_address <= rom_address;
                        last_address <= rom_address;
                        first_data <= rom_data;
                        distinct_address_count <= 8'd1;
                    end else begin
                        if (rom_address != last_address) begin
                            last_address <= rom_address;
                            address_progress_seen <= 1'b1;
                            if (address_change_count != 8'hff)
                                address_change_count <=
                                    address_change_count + 8'd1;
                            if (distinct_address_count != 8'hff)
                                distinct_address_count <=
                                    distinct_address_count + 8'd1;
                        end
                        if (rom_data != first_data)
                            data_changed_seen <= 1'b1;
                    end
                end
                if (address_progress_seen && data_changed_seen &&
                    !status_seen[2])
                    mark_event(2);
                if (sample_tick &&
                    (lane_left != 16'sd0 || lane_right != 16'sd0))
                    mark_event(3);
                if (sample_tick &&
                    (final_left != 16'sd0 || final_right != 16'sd0))
                    mark_event(4);
                if (sample_tick &&
                    (output_left != 16'sd0 || output_right != 16'sd0)) begin
                    mark_event(5);
                    if (phase_index == 3'd3) begin
                        if ((!pan_right && output_left != 16'sd0) ||
                            (pan_right && output_right != 16'sd0))
                            expected_output_seen <= 1'b1;
                        if ((!pan_right && output_right != 16'sd0) ||
                            (pan_right && output_left != 16'sd0))
                            opposite_output_seen <= 1'b1;
                    end
                end
            end

            if (attempt_end) begin
                attempt_active <= 1'b0;
                if (completed_attempt_count != 3'd7)
                    completed_attempt_count <=
                        completed_attempt_count + 3'd1;
                status_seen[6] <= completed_stop;
                status_fail <= ~completed_result;
                if (completed_stop) begin
                    event_counts[27:24] <= 4'd1;
                    first_event_ticks[111:96] <= sample_tick_count[15:0];
                end
                if (summary_valid[phase_index])
                    summary_pass[phase_index*7 +: 7] <=
                        summary_pass[phase_index*7 +: 7] &
                        completed_result;
                else begin
                    summary_pass[phase_index*7 +: 7] <= completed_result;
                    summary_valid[phase_index] <= 1'b1;
                end
                if (last_error_code == 4'd0 &&
                    completed_result != 7'h7f) begin
                    if (!completed_result[0]) last_error_code <= 4'd4;
                    else if (!completed_result[1] || !completed_result[2])
                        last_error_code <= 4'd5;
                    else if (!completed_result[3]) last_error_code <= 4'd6;
                    else if (!completed_result[4]) last_error_code <= 4'd7;
                    else if (!completed_result[5]) last_error_code <= 4'd8;
                    else if (phase_index == 3'd4)
                        last_error_code <= 4'd10;
                    else last_error_code <= 4'd9;
                end
            end
        end
    end
endmodule

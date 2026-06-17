`timescale 1ns/1ps

module tb_mister_vgm_wait_tick;

    localparam logic [31:0] TB_CLK_SYS_HZ = 32'd20_000;
    localparam logic [31:0] TB_VGM_WAIT_HZ = 32'd44;

    logic clk = 1'b0;
    logic reset_n = 1'b1;

    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_sample_valid;
    wire player_busy;
    wire player_done;
    wire [9:0] player_pc_debug;
    wire [7:0] player_last_cmd_debug;
    wire startup_reset_active;
    wire startup_waiting;
    wire startup_done;
    wire audio_gate_open;

    integer tick_count = 0;
    integer cycle_count = 0;

    mister_vgm_md_top #(
        .REGION_MODE                 (5),
        .POWER_ON_RESET_CYCLES       (32'd0),
        .START_DELAY_CYCLES          (32'd0),
        .INIT_AUDIO_SAMPLE_EDGES     (16'd0),
        .AUDIO_WARMUP_SAMPLES        (16'd0),
        .GATE_TO_START_CYCLES        (16'd0),
        .CLK_SYS_HZ                  (TB_CLK_SYS_HZ),
        .VGM_WAIT_HZ                 (TB_VGM_WAIT_HZ),
        .PLAYER_RESET_CYCLES         (32'd4),
        .START_ACCEPT_TIMEOUT_CYCLES (32'd1000),
        .PLAYER_DONE_TIMEOUT_TICKS   (32'd1000),
        .REPLAY_DELAY_TICKS          (32'd1000)
    ) dut (
        .clk                   (clk),
        .reset_n               (reset_n),
        .audio_l               (audio_l),
        .audio_r               (audio_r),
        .audio_sample_valid    (audio_sample_valid),
        .audio_lpf_mode        (2'b00),
        .audio_gain_boost      (1'b0),
        .audio_psg_level       (2'b00),
        .player_busy           (player_busy),
        .player_done           (player_done),
        .player_pc_debug       (player_pc_debug),
        .player_last_cmd_debug (player_last_cmd_debug),
        .startup_reset_active  (startup_reset_active),
        .startup_waiting       (startup_waiting),
        .startup_done          (startup_done),
        .audio_gate_open       (audio_gate_open),
        .ioctl_download        (1'b0),
        .ioctl_wr              (1'b0),
        .ioctl_addr            (27'd0),
        .ioctl_dout            (8'd0),
        .ioctl_index           (16'd0),
        .ioctl_wait            (),
        .vgm_load_busy         (),
        .vgm_load_done         (),
        .vgm_load_error        (),
        .vgm_load_overflow     (),
        .vgm_header_valid      (),
        .vgm_player_error      (),
        .vgm_unsupported_opcode(),
        .vgm_unsupported_pc    (),
        .vgm_player_error_code (),
        .vgm_error_pc_debug            (),
        .vgm_error_cmd_debug           (),
        .vgm_error_session_id          (),
        .vgm_player_state_debug        (),
        .vgm_mem_rd_req_debug          (),
        .vgm_mem_rd_ready_debug        (),
        .vgm_mem_rd_valid_debug        (),
        .vgm_mem_rd_addr_debug         (),
        .vgm_load_size         (),
        .vgm_load_magic        (),
        .vgm_data_start_debug  (),
        .vgm_current_pc_debug  (),
        .vgm_loop_pc_debug     (),
        .vgm_loop_valid_debug  (),
        .vgm_loop_taken_debug  (),
        .vgm_end_command_seen  (),
        .vgm_restarted_from_data_start(),
        .vgm_wait_ticks_consumed_debug(),
        .mode5_sound_reset_active(),
        .mode5_player_start_pulse_debug(),
        .fm_adjust_clip_count_l(),
        .fm_adjust_clip_count_r(),
        .genmix_wrap_count_l(),
        .genmix_wrap_count_r(),
        .ym_write_requested_count(),
        .ym_write_accepted_count(),
        .ym_write_dropped_or_busy_count(),
        .ym_port0_count(),
        .ym_port1_count(),
        .last_ym_port(),
        .last_ym_addr(),
        .last_ym_data(),
        .jt12_cen_interval_1_count(),
        .jt12_cen_interval_2_count(),
        .jt12_cen_interval_3_count(),
        .jt12_cen_interval_4_count(),
        .jt12_cen_interval_ge5_count(),
        .jt12_cen_interval_min(),
        .jt12_cen_interval_max(),
        .jt12_cen_interval_last(),
        .fm_raw_abs_peak(),
        .fm_adjust_abs_peak(),
        .fm_lpf_abs_peak(),
        .genmix_abs_peak(),
        .md_final_audio_abs_peak()
    );

    always #5 clk = ~clk;

    initial begin
        repeat (8) @(posedge clk);

        while (dut.reset) begin
            @(posedge clk);
        end

        tick_count = 0;
        for (cycle_count = 0; cycle_count < TB_CLK_SYS_HZ; cycle_count = cycle_count + 1) begin
            @(posedge clk);
            if (dut.vgm_wait_tick) begin
                tick_count = tick_count + 1;
            end
        end

        if (tick_count != TB_VGM_WAIT_HZ) begin
            $display("FAIL vgm_wait_tick_rate clk_hz=%0d wait_hz=%0d ticks=%0d",
                     TB_CLK_SYS_HZ, TB_VGM_WAIT_HZ, tick_count);
            $finish;
        end

        $display("PASS tb_mister_vgm_wait_tick clk_hz=%0d wait_hz=%0d ticks=%0d",
                 TB_CLK_SYS_HZ, TB_VGM_WAIT_HZ, tick_count);
        $finish;
    end

endmodule

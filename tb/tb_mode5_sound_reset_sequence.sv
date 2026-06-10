`timescale 1ns/1ps

module tb_mode5_sound_reset_sequence;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;
    logic [15:0] ioctl_index = 16'd1;

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
    wire vgm_load_busy;
    wire vgm_load_done;
    wire vgm_load_error;
    wire vgm_load_overflow;
    wire vgm_header_valid;
    wire vgm_player_error;
    wire [7:0] vgm_unsupported_opcode;
    wire [7:0] vgm_unsupported_pc;
    wire [7:0] vgm_player_error_code;
    wire [8:0] vgm_load_size;
    wire [31:0] vgm_load_magic;
    wire [7:0] vgm_data_start_debug;
    wire [7:0] vgm_current_pc_debug;
    wire [7:0] vgm_loop_pc_debug;
    wire vgm_loop_valid_debug;
    wire vgm_loop_taken_debug;
    wire vgm_end_command_seen;
    wire vgm_restarted_from_data_start;
    wire [31:0] vgm_wait_ticks_consumed_debug;
    wire mode5_sound_reset_active;
    wire mode5_player_start_pulse_debug;

    always #5 clk = ~clk;

    mister_vgm_md_top #(
        .REGION_MODE                 (5),
        .VGM_LOAD_ADDR_WIDTH         (8),
        .VGM_LOAD_FILE_INDEX         (16'd1),
        .POWER_ON_RESET_CYCLES       (32'd4),
        .START_DELAY_CYCLES          (32'd4),
        .INIT_AUDIO_SAMPLE_EDGES     (16'd0),
        .AUDIO_WARMUP_SAMPLES        (16'd0),
        .GATE_TO_START_CYCLES        (16'd1),
        .CLK_SYS_HZ                  (32'd20_000_000),
        .VGM_WAIT_HZ                 (32'd44_100),
        .REPLAY_ENABLE               (1'b0),
        .PLAYER_RESET_CYCLES         (32'd8),
        .START_ACCEPT_TIMEOUT_CYCLES (32'd1000),
        .PLAYER_DONE_TIMEOUT_TICKS   (32'd1000),
        .REPLAY_DELAY_TICKS          (32'd8),
        .MODE5_SOUND_RESET_CYCLES    (32'd8)
    ) dut (
        .clk                         (clk),
        .reset_n                     (reset_n),
        .audio_l                     (audio_l),
        .audio_r                     (audio_r),
        .audio_sample_valid          (audio_sample_valid),
        .player_busy                 (player_busy),
        .player_done                 (player_done),
        .player_pc_debug             (player_pc_debug),
        .player_last_cmd_debug       (player_last_cmd_debug),
        .startup_reset_active        (startup_reset_active),
        .startup_waiting             (startup_waiting),
        .startup_done                (startup_done),
        .audio_gate_open             (audio_gate_open),
        .ioctl_download              (ioctl_download),
        .ioctl_wr                    (ioctl_wr),
        .ioctl_addr                  (ioctl_addr),
        .ioctl_dout                  (ioctl_dout),
        .ioctl_index                 (ioctl_index),
        .vgm_load_busy               (vgm_load_busy),
        .vgm_load_done               (vgm_load_done),
        .vgm_load_error              (vgm_load_error),
        .vgm_load_overflow           (vgm_load_overflow),
        .vgm_header_valid            (vgm_header_valid),
        .vgm_player_error            (vgm_player_error),
        .vgm_unsupported_opcode      (vgm_unsupported_opcode),
        .vgm_unsupported_pc          (vgm_unsupported_pc),
        .vgm_player_error_code       (vgm_player_error_code),
        .vgm_error_pc_debug            (),
        .vgm_error_cmd_debug           (),
        .vgm_error_session_id          (),
        .vgm_player_state_debug        (),
        .vgm_mem_rd_req_debug          (),
        .vgm_mem_rd_ready_debug        (),
        .vgm_mem_rd_valid_debug        (),
        .vgm_mem_rd_addr_debug         (),
        .vgm_load_size               (vgm_load_size),
        .vgm_load_magic              (vgm_load_magic),
        .vgm_data_start_debug        (vgm_data_start_debug),
        .vgm_current_pc_debug        (vgm_current_pc_debug),
        .vgm_loop_pc_debug           (vgm_loop_pc_debug),
        .vgm_loop_valid_debug        (vgm_loop_valid_debug),
        .vgm_loop_taken_debug        (vgm_loop_taken_debug),
        .vgm_end_command_seen        (vgm_end_command_seen),
        .vgm_restarted_from_data_start(vgm_restarted_from_data_start),
        .vgm_wait_ticks_consumed_debug(vgm_wait_ticks_consumed_debug),
        .mode5_sound_reset_active    (mode5_sound_reset_active),
        .mode5_player_start_pulse_debug(mode5_player_start_pulse_debug),
        .fm_adjust_clip_count_l      (),
        .fm_adjust_clip_count_r      (),
        .genmix_wrap_count_l         (),
        .genmix_wrap_count_r         (),
        .ym_write_requested_count    (),
        .ym_write_accepted_count     (),
        .ym_write_dropped_or_busy_count(),
        .ym_port0_count              (),
        .ym_port1_count              (),
        .last_ym_port                (),
        .last_ym_addr                (),
        .last_ym_data                (),
        .jt12_cen_interval_1_count   (),
        .jt12_cen_interval_2_count   (),
        .jt12_cen_interval_3_count   (),
        .jt12_cen_interval_4_count   (),
        .jt12_cen_interval_ge5_count (),
        .jt12_cen_interval_min       (),
        .jt12_cen_interval_max       (),
        .jt12_cen_interval_last      (),
        .fm_raw_abs_peak             (),
        .fm_adjust_abs_peak          (),
        .fm_lpf_abs_peak             (),
        .genmix_abs_peak             (),
        .md_final_audio_abs_peak     ()
    );

    function automatic [7:0] minimal_vgm_byte(input int addr);
        begin
            unique case (addr)
                0: minimal_vgm_byte = "V";
                1: minimal_vgm_byte = "g";
                2: minimal_vgm_byte = "m";
                3: minimal_vgm_byte = " ";
                'h34: minimal_vgm_byte = 8'h0c;
                'h35: minimal_vgm_byte = 8'h00;
                'h36: minimal_vgm_byte = 8'h00;
                'h37: minimal_vgm_byte = 8'h00;
                'h40: minimal_vgm_byte = 8'h66;
                default: minimal_vgm_byte = 8'h00;
            endcase
        end
    endfunction

    task automatic write_download_byte(input int addr);
        begin
            @(posedge clk);
            ioctl_addr <= addr[26:0];
            ioctl_dout <= minimal_vgm_byte(addr);
            ioctl_wr <= 1'b1;
            @(posedge clk);
            ioctl_wr <= 1'b0;
        end
    endtask

    task automatic load_minimal_vgm;
        int i;
        begin
            @(posedge clk);
            ioctl_index <= 16'd1;
            ioctl_download <= 1'b1;
            for (i = 0; i <= 'h40; i = i + 1) begin
                write_download_byte(i);
            end
            @(posedge clk);
            ioctl_download <= 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic expect_reset_then_start(input int load_number);
        bit reset_seen;
        bit start_seen;
        bit start_during_reset;
        int i;
        begin
            reset_seen = 1'b0;
            start_seen = 1'b0;
            start_during_reset = 1'b0;

            for (i = 0; i < 64; i = i + 1) begin
                @(posedge clk);
                if (mode5_sound_reset_active) begin
                    reset_seen = 1'b1;
                end
                if (mode5_player_start_pulse_debug) begin
                    start_seen = 1'b1;
                    if (mode5_sound_reset_active) begin
                        start_during_reset = 1'b1;
                    end
                end
            end

            if (!reset_seen) begin
                $display("FAIL load %0d did not assert mode5_sound_reset_active", load_number);
                $finish;
            end
            if (!start_seen) begin
                $display("FAIL load %0d did not issue mode5 player start", load_number);
                $finish;
            end
            if (start_during_reset) begin
                $display("FAIL load %0d started player while sound reset was active", load_number);
                $finish;
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset_n <= 1'b1;
        repeat (16) @(posedge clk);

        load_minimal_vgm();
        expect_reset_then_start(1);

        repeat (16) @(posedge clk);

        load_minimal_vgm();
        expect_reset_then_start(2);

        if (vgm_load_error || vgm_load_overflow) begin
            $display("FAIL unexpected loader error error=%0b overflow=%0b", vgm_load_error, vgm_load_overflow);
            $finish;
        end

        $display("PASS tb_mode5_sound_reset_sequence");
        $finish;
    end

endmodule

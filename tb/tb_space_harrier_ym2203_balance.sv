`timescale 1ns/1ps

// Production-path audio statistics for a real YM2203/SegaPCM VGM (or a
// state-preserving window produced by extract_ym2203_balance_window.py).
module tb_space_harrier_ym2203_balance #(
    parameter logic [1:0] AUDIO_SELECT = 2'd0,
    parameter integer MEASURE_START_SAMPLES = 88_200,
    parameter integer MEASURE_END_SAMPLES = 132_300,
    parameter integer WAIT_HZ = 44_100
);
    localparam integer FILE_BYTES = 300_000;
    // SegaPCM needs two FSM enables per 8 MHz input clock. Match the existing
    // production integration test clock and keep every requested CEN legal.
    localparam integer CLK_HZ = 20_000_000;
    localparam [28:0] DDR_BASE = {4'b0011, 25'd0};
    localparam integer SEGA_WORD_BASE = 21'h100000;
    localparam integer PAYLOAD_WORDS = (65_536 + 7) / 8;
    localparam integer DDR_WORDS = SEGA_WORD_BASE + PAYLOAD_WORDS + 16;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg ioctl_download = 1'b0;
    reg ioctl_wr = 1'b0;
    reg [26:0] ioctl_addr = 27'd0;
    reg [7:0] ioctl_dout = 8'd0;
    wire ioctl_wait;
    wire player_busy;
    wire player_done;
    wire vgm_player_error;
    wire audio_sample_valid;
    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire [28:0] ddram_addr;
    reg [63:0] ddram_dout = 64'd0;
    reg ddram_dout_ready = 1'b0;
    wire [63:0] ddram_din;
    wire [7:0] ddram_be;
    wire ddram_rd;
    wire ddram_we;

    reg [7:0] vgm_mem [0:FILE_BYTES-1];
    reg [63:0] ddram_mem [0:DDR_WORDS-1];
    reg [28:0] read_addr_q = 29'd0;
    integer read_delay = 0;
    integer vgm_fd;
    integer vgm_read;
    integer vgm_size;
    integer i;
    integer timeout;
    integer drain_timeout;
    integer max_cycles = 80_000_000;
    reg [2047:0] vgm_file;
    reg [1:0] audio_select = AUDIO_SELECT;
    integer audio_select_arg;

    integer raw_count = 0;
    integer raw_nonzero = 0;
    integer raw_min = 32767;
    integer raw_max = -32768;
    integer raw_abs_peak = 0;
    integer raw_zero_cross = 0;
    integer raw_rail = 0;
    integer raw_lr_diff = 0;
    integer raw_xz = 0;
    integer raw_previous = 0;
    reg raw_previous_valid = 1'b0;
    longint unsigned raw_sumsq = 0;
    longint unsigned raw_hash = 64'hcbf29ce484222325;

    integer fm_min = 32767;
    integer fm_max = -32768;
    integer fm_abs_peak = 0;
    integer fm_nonzero = 0;
    integer fm_zero_cross = 0;
    integer fm_rail = 0;
    integer fm_previous = 0;
    reg fm_previous_valid = 1'b0;
    longint unsigned fm_sumsq = 0;
    longint unsigned fm_hash = 64'hcbf29ce484222325;

    integer internal_fm_min = 32767;
    integer internal_fm_max = -32768;
    integer internal_fm_abs_peak = 0;
    integer internal_fm_rail = 0;
    longint unsigned internal_fm_sumsq = 0;
    longint unsigned internal_fm_hash = 64'hcbf29ce484222325;

    integer psg_min = 1023;
    integer psg_max = 0;
    integer psg_nonzero = 0;
    integer psg_changes = 0;
    integer psg_previous = 0;
    reg psg_previous_valid = 1'b0;
    longint unsigned psg_sumsq = 0;
    longint unsigned psg_hash = 64'hcbf29ce484222325;

    integer final_count = 0;
    integer final_nonzero = 0;
    integer final_min = 32767;
    integer final_max = -32768;
    integer final_abs_peak = 0;
    integer final_zero_cross = 0;
    integer final_sat = 0;
    integer final_pos_sat = 0;
    integer final_neg_sat = 0;
    integer final_lr_diff = 0;
    integer final_xz = 0;
    integer final_previous = 0;
    reg final_previous_valid = 1'b0;
    longint unsigned final_sumsq = 0;
    longint unsigned final_hash = 64'hcbf29ce484222325;

    integer pcm_count = 0;
    integer pcm_nonzero = 0;
    integer pcm_min = 32767;
    integer pcm_max = -32768;
    integer pcm_abs_peak = 0;
    integer pcm_xz = 0;
    longint unsigned pcm_sumsq = 0;
    longint unsigned pcm_hash = 64'hcbf29ce484222325;

    integer parser_ym_writes = 0;
    integer parser_c0_writes = 0;
    integer busy_accepts = 0;
    integer busy_completes = 0;
    integer measurement_cycles = 0;

    always #1 clk = ~clk;

    function automatic longint unsigned hash_byte;
        input longint unsigned hash;
        input [7:0] value;
        begin
            hash_byte = (hash ^ value) * 64'h00000100000001b3;
        end
    endfunction

    function automatic longint unsigned hash_word;
        input longint unsigned hash;
        input [15:0] value;
        longint unsigned partial;
        begin
            partial = hash_byte(hash, value[7:0]);
            hash_word = hash_byte(partial, value[15:8]);
        end
    endfunction

    function automatic integer abs16;
        input integer value;
        begin
            abs16 = value < 0 ? -value : value;
        end
    endfunction

    wire measurement_active =
        (dut.vgm_wait_ticks_consumed_debug >= MEASURE_START_SAMPLES) &&
        (dut.vgm_wait_ticks_consumed_debug < MEASURE_END_SAMPLES);

    mister_vgm_md_top #(
        .REGION_MODE                     (5),
        .VGM_LOAD_ADDR_WIDTH             (19),
        .MODE5_VGM_BACKEND               (1),
        .CLK_SYS_HZ                      (CLK_HZ),
        .VGM_WAIT_HZ                     (WAIT_HZ),
        .POWER_ON_RESET_CYCLES           (32'd0),
        .START_DELAY_CYCLES              (32'd0),
        .INIT_AUDIO_SAMPLE_EDGES          (16'd0),
        .AUDIO_WARMUP_SAMPLES            (16'd0),
        .GATE_TO_START_CYCLES             (16'd0),
        .MODE5_SOUND_RESET_CYCLES        (32'd0),
        .MODE5_AUDIO_UNMUTE_DELAY_CYCLES (32'd0),
        .REPLAY_ENABLE                   (1'b0)
    ) dut (
        .clk                              (clk),
        .reset_n                          (reset_n),
        .audio_l                          (audio_l),
        .audio_r                          (audio_r),
        .audio_sample_valid               (audio_sample_valid),
        .audio_lpf_mode                   (2'b00),
        .audio_gain_boost                 (1'b0),
        .audio_psg_level                  (2'b00),
        .segapcm_smoke_variant            (3'd0),
        .segapcm_smoke_variant_valid      (1'b0),
        .segapcm_smoke_source_loaded      (player_busy),
        .segapcm_smoke_ddr_follow         (player_busy),
        .segapcm_smoke_ddr_offset         (3'd0),
        .segapcm_smoke_ddr_delta          (3'd0),
        .segapcm_smoke_c0_use             (2'd3),
        .segapcm_smoke_c0_sample_mode     (3'd3),
        .segapcm_smoke_c0_delta_speed     (2'd2),
        .segapcm_smoke_c0_hit_window      (3'd0),
        .segapcm_smoke_c0_format          (2'd0),
        .segapcm_smoke_c0_mame_tick_div   (3'd0),
        .segapcm_smoke_c0_vol_map         (3'd0),
        .segapcm_smoke_c0_drive           (2'd2),
        .segapcm_c0_pm3_audio_mask        (16'hffff),
        .segapcm_c0_top_audio_test        (audio_select),
        .segapcm_c0_pm3_mix_mode          (2'd1),
        .segapcm_c0_pm3_start_policy      (3'd0),
        .segapcm_c0_jt_backend            (1'b1),
        .segapcm_smoke_ddr_dest_map       (1'b1),
        .segapcm_smoke_ddr_dest_basis     (2'd1),
        .segapcm_smoke_ddr_full_capture   (1'b1),
        .segapcm_smoke_ddr_dest_loop_wrap (1'b0),
        .player_busy                      (player_busy),
        .player_done                      (player_done),
        .vgm_player_error                 (vgm_player_error),
        .ioctl_download                   (ioctl_download),
        .ioctl_wr                         (ioctl_wr),
        .ioctl_addr                       (ioctl_addr),
        .ioctl_dout                       (ioctl_dout),
        .ioctl_index                      (16'd1),
        .ioctl_wait                       (ioctl_wait),
        .ddram_busy                       (1'b0),
        .ddram_addr                       (ddram_addr),
        .ddram_dout                       (ddram_dout),
        .ddram_dout_ready                 (ddram_dout_ready),
        .ddram_din                        (ddram_din),
        .ddram_be                         (ddram_be),
        .ddram_rd                         (ddram_rd),
        .ddram_we                         (ddram_we)
    );

    always @(posedge clk) begin
        ddram_dout_ready <= 1'b0;
        if (ddram_we) begin
            if (ddram_addr < DDR_BASE ||
                ddram_addr >= DDR_BASE + DDR_WORDS)
                $fatal(1, "DDRAM write out of range addr=%08h", ddram_addr);
            if (ddram_be[0]) ddram_mem[ddram_addr-DDR_BASE][7:0] <= ddram_din[7:0];
            if (ddram_be[1]) ddram_mem[ddram_addr-DDR_BASE][15:8] <= ddram_din[15:8];
            if (ddram_be[2]) ddram_mem[ddram_addr-DDR_BASE][23:16] <= ddram_din[23:16];
            if (ddram_be[3]) ddram_mem[ddram_addr-DDR_BASE][31:24] <= ddram_din[31:24];
            if (ddram_be[4]) ddram_mem[ddram_addr-DDR_BASE][39:32] <= ddram_din[39:32];
            if (ddram_be[5]) ddram_mem[ddram_addr-DDR_BASE][47:40] <= ddram_din[47:40];
            if (ddram_be[6]) ddram_mem[ddram_addr-DDR_BASE][55:48] <= ddram_din[55:48];
            if (ddram_be[7]) ddram_mem[ddram_addr-DDR_BASE][63:56] <= ddram_din[63:56];
        end
        if (ddram_rd && read_delay == 0) begin
            if (ddram_addr < DDR_BASE ||
                ddram_addr >= DDR_BASE + DDR_WORDS)
                $fatal(1, "DDRAM read out of range addr=%08h", ddram_addr);
            read_addr_q <= ddram_addr;
            read_delay <= 2;
        end else if (read_delay != 0) begin
            read_delay <= read_delay - 1;
            if (read_delay == 1) begin
                ddram_dout <= ddram_mem[read_addr_q-DDR_BASE];
                ddram_dout_ready <= 1'b1;
            end
        end

        if (dut.loaded_vgm_mode.ym2203_cmd_valid)
            parser_ym_writes <= parser_ym_writes + 1;
        if (dut.loaded_vgm_mode.segapcm_cmd_valid)
            parser_c0_writes <= parser_c0_writes + 1;
        if (dut.loaded_vgm_mode.ym2203_write_accepted)
            busy_accepts <= busy_accepts + 1;
        if (dut.loaded_vgm_mode.ym2203_write_completed)
            busy_completes <= busy_completes + 1;

        if (measurement_active) begin
            integer value;
            integer magnitude;
            longint signed square_value;
            measurement_cycles <= measurement_cycles + 1;

            if (dut.loaded_vgm_mode.ym2203_raw_sample_valid) begin
                raw_count <= raw_count + 1;
                if ((^{dut.loaded_vgm_mode.ym2203_raw_audio_l,
                       dut.loaded_vgm_mode.ym2203_raw_audio_r,
                       dut.loaded_vgm_mode.ym2203_raw_fm_audio,
                       dut.loaded_vgm_mode.ym2203_raw_psg_audio}) === 1'bx) begin
                    raw_xz <= raw_xz + 1;
                end else begin
                    value = $signed(dut.loaded_vgm_mode.ym2203_raw_audio_l);
                    magnitude = abs16(value);
                    if (value < raw_min) raw_min <= value;
                    if (value > raw_max) raw_max <= value;
                    if (magnitude > raw_abs_peak) raw_abs_peak <= magnitude;
                    if (value != 0) raw_nonzero <= raw_nonzero + 1;
                    if (value == 32767 || value == -32768)
                        raw_rail <= raw_rail + 1;
                    if (raw_previous_valid && value != 0 &&
                        raw_previous != 0 && ((value < 0) != (raw_previous < 0)))
                        raw_zero_cross <= raw_zero_cross + 1;
                    raw_previous <= value;
                    raw_previous_valid <= 1'b1;
                    square_value = value;
                    raw_sumsq <= raw_sumsq + square_value * square_value;
                    raw_hash <= hash_word(
                        hash_word(raw_hash,
                            dut.loaded_vgm_mode.ym2203_raw_audio_l),
                        dut.loaded_vgm_mode.ym2203_raw_audio_r);
                    if (dut.loaded_vgm_mode.ym2203_raw_audio_l !==
                        dut.loaded_vgm_mode.ym2203_raw_audio_r)
                        raw_lr_diff <= raw_lr_diff + 1;

                    value = $signed(dut.loaded_vgm_mode.ym2203_raw_fm_audio);
                    magnitude = abs16(value);
                    if (value < fm_min) fm_min <= value;
                    if (value > fm_max) fm_max <= value;
                    if (magnitude > fm_abs_peak) fm_abs_peak <= magnitude;
                    if (value != 0) fm_nonzero <= fm_nonzero + 1;
                    if (value == 32767 || value == -32768)
                        fm_rail <= fm_rail + 1;
                    if (fm_previous_valid && value != 0 &&
                        fm_previous != 0 && ((value < 0) != (fm_previous < 0)))
                        fm_zero_cross <= fm_zero_cross + 1;
                    fm_previous <= value;
                    fm_previous_valid <= 1'b1;
                    square_value = value;
                    fm_sumsq <= fm_sumsq + square_value * square_value;
                    fm_hash <= hash_word(fm_hash,
                        dut.loaded_vgm_mode.ym2203_raw_fm_audio);

                    value = $signed(dut.loaded_vgm_mode.ym2203_sound.
                        ym2203_core.gen_2203_acc.mono_snd);
                    magnitude = abs16(value);
                    if (value < internal_fm_min) internal_fm_min <= value;
                    if (value > internal_fm_max) internal_fm_max <= value;
                    if (magnitude > internal_fm_abs_peak)
                        internal_fm_abs_peak <= magnitude;
                    if (value == 32767 || value == -32768)
                        internal_fm_rail <= internal_fm_rail + 1;
                    square_value = value;
                    internal_fm_sumsq <= internal_fm_sumsq +
                        square_value * square_value;
                    internal_fm_hash <= hash_word(internal_fm_hash,
                        dut.loaded_vgm_mode.ym2203_sound.
                        ym2203_core.gen_2203_acc.mono_snd);

                    value = dut.loaded_vgm_mode.ym2203_raw_psg_audio;
                    if (value < psg_min) psg_min <= value;
                    if (value > psg_max) psg_max <= value;
                    if (value != 0) psg_nonzero <= psg_nonzero + 1;
                    if (psg_previous_valid && value != psg_previous)
                        psg_changes <= psg_changes + 1;
                    psg_previous <= value;
                    psg_previous_valid <= 1'b1;
                    square_value = value * 32;
                    psg_sumsq <= psg_sumsq + square_value * square_value;
                    psg_hash <= hash_word(psg_hash, {6'd0,
                        dut.loaded_vgm_mode.ym2203_raw_psg_audio});
                end
            end

            if (audio_sample_valid) begin
                final_count <= final_count + 1;
                if ((^{audio_l, audio_r}) === 1'bx) begin
                    final_xz <= final_xz + 1;
                end else begin
                    value = $signed(audio_l);
                    magnitude = abs16(value);
                    if (value < final_min) final_min <= value;
                    if (value > final_max) final_max <= value;
                    if (magnitude > final_abs_peak) final_abs_peak <= magnitude;
                    if (value != 0) final_nonzero <= final_nonzero + 1;
                    if (final_previous_valid && value != 0 &&
                        final_previous != 0 &&
                        ((value < 0) != (final_previous < 0)))
                        final_zero_cross <= final_zero_cross + 1;
                    final_previous <= value;
                    final_previous_valid <= 1'b1;
                    square_value = value;
                    final_sumsq <= final_sumsq + square_value * square_value;
                    final_hash <= hash_word(hash_word(final_hash, audio_l), audio_r);
                    if (audio_l !== audio_r)
                        final_lr_diff <= final_lr_diff + 1;
                    if (dut.loaded_vgm_mode.mode5_audio_l_clipped) begin
                        final_sat <= final_sat + 1;
                        if (audio_l == 32767)
                            final_pos_sat <= final_pos_sat + 1;
                        if (audio_l == -32768)
                            final_neg_sat <= final_neg_sat + 1;
                    end
                end
            end

            if (dut.loaded_vgm_mode.segapcm_audio_sample_valid) begin
                pcm_count <= pcm_count + 1;
                if ((^{dut.loaded_vgm_mode.segapcm_audio_l,
                       dut.loaded_vgm_mode.segapcm_audio_r}) === 1'bx) begin
                    pcm_xz <= pcm_xz + 1;
                end else begin
                    value = $signed(dut.loaded_vgm_mode.segapcm_audio_l);
                    magnitude = abs16(value);
                    if (value < pcm_min) pcm_min <= value;
                    if (value > pcm_max) pcm_max <= value;
                    if (magnitude > pcm_abs_peak) pcm_abs_peak <= magnitude;
                    if (value != 0) pcm_nonzero <= pcm_nonzero + 1;
                    square_value = value;
                    pcm_sumsq <= pcm_sumsq + square_value * square_value;
                    pcm_hash <= hash_word(
                        hash_word(pcm_hash,
                            dut.loaded_vgm_mode.segapcm_audio_l),
                        dut.loaded_vgm_mode.segapcm_audio_r);
                end
            end
        end
    end

    initial begin
        if ($value$plusargs("MAX_CYCLES=%d", max_cycles)) begin end
        if ($value$plusargs("AUDIO_SELECT=%d", audio_select_arg))
            audio_select = audio_select_arg[1:0];
        if (!$value$plusargs("VGM=%s", vgm_file))
            $fatal(1, "VGM plusarg is required");
        vgm_fd = $fopen(vgm_file, "rb");
        if (vgm_fd == 0) $fatal(1, "cannot open VGM");
        vgm_read = $fread(vgm_mem, vgm_fd);
        $fclose(vgm_fd);
        if (vgm_read <= 0 || vgm_read > FILE_BYTES)
            $fatal(1, "VGM bytes %0d outside capacity %0d",
                   vgm_read, FILE_BYTES);
        vgm_size = vgm_read;
        for (i = 0; i < DDR_WORDS; i = i + 1)
            ddram_mem[i] = 64'd0;

        repeat (8) @(posedge clk);
        reset_n = 1'b1;
        repeat (8) @(posedge clk);
        @(negedge clk);
        ioctl_download = 1'b1;
        // The DDR backend detects the rising edge before accepting bytes.
        @(negedge clk);
        i = 0;
        while (i < vgm_size) begin
            @(negedge clk);
            ioctl_addr = i[26:0];
            ioctl_dout = vgm_mem[i];
            ioctl_wr = !ioctl_wait;
            @(posedge clk);
            if (ioctl_wr && !ioctl_wait)
                i = i + 1;
        end
        @(negedge clk);
        ioctl_wr = 1'b0;
        ioctl_download = 1'b0;

        timeout = 0;
        while (!player_done && !vgm_player_error && timeout < max_cycles) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        drain_timeout = 0;
        while (player_done &&
               dut.loaded_vgm_mode.ym2203_transport_busy &&
               drain_timeout < 1_000_000) begin
            @(posedge clk);
            drain_timeout = drain_timeout + 1;
        end
        repeat (16) @(posedge clk);
        if (vgm_player_error)
            $fatal(1, "production parser error code=%02h pc=%06h",
                dut.vgm_player_error_code, dut.vgm_error_pc_debug);
        if (!player_done)
            $fatal(1, "production simulation timeout cycles=%0d wait=%0d pc=%06h",
                timeout, dut.vgm_wait_ticks_consumed_debug,
                dut.vgm_current_pc_debug);
        if (dut.loaded_vgm_mode.ym2203_transport_busy ||
            busy_accepts != busy_completes)
            $fatal(1, "YM2203 transport did not drain accepts=%0d completes=%0d",
                busy_accepts, busy_completes);
        if (raw_count == 0 || final_count == 0)
            $fatal(1, "measurement window produced no samples raw=%0d final=%0d",
                raw_count, final_count);
        if (raw_xz || final_xz || pcm_xz || raw_lr_diff || final_lr_diff)
            $fatal(1, "audio integrity failure raw_xz=%0d final_xz=%0d pcm_xz=%0d raw_lr=%0d final_lr=%0d",
                raw_xz, final_xz, pcm_xz, raw_lr_diff, final_lr_diff);

        $display("BALANCE_RAW selector=%0d count=%0d min=%0d max=%0d abs=%0d nonzero=%0d zc=%0d rail=%0d sumsq=%0d hash=%016h lr_diff=%0d xz=%0d",
            audio_select, raw_count, raw_min, raw_max, raw_abs_peak,
            raw_nonzero, raw_zero_cross, raw_rail, raw_sumsq, raw_hash,
            raw_lr_diff, raw_xz);
        $display("BALANCE_FM selector=%0d count=%0d min=%0d max=%0d abs=%0d nonzero=%0d zc=%0d rail=%0d sumsq=%0d hash=%016h",
            audio_select, raw_count, fm_min, fm_max, fm_abs_peak,
            fm_nonzero, fm_zero_cross, fm_rail, fm_sumsq, fm_hash);
        $display("BALANCE_INTERNAL_FM selector=%0d count=%0d min=%0d max=%0d abs=%0d rail=%0d sumsq=%0d hash=%016h",
            audio_select, raw_count, internal_fm_min, internal_fm_max,
            internal_fm_abs_peak, internal_fm_rail, internal_fm_sumsq,
            internal_fm_hash);
        $display("BALANCE_PSG selector=%0d count=%0d min=%0d max=%0d nonzero=%0d changes=%0d scaled_sumsq=%0d hash=%016h",
            audio_select, raw_count, psg_min, psg_max, psg_nonzero,
            psg_changes, psg_sumsq, psg_hash);
        $display("BALANCE_PCM selector=%0d count=%0d min=%0d max=%0d abs=%0d nonzero=%0d sumsq=%0d hash=%016h xz=%0d",
            audio_select, pcm_count, pcm_min, pcm_max, pcm_abs_peak,
            pcm_nonzero, pcm_sumsq, pcm_hash, pcm_xz);
        $display("BALANCE_FINAL selector=%0d count=%0d min=%0d max=%0d abs=%0d nonzero=%0d zc=%0d sat=%0d pos_sat=%0d neg_sat=%0d sumsq=%0d hash=%016h lr_diff=%0d xz=%0d",
            audio_select, final_count, final_min, final_max, final_abs_peak,
            final_nonzero, final_zero_cross, final_sat, final_pos_sat,
            final_neg_sat, final_sumsq, final_hash, final_lr_diff, final_xz);
        $display("BALANCE_CONTROL selector=%0d cycles=%0d measurement_cycles=%0d waits=%0d commands=%0d ym_parser=%0d ym_accept=%0d ym_complete=%0d c0_parser=%0d end_pc=%06h sample_valid=%0d",
            audio_select, timeout, measurement_cycles,
            dut.vgm_wait_ticks_consumed_debug,
            dut.parser_command_count_debug, parser_ym_writes, busy_accepts,
            busy_completes, parser_c0_writes, dut.mode5_done_pc_debug,
            final_count);
        $display("PASS tb_space_harrier_ym2203_balance");
        $finish;
    end
endmodule

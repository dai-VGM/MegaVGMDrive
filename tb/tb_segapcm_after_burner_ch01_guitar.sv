`timescale 1ns/1ps

// After Burner II / Final Take Off, RTL ch0/ch1 guitar diagnostic.
// Replays the last known-good riff at 25.383492 s and the first following
// candidate at 27.098141 s, including the intervening delta-write sequence.
// No production RTL behavior is overridden.
module tb_segapcm_after_burner_ch01_guitar;
    localparam integer CLK_HZ = 8_053_974;
    localparam integer MAX_FRAMES = 70000;

    logic clk = 0, reset = 1;
    logic cmd_valid = 0;
    logic [15:0] cmd_addr = 0;
    logic [7:0] cmd_data = 0;
    logic payload_wr_valid = 0;
    logic [18:0] payload_wr_addr = 0;
    logic [7:0] payload_wr_data = 8'h80;
    logic [31:0] type80_rom_size = 0, type80_rom_dest = 0;
    logic ddr_ready = 1, ddr_valid = 0;
    logic [7:0] ddr_data = 8'h80;
    logic [15:0] ddr_last_index = 0;
    logic response_pending = 0;
    logic [18:0] response_index = 0;
    integer response_delay = 0;
    integer generation [0:1];
    integer committed_generation [0:1];

    wire ddr_req;
    wire [18:0] ddr_addr;
    wire signed [15:0] audio_l, audio_r;
    wire audio_valid;

    logic [7:0] rom [0:19'h7ffff];
    integer req_count [0:1][0:9];
    integer push_count [0:1][0:9];
    integer pop_count [0:1][0:9];
    integer accept_count [0:1][0:9];
    integer response_count [0:1][0:9];
    integer hold_count [0:1][0:9];
    integer consume_count [0:1][0:9];
    integer nonneutral_count [0:1][0:9];
    integer mix_count [0:1][0:9];
    integer cpu_accept_count [0:1][0:9];
    integer current_pair_count [0:1][0:9];
    integer enable_write_count [0:1][0:9];
    integer collision_count [0:1][0:9];
    integer pending_wb_seen_count [0:1][0:9];
    integer load_count [0:1][0:9][1:3];
    time first_request_time [0:1][0:9];
    time first_nonneutral_time [0:1][0:9];
    time first_mix_time [0:1][0:9];
    time last_mix_time [0:1][0:9];
    integer first_bad_frame [0:9];
    integer frame_count [0:1][0:9];
    integer request_frame_count [0:1][0:9];
    logic [18:0] request_frame_addr [0:1][0:9][0:MAX_FRAMES-1];
    logic [18:0] frame_addr [0:1][0:9][0:MAX_FRAMES-1];
    logic [7:0] frame_byte [0:1][0:9][0:MAX_FRAMES-1];
    logic signed [15:0] frame_mul [0:1][0:9][0:MAX_FRAMES-1];
    logic signed [11:0] frame_right [0:1][0:9][0:MAX_FRAMES-1];
    integer owner_gen = 0;
    integer hold_gen [0:15];
    integer fifo_gen [0:31];
    integer fifo_gen_wr = 0, fifo_gen_rd = 0;
    integer i, j, k;

    always #62 clk = ~clk;

    function automatic [18:0] payload_to_rom(input [18:0] index);
        begin
            if (index >= 19'h0d000 && index < 19'h21000)
                payload_to_rom = 19'h2c000 + (index - 19'h0d000);
            else if (index >= 19'h21400 && index < 19'h21800)
                payload_to_rom = 19'h50000 + (index - 19'h21400);
            else if (index >= 19'h21800 && index < 19'h25800)
                payload_to_rom = 19'h59600 + (index - 19'h21800);
            else
                payload_to_rom = 19'h00000;
        end
    endfunction

    // Four-system-clock, single-outstanding DDR model.
    always @(negedge clk) begin
        ddr_valid = 0;
        if (reset) begin
            response_pending = 0;
            response_delay = 0;
        end else if (ddr_req && ddr_ready && !response_pending) begin
            response_pending = 1;
            response_index = ddr_addr;
            response_delay = 4;
        end else if (response_pending) begin
            response_delay = response_delay - 1;
            if (response_delay == 1) begin
                ddr_last_index = response_index[15:0];
                ddr_data = rom[payload_to_rom(response_index)];
                ddr_valid = 1;
                response_pending = 0;
            end
        end
    end

    // Generation-tag the production request/FIFO/owner/hold chain in the TB.
    always @(posedge clk) begin : trace
        integer ch, gen, n;
        if (!reset) begin
            if (dut.core_cpu_cs) begin
                ch = dut.latched_cpu_addr[6:3];
                if (ch < 2) begin
                    gen = generation[ch];
                    cpu_accept_count[ch][gen] = cpu_accept_count[ch][gen] + 1;
                    if (dut.latched_cpu_addr[7] &&
                        dut.latched_cpu_addr[2:0] == 3'd5)
                        current_pair_count[ch][gen] =
                            current_pair_count[ch][gen] + 1;
                    if (dut.latched_cpu_addr[7] &&
                        dut.latched_cpu_addr[2:0] == 3'd6)
                        enable_write_count[ch][gen] =
                            enable_write_count[ch][gen] + 1;
                    if (dut.lab_jt_pcm_core.cpu_internal_ram_write_collision)
                        collision_count[ch][gen] = collision_count[ch][gen] + 1;
                    if (dut.lab_jt_pcm_core.wb_cur_valid_i &&
                        dut.lab_jt_pcm_core.wb_cur_ch_i == ch)
                        pending_wb_seen_count[ch][gen] =
                            pending_wb_seen_count[ch][gen] + 1;
                end
            end
            if (dut.segapcm_cen && dut.lab_jt_pcm_core.st >= 4'd1 &&
                dut.lab_jt_pcm_core.st <= 4'd3 &&
                dut.lab_jt_pcm_core.cur_ch < 2) begin
                ch = dut.lab_jt_pcm_core.cur_ch;
                gen = committed_generation[ch];
                load_count[ch][gen][dut.lab_jt_pcm_core.st] =
                    load_count[ch][gen][dut.lab_jt_pcm_core.st] + 1;
            end
            if (dut.rom_request_event) begin
                ch = dut.lab_jt_req_src_ch;
                if (ch < 2) begin
                    gen = committed_generation[ch];
                    req_count[ch][gen] = req_count[ch][gen] + 1;
                    if (req_count[ch][gen] == 1)
                        first_request_time[ch][gen] = $time;
                    n = request_frame_count[ch][gen];
                    if (n < MAX_FRAMES) begin
                        request_frame_addr[ch][gen][n] = dut.lab_jt_rom_addr;
                        request_frame_count[ch][gen] = n + 1;
                    end
                end
            end
            if (dut.lab_jt_ddr_request_queue_push) begin
                ch = dut.lab_jt_req_src_ch;
                fifo_gen[fifo_gen_wr] = (ch < 2) ? committed_generation[ch] : 0;
                fifo_gen_wr = (fifo_gen_wr + 1) & 31;
                if (ch < 2)
                    push_count[ch][committed_generation[ch]] =
                        push_count[ch][committed_generation[ch]] + 1;
            end
            if (dut.lab_jt_ddr_read_request_accept) begin
                ch = dut.lab_jt_ddr_issue_ch_i;
                owner_gen = fifo_gen[fifo_gen_rd];
                fifo_gen_rd = (fifo_gen_rd + 1) & 31;
                if (ch < 2) begin
                    pop_count[ch][owner_gen] = pop_count[ch][owner_gen] + 1;
                    accept_count[ch][owner_gen] = accept_count[ch][owner_gen] + 1;
                end
            end
            if (dut.lab_jt_ddr_payload_return_event &&
                dut.lab_jt_ddr_owner_valid_i) begin
                ch = dut.lab_jt_ddr_owner_ch_i;
                if (ch < 2)
                    response_count[ch][owner_gen] =
                        response_count[ch][owner_gen] + 1;
            end
            if (dut.lab_jt_ddr_payload_return_event &&
                dut.lab_jt_ddr_return_hold_candidate) begin
                ch = dut.lab_jt_ddr_owner_ch_i;
                hold_gen[ch] = owner_gen;
                if (ch < 2)
                    hold_count[ch][owner_gen] = hold_count[ch][owner_gen] + 1;
            end
            if (dut.segapcm_cen && dut.lab_jt_pcm_core.st == 4'd14) begin
                ch = dut.lab_jt_pcm_core.cur_ch;
                if (ch < 2 && !dut.lab_jt_pcm_core.cfg_en[0]) begin
                    gen = committed_generation[ch];
                    consume_count[ch][gen] = consume_count[ch][gen] + 1;
                    if (dut.lab_jt_rom_data_to_core != 8'h80)
                        nonneutral_count[ch][gen] = nonneutral_count[ch][gen] + 1;
                    if (dut.lab_jt_rom_data_to_core != 8'h80 &&
                        first_nonneutral_time[ch][gen] == 0)
                        first_nonneutral_time[ch][gen] = $time;
                end
            end
            if (dut.segapcm_cen && dut.lab_jt_pcm_core.st == 4'd15) begin
                ch = dut.lab_jt_pcm_core.cur_ch;
                if (ch < 2 && !dut.lab_jt_pcm_core.cfg_en[0]) begin
                    gen = committed_generation[ch];
                    n = frame_count[ch][gen];
                    if (n < MAX_FRAMES) begin
                        frame_addr[ch][gen][n] = dut.lab_jt_rom_addr;
                        frame_byte[ch][gen][n] = dut.lab_jt_rom_data_to_core;
                        frame_mul[ch][gen][n] = dut.lab_jt_pcm_core.mul_data;
                        frame_right[ch][gen][n] = dut.lab_jt_pcm_core.buf_r;
                        frame_count[ch][gen] = n + 1;
                    end
                    if ((dut.lab_jt_pcm_core.mul_data != 0) ||
                        (dut.lab_jt_pcm_core.buf_r != 0)) begin
                        mix_count[ch][gen] = mix_count[ch][gen] + 1;
                        if (first_mix_time[ch][gen] == 0)
                            first_mix_time[ch][gen] = $time;
                        last_mix_time[ch][gen] = $time;
                    end
                end
            end
        end
    end

    task automatic load_block(input [20:0] dest, input [18:0] len,
                              input [18:0] local_base);
        begin
            @(negedge clk);
            type80_rom_dest = {11'd0, dest};
            type80_rom_size = {13'd0, len} + 32'd8;
            payload_wr_addr = local_base;
            payload_wr_valid = 1;
            @(negedge clk);
            payload_wr_valid = 0;
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic c0(input [15:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            cmd_addr = addr; cmd_data = data; cmd_valid = 1;
            @(negedge clk);
            cmd_valid = 0;
            repeat (4) @(negedge clk);
        end
    endtask

    task automatic wait_us(input longint usec);
        longint clocks;
        begin
            clocks = (usec * CLK_HZ) / 1_000_000;
            repeat (clocks) @(posedge clk);
        end
    endtask

    task automatic setup_initial_volumes;
        begin
            c0(16'h0002, 8'h20); c0(16'h0003, 8'h02);
            c0(16'h000a, 8'h02); c0(16'h000b, 8'h20);
            c0(16'h0086, 8'h01); c0(16'h008e, 8'h01);
        end
    endtask

    // The 24.834/25.108/25.383 riffs only rewrite loop/current mid/high and
    // control. end=3f, delta=5a and the pan registers remain live.
    task automatic trigger_bank3_riff(input integer ch, input integer gen);
        reg [15:0] lo, hi;
        begin
            lo = ch << 3;
            hi = 16'h0080 | lo;
            generation[ch] = gen;
            c0(lo + 4, 8'h00);
            c0(hi + 4, 8'h00);
            c0(lo + 5, 8'h00);
            c0(hi + 5, 8'h00);
            c0(hi + 6, 8'h3a);
            committed_generation[ch] = gen;
            $display("RIFF_COMMIT t=%0t ch=%0d gen=%0d shadow=%02h/%02h/%02h live=%02h/%02h/%02h frac=%02h wb_valid=%b wb_ch=%0d wb=%06h active=%b",
                     $time, ch, gen,
                     dut.lab_jt_shadow_cur_high_i[ch],
                     dut.lab_jt_shadow_cur_mid_i[ch],
                     dut.lab_jt_shadow_ctrl_jt_i[ch],
                     dut.lab_jt_pcm_core.u_ram.mem[9'h084 + (ch<<3)],
                     dut.lab_jt_pcm_core.u_ram.mem[9'h085 + (ch<<3)],
                     dut.lab_jt_pcm_core.u_ram.mem[9'h086 + (ch<<3)],
                     dut.lab_jt_pcm_core.u_ram.mem[9'h100 + (ch<<3)],
                     dut.lab_jt_pcm_core.wb_cur_valid_i,
                     dut.lab_jt_pcm_core.wb_cur_ch_i,
                     dut.lab_jt_pcm_core.wb_cur_addr_i,
                     dut.lab_jt_pcm_core.active[ch]);
        end
    endtask

    task automatic delta_write(input integer ch, input [7:0] value);
        begin
            c0((ch << 3) + 7, value);
        end
    endtask

    task automatic trigger(input integer ch, input integer gen,
                           input [7:0] low, input [7:0] mid,
                           input [7:0] high, input [7:0] end_addr,
                           input [7:0] delta, input [7:0] control);
        reg [15:0] lo, hi;
        begin
            lo = ch << 3;
            hi = 16'h0080 | lo;
            generation[ch] = gen;
            c0(lo + 0, low);
            c0(lo + 4, mid);
            c0(hi + 4, mid);
            c0(lo + 5, high);
            c0(hi + 5, high);
            c0(lo + 6, end_addr);
            c0(lo + 7, delta);
            c0(hi + 6, control);
            committed_generation[ch] = gen;
            $display("COMMIT t=%0t ch=%0d gen=%0d cur=%02h%02h00 end=%02h delta=%02h ctrl=%02h shadow=%02h/%02h/%02h live=%02h/%02h/%02h frac=%02h",
                     $time, ch, gen, high, mid, end_addr, delta, control,
                     dut.lab_jt_shadow_cur_high_i[ch],
                     dut.lab_jt_shadow_cur_mid_i[ch],
                     dut.lab_jt_shadow_ctrl_jt_i[ch],
                     dut.lab_jt_pcm_core.u_ram.mem[9'h084 + (ch<<3)],
                     dut.lab_jt_pcm_core.u_ram.mem[9'h085 + (ch<<3)],
                     dut.lab_jt_pcm_core.u_ram.mem[9'h086 + (ch<<3)],
                     dut.lab_jt_pcm_core.u_ram.mem[9'h100 + (ch<<3)]);
        end
    endtask

    task automatic report_gen(input integer gen);
        integer limit, m;
        begin
            $display("GEN %0d CH0 req/push/pop/acc/resp/hold/consume/non80/mix/frames=%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d",
                gen, req_count[0][gen], push_count[0][gen], pop_count[0][gen],
                accept_count[0][gen], response_count[0][gen], hold_count[0][gen],
                consume_count[0][gen], nonneutral_count[0][gen],
                mix_count[0][gen], frame_count[0][gen]);
            $display("GEN %0d CH1 req/push/pop/acc/resp/hold/consume/non80/mix/frames=%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d",
                gen, req_count[1][gen], push_count[1][gen], pop_count[1][gen],
                accept_count[1][gen], response_count[1][gen], hold_count[1][gen],
                consume_count[1][gen], nonneutral_count[1][gen],
                mix_count[1][gen], frame_count[1][gen]);
            limit = request_frame_count[0][gen] < request_frame_count[1][gen] ?
                    request_frame_count[0][gen] : request_frame_count[1][gen];
            first_bad_frame[gen] = -1;
            for (m = 0; m < limit; m = m + 1)
                if (first_bad_frame[gen] < 0 &&
                    (request_frame_addr[0][gen][m] !=
                     request_frame_addr[1][gen][m]))
                    first_bad_frame[gen] = m;
            $display("GEN %0d FIRST_PATH_DIFF=%0d limit=%0d", gen,
                     first_bad_frame[gen], limit);
            $display("GEN %0d START ch0 cpu/pair/en/coll/wb/load123=%0d/%0d/%0d/%0d/%0d/%0d,%0d,%0d first_req/non80/mix=%0t/%0t/%0t duration=%0t",
                     gen, cpu_accept_count[0][gen], current_pair_count[0][gen],
                     enable_write_count[0][gen], collision_count[0][gen],
                     pending_wb_seen_count[0][gen], load_count[0][gen][1],
                     load_count[0][gen][2], load_count[0][gen][3],
                     first_request_time[0][gen], first_nonneutral_time[0][gen],
                     first_mix_time[0][gen],
                     last_mix_time[0][gen]-first_mix_time[0][gen]);
            $display("GEN %0d START ch1 cpu/pair/en/coll/wb/load123=%0d/%0d/%0d/%0d/%0d/%0d,%0d,%0d first_req/non80/mix=%0t/%0t/%0t duration=%0t",
                     gen, cpu_accept_count[1][gen], current_pair_count[1][gen],
                     enable_write_count[1][gen], collision_count[1][gen],
                     pending_wb_seen_count[1][gen], load_count[1][gen][1],
                     load_count[1][gen][2], load_count[1][gen][3],
                     first_request_time[1][gen], first_nonneutral_time[1][gen],
                     first_mix_time[1][gen],
                     last_mix_time[1][gen]-first_mix_time[1][gen]);
            if (first_bad_frame[gen] >= 0)
                $display("GEN %0d DIFF_ADDR ch0=%05h ch1=%05h",
                         gen,
                         request_frame_addr[0][gen][first_bad_frame[gen]],
                         request_frame_addr[1][gen][first_bad_frame[gen]]);
        end
    endtask

    segapcm_sound_module #(.CLK_SYS_HZ(CLK_HZ), .SEGAPCM_CLK_HZ(CLK_HZ)) dut (
        .clk(clk), .reset(reset),
        .segapcm_cmd_valid(cmd_valid), .segapcm_cmd_addr(cmd_addr),
        .segapcm_cmd_data(cmd_data), .segapcm_interface(32'h0000_000c),
        .smoke_variant(0), .smoke_variant_valid(0), .smoke_source_loaded(1),
        .loaded_payload_clear(0), .loaded_payload_wr_valid(payload_wr_valid),
        .loaded_payload_wr_addr(payload_wr_addr), .loaded_payload_wr_data(payload_wr_data),
        .loaded_payload_present(1), .loaded_payload_length(19'h25800),
        .loaded_payload_block_count(7), .smoke_ddr_follow_mode(1),
        .smoke_ddr_follow_offset_sel(0), .smoke_ddr_follow_delta_sel(0),
        .smoke_ddr_follow_dest_map(1), .smoke_ddr_follow_dest_basis(1),
        .smoke_ddr_follow_dest_loop_wrap(0), .smoke_c0_use_sel(0),
        .smoke_c0_sample_mode_sel(0), .smoke_c0_delta_speed_sel(0),
        .smoke_c0_hit_window_sel(0), .smoke_c0_format_sel(0),
        .smoke_c0_mame_tick_div_sel(0), .smoke_c0_vol_map_sel(0),
        .smoke_c0_drive_sel(1), .smoke_c0_pm3_audio_mask(16'hffff),
        .smoke_c0_pm3_mix_mode(1), .smoke_c0_pm3_start_policy(0),
        .smoke_c0_jt_backend(1), .smoke_playback_running(1),
        .smoke_playback_done(0), .smoke_vgm_end_seen(0),
        .smoke_vgm_wait_ticks(32'd0),
        .loaded_type80_rom_size(type80_rom_size), .loaded_type80_rom_dest(type80_rom_dest),
        .loaded_ddr_rd_req(ddr_req), .loaded_ddr_rd_ready(ddr_ready),
        .loaded_ddr_rd_addr(ddr_addr), .loaded_ddr_rd_valid(ddr_valid),
        .loaded_ddr_rd_data(ddr_data), .loaded_ddr_payload_present(1),
        .loaded_ddr_payload_length(19'h25800),
        .loaded_ddr_write_req_count_debug(0), .loaded_ddr_write_count_debug(0),
        .loaded_ddr_write_blocked_count_debug(0), .loaded_ddr_write_status_debug(0),
        .loaded_ddr_header_skip_count_debug(0), .loaded_ddr_last_write_index_debug(0),
        .loaded_ddr_last_write_addr_debug(0), .loaded_ddr_last_write_lane_debug(0),
        .loaded_ddr_last_write_data_debug(0), .loaded_ddr_read_count_debug(0),
        .loaded_ddr_last_read_index_debug(ddr_last_index),
        .loaded_ddr_last_read_addr_debug(0), .loaded_ddr_last_read_lane_debug(0),
        .loaded_ddr_last_read_word0_debug(0), .loaded_ddr_last_read_word1_debug(0),
        .loaded_ddr_last_read_data_debug(ddr_data), .loaded_ddr_base_addr_debug(0),
        .loaded_ddr_probe_write_index_debug(0), .loaded_ddr_probe_write_word_debug(0),
        .loaded_ddr_probe_write_lane_debug(0), .loaded_ddr_probe_write_addr_debug(0),
        .loaded_ddr_probe_write_count_debug(0), .loaded_ddr_probe_write_flags_debug(0),
        .loaded_ddr_probe_write_word0_debug(0), .loaded_ddr_probe_write_word6_debug(0),
        .audio_l(audio_l), .audio_r(audio_r), .audio_sample_valid(audio_valid)
    );

    initial begin
        $readmemh("tb/data/after_burner_final_takeoff_ch01.memh", rom);
        for (i=0; i<2; i=i+1) for (j=0; j<10; j=j+1) begin
            req_count[i][j]=0; push_count[i][j]=0; pop_count[i][j]=0;
            accept_count[i][j]=0; response_count[i][j]=0; hold_count[i][j]=0;
            consume_count[i][j]=0; nonneutral_count[i][j]=0; mix_count[i][j]=0;
            frame_count[i][j]=0;
            request_frame_count[i][j]=0;
            cpu_accept_count[i][j]=0; current_pair_count[i][j]=0;
            enable_write_count[i][j]=0; collision_count[i][j]=0;
            pending_wb_seen_count[i][j]=0;
            load_count[i][j][1]=0; load_count[i][j][2]=0; load_count[i][j][3]=0;
            first_request_time[i][j]=0; first_nonneutral_time[i][j]=0;
            first_mix_time[i][j]=0; last_mix_time[i][j]=0;
        end
        for (i=0; i<16; i=i+1) hold_gen[i]=0;
        generation[0]=0; generation[1]=0;
        committed_generation[0]=0; committed_generation[1]=0;
        repeat (8) @(posedge clk); reset=0;
        load_block(21'h00000,19'h00d00,19'h00000);
        load_block(21'h02c00,19'h04300,19'h00d00);
        load_block(21'h08000,19'h08000,19'h05000);
        load_block(21'h2c000,19'h14000,19'h0d000);
        load_block(21'h42000,19'h00400,19'h21000);
        load_block(21'h50000,19'h00400,19'h21400);
        load_block(21'h59600,19'h04000,19'h21800);
        setup_initial_volumes();

        // Establish the bank-3 guitar configuration before the repeated riff.
        c0(16'h0000,8'h18); c0(16'h0006,8'h3f); c0(16'h0007,8'h5a);
        c0(16'h0008,8'h18); c0(16'h000e,8'h3f); c0(16'h000f,8'h5a);

        // Warm-up starts at 24.834558 / 24.869025 and 25.108980 / 25.143447.
        trigger_bank3_riff(0,0); wait_us(34_467);
        trigger_bank3_riff(1,0); wait_us(239_955);
        trigger_bank3_riff(0,0); wait_us(34_467);
        trigger_bank3_riff(1,0); wait_us(240_045);

        // Last known-good complete riff: 25.383492 / 25.418118.
        trigger_bank3_riff(0,1); wait_us(34_626);
        trigger_bank3_riff(1,1);

        // Exact delta glide writes between the good and missing candidates.
        wait_us(651_224); delta_write(0,8'h59);
        wait_us(34_604);  delta_write(1,8'h59);
        wait_us(102_607); delta_write(0,8'h58);
        wait_us(34_603);  delta_write(1,8'h58);
        wait_us(85_465);  delta_write(0,8'h57);
        wait_us(34_603);  delta_write(1,8'h57);
        wait_us(51_157);  delta_write(0,8'h56);
        wait_us(34_603);  delta_write(1,8'h56);
        wait_us(16_848);  delta_write(0,8'h55);
        wait_us(34_603);  delta_write(1,8'h55);
        wait_us(16_871);  delta_write(0,8'h54);
        wait_us(34_286);  delta_write(0,8'h53);
        wait_us(295);     delta_write(1,8'h54);
        wait_us(34_308);  delta_write(1,8'h53);
        wait_us(16_871);  delta_write(0,8'h52);
        wait_us(34_580);  delta_write(1,8'h52);

        // First following full setup: 27.098141 / 27.132925.
        wait_us(462_404);
        trigger(0,2,8'h1c,8'h00,8'h96,8'hd5,8'h5a,8'h5a);
        wait_us(34_693);
        trigger(1,2,8'h1c,8'h00,8'h96,8'hd5,8'h5a,8'h5a);

        // Intervening short pair at 28.539229 / 28.573537.
        wait_us(1_406_304);
        trigger(0,4,8'h1d,8'h00,8'h00,8'h03,8'h4a,8'h5a);
        wait_us(34_308);
        trigger(1,4,8'h1d,8'h00,8'h00,8'h03,8'h4a,8'h5a);

        // Missing candidate 2 at 28.744898 / 28.779524.
        wait_us(171_361);
        trigger(0,3,8'h1c,8'h00,8'h96,8'hd5,8'h50,8'h5a);
        wait_us(34_626);
        trigger(1,3,8'h1c,8'h00,8'h96,8'hd5,8'h50,8'h5a);

        // Intervening short pair at 30.185828 / 30.220295.
        wait_us(1_406_304);
        trigger(0,6,8'h1d,8'h00,8'h00,8'h03,8'h4a,8'h5a);
        wait_us(34_467);
        trigger(1,6,8'h1d,8'h00,8'h00,8'h03,8'h4a,8'h5a);

        // Normal third guitar at 30.391655 / 30.425941.
        wait_us(171_360);
        trigger(0,5,8'h17,8'h00,8'hc0,8'hff,8'h5a,8'h2a);
        wait_us(34_286);
        trigger(1,5,8'h17,8'h00,8'hc0,8'hff,8'h5a,8'h2a);
        wait_us(120_000);

        report_gen(2); report_gen(3); report_gen(5);
        $display("FINAL dropped=%0d overflow=%0d rejected=%0d audio=%0d/%0d",
                 dut.lab_jt_req_dropped_count_i, dut.lab_jt_req_overflow_count_i,
                 dut.lab_jt_response_reject_count_i, audio_l, audio_r);
        $finish;
    end
endmodule

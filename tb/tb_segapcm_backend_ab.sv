`timescale 1ns/1ps

// Real-payload/C0 backend comparison. Compile once with AB_LAB_BACKEND and
// once without it; every signal below the backend boundary is identical.
module tb_segapcm_backend_ab;
`ifndef AB_BLOCKS
`define AB_BLOCKS 10
`endif
`ifndef AB_PAYLOAD_BYTES
`define AB_PAYLOAD_BYTES 59862
`endif
`ifndef AB_EVENTS
`define AB_EVENTS 390
`endif
`ifndef AB_END_CYCLE
`define AB_END_CYCLE 16107948
`endif
`ifndef AB_SEGAPCM_INTERFACE
`define AB_SEGAPCM_INTERFACE 32'h0000_000c
`endif
`ifndef AB_C0_SAMPLE_MODE
`define AB_C0_SAMPLE_MODE 0
`endif
`ifndef AB_C0_DELTA_SPEED
`define AB_C0_DELTA_SPEED 0
`endif
    localparam integer SYS_HZ = 8_053_974;
    localparam integer BLOCKS = `AB_BLOCKS;
    localparam integer PAYLOAD_BYTES = `AB_PAYLOAD_BYTES;
    localparam integer EVENTS = `AB_EVENTS;
    localparam integer END_CYCLE = `AB_END_CYCLE;
    localparam [31:0] SEGAPCM_INTERFACE = `AB_SEGAPCM_INTERFACE;
    localparam [28:0] DDR_BASE = 29'd0;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg cmd_valid = 1'b0;
    reg [15:0] cmd_addr = 16'd0;
    reg [7:0] cmd_data = 8'd0;
    reg payload_valid = 1'b0;
    reg [18:0] payload_addr = 19'd0;
    reg [7:0] payload_data = 8'h80;
    reg [31:0] block_dest = 32'd0;
    reg [31:0] block_size = 32'd0;
    reg [31:0] play_cycle = 32'd0;
    reg playback = 1'b0;
    reg payload_clear = 1'b0;

    reg [7:0] payload_mem [0:PAYLOAD_BYTES-1];
    reg [71:0] block_mem [0:BLOCKS-1];
    reg [63:0] event_mem [0:EVENTS-1];
    integer event_index = 0;
    integer i;
    integer b;
    integer trace_fd;
    integer output_fd;
    integer diag_fd;
    integer result_fd;
    reg [1023:0] payload_file;
    reg [1023:0] blocks_file;
    reg [1023:0] events_file;
    reg [1023:0] trace_file;
    reg [1023:0] output_file;
    reg [1023:0] diag_file;
    reg [1023:0] result_file;

    wire backend_rd_req;
    wire backend_rd_ready;
    wire [18:0] backend_rd_addr;
    wire backend_rd_valid;
    wire [7:0] backend_rd_data;
    wire backend_payload_present;
    wire [18:0] backend_payload_length;
    wire [15:0] backend_last_index;
    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_valid;

    wire [28:0] ddram_addr;
    wire [63:0] ddram_din;
    wire [7:0] ddram_be;
    wire ddram_rd;
    wire ddram_we;
    reg [63:0] ddram_dout = 64'd0;
    reg ddram_dout_ready = 1'b0;
    reg [63:0] ddram_mem [0:8191];
    reg [28:0] ddram_read_addr = 29'd0;
    integer ddram_read_delay = 0;

    always #5 clk = ~clk;

    // The physical DDR model accepts every write and returns reads after six
    // SYS clocks. The lab build does not use this model for payload reads.
    always @(posedge clk) begin
        ddram_dout_ready <= 1'b0;
        if (ddram_we) begin
            if (ddram_be[0]) ddram_mem[ddram_addr-DDR_BASE][7:0] <= ddram_din[7:0];
            if (ddram_be[1]) ddram_mem[ddram_addr-DDR_BASE][15:8] <= ddram_din[15:8];
            if (ddram_be[2]) ddram_mem[ddram_addr-DDR_BASE][23:16] <= ddram_din[23:16];
            if (ddram_be[3]) ddram_mem[ddram_addr-DDR_BASE][31:24] <= ddram_din[31:24];
            if (ddram_be[4]) ddram_mem[ddram_addr-DDR_BASE][39:32] <= ddram_din[39:32];
            if (ddram_be[5]) ddram_mem[ddram_addr-DDR_BASE][47:40] <= ddram_din[47:40];
            if (ddram_be[6]) ddram_mem[ddram_addr-DDR_BASE][55:48] <= ddram_din[55:48];
            if (ddram_be[7]) ddram_mem[ddram_addr-DDR_BASE][63:56] <= ddram_din[63:56];
        end
        if (ddram_rd && ddram_read_delay == 0) begin
            ddram_read_addr <= ddram_addr;
            ddram_read_delay <= 6;
        end else if (ddram_read_delay != 0) begin
            ddram_read_delay <= ddram_read_delay - 1;
            if (ddram_read_delay == 1) begin
                ddram_dout <= ddram_mem[ddram_read_addr-DDR_BASE];
                ddram_dout_ready <= 1'b1;
            end
        end
    end

`ifdef AB_LAB_BACKEND
    vgm_c0_lab_backend #(
        .ADDR_WIDTH(18), .CAPTURE_LEN(19'h20000),
        .PAYLOAD_ADDR_WIDTH(17), .DDRAM_BASE_ADDR(DDR_BASE)
    ) backend (
        .clk(clk), .reset(reset), .ioctl_download(1'b0), .ioctl_wr(1'b0),
        .ioctl_addr(32'd0), .ioctl_dout(8'd0), .ioctl_index(8'd1),
        .mem_rd_req(1'b0), .mem_rd_addr(18'd0),
        .payload_tap_valid(payload_valid), .payload_tap_addr(payload_addr),
        .payload_tap_data(payload_data), .type80_block_dest(block_dest),
        .type80_block_size(block_size), .smoke_rd_req(backend_rd_req),
        .smoke_rd_ready(backend_rd_ready), .smoke_rd_addr(backend_rd_addr),
        .smoke_rd_valid(backend_rd_valid), .smoke_rd_data(backend_rd_data),
        .smoke_payload_present(backend_payload_present),
        .smoke_payload_length(backend_payload_length),
        .smoke_last_read_index_debug(backend_last_index),
        .ddram_busy(1'b0), .ddram_addr(ddram_addr), .ddram_dout(ddram_dout),
        .ddram_dout_ready(ddram_dout_ready), .ddram_rd(ddram_rd),
        .ddram_din(ddram_din), .ddram_be(ddram_be), .ddram_we(ddram_we)
    );
`else
    vgm_ddram_backend #(
        .ADDR_WIDTH(18), .DDRAM_BASE_ADDR(DDR_BASE),
        .SEGAPCM_ROM_BASE_ADDR(DDR_BASE), .WRITE_FIFO_DEPTH(64)
    ) backend (
        .clk(clk), .reset(reset), .ioctl_download(1'b0), .ioctl_wr(1'b0),
        .ioctl_addr(32'd0), .ioctl_dout(8'd0), .ioctl_index(8'd1),
        .mem_rd_req(1'b0), .mem_rd_addr(18'd0),
        .segapcm_copy_wr_req(1'b0), .segapcm_copy_wr_addr(19'd0),
        .segapcm_copy_wr_data(8'd0), .segapcm_copy_flush_req(1'b0),
        .smoke_ddr_payload_tap_valid(payload_valid),
        .smoke_ddr_payload_tap_addr(payload_addr),
        .smoke_ddr_payload_tap_data(payload_data),
        .smoke_ddr_capture_limit(19'h7ffff),
        .smoke_ddr_rd_req(backend_rd_req),
        .smoke_ddr_rd_ready(backend_rd_ready),
        .smoke_ddr_rd_addr(backend_rd_addr),
        .smoke_ddr_rd_valid(backend_rd_valid),
        .smoke_ddr_rd_data(backend_rd_data),
        .smoke_ddr_payload_present(backend_payload_present),
        .smoke_ddr_payload_length(backend_payload_length),
        .smoke_ddr_last_read_index_debug(backend_last_index),
        .ddram_busy(1'b0), .ddram_addr(ddram_addr), .ddram_dout(ddram_dout),
        .ddram_dout_ready(ddram_dout_ready), .ddram_rd(ddram_rd),
        .ddram_din(ddram_din), .ddram_be(ddram_be), .ddram_we(ddram_we)
    );
`endif

    segapcm_sound_module #(.CLK_SYS_HZ(SYS_HZ), .SEGAPCM_CLK_HZ(SYS_HZ)) dut (
        .clk(clk), .reset(reset),
        .segapcm_cmd_valid(cmd_valid), .segapcm_cmd_addr(cmd_addr),
        .segapcm_cmd_data(cmd_data), .segapcm_interface(SEGAPCM_INTERFACE),
        .smoke_variant(3'd0), .smoke_variant_valid(1'b0),
        .smoke_source_loaded(1'b1), .loaded_payload_clear(payload_clear),
        .loaded_payload_wr_valid(payload_valid),
        .loaded_payload_wr_addr(payload_addr),
        .loaded_payload_wr_data(payload_data),
        .loaded_payload_present(backend_payload_present),
        .loaded_payload_length(PAYLOAD_BYTES[18:0]),
        .loaded_payload_block_count(BLOCKS[15:0]),
        .smoke_ddr_follow_mode(1'b1), .smoke_ddr_follow_offset_sel(3'd0),
        .smoke_ddr_follow_delta_sel(3'd0), .smoke_ddr_follow_dest_map(1'b1),
        .smoke_ddr_follow_dest_basis(2'd1),
        .smoke_ddr_follow_dest_loop_wrap(1'b0), .smoke_c0_use_sel(2'd0),
        .smoke_c0_sample_mode_sel(`AB_C0_SAMPLE_MODE),
        .smoke_c0_delta_speed_sel(`AB_C0_DELTA_SPEED),
        .smoke_c0_hit_window_sel(3'd0), .smoke_c0_format_sel(2'd0),
        .smoke_c0_mame_tick_div_sel(3'd0), .smoke_c0_vol_map_sel(3'd0),
        .smoke_c0_drive_sel(2'd1), .smoke_c0_pm3_audio_mask(16'hffff),
        .smoke_c0_pm3_mix_mode(2'd1), .smoke_c0_pm3_start_policy(3'd0),
        .smoke_c0_jt_backend(1'b1), .smoke_playback_running(playback),
        .smoke_playback_done(1'b0), .smoke_vgm_end_seen(1'b0),
        .smoke_vgm_wait_ticks(play_cycle * 44_100 / SYS_HZ),
        .loaded_type80_rom_size(block_size),
        .loaded_type80_rom_dest(block_dest),
        .loaded_ddr_rd_req(backend_rd_req),
        .loaded_ddr_rd_ready(backend_rd_ready),
        .loaded_ddr_rd_addr(backend_rd_addr),
        .loaded_ddr_rd_valid(backend_rd_valid),
        .loaded_ddr_rd_data(backend_rd_data),
        .loaded_ddr_payload_present(backend_payload_present),
        .loaded_ddr_payload_length(backend_payload_length),
        .loaded_ddr_write_req_count_debug(16'd0),
        .loaded_ddr_write_count_debug(16'd0),
        .loaded_ddr_write_blocked_count_debug(16'd0),
        .loaded_ddr_write_status_debug(16'd0),
        .loaded_ddr_header_skip_count_debug(16'd0),
        .loaded_ddr_last_write_index_debug(16'd0),
        .loaded_ddr_last_write_addr_debug(16'd0),
        .loaded_ddr_last_write_lane_debug(16'd0),
        .loaded_ddr_last_write_data_debug(8'd0),
        .loaded_ddr_read_count_debug(16'd0),
        .loaded_ddr_last_read_index_debug(backend_last_index),
        .loaded_ddr_last_read_addr_debug(16'd0),
        .loaded_ddr_last_read_lane_debug(16'd0),
        .loaded_ddr_last_read_word0_debug(16'd0),
        .loaded_ddr_last_read_word1_debug(16'd0),
        .loaded_ddr_last_read_data_debug(backend_rd_data),
        .loaded_ddr_base_addr_debug(16'd0),
        .loaded_ddr_probe_write_index_debug(16'd0),
        .loaded_ddr_probe_write_word_debug(16'd0),
        .loaded_ddr_probe_write_lane_debug(16'd0),
        .loaded_ddr_probe_write_addr_debug(16'd0),
        .loaded_ddr_probe_write_count_debug(16'd0),
        .loaded_ddr_probe_write_flags_debug(16'd0),
        .loaded_ddr_probe_write_word0_debug(16'd0),
        .loaded_ddr_probe_write_word6_debug(16'd0),
        .audio_l(audio_l), .audio_r(audio_r), .audio_sample_valid(audio_valid)
    );

    reg consume_pending = 1'b0;
    reg [31:0] consume_cycle;
    reg [31:0] consume_vgm_sample;
    reg [3:0] consume_ch;
    reg [23:0] consume_current;
    reg [7:0] consume_control;
    reg [7:0] consume_delta;
    reg [18:0] consume_rom_addr;
    reg [15:0] consume_generation;
    reg [7:0] consume_response;
    reg consume_response_valid;
    reg [31:0] consume_response_cycle;
    integer slot = 0;
    integer last_output_cycle = -1;
    integer interval_min = 32'h7fffffff;
    integer interval_max = 0;
    longint interval_sum = 0;
    integer interval_count = 0;
    integer interval_hist [0:511];
    integer nonzero_output_count = 0;
    integer last_nonzero_output_cycle = -1;
    integer nonzero_output_by_second [0:7];
    integer nonzero_output_second;
    integer run_end_cycle = END_CYCLE;
    integer start_offset = 0;
    integer state12_stall_count = 0;
    integer unexpected_neutral_count = 0;
    integer generation_write_count = 0;
    integer prefetch_invalidation_count = 0;
    integer request_drop_count = 0;
    integer request_coalesce_count = 0;
    integer state8_write_collision_count = 0;
    integer fixed_slot_missing_count = 0;
    integer fixed_slot_wrong_channel_count = 0;
    integer fixed_slot_wrong_address_count = 0;
    reg [63:0] consume_hash = 64'hcbf2_9ce4_8422_2325;
    reg [63:0] output_hash = 64'hcbf2_9ce4_8422_2325;
    integer cycle_trace_start = -1;
    integer cycle_trace_end = -1;
    integer anomaly_stop_cycle = -1;
    integer diag_trace_start = -1;
    integer diag_trace_end = -1;
    reg first_state12_stall_seen = 1'b0;
    reg first_fixed_slot_missing_seen = 1'b0;
    reg [31:0] response_cycle_by_ch [0:15];
    reg [7:0] response_data_by_ch [0:15];
    reg [18:0] response_addr_by_ch [0:15];
    reg [15:0] response_generation_by_ch [0:15];
`ifdef AB_DIAG_TRACE
    reg [15:0] diag_state15_request_seen = 16'd0;
    reg [15:0] diag_state1_early_seen = 16'd0;
    reg [15:0] diag_fifo_push_seen = 16'd0;
    reg [15:0] diag_retained_exact_seen = 16'd0;
    reg [15:0] diag_retag_seen = 16'd0;
    reg [15:0] diag_response_seen = 16'd0;
    reg [1:0] diag_mux_winner [0:15];
    reg [1:0] diag_mux_loser [0:15];
`endif

    function signed [15:0] sat2(input signed [15:0] value);
        reg signed [16:0] wide;
        begin
            wide = value <<< 1;
            if (wide > 17'sd32767) sat2 = 16'sh7fff;
            else if (wide < -17'sd32768) sat2 = 16'sh8000;
            else sat2 = wide[15:0];
        end
    endfunction

    always @(posedge clk) begin
`ifdef AB_DIAG_TRACE
        if (!reset && playback) begin
            if (dut.rom_request_event &&
                (dut.lab_jt_raw_req_src_st == 4'd15)) begin
                diag_state15_request_seen[dut.lab_jt_raw_req_src_ch] <= 1'b1;
            end
            if (dut.lab_jt_early_prefetch_event &&
                (dut.lab_jt_live_st == 4'd1)) begin
                diag_state1_early_seen[dut.lab_jt_early_prefetch_ch] <= 1'b1;
            end
            if (dut.lab_jt_early_prefetch_event) begin
                diag_mux_winner[dut.lab_jt_early_prefetch_ch] <= 2'd2;
                if (dut.rom_request_event)
                    diag_mux_loser[dut.lab_jt_raw_req_src_ch] <= 2'd1;
            end else if (dut.rom_request_event) begin
                if (dut.lab_jt_raw_duplicate_early ||
                    dut.lab_jt_raw_retained_exact)
                    diag_mux_winner[dut.lab_jt_raw_req_src_ch] <= 2'd3;
                else
                    diag_mux_winner[dut.lab_jt_raw_req_src_ch] <= 2'd1;
            end
            if (dut.lab_jt_ddr_request_queue_push)
                diag_fifo_push_seen[dut.lab_jt_req_src_ch] <= 1'b1;
            if (dut.lab_jt_raw_retained_exact) begin
                diag_retained_exact_seen[dut.lab_jt_raw_req_src_ch] <= 1'b1;
                diag_retag_seen[dut.lab_jt_raw_req_src_ch] <= 1'b1;
            end
            if (dut.lab_jt_ddr_payload_return_event &&
                dut.lab_jt_ddr_owner_valid_i)
                diag_response_seen[dut.lab_jt_ddr_owner_ch_i] <= 1'b1;
        end
`endif
        if (!reset && playback &&
            (cycle_trace_start >= 0) &&
            (play_cycle >= cycle_trace_start) &&
            (play_cycle <= cycle_trace_end)) begin
            $display("AB_CYCLE cycle=%0d cen=%0b st=%0d ch=%0d cur=%06h cs=%0b rom=%05h event=%0b seen=%0b push=%0b fifo=%0d launch=%0b rdreq=%0b rdvalid=%0b rddata=%02h owner=%0b/%0d/%05h/%0d match=%0b p=%0b/%05h/%0d a=%0b/%05h/%0d early=%0b/%0b/%05h cpu=%0b/%02h/%02h wb=%0b/%0d/%06h slotwr=%0b/%0b cfg=%03h/%02h",
                play_cycle, dut.segapcm_cen, dut.lab_jt_pcm_core.st,
                dut.lab_jt_pcm_core.cur_ch, dut.lab_jt_pcm_core.cur_addr,
                dut.lab_jt_pcm_core.rom_cs, dut.lab_jt_pcm_core.rom_addr,
                dut.rom_request_event, dut.lab_jt_request_seen_pulse,
                dut.lab_jt_ddr_request_queue_push,
                dut.lab_jt_req_fifo_count_i,
                dut.lab_jt_ddr_request_launch,
                backend_rd_req, backend_rd_valid, backend_rd_data,
                dut.lab_jt_ddr_owner_valid_i,
                dut.lab_jt_ddr_owner_ch_i,
                dut.lab_jt_ddr_owner_addr_i,
                dut.lab_jt_ddr_owner_generation_i,
                dut.lab_jt_prefetch_match,
                dut.lab_jt_prefetch_valid_i[dut.lab_jt_pcm_core.cur_ch],
                dut.lab_jt_prefetch_addr_i[dut.lab_jt_pcm_core.cur_ch],
                dut.lab_jt_prefetch_generation_i[dut.lab_jt_pcm_core.cur_ch],
                dut.lab_jt_prefetch_alt_valid_i[
                    dut.lab_jt_pcm_core.cur_ch],
                dut.lab_jt_prefetch_alt_addr_i[
                    dut.lab_jt_pcm_core.cur_ch],
                dut.lab_jt_prefetch_alt_generation_i[
                    dut.lab_jt_pcm_core.cur_ch],
                dut.lab_jt_early_prefetch_event,
                dut.lab_jt_early_prefetch_issued_i[
                    dut.lab_jt_pcm_core.cur_ch],
                dut.lab_jt_early_prefetch_selected_addr,
                dut.core_cpu_cs, dut.latched_cpu_addr,
                dut.lab_jt_cpu_data,
                dut.lab_jt_pcm_core.wb_cur_valid_i,
                dut.lab_jt_pcm_core.wb_cur_ch_i,
                dut.lab_jt_pcm_core.wb_cur_addr_i,
                1'b0, 1'b0,
                dut.lab_jt_pcm_core.cfg_ram_addr,
                dut.lab_jt_pcm_core.cfg_data);
        end
        if (!reset && dut.lab_jt_ddr_payload_return_event &&
            dut.lab_jt_ddr_owner_valid_i) begin
            response_cycle_by_ch[dut.lab_jt_ddr_owner_ch_i] <= play_cycle;
            response_data_by_ch[dut.lab_jt_ddr_owner_ch_i] <=
                dut.lab_jt_response_data;
            response_addr_by_ch[dut.lab_jt_ddr_owner_ch_i] <=
                dut.lab_jt_ddr_owner_addr_i;
            response_generation_by_ch[dut.lab_jt_ddr_owner_ch_i] <=
                dut.lab_jt_ddr_owner_generation_i;
        end
        if (!reset && playback && dut.lab_jt_generation_write_event)
            generation_write_count <= generation_write_count + 1;
        if (!reset && playback && dut.lab_jt_live_generation_invalidating_write)
            prefetch_invalidation_count <= prefetch_invalidation_count + 1;
        if (!reset && playback && dut.lab_jt_early_prefetch_event &&
            dut.rom_request_event) begin
            if (dut.lab_jt_raw_duplicate_early ||
                dut.lab_jt_raw_retained_exact ||
                ((dut.lab_jt_early_prefetch_ch ==
                 dut.lab_jt_raw_req_src_ch) &&
                (dut.lab_jt_early_prefetch_selected_addr ==
                 dut.lab_jt_rom_addr) &&
                (dut.lab_jt_early_prefetch_selected_generation ==
                 (dut.lab_jt_channel_generation_i[
                      dut.lab_jt_raw_req_src_ch] +
                  ((dut.lab_jt_generation_write_event &&
                    (dut.lab_jt_write_ch == dut.lab_jt_raw_req_src_ch)) ?
                       16'd1 : 16'd0))))) begin
                request_coalesce_count <= request_coalesce_count + 1;
            end else begin
                request_drop_count <= request_drop_count + 1;
                $display("AB_REQUEST_MUX_DROP cycle=%0d early=%0d/%05h/%0d raw=%0d/%05h/%0d",
                    play_cycle, dut.lab_jt_early_prefetch_ch,
                    dut.lab_jt_early_prefetch_selected_addr,
                    dut.lab_jt_early_prefetch_selected_generation,
                    dut.lab_jt_raw_req_src_ch, dut.lab_jt_rom_addr,
                    dut.lab_jt_channel_generation_i[
                        dut.lab_jt_raw_req_src_ch]);
`ifdef AB_FAST_DIAG
                if (anomaly_stop_cycle < 0)
                    anomaly_stop_cycle <= play_cycle + 32'd1024;
`endif
            end
        end
        if (!reset && playback && dut.segapcm_cen &&
            (dut.lab_jt_pcm_core.st == 4'd8) &&
            !dut.lab_jt_pcm_core.cfg_en[0] &&
            (dut.lab_jt_pcm_core.cpu_current_write_for_cur ||
             dut.lab_jt_pcm_core.cpu_control_disable_for_cur))
            state8_write_collision_count <= state8_write_collision_count + 1;
        if (playback) begin
            play_cycle <= play_cycle + 1;
            cmd_valid <= 1'b0;
            if (event_index < EVENTS &&
                event_mem[event_index][63:32] <= play_cycle &&
                dut.lab_jt_rv69_queue_empty) begin
                cmd_addr <= event_mem[event_index][31:16];
                cmd_data <= event_mem[event_index][15:8];
                cmd_valid <= 1'b1;
                event_index <= event_index + 1;
            end
        end

        if (!reset && playback && dut.segapcm_cen &&
            dut.lab_jt_pcm_core.st == 4'd12 &&
            !dut.lab_jt_pcm_core.cfg_en[0]) begin
`ifdef AB_DIAG_TRACE
            if (play_cycle >= diag_trace_start &&
                play_cycle <= diag_trace_end) begin
                $fwrite(diag_fd,
                    "%0d,%0d,%0d,12,%06h,%02h,%0d,%05h,%0b,%0b,%0d,%0d,%0b,%0b,%02h,%05h,%0d,%0b,%0b,%0b,%02h,%0b,%0b,%0d,%0d\n",
                    slot, play_cycle, dut.lab_jt_pcm_core.cur_ch,
                    dut.lab_jt_pcm_core.cur_addr,
                    dut.lab_jt_pcm_core.cfg_en,
                    dut.lab_jt_channel_generation_i[
                        dut.lab_jt_pcm_core.cur_ch],
                    dut.lab_jt_pcm_core.rom_addr,
                    diag_state15_request_seen[
                        dut.lab_jt_pcm_core.cur_ch],
                    diag_state1_early_seen[
                        dut.lab_jt_pcm_core.cur_ch],
                    diag_mux_winner[dut.lab_jt_pcm_core.cur_ch],
                    diag_mux_loser[dut.lab_jt_pcm_core.cur_ch],
                    diag_fifo_push_seen[dut.lab_jt_pcm_core.cur_ch],
                    diag_response_seen[dut.lab_jt_pcm_core.cur_ch],
                    response_data_by_ch[dut.lab_jt_pcm_core.cur_ch],
                    response_addr_by_ch[dut.lab_jt_pcm_core.cur_ch],
                    response_generation_by_ch[
                        dut.lab_jt_pcm_core.cur_ch],
                    diag_retained_exact_seen[
                        dut.lab_jt_pcm_core.cur_ch],
                    diag_retag_seen[dut.lab_jt_pcm_core.cur_ch],
                    dut.lab_jt_prefetch_match,
                    dut.lab_jt_pcm_core.c0_effective_rom_data,
                    dut.lab_jt_pcm_core.c0_normal_rom_wait_hold,
                    audio_valid,
                    $signed(dut.lab_jt_pcm_core.snd_left),
                    $signed(dut.lab_jt_pcm_core.snd_right));
            end
`endif
            if (dut.lab_jt_pcm_core.c0_normal_rom_wait_hold) begin
                state12_stall_count <= state12_stall_count + 1;
                if (!first_state12_stall_seen) begin
                    first_state12_stall_seen <= 1'b1;
`ifdef AB_FAST_DIAG
                    // Preserve a short post-fault cycle window without paying
                    // the cost of writing every preceding PCM slot to CSV.
                    anomaly_stop_cycle <= play_cycle + 32'd1024;
`endif
                    $display("AB_FIRST_STATE12_STALL offset=%0d cycle=%0d st=%0d ch=%0d c0=%0b/%02h/%02h rom=%05h live_gen=%0d slot_gen=%0d cpu_invalid=%0b match=%0b primary=%0b/%05h/%0d alt=%0b/%05h/%0d owner=%0b/%0d/%05h/%0d fifo=%0d early=%0b write_pending=%0b early_issued=%0b req_seen=%0b lab_c0=%0b queue_push=%0b queue_range=%0b map=%0b range=%0b rd_req=%0b rd_ready=%0b rd_valid=%0b rd_data=%02h",
                        start_offset,
                        play_cycle, dut.lab_jt_pcm_core.st,
                        dut.lab_jt_pcm_core.cur_ch,
                        dut.core_cpu_cs, dut.latched_cpu_addr,
                        dut.lab_jt_cpu_data,
                        dut.lab_jt_pcm_core.rom_addr,
                        dut.lab_jt_channel_generation_i[
                            dut.lab_jt_pcm_core.cur_ch],
                        response_generation_by_ch[
                            dut.lab_jt_pcm_core.cur_ch],
                        dut.lab_jt_pcm_core.c0_rom_prefetch_cpu_invalid_i[
                            dut.lab_jt_pcm_core.cur_ch],
                        dut.lab_jt_prefetch_match,
                        dut.lab_jt_prefetch_valid_i[
                            dut.lab_jt_pcm_core.cur_ch],
                        dut.lab_jt_prefetch_addr_i[
                            dut.lab_jt_pcm_core.cur_ch],
                        dut.lab_jt_prefetch_generation_i[
                            dut.lab_jt_pcm_core.cur_ch],
                        dut.lab_jt_prefetch_alt_valid_i[
                            dut.lab_jt_pcm_core.cur_ch],
                        dut.lab_jt_prefetch_alt_addr_i[
                            dut.lab_jt_pcm_core.cur_ch],
                        dut.lab_jt_prefetch_alt_generation_i[
                            dut.lab_jt_pcm_core.cur_ch],
                        dut.lab_jt_ddr_owner_valid_i,
                        dut.lab_jt_ddr_owner_ch_i,
                        dut.lab_jt_ddr_owner_addr_i,
                        dut.lab_jt_ddr_owner_generation_i,
                        dut.lab_jt_req_fifo_count_i,
                        dut.lab_jt_early_prefetch_event,
                        dut.lab_jt_write_prefetch_pending_i,
                        dut.lab_jt_early_prefetch_issued_i[
                            dut.lab_jt_pcm_core.cur_ch],
                        dut.lab_jt_request_seen_pulse,
                        dut.lab_c0_active_i,
                        dut.lab_jt_ddr_request_queue_push,
                        dut.smoke_ddr_follow_read_in_range_next,
                        dut.lab_jt_payload_match_valid_next,
                        dut.lab_jt_payload_index_in_range_next,
                        backend_rd_req, backend_rd_ready, backend_rd_valid,
                        backend_rd_data);
                end
            end
            // A literal 0x80 stored in a descriptor is valid PCM data. Count
            // only a descriptor-backed slot that lacks its tagged response;
            // that is the condition which would otherwise fall back to a
            // synthetic-looking neutral byte.
            if (!dut.lab_jt_pcm_core.c0_effective_rom_ok &&
                dut.lab_jt_payload_match_valid_next)
                unexpected_neutral_count <= unexpected_neutral_count + 1;
`ifdef AB_LAB_BACKEND
            if (!dut.lab_jt_fixed_response_available &&
                dut.lab_jt_payload_match_valid_next) begin
                fixed_slot_missing_count <= fixed_slot_missing_count + 1;
                if (!first_fixed_slot_missing_seen) begin
                    first_fixed_slot_missing_seen <= 1'b1;
`ifdef AB_FAST_DIAG
                    anomaly_stop_cycle <= play_cycle + 32'd1024;
`endif
                    $display("AB_FIRST_FIXED_MISSING offset=%0d cycle=%0d st=%0d ch=%0d c0=%0b/%02h/%02h cur=%06h rom=%05h slot=%0b/%0d/%05h rsp=%0b/%02h lab_c0=%0b req=%0b map=%0b range=%0b rd=%0b/%0b/%02h wb=%0b/%0d/%06h",
                        start_offset, play_cycle, dut.lab_jt_pcm_core.st,
                        dut.lab_jt_pcm_core.cur_ch, dut.core_cpu_cs,
                        dut.latched_cpu_addr, dut.lab_jt_cpu_data,
                        dut.lab_jt_pcm_core.cur_addr,
                        dut.lab_jt_pcm_core.rom_addr,
                        dut.lab_jt_fixed_slot_valid_i,
                        dut.lab_jt_fixed_slot_ch_i,
                        dut.lab_jt_fixed_slot_addr_i,
                        dut.lab_jt_fixed_response_valid_i,
                        dut.lab_jt_fixed_response_data_i,
                        dut.lab_c0_active_i, dut.lab_jt_request_seen_pulse,
                        dut.lab_jt_payload_match_valid_next,
                        dut.lab_jt_payload_index_in_range_next,
                        backend_rd_req, backend_rd_valid, backend_rd_data,
                        dut.lab_jt_pcm_core.wb_cur_valid_i,
                        dut.lab_jt_pcm_core.wb_cur_ch_i,
                        dut.lab_jt_pcm_core.wb_cur_addr_i);
                end
            end
            if (dut.lab_jt_fixed_slot_valid_i &&
                (dut.lab_jt_fixed_slot_ch_i !=
                 dut.lab_jt_pcm_core.cur_ch))
                fixed_slot_wrong_channel_count <=
                    fixed_slot_wrong_channel_count + 1;
            if (dut.lab_jt_fixed_slot_valid_i &&
                (dut.lab_jt_fixed_slot_ch_i ==
                 dut.lab_jt_pcm_core.cur_ch) &&
                (dut.lab_jt_fixed_slot_addr_i !=
                 dut.lab_jt_pcm_core.rom_addr))
                fixed_slot_wrong_address_count <=
                    fixed_slot_wrong_address_count + 1;
`endif
            consume_pending <= 1'b1;
            consume_cycle <= play_cycle;
            consume_vgm_sample <=
                ({32'd0, play_cycle} * 64'd44_100) / SYS_HZ;
            consume_ch <= dut.lab_jt_pcm_core.cur_ch;
            consume_current <= dut.lab_jt_pcm_core.cur_addr;
            consume_control <= dut.lab_jt_pcm_core.cfg_en;
            consume_delta <= dut.lab_jt_pcm_core.delta;
            consume_rom_addr <= dut.lab_jt_pcm_core.rom_addr;
            consume_generation <= dut.lab_jt_channel_generation_i[
                dut.lab_jt_pcm_core.cur_ch];
            consume_response <= dut.lab_jt_pcm_core.c0_effective_rom_data;
            consume_response_valid <= dut.lab_jt_pcm_core.c0_effective_rom_ok;
            consume_response_cycle <= response_cycle_by_ch[
                dut.lab_jt_pcm_core.cur_ch];
        end

        if (!reset && playback && dut.segapcm_cen &&
            dut.lab_jt_pcm_core.st == 4'd15 && consume_pending) begin
`ifndef AB_FAST_DIAG
            $fwrite(trace_fd,
                "%0d,%0d,%0d,12,%0d,%06h,%02h,%02h,%05h,%0d,%02h,%0d,%0d,%02h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                slot, consume_vgm_sample, consume_cycle, consume_ch,
                consume_current, consume_control, consume_delta,
                consume_rom_addr, consume_generation, consume_response,
                consume_response_valid, consume_response_cycle,
                dut.lab_jt_pcm_core.pcm_source_data, play_cycle,
                $signed(dut.lab_jt_pcm_core.mul_data),
                $signed(dut.lab_jt_pcm_core.buf_r),
                $signed(dut.lab_jt_pcm_core.acc_l),
                $signed(dut.lab_jt_pcm_core.acc_r),
                $signed(dut.lab_jt_pcm_core.clip_sum(
                    dut.lab_jt_pcm_core.acc_l,
                    dut.lab_jt_pcm_core.clipDAC(dut.lab_jt_pcm_core.mul_data))),
                $signed(dut.lab_jt_pcm_core.clip_sum(
                    dut.lab_jt_pcm_core.acc_r, dut.lab_jt_pcm_core.buf_r)),
                $signed(dut.lab_jt_pcm_core.clipDAC(dut.lab_jt_pcm_core.mul_data)),
                $signed(dut.lab_jt_pcm_core.buf_r),
                $signed(dut.lab_jt_pcm_core.snd_left),
                $signed(dut.lab_jt_pcm_core.snd_right),
                audio_valid, $signed(audio_l), $signed(audio_r),
                $signed(sat2(audio_l)), $signed(sat2(audio_r)));
`endif
            slot <= slot + 1;
            consume_hash <= {consume_hash[58:0], consume_hash[63:59]} ^
                {17'd0, consume_ch, consume_rom_addr,
                 consume_response, consume_control, 8'd0};
            consume_pending <= 1'b0;
`ifdef AB_DIAG_TRACE
            diag_state15_request_seen[dut.lab_jt_pcm_core.cur_ch] <= 1'b0;
            diag_state1_early_seen[dut.lab_jt_pcm_core.cur_ch] <= 1'b0;
            diag_fifo_push_seen[dut.lab_jt_pcm_core.cur_ch] <= 1'b0;
            diag_retained_exact_seen[dut.lab_jt_pcm_core.cur_ch] <= 1'b0;
            diag_retag_seen[dut.lab_jt_pcm_core.cur_ch] <= 1'b0;
            diag_response_seen[dut.lab_jt_pcm_core.cur_ch] <= 1'b0;
            diag_mux_winner[dut.lab_jt_pcm_core.cur_ch] <= 2'd0;
            diag_mux_loser[dut.lab_jt_pcm_core.cur_ch] <= 2'd0;
`endif
        end

        if (!reset && playback && audio_valid) begin
            if (last_output_cycle >= 0) begin
                i = play_cycle - last_output_cycle;
                if (i < interval_min) interval_min = i;
                if (i > interval_max) interval_max = i;
                interval_sum = interval_sum + i;
                interval_count = interval_count + 1;
                if (i < 511) interval_hist[i] = interval_hist[i] + 1;
                else interval_hist[511] = interval_hist[511] + 1;
            end else i = 0;
`ifndef AB_FAST_DIAG
            $fwrite(output_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                    interval_count, play_cycle,
                    i,
                    $signed(dut.lab_jt_pcm_core.snd_left),
                    $signed(dut.lab_jt_pcm_core.snd_right),
                    $signed(audio_l), $signed(audio_r),
                    $signed(sat2(audio_l)), $signed(sat2(audio_r)));
`endif
            last_output_cycle = play_cycle;
            output_hash <= {output_hash[56:0], output_hash[63:57]} ^
                {audio_l, audio_r, dut.lab_jt_pcm_core.snd_left,
                 dut.lab_jt_pcm_core.snd_right};
            if ((audio_l != 16'sd0) || (audio_r != 16'sd0)) begin
                nonzero_output_count = nonzero_output_count + 1;
                last_nonzero_output_cycle = play_cycle;
                nonzero_output_second = play_cycle / SYS_HZ;
                if (nonzero_output_second < 8)
                    nonzero_output_by_second[nonzero_output_second] =
                        nonzero_output_by_second[nonzero_output_second] + 1;
            end
        end
`ifdef AB_FAST_DIAG
        if (anomaly_stop_cycle >= 0 && play_cycle >= anomaly_stop_cycle)
            run_end_cycle <= play_cycle;
`endif
    end

    initial begin
        if (!$value$plusargs("PAYLOAD=%s", payload_file) ||
            !$value$plusargs("BLOCKS=%s", blocks_file) ||
            !$value$plusargs("EVENTS=%s", events_file))
            $fatal(1, "PAYLOAD/BLOCKS/EVENTS plusargs are required");
`ifndef AB_FAST_DIAG
        if (!$value$plusargs("TRACE=%s", trace_file) ||
            !$value$plusargs("OUTPUT_TRACE=%s", output_file))
            $fatal(1, "TRACE/OUTPUT_TRACE plusargs are required");
`endif
        if ($value$plusargs("END_CYCLE=%d", run_end_cycle)) begin end
        if ($value$plusargs("START_OFFSET=%d", start_offset)) begin end
        if ($value$plusargs("RESULT=%s", result_file))
            result_fd = $fopen(result_file, "w");
        else
            result_fd = 0;
        if ($value$plusargs("CYCLE_TRACE_START=%d", cycle_trace_start)) begin end
        if ($value$plusargs("CYCLE_TRACE_END=%d", cycle_trace_end)) begin end
`ifdef AB_DIAG_TRACE
        if (!$value$plusargs("DIAG_TRACE=%s", diag_file))
            $fatal(1, "DIAG_TRACE plusarg is required");
        if (!$value$plusargs("DIAG_TRACE_START=%d", diag_trace_start) ||
            !$value$plusargs("DIAG_TRACE_END=%d", diag_trace_end))
            $fatal(1, "DIAG_TRACE_START/DIAG_TRACE_END plusargs are required");
`endif
        $readmemh(payload_file, payload_mem);
        $readmemh(blocks_file, block_mem);
        $readmemh(events_file, event_mem);
`ifndef AB_FAST_DIAG
        trace_fd = $fopen(trace_file, "w");
        output_fd = $fopen(output_file, "w");
        $fwrite(trace_fd,
            "slot,vgm_sample,sys_cycle,jt_state,channel,current_16_8,control,delta,rom_request_address,request_generation,response_byte,response_valid,response_cycle,consume_byte,consume_cycle,multiply_l,multiply_r,accumulator_l_before,accumulator_r_before,accumulator_l_after,accumulator_r_after,channel_contribution_l,channel_contribution_r,jt_snd_left,jt_snd_right,jt_output_valid,wrapper_pcm_l,wrapper_pcm_r,top_pcm_contribution_l,top_pcm_contribution_r\n");
        $fwrite(output_fd,
            "output_index,sys_cycle,interval,jt_snd_left,jt_snd_right,wrapper_pcm_l,wrapper_pcm_r,top_pcm_contribution_l,top_pcm_contribution_r\n");
`endif
`ifdef AB_DIAG_TRACE
        diag_fd = $fopen(diag_file, "w");
        $fwrite(diag_fd,
            "slot,sys_cycle,channel,jt_state,current_16_8,control,generation,rom_address,state15_request,state1_early_request,request_mux_winner,request_mux_loser,fifo_push,response_valid,response_byte,response_address,response_generation,retained_exact_hit,retag_event,prefetch_valid,consume_byte,state12_stall,jt_output_valid,jt_left,jt_right\n");
`endif
        for (i = 0; i < 8192; i = i + 1) ddram_mem[i] = 64'd0;
        for (i = 0; i < 512; i = i + 1) interval_hist[i] = 0;
        for (i = 0; i < 8; i = i + 1) nonzero_output_by_second[i] = 0;
        for (i = 0; i < 16; i = i + 1) begin
            response_cycle_by_ch[i] = 0;
            response_data_by_ch[i] = 8'h80;
            response_addr_by_ch[i] = 0;
            response_generation_by_ch[i] = 0;
        end
        repeat (8) @(posedge clk);
        reset = 1'b0;

        // Replay the parser's exact block/payload order into both backends.
        for (b = 0; b < BLOCKS; b = b + 1) begin
            block_dest = {11'd0, block_mem[b][71:51]};
            block_size = {13'd0, block_mem[b][50:32]} + 32'd8;
            for (i = block_mem[b][31:13];
                 i < block_mem[b][31:13] + block_mem[b][50:32];
                 i = i + 1) begin
                @(negedge clk);
                payload_addr = i[18:0];
                payload_data = payload_mem[i];
                payload_valid = 1'b1;
            end
            @(negedge clk);
            payload_valid = 1'b0;
        end
        repeat (256) @(posedge clk);
        if (dut.smoke_type80_table_count_i != BLOCKS)
            $fatal(1, "descriptor count %0d expected %0d",
                   dut.smoke_type80_table_count_i, BLOCKS);
        repeat (start_offset) @(posedge clk);
        playback = 1'b1;
        while (play_cycle < run_end_cycle) @(posedge clk);
        playback = 1'b0;
        repeat (1024) @(posedge clk);
        $display("AB_SUMMARY backend=%s slots=%0d outputs=%0d interval_min=%0d interval_max=%0d interval_avg_x1000=%0d stale=%0d wrong_ch=%0d wrong_addr=%0d backlog=%0d stalls=%0d unexpected_neutral=%0d generation_writes=%0d live_invalidations=%0d request_drop=%0d request_coalesce=%0d state8_write_collision=%0d gaps=%0d/%0d",
`ifdef AB_LAB_BACKEND
                 "LAB",
`else
                 "DDR",
`endif
                 slot, interval_count + 1, interval_min, interval_max,
                 interval_count ? interval_sum * 1000 / interval_count : 0,
                 dut.lab_jt_prefetch_stale_consume_count_i,
                 dut.lab_jt_prefetch_wrong_channel_count_i,
                 dut.lab_jt_prefetch_wrong_address_count_i,
                 dut.lab_jt_req_fifo_count_i, state12_stall_count,
                 unexpected_neutral_count, generation_write_count,
                 prefetch_invalidation_count, request_drop_count,
                 request_coalesce_count, state8_write_collision_count,
                 dut.lab_jt_gap_read_count_i,
                 dut.lab_jt_gap_response_count_i);
        $write("AB_HIST");
        for (i = 0; i < 512; i = i + 1)
            if (interval_hist[i] != 0) $write(" %0d:%0d", i, interval_hist[i]);
        $write("\n");
        if (result_fd != 0) begin
            $fdisplay(result_fd,
                "AB_RESULT offset=%0d cycles=%0d slots=%0d outputs=%0d nonzero=%0d last_nonzero=%0d nz_by_sec=%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d interval_min=%0d interval_max=%0d stalls=%0d non_gap_neutral=%0d fixed_missing=%0d wrong_ch=%0d wrong_addr=%0d request_drop=%0d backlog=%0d consume_hash=%016h output_hash=%016h",
                start_offset, play_cycle, slot, interval_count + 1,
                nonzero_output_count, last_nonzero_output_cycle,
                nonzero_output_by_second[0], nonzero_output_by_second[1],
                nonzero_output_by_second[2], nonzero_output_by_second[3],
                nonzero_output_by_second[4], nonzero_output_by_second[5],
                nonzero_output_by_second[6], nonzero_output_by_second[7],
                interval_min, interval_max, state12_stall_count,
                unexpected_neutral_count, fixed_slot_missing_count,
                fixed_slot_wrong_channel_count,
                fixed_slot_wrong_address_count, request_drop_count,
                dut.lab_jt_req_fifo_count_i, consume_hash, output_hash);
            $fclose(result_fd);
        end
`ifdef AB_REQUIRE_CONTINUITY
        if (state12_stall_count != 0 || unexpected_neutral_count != 0 ||
            dut.lab_jt_prefetch_stale_consume_count_i != 0 ||
            dut.lab_jt_prefetch_wrong_channel_count_i != 0 ||
            dut.lab_jt_prefetch_wrong_address_count_i != 0 ||
`ifdef AB_LAB_BACKEND
            fixed_slot_missing_count != 0 ||
            fixed_slot_wrong_channel_count != 0 ||
            fixed_slot_wrong_address_count != 0 ||
`endif
            dut.lab_jt_req_fifo_count_i != 0 ||
            request_drop_count != 0 ||
            interval_min != 256 || interval_max != 256 ||
            generation_write_count == 0 ||
            prefetch_invalidation_count == 0)
            $fatal(1,
                "LAB continuity failure stall=%0d neutral=%0d stale=%0d wrong_ch=%0d wrong_addr=%0d fixed_missing=%0d fixed_wrong_ch=%0d fixed_wrong_addr=%0d fifo=%0d drop=%0d interval=%0d/%0d gen=%0d invalid=%0d",
                state12_stall_count, unexpected_neutral_count,
                dut.lab_jt_prefetch_stale_consume_count_i,
                dut.lab_jt_prefetch_wrong_channel_count_i,
                dut.lab_jt_prefetch_wrong_address_count_i,
`ifdef AB_LAB_BACKEND
                fixed_slot_missing_count,
                fixed_slot_wrong_channel_count,
                fixed_slot_wrong_address_count,
`else
                0, 0, 0,
`endif
                dut.lab_jt_req_fifo_count_i, request_drop_count, interval_min,
                interval_max,
                generation_write_count, prefetch_invalidation_count);

        // A loaded-file switch must not carry any LAB response generation,
        // owner, or early-prefetch state into the next session.
        @(negedge clk);
        payload_clear = 1'b1;
        @(posedge clk);
        #1;
        if (dut.lab_jt_prefetch_valid_i != 16'd0 ||
            dut.lab_jt_prefetch_alt_valid_i != 16'd0 ||
            dut.lab_jt_req_fifo_count_i != 0 ||
            dut.lab_jt_ddr_owner_valid_i ||
            dut.lab_jt_early_prefetch_issued_i != 16'd0 ||
            dut.lab_jt_prefetch_cpu_invalid_mask != 16'd0)
            $fatal(1,
                "LAB session clear failed primary=%04h alt=%04h fifo=%0d owner=%0b early=%04h invalid=%04h",
                dut.lab_jt_prefetch_valid_i,
                dut.lab_jt_prefetch_alt_valid_i,
                dut.lab_jt_req_fifo_count_i,
                dut.lab_jt_ddr_owner_valid_i,
                dut.lab_jt_early_prefetch_issued_i,
                dut.lab_jt_prefetch_cpu_invalid_mask);
        payload_clear = 1'b0;
`endif
`ifndef AB_FAST_DIAG
        $fclose(trace_fd);
        $fclose(output_fd);
`endif
`ifdef AB_DIAG_TRACE
        $fclose(diag_fd);
`endif
        $finish;
    end
endmodule

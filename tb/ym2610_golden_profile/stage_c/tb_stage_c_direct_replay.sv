`timescale 1ns/1ps

module tb_stage_c_direct_replay;
    localparam int MAX_FILE = 1 << 20;
    localparam int MAX_EVENTS = 100000;
    localparam logic [63:0] FNV_OFFSET = 64'hcbf29ce484222325;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic core_reset = 1'b1;
    logic parser_start = 1'b0;
    logic parser_abort;
    logic sample_tick = 1'b0;
    logic [31:0] original_size, data_offset, loop_target;
    logic mem_req;
    logic [22:0] mem_addr;
    logic mem_ready;
    logic mem_valid = 1'b0;
    logic [7:0] mem_data = 8'd0;
    logic parser_write_req, parser_write_port;
    logic [7:0] parser_write_address, parser_write_data;
    logic parser_write_accept;
    logic parser_active, parser_ended, parser_fatal, parser_loop_event;
    logic [7:0] parser_fatal_code;
    logic [31:0] parser_pc, parser_sample, parser_commands, parser_writes;
    logic [31:0] parser_fm, parser_ssg, parser_a, parser_b;
    logic [31:0] parser_blocks, parser_loops;
    logic [63:0] parser_trace_hash, parser_first256;
    logic parser_trace_valid, parser_trace_port, parser_trace_forwarded;
    logic [31:0] parser_trace_pc, parser_trace_sample, parser_trace_next_pc;
    logic [7:0] parser_trace_address, parser_trace_data;
    logic [3:0] parser_trace_semantic;
    logic [63:0] parser_trace_accept_cycle;

    logic accept_a, busy_a, timeout_a, while_busy_a;
    logic accept_a_d = 1'b0;
    logic [31:0] writes_a;
    logic signed [15:0] audio_l_a, audio_r_a, fm_l_a, fm_r_a;
    logic sample_valid_a;
    logic [7:0] psg_a_a, psg_b_a, psg_c_a;
    logic [9:0] psg_snd_a;
    logic signed [15:0] adpcma_l_a, adpcma_r_a, adpcmb_l_a, adpcmb_r_a;
    logic req_a_a, req_b_a;
    logic [19:0] addr_a_a;
    logic [3:0] bank_a_a;
    logic [23:0] addr_b_a;
    logic unexpected_req_a, unexpected_pcm_a, ready_a, rise_a, cen_a;
    logic [31:0] accumulator_a;
    logic invalid_a;

    logic accept_b, busy_b, timeout_b, while_busy_b;
    logic [31:0] writes_b;
    logic signed [15:0] audio_l_b, audio_r_b, fm_l_b, fm_r_b;
    logic sample_valid_b;
    logic [7:0] psg_a_b, psg_b_b, psg_c_b;
    logic [9:0] psg_snd_b;
    logic signed [15:0] adpcma_l_b, adpcma_r_b, adpcmb_l_b, adpcmb_r_b;
    logic req_a_b, req_b_b;
    logic [19:0] addr_a_b;
    logic [3:0] bank_a_b;
    logic [23:0] addr_b_b;
    logic unexpected_req_b, unexpected_pcm_b, ready_b, rise_b, cen_b;
    logic [31:0] accumulator_b;
    logic invalid_b;

    logic [7:0] memory [0:MAX_FILE-1];
    logic [31:0] expected_pc [0:MAX_EVENTS-1];
    logic [31:0] expected_sample [0:MAX_EVENTS-1];
    logic expected_port [0:MAX_EVENTS-1];
    logic [7:0] expected_address [0:MAX_EVENTS-1];
    logic [7:0] expected_data [0:MAX_EVENTS-1];
    logic [3:0] expected_semantic [0:MAX_EVENTS-1];
    logic expected_forwarded [0:MAX_EVENTS-1];
    logic [31:0] expected_next_pc [0:MAX_EVENTS-1];
    logic pending = 1'b0;
    logic [22:0] pending_addr = 23'd0;
    integer response_delay = 0;
    integer cycle_count = 0;
    integer tick_count = 0;
    integer tick_div = 200;
    integer event_count = 0;
    integer event_index = 0;
    integer arm_event = -1;
    integer stop_after_hash = 0;
    integer olga_contract = 0;
    integer check_prefm = 0;
    integer multi_windows = 0;
    integer pre_fm_zero_violations = 0;
    integer fm_nonzero_samples = 0;
    integer file_size;
    integer fd;
    integer trace_fd;
    integer fields;
    integer timeout;
    integer hash_samples = 0;
    logic hash_armed = 1'b0;
    logic hash_started = 1'b0;
    logic [63:0] hash_a = FNV_OFFSET;
    logic [63:0] hash_b = FNV_OFFSET;
    logic [63:0] fm_hash_a = FNV_OFFSET;
    logic [63:0] fm_hash_b = FNV_OFFSET;
    logic [63:0] expected_parser_hash;
    logic trace_exhausted = 1'b0;
    integer window_arm [0:4];
    integer window_samples [0:4];
    integer window_nonzero [0:4];
    logic window_armed [0:4];
    logic window_started [0:4];
    logic [63:0] window_hash_a [0:4];
    logic [63:0] window_hash_b [0:4];
    logic [63:0] window_fm_hash_a [0:4];
    logic [63:0] window_fm_hash_b [0:4];
    integer window_index;
    integer arm0, arm1, arm2, arm3, arm4;
    string filename;
    string trace_filename;
    string window_name;

    always #5 clk = ~clk;
    assign mem_ready = !pending && cycle_count[2:0] != 3'd3;
    assign parser_write_accept = accept_a;
    assign parser_abort = trace_exhausted;

    function automatic [63:0] hash_stereo(
        input logic [63:0] hash,
        input logic [15:0] left_sample,
        input logic [15:0] right_sample
    );
        integer byte_index;
        logic [31:0] sample_word;
        logic [63:0] next;
        begin
            sample_word = {right_sample, left_sample};
            next = hash;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                next = (next ^ sample_word[byte_index*8 +: 8]) *
                       64'h0000_0100_0000_01b3;
            hash_stereo = next;
        end
    endfunction

    function automatic logic all_windows_done;
        integer check_index;
        begin
            all_windows_done = 1'b1;
            for (check_index = 0; check_index < 5;
                 check_index = check_index + 1)
                if (window_samples[check_index] != 512)
                    all_windows_done = 1'b0;
        end
    endfunction

    // Full-song replay deliberately accelerates the 44.1 kHz timeline. Keep
    // the production/parser fault watchdog out of this equivalence TB; the
    // dedicated fault TB verifies the real 64-sample deadline separately.
    ym2610_golden_stage_c_parser #(
        .ADDR_WIDTH(23),
        .BUSY_DEADLINE_SAMPLES(1_000_000)
    ) u_parser (
        .clk(clk), .reset(reset), .abort(parser_abort),
        .start(parser_start), .original_size(original_size),
        .data_offset(data_offset), .loop_target(loop_target),
        .sample_tick(sample_tick), .mem_req(mem_req), .mem_addr(mem_addr),
        .mem_ready(mem_ready), .mem_valid(mem_valid), .mem_data(mem_data),
        .sound_write_req(parser_write_req),
        .sound_write_port(parser_write_port),
        .sound_write_address(parser_write_address),
        .sound_write_data(parser_write_data),
        .sound_write_accept(parser_write_accept), .sound_fault(1'b0),
        .active(parser_active), .ended(parser_ended), .fatal(parser_fatal),
        .fatal_code(parser_fatal_code), .loop_event(parser_loop_event),
        .current_pc(parser_pc), .timeline_sample(parser_sample),
        .command_count(parser_commands), .write_count(parser_writes),
        .forwarded_fm_global_count(parser_fm),
        .forwarded_ssg_count(parser_ssg),
        .suppressed_adpcma_count(parser_a),
        .suppressed_adpcmb_count(parser_b), .data_block_count(parser_blocks),
        .loop_count(parser_loops), .trace_hash(parser_trace_hash),
        .first256_trace_hash(parser_first256),
        .trace_valid(parser_trace_valid),
        .trace_command_pc(parser_trace_pc),
        .trace_sample(parser_trace_sample), .trace_port(parser_trace_port),
        .trace_address(parser_trace_address), .trace_data(parser_trace_data),
        .trace_semantic(parser_trace_semantic),
        .trace_forwarded(parser_trace_forwarded),
        .trace_next_pc(parser_trace_next_pc),
        .trace_sound_accept_cycle(parser_trace_accept_cycle)
    );

    ym2610_golden_stage_c_sound_adapter #(.CLK_SYS_HZ(8_820_000)) u_a (
        .clk(clk), .reset(reset), .core_reset(core_reset),
        .publish_enable(1'b1), .chip_clock(32'd8_000_000),
        .write_req(parser_write_req), .write_port(parser_write_port),
        .write_address(parser_write_address), .write_data(parser_write_data),
        .write_accept(accept_a), .write_busy(busy_a),
        .busy_timeout(timeout_a), .write_while_busy(while_busy_a),
        .accepted_write_count(writes_a), .audio_l(audio_l_a),
        .audio_r(audio_r_a), .audio_sample_valid(sample_valid_a),
        .fm_l(fm_l_a), .fm_r(fm_r_a), .psg_a(psg_a_a), .psg_b(psg_b_a),
        .psg_c(psg_c_a), .psg_snd(psg_snd_a), .adpcma_l(adpcma_l_a),
        .adpcma_r(adpcma_r_a), .adpcmb_l(adpcmb_l_a),
        .adpcmb_r(adpcmb_r_a), .adpcma_request(req_a_a),
        .adpcmb_request(req_b_a), .adpcma_addr(addr_a_a),
        .adpcma_bank(bank_a_a), .adpcmb_addr(addr_b_a),
        .unexpected_pcm_request(unexpected_req_a),
        .unexpected_pcm_activity(unexpected_pcm_a), .core_ready(ready_a),
        .public_sample_rise(rise_a), .cen(cen_a),
        .cen_accumulator(accumulator_a), .clock_invalid(invalid_a)
    );

    ym2610_golden_stage_c_sound_adapter #(.CLK_SYS_HZ(8_820_000)) u_b (
        .clk(clk), .reset(reset), .core_reset(core_reset),
        .publish_enable(1'b1), .chip_clock(32'd8_000_000),
        .write_req(parser_write_req),
        .write_port(expected_port[event_index]),
        .write_address(expected_address[event_index]),
        .write_data(expected_data[event_index]),
        .write_accept(accept_b), .write_busy(busy_b),
        .busy_timeout(timeout_b), .write_while_busy(while_busy_b),
        .accepted_write_count(writes_b), .audio_l(audio_l_b),
        .audio_r(audio_r_b), .audio_sample_valid(sample_valid_b),
        .fm_l(fm_l_b), .fm_r(fm_r_b), .psg_a(psg_a_b), .psg_b(psg_b_b),
        .psg_c(psg_c_b), .psg_snd(psg_snd_b), .adpcma_l(adpcma_l_b),
        .adpcma_r(adpcma_r_b), .adpcmb_l(adpcmb_l_b),
        .adpcmb_r(adpcmb_r_b), .adpcma_request(req_a_b),
        .adpcmb_request(req_b_b), .adpcma_addr(addr_a_b),
        .adpcma_bank(bank_a_b), .adpcmb_addr(addr_b_b),
        .unexpected_pcm_request(unexpected_req_b),
        .unexpected_pcm_activity(unexpected_pcm_b), .core_ready(ready_b),
        .public_sample_rise(rise_b), .cen(cen_b),
        .cen_accumulator(accumulator_b), .clock_invalid(invalid_b)
    );

    always_ff @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        accept_a_d <= accept_a;
        sample_tick <= 1'b0;
        if (tick_count == tick_div-1) begin
            tick_count <= 0;
            sample_tick <= 1'b1;
        end else begin
            tick_count <= tick_count + 1;
        end
        mem_valid <= 1'b0;
        if (mem_req && mem_ready) begin
            if (pending) $fatal(1, "direct replay multiple outstanding");
            pending <= 1'b1;
            pending_addr <= mem_addr;
            response_delay <= mem_addr[1:0] + 1;
        end
        if (pending) begin
            if (response_delay == 0) begin
                mem_data <= memory[pending_addr];
                mem_valid <= 1'b1;
                pending <= 1'b0;
            end else response_delay <= response_delay - 1;
        end
    end

    always @(posedge clk) begin
        #1;
        if (!reset && !core_reset) begin
            if (accept_a !== accept_b || busy_a !== busy_b ||
                rise_a !== rise_b || audio_l_a !== audio_l_b ||
                audio_r_a !== audio_r_b || fm_l_a !== fm_l_b ||
                fm_r_a !== fm_r_b || psg_snd_a !== psg_snd_b)
                $fatal(1, "parser/direct sound divergence event=%0d", event_index);
            if (parser_write_req &&
                (parser_write_port != expected_port[event_index] ||
                 parser_write_address != expected_address[event_index] ||
                 parser_write_data != expected_data[event_index]))
                $fatal(1, "independent direct sequence mismatch event=%0d", event_index);
            if (parser_trace_valid) begin
                if (event_index >= event_count ||
                    parser_trace_pc != expected_pc[event_index] ||
                    parser_trace_sample != expected_sample[event_index] ||
                    parser_trace_port != expected_port[event_index] ||
                    parser_trace_address != expected_address[event_index] ||
                    parser_trace_data != expected_data[event_index] ||
                    parser_trace_semantic != expected_semantic[event_index] ||
                    parser_trace_forwarded != expected_forwarded[event_index] ||
                    parser_trace_next_pc != expected_next_pc[event_index])
                    $fatal(1, "trace/direct mismatch event=%0d", event_index);
                if ((parser_trace_forwarded &&
                     (!accept_a_d ||
                      parser_trace_accept_cycle == 64'hffff_ffff_ffff_ffff)) ||
                    (!parser_trace_forwarded &&
                     (accept_a_d ||
                      parser_trace_accept_cycle != 64'hffff_ffff_ffff_ffff)))
                    $fatal(1, "trace sound-accept cycle contract mismatch event=%0d forwarded=%0d accept=%0d cycle=%016x",
                           event_index, parser_trace_forwarded, accept_a_d,
                           parser_trace_accept_cycle);
                for (window_index = 0; window_index < 5;
                     window_index = window_index + 1)
                    if (multi_windows &&
                        event_index == window_arm[window_index])
                        window_armed[window_index] = 1'b1;
                if (!multi_windows &&
                    ((arm_event >= 0 && event_index == arm_event) ||
                    (arm_event < 0 && parser_trace_address == 8'h28 &&
                     parser_trace_data == 8'hf1) ||
                    (arm_event < 0 && parser_fm == 0 &&
                     parser_trace_address == 8'h0a &&
                     parser_trace_data == 8'h0f)))
                    hash_armed = 1'b1;
                event_index = event_index + 1;
                if (stop_after_hash && event_index == event_count)
                    trace_exhausted = 1'b1;
            end
            if (hash_armed && hash_samples < 512 && rise_a &&
                (hash_started || audio_l_a != 0 || audio_r_a != 0 ||
                 fm_l_a != 0 || fm_r_a != 0)) begin
                hash_started = 1'b1;
                hash_a = hash_stereo(hash_a, audio_l_a, audio_r_a);
                hash_b = hash_stereo(hash_b, audio_l_b, audio_r_b);
                fm_hash_a = hash_stereo(fm_hash_a, fm_l_a, fm_r_a);
                fm_hash_b = hash_stereo(fm_hash_b, fm_l_b, fm_r_b);
                if (fm_l_a != 0 || fm_r_a != 0)
                    fm_nonzero_samples = fm_nonzero_samples + 1;
                hash_samples = hash_samples + 1;
            end
            if (multi_windows && rise_a) begin
                for (window_index = 0; window_index < 5;
                     window_index = window_index + 1) begin
                    if (window_armed[window_index] &&
                        window_samples[window_index] < 512 &&
                        (window_started[window_index] || audio_l_a != 0 ||
                         audio_r_a != 0 || fm_l_a != 0 || fm_r_a != 0)) begin
                        window_started[window_index] = 1'b1;
                        window_hash_a[window_index] = hash_stereo(
                            window_hash_a[window_index], audio_l_a, audio_r_a);
                        window_hash_b[window_index] = hash_stereo(
                            window_hash_b[window_index], audio_l_b, audio_r_b);
                        window_fm_hash_a[window_index] = hash_stereo(
                            window_fm_hash_a[window_index], fm_l_a, fm_r_a);
                        window_fm_hash_b[window_index] = hash_stereo(
                            window_fm_hash_b[window_index], fm_l_b, fm_r_b);
                        if (fm_l_a != 0 || fm_r_a != 0)
                            window_nonzero[window_index] =
                                window_nonzero[window_index] + 1;
                        window_samples[window_index] =
                            window_samples[window_index] + 1;
                    end
                end
            end
            if (check_prefm &&
                ((!multi_windows && !hash_armed) ||
                 (multi_windows && !window_armed[0])) &&
                (audio_l_a != 0 || audio_r_a != 0 ||
                 fm_l_a != 0 || fm_r_a != 0))
                pre_fm_zero_violations = pre_fm_zero_violations + 1;
            if (olga_contract && psg_snd_a != 0)
                $fatal(1, "Olga unexpectedly activated SSG lane");
            if (ready_a && ready_b &&
                (^{accept_a, accept_b, audio_l_a, audio_r_a,
                    audio_l_b, audio_r_b, fm_l_a, fm_r_a, fm_l_b, fm_r_b,
                    psg_snd_a, psg_snd_b, req_a_a, req_b_a, req_a_b,
                    req_b_b}) === 1'bx)
                $fatal(1, "direct replay X/Z");
        end
    end

    initial begin
        if (!$value$plusargs("VGM=%s", filename) ||
            !$value$plusargs("TRACE=%s", trace_filename) ||
            !$value$plusargs("ORIGINAL=%d", original_size) ||
            !$value$plusargs("DATA=%h", data_offset) ||
            !$value$plusargs("EXPECT_EVENTS=%d", event_count) ||
            !$value$plusargs("EXPECT_HASH=%h", expected_parser_hash))
            $fatal(1, "missing direct replay plusargs");
        if (!$value$plusargs("LOOP=%h", loop_target)) loop_target = 0;
        if (!$value$plusargs("TICK_DIV=%d", tick_div)) tick_div = 200;
        if (!$value$plusargs("ARM_EVENT=%d", arm_event)) arm_event = -1;
        stop_after_hash = $test$plusargs("STOP_AFTER_HASH");
        olga_contract = $test$plusargs("OLGA_CONTRACT");
        check_prefm = $test$plusargs("CHECK_PREFM");
        multi_windows = $test$plusargs("MULTI_WINDOWS");
        for (window_index = 0; window_index < 5;
             window_index = window_index + 1) begin
            window_arm[window_index] = -1;
            window_samples[window_index] = 0;
            window_nonzero[window_index] = 0;
            window_armed[window_index] = 1'b0;
            window_started[window_index] = 1'b0;
            window_hash_a[window_index] = FNV_OFFSET;
            window_hash_b[window_index] = FNV_OFFSET;
            window_fm_hash_a[window_index] = FNV_OFFSET;
            window_fm_hash_b[window_index] = FNV_OFFSET;
        end
        if (multi_windows &&
            (!$value$plusargs("ARM0=%d", arm0) ||
             !$value$plusargs("ARM1=%d", arm1) ||
             !$value$plusargs("ARM2=%d", arm2) ||
             !$value$plusargs("ARM3=%d", arm3) ||
             !$value$plusargs("ARM4=%d", arm4)))
            $fatal(1, "missing multi-window arm plusargs");
        window_arm[0] = arm0;
        window_arm[1] = arm1;
        window_arm[2] = arm2;
        window_arm[3] = arm3;
        window_arm[4] = arm4;
        if (!$value$plusargs("WINDOW=%s", window_name)) window_name = "synthetic";
        if (tick_div < 1) $fatal(1, "invalid TICK_DIV");
        fd = $fopen(filename, "rb");
        if (!fd) $fatal(1, "cannot open VGM");
        file_size = $fread(memory, fd);
        $fclose(fd);
        trace_fd = $fopen(trace_filename, "r");
        if (!trace_fd) $fatal(1, "cannot open trace");
        event_index = 0;
        while (!$feof(trace_fd) && event_index < MAX_EVENTS) begin
            fields = $fscanf(trace_fd, "%h %d %d %h %h %d %d %h\n",
                expected_pc[event_index], expected_sample[event_index],
                expected_port[event_index], expected_address[event_index],
                expected_data[event_index], expected_semantic[event_index],
                expected_forwarded[event_index], expected_next_pc[event_index]);
            if (fields == 8) event_index = event_index + 1;
        end
        $fclose(trace_fd);
        if (event_index != event_count)
            $fatal(1, "trace event count=%0d/%0d", event_index, event_count);
        event_index = 0;

        repeat (5) @(posedge clk);
        reset = 1'b0;
        repeat (32) @(posedge clk);
        core_reset = 1'b0;
        timeout = 0;
        while ((!ready_a || !ready_b) && timeout < 2_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!ready_a || !ready_b) $fatal(1, "direct cores not ready");
        @(posedge rise_a);
        @(negedge clk);
        parser_start = 1'b1;
        @(negedge clk);
        parser_start = 1'b0;
        timeout = 0;
        while (!parser_fatal &&
               ((stop_after_hash &&
                 ((!multi_windows && hash_samples < 512) ||
                  (multi_windows && !all_windows_done()))) ||
                (!stop_after_hash && !parser_ended)) &&
               timeout < 80_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        #1;
        if (timeout >= 80_000_000 || parser_fatal ||
            (!stop_after_hash && !parser_ended) ||
            (!stop_after_hash && event_index != event_count) ||
            (!stop_after_hash && parser_trace_hash != expected_parser_hash) ||
            (stop_after_hash && !multi_windows &&
             (arm_event < 0 || event_index <= arm_event)) ||
            (!multi_windows && hash_samples != 512) ||
            (!multi_windows && hash_a != hash_b) || writes_a != writes_b ||
            (!multi_windows && fm_hash_a != fm_hash_b) ||
            timeout_a || timeout_b || while_busy_a || while_busy_b ||
            unexpected_req_a || unexpected_req_b ||
            unexpected_pcm_a || unexpected_pcm_b ||
            req_a_a || req_b_a || req_a_b || req_b_b ||
            (check_prefm && pre_fm_zero_violations != 0) ||
            (olga_contract && !multi_windows && fm_nonzero_samples == 0))
            $fatal(1, "direct replay result mismatch ended=%0d fatal=%0d events=%0d/%0d trace=%016x/%016x samples=%0d hashes=%016x/%016x writes=%0d/%0d",
                   parser_ended, parser_fatal, event_index, event_count,
                   parser_trace_hash, expected_parser_hash, hash_samples,
                   hash_a, hash_b, writes_a, writes_b);
        if (multi_windows) begin
            for (window_index = 0; window_index < 5;
                 window_index = window_index + 1) begin
                if (window_samples[window_index] != 512 ||
                    window_nonzero[window_index] == 0 ||
                    window_hash_a[window_index] != window_hash_b[window_index] ||
                    window_fm_hash_a[window_index] !=
                    window_fm_hash_b[window_index])
                    $fatal(1, "window result mismatch index=%0d samples=%0d nonzero=%0d audio=%016x/%016x fm=%016x/%016x",
                           window_index, window_samples[window_index],
                           window_nonzero[window_index],
                           window_hash_a[window_index],
                           window_hash_b[window_index],
                           window_fm_hash_a[window_index],
                           window_fm_hash_b[window_index]);
                $display("STAGE_C_OLGA_WINDOW PASS index=%0d arm=%0d parser_audio=%016x direct_audio=%016x parser_fm=%016x direct_fm=%016x samples=512 fm_nonzero=%0d",
                         window_index, window_arm[window_index],
                         window_hash_a[window_index],
                         window_hash_b[window_index],
                         window_fm_hash_a[window_index],
                         window_fm_hash_b[window_index],
                         window_nonzero[window_index]);
            end
        end else begin
            $display("STAGE_C_DIRECT_REPLAY PASS window=%s events_seen=%0d trace_rows=%0d parser_trace=%016x parser_audio=%016x direct_audio=%016x parser_fm=%016x direct_fm=%016x fm_nonzero=%0d prefm_zero=%0d accept_cycle_match=1 fm_lane_match=1 final_lr_match=1 pcm=0 xz=0",
                     window_name, event_index, event_count, parser_trace_hash,
                     hash_a, hash_b, fm_hash_a, fm_hash_b,
                     fm_nonzero_samples, pre_fm_zero_violations == 0);
        end
        $finish;
    end
endmodule

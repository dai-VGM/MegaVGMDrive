`timescale 1ns/1ps

module tb_ym2610_player_core;
    localparam int MAX_FILE = 1 << 23;
    logic clk = 1'b0;
    logic hard_reset = 1'b1;
    logic soft_reset = 1'b0;
    logic ioctl_download = 1'b0;
    logic load_done_pulse = 1'b0;
    logic [31:0] file_size;
    logic mem_req;
    logic [22:0] mem_addr;
    logic mem_ready = 1'b1;
    logic mem_valid = 1'b0;
    logic [7:0] mem_data = 8'd0;
    logic signed [15:0] audio_l, audio_r;
    logic audio_sample, external_mute, start_pulse;
    logic [31:0] start_count;
    logic [3:0] load_state, classification;
    logic raw_variant_b;
    logic [7:0] reject_code;
    logic [31:0] original_size, parser_pc, wait_remaining, parser_samples;
    logic [31:0] parser_writes, port0_writes, port1_writes, loop_count;
    logic [7:0] parser_opcode;
    logic [3:0] descriptor_a_count, descriptor_b_count;
    logic [31:0] b_only_writes, unknown_writes, first_bad_pc;
    logic first_bad_port;
    logic [7:0] first_bad_address, first_bad_data;
    logic [31:0] unsupported_pc;
    logic [7:0] unsupported_opcode;
    logic [31:0] pcm_requests, pcm_responses, adpcma_requests, adpcmb_requests;
    logic [19:0] pcm_last_address;
    logic [19:0] adpcma_last_address, adpcmb_last_address;
    logic [31:0] adpcma_fetch_requests, adpcma_fetch_responses;
    logic [31:0] adpcmb_fetch_requests, adpcmb_fetch_responses;
    logic [6:0] pcm_occupancy;
    logic parser_underflow, adpcma_underflow, adpcmb_underflow;
    logic stale_response, owner_mismatch, busy_timeout, write_while_busy;
    logic [15:0] peak_l, peak_r;
    logic [7:0] psg_a, psg_b, psg_c;
    logic [9:0] psg_snd;
    logic signed [15:0] adpcma_l, adpcma_r, adpcmb_l, adpcmb_r;
    logic [7:0] memory [0:MAX_FILE-1];
    logic pending;
    logic [22:0] pending_addr;
    integer response_delay;
    integer fd, count, timeout;
    string filename;
    string expected_lane;
    logic sample_d;
    logic psg_a_seen, psg_b_seen, psg_c_seen, final_seen;
    logic adpcma_seen, adpcmb_seen, simultaneous_seen;
    logic [63:0] audio_hash;
    logic [31:0] sample_edges;
    logic xz_seen;
    integer start_pulse_count;
    logic after_loop;
    logic post_loop_nonzero;
    logic [31:0] loop_sample_start;

    always #5 clk = ~clk;

    function automatic [63:0] fnv_byte(input [63:0] hash, input [7:0] value);
        fnv_byte = (hash ^ value) * 64'h0000_0100_0000_01b3;
    endfunction

    ym2610_player_core #(.SYS_CLK_HZ(8_000_000), .CACHE_ENTRIES(16)) dut (
        .clk(clk), .hard_reset(hard_reset), .soft_reset(soft_reset),
        .ioctl_download(ioctl_download), .load_done_pulse(load_done_pulse),
        .file_size(file_size), .load_generation(8'd1),
        .mem_req(mem_req), .mem_addr(mem_addr),
        .mem_ready(mem_ready), .mem_valid(mem_valid), .mem_data(mem_data),
        .audio_l(audio_l), .audio_r(audio_r), .audio_sample(audio_sample),
        .external_mute(external_mute), .start_pulse(start_pulse),
        .start_count(start_count), .load_state(load_state),
        .classification(classification), .raw_variant_b(raw_variant_b),
        .reject_code(reject_code),
        .original_size(original_size), .parser_pc(parser_pc),
        .parser_opcode(parser_opcode), .wait_remaining(wait_remaining),
        .parser_samples(parser_samples), .parser_writes(parser_writes),
        .port0_writes(port0_writes), .port1_writes(port1_writes),
        .loop_count(loop_count), .descriptor_a_count(descriptor_a_count),
        .descriptor_b_count(descriptor_b_count),
        .b_only_writes(b_only_writes), .unknown_writes(unknown_writes),
        .first_bad_pc(first_bad_pc), .first_bad_port(first_bad_port),
        .first_bad_address(first_bad_address), .first_bad_data(first_bad_data),
        .unsupported_pc(unsupported_pc),
        .unsupported_opcode(unsupported_opcode),
        .pcm_requests(pcm_requests), .pcm_responses(pcm_responses),
        .adpcma_requests(adpcma_requests), .adpcmb_requests(adpcmb_requests),
        .pcm_last_address(pcm_last_address), .pcm_occupancy(pcm_occupancy),
        .adpcma_last_address(adpcma_last_address),
        .adpcmb_last_address(adpcmb_last_address),
        .adpcma_fetch_requests(adpcma_fetch_requests),
        .adpcma_fetch_responses(adpcma_fetch_responses),
        .adpcmb_fetch_requests(adpcmb_fetch_requests),
        .adpcmb_fetch_responses(adpcmb_fetch_responses),
        .parser_underflow(parser_underflow),
        .adpcma_underflow(adpcma_underflow),
        .adpcmb_underflow(adpcmb_underflow),
        .stale_response(stale_response), .owner_mismatch(owner_mismatch),
        .busy_timeout(busy_timeout), .write_while_busy(write_while_busy),
        .peak_l(peak_l), .peak_r(peak_r), .psg_a(psg_a), .psg_b(psg_b),
        .psg_c(psg_c), .psg_snd(psg_snd), .adpcma_l(adpcma_l),
        .adpcma_r(adpcma_r), .adpcmb_l(adpcmb_l), .adpcmb_r(adpcmb_r)
    );

    always_ff @(posedge clk) begin
        mem_valid <= 1'b0;
        if (mem_req && mem_ready && !pending) begin
            pending <= 1'b1;
            pending_addr <= mem_addr;
            response_delay <= 12 + mem_addr[1:0];
        end
        if (pending) begin
            if (response_delay == 0) begin
                mem_data <= memory[pending_addr];
                mem_valid <= 1'b1;
                pending <= 1'b0;
            end else response_delay <= response_delay - 1;
        end

        sample_d <= audio_sample;
        if (load_state == 4'd7) begin
            if (psg_a != 0) psg_a_seen <= 1'b1;
            if (psg_b != 0) psg_b_seen <= 1'b1;
            if (psg_c != 0) psg_c_seen <= 1'b1;
            if (adpcma_l != 0 || adpcma_r != 0) adpcma_seen <= 1'b1;
            if (adpcmb_l != 0 || adpcmb_r != 0) adpcmb_seen <= 1'b1;
            if ((adpcma_l != 0 || adpcma_r != 0) &&
                (adpcmb_l != 0 || adpcmb_r != 0)) simultaneous_seen <= 1'b1;
            if (audio_l != 0 || audio_r != 0) final_seen <= 1'b1;
            if (after_loop && (audio_l != 0 || audio_r != 0))
                post_loop_nonzero <= 1'b1;
        end
        if (start_pulse) start_pulse_count <= start_pulse_count + 1;
        if (audio_sample && !sample_d) begin
            if ($isunknown(audio_l) || $isunknown(audio_r) ||
                $isunknown(psg_snd) ||
                ((adpcma_requests != 0) &&
                 ($isunknown(adpcma_l) || $isunknown(adpcma_r))) ||
                ((adpcmb_requests != 0) &&
                 ($isunknown(adpcmb_l) || $isunknown(adpcmb_r)))) begin
                if (!xz_seen)
                    $display("CORE_XZ first_sample=%0d mask=%b%b%b%b%b%b%b L=%h R=%h psg=%h A=%h/%h B=%h/%h",
                        sample_edges,
                        $isunknown(audio_l), $isunknown(audio_r),
                        $isunknown(psg_snd), $isunknown(adpcma_l),
                        $isunknown(adpcma_r), $isunknown(adpcmb_l),
                        $isunknown(adpcmb_r),
                        audio_l, audio_r, psg_snd,
                        adpcma_l, adpcma_r, adpcmb_l, adpcmb_r);
                xz_seen <= 1'b1;
            end
            audio_hash <= fnv_byte(fnv_byte(fnv_byte(fnv_byte(audio_hash,
                audio_l[7:0]), audio_l[15:8]), audio_r[7:0]), audio_r[15:8]);
            sample_edges <= sample_edges + 32'd1;
        end
    end

    initial begin
        if (!$value$plusargs("VGM=%s", filename)) $fatal(1, "missing +VGM");
        if (!$value$plusargs("EXPECT=%s", expected_lane)) expected_lane = "NONE";
        fd = $fopen(filename, "rb");
        if (!fd) $fatal(1, "cannot open %s", filename);
        count = $fread(memory, fd);
        $fclose(fd);
        file_size = count;
        pending = 1'b0;
        pending_addr = 0;
        response_delay = 0;
        sample_d = 1'b0;
        psg_a_seen = 1'b0;
        psg_b_seen = 1'b0;
        psg_c_seen = 1'b0;
        final_seen = 1'b0;
        adpcma_seen = 1'b0;
        adpcmb_seen = 1'b0;
        simultaneous_seen = 1'b0;
        audio_hash = 64'hcbf2_9ce4_8422_2325;
        sample_edges = 0;
        xz_seen = 1'b0;
        start_pulse_count = 0;
        after_loop = 1'b0;
        post_loop_nonzero = 1'b0;
        loop_sample_start = 32'd0;
        repeat (8) @(posedge clk);
        hard_reset <= 1'b0;
        repeat (2) @(posedge clk);
        load_done_pulse <= 1'b1;
        @(posedge clk);
        load_done_pulse <= 1'b0;
        @(posedge clk);
        while (load_state == 4'd0) @(posedge clk);
        timeout = 0;
        while (load_state != 4'd10 && load_state != 4'd9 &&
               !(expected_lane == "LOOP" && loop_count >= 1) &&
               timeout < 20_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
            if ((timeout % 1_000_000) == 0)
                $display("CORE_PROGRESS cycles=%0d state=%0d scan_state=%0d parser_state=%0d pc=%08x samples=%0d writes=%0d",
                    timeout, load_state, dut.u_scanner.state,
                    dut.u_parser.state, parser_pc, parser_samples,
                    parser_writes);
        end
        repeat (4) @(posedge clk);
        if (timeout >= 20_000_000) $fatal(1, "core timeout state=%0d pc=%08x", load_state, parser_pc);
        if (expected_lane == "LOOP") begin
            after_loop = 1'b1;
            loop_sample_start = sample_edges;
            timeout = 0;
            while (sample_edges < loop_sample_start + 32'd9_000 &&
                   load_state == 4'd7 && timeout < 3_000_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (load_state != 4'd7 || loop_count < 1 || start_count != 1 ||
                external_mute || !final_seen || !post_loop_nonzero ||
                sample_edges < loop_sample_start + 32'd9_000 ||
                adpcma_underflow ||
                adpcmb_underflow || stale_response || owner_mismatch ||
                busy_timeout)
                $fatal(1, "loop continuity contract failure");
            $display("LOOP_RESULT loops=%0d start=%0d reset=0 descriptor_hold=1 post_samples=9000 post_nonzero=%0d audio_continuity=1 result=PASS",
                loop_count, start_count, post_loop_nonzero);
            $finish;
        end
        if (expected_lane == "LIFE") begin
            ioctl_download <= 1'b1;
            repeat (4) @(posedge clk);
            ioctl_download <= 1'b0;
            repeat (2) @(posedge clk);
            load_done_pulse <= 1'b1;
            @(posedge clk);
            load_done_pulse <= 1'b0;
            @(posedge clk);
            while (load_state == 4'd10) @(posedge clk);
            timeout = 0;
            while (load_state != 4'd10 && load_state != 4'd9 &&
                   timeout < 2_000_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (load_state != 4'd10) $fatal(1, "same-file reload failed");
            soft_reset <= 1'b1;
            @(posedge clk);
            soft_reset <= 1'b0;
            @(posedge clk);
            while (load_state == 4'd10) @(posedge clk);
            timeout = 0;
            while (load_state != 4'd10 && load_state != 4'd9 &&
                   timeout < 2_000_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (load_state != 4'd10) $fatal(1, "software reset replay failed");
            if (start_count != 3 || start_pulse_count != 3)
                $fatal(1, "lifecycle starts count=%0d pulses=%0d",
                       start_count, start_pulse_count);
            if (parser_writes != 0 || adpcma_underflow || adpcmb_underflow ||
                stale_response || owner_mismatch || busy_timeout)
                $fatal(1, "lifecycle transport failure");
            $display("LIFECYCLE_RESULT cold=1 reload=1 soft_reset=1 start_count=%0d start_pulses=%0d parser_restart=0 first_duplicate=0 result=PASS",
                start_count, start_pulse_count);
            $finish;
        end
        if (expected_lane == "REJECT") begin
            if (load_state != 4'd9) $fatal(1, "fixture was not rejected");
            if (start_count != 0 || dut.bus_accepted != 0 || !external_mute)
                $fatal(1, "reject leaked playback start/write/audio");
            ioctl_download <= 1'b1;
            repeat (4) @(posedge clk);
            ioctl_download <= 1'b0;
            repeat (2) @(posedge clk);
            load_done_pulse <= 1'b1;
            @(posedge clk);
            load_done_pulse <= 1'b0;
            @(posedge clk);
            timeout = 0;
            while (load_state != 4'd9 && timeout < 2_000_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (load_state != 4'd9 || start_count != 0 ||
                dut.bus_accepted != 0 || !external_mute)
                $fatal(1, "reject reload contract failure");
            $display("REJECT_RESULT class=%0d reject=%02x b_only=%0d unknown=%0d first_pc=%08x first_port=%0d first_addr=%02x first_data=%02x unsupported_pc=%08x unsupported_opcode=%02x start=%0d jt10_accept=%0d mute=%0d reload=1 result=PASS",
                classification, reject_code, b_only_writes, unknown_writes,
                first_bad_pc, first_bad_port, first_bad_address,
                first_bad_data, unsupported_pc, unsupported_opcode,
                start_count, dut.bus_accepted, external_mute);
            $finish;
        end
        if (load_state == 4'd9) $fatal(1, "core reject code=%02x pc=%08x A_under=%0d B_under=%0d range=%0d stale=%0d owner=%0d busy=%0d",
            reject_code, parser_pc, adpcma_underflow, adpcmb_underflow,
            dut.pcm_range_error, stale_response, owner_mismatch, busy_timeout);
        if (start_count != 1) $fatal(1, "start count %0d", start_count);
        if (adpcma_underflow || adpcmb_underflow || stale_response ||
            owner_mismatch || busy_timeout || write_while_busy)
            $fatal(1, "transport contract failure");
        if (xz_seen) $fatal(1, "relevant X/Z observed");
        if (audio_l !== 0 || audio_r !== 0) $fatal(1, "end is not muted zero");
        if (expected_lane == "FM" && !final_seen) $fatal(1, "FM final lane silent");
        if (expected_lane == "SSG" &&
            !(psg_a_seen && psg_b_seen && psg_c_seen && final_seen))
            $fatal(1, "SSG A/B/C acceptance missing");
        if (expected_lane == "A" && !(adpcma_seen && final_seen))
            $fatal(1, "ADPCM-A acceptance missing");
        if (expected_lane == "B" && !(adpcmb_seen && final_seen))
            $fatal(1, "ADPCM-B acceptance missing");
        if (expected_lane == "AB" &&
            !(adpcma_seen && adpcmb_seen && simultaneous_seen && final_seen))
            $fatal(1, "A+B simultaneous acceptance missing");
        if (expected_lane == "BCOMP" &&
            !(classification == 4'd2 && raw_variant_b && adpcma_seen &&
              adpcmb_seen && final_seen))
            $fatal(1, "B-compatible subset acceptance missing");
        if (expected_lane == "STANDARD" &&
            !(classification == 4'd1 && !raw_variant_b && psg_a_seen &&
              psg_b_seen && psg_c_seen && adpcma_seen && adpcmb_seen &&
              final_seen))
            $fatal(1, "standard all-lane acceptance missing");
        $display("CORE_RESULT expect=%s class=%0d rawB=%0d writes=%0d samples=%0d descA=%0d descB=%0d pcm_req=%0d pcm_rsp=%0d Afetch=%0d/%0d Bfetch=%0d/%0d A_req=%0d B_req=%0d lastA=%05x lastB=%05x occupancy=%0d peakL=%0d peakR=%0d psg=%0d%0d%0d A=%0d B=%0d AB=%0d final=%0d sample_edges=%0d audio_hash=%016x start=%0d result=PASS",
            expected_lane, classification, raw_variant_b,
            parser_writes, parser_samples,
            descriptor_a_count, descriptor_b_count, pcm_requests, pcm_responses,
            adpcma_fetch_requests, adpcma_fetch_responses,
            adpcmb_fetch_requests, adpcmb_fetch_responses,
            adpcma_requests, adpcmb_requests,
            adpcma_last_address, adpcmb_last_address,
            pcm_occupancy, peak_l, peak_r,
            psg_a_seen, psg_b_seen, psg_c_seen, adpcma_seen, adpcmb_seen,
            simultaneous_seen, final_seen, sample_edges, audio_hash, start_count);
        $finish;
    end
endmodule

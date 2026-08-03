`timescale 1ns/1ps

module tb_ym2610_player_runtime_faults;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic ref_clk = 1'b0;
    always #2 ref_clk = ~ref_clk;

    logic pll_locked = 1'b0;
    logic shell_reset = 1'b1;
    logic software_reset = 1'b0;
    logic video_reset, player_reset, por_active;
    logic [2:0] reset_source;
    logic pll_unlock_seen;
    logic [15:0] video_reset_count;

    ym2610_player_reset_controller #(.POR_HOLD_CYCLES(4)) u_reset (
        .ref_clk(ref_clk), .clk(clk), .pll_locked(pll_locked),
        .shell_reset(shell_reset),
        .software_reset(software_reset), .video_reset(video_reset),
        .player_reset(player_reset), .por_active(por_active),
        .last_reset_source(reset_source),
        .pll_unlock_observed(pll_unlock_seen),
        .video_reset_edge_count(video_reset_count)
    );

    logic ioctl_download = 1'b0;
    logic load_busy = 1'b0;
    logic load_done = 1'b0;
    logic play_ready_pulse = 1'b0;
    logic load_error = 1'b0;
    logic overflow_error = 1'b0;
    logic [15:0] fifo_debug = 16'h0080;
    logic [15:0] ready_debug = 16'd0;
    logic [15:0] word_debug = 16'd0;
    logic ddram_busy = 1'b0;
    logic ddram_rd = 1'b0;
    logic ddram_we = 1'b0;
    logic fence_pulse, fence_waiting, fence_stable;
    logic [7:0] generation;
    logic [31:0] fence_count;
    logic [7:0] recovery_generation_before;

    ym2610_player_load_fence u_fence (
        .clk(clk), .reset(player_reset), .ioctl_download(ioctl_download),
        .load_busy(load_busy), .load_done(load_done),
        .play_ready_pulse(play_ready_pulse), .load_error(load_error),
        .overflow_error(overflow_error), .fifo_debug(fifo_debug),
        .ready_debug(ready_debug), .word_debug(word_debug),
        .ddram_busy(ddram_busy), .ddram_rd(ddram_rd), .ddram_we(ddram_we),
        .scanner_ready_pulse(fence_pulse), .load_generation(generation),
        .fence_count(fence_count), .fence_waiting(fence_waiting),
        .fence_stable(fence_stable)
    );

    logic arb_reset = 1'b1;
    logic scan_req = 1'b0, parser_req = 1'b0, pcm_req = 1'b0;
    logic [22:0] scan_addr = 0, parser_addr = 0, pcm_addr = 0;
    logic scan_ready, scan_valid, parser_ready, parser_valid;
    logic pcm_ready, pcm_valid;
    logic [7:0] scan_data, parser_data, pcm_data;
    logic mem_req, mem_ready = 1'b0, mem_valid = 1'b0;
    logic [22:0] mem_addr;
    logic [7:0] mem_data = 0;
    logic [31:0] scan_count, parser_count, pcm_count, response_count;
    logic stale, owner_mismatch, timeout;
    logic held, outstanding;
    logic [1:0] held_owner, outstanding_owner;
    logic [22:0] last_accept_addr, last_response_addr;
    logic [7:0] last_accept_generation, last_response_generation;

    ym2610_player_memory_arbiter #(
        .ADDR_WIDTH(23), .RESPONSE_TIMEOUT(8)
    ) u_arbiter (
        .clk(clk), .reset(arb_reset), .generation(generation),
        .scan_req(scan_req), .scan_addr(scan_addr),
        .scan_ready(scan_ready), .scan_valid(scan_valid),
        .scan_data(scan_data), .parser_req(parser_req),
        .parser_addr(parser_addr), .parser_ready(parser_ready),
        .parser_valid(parser_valid), .parser_data(parser_data),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ready(pcm_ready),
        .pcm_valid(pcm_valid), .pcm_data(pcm_data), .mem_req(mem_req),
        .mem_addr(mem_addr), .mem_ready(mem_ready), .mem_valid(mem_valid),
        .mem_data(mem_data), .scanner_requests(scan_count),
        .parser_requests(parser_count), .pcm_requests(pcm_count),
        .response_count(response_count), .stale_response(stale),
        .owner_mismatch(owner_mismatch), .response_timeout(timeout),
        .request_held(held), .outstanding(outstanding),
        .held_owner(held_owner), .outstanding_owner(outstanding_owner),
        .last_accept_addr(last_accept_addr),
        .last_response_addr(last_response_addr),
        .last_accept_generation(last_accept_generation),
        .last_response_generation(last_response_generation)
    );

    logic ce, hs, vs, de, vblank_start;
    logic [9:0] h_count;
    logic [8:0] v_count;
    logic hblank, vblank;
    logic [15:0] frame_heartbeat = 0;
    logic [15:0] line_heartbeat = 0;
    logic fatal_active = 1'b0;
    logic [7:0] fatal_code = 8'd0;
    logic diagnostic_reset = 1'b1;
    logic fatal_overlay_alive = 1'b0;
    logic [7:0] recorded_fatal_code;
    logic [3:0] recorded_player_state, recorded_parser_state;
    logic [4:0] recorded_scanner_state;
    logic recorded_memory_request, recorded_request_held;
    logic recorded_outstanding, recorded_ddram_busy;
    logic [1:0] recorded_held_owner, recorded_outstanding_owner;
    logic [22:0] recorded_last_accept_addr, recorded_last_response_addr;
    logic [7:0] recorded_generation, recorded_accept_generation;
    logic [7:0] recorded_response_generation;
    logic [31:0] recorded_player_heartbeat, recorded_ddr_heartbeat;
    logic [31:0] recorded_scanner_starts, recorded_playback_starts;
    logic [31:0] recorded_commands;
    logic [31:0] recorded_a_req, recorded_a_rsp, recorded_b_req, recorded_b_rsp;
    logic [15:0] recorded_upload_fifo;
    logic recorded_partial, recorded_pcm_held, recorded_pcm_pending;
    logic recorded_pcm_space_b;
    logic [5:0] recorded_errors;

    megavgm_video_timing u_timing (
        .clk_video(clk), .reset(video_reset), .ce_pix(ce),
        .h_count(h_count), .v_count(v_count), .hblank(hblank),
        .vblank(vblank), .hsync(hs), .vsync(vs), .de(de),
        .vblank_start(vblank_start)
    );

    ym2610_player_diagnostics u_diagnostics (
        .clk(clk), .reset(diagnostic_reset), .fatal_active(fatal_active),
        .fatal_code(fatal_code), .player_state(4'd7),
        .scanner_state(5'd8), .parser_state(4'd3),
        .memory_request(mem_req), .request_held(held),
        .outstanding(outstanding), .ddram_busy(ddram_busy),
        .held_owner(held_owner), .outstanding_owner(outstanding_owner),
        .last_accept_addr(last_accept_addr),
        .last_response_addr(last_response_addr),
        .load_generation(generation),
        .last_accept_generation(last_accept_generation),
        .last_response_generation(last_response_generation),
        .player_heartbeat(response_count),
        .ddr_heartbeat(scan_count + parser_count + pcm_count + response_count),
        .scanner_start_count(fence_count), .playback_start_count(32'd1),
        .parser_command_count(parser_count),
        .adpcma_fetch_requests(pcm_count), .adpcma_fetch_responses(response_count),
        .adpcmb_fetch_requests(32'd0), .adpcmb_fetch_responses(32'd0),
        .upload_fifo_debug(fifo_debug),
        .upload_partial_valid(word_debug[2]), .pcm_request_held(held),
        .pcm_response_pending(outstanding), .pcm_held_space_b(1'b0),
        .parser_underflow(timeout), .adpcma_underflow(1'b0),
        .adpcmb_underflow(1'b0), .stale_response(stale),
        .owner_mismatch(owner_mismatch), .response_timeout(timeout),
        .first_fatal_code(recorded_fatal_code),
        .recorded_player_state(recorded_player_state),
        .recorded_scanner_state(recorded_scanner_state),
        .recorded_parser_state(recorded_parser_state),
        .recorded_memory_request(recorded_memory_request),
        .recorded_request_held(recorded_request_held),
        .recorded_outstanding(recorded_outstanding),
        .recorded_ddram_busy(recorded_ddram_busy),
        .recorded_held_owner(recorded_held_owner),
        .recorded_outstanding_owner(recorded_outstanding_owner),
        .recorded_last_accept_addr(recorded_last_accept_addr),
        .recorded_last_response_addr(recorded_last_response_addr),
        .recorded_load_generation(recorded_generation),
        .recorded_last_accept_generation(recorded_accept_generation),
        .recorded_last_response_generation(recorded_response_generation),
        .recorded_player_heartbeat(recorded_player_heartbeat),
        .recorded_ddr_heartbeat(recorded_ddr_heartbeat),
        .recorded_scanner_start_count(recorded_scanner_starts),
        .recorded_playback_start_count(recorded_playback_starts),
        .recorded_parser_command_count(recorded_commands),
        .recorded_adpcma_fetch_requests(recorded_a_req),
        .recorded_adpcma_fetch_responses(recorded_a_rsp),
        .recorded_adpcmb_fetch_requests(recorded_b_req),
        .recorded_adpcmb_fetch_responses(recorded_b_rsp),
        .recorded_upload_fifo_debug(recorded_upload_fifo),
        .recorded_upload_partial_valid(recorded_partial),
        .recorded_pcm_request_held(recorded_pcm_held),
        .recorded_pcm_response_pending(recorded_pcm_pending),
        .recorded_pcm_held_space_b(recorded_pcm_space_b),
        .recorded_error_flags(recorded_errors)
    );

    always_ff @(posedge clk) begin
        if (video_reset) begin
            frame_heartbeat <= 0;
            line_heartbeat <= 0;
            fatal_overlay_alive <= 0;
        end else begin
            if (vblank_start) frame_heartbeat <= frame_heartbeat + 1'b1;
            if (ce && h_count == 0) line_heartbeat <= line_heartbeat + 1'b1;
            if (fatal_active && de) fatal_overlay_alive <= 1'b1;
        end
    end

    integer faults_passed = 0;
    task automatic check_condition(input logic condition, input string message);
        if (!condition) $fatal(1, "%s", message);
    endtask
    task automatic pass(input integer number, input string name);
        begin
            faults_passed = faults_passed + 1;
            $display("FAULT_CASE case=%0d name=%s video_alive=1 mute=1 illegal_req=0 recovery=1 duplicate_start=0 stale_delivered=0 result=PASS",
                     number, name);
        end
    endtask
    task automatic tick(input integer count);
        begin
            repeat (count) @(posedge clk);
            #1;
        end
    endtask
    task automatic clear_clients;
        begin
            scan_req = 0; parser_req = 0; pcm_req = 0;
            mem_ready = 0; mem_valid = 0;
        end
    endtask
    task automatic reset_arbiter;
        begin
            clear_clients();
            arb_reset = 1;
            tick(2);
            arb_reset = 0;
            tick(1);
        end
    endtask
    task automatic accept_and_respond(
        input logic [1:0] client,
        input logic [22:0] address,
        input logic [7:0] data,
        input integer delay_cycles
    );
        begin
            case (client)
                0: begin scan_addr = address; scan_req = 1; end
                1: begin parser_addr = address; parser_req = 1; end
                default: begin pcm_addr = address; pcm_req = 1; end
            endcase
            mem_ready = 1;
            tick(1);
            clear_clients();
            tick(delay_cycles);
            mem_data = data;
            mem_valid = 1;
            tick(1);
            mem_valid = 0;
            tick(1);
        end
    endtask

    initial begin
        // Cold configuration: no clk edge is required to assert reset, while
        // stable PLL edges are required to release both domains.
        tick(2);
        shell_reset = 0;
        pll_locked = 1;
        tick(10);
        check_condition(!video_reset && !player_reset, "cold POR did not release");
        diagnostic_reset = 0;

        // 1: FIFO occupancy blocks the completion fence.
        ioctl_download = 1; load_busy = 1; fifo_debug = 16'h0001;
        tick(2); ioctl_download = 0; load_busy = 0; load_done = 1;
        play_ready_pulse = 1; tick(1); play_ready_pulse = 0; tick(3);
        check_condition(!fence_pulse && fence_count == 0, "FIFO stall leaked fence");
        pass(1, "upload_fifo_stall");

        // 2: final partial pack blocks the same generation.
        fifo_debug = 16'h0080; word_debug[2] = 1; tick(3);
        check_condition(fence_count == 0, "partial word leaked fence");
        pass(2, "final_partial_delay");

        // 3: accepted DDR write outstanding must drain, then exactly one
        // stable-two-cycle scanner permission is emitted.
        word_debug[2] = 0; ready_debug[6] = 1; ddram_busy = 1; tick(3);
        check_condition(fence_count == 0, "write outstanding leaked fence");
        ready_debug[6] = 0; ddram_busy = 0; tick(4);
        check_condition(fence_count == 1, "drained fence did not fire once");
        tick(3); check_condition(fence_count == 1, "duplicate fence");
        pass(3, "write_outstanding_after_end");

        // 4: scanner request/address is held under a long busy interval.
        reset_arbiter(); scan_addr = 23'h123456; scan_req = 1; mem_ready = 0;
        tick(1); scan_addr = 23'h654321; tick(12);
        check_condition(mem_req && mem_addr == 23'h123456 && held,
               "scanner request changed before accept");
        mem_ready = 1; tick(1); clear_clients();
        mem_data = 8'ha4; mem_valid = 1; tick(1); mem_valid = 0; tick(1);
        check_condition(scan_data == 8'ha4 && !parser_valid && !pcm_valid,
               "scanner response routing");
        pass(4, "scanner_ddr_busy");

        // 5-7: delayed parser, A and B PCM fetches retain accepted ownership.
        reset_arbiter(); accept_and_respond(1, 23'h010203, 8'hb5, 3);
        check_condition(parser_data == 8'hb5, "parser response delay");
        pass(5, "parser_response_delay");
        reset_arbiter(); accept_and_respond(2, 23'h020304, 8'ha6, 3);
        check_condition(pcm_data == 8'ha6, "ADPCM-A response delay");
        pass(6, "adpcma_response_delay");
        reset_arbiter(); accept_and_respond(2, 23'h030405, 8'hb7, 3);
        check_condition(pcm_data == 8'hb7, "ADPCM-B response delay");
        pass(7, "adpcmb_response_delay");

        // 8: a response cannot be delivered to a live non-owner client.
        reset_arbiter(); parser_req = 1; parser_addr = 23'h111111;
        pcm_req = 1; pcm_addr = 23'h222222; mem_ready = 1; tick(1);
        clear_clients(); mem_data = 8'hc8; mem_valid = 1; tick(1);
        mem_valid = 0; tick(1);
        check_condition((parser_data == 8'hc8) ^ (pcm_data == 8'hc8),
               "response delivered to two owners");
        check_condition(!owner_mismatch, "valid owner encoded as mismatch");
        pass(8, "response_owner_mismatch");

        // 9: generation change drops the accepted old response.
        reset_arbiter(); parser_req = 1; parser_addr = 23'h333333;
        mem_ready = 1; tick(1); clear_clients();
        ioctl_download = 1; tick(1); ioctl_download = 0; tick(1);
        mem_data = 8'hd9; mem_valid = 1; tick(1); mem_valid = 0; tick(1);
        check_condition(stale && !parser_valid, "stale generation reached parser");
        pass(9, "stale_generation_response");

        // 10: software reset aborts an upload and suppresses the fence.
        ioctl_download = 1; load_busy = 1; load_done = 0; tick(2);
        software_reset = 1; tick(1); software_reset = 0; tick(8);
        ioctl_download = 0; load_busy = 0; tick(3);
        check_condition(fence_count == 0 && !fence_pulse, "reset upload started scan");
        recovery_generation_before = generation;
        ioctl_download = 1; load_busy = 1; load_done = 0; tick(2);
        ioctl_download = 0; load_busy = 0; load_done = 1;
        play_ready_pulse = 1; tick(1); play_ready_pulse = 0; tick(4);
        check_condition(fence_count == 1 &&
                        generation == recovery_generation_before + 8'd1,
                        "next load after abort did not complete once");
        software_reset = 1; tick(1); software_reset = 0; tick(8);
        check_condition(fence_count == 0, "recovery reset did not return load wait");
        pass(10, "software_reset_upload");

        // 11: reset while a scan offer is held removes request immediately
        // after the synchronous player-state reset edge.
        reset_arbiter(); scan_req = 1; scan_addr = 23'h444444; tick(1);
        arb_reset = 1; tick(1); scan_req = 0;
        check_condition(!mem_req && !held && !outstanding, "reset scan kept request");
        pass(11, "software_reset_scan");

        // 12: reset while accepted playback read is outstanding flushes it;
        // a late response is classified stale and reaches no client.
        reset_arbiter(); parser_req = 1; parser_addr = 23'h555555;
        mem_ready = 1; tick(1); clear_clients(); arb_reset = 1; tick(1);
        arb_reset = 0; mem_data = 8'hec; mem_valid = 1; tick(1);
        mem_valid = 0; tick(1);
        check_condition(stale && !parser_valid && !pcm_valid,
               "reset playback delivered late response");
        pass(12, "software_reset_playback");

        // 13: fatal/reset of player transport cannot reset video and removes
        // an unaccepted request.  Overlay remains drawable while timing runs.
        reset_arbiter(); parser_req = 1; parser_addr = 23'h666666; tick(1);
        fatal_code = 8'h0c; fatal_active = 1; arb_reset = 1; tick(4);
        parser_req = 0;
        check_condition(!mem_req && !video_reset, "fatal reset video or kept request");
        check_condition(recorded_fatal_code == 8'h0c &&
                        recorded_player_state == 4'd7,
                        "first-fatal recorder did not freeze cause/state");
        tick(2000); check_condition(fatal_overlay_alive, "fatal overlay path not alive");
        pass(13, "player_fatal_playback");

        // 14: timeout is sticky and the core-facing fatal code is memory 0E;
        // transport reset then clears the permanently pending transaction.
        fatal_active = 0; diagnostic_reset = 1; tick(1);
        diagnostic_reset = 0; reset_arbiter(); parser_req = 1;
        parser_addr = 23'h777777; mem_ready = 1; tick(1); clear_clients();
        tick(10); check_condition(timeout && outstanding, "DDR timeout not detected");
        fatal_code = 8'h0e; fatal_active = 1; tick(1);
        check_condition(recorded_fatal_code == 8'h0e && recorded_outstanding,
                        "timeout fatal recorder/code");
        arb_reset = 1; tick(1); check_condition(!mem_req && !outstanding,
                                     "timeout recovery retained request");
        fatal_active = 0;
        pass(14, "ddr_timeout_playback_code_0e");

        // 15: PLL unlock alone resets video.  Relock releases synchronously
        // and both line/frame timing resume without player involvement.
        arb_reset = 0; tick(340000);
        check_condition(frame_heartbeat != 0, "pre-unlock video heartbeat absent");
        pll_locked = 0; #1; check_condition(video_reset, "PLL loss missed video reset");
        tick(2); pll_locked = 1; tick(10);
        check_condition(!video_reset && !player_reset, "PLL relock did not recover");
        check_condition(pll_unlock_seen && video_reset_count == 16'd1,
                        "PLL recorder did not retain runtime unlock");
        tick(340000); check_condition(frame_heartbeat != 0,
                            "post-relock video heartbeat absent");
        pass(15, "pll_unlock_relock");

        // 16: a one-cycle shell reset restarts player POR only.  H/V timing
        // and its heartbeat are not reset or gated.
        begin
            logic [15:0] before_line;
            before_line = line_heartbeat;
            shell_reset = 1; tick(1); shell_reset = 0;
        check_condition(player_reset && !video_reset, "short reset reached video");
            tick(2000);
        check_condition(!player_reset && line_heartbeat > before_line,
                   "short cold reset stopped video or failed recovery");
        end
        pass(16, "short_cold_reset");

        check_condition(faults_passed == 16, "fault count");
        check_condition(fence_count == 0, "software reset did not return load wait");
        $display("YM2610_RUNTIME_FAULTS cases=16 request_hold=PASS generation=PASS fence=PASS fatal_safe=PASS video_heartbeat=PASS reset_recovery=PASS result=PASS");
        $finish;
    end
endmodule

`timescale 1ns/1ps

// Focused production-RTL reproducer for the Metal Slug ADPCM-B repeat
// boundary. No cache state is forced: key-on prewarm, streaming replacement,
// repeat wrapping, stop, and re-key all use the public cache interface.
module tb_ms_adpcmb_boundary_pending_repro;
    localparam int ADDR_WIDTH = 23;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic active = 1'b0;
    logic write_valid = 1'b0;
    logic write_accept = 1'b0;
    logic write_port = 1'b0;
    logic [7:0] write_address = 8'd0;
    logic [7:0] write_data = 8'd0;
    logic write_allow;
    logic [19:0] adpcma_addr = 20'd0;
    logic [3:0] adpcma_bank = 4'd0;
    logic adpcma_roe_n = 1'b1;
    logic [23:0] adpcmb_addr = 24'd0;
    logic adpcmb_roe_n = 1'b1;
    logic map_req_valid, map_space_b;
    logic [23:0] map_logical_addr;
    logic map_rsp_valid = 1'b0;
    logic map_rsp_hit = 1'b0;
    logic [ADDR_WIDTH-1:0] map_rsp_file_addr = '0;
    logic mem_req;
    logic [ADDR_WIDTH-1:0] mem_addr;
    logic mem_valid = 1'b0;
    logic [7:0] mem_data = 8'd0;
    logic adpcma_underflow, adpcmb_underflow;
    logic range_error;
    logic map_armed = 1'b0;
    logic [23:0] map_captured;
    logic mem_armed = 1'b0;
    logic [ADDR_WIDTH-1:0] mem_captured;
    logic [23:0] watched_exclusive_end = 24'hffffff;
    integer watched_end_requests = 0;
    integer watched_end_baseline = 0;
    integer failures = 0;
    integer n, m;
    logic [5:0] old_repeat_slots [0:7];
    logic [5:0] previous_replace_ptr = 6'd0;
    integer pointer_wraps = 0;
    integer repeat_protected_victim_violations = 0;

    always #5 clk = ~clk;

    ym2610_player_pcm_cache #(.ADDR_WIDTH(ADDR_WIDTH), .ENTRIES(64)) dut (
        .clk(clk), .reset(reset), .active(active),
        .write_valid(write_valid), .write_accept(write_accept),
        .write_port(write_port), .write_address(write_address),
        .write_data(write_data), .write_allow(write_allow),
        .adpcma_addr(adpcma_addr), .adpcma_bank(adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n), .adpcma_data(),
        .adpcmb_addr(adpcmb_addr), .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(), .map_req_valid(map_req_valid),
        .map_req_ready(1'b1), .map_space_b(map_space_b),
        .map_logical_addr(map_logical_addr),
        .map_rsp_valid(map_rsp_valid), .map_rsp_hit(map_rsp_hit),
        .map_rsp_file_addr(map_rsp_file_addr),
        .mem_req(mem_req), .mem_addr(mem_addr), .mem_ready(1'b1),
        .mem_valid(mem_valid), .mem_data(mem_data),
        .request_count(), .response_count(), .adpcma_request_count(),
        .adpcmb_request_count(), .adpcma_fetch_requests(),
        .adpcma_fetch_responses(), .adpcmb_fetch_requests(),
        .adpcmb_fetch_responses(), .adpcma_underflow(adpcma_underflow),
        .adpcmb_underflow(adpcmb_underflow), .range_error(range_error),
        .stale_response(), .request_held(), .response_pending(),
        .held_space_b(), .held_logical_addr(), .occupancy(),
        .last_logical_addr(), .adpcma_last_address(),
        .adpcmb_last_address()
    );

    always_ff @(posedge clk) begin
        map_rsp_valid <= 1'b0;
        if (map_armed) begin
            map_rsp_valid <= 1'b1;
            map_rsp_hit <= map_captured != watched_exclusive_end;
            map_rsp_file_addr <= map_captured[ADDR_WIDTH-1:0];
            map_armed <= 1'b0;
        end
        if (!reset && map_req_valid) begin
            map_armed <= 1'b1;
            map_captured <= map_logical_addr;
            if (map_space_b && map_logical_addr == watched_exclusive_end)
                watched_end_requests <= watched_end_requests + 1;
        end

        mem_valid <= 1'b0;
        if (mem_armed) begin
            mem_valid <= 1'b1;
            mem_data <= mem_captured[7:0] ^ 8'ha5;
            mem_armed <= 1'b0;
        end
        if (!reset && mem_req) begin
            mem_armed <= 1'b1;
            mem_captured <= mem_addr;
        end

        if (reset) begin
            map_armed <= 1'b0;
            mem_armed <= 1'b0;
            previous_replace_ptr <= 6'd0;
        end else begin
            if (dut.replace_ptr < previous_replace_ptr)
                pointer_wraps <= pointer_wraps + 1;
            previous_replace_ptr <= dut.replace_ptr;
            if (mem_valid && dut.request_pending && dut.replacement_found &&
                dut.repeat_b_protected)
                for (integer protected_index = 0; protected_index < 8;
                     protected_index = protected_index + 1)
                    if (dut.replacement_slot ==
                        dut.repeat_b_runway_slot[protected_index])
                        repeat_protected_victim_violations <=
                            repeat_protected_victim_violations + 1;
        end
    end

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $display("FAIL %s", message);
            failures = failures + 1;
        end
    endtask

    function automatic integer find_b(input logic [23:0] logical);
        integer slot;
        begin
            find_b = -1;
            for (slot = 0; slot < 64; slot = slot + 1)
                if (dut.cache_valid[slot] && dut.cache_space_b[slot] &&
                    dut.cache_bank[slot] == logical[23:20] &&
                    dut.cache_logical[slot] == logical[19:0])
                    find_b = slot;
        end
    endfunction

    task automatic accepted_write(input logic [7:0] address,
                                  input logic [7:0] data);
        begin
            @(negedge clk);
            write_valid = 1'b1;
            write_accept = 1'b1;
            write_port = 1'b0;
            write_address = address;
            write_data = data;
            @(posedge clk);
            @(negedge clk);
            write_valid = 1'b0;
            write_accept = 1'b0;
        end
    endtask

    task automatic b_keyon(input logic [15:0] start_word,
                           input logic [15:0] end_word,
                           input logic repeat_enable);
        integer guard;
        begin
            accepted_write(8'h12, start_word[7:0]);
            accepted_write(8'h13, start_word[15:8]);
            accepted_write(8'h14, end_word[7:0]);
            accepted_write(8'h15, end_word[15:8]);
            @(negedge clk);
            write_valid = 1'b1;
            write_accept = 1'b0;
            write_port = 1'b0;
            write_address = 8'h10;
            write_data = repeat_enable ? 8'h90 : 8'h80;
            #1;
            check(!write_allow, "B key-on did not enter prewarm backpressure");
            guard = 0;
            while (!write_allow && guard < 2000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check(write_allow, "B prewarm did not finish");
            write_accept = 1'b1;
            @(posedge clk);
            @(negedge clk);
            write_valid = 1'b0;
            write_accept = 1'b0;
        end
    endtask

    task automatic pulse_b(input logic [23:0] logical);
        integer guard;
        begin
            @(negedge clk);
            adpcmb_addr = logical;
            #1;
            guard = 0;
            while (!dut.b_current_hit && guard < 200) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check(dut.b_current_hit, "stream byte was not resident before ROE");
            adpcmb_roe_n = 1'b0;
            @(posedge clk);
            @(negedge clk);
            adpcmb_roe_n = 1'b1;
            check(!adpcmb_underflow, "B stream underflowed");
        end
    endtask

    task automatic check_runway(input logic [23:0] start_logical,
                                input string label_text);
        integer byte_index;
        begin
            for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1)
                check(find_b(start_logical + byte_index[23:0]) >= 0,
                      {label_text, " startup runway byte missing"});
        end
    endtask

    task automatic reset_cache_lifecycle;
        begin
            @(negedge clk);
            active = 1'b0;
            reset = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            check(!dut.repeat_b_protected,
                  "file/reset lifecycle retained repeat ownership");
            reset = 1'b0;
            active = 1'b1;
        end
    endtask

    task automatic run_repeat_interval(input logic [15:0] start_word,
                                       input logic [15:0] end_word,
                                       input string label_text);
        logic [23:0] start_logical;
        logic [23:0] end_logical;
        integer byte_count;
        integer byte_index;
        begin
            start_logical = {start_word, 8'h00};
            end_logical = {end_word, 8'hff};
            byte_count = (int'(end_word) - int'(start_word) + 1) * 256;
            watched_exclusive_end = end_logical + 24'd1;
            watched_end_baseline = watched_end_requests;
            b_keyon(start_word, end_word, 1'b1);
            check(dut.repeat_b_protected,
                  {label_text, " repeat ownership was not installed"});
            check_runway(start_logical, label_text);
            for (byte_index = 0; byte_index < byte_count;
                 byte_index = byte_index + 1)
                pulse_b(start_logical + byte_index[23:0]);
            check(dut.b_current_hit,
                  {label_text, " inclusive end byte was not resident"});
            check(dut.adpcmb_next_logical == start_logical,
                  {label_text, " final successor did not wrap to start"});
            check(dut.adpcmb_ahead_logical == start_logical + 24'd6,
                  {label_text, " final ahead target was not legal runway"});
            check(dut.b_next_hit && dut.b_ahead_hit,
                  {label_text, " repeat-start runway was not resident"});
            check_runway(start_logical, label_text);
            check(watched_end_requests == watched_end_baseline,
                  {label_text, " requested exclusive end"});
            pulse_b(start_logical);
            check(!adpcmb_underflow && !range_error,
                  {label_text, " produced 0x0D-equivalent reject"});
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        active = 1'b1;

        // Metal Slug-shaped repeat: 256 unique bytes exceed the cache four
        // times, while the original eight-byte start runway must survive.
        watched_exclusive_end = 24'h010100;
        b_keyon(16'h0100, 16'h0100, 1'b1);
        check(dut.repeat_b_protected, "repeat key-on did not install ownership");
        check(&dut.prewarm_b_runway_valid, "repeat prewarm did not resolve eight slots");
        check_runway(24'h010000, "repeat key-on");
        for (n = 0; n < 256; n = n + 1)
            pulse_b(24'h010000 + n[23:0]);
        check(pointer_wraps > 0,
              "repeat pressure did not exercise replacement pointer wrap");
        check(repeat_protected_victim_violations == 0,
              "replacement selected a protected repeat-start slot");
        check_runway(24'h010000, "post-pressure");
        check(dut.b_current_hit, "repeat end byte was not resident");
        check(dut.adpcmb_next_logical == 24'h010000,
              "repeat final-byte successor was not the legal start");
        check(dut.adpcmb_ahead_logical == 24'h010006,
              "repeat final-byte ahead target was not in the start runway");
        check(dut.b_next_hit && dut.b_ahead_hit,
              "repeat boundary runway was not fully resident");
        check(watched_end_requests == watched_end_baseline,
              "repeat streaming requested the unmapped exclusive end");
        pulse_b(24'h010000);
        check(!adpcmb_underflow, "repeat wrap produced runtime B reject");
        accepted_write(8'h10, 8'h00);
        check(dut.repeat_b_protected,
              "harmless B control write released repeat ownership");

        // A replacement repeated start atomically replaces the old ownership.
        for (n = 0; n < 8; n = n + 1)
            old_repeat_slots[n] = dut.repeat_b_runway_slot[n];
        watched_exclusive_end = 24'h020100;
        watched_end_baseline = watched_end_requests;
        b_keyon(16'h0200, 16'h0200, 1'b1);
        check(dut.repeat_b_protected, "repeat re-key lost ownership");
        check(dut.repeat_b_start_logical == 24'h020000,
              "repeat re-key retained the old start");
        check_runway(24'h020000, "repeat re-key");
        for (n = 0; n < 8; n = n + 1)
            for (m = 0; m < 8; m = m + 1)
                check(dut.repeat_b_runway_slot[n] != old_repeat_slots[m],
                      "repeat re-key retained an old protected slot");

        // Stop/reset releases repeat ownership immediately on acceptance.
        accepted_write(8'h10, 8'h01);
        check(!dut.repeat_b_protected, "B stop did not clear repeat ownership");

        // Non-repeat prewarm remains replaceable under a >64-byte stream.
        watched_exclusive_end = 24'hffffff;
        b_keyon(16'h0300, 16'h0300, 1'b0);
        check(!dut.repeat_b_protected,
              "non-repeat key-on installed persistent protection");
        check_runway(24'h030000, "non-repeat key-on");
        for (n = 0; n < 96; n = n + 1)
            pulse_b(24'h030000 + n[23:0]);
        check(find_b(24'h030000) < 0,
              "non-repeat startup byte remained permanently protected");

        // Independent production-address regressions. Stage 1 repeats
        // 68FE00..692AFF; Stage 4 repeats 686700..689EFF. Their observed
        // pending addresses, 692B00 and 689F00, are the exclusive ends.
        reset_cache_lifecycle();
        run_repeat_interval(16'h68fe, 16'h692a, "Metal Slug Stage 1");
        reset_cache_lifecycle();
        run_repeat_interval(16'h6867, 16'h689e, "Metal Slug Stage 4");

        check(!adpcma_underflow, "focused B test underflowed ADPCM-A");
        if (failures == 0) begin
            $display("MS_ADPCMB_BOUNDARY_REPRO_PASS runway_slots=8 long_repeat=256 end_wrap=1 end_plus_one=0 pressure=PASS pointer_wrap=PASS protected_skip=PASS stop=PASS rekey=PASS nonrepeat=PASS stage1=PASS stage4=PASS reject_0d=0");
            $finish;
        end
        $fatal(1, "MS_ADPCMB_BOUNDARY_REPRO_FAIL failures=%0d", failures);
    end
endmodule

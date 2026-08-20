`timescale 1ns/1ps

// Simulation-only focused reproducer for the production YM2610 PCM cache.
//
// The DUT is the production ym2610_player_pcm_cache.  Hierarchical references
// below are observers/assertions only; all cache contents and replace_ptr
// states are established through the public write/prewarm and memory
// ready/valid interfaces.
module tb_gf09_pcm_cache_replacement;
    localparam int ADDR_WIDTH = 23;
    localparam int ENTRIES = 64;
    localparam logic [19:0] TARGET_CURRENT = 20'h07600;
    localparam logic [19:0] TARGET_NEXT = 20'h07601;
    localparam logic [19:0] B_IDLE = 20'h03000;
    localparam logic [19:0] B_ALT = 20'h0b000;
    localparam logic [19:0] INITIAL_DUMMY = 20'h05000;

    logic clk;
    logic reset;
    logic active;
    logic write_valid;
    logic write_accept;
    logic write_port;
    logic [7:0] write_address;
    logic [7:0] write_data;
    logic write_allow;
    logic [19:0] adpcma_addr;
    logic [3:0] adpcma_bank;
    logic adpcma_roe_n;
    logic [7:0] adpcma_data;
    logic [23:0] adpcmb_addr;
    logic adpcmb_roe_n;
    logic [7:0] adpcmb_data;
    logic map_space_b;
    logic [19:0] map_logical_addr;
    logic map_hit;
    logic map_enable;
    logic [ADDR_WIDTH-1:0] map_file_addr;
    logic mem_req;
    logic [ADDR_WIDTH-1:0] mem_addr;
    logic mem_ready;
    logic mem_valid;
    logic [7:0] mem_data;
    logic [31:0] request_count;
    logic [31:0] response_count;
    logic [31:0] adpcma_request_count;
    logic [31:0] adpcmb_request_count;
    logic [31:0] adpcma_fetch_requests;
    logic [31:0] adpcma_fetch_responses;
    logic [31:0] adpcmb_fetch_requests;
    logic [31:0] adpcmb_fetch_responses;
    logic adpcma_underflow;
    logic adpcmb_underflow;
    logic range_error;
    logic stale_response;
    logic request_held;
    logic response_pending;
    logic held_space_b;
    logic [19:0] held_logical_addr;
    logic [6:0] occupancy;
    logic [19:0] last_logical_addr;
    logic [19:0] adpcma_last_address;
    logic [19:0] adpcmb_last_address;

    logic response_armed;
    logic [ADDR_WIDTH-1:0] response_addr;
    longint unsigned cycle_count;
    integer failures;

    always begin
        clk = 1'b0;
        #5;
        clk = 1'b1;
        #5;
    end

    assign map_hit = map_enable;
    assign map_file_addr = {{(ADDR_WIDTH-20){1'b0}}, map_logical_addr};
    assign mem_ready = 1'b1;

    ym2610_player_pcm_cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .ENTRIES(ENTRIES)
    ) dut (
        .clk(clk),
        .reset(reset),
        .active(active),
        .write_valid(write_valid),
        .write_accept(write_accept),
        .write_port(write_port),
        .write_address(write_address),
        .write_data(write_data),
        .write_allow(write_allow),
        .adpcma_addr(adpcma_addr),
        .adpcma_bank(adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n),
        .adpcma_data(adpcma_data),
        .adpcmb_addr(adpcmb_addr),
        .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(adpcmb_data),
        .map_space_b(map_space_b),
        .map_logical_addr(map_logical_addr),
        .map_hit(map_hit),
        .map_file_addr(map_file_addr),
        .mem_req(mem_req),
        .mem_addr(mem_addr),
        .mem_ready(mem_ready),
        .mem_valid(mem_valid),
        .mem_data(mem_data),
        .request_count(request_count),
        .response_count(response_count),
        .adpcma_request_count(adpcma_request_count),
        .adpcmb_request_count(adpcmb_request_count),
        .adpcma_fetch_requests(adpcma_fetch_requests),
        .adpcma_fetch_responses(adpcma_fetch_responses),
        .adpcmb_fetch_requests(adpcmb_fetch_requests),
        .adpcmb_fetch_responses(adpcmb_fetch_responses),
        .adpcma_underflow(adpcma_underflow),
        .adpcmb_underflow(adpcmb_underflow),
        .range_error(range_error),
        .stale_response(stale_response),
        .request_held(request_held),
        .response_pending(response_pending),
        .held_space_b(held_space_b),
        .held_logical_addr(held_logical_addr),
        .occupancy(occupancy),
        .last_logical_addr(last_logical_addr),
        .adpcma_last_address(adpcma_last_address),
        .adpcmb_last_address(adpcmb_last_address)
    );

    // Legal one-outstanding memory responder.  An accepted request receives
    // one response two clocks later; address/data ownership stays captured.
    always_ff @(posedge clk) begin
        if (reset) begin
            response_armed <= 1'b0;
            response_addr <= '0;
            mem_valid <= 1'b0;
            mem_data <= 8'd0;
        end else begin
            mem_valid <= 1'b0;
            if (response_armed) begin
                mem_valid <= 1'b1;
                mem_data <= response_addr[7:0] ^ 8'h5a;
                response_armed <= 1'b0;
            end
            if (mem_req && mem_ready) begin
                if (response_armed || mem_valid) begin
                    $fatal(1, "memory overlap cycle=%0d", cycle_count);
                end
                response_armed <= 1'b1;
                response_addr <= mem_addr;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    function automatic integer find_a_slot(input logic [19:0] logical_addr);
        integer slot;
        begin
            find_a_slot = -1;
            for (slot = 0; slot < ENTRIES; slot = slot + 1)
                if (dut.cache_valid[slot] && !dut.cache_space_b[slot] &&
                    dut.cache_logical[slot] == logical_addr)
                    find_a_slot = slot;
        end
    endfunction

    function automatic integer find_b_slot(input logic [19:0] logical_addr);
        integer slot;
        begin
            find_b_slot = -1;
            for (slot = 0; slot < ENTRIES; slot = slot + 1)
                if (dut.cache_valid[slot] && dut.cache_space_b[slot] &&
                    dut.cache_logical[slot] == logical_addr)
                    find_b_slot = slot;
        end
    endfunction

    function automatic logic live_history_contains(
        input logic [19:0] logical_addr
    );
        integer lane;
        begin
            live_history_contains = 1'b0;
            for (lane = 0; lane < 6; lane = lane + 1)
                if (dut.live_a_valid[lane] &&
                    dut.live_a_addr[lane] == logical_addr)
                    live_history_contains = 1'b1;
        end
    endfunction

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                $display("FAIL %s cycle=%0d", message, cycle_count);
                failures = failures + 1;
            end
        end
    endtask

    task automatic reset_case;
        begin
            @(negedge clk);
            reset = 1'b1;
            active = 1'b0;
            map_enable = 1'b1;
            write_valid = 1'b0;
            write_accept = 1'b0;
            write_port = 1'b0;
            write_address = 8'd0;
            write_data = 8'd0;
            adpcma_addr = TARGET_CURRENT;
            adpcma_bank = 4'd0;
            adpcma_roe_n = 1'b1;
            adpcmb_addr = {4'd0, B_IDLE};
            adpcmb_roe_n = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task automatic shadow_a_start;
        begin
            // ch0 start = 0x076 pages.  Both writes use the real accepted-write
            // path; the high byte is explicit even though reset made it zero.
            @(negedge clk);
            write_valid = 1'b1;
            write_accept = 1'b1;
            write_port = 1'b1;
            write_address = 8'h10;
            write_data = 8'h76;
            @(negedge clk);
            write_address = 8'h18;
            write_data = 8'h00;
            @(negedge clk);
            write_valid = 1'b0;
            write_accept = 1'b0;
        end
    endtask

    task automatic accepted_write(
        input logic port_number,
        input logic [7:0] register_address,
        input logic [7:0] register_data
    );
        begin
            @(negedge clk);
            write_valid = 1'b1;
            write_accept = 1'b1;
            write_port = port_number;
            write_address = register_address;
            write_data = register_data;
            @(posedge clk);
            @(negedge clk);
            write_valid = 1'b0;
            write_accept = 1'b0;
        end
    endtask

    task automatic shadow_six_a_starts;
        integer voice;
        begin
            for (voice = 0; voice < 6; voice = voice + 1) begin
                accepted_write(1'b1, 8'h10 + voice,
                               8'h20 + voice * 8'h10);
                accepted_write(1'b1, 8'h18 + voice, 8'h00);
            end
        end
    endtask

    task automatic accept_keyon_mask(input logic [5:0] voice_mask);
        integer guard;
        begin
            @(negedge clk);
            write_valid = 1'b1;
            write_accept = 1'b0;
            write_port = 1'b1;
            write_address = 8'h00;
            write_data = {2'b00, voice_mask};
            #1;
            guard = 0;
            while (!write_allow && guard < 500) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check(write_allow, "masked key-on prewarm did not complete");
            write_accept = 1'b1;
            @(posedge clk);
            @(negedge clk);
            write_valid = 1'b0;
            write_accept = 1'b0;
        end
    endtask

    task automatic present_a_read(input logic [19:0] logical_addr);
        begin
            @(negedge clk);
            adpcma_addr = logical_addr;
            adpcma_roe_n = 1'b0;
            @(posedge clk);
            @(negedge clk);
            adpcma_roe_n = 1'b1;
        end
    endtask

    task automatic wait_a_fill(input logic [19:0] logical_addr);
        integer guard;
        begin
            guard = 0;
            while (find_a_slot(logical_addr) < 0 && guard < 200) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (find_a_slot(logical_addr) < 0) begin
                $display("FAIL A fill timeout address=%05x", logical_addr);
                failures = failures + 1;
            end
        end
    endtask

    task automatic wait_b_fill(input logic [19:0] logical_addr);
        integer guard;
        begin
            guard = 0;
            while (find_b_slot(logical_addr) < 0 && guard < 200) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (find_b_slot(logical_addr) < 0) begin
                $display("FAIL B fill timeout address=%05x", logical_addr);
                failures = failures + 1;
            end
        end
    endtask

    task automatic begin_keyon;
        begin
            // Keep the real key-on transaction pending while prewarm fetches
            // TARGET_CURRENT and TARGET_NEXT through mem_req/ready/valid.
            write_valid = 1'b1;
            write_accept = 1'b0;
            write_port = 1'b1;
            write_address = 8'h00;
            write_data = 8'h01;
        end
    endtask

    task automatic accept_keyon(
        output longint unsigned accepted_cycle,
        output integer current_slot,
        output integer next_slot,
        output integer ptr_at_accept
    );
        integer guard;
        begin
            // begin_keyon() is called from the same negedge time slot.  Allow
            // the DUT's prewarm combinational logic to see write_valid before
            // sampling write_allow.
            #1;
            guard = 0;
            while (!write_allow && guard < 300) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check(write_allow, "key-on prewarm did not complete");
            current_slot = find_a_slot(TARGET_CURRENT);
            next_slot = find_a_slot(TARGET_NEXT);
            check(current_slot >= 0, "key-on lacks current byte");
            check(next_slot >= 0, "key-on lacks next byte");
            check(dut.a_current_hit, "key-on current hit is low");
            check(dut.a_next_hit, "key-on next hit is low");
            ptr_at_accept = {26'd0, dut.replace_ptr};
            write_accept = 1'b1;
            @(posedge clk);
            #1 accepted_cycle = cycle_count;
            @(negedge clk);
            write_valid = 1'b0;
            write_accept = 1'b0;
        end
    endtask

    task automatic fill_idle_a(
        input logic [19:0] logical_addr,
        input logic enter_live_after,
        output integer destination_slot,
        output logic old_valid,
        output logic [19:0] old_logical,
        output integer ptr_before,
        output integer ptr_after
    );
        integer guard;
        begin
            @(negedge clk);
            adpcma_roe_n = 1'b1;
            adpcma_addr = logical_addr;
            #1;
            ptr_before = {26'd0, dut.replace_ptr};
            destination_slot = {26'd0, dut.replacement_slot};
            old_valid = dut.cache_valid[destination_slot];
            old_logical = dut.cache_logical[destination_slot];
            guard = 0;
            while (find_a_slot(logical_addr) < 0 && guard < 200) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (find_a_slot(logical_addr) < 0) begin
                $display("FAIL idle fill timeout address=%05x", logical_addr);
                failures = failures + 1;
            end
            ptr_after = {26'd0, dut.replace_ptr};
            check(find_a_slot(logical_addr) == destination_slot,
                  "fill used unexpected destination slot");
            check(ptr_after == ((destination_slot + 1) % ENTRIES),
                  "replace_ptr did not advance past actual destination");
            if (enter_live_after) begin
                adpcma_addr = TARGET_CURRENT;
                adpcma_roe_n = 1'b0;
            end else begin
                // TARGET_CURRENT is resident in every non-race filler case,
                // so returning to it suppresses an unintended +1 request.
                adpcma_addr = TARGET_CURRENT;
                adpcma_roe_n = 1'b1;
            end
        end
    endtask

    task automatic fill_idle_a_park(
        input logic [19:0] logical_addr,
        input logic [19:0] park_addr,
        output integer destination_slot,
        output logic old_valid,
        output logic [19:0] old_logical,
        output integer ptr_before,
        output integer ptr_after
    );
        integer guard;
        begin
            @(negedge clk);
            adpcma_roe_n = 1'b1;
            adpcma_addr = logical_addr;
            #1;
            ptr_before = {26'd0, dut.replace_ptr};
            destination_slot = {26'd0, dut.replacement_slot};
            old_valid = dut.cache_valid[destination_slot];
            old_logical = dut.cache_logical[destination_slot];
            guard = 0;
            while (find_a_slot(logical_addr) < 0 && guard < 200) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (find_a_slot(logical_addr) < 0) begin
                $display("FAIL parked fill timeout address=%05x", logical_addr);
                failures = failures + 1;
            end
            ptr_after = {26'd0, dut.replace_ptr};
            check(find_a_slot(logical_addr) == destination_slot,
                  "parked fill used unexpected destination slot");
            check(ptr_after == ((destination_slot + 1) % ENTRIES),
                  "parked fill pointer did not follow destination");
            adpcma_addr = park_addr;
            adpcma_roe_n = 1'b1;
        end
    endtask

    // Accept exactly one A request, then make the cache inactive before its
    // response.  This uses only public handshakes and prevents the idle B lane
    // from inserting extra fills while constructing exact pointer states.
    task automatic fill_a_single_pulsed(
        input logic [19:0] logical_addr,
        output integer destination_slot,
        output logic old_valid,
        output logic [19:0] old_logical,
        output integer ptr_before,
        output integer ptr_after
    );
        integer guard;
        begin
            @(negedge clk);
            active = 1'b1;
            map_enable = 1'b1;
            adpcma_addr = logical_addr;
            adpcma_roe_n = 1'b1;
            guard = 0;
            while (!dut.request_pending && guard < 100) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check(dut.request_pending,
                  "single-pulsed request was not accepted");
            active = 1'b0;
            #1;
            ptr_before = {26'd0, dut.replace_ptr};
            destination_slot = {26'd0, dut.replacement_slot};
            old_valid = dut.cache_valid[destination_slot];
            old_logical = dut.cache_logical[destination_slot];
            wait_a_fill(logical_addr);
            ptr_after = {26'd0, dut.replace_ptr};
            check(find_a_slot(logical_addr) == destination_slot,
                  "single-pulsed response used unexpected slot");
            check(ptr_after == ((destination_slot + 1) % ENTRIES),
                  "single-pulsed pointer did not follow destination");
        end
    endtask

    task automatic prefill_then_begin_keyon;
        integer slot;
        integer old_ptr;
        integer new_ptr;
        logic old_valid;
        logic [19:0] old_logical;
        begin
            // A normal speculative fill moves ptr 0->1 and places a harmless
            // entry in slot 0.  At the response negedge, immediately switch to
            // the pending key-on so no uncontrolled second fill is accepted.
            @(negedge clk);
            active = 1'b1;
            adpcma_addr = INITIAL_DUMMY;
            adpcma_roe_n = 1'b1;
            old_ptr = {26'd0, dut.replace_ptr};
            old_valid = dut.cache_valid[old_ptr];
            old_logical = dut.cache_logical[old_ptr];
            wait_a_fill(INITIAL_DUMMY);
            slot = find_a_slot(INITIAL_DUMMY);
            new_ptr = {26'd0, dut.replace_ptr};
            check(slot == 0, "initial dummy was not placed in slot 0");
            check(new_ptr == 1, "initial dummy did not move ptr to 1");
            adpcma_addr = TARGET_CURRENT;
            begin_keyon();
        end
    endtask

    task automatic setup_live_case(
        input logic prefill_dummy,
        output longint unsigned keyon_cycle,
        output integer current_slot,
        output integer next_slot,
        output integer keyon_ptr
    );
        begin
            reset_case();
            shadow_a_start();
            adpcma_addr = TARGET_CURRENT;
            adpcmb_addr = {4'd0, B_IDLE};
            if (prefill_dummy)
                prefill_then_begin_keyon();
            else begin
                @(negedge clk);
                active = 1'b1;
                begin_keyon();
            end
            accept_keyon(keyon_cycle, current_slot, next_slot, keyon_ptr);

            // The idle B lane is a real cache client.  Its current/+1 fills are
            // intentionally allowed to complete after key-on and count as the
            // first two post-key-on replacement operations.
            wait_b_fill(B_IDLE);
            wait_b_fill(B_IDLE + 20'd1);
            check(!dut.request_pending, "request remains pending after B fills");
            check(!dut.offer_valid, "offer remains held after B fills");
        end
    endtask

    task automatic live_read_check(
        input logic expected_hit,
        input logic expected_underflow,
        input string case_name
    );
        logic observed_hit;
        begin
            if (adpcma_roe_n) begin
                @(negedge clk);
                adpcma_addr = TARGET_CURRENT;
                adpcma_roe_n = 1'b0;
            end
            #1 observed_hit = dut.a_current_hit;
            $display("FOCUSED_FIRST_READ case=%s cycle=%0d address=%05x hit=%0d next_hit=%0d ptr=%0d",
                     case_name, cycle_count, adpcma_addr, observed_hit,
                     dut.a_next_hit, dut.replace_ptr);
            check(observed_hit == expected_hit, "live-read hit mismatch");
            @(posedge clk);
            #1;
            check(adpcma_underflow == expected_underflow,
                  "underflow result mismatch");
            $display("FOCUSED_UNDERFLOW case=%s cycle=%0d asserted=%0d",
                     case_name, cycle_count, adpcma_underflow);
            @(negedge clk);
            adpcma_roe_n = 1'b1;
            active = 1'b0;
        end
    endtask

    task automatic run_race_case;
        longint unsigned keyon_cycle;
        integer current_slot;
        integer next_slot;
        integer keyon_ptr;
        integer slot;
        integer ptr_before;
        integer ptr_after;
        integer n;
        logic [19:0] fill_addr;
        logic old_valid;
        logic [19:0] old_logical;
        begin
            setup_live_case(1'b0, keyon_cycle, current_slot, next_slot,
                            keyon_ptr);
            check(current_slot == 0, "race current byte not in slot 0");
            check(next_slot == 1, "race next byte not in slot 1");
            check(keyon_ptr == 2, "race key-on ptr is not 2");
            $display("FOCUSED_KEYON case=RACE cycle=%0d current=%05x next=%05x current_hit=%0d next_hit=%0d current_slot=%0d next_slot=%0d ptr=%0d",
                     keyon_cycle, TARGET_CURRENT, TARGET_NEXT,
                     dut.a_current_hit, dut.a_next_hit, current_slot,
                     next_slot, keyon_ptr);

            // B consumed slots 2/3.  Sixty more legal A fills consume 4..63,
            // placing replace_ptr at 0 without touching the prepared pair.
            fill_addr = 20'h40000;
            for (n = 0; n < 60; n = n + 1) begin
                fill_idle_a(fill_addr, 1'b0, slot,
                            old_valid, old_logical, ptr_before, ptr_after);
                fill_addr = fill_addr + 20'd4;
            end
            check(dut.replace_ptr == 0, "race ptr did not wrap to slot 0");
            check(find_a_slot(TARGET_CURRENT) == 0,
                  "current byte lost before designated replacement");
            check(find_a_slot(TARGET_NEXT) == 1,
                  "next byte lost before designated replacement");
            check(dut.prepared_a_valid[0],
                  "idle address aliases revoked prepared ownership");
            check(dut.live_a_valid == 0,
                  "idle address presentations entered live-read history");

            // The 63rd post-key-on response begins at slot 0.  The fixed cache
            // must skip both prepared slots, retain the incoming response in
            // the next eligible slot, and leave zero-wait playback intact.
            fill_idle_a(20'h6f000, 1'b1, slot, old_valid, old_logical,
                        ptr_before, ptr_after);
            $display("FOCUSED_REPLACE case=RACE cycle=%0d incoming=%05x slot=%0d old_valid=%0d old=%05x new=%05x ptr_before=%0d ptr_after=%0d keyon_cycle=%0d consumed_before=0",
                     cycle_count, 20'h6f000, slot, old_valid, old_logical,
                     dut.cache_logical[slot], ptr_before, ptr_after,
                     keyon_cycle);
            check(slot == 2, "fixed replacement did not skip prepared pair");
            check(old_valid && old_logical == B_IDLE,
                  "fixed replacement did not select first eligible slot");
            check(find_a_slot(20'h6f000) == slot,
                  "incoming replacement response was not cached");
            check(find_a_slot(TARGET_CURRENT) == current_slot,
                  "0x07600 was evicted after key-on readiness");
            check(find_a_slot(TARGET_NEXT) == 1,
                  "0x07601 should remain resident");
            check(ptr_after == 3,
                  "fixed replacement pointer did not advance past slot 2");
            live_read_check(1'b1, 1'b0, "RACE_FIXED");
        end
    endtask

    task automatic run_control_a;
        longint unsigned keyon_cycle;
        integer current_slot;
        integer next_slot;
        integer keyon_ptr;
        integer slot;
        integer ptr_before;
        integer ptr_after;
        integer n;
        logic [19:0] fill_addr;
        logic old_valid;
        logic [19:0] old_logical;
        begin
            setup_live_case(1'b0, keyon_cycle, current_slot, next_slot,
                            keyon_ptr);
            fill_addr = 20'h50000;
            for (n = 0; n < 60; n = n + 1) begin
                fill_idle_a(fill_addr, 1'b0, slot,
                            old_valid, old_logical, ptr_before, ptr_after);
                fill_addr = fill_addr + 20'd4;
            end
            check(dut.replace_ptr == 0, "control A ptr did not reach slot 0");
            check(find_a_slot(TARGET_CURRENT) == current_slot,
                  "control A lost current byte");
            live_read_check(1'b1, 1'b0, "CONTROL_A_ONE_FEWER");
            $display("CONTROL_A_PASS replacements_after_keyon=62 current_slot=%0d ptr=%0d",
                     current_slot, dut.replace_ptr);
        end
    endtask

    task automatic run_control_b;
        longint unsigned keyon_cycle;
        integer current_slot;
        integer next_slot;
        integer keyon_ptr;
        integer slot;
        integer ptr_before;
        integer ptr_after;
        integer n;
        logic [19:0] fill_addr;
        logic old_valid;
        logic [19:0] old_logical;
        begin
            setup_live_case(1'b1, keyon_cycle, current_slot, next_slot,
                            keyon_ptr);
            check(current_slot == 1, "control B current byte not in slot 1");
            check(next_slot == 2, "control B next byte not in slot 2");
            check(keyon_ptr == 3, "control B key-on ptr is not 3");
            // B fills slots 3/4.  Fifty-nine A fills place ptr at slot 0.
            fill_addr = 20'h60000;
            for (n = 0; n < 59; n = n + 1) begin
                fill_idle_a(fill_addr, 1'b0, slot,
                            old_valid, old_logical, ptr_before, ptr_after);
                fill_addr = fill_addr + 20'd4;
            end
            check(dut.replace_ptr == 0, "control B ptr did not reach slot 0");
            fill_idle_a(20'h6e000, 1'b0, slot, old_valid, old_logical,
                        ptr_before, ptr_after);
            $display("FOCUSED_REPLACE case=CONTROL_B cycle=%0d incoming=%05x slot=%0d old=%05x current_slot=%0d ptr_before=%0d ptr_after=%0d",
                     cycle_count, 20'h6e000, slot, old_logical,
                     current_slot, ptr_before, ptr_after);
            check(slot == 0, "control B candidate did not select slot 0");
            check(old_valid && old_logical == INITIAL_DUMMY,
                  "control B candidate did not replace dummy entry");
            check(find_a_slot(TARGET_CURRENT) == current_slot,
                  "control B lost current byte");
            live_read_check(1'b1, 1'b0, "CONTROL_B_DIFFERENT_POINTER");
            $display("CONTROL_B_PASS current_slot=%0d replacement_slot=%0d",
                     current_slot, slot);
        end
    endtask

    task automatic run_control_c;
        longint unsigned keyon_cycle;
        integer current_slot;
        integer next_slot;
        integer keyon_ptr;
        integer slot;
        integer ptr_before;
        integer ptr_after;
        logic old_valid;
        logic [19:0] old_logical;
        begin
            setup_live_case(1'b0, keyon_cycle, current_slot, next_slot,
                            keyon_ptr);
            // B already filled slots 2/3 harmlessly.  One additional fill at
            // slot 4 proves replacement of a non-live entry is also harmless.
            fill_idle_a(20'h6d000, 1'b0, slot, old_valid, old_logical,
                        ptr_before, ptr_after);
            check(slot == 4, "control C did not select expected non-live slot");
            check(find_a_slot(TARGET_CURRENT) == current_slot,
                  "control C lost current byte");
            live_read_check(1'b1, 1'b0, "CONTROL_C_HARMLESS");
            $display("CONTROL_C_PASS current_slot=%0d replacement_slot=%0d",
                     current_slot, slot);
        end
    endtask

    task automatic run_streaming_history_case;
        longint unsigned keyon_cycle;
        integer current_slot;
        integer next_slot;
        integer keyon_ptr;
        integer slot;
        integer ptr_before;
        integer ptr_after;
        integer n;
        integer guard;
        logic old_valid;
        logic [19:0] old_logical;
        logic [19:0] other_addr;
        begin
            setup_live_case(1'b0, keyon_cycle, current_slot, next_slot,
                            keyon_ptr);

            // Reach the prepared pair again, then remove its command-owned
            // reservation.  The following replacement must be prevented by
            // the persistent six-lane active-read history alone.
            for (n = 0; n < 60; n = n + 1)
                fill_idle_a(20'h52000 + n * 20'd4, 1'b0, slot,
                            old_valid, old_logical, ptr_before, ptr_after);
            check(dut.replace_ptr == 0,
                  "streaming case did not wrap to prepared current");
            accepted_write(1'b1, 8'h00, 8'h81);
            check(!dut.prepared_a_valid[0],
                  "accepted key-off did not release prepared ownership");

            // Supersede all three command-owned generations so TARGET is
            // protected only by the active-read history below.
            accepted_write(1'b1, 8'h10, 8'h52);
            accepted_write(1'b1, 8'h18, 8'h00);
            adpcma_addr = 20'h05200;
            accept_keyon_mask(6'h01);
            accepted_write(1'b1, 8'h10, 8'h53);
            adpcma_addr = 20'h05300;
            accept_keyon_mask(6'h01);
            accepted_write(1'b1, 8'h10, 8'h54);
            adpcma_addr = 20'h05400;
            accept_keyon_mask(6'h01);
            check(dut.prepared_a_current_slot[0] != current_slot &&
                  dut.retired_a_current_slot[0] != current_slot &&
                  dut.retired2_a_current_slot[0] != current_slot &&
                  dut.prepared_a_next_slot[0] != next_slot &&
                  dut.retired_a_next_slot[0] != next_slot &&
                  dut.retired2_a_next_slot[0] != next_slot,
                  "streaming setup left target command-pinned");

            // Disable mapping while presenting one full synthetic lane round,
            // avoiding unrelated fills.  Every address after TARGET is one
            // of the three newly prepared pairs, so no cache insertion can
            // disturb the victim state.  TARGET_CURRENT is deliberately the
            // oldest retained presentation while subsequent idle fills walk
            // the pointer back to it.
            map_enable = 1'b0;
            present_a_read(TARGET_CURRENT);
            present_a_read(20'h05200);
            present_a_read(20'h05201);
            present_a_read(20'h05300);
            present_a_read(20'h05301);
            present_a_read(20'h05400);
            check(live_history_contains(TARGET_CURRENT),
                  "six-lane history lost oldest live current");

            @(negedge clk);
            map_enable = 1'b1;
            adpcma_roe_n = 1'b1;
            ptr_before = -1;
            guard = 0;
            while (ptr_before != 0 && guard < 80) begin
                other_addr = 20'h56000 + guard * 20'd4;
                fill_idle_a(other_addr, 1'b0, slot, old_valid,
                            old_logical, ptr_before, ptr_after);
                guard = guard + 1;
            end
            map_enable = 1'b0;
            check(ptr_before == 0,
                  "streaming victim did not reach protected slot 0");
            check(slot != current_slot && slot != next_slot,
                  "streaming victim did not skip historical current/next");
            check(find_a_slot(other_addr) == slot,
                  "streaming incoming response was not cached");
            check(find_a_slot(TARGET_CURRENT) == current_slot,
                  "historical current was evicted");
            check(find_a_slot(TARGET_NEXT) == next_slot,
                  "historical next was evicted");
            check(ptr_after == ((slot + 1) % ENTRIES),
                  "streaming skip pointer did not advance past destination");
            check(!adpcma_underflow,
                  "streaming protection case asserted underflow");
            $display("INVARIANT_STREAMING_PASS current_slot=%0d next_slot=%0d incoming_slot=%0d ptr=%0d->%0d response_edge_addr=%05x",
                     current_slot, next_slot, slot, ptr_before, ptr_after,
                     other_addr);
            active = 1'b0;
            map_enable = 1'b1;
        end
    endtask

    task automatic run_transition_response_case;
        longint unsigned keyon_cycle;
        integer current_slot;
        integer next_slot;
        integer keyon_ptr;
        integer response_slot;
        integer slot;
        integer ptr_before;
        integer ptr_after;
        integer guard;
        integer n;
        logic old_valid;
        logic [19:0] old_logical;
        logic [19:0] response_addr_logical;
        logic [19:0] other_addr;
        begin
            setup_live_case(1'b0, keyon_cycle, current_slot, next_slot,
                            keyon_ptr);
            response_addr_logical = 20'h6a000;

            // Leave a run of ordinary A entries before the response slot so
            // the pointer can later approach it exactly.  The resident B pair
            // remains untouched in slots 2/3.
            for (n = 0; n < 6; n = n + 1)
                fill_idle_a_park(20'h69000 + n * 20'd4,
                                 TARGET_CURRENT, slot, old_valid,
                                 old_logical, ptr_before, ptr_after);

            // Put the requested address in the active history without
            // allowing a fill.  Its response will return on the same edge as
            // the bus transitions to a different, already-resident address.
            map_enable = 1'b0;
            present_a_read(response_addr_logical);
            check(live_history_contains(response_addr_logical),
                  "transition setup did not record response address");

            @(negedge clk);
            map_enable = 1'b1;
            adpcma_addr = response_addr_logical;
            adpcma_roe_n = 1'b1;
            guard = 0;
            while (!mem_valid && guard < 40) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check(mem_valid,
                  "transition response did not reach memory interface");
            check(dut.request_pending && !dut.request_space_b,
                  "transition response lost captured A ownership");

            // mem_valid is consumed at the next posedge.  Change the active
            // presentation now so response_live_a must use retained history,
            // not the raw address visible on the response edge.
            adpcma_addr = TARGET_CURRENT;
            adpcma_roe_n = 1'b0;
            #1;
            check(dut.live_a_transition,
                  "response-edge address did not create a live transition");
            check(dut.response_live_a,
                  "response-edge retained history did not mark response live");
            response_slot = {26'd0, dut.replacement_slot};
            @(posedge clk);
            #1;
            check(find_a_slot(response_addr_logical) == response_slot,
                  "transition-edge response was not cached");
            check(dut.live_a_slots[response_slot],
                  "transition-edge response lost live-slot protection");

            // Walk the public fill interface back to that slot and prove the
            // marked response is skipped, while the incoming fill progresses.
            @(negedge clk);
            adpcma_roe_n = 1'b1;
            adpcmb_roe_n = 1'b0;
            #1;
            check(dut.b_current_hit && dut.b_next_hit,
                  "transition scan lacks resident B pair");
            ptr_before = -1;
            guard = 0;
            while (ptr_before != response_slot && guard < 80) begin
                other_addr = 20'h6b000 + guard * 20'd4;
                fill_idle_a_park(other_addr, TARGET_CURRENT, slot,
                                 old_valid, old_logical,
                                 ptr_before, ptr_after);
                guard = guard + 1;
            end
            check(ptr_before == response_slot,
                  "transition test did not reach protected response slot");
            check(slot != response_slot,
                  "transition-edge live response was selected as victim");
            check(find_a_slot(response_addr_logical) == response_slot,
                  "transition-edge live response was evicted");
            check(find_a_slot(other_addr) == slot,
                  "transition-edge skip dropped incoming fill");
            check(ptr_after == ((slot + 1) % ENTRIES),
                  "transition-edge skip pointer did not progress");
            $display("INVARIANT_TRANSITION_RESPONSE_PASS response_slot=%0d incoming_slot=%0d ptr=%0d->%0d",
                     response_slot, slot, ptr_before, ptr_after);
            active = 1'b0;
            adpcmb_roe_n = 1'b1;
        end
    endtask

    task automatic run_six_channel_case;
        integer voice;
        integer n;
        integer slot;
        integer ptr_before;
        integer ptr_after;
        integer current_slots [0:5];
        integer next_slots [0:5];
        logic old_valid;
        logic [19:0] old_logical;
        logic [19:0] voice_current;
        begin
            reset_case();
            shadow_six_a_starts();
            @(negedge clk);
            active = 1'b1;
            adpcma_addr = 20'h02000;
            adpcmb_addr = {4'd0, B_IDLE};
            accept_keyon_mask(6'h3f);

            for (voice = 0; voice < 6; voice = voice + 1) begin
                voice_current = 20'h02000 + voice * 20'h01000;
                current_slots[voice] = find_a_slot(voice_current);
                next_slots[voice] = find_a_slot(voice_current + 20'd1);
                check(current_slots[voice] >= 0,
                      "six-channel key-on lacks current");
                check(next_slots[voice] >= 0,
                      "six-channel key-on lacks next");
                check(dut.prepared_a_valid[voice],
                      "six-channel prepared owner missing");
            end
            check(dut.replace_ptr == 12,
                  "six-channel prewarm did not consume twelve slots");

            wait_b_fill(B_IDLE);
            wait_b_fill(B_IDLE + 20'd1);
            check(dut.replace_ptr == 14,
                  "six-channel B warmup pointer mismatch");
            for (n = 0; n < 50; n = n + 1)
                fill_idle_a_park(20'h30000 + n * 20'd4, 20'h02000,
                                 slot, old_valid, old_logical,
                                 ptr_before, ptr_after);
            check(dut.replace_ptr == 0,
                  "six-channel replacement pointer did not wrap");

            fill_idle_a_park(20'h7a000, 20'h02000, slot, old_valid,
                             old_logical, ptr_before, ptr_after);
            check(ptr_before == 0,
                  "six-channel protected scan did not begin at slot 0");
            check(slot == 12,
                  "six-channel scan did not skip all twelve prepared slots");
            check(old_valid && old_logical == B_IDLE,
                  "six-channel scan did not choose first eligible slot");
            check(find_a_slot(20'h7a000) == 12,
                  "six-channel incoming fill was dropped");
            check(ptr_after == 13,
                  "six-channel pointer did not advance after skipped victim");

            for (voice = 0; voice < 6; voice = voice + 1) begin
                voice_current = 20'h02000 + voice * 20'h01000;
                check(find_a_slot(voice_current) == current_slots[voice],
                      "six-channel current changed during replacement");
                check(find_a_slot(voice_current + 20'd1) == next_slots[voice],
                      "six-channel next changed during replacement");
                adpcma_addr = voice_current;
                #1;
                check(dut.a_current_hit && dut.a_next_hit,
                      "six-channel current/next lookup failed");
            end
            check(!adpcma_underflow,
                  "six-channel stress asserted A underflow");
            $display("INVARIANT_SIX_CHANNEL_PASS protected=12 incoming_slot=%0d ptr=%0d->%0d",
                     slot, ptr_before, ptr_after);
            active = 1'b0;
        end
    endtask

    task automatic run_pointer_wrap_case;
        longint unsigned keyon_cycle;
        integer current_slot;
        integer next_slot;
        integer keyon_ptr;
        integer slot;
        integer ptr_before;
        integer ptr_after;
        integer n;
        integer guard;
        logic old_valid;
        logic [19:0] old_logical;
        begin
            reset_case();
            // Public one-request pulses place the prepared current at slot 63
            // and its next byte at slot 0.
            for (n = 0; n < 63; n = n + 1)
                fill_a_single_pulsed(20'h10000 + n * 20'd4, slot,
                                     old_valid, old_logical,
                                     ptr_before, ptr_after);
            check(dut.replace_ptr == 63,
                  "pointer-wrap setup did not reach slot 63");
            shadow_a_start();
            @(negedge clk);
            active = 1'b1;
            adpcma_addr = TARGET_CURRENT;
            begin_keyon();
            #1;
            guard = 0;
            while (!write_allow && guard < 300) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check(write_allow,
                  "pointer-wrap key-on prewarm did not complete");
            current_slot = find_a_slot(TARGET_CURRENT);
            next_slot = find_a_slot(TARGET_NEXT);
            keyon_ptr = {26'd0, dut.replace_ptr};
            // Suppress the unrelated idle-B request on the acceptance edge.
            map_enable = 1'b0;
            write_accept = 1'b1;
            @(posedge clk);
            #1 keyon_cycle = cycle_count;
            @(negedge clk);
            write_valid = 1'b0;
            write_accept = 1'b0;
            active = 1'b0;
            map_enable = 1'b1;
            check(current_slot == 63,
                  "pointer-wrap current was not placed at slot 63");
            check(next_slot == 0,
                  "pointer-wrap next was not placed at slot 0");
            check(keyon_ptr == 1,
                  "pointer-wrap key-on pointer was not slot 1");

            for (n = 0; n < 62; n = n + 1)
                fill_a_single_pulsed(20'h40000 + n * 20'd4, slot,
                                     old_valid, old_logical,
                                     ptr_before, ptr_after);
            check(dut.replace_ptr == 63,
                  "pointer-wrap victim scan did not return to slot 63");

            fill_a_single_pulsed(20'h7b000, slot, old_valid, old_logical,
                                 ptr_before, ptr_after);
            check(ptr_before == 63,
                  "pointer-wrap response did not begin at slot 63");
            check(slot == 1,
                  "pointer-wrap response did not skip slots 63 and 0");
            check(ptr_after == 2,
                  "pointer-wrap pointer did not advance to slot 2");
            check(find_a_slot(TARGET_CURRENT) == 63,
                  "pointer-wrap current was evicted");
            check(find_a_slot(TARGET_NEXT) == 0,
                  "pointer-wrap next was evicted");
            check(find_a_slot(20'h7b000) == 1,
                  "pointer-wrap incoming response was dropped");
            $display("INVARIANT_POINTER_WRAP_PASS current_slot=%0d next_slot=%0d incoming_slot=%0d ptr=%0d->%0d",
                     current_slot, next_slot, slot, ptr_before, ptr_after);
        end
    endtask

    task automatic run_lifecycle_case;
        longint unsigned keyon_cycle;
        integer current_slot;
        integer next_slot;
        integer keyon_ptr;
        integer slot;
        integer ptr_before;
        integer ptr_after;
        integer n;
        logic old_valid;
        logic [19:0] old_logical;
        begin
            // A stop accepted before JT10's first read moves the prepared
            // generation into the bounded retirement reservation.  A response
            // at its slots must still skip it while the bus command catches up.
            setup_live_case(1'b0, keyon_cycle, current_slot, next_slot,
                            keyon_ptr);
            for (n = 0; n < 60; n = n + 1)
                fill_idle_a(20'h61000 + n * 20'd4, 1'b0, slot,
                            old_valid, old_logical, ptr_before, ptr_after);
            check(dut.replace_ptr == 0,
                  "lifecycle stop setup did not wrap pointer");
            accepted_write(1'b1, 8'h00, 8'h81);
            check(!dut.prepared_a_valid[0],
                  "lifecycle stop left prepared owner set");
            check(dut.retired_a_valid[0],
                  "lifecycle stop did not retain prior generation");
            fill_idle_a(20'h7d000, 1'b0, slot, old_valid, old_logical,
                        ptr_before, ptr_after);
            check(slot == 2,
                  "immediate-stop response did not skip retired pair");
            check(find_a_slot(TARGET_CURRENT) == current_slot &&
                  find_a_slot(TARGET_NEXT) == next_slot,
                  "immediate stop exposed the in-flight generation");

            // Re-key establishes a new current generation while retaining the
            // prior two.  A third re-key supersedes the oldest bounded slot;
            // reservations do not accumulate over the track.
            accepted_write(1'b1, 8'h10, 8'h77);
            accepted_write(1'b1, 8'h18, 8'h00);
            adpcma_addr = 20'h07700;
            accept_keyon_mask(6'h01);
            check(dut.prepared_a_valid[0],
                  "re-key did not establish new prepared owner");
            check(dut.prepared_a_current_slot[0] ==
                      find_a_slot(20'h07700),
                  "re-key current owner did not move to new slot");
            check(dut.prepared_a_next_slot[0] ==
                      find_a_slot(20'h07701),
                  "re-key next owner did not move to new slot");
            check(dut.retired_a_valid[0] &&
                  dut.retired_a_current_slot[0] == current_slot,
                  "re-key did not preserve stopped generation");

            accepted_write(1'b1, 8'h10, 8'h78);
            adpcma_addr = 20'h07800;
            accept_keyon_mask(6'h01);
            check(dut.prepared_a_valid[0] &&
                  find_a_slot(20'h07800) >= 0 &&
                  find_a_slot(20'h07801) >= 0,
                  "second re-key did not establish current generation");
            check(dut.retired_a_valid[0] &&
                  dut.retired_a_current_slot[0] == find_a_slot(20'h07700),
                  "second re-key did not supersede prior reservation");
            check(dut.retired2_a_valid[0] &&
                  dut.retired2_a_current_slot[0] == current_slot,
                  "second re-key did not preserve oldest generation");

            accepted_write(1'b1, 8'h10, 8'h79);
            adpcma_addr = 20'h07900;
            accept_keyon_mask(6'h01);
            check(dut.prepared_a_valid[0] &&
                  find_a_slot(20'h07900) >= 0 &&
                  find_a_slot(20'h07901) >= 0,
                  "third re-key did not establish current generation");
            check(dut.retired_a_current_slot[0] ==
                      find_a_slot(20'h07800) &&
                  dut.retired2_a_current_slot[0] ==
                      find_a_slot(20'h07700),
                  "third re-key generation order is incorrect");
            active = 1'b0;
            @(posedge clk);
            for (n = 0; n < 60; n = n + 1)
                fill_a_single_pulsed(20'h65000 + n * 20'd4, slot,
                                     old_valid, old_logical,
                                     ptr_before, ptr_after);
            check(find_a_slot(TARGET_CURRENT) < 0,
                  "re-key left old current protected");
            check(find_a_slot(TARGET_NEXT) < 0,
                  "third re-key accumulated oldest next reservation");
            check(find_a_slot(20'h07700) >= 0,
                  "retired re-key current was evicted");
            check(find_a_slot(20'h07701) >= 0,
                  "retired re-key next was evicted");
            check(find_a_slot(20'h07800) >= 0 &&
                  find_a_slot(20'h07801) >= 0,
                  "newer retired re-key pair was evicted");
            check(find_a_slot(20'h07900) >= 0 &&
                  find_a_slot(20'h07901) >= 0,
                  "current re-key pair was evicted");

            reset_case();
            check(dut.prepared_a_valid == 0,
                  "reset left prepared ownership");
            check(dut.retired_a_valid == 0,
                  "reset left retired ownership");
            check(dut.retired2_a_valid == 0,
                  "reset left second retired ownership");
            check(dut.live_a_valid == 0,
                  "reset left live presentation history");
            check(!dut.live_b_valid && dut.live_b_slots == 0,
                  "reset left live ADPCM-B protection");
            check(dut.replace_ptr == 0,
                  "reset did not restore replacement pointer");
            check(occupancy == 0,
                  "reset did not invalidate cache entries");
            fill_a_single_pulsed(20'h7c000, slot, old_valid, old_logical,
                                 ptr_before, ptr_after);
            check(slot == 0 && ptr_after == 1,
                  "post-reset first response did not use slot 0");
            $display("INVARIANT_LIFECYCLE_PASS stop=1 rekey=1 reset=1");
        end
    endtask

    task automatic run_adpcmb_regression_case;
        longint unsigned keyon_cycle;
        integer current_slot;
        integer next_slot;
        integer keyon_ptr;
        integer slot;
        integer ptr_before;
        integer ptr_after;
        integer n;
        integer guard;
        logic old_valid;
        logic [19:0] old_logical;
        logic [31:0] a_responses_before;
        logic [31:0] b_responses_before;
        logic [31:0] responses_before;
        begin
            setup_live_case(1'b0, keyon_cycle, current_slot, next_slot,
                            keyon_ptr);
            for (n = 0; n < 60; n = n + 1)
                fill_idle_a(20'h58000 + n * 20'd4, 1'b0, slot,
                            old_valid, old_logical, ptr_before, ptr_after);
            check(dut.replace_ptr == 0,
                  "ADPCM-B shared-cache case did not wrap pointer");

            // Redirecting around protected A must not sacrifice the last B
            // current/next pair.  JT10's real B ROE is a one-clock pulse, so
            // make the A response arrive only after ROE has returned high.
            @(negedge clk);
            adpcmb_addr = {4'd0, B_IDLE};
            adpcmb_roe_n = 1'b0;
            @(posedge clk);
            #1;
            check(dut.live_b_valid &&
                  dut.live_b_slots[2] && dut.live_b_slots[3],
                  "one-cycle ADPCM-B read did not retain its live pair");
            @(negedge clk);
            adpcmb_roe_n = 1'b1;
            fill_idle_a(20'h7e000, 1'b0, slot, old_valid, old_logical,
                        ptr_before, ptr_after);
            check(ptr_before == 0 && slot == 4,
                  "redirected victim did not skip active ADPCM-B pair");
            check(find_b_slot(B_IDLE) == 2 &&
                  find_b_slot(B_IDLE + 20'd1) == 3,
                  "redirected fill evicted active ADPCM-B data");
            check(find_a_slot(20'h7e000) == 4,
                  "redirected fill after active B pair was dropped");
            check(!adpcmb_underflow,
                  "active ADPCM-B protection case underflowed");
            @(negedge clk);
            adpcmb_roe_n = 1'b0;
            #1;
            check(dut.b_current_hit,
                  "next ADPCM-B pulse missed retained current");
            @(posedge clk);
            #1;
            check(!adpcmb_underflow,
                  "next ADPCM-B pulse underflowed after redirected fill");
            @(negedge clk);
            adpcmb_roe_n = 1'b1;
            active = 1'b0;

            // Retain the existing space-B response/counter coverage in an
            // independent exact pointer setup.
            setup_live_case(1'b0, keyon_cycle, current_slot, next_slot,
                            keyon_ptr);
            for (n = 0; n < 60; n = n + 1)
                fill_idle_a(20'h58000 + n * 20'd4, 1'b0, slot,
                            old_valid, old_logical, ptr_before, ptr_after);
            check(dut.replace_ptr == 0,
                  "ADPCM-B response subcase did not wrap pointer");
            a_responses_before = adpcma_fetch_responses;
            b_responses_before = adpcmb_fetch_responses;
            responses_before = response_count;

            @(negedge clk);
            adpcma_addr = TARGET_CURRENT;
            adpcmb_addr = {4'd0, B_ALT};
            #1;
            ptr_before = {26'd0, dut.replace_ptr};
            slot = {26'd0, dut.replacement_slot};
            old_valid = dut.cache_valid[slot];
            old_logical = dut.cache_logical[slot];
            wait_b_fill(B_ALT);
            ptr_after = {26'd0, dut.replace_ptr};
            active = 1'b0;
            check(ptr_before == 0 && slot == 2,
                  "ADPCM-B response did not skip prepared A pair");
            check(old_valid && old_logical == B_IDLE,
                  "ADPCM-B response did not replace eligible B slot");
            check(find_b_slot(B_ALT) == slot,
                  "ADPCM-B incoming response was not cached as space B");
            check(ptr_after == 3,
                  "ADPCM-B replacement pointer did not progress");
            check(find_a_slot(TARGET_CURRENT) == current_slot &&
                  find_a_slot(TARGET_NEXT) == next_slot,
                  "ADPCM-B response damaged protected A entries");
            check(response_count == responses_before + 32'd1,
                  "ADPCM-B response count did not advance exactly once");
            check(adpcma_fetch_responses == a_responses_before,
                  "ADPCM-B response changed A response counter");
            check(adpcmb_fetch_responses == b_responses_before + 32'd1,
                  "ADPCM-B response counter did not advance exactly once");

            @(negedge clk);
            active = 1'b1;
            map_enable = 1'b0;
            adpcmb_addr = {4'd0, B_ALT};
            adpcmb_roe_n = 1'b0;
            #1;
            check(dut.b_current_hit && adpcmb_data == 8'h5a,
                  "ADPCM-B cached read data mismatch");
            @(posedge clk);
            #1;
            check(!adpcmb_underflow,
                  "ADPCM-B shared-cache read underflowed");

            // Preserve the existing B key-on prewarm contract as a separate
            // lifecycle subcase.
            reset_case();
            accepted_write(1'b0, 8'h12, 8'h34);
            accepted_write(1'b0, 8'h13, 8'h00);
            @(negedge clk);
            active = 1'b1;
            adpcmb_addr = {4'd0, 20'h03400};
            write_valid = 1'b1;
            write_accept = 1'b0;
            write_port = 1'b0;
            write_address = 8'h10;
            write_data = 8'h80;
            #1;
            check(!write_allow,
                  "ADPCM-B command was allowed before prewarm");
            guard = 0;
            while (!write_allow && guard < 300) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check(write_allow,
                  "ADPCM-B prewarm did not complete");
            check(find_b_slot(20'h03400) >= 0 &&
                  find_b_slot(20'h03401) >= 0,
                  "ADPCM-B prewarm pair is not resident");
            map_enable = 1'b0;
            write_accept = 1'b1;
            @(posedge clk);
            @(negedge clk);
            write_valid = 1'b0;
            write_accept = 1'b0;
            adpcmb_roe_n = 1'b0;
            #1;
            check(dut.b_current_hit,
                  "ADPCM-B first prepared read missed");
            @(posedge clk);
            #1;
            check(!adpcmb_underflow,
                  "ADPCM-B prepared read underflowed");
            $display("INVARIANT_ADPCMB_PASS shared_replacement=1 inter_strobe=1 prewarm=1 read=1");
            active = 1'b0;
            adpcmb_roe_n = 1'b1;
            map_enable = 1'b1;
        end
    endtask

    initial begin
        reset = 1'b1;
        active = 1'b0;
        map_enable = 1'b1;
        write_valid = 1'b0;
        write_accept = 1'b0;
        write_port = 1'b0;
        write_address = 8'd0;
        write_data = 8'd0;
        adpcma_addr = TARGET_CURRENT;
        adpcma_bank = 4'd0;
        adpcma_roe_n = 1'b1;
        adpcmb_addr = {4'd0, B_IDLE};
        adpcmb_roe_n = 1'b1;
        failures = 0;

        run_race_case();
        run_control_a();
        run_control_b();
        run_control_c();
        run_streaming_history_case();
        run_transition_response_case();
        run_six_channel_case();
        run_pointer_wrap_case();
        run_lifecycle_case();
        run_adpcmb_regression_case();

        if (failures == 0) begin
            $display("GF09_FOCUSED_CACHE_PASS fixed_race=1 control_a=1 control_b=1 control_c=1 streaming=1 transition_response=1 six_channel=1 pointer_wrap=1 lifecycle=1 adpcmb=1");
            $finish;
        end else
            $fatal(1, "GF09_FOCUSED_CACHE_FAIL failures=%0d", failures);
    end
endmodule

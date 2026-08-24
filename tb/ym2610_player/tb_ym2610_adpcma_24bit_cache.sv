`timescale 1ns/1ps

module tb_ym2610_adpcma_24bit_cache;
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
    logic [7:0] adpcma_data;
    logic [23:0] adpcmb_addr = 24'd0;
    logic adpcmb_roe_n = 1'b1;
    logic [7:0] adpcmb_data;
    logic map_req_valid, map_req_ready, map_space_b;
    logic [23:0] map_logical_addr;
    logic map_rsp_valid = 1'b0;
    logic map_rsp_hit = 1'b0;
    logic [ADDR_WIDTH-1:0] map_rsp_file_addr = '0;
    logic mem_req;
    logic [ADDR_WIDTH-1:0] mem_addr;
    logic mem_ready = 1'b1;
    logic mem_valid = 1'b0;
    logic [7:0] mem_data = 8'd0;
    logic mem_armed = 1'b0;
    logic [ADDR_WIDTH-1:0] mem_captured;
    integer failures = 0;
    integer a_mapper_requests = 0;

    always #5 clk = ~clk;
    assign map_req_ready = 1'b1;

    ym2610_player_pcm_cache dut (
        .clk(clk), .reset(reset), .active(active),
        .write_valid(write_valid), .write_accept(write_accept),
        .write_port(write_port), .write_address(write_address),
        .write_data(write_data), .write_allow(write_allow),
        .adpcma_addr(adpcma_addr), .adpcma_bank(adpcma_bank),
        .adpcma_roe_n(adpcma_roe_n), .adpcma_data(adpcma_data),
        .adpcmb_addr(adpcmb_addr), .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(adpcmb_data),
        .map_req_valid(map_req_valid), .map_req_ready(map_req_ready),
        .map_space_b(map_space_b), .map_logical_addr(map_logical_addr),
        .map_rsp_valid(map_rsp_valid), .map_rsp_hit(map_rsp_hit),
        .map_rsp_file_addr(map_rsp_file_addr),
        .mem_req(mem_req), .mem_addr(mem_addr), .mem_ready(mem_ready),
        .mem_valid(mem_valid), .mem_data(mem_data),
        .request_count(), .response_count(), .adpcma_request_count(),
        .adpcmb_request_count(), .adpcma_fetch_requests(),
        .adpcma_fetch_responses(), .adpcmb_fetch_requests(),
        .adpcmb_fetch_responses(), .adpcma_underflow(),
        .adpcmb_underflow(), .range_error(), .stale_response(),
        .request_held(), .response_pending(), .held_space_b(),
        .held_logical_addr(), .occupancy(), .last_logical_addr(),
        .adpcma_last_address(), .adpcmb_last_address()
    );

    always_ff @(posedge clk) begin
        map_rsp_valid <= 1'b0;
        if (!reset && map_req_valid && map_req_ready) begin
            if (!map_space_b)
                a_mapper_requests <= a_mapper_requests + 1;
            map_rsp_valid <= 1'b1;
            map_rsp_hit <= 1'b1;
            map_rsp_file_addr <= map_logical_addr[ADDR_WIDTH-1:0];
        end
        mem_valid <= 1'b0;
        if (reset) begin
            mem_armed <= 1'b0;
        end else begin
            if (mem_armed) begin
                mem_valid <= 1'b1;
                mem_data <= mem_captured[7:0] ^ 8'hA5;
                mem_armed <= 1'b0;
            end
            if (mem_req && mem_ready) begin
                if (mem_armed || mem_valid)
                    $fatal(1, "overlapping memory transaction");
                mem_armed <= 1'b1;
                mem_captured <= mem_addr;
            end
        end
    end

    function automatic integer find_a(
        input logic [3:0] bank,
        input logic [19:0] low
    );
        integer slot;
        begin
            find_a = -1;
            for (slot = 0; slot < 64; slot = slot + 1)
                if (dut.cache_valid[slot] && !dut.cache_space_b[slot] &&
                    dut.cache_bank[slot] == bank &&
                    dut.cache_logical[slot] == low)
                    find_a = slot;
        end
    endfunction

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $display("FAIL %s", message);
            failures = failures + 1;
        end
    endtask

    task automatic reset_cache;
        begin
            @(negedge clk);
            reset = 1'b1;
            active = 1'b0;
            write_valid = 1'b0;
            write_accept = 1'b0;
            adpcma_roe_n = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;
            active = 1'b1;
        end
    endtask

    task automatic accepted_write(
        input logic port_number,
        input logic [7:0] address,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            write_valid = 1'b1;
            write_accept = 1'b1;
            write_port = port_number;
            write_address = address;
            write_data = value;
            @(posedge clk);
            @(negedge clk);
            write_valid = 1'b0;
            write_accept = 1'b0;
        end
    endtask

    task automatic set_a_start(
        input integer voice,
        input logic [15:0] start_value
    );
        begin
            accepted_write(1'b1, 8'h10 + voice[7:0], start_value[7:0]);
            accepted_write(1'b1, 8'h18 + voice[7:0], start_value[15:8]);
        end
    endtask

    task automatic accept_keyon(input logic [5:0] mask);
        integer guard;
        begin
            @(negedge clk);
            write_valid = 1'b1;
            write_accept = 1'b0;
            write_port = 1'b1;
            write_address = 8'h00;
            write_data = {2'b00, mask};
            guard = 0;
            #1;
            while (!write_allow && guard < 3000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check(write_allow, "serialized prewarm timeout");
            write_accept = 1'b1;
            @(posedge clk);
            @(negedge clk);
            write_valid = 1'b0;
            write_accept = 1'b0;
        end
    endtask

    task automatic wait_pair(input logic [23:0] current);
        integer guard;
        logic [23:0] following;
        begin
            following = current + 24'd1;
            adpcma_bank = current[23:20];
            adpcma_addr = current[19:0];
            guard = 0;
            while ((find_a(current[23:20], current[19:0]) < 0 ||
                    find_a(following[23:20], following[19:0]) < 0) &&
                   guard < 1000) begin
                // Runtime current/next requests have a real owner only while
                // JT10 asserts its A ROM read pulse.
                adpcma_roe_n = 1'b0;
                @(negedge clk);
                adpcma_roe_n = 1'b1;
                @(negedge clk);
                guard = guard + 1;
            end
            check(find_a(current[23:20], current[19:0]) >= 0,
                  "current fill missing");
            check(find_a(following[23:20], following[19:0]) >= 0,
                  "next fill missing");
        end
    endtask

    initial begin
        logic [23:0] boundary_next;
        integer voice;
        integer bank;
        integer vector_index;
        integer request_baseline;
        logic [15:0] starts [0:5];
        logic [23:0] address_vectors [0:7];

        reset_cache();
        request_baseline = a_mapper_requests;
        adpcma_bank = 4'd0;
        adpcma_addr = 20'd0;
        adpcma_roe_n = 1'b1;
        repeat (40) @(negedge clk);
        check(a_mapper_requests == request_baseline,
              "idle/non-live A generated a mapper request");
        $display("ADPCMA24_IDLE_A mapper_requests=0 result=PASS");

        request_baseline = a_mapper_requests;
        wait_pair(24'h0FFFFF);
        check(a_mapper_requests >= request_baseline + 2,
              "live A current/next mapper requests missing");
        boundary_next = 24'h0FFFFF + 24'd1;
        check(boundary_next == 24'h100000, "test arithmetic is wrong");
        check(find_a(4'h0, 20'hFFFFF) >= 0,
              "bank0 boundary current not resident");
        check(find_a(4'h1, 20'h00000) >= 0,
              "24-bit +1 did not carry into bank1");
        check(find_a(4'h0, 20'h00000) < 0,
              "24-bit +1 wrapped into bank0 alias");
        adpcma_roe_n = 1'b0;
        #1 check(dut.a_current_hit && dut.a_next_hit,
                 "boundary live lookup is not zero-wait");
        @(negedge clk);
        adpcma_roe_n = 1'b1;
        $display("ADPCMA24_BOUNDARY current=0FFFFF next=100000 result=PASS");

        for (bank = 1; bank < 15; bank = bank + 1) begin
            reset_cache();
            wait_pair({bank[3:0], 20'hFFFFF});
            check(find_a(bank[3:0], 20'hFFFFF) >= 0,
                  "bank-boundary current missing");
            check(find_a(bank[3:0] + 4'd1, 20'h00000) >= 0,
                  "bank-boundary carry target missing");
            check(find_a(bank[3:0], 20'h00000) < 0,
                  "bank-boundary next aliased old bank");
        end
        $display("ADPCMA24_ALL_BOUNDARIES transitions=15 result=PASS");

        address_vectors[0] = 24'h0FFFFE;
        address_vectors[1] = 24'h100000;
        address_vectors[2] = 24'h100001;
        address_vectors[3] = 24'h168B00;
        address_vectors[4] = 24'h16AFFF;
        address_vectors[5] = 24'h170000;
        address_vectors[6] = 24'h17EAFF;
        address_vectors[7] = 24'h301AFF;
        for (vector_index = 0; vector_index < 8;
             vector_index = vector_index + 1) begin
            reset_cache();
            wait_pair(address_vectors[vector_index]);
            adpcma_roe_n = 1'b0;
            #1 check(dut.a_current_hit && dut.a_next_hit,
                     "required wide-address vector is not zero-wait");
            @(negedge clk);
            adpcma_roe_n = 1'b1;
        end
        $display("ADPCMA24_REQUIRED_VECTORS count=8 cache_fill_hit=PASS zero_wait=PASS");

        reset_cache();
        set_a_start(0, 16'h168B);
        accept_keyon(6'b000001);
        check(find_a(4'h1, 20'h68B00) >= 0,
              "bank1 selected-voice current missing");
        check(find_a(4'h1, 20'h68B01) >= 0,
              "bank1 selected-voice next missing");
        check(dut.prepared_a_valid[0], "bank1 voice was not prepared");
        $display("ADPCMA24_PREWARM address=168B00 voice=0 result=PASS");

        reset_cache();
        wait_pair(24'h301AFF);
        check(find_a(4'h3, 20'h01AFF) >= 0,
              "high Neo Geo structural address was truncated");
        check(find_a(4'h0, 20'h01AFF) < 0,
              "high Neo Geo address aliased bank0");
        $display("ADPCMA24_HIGH address=301AFF result=PASS");

        reset_cache();
        starts[0] = 16'h0001;
        starts[1] = 16'h1002;
        starts[2] = 16'h2003;
        starts[3] = 16'h3004;
        starts[4] = 16'h4005;
        starts[5] = 16'h5006;
        for (voice = 0; voice < 6; voice = voice + 1)
            set_a_start(voice, starts[voice]);
        accept_keyon(6'b111111);
        for (voice = 0; voice < 6; voice = voice + 1) begin
            check(dut.prepared_a_valid[voice],
                  "all-six prepared valid missing");
            check(find_a(starts[voice][15:12],
                         {starts[voice][11:0], 8'd0}) >= 0,
                  "all-six banked current missing");
        end
        $display("ADPCMA24_ALL_SIX banks=0..5 result=PASS");

        reset_cache();
        set_a_start(0, 16'h17EA);
        @(negedge clk);
        write_valid = 1'b1;
        write_port = 1'b1;
        write_address = 8'h00;
        write_data = 8'h01;
        repeat (8) @(posedge clk);
        reset = 1'b1;
        repeat (2) @(posedge clk);
        check(dut.prewarm_state == dut.PW_IDLE,
              "reset did not abort serialized prewarm");
        check(!dut.lookup_offer_valid && !dut.map_pending &&
              !dut.offer_valid && !dut.request_pending,
              "reset left a stale prewarm transaction");
        @(negedge clk);
        reset = 1'b0;
        write_valid = 1'b0;
        active = 1'b1;
        set_a_start(0, 16'h17EA);
        accept_keyon(6'b000001);
        check(dut.prepared_a_valid[0] &&
              find_a(4'h1, 20'h7EA00) >= 0 &&
              find_a(4'h1, 20'h7EA01) >= 0,
              "reload did not rearm serialized prewarm");
        $display("ADPCMA24_RESET_RELOAD_PREWARM stale=0 rearm=1 result=PASS");

        if (failures != 0)
            $fatal(1, "ADPCMA24_CACHE_FAIL failures=%0d", failures);
        $display("ADPCMA24_CACHE_PASS boundary=15 banked=1 high=1 voices=6 reset_reload=1");
        $finish;
    end
endmodule

`timescale 1ns/1ps

// Small shared read-through cache for JT10's zero-wait-state ROM pins.  Parser
// writes to ADPCM start registers are shadowed.  A key-on is held before the
// public JT10 bus until the first two bytes of every selected stream are
// resident; steady-state current/+1 prefetch then hides DDR latency.
module ym2610_player_pcm_cache #(
    parameter int ADDR_WIDTH = 23,
    parameter int ENTRIES = 64
) (
    input  logic                  clk,
    input  logic                  reset,
    input  logic                  active,

    input  logic                  write_valid,
    input  logic                  write_accept,
    input  logic                  write_port,
    input  logic [7:0]            write_address,
    input  logic [7:0]            write_data,
    output logic                  write_allow,

    input  logic [19:0]           adpcma_addr,
    input  logic [3:0]            adpcma_bank,
    input  logic                  adpcma_roe_n,
    output logic [7:0]            adpcma_data,
    input  logic [23:0]           adpcmb_addr,
    input  logic                  adpcmb_roe_n,
    output logic [7:0]            adpcmb_data,

    output logic                  map_space_b,
    output logic [19:0]           map_logical_addr,
    input  logic                  map_hit,
    input  logic [ADDR_WIDTH-1:0] map_file_addr,

    output logic                  mem_req,
    output logic [ADDR_WIDTH-1:0] mem_addr,
    input  logic                  mem_ready,
    input  logic                  mem_valid,
    input  logic [7:0]            mem_data,

    output logic [31:0]           request_count,
    output logic [31:0]           response_count,
    output logic [31:0]           adpcma_request_count,
    output logic [31:0]           adpcmb_request_count,
    output logic [31:0]           adpcma_fetch_requests,
    output logic [31:0]           adpcma_fetch_responses,
    output logic [31:0]           adpcmb_fetch_requests,
    output logic [31:0]           adpcmb_fetch_responses,
    output logic                  adpcma_underflow,
    output logic                  adpcmb_underflow,
    output logic                  range_error,
    output logic                  stale_response,
    output logic                  request_held,
    output logic                  response_pending,
    output logic                  held_space_b,
    output logic [19:0]           held_logical_addr,
    output logic [6:0]            occupancy,
    output logic [19:0]           last_logical_addr,
    output logic [19:0]           adpcma_last_address,
    output logic [19:0]           adpcmb_last_address
);
    localparam int PTR_WIDTH = $clog2(ENTRIES);
    logic cache_valid [0:ENTRIES-1];
    logic cache_space_b [0:ENTRIES-1];
    logic [19:0] cache_logical [0:ENTRIES-1];
    logic [7:0] cache_data [0:ENTRIES-1];
    logic [PTR_WIDTH-1:0] replace_ptr;
    logic [15:0] start_a [0:5];
    logic [15:0] start_b;
    logic request_pending;
    logic request_space_b;
    logic [19:0] request_logical;
    logic offer_valid;
    logic offer_space_b;
    logic [19:0] offer_logical;
    logic [ADDR_WIDTH-1:0] offer_file_addr;
    logic accepted_space_b;
    logic [19:0] accepted_logical;
    logic prefer_b;
    logic need_valid;
    logic need_required;
    logic need_space_b;
    logic [19:0] need_logical;
    logic a_current_hit, a_next_hit, b_current_hit, b_next_hit;
    logic [7:0] a_current_data, b_current_data;
    logic prewarm_a;
    logic prewarm_b;
    logic prewarm_missing;
    logic a_need_valid, a_need_required;
    logic b_need_valid, b_need_required;
    logic [19:0] a_need_logical, b_need_logical;
    integer i;

    function automatic logic contains(input logic space_b,
                                      input logic [19:0] logical_addr);
        logic found;
        begin
            found = 1'b0;
            for (integer find_i = 0; find_i < ENTRIES; find_i = find_i + 1)
                if (cache_valid[find_i] && cache_space_b[find_i] == space_b &&
                    cache_logical[find_i] == logical_addr)
                    found = 1'b1;
            contains = found;
        end
    endfunction

    always_comb begin
        a_current_hit = 1'b0;
        a_next_hit = 1'b0;
        b_current_hit = 1'b0;
        b_next_hit = 1'b0;
        a_current_data = 8'd0;
        b_current_data = 8'd0;
        occupancy = 7'd0;
        for (integer lookup_i = 0; lookup_i < ENTRIES; lookup_i = lookup_i + 1) begin
            if (cache_valid[lookup_i]) begin
                occupancy = occupancy + 7'd1;
                if (!cache_space_b[lookup_i] &&
                    cache_logical[lookup_i] == adpcma_addr) begin
                    a_current_hit = 1'b1;
                    a_current_data = cache_data[lookup_i];
                end
                if (!cache_space_b[lookup_i] &&
                    cache_logical[lookup_i] == adpcma_addr + 20'd1)
                    a_next_hit = 1'b1;
                if (cache_space_b[lookup_i] &&
                    cache_logical[lookup_i] == adpcmb_addr[19:0]) begin
                    b_current_hit = 1'b1;
                    b_current_data = cache_data[lookup_i];
                end
                if (cache_space_b[lookup_i] &&
                    cache_logical[lookup_i] == adpcmb_addr[19:0] + 20'd1)
                    b_next_hit = 1'b1;
            end
        end
        adpcma_data = a_current_data;
        adpcmb_data = b_current_data;
    end

    assign mem_req = offer_valid ||
                     (active && need_valid && map_hit && !request_pending);
    assign mem_addr = offer_valid ? offer_file_addr : map_file_addr;
    assign accepted_space_b = offer_valid ? offer_space_b : need_space_b;
    assign accepted_logical = offer_valid ? offer_logical : need_logical;
    assign request_held = offer_valid;
    assign response_pending = request_pending;
    assign held_space_b = offer_valid ? offer_space_b : request_space_b;
    assign held_logical_addr = offer_valid ? offer_logical : request_logical;

    always_comb begin
        prewarm_a = write_valid && write_port && write_address == 8'h00 &&
                    !write_data[7] && |write_data[5:0];
        prewarm_b = write_valid && !write_port && write_address == 8'h10 &&
                    write_data[7] && !write_data[0];
        prewarm_missing = 1'b0;
        need_valid = 1'b0;
        need_required = 1'b0;
        need_space_b = 1'b0;
        need_logical = 20'd0;
        a_need_valid = 1'b0;
        a_need_required = 1'b0;
        a_need_logical = adpcma_addr;
        b_need_valid = 1'b0;
        b_need_required = 1'b0;
        b_need_logical = adpcmb_addr[19:0];

        if (prewarm_a) begin
            for (integer voice = 0; voice < 6; voice = voice + 1) begin
                if (write_data[voice] && !contains(1'b0, {start_a[voice][11:0], 8'd0}) &&
                    !need_valid) begin
                    need_valid = 1'b1;
                    need_required = 1'b1;
                    need_space_b = 1'b0;
                    need_logical = {start_a[voice][11:0], 8'd0};
                end else if (write_data[voice] &&
                             !contains(1'b0, {start_a[voice][11:0], 8'd0} + 20'd1) &&
                             !need_valid) begin
                    need_valid = 1'b1;
                    need_required = 1'b1;
                    need_space_b = 1'b0;
                    need_logical = {start_a[voice][11:0], 8'd0} + 20'd1;
                end
                if (write_data[voice] &&
                    (!contains(1'b0, {start_a[voice][11:0], 8'd0}) ||
                     !contains(1'b0, {start_a[voice][11:0], 8'd0} + 20'd1)))
                    prewarm_missing = 1'b1;
            end
        end else if (prewarm_b) begin
            if (!contains(1'b1, {start_b[11:0], 8'd0})) begin
                need_valid = 1'b1;
                need_required = 1'b1;
                need_space_b = 1'b1;
                need_logical = {start_b[11:0], 8'd0};
            end else if (!contains(1'b1, {start_b[11:0], 8'd0} + 20'd1)) begin
                need_valid = 1'b1;
                need_required = 1'b1;
                need_space_b = 1'b1;
                need_logical = {start_b[11:0], 8'd0} + 20'd1;
            end
            prewarm_missing = need_valid;
        end

        if (!adpcma_roe_n && !a_current_hit) begin
            a_need_valid = 1'b1;
            a_need_required = 1'b1;
            a_need_logical = adpcma_addr;
        end else if (a_current_hit && !a_next_hit) begin
            a_need_valid = 1'b1;
            a_need_logical = adpcma_addr + 20'd1;
        end else if (!a_current_hit) begin
            a_need_valid = 1'b1;
            a_need_logical = adpcma_addr;
        end

        if (!adpcmb_roe_n && !b_current_hit) begin
            b_need_valid = 1'b1;
            b_need_required = 1'b1;
            b_need_logical = adpcmb_addr[19:0];
        end else if (b_current_hit && !b_next_hit) begin
            b_need_valid = 1'b1;
            b_need_logical = adpcmb_addr[19:0] + 20'd1;
        end else if (!b_current_hit) begin
            b_need_valid = 1'b1;
            b_need_logical = adpcmb_addr[19:0];
        end

        // Required current bytes outrank speculative +1 prefetch.  If both
        // active pins need the same class of service, alternate the accepted
        // lane.  An idle lane never displaces an actively decoding lane.
        if (!need_valid && (a_need_valid || b_need_valid)) begin
            need_valid = 1'b1;
            if (a_need_required && b_need_required) begin
                need_required = 1'b1;
                need_space_b = prefer_b;
                need_logical = prefer_b ? b_need_logical : a_need_logical;
            end else if (a_need_required) begin
                need_required = 1'b1;
                need_space_b = 1'b0;
                need_logical = a_need_logical;
            end else if (b_need_required) begin
                need_required = 1'b1;
                need_space_b = 1'b1;
                need_logical = b_need_logical;
            end else if (a_need_valid && b_need_valid &&
                         !adpcma_roe_n && !adpcmb_roe_n) begin
                need_space_b = prefer_b;
                need_logical = prefer_b ? b_need_logical : a_need_logical;
            end else if (a_need_valid && !adpcma_roe_n) begin
                need_space_b = 1'b0;
                need_logical = a_need_logical;
            end else if (b_need_valid && !adpcmb_roe_n) begin
                need_space_b = 1'b1;
                need_logical = b_need_logical;
            end else if (a_need_valid) begin
                need_space_b = 1'b0;
                need_logical = a_need_logical;
            end else begin
                need_space_b = 1'b1;
                need_logical = b_need_logical;
            end
        end

        write_allow = !(prewarm_a || prewarm_b) || !prewarm_missing;
        map_space_b = need_space_b;
        map_logical_addr = need_logical;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            request_pending <= 1'b0;
            request_space_b <= 1'b0;
            request_logical <= 20'd0;
            offer_valid <= 1'b0;
            offer_space_b <= 1'b0;
            offer_logical <= 20'd0;
            offer_file_addr <= '0;
            prefer_b <= 1'b0;
            replace_ptr <= '0;
            request_count <= 32'd0;
            response_count <= 32'd0;
            adpcma_request_count <= 32'd0;
            adpcmb_request_count <= 32'd0;
            adpcma_fetch_requests <= 32'd0;
            adpcma_fetch_responses <= 32'd0;
            adpcmb_fetch_requests <= 32'd0;
            adpcmb_fetch_responses <= 32'd0;
            adpcma_underflow <= 1'b0;
            adpcmb_underflow <= 1'b0;
            range_error <= 1'b0;
            stale_response <= 1'b0;
            last_logical_addr <= 20'd0;
            adpcma_last_address <= 20'd0;
            adpcmb_last_address <= 20'd0;
            start_b <= 16'd0;
            for (i = 0; i < 6; i = i + 1)
                start_a[i] <= 16'd0;
            for (i = 0; i < ENTRIES; i = i + 1) begin
                cache_valid[i] <= 1'b0;
                cache_space_b[i] <= 1'b0;
                cache_logical[i] <= 20'd0;
                cache_data[i] <= 8'd0;
            end
        end else begin
            if (active && need_valid && map_hit && !offer_valid &&
                !request_pending && !mem_ready) begin
                offer_valid <= 1'b1;
                offer_space_b <= need_space_b;
                offer_logical <= need_logical;
                offer_file_addr <= map_file_addr;
            end
            if (write_accept) begin
                if (write_port && write_address >= 8'h10 && write_address <= 8'h15)
                    start_a[write_address[2:0]][7:0] <= write_data;
                if (write_port && write_address >= 8'h18 && write_address <= 8'h1d)
                    start_a[write_address[2:0]][15:8] <= write_data;
                if (!write_port && write_address == 8'h12)
                    start_b[7:0] <= write_data;
                if (!write_port && write_address == 8'h13)
                    start_b[15:8] <= write_data;
            end
            if (mem_req && mem_ready) begin
                offer_valid <= 1'b0;
                request_pending <= 1'b1;
                request_space_b <= accepted_space_b;
                request_logical <= accepted_logical;
                request_count <= request_count + 32'd1;
                last_logical_addr <= accepted_logical;
                prefer_b <= !accepted_space_b;
                if (accepted_space_b)
                    adpcmb_fetch_requests <= adpcmb_fetch_requests + 32'd1;
                else
                    adpcma_fetch_requests <= adpcma_fetch_requests + 32'd1;
            end
            if (mem_valid) begin
                if (!request_pending)
                    stale_response <= 1'b1;
                else begin
                    request_pending <= 1'b0;
                    response_count <= response_count + 32'd1;
                    if (request_space_b)
                        adpcmb_fetch_responses <= adpcmb_fetch_responses + 32'd1;
                    else
                        adpcma_fetch_responses <= adpcma_fetch_responses + 32'd1;
                    cache_valid[replace_ptr] <= 1'b1;
                    cache_space_b[replace_ptr] <= request_space_b;
                    cache_logical[replace_ptr] <= request_logical;
                    cache_data[replace_ptr] <= mem_data;
                    replace_ptr <= replace_ptr + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
                end
            end
            if (active && !adpcma_roe_n) begin
                adpcma_request_count <= adpcma_request_count + 32'd1;
                adpcma_last_address <= adpcma_addr;
                if (!a_current_hit || adpcma_bank != 0)
                    adpcma_underflow <= 1'b1;
            end
            if (active && !adpcmb_roe_n) begin
                adpcmb_request_count <= adpcmb_request_count + 32'd1;
                adpcmb_last_address <= adpcmb_addr[19:0];
                if (!b_current_hit || |adpcmb_addr[23:19])
                    adpcmb_underflow <= 1'b1;
            end
            if (active && need_required && need_valid && !map_hit)
                range_error <= 1'b1;
        end
    end
endmodule

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
`ifdef YM2610_GF_RG1_PROBE
    ,output logic                  range_fault_valid,
    output logic [19:0]           range_fault_addr,
    output logic                  range_fault_current
`endif
);
    localparam int PTR_WIDTH = $clog2(ENTRIES);
    localparam logic [PTR_WIDTH-1:0] LAST_SLOT = PTR_WIDTH'(ENTRIES - 1);
    logic cache_valid [0:ENTRIES-1];
    logic cache_space_b [0:ENTRIES-1];
    logic [19:0] cache_logical [0:ENTRIES-1];
    logic [7:0] cache_data [0:ENTRIES-1];
    logic [PTR_WIDTH-1:0] replace_ptr;
    // A key-on is released only after both startup bytes for every selected
    // voice are resident.  Keep those cache slots pinned for that voice until
    // an accepted stop, re-key, or reset.  The cache has no channel tag on the
    // multiplexed ROM bus, so a matching presentation alone cannot prove that
    // this particular voice consumed its prepared byte.
    logic [5:0] prepared_a_valid;
    logic [PTR_WIDTH-1:0] prepared_a_current_slot [0:5];
    logic [PTR_WIDTH-1:0] prepared_a_next_slot [0:5];
    // Parser acceptance precedes JT10 command application.  Keep the prior
    // two generations as well when a voice is stopped or re-keyed.  Three
    // total generations cover the production bus/JT command-to-first-read
    // pipeline without becoming an accumulating log.
    logic [5:0] retired_a_valid;
    logic [PTR_WIDTH-1:0] retired_a_current_slot [0:5];
    logic [PTR_WIDTH-1:0] retired_a_next_slot [0:5];
    logic [5:0] retired2_a_valid;
    logic [PTR_WIDTH-1:0] retired2_a_current_slot [0:5];
    logic [PTR_WIDTH-1:0] retired2_a_next_slot [0:5];
    // JT10 presents the six ADPCM-A lanes round-robin on one ROM address bus.
    // The last six active-read address transitions therefore contain the
    // current byte of every distinct live lane (equal adjacent lane addresses
    // need only one copy).
    // Retaining this union makes streaming current/+1 protection independent
    // of which lane happens to be visible when a memory response arrives.
    logic [5:0] live_a_valid;
    logic [19:0] live_a_addr [0:5];
    logic [5:0] live_a_current_slot_valid;
    logic [5:0] live_a_next_slot_valid;
    logic [PTR_WIDTH-1:0] live_a_current_slot [0:5];
    logic [PTR_WIDTH-1:0] live_a_next_slot [0:5];
    logic [ENTRIES-1:0] live_a_slots;
    logic live_a_transition;
    // ADPCM-B has one channel, but its ROM output-enable is a pulse.  Retain
    // the last observed byte/+1 pair between pulses so redirecting an A victim
    // cannot evict data that B still presents to the decoder.
    logic live_b_valid;
    logic [19:0] live_b_addr;
    logic live_b_current_slot_valid;
    logic live_b_next_slot_valid;
    logic [PTR_WIDTH-1:0] live_b_current_slot;
    logic [PTR_WIDTH-1:0] live_b_next_slot;
    logic [ENTRIES-1:0] live_b_slots;
    logic live_b_transition;
    logic [ENTRIES-1:0] live_a_victim_slots;
    logic [ENTRIES-1:0] live_b_victim_slots;
    logic [ENTRIES-1:0] protected_slots;
    logic [PTR_WIDTH-1:0] replacement_slot;
    logic replacement_found;
    logic response_live_a;
    logic response_live_b;
    logic [5:0] response_a_current_lane;
    logic [5:0] response_a_next_lane;
    logic response_b_current;
    logic response_b_next;
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
`ifdef YM2610_GF_RG1_PROBE
    // Diagnostic-only source tag for the final selected need.  A prewarm
    // need has priority over decoder service and must remain distinguishable.
    logic need_current_a;
`endif
    logic a_current_hit, a_next_hit, b_current_hit, b_next_hit;
    logic [7:0] a_current_data, b_current_data;
    logic [PTR_WIDTH-1:0] a_current_slot, a_next_slot;
    logic [PTR_WIDTH-1:0] b_current_slot, b_next_slot;
    logic [5:0] prewarm_a_current_hit, prewarm_a_next_hit;
    logic [PTR_WIDTH-1:0] prewarm_a_current_slot [0:5];
    logic [PTR_WIDTH-1:0] prewarm_a_next_slot [0:5];
    logic prewarm_b_current_hit, prewarm_b_next_hit;
    logic prewarm_a;
    logic prewarm_b;
    logic prewarm_missing;
    logic a_need_valid, a_need_required;
    logic b_need_valid, b_need_required;
    logic [19:0] a_need_logical, b_need_logical;
    integer i;

    // Protection is represented by resident slot indices.  Address/tag
    // comparison happens only in the ordinary cache lookup paths; the victim
    // scan consumes one protected bit per candidate and never re-compares a
    // candidate tag against every live or prepared address.
    always_comb begin
        live_a_transition = active && !adpcma_roe_n &&
                            (!live_a_valid[0] ||
                             live_a_addr[0] != adpcma_addr);
        live_b_transition = active && !adpcmb_roe_n &&
                            (!live_b_valid ||
                             live_b_addr != adpcmb_addr[19:0]);

        live_a_slots = '0;
        for (integer live_lane = 0; live_lane < 6;
             live_lane = live_lane + 1) begin
            if (live_a_current_slot_valid[live_lane])
                live_a_slots[live_a_current_slot[live_lane]] = 1'b1;
            if (live_a_next_slot_valid[live_lane])
                live_a_slots[live_a_next_slot[live_lane]] = 1'b1;
        end
        live_b_slots = '0;
        if (live_b_current_slot_valid)
            live_b_slots[live_b_current_slot] = 1'b1;
        if (live_b_next_slot_valid)
            live_b_slots[live_b_next_slot] = 1'b1;

        // A replacement on the same edge as a presentation transition sees
        // the post-transition six-lane union: new lane plus history 0..4.
        live_a_victim_slots = live_a_slots;
        if (!active) begin
            live_a_victim_slots = '0;
        end else if (live_a_transition) begin
            live_a_victim_slots = '0;
            if (a_current_hit)
                live_a_victim_slots[a_current_slot] = 1'b1;
            if (a_next_hit)
                live_a_victim_slots[a_next_slot] = 1'b1;
            for (integer victim_lane = 0; victim_lane < 5;
                 victim_lane = victim_lane + 1) begin
                if (live_a_current_slot_valid[victim_lane])
                    live_a_victim_slots[
                        live_a_current_slot[victim_lane]] = 1'b1;
                if (live_a_next_slot_valid[victim_lane])
                    live_a_victim_slots[
                        live_a_next_slot[victim_lane]] = 1'b1;
            end
        end

        live_b_victim_slots = live_b_slots;
        if (!active) begin
            live_b_victim_slots = '0;
        end else if (live_b_transition) begin
            live_b_victim_slots = '0;
            if (b_current_hit)
                live_b_victim_slots[b_current_slot] = 1'b1;
            if (b_next_hit)
                live_b_victim_slots[b_next_slot] = 1'b1;
        end
    end

    always_comb begin
        protected_slots = live_a_victim_slots | live_b_victim_slots;
        for (integer voice = 0; voice < 6; voice = voice + 1) begin
            if (prepared_a_valid[voice]) begin
                protected_slots[prepared_a_current_slot[voice]] = 1'b1;
                protected_slots[prepared_a_next_slot[voice]] = 1'b1;
            end
            if (retired_a_valid[voice]) begin
                protected_slots[retired_a_current_slot[voice]] = 1'b1;
                protected_slots[retired_a_next_slot[voice]] = 1'b1;
            end
            if (retired2_a_valid[voice]) begin
                protected_slots[retired2_a_current_slot[voice]] = 1'b1;
                protected_slots[retired2_a_next_slot[voice]] = 1'b1;
            end

            // Preserve same-edge key-on atomicity with already-resolved slot
            // references instead of another candidate-wide tag match.
            if (write_accept && write_port && write_address == 8'h00 &&
                !write_data[7] && write_data[voice]) begin
                if (prewarm_a_current_hit[voice])
                    protected_slots[
                        prewarm_a_current_slot[voice]] = 1'b1;
                if (prewarm_a_next_hit[voice])
                    protected_slots[prewarm_a_next_slot[voice]] = 1'b1;
            end
        end
    end

    // Deterministic round-robin victim selection.  Command generations cover
    // at most 36 slots, the six-lane live union at most 12, active ADPCM-B at
    // most two, and a same-edge six-voice key-on at most 12.  The production
    // 64-entry cache therefore has progress even at the 62-slot upper bound.
    // If a smaller parameterization protects every slot, replacement_found
    // remains low rather than violating a live reservation.
    always_comb begin
        replacement_slot = replace_ptr;
        replacement_found = 1'b0;
        for (integer victim_offset = 0; victim_offset < ENTRIES;
             victim_offset = victim_offset + 1) begin
            integer candidate_index;
            logic [PTR_WIDTH-1:0] candidate_slot;

            candidate_index = int'(replace_ptr) + victim_offset;
            if (candidate_index >= ENTRIES)
                candidate_index = candidate_index - ENTRIES;
            candidate_slot = candidate_index[PTR_WIDTH-1:0];
            if ((mem_req || request_pending || mem_valid) &&
                !replacement_found && !protected_slots[candidate_slot]) begin
                replacement_slot = candidate_slot;
                replacement_found = 1'b1;
            end
        end
    end

    // A response inherits live status from captured logical ownership.  The
    // lane-match vector also installs the new resident slot into the correct
    // post-transition history entry on the response edge.
    always_comb begin
        response_a_current_lane = 6'd0;
        response_a_next_lane = 6'd0;
        if (active && !request_space_b) begin
            if (live_a_transition) begin
                if (request_logical == adpcma_addr)
                    response_a_current_lane[0] = 1'b1;
                if (request_logical == adpcma_addr + 20'd1)
                    response_a_next_lane[0] = 1'b1;
                for (integer response_lane = 0; response_lane < 5;
                     response_lane = response_lane + 1) begin
                    if (live_a_valid[response_lane] &&
                        request_logical == live_a_addr[response_lane])
                        response_a_current_lane[response_lane + 1] = 1'b1;
                    if (live_a_valid[response_lane] &&
                        request_logical == live_a_addr[response_lane] + 20'd1)
                        response_a_next_lane[response_lane + 1] = 1'b1;
                end
            end else begin
                for (integer response_lane = 0; response_lane < 6;
                     response_lane = response_lane + 1) begin
                    if (live_a_valid[response_lane] &&
                        request_logical == live_a_addr[response_lane])
                        response_a_current_lane[response_lane] = 1'b1;
                    if (live_a_valid[response_lane] &&
                        request_logical == live_a_addr[response_lane] + 20'd1)
                        response_a_next_lane[response_lane] = 1'b1;
                end
            end
        end
        response_live_a = |response_a_current_lane |
                          |response_a_next_lane;

        response_b_current = 1'b0;
        response_b_next = 1'b0;
        if (active && request_space_b) begin
            if (live_b_transition) begin
                response_b_current = request_logical == adpcmb_addr[19:0];
                response_b_next =
                    request_logical == adpcmb_addr[19:0] + 20'd1;
            end else if (live_b_valid) begin
                response_b_current = request_logical == live_b_addr;
                response_b_next = request_logical == live_b_addr + 20'd1;
            end
        end
        response_live_b = response_b_current | response_b_next;
    end

    // Resolve all startup-byte hits and resident slots once.  These results
    // serve both write_allow and the accepted key-on snapshot; the old design
    // repeated the same 20-bit tag searches again in protection logic.
    always_comb begin
        prewarm_a_current_hit = 6'd0;
        prewarm_a_next_hit = 6'd0;
        prewarm_b_current_hit = 1'b0;
        prewarm_b_next_hit = 1'b0;
        for (integer voice = 0; voice < 6; voice = voice + 1) begin
            prewarm_a_current_slot[voice] = '0;
            prewarm_a_next_slot[voice] = '0;
        end
        for (integer startup_slot = 0; startup_slot < ENTRIES;
             startup_slot = startup_slot + 1) begin
            if (cache_valid[startup_slot]) begin
                if (cache_space_b[startup_slot]) begin
                    if (cache_logical[startup_slot] ==
                        {start_b[11:0], 8'd0}) begin
                        prewarm_b_current_hit = 1'b1;
                    end
                    if (cache_logical[startup_slot] ==
                        {start_b[11:0], 8'd0} + 20'd1) begin
                        prewarm_b_next_hit = 1'b1;
                    end
                end else begin
                    for (integer voice = 0; voice < 6;
                         voice = voice + 1) begin
                        if (cache_logical[startup_slot] ==
                            {start_a[voice][11:0], 8'd0}) begin
                            prewarm_a_current_hit[voice] = 1'b1;
                            prewarm_a_current_slot[voice] =
                                startup_slot[PTR_WIDTH-1:0];
                        end
                        if (cache_logical[startup_slot] ==
                            {start_a[voice][11:0], 8'd0} + 20'd1) begin
                            prewarm_a_next_hit[voice] = 1'b1;
                            prewarm_a_next_slot[voice] =
                                startup_slot[PTR_WIDTH-1:0];
                        end
                    end
                end
            end
        end
    end

    always_comb begin
        a_current_hit = 1'b0;
        a_next_hit = 1'b0;
        b_current_hit = 1'b0;
        b_next_hit = 1'b0;
        a_current_data = 8'd0;
        b_current_data = 8'd0;
        a_current_slot = '0;
        a_next_slot = '0;
        b_current_slot = '0;
        b_next_slot = '0;
        occupancy = 7'd0;
        for (integer lookup_i = 0; lookup_i < ENTRIES; lookup_i = lookup_i + 1) begin
            if (cache_valid[lookup_i]) begin
                occupancy = occupancy + 7'd1;
                if (!cache_space_b[lookup_i] &&
                    cache_logical[lookup_i] == adpcma_addr) begin
                    a_current_hit = 1'b1;
                    a_current_data = cache_data[lookup_i];
                    a_current_slot = lookup_i[PTR_WIDTH-1:0];
                end
                if (!cache_space_b[lookup_i] &&
                    cache_logical[lookup_i] == adpcma_addr + 20'd1) begin
                    a_next_hit = 1'b1;
                    a_next_slot = lookup_i[PTR_WIDTH-1:0];
                end
                if (cache_space_b[lookup_i] &&
                    cache_logical[lookup_i] == adpcmb_addr[19:0]) begin
                    b_current_hit = 1'b1;
                    b_current_data = cache_data[lookup_i];
                    b_current_slot = lookup_i[PTR_WIDTH-1:0];
                end
                if (cache_space_b[lookup_i] &&
                    cache_logical[lookup_i] == adpcmb_addr[19:0] + 20'd1) begin
                    b_next_hit = 1'b1;
                    b_next_slot = lookup_i[PTR_WIDTH-1:0];
                end
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
`ifdef YM2610_GF_RG1_PROBE
        need_current_a = 1'b0;
`endif
        a_need_valid = 1'b0;
        a_need_required = 1'b0;
        a_need_logical = adpcma_addr;
        b_need_valid = 1'b0;
        b_need_required = 1'b0;
        b_need_logical = adpcmb_addr[19:0];

        if (prewarm_a) begin
            for (integer voice = 0; voice < 6; voice = voice + 1) begin
                if (write_data[voice] && !prewarm_a_current_hit[voice] &&
                    !need_valid) begin
                    need_valid = 1'b1;
                    need_required = 1'b1;
                    need_space_b = 1'b0;
                    need_logical = {start_a[voice][11:0], 8'd0};
                end else if (write_data[voice] &&
                             !prewarm_a_next_hit[voice] &&
                             !need_valid) begin
                    need_valid = 1'b1;
                    need_required = 1'b1;
                    need_space_b = 1'b0;
                    need_logical = {start_a[voice][11:0], 8'd0} + 20'd1;
                end
                if (write_data[voice] &&
                    (!prewarm_a_current_hit[voice] ||
                     !prewarm_a_next_hit[voice]))
                    prewarm_missing = 1'b1;
            end
        end else if (prewarm_b) begin
            if (!prewarm_b_current_hit) begin
                need_valid = 1'b1;
                need_required = 1'b1;
                need_space_b = 1'b1;
                need_logical = {start_b[11:0], 8'd0};
            end else if (!prewarm_b_next_hit) begin
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
`ifdef YM2610_GF_RG1_PROBE
                need_current_a = 1'b1;
`endif
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
            prepared_a_valid <= 6'd0;
            retired_a_valid <= 6'd0;
            retired2_a_valid <= 6'd0;
            live_a_valid <= 6'd0;
            live_a_current_slot_valid <= 6'd0;
            live_a_next_slot_valid <= 6'd0;
            live_b_valid <= 1'b0;
            live_b_addr <= 20'd0;
            live_b_current_slot_valid <= 1'b0;
            live_b_next_slot_valid <= 1'b0;
            live_b_current_slot <= '0;
            live_b_next_slot <= '0;
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
`ifdef YM2610_GF_RG1_PROBE
            range_fault_valid <= 1'b0;
            range_fault_addr <= 20'd0;
            range_fault_current <= 1'b0;
`endif
            start_b <= 16'd0;
            for (i = 0; i < 6; i = i + 1)
                start_a[i] <= 16'd0;
            for (i = 0; i < 6; i = i + 1) begin
                prepared_a_current_slot[i] <= '0;
                prepared_a_next_slot[i] <= '0;
                retired_a_current_slot[i] <= '0;
                retired_a_next_slot[i] <= '0;
                retired2_a_current_slot[i] <= '0;
                retired2_a_next_slot[i] <= '0;
                live_a_addr[i] <= 20'd0;
                live_a_current_slot[i] <= '0;
                live_a_next_slot[i] <= '0;
            end
            for (i = 0; i < ENTRIES; i = i + 1) begin
                cache_valid[i] <= 1'b0;
                cache_space_b[i] <= 1'b0;
                cache_logical[i] <= 20'd0;
                cache_data[i] <= 8'd0;
            end
        end else begin
            if (!active) begin
                live_a_valid <= 6'd0;
                live_a_current_slot_valid <= 6'd0;
                live_a_next_slot_valid <= 6'd0;
            end else if (live_a_transition) begin
                for (i = 5; i > 0; i = i - 1) begin
                    live_a_valid[i] <= live_a_valid[i-1];
                    live_a_addr[i] <= live_a_addr[i-1];
                    live_a_current_slot_valid[i] <=
                        live_a_current_slot_valid[i-1];
                    live_a_next_slot_valid[i] <=
                        live_a_next_slot_valid[i-1];
                    live_a_current_slot[i] <= live_a_current_slot[i-1];
                    live_a_next_slot[i] <= live_a_next_slot[i-1];
                end
                live_a_valid[0] <= 1'b1;
                live_a_addr[0] <= adpcma_addr;
                live_a_current_slot_valid[0] <= a_current_hit;
                live_a_next_slot_valid[0] <= a_next_hit;
                live_a_current_slot[0] <= a_current_slot;
                live_a_next_slot[0] <= a_next_slot;
            end
            if (!active) begin
                live_b_valid <= 1'b0;
                live_b_current_slot_valid <= 1'b0;
                live_b_next_slot_valid <= 1'b0;
            end else if (live_b_transition) begin
                live_b_valid <= 1'b1;
                live_b_addr <= adpcmb_addr[19:0];
                live_b_current_slot_valid <= b_current_hit;
                live_b_next_slot_valid <= b_next_hit;
                live_b_current_slot <= b_current_slot;
                live_b_next_slot <= b_next_slot;
            end
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
                if (write_port && write_address == 8'h00) begin
                    for (i = 0; i < 6; i = i + 1) begin
                        if (write_data[i]) begin
                            if (prepared_a_valid[i]) begin
                                retired2_a_valid[i] <= retired_a_valid[i];
                                retired2_a_current_slot[i] <=
                                    retired_a_current_slot[i];
                                retired2_a_next_slot[i] <=
                                    retired_a_next_slot[i];
                                retired_a_valid[i] <= 1'b1;
                                retired_a_current_slot[i] <=
                                    prepared_a_current_slot[i];
                                retired_a_next_slot[i] <=
                                    prepared_a_next_slot[i];
                            end
                            if (write_data[7]) begin
                                prepared_a_valid[i] <= 1'b0;
                            end else begin
                                prepared_a_valid[i] <= 1'b1;
                                prepared_a_current_slot[i] <=
                                    prewarm_a_current_slot[i];
                                prepared_a_next_slot[i] <=
                                    prewarm_a_next_slot[i];
                            end
                        end
                    end
                end
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
                    if (replacement_found) begin
                        cache_valid[replacement_slot] <= 1'b1;
                        cache_space_b[replacement_slot] <= request_space_b;
                        cache_logical[replacement_slot] <= request_logical;
                        cache_data[replacement_slot] <= mem_data;
                        if (response_live_a) begin
                            for (i = 0; i < 6; i = i + 1) begin
                                if (response_a_current_lane[i]) begin
                                    live_a_current_slot_valid[i] <= 1'b1;
                                    live_a_current_slot[i] <= replacement_slot;
                                end
                                if (response_a_next_lane[i]) begin
                                    live_a_next_slot_valid[i] <= 1'b1;
                                    live_a_next_slot[i] <= replacement_slot;
                                end
                            end
                        end
                        if (response_live_b) begin
                            if (response_b_current) begin
                                live_b_current_slot_valid <= 1'b1;
                                live_b_current_slot <= replacement_slot;
                            end
                            if (response_b_next) begin
                                live_b_next_slot_valid <= 1'b1;
                                live_b_next_slot <= replacement_slot;
                            end
                        end
                        if (replacement_slot == LAST_SLOT)
                            replace_ptr <= '0;
                        else
                            replace_ptr <= replacement_slot +
                                {{(PTR_WIDTH-1){1'b0}}, 1'b1};
                    end
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
`ifdef YM2610_GF_RG1_PROBE
            if (active && need_required && need_valid && !map_hit &&
                !range_fault_valid) begin
                range_fault_valid <= 1'b1;
                range_fault_addr <= need_logical;
                range_fault_current <= need_current_a;
            end
`endif
        end
    end
endmodule

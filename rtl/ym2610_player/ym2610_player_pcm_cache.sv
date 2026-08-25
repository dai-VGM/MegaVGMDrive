`timescale 1ns/1ps

// Shared zero-wait PCM cache. ADPCM-A tags retain JT10's complete logical
// {bank[3:0],addr[19:0]} address. ADPCM-B uses the same split 24-bit tag.
// Live decoder lookup remains parallel; only parser key-on prewarm is scanned
// one resident slot at a time.
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

    output logic                  map_req_valid,
    input  logic                  map_req_ready,
    output logic                  map_space_b,
    output logic [23:0]           map_logical_addr,
    input  logic                  map_rsp_valid,
    input  logic                  map_rsp_hit,
    input  logic [ADDR_WIDTH-1:0] map_rsp_file_addr,

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
`ifdef YM2610B_METAL_SLUG_REJECT_UART_LAB
    ,output logic                 lab_a_current_hit,
    output logic                  lab_a_next_hit,
    output logic                  lab_b_current_hit,
    output logic                  lab_b_next_hit,
    output logic                  lab_request_active,
    output logic                  lab_request_pending,
    output logic                  lab_request_space_b,
    output logic [23:0]           lab_request_logical,
    output logic                  lab_response_valid,
    output logic                  lab_response_hit,
    output logic [ADDR_WIDTH-1:0] lab_response_file_addr,
    output logic                  lab_response_space_b,
    output logic                  lab_last_fill_valid,
    output logic                  lab_last_fill_space_b,
    output logic [23:0]           lab_last_fill_logical
`endif
`ifdef YM2610_GF_RG1_PROBE
    ,output logic                 range_fault_valid,
    output logic [19:0]           range_fault_addr,
    output logic                  range_fault_current
`endif
);
    localparam int PTR_WIDTH = $clog2(ENTRIES);
    localparam logic [PTR_WIDTH-1:0] LAST_SLOT = PTR_WIDTH'(ENTRIES - 1);

    logic cache_valid [0:ENTRIES-1];
    logic cache_space_b [0:ENTRIES-1];
    logic [19:0] cache_logical [0:ENTRIES-1];
    logic [3:0] cache_bank [0:ENTRIES-1];
    logic [7:0] cache_data [0:ENTRIES-1];
    logic [PTR_WIDTH-1:0] replace_ptr;

    // Slot-index protection from ba6f795. No victim tag comparison is added.
    logic [5:0] prepared_a_valid;
    logic [PTR_WIDTH-1:0] prepared_a_current_slot [0:5];
    logic [PTR_WIDTH-1:0] prepared_a_next_slot [0:5];
    logic [5:0] retired_a_valid;
    logic [PTR_WIDTH-1:0] retired_a_current_slot [0:5];
    logic [PTR_WIDTH-1:0] retired_a_next_slot [0:5];
    logic [5:0] retired2_a_valid;
    logic [PTR_WIDTH-1:0] retired2_a_current_slot [0:5];
    logic [PTR_WIDTH-1:0] retired2_a_next_slot [0:5];

    logic [5:0] live_a_valid;
    logic [19:0] live_a_addr [0:5];
    logic [3:0] live_a_bank [0:5];
    logic [5:0] live_a_current_slot_valid;
    logic [5:0] live_a_next_slot_valid;
    logic [PTR_WIDTH-1:0] live_a_current_slot [0:5];
    logic [PTR_WIDTH-1:0] live_a_next_slot [0:5];
    logic [ENTRIES-1:0] live_a_slots, live_a_victim_slots;
    logic live_a_transition;

    logic live_b_valid;
    logic [23:0] live_b_addr;
    logic live_b_current_slot_valid, live_b_next_slot_valid;
    logic [PTR_WIDTH-1:0] live_b_current_slot, live_b_next_slot;
    logic [ENTRIES-1:0] live_b_slots, live_b_victim_slots;
    logic live_b_transition;

    logic [ENTRIES-1:0] protected_slots;
    logic [PTR_WIDTH-1:0] replacement_slot;
    logic replacement_found;

    logic [15:0] start_a [0:5];
    logic [15:0] start_b, end_b;
    // Serialized selected-voice prewarm.
    typedef enum logic [2:0] {
        PW_IDLE, PW_WAIT_IDLE, PW_SCAN, PW_REFILL_CURRENT,
        PW_REFILL_NEXT, PW_DONE
    } prewarm_state_t;
    prewarm_state_t prewarm_state;
    logic prewarm_space_b;
    logic [5:0] prewarm_remaining;
    logic [2:0] prewarm_voice;
    logic [PTR_WIDTH-1:0] prewarm_scan_slot;
    logic [15:0] prewarm_start_a [0:5];
    logic [15:0] prewarm_start_b;
    logic [5:0] prewarm_a_current_hit, prewarm_a_next_hit;
    logic [PTR_WIDTH-1:0] prewarm_a_current_slot [0:5];
    logic [PTR_WIDTH-1:0] prewarm_a_next_slot [0:5];
    logic prewarm_b_current_hit, prewarm_b_next_hit;
    logic [2:0] prewarm_b_offset;
    logic [PTR_WIDTH-1:0] prewarm_b_current_slot, prewarm_b_next_slot;
    logic [7:0] prewarm_b_runway_valid;
    logic [PTR_WIDTH-1:0] prewarm_b_runway_slot [0:7];
    logic prewarm_b_repeat;
    logic repeat_b_protected;
    logic [PTR_WIDTH-1:0] repeat_b_runway_slot [0:7];
    logic [23:0] repeat_b_start_logical, repeat_b_end_logical;
    logic prewarm_a, prewarm_b;
    logic [23:0] prewarm_current_logical, prewarm_next_logical;
    logic prewarm_scan_current_match, prewarm_scan_next_match;
    logic prewarm_current_found, prewarm_next_found;
    logic [5:0] prewarm_remaining_after;
    logic prewarm_more_voices;
    logic [2:0] prewarm_next_voice;

    // Mapper request offer, accepted lookup, DDR offer, and DDR transaction.
    // Each layer captures ownership so every valid/ready contract is stable.
    logic lookup_offer_valid;
    logic lookup_offer_space_b, lookup_offer_required;
    logic [23:0] lookup_offer_logical;
    logic lookup_offer_prewarm, lookup_offer_prewarm_next;
    logic [2:0] lookup_offer_prewarm_voice;

    logic map_pending;
    logic map_pending_space_b, map_pending_required;
    logic [23:0] map_pending_logical;
    logic map_pending_prewarm, map_pending_prewarm_next;
    logic [2:0] map_pending_prewarm_voice;

    logic offer_valid;
    logic offer_space_b;
    logic [23:0] offer_logical;
    logic [ADDR_WIDTH-1:0] offer_file_addr;
    logic offer_prewarm, offer_prewarm_next;
    logic [2:0] offer_prewarm_voice;

    logic request_pending;
    logic request_space_b;
    logic [23:0] request_logical;
    logic request_prewarm, request_prewarm_next;
    logic [2:0] request_prewarm_voice;

    logic need_valid, need_required, need_space_b;
    logic [23:0] need_logical;
    logic need_prewarm, need_prewarm_next;
    logic [2:0] need_prewarm_voice;
    logic a_need_valid, a_need_required;
    logic b_need_valid, b_need_required;
    logic [23:0] a_need_logical, b_need_logical;
    logic prefer_b;

`ifdef YM2610_GF_RG1_PROBE
    logic need_current_a;
    logic map_pending_current_a;
`endif

    logic a_current_hit, a_next_hit, b_current_hit, b_next_hit;
    logic b_ahead_hit;
    logic [7:0] a_current_data, b_current_data;
    logic [PTR_WIDTH-1:0] a_current_slot, a_next_slot;
    logic [PTR_WIDTH-1:0] b_current_slot, b_next_slot;

    logic response_live_a, response_live_b;
    logic [5:0] response_a_current_lane, response_a_next_lane;
    logic response_b_current, response_b_next;
    integer i;

`ifdef YM2610B_METAL_SLUG_REJECT_UART_LAB
    // Existing cache decisions exported as passive lab observations. The
    // only added state records the most recent successful production fill.
    assign lab_a_current_hit = a_current_hit;
    assign lab_a_next_hit = a_next_hit;
    assign lab_b_current_hit = b_current_hit;
    assign lab_b_next_hit = b_next_hit;
    assign lab_request_active = map_req_valid;
    assign lab_request_pending = map_pending;
    assign lab_request_space_b = map_pending ? map_pending_space_b : map_space_b;
    assign lab_request_logical = map_pending ? map_pending_logical : map_logical_addr;
    assign lab_response_valid = map_rsp_valid;
    assign lab_response_hit = map_rsp_hit;
    assign lab_response_file_addr = map_rsp_file_addr;
    assign lab_response_space_b = map_pending_space_b;

    always_ff @(posedge clk) begin
        if (reset) begin
            lab_last_fill_valid <= 1'b0;
            lab_last_fill_space_b <= 1'b0;
            lab_last_fill_logical <= 24'd0;
        end else if (mem_valid && request_pending && replacement_found) begin
            lab_last_fill_valid <= 1'b1;
            lab_last_fill_space_b <= request_space_b;
            lab_last_fill_logical <= request_logical;
        end
    end
`endif

    wire [23:0] adpcma_logical = {adpcma_bank, adpcma_addr};
    wire [23:0] adpcma_next_logical = adpcma_logical + 24'd1;
    function automatic [23:0] b_offset_logical(
        input logic [23:0] base,
        input logic [3:0] offset
    );
        logic [24:0] extended;
        logic [24:0] wrapped;
        begin
            extended = {1'b0, base} + {21'd0, offset};
            wrapped = extended;
            if (repeat_b_protected && base >= repeat_b_start_logical &&
                base <= repeat_b_end_logical &&
                extended > {1'b0, repeat_b_end_logical})
                wrapped = {1'b0, repeat_b_start_logical} +
                          extended - {1'b0, repeat_b_end_logical} - 25'd1;
            b_offset_logical = wrapped[23:0];
        end
    endfunction

    wire [23:0] adpcmb_next_logical = b_offset_logical(adpcmb_addr, 4'd1);
    wire [23:0] adpcmb_ahead_logical = b_offset_logical(adpcmb_addr, 4'd7);
    wire pipeline_idle = !lookup_offer_valid && !map_pending &&
                         !offer_valid && !request_pending;

    function automatic [2:0] first_voice(input logic [5:0] mask);
        begin
            if (mask[0]) first_voice = 3'd0;
            else if (mask[1]) first_voice = 3'd1;
            else if (mask[2]) first_voice = 3'd2;
            else if (mask[3]) first_voice = 3'd3;
            else if (mask[4]) first_voice = 3'd4;
            else first_voice = 3'd5;
        end
    endfunction

    always_comb begin
        prewarm_a = write_valid && write_port && write_address == 8'h00 &&
                    !write_data[7] && |write_data[5:0];
        prewarm_b = write_valid && !write_port && write_address == 8'h10 &&
                    write_data[7] && !write_data[0];

        if (prewarm_space_b)
            prewarm_current_logical =
                {prewarm_start_b, 8'd0} +
                {21'd0, prewarm_b_offset};
        else
            prewarm_current_logical =
                {prewarm_start_a[prewarm_voice][15:12],
                 prewarm_start_a[prewarm_voice][11:0], 8'd0};
        prewarm_next_logical = prewarm_current_logical + 24'd1;

        prewarm_scan_current_match =
            cache_valid[prewarm_scan_slot] &&
            cache_space_b[prewarm_scan_slot] == prewarm_space_b &&
            cache_logical[prewarm_scan_slot] ==
              prewarm_current_logical[19:0] &&
            cache_bank[prewarm_scan_slot] ==
              prewarm_current_logical[23:20];
        prewarm_scan_next_match =
            cache_valid[prewarm_scan_slot] &&
            cache_space_b[prewarm_scan_slot] == prewarm_space_b &&
            cache_logical[prewarm_scan_slot] == prewarm_next_logical[19:0] &&
            cache_bank[prewarm_scan_slot] == prewarm_next_logical[23:20];

        if (prewarm_space_b) begin
            prewarm_current_found = prewarm_b_current_hit ||
                                    prewarm_scan_current_match;
            prewarm_next_found = prewarm_b_next_hit ||
                                 prewarm_scan_next_match;
        end else begin
            prewarm_current_found = prewarm_a_current_hit[prewarm_voice] ||
                                    prewarm_scan_current_match;
            prewarm_next_found = prewarm_a_next_hit[prewarm_voice] ||
                                 prewarm_scan_next_match;
        end

        prewarm_remaining_after = prewarm_remaining &
                                  ~(6'b000001 << prewarm_voice);
        prewarm_more_voices = |prewarm_remaining_after;
        prewarm_next_voice = first_voice(prewarm_remaining_after);
    end

    // Live decoder lookup stays fully parallel and zero-wait. A compares a
    // split bank tag plus low tag in both address spaces.
    always_comb begin
        a_current_hit = 1'b0;
        a_next_hit = 1'b0;
        b_current_hit = 1'b0;
        b_next_hit = 1'b0;
        b_ahead_hit = 1'b0;
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
                    cache_bank[lookup_i] == adpcma_logical[23:20] &&
                    cache_logical[lookup_i] == adpcma_logical[19:0]) begin
                    a_current_hit = 1'b1;
                    a_current_data = cache_data[lookup_i];
                    a_current_slot = lookup_i[PTR_WIDTH-1:0];
                end
                if (!cache_space_b[lookup_i] &&
                    cache_bank[lookup_i] == adpcma_next_logical[23:20] &&
                    cache_logical[lookup_i] == adpcma_next_logical[19:0]) begin
                    a_next_hit = 1'b1;
                    a_next_slot = lookup_i[PTR_WIDTH-1:0];
                end
                if (cache_space_b[lookup_i] &&
                    cache_bank[lookup_i] == adpcmb_addr[23:20] &&
                    cache_logical[lookup_i] == adpcmb_addr[19:0]) begin
                    b_current_hit = 1'b1;
                    b_current_data = cache_data[lookup_i];
                    b_current_slot = lookup_i[PTR_WIDTH-1:0];
                end
                if (cache_space_b[lookup_i] &&
                    cache_bank[lookup_i] == adpcmb_next_logical[23:20] &&
                    cache_logical[lookup_i] == adpcmb_next_logical[19:0]) begin
                    b_next_hit = 1'b1;
                    b_next_slot = lookup_i[PTR_WIDTH-1:0];
                end
                if (cache_space_b[lookup_i] &&
                    cache_bank[lookup_i] == adpcmb_ahead_logical[23:20] &&
                    cache_logical[lookup_i] == adpcmb_ahead_logical[19:0])
                    b_ahead_hit = 1'b1;
            end
        end
        adpcma_data = a_current_data;
        adpcmb_data = b_current_data;
    end

    always_comb begin
        live_a_transition = active && !adpcma_roe_n &&
            (!live_a_valid[0] || live_a_addr[0] != adpcma_addr ||
             live_a_bank[0] != adpcma_bank);
        live_b_transition = active && !adpcmb_roe_n &&
            (!live_b_valid || live_b_addr != adpcmb_addr);

        live_a_slots = '0;
        for (integer lane = 0; lane < 6; lane = lane + 1) begin
            if (live_a_current_slot_valid[lane])
                live_a_slots[live_a_current_slot[lane]] = 1'b1;
            if (live_a_next_slot_valid[lane])
                live_a_slots[live_a_next_slot[lane]] = 1'b1;
        end
        live_b_slots = '0;
        if (live_b_current_slot_valid)
            live_b_slots[live_b_current_slot] = 1'b1;
        if (live_b_next_slot_valid)
            live_b_slots[live_b_next_slot] = 1'b1;

        live_a_victim_slots = live_a_slots;
        if (!active) begin
            live_a_victim_slots = '0;
        end else if (live_a_transition) begin
            live_a_victim_slots = '0;
            if (a_current_hit) live_a_victim_slots[a_current_slot] = 1'b1;
            if (a_next_hit) live_a_victim_slots[a_next_slot] = 1'b1;
            for (integer lane = 0; lane < 5; lane = lane + 1) begin
                if (live_a_current_slot_valid[lane])
                    live_a_victim_slots[live_a_current_slot[lane]] = 1'b1;
                if (live_a_next_slot_valid[lane])
                    live_a_victim_slots[live_a_next_slot[lane]] = 1'b1;
            end
        end

        live_b_victim_slots = live_b_slots;
        if (!active) begin
            live_b_victim_slots = '0;
        end else if (live_b_transition) begin
            live_b_victim_slots = '0;
            if (b_current_hit) live_b_victim_slots[b_current_slot] = 1'b1;
            if (b_next_hit) live_b_victim_slots[b_next_slot] = 1'b1;
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
            // A found serialized-prewarm slot is protected immediately.
            if (prewarm_state != PW_IDLE) begin
                if (prewarm_a_current_hit[voice])
                    protected_slots[prewarm_a_current_slot[voice]] = 1'b1;
                if (prewarm_a_next_hit[voice])
                    protected_slots[prewarm_a_next_slot[voice]] = 1'b1;
            end
        end
        if (prewarm_state != PW_IDLE) begin
            if (prewarm_b_current_hit)
                protected_slots[prewarm_b_current_slot] = 1'b1;
            if (prewarm_b_next_hit)
                protected_slots[prewarm_b_next_slot] = 1'b1;
            for (integer byte_index = 0; byte_index < 8;
                 byte_index = byte_index + 1)
                if (prewarm_b_runway_valid[byte_index])
                    protected_slots[prewarm_b_runway_slot[byte_index]] = 1'b1;
        end
        if (repeat_b_protected)
            for (integer byte_index = 0; byte_index < 8;
                 byte_index = byte_index + 1)
                protected_slots[repeat_b_runway_slot[byte_index]] = 1'b1;
    end

    always_comb begin
        replacement_slot = replace_ptr;
        replacement_found = 1'b0;
        for (integer offset = 0; offset < ENTRIES; offset = offset + 1) begin
            integer candidate_index;
            logic [PTR_WIDTH-1:0] candidate_slot;
            candidate_index = int'(replace_ptr) + offset;
            if (candidate_index >= ENTRIES)
                candidate_index = candidate_index - ENTRIES;
            candidate_slot = candidate_index[PTR_WIDTH-1:0];
            if (((active && need_valid) || lookup_offer_valid || map_pending ||
                 offer_valid || request_pending || mem_valid) &&
                !replacement_found &&
                !protected_slots[candidate_slot]) begin
                replacement_slot = candidate_slot;
                replacement_found = 1'b1;
            end
        end
    end

    always_comb begin
        response_a_current_lane = 6'd0;
        response_a_next_lane = 6'd0;
        if (active && !request_space_b) begin
            if (live_a_transition) begin
                if (request_logical == adpcma_logical)
                    response_a_current_lane[0] = 1'b1;
                if (request_logical == adpcma_next_logical)
                    response_a_next_lane[0] = 1'b1;
                for (integer lane = 0; lane < 5; lane = lane + 1) begin
                    if (live_a_valid[lane] && request_logical ==
                        {live_a_bank[lane], live_a_addr[lane]})
                        response_a_current_lane[lane + 1] = 1'b1;
                    if (live_a_valid[lane] && request_logical ==
                        ({live_a_bank[lane], live_a_addr[lane]} + 24'd1))
                        response_a_next_lane[lane + 1] = 1'b1;
                end
            end else begin
                for (integer lane = 0; lane < 6; lane = lane + 1) begin
                    if (live_a_valid[lane] && request_logical ==
                        {live_a_bank[lane], live_a_addr[lane]})
                        response_a_current_lane[lane] = 1'b1;
                    if (live_a_valid[lane] && request_logical ==
                        ({live_a_bank[lane], live_a_addr[lane]} + 24'd1))
                        response_a_next_lane[lane] = 1'b1;
                end
            end
        end
        response_live_a = |response_a_current_lane | |response_a_next_lane;

        response_b_current = 1'b0;
        response_b_next = 1'b0;
        if (active && request_space_b) begin
            if (live_b_transition) begin
                response_b_current = request_logical == adpcmb_addr;
                response_b_next = request_logical == adpcmb_next_logical;
            end else if (live_b_valid) begin
                response_b_current = request_logical == live_b_addr;
                response_b_next = request_logical ==
                                  b_offset_logical(live_b_addr, 4'd1);
            end
        end
        response_live_b = response_b_current | response_b_next;
    end

    // Need selection. Serialized prewarm owns the lookup pipeline while active;
    // otherwise required live bytes outrank speculative +1 fetches.
    always_comb begin
        need_valid = 1'b0;
        need_required = 1'b0;
        need_space_b = 1'b0;
        need_logical = 24'd0;
        need_prewarm = 1'b0;
        need_prewarm_next = 1'b0;
        need_prewarm_voice = prewarm_voice;
`ifdef YM2610_GF_RG1_PROBE
        need_current_a = 1'b0;
`endif
        a_need_valid = 1'b0;
        a_need_required = 1'b0;
        a_need_logical = adpcma_logical;
        b_need_valid = 1'b0;
        b_need_required = 1'b0;
        b_need_logical = adpcmb_addr;

        if (prewarm_state == PW_REFILL_CURRENT ||
            prewarm_state == PW_REFILL_NEXT) begin
            need_valid = 1'b1;
            need_required = 1'b1;
            need_space_b = prewarm_space_b;
            need_logical = prewarm_state == PW_REFILL_NEXT ?
                           prewarm_next_logical : prewarm_current_logical;
            need_prewarm = 1'b1;
            need_prewarm_next = prewarm_state == PW_REFILL_NEXT;
        end else if (prewarm_state == PW_IDLE && !(prewarm_a || prewarm_b)) begin
            if (!adpcma_roe_n && !a_current_hit) begin
                a_need_valid = 1'b1;
                a_need_required = 1'b1;
                a_need_logical = adpcma_logical;
            end else if (a_current_hit && !a_next_hit) begin
                a_need_valid = 1'b1;
                a_need_logical = adpcma_next_logical;
            end

            if (!adpcmb_roe_n && !b_current_hit) begin
                b_need_valid = 1'b1;
                b_need_required = 1'b1;
                b_need_logical = adpcmb_addr;
            end else if (b_current_hit && !b_next_hit) begin
                b_need_valid = 1'b1;
                b_need_logical = adpcmb_next_logical;
            end else if (b_current_hit && b_next_hit && !b_ahead_hit &&
                         live_b_valid) begin
                // The serialized descriptor mapper adds a few clocks before
                // DDR acceptance.  An eight-byte startup runway keeps this
                // speculative refill seven bytes ahead of the live decoder.
                b_need_valid = 1'b1;
                b_need_logical = adpcmb_ahead_logical;
            end else if (!b_current_hit) begin
                b_need_valid = 1'b1;
                b_need_logical = adpcmb_addr;
            end

            if (a_need_valid || b_need_valid) begin
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
                    need_logical = a_need_logical;
                end else if (b_need_valid && !adpcmb_roe_n) begin
                    need_space_b = 1'b1;
                    need_logical = b_need_logical;
                end else if (a_need_valid && b_need_valid) begin
                    // Both JT10 ROM output enables are pulsed. Between live
                    // strobes prefer the retained live owner; alternate only
                    // when both decoders are live. With neither live, retain
                    // the established A-first speculative behavior.
                    if (live_b_valid && !(|live_a_valid)) begin
                        need_space_b = 1'b1;
                        need_logical = b_need_logical;
                    end else if ((|live_a_valid) && live_b_valid) begin
                        need_space_b = prefer_b;
                        need_logical = prefer_b ?
                                       b_need_logical : a_need_logical;
                    end else begin
                        need_logical = a_need_logical;
                    end
                end else if (a_need_valid) begin
                    need_logical = a_need_logical;
                end else begin
                    need_space_b = 1'b1;
                    need_logical = b_need_logical;
                end
            end
        end

        write_allow = !(prewarm_a || prewarm_b) || prewarm_state == PW_DONE;
    end

    assign map_req_valid = lookup_offer_valid;
    assign map_space_b = lookup_offer_space_b;
    assign map_logical_addr = lookup_offer_logical;
    assign mem_req = offer_valid;
    assign mem_addr = offer_file_addr;
    assign request_held = offer_valid || lookup_offer_valid;
    assign response_pending = request_pending || map_pending;
    assign held_space_b = offer_valid ? offer_space_b :
                          (lookup_offer_valid ? lookup_offer_space_b :
                           request_space_b);
    assign held_logical_addr = offer_valid ? offer_logical[19:0] :
                               (lookup_offer_valid ?
                                lookup_offer_logical[19:0] :
                                request_logical[19:0]);

    always_ff @(posedge clk) begin
        if (reset) begin
            replace_ptr <= '0;
            prepared_a_valid <= 6'd0;
            retired_a_valid <= 6'd0;
            retired2_a_valid <= 6'd0;
            live_a_valid <= 6'd0;
            live_a_current_slot_valid <= 6'd0;
            live_a_next_slot_valid <= 6'd0;
            live_b_valid <= 1'b0;
            live_b_addr <= 24'd0;
            live_b_current_slot_valid <= 1'b0;
            live_b_next_slot_valid <= 1'b0;
            live_b_current_slot <= '0;
            live_b_next_slot <= '0;
            start_b <= 16'd0;
            end_b <= 16'd0;

            prewarm_state <= PW_IDLE;
            prewarm_space_b <= 1'b0;
            prewarm_remaining <= 6'd0;
            prewarm_voice <= 3'd0;
            prewarm_scan_slot <= '0;
            prewarm_start_b <= 16'd0;
            prewarm_a_current_hit <= 6'd0;
            prewarm_a_next_hit <= 6'd0;
            prewarm_b_current_hit <= 1'b0;
            prewarm_b_next_hit <= 1'b0;
            prewarm_b_offset <= 3'd0;
            prewarm_b_current_slot <= '0;
            prewarm_b_next_slot <= '0;
            prewarm_b_runway_valid <= 8'd0;
            prewarm_b_repeat <= 1'b0;
            repeat_b_protected <= 1'b0;
            repeat_b_start_logical <= 24'd0;
            repeat_b_end_logical <= 24'd0;

            lookup_offer_valid <= 1'b0;
            lookup_offer_space_b <= 1'b0;
            lookup_offer_required <= 1'b0;
            lookup_offer_logical <= 24'd0;
            lookup_offer_prewarm <= 1'b0;
            lookup_offer_prewarm_next <= 1'b0;
            lookup_offer_prewarm_voice <= 3'd0;
            map_pending <= 1'b0;
            map_pending_space_b <= 1'b0;
            map_pending_required <= 1'b0;
            map_pending_logical <= 24'd0;
            map_pending_prewarm <= 1'b0;
            map_pending_prewarm_next <= 1'b0;
            map_pending_prewarm_voice <= 3'd0;
`ifdef YM2610_GF_RG1_PROBE
            map_pending_current_a <= 1'b0;
`endif
            offer_valid <= 1'b0;
            offer_space_b <= 1'b0;
            offer_logical <= 24'd0;
            offer_file_addr <= '0;
            offer_prewarm <= 1'b0;
            offer_prewarm_next <= 1'b0;
            offer_prewarm_voice <= 3'd0;
            request_pending <= 1'b0;
            request_space_b <= 1'b0;
            request_logical <= 24'd0;
            request_prewarm <= 1'b0;
            request_prewarm_next <= 1'b0;
            request_prewarm_voice <= 3'd0;
            prefer_b <= 1'b0;

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
            for (i = 0; i < 6; i = i + 1) begin
                start_a[i] <= 16'd0;
                prewarm_start_a[i] <= 16'd0;
                prewarm_a_current_slot[i] <= '0;
                prewarm_a_next_slot[i] <= '0;
                prepared_a_current_slot[i] <= '0;
                prepared_a_next_slot[i] <= '0;
                retired_a_current_slot[i] <= '0;
                retired_a_next_slot[i] <= '0;
                retired2_a_current_slot[i] <= '0;
                retired2_a_next_slot[i] <= '0;
                live_a_addr[i] <= 20'd0;
                live_a_bank[i] <= 4'd0;
                live_a_current_slot[i] <= '0;
                live_a_next_slot[i] <= '0;
            end
            for (i = 0; i < ENTRIES; i = i + 1) begin
                cache_valid[i] <= 1'b0;
                cache_space_b[i] <= 1'b0;
                cache_logical[i] <= 20'd0;
                cache_bank[i] <= 4'd0;
                cache_data[i] <= 8'd0;
            end
            for (i = 0; i < 8; i = i + 1) begin
                prewarm_b_runway_slot[i] <= '0;
                repeat_b_runway_slot[i] <= '0;
            end
        end else begin
            // Start/range shadows change only on accepted bus writes.
            if (write_accept) begin
                if (write_port && write_address >= 8'h10 &&
                    write_address <= 8'h15)
                    start_a[write_address[2:0]][7:0] <= write_data;
                if (write_port && write_address >= 8'h18 &&
                    write_address <= 8'h1d)
                    start_a[write_address[2:0]][15:8] <= write_data;
                if (!write_port && write_address == 8'h12)
                    start_b[7:0] <= write_data;
                if (!write_port && write_address == 8'h13)
                    start_b[15:8] <= write_data;
                if (!write_port && write_address == 8'h14)
                    end_b[7:0] <= write_data;
                if (!write_port && write_address == 8'h15)
                    end_b[15:8] <= write_data;

                // Retain exactly the eight slots prepared for a repeated B
                // command. Any accepted stop/reset or replacement start ends
                // the prior ownership; a repeat start installs the new set.
                if (!write_port && write_address == 8'h10 &&
                    write_data[7] && !write_data[0]) begin
                    if (prewarm_b_repeat && &prewarm_b_runway_valid) begin
                        repeat_b_protected <= 1'b1;
                        repeat_b_start_logical <= {prewarm_start_b, 8'd0};
                        repeat_b_end_logical <= {end_b, 8'hff};
                        for (i = 0; i < 8; i = i + 1)
                            repeat_b_runway_slot[i] <=
                                prewarm_b_runway_slot[i];
                    end else begin
                        repeat_b_protected <= 1'b0;
                    end
                end else if (!write_port && write_address == 8'h10 &&
                             write_data[0]) begin
                    repeat_b_protected <= 1'b0;
                end
            end

            // Capture a key-on before bus acceptance, then drain any older
            // lookup/fetch and scan only the selected voices.
            if (prewarm_state == PW_IDLE && (prewarm_a || prewarm_b)) begin
                prewarm_space_b <= prewarm_b;
                prewarm_remaining <= prewarm_b ? 6'b000001 : write_data[5:0];
                prewarm_voice <= prewarm_b ? 3'd0 : first_voice(write_data[5:0]);
                prewarm_scan_slot <= '0;
                prewarm_start_b <= start_b;
                prewarm_a_current_hit <= 6'd0;
                prewarm_a_next_hit <= 6'd0;
                prewarm_b_current_hit <= 1'b0;
                prewarm_b_next_hit <= 1'b0;
                prewarm_b_offset <= 3'd0;
                prewarm_b_runway_valid <= 8'd0;
                prewarm_b_repeat <= prewarm_b && write_data[4];
                for (i = 0; i < 6; i = i + 1)
                    prewarm_start_a[i] <= start_a[i];
                if (pipeline_idle)
                    prewarm_state <= PW_SCAN;
                else
                    prewarm_state <= PW_WAIT_IDLE;
            end else begin
                case (prewarm_state)
                    PW_WAIT_IDLE: if (pipeline_idle) begin
                        prewarm_scan_slot <= '0;
                        prewarm_state <= PW_SCAN;
                    end
                    PW_SCAN: begin
                        if (prewarm_scan_current_match) begin
                            if (prewarm_space_b) begin
                                prewarm_b_current_hit <= 1'b1;
                                prewarm_b_current_slot <= prewarm_scan_slot;
                                prewarm_b_runway_valid[prewarm_b_offset] <= 1'b1;
                                prewarm_b_runway_slot[prewarm_b_offset] <=
                                    prewarm_scan_slot;
                            end else begin
                                prewarm_a_current_hit[prewarm_voice] <= 1'b1;
                                prewarm_a_current_slot[prewarm_voice] <=
                                    prewarm_scan_slot;
                            end
                        end
                        if (prewarm_scan_next_match) begin
                            if (prewarm_space_b) begin
                                prewarm_b_next_hit <= 1'b1;
                                prewarm_b_next_slot <= prewarm_scan_slot;
                                prewarm_b_runway_valid[
                                    prewarm_b_offset + 3'd1] <= 1'b1;
                                prewarm_b_runway_slot[
                                    prewarm_b_offset + 3'd1] <=
                                    prewarm_scan_slot;
                            end else begin
                                prewarm_a_next_hit[prewarm_voice] <= 1'b1;
                                prewarm_a_next_slot[prewarm_voice] <=
                                    prewarm_scan_slot;
                            end
                        end
                        if (prewarm_scan_slot == LAST_SLOT) begin
                            if (!prewarm_current_found)
                                prewarm_state <= PW_REFILL_CURRENT;
                            else if (!prewarm_next_found)
                                prewarm_state <= PW_REFILL_NEXT;
                            else if (prewarm_space_b) begin
                                if (prewarm_b_offset < 3'd6) begin
                                    prewarm_b_offset <=
                                        prewarm_b_offset + 3'd2;
                                    prewarm_b_current_hit <= 1'b0;
                                    prewarm_b_next_hit <= 1'b0;
                                    prewarm_scan_slot <= '0;
                                end else begin
                                    prewarm_state <= PW_DONE;
                                end
                            end
                            else if (!prewarm_more_voices)
                                prewarm_state <= PW_DONE;
                            else begin
                                prewarm_remaining <= prewarm_remaining_after;
                                prewarm_voice <= prewarm_next_voice;
                                prewarm_scan_slot <= '0;
                            end
                        end else begin
                            prewarm_scan_slot <= prewarm_scan_slot +
                                {{(PTR_WIDTH-1){1'b0}}, 1'b1};
                        end
                    end
                    PW_DONE: if (write_accept)
                        prewarm_state <= PW_IDLE;
                    default: begin end
                endcase
            end

            // Slot lifecycle snapshot on accepted A command. The proven
            // 1ec8b7f MMR-to-driver mailbox is downstream and untouched.
            if (write_accept && write_port && write_address == 8'h00) begin
                for (i = 0; i < 6; i = i + 1) begin
                    if (write_data[i]) begin
                        if (prepared_a_valid[i]) begin
                            retired2_a_valid[i] <= retired_a_valid[i];
                            retired2_a_current_slot[i] <=
                                retired_a_current_slot[i];
                            retired2_a_next_slot[i] <= retired_a_next_slot[i];
                            retired_a_valid[i] <= 1'b1;
                            retired_a_current_slot[i] <=
                                prepared_a_current_slot[i];
                            retired_a_next_slot[i] <= prepared_a_next_slot[i];
                        end
                        if (write_data[7]) begin
                            prepared_a_valid[i] <= 1'b0;
                        end else begin
                            prepared_a_valid[i] <= 1'b1;
                            prepared_a_current_slot[i] <=
                                prewarm_a_current_slot[i];
                            prepared_a_next_slot[i] <= prewarm_a_next_slot[i];
                        end
                    end
                end
            end

            // Hold the mapper request address and ownership until acceptance.
            if (!lookup_offer_valid && !map_pending && !offer_valid &&
                !request_pending && active && need_valid && !range_error) begin
                lookup_offer_valid <= 1'b1;
                lookup_offer_space_b <= need_space_b;
                lookup_offer_required <= need_required;
                lookup_offer_logical <= need_logical;
                lookup_offer_prewarm <= need_prewarm;
                lookup_offer_prewarm_next <= need_prewarm_next;
                lookup_offer_prewarm_voice <= need_prewarm_voice;
`ifdef YM2610_GF_RG1_PROBE
                map_pending_current_a <= need_current_a;
`endif
            end
            if (map_req_valid && map_req_ready) begin
                lookup_offer_valid <= 1'b0;
                map_pending <= 1'b1;
                map_pending_space_b <= lookup_offer_space_b;
                map_pending_required <= lookup_offer_required;
                map_pending_logical <= lookup_offer_logical;
                map_pending_prewarm <= lookup_offer_prewarm;
                map_pending_prewarm_next <= lookup_offer_prewarm_next;
                map_pending_prewarm_voice <= lookup_offer_prewarm_voice;
            end
            if (map_rsp_valid) begin
                if (!map_pending) begin
                    stale_response <= 1'b1;
                end else begin
                    map_pending <= 1'b0;
                    if (map_rsp_hit) begin
                        offer_valid <= 1'b1;
                        offer_space_b <= map_pending_space_b;
                        offer_logical <= map_pending_logical;
                        offer_file_addr <= map_rsp_file_addr;
                        offer_prewarm <= map_pending_prewarm;
                        offer_prewarm_next <= map_pending_prewarm_next;
                        offer_prewarm_voice <= map_pending_prewarm_voice;
                    end else if (map_pending_required) begin
                        range_error <= 1'b1;
`ifdef YM2610_GF_RG1_PROBE
                        if (!range_fault_valid) begin
                            range_fault_valid <= 1'b1;
                            range_fault_addr <= map_pending_logical[19:0];
                            range_fault_current <= map_pending_current_a;
                        end
`endif
                    end
                end
            end

            if (mem_req && mem_ready) begin
                offer_valid <= 1'b0;
                request_pending <= 1'b1;
                request_space_b <= offer_space_b;
                request_logical <= offer_logical;
                request_prewarm <= offer_prewarm;
                request_prewarm_next <= offer_prewarm_next;
                request_prewarm_voice <= offer_prewarm_voice;
                request_count <= request_count + 32'd1;
                last_logical_addr <= offer_logical[19:0];
                prefer_b <= !offer_space_b;
                if (offer_space_b)
                    adpcmb_fetch_requests <= adpcmb_fetch_requests + 32'd1;
                else
                    adpcma_fetch_requests <= adpcma_fetch_requests + 32'd1;
            end

            if (mem_valid) begin
                if (!request_pending) begin
                    stale_response <= 1'b1;
                end else begin
                    request_pending <= 1'b0;
                    response_count <= response_count + 32'd1;
                    if (request_space_b)
                        adpcmb_fetch_responses <= adpcmb_fetch_responses + 32'd1;
                    else
                        adpcma_fetch_responses <= adpcma_fetch_responses + 32'd1;
                    if (replacement_found) begin
                        cache_valid[replacement_slot] <= 1'b1;
                        cache_space_b[replacement_slot] <= request_space_b;
                        cache_logical[replacement_slot] <= request_logical[19:0];
                        cache_bank[replacement_slot] <= request_logical[23:20];
                        cache_data[replacement_slot] <= mem_data;

                        if (request_prewarm) begin
                            if (request_space_b) begin
                                if (request_prewarm_next) begin
                                    prewarm_b_next_hit <= 1'b1;
                                    prewarm_b_next_slot <= replacement_slot;
                                    prewarm_b_runway_valid[
                                        prewarm_b_offset + 3'd1] <= 1'b1;
                                    prewarm_b_runway_slot[
                                        prewarm_b_offset + 3'd1] <=
                                        replacement_slot;
                                end else begin
                                    prewarm_b_current_hit <= 1'b1;
                                    prewarm_b_current_slot <= replacement_slot;
                                    prewarm_b_runway_valid[prewarm_b_offset]
                                        <= 1'b1;
                                    prewarm_b_runway_slot[prewarm_b_offset] <=
                                        replacement_slot;
                                end
                            end else if (request_prewarm_next) begin
                                prewarm_a_next_hit[request_prewarm_voice] <= 1'b1;
                                prewarm_a_next_slot[request_prewarm_voice] <=
                                    replacement_slot;
                            end else begin
                                prewarm_a_current_hit[request_prewarm_voice] <= 1'b1;
                                prewarm_a_current_slot[request_prewarm_voice] <=
                                    replacement_slot;
                            end

                            if (!request_prewarm_next &&
                                !prewarm_next_found) begin
                                prewarm_state <= PW_REFILL_NEXT;
                            end else if (prewarm_space_b) begin
                                if (prewarm_b_offset < 3'd6) begin
                                    prewarm_b_offset <=
                                        prewarm_b_offset + 3'd2;
                                    prewarm_b_current_hit <= 1'b0;
                                    prewarm_b_next_hit <= 1'b0;
                                    prewarm_scan_slot <= '0;
                                    prewarm_state <= PW_SCAN;
                                end else begin
                                    prewarm_state <= PW_DONE;
                                end
                            end else if (!prewarm_more_voices) begin
                                prewarm_state <= PW_DONE;
                            end else begin
                                prewarm_remaining <= prewarm_remaining_after;
                                prewarm_voice <= prewarm_next_voice;
                                prewarm_scan_slot <= '0;
                                prewarm_state <= PW_SCAN;
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

            if (!active) begin
                live_a_valid <= 6'd0;
                live_a_current_slot_valid <= 6'd0;
                live_a_next_slot_valid <= 6'd0;
                live_b_valid <= 1'b0;
                live_b_current_slot_valid <= 1'b0;
                live_b_next_slot_valid <= 1'b0;
            end else begin
                if (live_a_transition) begin
                    for (i = 5; i > 0; i = i - 1) begin
                        live_a_valid[i] <= live_a_valid[i-1];
                        live_a_addr[i] <= live_a_addr[i-1];
                        live_a_bank[i] <= live_a_bank[i-1];
                        live_a_current_slot_valid[i] <=
                            live_a_current_slot_valid[i-1];
                        live_a_next_slot_valid[i] <=
                            live_a_next_slot_valid[i-1];
                        live_a_current_slot[i] <= live_a_current_slot[i-1];
                        live_a_next_slot[i] <= live_a_next_slot[i-1];
                    end
                    live_a_valid[0] <= 1'b1;
                    live_a_addr[0] <= adpcma_addr;
                    live_a_bank[0] <= adpcma_bank;
                    live_a_current_slot_valid[0] <= a_current_hit;
                    live_a_next_slot_valid[0] <= a_next_hit;
                    live_a_current_slot[0] <= a_current_slot;
                    live_a_next_slot[0] <= a_next_slot;
                end
                if (live_b_transition) begin
                    live_b_valid <= 1'b1;
                    live_b_addr <= adpcmb_addr;
                    live_b_current_slot_valid <= b_current_hit;
                    live_b_next_slot_valid <= b_next_hit;
                    live_b_current_slot <= b_current_slot;
                    live_b_next_slot <= b_next_slot;
                end
            end

            // A fill that belongs to retained live history must win over the
            // same-edge round-robin history shift. This is the ba6f795 GF09
            // transition-response invariant expressed with slot references.
            if (mem_valid && request_pending && replacement_found) begin
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
            end

            if (active && !adpcma_roe_n) begin
                adpcma_request_count <= adpcma_request_count + 32'd1;
                adpcma_last_address <= adpcma_addr;
                if (!a_current_hit)
                    adpcma_underflow <= 1'b1;
            end
            if (active && !adpcmb_roe_n) begin
                adpcmb_request_count <= adpcmb_request_count + 32'd1;
                adpcmb_last_address <= adpcmb_addr[19:0];
                if (!b_current_hit)
                    adpcmb_underflow <= 1'b1;
            end
        end
    end
endmodule

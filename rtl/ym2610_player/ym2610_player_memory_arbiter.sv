`timescale 1ns/1ps

// One-outstanding byte-read arbiter.  A selected request is first copied into
// an offer register and remains bit-for-bit stable until the backend accepts
// it.  Response routing uses the owner/address/generation captured at accept;
// no live client signal participates in response ownership.
module ym2610_player_memory_arbiter #(
    parameter int ADDR_WIDTH = 23,
    parameter int RESPONSE_TIMEOUT = 1024,
    parameter int GENERATION_WIDTH = 8
) (
    input  logic                  clk,
    input  logic                  reset,
    input  logic [GENERATION_WIDTH-1:0] generation,

    input  logic                  scan_req,
    input  logic [ADDR_WIDTH-1:0] scan_addr,
    output logic                  scan_ready,
    output logic                  scan_valid,
    output logic [7:0]            scan_data,

    input  logic                  parser_req,
    input  logic [ADDR_WIDTH-1:0] parser_addr,
    output logic                  parser_ready,
    output logic                  parser_valid,
    output logic [7:0]            parser_data,

    input  logic                  pcm_req,
    input  logic [ADDR_WIDTH-1:0] pcm_addr,
    output logic                  pcm_ready,
    output logic                  pcm_valid,
    output logic [7:0]            pcm_data,

    output logic                  mem_req,
    output logic [ADDR_WIDTH-1:0] mem_addr,
    input  logic                  mem_ready,
    input  logic                  mem_valid,
    input  logic [7:0]            mem_data,

    output logic [31:0]           scanner_requests,
    output logic [31:0]           parser_requests,
    output logic [31:0]           pcm_requests,
    output logic [31:0]           response_count,
    output logic                  stale_response,
    output logic                  owner_mismatch,
    output logic                  response_timeout,
    output logic                  request_held,
    output logic                  outstanding,
    output logic [1:0]            held_owner,
    output logic [1:0]            outstanding_owner,
    output logic [ADDR_WIDTH-1:0] last_accept_addr,
    output logic [ADDR_WIDTH-1:0] last_response_addr,
    output logic [GENERATION_WIDTH-1:0] last_accept_generation,
    output logic [GENERATION_WIDTH-1:0] last_response_generation
);
    localparam logic [1:0] OWNER_SCAN = 2'd0;
    localparam logic [1:0] OWNER_PARSER = 2'd1;
    localparam logic [1:0] OWNER_PCM = 2'd2;
    localparam int AGE_WIDTH = $clog2(RESPONSE_TIMEOUT+1);
    localparam logic [AGE_WIDTH-1:0] TIMEOUT_VALUE =
        RESPONSE_TIMEOUT[AGE_WIDTH-1:0];
    localparam logic [AGE_WIDTH-1:0] TIMEOUT_LAST = TIMEOUT_VALUE - 1'b1;

    logic offer_valid;
    logic [1:0] offer_owner;
    logic [ADDR_WIDTH-1:0] offer_addr;
    logic [GENERATION_WIDTH-1:0] offer_generation;
    logic pending;
    logic [1:0] owner;
    logic [ADDR_WIDTH-1:0] pending_addr;
    logic [GENERATION_WIDTH-1:0] pending_generation;
    logic prefer_pcm;
    logic selected;
    logic [1:0] selected_owner;
    logic [ADDR_WIDTH-1:0] selected_addr;
    logic [1:0] accepted_owner;
    logic [ADDR_WIDTH-1:0] accepted_addr;
    logic [GENERATION_WIDTH-1:0] accepted_generation;
    logic [AGE_WIDTH-1:0] response_age;

    assign mem_req = !reset && (offer_valid || selected);
    assign mem_addr = offer_valid ? offer_addr : selected_addr;
    assign request_held = offer_valid;
    assign outstanding = pending;
    assign held_owner = offer_owner;
    assign outstanding_owner = owner;
    assign accepted_owner = offer_valid ? offer_owner : selected_owner;
    assign accepted_addr = offer_valid ? offer_addr : selected_addr;
    assign accepted_generation = offer_valid ? offer_generation : generation;
    assign scan_ready = mem_req && accepted_owner == OWNER_SCAN && mem_ready;
    assign parser_ready = mem_req && accepted_owner == OWNER_PARSER && mem_ready;
    assign pcm_ready = mem_req && accepted_owner == OWNER_PCM && mem_ready;

    always_comb begin
        selected = 1'b0;
        selected_owner = OWNER_SCAN;
        selected_addr = scan_addr;
        if (!reset && !offer_valid && !pending) begin
            if (scan_req) begin
                selected = 1'b1;
                selected_owner = OWNER_SCAN;
                selected_addr = scan_addr;
            end else if (pcm_req && (prefer_pcm || !parser_req)) begin
                selected = 1'b1;
                selected_owner = OWNER_PCM;
                selected_addr = pcm_addr;
            end else if (parser_req) begin
                selected = 1'b1;
                selected_owner = OWNER_PARSER;
                selected_addr = parser_addr;
            end else if (pcm_req) begin
                selected = 1'b1;
                selected_owner = OWNER_PCM;
                selected_addr = pcm_addr;
            end
        end
    end

    always_ff @(posedge clk) begin
        scan_valid <= 1'b0;
        parser_valid <= 1'b0;
        pcm_valid <= 1'b0;
        if (reset) begin
            offer_valid <= 1'b0;
            offer_owner <= OWNER_SCAN;
            offer_addr <= '0;
            offer_generation <= '0;
            pending <= 1'b0;
            owner <= OWNER_SCAN;
            pending_addr <= '0;
            pending_generation <= '0;
            prefer_pcm <= 1'b1;
            scan_data <= 8'd0;
            parser_data <= 8'd0;
            pcm_data <= 8'd0;
            scanner_requests <= 32'd0;
            parser_requests <= 32'd0;
            pcm_requests <= 32'd0;
            response_count <= 32'd0;
            stale_response <= 1'b0;
            owner_mismatch <= 1'b0;
            response_timeout <= 1'b0;
            response_age <= '0;
            last_accept_addr <= '0;
            last_response_addr <= '0;
            last_accept_generation <= '0;
            last_response_generation <= '0;
        end else begin
            if (selected && !mem_ready) begin
                offer_valid <= 1'b1;
                offer_owner <= selected_owner;
                offer_addr <= selected_addr;
                offer_generation <= generation;
            end

            if (mem_req && mem_ready) begin
                offer_valid <= 1'b0;
                pending <= 1'b1;
                owner <= accepted_owner;
                pending_addr <= accepted_addr;
                pending_generation <= accepted_generation;
                response_age <= '0;
                last_accept_addr <= accepted_addr;
                last_accept_generation <= accepted_generation;
                case (accepted_owner)
                    OWNER_SCAN: scanner_requests <= scanner_requests + 32'd1;
                    OWNER_PARSER: begin
                        parser_requests <= parser_requests + 32'd1;
                        prefer_pcm <= 1'b1;
                    end
                    OWNER_PCM: begin
                        pcm_requests <= pcm_requests + 32'd1;
                        prefer_pcm <= 1'b0;
                    end
                    default: owner_mismatch <= 1'b1;
                endcase
            end

            if (pending && !mem_valid) begin
                if (response_age == TIMEOUT_LAST)
                    response_timeout <= 1'b1;
                else if (!response_timeout)
                    response_age <= response_age + 1'b1;
            end

            if (mem_valid) begin
                if (!pending) begin
                    stale_response <= 1'b1;
                end else begin
                    pending <= 1'b0;
                    response_age <= '0;
                    last_response_addr <= pending_addr;
                    last_response_generation <= pending_generation;
                    if (pending_generation != generation) begin
                        stale_response <= 1'b1;
                    end else begin
                        response_count <= response_count + 32'd1;
                        case (owner)
                            OWNER_SCAN: begin
                                scan_data <= mem_data;
                                scan_valid <= 1'b1;
                            end
                            OWNER_PARSER: begin
                                parser_data <= mem_data;
                                parser_valid <= 1'b1;
                            end
                            OWNER_PCM: begin
                                pcm_data <= mem_data;
                                pcm_valid <= 1'b1;
                            end
                            default: owner_mismatch <= 1'b1;
                        endcase
                    end
                end
            end
        end
    end
endmodule

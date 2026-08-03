`timescale 1ns/1ps

// One-outstanding byte-read arbiter for scanner, parser and the shared A/B
// PCM cache.  The scanner owns memory exclusively before playback; parser and
// PCM alternate after playback starts, with PCM winning the first tie.
module ym2610_player_memory_arbiter #(
    parameter int ADDR_WIDTH = 23,
    parameter int RESPONSE_TIMEOUT = 1024
) (
    input  logic                  clk,
    input  logic                  reset,

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
    output logic                  stale_response,
    output logic                  owner_mismatch,
    output logic                  response_timeout
);
    localparam logic [1:0] OWNER_SCAN = 2'd0;
    localparam logic [1:0] OWNER_PARSER = 2'd1;
    localparam logic [1:0] OWNER_PCM = 2'd2;
    localparam int AGE_WIDTH = $clog2(RESPONSE_TIMEOUT+1);
    localparam logic [AGE_WIDTH-1:0] TIMEOUT_VALUE =
        RESPONSE_TIMEOUT[AGE_WIDTH-1:0];
    localparam logic [AGE_WIDTH-1:0] TIMEOUT_LAST = TIMEOUT_VALUE - 1'b1;

    logic pending;
    logic [1:0] owner;
    logic prefer_pcm;
    logic selected;
    logic [1:0] selected_owner;
    logic [AGE_WIDTH-1:0] response_age;

    always_comb begin
        selected = 1'b0;
        selected_owner = OWNER_SCAN;
        if (!pending) begin
            if (scan_req) begin
                selected = 1'b1;
                selected_owner = OWNER_SCAN;
            end else if (pcm_req && (prefer_pcm || !parser_req)) begin
                selected = 1'b1;
                selected_owner = OWNER_PCM;
            end else if (parser_req) begin
                selected = 1'b1;
                selected_owner = OWNER_PARSER;
            end else if (pcm_req) begin
                selected = 1'b1;
                selected_owner = OWNER_PCM;
            end
        end

        mem_req = selected;
        case (selected_owner)
            OWNER_SCAN: mem_addr = scan_addr;
            OWNER_PARSER: mem_addr = parser_addr;
            default: mem_addr = pcm_addr;
        endcase
        scan_ready = selected && selected_owner == OWNER_SCAN && mem_ready;
        parser_ready = selected && selected_owner == OWNER_PARSER && mem_ready;
        pcm_ready = selected && selected_owner == OWNER_PCM && mem_ready;
    end

    always_ff @(posedge clk) begin
        scan_valid <= 1'b0;
        parser_valid <= 1'b0;
        pcm_valid <= 1'b0;
        if (reset) begin
            pending <= 1'b0;
            owner <= OWNER_SCAN;
            prefer_pcm <= 1'b1;
            scan_data <= 8'd0;
            parser_data <= 8'd0;
            pcm_data <= 8'd0;
            scanner_requests <= 32'd0;
            parser_requests <= 32'd0;
            pcm_requests <= 32'd0;
            stale_response <= 1'b0;
            owner_mismatch <= 1'b0;
            response_timeout <= 1'b0;
            response_age <= '0;
        end else begin
            if (mem_req && mem_ready) begin
                pending <= 1'b1;
                owner <= selected_owner;
                response_age <= '0;
                case (selected_owner)
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
                if (!pending)
                    stale_response <= 1'b1;
                else begin
                    pending <= 1'b0;
                    response_age <= '0;
                    case (owner)
                        OWNER_SCAN: begin scan_data <= mem_data; scan_valid <= 1'b1; end
                        OWNER_PARSER: begin parser_data <= mem_data; parser_valid <= 1'b1; end
                        OWNER_PCM: begin pcm_data <= mem_data; pcm_valid <= 1'b1; end
                        default: owner_mismatch <= 1'b1;
                    endcase
                end
            end
        end
    end
endmodule

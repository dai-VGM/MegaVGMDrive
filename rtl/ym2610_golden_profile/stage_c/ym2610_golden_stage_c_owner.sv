// SPDX-License-Identifier: GPL-2.0-or-later
// Time-separated ownership for the one immutable shell byte-read client.
`timescale 1ns/1ps

module ym2610_golden_stage_c_owner #(
    parameter int ADDR_WIDTH = 23
) (
    input  logic                  clk,
    input  logic                  reset,
    input  logic                  cancel,
    input  logic                  scanner_enable,
    input  logic                  parser_handoff,
    input  logic                  adapter_outstanding,

    input  logic                  scanner_req,
    input  logic [ADDR_WIDTH-1:0] scanner_addr,
    output logic                  scanner_ready,
    output logic                  scanner_valid,
    output logic [7:0]            scanner_data,

    input  logic                  parser_req,
    input  logic [ADDR_WIDTH-1:0] parser_addr,
    output logic                  parser_ready,
    output logic                  parser_valid,
    output logic [7:0]            parser_data,

    output logic                  client_req,
    output logic [ADDR_WIDTH-1:0] client_addr,
    input  logic                  client_ready,
    input  logic                  client_valid,
    input  logic [7:0]            client_data,

    output logic [1:0]            owner,
    output logic                  parser_owned,
    output logic                  transition_error,
    output logic [31:0]           transition_count
);
    localparam logic [1:0] OWNER_NONE    = 2'd0;
    localparam logic [1:0] OWNER_SCANNER = 2'd1;
    localparam logic [1:0] OWNER_PARSER  = 2'd2;

    logic [1:0] quiet_cycles;

    always_comb begin
        client_req = 1'b0;
        client_addr = '0;
        scanner_ready = 1'b0;
        scanner_valid = 1'b0;
        scanner_data = client_data;
        parser_ready = 1'b0;
        parser_valid = 1'b0;
        parser_data = client_data;

        case (owner)
            OWNER_SCANNER: begin
                client_req = scanner_req;
                client_addr = scanner_addr;
                scanner_ready = client_ready;
                scanner_valid = client_valid;
            end
            OWNER_PARSER: begin
                client_req = parser_req;
                client_addr = parser_addr;
                parser_ready = client_ready;
                parser_valid = client_valid;
            end
            default: begin end
        endcase
    end

    assign parser_owned = owner == OWNER_PARSER;

    always_ff @(posedge clk) begin
        if (reset || cancel) begin
            owner <= OWNER_NONE;
            quiet_cycles <= 2'd0;
            transition_error <= 1'b0;
            transition_count <= 32'd0;
        end else begin
            case (owner)
                OWNER_NONE: begin
                    quiet_cycles <= 2'd0;
                    if (scanner_enable)
                        owner <= OWNER_SCANNER;
                end

                OWNER_SCANNER: begin
                    if (parser_req)
                        transition_error <= 1'b1;
                    if (parser_handoff) begin
                        if (!scanner_req && !adapter_outstanding &&
                            !client_valid) begin
                            if (quiet_cycles == 2'd1) begin
                                owner <= OWNER_PARSER;
                                quiet_cycles <= 2'd0;
                                transition_count <= transition_count + 32'd1;
                            end else begin
                                quiet_cycles <= quiet_cycles + 2'd1;
                            end
                        end else begin
                            quiet_cycles <= 2'd0;
                        end
                    end else begin
                        quiet_cycles <= 2'd0;
                    end
                end

                OWNER_PARSER: begin
                    quiet_cycles <= 2'd0;
                    if (scanner_req)
                        transition_error <= 1'b1;
                end

                default: owner <= OWNER_NONE;
            endcase

            if (scanner_req && parser_req)
                transition_error <= 1'b1;
            if (owner == OWNER_NONE && client_valid)
                transition_error <= 1'b1;
        end
    end
endmodule

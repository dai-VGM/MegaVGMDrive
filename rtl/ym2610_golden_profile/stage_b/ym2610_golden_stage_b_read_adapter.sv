// SPDX-License-Identifier: GPL-2.0-or-later
// Single-client adapter for the immutable Golden Shell byte-read boundary.
`timescale 1ns/1ps

module ym2610_golden_stage_b_read_adapter #(
    parameter int ADDR_WIDTH = 23,
    parameter int GENERATION_WIDTH = 8,
    parameter int TIMEOUT_CYCLES = 1_000_000
) (
    input  logic                        clk,
    input  logic                        reset,
    input  logic                        cancel,
    input  logic                        download_active,
    input  logic [GENERATION_WIDTH-1:0] load_generation,

    input  logic                        client_req,
    input  logic [ADDR_WIDTH-1:0]       client_addr,
    output logic                        client_ready,
    output logic                        client_valid,
    output logic [7:0]                  client_data,

    output logic                        file_req,
    output logic [ADDR_WIDTH-1:0]       file_addr,
    input  logic                        file_ready,
    input  logic                        file_valid,
    input  logic [7:0]                  file_data,

    output logic                        outstanding,
    output logic                        timeout_error,
    output logic                        stale_response_error,
    output logic [31:0]                 accepted_count,
    output logic [31:0]                 response_count
);
    localparam int TIMEOUT_WIDTH = $clog2(TIMEOUT_CYCLES + 1);
    typedef enum logic [1:0] {RD_IDLE, RD_ACCEPT, RD_RESPONSE, RD_ERROR} rd_state_t;
    rd_state_t state;
    logic [ADDR_WIDTH-1:0] captured_addr;
    logic [GENERATION_WIDTH-1:0] captured_generation;
    logic [TIMEOUT_WIDTH-1:0] timeout_count;
    logic quarantine;
    logic [1:0] valid_low_count;

    assign file_req = (state == RD_ACCEPT) && !download_active && !cancel;
    assign file_addr = captured_addr;
    assign client_ready = file_req && file_ready;
    assign outstanding = (state == RD_ACCEPT) || (state == RD_RESPONSE);

    always_ff @(posedge clk) begin
        client_valid <= 1'b0;

        if (reset) begin
            state <= RD_IDLE;
            captured_addr <= '0;
            captured_generation <= '0;
            client_data <= 8'd0;
            timeout_count <= '0;
            timeout_error <= 1'b0;
            stale_response_error <= 1'b0;
            accepted_count <= 32'd0;
            response_count <= 32'd0;
            quarantine <= 1'b0;
            valid_low_count <= 2'd0;
        end else begin
            if (cancel || download_active) begin
                state <= RD_IDLE;
                timeout_count <= '0;
                quarantine <= 1'b1;
                valid_low_count <= 2'd0;
                if (download_active) begin
                    timeout_error <= 1'b0;
                    stale_response_error <= 1'b0;
                    accepted_count <= 32'd0;
                    response_count <= 32'd0;
                end
            end else begin
                if (quarantine) begin
                    if (file_valid) begin
                        valid_low_count <= 2'd0;
                        stale_response_error <= 1'b1;
                    end else if (valid_low_count == 2'd1) begin
                        quarantine <= 1'b0;
                        valid_low_count <= 2'd0;
                    end else begin
                        valid_low_count <= valid_low_count + 2'd1;
                    end
                end

                case (state)
                    RD_IDLE: begin
                        timeout_count <= '0;
                        if (!quarantine && client_req) begin
                            captured_addr <= client_addr;
                            captured_generation <= load_generation;
                            state <= RD_ACCEPT;
                        end else if (!quarantine && file_valid) begin
                            // No transaction owns this response.
                            stale_response_error <= 1'b1;
                        end
                    end

                    RD_ACCEPT: begin
                        if (file_ready) begin
                            accepted_count <= accepted_count + 32'd1;
                            timeout_count <= '0;
                            state <= RD_RESPONSE;
                        end else if (timeout_count == TIMEOUT_CYCLES-1) begin
                            timeout_error <= 1'b1;
                            state <= RD_ERROR;
                        end else begin
                            timeout_count <= timeout_count + 1'b1;
                        end
                    end

                    RD_RESPONSE: begin
                        if (file_valid) begin
                            response_count <= response_count + 32'd1;
                            timeout_count <= '0;
                            state <= RD_IDLE;
                            if (captured_generation == load_generation) begin
                                client_data <= file_data;
                                client_valid <= 1'b1;
                            end else begin
                                stale_response_error <= 1'b1;
                            end
                        end else if (timeout_count == TIMEOUT_CYCLES-1) begin
                            timeout_error <= 1'b1;
                            state <= RD_ERROR;
                        end else begin
                            timeout_count <= timeout_count + 1'b1;
                        end
                    end

                    RD_ERROR: begin
                        timeout_count <= '0;
                        if (!client_req)
                            state <= RD_IDLE;
                    end

                    default: state <= RD_IDLE;
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    logic [ADDR_WIDTH-1:0] held_addr;
    logic file_req_d;
    always_ff @(posedge clk) begin
        if (reset) begin
            held_addr <= '0;
            file_req_d <= 1'b0;
        end else begin
            if (file_req && file_req_d && !file_ready && file_addr !== held_addr)
                $fatal(1, "Stage B read address changed before accept");
            if (file_req)
                held_addr <= file_addr;
            file_req_d <= file_req;
            if (outstanding && download_active && file_req)
                $fatal(1, "Stage B issued DDR read during upload");
        end
    end
`endif
endmodule

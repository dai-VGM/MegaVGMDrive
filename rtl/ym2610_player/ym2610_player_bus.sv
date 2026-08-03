`timescale 1ns/1ps

// Public JT10 bus writer.  It polls status bit 7 before both address and data
// phases and never relies on a hierarchical busy signal or fixed delay.
module ym2610_player_bus (
    input  logic       clk,
    input  logic       reset,
    input  logic       request_valid,
    input  logic       request_port,
    input  logic [7:0] request_address,
    input  logic [7:0] request_data,
    output logic       request_ready,

    output logic [1:0] bus_addr,
    output logic [7:0] bus_din,
    output logic       bus_cs_n,
    output logic       bus_wr_n,
    input  logic [7:0] bus_dout,
    output logic       busy_timeout,
    output logic       write_while_busy,
    output logic [31:0] accepted_count
);
    typedef enum logic [3:0] {
        ST_IDLE, ST_CLEAR_SETUP, ST_CLEAR_SAMPLE, ST_ADDR_SETUP,
        ST_ADDR_CAPTURE, ST_DATA_SETUP, ST_DATA_SAMPLE,
        ST_DATA_CAPTURE
    } state_t;
    state_t state;
    logic current_port;
    logic [7:0] current_address;
    logic [7:0] current_data;
    logic [15:0] watchdog;

    always_comb request_ready = (state == ST_IDLE) && !busy_timeout;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            current_port <= 1'b0;
            current_address <= 8'd0;
            current_data <= 8'd0;
            watchdog <= 16'd0;
            busy_timeout <= 1'b0;
            write_while_busy <= 1'b0;
            accepted_count <= 32'd0;
            bus_addr <= 2'b00;
            bus_din <= 8'd0;
            bus_cs_n <= 1'b1;
            bus_wr_n <= 1'b1;
        end else begin
            case (state)
                ST_IDLE: begin
                    bus_addr <= 2'b00;
                    bus_din <= 8'd0;
                    bus_cs_n <= 1'b1;
                    bus_wr_n <= 1'b1;
                    if (request_valid) begin
                        current_port <= request_port;
                        current_address <= request_address;
                        current_data <= request_data;
                        watchdog <= 16'd0;
                        state <= ST_CLEAR_SETUP;
                    end
                end
                ST_CLEAR_SETUP: begin
                    bus_addr <= 2'b00;
                    bus_din <= 8'd0;
                    bus_cs_n <= 1'b0;
                    bus_wr_n <= 1'b1;
                    state <= ST_CLEAR_SAMPLE;
                end
                ST_CLEAR_SAMPLE: begin
                    if (!bus_dout[7]) begin
                        bus_addr <= 2'b00;
                        bus_din <= 8'd0;
                        bus_cs_n <= 1'b1;
                        bus_wr_n <= 1'b1;
                        watchdog <= 16'd0;
                        state <= ST_ADDR_SETUP;
                    end else if (&watchdog) begin
                        busy_timeout <= 1'b1;
                        bus_addr <= 2'b00;
                        bus_din <= 8'd0;
                        bus_cs_n <= 1'b1;
                        bus_wr_n <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        watchdog <= watchdog + 16'd1;
                        bus_addr <= 2'b00;
                        bus_din <= 8'd0;
                        bus_cs_n <= 1'b0;
                        bus_wr_n <= 1'b1;
                    end
                end
                ST_ADDR_SETUP: begin
                    bus_addr <= {current_port, 1'b0};
                    bus_din <= current_address;
                    bus_cs_n <= 1'b0;
                    bus_wr_n <= 1'b0;
                    state <= ST_ADDR_CAPTURE;
                end
                ST_ADDR_CAPTURE: begin
                    bus_addr <= 2'b00;
                    bus_din <= 8'd0;
                    bus_cs_n <= 1'b1;
                    bus_wr_n <= 1'b1;
                    state <= ST_DATA_SETUP;
                end
                ST_DATA_SETUP: begin
                    bus_addr <= 2'b00;
                    bus_din <= 8'd0;
                    bus_cs_n <= 1'b0;
                    bus_wr_n <= 1'b1;
                    state <= ST_DATA_SAMPLE;
                end
                ST_DATA_SAMPLE: begin
                    if (bus_dout[7]) begin
                        write_while_busy <= 1'b1;
                        bus_addr <= 2'b00;
                        bus_din <= 8'd0;
                        bus_cs_n <= 1'b1;
                        bus_wr_n <= 1'b1;
                        state <= ST_CLEAR_SETUP;
                    end else begin
                        bus_addr <= {current_port, 1'b1};
                        bus_din <= current_data;
                        bus_cs_n <= 1'b0;
                        bus_wr_n <= 1'b0;
                        state <= ST_DATA_CAPTURE;
                    end
                end
                ST_DATA_CAPTURE: begin
                    bus_addr <= 2'b00;
                    bus_din <= 8'd0;
                    bus_cs_n <= 1'b1;
                    bus_wr_n <= 1'b1;
                    accepted_count <= accepted_count + 32'd1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

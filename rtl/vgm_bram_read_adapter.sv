// Bridge the vgm_loaded_player byte-read interface to the existing
// vgm_file_loader synchronous BRAM read port.

module vgm_bram_read_adapter #(
    parameter int ADDR_WIDTH = 18
) (
    input  logic                      clk,
    input  logic                      reset,

    input  logic                      mem_rd_req,
    input  logic [ADDR_WIDTH-1:0]     mem_rd_addr,
    output logic                      mem_rd_ready,
    output logic                      mem_rd_valid,
    output logic [7:0]                mem_rd_data,

    output logic [ADDR_WIDTH-1:0]     bram_rd_addr,
    input  logic [7:0]                bram_rd_data
);

    logic pending;
    logic wait_data_cycle;

    assign mem_rd_ready = !pending;

    always_ff @(posedge clk) begin
        if (reset) begin
            pending <= 1'b0;
            wait_data_cycle <= 1'b0;
            mem_rd_valid <= 1'b0;
            mem_rd_data <= 8'd0;
            bram_rd_addr <= '0;
        end else begin
            mem_rd_valid <= 1'b0;

            if (pending && wait_data_cycle) begin
                wait_data_cycle <= 1'b0;
            end else if (pending) begin
                mem_rd_data <= bram_rd_data;
                mem_rd_valid <= 1'b1;
                pending <= 1'b0;
            end

            if (mem_rd_req && mem_rd_ready) begin
                bram_rd_addr <= mem_rd_addr;
                pending <= 1'b1;
                wait_data_cycle <= 1'b1;
            end
        end
    end

endmodule

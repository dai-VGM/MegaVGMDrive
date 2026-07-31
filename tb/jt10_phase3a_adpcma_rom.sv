`timescale 1ns/1ps

// Test-only, zero-wait-state ADPCM-A ROM.
//
// Both patterns are 4096-byte affine permutations selected only by logical
// address bits 11:0.  They therefore repeat every 4096 bytes, exercise every
// possible byte value in each 256-byte block, and make a legal one-register
// start-address shift (256 bytes) observably change the byte stream.
module jt10_phase3a_adpcma_rom (
    input  logic [19:0] address,
    input  logic  [3:0] bank,
    input  logic        changed_pattern,
    output logic  [7:0] data
);
    logic [23:0] logical_address;
    logic  [7:0] low_term;
    logic  [7:0] high_term;

    always @(*) begin
        logical_address = {bank, address};
        if (!changed_pattern) begin
            low_term  = logical_address[7:0] * 8'd73;
            high_term = {4'd0, logical_address[11:8]} * 8'd29;
            data      = low_term + high_term + 8'd41;
        end else begin
            low_term  = logical_address[7:0] * 8'd151;
            high_term = {4'd0, logical_address[11:8]} * 8'd67;
            data      = low_term + high_term + 8'd109;
        end
    end
endmodule

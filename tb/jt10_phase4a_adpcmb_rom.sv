`timescale 1ns/1ps

// Test-only, asynchronous ADPCM-B ROM.  JT10 presents a 24-bit byte
// address and captures the selected nibble on the following clock edge; the
// physical interface has no ready/valid handshake.
module jt10_phase4a_adpcmb_rom (
    input  logic [23:0] address,
    input  logic        changed_pattern,
    output logic [7:0]  data
);
    logic [18:0] mixed;

    always_comb begin
        if (changed_pattern) begin
            mixed = address[7:0] * 19'd151 +
                    address[15:8] * 19'd67 + 19'd109;
        end else begin
            mixed = address[7:0] * 19'd73 +
                    address[15:8] * 19'd29 + 19'd41;
        end
        data = mixed[7:0];
    end
endmodule

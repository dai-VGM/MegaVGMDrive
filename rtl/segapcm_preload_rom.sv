// Temporary SegaPCM preload ROM for YM2151/SegaPCM experiments.
//
// This supplies bytes extracted from the first 0x67/0x66/type-0x80 block in
// Last Wave with Seashore SFX, after the 8-byte SegaPCM ROM header. It is a
// small synchronous readback block intended to feed a SegaPCM core ROM port.
// The module is deliberately standalone so normal MD/backend/FM paths are not
// changed unless an experimental SegaPCM core instantiates it.

module segapcm_preload_rom #(
    parameter int unsigned ADDR_WIDTH = 19,
    parameter int unsigned ROM_BYTES = 23040
) (
    input  logic                  clk,
    input  logic                  req,
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic                  ok,
    output logic            [7:0] data
);

    logic [7:0] rom [0:ROM_BYTES-1];

    initial begin
        $readmemh("segapcm_lastwave_seashore_payload.mem", rom);
    end

    always_ff @(posedge clk) begin
        ok <= req;
        if (req && (addr < ROM_BYTES[ADDR_WIDTH-1:0])) begin
            data <= rom[addr];
        end else begin
            data <= 8'd0;
        end
    end

endmodule

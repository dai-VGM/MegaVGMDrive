`timescale 1ns/1ps

module tb_ym2610_gunfrontier_persistent_range_fault;
    logic clk = 1'b0;
    logic clear, capture, capture_current, valid, current;
    logic [19:0] capture_addr, addr;
    always #5 clk = ~clk;

    ym2610_gunfrontier_range_fault_sticky dut (
        .clk(clk), .clear(clear), .capture(capture),
        .capture_addr(capture_addr), .capture_current(capture_current),
        .valid(valid), .addr(addr), .current(current)
    );

    task automatic tick;
        begin
            @(negedge clk);
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        // Initial/new-load clear.
        clear = 1'b1;
        capture = 1'b0;
        capture_addr = 20'd0;
        capture_current = 1'b0;
        tick();
        if (valid !== 1'b0) $fatal(1, "clear did not reset sticky state");

        // N: cache captures its raw event. N+1: core receives range_error and
        // captures the still-live cache snapshot into this persistent bank.
        clear = 1'b0;
        capture = 1'b1;
        capture_addr = 20'h07600;
        capture_current = 1'b1;
        tick();
        if ({valid, addr, current} !== {1'b1, 20'h07600, 1'b1})
            $fatal(1, "N+1 capture failed");

        // N+2 and beyond emulate LS_REJECT cache reset: source is gone, but
        // diagnostic state must survive indefinitely.
        capture = 1'b0;
        repeat (101) tick();
        if ({valid, addr, current} !== {1'b1, 20'h07600, 1'b1})
            $fatal(1, "LS_REJECT persistence failed");

        // A later raw fault cannot overwrite the first snapshot.
        capture = 1'b1;
        capture_addr = 20'hac900;
        capture_current = 1'b0;
        tick();
        if ({valid, addr, current} !== {1'b1, 20'h07600, 1'b1})
            $fatal(1, "second fault overwrote first snapshot");

        // New attempt clears it.
        clear = 1'b1;
        capture = 1'b0;
        tick();
        if ({valid, addr, current} !== {1'b0, 20'd0, 1'b0})
            $fatal(1, "new-load clear failed");
        $display("PASS: persistent range-fault diagnostic");
        $finish;
    end
endmodule

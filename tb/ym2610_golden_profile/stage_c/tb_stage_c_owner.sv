`timescale 1ns/1ps

module tb_stage_c_owner;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cancel = 1'b0;
    logic scanner_enable = 1'b0;
    logic parser_handoff = 1'b0;
    logic adapter_outstanding = 1'b0;
    logic scanner_req = 1'b0;
    logic [22:0] scanner_addr = 23'd0;
    logic scanner_ready, scanner_valid;
    logic [7:0] scanner_data;
    logic parser_req = 1'b0;
    logic [22:0] parser_addr = 23'd0;
    logic parser_ready, parser_valid;
    logic [7:0] parser_data;
    logic client_req;
    logic [22:0] client_addr;
    logic client_ready = 1'b0;
    logic client_valid = 1'b0;
    logic [7:0] client_data = 8'h00;
    logic [1:0] owner;
    logic parser_owned, transition_error;
    logic [31:0] transition_count;

    always #5 clk = ~clk;

    ym2610_golden_stage_c_owner dut (.*);

    task automatic check_known;
        begin
            if ((^{scanner_ready, scanner_valid, scanner_data,
                    parser_ready, parser_valid, parser_data, client_req,
                    client_addr, owner, parser_owned, transition_error,
                    transition_count}) === 1'bx)
                $fatal(1, "owner X/Z");
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        scanner_enable = 1'b1;
        @(posedge clk);
        #1;
        check_known();
        if (owner != 2'd1 || parser_owned)
            $fatal(1, "scanner owner not acquired");

        scanner_req = 1'b1;
        scanner_addr = 23'h123456;
        client_ready = 1'b0;
        repeat (3) begin
            @(posedge clk);
            #1;
            if (!client_req || client_addr != 23'h123456 || scanner_ready)
                $fatal(1, "scanner request/address hold failure");
        end
        client_ready = 1'b1;
        adapter_outstanding = 1'b1;
        @(posedge clk);
        #1;
        if (!scanner_ready || parser_ready)
            $fatal(1, "scanner accept routing failure");

        scanner_req = 1'b0;
        client_ready = 1'b0;
        parser_handoff = 1'b1;
        parser_addr = 23'h654321;
        repeat (3) begin
            @(posedge clk);
            #1;
            if (owner != 2'd1 || client_req || parser_ready)
                $fatal(1, "owner switched with outstanding response");
        end

        client_data = 8'ha5;
        client_valid = 1'b1;
        @(posedge clk);
        #1;
        if (!scanner_valid || scanner_data != 8'ha5 || parser_valid)
            $fatal(1, "scanner response routing failure");
        client_valid = 1'b0;
        adapter_outstanding = 1'b0;

        // Two fully quiet clk_sys cycles are required before parser ownership.
        @(posedge clk);
        #1;
        if (owner != 2'd1)
            $fatal(1, "owner switched before quiet fence");
        @(posedge clk);
        #1;
        if (owner != 2'd2 || !parser_owned || transition_count != 1)
            $fatal(1, "parser handoff failed owner=%0d count=%0d",
                   owner, transition_count);

        parser_req = 1'b1;
        client_ready = 1'b1;
        @(posedge clk);
        #1;
        if (!client_req || client_addr != 23'h654321 || !parser_ready ||
            scanner_ready)
            $fatal(1, "parser request routing failure");
        client_data = 8'h5a;
        client_valid = 1'b1;
        @(posedge clk);
        #1;
        if (!parser_valid || parser_data != 8'h5a || scanner_valid)
            $fatal(1, "parser response routing failure");
        client_valid = 1'b0;
        parser_req = 1'b0;
        client_ready = 1'b0;

        cancel = 1'b1;
        @(posedge clk);
        #1;
        if (owner != 2'd0 || client_req || parser_owned ||
            transition_error || transition_count != 0)
            $fatal(1, "cancel did not return safe NONE");

        $display("STAGE_C_OWNER PASS quiet_cycles=2 transitions=1 concurrency=0 xz=0");
        $finish;
    end
endmodule

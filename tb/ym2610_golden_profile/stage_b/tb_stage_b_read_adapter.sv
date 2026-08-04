`timescale 1ns/1ps

module tb_stage_b_read_adapter;
    logic clk = 0;
    logic reset = 1;
    logic cancel = 0;
    logic download_active = 0;
    logic [7:0] generation = 1;
    logic client_req = 0;
    logic [22:0] client_addr = 0;
    logic client_ready, client_valid;
    logic [7:0] client_data;
    logic file_req;
    logic [22:0] file_addr;
    logic file_ready = 0;
    logic file_valid = 0;
    logic [7:0] file_data = 0;
    logic outstanding, timeout_error, stale_response_error;
    logic [31:0] accepted_count, response_count;

    always #5 clk = ~clk;

    ym2610_golden_stage_b_read_adapter #(
        .TIMEOUT_CYCLES(12)
    ) dut (
        .clk(clk), .reset(reset), .cancel(cancel),
        .download_active(download_active), .load_generation(generation),
        .client_req(client_req), .client_addr(client_addr),
        .client_ready(client_ready), .client_valid(client_valid),
        .client_data(client_data), .file_req(file_req), .file_addr(file_addr),
        .file_ready(file_ready), .file_valid(file_valid), .file_data(file_data),
        .outstanding(outstanding), .timeout_error(timeout_error),
        .stale_response_error(stale_response_error),
        .accepted_count(accepted_count), .response_count(response_count)
    );

    initial begin
        repeat (3) @(posedge clk);
        reset = 0;
        repeat (3) @(posedge clk);

        client_addr = 23'h12345;
        client_req = 1;
        repeat (3) @(posedge clk);
        if (!file_req || file_addr != 23'h12345 || !outstanding)
            $fatal(1, "request was not held");
        client_addr = 23'h54321;
        repeat (2) @(posedge clk);
        if (file_addr != 23'h12345)
            $fatal(1, "live client address replaced captured address");
        file_ready = 1;
        @(posedge clk);
        client_req = 0;
        file_ready = 0;
        repeat (2) @(posedge clk);
        file_data = 8'h6a;
        file_valid = 1;
        @(posedge clk);
        @(negedge clk);
        if (!client_valid || client_data != 8'h6a)
            $fatal(1, "captured response data contract");
        file_valid = 0;
        @(posedge clk);
        if (outstanding || accepted_count != 1 || response_count != 1)
            $fatal(1, "captured response contract");

        // Cancel an accepted generation and present its old response.
        client_addr = 23'h22222;
        client_req = 1;
        file_ready = 1;
        repeat (2) @(posedge clk);
        client_req = 0;
        file_ready = 0;
        generation = 2;
        cancel = 1;
        @(posedge clk);
        cancel = 0;
        file_valid = 1;
        repeat (2) @(posedge clk);
        file_valid = 0;
        repeat (3) @(posedge clk);
        if (!stale_response_error || client_valid || outstanding)
            $fatal(1, "stale generation response was delivered");

        // A new download clears sticky diagnostics; a never-accepted request
        // must time out and deassert permanently.
        download_active = 1;
        repeat (2) @(posedge clk);
        download_active = 0;
        repeat (3) @(posedge clk);
        if (stale_response_error || timeout_error)
            $fatal(1, "new generation did not clear adapter diagnostics");
        client_addr = 23'h33333;
        client_req = 1;
        repeat (20) @(posedge clk);
        client_req = 0;
        if (!timeout_error || file_req || outstanding)
            $fatal(1, "request timeout contract");

        $display("READ_ADAPTER_RESULT PASS accepted=%0d responses=%0d timeout=1 stale=1",
                 accepted_count, response_count);
        $finish;
    end
endmodule

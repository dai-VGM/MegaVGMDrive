`timescale 1ns/1ps

module tb_ym2610b_metal_slug_reject_serial_observer;
    localparam int CLOCKS_PER_BIT = 10;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic capture = 1'b0;
    logic [7:0] reject_code = 8'h0b;
    logic [3:0] classification = 4'h3;
    logic [31:0] sample_count = 32'h0123_4567;
    logic [31:0] vgm_pc = 32'h0003_b40d;
    logic [31:0] loop_count = 32'h0000_0002;
    logic ym_port = 1'b1;
    logic [7:0] ym_register = 8'h28;
    logic [7:0] ym_value = 8'hf0;
    logic [3:0] bus_state = 4'h2;
    logic [7:0] bus_dout = 8'h80;
    logic busy_timeout = 1'b0;
    logic [15:0] bus_watchdog = 16'h1234;
    logic [23:0] adpcma_logical = 24'h012345;
    logic [23:0] adpcmb_logical = 24'h234567;
    logic a_current_hit = 1'b0;
    logic a_next_hit = 1'b1;
    logic b_current_hit = 1'b1;
    logic b_next_hit = 1'b0;
    logic request_active = 1'b0;
    logic request_pending = 1'b1;
    logic request_space_b = 1'b0;
    logic [23:0] request_logical = 24'h012345;
    logic response_valid = 1'b1;
    logic response_hit = 1'b0;
    logic response_space_b = 1'b0;
    logic [22:0] response_file_addr = 23'h000000;
    logic last_fill_valid = 1'b1;
    logic last_fill_space_b = 1'b1;
    logic [23:0] last_fill_logical = 24'h234566;
    logic uart_tx, frozen, sent;
    string line, expected;

    always #5 clk = ~clk;

    ym2610b_metal_slug_reject_serial_observer #(
        .CLK_HZ(100), .BAUD(10), .FILE_ADDR_WIDTH(23)
    ) dut (.*);

    task automatic pulse_capture;
        begin
            @(negedge clk); capture = 1'b1;
            @(negedge clk); capture = 1'b0;
        end
    endtask

    task automatic receive_byte(output logic [7:0] value);
        integer bit_index;
        begin
            value = 8'd0;
            @(negedge uart_tx);
            repeat (CLOCKS_PER_BIT / 2) @(posedge clk);
            if (uart_tx !== 1'b0) $fatal(1, "invalid UART start bit");
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (CLOCKS_PER_BIT) @(posedge clk);
                value[bit_index] = uart_tx;
            end
            repeat (CLOCKS_PER_BIT) @(posedge clk);
            if (uart_tx !== 1'b1) $fatal(1, "invalid UART stop bit");
        end
    endtask

    task automatic receive_line(output string value);
        logic [7:0] character;
        begin
            value = "";
            character = 8'd0;
            while (character != 8'h0a) begin
                receive_byte(character);
                value = {value, character};
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        repeat (3) @(posedge clk);
        if (uart_tx !== 1'b1 || frozen || sent)
            $fatal(1, "idle observer state failed");

        // Change live inputs with capture: the observer must freeze the
        // previous production cycle, not post-reject reset values.
        @(negedge clk);
        sample_count = 32'hdead_beef;
        vgm_pc = 32'hfeed_cafe;
        capture = 1'b1;
        @(negedge clk);
        capture = 1'b0;
        receive_line(line);
        expected = {"MS_REJECT code=0B class=RANGE scan_class=3 ",
                    "sample=0x01234567 pc=0x0003B40D loop=0x00000002 ",
                    "port=1 reg=28 value=F0 bus_state=2 dout=80 busy=0 ",
                    "watchdog=1234 a_addr=012345 a_bank=0 a_map_hit=0 ",
                    "a_current_hit=0 a_next_hit=1 b_addr=234567 ",
                    "b_map_hit=X b_current_hit=1 b_next_hit=0 req_space=A ",
                    "req_addr=012345 req_active=0 req_pending=1 rsp_valid=1 ",
                    "rsp_space=A rsp_hit=0 rsp_file=000000 fill_valid=1 ",
                    "fill_space=B fill_addr=234566", 8'h0d, 8'h0a};
        if (line != expected)
            $fatal(1, "first line mismatch\nGOT: %s\nEXP: %s", line, expected);
        if (!frozen || !sent) $fatal(1, "first snapshot did not freeze/send");
        if (dut.snap_sample_count != 32'h0123_4567 ||
            dut.snap_vgm_pc != 32'h0003_b40d)
            $fatal(1, "previous-cycle context was not retained");

        // Stable reject cannot overwrite or transmit another line.
        reject_code = 8'h0d;
        repeat (3) pulse_capture();
        repeat (100) @(posedge clk);
        if (dut.snap_code != 8'h0b || !uart_tx)
            $fatal(1, "one-shot snapshot was overwritten/retransmitted");

        // A new download/reset rearms one new snapshot with X placeholders
        // for unavailable response/fill values.
        reset = 1'b1;
        sample_count = 32'haabb_ccdd; vgm_pc = 32'h0102_0304;
        loop_count = 32'h0000_0005; ym_port = 1'b0;
        ym_register = 8'h10; ym_value = 8'h80; bus_state = 4'h3;
        bus_dout = 8'h80; busy_timeout = 1'b1; bus_watchdog = 16'hffff;
        adpcma_logical = 24'hf12345; adpcmb_logical = 24'h654321;
        a_current_hit = 1'b0; a_next_hit = 1'b0;
        b_current_hit = 1'b0; b_next_hit = 1'b0;
        request_active = 1'b1; request_pending = 1'b0;
        request_space_b = 1'b1; request_logical = 24'h654321;
        response_valid = 1'b0; response_hit = 1'b0; response_space_b = 1'b1;
        response_file_addr = 23'h123456; last_fill_valid = 1'b0;
        last_fill_space_b = 1'b0; last_fill_logical = 24'habcdef;
        reject_code = 8'h0a; classification = 4'h4;
        repeat (2) @(posedge clk);
        reset = 1'b0;
        repeat (3) @(posedge clk);
        pulse_capture();
        receive_line(line);
        expected = {"MS_REJECT code=0A class=BUSY scan_class=4 ",
                    "sample=0xAABBCCDD pc=0x01020304 loop=0x00000005 ",
                    "port=0 reg=10 value=80 bus_state=3 dout=80 busy=1 ",
                    "watchdog=FFFF a_addr=F12345 a_bank=F a_map_hit=X ",
                    "a_current_hit=0 a_next_hit=0 b_addr=654321 ",
                    "b_map_hit=X b_current_hit=0 b_next_hit=0 req_space=B ",
                    "req_addr=654321 req_active=1 req_pending=0 rsp_valid=0 ",
                    "rsp_space=X rsp_hit=X rsp_file=XXXXXX fill_valid=0 ",
                    "fill_space=X fill_addr=XXXXXX", 8'h0d, 8'h0a};
        if (line != expected)
            $fatal(1, "reload line mismatch\nGOT: %s\nEXP: %s", line, expected);
        if (!frozen || !sent) $fatal(1, "reload did not rearm observer");

        $display("METAL_SLUG_REJECT_UART_OBSERVER_PASS idle=1 previous_cycle=1 one_shot=1 reload=1 x_fields=1");
        $finish;
    end
endmodule

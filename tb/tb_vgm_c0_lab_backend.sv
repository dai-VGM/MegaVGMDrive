`timescale 1ns/1ps

module tb_vgm_c0_lab_backend;
    logic clk = 1'b0;
    logic reset = 1'b1;

    logic smoke_rd_req = 1'b0;
    logic [18:0] smoke_rd_addr = 19'd0;
    wire smoke_rd_ready;
    wire smoke_rd_valid;
    wire [7:0] smoke_rd_data;
    wire smoke_payload_present;
    wire [18:0] smoke_payload_length;
    wire [15:0] smoke_last_read_word0_debug;
    wire [15:0] smoke_last_read_word1_debug;
    wire [15:0] smoke_probe_write_word0_debug;
    wire [15:0] smoke_probe_write_word6_debug;

    logic payload_tap_valid = 1'b0;
    logic [18:0] payload_tap_addr = 19'd0;
    logic [7:0] payload_tap_data = 8'd0;

    always #5 clk = ~clk;

    vgm_c0_lab_backend dut (
        .clk(clk),
        .reset(reset),
        .ioctl_download(1'b0),
        .ioctl_wr(1'b0),
        .ioctl_addr(32'd0),
        .ioctl_dout(8'd0),
        .ioctl_index(8'd1),
        .ioctl_wait(),
        .mem_rd_req(1'b0),
        .mem_rd_addr(23'd0),
        .mem_rd_ready(),
        .mem_rd_valid(),
        .mem_rd_data(),
        .payload_tap_valid(payload_tap_valid),
        .payload_tap_addr(payload_tap_addr),
        .payload_tap_data(payload_tap_data),
        .type80_block_dest(32'h0001_7100),
        .type80_block_size(32'h0000_1208),
        .smoke_rd_req(smoke_rd_req),
        .smoke_rd_ready(smoke_rd_ready),
        .smoke_rd_addr(smoke_rd_addr),
        .smoke_rd_valid(smoke_rd_valid),
        .smoke_rd_data(smoke_rd_data),
        .smoke_payload_present(smoke_payload_present),
        .smoke_payload_length(smoke_payload_length),
        .smoke_write_req_count_debug(),
        .smoke_write_count_debug(),
        .smoke_write_blocked_count_debug(),
        .smoke_write_status_debug(),
        .smoke_header_skip_count_debug(),
        .smoke_last_write_index_debug(),
        .smoke_last_write_addr_debug(),
        .smoke_last_write_lane_debug(),
        .smoke_last_write_data_debug(),
        .smoke_read_count_debug(),
        .smoke_last_read_index_debug(),
        .smoke_last_read_addr_debug(),
        .smoke_last_read_lane_debug(),
        .smoke_last_read_word0_debug(smoke_last_read_word0_debug),
        .smoke_last_read_word1_debug(smoke_last_read_word1_debug),
        .smoke_last_read_data_debug(),
        .smoke_base_addr_debug(),
        .smoke_probe_write_index_debug(),
        .smoke_probe_write_word_debug(),
        .smoke_probe_write_lane_debug(),
        .smoke_probe_write_addr_debug(),
        .smoke_probe_write_count_debug(),
        .smoke_probe_write_flags_debug(),
        .smoke_probe_write_word0_debug(smoke_probe_write_word0_debug),
        .smoke_probe_write_word6_debug(smoke_probe_write_word6_debug),
        .load_busy(),
        .load_done(),
        .load_done_pulse(),
        .play_ready_pulse(),
        .load_error(),
        .overflow_error(),
        .file_size(),
        .magic_debug(),
        .ddram_busy(1'b0),
        .ddram_burstcnt(),
        .ddram_addr(),
        .ddram_dout(64'd0),
        .ddram_dout_ready(1'b0),
        .ddram_rd(),
        .ddram_din(),
        .ddram_be(),
        .ddram_we()
    );

    task write_payload(input logic [18:0] addr, input logic [7:0] data);
        begin
            @(negedge clk);
            payload_tap_valid <= 1'b1;
            payload_tap_addr <= addr;
            payload_tap_data <= data;
            @(posedge clk);
            @(negedge clk);
            payload_tap_valid <= 1'b0;
        end
    endtask

    task read_payload(input logic [18:0] addr, output logic [7:0] data);
        begin
            @(negedge clk);
            smoke_rd_req <= 1'b1;
            smoke_rd_addr <= addr;
            @(posedge clk);
            @(negedge clk);
            smoke_rd_req <= 1'b0;
            while (!smoke_rd_valid) @(posedge clk);
            data = smoke_rd_data;
        end
    endtask

    initial begin
        logic [7:0] d0;
        logic [7:0] d2;

        repeat (4) @(posedge clk);
        reset <= 1'b0;

        write_payload(19'd0, 8'h80);
        write_payload(19'd1, 8'h80);
        write_payload(19'd2, 8'h81);
        write_payload(19'd3, 8'h80);
        @(posedge clk);

        if (!smoke_payload_present || smoke_payload_length != 19'h01200) begin
            $display("FAIL payload present=%0d len=%05h",
                     smoke_payload_present, smoke_payload_length);
            $finish;
        end
        if (smoke_probe_write_word0_debug != 16'h8080 ||
            smoke_probe_write_word6_debug != 16'h8180) begin
            $display("FAIL write words W0=%04h W2=%04h",
                     smoke_probe_write_word0_debug,
                     smoke_probe_write_word6_debug);
            $finish;
        end

        read_payload(19'd0, d0);
        read_payload(19'd2, d2);
        if (d0 != 8'h80 || d2 != 8'h81) begin
            $display("FAIL read d0=%02h d2=%02h", d0, d2);
            $finish;
        end
        if (smoke_last_read_word0_debug != 16'h8080 ||
            smoke_last_read_word1_debug != 16'h8180) begin
            $display("FAIL read words D0=%04h D2=%04h",
                     smoke_last_read_word0_debug,
                     smoke_last_read_word1_debug);
            $finish;
        end

        $display("PASS tb_vgm_c0_lab_backend W0=%04h W2=%04h D0=%04h D2=%04h",
                 smoke_probe_write_word0_debug,
                 smoke_probe_write_word6_debug,
                 smoke_last_read_word0_debug,
                 smoke_last_read_word1_debug);
        $finish;
    end
endmodule

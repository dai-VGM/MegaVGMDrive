`timescale 1ns/1ps

module tb_vgm_file_loader;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;
    logic [15:0] ioctl_index = 16'd0;
    logic [7:0] rd_data;
    logic load_busy;
    logic load_done;
    logic load_done_pulse;
    logic load_error;
    logic overflow_error;
    logic [18:0] file_size;
    logic [31:0] magic_debug;
    logic [17:0] rd_addr = 18'd0;
    logic [18:0] normal_file_size;
    logic [31:0] normal_magic_debug;
    integer load_done_pulse_count = 0;

    vgm_file_loader #(
        .ADDR_WIDTH       (18),
        .ACCEPT_ANY_INDEX (1'b0),
        .FILE_INDEX       (16'd1)
    ) dut (
        .clk              (clk),
        .reset            (reset),
        .ioctl_download   (ioctl_download),
        .ioctl_wr         (ioctl_wr),
        .ioctl_addr       (ioctl_addr),
        .ioctl_dout       (ioctl_dout),
        .ioctl_index      (ioctl_index),
        .rd_addr          (rd_addr),
        .rd_data          (rd_data),
        .load_busy        (load_busy),
        .load_done        (load_done),
        .load_done_pulse  (load_done_pulse),
        .load_error       (load_error),
        .overflow_error   (overflow_error),
        .file_size        (file_size),
        .magic_debug      (magic_debug)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (reset) begin
            load_done_pulse_count <= 0;
        end else if (load_done_pulse) begin
            load_done_pulse_count <= load_done_pulse_count + 1;
        end
    end

    task write_byte(input [26:0] addr, input [7:0] data);
        begin
            @(posedge clk);
            ioctl_addr <= addr;
            ioctl_dout <= data;
            ioctl_wr <= 1'b1;
            @(posedge clk);
            ioctl_wr <= 1'b0;
        end
    endtask

    task download_tiny_vgm(input [15:0] index);
        begin
            ioctl_index <= index;
            ioctl_download <= 1'b1;
            write_byte(27'd0, "V");
            write_byte(27'd1, "g");
            write_byte(27'd2, "m");
            write_byte(27'd3, " ");
            write_byte(27'd4, 8'h66);
            @(posedge clk);
            ioctl_download <= 1'b0;
            repeat (3) @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset <= 1'b0;
        repeat (2) @(posedge clk);

        download_tiny_vgm(16'd0);

        if (load_done || load_busy || load_error || file_size != 19'd0) begin
            $display("FAIL index_mismatch done=%0b busy=%0b error=%0b size=%0d",
                     load_done, load_busy, load_error, file_size);
            $finish;
        end

        download_tiny_vgm(16'd1);

        if (!load_done || load_error || overflow_error || file_size != 19'd5 || load_done_pulse_count != 1) begin
            $display("FAIL normal_load done=%0b error=%0b overflow=%0b size=%0d",
                     load_done, load_error, overflow_error, file_size);
            $finish;
        end

        if (magic_debug != 32'h206d6756) begin
            $display("FAIL magic_debug=%08h", magic_debug);
            $finish;
        end

        normal_file_size = file_size;
        normal_magic_debug = magic_debug;

        rd_addr <= 18'd4;
        repeat (2) @(posedge clk);
        if (rd_data != 8'h66) begin
            $display("FAIL rd_data=%02h", rd_data);
            $finish;
        end

        ioctl_download <= 1'b1;
        write_byte(27'd70000, 8'haa);
        @(posedge clk);
        ioctl_download <= 1'b0;
        repeat (3) @(posedge clk);

        if (!load_done || load_error || overflow_error || file_size != 19'd70001) begin
            $display("FAIL above_64k_load done=%0b error=%0b overflow=%0b size=%0d",
                     load_done, load_error, overflow_error, file_size);
            $finish;
        end

        rd_addr <= 18'd70000;
        repeat (2) @(posedge clk);
        if (rd_data != 8'haa) begin
            $display("FAIL above_64k_rd_data=%02h", rd_data);
            $finish;
        end

        ioctl_download <= 1'b1;
        write_byte(27'd262144, 8'hbb);
        @(posedge clk);
        ioctl_download <= 1'b0;
        repeat (3) @(posedge clk);

        if (!load_error || !overflow_error || load_done) begin
            $display("FAIL overflow done=%0b error=%0b overflow=%0b",
                     load_done, load_error, overflow_error);
            $finish;
        end

        $display("PASS tb_vgm_file_loader normal_size=%0d normal_magic=%08h overflow_error=%0b",
                 normal_file_size, normal_magic_debug, overflow_error);
        $finish;
    end

endmodule

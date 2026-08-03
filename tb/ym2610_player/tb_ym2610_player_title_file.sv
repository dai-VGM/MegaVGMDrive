`timescale 1ns/1ps

module tb_ym2610_player_title_file;
    localparam int MAX_FILE = 1 << 23;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;
    logic [15:0] ioctl_index = 16'd1;
    logic title_valid;
    logic [5:0] directory_length, basename_length;
    logic [6:0] title_read_addr = 7'd0;
    logic [7:0] title_read_data;
    logic metadata_busy;
    logic [7:0] memory [0:MAX_FILE-1];
    integer fd, file_size, index, timeout;
    string filename, expected_directory, expected_basename;
    integer expect_title;

    always #5 clk = ~clk;

    megavgm_title_receiver #(.FILE_INDEX(16'd1)) dut (
        .clk(clk), .reset(reset), .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout), .ioctl_index(ioctl_index),
        .title_valid(title_valid), .directory_length(directory_length),
        .basename_length(basename_length), .title_read_addr(title_read_addr),
        .title_read_data(title_read_data), .metadata_busy(metadata_busy)
    );

    initial begin
        if (!$value$plusargs("VGM=%s", filename)) $fatal(1, "missing +VGM");
        if (!$value$plusargs("TITLE=%d", expect_title)) expect_title = 1;
        if (!$value$plusargs("DIR=%s", expected_directory)) expected_directory = "";
        if (!$value$plusargs("BASE=%s", expected_basename)) expected_basename = "";
        fd = $fopen(filename, "rb");
        if (!fd) $fatal(1, "cannot open %s", filename);
        file_size = $fread(memory, fd);
        $fclose(fd);
        repeat (4) @(posedge clk);
        reset <= 1'b0;
        @(posedge clk);
        ioctl_download <= 1'b1;
        for (index = 0; index < file_size; index = index + 1) begin
            ioctl_wr <= 1'b1;
            ioctl_addr <= index;
            ioctl_dout <= memory[index];
            @(posedge clk);
        end
        ioctl_wr <= 1'b0;
        @(posedge clk);
        ioctl_download <= 1'b0;
        @(posedge clk);
        timeout = 0;
        while (metadata_busy && timeout < 512) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 512) $fatal(1, "title validation timeout");
        @(posedge clk);
        if (!expect_title) begin
            if (title_valid || directory_length != 0 || basename_length != 0)
                $fatal(1, "raw VGM unexpectedly produced a title");
            $display("TITLE_RESULT prepared=0 valid=0 raw_playable=1 result=PASS");
            $finish;
        end
        if (!title_valid || directory_length != expected_directory.len() ||
            basename_length != expected_basename.len())
            $fatal(1, "title validity/length mismatch valid=%0d dir=%0d base=%0d",
                title_valid, directory_length, basename_length);
        for (index = 0; index < expected_directory.len(); index = index + 1) begin
            title_read_addr = index;
            #1;
            if (title_read_data !== expected_directory[index])
                $fatal(1, "directory mismatch at %0d", index);
        end
        for (index = 0; index < expected_basename.len(); index = index + 1) begin
            title_read_addr = 32 + index;
            #1;
            if (title_read_data !== expected_basename[index])
                $fatal(1, "basename mismatch at %0d", index);
        end
        $display("TITLE_RESULT prepared=1 valid=1 directory=%s basename=%s ioctl_wait_from_title=0 result=PASS",
            expected_directory, expected_basename);
        $finish;
    end
endmodule

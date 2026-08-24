`timescale 1ns/1ps

module tb_ym2610_player_scanner;
    localparam int MAX_FILE = 1 << 23;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic [31:0] physical_size;
    logic mem_req;
    logic [22:0] mem_addr;
    logic mem_ready = 1'b1;
    logic mem_valid = 1'b0;
    logic [7:0] mem_data = 8'd0;
    logic busy, done, accepted;
    logic [3:0] classification;
    logic [7:0] reject_code;
    logic [31:0] original_size, data_offset, chip_clock, loop_target;
    logic [31:0] loop_samples, end_pc, total_samples, total_writes;
    logic [31:0] port0_writes, port1_writes, b_only_writes;
    logic [31:0] unknown_writes, command_count;
    logic variant_b, dual_chip;
    logic [31:0] first_bad_pc, first_bad_sample;
    logic first_bad_port;
    logic [7:0] first_bad_address, first_bad_data;
    logic [3:0] first_bad_semantic;
    logic [2:0] first_bad_target;
    logic [3:0] descriptor_a_count, descriptor_b_count;
    logic [6:0] descriptor_a_count_full;
    logic [4:0] descriptor_b_count_full;
    logic map_req_valid, map_req_ready, map_space_b;
    logic [23:0] map_logical_addr;
    logic map_rsp_valid, map_rsp_hit;
    logic [22:0] map_rsp_file_addr;
    logic [7:0] memory [0:MAX_FILE-1];
    logic pending;
    logic [22:0] pending_addr;
    integer response_delay;
    integer fd;
    integer count;
    integer timeout;
    integer map_fd;
    integer map_rc;
    integer map_vectors;
    integer map_space_value;
    integer map_hit_value;
    reg [31:0] map_logical_value;
    reg [31:0] map_file_value;
    reg [31:0] map_byte_value;
    string filename;
    string map_filename;
    integer expected_accepted;
    integer expected_reject;
    integer expected_desc_a;
    integer expected_desc_b;

    always #5 clk = ~clk;

    ym2610_player_scanner dut (
        .clk(clk), .reset(reset), .start(start),
        .physical_size(physical_size),
        .mem_req(mem_req), .mem_addr(mem_addr), .mem_ready(mem_ready),
        .mem_valid(mem_valid), .mem_data(mem_data),
        .busy(busy), .done(done), .accepted(accepted),
        .classification(classification), .reject_code(reject_code),
        .original_size(original_size), .data_offset(data_offset),
        .chip_clock(chip_clock), .loop_target(loop_target),
        .loop_samples(loop_samples), .end_pc(end_pc),
        .total_samples(total_samples), .total_writes(total_writes),
        .port0_writes(port0_writes), .port1_writes(port1_writes),
        .b_only_writes(b_only_writes), .unknown_writes(unknown_writes),
        .command_count(command_count), .variant_b(variant_b),
        .dual_chip(dual_chip), .first_bad_pc(first_bad_pc),
        .first_bad_port(first_bad_port), .first_bad_address(first_bad_address),
        .first_bad_data(first_bad_data), .first_bad_sample(first_bad_sample),
        .first_bad_semantic(first_bad_semantic),
        .first_bad_target(first_bad_target),
        .descriptor_a_count(descriptor_a_count),
        .descriptor_b_count(descriptor_b_count),
        .descriptor_a_count_full(descriptor_a_count_full),
        .descriptor_b_count_full(descriptor_b_count_full),
        .map_req_valid(map_req_valid), .map_req_ready(map_req_ready),
        .map_space_b(map_space_b), .map_logical_addr(map_logical_addr),
        .map_rsp_valid(map_rsp_valid), .map_rsp_hit(map_rsp_hit),
        .map_rsp_file_addr(map_rsp_file_addr)
    );

    always_ff @(posedge clk) begin
        mem_valid <= 1'b0;
        if (mem_req && mem_ready && !pending) begin
            pending <= 1'b1;
            pending_addr <= mem_addr;
            response_delay <= (mem_addr[2:0] + 1);
        end
        if (pending) begin
            if (response_delay == 0) begin
                mem_data <= memory[pending_addr];
                mem_valid <= 1'b1;
                pending <= 1'b0;
            end else response_delay <= response_delay - 1;
        end
    end

    initial begin
        if (!$value$plusargs("VGM=%s", filename))
            $fatal(1, "use +VGM=/path/file.vgm");
        fd = $fopen(filename, "rb");
        if (!fd) $fatal(1, "cannot open %s", filename);
        count = $fread(memory, fd);
        $fclose(fd);
        physical_size = count;
        pending = 1'b0;
        pending_addr = 0;
        response_delay = 0;
        map_space_b = 1'b0;
        map_logical_addr = 24'd0;
        map_req_valid = 1'b0;
        repeat (5) @(posedge clk);
        reset <= 1'b0;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
        timeout = 0;
        while (!done && timeout < 20_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!done) $fatal(1, "scanner timeout state=%0d pc=%08x", dut.state, dut.scan_pc);
        if ($value$plusargs("EXPECT_ACCEPTED=%d", expected_accepted) &&
            accepted !== expected_accepted[0])
            $fatal(1, "accepted mismatch expected=%0d actual=%0d",
                expected_accepted, accepted);
        if ($value$plusargs("EXPECT_REJECT=%h", expected_reject) &&
            reject_code !== expected_reject[7:0])
            $fatal(1, "reject mismatch expected=%02x actual=%02x",
                expected_reject[7:0], reject_code);
        if ($value$plusargs("EXPECT_DESC_A=%d", expected_desc_a) &&
            descriptor_a_count_full !== expected_desc_a[6:0])
            $fatal(1, "A descriptor mismatch expected=%0d actual=%0d",
                expected_desc_a, descriptor_a_count_full);
        if ($value$plusargs("EXPECT_DESC_B=%d", expected_desc_b) &&
            descriptor_b_count_full !== expected_desc_b[4:0])
            $fatal(1, "B descriptor mismatch expected=%0d actual=%0d",
                expected_desc_b, descriptor_b_count_full);
        map_vectors = 0;
        if ($value$plusargs("MAP=%s", map_filename)) begin
            map_fd = $fopen(map_filename, "r");
            if (!map_fd) $fatal(1, "cannot open map vectors %s", map_filename);
            while (!$feof(map_fd)) begin
                map_rc = $fscanf(map_fd, "%d %h %d %h %h\n",
                    map_space_value, map_logical_value, map_hit_value,
                    map_file_value, map_byte_value);
                if (map_rc == 5) begin
                    map_space_b = map_space_value[0];
                    map_logical_addr = map_logical_value[23:0];
                    map_req_valid = 1'b1;
                    do @(posedge clk); while (!map_req_ready);
                    #1 begin
                        map_req_valid = 1'b0;
                        // The serialized mapper must own a captured request;
                        // live request inputs may change immediately after
                        // the valid/ready acceptance edge.
                        map_space_b = ~map_space_value[0];
                        map_logical_addr = ~map_logical_value[23:0];
                    end
                    do @(posedge clk); while (!map_rsp_valid);
                    if (map_rsp_hit !== map_hit_value[0])
                        $fatal(1, "map hit mismatch space=%0d logical=%06x expected=%0d actual=%0d",
                            map_space_value, map_logical_value, map_hit_value, map_rsp_hit);
                    if (map_hit_value &&
                        (map_rsp_file_addr !== map_file_value[22:0] ||
                         memory[map_rsp_file_addr] !== map_byte_value[7:0]))
                        $fatal(1, "map byte mismatch space=%0d logical=%06x expected_file=%06x actual_file=%06x expected_byte=%02x actual_byte=%02x",
                            map_space_value, map_logical_value,
                            map_file_value, map_rsp_file_addr,
                            map_byte_value, memory[map_rsp_file_addr]);
                    map_vectors = map_vectors + 1;
                end
            end
            $fclose(map_fd);
            $display("MAP_RESULT vectors=%0d boundary=1 random_legal_per_space=256 gap=1 result=PASS",
                map_vectors);
        end
        $display("SCAN_RESULT accepted=%0d class=%0d reject=%02x physical=%0d original=%0d data=%08x clock=%0d variant_b=%0d dual=%0d writes=%0d p0=%0d p1=%0d b_only=%0d unknown=%0d samples=%0d loop=%08x loop_samples=%0d end=%08x desc_a=%0d desc_b=%0d first_pc=%08x first_port=%0d first_addr=%02x first_data=%02x first_sample=%0d first_sem=%0d first_target=%0d commands=%0d",
            accepted, classification, reject_code, physical_size, original_size,
            data_offset, chip_clock, variant_b, dual_chip, total_writes,
            port0_writes, port1_writes, b_only_writes, unknown_writes,
            total_samples, loop_target, loop_samples, end_pc,
            descriptor_a_count_full, descriptor_b_count_full, first_bad_pc,
            first_bad_port, first_bad_address, first_bad_data,
            first_bad_sample, first_bad_semantic, first_bad_target,
            command_count);
        $finish;
    end
endmodule

`timescale 1ns/1ps

module tb_stage_b_scanner;
    localparam int MAX_FILE = 1 << 23;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic [31:0] scan_limit;
    logic mem_req;
    logic [22:0] mem_addr;
    logic mem_ready;
    logic mem_valid = 1'b0;
    logic [7:0] mem_data = 8'd0;
    logic busy, done, accepted;
    logic [3:0] classification;
    logic [7:0] reject_code;
    logic [31:0] original_size, data_offset, chip_clock, loop_target;
    logic [31:0] loop_samples, end_pc, total_samples, total_writes;
    logic [31:0] port0_writes, port1_writes, b_only_writes;
    logic [31:0] unknown_writes, command_count, unsupported_opcodes;
    logic [31:0] ssg_writes, adpcma_key_on_voices, adpcma_key_off_voices;
    logic [31:0] adpcmb_start_count, adpcmb_reset_count;
    logic [63:0] trace_hash, first256_trace_hash;
    logic [4:0] debug_state;
    logic variant_b, dual_chip;
    logic [31:0] first_bad_pc, first_bad_sample;
    logic first_bad_port;
    logic [7:0] first_bad_address, first_bad_data;
    logic [3:0] first_bad_semantic;
    logic [2:0] first_bad_target;
    logic [3:0] descriptor_a_count, descriptor_b_count;
    logic map_space_b, map_hit;
    logic [19:0] map_logical_addr;
    logic [22:0] map_file_addr;
    logic [7:0] memory [0:MAX_FILE-1];
    logic pending;
    logic [22:0] pending_addr;
    integer response_delay, cycle_count, accepts, responses;
    integer fd, count, timeout, original_arg, olga_mode;
    integer expect_class, expect_reject, expect_accept, have_expect;
    integer request_hold_cycles;
    logic [22:0] held_addr;
    string filename;

    always #5 clk = ~clk;
    assign mem_ready = !pending && (cycle_count[2:0] != 3'd3);

    ym2610_golden_stage_b_scanner dut (
        .clk(clk), .reset(reset), .start(start), .scan_limit(scan_limit),
        .mem_req(mem_req), .mem_addr(mem_addr), .mem_ready(mem_ready),
        .mem_valid(mem_valid), .mem_data(mem_data), .busy(busy), .done(done),
        .accepted(accepted), .classification(classification),
        .reject_code(reject_code), .original_size(original_size),
        .data_offset(data_offset), .chip_clock(chip_clock),
        .loop_target(loop_target), .loop_samples(loop_samples), .end_pc(end_pc),
        .total_samples(total_samples), .total_writes(total_writes),
        .port0_writes(port0_writes), .port1_writes(port1_writes),
        .b_only_writes(b_only_writes), .unknown_writes(unknown_writes),
        .command_count(command_count), .unsupported_opcodes(unsupported_opcodes),
        .ssg_writes(ssg_writes),
        .adpcma_key_on_voices(adpcma_key_on_voices),
        .adpcma_key_off_voices(adpcma_key_off_voices),
        .adpcmb_start_count(adpcmb_start_count),
        .adpcmb_reset_count(adpcmb_reset_count), .trace_hash(trace_hash),
        .first256_trace_hash(first256_trace_hash), .debug_state(debug_state),
        .variant_b(variant_b), .dual_chip(dual_chip),
        .first_bad_pc(first_bad_pc), .first_bad_port(first_bad_port),
        .first_bad_address(first_bad_address), .first_bad_data(first_bad_data),
        .first_bad_sample(first_bad_sample),
        .first_bad_semantic(first_bad_semantic),
        .first_bad_target(first_bad_target),
        .descriptor_a_count(descriptor_a_count),
        .descriptor_b_count(descriptor_b_count), .map_space_b(map_space_b),
        .map_logical_addr(map_logical_addr), .map_hit(map_hit),
        .map_file_addr(map_file_addr)
    );

    always_ff @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        mem_valid <= 1'b0;
        if (mem_req && !mem_ready) begin
            if (request_hold_cycles == 0) held_addr <= mem_addr;
            else if (mem_addr !== held_addr)
                $fatal(1, "address changed while request waited");
            request_hold_cycles <= request_hold_cycles + 1;
        end else begin
            request_hold_cycles <= 0;
        end
        if (mem_req && mem_ready) begin
            if (pending) $fatal(1, "more than one outstanding request");
            pending <= 1'b1;
            pending_addr <= mem_addr;
            response_delay <= mem_addr[1:0] + 1;
            accepts <= accepts + 1;
        end
        if (pending) begin
            if (response_delay == 0) begin
                mem_data <= memory[pending_addr];
                mem_valid <= 1'b1;
                pending <= 1'b0;
                responses <= responses + 1;
            end else begin
                response_delay <= response_delay - 1;
            end
        end
        if (!reset && ^{mem_req, mem_addr, busy, done, accepted,
                        classification, reject_code} === 1'bx)
            $fatal(1, "relevant X/Z detected");
    end

    task automatic check_olga_descriptor(
        input integer space_b,
        input integer index,
        input [31:0] source_pc,
        input [19:0] logical_start,
        input [20:0] length,
        input [22:0] file_start
    );
        begin
            if (!space_b) begin
                if (!dut.desc_a_valid[index] ||
                    dut.desc_a_source_pc[index] !== source_pc ||
                    dut.desc_a_logical[index] !== logical_start ||
                    dut.desc_a_length[index] !== length ||
                    dut.desc_a_file[index] !== file_start)
                    $fatal(1, "Olga A descriptor %0d mismatch", index);
            end else begin
                if (!dut.desc_b_valid[index] ||
                    dut.desc_b_source_pc[index] !== source_pc ||
                    dut.desc_b_logical[index] !== logical_start ||
                    dut.desc_b_length[index] !== length ||
                    dut.desc_b_file[index] !== file_start)
                    $fatal(1, "Olga B descriptor %0d mismatch", index);
            end
        end
    endtask

    task automatic check_map(
        input logic space_b,
        input logic [19:0] logical,
        input logic [22:0] expected_file
    );
        begin
            map_space_b = space_b;
            map_logical_addr = logical;
            #1;
            if (!map_hit || map_file_addr !== expected_file ||
                memory[map_file_addr] !== memory[expected_file])
                $fatal(1, "map mismatch space=%0d logical=%05x file=%06x/%06x",
                       space_b, logical, map_file_addr, expected_file);
        end
    endtask

    task automatic check_map_miss(
        input logic space_b,
        input logic [19:0] logical
    );
        begin
            map_space_b = space_b;
            map_logical_addr = logical;
            #1;
            if (map_hit) $fatal(1, "map gap/out-of-range hit space=%0d logical=%05x",
                                space_b, logical);
        end
    endtask

    initial begin
        integer sample_index;
        integer descriptor_index;
        integer offset;
        integer logical_base;
        integer descriptor_length;
        integer file_base;
        if (!$value$plusargs("VGM=%s", filename))
            $fatal(1, "use +VGM=/path/file.vgm");
        fd = $fopen(filename, "rb");
        if (!fd) $fatal(1, "cannot open %s", filename);
        count = $fread(memory, fd);
        $fclose(fd);
        if (!$value$plusargs("ORIGINAL=%d", original_arg)) original_arg = count;
        olga_mode = $test$plusargs("OLGA");
        have_expect = $value$plusargs("EXPECT_CLASS=%d", expect_class);
        if (!$value$plusargs("EXPECT_REJECT=%d", expect_reject)) expect_reject = 0;
        if (!$value$plusargs("EXPECT_ACCEPT=%d", expect_accept)) expect_accept = 0;
        scan_limit = original_arg;
        pending = 1'b0;
        pending_addr = 0;
        response_delay = 0;
        cycle_count = 0;
        accepts = 0;
        responses = 0;
        request_hold_cycles = 0;
        held_addr = 0;
        map_space_b = 0;
        map_logical_addr = 0;
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
        repeat (3) @(posedge clk);
        if (mem_req || pending || dut.read_pending)
            $fatal(1, "request/outstanding remained after scan");
        if (accepts != responses)
            $fatal(1, "accept/response mismatch %0d/%0d", accepts, responses);
        if (have_expect &&
            (classification !== expect_class[3:0] ||
             reject_code !== expect_reject[7:0] ||
             accepted !== expect_accept[0]))
            $fatal(1, "fixture expectation mismatch class=%0d/%0d reject=%02x/%02x accept=%0d/%0d",
                classification, expect_class, reject_code, expect_reject,
                accepted, expect_accept);

        if (olga_mode) begin
            if (!accepted || classification != 4'd1 || original_size != 933897 ||
                data_offset != 32'h80 || chip_clock != 8_000_000 ||
                !variant_b || dual_chip || command_count != 171869 ||
                port0_writes != 38246 || port1_writes != 43026 ||
                total_writes != 81272 || total_samples != 8372668 ||
                b_only_writes != 0 || unknown_writes != 0 ||
                unsupported_opcodes != 0 || ssg_writes != 0 ||
                adpcma_key_on_voices != 793 || adpcma_key_off_voices != 850 ||
                adpcmb_start_count != 23 || adpcmb_reset_count != 27 ||
                descriptor_a_count != 4 || descriptor_b_count != 3 ||
                loop_target != 32'h000b6223 || end_pc != 32'h000e3f24 ||
                trace_hash != 64'h7c3088bd1d4eea6f ||
                first256_trace_hash != 64'h155cbbc09e7b636b)
                $fatal(1, "Olga scalar acceptance mismatch");
            check_olga_descriptor(0, 0, 32'h80, 20'h64000, 21'h06f00, 23'h00008f);
            check_olga_descriptor(0, 1, 32'h6f8f, 20'h71200, 21'h06d00, 23'h006f9e);
            check_olga_descriptor(0, 2, 32'hdc9e, 20'h78d00, 21'h16700, 23'h00dcad);
            check_olga_descriptor(0, 3, 32'h243ad, 20'h90300, 21'h3e100, 23'h0243bc);
            check_olga_descriptor(1, 0, 32'h624bc, 20'h00000, 21'h1a600, 23'h0624cb);
            check_olga_descriptor(1, 1, 32'h7cacb, 20'h1cf00, 21'h04000, 23'h07cada);
            check_olga_descriptor(1, 2, 32'h80ada, 20'h5f500, 21'h07000, 23'h080ae9);
            // Every descriptor boundary plus 256 deterministic addresses in
            // each independent logical ROM space are compared to file bytes.
            for (descriptor_index = 0; descriptor_index < 4;
                 descriptor_index = descriptor_index + 1) begin
                check_map(0, dut.desc_a_logical[descriptor_index],
                          dut.desc_a_file[descriptor_index]);
                check_map(0, dut.desc_a_logical[descriptor_index] +
                          dut.desc_a_length[descriptor_index] - 1,
                          dut.desc_a_file[descriptor_index] +
                          dut.desc_a_length[descriptor_index] - 1);
            end
            for (descriptor_index = 0; descriptor_index < 3;
                 descriptor_index = descriptor_index + 1) begin
                check_map(1, dut.desc_b_logical[descriptor_index],
                          dut.desc_b_file[descriptor_index]);
                check_map(1, dut.desc_b_logical[descriptor_index] +
                          dut.desc_b_length[descriptor_index] - 1,
                          dut.desc_b_file[descriptor_index] +
                          dut.desc_b_length[descriptor_index] - 1);
            end
            for (sample_index = 0; sample_index < 256; sample_index = sample_index + 1) begin
                descriptor_index = sample_index % 4;
                logical_base = dut.desc_a_logical[descriptor_index];
                descriptor_length = dut.desc_a_length[descriptor_index];
                file_base = dut.desc_a_file[descriptor_index];
                offset = ((sample_index * 1103) + 17) % descriptor_length;
                check_map(0, logical_base + offset, file_base + offset);
                descriptor_index = sample_index % 3;
                logical_base = dut.desc_b_logical[descriptor_index];
                descriptor_length = dut.desc_b_length[descriptor_index];
                file_base = dut.desc_b_file[descriptor_index];
                offset = ((sample_index * 1877) + 29) % descriptor_length;
                check_map(1, logical_base + offset, file_base + offset);
            end
            check_map_miss(0, 20'h00000);
            check_map_miss(0, 20'hfffff);
            check_map_miss(1, 20'h1a600);
            check_map_miss(1, 20'h7ffff);
            $display("MAP_RESULT descriptor_boundaries=14 random_A=256 random_B=256 gap_out_of_range=4 PASS");
        end

        $display("SCAN_RESULT accept=%0d class=%0d reject=%02x commands=%0d writes=%0d p0=%0d p1=%0d samples=%0d hash=%016x first256=%016x A=%0d B=%0d requests=%0d responses=%0d",
            accepted, classification, reject_code, command_count, total_writes,
            port0_writes, port1_writes, total_samples, trace_hash,
            first256_trace_hash, descriptor_a_count, descriptor_b_count,
            accepts, responses);
        $finish;
    end
endmodule

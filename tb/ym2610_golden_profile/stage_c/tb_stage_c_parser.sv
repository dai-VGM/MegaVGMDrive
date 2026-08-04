`timescale 1ns/1ps

module tb_stage_c_parser;
    localparam int MAX_FILE = 1 << 23;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic abort_parser = 1'b0;
    logic start = 1'b0;
    logic sample_tick = 1'b1;
    logic [31:0] original_size;
    logic [31:0] data_offset;
    logic [31:0] loop_target;
    logic mem_req;
    logic [22:0] mem_addr;
    logic mem_ready;
    logic mem_valid = 1'b0;
    logic [7:0] mem_data = 8'd0;
    logic sound_write_req;
    logic sound_write_port;
    logic [7:0] sound_write_address;
    logic [7:0] sound_write_data;
    logic sound_write_accept;
    logic active, ended, fatal, loop_event;
    logic [7:0] fatal_code;
    logic [31:0] current_pc, timeline_sample, command_count, write_count;
    logic [31:0] forwarded_fm, forwarded_ssg, suppressed_a, suppressed_b;
    logic [31:0] data_blocks, loop_count;
    logic [63:0] trace_hash, first256_trace_hash;
    logic trace_valid, trace_port, trace_forwarded;
    logic [31:0] trace_command_pc, trace_sample, trace_next_pc;
    logic [7:0] trace_address, trace_data;
    logic [3:0] trace_semantic;
    logic [63:0] trace_sound_accept_cycle;

    logic [7:0] memory [0:MAX_FILE-1];
    logic pending;
    logic [22:0] pending_addr;
    integer response_delay;
    integer cycle_count;
    integer accepted_reads;
    integer responses;
    integer held_cycles;
    logic [22:0] held_addr;
    integer fd;
    integer trace_fd;
    integer file_size;
    integer timeout;
    integer loop_mode;
    integer trace_rows;
    integer xz_count;
    integer expect_commands;
    integer expect_writes;
    integer expect_forwarded_fm;
    integer expect_forwarded_ssg;
    integer expect_suppressed_a;
    integer expect_suppressed_b;
    integer expect_blocks;
    integer expect_samples;
    logic [63:0] expect_hash;
    logic [63:0] expect_first256;
    string filename;
    string trace_filename;

    always #5 clk = ~clk;
    assign mem_ready = !pending && cycle_count[2:0] != 3'd3;
    assign sound_write_accept = sound_write_req;

    ym2610_golden_stage_c_parser #(
        .ADDR_WIDTH(23),
        .BUSY_DEADLINE_SAMPLES(64)
    ) dut (
        .clk(clk),
        .reset(reset),
        .abort(abort_parser),
        .start(start),
        .original_size(original_size),
        .data_offset(data_offset),
        .loop_target(loop_target),
        .sample_tick(sample_tick),
        .mem_req(mem_req),
        .mem_addr(mem_addr),
        .mem_ready(mem_ready),
        .mem_valid(mem_valid),
        .mem_data(mem_data),
        .sound_write_req(sound_write_req),
        .sound_write_port(sound_write_port),
        .sound_write_address(sound_write_address),
        .sound_write_data(sound_write_data),
        .sound_write_accept(sound_write_accept),
        .sound_fault(1'b0),
        .active(active),
        .ended(ended),
        .fatal(fatal),
        .fatal_code(fatal_code),
        .loop_event(loop_event),
        .current_pc(current_pc),
        .timeline_sample(timeline_sample),
        .command_count(command_count),
        .write_count(write_count),
        .forwarded_fm_global_count(forwarded_fm),
        .forwarded_ssg_count(forwarded_ssg),
        .suppressed_adpcma_count(suppressed_a),
        .suppressed_adpcmb_count(suppressed_b),
        .data_block_count(data_blocks),
        .loop_count(loop_count),
        .trace_hash(trace_hash),
        .first256_trace_hash(first256_trace_hash),
        .trace_valid(trace_valid),
        .trace_command_pc(trace_command_pc),
        .trace_sample(trace_sample),
        .trace_port(trace_port),
        .trace_address(trace_address),
        .trace_data(trace_data),
        .trace_semantic(trace_semantic),
        .trace_forwarded(trace_forwarded),
        .trace_next_pc(trace_next_pc),
        .trace_sound_accept_cycle(trace_sound_accept_cycle)
    );

    always_ff @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        mem_valid <= 1'b0;

        if (mem_req && !mem_ready) begin
            if (held_cycles == 0)
                held_addr <= mem_addr;
            else if (mem_addr !== held_addr)
                $fatal(1, "parser address changed before accept");
            held_cycles <= held_cycles + 1;
        end else begin
            held_cycles <= 0;
        end

        if (mem_req && mem_ready) begin
            if (pending)
                $fatal(1, "parser issued more than one outstanding request");
            pending <= 1'b1;
            pending_addr <= mem_addr;
            response_delay <= mem_addr[1:0] + 1;
            accepted_reads <= accepted_reads + 1;
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

        if (!reset && ^{
            mem_req, mem_addr, mem_ready, mem_valid, sound_write_req,
            sound_write_port, sound_write_address, sound_write_data,
            active, ended, fatal, fatal_code, current_pc, timeline_sample,
            command_count, write_count, forwarded_fm, forwarded_ssg,
            suppressed_a, suppressed_b, data_blocks, loop_count,
            trace_hash, first256_trace_hash
        } === 1'bx)
            xz_count <= xz_count + 1;
    end

    always @(posedge clk) begin
        #1;
        if (trace_valid) begin
            trace_rows = trace_rows + 1;
            if (trace_fd)
                $fwrite(
                    trace_fd,
                    "%08x %0d %0d %02x %02x %0d %0d %08x\n",
                    trace_command_pc, trace_sample, trace_port,
                    trace_address, trace_data, trace_semantic,
                    trace_forwarded, trace_next_pc
                );
        end
    end

    task automatic require_plusargs;
        begin
            if (!$value$plusargs("VGM=%s", filename))
                $fatal(1, "missing +VGM");
            if (!$value$plusargs("ORIGINAL=%d", original_size))
                $fatal(1, "missing +ORIGINAL");
            if (!$value$plusargs("DATA=%h", data_offset))
                $fatal(1, "missing +DATA");
            if (!$value$plusargs("LOOP=%h", loop_target))
                loop_target = 0;
            if (!$value$plusargs("EXPECT_COMMANDS=%d", expect_commands))
                $fatal(1, "missing +EXPECT_COMMANDS");
            if (!$value$plusargs("EXPECT_WRITES=%d", expect_writes))
                $fatal(1, "missing +EXPECT_WRITES");
            if (!$value$plusargs("EXPECT_FM=%d", expect_forwarded_fm))
                $fatal(1, "missing +EXPECT_FM");
            if (!$value$plusargs("EXPECT_SSG=%d", expect_forwarded_ssg))
                $fatal(1, "missing +EXPECT_SSG");
            if (!$value$plusargs("EXPECT_A=%d", expect_suppressed_a))
                $fatal(1, "missing +EXPECT_A");
            if (!$value$plusargs("EXPECT_B=%d", expect_suppressed_b))
                $fatal(1, "missing +EXPECT_B");
            if (!$value$plusargs("EXPECT_BLOCKS=%d", expect_blocks))
                $fatal(1, "missing +EXPECT_BLOCKS");
            if (!$value$plusargs("EXPECT_SAMPLES=%d", expect_samples))
                $fatal(1, "missing +EXPECT_SAMPLES");
            if (!$value$plusargs("EXPECT_HASH=%h", expect_hash))
                $fatal(1, "missing +EXPECT_HASH");
            if (!$value$plusargs("EXPECT_FIRST256=%h", expect_first256))
                $fatal(1, "missing +EXPECT_FIRST256");
            loop_mode = $test$plusargs("LOOP_MODE");
            if ($value$plusargs("TRACE=%s", trace_filename))
                trace_fd = $fopen(trace_filename, "w");
        end
    endtask

    initial begin
        trace_fd = 0;
        require_plusargs();
        fd = $fopen(filename, "rb");
        if (!fd)
            $fatal(1, "cannot open %s", filename);
        file_size = $fread(memory, fd);
        $fclose(fd);
        if (file_size < original_size)
            $fatal(1, "fixture shorter than original body");

        pending = 1'b0;
        pending_addr = 0;
        response_delay = 0;
        cycle_count = 0;
        accepted_reads = 0;
        responses = 0;
        held_cycles = 0;
        held_addr = 0;
        trace_rows = 0;
        xz_count = 0;
        repeat (5) @(posedge clk);
        reset <= 1'b0;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        timeout = 0;
        while (!fatal && !ended && !(loop_mode && loop_count == 1) &&
               timeout < 80_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        #1;
        if (trace_fd)
            $fclose(trace_fd);
        if (timeout >= 80_000_000)
            $fatal(1, "parser timeout state=%0d pc=%08x", dut.state, current_pc);
        if (fatal)
            $fatal(1, "parser fatal code=%02x pc=%08x", fatal_code, current_pc);
        if (!loop_mode && !ended)
            $fatal(1, "no-loop fixture did not end");
        if (loop_mode && loop_count != 1)
            $fatal(1, "loop fixture did not loop exactly once");
        if (!loop_mode && (pending || mem_req || accepted_reads != responses))
            $fatal(1, "read contract mismatch pending=%0d req=%0d a/r=%0d/%0d",
                   pending, mem_req, accepted_reads, responses);
        if (loop_mode &&
            (accepted_reads < responses || accepted_reads > responses + 1 ||
             pending != (accepted_reads == responses + 1)))
            $fatal(1, "loop-boundary read accounting mismatch pending=%0d req=%0d a/r=%0d/%0d",
                   pending, mem_req, accepted_reads, responses);
        if (command_count != expect_commands ||
            write_count != expect_writes ||
            forwarded_fm != expect_forwarded_fm ||
            forwarded_ssg != expect_forwarded_ssg ||
            suppressed_a != expect_suppressed_a ||
            suppressed_b != expect_suppressed_b ||
            data_blocks != expect_blocks ||
            timeline_sample != expect_samples ||
            trace_hash != expect_hash ||
            first256_trace_hash != expect_first256 ||
            trace_rows != expect_writes ||
            xz_count != 0)
            $fatal(1,
                "parser result mismatch cmd=%0d/%0d writes=%0d/%0d fm=%0d/%0d ssg=%0d/%0d A=%0d/%0d B=%0d/%0d blocks=%0d/%0d samples=%0d/%0d hash=%016x/%016x first=%016x/%016x trace=%0d xz=%0d",
                command_count, expect_commands, write_count, expect_writes,
                forwarded_fm, expect_forwarded_fm,
                forwarded_ssg, expect_forwarded_ssg,
                suppressed_a, expect_suppressed_a,
                suppressed_b, expect_suppressed_b,
                data_blocks, expect_blocks,
                timeline_sample, expect_samples,
                trace_hash, expect_hash,
                first256_trace_hash, expect_first256,
                trace_rows, xz_count
            );

        $display(
            "STAGE_C_PARSER PASS commands=%0d writes=%0d fm=%0d ssg=%0d suppressed_a=%0d suppressed_b=%0d blocks=%0d samples=%0d loop=%0d hash=%016x first256=%016x reads=%0d",
            command_count, write_count, forwarded_fm, forwarded_ssg,
            suppressed_a, suppressed_b, data_blocks, timeline_sample,
            loop_count, trace_hash, first256_trace_hash, accepted_reads
        );
        $finish;
    end
endmodule

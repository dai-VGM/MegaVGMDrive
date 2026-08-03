`timescale 1ns/1ps

module tb_ym2610_player_parser;
    localparam int MAX_FILE = 1 << 23;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic sample_tick = 1'b1;
    logic [31:0] start_pc = 32'h80;
    logic [31:0] loop_target = 32'd0;
    logic mem_req;
    logic [22:0] mem_addr;
    logic mem_ready = 1'b1;
    logic mem_valid = 1'b0;
    logic [7:0] mem_data = 8'd0;
    logic write_valid, write_port;
    logic [7:0] write_address, write_data;
    logic write_ready = 1'b1;
    logic running, finished, error;
    logic [31:0] pc, wait_remaining, sample_position, accepted_writes;
    logic [31:0] port0_writes, port1_writes, loop_count, unsupported_pc;
    logic [7:0] opcode, unsupported_opcode;
    logic trace_valid;
    logic [31:0] trace_pc, trace_sample;
    logic [7:0] memory [0:MAX_FILE-1];
    logic pending;
    logic [22:0] pending_addr;
    integer response_delay;
    integer fd, count, timeout, run_index;
    integer start_count;
    string filename;
    logic [63:0] trace_hash;
    logic [63:0] first_hash;
    logic [63:0] prior_hash;
    logic [63:0] prior_first_hash;
    logic [31:0] trace_count;

    always #5 clk = ~clk;

    function automatic [63:0] fnv_byte(input [63:0] hash, input [7:0] value);
        fnv_byte = (hash ^ value) * 64'h0000_0100_0000_01b3;
    endfunction

    task automatic hash_event;
        logic [63:0] next;
        begin
            next = trace_hash;
            next = fnv_byte(next, trace_pc[7:0]);
            next = fnv_byte(next, trace_pc[15:8]);
            next = fnv_byte(next, trace_pc[23:16]);
            next = fnv_byte(next, trace_pc[31:24]);
            next = fnv_byte(next, trace_sample[7:0]);
            next = fnv_byte(next, trace_sample[15:8]);
            next = fnv_byte(next, trace_sample[23:16]);
            next = fnv_byte(next, trace_sample[31:24]);
            next = fnv_byte(next, opcode);
            next = fnv_byte(next, {7'd0, write_port});
            next = fnv_byte(next, write_address);
            next = fnv_byte(next, write_data);
            trace_hash <= next;
            if (trace_count < 32'd256)
                first_hash <= next;
            trace_count <= trace_count + 32'd1;
        end
    endtask

    ym2610_player_parser dut (
        .clk(clk), .reset(reset), .start(start), .sample_tick(sample_tick),
        .start_pc(start_pc), .loop_target(loop_target),
        .mem_req(mem_req), .mem_addr(mem_addr), .mem_ready(mem_ready),
        .mem_valid(mem_valid), .mem_data(mem_data),
        .write_valid(write_valid), .write_port(write_port),
        .write_address(write_address), .write_data(write_data),
        .write_ready(write_ready), .running(running), .finished(finished),
        .error(error), .pc(pc), .opcode(opcode),
        .wait_remaining(wait_remaining), .sample_position(sample_position),
        .accepted_writes(accepted_writes), .port0_writes(port0_writes),
        .port1_writes(port1_writes), .loop_count(loop_count),
        .unsupported_pc(unsupported_pc),
        .unsupported_opcode(unsupported_opcode),
        .trace_valid(trace_valid), .trace_pc(trace_pc),
        .trace_sample(trace_sample)
    );

    always_ff @(posedge clk) begin
        mem_valid <= 1'b0;
        if (mem_req && mem_ready && !pending) begin
            pending <= 1'b1;
            pending_addr <= mem_addr;
            response_delay <= mem_addr[1:0];
        end
        if (pending) begin
            if (response_delay == 0) begin
                mem_data <= memory[pending_addr];
                mem_valid <= 1'b1;
                pending <= 1'b0;
            end else response_delay <= response_delay - 1;
        end
        if (trace_valid)
            hash_event();
        if (start)
            start_count <= start_count + 1;
    end

    initial begin
        if (!$value$plusargs("VGM=%s", filename))
            $fatal(1, "use +VGM=/path/file.vgm");
        fd = $fopen(filename, "rb");
        if (!fd) $fatal(1, "cannot open %s", filename);
        count = $fread(memory, fd);
        $fclose(fd);
        if ({memory[3], memory[2], memory[1], memory[0]} != 32'h206d6756)
            $fatal(1, "bad input magic");
        start_pc = 32'h34 + {memory[8'h37], memory[8'h36],
                             memory[8'h35], memory[8'h34]};
        pending = 1'b0;
        pending_addr = 0;
        response_delay = 0;
        trace_hash = 64'hcbf2_9ce4_8422_2325;
        first_hash = 64'hcbf2_9ce4_8422_2325;
        prior_hash = 0;
        prior_first_hash = 0;
        trace_count = 0;
        start_count = 0;
        repeat (5) @(posedge clk);
        reset <= 1'b0;
        for (run_index = 0; run_index < 2; run_index = run_index + 1) begin
            @(posedge clk);
            trace_hash <= 64'hcbf2_9ce4_8422_2325;
            first_hash <= 64'hcbf2_9ce4_8422_2325;
            trace_count <= 0;
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            @(posedge clk);
            timeout = 0;
            while (!finished && !error && timeout < 40_000_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            repeat (2) @(posedge clk);
            if (error) $fatal(1, "parser error pc=%08x opcode=%02x", unsupported_pc, unsupported_opcode);
            if (!finished) $fatal(1, "parser timeout state=%0d pc=%08x", dut.state, pc);
            $display("PARSER_RESULT run=%0d writes=%0d p0=%0d p1=%0d samples=%0d hash=%016x first256=%016x start_count=%0d",
                run_index, accepted_writes, port0_writes, port1_writes,
                sample_position, trace_hash, first_hash, start_count);
            if (run_index == 0) begin
                prior_hash = trace_hash;
                prior_first_hash = first_hash;
            end else if (trace_hash != prior_hash || first_hash != prior_first_hash)
                $fatal(1, "cold/reload trace mismatch");
        end
        if (start_count != 2) $fatal(1, "start pulse count mismatch");
        $finish;
    end
endmodule

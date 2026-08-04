`timescale 1ns/1ps

module tb_stage_c_parser_faults;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic abort_parser = 1'b0;
    logic start = 1'b0;
    logic [31:0] original_size = 32'h90;
    logic [31:0] data_offset = 32'h80;
    logic [31:0] loop_target = 32'd0;
    logic sample_tick = 1'b1;
    logic mem_req;
    logic [22:0] mem_addr;
    logic mem_ready = 1'b1;
    logic mem_valid = 1'b0;
    logic [7:0] mem_data = 8'd0;
    logic sound_write_req, sound_write_port;
    logic [7:0] sound_write_address, sound_write_data;
    logic sound_write_accept = 1'b0;
    logic sound_fault = 1'b0;
    logic active, ended, fatal, loop_event;
    logic [7:0] fatal_code;
    logic [31:0] current_pc, timeline_sample, command_count, write_count;
    logic [31:0] forwarded_fm_global_count, forwarded_ssg_count;
    logic [31:0] suppressed_adpcma_count, suppressed_adpcmb_count;
    logic [31:0] data_block_count, loop_count;
    logic [63:0] trace_hash, first256_trace_hash;
    logic trace_valid, trace_port, trace_forwarded;
    logic [31:0] trace_command_pc, trace_sample, trace_next_pc;
    logic [7:0] trace_address, trace_data;
    logic [3:0] trace_semantic;
    logic [63:0] trace_sound_accept_cycle;
    logic [7:0] memory [0:255];
    logic pending = 1'b0;
    logic [7:0] pending_addr = 8'd0;
    integer timeout;
    integer index;

    always #5 clk = ~clk;

    ym2610_golden_stage_c_parser #(
        .ADDR_WIDTH(23),
        .BUSY_DEADLINE_SAMPLES(8)
    ) dut (
        .clk(clk), .reset(reset), .abort(abort_parser), .start(start),
        .original_size(original_size), .data_offset(data_offset),
        .loop_target(loop_target), .sample_tick(sample_tick),
        .mem_req(mem_req), .mem_addr(mem_addr), .mem_ready(mem_ready),
        .mem_valid(mem_valid), .mem_data(mem_data),
        .sound_write_req(sound_write_req),
        .sound_write_port(sound_write_port),
        .sound_write_address(sound_write_address),
        .sound_write_data(sound_write_data),
        .sound_write_accept(sound_write_accept), .sound_fault(sound_fault),
        .active(active), .ended(ended), .fatal(fatal),
        .fatal_code(fatal_code), .loop_event(loop_event),
        .current_pc(current_pc), .timeline_sample(timeline_sample),
        .command_count(command_count), .write_count(write_count),
        .forwarded_fm_global_count(forwarded_fm_global_count),
        .forwarded_ssg_count(forwarded_ssg_count),
        .suppressed_adpcma_count(suppressed_adpcma_count),
        .suppressed_adpcmb_count(suppressed_adpcmb_count),
        .data_block_count(data_block_count), .loop_count(loop_count),
        .trace_hash(trace_hash),
        .first256_trace_hash(first256_trace_hash),
        .trace_valid(trace_valid), .trace_command_pc(trace_command_pc),
        .trace_sample(trace_sample), .trace_port(trace_port),
        .trace_address(trace_address), .trace_data(trace_data),
        .trace_semantic(trace_semantic),
        .trace_forwarded(trace_forwarded),
        .trace_next_pc(trace_next_pc),
        .trace_sound_accept_cycle(trace_sound_accept_cycle)
    );

    always_ff @(posedge clk) begin
        mem_valid <= 1'b0;
        if (mem_req && mem_ready) begin
            if (pending) $fatal(1, "fault TB multiple outstanding");
            pending <= 1'b1;
            pending_addr <= mem_addr[7:0];
        end
        if (pending) begin
            mem_data <= memory[pending_addr];
            mem_valid <= 1'b1;
            pending <= 1'b0;
        end
    end

    task automatic clear_memory;
        begin
            for (index = 0; index < 256; index = index + 1)
                memory[index] = 8'd0;
            original_size = 32'h90;
            data_offset = 32'h80;
            loop_target = 32'd0;
            sound_write_accept = 1'b0;
            sound_fault = 1'b0;
        end
    endtask

    task automatic restart;
        begin
            reset = 1'b1;
            abort_parser = 1'b0;
            start = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task automatic expect_fatal(input logic [7:0] code);
        begin
            timeout = 0;
            while (!fatal && timeout < 200) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            #1;
            if (!fatal || fatal_code != code || mem_req ||
                sound_write_accept)
                $fatal(1, "expected fatal=%02x actual=%02x state=%0d req=%0d",
                       code, fatal_code, dut.state, mem_req);
            if ((^{active, ended, fatal, fatal_code, current_pc,
                    timeline_sample, command_count, write_count,
                    trace_hash}) === 1'bx)
                $fatal(1, "fault path X/Z");
        end
    endtask

    initial begin
        clear_memory();
        loop_target = 32'h40;
        restart();
        expect_fatal(8'h05);

        clear_memory();
        memory[8'h80] = 8'h50;
        restart();
        expect_fatal(8'h02);

        clear_memory();
        memory[8'h80] = 8'h67;
        memory[8'h81] = 8'h00;
        restart();
        expect_fatal(8'h03);

        clear_memory();
        memory[8'h80] = 8'h58;
        memory[8'h81] = 8'hff;
        memory[8'h82] = 8'h00;
        restart();
        expect_fatal(8'h04);

        clear_memory();
        memory[8'h80] = 8'h58;
        memory[8'h81] = 8'h28;
        memory[8'h82] = 8'hf1;
        memory[8'h83] = 8'h66;
        original_size = 32'h84;
        restart();
        expect_fatal(8'h07);

        clear_memory();
        memory[8'h80] = 8'h62;
        memory[8'h81] = 8'h66;
        restart();
        repeat (5) @(posedge clk);
        sound_fault = 1'b1;
        expect_fatal(8'h06);

        // Abort with one response in flight; the late response must not
        // revive the parser or become the first byte of a later session.
        clear_memory();
        memory[8'h80] = 8'h66;
        restart();
        while (!mem_req) @(posedge clk);
        @(negedge clk);
        abort_parser = 1'b1;
        @(posedge clk);
        @(negedge clk);
        abort_parser = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        if (active || fatal || ended || mem_req || command_count != 0)
            $fatal(1, "abort/stale response quarantine failure active=%0d fatal=%0d ended=%0d req=%0d commands=%0d state=%0d pending=%0d",
                   active, fatal, ended, mem_req, command_count, dut.state,
                   pending);

        // A fresh generation/session must remain usable after the quarantined
        // response and every preceding safe-stop path.
        clear_memory();
        memory[8'h80] = 8'h66;
        original_size = 32'h81;
        restart();
        timeout = 0;
        while (!ended && !fatal && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        #1;
        if (!ended || fatal || command_count != 1 || write_count != 0 ||
            mem_req || sound_write_req)
            $fatal(1, "post-fault reload/session failed ended=%0d fatal=%0d commands=%0d writes=%0d",
                   ended, fatal, command_count, write_count);

        $display("STAGE_C_PARSER_FAULTS PASS range=1 opcode=1 block=1 register=1 busy_timeout=1 sound_fault=1 stale_response=0 reload=1 xz=0");
        $finish;
    end
endmodule

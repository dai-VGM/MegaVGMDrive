`timescale 1ns/1ps

// Fast file-backed parser/C0 startup contract test.  This deliberately leaves
// the SegaPCM ROM/mixer path out: it proves the ordering of pre-scan complete,
// first decoded C0 and the wrapper's one-entry apply cadence.
module tb_vgm_loaded_player_c0_startup;
    localparam integer ADDR_WIDTH = 20;
    localparam integer MEM_BYTES = 1 << ADDR_WIDTH;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg start = 1'b0;
    reg load_done = 1'b1;
    reg vgm_wait_tick = 1'b1;
    reg [ADDR_WIDTH:0] file_size = 0;
    wire mem_rd_req;
    wire [ADDR_WIDTH-1:0] mem_rd_addr;
    reg mem_rd_ready = 1'b1;
    reg mem_rd_valid = 1'b0;
    reg [7:0] mem_rd_data = 8'd0;
    reg read_pending = 1'b0;
    reg [7:0] read_pending_data = 8'd0;
    wire copy_flush_req;
    reg copy_flush_done = 1'b0;
    wire busy;
    wire done;
    wire header_valid;
    wire player_error;
    wire scan_busy;
    wire scan_done;
    wire c0_valid;
    wire [15:0] c0_addr;
    wire [7:0] c0_data;
    wire [31:0] c0_count;
    wire [ADDR_WIDTH-1:0] current_pc;
    wire [31:0] wait_samples;
    reg [7:0] mem [0:MEM_BYTES-1];
    reg [1023:0] vgm_file;
    integer fd;
    integer file_bytes;
    integer timeout;
    integer cycle_count = 0;
    integer scan_done_cycle = -1;
    integer first_c0_cycle = -1;
    integer decoded_count = 0;
    integer accepted_count = 0;
    integer applied_count = 0;
    integer pending_overwrite_count = 0;
    integer back_to_back_drain_count = 0;
    integer stop_c0_count = 1;
    reg wrapper_pending = 1'b0;
    reg [15:0] wrapper_addr = 16'd0;
    reg [7:0] wrapper_data = 8'd0;
    reg [15:0] expected_addr [0:131071];
    reg [7:0] expected_data [0:131071];

    always #5 clk = ~clk;

    vgm_loaded_player #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .YM2151_MODE(1'b1)
    ) dut (
        .clk(clk), .reset(reset), .start(start),
        .load_done(load_done), .load_done_pulse(1'b0),
        .load_error(1'b0), .overflow_error(1'b0), .file_size(file_size),
        .vgm_wait_tick(vgm_wait_tick),
        .halt_at_loop_boundary(1'b0),
        .mem_rd_req(mem_rd_req), .mem_rd_addr(mem_rd_addr),
        .mem_rd_ready(mem_rd_ready), .mem_rd_valid(mem_rd_valid),
        .mem_rd_data(mem_rd_data),
        .segapcm_copy_wr_req(), .segapcm_copy_wr_ready(1'b1),
        .segapcm_copy_wr_addr(), .segapcm_copy_wr_data(),
        .segapcm_copy_flush_req(copy_flush_req),
        .segapcm_copy_flush_done(copy_flush_done),
        .ym_cmd_ready(1'b1), .psg_cmd_ready(1'b1),
        .ym2151_cmd_ready(1'b1),
        .busy(busy), .done(done), .header_valid(header_valid),
        .player_error(player_error),
        .current_pc_debug(current_pc),
        .wait_ticks_consumed_debug(wait_samples),
        .segapcm_cmd_valid(c0_valid), .segapcm_cmd_addr(c0_addr),
        .segapcm_cmd_data(c0_data), .segapcm_write_count(c0_count),
        .segapcm_rom_scan_busy(scan_busy),
        .segapcm_rom_scan_done(scan_done)
    );

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        mem_rd_valid <= 1'b0;
        copy_flush_done <= copy_flush_req;
        if (read_pending) begin
            mem_rd_valid <= 1'b1;
            mem_rd_data <= read_pending_data;
            read_pending <= 1'b0;
        end
        if (mem_rd_req && mem_rd_ready) begin
            read_pending <= 1'b1;
            read_pending_data <= mem[mem_rd_addr];
        end
        if (scan_done && scan_done_cycle < 0)
            scan_done_cycle <= cycle_count;

        // Exact one-entry wrapper cadence from segapcm_sound_module.  Since
        // the player has no ready input, any valid while pending is a drop by
        // overwrite and is fatal to ordered C0 application.
        if (wrapper_pending) begin
            if (wrapper_addr !== expected_addr[applied_count] ||
                wrapper_data !== expected_data[applied_count]) begin
                $fatal(1,
                    "C0 apply sequence mismatch seq=%0d got=%04h/%02h expected=%04h/%02h",
                    applied_count, wrapper_addr, wrapper_data,
                    expected_addr[applied_count], expected_data[applied_count]);
            end
            applied_count <= applied_count + 1;
            wrapper_pending <= 1'b0;
        end
        if (c0_valid) begin
            if (first_c0_cycle < 0) begin
                first_c0_cycle <= cycle_count;
                $display("FIRST_C0 cycle=%0d scan_done_cycle=%0d delta=%0d sample=%0d pc=%06h addr=%04h data=%02h",
                    cycle_count, scan_done_cycle,
                    (scan_done_cycle < 0) ? -1 : cycle_count-scan_done_cycle,
                    wait_samples, current_pc-4, c0_addr, c0_data);
            end
            expected_addr[decoded_count] <= c0_addr;
            expected_data[decoded_count] <= c0_data;
            decoded_count <= decoded_count + 1;
            accepted_count <= accepted_count + 1;
            if (wrapper_pending)
                back_to_back_drain_count <= back_to_back_drain_count + 1;
            wrapper_pending <= 1'b1;
            wrapper_addr <= c0_addr;
            wrapper_data <= c0_data;
        end
    end

    initial begin
        if (!$value$plusargs("VGM=%s", vgm_file))
            $fatal(1, "VGM plusarg is required");
        if ($value$plusargs("STOP_C0_COUNT=%d", stop_c0_count)) begin end
        fd = $fopen(vgm_file, "rb");
        if (fd == 0) $fatal(1, "cannot open VGM");
        file_bytes = $fread(mem, fd);
        $fclose(fd);
        if (file_bytes <= 0 || file_bytes > MEM_BYTES)
            $fatal(1, "VGM size outside TB memory: %0d", file_bytes);
        file_size = file_bytes;
        repeat (4) @(posedge clk);
        reset <= 1'b0;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        timeout = 0;
        while (decoded_count < stop_c0_count && !player_error &&
               timeout < 50_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (decoded_count < stop_c0_count || player_error)
            $fatal(1,
                "C0 target timeout/error timeout=%0d decoded=%0d target=%0d error=%0b",
                timeout, decoded_count, stop_c0_count, player_error);
        repeat (8) @(posedge clk);
        if (decoded_count != accepted_count ||
            decoded_count != applied_count || pending_overwrite_count != 0)
            $fatal(1,
                "C0 startup scoreboard decoded=%0d accepted=%0d applied=%0d overwrite=%0d",
                decoded_count, accepted_count, applied_count,
                pending_overwrite_count);
        $display("PASS tb_vgm_loaded_player_c0_startup decoded=%0d back_to_back_drain=%0d scan_to_c0=%0d",
            decoded_count, back_to_back_drain_count,
            first_c0_cycle-scan_done_cycle);
        $finish;
    end
endmodule

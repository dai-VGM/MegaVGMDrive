`timescale 1ns/1ps

module tb_vgm_ddram_backend_after_burner_direct_read;
    localparam int ADDR_WIDTH = 8;
    localparam int PAYLOAD_BYTES = 19'h25800;
    localparam int PAYLOAD_WORDS = PAYLOAD_BYTES / 8;
    localparam logic [28:0] VGM_BASE = {4'b0011, 25'd0};
    localparam logic [28:0] SEGAPCM_BASE = VGM_BASE + 29'h0010_0000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [31:0] ioctl_addr = 32'd0;
    logic [7:0] ioctl_dout = 8'd0;
    wire ioctl_wait;
    wire load_busy;
    wire load_done;
    logic smoke_tap_valid = 1'b0;
    logic [18:0] smoke_tap_addr = 19'd0;
    logic [7:0] smoke_tap_data = 8'd0;
    logic smoke_rd_req = 1'b0;
    logic [18:0] smoke_rd_addr = 19'd0;
    wire smoke_rd_ready;
    wire smoke_rd_valid;
    wire [7:0] smoke_rd_data;
    wire [18:0] smoke_payload_length;
    wire [15:0] smoke_blocked_count;

    logic ddram_busy = 1'b0;
    logic [63:0] ddram_dout = 64'd0;
    logic ddram_dout_ready = 1'b0;
    wire [28:0] ddram_addr;
    wire [63:0] ddram_din;
    wire [7:0] ddram_be;
    wire ddram_rd;
    wire ddram_we;

    logic [7:0] expected [0:PAYLOAD_BYTES-1];
    logic [63:0] ddr_mem [0:PAYLOAD_WORDS-1];
    integer accepted_count = 0;
    integer write_count = 0;
    integer block6_write_count = 0;
    integer read_countdown = -1;
    logic [28:0] pending_read_word;
    logic [28:0] observed_read_word;
    logic [63:0] observed_return_word;
    integer timeout;
    integer post_load_busy_count = 0;
    logic post_load_copy_started = 1'b0;

    vgm_ddram_backend #(
        .ADDR_WIDTH            (ADDR_WIDTH),
        .FILE_INDEX            (8'd1),
        .DDRAM_BASE_ADDR       (VGM_BASE),
        .SEGAPCM_ROM_BASE_ADDR (SEGAPCM_BASE),
        .WRITE_FIFO_DEPTH      (64)
    ) dut (
        .clk                    (clk),
        .reset                  (reset),
        .ioctl_download         (ioctl_download),
        .ioctl_wr               (ioctl_wr),
        .ioctl_addr             (ioctl_addr),
        .ioctl_dout             (ioctl_dout),
        .ioctl_index            (8'd1),
        .ioctl_wait             (ioctl_wait),
        .mem_rd_req             (1'b0),
        .mem_rd_addr            ('0),
        .mem_rd_ready           (),
        .mem_rd_valid           (),
        .mem_rd_data            (),
        .segapcm_copy_wr_req    (1'b0),
        .segapcm_copy_wr_ready  (),
        .segapcm_copy_wr_addr   (19'd0),
        .segapcm_copy_wr_data   (8'd0),
        .segapcm_copy_flush_req (1'b0),
        .segapcm_copy_flush_done(),
        .smoke_ddr_payload_tap_valid(smoke_tap_valid),
        .smoke_ddr_payload_tap_addr (smoke_tap_addr),
        .smoke_ddr_payload_tap_data (smoke_tap_data),
        .smoke_ddr_capture_limit    (PAYLOAD_BYTES[18:0]),
        .smoke_ddr_rd_req           (smoke_rd_req),
        .smoke_ddr_rd_ready         (smoke_rd_ready),
        .smoke_ddr_rd_addr          (smoke_rd_addr),
        .smoke_ddr_rd_valid         (smoke_rd_valid),
        .smoke_ddr_rd_data          (smoke_rd_data),
        .smoke_ddr_payload_present  (),
        .smoke_ddr_payload_length   (smoke_payload_length),
        .smoke_ddr_write_blocked_count_debug(smoke_blocked_count),
        .load_busy              (load_busy),
        .load_done              (load_done),
        .load_done_pulse        (),
        .play_ready_pulse       (),
        .load_error             (),
        .overflow_error         (),
        .file_size              (),
        .magic_debug            (),
        .ddram_busy             (ddram_busy),
        .ddram_burstcnt         (),
        .ddram_addr             (ddram_addr),
        .ddram_dout             (ddram_dout),
        .ddram_dout_ready       (ddram_dout_ready),
        .ddram_rd               (ddram_rd),
        .ddram_din              (ddram_din),
        .ddram_be               (ddram_be),
        .ddram_we               (ddram_we)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        integer relative_word;
        ddram_dout_ready <= 1'b0;

        if (post_load_copy_started && load_busy)
            post_load_busy_count = post_load_busy_count + 1;

        if (!reset && dut.smoke_ddr_write_accept_live) begin
            accepted_count = accepted_count + 1;
            if (dut.smoke_ddr_capture_index !== smoke_tap_addr) begin
                $fatal(1, "tap/index divergence tap=%05h capture=%05h",
                       smoke_tap_addr, dut.smoke_ddr_capture_index);
            end
        end

        if (ddram_we) begin
            if (ddram_addr >= SEGAPCM_BASE) begin
                relative_word = ddram_addr - SEGAPCM_BASE;
                if (relative_word < 0 || relative_word >= PAYLOAD_WORDS) begin
                    $fatal(1, "write outside payload ddram_addr=%08h", ddram_addr);
                end
                for (integer lane = 0; lane < 8; lane = lane + 1) begin
                    if (ddram_be[lane]) begin
                        ddr_mem[relative_word][lane*8 +: 8] =
                            ddram_din[lane*8 +: 8];
                    end
                end
                write_count = write_count + 1;
                if (relative_word >= (19'h21800 >> 3) &&
                    relative_word <= (19'h257f8 >> 3)) begin
                    block6_write_count = block6_write_count + 1;
                    if (relative_word == (19'h21800 >> 3) ||
                        relative_word == (19'h257f8 >> 3)) begin
                        $display("BLOCK6_WRITE edge=%s payload_base=%05h physical_byte=%08h word=%08h lane_mask=%02h data=%016h bit18_16=%03b",
                                 relative_word == (19'h21800 >> 3) ? "first" : " last",
                                 relative_word * 8,
                                 (SEGAPCM_BASE << 3) + relative_word * 8,
                                 ddram_addr, ddram_be, ddram_din,
                                 relative_word[15:13]);
                    end
                end
            end
        end

        if (ddram_rd) begin
            if (read_countdown >= 0) begin
                $fatal(1, "overlapping DDR reads");
            end
            pending_read_word <= ddram_addr;
            observed_read_word <= ddram_addr;
            read_countdown <= 2;
        end else if (read_countdown > 0) begin
            read_countdown <= read_countdown - 1;
        end else if (read_countdown == 0) begin
            relative_word = pending_read_word - SEGAPCM_BASE;
            ddram_dout <= ddr_mem[relative_word];
            observed_return_word <= ddr_mem[relative_word];
            ddram_dout_ready <= 1'b1;
            read_countdown <= -1;
        end
    end

    task automatic direct_read(input logic [18:0] payload_index);
        logic [7:0] got;
        logic [7:0] want;
        logic [28:0] want_word;
        begin
            want = expected[payload_index];
            want_word = SEGAPCM_BASE + payload_index[18:3];
            while (!smoke_rd_ready) @(posedge clk);
            @(negedge clk);
            smoke_rd_addr = payload_index;
            smoke_rd_req = 1'b1;
            @(negedge clk);
            smoke_rd_req = 1'b0;
            timeout = 0;
            while (!smoke_rd_valid) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout == 100) $fatal(1, "read timeout index=%05h", payload_index);
            end
            got = smoke_rd_data;
            $display("DIRECT_READ index=%05h backend_addr=%05h word=%08h returned_word=%016h lane=%0d byte=%02h expected=%02h bit18_16=%03b",
                     payload_index, smoke_rd_addr, observed_read_word,
                     observed_return_word, payload_index[2:0], got, want,
                     payload_index[18:16]);
            if (observed_read_word !== want_word || got !== want) begin
                $fatal(1, "direct read mismatch index=%05h word=%08h/%08h byte=%02h/%02h",
                       payload_index, observed_read_word, want_word, got, want);
            end
            @(posedge clk);
        end
    endtask

    initial begin
        $readmemh("tb/data/after_burner_final_takeoff_payload.memh", expected);
        for (integer word = 0; word < PAYLOAD_WORDS; word = word + 1)
            ddr_mem[word] = 64'hx;

        repeat (5) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        // Complete a real file-load transaction first.  Subsequent SegaPCM
        // payload writes share write_pending, but must not reassert load_busy.
        @(negedge clk);
        ioctl_download = 1'b1;
        for (integer index = 0; index < 8; index = index + 1) begin
            @(negedge clk);
            ioctl_addr = index;
            ioctl_dout = 8'h40 + index[7:0];
            ioctl_wr = 1'b1;
        end
        @(negedge clk);
        ioctl_wr = 1'b0;
        ioctl_download = 1'b0;
        timeout = 0;
        while (!load_done) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (timeout == 1000) $fatal(1, "file load did not complete");
        end
        if (load_busy) $fatal(1, "load_busy remained set after load_done");
        post_load_copy_started = 1'b1;

        for (integer index = 0; index < PAYLOAD_BYTES; index = index + 1) begin
            @(negedge clk);
            smoke_tap_addr = index[18:0];
            smoke_tap_data = expected[index];
            smoke_tap_valid = 1'b1;
        end
        @(negedge clk);
        smoke_tap_valid = 1'b0;

        timeout = 0;
        while (write_count != PAYLOAD_WORDS) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (timeout == 1000) begin
                $fatal(1, "copy drain timeout accepts=%0d writes=%0d/%0d blocked=%0d",
                       accepted_count, write_count, PAYLOAD_WORDS,
                       smoke_blocked_count);
            end
        end
        repeat (3) @(posedge clk);

        $display("COPY_SUMMARY accepts=%0d words=%0d block6_words=%0d payload_length=%05h blocked=%0d post_load_busy=%0d",
                 accepted_count, write_count, block6_write_count,
                 smoke_payload_length, smoke_blocked_count,
                 post_load_busy_count);
        if (accepted_count != PAYLOAD_BYTES ||
            write_count != PAYLOAD_WORDS ||
            block6_write_count != (19'h4000 >> 3) ||
            smoke_payload_length != PAYLOAD_BYTES ||
            smoke_blocked_count != 0) begin
            $fatal(1, "copy accounting mismatch");
        end
        if (post_load_busy_count != 0)
            $fatal(1, "post-load payload writes reasserted load_busy %0d cycles",
                   post_load_busy_count);

        direct_read(19'h0d000);
        direct_read(19'h0d001);
        direct_read(19'h0d007);
        $display("PLAYBACK_PREFIX indices=21800,21800,21800,21801 expected=7a,7a,7a,73");
        direct_read(19'h21800);
        direct_read(19'h21800);
        direct_read(19'h21800);
        direct_read(19'h21801);
        for (integer index = 19'h217f8; index <= 19'h21810; index = index + 1)
            direct_read(index[18:0]);
        direct_read(19'h23800);
        direct_read(19'h257f8);
        direct_read(19'h257ff);

        $display("PASS tb_vgm_ddram_backend_after_burner_direct_read");
        $finish;
    end
endmodule

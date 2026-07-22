`timescale 1ns/1ps

module tb_vgm_segapcm_header_clock;
    localparam integer ADDR_WIDTH = 8;
    localparam logic [31:0] STAGE_CLOCK_HZ = 32'd4_026_987;
    localparam logic [31:0] FOUR_MHZ = 32'd4_000_000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic load_done = 1'b1;
    logic load_done_pulse = 1'b0;
    wire mem_rd_req;
    wire [ADDR_WIDTH-1:0] mem_rd_addr;
    logic mem_rd_valid = 1'b0;
    logic [7:0] mem_rd_data = 8'd0;
    wire done;
    wire header_valid;
    wire [31:0] segapcm_clock;
    wire segapcm_clock_commit;
    wire segapcm_clock_session_reset;
    logic [7:0] mem [0:255];
    logic pending = 1'b0;
    logic [7:0] pending_data = 8'd0;
    logic [31:0] previous_clock = 32'd0;
    integer commit_count = 0;
    integer session_count = 0;
    integer i;

    always #5 clk = ~clk;

    vgm_loaded_player #(.ADDR_WIDTH(ADDR_WIDTH)) dut (
        .clk(clk), .reset(reset), .start(start),
        .load_done(load_done), .load_done_pulse(load_done_pulse),
        .load_error(1'b0), .overflow_error(1'b0), .file_size(9'h041),
        .vgm_wait_tick(1'b0),
        .mem_rd_req(mem_rd_req), .mem_rd_addr(mem_rd_addr),
        .mem_rd_ready(!pending), .mem_rd_valid(mem_rd_valid),
        .mem_rd_data(mem_rd_data),
        .segapcm_copy_wr_ready(1'b1), .segapcm_copy_flush_done(1'b1),
        .ym_cmd_ready(1'b1), .psg_cmd_ready(1'b1), .ym2151_cmd_ready(1'b1),
        .done(done), .header_valid(header_valid),
        .segapcm_clock(segapcm_clock),
        .segapcm_clock_commit(segapcm_clock_commit),
        .segapcm_clock_session_reset(segapcm_clock_session_reset)
    );

    always_ff @(posedge clk) begin
        mem_rd_valid <= 1'b0;
        if (reset) begin
            pending <= 1'b0;
            mem_rd_data <= 8'd0;
        end else begin
            if (pending) begin
                mem_rd_data <= pending_data;
                mem_rd_valid <= 1'b1;
                pending <= 1'b0;
            end
            if (mem_rd_req && !pending) begin
                pending_data <= mem[mem_rd_addr];
                pending <= 1'b1;
            end
        end
    end

    always @(negedge clk) begin
        if (!reset) begin
            if ((segapcm_clock !== previous_clock) && !segapcm_clock_commit &&
                !segapcm_clock_session_reset)
                $fatal(1, "partial header clock became visible old=%0d new=%0d",
                       previous_clock, segapcm_clock);
            if (segapcm_clock_commit)
                commit_count = commit_count + 1;
            if (segapcm_clock_session_reset)
                session_count = session_count + 1;
            previous_clock = segapcm_clock;
        end
    end

    task set_header_clock(input logic [31:0] value);
        begin
            mem[8'h38] = value[7:0];
            mem[8'h39] = value[15:8];
            mem[8'h3a] = value[23:16];
            mem[8'h3b] = value[31:24];
        end
    endtask

    task start_session(input logic [31:0] value);
        begin
            set_header_clock(value);
            if (done) begin
                @(negedge clk); start = 1'b1;
                @(negedge clk); start = 1'b0;
                repeat (2) @(negedge clk);
            end
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;
            wait (segapcm_clock_session_reset === 1'b1);
            @(negedge clk);
            if (segapcm_clock !== 32'd0)
                $fatal(1, "new session exposed previous clock %0d", segapcm_clock);
            wait (segapcm_clock_commit === 1'b1);
            @(negedge clk);
            if (segapcm_clock !== value)
                $fatal(1, "atomic clock commit got=%0d expected=%0d",
                       segapcm_clock, value);
            wait (done === 1'b1);
        end
    endtask

    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 8'd0;
        mem[8'h00] = "V";
        mem[8'h01] = "g";
        mem[8'h02] = "m";
        mem[8'h03] = " ";
        mem[8'h34] = 8'd0;
        mem[8'h35] = 8'd0;
        mem[8'h36] = 8'd0;
        mem[8'h37] = 8'd0;
        mem[8'h3c] = 8'h0c;
        mem[8'h40] = 8'h66;

        repeat (3) @(posedge clk);
        @(negedge clk); reset = 1'b0;

        start_session(STAGE_CLOCK_HZ);
        start_session(FOUR_MHZ);
        start_session(STAGE_CLOCK_HZ);

        if (commit_count != 3 || session_count != 3)
            $fatal(1, "commit/session count mismatch commits=%0d sessions=%0d",
                   commit_count, session_count);
        $display("PASS tb_vgm_segapcm_header_clock commits=%0d sessions=%0d final=%0d",
                 commit_count, session_count, segapcm_clock);
        $finish;
    end
endmodule

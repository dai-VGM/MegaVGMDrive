`timescale 1ns/1ps

module tb_mode5_ddram_header_start;
    localparam int ADDR_WIDTH = 8;
    localparam logic [28:0] VGM_BASE = {4'b0011, 25'd0};

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;

    wire [28:0] ddram_addr;
    logic [63:0] ddram_dout = 64'd0;
    logic ddram_dout_ready = 1'b0;
    wire [63:0] ddram_din;
    wire [7:0] ddram_be;
    wire ddram_rd;
    wire ddram_we;

    wire player_busy;
    wire vgm_header_valid;
    wire [6:0] vgm_player_state_debug;
    wire [15:0] vgm_player_core_debug;
    wire [31:0] vgm_header_magic_read_debug;
    wire [3:0] vgm_header_magic_fail_index_debug;
    wire [31:0] mode5_player_start_count;
    wire vgm_load_done;
    wire vgm_load_error;
    wire vgm_load_overflow;
    wire [ADDR_WIDTH:0] vgm_load_size;

    logic [63:0] ddram_mem [0:31];
    logic [28:0] read_addr_q = 29'd0;
    logic read_pending = 1'b0;

    always #5 clk = ~clk;

    mister_vgm_md_top #(
        .REGION_MODE                     (5),
        .VGM_LOAD_ADDR_WIDTH             (ADDR_WIDTH),
        .MODE5_VGM_BACKEND               (1),
        .POWER_ON_RESET_CYCLES           (32'd0),
        .START_DELAY_CYCLES              (32'd0),
        .AUDIO_WARMUP_SAMPLES            (16'd0),
        .MODE5_SOUND_RESET_CYCLES        (32'd0),
        .MODE5_AUDIO_UNMUTE_DELAY_CYCLES (32'd0)
    ) dut (
        .clk                            (clk),
        .reset_n                        (reset_n),
        .audio_lpf_mode                 (2'b00),
        .audio_gain_boost               (1'b0),
        .audio_psg_level                (2'b00),
        .ioctl_download                 (ioctl_download),
        .ioctl_wr                       (ioctl_wr),
        .ioctl_addr                     (ioctl_addr),
        .ioctl_dout                     (ioctl_dout),
        .ioctl_index                    (16'd1),
        .player_busy                    (player_busy),
        .vgm_header_valid               (vgm_header_valid),
        .vgm_player_state_debug         (vgm_player_state_debug),
        .vgm_player_core_debug          (vgm_player_core_debug),
        .vgm_header_magic_read_debug    (vgm_header_magic_read_debug),
        .vgm_header_magic_fail_index_debug(vgm_header_magic_fail_index_debug),
        .mode5_player_start_count       (mode5_player_start_count),
        .vgm_load_done                  (vgm_load_done),
        .vgm_load_error                 (vgm_load_error),
        .vgm_load_overflow              (vgm_load_overflow),
        .vgm_load_size                  (vgm_load_size),
        .ddram_busy                     (1'b0),
        .ddram_addr                     (ddram_addr),
        .ddram_dout                     (ddram_dout),
        .ddram_dout_ready               (ddram_dout_ready),
        .ddram_din                      (ddram_din),
        .ddram_be                       (ddram_be),
        .ddram_rd                       (ddram_rd),
        .ddram_we                       (ddram_we)
    );

    task automatic write_byte(input logic [7:0] addr, input logic [7:0] data);
        begin
            @(negedge clk);
            ioctl_addr = {19'd0, addr};
            ioctl_dout = data;
            ioctl_wr = 1'b1;
            @(posedge clk);
            @(negedge clk);
            ioctl_wr = 1'b0;
            @(posedge clk);
        end
    endtask

    always_ff @(posedge clk) begin
        ddram_dout_ready <= read_pending;
        ddram_dout <= ddram_mem[read_addr_q - VGM_BASE];
        read_pending <= 1'b0;

        if (ddram_we) begin
            if (ddram_be[0]) ddram_mem[ddram_addr - VGM_BASE][7:0] <= ddram_din[7:0];
            if (ddram_be[1]) ddram_mem[ddram_addr - VGM_BASE][15:8] <= ddram_din[15:8];
            if (ddram_be[2]) ddram_mem[ddram_addr - VGM_BASE][23:16] <= ddram_din[23:16];
            if (ddram_be[3]) ddram_mem[ddram_addr - VGM_BASE][31:24] <= ddram_din[31:24];
            if (ddram_be[4]) ddram_mem[ddram_addr - VGM_BASE][39:32] <= ddram_din[39:32];
            if (ddram_be[5]) ddram_mem[ddram_addr - VGM_BASE][47:40] <= ddram_din[47:40];
            if (ddram_be[6]) ddram_mem[ddram_addr - VGM_BASE][55:48] <= ddram_din[55:48];
            if (ddram_be[7]) ddram_mem[ddram_addr - VGM_BASE][63:56] <= ddram_din[63:56];
        end

        if (ddram_rd) begin
            read_addr_q <= ddram_addr;
            read_pending <= 1'b1;
        end
    end

    integer i;
    integer timeout;

    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            ddram_mem[i] = 64'd0;
        end

        repeat (4) @(posedge clk);
        reset_n = 1'b1;
        wait (dut.reset === 1'b0);
        repeat (4) @(posedge clk);

        @(negedge clk);
        ioctl_download = 1'b1;
        @(posedge clk);
        for (i = 0; i < 65; i = i + 1) begin
            write_byte(i[7:0], 8'h00);
        end
        write_byte(8'h00, "V");
        write_byte(8'h01, "g");
        write_byte(8'h02, "m");
        write_byte(8'h03, " ");
        write_byte(8'h40, 8'h66);
        @(negedge clk);
        ioctl_download = 1'b0;
        @(posedge clk);

        timeout = 0;
        while (!vgm_header_valid && (timeout < 1000)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (mode5_player_start_count == 32'd0) begin
            $display("FAIL start_count stayed zero core=%04h state=%0d load_done=%0b load_error=%0b overflow=%0b size=%0d",
                     vgm_player_core_debug, vgm_player_state_debug,
                     vgm_load_done, vgm_load_error, vgm_load_overflow,
                     vgm_load_size);
            $finish;
        end

        if (!vgm_header_valid) begin
            $display("FAIL header_valid timeout core=%04h state=%0d magic=%08h mf=%0d",
                     vgm_player_core_debug,
                     vgm_player_state_debug,
                     vgm_header_magic_read_debug,
                     vgm_header_magic_fail_index_debug);
            $finish;
        end

        if (vgm_header_magic_read_debug != 32'h206d_6756) begin
            $display("FAIL magic readback expected 206d6756 got %08h",
                     vgm_header_magic_read_debug);
            $finish;
        end

        $display("PASS tb_mode5_ddram_header_start core=%04h magic=%08h",
                 vgm_player_core_debug, vgm_header_magic_read_debug);
        $finish;
    end
endmodule

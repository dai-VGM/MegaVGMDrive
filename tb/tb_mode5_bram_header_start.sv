`timescale 1ns/1ps

module tb_mode5_bram_header_start;
    localparam int ADDR_WIDTH = 8;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic ioctl_download = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_dout = 8'd0;

    wire player_busy;
    wire vgm_header_valid;
    wire [6:0] vgm_player_state_debug;
    wire vgm_mem_rd_req_debug;
    wire vgm_mem_rd_valid_debug;
    wire [15:0] vgm_player_core_debug;
    wire [7:0] vgm_player_last_read_byte_debug;
    wire [31:0] mode5_player_start_count;
    wire vgm_load_done;
    wire vgm_load_error;
    wire vgm_load_overflow;
    wire [ADDR_WIDTH:0] vgm_load_size;

    always #5 clk = ~clk;

    mister_vgm_md_top #(
        .REGION_MODE                     (5),
        .VGM_LOAD_ADDR_WIDTH             (ADDR_WIDTH),
        .MODE5_VGM_BACKEND               (0),
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
        .vgm_mem_rd_req_debug           (vgm_mem_rd_req_debug),
        .vgm_mem_rd_valid_debug         (vgm_mem_rd_valid_debug),
        .vgm_player_core_debug          (vgm_player_core_debug),
        .vgm_player_last_read_byte_debug(vgm_player_last_read_byte_debug),
        .mode5_player_start_count       (mode5_player_start_count),
        .vgm_load_done                  (vgm_load_done),
        .vgm_load_error                 (vgm_load_error),
        .vgm_load_overflow              (vgm_load_overflow),
        .vgm_load_size                  (vgm_load_size),
        .ddram_busy                     (1'b0),
        .ddram_dout                     (64'd0),
        .ddram_dout_ready               (1'b0)
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

    integer i;
    integer timeout;

    initial begin
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
        while (!vgm_header_valid && (timeout < 500)) begin
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

        if (!vgm_player_core_debug[12]) begin
            $display("FAIL player did not request header byte core=%04h state=%0d",
                     vgm_player_core_debug, vgm_player_state_debug);
            $finish;
        end

        if (!vgm_player_core_debug[10]) begin
            $display("FAIL player never saw mem valid core=%04h state=%0d",
                     vgm_player_core_debug, vgm_player_state_debug);
            $finish;
        end

        if (!vgm_header_valid) begin
            $display("FAIL header_valid timeout core=%04h state=%0d last=%02h",
                     vgm_player_core_debug,
                     vgm_player_state_debug,
                     vgm_player_last_read_byte_debug);
            $finish;
        end

        $display("PASS tb_mode5_bram_header_start core=%04h state=%0d",
                 vgm_player_core_debug, vgm_player_state_debug);
        $finish;
    end
endmodule

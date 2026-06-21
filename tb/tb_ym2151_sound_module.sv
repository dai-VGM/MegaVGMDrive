module tb_ym2151_sound_module;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cmd_valid = 1'b0;
    logic [7:0] cmd_reg = 8'd0;
    logic [7:0] cmd_data = 8'd0;
    wire cmd_ready;
    wire signed [15:0] audio_l;
    wire signed [15:0] audio_r;
    wire audio_sample_valid;

    integer sample_count = 0;

    ym2151_sound_module #(
        .CLK_SYS_HZ    (32'd20_000_000),
        .YM2151_CLK_HZ (32'd4_000_000)
    ) dut (
        .clk                (clk),
        .reset              (reset),
        .ym2151_cmd_valid   (cmd_valid),
        .ym2151_cmd_reg     (cmd_reg),
        .ym2151_cmd_data    (cmd_data),
        .ym2151_cmd_ready   (cmd_ready),
        .audio_l            (audio_l),
        .audio_r            (audio_r),
        .audio_sample_valid (audio_sample_valid)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (reset) begin
            sample_count <= 0;
        end else if (audio_sample_valid) begin
            sample_count <= sample_count + 1;
        end
    end

    task send_cmd(input logic [7:0] reg_addr, input logic [7:0] reg_data);
        begin
            wait (cmd_ready);
            @(posedge clk);
            cmd_reg <= reg_addr;
            cmd_data <= reg_data;
            cmd_valid <= 1'b1;
            @(posedge clk);
            cmd_valid <= 1'b0;
            wait (cmd_ready);
        end
    endtask

    initial begin
        repeat (8) @(posedge clk);
        reset <= 1'b0;
        send_cmd(8'h20, 8'hc7);
        send_cmd(8'h28, 8'h4a);
        send_cmd(8'h08, 8'h78);
        repeat (5000) @(posedge clk);
        if (!cmd_ready) begin
            $display("FAIL ym2151 wrapper did not return ready");
            $finish;
        end
        if (sample_count == 0) begin
            $display("FAIL ym2151 wrapper produced no sample strobes");
            $finish;
        end
        $display("PASS tb_ym2151_sound_module samples=%0d last_l=%0d last_r=%0d",
                 sample_count, audio_l, audio_r);
        $finish;
    end
endmodule

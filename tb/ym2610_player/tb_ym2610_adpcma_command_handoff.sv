`timescale 1ns/1ps

// Production MMR -> ADPCM-A driver handoff regression.  The legacy build is
// compiled from the exact ba6f795 tree; the fixed build uses the worktree.
module tb_ym2610_adpcma_command_handoff;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic rst_n;
    logic cen = 1'b0;
    integer cen_phase = 0;
    integer phase_seed = 0;
    integer system_cycles = 0;

    logic [7:0] din = 8'h00;
    logic write = 1'b0;
    logic [1:0] bus_addr = 2'b00;
    wire busy;
    wire clk_en;
    wire clk_en_666;
    wire clk_en_111;
    wire [7:0] aon_a;
    wire [5:0] atl_a;
    wire [95:0] start_addr_a;
    wire [95:0] end_addr_a;
    wire [7:0] lracl;
    wire [5:0] up_start;
    wire [5:0] up_end;
    wire [2:0] up_lracl;
    wire up_aon;
    wire aon_accept;

    wire [19:0] adpcma_addr;
    wire [3:0] adpcma_bank;
    wire adpcma_roe_n;
    wire [5:0] adpcma_flags;
    wire signed [15:0] adpcma_l;
    wire signed [15:0] adpcma_r;

    integer accept_count;
    integer consume_count;
    integer aon_apply_count [0:5];
    integer aoff_apply_count [0:5];
    integer index;

    wire [5:0] current_channel = production_driver.cur_ch;
    wire [20:0] current_addr1 = production_driver.u_cnt.addr1;
    wire [15:0] current_start = production_driver.start_top;
    wire [15:0] current_end = production_driver.end_top;
    wire current_on1 = production_driver.u_cnt.on1;
    wire current_done1 = production_driver.u_cnt.done1;
    wire command_valid = production_driver.aon_cmd_valid;
    wire command_consume = production_driver.audit_command_consume;

    always #5 clk = ~clk;

    always @(posedge clk)
        system_cycles <= system_cycles + 1;

    // Isolated pulses at the same 8 MHz / 20 MHz density as production.
    always @(negedge clk) begin
        if (rst) begin
            cen_phase <= phase_seed;
            cen <= 1'b0;
        end else begin
            cen <= (cen_phase == 1 || cen_phase == 3);
            cen_phase <= cen_phase == 4 ? 0 : cen_phase + 1;
        end
    end

    jt12_rst u_rst (
        .rst(rst),
        .clk(clk),
        .rst_n(rst_n)
    );

    ym2610_hw0_jt12_mmr #(
        .use_ssg(0), .num_ch(6), .use_pcm(0), .use_adpcm(1),
        .mask_div(0)
    ) production_mmr (
        .rst(rst), .clk(clk), .cen(cen),
        .clk_en(clk_en), .clk_en_666(clk_en_666),
        .clk_en_111(clk_en_111),
        .din(din), .write(write), .addr(bus_addr), .busy(busy),
        .flag_A(1'b0), .overflow_A(1'b0),
        .aon_a(aon_a), .atl_a(atl_a),
        .start_addr_a(start_addr_a), .end_addr_a(end_addr_a),
        .lracl(lracl), .up_start(up_start), .up_end(up_end),
        .up_lracl(up_lracl), .up_aon(up_aon),
`ifndef EXPECT_LEGACY_LOSS
        .aon_accept(aon_accept),
`endif
        .debug_bus(8'h00)
    );

    ym2610_hw0_jt10_adpcm_drvA production_driver (
        .rst_n(rst_n), .clk(clk), .cen(cen),
        .cen6(clk_en_666), .cen1(clk_en_111),
        .addr(adpcma_addr), .bank(adpcma_bank), .roe_n(adpcma_roe_n),
        .atl(atl_a), .lracl_in(lracl),
        .start_addr_in(start_addr_a), .end_addr_in(end_addr_a),
        .up_lracl(up_lracl), .up_start(up_start), .up_end(up_end),
        .aon_cmd(aon_a), .up_aon(up_aon),
`ifndef EXPECT_LEGACY_LOSS
        .aon_accept(aon_accept),
`endif
        .datain(8'h00), .flags(adpcma_flags), .clr_flags(6'h00),
        .pcm55_l(adpcma_l), .pcm55_r(adpcma_r), .ch_enable(6'h3f)
    );

`ifdef EXPECT_LEGACY_LOSS
    assign aon_accept = cen && up_aon && production_driver.up_aon_armed;
`endif

    function automatic integer channel_index(input [5:0] one_hot);
        begin
            case (one_hot)
                6'h01: channel_index = 0;
                6'h02: channel_index = 1;
                6'h04: channel_index = 2;
                6'h08: channel_index = 3;
                6'h10: channel_index = 4;
                6'h20: channel_index = 5;
                default: channel_index = -1;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            accept_count <= 0;
            consume_count <= 0;
            for (index = 0; index < 6; index = index + 1) begin
                aon_apply_count[index] <= 0;
                aoff_apply_count[index] <= 0;
            end
        end else begin
            if (aon_accept)
                accept_count <= accept_count + 1;
            if (command_consume)
                consume_count <= consume_count + 1;
            if (clk_en_666 && channel_index(current_channel) >= 0) begin
                if (production_driver.aon_sr[0])
                    aon_apply_count[channel_index(current_channel)] <=
                        aon_apply_count[channel_index(current_channel)] + 1;
                if (production_driver.aoff_sr[0])
                    aoff_apply_count[channel_index(current_channel)] <=
                        aoff_apply_count[channel_index(current_channel)] + 1;
            end
        end
    end

    task automatic reset_case(input integer seed);
        begin
            @(negedge clk);
            rst = 1'b1;
            phase_seed = seed;
            bus_addr = 2'b00;
            din = 8'h00;
            write = 1'b0;
            repeat (16) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
            repeat (40) @(posedge clk);
        end
    endtask

    task automatic wait_busy_clear;
        integer timeout;
        begin
            timeout = 0;
            while (busy !== 1'b0 && timeout < 30000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (busy !== 1'b0)
                $fatal(1, "BUSY did not clear");
        end
    endtask

    task automatic address_phase(input [7:0] reg_addr);
        begin
            wait_busy_clear();
            @(negedge clk);
            bus_addr = 2'b10;
            din = reg_addr;
            write = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            bus_addr = 2'b00;
            din = 8'h00;
            write = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic data_phase(input [7:0] value);
        begin
            @(negedge clk);
            bus_addr = 2'b11;
            din = value;
            write = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            bus_addr = 2'b00;
            din = 8'h00;
            write = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic write_port1(input [7:0] reg_addr, input [7:0] value);
        begin
            address_phase(reg_addr);
            data_phase(value);
        end
    endtask

    task automatic wait_clk_en_reference;
        integer timeout;
        begin
            timeout = 0;
            while (clk_en !== 1'b1 && timeout < 30000) begin
                @(negedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (clk_en !== 1'b1)
                $fatal(1, "No clk_en reference");
        end
    endtask

    task automatic wait_future_cen(input integer count);
        integer seen;
        begin
            seen = 0;
            while (seen < count) begin
                @(negedge clk);
                #1;
                if (cen)
                    seen = seen + 1;
            end
        end
    endtask

    task automatic wait_command_counts(
        input integer expected_accept,
        input integer expected_consume
    );
        integer timeout;
        begin
            timeout = 0;
            while ((accept_count != expected_accept ||
                    consume_count != expected_consume) && timeout < 30000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (accept_count != expected_accept ||
                consume_count != expected_consume)
                $fatal(1, "command count timeout accept=%0d/%0d consume=%0d/%0d",
                       accept_count, expected_accept,
                       consume_count, expected_consume);
        end
    endtask

    // Places the data write on the proven bad phase: its CEN pulse publishes
    // clk_en at the following negedge; the next active edge has CEN low.
    task automatic command_bad_phase(
        input [7:0] value,
        input logic expect_loss
    );
        integer accept_before;
        integer consume_before;
        begin
            wait_busy_clear();
            address_phase(8'h00);
            accept_before = accept_count;
            consume_before = consume_count;
            wait_clk_en_reference();
            wait_future_cen(6);
            bus_addr = 2'b11;
            din = value;
            write = 1'b1;
            @(posedge clk);
            #1;
            if (!up_aon)
                $fatal(1, "MMR did not accept reg00=%02h", value);
            @(negedge clk);
            #1;
            if (clk_en !== 1'b1 || cen !== 1'b0)
                $fatal(1, "bad-phase contract missing clk_en=%b cen=%b",
                       clk_en, cen);
            bus_addr = 2'b00;
            din = 8'h00;
            write = 1'b0;
            @(posedge clk);
            #1;
            if (expect_loss) begin
                if (up_aon || accept_count != accept_before || command_valid)
                    $fatal(1, "legacy command was not lost");
                repeat (20) @(posedge clk);
                #1;
                if (accept_count != accept_before ||
                    consume_count != consume_before)
                    $fatal(1, "legacy command appeared after loss edge");
            end else begin
                if (!up_aon)
                    $fatal(1, "fixed pending command cleared before CEN accept");
                wait_command_counts(accept_before + 1, consume_before + 1);
                if (up_aon || command_valid)
                    $fatal(1, "fixed command did not drain exactly once");
            end
        end
    endtask

    task automatic command_safe_phase(input [7:0] value);
        integer accept_before;
        integer consume_before;
        begin
            wait_busy_clear();
            address_phase(8'h00);
            accept_before = accept_count;
            consume_before = consume_count;
            wait_clk_en_reference();
            wait_future_cen(1);
            bus_addr = 2'b11;
            din = value;
            write = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            #1;
            if (clk_en)
                $fatal(1, "safe phase selected clk_en clear edge");
            bus_addr = 2'b00;
            din = 8'h00;
            write = 1'b0;
            wait_command_counts(accept_before + 1, consume_before + 1);
        end
    endtask

    task automatic configure_channel(
        input integer channel,
        input [15:0] start_value,
        input [15:0] end_value
    );
        begin
            write_port1(8'h10 + channel[7:0], start_value[7:0]);
            write_port1(8'h18 + channel[7:0], start_value[15:8]);
            write_port1(8'h20 + channel[7:0], end_value[7:0]);
            write_port1(8'h28 + channel[7:0], end_value[15:8]);
        end
    endtask

    task automatic wait_owner_state(
        input [5:0] owner,
        input [15:0] expected_start,
        input [15:0] expected_end,
        input [19:0] expected_addr,
        input logic expected_on
    );
        integer timeout;
        begin
            timeout = 0;
            while (timeout < 500000) begin
                @(posedge clk);
                #1;
                if (current_channel == owner &&
                    current_start == expected_start &&
                    current_end == expected_end &&
                    current_addr1[20:1] == expected_addr &&
                    current_on1 == expected_on)
                    timeout = 500000;
                else
                    timeout = timeout + 1;
            end
            if (!(current_channel == owner &&
                  current_start == expected_start &&
                  current_end == expected_end &&
                  current_addr1[20:1] == expected_addr &&
                  current_on1 == expected_on))
                $fatal(1, "owner state timeout owner=%02h cur=%02h addr=%05h start=%04h end=%04h on=%b",
                       owner, current_channel, current_addr1[20:1],
                       current_start, current_end, current_on1);
        end
    endtask

    task automatic wait_owner_on(input [5:0] owner, input logic expected_on);
        integer timeout;
        begin
            timeout = 0;
            while (timeout < 300000) begin
                @(posedge clk);
                #1;
                if (current_channel == owner && current_on1 == expected_on)
                    timeout = 300000;
                else
                    timeout = timeout + 1;
            end
            if (!(current_channel == owner && current_on1 == expected_on))
                $fatal(1, "owner on-state timeout owner=%02h on=%b",
                       owner, expected_on);
        end
    endtask

    task automatic wait_owner_addr_at_least(
        input [5:0] owner,
        input [19:0] minimum_addr
    );
        integer timeout;
        begin
            timeout = 0;
            while (timeout < 1000000) begin
                @(posedge clk);
                #1;
                if (current_channel == owner && current_on1 &&
                    current_addr1[20:1] >= minimum_addr)
                    timeout = 1000000;
                else
                    timeout = timeout + 1;
            end
            if (!(current_channel == owner && current_on1 &&
                  current_addr1[20:1] >= minimum_addr))
                $fatal(1, "owner did not advance owner=%02h addr=%05h min=%05h",
                       owner, current_addr1[20:1], minimum_addr);
        end
    endtask

    task automatic gf12_sequence(input logic expect_legacy_failure);
        reg [19:0] old_addr_before_stop;
        integer timeout;
        begin
            reset_case(0);
            configure_channel(1, 16'h0251, 16'h0265);
            command_safe_phase(8'h02);
            wait_owner_on(6'h02, 1'b1);
            wait_owner_addr_at_least(6'h02, 20'h25120);
            old_addr_before_stop = current_addr1[20:1];

            command_bad_phase(8'h82, expect_legacy_failure);
            if (!expect_legacy_failure)
                wait_owner_on(6'h02, 1'b0);

            configure_channel(1, 16'h0AB4, 16'h0AC8);
            command_bad_phase(8'h02, expect_legacy_failure);

            if (expect_legacy_failure) begin
                // New persistent staging reaches ch1 while its old counter is
                // still on and has not been reloaded.
                timeout = 0;
                while (timeout < 500000) begin
                    @(posedge clk);
                    #1;
                    if (current_channel == 6'h02 &&
                        current_start == 16'h0AB4 &&
                        current_end == 16'h0AC8 && current_on1)
                        timeout = 500000;
                    else
                        timeout = timeout + 1;
                end
                if (!(current_channel == 6'h02 &&
                      current_start == 16'h0AB4 &&
                      current_end == 16'h0AC8 && current_on1 &&
                      current_addr1[20:1] >= old_addr_before_stop &&
                      current_addr1[20:1] < 20'h26600 &&
                      current_addr1[20:1] != 20'hAB400))
                    $fatal(1, "legacy trajectory mismatch before=%05h now=%05h",
                           old_addr_before_stop, current_addr1[20:1]);
                $display("GF12_PREFIX_FAIL_EXPECTED start=0AB4 end=0AC8 addr=%05h trajectory=OLD",
                         current_addr1[20:1]);
            end else begin
                wait_owner_state(6'h02, 16'h0AB4, 16'h0AC8,
                                 20'hAB400, 1'b1);
                $display("GF12_POSTFIX_PASS start=0AB4 end=0AC8 addr=AB400 trajectory=NEW");
            end
        end
    endtask

    task automatic fixed_phase_matrix;
        integer seed;
        begin
            for (seed = 0; seed < 5; seed = seed + 1) begin
                reset_case(seed);
                command_bad_phase(8'h01 << seed, 1'b0);
                repeat (2000) @(posedge clk);
                #1;
                if (accept_count != 1 || consume_count != 1)
                    $fatal(1, "phase duplicate/loss seed=%0d", seed);
            end
            $display("SPARSE_CEN_PHASE_MATRIX_PASS offsets=5");
        end
    endtask

    task automatic all_six_channels;
        integer channel;
        integer accepts_before;
        integer consumes_before;
        begin
            reset_case(2);
            for (channel = 0; channel < 6; channel = channel + 1)
                configure_channel(channel, 16'h0100 + channel,
                                  16'h0110 + channel);
            command_bad_phase(8'h3F, 1'b0);
            repeat (30000) @(posedge clk);
            #1;
            for (channel = 0; channel < 6; channel = channel + 1)
                if (aon_apply_count[channel] != 1)
                    $fatal(1, "channel %0d key-on applications=%0d",
                           channel, aon_apply_count[channel]);

            accepts_before = accept_count;
            consumes_before = consume_count;
            command_bad_phase(8'hBF, 1'b0);
            repeat (30000) @(posedge clk);
            #1;
            for (channel = 0; channel < 6; channel = channel + 1)
                if (aoff_apply_count[channel] != 1)
                    $fatal(1, "channel %0d stop applications=%0d",
                           channel, aoff_apply_count[channel]);
            if (accept_count != accepts_before + 1 ||
                consume_count != consumes_before + 1)
                $fatal(1, "six-channel command count mismatch");
            $display("ALL_SIX_CHANNELS_PASS key_on_once=1 stop_once=1");
        end
    endtask

    task automatic back_to_back_legal;
        integer command;
        integer accept_before;
        integer consume_before;
        begin
            reset_case(3);
            // Exercise the shortest generic BUSY setting.  Production
            // YM2610 masks divider writes, but the shared MMR contract must
            // still preserve ordering when mask_div is disabled.
            wait_busy_clear();
            @(negedge clk);
            bus_addr = 2'b00;
            din = 8'h2F;
            write = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            bus_addr = 2'b00;
            din = 8'h00;
            write = 1'b0;
            repeat (8) @(posedge clk);
            if (production_mmr.div_setting != 2'b00)
                $fatal(1, "fast divider selection failed");

            accept_before = accept_count;
            consume_before = consume_count;
            // No delay beyond the chip's public BUSY contract.  Sustained
            // commands would outrun the six-lane consume rate without the
            // pending-aware BUSY hold.
            for (command = 0; command < 12; command = command + 1)
                write_port1(8'h00, command[0] ? 8'h81 : 8'h01);
            wait_command_counts(accept_before + 12, consume_before + 12);
            repeat (30000) @(posedge clk);
            #1;
            if (accept_count != 12 || consume_count != 12 ||
                aon_apply_count[0] != 6 || aoff_apply_count[0] != 6)
                $fatal(1, "back-to-back command duplicate");
            $display("BACK_TO_BACK_LEGAL_PASS accepts=12 consumes=12 fast_div=1");
        end
    endtask

    task automatic reset_pending;
        integer accept_before;
        begin
            reset_case(4);
            wait_busy_clear();
            address_phase(8'h00);
            accept_before = accept_count;
            wait_clk_en_reference();
            wait_future_cen(6);
            bus_addr = 2'b11;
            din = 8'h02;
            write = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            #1;
            if (clk_en !== 1'b1 || cen !== 1'b0)
                $fatal(1, "reset-pending did not reach hold phase");
            bus_addr = 2'b00;
            din = 8'h00;
            write = 1'b0;
            @(posedge clk);
            #1;
            if (!up_aon || accept_count != accept_before)
                $fatal(1, "command not pending before reset");
            @(negedge clk);
            rst = 1'b1;
            repeat (8) @(posedge clk);
            #1;
            if (up_aon || command_valid || accept_count != 0 ||
                consume_count != 0)
                $fatal(1, "stale command survived reset");
            @(negedge clk);
            rst = 1'b0;
            repeat (30000) @(posedge clk);
            #1;
            if (accept_count != 0 || consume_count != 0)
                $fatal(1, "reset command applied late");
            $display("RESET_PENDING_PASS stale=0 application=0");
        end
    endtask

    initial begin
`ifdef EXPECT_LEGACY_LOSS
        gf12_sequence(1'b1);
        $display("ADPCMA_HANDOFF_LEGACY_EXPECTED_FAIL_PASS");
`else
        gf12_sequence(1'b0);
        fixed_phase_matrix();
        all_six_channels();
        back_to_back_legal();
        reset_pending();
        $display("ADPCMA_HANDOFF_FIXED_REGRESSION_PASS");
`endif
        $finish;
    end
endmodule

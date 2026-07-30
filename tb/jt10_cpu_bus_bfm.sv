`timescale 1ns/1ps

// Test-only YM2610/JT10 CPU-bus master.
//
// The BFM performs real status reads through dout[7].  It never inspects or
// changes JT10 internals and never substitutes a fixed delay for BUSY polling.
module jt10_cpu_bus_bfm (
    input                  rst,
    input                  clk,
    input            [7:0] dout,
    output logic     [1:0] addr = 2'b00,
    output logic     [7:0] din = 8'h00,
    output logic           cs_n = 1'b1,
    output logic           wr_n = 1'b1,

    output integer         accepted_write_count = 0,
    output integer         port0_write_count = 0,
    output integer         port1_write_count = 0,
    output integer         busy_timeout_count = 0,
    output integer         busy_while_write_count = 0,
    output integer         busy_min_cycles = 32'h7fffffff,
    output integer         busy_max_cycles = 0,
    output integer         last_issue_cycle = -1,
    output integer         last_busy_assert_cycle = -1,
    output integer         last_busy_clear_cycle = -1,
    output logic    [63:0] busy_duration_hash =
        64'hcbf29ce484222325
);
    localparam integer BUSY_ASSERT_TIMEOUT = 64;
    localparam integer BUSY_CLEAR_TIMEOUT = 4096;

    integer system_cycle = 0;
    integer transaction_index = 0;
    integer status_x_count = 0;

    function automatic [63:0] hash_byte(
        input [63:0] hash_in,
        input [7:0] value
    );
        hash_byte =
            (hash_in ^ value) * 64'h00000100000001b3;
    endfunction

    always @(posedge clk)
        system_cycle = system_cycle + 1;

    task automatic jt10_idle;
        begin
            @(negedge clk);
            addr = 2'b00;
            din = 8'h00;
            cs_n = 1'b1;
            wr_n = 1'b1;
        end
    endtask

    task automatic jt10_status_read(output reg [7:0] status);
        begin
            @(negedge clk);
            addr = 2'b00;
            din = 8'h00;
            cs_n = 1'b0;
            wr_n = 1'b1;
            @(posedge clk);
            #1;
            status = dout;
            if ($isunknown(status)) begin
                status_x_count = status_x_count + 1;
                $display("FAIL BUS_STATUS_X cycle=%0d status=%b",
                         system_cycle, status);
            end
        end
    endtask

    task automatic jt10_wait_busy_clear;
        integer poll_count;
        reg [7:0] status;
        begin
            poll_count = 0;
            jt10_status_read(status);
            while (status[7] !== 1'b0 &&
                   poll_count < BUSY_CLEAR_TIMEOUT) begin
                poll_count = poll_count + 1;
                jt10_status_read(status);
            end
            if (status[7] !== 1'b0) begin
                busy_timeout_count = busy_timeout_count + 1;
                $display("FAIL BUSY_CLEAR_TIMEOUT cycle=%0d polls=%0d",
                         system_cycle, poll_count);
            end
            jt10_idle();
        end
    endtask

    task automatic jt10_bus_pulse(
        input [1:0] phase_addr,
        input [7:0] value
    );
        reg [7:0] status;
        begin
            jt10_status_read(status);
            if (status[7] !== 1'b0) begin
                busy_while_write_count = busy_while_write_count + 1;
                $display("FAIL WRITE_WHILE_BUSY cycle=%0d phase=%02b",
                         system_cycle, phase_addr);
                jt10_wait_busy_clear();
            end
            @(negedge clk);
            addr = phase_addr;
            din = value;
            cs_n = 1'b0;
            wr_n = 1'b0;
            @(posedge clk);
            #1;
            if (phase_addr[0])
                last_issue_cycle = system_cycle;
            @(negedge clk);
            addr = 2'b00;
            din = 8'h00;
            cs_n = 1'b1;
            wr_n = 1'b1;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic jt10_write_register(
        input       port,
        input [7:0] reg_addr,
        input [7:0] reg_data
    );
        integer assert_polls;
        integer clear_polls;
        integer duration;
        reg [7:0] status;
        begin
            jt10_wait_busy_clear();

            // Port 0 uses address/data phases 00/01; port 1 uses 10/11.
            jt10_bus_pulse({port, 1'b0}, reg_addr);
            jt10_bus_pulse({port, 1'b1}, reg_data);

            accepted_write_count = accepted_write_count + 1;
            transaction_index = transaction_index + 1;
            if (port)
                port1_write_count = port1_write_count + 1;
            else
                port0_write_count = port0_write_count + 1;

            assert_polls = 0;
            jt10_status_read(status);
            while (status[7] !== 1'b1 &&
                   assert_polls < BUSY_ASSERT_TIMEOUT) begin
                assert_polls = assert_polls + 1;
                jt10_status_read(status);
            end
            if (status[7] !== 1'b1) begin
                busy_timeout_count = busy_timeout_count + 1;
                last_busy_assert_cycle = -1;
                $display(
                    "FAIL BUSY_ASSERT_TIMEOUT index=%0d port=%0d reg=%02h data=%02h issue=%0d",
                    transaction_index, port, reg_addr, reg_data,
                    last_issue_cycle
                );
            end else begin
                last_busy_assert_cycle = system_cycle;
            end

            clear_polls = 0;
            while (status[7] !== 1'b0 &&
                   clear_polls < BUSY_CLEAR_TIMEOUT) begin
                clear_polls = clear_polls + 1;
                jt10_status_read(status);
            end
            if (status[7] !== 1'b0) begin
                busy_timeout_count = busy_timeout_count + 1;
                last_busy_clear_cycle = -1;
                $display(
                    "FAIL BUSY_CLEAR_TIMEOUT index=%0d port=%0d reg=%02h data=%02h issue=%0d",
                    transaction_index, port, reg_addr, reg_data,
                    last_issue_cycle
                );
            end else begin
                last_busy_clear_cycle = system_cycle;
                duration = last_busy_clear_cycle - last_issue_cycle;
                if (duration < busy_min_cycles)
                    busy_min_cycles = duration;
                if (duration > busy_max_cycles)
                    busy_max_cycles = duration;
                busy_duration_hash =
                    hash_byte(busy_duration_hash, duration[7:0]);
                busy_duration_hash =
                    hash_byte(busy_duration_hash, duration[15:8]);
            end
            $display(
                "BUS_WRITE index=%0d port=%0d address_phase=%02b data_phase=%02b register=%02h data=%02h issue_cycle=%0d busy_assert_cycle=%0d busy_clear_cycle=%0d busy_duration=%0d timeout=%0d",
                transaction_index, port, {port, 1'b0}, {port, 1'b1},
                reg_addr, reg_data, last_issue_cycle,
                last_busy_assert_cycle, last_busy_clear_cycle,
                last_busy_clear_cycle - last_issue_cycle,
                (last_busy_assert_cycle < 0 ||
                 last_busy_clear_cycle < 0)
            );
            jt10_idle();
        end
    endtask

    task automatic jt10_write_port0(
        input [7:0] reg_addr,
        input [7:0] reg_data
    );
        begin
            jt10_write_register(1'b0, reg_addr, reg_data);
        end
    endtask

    task automatic jt10_write_port1(
        input [7:0] reg_addr,
        input [7:0] reg_data
    );
        begin
            jt10_write_register(1'b1, reg_addr, reg_data);
        end
    endtask

    final begin
        if (status_x_count != 0)
            $display("FAIL BUS_STATUS_X_TOTAL count=%0d", status_x_count);
    end
endmodule

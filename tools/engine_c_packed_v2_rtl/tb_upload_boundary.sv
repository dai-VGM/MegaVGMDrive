`timescale 1ns/1ps
module tb_upload_boundary;
    logic clk=0,reset=1,download=0,wr=0;
    logic [26:0] address=0;
    logic [7:0] data=0;
    wire wait_io,load_done,load_pulse,load_error,load_overflow;
    wire [31:0] file_size,magic;
    wire [7:0] burst,be;
    wire [28:0] ddram_addr;
    wire [63:0] ddram_din;
    wire ddram_rd,ddram_we;
    integer writes=0;
    logic [28:0] last_addr;
    logic [7:0] last_be;
    logic [63:0] last_data;

    golden_player_shell_upload #(.VGM_ADDR_WIDTH(23),.FILE_INDEX(16'd1)) dut(
        .clk(clk),.reset(reset),.ioctl_download(download),.ioctl_wr(wr),
        .ioctl_addr(address),.ioctl_dout(data),.ioctl_index(16'd1),.ioctl_wait(wait_io),
        .file_read_request(1'b0),.file_read_address(23'd0),.file_read_ready(),
        .file_read_valid(),.file_read_data(),.load_busy(),.load_done(load_done),
        .load_done_pulse(load_pulse),.load_error(load_error),.load_overflow(load_overflow),
        .uploaded_physical_size(file_size),.upload_magic(magic),.ddram_busy(1'b0),
        .ddram_burstcnt(burst),.ddram_addr(ddram_addr),.ddram_dout(64'd0),
        .ddram_dout_ready(1'b0),.ddram_rd(ddram_rd),.ddram_din(ddram_din),
        .ddram_be(be),.ddram_we(ddram_we));

    always #1 clk=~clk;
    task tick; begin @(posedge clk);#1;if(ddram_we)begin
        writes=writes+1;last_addr=ddram_addr;last_be=be;last_data=ddram_din;end end endtask
    task clear; begin
        reset=1;download=0;wr=0;address=0;data=0;writes=0;repeat(3)tick();reset=0;tick();
    end endtask
    initial begin
        clear();download=1;tick();while(wait_io)tick();
        address=27'h07fffff;data=8'haa;wr=1;tick();wr=0;download=0;
        repeat(300)tick();
        assert(load_done&&!load_error&&!load_overflow&&file_size==32'h00800000)
            else $fatal(1,"final valid byte was not accepted");
        assert(writes==1&&last_addr==29'h060fffff&&last_be==8'h80&&last_data[63:56]==8'haa)
            else $fatal(1,"final valid byte wrapped or crossed DDR region");
        $display("UPLOAD final valid byte 0x7fffff -> DDR word 0x060fffff PASS");

        clear();download=1;tick();while(wait_io)tick();
        address=27'h0800000;data=8'h55;wr=1;tick();wr=0;download=0;
        repeat(300)tick();
        assert(load_overflow&&!load_done&&writes==0)
            else $fatal(1,"0x800000 was accepted, wrapped, or published");
        $display("UPLOAD 0x800000 rejected without wrap PASS");
        $finish;
    end
endmodule

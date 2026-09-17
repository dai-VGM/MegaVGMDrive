`timescale 1ns/1ps
module tb_engine_c_title_renderer;
    logic [9:0] h_count; logic [8:0] v_count; logic drawing_active=1;
    logic title_valid=0; logic [5:0] directory_length=0,basename_length=0;
    logic [6:0] title_read_addr; logic [7:0] title_read_data=0;
    logic [23:0] sid_activity_history=0; logic sid_model_8580=0,sid_timing_ntsc=0;
    logic text_pixel,panel_pixel; logic [23:0] panel_rgb;
    megavgm_title_renderer dut(.*);
    initial begin
        #1;
        if(dut.info_character(5)!="5" || dut.info_character(6)!="8" || dut.info_character(7)!="1") $fatal(1,"6581 label");
        if(dut.info_character(10)!="P" || dut.info_character(11)!="A" || dut.info_character(12)!="L") $fatal(1,"PAL label");
        sid_model_8580=1;sid_timing_ntsc=1;#1;
        if(dut.info_character(5)!="8" || dut.info_character(6)!="5" || dut.info_character(7)!="8") $fatal(1,"8580 label");
        if(dut.info_character(10)!="N" || dut.info_character(11)!="T" || dut.info_character(12)!="S" || dut.info_character(13)!="C") $fatal(1,"NTSC label");
        if(dut.lane_character(0,6)!="1" || dut.lane_character(1,6)!="2" || dut.lane_character(2,6)!="3") $fatal(1,"voice labels");
        if(dut.lane_character(3,0)!="D" || dut.lane_character(3,3)!="8") $fatal(1,"D418 label");
        h_count=192;v_count=71;sid_activity_history=0;#1;
        if(panel_rgb!==24'h102838)$fatal(1,"inactive palette");
        sid_activity_history[5]=1;#1;
        if(panel_rgb!==24'h40c5d8)$fatal(1,"active palette/oldest slot");
        h_count=232;sid_activity_history=1;#1;
        if(panel_rgb!==24'h40c5d8)$fatal(1,"newest slot");
        title_valid=1;directory_length=1;title_read_data="X";h_count=120;v_count=24;#1;
        if(title_read_addr!==0)$fatal(1,"directory title address regression");
        basename_length=1;v_count=34;#1;
        if(title_read_addr!==32)$fatal(1,"basename title address regression");
        $display("ENGINE_C_TITLE_RENDERER_PASS");$finish;
    end
endmodule

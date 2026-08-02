`timescale 1ns/1ps

module ym2610_hw0_sequencer #(
    parameter integer BOOT_SAMPLES = 159801,
    parameter integer COLOR_PREROLL_SAMPLES = 53267,
    parameter integer SOUND_DWELL_SAMPLES = 213068,
    parameter integer INTER_SILENCE_SAMPLES = 79901,
    parameter integer PAN_DWELL_SAMPLES = 159801,
    parameter integer PAN_INTER_SAMPLES = 53267,
    parameter integer NATURAL_SILENCE_SAMPLES = 79901,
    parameter integer FINAL_SILENCE_SAMPLES = 159801,
    parameter integer ZERO_TIMEOUT_SAMPLES = 8192,
    parameter integer ZERO_CONFIRM_SAMPLES = 32
) (
    input  logic               clk,
    input  logic               reset,
    input  logic               core_ready,
    input  logic               audio_zero,
    input  logic               sample_tick,
    input  logic               sample_contract_error,
    input  logic        [8:0]  chip_cycle_mod432,
    input  logic        [7:0]  bus_dout,
    input  logic               adpcmb_eos,
    input  logic               adpcmb_active,
    input  logic               adpcmb_request,
    output logic        [1:0]  bus_addr,
    output logic        [7:0]  bus_din,
    output logic               bus_cs_n,
    output logic               bus_wr_n,
    output logic        [3:0]  display_phase,
    output logic        [6:0]  segment_state,
    output logic        [2:0]  startup_state,
    output logic               audio_mute,
    output logic       [31:0]  sample_tick_count,
    output logic        [7:0]  microcode_index,
    output logic       [31:0]  accepted_write_count,
    output logic               busy_timeout,
    output logic               write_while_busy,
    output logic               zero_timeout,
    output logic               phase_error,
    output logic       [15:0]  sequence_restart_count,
    output logic               measurement_active,
    output logic        [3:0]  measurement_phase,
    output logic               halted
);
    localparam logic [4:0] P_SILENCE   = 5'd0;
    localparam logic [4:0] P_FM_CFG    = 5'd1;
    localparam logic [4:0] P_FM_ON     = 5'd2;
    localparam logic [4:0] P_FM_OFF    = 5'd3;
    localparam logic [4:0] P_SSG_CFG   = 5'd4;
    localparam logic [4:0] P_SSG_OFF   = 5'd6;
    localparam logic [4:0] P_A0_CFG    = 5'd7;
    localparam logic [4:0] P_A0_ON     = 5'd8;
    localparam logic [4:0] P_A0_OFF    = 5'd9;
    localparam logic [4:0] P_A6_CFG    = 5'd10;
    localparam logic [4:0] P_A6_ON     = 5'd11;
    localparam logic [4:0] P_A6_OFF    = 5'd12;
    localparam logic [4:0] P_B_STEREO  = 5'd13;
    localparam logic [4:0] P_B_LEFT    = 5'd14;
    localparam logic [4:0] P_B_RIGHT   = 5'd15;
    localparam logic [4:0] P_B_SHORT   = 5'd16;
    localparam logic [4:0] P_B_START   = 5'd17;
    localparam logic [4:0] P_B_RESET   = 5'd18;

    localparam logic [6:0] H_BOOT_WAIT       = 7'd0;
    localparam logic [6:0] H_BOOT_HOLD       = 7'd1;
    localparam logic [6:0] H_INITIAL_SILENCE = 7'd2;
    localparam logic [6:0] H_FM_PREROLL      = 7'd3;
    localparam logic [6:0] H_FM_START        = 7'd4;
    localparam logic [6:0] H_FM_ATTACK       = 7'd5;
    localparam logic [6:0] H_FM_MEASURE      = 7'd6;
    localparam logic [6:0] H_FM_HOLD         = 7'd7;
    localparam logic [6:0] H_FM_OFF          = 7'd8;
    localparam logic [6:0] H_FM_ZERO         = 7'd9;
    localparam logic [6:0] H_SILENCE_1       = 7'd10;
    localparam logic [6:0] H_SSG_PREROLL     = 7'd11;
    localparam logic [6:0] H_SSG_ALIGN       = 7'd12;
    localparam logic [6:0] H_SSG_ATTACK      = 7'd13;
    localparam logic [6:0] H_SSG_MEASURE     = 7'd14;
    localparam logic [6:0] H_SSG_HOLD        = 7'd15;
    localparam logic [6:0] H_SSG_OFF         = 7'd16;
    localparam logic [6:0] H_SSG_ZERO        = 7'd17;
    localparam logic [6:0] H_SILENCE_2       = 7'd18;
    localparam logic [6:0] H_A0_PREROLL      = 7'd19;
    localparam logic [6:0] H_A0_ALIGN        = 7'd20;
    localparam logic [6:0] H_A0_START        = 7'd21;
    localparam logic [6:0] H_A0_DWELL        = 7'd22;
    localparam logic [6:0] H_A0_OFF          = 7'd23;
    localparam logic [6:0] H_A0_ZERO         = 7'd24;
    localparam logic [6:0] H_SILENCE_3       = 7'd25;
    localparam logic [6:0] H_A6_PREROLL      = 7'd26;
    localparam logic [6:0] H_A6_ALIGN        = 7'd27;
    localparam logic [6:0] H_A6_START        = 7'd28;
    localparam logic [6:0] H_A6_DWELL        = 7'd29;
    localparam logic [6:0] H_A6_OFF          = 7'd30;
    localparam logic [6:0] H_A6_ZERO         = 7'd31;
    localparam logic [6:0] H_SILENCE_4       = 7'd32;
    localparam logic [6:0] H_B_PREROLL       = 7'd33;
    localparam logic [6:0] H_B_ALIGN         = 7'd34;
    localparam logic [6:0] H_B_START         = 7'd35;
    localparam logic [6:0] H_B_DWELL         = 7'd36;
    localparam logic [6:0] H_B_RESET         = 7'd37;
    localparam logic [6:0] H_B_ZERO          = 7'd38;
    localparam logic [6:0] H_SILENCE_5       = 7'd39;
    localparam logic [6:0] H_L_PREROLL       = 7'd40;
    localparam logic [6:0] H_L_ALIGN         = 7'd41;
    localparam logic [6:0] H_L_START         = 7'd42;
    localparam logic [6:0] H_L_DWELL         = 7'd43;
    localparam logic [6:0] H_L_RESET         = 7'd44;
    localparam logic [6:0] H_L_ZERO          = 7'd45;
    localparam logic [6:0] H_PAN_SILENCE     = 7'd46;
    localparam logic [6:0] H_R_PREROLL       = 7'd47;
    localparam logic [6:0] H_R_ALIGN         = 7'd48;
    localparam logic [6:0] H_R_START         = 7'd49;
    localparam logic [6:0] H_R_DWELL         = 7'd50;
    localparam logic [6:0] H_R_RESET         = 7'd51;
    localparam logic [6:0] H_R_ZERO          = 7'd52;
    localparam logic [6:0] H_SILENCE_6       = 7'd53;
    localparam logic [6:0] H_SHORT_PREROLL   = 7'd54;
    localparam logic [6:0] H_SHORT_ALIGN1    = 7'd55;
    localparam logic [6:0] H_SHORT_START1    = 7'd56;
    localparam logic [6:0] H_SHORT_PLAY1     = 7'd57;
    localparam logic [6:0] H_SHORT_ZERO1     = 7'd58;
    localparam logic [6:0] H_SHORT_SILENCE   = 7'd59;
    localparam logic [6:0] H_SHORT_ALIGN2    = 7'd60;
    localparam logic [6:0] H_SHORT_START2    = 7'd61;
    localparam logic [6:0] H_SHORT_PLAY2     = 7'd62;
    localparam logic [6:0] H_SHORT_ZERO2     = 7'd63;
    localparam logic [6:0] H_FINAL_STOP      = 7'd64;
    localparam logic [6:0] H_FINAL_SILENCE   = 7'd65;
    localparam logic [6:0] H_SSG_CFG         = 7'd66;

    localparam logic [3:0] B_IDLE          = 4'd0;
    localparam logic [3:0] B_CLEAR_SETUP   = 4'd1;
    localparam logic [3:0] B_CLEAR_SAMPLE  = 4'd2;
    localparam logic [3:0] B_ADDR_SETUP    = 4'd3;
    localparam logic [3:0] B_ADDR_CAPTURE  = 4'd4;
    localparam logic [3:0] B_DATA_CHECK    = 4'd5;
    localparam logic [3:0] B_DATA_SAMPLE   = 4'd6;
    localparam logic [3:0] B_DATA_CAPTURE  = 4'd7;
    localparam logic [3:0] B_ASSERT_SETUP  = 4'd8;
    localparam logic [3:0] B_ASSERT_SAMPLE = 4'd9;
    localparam logic [3:0] B_DONE_SETUP    = 4'd10;
    localparam logic [3:0] B_DONE_SAMPLE   = 4'd11;

    logic [6:0] high_state;
    logic [4:0] program_id;
    logic       program_active;
    logic       program_done;
    logic [3:0] bus_state;
    logic       txn_active;
    logic [16:0] current_word;
    logic [15:0] busy_watchdog;
    logic [31:0] sample_count;
    logic [31:0] sound_start_tick;
    logic [7:0]  zero_run_count;
    logic [31:0] natural_watchdog;
    logic        natural_armed;

    assign segment_state = high_state;

    wire zero_wait_state = high_state == H_FM_ZERO ||
                           high_state == H_SSG_ZERO ||
                           high_state == H_A0_ZERO ||
                           high_state == H_A6_ZERO ||
                           high_state == H_B_ZERO ||
                           high_state == H_L_ZERO ||
                           high_state == H_R_ZERO ||
                           high_state == H_SHORT_ZERO1 ||
                           high_state == H_SHORT_ZERO2;
    wire adpcmb_zero_wait = high_state == H_B_ZERO ||
                            high_state == H_L_ZERO ||
                            high_state == H_R_ZERO ||
                            high_state == H_SHORT_ZERO1 ||
                            high_state == H_SHORT_ZERO2;
    wire zero_sample_ok = audio_zero &&
                          (!adpcmb_zero_wait ||
                           (!adpcmb_request && !adpcmb_active));

    function automatic integer program_length(input logic [4:0] id);
        begin
            case (id)
                P_SILENCE:  program_length = 18;
                P_FM_CFG:   program_length = 32;
                P_FM_ON:    program_length = 1;
                P_FM_OFF:   program_length = 1;
                P_SSG_CFG:  program_length = 4;
                P_SSG_OFF:  program_length = 2;
                P_A0_CFG:   program_length = 11;
                P_A0_ON:    program_length = 1;
                P_A0_OFF:   program_length = 1;
                P_A6_CFG:   program_length = 31;
                P_A6_ON:    program_length = 1;
                P_A6_OFF:   program_length = 1;
                P_B_STEREO,
                P_B_LEFT,
                P_B_RIGHT,
                P_B_SHORT:  program_length = 10;
                P_B_START:  program_length = 1;
                P_B_RESET:  program_length = 2;
                default:    program_length = 0;
            endcase
        end
    endfunction

    function automatic [16:0] program_word(
        input logic [4:0] id,
        input logic [7:0] index
    );
        integer op_group;
        integer op_step;
        integer voice;
        integer voice_step;
        logic [7:0] op_offset;
        logic [7:0] op_data;
        logic [7:0] pan;
        logic [7:0] end_page;
        begin
            program_word = {1'b0, 8'h00, 8'h00};
            case (id)
                P_SILENCE: begin
                    case (index)
                        0: program_word={1'b0,8'h28,8'h00};
                        1: program_word={1'b0,8'h28,8'h01};
                        2: program_word={1'b0,8'h28,8'h02};
                        3: program_word={1'b0,8'h28,8'h04};
                        4: program_word={1'b0,8'h28,8'h05};
                        5: program_word={1'b0,8'h28,8'h06};
                        6: program_word={1'b0,8'h22,8'h00};
                        7: program_word={1'b0,8'h27,8'h00};
                        8: program_word={1'b0,8'h2b,8'h00};
                        9: program_word={1'b0,8'h08,8'h00};
                       10: program_word={1'b0,8'h09,8'h00};
                       11: program_word={1'b0,8'h0a,8'h00};
                       12: program_word={1'b0,8'h06,8'h00};
                       13: program_word={1'b0,8'h07,8'h3f};
                       14: program_word={1'b1,8'h00,8'hbf};
                       15: program_word={1'b0,8'h10,8'h01};
                       16: program_word={1'b0,8'h1c,8'h80};
                       17: program_word={1'b0,8'h10,8'h00};
                       default: ;
                    endcase
                end
                P_FM_CFG: begin
                    case (index)
                        0: program_word={1'b0,8'ha5,8'h22};
                        1: program_word={1'b0,8'ha1,8'h00};
                        2: program_word={1'b0,8'hb1,8'h07};
                        3: program_word={1'b0,8'hb5,8'hc0};
                        default: begin
                            op_group = (index - 4) / 7;
                            op_step = (index - 4) % 7;
                            case (op_group)
                                0: op_offset = 8'h00;
                                1: op_offset = 8'h08;
                                2: op_offset = 8'h04;
                                default: op_offset = 8'h0c;
                            endcase
                            case (op_step)
                                0: op_data = 8'h01;
                                1: op_data = op_group == 0 ? 8'h00 : 8'h7f;
                                2: op_data = 8'h1f;
                                3: op_data = 8'h00;
                                4: op_data = 8'h00;
                                5: op_data = 8'haf;
                                default: op_data = 8'h00;
                            endcase
                            case (op_step)
                                0: program_word={1'b0,8'h31+op_offset,op_data};
                                1: program_word={1'b0,8'h41+op_offset,op_data};
                                2: program_word={1'b0,8'h51+op_offset,op_data};
                                3: program_word={1'b0,8'h61+op_offset,op_data};
                                4: program_word={1'b0,8'h71+op_offset,op_data};
                                5: program_word={1'b0,8'h81+op_offset,op_data};
                                default: program_word={1'b0,8'h91+op_offset,op_data};
                            endcase
                        end
                    endcase
                end
                P_FM_ON:  program_word={1'b0,8'h28,8'h11};
                P_FM_OFF: program_word={1'b0,8'h28,8'h01};
                P_SSG_CFG: begin
                    case(index)
                        0: program_word={1'b0,8'h00,8'h20};
                        1: program_word={1'b0,8'h01,8'h00};
                        2: program_word={1'b0,8'h07,8'h3e};
                        default: program_word={1'b0,8'h08,8'h0f};
                    endcase
                end
                P_SSG_OFF: program_word = index == 0 ?
                    {1'b0,8'h08,8'h00} : {1'b0,8'h07,8'h3f};
                P_A0_CFG: begin
                    case(index)
                        0: program_word={1'b1,8'h10,8'h00};
                        1: program_word={1'b1,8'h18,8'h00};
                        2: program_word={1'b1,8'h20,8'h0f};
                        3: program_word={1'b1,8'h28,8'h00};
                        4: program_word={1'b1,8'h01,8'h3f};
                        5: program_word={1'b1,8'h08,8'hf5};
                        6: program_word={1'b1,8'h09,8'h00};
                        7: program_word={1'b1,8'h0a,8'h00};
                        8: program_word={1'b1,8'h0b,8'h00};
                        9: program_word={1'b1,8'h0c,8'h00};
                        default: program_word={1'b1,8'h0d,8'h00};
                    endcase
                end
                P_A0_ON:  program_word={1'b1,8'h00,8'h01};
                P_A0_OFF: program_word={1'b1,8'h00,8'h81};
                P_A6_CFG: begin
                    if (index == 0) program_word={1'b1,8'h01,8'h3f};
                    else begin
                        voice = (index - 1) / 5;
                        voice_step = (index - 1) % 5;
                        case (voice_step)
                            0: program_word={1'b1,8'h10+voice[7:0],voice[7:0]};
                            1: program_word={1'b1,8'h18+voice[7:0],8'h00};
                            2: program_word={1'b1,8'h20+voice[7:0],voice[7:0]+8'h0f};
                            3: program_word={1'b1,8'h28+voice[7:0],8'h00};
                            default: program_word={1'b1,8'h08+voice[7:0],8'hc0};
                        endcase
                    end
                end
                P_A6_ON:  program_word={1'b1,8'h00,8'h3f};
                P_A6_OFF: program_word={1'b1,8'h00,8'hbf};
                P_B_STEREO,
                P_B_LEFT,
                P_B_RIGHT,
                P_B_SHORT: begin
                    pan = id == P_B_LEFT ? 8'h80 :
                          id == P_B_RIGHT ? 8'h40 : 8'hc0;
                    end_page = id == P_B_SHORT ? 8'h20 : 8'h4f;
                    case(index)
                        0: program_word={1'b0,8'h10,8'h01};
                        1: program_word={1'b0,8'h10,8'h00};
                        2: program_word={1'b0,8'h11,pan};
                        3: program_word={1'b0,8'h12,8'h20};
                        4: program_word={1'b0,8'h13,8'h00};
                        5: program_word={1'b0,8'h14,end_page};
                        6: program_word={1'b0,8'h15,8'h00};
                        7: program_word={1'b0,8'h19,8'h00};
                        8: program_word={1'b0,8'h1a,8'h80};
                        default: program_word={1'b0,8'h1b,8'hff};
                    endcase
                end
                P_B_START: program_word={1'b0,8'h10,8'h80};
                P_B_RESET: program_word = index == 0 ?
                    {1'b0,8'h10,8'h01} : {1'b0,8'h10,8'h00};
                default: ;
            endcase
        end
    endfunction

    task automatic drive_idle;
        begin
            bus_addr <= 2'b00;
            bus_din <= 8'h00;
            bus_cs_n <= 1'b1;
            bus_wr_n <= 1'b1;
        end
    endtask

    task automatic drive_status;
        begin
            bus_addr <= 2'b00;
            bus_din <= 8'h00;
            bus_cs_n <= 1'b0;
            bus_wr_n <= 1'b1;
        end
    endtask

    task automatic start_program(input logic [4:0] id);
        begin
            program_id <= id;
            microcode_index <= 8'd0;
            program_active <= 1'b1;
        end
    endtask

    // The synthesizable bus-drive tasks below assign this process's outputs.
    // Use a plain clocked process so lint tools do not misclassify task-body
    // assignments as separate always_ff drivers.
    always @(posedge clk) begin
        program_done <= 1'b0;

        if (reset) begin
            bus_addr <= 2'b00;
            bus_din <= 8'h00;
            bus_cs_n <= 1'b1;
            bus_wr_n <= 1'b1;
            display_phase <= 4'd0;
            high_state <= H_BOOT_WAIT;
            startup_state <= 3'd0;
            audio_mute <= 1'b1;
            program_id <= P_SILENCE;
            program_active <= 1'b0;
            txn_active <= 1'b0;
            bus_state <= B_IDLE;
            microcode_index <= 8'd0;
            current_word <= 17'd0;
            busy_watchdog <= 16'd0;
            sample_count <= 32'd0;
            sample_tick_count <= 32'd0;
            sound_start_tick <= 32'd0;
            zero_run_count <= 8'd0;
            natural_watchdog <= 32'd0;
            natural_armed <= 1'b0;
            accepted_write_count <= 32'd0;
            busy_timeout <= 1'b0;
            write_while_busy <= 1'b0;
            zero_timeout <= 1'b0;
            phase_error <= 1'b0;
            sequence_restart_count <= 16'd0;
            measurement_active <= 1'b0;
            measurement_phase <= 4'd0;
            halted <= 1'b0;
        end else if (!halted) begin
            if (sample_tick)
                sample_tick_count <= sample_tick_count + 32'd1;
            if (sample_tick) begin
                if (zero_wait_state && zero_sample_ok &&
                    zero_run_count < ZERO_CONFIRM_SAMPLES)
                    zero_run_count <= zero_run_count + 8'd1;
                else if (!zero_wait_state || !zero_sample_ok)
                    zero_run_count <= 8'd0;
            end

            // Transaction engine.  Status is read through the public bus;
            // no internal busy net or fixed inter-write delay is used.
            case (bus_state)
                B_IDLE: begin
                    drive_idle();
                    if (program_active && !txn_active) begin
                        current_word <= program_word(program_id,
                                                     microcode_index);
                        txn_active <= 1'b1;
                        busy_watchdog <= 16'd0;
                        bus_state <= B_CLEAR_SETUP;
                    end
                end
                B_CLEAR_SETUP: begin
                    drive_status();
                    bus_state <= B_CLEAR_SAMPLE;
                end
                B_CLEAR_SAMPLE: begin
                    if (bus_dout[7] == 1'b0) begin
                        drive_idle();
                        busy_watchdog <= 16'd0;
                        bus_state <= B_ADDR_SETUP;
                    end else if (busy_watchdog == 16'hffff) begin
                        busy_timeout <= 1'b1;
                        halted <= 1'b1;
                    end else begin
                        busy_watchdog <= busy_watchdog + 16'd1;
                        drive_status();
                    end
                end
                B_ADDR_SETUP: begin
                    bus_addr <= {current_word[16],1'b0};
                    bus_din <= current_word[15:8];
                    bus_cs_n <= 1'b0;
                    bus_wr_n <= 1'b0;
                    bus_state <= B_ADDR_CAPTURE;
                end
                B_ADDR_CAPTURE: begin
                    drive_idle();
                    bus_state <= B_DATA_CHECK;
                end
                B_DATA_CHECK: begin
                    drive_status();
                    bus_state <= B_DATA_SAMPLE;
                end
                B_DATA_SAMPLE: begin
                    if (bus_dout[7] != 1'b0) begin
                        write_while_busy <= 1'b1;
                        halted <= 1'b1;
                        drive_idle();
                    end else begin
                        if (program_id == P_FM_ON ||
                            (program_id == P_SSG_CFG &&
                             microcode_index == 8'd3) ||
                            program_id == P_A0_ON ||
                            program_id == P_A6_ON ||
                            program_id == P_B_START)
                            audio_mute <= 1'b0;
                        bus_addr <= {current_word[16],1'b1};
                        bus_din <= current_word[7:0];
                        bus_cs_n <= 1'b0;
                        bus_wr_n <= 1'b0;
                        bus_state <= B_DATA_CAPTURE;
                    end
                end
                B_DATA_CAPTURE: begin
                    drive_idle();
                    accepted_write_count <= accepted_write_count + 32'd1;
                    if (program_id == P_FM_ON ||
                        (program_id == P_SSG_CFG &&
                         microcode_index == 8'd3) ||
                        program_id == P_A0_ON ||
                        program_id == P_A6_ON ||
                        program_id == P_B_START) begin
                        sound_start_tick <= sample_tick_count;
                        sample_count <= 32'd0;
                    end
                    if (program_id == P_A0_ON) begin
                        measurement_active <= 1'b1;
                        measurement_phase <= 4'd3;
                    end else if (program_id == P_A6_ON) begin
                        measurement_active <= 1'b1;
                        measurement_phase <= 4'd4;
                    end else if (program_id == P_B_START &&
                                 display_phase == 4'd5) begin
                        measurement_active <= 1'b1;
                        measurement_phase <= 4'd5;
                    end
                    busy_watchdog <= 16'd0;
                    bus_state <= B_ASSERT_SETUP;
                end
                B_ASSERT_SETUP: begin
                    drive_status();
                    bus_state <= B_ASSERT_SAMPLE;
                end
                B_ASSERT_SAMPLE: begin
                    if (bus_dout[7] == 1'b1) begin
                        busy_watchdog <= 16'd0;
                        drive_status();
                        bus_state <= B_DONE_SAMPLE;
                    end else if (busy_watchdog == 16'hffff) begin
                        busy_timeout <= 1'b1;
                        halted <= 1'b1;
                    end else begin
                        busy_watchdog <= busy_watchdog + 16'd1;
                        drive_status();
                    end
                end
                B_DONE_SETUP: begin
                    drive_status();
                    bus_state <= B_DONE_SAMPLE;
                end
                B_DONE_SAMPLE: begin
                    if (bus_dout[7] == 1'b0) begin
                        drive_idle();
                        txn_active <= 1'b0;
                        bus_state <= B_IDLE;
                        if (microcode_index + 1 >=
                            program_length(program_id)) begin
                            program_active <= 1'b0;
                            program_done <= 1'b1;
                        end else begin
                            microcode_index <= microcode_index + 8'd1;
                        end
                    end else if (busy_watchdog == 16'hffff) begin
                        busy_timeout <= 1'b1;
                        halted <= 1'b1;
                    end else begin
                        busy_watchdog <= busy_watchdog + 16'd1;
                        drive_status();
                    end
                end
                default: bus_state <= B_IDLE;
            endcase

            if (sample_contract_error) begin
                phase_error <= 1'b1;
                halted <= 1'b1;
                startup_state <= 3'd4;
                audio_mute <= 1'b1;
                measurement_active <= 1'b0;
                drive_idle();
            end else if (halted || busy_timeout || write_while_busy ||
                         zero_timeout || phase_error) begin
                halted <= 1'b1;
                startup_state <= 3'd4;
                audio_mute <= 1'b1;
                measurement_active <= 1'b0;
                drive_idle();
            end else begin
                if (sample_tick && sample_count == 32'hffff_ffff) begin
                    phase_error <= 1'b1;
                    halted <= 1'b1;
                end else case (high_state)
                    H_BOOT_WAIT: begin
                        display_phase <= 4'd0;
                        audio_mute <= 1'b1;
                        startup_state <= 3'd1;
                        if (core_ready && audio_zero &&
                            bus_dout[7] == 1'b0 && !program_active) begin
                            high_state <= H_BOOT_HOLD;
                            startup_state <= 3'd2;
                            sample_count <= 32'd0;
                        end
                    end
                    H_BOOT_HOLD: if (sample_tick) begin
                        if (!audio_zero) begin
                            phase_error <= 1'b1;
                            halted <= 1'b1;
                        end else if (sample_count + 1 >= BOOT_SAMPLES) begin
                            start_program(P_SILENCE);
                            high_state <= H_INITIAL_SILENCE;
                            sample_count <= 32'd0;
                        end else sample_count <= sample_count + 32'd1;
                    end
                    H_INITIAL_SILENCE: if (program_done) begin
                        display_phase <= 4'd1;
                        startup_state <= 3'd3;
                        start_program(P_FM_CFG);
                        high_state <= H_FM_PREROLL;
                        sample_count <= 32'd0;
                    end

                    H_FM_PREROLL: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1'b1; halted<=1'b1; end
                        else if (sample_count + 1 >= COLOR_PREROLL_SAMPLES) begin
                            if (program_active) begin phase_error<=1'b1; halted<=1'b1; end
                            else begin start_program(P_FM_ON); high_state<=H_FM_START; sample_count<=0; end
                        end else sample_count <= sample_count + 1;
                    end
                    H_FM_START: if (program_done) begin high_state<=H_FM_ATTACK; sample_count<=0; end
                    H_FM_ATTACK: if (sample_tick) begin
                        if (sample_count + 1 >= 4096) begin
                            high_state<=H_FM_MEASURE; sample_count<=0;
                            measurement_active<=1'b1; measurement_phase<=4'd1;
                        end else sample_count<=sample_count+1;
                    end
                    H_FM_MEASURE: if (sample_tick) begin
                        if (sample_count + 1 >= 4096) begin
                            measurement_active<=1'b0; high_state<=H_FM_HOLD; sample_count<=0;
                        end else sample_count<=sample_count+1;
                    end
                    H_FM_HOLD: if (sample_tick &&
                        sample_tick_count + 1 - sound_start_tick >= SOUND_DWELL_SAMPLES) begin
                        start_program(P_FM_OFF); high_state<=H_FM_OFF;
                    end
                    H_FM_OFF: if (program_done) begin high_state<=H_FM_ZERO; sample_count<=0; end
                    H_FM_ZERO: if (sample_tick) begin
                        if (zero_sample_ok && zero_run_count+1>=ZERO_CONFIRM_SAMPLES) begin display_phase<=0; audio_mute<=1; high_state<=H_SILENCE_1; sample_count<=0; end
                        else if (sample_count+1>=ZERO_TIMEOUT_SAMPLES) begin zero_timeout<=1; halted<=1; end
                        else sample_count<=sample_count+1;
                    end
                    H_SILENCE_1: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=INTER_SILENCE_SAMPLES) begin
                            display_phase<=2; high_state<=H_SSG_PREROLL; sample_count<=0;
                        end else sample_count<=sample_count+1;
                    end

                    H_SSG_PREROLL: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=COLOR_PREROLL_SAMPLES) begin
                            if (program_active) begin phase_error<=1; halted<=1; end
                            else begin high_state<=H_SSG_ALIGN; sample_count<=0; end
                        end else sample_count<=sample_count+1;
                    end
                    // JT49's divider is free-running.  Preserve the Phase 2A
                    // write/measurement alignment while still completing the
                    // full color-only pre-roll before the first SSG write.
                    H_SSG_ALIGN: if (!program_active &&
                                     chip_cycle_mod432 == 9'd428 &&
                                     sample_tick_count[6:0] == 7'd53) begin
                        start_program(P_SSG_CFG);
                        high_state<=H_SSG_CFG;
                    end
                    H_SSG_CFG: if (program_done) begin high_state<=H_SSG_ATTACK; sample_count<=0; end
                    H_SSG_ATTACK: if (sample_tick) begin
                        if (sample_count+1>=263) begin high_state<=H_SSG_MEASURE; sample_count<=0; measurement_active<=1; measurement_phase<=2; end
                        else sample_count<=sample_count+1;
                    end
                    H_SSG_MEASURE: if (sample_tick) begin
                        if (sample_count+1>=4096) begin measurement_active<=0; high_state<=H_SSG_HOLD; sample_count<=0; end
                        else sample_count<=sample_count+1;
                    end
                    H_SSG_HOLD: if (sample_tick &&
                        sample_tick_count + 1 - sound_start_tick >= SOUND_DWELL_SAMPLES) begin
                        start_program(P_SSG_OFF); high_state<=H_SSG_OFF;
                    end
                    H_SSG_OFF: if (program_done) begin high_state<=H_SSG_ZERO; sample_count<=0; end
                    H_SSG_ZERO: if (sample_tick) begin
                        if (zero_sample_ok && zero_run_count+1>=ZERO_CONFIRM_SAMPLES) begin display_phase<=0; audio_mute<=1; high_state<=H_SILENCE_2; sample_count<=0; end
                        else if (sample_count+1>=ZERO_TIMEOUT_SAMPLES) begin zero_timeout<=1; halted<=1; end
                        else sample_count<=sample_count+1;
                    end
                    H_SILENCE_2: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=INTER_SILENCE_SAMPLES) begin
                            display_phase<=3; start_program(P_A0_CFG); high_state<=H_A0_PREROLL; sample_count<=0;
                        end else sample_count<=sample_count+1;
                    end

                    H_A0_PREROLL: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=COLOR_PREROLL_SAMPLES) begin
                            if (program_active) begin phase_error<=1; halted<=1; end
                            else begin high_state<=H_A0_ALIGN; sample_count<=0; end
                        end else sample_count<=sample_count+1;
                    end
                    H_A0_ALIGN: if (!program_active && chip_cycle_mod432==9'd230) begin start_program(P_A0_ON); high_state<=H_A0_START; end
                    H_A0_START: if (program_done) begin high_state<=H_A0_DWELL; sample_count<=0; end
                    H_A0_DWELL: if (sample_tick) begin
                        if (measurement_active && sample_count+1>=4096) measurement_active<=0;
                        if (sample_tick_count+1-sound_start_tick>=SOUND_DWELL_SAMPLES) begin measurement_active<=0; start_program(P_A0_OFF); high_state<=H_A0_OFF; end
                        else sample_count<=sample_count+1;
                    end
                    H_A0_OFF: if (program_done) begin high_state<=H_A0_ZERO; sample_count<=0; end
                    H_A0_ZERO: if (sample_tick) begin
                        if (zero_sample_ok && zero_run_count+1>=ZERO_CONFIRM_SAMPLES) begin display_phase<=0; audio_mute<=1; high_state<=H_SILENCE_3; sample_count<=0; end
                        else if (sample_count+1>=ZERO_TIMEOUT_SAMPLES) begin zero_timeout<=1; halted<=1; end
                        else sample_count<=sample_count+1;
                    end
                    H_SILENCE_3: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=INTER_SILENCE_SAMPLES) begin
                            display_phase<=4; start_program(P_A6_CFG); high_state<=H_A6_PREROLL; sample_count<=0;
                        end else sample_count<=sample_count+1;
                    end

                    H_A6_PREROLL: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=COLOR_PREROLL_SAMPLES) begin
                            if (program_active) begin phase_error<=1; halted<=1; end
                            else begin high_state<=H_A6_ALIGN; sample_count<=0; end
                        end else sample_count<=sample_count+1;
                    end
                    H_A6_ALIGN: if (!program_active && chip_cycle_mod432==9'd402) begin start_program(P_A6_ON); high_state<=H_A6_START; end
                    H_A6_START: if (program_done) begin high_state<=H_A6_DWELL; sample_count<=0; end
                    H_A6_DWELL: if (sample_tick) begin
                        if (measurement_active && sample_count+1>=8192) measurement_active<=0;
                        if (sample_tick_count+1-sound_start_tick>=SOUND_DWELL_SAMPLES) begin measurement_active<=0; start_program(P_A6_OFF); high_state<=H_A6_OFF; end
                        else sample_count<=sample_count+1;
                    end
                    H_A6_OFF: if (program_done) begin high_state<=H_A6_ZERO; sample_count<=0; end
                    H_A6_ZERO: if (sample_tick) begin
                        if (zero_sample_ok && zero_run_count+1>=ZERO_CONFIRM_SAMPLES) begin display_phase<=0; audio_mute<=1; high_state<=H_SILENCE_4; sample_count<=0; end
                        else if (sample_count+1>=ZERO_TIMEOUT_SAMPLES) begin zero_timeout<=1; halted<=1; end
                        else sample_count<=sample_count+1;
                    end
                    H_SILENCE_4: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=INTER_SILENCE_SAMPLES) begin
                            display_phase<=5; start_program(P_B_STEREO); high_state<=H_B_PREROLL; sample_count<=0;
                        end else sample_count<=sample_count+1;
                    end

                    H_B_PREROLL: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=COLOR_PREROLL_SAMPLES) begin
                            if (program_active) begin phase_error<=1; halted<=1; end
                            else begin high_state<=H_B_ALIGN; sample_count<=0; end
                        end else sample_count<=sample_count+1;
                    end
                    H_B_ALIGN: if (!program_active && chip_cycle_mod432==9'd416) begin start_program(P_B_START); high_state<=H_B_START; end
                    H_B_START: if (program_done) begin high_state<=H_B_DWELL; sample_count<=0; end
                    H_B_DWELL: if (sample_tick) begin
                        if (!adpcmb_active) begin phase_error<=1; halted<=1; end
                        else begin
                            if (measurement_active && sample_count+1>=4097) measurement_active<=0;
                            if (sample_tick_count+1-sound_start_tick>=SOUND_DWELL_SAMPLES) begin measurement_active<=0; start_program(P_B_RESET); high_state<=H_B_RESET; end
                            else sample_count<=sample_count+1;
                        end
                    end
                    H_B_RESET: if (program_done) begin high_state<=H_B_ZERO; sample_count<=0; end
                    H_B_ZERO: if (sample_tick) begin
                        if (zero_sample_ok && zero_run_count+1>=ZERO_CONFIRM_SAMPLES) begin display_phase<=0; audio_mute<=1; high_state<=H_SILENCE_5; sample_count<=0; end
                        else if (sample_count+1>=ZERO_TIMEOUT_SAMPLES) begin zero_timeout<=1; halted<=1; end
                        else sample_count<=sample_count+1;
                    end
                    H_SILENCE_5: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=INTER_SILENCE_SAMPLES) begin
                            display_phase<=6; start_program(P_B_LEFT); high_state<=H_L_PREROLL; sample_count<=0;
                        end else sample_count<=sample_count+1;
                    end

                    H_L_PREROLL: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=COLOR_PREROLL_SAMPLES) begin
                            if (program_active) begin phase_error<=1; halted<=1; end
                            else begin high_state<=H_L_ALIGN; sample_count<=0; end
                        end else sample_count<=sample_count+1;
                    end
                    H_L_ALIGN: if (!program_active && chip_cycle_mod432==9'd416) begin start_program(P_B_START); high_state<=H_L_START; end
                    H_L_START: if (program_done) begin high_state<=H_L_DWELL; sample_count<=0; end
                    H_L_DWELL: if (sample_tick) begin
                        if (!adpcmb_active) begin phase_error<=1; halted<=1; end
                        else if (sample_tick_count+1-sound_start_tick>=PAN_DWELL_SAMPLES) begin start_program(P_B_RESET); high_state<=H_L_RESET; end
                        else sample_count<=sample_count+1;
                    end
                    H_L_RESET: if (program_done) begin high_state<=H_L_ZERO; sample_count<=0; end
                    H_L_ZERO: if (sample_tick) begin
                        if (zero_sample_ok && zero_run_count+1>=ZERO_CONFIRM_SAMPLES) begin display_phase<=0; audio_mute<=1; high_state<=H_PAN_SILENCE; sample_count<=0; end
                        else if (sample_count+1>=ZERO_TIMEOUT_SAMPLES) begin zero_timeout<=1; halted<=1; end
                        else sample_count<=sample_count+1;
                    end
                    H_PAN_SILENCE: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=PAN_INTER_SAMPLES) begin
                            display_phase<=6; start_program(P_B_RIGHT); high_state<=H_R_PREROLL; sample_count<=0;
                        end else sample_count<=sample_count+1;
                    end
                    H_R_PREROLL: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=COLOR_PREROLL_SAMPLES) begin
                            if (program_active) begin phase_error<=1; halted<=1; end
                            else begin high_state<=H_R_ALIGN; sample_count<=0; end
                        end else sample_count<=sample_count+1;
                    end
                    H_R_ALIGN: if (!program_active && chip_cycle_mod432==9'd416) begin start_program(P_B_START); high_state<=H_R_START; end
                    H_R_START: if (program_done) begin high_state<=H_R_DWELL; sample_count<=0; end
                    H_R_DWELL: if (sample_tick) begin
                        if (!adpcmb_active) begin phase_error<=1; halted<=1; end
                        else if (sample_tick_count+1-sound_start_tick>=PAN_DWELL_SAMPLES) begin start_program(P_B_RESET); high_state<=H_R_RESET; end
                        else sample_count<=sample_count+1;
                    end
                    H_R_RESET: if (program_done) begin high_state<=H_R_ZERO; sample_count<=0; end
                    H_R_ZERO: if (sample_tick) begin
                        if (zero_sample_ok && zero_run_count+1>=ZERO_CONFIRM_SAMPLES) begin display_phase<=0; audio_mute<=1; high_state<=H_SILENCE_6; sample_count<=0; end
                        else if (sample_count+1>=ZERO_TIMEOUT_SAMPLES) begin zero_timeout<=1; halted<=1; end
                        else sample_count<=sample_count+1;
                    end
                    H_SILENCE_6: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=INTER_SILENCE_SAMPLES) begin
                            display_phase<=7; start_program(P_B_SHORT); high_state<=H_SHORT_PREROLL; sample_count<=0;
                        end else sample_count<=sample_count+1;
                    end

                    H_SHORT_PREROLL: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=COLOR_PREROLL_SAMPLES) begin
                            if (program_active) begin phase_error<=1; halted<=1; end
                            else begin high_state<=H_SHORT_ALIGN1; sample_count<=0; end
                        end else sample_count<=sample_count+1;
                    end
                    H_SHORT_ALIGN1: if (!program_active && chip_cycle_mod432==9'd416) begin start_program(P_B_START); high_state<=H_SHORT_START1; natural_watchdog<=0; natural_armed<=0; end
                    H_SHORT_START1: if (program_done) begin high_state<=H_SHORT_PLAY1; natural_armed<=1; end
                    H_SHORT_PLAY1: if (natural_armed && adpcmb_eos) begin high_state<=H_SHORT_ZERO1; sample_count<=0; natural_armed<=0; end
                        else if (sample_tick) begin natural_watchdog<=natural_watchdog+1; if(natural_watchdog>4096) begin busy_timeout<=1; halted<=1; end end
                    H_SHORT_ZERO1: if (sample_tick) begin
                        if (zero_sample_ok && zero_run_count+1>=ZERO_CONFIRM_SAMPLES) begin audio_mute<=1; high_state<=H_SHORT_SILENCE; sample_count<=0; end
                        else if (sample_count+1>=ZERO_TIMEOUT_SAMPLES) begin zero_timeout<=1; halted<=1; end
                        else sample_count<=sample_count+1;
                    end
                    H_SHORT_SILENCE: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=NATURAL_SILENCE_SAMPLES) begin high_state<=H_SHORT_ALIGN2; sample_count<=0; end
                        else sample_count<=sample_count+1;
                    end
                    H_SHORT_ALIGN2: if (!program_active && chip_cycle_mod432==9'd416) begin start_program(P_B_START); high_state<=H_SHORT_START2; natural_watchdog<=0; natural_armed<=0; end
                    H_SHORT_START2: if (program_done) begin high_state<=H_SHORT_PLAY2; natural_armed<=1; end
                    H_SHORT_PLAY2: if (natural_armed && adpcmb_eos) begin high_state<=H_SHORT_ZERO2; sample_count<=0; natural_armed<=0; end
                        else if (sample_tick) begin natural_watchdog<=natural_watchdog+1; if(natural_watchdog>4096) begin busy_timeout<=1; halted<=1; end end
                    H_SHORT_ZERO2: if (sample_tick) begin
                        if (zero_sample_ok && zero_run_count+1>=ZERO_CONFIRM_SAMPLES) begin
                            display_phase<=0; audio_mute<=1; start_program(P_SILENCE); high_state<=H_FINAL_STOP; sample_count<=0;
                        end else if (sample_count+1>=ZERO_TIMEOUT_SAMPLES) begin zero_timeout<=1; halted<=1; end
                        else sample_count<=sample_count+1;
                    end
                    H_FINAL_STOP: if (program_done) begin high_state<=H_FINAL_SILENCE; sample_count<=0; end
                    H_FINAL_SILENCE: if (sample_tick) begin
                        if (!audio_zero) begin phase_error<=1; halted<=1; end
                        else if (sample_count+1>=FINAL_SILENCE_SAMPLES) begin
                            sequence_restart_count<=sequence_restart_count+1;
                            display_phase<=1; start_program(P_FM_CFG); high_state<=H_FM_PREROLL; sample_count<=0;
                        end else sample_count<=sample_count+1;
                    end
                    default: begin phase_error<=1; halted<=1; end
                endcase
            end
        end else begin
            drive_idle();
            measurement_active <= 1'b0;
        end
    end
endmodule

// pixel_gen.v : generates RGB pixel stream for VGA output based on FSM state and game data

`timescale 1ns / 1ps

module pixel_gen (
    input  wire        clk,
    input  wire        reset,
    input  wire        video_on,
    input  wire [9:0]  hcount,
    input  wire [9:0]  vcount,

    // FSM state (one-hot)
    input  wire        st_idle,
    input  wire        st_show,
    input  wire        st_wait,
    input  wire        st_correct,
    input  wire        st_incorrect,
    input  wire        st_score,

    // game data
    input  wire [1:0]  cur_word,        // 0=RED 1=GREEN 2=BLUE 3=YELLOW
    input  wire [1:0]  cur_color,
    input  wire [4:0]  round_num,       // 0..29 (adaptive) or 0..19 (classic)
    input  wire [15:0] score_val,
    input  wire [15:0] react_time_ms,
    input  wire        results_ready,

    // per-session stats and adaptive mode
    input  wire [15:0] best_rt,         // sentinel 16'hFFFF if no data
    input  wire [15:0] worst_rt,
    input  wire [15:0] avg_rt,
    input  wire [15:0] cur_timeout_ms,
    input  wire [15:0] min_timeout_ms,
    input  wire        adaptive_mode,

    output reg  [11:0] rgb              // 12-bit color out
);

    // Color palette 
    localparam [11:0] C_BLACK  = 12'h000;
    localparam [11:0] C_WHITE  = 12'hFFF;
    localparam [11:0] C_RED    = 12'hF00;
    localparam [11:0] C_GREEN  = 12'h2C5;
    localparam [11:0] C_BLUE   = 12'h35F;
    localparam [11:0] C_YELLOW = 12'hFC0;
    localparam [11:0] C_GREY   = 12'h888;

    function [11:0] color_of;
        input [1:0] c;
        begin
            case (c)
                2'd0: color_of = C_RED;
                2'd1: color_of = C_GREEN;
                2'd2: color_of = C_BLUE;
                2'd3: color_of = C_YELLOW;
                default: color_of = C_WHITE;
            endcase
        end
    endfunction

    //  font ROM access 
    reg  [5:0] rom_char;
    reg  [3:0] rom_row;
    wire [9:0] rom_addr = {rom_char, rom_row};
    wire [7:0] rom_data;
    font_rom u_font (
        .clk  (clk),
        .addr (rom_addr),
        .data (rom_data)
    );

    reg [2:0]  col_d1;     // which of the 8 glyph columns
    reg [11:0] fg_col_d1;  // foreground color at this pixel
    reg [11:0] bg_col_d1;  // background color at this pixel
    reg        in_glyph_d1;

    // default values for outputs 
    reg [5:0]  target_char;
    reg [3:0]  target_row;
    reg [2:0]  target_col;
    reg [11:0] target_fg;
    reg [11:0] target_bg;
    reg        target_in_glyph;

    // letter codes (6-bit, == ASCII & 0x3F)
    localparam [5:0] CH_SPACE = 6'h20;
    localparam [5:0] CH_SLASH = 6'h2F;
    localparam [5:0] CH_COLON = 6'h3A;
    localparam [5:0] CH_A = 6'h01, CH_B = 6'h02, CH_C = 6'h03, CH_D = 6'h04;
    localparam [5:0] CH_E = 6'h05, CH_F = 6'h06, CH_G = 6'h07, CH_H = 6'h08;
    localparam [5:0] CH_I = 6'h09, CH_J = 6'h0A, CH_K = 6'h0B, CH_L = 6'h0C;
    localparam [5:0] CH_M = 6'h0D, CH_N = 6'h0E, CH_O = 6'h0F, CH_P = 6'h10;
    localparam [5:0] CH_Q = 6'h11, CH_R = 6'h12, CH_S = 6'h13, CH_T = 6'h14;
    localparam [5:0] CH_U = 6'h15, CH_V = 6'h16, CH_W = 6'h17, CH_X = 6'h18;
    localparam [5:0] CH_Y = 6'h19, CH_Z = 6'h1A;
    localparam [5:0] CH_0 = 6'h30, CH_1 = 6'h31, CH_2 = 6'h32, CH_3 = 6'h33;
    localparam [5:0] CH_4 = 6'h34, CH_5 = 6'h35, CH_6 = 6'h36, CH_7 = 6'h37;
    localparam [5:0] CH_8 = 6'h38, CH_9 = 6'h39;
    localparam [5:0] CH_CHECK = 6'h3E;
    localparam [5:0] CH_XMARK = 6'h3F;

    // helper that converts a 4-bit BCD value to its character code
    function [5:0] bcd_char;
        input [3:0] d;
        begin
            bcd_char = {2'b11, d};   // 0x30 | d  -> 6'h30..6'h39 -> '0'..'9'
        end
    endfunction

 

    // capture relevant game data
    reg [15:0] score_q,  react_q,  avg_q,  best_q,  worst_q,  ctmo_q,  mtmo_q;

    always @(posedge clk) begin
        if (reset) begin
            score_q  <= 16'd0;
            react_q  <= 16'd0;
            avg_q    <= 16'd0;
            best_q   <= 16'd0;
            worst_q  <= 16'd0;
            ctmo_q   <= 16'd0;
            mtmo_q   <= 16'd0;
        end else begin
            score_q  <= score_val;
            react_q  <= react_time_ms;
            avg_q    <= avg_rt;
            best_q   <= (best_rt == 16'hFFFF) ? 16'd0 : best_rt;
            worst_q  <= worst_rt;
            ctmo_q   <= cur_timeout_ms;
            mtmo_q   <= min_timeout_ms;
        end
    end

    reg [3:0] sc_d3, sc_d2, sc_d1, sc_d0;
    reg [3:0] rt_d3, rt_d2, rt_d1, rt_d0;
    reg [3:0] av_d3, av_d2, av_d1, av_d0;
    reg [3:0] be_d3, be_d2, be_d1, be_d0;
    reg [3:0] wo_d3, wo_d2, wo_d1, wo_d0;
    reg [3:0] ct_d3, ct_d2, ct_d1, ct_d0;
    reg [3:0] mt_d3, mt_d2, mt_d1, mt_d0;

    always @(posedge clk) begin
        sc_d3 <= (score_q/1000)%10;  sc_d2 <= (score_q/100)%10;
        sc_d1 <= (score_q/10)%10;    sc_d0 <=  score_q%10;
        rt_d3 <= (react_q/1000)%10;  rt_d2 <= (react_q/100)%10;
        rt_d1 <= (react_q/10)%10;    rt_d0 <=  react_q%10;
        av_d3 <= (avg_q/1000)%10;    av_d2 <= (avg_q/100)%10;
        av_d1 <= (avg_q/10)%10;      av_d0 <=  avg_q%10;
        be_d3 <= (best_q/1000)%10;   be_d2 <= (best_q/100)%10;
        be_d1 <= (best_q/10)%10;     be_d0 <=  best_q%10;
        wo_d3 <= (worst_q/1000)%10;  wo_d2 <= (worst_q/100)%10;
        wo_d1 <= (worst_q/10)%10;    wo_d0 <=  worst_q%10;
        ct_d3 <= (ctmo_q/1000)%10;   ct_d2 <= (ctmo_q/100)%10;
        ct_d1 <= (ctmo_q/10)%10;     ct_d0 <=  ctmo_q%10;
        mt_d3 <= (mtmo_q/1000)%10;   mt_d2 <= (mtmo_q/100)%10;
        mt_d1 <= (mtmo_q/10)%10;     mt_d0 <=  mtmo_q%10;
    end

    // round_num+1 BCD: small enough to leave combinational
    wire [5:0] rn_p1   = {1'b0, round_num} + 6'd1;     // 1..30
    wire [3:0] rn_d1   = (rn_p1/10)%10;
    wire [3:0] rn_d0   =  rn_p1%10;

    // word-text helper
    function [5:0] word_letter;
        input [1:0] w;
        input [2:0] idx;     // 0..5
        begin
            word_letter = CH_SPACE;
            case (w)
                2'd0: case (idx)            // "RED"
                    3'd0: word_letter = CH_R;
                    3'd1: word_letter = CH_E;
                    3'd2: word_letter = CH_D;
                    default: word_letter = CH_SPACE;
                endcase
                2'd1: case (idx)            // "GREEN"
                    3'd0: word_letter = CH_G;
                    3'd1: word_letter = CH_R;
                    3'd2: word_letter = CH_E;
                    3'd3: word_letter = CH_E;
                    3'd4: word_letter = CH_N;
                    default: word_letter = CH_SPACE;
                endcase
                2'd2: case (idx)            // "BLUE"
                    3'd0: word_letter = CH_B;
                    3'd1: word_letter = CH_L;
                    3'd2: word_letter = CH_U;
                    3'd3: word_letter = CH_E;
                    default: word_letter = CH_SPACE;
                endcase
                2'd3: case (idx)            // "YELLOW"
                    3'd0: word_letter = CH_Y;
                    3'd1: word_letter = CH_E;
                    3'd2: word_letter = CH_L;
                    3'd3: word_letter = CH_L;
                    3'd4: word_letter = CH_O;
                    3'd5: word_letter = CH_W;
                    default: word_letter = CH_SPACE;
                endcase
            endcase
        end
    endfunction

    // word lengths for centering
    function [3:0] word_len;
        input [1:0] w;
        begin
            case (w)
                2'd0: word_len = 4'd3;     // RED
                2'd1: word_len = 4'd5;     // GREEN
                2'd2: word_len = 4'd4;     // BLUE
                2'd3: word_len = 4'd6;     // YELLOW
                default: word_len = 4'd0;
            endcase
        end
    endfunction

    //MAIN COMBINATIONAL BLOCK

    // local pixel coords
    wire [9:0] px = hcount;
    wire [9:0] py = vcount;

    // big rendering (scale 4): 32x64 per character
    reg [9:0]  big_ox;
    reg [9:0]  big_oy;
    reg [4:0]  big_nchars;
    reg [11:0] big_color;
    reg        big_active;

    //  small string (scale 2): 16x32 per character
    reg [9:0]  sm_ox, sm_oy;
    reg [4:0]  sm_nchars;
    reg [11:0] sm_color;
    reg        sm_active;

    // per-cell character lookups
    reg [5:0] big_char_lut;
    reg [5:0] sm_char_lut;

    // index of the cell + col/row within cell
    reg [4:0] big_cell;
    reg [4:0] big_col_in_cell;   // 0..31
    reg [5:0] big_row_in_cell;   // 0..63
    reg [4:0] sm_cell;
    reg [3:0] sm_col_in_cell;    // 0..15
    reg [4:0] sm_row_in_cell;    // 0..31

    reg in_big, in_sm;

    //compute
    always @(*) begin
        in_big = 1'b0;
        big_cell        = 5'd0;
        big_col_in_cell = 5'd0;
        big_row_in_cell = 6'd0;
        if (big_active) begin
            if ((px >= big_ox) && (py >= big_oy) &&
                (py <  big_oy + 64)) begin
                if (px < big_ox + (big_nchars * 32)) begin
                    in_big          = 1'b1;
                    big_cell        = (px - big_ox) >> 5;     // /32
                    big_col_in_cell = (px - big_ox) & 5'h1F;  // %32
                    big_row_in_cell = (py - big_oy);
                end
            end
        end
    end

    always @(*) begin
        in_sm = 1'b0;
        sm_cell        = 5'd0;
        sm_col_in_cell = 4'd0;
        sm_row_in_cell = 5'd0;
        if (sm_active) begin
            if ((px >= sm_ox) && (py >= sm_oy) &&
                (py <  sm_oy + 32)) begin
                if (px < sm_ox + (sm_nchars * 16)) begin
                    in_sm          = 1'b1;
                    sm_cell        = (px - sm_ox) >> 4;     // /16
                    sm_col_in_cell = (px - sm_ox) & 4'hF;   // %16
                    sm_row_in_cell = (py - sm_oy);
                end
            end
        end
    end

    //  per-state screen layout 

    always @(*) begin
        // defaults: nothing
        big_active   = 1'b0;
        big_ox       = 10'd0;
        big_oy       = 10'd0;
        big_nchars   = 5'd0;
        big_color    = C_WHITE;
        big_char_lut = CH_SPACE;

        sm_active    = 1'b0;
        sm_ox        = 10'd0;
        sm_oy        = 10'd0;
        sm_nchars    = 5'd0;
        sm_color     = C_GREY;
        sm_char_lut  = CH_SPACE;

        //IDLE: start screen, then results screen
        if (st_idle) begin
            if (results_ready) begin
                //  RESULTS SCREEN 
                // BIG "RESULTS" header (7 chars)
                big_active = 1'b1;
                big_nchars = 5'd7;
                big_ox     = 10'd320 - (7*32)/2;   // 320-112 = 208
                big_oy     = 10'd60;
                big_color  = C_YELLOW;
                case (big_cell)
                    5'd0: big_char_lut = CH_R;
                    5'd1: big_char_lut = CH_E;
                    5'd2: big_char_lut = CH_S;
                    5'd3: big_char_lut = CH_U;
                    5'd4: big_char_lut = CH_L;
                    5'd5: big_char_lut = CH_T;
                    5'd6: big_char_lut = CH_S;
                    default: big_char_lut = CH_SPACE;
                endcase

                //  stats lines

                // Line 1 @ y=160:  "SCORE: NN/20"  (classic) or "TRIALS: NN" (adaptive)
                if (py >= 10'd160 && py < 10'd192) begin
                    sm_active = 1'b1;
                    sm_oy     = 10'd160;
                    sm_color  = C_WHITE;
                    if (adaptive_mode) begin
                        // "TRIALS: NN" - 10 chars
                        sm_nchars = 5'd10;
                        sm_ox     = 10'd320 - (10*16)/2;   // 240
                        case (sm_cell)
                            5'd0: sm_char_lut = CH_T;
                            5'd1: sm_char_lut = CH_R;
                            5'd2: sm_char_lut = CH_I;
                            5'd3: sm_char_lut = CH_A;
                            5'd4: sm_char_lut = CH_L;
                            5'd5: sm_char_lut = CH_S;
                            5'd6: sm_char_lut = CH_COLON;
                            5'd7: sm_char_lut = CH_SPACE;
                            5'd8: sm_char_lut = bcd_char(sc_d1);
                            5'd9: sm_char_lut = bcd_char(sc_d0);
                            default: sm_char_lut = CH_SPACE;
                        endcase
                    end else begin
                        // "SCORE: NN/20" - 12 chars
                        sm_nchars = 5'd12;
                        sm_ox     = 10'd320 - (12*16)/2;   // 224
                        case (sm_cell)
                            5'd0:  sm_char_lut = CH_S;
                            5'd1:  sm_char_lut = CH_C;
                            5'd2:  sm_char_lut = CH_O;
                            5'd3:  sm_char_lut = CH_R;
                            5'd4:  sm_char_lut = CH_E;
                            5'd5:  sm_char_lut = CH_COLON;
                            5'd6:  sm_char_lut = CH_SPACE;
                            5'd7:  sm_char_lut = bcd_char(sc_d1);
                            5'd8:  sm_char_lut = bcd_char(sc_d0);
                            5'd9:  sm_char_lut = CH_SLASH;
                            5'd10: sm_char_lut = CH_2;
                            5'd11: sm_char_lut = CH_0;
                            default: sm_char_lut = CH_SPACE;
                        endcase
                    end
                end

                // Line 2 @ y=200:  "AVG TIME: NNNNMS"  (16 chars)
                else if (py >= 10'd200 && py < 10'd232) begin
                    sm_active = 1'b1;
                    sm_nchars = 5'd16;
                    sm_oy     = 10'd200;
                    sm_ox     = 10'd320 - (16*16)/2;       // 192
                    sm_color  = C_WHITE;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_A;
                        5'd1:  sm_char_lut = CH_V;
                        5'd2:  sm_char_lut = CH_G;
                        5'd3:  sm_char_lut = CH_SPACE;
                        5'd4:  sm_char_lut = CH_T;
                        5'd5:  sm_char_lut = CH_I;
                        5'd6:  sm_char_lut = CH_M;
                        5'd7:  sm_char_lut = CH_E;
                        5'd8:  sm_char_lut = CH_COLON;
                        5'd9:  sm_char_lut = CH_SPACE;
                        5'd10: sm_char_lut = bcd_char(av_d3);
                        5'd11: sm_char_lut = bcd_char(av_d2);
                        5'd12: sm_char_lut = bcd_char(av_d1);
                        5'd13: sm_char_lut = bcd_char(av_d0);
                        5'd14: sm_char_lut = CH_M;
                        5'd15: sm_char_lut = CH_S;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end

                // Line 3 @ y=240:  "BEST TIME: NNNNMS"  (17 chars)
                else if (py >= 10'd240 && py < 10'd272) begin
                    sm_active = 1'b1;
                    sm_nchars = 5'd17;
                    sm_oy     = 10'd240;
                    sm_ox     = 10'd320 - (17*16)/2;       // 184
                    sm_color  = C_GREEN;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_B;
                        5'd1:  sm_char_lut = CH_E;
                        5'd2:  sm_char_lut = CH_S;
                        5'd3:  sm_char_lut = CH_T;
                        5'd4:  sm_char_lut = CH_SPACE;
                        5'd5:  sm_char_lut = CH_T;
                        5'd6:  sm_char_lut = CH_I;
                        5'd7:  sm_char_lut = CH_M;
                        5'd8:  sm_char_lut = CH_E;
                        5'd9:  sm_char_lut = CH_COLON;
                        5'd10: sm_char_lut = CH_SPACE;
                        5'd11: sm_char_lut = bcd_char(be_d3);
                        5'd12: sm_char_lut = bcd_char(be_d2);
                        5'd13: sm_char_lut = bcd_char(be_d1);
                        5'd14: sm_char_lut = bcd_char(be_d0);
                        5'd15: sm_char_lut = CH_M;
                        5'd16: sm_char_lut = CH_S;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end

                // Line 4 @ y=280:  "WORST TIME: NNNNMS"  (18 chars)
                else if (py >= 10'd280 && py < 10'd312) begin
                    sm_active = 1'b1;
                    sm_nchars = 5'd18;
                    sm_oy     = 10'd280;
                    sm_ox     = 10'd320 - (18*16)/2;       // 176
                    sm_color  = C_RED;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_W;
                        5'd1:  sm_char_lut = CH_O;
                        5'd2:  sm_char_lut = CH_R;
                        5'd3:  sm_char_lut = CH_S;
                        5'd4:  sm_char_lut = CH_T;
                        5'd5:  sm_char_lut = CH_SPACE;
                        5'd6:  sm_char_lut = CH_T;
                        5'd7:  sm_char_lut = CH_I;
                        5'd8:  sm_char_lut = CH_M;
                        5'd9:  sm_char_lut = CH_E;
                        5'd10: sm_char_lut = CH_COLON;
                        5'd11: sm_char_lut = CH_SPACE;
                        5'd12: sm_char_lut = bcd_char(wo_d3);
                        5'd13: sm_char_lut = bcd_char(wo_d2);
                        5'd14: sm_char_lut = bcd_char(wo_d1);
                        5'd15: sm_char_lut = bcd_char(wo_d0);
                        5'd16: sm_char_lut = CH_M;
                        5'd17: sm_char_lut = CH_S;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end

                // Line 5 @ y=320:  "MIN TIMEOUT: NNNNMS"  (19 chars, adaptive only)
                else if (adaptive_mode && py >= 10'd320 && py < 10'd352) begin
                    sm_active = 1'b1;
                    sm_nchars = 5'd19;
                    sm_oy     = 10'd320;
                    sm_ox     = 10'd320 - (19*16)/2;       // 168
                    sm_color  = C_YELLOW;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_M;
                        5'd1:  sm_char_lut = CH_I;
                        5'd2:  sm_char_lut = CH_N;
                        5'd3:  sm_char_lut = CH_SPACE;
                        5'd4:  sm_char_lut = CH_T;
                        5'd5:  sm_char_lut = CH_I;
                        5'd6:  sm_char_lut = CH_M;
                        5'd7:  sm_char_lut = CH_E;
                        5'd8:  sm_char_lut = CH_O;
                        5'd9:  sm_char_lut = CH_U;
                        5'd10: sm_char_lut = CH_T;
                        5'd11: sm_char_lut = CH_COLON;
                        5'd12: sm_char_lut = CH_SPACE;
                        5'd13: sm_char_lut = bcd_char(mt_d3);
                        5'd14: sm_char_lut = bcd_char(mt_d2);
                        5'd15: sm_char_lut = bcd_char(mt_d1);
                        5'd16: sm_char_lut = bcd_char(mt_d0);
                        5'd17: sm_char_lut = CH_M;
                        5'd18: sm_char_lut = CH_S;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end

                // Line 6 @ y=400:  "PRESS BTNC TO RESTART"  (21 chars)
                else if (py >= 10'd400 && py < 10'd432) begin
                    sm_active = 1'b1;
                    sm_nchars = 5'd21;
                    sm_oy     = 10'd400;
                    sm_ox     = 10'd320 - (21*16)/2;       // 152
                    sm_color  = C_GREY;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_P;
                        5'd1:  sm_char_lut = CH_R;
                        5'd2:  sm_char_lut = CH_E;
                        5'd3:  sm_char_lut = CH_S;
                        5'd4:  sm_char_lut = CH_S;
                        5'd5:  sm_char_lut = CH_SPACE;
                        5'd6:  sm_char_lut = CH_B;
                        5'd7:  sm_char_lut = CH_T;
                        5'd8:  sm_char_lut = CH_N;
                        5'd9:  sm_char_lut = CH_C;
                        5'd10: sm_char_lut = CH_SPACE;
                        5'd11: sm_char_lut = CH_T;
                        5'd12: sm_char_lut = CH_O;
                        5'd13: sm_char_lut = CH_SPACE;
                        5'd14: sm_char_lut = CH_R;
                        5'd15: sm_char_lut = CH_E;
                        5'd16: sm_char_lut = CH_S;
                        5'd17: sm_char_lut = CH_T;
                        5'd18: sm_char_lut = CH_A;
                        5'd19: sm_char_lut = CH_R;
                        5'd20: sm_char_lut = CH_T;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end

            end else begin
                // title instructino screen

                // BIG "STROOP TEST" header at y=60
                big_active = 1'b1;
                big_nchars = 5'd11;
                big_ox     = 10'd320 - (11*32)/2;   // 144
                big_oy     = 10'd60;
                big_color  = C_WHITE;
                case (big_cell)
                    5'd0:  big_char_lut = CH_S;
                    5'd1:  big_char_lut = CH_T;
                    5'd2:  big_char_lut = CH_R;
                    5'd3:  big_char_lut = CH_O;
                    5'd4:  big_char_lut = CH_O;
                    5'd5:  big_char_lut = CH_P;
                    5'd6:  big_char_lut = CH_SPACE;
                    5'd7:  big_char_lut = CH_T;
                    5'd8:  big_char_lut = CH_E;
                    5'd9:  big_char_lut = CH_S;
                    5'd10: big_char_lut = CH_T;
                    default: big_char_lut = CH_SPACE;
                endcase

                // Small instruction lines (py-zone dispatch)

                // y=140: "IDENTIFY THE INK COLOR" (22 chars)
                if (py >= 10'd140 && py < 10'd172) begin
                    sm_active = 1'b1;
                    sm_nchars = 5'd22;
                    sm_oy     = 10'd140;
                    sm_ox     = 10'd320 - (22*16)/2;       // 144
                    sm_color  = C_WHITE;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_I;
                        5'd1:  sm_char_lut = CH_D;
                        5'd2:  sm_char_lut = CH_E;
                        5'd3:  sm_char_lut = CH_N;
                        5'd4:  sm_char_lut = CH_T;
                        5'd5:  sm_char_lut = CH_I;
                        5'd6:  sm_char_lut = CH_F;
                        5'd7:  sm_char_lut = CH_Y;
                        5'd8:  sm_char_lut = CH_SPACE;
                        5'd9:  sm_char_lut = CH_T;
                        5'd10: sm_char_lut = CH_H;
                        5'd11: sm_char_lut = CH_E;
                        5'd12: sm_char_lut = CH_SPACE;
                        5'd13: sm_char_lut = CH_I;
                        5'd14: sm_char_lut = CH_N;
                        5'd15: sm_char_lut = CH_K;
                        5'd16: sm_char_lut = CH_SPACE;
                        5'd17: sm_char_lut = CH_C;
                        5'd18: sm_char_lut = CH_O;
                        5'd19: sm_char_lut = CH_L;
                        5'd20: sm_char_lut = CH_O;
                        5'd21: sm_char_lut = CH_R;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end

                // y=180: "NOT THE WORD" (12 chars)
                else if (py >= 10'd180 && py < 10'd212) begin
                    sm_active = 1'b1;
                    sm_nchars = 5'd12;
                    sm_oy     = 10'd180;
                    sm_ox     = 10'd320 - (12*16)/2;       // 224
                    sm_color  = C_WHITE;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_N;
                        5'd1:  sm_char_lut = CH_O;
                        5'd2:  sm_char_lut = CH_T;
                        5'd3:  sm_char_lut = CH_SPACE;
                        5'd4:  sm_char_lut = CH_T;
                        5'd5:  sm_char_lut = CH_H;
                        5'd6:  sm_char_lut = CH_E;
                        5'd7:  sm_char_lut = CH_SPACE;
                        5'd8:  sm_char_lut = CH_W;
                        5'd9:  sm_char_lut = CH_O;
                        5'd10: sm_char_lut = CH_R;
                        5'd11: sm_char_lut = CH_D;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end

                // y=240: "BTNU : RED  BTNR : GREEN" (24 chars)
                else if (py >= 10'd240 && py < 10'd272) begin
                    sm_active = 1'b1;
                    sm_nchars = 5'd24;
                    sm_oy     = 10'd240;
                    sm_ox     = 10'd320 - (24*16)/2;       // 128
                    sm_color  = C_WHITE;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_B;
                        5'd1:  sm_char_lut = CH_T;
                        5'd2:  sm_char_lut = CH_N;
                        5'd3:  sm_char_lut = CH_U;
                        5'd4:  sm_char_lut = CH_SPACE;
                        5'd5:  sm_char_lut = CH_COLON;
                        5'd6:  sm_char_lut = CH_SPACE;
                        5'd7:  sm_char_lut = CH_R;
                        5'd8:  sm_char_lut = CH_E;
                        5'd9:  sm_char_lut = CH_D;
                        5'd10: sm_char_lut = CH_SPACE;
                        5'd11: sm_char_lut = CH_SPACE;
                        5'd12: sm_char_lut = CH_B;
                        5'd13: sm_char_lut = CH_T;
                        5'd14: sm_char_lut = CH_N;
                        5'd15: sm_char_lut = CH_R;
                        5'd16: sm_char_lut = CH_SPACE;
                        5'd17: sm_char_lut = CH_COLON;
                        5'd18: sm_char_lut = CH_SPACE;
                        5'd19: sm_char_lut = CH_G;
                        5'd20: sm_char_lut = CH_R;
                        5'd21: sm_char_lut = CH_E;
                        5'd22: sm_char_lut = CH_E;
                        5'd23: sm_char_lut = CH_N;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end

                // y=280: "BTND : BLUE  BTNL : YELLOW" (26 chars)
                else if (py >= 10'd280 && py < 10'd312) begin
                    sm_active = 1'b1;
                    sm_nchars = 5'd26;
                    sm_oy     = 10'd280;
                    sm_ox     = 10'd320 - (26*16)/2;       // 112
                    sm_color  = C_WHITE;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_B;
                        5'd1:  sm_char_lut = CH_T;
                        5'd2:  sm_char_lut = CH_N;
                        5'd3:  sm_char_lut = CH_D;
                        5'd4:  sm_char_lut = CH_SPACE;
                        5'd5:  sm_char_lut = CH_COLON;
                        5'd6:  sm_char_lut = CH_SPACE;
                        5'd7:  sm_char_lut = CH_B;
                        5'd8:  sm_char_lut = CH_L;
                        5'd9:  sm_char_lut = CH_U;
                        5'd10: sm_char_lut = CH_E;
                        5'd11: sm_char_lut = CH_SPACE;
                        5'd12: sm_char_lut = CH_SPACE;
                        5'd13: sm_char_lut = CH_B;
                        5'd14: sm_char_lut = CH_T;
                        5'd15: sm_char_lut = CH_N;
                        5'd16: sm_char_lut = CH_L;
                        5'd17: sm_char_lut = CH_SPACE;
                        5'd18: sm_char_lut = CH_COLON;
                        5'd19: sm_char_lut = CH_SPACE;
                        5'd20: sm_char_lut = CH_Y;
                        5'd21: sm_char_lut = CH_E;
                        5'd22: sm_char_lut = CH_L;
                        5'd23: sm_char_lut = CH_L;
                        5'd24: sm_char_lut = CH_O;
                        5'd25: sm_char_lut = CH_W;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end

                // y=340: "SW1 UP : ADAPTIVE MODE" (22 chars)
                else if (py >= 10'd340 && py < 10'd372) begin
                    sm_active = 1'b1;
                    sm_nchars = 5'd22;
                    sm_oy     = 10'd340;
                    sm_ox     = 10'd320 - (22*16)/2;       // 144
                    sm_color  = C_YELLOW;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_S;
                        5'd1:  sm_char_lut = CH_W;
                        5'd2:  sm_char_lut = CH_1;
                        5'd3:  sm_char_lut = CH_SPACE;
                        5'd4:  sm_char_lut = CH_U;
                        5'd5:  sm_char_lut = CH_P;
                        5'd6:  sm_char_lut = CH_SPACE;
                        5'd7:  sm_char_lut = CH_COLON;
                        5'd8:  sm_char_lut = CH_SPACE;
                        5'd9:  sm_char_lut = CH_A;
                        5'd10: sm_char_lut = CH_D;
                        5'd11: sm_char_lut = CH_A;
                        5'd12: sm_char_lut = CH_P;
                        5'd13: sm_char_lut = CH_T;
                        5'd14: sm_char_lut = CH_I;
                        5'd15: sm_char_lut = CH_V;
                        5'd16: sm_char_lut = CH_E;
                        5'd17: sm_char_lut = CH_SPACE;
                        5'd18: sm_char_lut = CH_M;
                        5'd19: sm_char_lut = CH_O;
                        5'd20: sm_char_lut = CH_D;
                        5'd21: sm_char_lut = CH_E;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end

                // y=400: "PRESS BTNC TO START" (19 chars)
                else if (py >= 10'd400 && py < 10'd432) begin
                    sm_active = 1'b1;
                    sm_nchars = 5'd19;
                    sm_oy     = 10'd400;
                    sm_ox     = 10'd320 - (19*16)/2;       // 168
                    sm_color  = C_GREY;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_P;
                        5'd1:  sm_char_lut = CH_R;
                        5'd2:  sm_char_lut = CH_E;
                        5'd3:  sm_char_lut = CH_S;
                        5'd4:  sm_char_lut = CH_S;
                        5'd5:  sm_char_lut = CH_SPACE;
                        5'd6:  sm_char_lut = CH_B;
                        5'd7:  sm_char_lut = CH_T;
                        5'd8:  sm_char_lut = CH_N;
                        5'd9:  sm_char_lut = CH_C;
                        5'd10: sm_char_lut = CH_SPACE;
                        5'd11: sm_char_lut = CH_T;
                        5'd12: sm_char_lut = CH_O;
                        5'd13: sm_char_lut = CH_SPACE;
                        5'd14: sm_char_lut = CH_S;
                        5'd15: sm_char_lut = CH_T;
                        5'd16: sm_char_lut = CH_A;
                        5'd17: sm_char_lut = CH_R;
                        5'd18: sm_char_lut = CH_T;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end
            end
        end

        // SHOW_WORD or WAIT_INPUT: trial screen
        else if (st_show || st_wait) begin
            // BIG word, mismatched ink color, centered at y=200
            big_active = 1'b1;
            big_nchars = {1'b0, word_len(cur_word)};
            big_ox     = 10'd320 - ((word_len(cur_word) * 32) >> 1);
            big_oy     = 10'd200;
            big_color  = color_of(cur_color);
            big_char_lut = word_letter(cur_word, big_cell[2:0]);

            // Top bar @ y=20: ROUND on the left, TIMEOUT on the right.
            // Both share one sm_* slot via px-zone dispatch.
            if (py >= 10'd20 && py < 10'd52) begin
                if (px < 10'd320) begin
                    // "ROUND NN/20" or "ROUND NN/30" - 11 chars, top-left
                    sm_active = 1'b1;
                    sm_nchars = 5'd11;
                    sm_ox     = 10'd20;
                    sm_oy     = 10'd20;
                    sm_color  = C_WHITE;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_R;
                        5'd1:  sm_char_lut = CH_O;
                        5'd2:  sm_char_lut = CH_U;
                        5'd3:  sm_char_lut = CH_N;
                        5'd4:  sm_char_lut = CH_D;
                        5'd5:  sm_char_lut = CH_SPACE;
                        5'd6:  sm_char_lut = bcd_char(rn_d1);
                        5'd7:  sm_char_lut = bcd_char(rn_d0);
                        5'd8:  sm_char_lut = CH_SLASH;
                        5'd9:  sm_char_lut = adaptive_mode ? CH_3 : CH_2;
                        5'd10: sm_char_lut = CH_0;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end else begin
                    // "TIMEOUT: NNNNMS" - 15 chars, top-right
                    sm_active = 1'b1;
                    sm_nchars = 5'd15;
                    sm_ox     = 10'd640 - 15*16 - 10'd20;  // 380
                    sm_oy     = 10'd20;
                    sm_color  = adaptive_mode ? C_YELLOW : C_GREY;
                    case (sm_cell)
                        5'd0:  sm_char_lut = CH_T;
                        5'd1:  sm_char_lut = CH_I;
                        5'd2:  sm_char_lut = CH_M;
                        5'd3:  sm_char_lut = CH_E;
                        5'd4:  sm_char_lut = CH_O;
                        5'd5:  sm_char_lut = CH_U;
                        5'd6:  sm_char_lut = CH_T;
                        5'd7:  sm_char_lut = CH_COLON;
                        5'd8:  sm_char_lut = CH_SPACE;
                        5'd9:  sm_char_lut = bcd_char(ct_d3);
                        5'd10: sm_char_lut = bcd_char(ct_d2);
                        5'd11: sm_char_lut = bcd_char(ct_d1);
                        5'd12: sm_char_lut = bcd_char(ct_d0);
                        5'd13: sm_char_lut = CH_M;
                        5'd14: sm_char_lut = CH_S;
                        default: sm_char_lut = CH_SPACE;
                    endcase
                end
            end
        end

        // CORRECT: green check + reaction time
        else if (st_correct) begin
            big_active = 1'b1;
            big_nchars = 5'd8;
            big_ox     = 10'd320 - (8*32)/2;
            big_oy     = 10'd200;
            big_color  = C_GREEN;
            case (big_cell)
                5'd0: big_char_lut = CH_CHECK;
                5'd1: big_char_lut = CH_SPACE;
                5'd2: big_char_lut = bcd_char(rt_d3);
                5'd3: big_char_lut = bcd_char(rt_d2);
                5'd4: big_char_lut = bcd_char(rt_d1);
                5'd5: big_char_lut = bcd_char(rt_d0);
                5'd6: big_char_lut = CH_M;
                5'd7: big_char_lut = CH_S;
                default: big_char_lut = CH_SPACE;
            endcase
        end

        // INCORRECT: red X + reaction time
        else if (st_incorrect) begin
            big_active = 1'b1;
            big_nchars = 5'd8;
            big_ox     = 10'd320 - (8*32)/2;
            big_oy     = 10'd200;
            big_color  = C_RED;
            case (big_cell)
                5'd0: big_char_lut = CH_XMARK;
                5'd1: big_char_lut = CH_SPACE;
                5'd2: big_char_lut = bcd_char(rt_d3);
                5'd3: big_char_lut = bcd_char(rt_d2);
                5'd4: big_char_lut = bcd_char(rt_d1);
                5'd5: big_char_lut = bcd_char(rt_d0);
                5'd6: big_char_lut = CH_M;
                5'd7: big_char_lut = CH_S;
                default: big_char_lut = CH_SPACE;
            endcase
        end

        // SCORE state is one cycle long
    end

    //  Pick which (big or small) glyph this pixel is in 
    always @(*) begin
        target_in_glyph = 1'b0;
        target_char     = CH_SPACE;
        target_row      = 4'd0;
        target_col      = 3'd0;
        target_fg       = C_WHITE;
        target_bg       = C_BLACK;

        if (in_big) begin
            target_in_glyph = 1'b1;
            target_char     = big_char_lut;
            target_row      = big_row_in_cell[5:2];     // /4 (scale=4)
            target_col      = big_col_in_cell[4:2];     // /4
            target_fg       = big_color;
            target_bg       = C_BLACK;
        end else if (in_sm) begin
            target_in_glyph = 1'b1;
            target_char     = sm_char_lut;
            target_row      = sm_row_in_cell[4:1];      // /2 (scale=2)
            target_col      = sm_col_in_cell[3:1];      // /2
            target_fg       = sm_color;
            target_bg       = C_BLACK;
        end
    end

    // drive font ROM address
    always @(posedge clk) begin
        rom_char    <= target_char;
        rom_row     <= target_row;
        col_d1      <= target_col;
        fg_col_d1   <= target_fg;
        bg_col_d1   <= target_bg;
        in_glyph_d1 <= target_in_glyph;
    end

    // combine ROM data with column index to pick pixel
    wire pix_lit = rom_data[7 - col_d1];

    //  final RGB output
    always @(posedge clk) begin
        if (!video_on) begin
            rgb <= C_BLACK;
        end else if (in_glyph_d1 && pix_lit) begin
            rgb <= fg_col_d1;
        end else begin
            rgb <= bg_col_d1;
        end
    end

endmodule

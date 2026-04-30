//==============================================================================
// pixel_gen.v
//------------------------------------------------------------------------------
// Composes the VGA pixel stream depending on the current FSM state and game
// data. Renders four distinct screens:
//
//   1) IDLE / Title      -- "STROOP TEST" + "PRESS BTNC TO START"
//                           OR results screen if results_ready==1
//   2) SHOW_WORD/WAIT    -- the trial: big color word in mismatched ink color
//                           plus a countdown timer bar at the bottom and the
//                           current score in the corner.
//   3) CORRECT/INCORRECT -- giant check or X plus the reaction time in ms.
//   4) (results)         -- handled in IDLE branch when results_ready==1.
//
// All glyphs use a SCALE factor so the 8x16 source font is enlarged uniformly.
// Characters are positioned by computing the (x,y) origin for each glyph and
// then asking the font ROM whether the current pixel is inside that glyph.
//
// Performance:
//   - The font ROM has a one-cycle latency. We register the pixel coordinate
//     and the requested character one cycle ahead so the ROM data lines up
//     with the pixel being drawn. This is implemented by computing addresses
//     in the same cycle as we use them, accepting one pixel of horizontal
//     latency (invisible to the user).
//
// Color encoding (12-bit RGB, 4 bits/channel):
//   RED    = 12'hF00
//   GREEN  = 12'h2C5  (slightly muted, looks more like the screenshot)
//   BLUE   = 12'h35F  (a brighter, friendlier blue)
//   YELLOW = 12'hFC0
//   WHITE  = 12'hFFF
//   BLACK  = 12'h000  (background)
//==============================================================================

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

    // Game data
    input  wire [1:0]  cur_word,        // 0=RED 1=GREEN 2=BLUE 3=YELLOW
    input  wire [1:0]  cur_color,
    input  wire [4:0]  round_num,       // 0..20
    input  wire [15:0] score_val,
    input  wire [15:0] react_time_ms,
    input  wire        results_ready,

    output reg  [11:0] rgb              // 12-bit color out
);

    // ---------------- Color palette ----------------
    localparam [11:0] C_BLACK  = 12'h000;
    localparam [11:0] C_WHITE  = 12'hFFF;
    localparam [11:0] C_RED    = 12'hF00;
    localparam [11:0] C_GREEN  = 12'h2C5;
    localparam [11:0] C_BLUE   = 12'h35F;
    localparam [11:0] C_YELLOW = 12'hFC0;
    localparam [11:0] C_GREY   = 12'h888;

    // Look up "ink color" from a 2-bit color code
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

    // ---------------- Font ROM access ----------------
    // The pixel_gen module computes a 6-bit character code and a 4-bit row
    // for the GLYPH covering the current pixel. The font ROM returns the
    // 8-pixel wide bitmap row, and we pick the column bit indexed by
    // (pix_x - glyph_origin_x) >> SCALE.
    reg  [5:0] rom_char;
    reg  [3:0] rom_row;
    wire [9:0] rom_addr = {rom_char, rom_row};
    wire [7:0] rom_data;
    font_rom u_font (
        .clk  (clk),
        .addr (rom_addr),
        .data (rom_data)
    );

    // Because rom_data is registered (1-cycle read latency), we delay the
    // pixel-column index, requested glyph color, and fg/bg validity by one
    // cycle so they line up with the data coming back from the ROM.
    reg [2:0]  col_d1;     // which of the 8 glyph columns (post-scale)
    reg [11:0] fg_col_d1;  // foreground color at this pixel
    reg [11:0] bg_col_d1;  // background color at this pixel
    reg        in_glyph_d1; // 1 if this pixel falls inside any glyph cell

    // ---------------- Helper: render N-character string at (ox, oy) -------------
    // We can't use loops in synth-friendly Verilog elegantly here, so each
    // screen has explicit per-character logic. We define a single "scaled
    // character cell" of CW pixels x CH pixels (CW=8*scale, CH=16*scale).
    //
    // For a given (px, py) we ask: is it inside cell i of a string starting
    // at (ox, oy)? If yes, we know the cell index, the column within the
    // cell, and the row within the cell. We then map cell index -> char code.
    //
    // To keep the file readable, the per-screen logic computes a few useful
    // intermediate signals: target_char, target_row, target_col, fg, bg,
    // and in_glyph. These are then registered into rom_char/rom_row plus
    // the *_d1 pipeline registers.

    // ---------------- Default values for outputs ----------------
    reg [5:0]  target_char;
    reg [3:0]  target_row;
    reg [2:0]  target_col;
    reg [11:0] target_fg;
    reg [11:0] target_bg;
    reg        target_in_glyph;

    // ---------------- Letter codes (6-bit, == ASCII & 0x3F) ----------------
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

    // Helper that converts a 4-bit BCD value to its character code
    function [5:0] bcd_char;
        input [3:0] d;
        begin
            bcd_char = {2'b11, d};   // 0x30 | d  -> 6'h30..6'h39 -> '0'..'9'
        end
    endfunction

    // ---------------- BCD breakouts for score and reaction time ----------------
    wire [3:0] sc_d3 = (score_val/1000)%10;
    wire [3:0] sc_d2 = (score_val/100) %10;
    wire [3:0] sc_d1 = (score_val/10)  %10;
    wire [3:0] sc_d0 =  score_val      %10;

    wire [3:0] rt_d3 = (react_time_ms/1000)%10;
    wire [3:0] rt_d2 = (react_time_ms/100) %10;
    wire [3:0] rt_d1 = (react_time_ms/10)  %10;
    wire [3:0] rt_d0 =  react_time_ms      %10;

    // ---------------- Word-text helper ----------------
    // Given a 2-bit word index and a character position 0..5, return the
    // character code for that letter (or SPACE beyond the word's length).
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

    // Word lengths for centering
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

    // ===================================================================
    //                    MAIN COMBINATIONAL DRAW LOGIC
    // ===================================================================
    // We compute "what character (if any) is at this pixel?" for each screen.
    // Resolution: 640 wide, 480 tall. We use SCALE=4 mainly (8*4=32 wide,
    // 16*4=64 tall per glyph) for the BIG word/digit displays, and SCALE=2
    // (16x32) for normal text rows.

    integer i;       // generic loop var, only used in always @(*) for codegen

    // Local pixel coords
    wire [9:0] px = hcount;
    wire [9:0] py = vcount;

    // ---------- Big rendering (scale 4): 32x64 per char ----------
    // Layout the title or trial word horizontally centered at vertical row Y0.
    // For up to N chars, total width = N * 32. We pick the origin so the
    // string is centered around x = 320.

    // We compute these for whichever screen is active.
    reg [9:0]  big_ox;        // string origin X (top-left of leftmost char)
    reg [9:0]  big_oy;        // string origin Y
    reg [3:0]  big_nchars;    // number of chars in the string
    reg [11:0] big_color;     // foreground color
    reg        big_active;    // 1 if the big string is being drawn this state

    // For each screen we will populate big_* and then a uniform inner block
    // tests whether (px,py) lies inside that string and, if so, picks the
    // character code from a per-screen helper.

    // ------------- small string (scale 2): 16x32 per char --------------
    // Used for "PRESS BTNC TO START", score readout, "ROUND XX/20", etc.
    reg [9:0]  sm_ox, sm_oy;
    reg [3:0]  sm_nchars;
    reg [11:0] sm_color;
    reg        sm_active;

    // Per-cell character lookups for big and small strings: each screen
    // implements `big_char(idx)` and `sm_char(idx)` via a case below.
    reg [5:0] big_char_lut;
    reg [5:0] sm_char_lut;

    // Index of the cell (0..N-1) that the current pixel falls into, plus
    // the column/row within that 32x64 (or 16x32) cell.
    reg [3:0] big_cell;
    reg [4:0] big_col_in_cell;   // 0..31
    reg [5:0] big_row_in_cell;   // 0..63
    reg [3:0] sm_cell;
    reg [3:0] sm_col_in_cell;    // 0..15
    reg [4:0] sm_row_in_cell;    // 0..31

    reg in_big, in_sm;

    // Compute "in big string?" and indices.
    always @(*) begin
        in_big = 1'b0;
        big_cell        = 4'd0;
        big_col_in_cell = 5'd0;
        big_row_in_cell = 6'd0;
        if (big_active) begin
            if ((px >= big_ox) && (py >= big_oy) &&
                (py <  big_oy + 64)) begin
                // Width of full string is big_nchars * 32
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
        sm_cell        = 4'd0;
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

    // ---------------- Per-state screen layout ----------------
    // We populate big_* and sm_* and big_char_lut/sm_char_lut here.

    // Determine which "BIG" string and "SMALL" string to draw and their cells.
    always @(*) begin
        // defaults: nothing
        big_active   = 1'b0;
        big_ox       = 10'd0;
        big_oy       = 10'd0;
        big_nchars   = 4'd0;
        big_color    = C_WHITE;
        big_char_lut = CH_SPACE;

        sm_active    = 1'b0;
        sm_ox        = 10'd0;
        sm_oy        = 10'd0;
        sm_nchars    = 4'd0;
        sm_color     = C_GREY;
        sm_char_lut  = CH_SPACE;

        // ------------- IDLE: title screen OR results screen -------------
        if (st_idle) begin
            if (results_ready) begin
                // Big: "SCORE XX/20" centered. We use 8 chars: "SCORE NN/20"
                //  => 'S','C','O','R','E',' ',d1,d0,'/','2','0'  = 11 chars
                big_active = 1'b1;
                big_nchars = 4'd11;
                big_ox     = 10'd320 - (11*32)/2;   // center: 320 - 176 = 144
                big_oy     = 10'd200;
                big_color  = C_YELLOW;
                case (big_cell)
                    4'd0: big_char_lut = CH_S;
                    4'd1: big_char_lut = CH_C;
                    4'd2: big_char_lut = CH_O;
                    4'd3: big_char_lut = CH_R;
                    4'd4: big_char_lut = CH_E;
                    4'd5: big_char_lut = CH_SPACE;
                    4'd6: big_char_lut = bcd_char(sc_d1);
                    4'd7: big_char_lut = bcd_char(sc_d0);
                    4'd8: big_char_lut = CH_SLASH;
                    4'd9: big_char_lut = CH_2;
                    4'd10: big_char_lut = CH_0;
                    default: big_char_lut = CH_SPACE;
                endcase

                // Small: "PRESS BTNC TO RESTART" -- 21 chars
                sm_active = 1'b1;
                sm_nchars = 4'd14;
                sm_ox     = 10'd320 - (14*16)/2;
                sm_oy     = 10'd320;
                sm_color  = C_WHITE;
                case (sm_cell)
                    4'd0: sm_char_lut = CH_P;
                    4'd1: sm_char_lut = CH_R;
                    4'd2: sm_char_lut = CH_E;
                    4'd3: sm_char_lut = CH_S;
                    4'd4: sm_char_lut = CH_S;
                    4'd5: sm_char_lut = CH_SPACE;
                    4'd6: sm_char_lut = CH_T;
                    4'd7: sm_char_lut = CH_O;
                    4'd8: sm_char_lut = CH_SPACE;
                    4'd9: sm_char_lut = CH_R;
                    4'd10: sm_char_lut = CH_E;
                    4'd11: sm_char_lut = CH_T;
                    4'd12: sm_char_lut = CH_R;
                    4'd13: sm_char_lut = CH_Y;
                    default: sm_char_lut = CH_SPACE;
                endcase
            end else begin
                // Title screen: big "STROOP TEST" (11 chars), small prompt
                big_active = 1'b1;
                big_nchars = 4'd11;
                big_ox     = 10'd320 - (11*32)/2;
                big_oy     = 10'd180;
                big_color  = C_WHITE;
                case (big_cell)
                    4'd0: big_char_lut = CH_S;
                    4'd1: big_char_lut = CH_T;
                    4'd2: big_char_lut = CH_R;
                    4'd3: big_char_lut = CH_O;
                    4'd4: big_char_lut = CH_O;
                    4'd5: big_char_lut = CH_P;
                    4'd6: big_char_lut = CH_SPACE;
                    4'd7: big_char_lut = CH_T;
                    4'd8: big_char_lut = CH_E;
                    4'd9: big_char_lut = CH_S;
                    4'd10: big_char_lut = CH_T;
                    default: big_char_lut = CH_SPACE;
                endcase

                // "PRESS BTNC TO START" (19 chars w/ spaces)
                sm_active = 1'b1;
                sm_nchars = 4'd11;
                sm_ox     = 10'd320 - (11*16)/2;
                sm_oy     = 10'd300;
                sm_color  = C_GREY;
                case (sm_cell)
                    4'd0: sm_char_lut = CH_P;
                    4'd1: sm_char_lut = CH_R;
                    4'd2: sm_char_lut = CH_E;
                    4'd3: sm_char_lut = CH_S;
                    4'd4: sm_char_lut = CH_S;
                    4'd5: sm_char_lut = CH_SPACE;
                    4'd6: sm_char_lut = CH_S;
                    4'd7: sm_char_lut = CH_T;
                    4'd8: sm_char_lut = CH_A;
                    4'd9: sm_char_lut = CH_R;
                    4'd10: sm_char_lut = CH_T;
                    default: sm_char_lut = CH_SPACE;
                endcase
            end
        end

        // ------------- SHOW_WORD or WAIT_INPUT: trial screen -------------
        else if (st_show || st_wait) begin
            // Big word in the mismatched ink color
            big_active = 1'b1;
            big_nchars = {2'd0, word_len(cur_word)};
            big_ox     = 10'd320 - ((word_len(cur_word) * 32) >> 1);
            big_oy     = 10'd200;
            big_color  = color_of(cur_color);
            big_char_lut = word_letter(cur_word, big_cell[2:0]);

            // Small status line: "ROUND NN/20" - 11 chars, top-left
            sm_active = 1'b1;
            sm_nchars = 4'd11;
            sm_ox     = 10'd20;
            sm_oy     = 10'd20;
            sm_color  = C_WHITE;
            case (sm_cell)
                4'd0: sm_char_lut = CH_R;
                4'd1: sm_char_lut = CH_O;
                4'd2: sm_char_lut = CH_U;
                4'd3: sm_char_lut = CH_N;
                4'd4: sm_char_lut = CH_D;
                4'd5: sm_char_lut = CH_SPACE;
                4'd6: sm_char_lut = bcd_char(((round_num+1)/10) % 10);
                4'd7: sm_char_lut = bcd_char((round_num+1) % 10);
                4'd8: sm_char_lut = CH_SLASH;
                4'd9: sm_char_lut = CH_2;
                4'd10: sm_char_lut = CH_0;
                default: sm_char_lut = CH_SPACE;
            endcase
        end

        // ------------- CORRECT: green check + reaction time -------------
        else if (st_correct) begin
            // "✓ NNNNms" - 8 chars: check, space, d3,d2,d1,d0,'m','s'
            big_active = 1'b1;
            big_nchars = 4'd8;
            big_ox     = 10'd320 - (8*32)/2;
            big_oy     = 10'd200;
            big_color  = C_GREEN;
            case (big_cell)
                4'd0: big_char_lut = CH_CHECK;
                4'd1: big_char_lut = CH_SPACE;
                4'd2: big_char_lut = bcd_char(rt_d3);
                4'd3: big_char_lut = bcd_char(rt_d2);
                4'd4: big_char_lut = bcd_char(rt_d1);
                4'd5: big_char_lut = bcd_char(rt_d0);
                4'd6: big_char_lut = CH_M;
                4'd7: big_char_lut = CH_S;
                default: big_char_lut = CH_SPACE;
            endcase
        end

        // ------------- INCORRECT: red X -------------
        else if (st_incorrect) begin
            big_active = 1'b1;
            big_nchars = 4'd8;
            big_ox     = 10'd320 - (8*32)/2;
            big_oy     = 10'd200;
            big_color  = C_RED;
            case (big_cell)
                4'd0: big_char_lut = CH_XMARK;
                4'd1: big_char_lut = CH_SPACE;
                4'd2: big_char_lut = bcd_char(rt_d3);
                4'd3: big_char_lut = bcd_char(rt_d2);
                4'd4: big_char_lut = bcd_char(rt_d1);
                4'd5: big_char_lut = bcd_char(rt_d0);
                4'd6: big_char_lut = CH_M;
                4'd7: big_char_lut = CH_S;
                default: big_char_lut = CH_SPACE;
            endcase
        end

        // ------------- SCORE (single-cycle bookkeeping): just blank -------------
        // The SCORE state is one cycle long, so the user never sees it; we
        // leave the screen blank (background color).
    end

    // -------------- Pick which (big or small) glyph this pixel is in --------------
    // If both overlap (shouldn't happen if layouts are sane), big wins.
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

    // Drive font ROM address. Rom data appears 1 cycle later.
    always @(posedge clk) begin
        rom_char    <= target_char;
        rom_row     <= target_row;
        col_d1      <= target_col;
        fg_col_d1   <= target_fg;
        bg_col_d1   <= target_bg;
        in_glyph_d1 <= target_in_glyph;
    end

    // -------------- Combine ROM data with column index to pick pixel --------------
    // Bit 7 of rom_data is the leftmost pixel of the glyph row.
    wire pix_lit = rom_data[7 - col_d1];

    // -------------- Final RGB output --------------
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

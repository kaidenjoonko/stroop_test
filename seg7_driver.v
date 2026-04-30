//==============================================================================
// seg7_driver.v
//------------------------------------------------------------------------------
// 8-digit 7-segment display driver for the Nexys A7.
//
// Hardware notes for Nexys A7:
//   - Both anodes (an[7:0]) and segments (seg[6:0], dp) are ACTIVE LOW.
//   - Anodes select which digit is currently illuminated.
//   - We multiplex at ~1 kHz per digit (refresh ~125 Hz total) so all 8 digits
//     appear lit simultaneously to the human eye.
//
// Display layout (from leftmost an[7] to rightmost an[0]):
//   an[7..4] -> SCORE      : displayed as 4-digit decimal (0..20 in practice)
//   an[3..0] -> REACT_TIME : displayed as 4-digit decimal milliseconds (0..3000)
//
// BCD conversion uses a simple combinational divide-by-10 chain. For 16-bit
// inputs (max 65535 -> 5 digits) this is small and meets timing easily.
//==============================================================================

`timescale 1ns / 1ps

module seg7_driver (
    input  wire        clk,           // 100 MHz
    input  wire        reset,
    input  wire [15:0] score_val,     // shown on left 4 digits
    input  wire [15:0] time_val,      // shown on right 4 digits (ms)
    output reg  [6:0]  seg,           // segment cathodes (active LOW), [a..g]
    output wire        dp,            // decimal point (always off)
    output reg  [7:0]  an             // digit anodes (active LOW)
);

    assign dp = 1'b1;   // active-low: 1 = off

    // ---------------- BCD conversion (combinational) ----------------
    // Splits score_val and time_val into 4 BCD digits each.
    wire [3:0] s_d0 =  score_val        % 10;
    wire [3:0] s_d1 = (score_val / 10)  % 10;
    wire [3:0] s_d2 = (score_val / 100) % 10;
    wire [3:0] s_d3 = (score_val / 1000)% 10;

    wire [3:0] t_d0 =  time_val         % 10;
    wire [3:0] t_d1 = (time_val / 10)   % 10;
    wire [3:0] t_d2 = (time_val / 100)  % 10;
    wire [3:0] t_d3 = (time_val / 1000) % 10;

    // ---------------- Refresh counter ----------------
    // We use the upper 3 bits of an 18-bit counter to select the active digit,
    // giving each digit ~2.62 ms of on-time (refresh = 100 MHz / 2^18 ~ 381 Hz
    // per digit, total frame ~48 Hz which is fine; bump width for slower if
    // needed). Width 18 is a common textbook value.
    reg [17:0] refresh_cnt;
    always @(posedge clk) begin
        if (reset) refresh_cnt <= 18'd0;
        else       refresh_cnt <= refresh_cnt + 1'b1;
    end
    wire [2:0] digit_sel = refresh_cnt[17:15];

    // ---------------- Anode + digit MUX ----------------
    // Active LOW: drive a single bit low to enable that digit.
    reg [3:0] cur_digit;
    always @(*) begin
        case (digit_sel)
            3'd0: begin an = 8'b1111_1110; cur_digit = t_d0; end // rightmost
            3'd1: begin an = 8'b1111_1101; cur_digit = t_d1; end
            3'd2: begin an = 8'b1111_1011; cur_digit = t_d2; end
            3'd3: begin an = 8'b1111_0111; cur_digit = t_d3; end
            3'd4: begin an = 8'b1110_1111; cur_digit = s_d0; end
            3'd5: begin an = 8'b1101_1111; cur_digit = s_d1; end
            3'd6: begin an = 8'b1011_1111; cur_digit = s_d2; end
            3'd7: begin an = 8'b0111_1111; cur_digit = s_d3; end // leftmost
            default: begin an = 8'b1111_1111; cur_digit = 4'd0; end
        endcase
    end

    // ---------------- Hex/BCD digit -> segment encoding ----------------
    // seg = {a,b,c,d,e,f,g}, ACTIVE LOW (0 = lit). Patterns are the standard
    // 7-segment glyphs for 0-9.
    always @(*) begin
        case (cur_digit)
            4'h0: seg = 7'b0000001;
            4'h1: seg = 7'b1001111;
            4'h2: seg = 7'b0010010;
            4'h3: seg = 7'b0000110;
            4'h4: seg = 7'b1001100;
            4'h5: seg = 7'b0100100;
            4'h6: seg = 7'b0100000;
            4'h7: seg = 7'b0001111;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0000100;
            default: seg = 7'b1111111;   // blank
        endcase
    end

endmodule

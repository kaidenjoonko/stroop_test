// lfsr.v: generating random word/color pairs

`timescale 1ns / 1ps

module lfsr (
    input  wire       clk,
    input  wire       reset,
    input  wire       sample,       // pulse: latch new word/color pair
    output reg  [1:0] word_idx,     // word to display (RED/GREEN/BLUE/YELLOW)
    output reg  [1:0] color_idx     // ink color (always != word_idx)
);

    // 8 bit lfsr
    reg [7:0] lfsr_reg;
    wire feedback = lfsr_reg[7] ^ lfsr_reg[5] ^ lfsr_reg[4] ^ lfsr_reg[3];
    always @(posedge clk) begin
        if (reset)       lfsr_reg <= 8'hA5;            // non-zero seed
        else if (lfsr_reg == 8'h00) lfsr_reg <= 8'hA5; // safety: avoid stuck-at-zero
        else             lfsr_reg <= {lfsr_reg[6:0], feedback};
    end

    wire [1:0] w_raw      = lfsr_reg[1:0];
    wire [1:0] c_raw      = lfsr_reg[3:2];
    wire [1:0] offset_nz  = lfsr_reg[5:4] | 2'b01;       // forced non-zero offset
    wire [1:0] c_fixed    = w_raw + offset_nz;           // 2-bit add wraps mod 4

    always @(posedge clk) begin
        if (reset) begin
            word_idx  <= 2'd0;     // default RED
            color_idx <= 2'd2;     // default BLUE (mismatched)
        end else if (sample) begin
            word_idx  <= w_raw;
            color_idx <= (c_raw == w_raw) ? c_fixed : c_raw;
        end
    end

endmodule

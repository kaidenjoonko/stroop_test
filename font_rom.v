// font_rom.v: front end for 8x16 pixel map

`timescale 1ns / 1ps

module font_rom (
    input  wire        clk,
    input  wire [9:0]  addr,    // {char[5:0], row[3:0]}
    output reg  [7:0]  data
);

    // we used custom glyph codes (above the printable-ASCII subset we use)
    localparam GLYPH_CHECK = 6'h3E; //check mark
    localparam GLYPH_XMARK = 6'h3F; //X Mark

    wire [5:0] ch  = addr[9:4];
    wire [3:0] row = addr[3:0];

    // output is registered (synchronous read) to map to BRAM
    always @(posedge clk) begin
        data <= 8'h00;
        case (ch)

            //space
            6'h20: data <= 8'h00;

            // forward slash
            6'h2F: case (row)
                4'd2: data <= 8'b00000010;
                4'd3: data <= 8'b00000110;
                4'd4: data <= 8'b00001100;
                4'd5: data <= 8'b00001100;
                4'd6: data <= 8'b00011000;
                4'd7: data <= 8'b00011000;
                4'd8: data <= 8'b00110000;
                4'd9: data <= 8'b00110000;
                4'd10: data <= 8'b01100000;
                4'd11: data <= 8'b01100000;
                4'd12: data <= 8'b11000000;
                default: data <= 8'h00;
            endcase

            // semicolon
            6'h3A: case (row)
                4'd4,4'd5: data <= 8'b00011000;
                4'd11,4'd12: data <= 8'b00011000;
                default: data <= 8'h00;
            endcase

            // question mark
            // exclamation mark
            6'h21: case (row)
                4'd2,4'd3,4'd4,4'd5,4'd6,4'd7,4'd8: data <= 8'b00011000;
                4'd11,4'd12: data <= 8'b00011000;
                default: data <= 8'h00;
            endcase

            // digits 0-9
            6'h30: case (row)   // 0
                4'd2: data <= 8'b00111100;
                4'd3: data <= 8'b01100110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11000011;
                4'd7: data <= 8'b11000011;
                4'd8: data <= 8'b11000011;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b01100110;
                4'd12: data <= 8'b00111100;
                default: data <= 8'h00;
            endcase
            6'h31: case (row)   // 1
                4'd2: data <= 8'b00011000;
                4'd3: data <= 8'b00111000;
                4'd4: data <= 8'b01111000;
                4'd5: data <= 8'b00011000;
                4'd6: data <= 8'b00011000;
                4'd7: data <= 8'b00011000;
                4'd8: data <= 8'b00011000;
                4'd9: data <= 8'b00011000;
                4'd10: data <= 8'b00011000;
                4'd11: data <= 8'b00011000;
                4'd12: data <= 8'b01111110;
                default: data <= 8'h00;
            endcase
            6'h32: case (row)   // 2
                4'd2: data <= 8'b00111100;
                4'd3: data <= 8'b01100110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b00000011;
                4'd6: data <= 8'b00000110;
                4'd7: data <= 8'b00001100;
                4'd8: data <= 8'b00011000;
                4'd9: data <= 8'b00110000;
                4'd10: data <= 8'b01100000;
                4'd11: data <= 8'b11000000;
                4'd12: data <= 8'b11111111;
                default: data <= 8'h00;
            endcase
            6'h33: case (row)   // 3
                4'd2: data <= 8'b00111100;
                4'd3: data <= 8'b01100110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b00000011;
                4'd6: data <= 8'b00000110;
                4'd7: data <= 8'b00011100;
                4'd8: data <= 8'b00000110;
                4'd9: data <= 8'b00000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b01100110;
                4'd12: data <= 8'b00111100;
                default: data <= 8'h00;
            endcase
            6'h34: case (row)   // 4
                4'd2: data <= 8'b00000110;
                4'd3: data <= 8'b00001110;
                4'd4: data <= 8'b00011110;
                4'd5: data <= 8'b00110110;
                4'd6: data <= 8'b01100110;
                4'd7: data <= 8'b11000110;
                4'd8: data <= 8'b11111111;
                4'd9: data <= 8'b00000110;
                4'd10: data <= 8'b00000110;
                4'd11: data <= 8'b00000110;
                4'd12: data <= 8'b00000110;
                default: data <= 8'h00;
            endcase
            6'h35: case (row)   // 5
                4'd2: data <= 8'b11111111;
                4'd3: data <= 8'b11000000;
                4'd4: data <= 8'b11000000;
                4'd5: data <= 8'b11000000;
                4'd6: data <= 8'b11111100;
                4'd7: data <= 8'b00000110;
                4'd8: data <= 8'b00000011;
                4'd9: data <= 8'b00000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b01100110;
                4'd12: data <= 8'b00111100;
                default: data <= 8'h00;
            endcase
            6'h36: case (row)   // 6
                4'd2: data <= 8'b00111100;
                4'd3: data <= 8'b01100110;
                4'd4: data <= 8'b11000000;
                4'd5: data <= 8'b11000000;
                4'd6: data <= 8'b11111100;
                4'd7: data <= 8'b11000110;
                4'd8: data <= 8'b11000011;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b01100110;
                4'd12: data <= 8'b00111100;
                default: data <= 8'h00;
            endcase
            6'h37: case (row)   // 7
                4'd2: data <= 8'b11111111;
                4'd3: data <= 8'b00000011;
                4'd4: data <= 8'b00000110;
                4'd5: data <= 8'b00001100;
                4'd6: data <= 8'b00011000;
                4'd7: data <= 8'b00011000;
                4'd8: data <= 8'b00110000;
                4'd9: data <= 8'b00110000;
                4'd10: data <= 8'b01100000;
                4'd11: data <= 8'b01100000;
                4'd12: data <= 8'b11000000;
                default: data <= 8'h00;
            endcase
            6'h38: case (row)   // 8
                4'd2: data <= 8'b00111100;
                4'd3: data <= 8'b01100110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b01100110;
                4'd7: data <= 8'b00111100;
                4'd8: data <= 8'b01100110;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b01100110;
                4'd12: data <= 8'b00111100;
                default: data <= 8'h00;
            endcase
            6'h39: case (row)   // 9
                4'd2: data <= 8'b00111100;
                4'd3: data <= 8'b01100110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11000011;
                4'd7: data <= 8'b01100111;
                4'd8: data <= 8'b00111111;
                4'd9: data <= 8'b00000011;
                4'd10: data <= 8'b00000011;
                4'd11: data <= 8'b01100110;
                4'd12: data <= 8'b00111100;
                default: data <= 8'h00;
            endcase

    
            //uppercase letters A-Z
            6'h01: case (row)   // A
                4'd2: data <= 8'b00111100;
                4'd3: data <= 8'b01100110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11000011;
                4'd7: data <= 8'b11111111;
                4'd8: data <= 8'b11111111;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b11000011;
                4'd12: data <= 8'b11000011;
                default: data <= 8'h00;
            endcase
            6'h02: case (row)   // B
                4'd2: data <= 8'b11111100;
                4'd3: data <= 8'b11000110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11000110;
                4'd7: data <= 8'b11111100;
                4'd8: data <= 8'b11000110;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b11000110;
                4'd12: data <= 8'b11111100;
                default: data <= 8'h00;
            endcase
            6'h03: case (row)   // C
                4'd2: data <= 8'b00111100;
                4'd3: data <= 8'b01100110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000000;
                4'd6: data <= 8'b11000000;
                4'd7: data <= 8'b11000000;
                4'd8: data <= 8'b11000000;
                4'd9: data <= 8'b11000000;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b01100110;
                4'd12: data <= 8'b00111100;
                default: data <= 8'h00;
            endcase
            6'h04: case (row)   // D
                4'd2: data <= 8'b11111100;
                4'd3: data <= 8'b11000110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11000011;
                4'd7: data <= 8'b11000011;
                4'd8: data <= 8'b11000011;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b11000110;
                4'd12: data <= 8'b11111100;
                default: data <= 8'h00;
            endcase
            6'h05: case (row)   // E
                4'd2: data <= 8'b11111111;
                4'd3: data <= 8'b11000000;
                4'd4: data <= 8'b11000000;
                4'd5: data <= 8'b11000000;
                4'd6: data <= 8'b11111100;
                4'd7: data <= 8'b11111100;
                4'd8: data <= 8'b11000000;
                4'd9: data <= 8'b11000000;
                4'd10: data <= 8'b11000000;
                4'd11: data <= 8'b11000000;
                4'd12: data <= 8'b11111111;
                default: data <= 8'h00;
            endcase
            6'h06: case (row)   // F
                4'd2: data <= 8'b11111111;
                4'd3: data <= 8'b11000000;
                4'd4: data <= 8'b11000000;
                4'd5: data <= 8'b11000000;
                4'd6: data <= 8'b11111100;
                4'd7: data <= 8'b11111100;
                4'd8: data <= 8'b11000000;
                4'd9: data <= 8'b11000000;
                4'd10: data <= 8'b11000000;
                4'd11: data <= 8'b11000000;
                4'd12: data <= 8'b11000000;
                default: data <= 8'h00;
            endcase
            6'h07: case (row)   // G
                4'd2: data <= 8'b00111100;
                4'd3: data <= 8'b01100110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000000;
                4'd6: data <= 8'b11000000;
                4'd7: data <= 8'b11001111;
                4'd8: data <= 8'b11001111;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b01100110;
                4'd12: data <= 8'b00111100;
                default: data <= 8'h00;
            endcase
            6'h08: case (row)   // H
                4'd2: data <= 8'b11000011;
                4'd3: data <= 8'b11000011;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11111111;
                4'd7: data <= 8'b11111111;
                4'd8: data <= 8'b11000011;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b11000011;
                4'd12: data <= 8'b11000011;
                default: data <= 8'h00;
            endcase
            6'h09: case (row)   // I
                4'd2: data <= 8'b01111110;
                4'd3: data <= 8'b00011000;
                4'd4: data <= 8'b00011000;
                4'd5: data <= 8'b00011000;
                4'd6: data <= 8'b00011000;
                4'd7: data <= 8'b00011000;
                4'd8: data <= 8'b00011000;
                4'd9: data <= 8'b00011000;
                4'd10: data <= 8'b00011000;
                4'd11: data <= 8'b00011000;
                4'd12: data <= 8'b01111110;
                default: data <= 8'h00;
            endcase
            6'h0C: case (row)   // L
                4'd2: data <= 8'b11000000;
                4'd3: data <= 8'b11000000;
                4'd4: data <= 8'b11000000;
                4'd5: data <= 8'b11000000;
                4'd6: data <= 8'b11000000;
                4'd7: data <= 8'b11000000;
                4'd8: data <= 8'b11000000;
                4'd9: data <= 8'b11000000;
                4'd10: data <= 8'b11000000;
                4'd11: data <= 8'b11000000;
                4'd12: data <= 8'b11111111;
                default: data <= 8'h00;
            endcase
            6'h0D: case (row)   // M
                4'd2: data <= 8'b11000011;
                4'd3: data <= 8'b11100111;
                4'd4: data <= 8'b11111111;
                4'd5: data <= 8'b11011011;
                4'd6: data <= 8'b11000011;
                4'd7: data <= 8'b11000011;
                4'd8: data <= 8'b11000011;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b11000011;
                4'd12: data <= 8'b11000011;
                default: data <= 8'h00;
            endcase
            6'h0E: case (row)   // N
                4'd2: data <= 8'b11000011;
                4'd3: data <= 8'b11100011;
                4'd4: data <= 8'b11110011;
                4'd5: data <= 8'b11011011;
                4'd6: data <= 8'b11001111;
                4'd7: data <= 8'b11001111;
                4'd8: data <= 8'b11000111;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b11000011;
                4'd12: data <= 8'b11000011;
                default: data <= 8'h00;
            endcase
            6'h0F: case (row)   // O
                4'd2: data <= 8'b00111100;
                4'd3: data <= 8'b01100110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11000011;
                4'd7: data <= 8'b11000011;
                4'd8: data <= 8'b11000011;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b01100110;
                4'd12: data <= 8'b00111100;
                default: data <= 8'h00;
            endcase
            6'h10: case (row)   // P
                4'd2: data <= 8'b11111100;
                4'd3: data <= 8'b11000110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11000110;
                4'd7: data <= 8'b11111100;
                4'd8: data <= 8'b11000000;
                4'd9: data <= 8'b11000000;
                4'd10: data <= 8'b11000000;
                4'd11: data <= 8'b11000000;
                4'd12: data <= 8'b11000000;
                default: data <= 8'h00;
            endcase
            6'h12: case (row)   // R
                4'd2: data <= 8'b11111100;
                4'd3: data <= 8'b11000110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11000110;
                4'd7: data <= 8'b11111100;
                4'd8: data <= 8'b11011000;
                4'd9: data <= 8'b11001100;
                4'd10: data <= 8'b11000110;
                4'd11: data <= 8'b11000011;
                4'd12: data <= 8'b11000011;
                default: data <= 8'h00;
            endcase
            6'h13: case (row)   // S
                4'd2: data <= 8'b00111100;
                4'd3: data <= 8'b01100110;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000000;
                4'd6: data <= 8'b01100000;
                4'd7: data <= 8'b00111100;
                4'd8: data <= 8'b00000110;
                4'd9: data <= 8'b00000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b01100110;
                4'd12: data <= 8'b00111100;
                default: data <= 8'h00;
            endcase
            6'h14: case (row)   // T
                4'd2: data <= 8'b11111111;
                4'd3: data <= 8'b11111111;
                4'd4: data <= 8'b00011000;
                4'd5: data <= 8'b00011000;
                4'd6: data <= 8'b00011000;
                4'd7: data <= 8'b00011000;
                4'd8: data <= 8'b00011000;
                4'd9: data <= 8'b00011000;
                4'd10: data <= 8'b00011000;
                4'd11: data <= 8'b00011000;
                4'd12: data <= 8'b00011000;
                default: data <= 8'h00;
            endcase
            6'h15: case (row)   // U
                4'd2: data <= 8'b11000011;
                4'd3: data <= 8'b11000011;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11000011;
                4'd7: data <= 8'b11000011;
                4'd8: data <= 8'b11000011;
                4'd9: data <= 8'b11000011;
                4'd10: data <= 8'b11000011;
                4'd11: data <= 8'b01100110;
                4'd12: data <= 8'b00111100;
                default: data <= 8'h00;
            endcase
            6'h16: case (row)   // V 
                4'd2: data <= 8'b11000011;
                4'd3: data <= 8'b11000011;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11000011;
                4'd7: data <= 8'b01100110;
                4'd8: data <= 8'b01100110;
                4'd9: data <= 8'b01100110;
                4'd10: data <= 8'b00111100;
                4'd11: data <= 8'b00111100;
                4'd12: data <= 8'b00011000;
                default: data <= 8'h00;
            endcase
            6'h17: case (row)   // W
                4'd2: data <= 8'b11000011;
                4'd3: data <= 8'b11000011;
                4'd4: data <= 8'b11000011;
                4'd5: data <= 8'b11000011;
                4'd6: data <= 8'b11000011;
                4'd7: data <= 8'b11000011;
                4'd8: data <= 8'b11011011;
                4'd9: data <= 8'b11011011;
                4'd10: data <= 8'b11111111;
                4'd11: data <= 8'b11100111;
                4'd12: data <= 8'b11000011;
                default: data <= 8'h00;
            endcase
            6'h19: case (row)   // Y
                4'd2: data <= 8'b11000011;
                4'd3: data <= 8'b11000011;
                4'd4: data <= 8'b01100110;
                4'd5: data <= 8'b00111100;
                4'd6: data <= 8'b00011000;
                4'd7: data <= 8'b00011000;
                4'd8: data <= 8'b00011000;
                4'd9: data <= 8'b00011000;
                4'd10: data <= 8'b00011000;
                4'd11: data <= 8'b00011000;
                4'd12: data <= 8'b00011000;
                default: data <= 8'h00;
            endcase

            // custom glyphs
            6'h3E: case (row)   // checkmark
                4'd6: data <= 8'b00000011;
                4'd7: data <= 8'b00000111;
                4'd8: data <= 8'b11001110;
                4'd9: data <= 8'b11111100;
                4'd10: data <= 8'b01111000;
                4'd11: data <= 8'b00110000;
                default: data <= 8'h00;
            endcase
            6'h3F: case (row)   // x mark
                4'd3: data <= 8'b11000011;
                4'd4: data <= 8'b11100111;
                4'd5: data <= 8'b01111110;
                4'd6: data <= 8'b00111100;
                4'd7: data <= 8'b00011000;
                4'd8: data <= 8'b00111100;
                4'd9: data <= 8'b01111110;
                4'd10: data <= 8'b11100111;
                4'd11: data <= 8'b11000011;
                default: data <= 8'h00;
            endcase

            default: data <= 8'h00;
        endcase
    end

endmodule

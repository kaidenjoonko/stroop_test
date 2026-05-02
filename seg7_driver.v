// seg7_driver.v: 8-digit 7-segment display driver for the Nexys A7.

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

    //  Registered inputs
    reg [15:0] score_r, time_r;
    always @(posedge clk) begin
        if (reset) begin
            score_r <= 16'd0;
            time_r  <= 16'd0;
        end else begin
            score_r <= score_val;
            time_r  <= time_val;
        end
    end

    //  registered BCD digits
    reg [3:0] s_d0, s_d1, s_d2, s_d3;
    reg [3:0] t_d0, t_d1, t_d2, t_d3;

    always @(posedge clk) begin
        if (reset) begin
            s_d0 <= 4'd0; s_d1 <= 4'd0; s_d2 <= 4'd0; s_d3 <= 4'd0;
            t_d0 <= 4'd0; t_d1 <= 4'd0; t_d2 <= 4'd0; t_d3 <= 4'd0;
        end else begin
            s_d0 <=  score_r        % 10;
            s_d1 <= (score_r / 10)  % 10;
            s_d2 <= (score_r / 100) % 10;
            s_d3 <= (score_r / 1000)% 10;
            t_d0 <=  time_r         % 10;
            t_d1 <= (time_r / 10)   % 10;
            t_d2 <= (time_r / 100)  % 10;
            t_d3 <= (time_r / 1000) % 10;
        end
    end

    //  refresh counter
    reg [17:0] refresh_cnt;
    always @(posedge clk) begin
        if (reset) refresh_cnt <= 18'd0;
        else       refresh_cnt <= refresh_cnt + 1'b1;
    end
    wire [2:0] digit_sel = refresh_cnt[17:15];

    //  anode + digit MUX 
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

    // hex/BCD digit -> segment encoding
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

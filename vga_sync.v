// vga_sync.v: VGA 640x480 @ 60Hz timing controller

`timescale 1ns / 1ps

module vga_sync (
    input  wire        clk_100mhz,   // 100 MHz system clock
    input  wire        reset,         // synchronous reset, active high
    output wire        hsync,         // VGA horizontal sync (active low)
    output wire        vsync,         // VGA vertical sync   (active low)
    output wire        video_on,      // 1 when (hcount<640) && (vcount<480)
    output wire        p_tick,        // 25 MHz pixel-rate enable pulse
    output wire [9:0]  hcount,        // 0..799
    output wire [9:0]  vcount         // 0..524
);

    // horizontal/vertical timing constants
    localparam H_DISPLAY     = 640;
    localparam H_FRONT_PORCH = 16;
    localparam H_SYNC_PULSE  = 96;
    localparam H_BACK_PORCH  = 48;
    localparam H_TOTAL       = 800;   // 640+16+96+48

    localparam V_DISPLAY     = 480;
    localparam V_FRONT_PORCH = 10;
    localparam V_SYNC_PULSE  = 2;
    localparam V_BACK_PORCH  = 33;
    localparam V_TOTAL       = 525;

    //  100 MHz -> 25 MHz pixel-tick
    reg [1:0] pix_div = 2'b00;
    always @(posedge clk_100mhz) begin
        if (reset) pix_div <= 2'b00;
        else       pix_div <= pix_div + 1'b1;
    end
    assign p_tick = (pix_div == 2'b11);

    // horizontal counter
    reg [9:0] h_cnt = 10'd0;
    always @(posedge clk_100mhz) begin
        if (reset)
            h_cnt <= 10'd0;
        else if (p_tick) begin
            if (h_cnt == H_TOTAL-1) h_cnt <= 10'd0;
            else                    h_cnt <= h_cnt + 1'b1;
        end
    end

    // vertical counter
    reg [9:0] v_cnt = 10'd0;
    always @(posedge clk_100mhz) begin
        if (reset)
            v_cnt <= 10'd0;
        else if (p_tick && (h_cnt == H_TOTAL-1)) begin
            if (v_cnt == V_TOTAL-1) v_cnt <= 10'd0;
            else                    v_cnt <= v_cnt + 1'b1;
        end
    end

    //  sync pulse generation (active LOW)
    wire hsync_active = (h_cnt >= (H_DISPLAY + H_FRONT_PORCH)) &&
                        (h_cnt <  (H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE));
    wire vsync_active = (v_cnt >= (V_DISPLAY + V_FRONT_PORCH)) &&
                        (v_cnt <  (V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE));

    assign hsync    = ~hsync_active;
    assign vsync    = ~vsync_active;
    assign video_on = (h_cnt < H_DISPLAY) && (v_cnt < V_DISPLAY);
    assign hcount   = h_cnt;
    assign vcount   = v_cnt;

endmodule

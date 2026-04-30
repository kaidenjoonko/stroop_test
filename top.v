//==============================================================================
// top.v
//------------------------------------------------------------------------------
// Top-level integration module for the Stroop Effect Game on the Nexys A7.
//
// Pin summary (see nexys_a7.xdc for the constraints):
//   clk       : 100 MHz crystal (E3)
//   reset     : SW0 (active high)  - synchronous reset to all submodules
//   sw[1:0]   : two slide switches  -- sw[1]=adaptive mode, sw[0]=reserved
//   btnc      : center pushbutton (start/confirm)
//   btnu      : up    pushbutton (RED)
//   btnr      : right pushbutton (GREEN)
//   btnd      : down  pushbutton (BLUE)
//   btnl      : left  pushbutton (YELLOW)
//   vga_r,g,b : 4 bits each, 12-bit color out to VGA connector
//   vga_hs    : horizontal sync
//   vga_vs    : vertical sync
//   seg[6:0]  : 7-segment cathodes (active LOW)
//   dp        : decimal point (held high = off)
//   an[7:0]   : digit anodes (active LOW, multiplexed)
//==============================================================================

`timescale 1ns / 1ps

module top (
    input  wire        clk,        // 100 MHz
    input  wire        reset,      // SW0
    input  wire [1:0]  sw,         // SW1 (mode), SW2 (reserved)
    input  wire        btnc,
    input  wire        btnu,
    input  wire        btnr,
    input  wire        btnd,
    input  wire        btnl,

    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs,

    output wire [6:0]  seg,
    output wire        dp,
    output wire [7:0]  an
);

    // ============================================================
    // 1. Synchronize external reset
    // ============================================================
    reg rst_s0, rst_s1;
    always @(posedge clk) begin
        rst_s0 <= reset;
        rst_s1 <= rst_s0;
    end
    wire rst = rst_s1;

    // Two-flop synchronizer for the slide switches as well -- they're
    // mechanical, asynchronous, and feed combinational paths in the FSM.
    reg [1:0] sw_s0, sw_s1;
    always @(posedge clk) begin
        sw_s0 <= sw;
        sw_s1 <= sw_s0;
    end
    wire [1:0] sw_sync = sw_s1;

    // ============================================================
    // 2. Debounce + edge-detect all five pushbuttons
    // ============================================================
    wire btnc_stable, btnc_p;
    wire btnu_stable, btnu_p;
    wire btnr_stable, btnr_p;
    wire btnd_stable, btnd_p;
    wire btnl_stable, btnl_p;

    debounce u_db_c (.clk(clk), .reset(rst), .btn_in(btnc), .btn_stable(btnc_stable), .btn_pulse(btnc_p));
    debounce u_db_u (.clk(clk), .reset(rst), .btn_in(btnu), .btn_stable(btnu_stable), .btn_pulse(btnu_p));
    debounce u_db_r (.clk(clk), .reset(rst), .btn_in(btnr), .btn_stable(btnr_stable), .btn_pulse(btnr_p));
    debounce u_db_d (.clk(clk), .reset(rst), .btn_in(btnd), .btn_stable(btnd_stable), .btn_pulse(btnd_p));
    debounce u_db_l (.clk(clk), .reset(rst), .btn_in(btnl), .btn_stable(btnl_stable), .btn_pulse(btnl_p));

    // ============================================================
    // 3. LFSR (free-running, sampled by FSM)
    // ============================================================
    wire        lfsr_sample;
    wire [1:0]  word_idx, color_idx;
    lfsr u_lfsr (
        .clk      (clk),
        .reset    (rst),
        .sample   (lfsr_sample),
        .word_idx (word_idx),
        .color_idx(color_idx)
    );

    // ============================================================
    // 4. Game FSM
    // ============================================================
    wire        st_idle, st_show, st_wait, st_correct, st_incorrect, st_score;
    wire [4:0]  round_num;
    wire [15:0] score_val, react_time_ms;
    wire [1:0]  cur_word, cur_color;
    wire        results_ready;
    wire [15:0] best_rt, worst_rt, avg_rt;
    wire [15:0] cur_timeout_ms, min_timeout_ms;
    wire        adaptive_mode;

    stroop_fsm u_fsm (
        .clk           (clk),
        .reset         (rst),
        .btnc_p        (btnc_p),
        .btnu_p        (btnu_p),
        .btnr_p        (btnr_p),
        .btnd_p        (btnd_p),
        .btnl_p        (btnl_p),
        .sw            (sw_sync),
        .lfsr_sample   (lfsr_sample),
        .word_idx      (word_idx),
        .color_idx     (color_idx),
        .st_idle       (st_idle),
        .st_show       (st_show),
        .st_wait       (st_wait),
        .st_correct    (st_correct),
        .st_incorrect  (st_incorrect),
        .st_score      (st_score),
        .round_num     (round_num),
        .score_val     (score_val),
        .react_time_ms (react_time_ms),
        .cur_word      (cur_word),
        .cur_color     (cur_color),
        .results_ready (results_ready),
        .best_rt       (best_rt),
        .worst_rt      (worst_rt),
        .avg_rt        (avg_rt),
        .cur_timeout_ms(cur_timeout_ms),
        .min_timeout_ms(min_timeout_ms),
        .adaptive_mode (adaptive_mode)
    );

    // ============================================================
    // 5. VGA timing generator
    // ============================================================
    wire        video_on, p_tick;
    wire [9:0]  hcount, vcount;

    vga_sync u_vga (
        .clk_100mhz (clk),
        .reset      (rst),
        .hsync      (vga_hs),
        .vsync      (vga_vs),
        .video_on   (video_on),
        .p_tick     (p_tick),
        .hcount     (hcount),
        .vcount     (vcount)
    );

    // ============================================================
    // 6. Pixel generator (renders the active screen)
    // ============================================================
    wire [11:0] rgb;

    pixel_gen u_pix (
        .clk           (clk),
        .reset         (rst),
        .video_on      (video_on),
        .hcount        (hcount),
        .vcount        (vcount),
        .st_idle       (st_idle),
        .st_show       (st_show),
        .st_wait       (st_wait),
        .st_correct    (st_correct),
        .st_incorrect  (st_incorrect),
        .st_score      (st_score),
        .cur_word      (cur_word),
        .cur_color     (cur_color),
        .round_num     (round_num),
        .score_val     (score_val),
        .react_time_ms (react_time_ms),
        .results_ready (results_ready),
        .best_rt       (best_rt),
        .worst_rt      (worst_rt),
        .avg_rt        (avg_rt),
        .cur_timeout_ms(cur_timeout_ms),
        .min_timeout_ms(min_timeout_ms),
        .adaptive_mode (adaptive_mode),
        .rgb           (rgb)
    );

    // Map 12-bit RGB to the three 4-bit VGA buses
    assign vga_r = rgb[11:8];
    assign vga_g = rgb[7:4];
    assign vga_b = rgb[3:0];

    // ============================================================
    // 7. 7-segment display driver
    // ============================================================
    seg7_driver u_seg7 (
        .clk        (clk),
        .reset      (rst),
        .score_val  (score_val),
        .time_val   (react_time_ms),
        .seg        (seg),
        .dp         (dp),
        .an         (an)
    );

endmodule

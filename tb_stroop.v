// tb_stroop.v: combined testbench for the stroop test

`timescale 1ns / 1ps

module tb_stroop;

    //  clock / reset 
    reg clk = 0;
    always #5 clk = ~clk;     // 100 MHz

    reg reset = 1;
    reg btnc=0, btnu=0, btnr=0, btnd=0, btnl=0;
    reg [1:0] sw = 2'b00;     // sw[1]=0 -> classic mode (matches the
                              // original 12 assertions); sw[0] reserved.

    //  DUT instances 
    wire        lfsr_sample;
    wire [1:0]  word_idx, color_idx;

    lfsr u_lfsr (
        .clk(clk), .reset(reset),
        .sample(lfsr_sample),
        .word_idx(word_idx), .color_idx(color_idx)
    );

    wire st_idle, st_show, st_wait, st_correct, st_incorrect, st_score;
    wire [4:0]  round_num;
    wire [15:0] score_val, react_time_ms;
    wire [1:0]  cur_word, cur_color;
    wire        results_ready;
    //  stat outputs
    wire [15:0] best_rt, worst_rt, avg_rt;
    wire [15:0] cur_timeout_ms, min_timeout_ms;
    wire        adaptive_mode;

    stroop_fsm dut (
        .clk(clk), .reset(reset),
        .btnc_p(btnc), .btnu_p(btnu), .btnr_p(btnr),
        .btnd_p(btnd), .btnl_p(btnl),
        .sw(sw),
        .lfsr_sample(lfsr_sample),
        .word_idx(word_idx), .color_idx(color_idx),
        .st_idle(st_idle), .st_show(st_show), .st_wait(st_wait),
        .st_correct(st_correct), .st_incorrect(st_incorrect), .st_score(st_score),
        .round_num(round_num), .score_val(score_val),
        .react_time_ms(react_time_ms),
        .cur_word(cur_word), .cur_color(cur_color),
        .results_ready(results_ready),
        .best_rt(best_rt), .worst_rt(worst_rt), .avg_rt(avg_rt),
        .cur_timeout_ms(cur_timeout_ms), .min_timeout_ms(min_timeout_ms),
        .adaptive_mode(adaptive_mode)
    );

    //  Helpers 
    integer pass = 0;
    integer fail = 0;
    task check;
        input cond;
        input [255:0] msg;
        begin
            if (cond) begin pass = pass + 1; $display("PASS: %0s", msg); end
            else      begin fail = fail + 1; $display("FAIL: %0s", msg); end
        end
    endtask

    task pulse_btnc;
        begin
            @(posedge clk) btnc <= 1;
            @(posedge clk) btnc <= 0;
        end
    endtask

    task press_color;
        input [1:0] c;
        begin
            @(posedge clk);
            case (c)
                2'd0: btnu <= 1;
                2'd1: btnr <= 1;
                2'd2: btnd <= 1;
                2'd3: btnl <= 1;
            endcase
            @(posedge clk);
            btnu <= 0; btnr <= 0; btnd <= 0; btnl <= 0;
        end
    endtask

    // Run one full trial with the chosen outcome:
    //   outcome=0 -> answer correctly,
    //   outcome=1 -> answer wrong,
    //   outcome=2 -> let it time out (3 s)
    task run_trial;
        input [1:0] outcome;
        reg [1:0] wrong_color;
        begin
            // Give SHOW_WORD entry one clock so the LFSR can be sampled and cur_word/cur_color are updated, THEN fast-forward through the 500 ms timer
            wait (st_show);
            @(posedge clk);
            @(posedge clk);
            force dut.tmr = 29'd49_999_999;
            @(posedge clk);
            release dut.tmr;
            wait (st_wait);
            @(posedge clk);

            case (outcome)
                2'd0: press_color(cur_color);
                2'd1: begin
                    // pick any color != cur_color
                    wrong_color = (cur_color == 2'd0) ? 2'd1 : 2'd0;
                    press_color(wrong_color);
                end
                2'd2: begin
                    // force the 3 s timeout
                    force dut.tmr = 29'd299_999_999;
                    @(posedge clk);
                    release dut.tmr;
                end
            endcase

            // skip the 1 s feedback timer
            wait (st_correct || st_incorrect);
            @(posedge clk);
            @(posedge clk);
            force dut.tmr = 29'd99_999_999;
            @(posedge clk);
            release dut.tmr;
            wait (st_score);
            @(posedge clk);
        end
    endtask

    //  test sequence 
    integer i;
    initial begin
        repeat (5) @(posedge clk);
        reset = 0;
        repeat (3) @(posedge clk);

        check(st_idle, "Reset -> IDLE");

        // 1) Start a session
        pulse_btnc;
        @(posedge clk);
        check(st_show, "BTNC: IDLE -> SHOW_WORD");

        // 2) LFSR mismatch in SHOW_WORD
        check(cur_word != cur_color, "LFSR word != color");

        // 3) Correct answer -> CORRECT, score=1
        @(posedge clk);  // let SHOW_WORD entry latch the LFSR
        @(posedge clk);
        force dut.tmr = 29'd49_999_999;
        @(posedge clk);
        release dut.tmr;
        wait (st_wait);
        @(posedge clk);
        press_color(cur_color);
        @(posedge clk);
        check(st_correct, "Correct btn -> CORRECT");
        @(posedge clk);
        check(score_val == 1, "Score == 1 after correct");

        // 4) Continue, then deliberately answer wrong on the next trial
        @(posedge clk);
        @(posedge clk);
        force dut.tmr = 29'd99_999_999;
        @(posedge clk); release dut.tmr;
        wait (st_score);
        @(posedge clk);
        wait (st_show);
        @(posedge clk);
        @(posedge clk);
        force dut.tmr = 29'd49_999_999;
        @(posedge clk); release dut.tmr;
        wait (st_wait); @(posedge clk);
        press_color((cur_color == 2'd0) ? 2'd1 : 2'd0);
        @(posedge clk);
        check(st_incorrect, "Wrong btn -> INCORRECT");
        @(posedge clk);
        check(score_val == 1, "Score unchanged after wrong");

        // 5) Run remaining trials until 20 are complete
        @(posedge clk);
        @(posedge clk);
        force dut.tmr = 29'd99_999_999;
        @(posedge clk); release dut.tmr;
        wait (st_score);
        @(posedge clk);

        // round 0 and 1 complete Run 18 more.
        for (i = 0; i < 18; i = i + 1) begin
            wait (st_show);
            run_trial(2'd0);  // all correct from here
            $display("  trial %0d done: score=%0d round=%0d", i, score_val, round_num);
        end

        // after round 19's SCORE state, the FSM should head back to IDLE with results_ready=1
        wait (st_idle);
        check(results_ready, "After 20 rounds: results_ready=1");
        $display("Final score = %0d (round_num=%0d)", score_val, round_num);
        check(score_val == 19, "Final score = 19 (1 wrong out of 20)");

        // 6) Pressing BTNC again should clear and restart
        pulse_btnc;
        @(posedge clk);
        check(!results_ready,    "BTNC restart clears results_ready");
        check(score_val == 0,    "Score reset to 0");
        check(round_num == 0,    "Round reset to 0");

        $display("==============================");
        $display(" %0d passed,  %0d failed", pass, fail);
        $display("==============================");
        $finish;
    end

    // Watchdog: kill the sim if it ever runs away
    initial begin
        #2_000_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

// stroop_fsm.v: six-state Moore FSM, ONE-HOT encoded, for the Stroop reaction-time game


`timescale 1ns / 1ps

module stroop_fsm (
    input  wire        clk,
    input  wire        reset,
    // Debounced single-cycle button pulses
    input  wire        btnc_p,         // start/confirm
    input  wire        btnu_p,         // RED
    input  wire        btnr_p,         // GREEN
    input  wire        btnd_p,         // BLUE
    input  wire        btnl_p,         // YELLOW
    // Mode select switch (sw[1] = adaptive when high; sw[0] reserved)
    input  wire [1:0]  sw,
    // LFSR interface
    output reg         lfsr_sample,    // 1-cycle pulse to latch new pair
    input  wire [1:0]  word_idx,
    input  wire [1:0]  color_idx,
    // FSM state observation (one-hot, exposed for pixel_gen)
    output wire        st_idle,
    output wire        st_show,
    output wire        st_wait,
    output wire        st_correct,
    output wire        st_incorrect,
    output wire        st_score,
    // Round/score tracking
    output reg  [4:0]  round_num,      // 0..30 (classic ends at 20, adaptive at 30)
    output reg  [15:0] score_val,
    output reg  [15:0] react_time_ms,  // reaction time of last trial in ms
    // Latched word/color shown to pixel_gen during SHOW_WORD/WAIT/feedback
    output reg  [1:0]  cur_word,
    output reg  [1:0]  cur_color,
    // Results-flag: stays high in IDLE *after* a session has completed
    output reg         results_ready,
    // ----- New: per-session reaction-time statistics -----
    output reg  [15:0] best_rt,        // min RT, 16'hFFFF = no data yet
    output reg  [15:0] worst_rt,       // max RT
    output reg  [15:0] avg_rt,         // total_rt / score_val (computed at EOS)
    // ----- New: adaptive-mode visibility -----
    output reg  [15:0] cur_timeout_ms, // current timeout displayed on trial screen
    output reg  [15:0] min_timeout_ms, // lowest timeout reached (adaptive only)
    output wire        adaptive_mode   // sw[1] passthrough for pixel_gen
);

    // ---------------- Mode passthrough ----------------
    assign adaptive_mode = sw[1];

    // ---------------- One-hot state encoding ----------------
    localparam IDLE       = 6'b000001;
    localparam SHOW_WORD  = 6'b000010;
    localparam WAIT_INPUT = 6'b000100;
    localparam CORRECT    = 6'b001000;
    localparam INCORRECT  = 6'b010000;
    localparam SCORE      = 6'b100000;

    reg [5:0] state, next_state;

    assign st_idle      = state[0];
    assign st_show      = state[1];
    assign st_wait      = state[2];
    assign st_correct   = state[3];
    assign st_incorrect = state[4];
    assign st_score     = state[5];

    // ---------------- Timing constants ----------------
    // Per Feature 5: SHOW_WORD shortened to 300 ms, feedback to 600 ms.
    localparam [26:0] T_SHOW   = 27'd30_000_000;   // 300 ms
    localparam [26:0] T_FB     = 27'd60_000_000;   // 600 ms
    localparam [28:0] T_INIT   = 29'd300_000_000;  // 3000 ms initial timeout
    localparam [28:0] T_STEP   = 29'd20_000_000;   // 200 ms adaptive step
    localparam [28:0] T_FLOOR  = 29'd50_000_000;   // 500 ms minimum
    localparam [28:0] T_CAP    = 29'd500_000_000;  // 5000 ms maximum
    localparam [16:0] MS_TICK  = 17'd100_000;      // 100,000 cycles = 1 ms

    // Companion millisecond constants for cur_timeout_ms maintenance.
    localparam [15:0] T_INIT_MS  = 16'd3000;
    localparam [15:0] T_STEP_MS  = 16'd200;
    localparam [15:0] T_FLOOR_MS = 16'd500;
    localparam [15:0] T_CAP_MS   = 16'd5000;

    // End-of-session round thresholds (classic = 20 trials, adaptive = 30).
    localparam [4:0] R_CLASSIC = 5'd19;
    localparam [4:0] R_ADAPT   = 5'd29;

    // ---------------- Adaptive-mode current timeout ----------------
    // cur_timeout_cycles is the value tmr is compared against in WAIT_INPUT.
    // Both classic and adaptive mode start at 3 s; only adaptive mutates.
    reg [28:0] cur_timeout_cycles;

    // ---------------- Shared timer + ms counter ----------------
    reg [28:0] tmr;          // 29 bits to cover up to 5 s window
    reg [16:0] ms_div;        // divides 100 MHz down to 1 kHz tick
    reg        ms_pulse;      // 1-cycle pulse every 1 ms while in WAIT_INPUT

    wire state_change = (state != next_state);

    always @(posedge clk) begin
        if (reset) begin
            tmr      <= 29'd0;
            ms_div   <= 17'd0;
            ms_pulse <= 1'b0;
        end else begin
            ms_pulse <= 1'b0;
            if (state_change) begin
                tmr    <= 29'd0;
                ms_div <= 17'd0;
            end else begin
                tmr <= tmr + 1'b1;
                if (state == WAIT_INPUT) begin
                    if (ms_div == MS_TICK-1) begin
                        ms_div   <= 17'd0;
                        ms_pulse <= 1'b1;
                    end else begin
                        ms_div <= ms_div + 1'b1;
                    end
                end
            end
        end
    end

    // ---------------- Color-button-pressed decoder ----------------
    // Player's chosen color when any color button fires. Encoding matches
    // word_idx / color_idx (0=RED,1=GREEN,2=BLUE,3=YELLOW).
    wire color_pressed = btnu_p | btnr_p | btnd_p | btnl_p;
    wire [1:0] chosen_color = btnu_p ? 2'd0 :
                              btnr_p ? 2'd1 :
                              btnd_p ? 2'd2 :
                              btnl_p ? 2'd3 : 2'd0;

    // ---------------- Streak counters (used by adaptive mode) ----------------
    // streak       : running count of correct answers in a row (caps at 3, reset).
    // wrong_streak : running count of wrong answers in a row; ends adaptive game
    //                when it reaches 3.
    reg [3:0] streak;
    reg [3:0] wrong_streak;

    // ---------------- Stats accumulators ----------------
    reg [19:0] total_rt;       // 20-bit sum of correct-answer reaction times

    // ---------------- End-of-session detector (mode-dependent) ----------------
    // True when the FSM is currently in SCORE and the next trial will be the
    // last (i.e. we should head to IDLE with results_ready). The decision is
    // taken using the round_num / wrong_streak values entering SCORE.
    wire end_of_session = sw[1]
        ? ((wrong_streak >= 4'd3) || (round_num >= R_ADAPT))   // adaptive
        : (round_num >= R_CLASSIC);                            // classic

    // ---------------- State register ----------------
    always @(posedge clk) begin
        if (reset) state <= IDLE;
        else       state <= next_state;
    end

    // ---------------- Next-state logic (combinational) ----------------
    always @(*) begin
        next_state = state;     // hold by default
        case (state)
            IDLE: begin
                if (btnc_p) next_state = SHOW_WORD;
            end
            SHOW_WORD: begin
                if (tmr >= T_SHOW-1) next_state = WAIT_INPUT;
            end
            WAIT_INPUT: begin
                if (color_pressed) begin
                    if (chosen_color == cur_color) next_state = CORRECT;
                    else                            next_state = INCORRECT;
                end else if (tmr >= cur_timeout_cycles - 1) begin
                    next_state = INCORRECT;     // timeout
                end
            end
            CORRECT:   if (tmr >= T_FB-1) next_state = SCORE;
            INCORRECT: if (tmr >= T_FB-1) next_state = SCORE;
            SCORE: begin
                if (end_of_session) next_state = IDLE;
                else                next_state = SHOW_WORD;
            end
            default: next_state = IDLE;
        endcase
    end

    // ---------------- Datapath: round, score, RT, latched pair, stats, timeout ----------------
    // We collect every register update inside one always block so reset and
    // session-restart logic stay together. Each "case" branch handles only the
    // updates that fire while in that state.
    always @(posedge clk) begin
        if (reset) begin
            round_num          <= 5'd0;
            score_val          <= 16'd0;
            react_time_ms      <= 16'd0;
            cur_word           <= 2'd0;
            cur_color          <= 2'd2;
            lfsr_sample        <= 1'b0;
            results_ready      <= 1'b0;
            best_rt            <= 16'hFFFF;
            worst_rt           <= 16'd0;
            total_rt           <= 20'd0;
            streak             <= 4'd0;
            wrong_streak       <= 4'd0;
            cur_timeout_cycles <= T_INIT;
            cur_timeout_ms     <= T_INIT_MS;
            min_timeout_ms     <= T_INIT_MS;
        end else begin
            lfsr_sample <= 1'b0;   // default: deassert

            case (state)
                IDLE: begin
                    if (btnc_p) begin
                        // Begin a new session -> clear all per-session state.
                        round_num          <= 5'd0;
                        score_val          <= 16'd0;
                        react_time_ms      <= 16'd0;
                        results_ready      <= 1'b0;
                        best_rt            <= 16'hFFFF;
                        worst_rt           <= 16'd0;
                        total_rt           <= 20'd0;
                        streak             <= 4'd0;
                        wrong_streak       <= 4'd0;
                        cur_timeout_cycles <= T_INIT;
                        cur_timeout_ms     <= T_INIT_MS;
                        min_timeout_ms     <= T_INIT_MS;
                    end
                end

                SHOW_WORD: begin
                    // Sample LFSR exactly once on entry (tmr just got cleared).
                    if (tmr == 29'd0) begin
                        lfsr_sample <= 1'b1;
                        cur_word    <= word_idx;
                        cur_color   <= color_idx;
                    end
                end

                WAIT_INPUT: begin
                    // Tick reaction-time counter every 1 ms, clearing on entry.
                    // The cap at 5000 ms protects against overflow but doesn't
                    // bound the visible value: the timeout edge in next_state
                    // will fire first.
                    if (tmr == 29'd0) begin
                        react_time_ms <= 16'd0;
                    end else if (ms_pulse && react_time_ms < T_CAP_MS) begin
                        react_time_ms <= react_time_ms + 1'b1;
                    end
                end

                CORRECT: begin
                    // Bump score and update stats once on entry.
                    if (tmr == 29'd0) begin
                        score_val <= score_val + 1'b1;

                        // best/worst/total update (correct answers only)
                        if (react_time_ms < best_rt)  best_rt  <= react_time_ms;
                        if (react_time_ms > worst_rt) worst_rt <= react_time_ms;
                        total_rt <= total_rt + {4'd0, react_time_ms};

                        // Streak bookkeeping
                        wrong_streak <= 4'd0;

                        if (sw[1]) begin
                            // Adaptive mode: 3 in a row -> shrink timeout.
                            // streak counts the *prior* run of correct answers,
                            // so testing == 2 means this is the 3rd correct.
                            if (streak == 4'd2) begin
                                streak <= 4'd0;
                                if (cur_timeout_cycles > T_FLOOR + T_STEP) begin
                                    cur_timeout_cycles <= cur_timeout_cycles - T_STEP;
                                    cur_timeout_ms     <= cur_timeout_ms - T_STEP_MS;
                                    if ((cur_timeout_ms - T_STEP_MS) < min_timeout_ms)
                                        min_timeout_ms <= cur_timeout_ms - T_STEP_MS;
                                end else begin
                                    cur_timeout_cycles <= T_FLOOR;
                                    cur_timeout_ms     <= T_FLOOR_MS;
                                    if (T_FLOOR_MS < min_timeout_ms)
                                        min_timeout_ms <= T_FLOOR_MS;
                                end
                            end else begin
                                streak <= streak + 1'b1;
                            end
                        end
                    end
                end

                INCORRECT: begin
                    // Update streaks and (in adaptive mode) bump timeout.
                    if (tmr == 29'd0) begin
                        streak       <= 4'd0;
                        wrong_streak <= wrong_streak + 1'b1;
                        if (sw[1]) begin
                            if (cur_timeout_cycles + T_STEP <= T_CAP) begin
                                cur_timeout_cycles <= cur_timeout_cycles + T_STEP;
                                cur_timeout_ms     <= cur_timeout_ms + T_STEP_MS;
                            end else begin
                                cur_timeout_cycles <= T_CAP;
                                cur_timeout_ms     <= T_CAP_MS;
                            end
                        end
                    end
                end

                SCORE: begin
                    // Bookkeeping at end of trial: increment round counter.
                    // If end_of_session is true, head to IDLE with
                    // results_ready set (visible on the next render frame).
                    if (tmr == 29'd0) begin
                        round_num <= round_num + 1'b1;
                        if (end_of_session) results_ready <= 1'b1;
                    end
                end

                default: ;
            endcase
        end
    end

    // ===========================================================================
    // Sequential 21-cycle restoring divider for avg_rt = total_rt / score_val.
    // Triggered for one cycle when SCORE -> IDLE (end of session, score_val>0).
    // total_rt is at most 30*5000 = 150_000 (fits in 18 bits), so 20 div steps
    // are sufficient. We use 21 for a small safety margin, finishing many
    // millions of cycles before the user can press BTNC again.
    //
    // The output flop avg_rt is held thereafter until the next reset/BTNC.
    // ===========================================================================
    wire div_start = (state == SCORE) && (next_state == IDLE) && (score_val != 16'd0);

    reg [19:0] div_dvd;       // shifting dividend
    reg [19:0] div_rem;       // running remainder
    reg [19:0] div_quo;       // running quotient (only low 16 bits ever used)
    reg [4:0]  div_step;
    reg        div_busy;

    // Combinational restoring-division step on the captured operands.
    wire [19:0] div_shifted = {div_rem[18:0], div_dvd[19]};
    wire [19:0] div_divisor = {4'd0, score_val};
    wire        div_ge      = (div_shifted >= div_divisor);

    always @(posedge clk) begin
        if (reset) begin
            div_dvd  <= 20'd0;
            div_rem  <= 20'd0;
            div_quo  <= 20'd0;
            div_step <= 5'd0;
            div_busy <= 1'b0;
            avg_rt   <= 16'd0;
        end else if (state == IDLE && btnc_p) begin
            // Clear divider state on session restart so a stale result from
            // the previous session can't sneak onto the next results screen.
            div_busy <= 1'b0;
            avg_rt   <= 16'd0;
        end else if (div_start) begin
            div_dvd  <= total_rt;
            div_rem  <= 20'd0;
            div_quo  <= 20'd0;
            div_step <= 5'd20;
            div_busy <= 1'b1;
        end else if (div_busy) begin
            if (div_step == 5'd0) begin
                avg_rt   <= div_quo[15:0];
                div_busy <= 1'b0;
            end else begin
                if (div_ge) begin
                    div_rem <= div_shifted - div_divisor;
                    div_quo <= {div_quo[18:0], 1'b1};
                end else begin
                    div_rem <= div_shifted;
                    div_quo <= {div_quo[18:0], 1'b0};
                end
                div_dvd  <= {div_dvd[18:0], 1'b0};
                div_step <= div_step - 1'b1;
            end
        end
    end

endmodule

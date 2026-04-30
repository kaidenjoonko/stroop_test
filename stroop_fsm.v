//==============================================================================
// stroop_fsm.v
//------------------------------------------------------------------------------
// Six-state Moore FSM, ONE-HOT encoded, for the Stroop reaction-time game.
//
// States:
//   IDLE      : Title screen. Wait for BTNC. Score, round, timers all reset.
//   SHOW_WORD : Display the word for 500 ms while LFSR is sampled (once at
//               state entry). VGA renders the word in the mismatched ink color.
//   WAIT_INPUT: Up to 3 s. Reaction-time counter ticks every ms. As soon as
//               any color button is pressed, decide CORRECT vs INCORRECT.
//               If 3 s elapse with no press, treat as INCORRECT.
//   CORRECT   : Flash green check for 1 s. Increment score. Latch reaction time.
//   INCORRECT : Flash red X for 1 s. No score change.
//   SCORE     : One-cycle housekeeping state: bump round counter, then go
//               back to SHOW_WORD if round<20, else back to IDLE (results).
//
// Timing constants (all derived from 100 MHz clk):
//   1 ms tick = 100,000 cycles
//   500 ms    = 50,000,000 cycles
//   3 s       = 300,000,000 cycles  -> needs 29-bit counter
//   1 s       = 100,000,000 cycles
//
// The FSM uses a single shared counter (`tmr`) that's reset on each state
// entry and increments every clock cycle while in that state. The reaction-
// time output is in milliseconds (max 3000) and is latched when the player
// presses a button (or saturates to 3000 on timeout).
//
// Button-to-color mapping (matches problem statement):
//   BTNU -> RED    (color 0)
//   BTNR -> GREEN  (color 1)
//   BTND -> BLUE   (color 2)
//   BTNL -> YELLOW (color 3)
//==============================================================================

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
    output reg  [4:0]  round_num,      // 0..20
    output reg  [15:0] score_val,
    output reg  [15:0] react_time_ms,  // reaction time of last trial in ms
    // Latched word/color shown to pixel_gen during SHOW_WORD/WAIT/feedback
    output reg  [1:0]  cur_word,
    output reg  [1:0]  cur_color,
    // Results-flag: stays high in IDLE *after* a 20-round session has completed
    output reg         results_ready
);

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
    localparam [26:0] T_500MS = 27'd50_000_000;
    localparam [28:0] T_3S    = 29'd300_000_000;
    localparam [26:0] T_1S    = 27'd100_000_000;
    localparam [16:0] MS_TICK = 17'd100_000;     // 100,000 cycles = 1 ms

    // ---------------- Shared timer + ms counter ----------------
    reg [28:0] tmr;          // 29 bits to cover the 3 s window
    reg [16:0] ms_div;        // divides 100 MHz down to 1 kHz tick
    reg        ms_pulse;      // 1-cycle pulse every 1 ms while in WAIT_INPUT

    // tmr clear happens whenever we enter a new state. The next_state logic
    // below uses tmr against the relevant constant.
    wire state_change = (state != next_state);

    always @(posedge clk) begin
        if (reset) begin
            tmr      <= 29'd0;
            ms_div   <= 17'd0;
            ms_pulse <= 1'b0;
        end else begin
            // default
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
                if (tmr >= T_500MS-1) next_state = WAIT_INPUT;
            end
            WAIT_INPUT: begin
                if (color_pressed) begin
                    if (chosen_color == cur_color) next_state = CORRECT;
                    else                            next_state = INCORRECT;
                end else if (tmr >= T_3S-1) begin
                    next_state = INCORRECT;     // timeout
                end
            end
            CORRECT: begin
                if (tmr >= T_1S-1) next_state = SCORE;
            end
            INCORRECT: begin
                if (tmr >= T_1S-1) next_state = SCORE;
            end
            SCORE: begin
                // single-cycle bookkeeping; round_num is bumped in the
                // sequential block below at the same instant.
                if (round_num >= 5'd19) next_state = IDLE;       // results
                else                    next_state = SHOW_WORD;
            end
            default: next_state = IDLE;
        endcase
    end

    // ---------------- Datapath: round, score, reaction time, latched pair ----------------
    always @(posedge clk) begin
        if (reset) begin
            round_num     <= 5'd0;
            score_val     <= 16'd0;
            react_time_ms <= 16'd0;
            cur_word      <= 2'd0;
            cur_color     <= 2'd2;
            lfsr_sample   <= 1'b0;
            results_ready <= 1'b0;
        end else begin
            lfsr_sample <= 1'b0;   // default: deassert

            case (state)
                IDLE: begin
                    // BTNC pressed -> begin a new session (clear stats, drop
                    // results_ready since we've moved past the results screen).
                    if (btnc_p) begin
                        round_num     <= 5'd0;
                        score_val     <= 16'd0;
                        react_time_ms <= 16'd0;
                        results_ready <= 1'b0;
                    end
                end

                SHOW_WORD: begin
                    // Sample LFSR exactly once on entry. We detect "entry" by
                    // checking that the timer is at zero (i.e. just reset by
                    // the state-change detector).
                    if (tmr == 29'd0) begin
                        lfsr_sample <= 1'b1;
                        cur_word    <= word_idx;
                        cur_color   <= color_idx;
                    end
                end

                WAIT_INPUT: begin
                    // Tick reaction-time counter every 1 ms, clearing on entry.
                    if (tmr == 29'd0) begin
                        react_time_ms <= 16'd0;
                    end else if (ms_pulse && react_time_ms < 16'd3000) begin
                        react_time_ms <= react_time_ms + 1'b1;
                    end
                end

                CORRECT: begin
                    // Bump score exactly once on entry to CORRECT.
                    if (tmr == 29'd0) begin
                        score_val <= score_val + 1'b1;
                    end
                end

                INCORRECT: begin
                    // No score change. (Could log a miss here if desired.)
                end

                SCORE: begin
                    // Bookkeeping at end of trial: increment round counter.
                    // If this was round 20 (round_num goes 19 -> 20), the next
                    // state is IDLE and we set results_ready so IDLE renders
                    // the final stats screen instead of the title.
                    if (tmr == 29'd0) begin
                        if (round_num >= 5'd19) begin
                            round_num     <= 5'd20;
                            results_ready <= 1'b1;
                        end else begin
                            round_num <= round_num + 1'b1;
                        end
                    end
                end

                default: ;
            endcase
        end
    end

endmodule

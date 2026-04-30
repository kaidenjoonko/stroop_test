//==============================================================================
// debounce.v
//------------------------------------------------------------------------------
// Counter-based debouncer with a synchronizer and rising-edge detector.
//
// Strategy:
//   1) Two-flop synchronizer (metastability protection on async button input).
//   2) Saturating counter: increments while the synchronized input is high,
//      decrements while low. The "stable" output flips only when the counter
//      reaches its max or min, so transient glitches shorter than the debounce
//      period are rejected.
//   3) Rising-edge detect on the stable output produces a single-cycle pulse.
//
// At 100 MHz with COUNT_MAX = 1_000_000 we get a ~10 ms debounce window, which
// is the standard textbook value for mechanical pushbuttons.
//==============================================================================

`timescale 1ns / 1ps

module debounce #(
    parameter integer COUNT_MAX = 1_000_000   // 10 ms @ 100 MHz
)(
    input  wire clk,        // 100 MHz
    input  wire reset,
    input  wire btn_in,     // raw async button input
    output reg  btn_stable, // debounced level
    output wire btn_pulse   // 1-cycle pulse on rising edge of btn_stable
);

    // ---------------- 2-flop synchronizer ----------------
    reg sync_0, sync_1;
    always @(posedge clk) begin
        if (reset) begin
            sync_0 <= 1'b0;
            sync_1 <= 1'b0;
        end else begin
            sync_0 <= btn_in;
            sync_1 <= sync_0;
        end
    end

    // ---------------- Saturating counter ----------------
    // Width must be wide enough to hold COUNT_MAX. We size it to 20 bits which
    // covers up to ~1 million; for larger COUNT_MAX increase the width below.
    reg [19:0] cnt;
    always @(posedge clk) begin
        if (reset) begin
            cnt        <= 20'd0;
            btn_stable <= 1'b0;
        end else begin
            if (sync_1 == btn_stable) begin
                // input matches current stable level -> reset counter
                cnt <= 20'd0;
            end else begin
                // input differs -> count toward the threshold
                if (cnt == COUNT_MAX-1) begin
                    btn_stable <= sync_1;   // accept new level
                    cnt        <= 20'd0;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end

    // ---------------- Rising-edge detect ----------------
    reg btn_stable_d;
    always @(posedge clk) begin
        if (reset) btn_stable_d <= 1'b0;
        else       btn_stable_d <= btn_stable;
    end
    assign btn_pulse = btn_stable & ~btn_stable_d;

endmodule

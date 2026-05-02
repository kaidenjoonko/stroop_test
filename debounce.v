// debounce.v: counter-based debouncer with a synchronizer and rising-edge detector

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

    // 2-flop synchronizer
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

    //counter system (up to 20 points)
    reg [19:0] cnt;
    always @(posedge clk) begin
        if (reset) begin
            cnt        <= 20'd0;
            btn_stable <= 1'b0;
        end else begin
            if (sync_1 == btn_stable) begin
                //reset
                cnt <= 20'd0;
            end else begin
                if (cnt == COUNT_MAX-1) begin
                    btn_stable <= sync_1;
                    cnt        <= 20'd0;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end

    // detech rising edge
    reg btn_stable_d;
    always @(posedge clk) begin
        if (reset) btn_stable_d <= 1'b0;
        else       btn_stable_d <= btn_stable;
    end
    assign btn_pulse = btn_stable & ~btn_stable_d;

endmodule

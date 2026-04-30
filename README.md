# Stroop Effect Game — Nexys A7 (XC7A100T-CSG324-1)

A Verilog-2001 implementation of a cognitive-interference reaction-time game
for the EE354 course. The user is shown a color word (e.g. "RED") drawn in
a deliberately mismatched ink color (e.g. blue), and must press the button
matching the **ink color**, not the word. Twenty rounds are played per
session, with the score and reaction time displayed on the 7-segment.

## File layout

| File            | Role                                                            |
|-----------------|-----------------------------------------------------------------|
| `top.v`         | Top-level. Instantiates all submodules and wires the pads.      |
| `vga_sync.v`    | 640×480 @ 60 Hz timing generator (25 MHz pixel-tick from 100 MHz). |
| `font_rom.v`    | 8×16 bitmapped font ROM (subset of letters/digits + ✓ ✗).       |
| `pixel_gen.v`   | Per-state screen layout (title, trial, feedback, results).      |
| `stroop_fsm.v`  | 6-state one-hot Moore FSM driving the game.                     |
| `lfsr.v`        | 8-bit Fibonacci LFSR with mismatch-guarantee post-processing.   |
| `debounce.v`    | 10 ms counter debouncer + rising-edge detector (instantiated 5×). |
| `seg7_driver.v` | BCD conversion + 8-digit anode mux for the 7-segment display.   |
| `nexys_a7.xdc`  | Pin/clock constraints for the Digilent Nexys A7-100T.           |
| `tb_stroop.v`   | Self-checking testbench (FSM + LFSR).                           |

## Pin map (highlights)

| Signal     | Pin   | Notes                          |
|------------|-------|--------------------------------|
| `clk`      | E3    | 100 MHz crystal                |
| `reset`    | J15   | SW0, active high               |
| `btnc`     | N17   | Center, Start/Confirm          |
| `btnu`     | M18   | Up,   selects RED              |
| `btnr`     | M17   | Right, selects GREEN           |
| `btnd`     | P18   | Down,  selects BLUE            |
| `btnl`     | P17   | Left,  selects YELLOW          |
| VGA HS/VS  | B11/B12 | Active LOW (per VESA spec)   |

Full pin list is in `nexys_a7.xdc`.

## Build (Vivado)

1. **Create a new RTL project** targeting `xc7a100tcsg324-1`.
2. **Add sources**: `top.v`, `vga_sync.v`, `font_rom.v`, `pixel_gen.v`,
   `stroop_fsm.v`, `lfsr.v`, `debounce.v`, `seg7_driver.v`.
3. **Add constraints**: `nexys_a7.xdc`.
4. *(Optional)* **Add simulation source**: `tb_stroop.v`. Set it as the
   top-level for simulation.
5. Run synthesis, implementation, generate bitstream, program the board.

## Simulate (iverilog or QuestaSim)

```sh
iverilog -g2001 -o tb tb_stroop.v stroop_fsm.v lfsr.v vga_sync.v
vvp tb
```

Expected output: 12 PASS / 0 FAIL.

## State machine timing

All timing is derived from the 100 MHz system clock:

| Constant   | Cycles            | Wall-clock |
|------------|-------------------|------------|
| 1 ms tick  | 100,000           | 1 ms       |
| SHOW_WORD  | 50,000,000        | 500 ms     |
| WAIT_INPUT | up to 300,000,000 | up to 3 s  |
| CORRECT/INCORRECT | 100,000,000 | 1 s     |

The shared `tmr` register is reset on every state transition (detected by
`state != next_state`), so each state's timeout starts from zero.

## Color encoding

12-bit RGB output (4 bits per channel):

| Color  | Hex   |
|--------|-------|
| Red    | F00   |
| Green  | 2C5   |
| Blue   | 35F   |
| Yellow | FC0   |
| White  | FFF   |
| Grey   | 888   |
| Black  | 000   |

## Notes for the student

- **One-hot encoding** is used for the FSM. Vivado's synthesizer will keep
  the encoding as written because of the explicit `localparam` patterns;
  if you want to verify, look for `state_reg` in the synthesized netlist.
- **Reset** is synchronized through two flops in `top.v` before being fanned
  out to all submodules. This avoids metastability if the slide switch is
  thrown asynchronously.
- The **font ROM** only contains the letters/digits/glyphs the game
  actually uses. If you want to add new strings, update the case statements
  in `font_rom.v` for any letters not yet supported.
- The **7-segment** shows score on the left 4 digits and last-trial
  reaction time (in ms) on the right 4 digits. During IDLE both fields
  hold their last values.

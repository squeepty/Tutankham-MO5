# `src/timing.asm`

Source: [timing.asm](../../../src/timing.asm)

## Purpose

This file supplies the calibrated, hardware-independent busy wait from which
game pacing is derived. It replaced a monitor ROM timing hook that made the game
run roughly twelve times too quickly in DCMOTO.

## Algorithm and timing model

`WaitFrame` is a rectangular pair of countdown loops. `X` counts outer
iterations and `Y` counts inner iterations. Each inner pass uses `LEAY -1,Y`
and `BNE`; when it reaches zero the outer loop performs the equivalent pair on
`X`.

The constants are selected so the routine consumes a little over 20,000 cycles
on a stock 1 MHz 6809. Normal frame work is then considered alongside this
baseline to approach a 20 ms, 50 Hz cadence.

The gameplay loop calls `WaitMainLoopFrame`, documented in
[progression-runtime.asm](game/flow/progression-runtime.asm.md). That routine
uses the same calibrated idea but reduces waiting when additional active
guardians increase simulation cost. `WaitFrame` remains the compact reference
delay and a useful standalone timing primitive.

## Register contract

| Routine | Inputs | Outputs and clobbers |
| --- | --- | --- |
| `WaitFrame` | none | elapsed delay; `X`, `Y`, condition codes clobbered; `A`, `B`, `U` untouched |

No memory state changes and no ROM service is called. IRQ and FIRQ remain under
the program-wide policy established by `main.asm`.

## Design consequences

- Busy waiting makes frame order deterministic and avoids dependence on monitor
  firmware revisions.
- The loop consumes the CPU completely; this bare-metal program has no other
  task to schedule while waiting.
- Sound routines are also busy loops, so an audible event lengthens its frame.
- Emulator speed must match the target machine for meaningful tuning.
- Cycle counts, branch timing, and the cost of added actor logic all affect
  cadence. Functional correctness alone is not enough for a timing change.

When changing delay constants, measure both an idle scene and a guardian-heavy
scene. A single calibration point can hide frame-rate variation caused by game
work.

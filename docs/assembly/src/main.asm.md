# `src/main.asm`

Source: [main.asm](../../../src/main.asm)

## Purpose

This is the translation-unit root and the complete lifetime of the running
program. It establishes constants and memory assumptions, places code at
`PROGRAM_ORIGIN`, initializes the machine-facing systems, then runs an infinite
wait/update loop. Every other assembly module is textually included below that
loop, so forward calls such as `JSR InitSound` are legal even though their
definitions occur later in the source stream.

## Startup sequence

`Start` performs four operations:

1. `ORCC #$50` masks IRQ and FIRQ. The game owns its timing and does not permit
   monitor interrupts to inject extra simulation work.
2. `LDS #STACK_TOP` places the hardware stack at `$9FFF`; pushes and subroutine
   calls grow downward.
3. `InitSound` leaves the buzzer low, preventing a stale hardware level.
4. `InitInput` configures the optional joystick PIA and clears input snapshots.
5. `InitGame` creates title/session state and draws the first title screen.

The apparent fifth item is intentional: initialization is best understood as
hardware safety, input state, then game state, even though the source contains
three `JSR` instructions after stack setup.

## Main-loop algorithm

`MainLoop` calls `WaitMainLoopFrame`, calls `RunGameFrame`, and branches back
unconditionally. There is no operating-system return path and no interrupt-
driven scheduler. A blocking sound cue therefore makes its current frame longer;
this is a deliberate part of the simple 1 MHz architecture.

The loop separates *when* a frame runs from *what* a frame does. The wait
routine adjusts its cost for extra active guardians, while `RunGameFrame`
handles state dispatch and simulation. Keeping those responsibilities separate
makes timing calibration possible without rewriting game rules.

## Include order and linkage

The order after `MainLoop` is `video`, `input`, `sound`, `timing`, then `game`.
`game.asm` in turn includes immutable data, rendering, flow, and writable state.
LWASM sees all of this as one program. There are no relocatable object files,
linker sections, private symbols, or independently initialized modules.

`end Start` records the execution address for formats that carry one. Raw output
still begins at the preceding `org PROGRAM_ORIGIN`.

## Register contract

`Start` has no caller and no return contract. `MainLoop` assumes only that each
public frame routine balances `S`; ordinary working registers may be destroyed.
`DP` is never changed. Every included renderer promises to return with the
bitmap video plane selected.

## Educational points

- `ORCC` demonstrates direct manipulation of CPU control flags.
- `LDS` shows why stack initialization must precede every `JSR`.
- A backward `BRA` is sufficient for a bare-metal event loop.
- Textual includes allow source modularity without changing binary placement.
- Initialization order is a dependency graph even when no language runtime
  enforces it.

When adding a platform subsystem, initialize it before `InitGame` if title
drawing or title input can use it. Never place executable fall-through code
after `MainLoop`; the loop cannot reach the include bodies except through calls.

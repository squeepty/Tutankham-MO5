# `src/game/flow/title-lifecycle.asm`

Source: [title-lifecycle.asm](../../../../../src/game/flow/title-lifecycle.asm)

## Purpose

This fragment owns the four major lifecycle entries: initialize the loaded
program, show the title, start a new run, and start an attract-mode demo. It is
where persistent session state is distinguished from per-run and per-demo state.

## Initialization boundaries

`InitGame` runs once after hardware setup. It clears the cheat and demo control
bytes, seeds `DemoRandomState` with `$A5`, and falls through to
`ShowTitleScreen`. It intentionally does not erase the assembled high-score
table: scores persist across runs for as long as the program remains loaded.

`ShowTitleScreen` cancels demo mode, resets cheat-entry progress and idle timing,
sets `GAME_STATE_TITLE`, resets the scripted title scene, and tail-jumps to the
title renderer. `CheatUnlocked` itself is not cleared here, so returning to the
title does not make the player re-enter the unlock sequence during that session.

## Starting a real game

`StartNewGame` disables demo mode and calls `ResetLevel`, which initializes Stage
1, Room 1, run inventory, lives, score, actors, and movement. It then enters the
timed level-introduction state, draws the introduction, and tail-jumps to the
stage-start cue. Gameplay begins later when the dispatcher expires
`PresentationTimer`; initialization never runs a nested frame loop.

## Starting the demo

`StartDemo` begins from the same clean run reset, then chooses a stage by
repeatedly subtracting `LEVEL_COUNT` from the pseudo-random byte. This is a
small modulo operation that avoids division. Room zero of the selected stage is
loaded and actor pools are reset.

Demo-only path state, visit counts, target validity, automatic fire/flash
timers, and total duration are initialized. `GameState` is cleared to the same
playing state used by a real run; `DemoActive` changes the input producer and
completion behavior rather than duplicating the simulation. The room is drawn
and the normal level-start sound completes setup.

## Register contract

| Entry | Inputs | Outputs and clobbers |
| --- | --- | --- |
| `InitGame` | none | session/title initialized; falls through to title display |
| `ShowTitleScreen` | none | title mode and title timers initialized; display redrawn |
| `StartNewGame` | none | clean run in level-intro mode |
| `StartDemo` | `DemoRandomState` as stage source | clean demo in playing mode |

All exported entries may clobber `A`, `B`, `X`, `Y`, `U`, and condition codes.
They balance `S` and do not change `DP`.

## Educational points

- State lifetime is explicit: boot, title session, run, room, and frame resets
  are different operations.
- Demo mode reuses the real rules and actor code by substituting input.
- Repeated subtraction is often smaller and clearer than general division when
  the divisor is a tiny constant.
- Tail calls let a draw or sound routine return directly to the lifecycle
  caller.

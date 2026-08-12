# `src/game/flow/progression-runtime.asm`

Source: [progression-runtime.asm](../../../../../src/game/flow/progression-runtime.asm)

## Purpose

This fragment resets runs and rooms, expands packed maps, calibrates each main
loop wait, and dispatches frames by `GameState`. It is the closest thing the
game has to a runtime scheduler.

## Complete-run reset

`ResetLevel` returns to Stage 1, Room 1 and clears run-scoped score, inventory,
cheats that affect play, motion, damage, presentation, projectile, and redraw
state. It sets the player at the room's table-driven start, gives the initial
lives and flash bomb, clears shots, and resets guardians.

High scores and `CheatUnlocked` survive because they belong to the loaded
session. This routine demonstrates why “reset the game” is not equivalent to
zeroing the entire writable block.

## Map expansion and table indexing

`SetCurrentStageRoomIndex` computes
`StageRoomOffsets[CurrentLevel] + CurrentRoom`. That cached index selects the
wall color, player start, map pointer, and other parallel room tables.

`LoadCurrentRoomMap` resets the room-local treasure streak, chooses the three-
nest record slice, and expands the selected 330-byte packed room into the
660-byte `LevelMap`. For each input byte it translates the high nibble and then
the low nibble through `PackedTileValues`. Runtime collision therefore sees
readable ASCII tile values despite the compact storage format.

`SetPlayerAtCurrentRoomStart` reads the X/Y tables and calls
`SyncPlayerPixelPosition`, aligning committed cell, pixel, and movement state.

## Work-aware frame pacing

`WaitMainLoopFrame` begins with `FRAME_DELAY_ITERATIONS`. During play it counts
active guardian slots. The historical baseline assumes three; each additional
active guardian removes `FRAME_DELAY_EXTRA_ENEMY_ITERATIONS` from the busy wait.
This compensates for simulation/rendering cost without changing movement units
or actor behavior.

Presentation states use the full wait. The routine counts actual active bytes,
not fixed slot numbers, so destroying an early guardian while a later one is
alive does not distort compensation.

## Frame state machine

`RunGameFrame` first updates the firing-pose timer, polls physical input, and
advances the pseudo-random mixer. In demo mode, any physical input returns to
the title; otherwise the demo timer runs and synthetic input is built only in
the playing state.

Dispatch then follows `GameState`:

- playing (`0`): update status/cheats, death or invulnerability, player, shots,
  guardians/contact, and final player compositing;
- title: process the cheat, start on Fire, otherwise advance idle/title scenes;
- level intro: count down, clear the state, and draw the room;
- complete/game over/other terminal state: Fire returns to the title.

After player logic, every state-changing operation is checked before proceeding.
A room transition, death, or completion can therefore stop the remainder of
the old room's frame.

## Dynamic-layer ordering

When the player changes, it is redrawn before actor processing for immediate
feedback and marked for final compositing. Shots then update; guardians restore,
move, and test contact; finally the player is redrawn on top if either pass may
have overwritten its footprint. This is painter's ordering coordinated through
`PlayerRedrawPending` and `PlayerCompositePending`.

## Register contract

The exported entries `ResetLevel`, `LoadCurrentRoomMap`,
`SetCurrentStageRoomIndex`, `SetPlayerAtCurrentRoomStart`,
`WaitMainLoopFrame`, and `RunGameFrame` take their inputs from memory. They may
clobber `A`, `B`, `X`, `Y`, `U`, and condition codes; `S` is balanced and `DP`
is unchanged. Their durable outputs are the named state and rendered display.

## Educational points and pitfalls

- A dispatcher is an explicit state machine even when implemented with compares
  and branches rather than a jump table.
- Packed assets can be expanded once per room to make hot collision reads cheap.
- Check `GameState` after calls that can transition; continuing would update an
  obsolete room or overwrite a terminal screen.
- Timing compensation is coupled to measured actor cost and should be retested
  after substantial renderer or AI changes.

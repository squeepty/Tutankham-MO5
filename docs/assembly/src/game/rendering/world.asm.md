# `src/game/rendering/world.asm`

Source: [world.asm](../../../../../src/game/rendering/world.asm)

## Purpose

This fragment builds the gameplay display, owns transient status messages,
draws the complete static room, performs the diagonal room wipe, and translates
each `LevelMap` tile into artwork and color.

## Gameplay screen layering

`DrawGameScreen` clears the screen, writes the fixed HUD template, draws the
entire static room, then composites guardians, shots, player, live values,
indicators, and initial status in that order. It is used for stage/room entry.
Respawn uses targeted restoration instead, retaining map and HUD work.

`LevelMap` remains the static authority. Dynamic actors do not alter tile
selection, and tile drawing never examines pixels already on screen.

## Status-message system

Small named helpers load a zero-terminated message into `U` and tail-jump to
`DrawStatus`. That common routine clears the bottom span, counts string bytes,
computes `(TEXT_COLUMNS - length) / 2`, starts a roughly two-second timer, and
draws the centered text.

The caller contract caps text at 38 cells. `UpdateStatusMessage` in player flow
expires the timer and calls `ClearStatusLine`. The line clearer writes empty
cell patterns, ensuring both bitmap and attributes are reset.

## Full-room traversal

`DrawFullLevel` is a nested `LEVEL_HEIGHT × LEVEL_WIDTH` loop using
`MapDrawX/Y` and remaining counters. Each iteration calls `DrawMapCellAt`, which
copies the requested coordinates into scratch and dispatches the tile.

`DrawMapCell` reads the ASCII tile from `LevelMap`. A compare chain selects
floor, alternating wall, final exit, key, treasure, spawn, either warp,
intermediate exit, or default empty art. Each case sets `DrawCellColor` and `U`,
then the shared tail converts room coordinates to screen cell coordinates and
jumps to `DrawCellPattern`.

Walls choose `CellWallA` or `CellWallB` from `(X XOR Y) AND 1`, creating a
checkerboard texture without storing another map bit.

## Diagonal room-transition algorithm

The transition draws the already-loaded destination room over the outgoing
playfield. Every anti-diagonal contains cells where `X + Y` equals
`RoomTransitionDiagonal`. The start X is the diagonal number clamped to the
right edge; Y is `diagonal - X`. The loop decrements X and increments Y until it
leaves the room.

Three diagonals are drawn per visual frame, followed by `WaitFrame`. Advancing
from diagonal zero through `width + height - 2` produces a top-left to bottom-
right wipe while leaving HUD and status rows intact.

## Register contracts

`DrawGameScreen`, status helpers, `DrawFullLevel`, and
`DrawDiagonalRoomTransition` take state from memory. `DrawStatus` takes a string
in `U` of at most 38 cells. `DrawMapCellAt` takes room X in `A` and Y in `B`.
All may clobber `A`, `B`, `X`, `Y`, `U`, condition codes, and renderer scratch;
they balance `S`, preserve `DP`, and return with the bitmap plane selected.

## Educational points and pitfalls

- A single authoritative tile renderer guarantees full draws and footprint
  restoration produce identical backgrounds.
- Coordinate spaces are explicit: room cells gain `LEVEL_SCREEN_COL/ROW` only
  at the final drawing boundary.
- Anti-diagonal traversal creates a wipe without a framebuffer copy.
- A compare chain is appropriate for this small tile alphabet; a jump table
  would require careful range normalization and indirect-call conventions.

## Wall engravings and stage-door overlays

`DrawMapCell` first calls `TryDrawExitDoor`. It returns carry set after drawing
one door quadrant; otherwise the ordinary tile dispatch continues. The helper
checks one and two cells to the left for a paired `D`, derives the top/bottom
half from the odd/even physical row, and selects the stage's yellow/red palette.
Only cells visited inside the map are rendered, so a boundary door clips to
its left leaf. Source `D` markers retain their interaction and collision rules.

Wall cells consult `RoomWallDecorationPointers[CurrentStageRoomIndex]` for ten
X/Y/symbol triples. A match chooses one eight-byte half of a 16×8 engraving
only when its neighboring half is still a wall. Otherwise the normal alternating
stone pattern is used. Six designs occupy 96 bytes; placement tables use 30
bytes per room plus pointers. Rendering adds no map tile IDs or collision state.

`GetLevelTile` clobbers A/B/X. Door probing reloads the original MapDrawX/Y
before ordinary dispatch; MapTargetX/Y remain the final drawing destination.
Both overlay paths are shared by full-room draws, diagonal wipes, and actor
background restoration, preventing decorative pixels from disappearing when
an actor passes over them.

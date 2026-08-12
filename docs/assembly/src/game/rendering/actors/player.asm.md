# `src/game/rendering/actors/player.asm`

Source: [player.asm](../../../../../../src/game/rendering/actors/player.asm)

## Purpose

This fragment chooses the explorer pose and OR-composites an 8×8 sprite at
arbitrary room-local pixel coordinates.

## Pose selection

`DrawPlayer` uses directional firing silhouettes while moving horizontally, so
left/right facing is unmistakable. Vertical or idle movement uses one of two
walking frames selected by `PlayerAnimationFrame`. `DrawPlayerFire` ignores
movement direction and chooses the left/right firing pose from signed
`PlayerFacing`.

All cases load the base of an eight-phase table into `U` and enter
`DrawPlayerPattern`.

## Phase and destination calculation

Each horizontal phase occupies 16 bytes: two bytes for each of eight rows.
`PlayerPixelX AND 7` selects a phase and multiplication by 16 advances `U`.
`PlayerPixelX >> 3` gives the left byte column; the room-screen offset is added.

Y is already in pixels. Adding `LEVEL_SCREEN_ROW * 8`, multiplying by 40 bytes
per scanline, and adding the column gives the destination address. This differs
from `CellAddress`, whose Y is a cell row.

## Bitmap and color compositing

For eight rows the renderer pulls a two-byte word, ORs it with the existing two
bitmap bytes, and stores the result. OR permits the static maze to remain
visible through zero sprite bits, but requires old-footprint reconstruction
before the actor moves or changes pose.

The color pass writes `COLOR_PLAYER` to the left byte on every row. It writes
the right byte only for a nonzero horizontal phase; phase zero has no spilled
sprite bits and should not recolor the neighboring cell. The final jump restores
the bitmap plane.

## Register contract

`DrawPlayer` and `DrawPlayerFire` take explorer pose/position from state.
`DrawPlayerPattern` takes an eight-phase artwork base in `U`. Output is the
composited explorer. `A`, `B`, `X`, `Y`, `U`, condition codes, phase, and draw-
column scratch are clobbered; `S` is balanced, `DP` unchanged, and the bitmap
plane selected on return.

## Educational points and pitfalls

- Pre-shifted data moves bit-shift cost from every frame to asset preparation.
- OR compositing is inexpensive but not reversible; restoration is its paired
  operation.
- Pixel Y and cell Y are distinct units even though both often travel in `B`.
- Do not color the spill byte at phase zero, or adjacent wall/floor attributes
  will change despite receiving no player pixels.

# `src/game/rendering/restoration/player.asm`

Source: [player.asm](../../../../../../src/game/rendering/restoration/player.asm)

## Purpose

This fragment erases the current explorer image by reconstructing every static
map cell its arbitrary-pixel 8×8 footprint touches. It does not copy pixels from
a saved background buffer.

## Dirty guard

`EnsurePlayerFootprintRestored` checks `PlayerRedrawPending`. If the current
frame already restored the old footprint, it returns; otherwise it tail-jumps to
`RestorePlayerFootprint`. This prevents multiple subsystems—movement, firing,
blinking, damage—from redundantly repairing the same image.

`RestorePlayerFootprint` sets the pending flag immediately. The flag means “old
image removed; player must be redrawn,” so later frame orchestration can
composite the new pose at the correct layer.

## Footprint algorithm

The left/top cells are `pixelX >> 3` and `pixelY >> 3`. If either coordinate has
a nonzero low-three-bit phase, the 8×8 sprite crosses that axis's next cell, so
right or bottom increments.

This produces four possible rectangles:

- aligned: 1×1 cell;
- horizontally shifted: 2×1;
- vertically shifted: 1×2;
- shifted on both axes: 2×2.

Movement normally changes one axis at a time, but handling the full 2×2 case
makes the renderer valid for future diagonal effects. Each distinct corner is
redrawn through `DrawMapCellAt`, whose tile source is the current `LevelMap`.
Collected objects therefore remain absent after restoration.

## Register contract

Both entries take position from player state. Output is a reconstructed static
footprint and `PlayerRedrawPending = 1`. They clobber `A`, `B`, `X`, `Y`, `U`,
condition codes, and shared footprint fields; balance `S`; preserve `DP`; and
return on the bitmap plane.

## Educational points and pitfalls

- The low address bits are both a sprite-shift phase and proof that a second
  cell is covered.
- Reconstructing from authoritative world state avoids per-actor background
  buffers and their synchronization problems.
- Restoration and redraw are separate operations; clearing the pending flag too
  early can erase the actor for a frame.

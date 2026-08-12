# `src/game/rendering/actors/projectiles.asm`

Source: [projectiles.asm](../../../../../../src/game/rendering/actors/projectiles.asm)

## Purpose

This fragment draws the fixed shot pool. Unlike explorers and guardians, shots
remain cell-aligned, so they can use `DrawCellPattern` and require no horizontal
phase tables.

## Pool and frame selection

`DrawAllShots` scans active slots with `CurrentActorIndex` and calls
`DrawCurrentShot`. The current renderer chooses a left- or right-facing pattern
from signed `ShotDirection`.

Each direction has two animation frames. The selection bit is
`ShotAnimationFrame XOR CurrentActorIndex`, making adjacent slots alternate
even though the pool shares one timer. This creates visual variation without a
per-shot animation byte.

The shot's room X/Y receives the playfield cell offset, `DrawCellColor` becomes
`COLOR_SHOT`, and a tail jump draws the eight-byte pattern.

## Register contract

`DrawAllShots` takes no input and clobbers `CurrentActorIndex` while drawing all
active slots. `DrawCurrentShot` requires `CurrentActorIndex`. Both may clobber
`A`, `B`, `X`, `Y`, `U`, condition codes, and renderer scratch; they balance
`S`, preserve `DP`, and return on the bitmap plane.

## Educational points

- Cell alignment dramatically simplifies addressing, clipping, restoration,
  and art storage.
- XORing a global phase with slot parity creates stagger for free.
- Direction is signed movement data but maps naturally to visual table choice.

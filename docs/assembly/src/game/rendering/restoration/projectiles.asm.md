# `src/game/rendering/restoration/projectiles.asm`

Source: [projectiles.asm](../../../../../../src/game/rendering/restoration/projectiles.asm)

## Purpose and algorithm

`RestoreAllShotCells` walks the fixed projectile pool. For each active slot it
loads `ShotX` and `ShotY`, preserving X briefly on `S` while loading Y, and calls
`DrawMapCellAt`. Because shots are cell-aligned, each occupies exactly one
static map cell.

Projectile simulation calls this once before changing animation frames or
positions. Player respawn also calls it before clearing the pool. In both cases
the mutable `LevelMap` determines what reappears, so collected items cannot be
resurrected by erasing a shot.

## Register contract

The routine takes no input and restores every active shot cell. It clobbers
`A`, `B`, `X`, `Y`, `U`, `CurrentActorIndex`, and condition codes; balances
`S`; preserves `DP`; and returns on the bitmap plane.

The key educational contrast with actor restoration is alignment: restricting
shots to cells eliminates phase tests and multi-cell footprints at the cost of
coarser motion.

# `src/game/flow/projectile-pool.asm`

Source: [projectile-pool.asm](../../../../../src/game/flow/projectile-pool.asm)

## Purpose and algorithm

This reset helper initializes the fixed projectile pool. `ClearShots` walks
`ShotActive[0..SHOT_COUNT-1]` with `B` and clears each byte, then clears the
shared movement timer and animation frame. Coordinates and directions need not
be erased because an inactive slot is never simulated or drawn; allocation
overwrites those fields before setting it active.

That choice illustrates a useful low-level invariant: the active flag defines
whether every other byte in a slot is meaningful. Clearing dead data would add
cycles without increasing correctness.

## Register contract

`ClearShots` takes no input and leaves every shot inactive with global shot
timers reset. It clobbers `A`, `B`, `X`, and condition codes, balances `S`, and
does not change `DP`.

When adding another per-pool timer, reset it here. When adding a field that must
have a defined value before activation, initialize it in `FireShot`, not
necessarily in this loop.

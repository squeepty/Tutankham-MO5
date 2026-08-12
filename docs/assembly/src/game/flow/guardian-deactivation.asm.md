# `src/game/flow/guardian-deactivation.asm`

Source: [guardian-deactivation.asm](../../../../../src/game/flow/guardian-deactivation.asm)

## Purpose and sequence

`DeactivateCurrentEnemy` is the single path for a shot or flash-bomb guardian
hit. `CurrentActorIndex` selects the slot.

It first restores the old sprite footprint. The effect cell is calculated from
the guardian's pixel center: add four, then divide by eight with three logical
shifts. It installs the hit-effect timer, clears spawn grace and the active flag,
and cancels in-flight movement and carried pixel credit.

Respawn delay is `ENEMY_RESPAWN_BASE + slot * ENEMY_RESPAWN_STAGGER`, computed
by a compact repeated-add loop. Different slots therefore do not reappear in a
single synchronized wave. The routine tail-jumps to `DrawCurrentEnemyHitEffect`,
which returns directly to the original caller.

## Register contract

Input is `CurrentActorIndex`. Output is an inactive slot with centered effect
coordinates, an active effect timer, and a staggered respawn timer. `A`, `B`,
`X`, `U`, and condition codes are clobbered; `S` is balanced and `DP` unchanged.

## Educational points

- Centralizing deactivation keeps projectile and flash behavior identical.
- Pixel-to-cell rounding is explicit: adding half a cell before shifting chooses
  the nearest cell instead of the top-left cell.
- Slot-based staggering creates temporal variation without random numbers.
- Restoration must happen before clearing the active flag, or generic active-
  actor restoration would no longer know that the sprite exists.

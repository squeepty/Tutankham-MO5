# `src/game/flow/projectiles.asm`

Source: [projectiles.asm](../../../../../src/game/flow/projectiles.asm)

## Purpose

This fragment allocates and advances the three-shot fixed pool, resolves shots
against static tiles and moving guardians, awards hit score, and implements the
single-use flash bomb.

## Firing and allocation

`FireShot` linearly selects the first inactive slot. A full pool makes firing a
silent no-op. It restores the player's footprint, starts the firing pose and
blocking sound, then builds a candidate one cell left or right according to the
signed `PlayerFacing`.

Walls and final exits absorb the shot before allocation. A guardian already
overlapping the starting cell is hit immediately. Otherwise X, Y, and direction
are written before the active flag is observed by later passes, and the shot is
drawn.

## Batched movement and restoration

`ProcessShots` runs only when `ShotMoveTimer` expires. It flips the shared
animation frame, restores every active shot cell from `LevelMap`, then walks the
pool. Each shot advances horizontally by signed direction. Walls and final
exits deactivate it; a guardian hit deactivates both participants; otherwise
the candidate X commits. All surviving shots are drawn after the complete pass.

Restoring as a batch before movement prevents trails and prevents one old shot
image from being mistaken for another object's background. Shots remain cell-
aligned, so restoration needs only one map cell per slot.

## Guardian hit testing

`HitEnemyAtCandidate` scans active guardians and temporarily exchanges
`CurrentActorIndex`: the caller's shot slot is saved on the stack while the hit
guardian becomes current for `DeactivateCurrentEnemy`. It restores the shot
index afterward, awards 100 points, refreshes the HUD/status, and plays the hit
cue.

`CurrentEnemyOverlapsCandidateCell` converts the projectile cell to pixel
coordinates and performs inclusive 8×8 axis-aligned overlap tests. Pixel-space
testing is necessary because a guardian may straddle two cells. Both its
committed and in-flight visual position are therefore hittable.

## Flash-bomb rule

`UseFlashBomb` checks `FlashAvailable`, consumes it once, and deactivates every
currently active guardian through the normal hit/effect/respawn path. Each one
awards 100 points. Inactive guardians are not scored again and retain their
existing respawn schedule. The HUD and indicator are updated once after the
loop. Attempting to reuse the bomb only displays the unavailable message.

Each new life restores one flash bomb; changing rooms does not.

## Register contracts

| Entry | Inputs | Outputs |
| --- | --- | --- |
| `FireShot`, `ProcessShots`, `UseFlashBomb` | state/input in memory | pool, guardian and score state updated |
| `HitEnemyAtCandidate` | `CandidateX/Y` | `A != 0` on a guardian hit |
| `CurrentEnemyOverlapsCandidateCell` | `B` guardian index, `CandidateX/Y` | `A != 0` on 8×8 overlap |

Entries may clobber `A`, `B`, `X`, `Y`, `U`, condition codes, and shared actor
scratch. `S` is balanced and `DP` unchanged.

## Educational points and pitfalls

- A small linear free-slot search is simpler than dynamic allocation.
- Restore, simulate, then redraw is the core animation transaction.
- Save and restore implicit context such as `CurrentActorIndex` before calling
  a helper that assigns it a different meaning.
- Cell-only collision would miss partially moved guardians; pixel AABBs bridge
  the cell and sprite models.

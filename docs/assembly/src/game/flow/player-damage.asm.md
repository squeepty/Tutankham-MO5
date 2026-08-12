# `src/game/flow/player-damage.asm`

Source: [player-damage.asm](../../../../../src/game/flow/player-damage.asm)

## Purpose

This fragment detects explorer/guardian contact, applies life and demo rules,
centers the death effect, and rebuilds dynamic state for a respawn.

## Contact algorithm

`CheckPlayerEnemyContact` first rejects damage globally when the guardian-hit
cheat is active, death is already running, or invulnerability is active. It
then scans active guardians, ignoring their spawn-grace windows.

For each guardian it calculates absolute pixel X and Y differences. Two 8×8
sprites overlap exactly when both differences are below eight. This inexpensive
test is equivalent to an axis-aligned bounding-box intersection for equal-size
sprites and correctly handles sub-cell positions.

The routine calls `PlayerHit` on the first overlap and returns `A = 1`; no
contact returns zero.

## Life, death, and game-over rules

Every hit clears `TreasureStreak`, including hits under infinite-lives mode. In
normal play the life count decrements. A remaining life enters the recoverable
death sequence; the final life records the score, plays death audio, and shows
game over. A demo losing its final life returns to the title instead.

Infinite lives still runs the visual/audio death and respawn sequence but never
decrements the life counter. This keeps the cheat from bypassing state cleanup.

`BeginPlayerDeathEffect` restores the old sprite, makes the explorer invisible,
cancels motion/fire/compositing, rounds the pixel center to a cell, and draws the
effect there. `BeginPlayerDeath` starts its timer and updates HUD/status.

## Respawn transaction

`RespawnPlayer` restores shots, guardian visuals, and the death cell from the
unchanged `LevelMap`. It teleports the explorer to the current room start,
restores facing/visibility and a fresh flash bomb, and starts invulnerability
plus blinking.

Shot and guardian pools are reset, then all live actors and the player are
redrawn over the existing maze. The room is not reloaded: collected key and
treasure tiles remain gone, the stage key remains owned, score remains, but the
treasure streak has broken.

## Register contract

`CheckPlayerEnemyContact` takes state from memory and returns `A != 0` when a
hit begins. `PlayerHit`, `BeginPlayerDeath`, and `RespawnPlayer` update life,
actor, presentation, and inventory state. These entries may clobber `A`, `B`,
`X`, `Y`, `U`, and condition codes; `S` is balanced and `DP` unchanged.

## Educational points and pitfalls

- Grace and invulnerability are collision filters, not visibility rules.
- Reset dynamic overlays before redrawing them, while leaving durable map
  mutations intact.
- A cheat should enter the normal recovery path wherever possible, preserving
  invariants that later frames rely on.
- The order “restore sprite, clear active motion, draw effect” prevents remnants
  and misplaced restoration.

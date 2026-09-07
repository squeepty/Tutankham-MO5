# `src/game/flow/player.asm`

Source: [player.asm](../../../../../src/game/flow/player.asm)

## Purpose

This fragment implements explorer timers, input priority, smooth cell-to-cell
motion, firing/flash actions, item collection, treasure streak scoring, warps,
and tile-triggered progression.

## Timer updates and visibility

`UpdateStatusMessage` decrements the message timer and clears the line exactly
when it reaches zero. `UpdatePlayerFireAnimation` similarly marks the visual
dirty when the firing pose expires.

`UpdatePlayerInvulnerability` alternates `PlayerVisible` at a separate blink
cadence. Hiding first restores the old footprint; showing requests a redraw.
When invulnerability ends it forces a visible state. `UpdatePlayerDeath` waits
for the death-effect duration, then calls the respawn routine.

## Input priority and movement transaction

`ProcessPlayer` completes an in-flight move before considering a new direction,
so the explorer cannot turn halfway across a cell. At rest it checks held
directions in Up, Down, Left, Right priority order and constructs `CandidateX/Y`.
Left/right also update the signed `PlayerFacing` used by firing and artwork.

`StartPlayerMove` rejects walls. Final exits and intermediate room exits also
reject entry until `HasKey` is set; no treasure requirement is imposed. Other
tiles, including collectibles and warps, are traversable. An accepted move
stores the target and starts an eight-pixel transaction.

Actions use rising edges and are processed after movement work. The development
next-room action supplies the key and enters the real transition path. Fire
allocates a projectile; flash consumes the currently available bomb. Respawn and stage advancement
restore it; room transitions do not.

## Fractional-speed algorithm

Explorer speed averages 2.25 pixels per movement frame without fractions. The
phase sequence issues budgets of 2, 2, 2, then 3 pixels. Every budget advances
one pixel at a time so animation and the eight-pixel boundary remain exact.

If a budget reaches the target cell with credit left, that credit is stored in
`PlayerStepCarry` for the next legal cell. Without carry, every boundary would
discard a fraction of speed and long straight paths would be slower than the
tuning value.

`AdvancePlayerOnePixel` updates only pixel coordinates and the remaining count.
On the eighth step, `CommitPlayerMove` copies the target into committed X/Y and
resolves the destination tile once. This two-phase commit prevents pickups or
exits from triggering while the sprite is visually between cells.

## Tile interactions and game rules

- Key: set `HasKey`, award 200 points, replace the map tile with floor, and
  report that exits are open.
- Treasure: increment the room-local streak and award `streak × 500` points.
  Each validated room has exactly three treasures, producing 500, 1,000, and
  1,500-point pickups when collected without a death or room change.
- Warp: move instantly to the fixed opposite vertical endpoint and synchronize
  cell/pixel motion state.
- Final exit: call `TryPlayerExit`; only the key is required.
- Intermediate exit: call `TryRoomTransition`; only the key is required.

Collected key/treasure tiles are changed to floor in `LevelMap`, making both
collision and later background restoration agree that the item is gone.

Every completed move refreshes HUD values and checks guardian overlap. This
catches contact at the committed destination even before the later guardian
pass.

## Register contract

Timer routines and `ProcessPlayer` take inputs from state and may clobber `A`,
`B`, `X`, `Y`, `U`, and condition codes. `StartPlayerMove` additionally expects
`A = PLAYER_DIR_*` and `CandidateX/Y = destination`; acceptance is reported by
the resulting movement state rather than a return register. All entries balance
`S` and preserve `DP`.

## Educational points and pitfalls

- Separate Held and Press snapshots naturally distinguish movement from actions.
- Committed, target, and pixel coordinates form a tiny transaction protocol.
- Fixed-point behavior can be implemented with a repeating integer schedule and
  carry rather than a general fractional type.
- Tile effects belong at commit, not at movement start or every pixel.
- Death and room loading reset `TreasureStreak`; collecting the key or using a
  warp does not.

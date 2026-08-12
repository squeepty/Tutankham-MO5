# `src/game/rendering/actors/guardians.asm`

Source: [guardians.asm](../../../../../../src/game/rendering/actors/guardians.asm)

## Purpose

This fragment draws one arbitrary-pixel guardian and the cell-aligned guardian-
hit/player-death effects.

## Artwork selection

`DrawCurrentEnemy` uses the selected slot's DPAD movement direction to choose
up, down, left, or right artwork. `EnemyAnimationFrame` adds 128 bytes to reach
frame one because each frame contains eight phases × 16 bytes. Pixel X then
selects the exact horizontal phase.

Behavioral identity does not change appearance; direct, intercepting, and
wandering guardians are recognized by movement, not separate art.

## Destination arithmetic

X uses the familiar `pixelX >> 3` byte column plus playfield offset. Y must be
multiplied by 40. The code constructs this as `Y*8 + Y*32` with shifts and an
intermediate stack save, then adds the draw column. This demonstrates constant
multiplication without a general multiply operand while preserving the partial
value.

Eight left/right sprite words are ORed into the bitmap. The color pass uses
`COLOR_ENEMY`, or `COLOR_ENEMY_RESPAWN` while the slot's grace timer is nonzero.
As with the player, the right color byte is touched only for a nonzero phase.

## Cell-aligned effects

`DrawCurrentEnemyHitEffect` reads the chosen slot's stored effect X/Y, adds the
playfield cell offsets, selects `CellHitEffect` and `COLOR_HIT_EFFECT`, and
tail-jumps to `DrawCellPattern`.

`DrawPlayerDeathEffect` is the same operation using the player death cell. The
shared art intentionally gives damage events a consistent visual vocabulary.

## Register contract

`DrawCurrentEnemy` and `DrawCurrentEnemyHitEffect` require
`CurrentActorIndex`. `DrawPlayerDeathEffect` reads `PlayerDeathX/Y`. Output is
the named composite. They may clobber `A`, `B`, `X`, `Y`, `U`, condition codes,
and renderer scratch; they balance `S`, preserve `DP`, and return on the bitmap
plane.

## Educational points and pitfalls

- Table stride is part of the algorithm: 128 bytes means one complete animation
  frame, 16 bytes one shift phase.
- Multiplication by 40 can be decomposed into powers of two, useful on processors
  without an appropriate multiply form.
- Spawn grace changes collision and color in parallel while preserving normal
  position and sprite logic.
- Effect coordinates are cells; guardian coordinates are pixels. Mixing them
  would apply playfield offsets or shifts twice.

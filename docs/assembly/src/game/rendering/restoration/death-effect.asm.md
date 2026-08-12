# `src/game/rendering/restoration/death-effect.asm`

Source: [death-effect.asm](../../../../../../src/game/rendering/restoration/death-effect.asm)

## Purpose and algorithm

`RestorePlayerDeathEffect` is a one-routine adapter. It loads the room-local
effect cell from `PlayerDeathX/Y` and tail-jumps to `DrawMapCellAt`, reconstructing
the current static tile after the death timer expires.

The effect was drawn at cell resolution even though its origin was rounded from
the explorer's pixel center. It therefore needs no multi-cell footprint logic.
Using the map renderer ensures a wall, floor, spawn, or uncollected item beneath
the effect returns with the correct bitmap and color.

## Register contract

There are no register inputs. The death cell is restored from state. The call
may clobber `A`, `B`, `X`, `Y`, `U`, condition codes, and renderer scratch;
balances `S`; preserves `DP`; and returns on the bitmap plane.

This is also a compact example of API adaptation through a tail jump: global
state is converted to another routine's `A/B` interface without an extra return
layer.

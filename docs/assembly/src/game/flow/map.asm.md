# `src/game/flow/map.asm`

Source: [map.asm](../../../../../src/game/flow/map.asm)

## Purpose and address algorithm

This tiny fragment is the sole row-major addressing primitive for the active
30×22 room. Given `A = X` and `B = Y`, `GetLevelCellAddress` computes:

```text
LevelMap + Y * LEVEL_WIDTH + X
```

It saves X in `QueryX`, loads `A = LEVEL_WIDTH`, and uses 6809 `MUL` to produce
the 16-bit row offset in `D`. Adding the saved column to `B` plus carry to `A`
finishes the offset, which is indexed from `LevelMap` into `X`.

`GetLevelTile` calls the address routine and loads the ASCII tile byte at `,X`.
It deliberately returns both the value in `A` and its address in `X`, letting a
caller inspect and then mutate without calculating twice.

## Register contract

`GetLevelCellAddress` clobbers `A`, `B`, `X`, `QueryX`, and condition codes and
returns the address in `X`. `GetLevelTile` has the same clobbers and returns the
tile in `A` plus its address in `X`. Both preserve `Y`, `U`, `S`, and `DP`.

Coordinates are assumed valid. Border walls and callers' movement rules prevent
normal out-of-range values; this hot primitive does not pay for bounds checks.

## Educational points

- Row-major two-dimensional access reduces to multiply, add, and base indexing.
- `MUL` produces a 16-bit result in `D`, which matters because 660 cells exceed
  an eight-bit offset.
- A shared scratch byte substitutes for an extra stack push, but callers must
  treat `QueryX` as destroyed.

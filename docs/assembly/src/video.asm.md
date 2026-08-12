# `src/video.asm`

Source: [video.asm](../../../src/video.asm)

## Purpose

This file is the hardware-facing drawing layer. It knows how the Thomson MO5
selects its bitmap and color planes, how an 8-pixel cell maps to memory, and how
the game writes cells and text. Higher-level renderers build sprites, rooms,
status panels, and presentation screens on these primitives.

The MO5 exposes the bitmap and color planes through the same `$0000`-based
address range. Bit 0 at `VIDEO_BANK_SELECT` decides which plane CPU reads and
writes reach. A bitmap byte supplies eight monochrome pixels; the corresponding
color byte supplies foreground and background attributes for that scanline.

## Coordinate and address model

Cell coordinates use `A = column` and `B = row`. There are 40 bytes per
scanline and eight scanlines per cell, so the first byte of a cell is:

```text
VIDEO_BITMAP_BASE + row * (8 * 40) + column
```

`CellAddress` computes `row * 320 + column`. The 6809 `MUL` instruction
multiplies `A` and `B` into `D`; two shifts then finish the factor of 320. The
routine temporarily stores the column by patching the immediate operand at
`CellAddressColumn`. This is intentional self-modifying code and is one reason
the program must be loaded into writable RAM.

## Plane selection and clearing

`SelectBitmapPlane` sets bit 0 of the bank register. `SelectColorPlane` clears
it. Public drawing routines restore the bitmap plane before returning, creating
an important global invariant: a caller may begin bitmap work without first
repairing an unknown plane selection.

`ClearScreen` clears all 8,000 bitmap bytes and then fills all 8,000 color bytes
with `COLOR_BACKGROUND`. The bitmap loop writes words through `D`; the color
loop writes bytes because every location receives the same attribute. It ends
by reselecting the bitmap plane.

## Cell drawing

`DrawCellPattern` consumes eight bytes at `U`, one per scanline. It calculates
the destination, unrolls the eight bitmap stores at 40-byte intervals, switches
planes, writes the selected `DrawCellColor` to the same eight offsets, and
switches back. The unrolled sequence costs source space but avoids a loop and
address recalculation in one of the most frequently used primitives.

`DrawCellColor` is writable global drawing state. Callers set it immediately
before drawing a tile; they must not assume a previous caller left a useful
value.

## Text and glyph lookup

`DrawString` accepts a zero-terminated ASCII string in `U` and advances one
cell to the right for every character. It saves the destination and string
pointer while `DrawGlyphAtX` performs its work.

`DrawGlyphAtX` classifies the byte as punctuation, digit, or uppercase letter.
Digits and letters use `(character - base) * 8` to index fixed-width tables.
Unsupported bytes select `GlyphFallback`, so corrupt or unexpected strings are
visible instead of silently blank. Each glyph first writes eight bitmap rows,
then eight `TextColor` attributes in the color plane.

## Register contracts

| Routine | Inputs | Outputs and clobbers |
| --- | --- | --- |
| `SelectBitmapPlane`, `SelectColorPlane` | none | plane selected; `A` clobbered |
| `ClearScreen` | none | both planes initialized; bitmap selected; `D`, `X`, `Y` clobbered |
| `CellAddress` | `A` column, `B` cell row | `X` destination; `D` clobbered |
| `DrawCellPattern` | `U` pattern, `A/B` column/row, `DrawCellColor` | `U += 8`; bitmap selected; `D`, `X` clobbered |
| `DrawString` | `U` C string, `A/B` start cell | string drawn; `A`, `X`, `U` clobbered |
| `DrawGlyphAtX` | `A` ASCII, `X` destination | `X` restored, bitmap selected; `A`, `B`, `U` clobbered |

## Educational points and pitfalls

- Display memory is not a linear array of colored pixels: bitmap bits and color
  attributes must remain synchronized across banked planes.
- A stable return-plane convention is the assembly equivalent of an API
  postcondition.
- Fixed-width glyph tables turn character conversion into subtraction,
  multiplication by eight, and indexed addressing.
- `CellAddress` demonstrates a legitimate space-saving use of self-modifying
  code, but makes ROM placement and re-entrant calls impossible.
- Arbitrary-pixel sprites do not use these cell routines; their shifted OR
  compositing is documented under `game/rendering/actors/`.

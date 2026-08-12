# `src/game/rendering/hud.asm`

Source: [hud.asm](../../../../../src/game/rendering/hud.asm)

## Purpose

This fragment updates score digits, derives the live high-score display, draws
reserve-life icons or the infinite-lives label, and places the flash-bomb
indicator.

## Score display

The score representation contains a ten-thousands digit and a 0–99 hundreds
byte. `DrawHudValues` draws the first field, splits the lower byte into decimal
tens/ones, and leaves the template's final two zeroes unchanged.

The HUD high-score field shows the greater of the current run and stored first
place. It performs a lexicographic comparison of the two fields without
inserting the current value into persistent rankings. The title/game-over table
is updated only by `RecordHighScore`.

`SplitScoreHundreds` repeatedly subtracts ten while counting `B`. For an input
limited to 0–99 this uses at most nine iterations and is smaller than a general
division/conversion routine. It writes `NumberTens` and `NumberOnes`.

## Lives and flash indicators

`DrawHudIndicators` first clears the entire possible icon span so lost lives or
consumed flash icons cannot remain. In finite mode, `PlayerLives` includes the
currently active explorer, so only `lives - 1` reserve icons are drawn. Their
run is centered and the flash indicator, when available, is placed after a
spacer.

With infinite lives enabled, the centered reserve icons are replaced by `INF`
and the flash uses a fixed position after that label. A single remaining active
life shows no reserve icon; a flash by itself is centered.

## Character replacement

`DrawHudDigit` converts 0–9 to ASCII and falls through to `DrawHudCharacter`.
That helper clears the target cell first, calculates its address, then draws one
glyph. Clearing matters because glyph output overwrites bitmap rows but dynamic
HUD changes may otherwise leave old set pixels or attributes.

## Register contracts

| Entry | Inputs | Outputs |
| --- | --- | --- |
| `DrawHudValues`, `DrawHudIndicators` | game state | corresponding HUD cells updated |
| `SplitScoreHundreds` | `A = 0..99` | `NumberTens`, `NumberOnes` |
| `DrawHudDigit` | `A = 0..9`, `B` screen column | digit at HUD row |
| `DrawHudCharacter` | `A` ASCII, `B` screen column | glyph at HUD row |

Routines may clobber `A`, `B`, `X`, `Y`, `U`, condition codes, and HUD scratch.
They balance `S`, preserve `DP`, and return on the bitmap plane.

## Educational points and pitfalls

- Restricting score values lets repeated subtraction replace generic division.
- Displaying max(current, stored) is a view calculation, not a mutation.
- Reserve lives and total lives are different quantities; the active explorer
  is deliberately excluded from the icon row.
- Clear a variable-width old display before drawing a shorter replacement.

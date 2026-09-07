# `src/game/rendering/presentation.asm`

Source: [presentation.asm](../../../../../src/game/rendering/presentation.asm)

## Purpose

This fragment renders the title and its animated vignette, the stage-intro card,
and the completion/game-over screens. It combines cell graphics, fixed text,
score insertion, and arbitrary-X shifted sprites without depending on the live
room renderer.

## Full title composition

`DrawTitleScreen` clears both planes, draws the logo, decorative treasures,
subtitle, three high-score templates, play prompt, controls, framed animation
band, the single-cell `V1` version sprite, and—when session-unlocked—the cheat notice. Each score
template already contains trailing zeroes; `DrawPresentationScore` overwrites
only its three significant digits.

The frame around the vignette is a small nested row/column traversal. Boundary
cells alternate the same two wall textures as the maze using `(X XOR Y) AND 1`.
Interior cells are skipped, leaving the animation its own clean band.

## Stateful title-band rendering

`DrawTitleScene` clears the band only for a full scene reset, redraws diamonds
from `TitleSceneDiamondMask`, then composites the current snake, shot, and
player. Per-frame updates enter at `DrawTitleSceneSnake`, preserving resident
diamonds until their scripted collection.

Pose selection comes from state rather than collision data. The snake toggles
frames from a pixel-position bit. The player uses a firing silhouette during
the alert/shot phases and a walking frame otherwise. Visibility flags decide
whether snake and shot are emitted.

`EraseTitleSceneDynamic` clears only the one or two cells touched by each
current shifted sprite. This targeted erase avoids flicker and prevents the
diamonds from being needlessly reconstructed.

## Shifted-sprite algorithm

`DrawTitleSceneShiftedSprite` receives a table with eight horizontal phases,
16 bytes per phase. `pixelX AND 7` selects the phase; `pixelX >> 3` selects the
left destination byte. Each of eight rows provides a left/right word which is
ORed into the bitmap.

The color plane always receives the left attribute. It receives the right one
only for a nonzero phase, when pixels actually spill into the neighboring byte.
The routine restores the bitmap plane before returning.

This is the same fundamental technique as gameplay actors, but the title's Y is
constant, so its destination calculation is smaller.

## Stage and terminal screens

`DrawLevelIntroScreen` selects the chamber name from `ChamberNamePointers`,
centers it on the text grid, and displays the key objective,
and a one/two/three-room message selected from `StageRoomCounts`. A key cell
reinforces the rule visually. All intro text uses `DrawCenteredIntroString`
to derive its column from the string length, rounding half-cell positions up.
The key icon uses the same centering convention.

Completion and game-over use a shared `DrawFinalScores` path. They display the
current score, recorded high score, optional new-high-score notice, and a Fire
prompt. Separate top-level routines differ mainly in title text. Completion and game-over
lines are centered on the 40-column text grid, rounding half-cell positions up;
score digit positions are derived from the centered template columns. The
return-to-title prompt has a one-column left adjustment on both end screens.

`DrawPresentationScore` splits the 0–99 hundreds byte with the HUD helper, then
draws the ten-thousands, tens, and ones digits at a writable column/row cursor.
The string template supplies the final `00`.

## Register contracts

Full-screen and title-update entries take input from state and output the named
display. `ClearTitleSceneSprite` takes absolute pixel X in `A`.
`DrawTitleSceneShiftedSprite` takes the phase table in `U`, X from
`TitleSceneSpritePixelX`, and color from `DrawCellColor`.
`DrawPresentationScore` takes lower hundreds in `A` and the ten-thousands digit
in `B`.

Entries may clobber `A`, `B`, `X`, `Y`, `U`, condition codes, and renderer
scratch. They balance `S`, preserve `DP`, and return on the bitmap plane.

## Educational points and pitfalls

- Templates plus targeted digit replacement avoid a general formatted-print
  system.
- A presentation animation can reuse sprite data while keeping a much smaller
  state and collision model than gameplay.
- OR compositing requires erasing the previous footprint before position or
  pose changes.
- When adding a shifted title sprite, both phase stride and two-byte spill must
  match the artwork generator/layout.

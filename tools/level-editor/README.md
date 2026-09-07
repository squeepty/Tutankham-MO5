# Tutankham Maze Workshop

The Maze Workshop is a dependency-free local web editor for the 21 readable
room templates and their actor-coordinate tables in `src/game/data.asm`.

Start it from the repository root:

```sh
node tools/level-editor/server.mjs
```

Then open <http://127.0.0.1:4173> in a browser. Use `--port <number>` to choose
another local port.

## Editing workflow

- Choose a named chamber and room in the left rail.
- Drag the wall or floor tools to reshape the maze. `Double terrain rows` is on
  by default because the game collapses pairs of physical rows into one logical
  maze row.
- Place treasures, the key, guardian spawners, warp endpoints, the exit, and
  the player start with the palette. Spawners, warps, and exits automatically
  occupy their required two vertical cells.
- Choose `Move`, or select an entry in `Placed objects`, then click its new
  location. Moving a spawner also updates its guardian start coordinate.
- Right-click any grid cell to erase it to floor. `Ctrl/Cmd+Z` and
  `Ctrl/Cmd+Shift+Z` undo and redo edits.
- Use `Export draft` for an intermediate JSON backup that does not change game
  source.
- Run `Validate`, then `Save to source`. Saving runs the same full campaign
  validator as the build and writes `src/game/data.asm` atomically only when all
  checks pass.

Grid coordinates shown by the editor are zero-based physical room coordinates,
matching the assembly tables. The packed map include remains generated output;
run `./tools/build.sh` after saving to regenerate it and build the game.

## Tests

```sh
node --test tools/level-editor/test/*.test.mjs
```

Chamber names are read from `ChamberNamePointers` in `src/game/data.asm`,
so the editor follows the game’s names and campaign order. Imported drafts
retain the current source names.

Each of the 21 room maps contains ten fixed, randomly scattered wall engravings:
ankh, Eye of Horus, scarab, pyramid, sun disk, and lotus. All six designs appear
in every room. `RoomWallDecorationPointers` in `src/game/data.asm` selects each
room's ten X/Y/symbol triples. Each engraving spans two horizontal wall cells;
the game, editor, and image exporter hide it if either cell is no longer a wall.
Decorations do not alter collision or the readable map tiles.

End-of-level `D` marker pairs also preview a 2×2 arcade-style double door
immediately to their right. Odd-numbered stages use yellow, even-numbered
stages use red. At the right map edge, only the left half is drawn if one
column remains. Artwork is read from `CellDoorYellow` / `CellDoorRed`; marker
positions and exit behavior stay in the source map.

The Exit tool selects `D` or `R` from the chamber's actual room count.
Room-transition arrows (`R`) snap to column 28, immediately left of the
right boundary. Placing or moving an arrow opens both corresponding cells in column 29
to show the passage. Validation and saving enforce this rule.

Door previews use `public/room-art.mjs`, shared with the PNG exporter. Changes
to assembly bitmaps appear on reload. Rebuild the game after saving maps and
run `node tools/export-level-images.mjs` to refresh the tracked previews.

Documentation checks run with `node tools/validate-docs.mjs` from the repository
root and are included in release preparation. They verify local Markdown file
links and assembly handbook coverage.

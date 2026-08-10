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

- Choose a stage and room in the left rail.
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

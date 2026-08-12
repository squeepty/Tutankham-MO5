# Tutankham for Thomson MO5

An original Motorola 6809 implementation of the maze-action structure of
Konami's *Tutankham*, written for the Thomson MO5. The opening seven rooms adapt
the four arcade maze layouts from the supplied ASCII reference; the game uses
original graphics, code, and one-bit sound effects, with no arcade ROM data or
extracted assets.

The current build contains nine variable-length stages and 21 playable rooms.
It includes the title and attract sequence, keyboard and
joystick controls, projectiles, guardians, keys, treasures, warps, room gates,
stage doors, scoring, lives, high scores, sound, and a guarded title-screen
cheat.

## Terminology

Player-facing documentation identifies every location by stage and room.
“Screen” is used only as a secondary sequential number when it helps locate old
test notes.

| Player-facing name | Sequential screen | Layout origin |
| --- | ---: | --- |
| Stage 1, Room 1 | 1 | Arcade Level 1 |
| Stage 2, Rooms 1–2 | 2–3 | Arcade Level 2, left/right |
| Stage 3, Rooms 1–2 | 4–5 | Arcade Level 3, left/right |
| Stage 4, Rooms 1–2 | 6–7 | Arcade Level 4, left/right |
| Stage 5, Rooms 1–2 | 8–9 | Original MO5 screens 2–3 |
| Stage 6, Rooms 1–3 | 10–12 | Original MO5 screens 4–6 |
| Stage 7, Rooms 1–3 | 13–15 | Original MO5 screens 7–9 |
| Stage 8, Rooms 1–3 | 16–18 | Original MO5 screens 10–12 |
| Stage 9, Rooms 1–3 | 19–21 | Original MO5 screens 13–15 |

Some internal symbols retain the earlier naming convention:

- `CurrentLevel` and `LEVEL_COUNT` mean the zero-based stage number.
- `CurrentRoom` is the zero-based room within that variable-length stage.
- `CurrentStageRoomIndex` is the flattened room index from 0 through 20.
- `StageRoomOffsets` and `StageRoomCounts` define the nine stage boundaries.
- `LEVEL_WIDTH` and `LEVEL_HEIGHT` describe one room's 30×22 tile grid.

New documentation and player-visible text should use **stage** and **room**.

## Gameplay

Guide the explorer through each maze, collect treasure, take the stage key, and
reach the exit:

- Every room contains three treasures.
- Room 1 of each stage contains that stage's key.
- Every non-final room contains a gate to the next room.
- The final room of each stage contains the stage door. Stage 1 therefore has
  its key and stage door in its only room.
- The explorer must hold the key before a gate or stage door opens.
- Five guardians emerge from three two-cell nests in each room; the fourth and
  fifth guardians reuse cleared nest locations.
- The explorer can fire left or right, but not vertically.
- Warps appear as paired up/down destinations and move the explorer between
  their aligned endpoints.
- Score and lives carry across rooms and stages. Each run starts with five
  lives, each life receives one flash bomb, and reaching 20000 points awards
  one extra life for the run. The stage key is refreshed when a new stage begins.
- The three highest scores remain available for the loaded session. Attract-mode
  demonstration scores are never recorded.

Guardian speed progression is currently disabled. Guardians move at 1.575
pixels per frame in every room, 70% of the explorer's 2.25-pixel-per-frame
average.

## Controls

| Action | Keyboard | Joystick |
| --- | --- | --- |
| Move | Arrow keys or `Z`/`S`/`Q`/`D` | Direction |
| Fire | `Space` | Fire button |
| Use the flash bomb | `X` | — |
| Start from title | `Space` | Fire button |

### Guarded title-screen cheat

Type `SQUEEPTY` while the title screen is active. The sequence must be entered
in order; a mismatch restarts matching from the first letter. Once accepted,
the unlock remains active until the program is reloaded.

After unlocking:

- `D` disables guardian contact hits on the explorer for the current run.
- `I` enables infinite lives for the current run.
- `N` enters the next room or stage through the current exit.

Before `SQUEEPTY` is accepted, `D` remains only the right-movement alias, while
`I` and `N` are ignored. The title confirms the unlock with
`CHEATS UNLOCKED N NEXT`; it intentionally does not advertise the other cheat
keys.

If the title remains idle for about ten seconds, a non-interactive demonstration
runs for about thirty seconds before returning to the title.

## Build

Requirements:

- A POSIX-compatible shell.
- Node.js for map packing, validation, and K7 packaging.
- `lwasm` from LWTOOLS for Motorola 6809 assembly.

Build everything from the repository root:

```sh
./tools/build.sh
```

The build performs five stages:

1. Validate all readable room templates and progression tables.
2. Pack the 30×22 tile templates into two-nibble map data.
3. Assemble the single 6809 translation unit and emit symbols/listing data.
4. Produce DECB `LOADM` and Thomson K7 container files.
5. Reject a program that reaches the protected `$9800` stack-safety boundary.

Generated files are placed in `build/`:

| File | Purpose |
| --- | --- |
| `tutankham-mo5.bin` | Raw image loaded at `$4000` |
| `tutankham-mo5.loadm` | DECB-style loadable image |
| `tutankham-mo5.k7` | Thomson cassette image |
| `tutankham-mo5.lst` | Assembly listing |
| `tutankham-mo5.map` | Symbol map |
| `maps-packed.asm` | Generated packed room data included by the assembler |
| `DCMOTO_LOAD.txt` | DCMOTO loading note |
| `DCMOTO_AUTOTYPE.txt` | Text suitable for emulator auto-typing |

`build/maps-packed.asm` is generated. Edit the readable templates in
`src/game/data.asm`, never the packed include.

## Run

### DCMOTO

Attach `build/tutankham-mo5.k7`, then enter:

```text
LOADM"",,R
```

### RetroArch with Theodore

Load `build/tutankham-mo5.k7` with the Theodore core and use the core's Thomson
cassette-loading workflow. Keyboard layout and joystick mapping depend on the
frontend configuration, so a real-input smoke test is recommended after
changing input code.

## Room authoring

Readable room templates live in the disabled assembly block in
`src/game/data.asm`. The assembler does not emit that text; the Node.js tools
parse it to validate and generate compact runtime data.

For visual editing, start the dependency-free local Maze Workshop:

```sh
node tools/level-editor/server.mjs
```

Open `http://127.0.0.1:4173` to paint walls, place or move predefined objects,
edit player and guardian starts, validate the full campaign, and save safely
back to `src/game/data.asm`. See
[`tools/level-editor/README.md`](tools/level-editor/README.md) for its shortcuts
and save workflow.

Each template is exactly 30 characters wide by 22 rows high. Its symbols are:

| Tile | Meaning |
| --- | --- |
| `#` | Solid wall |
| `.` | Walkable floor |
| `K` | Stage key |
| `T` | Treasure |
| `S` | Guardian nest tile; two vertical tiles form one nest |
| `V` | Downward warp endpoint |
| `A` | Upward warp endpoint |
| `R` | Vertical gate to the next room |
| `D` | Vertical door to the next stage |

To change a room:

1. Edit its readable template in `src/game/data.asm`.
2. Keep its start coordinates and guardian origins aligned with the template
   tables later in the same file.
3. Run `node tools/validate-content.mjs` for focused feedback.
4. Run `./tools/build.sh` to regenerate packed maps and the distributable images.
5. Play the affected room and its incoming/outgoing transition in an emulator.

The packed format stores two four-bit tile values per byte. A room occupies
330 packed bytes on disk and expands to the 660-byte `LevelMap` buffer when
loaded.

## Automated content checks

`tools/validate-content.mjs` treats each room as both a 30×22 physical grid and a
28×10 logical interior. The logical view removes the border columns and
collapses each pair of vertically doubled rows. It rejects content that violates
structural, progression, reachability, pacing, or spacing rules, including:

- exactly 9 stages with room counts `1/2/2/2/2/3/3/3/3`, and 21 unique
  templates;
- exactly 3 two-cell guardian nests and the correct two-cell room/stage exit;
- correct placement of the key, room gate, and final stage door;
- reachable player starts, guardian starts, key, treasure, exits, and warp
  destinations;
- a safe route to required progression items that does not pass through a nest;
- paired warps whose destination has an escape route;
- minimum key-to-treasure distance of 10 Manhattan cells;
- no treasure directly beside the player start or a guardian nest;
- no guardian nest directly beside a teleporter;
- no key directly beside an exit;
- guardian speed fixed at 70% of explorer speed while progression is disabled;
- maze-quality checks for the final 12 generated rooms, including route turns
  and open-area limits.

Stage 1, Room 1 is the reference room and intentionally keeps a few topology
exceptions. All other exceptions are explicit in the validator rather than
silently accepted.

## Code map

| Path | Responsibility |
| --- | --- |
| `src/main.asm` | Translation-unit root, hardware setup, main loop |
| `src/constants.asm` | Hardware addresses, dimensions, tile IDs, state values |
| `src/memory.asm` | Bank selection and writable display-memory clearing |
| `src/video.asm` | Cell addressing, text, glyph, and primitive rendering |
| `src/input.asm` | Active-low keyboard/joystick sampling and cheat gating |
| `src/sound.asm` | Blocking one-bit buzzer tones and gameplay cues |
| `src/timing.asm` | Busy-wait frame pacing |
| `src/game.asm` | Game-module include ordering |
| `src/game/data.asm` | Strings, graphics, readable rooms, packed-room tables |
| `src/game/state.asm` | Mutable game state and fixed actor pools |
| `src/game/flow.asm` | State machine, movement, collisions, AI, progression |
| `src/game/rendering.asm` | Static-map restoration and dynamic compositing |
| `tools/validate-content.mjs` | Structural and playability validation |
| `tools/pack-maps.mjs` | Readable-template to packed-map generator |
| `tools/make-k7.mjs` | Thomson cassette block writer |
| `tools/build.sh` | Reproducible validation, build, packaging, and size guard |
| `docs/ARCHITECTURE.md` | Runtime and data-design reference |
| `docs/NEXT_STEPS.md` | Verification backlog and release checklist |
| `prompt.md` | Audio direction and event-to-cue mapping |

## Implementation notes

- The code is assembled as one translation unit rooted at `src/main.asm`.
- Interrupts are masked; timing and sound are synchronous.
- The MO5 display uses separate bitmap and color planes selected through the
  system bank register.
- Static room tiles live in `LevelMap`. Dynamic actors are OR-composited and
  their old footprints are restored from that authoritative map.
- The explorer and guardians have eight horizontal shift phases for pixel-smooth
  motion while room collision remains tile based.
- Actor pools are deliberately fixed: three player shots and five guardians.

For the complete routine and state contracts, see
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Project provenance

This is a clean-room recreation for the Thomson MO5. It takes design inspiration
from the original arcade game's rhythm and event structure, while using original
source code, maps, graphics, and sound synthesis.

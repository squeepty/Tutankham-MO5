# Architecture

This document describes the implemented Thomson MO5 runtime, its data contracts,
and the invariants that code or content changes must preserve.

## Naming and indexing

The game contains 9 stages and 21 rooms. Stage room counts are
`1/2/2/2/2/3/3/3/3`.

- `CurrentLevel` is the zero-based stage index, despite its legacy name.
- `CurrentRoom` is the zero-based room index within the stage.
- `CurrentStageRoomIndex = StageRoomOffsets[CurrentLevel] + CurrentRoom`.
- `StageRoomOffsets` and `StageRoomCounts` define variable stage boundaries.
- Flattened room tables are ordered from Stage 1, Room 1 through Stage 9,
  Room 3.
- A flattened index of 0–20 is a storage detail, not the preferred user-facing
  name.
- `LEVEL_WIDTH` and `LEVEL_HEIGHT` mean the width and height of one room:
  30×22 tiles.

Readable templates retain their historical storage labels. Player-facing stage
and room identities come from the boundary tables rather than those labels.

## Translation unit and module order

LWASM sees one translation unit rooted at `src/main.asm`:

```text
main.asm
├── constants.asm
├── memory.asm
├── video.asm
├── input.asm
├── sound.asm
├── timing.asm
└── game.asm
    ├── game/data.asm
    ├── game/rendering.asm
    ├── game/flow.asm
    └── game/state.asm
```

The order is intentional:

- constants must exist before hardware and gameplay code uses them;
- data labels must exist before rendering and flow reference them;
- routine labels may reference state allocated later in the same translation
  unit;
- mutable state is kept together at the end of the game module so its layout is
  auditable.

There is no linker-level module boundary. Labels are globally visible, and
comments at each public routine are the calling convention.

## Platform and memory model

The target CPU is a Motorola 6809 running in the MO5's approximately 1 MHz
environment. The program disables interrupts and uses synchronous polling,
busy-wait pacing, and blocking sound generation.

| Region or boundary | Use |
| --- | --- |
| `$0000-$1F3F` | Banked MO5 bitmap or color display plane |
| `$4000` | Raw program load and execution origin |
| `$9800` | Build-time upper limit for program data |
| `$9FFF` downward | Runtime stack |

The `$9800` build guard leaves separation between the growing image and the
downward-growing stack. `tools/build.sh` calculates the assembled end address
and fails if the boundary is crossed.

### Display planes

The MO5 exposes bitmap and color memory through the same CPU address range.
`VIDEO_BANK_REG` selects which plane is visible:

- the bitmap plane stores pixel patterns;
- the color plane stores foreground/background attributes;
- a routine that switches banks must leave the expected bank selected or
  explicitly document otherwise.

`ClearBitmap`, `ClearColor`, and the render primitives centralize these switches.

## Coordinate systems

Several coordinate systems coexist:

| Name | Units | Typical state |
| --- | --- | --- |
| Physical room grid | 30×22 character cells | `LevelMap`, room templates |
| Logical gameplay grid | 28×10 interior cells | content validation |
| Pixel-space actor position | individual pixels | `PlayerPixelX`, `PlayerPixelY`, guardian arrays |
| Cell-space committed position | character cells | `PlayerX`, `PlayerY`, collision |
| Horizontal art phase | 0–7 pixel shifts | explorer/guardian shifted tables |

The physical grid is the runtime authority. The validation grid strips the
one-cell left/right border and collapses each pair of vertically doubled
interior rows. It is used to reason about nest pairs, branches, and maze
connectivity without counting the doubled artwork rows as separate paths.

The explorer's pixel coordinates permit smooth motion. Cell coordinates change
only when enough pixel motion has crossed a cell boundary; wall and interaction
tests use the committed cell position.

## Startup and frame loop

`Start` establishes the stack, masks interrupts, clears both display planes,
initializes input, and enters `GameInit`.

Each iteration of `MainLoop` performs:

1. `PollInput` captures one stable input snapshot.
2. `GameUpdate` advances exactly one state-machine frame.
3. `FrameDelay` applies the software frame cadence.

Sound routines are blocking. A cue consumes CPU time inside the current frame,
so its loop count affects perceived pacing as well as pitch and duration.

## Game state machine

`GameState` selects one of six top-level flows:

| Value | Symbol | Responsibility |
| ---: | --- | --- |
| 0 | `GAME_STATE_PLAYING` | Movement, shots, guardians, contacts, redraw |
| 1 | `GAME_STATE_COMPLETE` | Stage-complete presentation and next-stage setup |
| 2 | `GAME_STATE_OVER` | Game-over presentation and title return |
| 3 | `GAME_STATE_TITLE` | Title input, cheat sequence, idle timer |
| 4 | `GAME_STATE_INTRO` | Stage/room introduction |
| 5 | `GAME_STATE_ROOM_TRANSITION` | Move to the next room in the stage |

The value for playing is deliberately zero, which keeps several hot-path tests
short.

### Gameplay frame order

The playing-state update has a stable dependency order:

1. Read normalized movement and fire edges.
2. Update the explorer's pixel and cell position.
3. Resolve tile interactions such as treasure, key, warp, gate, and door.
4. Allocate or move player shots.
5. Move guardians and update their lifecycle state.
6. Resolve shot/guardian and explorer/guardian contact.
7. Restore old dynamic footprints from `LevelMap`.
8. Draw shots, guardians, effects, and the explorer in compositing order.
9. Refresh HUD fields whose values changed.

The explorer is drawn last so it remains legible when sprites overlap.

## Input architecture

`PollInput` reads the active-low MO5 keyboard matrix and joystick hardware once
per frame. It produces:

- a normalized held-direction mask;
- a held fire state;
- an edge-triggered action state for events that must not repeat every frame;
- title-screen cheat-sequence progress.

Arrow keys and the `Z`/`S`/`Q`/`D` aliases feed the same normalized movement
bits. `Space` and joystick fire feed the fire action. `X` consumes the run's
flash bomb through a separate action bit.

### Cheat gate

The title compares newly pressed keyboard selectors against `SQUEEPTY`.
Repeated letters are edge detected, so the two `E` characters require two real
keypresses. A mismatch resets progress while still allowing the current key to
begin a new match when appropriate.

Until the sequence completes, the `I` and `N` actions are removed from the
snapshot. After completion:

- `I` enables infinite lives for the run;
- `N` requests the next unlocked room or stage transition;
- the unlock persists until the program is reloaded.

The title displays `CHEATS UNLOCKED N NEXT`. The infinite-lives key remains
undisclosed on screen by design.

## Room data pipeline

Room content has a readable authoring representation and a compact runtime
representation.

```text
src/game/data.asm readable templates
             │
             ├── tools/validate-content.mjs ── structural/playability checks
             │
             └── tools/pack-maps.mjs ──────── build/maps-packed.asm
                                                  │
                                                  └── included by LWASM
```

Readable templates sit inside an `ifne 0` block. That makes them invisible to
the assembler while leaving a single reviewable source for the Node.js tools.

The packer maps each tile character to a four-bit value and stores two tiles per
byte. One 30×22 room therefore occupies 330 packed bytes. At room entry,
`LoadCurrentLevel` expands the chosen data to the 660-byte `LevelMap`.

`RoomTemplatePointers`, palettes, player starts, guardian starts, and guardian
speeds all share the same flattened Stage/Room ordering. Changing that order in
one table requires changing it everywhere.

## Tile and progression contracts

| Tile | Runtime role |
| --- | --- |
| `#` | Wall and collision barrier |
| `.` | Floor |
| `K` | Key pickup |
| `T` | Treasure pickup |
| `S` | One half of a two-cell guardian nest |
| `V` | Downward warp endpoint |
| `A` | Upward warp endpoint |
| `R` | Two-cell gate to the next room |
| `D` | Two-cell door to the next stage |

Every room has three two-cell guardian nests and three treasures.

- The first room has one key.
- Every non-final room has one `R` gate.
- The final room has one `D` door. In the single-room first stage, that room
  therefore holds both the key and final door.

The key remains owned across all rooms of a stage. Entering the next stage
refreshes the key and flash state while preserving the run's score and remaining
lives.

Warp endpoints are paired by direction. The destination lookup must land on
walkable content with a valid escape path.

## Rendering model

`LevelMap` is the authoritative static image of the current room. Dynamic actors
are never permanently painted into it.

For every moving object:

1. Remember its old footprint.
2. Restore the cells under that footprint from `LevelMap`.
3. Update its state and position.
4. Draw its new bitmap with OR compositing.

This design avoids a second full-screen back buffer and works with the MO5's
banked display planes. It also makes draw order significant.

### Cell addressing

`CellAddress` converts a physical cell coordinate to the byte address used by
the selected display plane. It uses a small self-modifying operand as scratch,
which is safe because:

- code is loaded into writable RAM;
- interrupts are masked;
- rendering is single-threaded and non-reentrant.

Callers must not assume `CellAddress` preserves scratch registers unless its
routine comment promises that.

### Shifted artwork

Explorer and guardian art has eight horizontal phases. A phase selects the
pre-shifted bitmap corresponding to the low three bits of pixel X. Vertical
movement uses scanline addressing, which allows arbitrary pixel Y positions.

Static room art remains cell aligned. Collision tests therefore stay small even
though dynamic actors move smoothly.

## Actor state

Mutable state is declared in `src/game/state.asm`.

### Explorer

The explorer has:

- pixel and committed cell positions;
- previous position for footprint restoration;
- facing and animation state;
- death/respawn timers;
- score, lives, key ownership, and flash inventory.

Motion follows a 2, 2, 2, 3-pixel cadence: nine pixels over four frames, or an
average of 2.25 pixels per frame.

### Player shots

The shot pool contains three fixed slots. Each slot records activation,
position, direction, and previous footprint information. Allocation scans for
an inactive slot; if all slots are active, the fire request is ignored.

Shots travel horizontally and are removed when they hit a wall, leave the room,
or strike a guardian.

### Guardians

The guardian pool contains five fixed slots. Its fields use a
structure-of-arrays layout: all states together, all X positions together, and
so on. A shared slot index selects the corresponding byte from each array.

Guardian lifecycle includes nest, emergence, active pursuit, hit/death effect,
and respawn timing. Starts in the data tables must coincide with the room's
three `S` nest pairs. Runtime slots four and five reuse the first and second
nest records; emergence waits until the selected nest cell is clear.

Speed uses an accumulator over an 80-unit denominator. The flattened speed table
must rise strictly from 126/80 in Stage 1, Room 1 to 162/80 in Stage 9, Room 3.

## Collision and interaction

Static collision queries `LevelMap`, not the screen bitmap. This separates
gameplay semantics from whatever dynamic art currently overlaps the display.

Important interaction rules:

- a wall rejects explorer and guardian movement;
- treasure becomes floor and increases score;
- the key becomes floor and sets stage-key ownership;
- a gate or door remains closed unless the key is held;
- a permitted gate triggers room or stage transition;
- warp contact relocates the explorer to the paired destination;
- a shot hitting a guardian enters the guardian's hit/death lifecycle;
- explorer/guardian overlap removes a life unless the run has infinite lives.

When mutable tiles are consumed or opened, both `LevelMap` and the visible
static layer must be updated so later footprint restoration does not resurrect
them.

## Title, attract mode, and demonstration

The title is a normal game state, not a separate program. It handles:

- start input from `Space` or joystick fire;
- cheat-sequence matching;
- high-score display;
- an idle timer of roughly ten seconds.

At idle expiry, a scripted demonstration runs for roughly thirty seconds. It
uses `DemoVisitMap` to track explored cells and feeds synthetic controls into
the normal gameplay machinery. Demo completion, death, or timeout returns to
the title. Demo scores never enter the high-score table.

## Score, lives, and high scores

The score is stored as binary state and converted to display digits when the HUD
or presentation screen needs it. Treasure, guardian hits, and progression events
award points through shared score routines.

Lives are decremented by the normal death flow. Infinite lives suppresses that
decrement but does not bypass collision, death animation, or respawn.

The high-score table contains three session-persistent entries. It is initialized
when the program starts, not every run. Game-over submission maintains descending
order.

## Sound and timing

Sound is synthesized through the MO5 one-bit buzzer output. `SoundTone` is the
primitive:

- register `A` controls the half-period and therefore pitch;
- register `B` controls the number of waveform iterations and therefore
  duration;
- the routine blocks and leaves the buzzer output low.

Named sound wrappers map gameplay events to short, locally synthesized cues.
Several timing contours are identified in `src/sound.asm` by their Bomb Jacques
design reference. Because sound and frame pacing are both busy loops, changes
should be tested at target clock speed rather than judged only from instruction
counts. The fourth and fifth active guardians shorten only the gameplay busy
wait to compensate for their additional simulation and rendering workload;
presentation states retain the full base delay.

## Content validation

`tools/validate-content.mjs` is part of the build, not an optional lint step.
It reconstructs the room tables and checks:

### Shape and progression

- correct stage, room, row, and column counts;
- allowed tile alphabet;
- exactly three nest pairs and the expected exit type;
- correct key placement by room;
- matching start and guardian-origin tables;
- unique room templates.

### Reachability and safety

- all required objects are reachable from the explorer start;
- all walkable cells belong to the connected room region;
- key and exit have nest-avoiding safe routes;
- warp endpoints are paired and their destinations can escape;
- the player start is not immediately exposed to a nest.

### Spacing

- treasure-to-treasure and key-to-treasure Manhattan distance is at least 10;
- a treasure is not directly adjacent to the explorer start;
- treasure and guardian nest retain more than one Chebyshev cell of clearance;
- guardian nests retain more than one Chebyshev cell from teleporters;
- collinear guardian nests and teleporters differ by more than two cells;
- guardian nests are at least four Chebyshev cells from the exit;
- a key is not directly adjacent to the exit.

### Maze quality

Every room starts on floor with a horizontal escape and a graph distance of at
least twelve logical cells to the nearest nest. Every room except Stage 1,
Room 1 must also provide a horizontal entrance lane at least five logical cells
long and avoid unrewarded cul-de-sac branches or isolated accessible pockets.

For the final twelve generated rooms, the validator additionally enforces:

- at least seven turns on the route to the exit;
- at least five branch cells along that route;
- at least twelve independent cycles;
- a maximum straight horizontal run of fifteen logical cells;
- a maximum open-square score of eighteen.

Stage 1, Room 1 is the explicit reference-room exception for selected topology
checks.

## Build and packaging

`tools/build.sh` is the authoritative pipeline:

1. Run content validation.
2. Generate `build/maps-packed.asm`.
3. Assemble at `$4000` to raw binary, listing, and symbol map.
4. Create a DECB `LOADM` image.
5. Wrap the raw image in Thomson K7 blocks.
6. Check the `$9800` upper boundary and write emulator loading notes.

`tools/make-k7.mjs` emits Thomson cassette blocks with leader, filename,
payload, execution address, padding, and checksums. Its output should be tested
as a cassette image rather than treated as an arbitrary raw binary.

## Invariants for contributors

When changing the runtime:

- preserve the single input snapshot per frame;
- keep `LevelMap` authoritative for static collision and restoration;
- update both the map and display when consuming a mutable tile;
- document register inputs, outputs, and clobbers for reusable assembly routines;
- treat the display bank as part of a rendering routine's contract;
- keep fixed-pool counts synchronized with their state arrays;
- avoid making sound or address helpers reentrant without removing their shared
  scratch assumptions.

When changing content:

- use Stage/Room terminology;
- edit readable templates, never generated packed data;
- preserve flattened table order across all per-room tables;
- update player and guardian origins with the map;
- run validation, rebuild, and manually play the affected transitions.

When changing build tools:

- fail with a precise room/template name;
- make generated output deterministic;
- keep validation before packing and assembly;
- retain the memory-boundary failure as a hard error.

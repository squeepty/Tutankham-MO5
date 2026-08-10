# Verification and next steps

The game is feature complete at the source level: all 9 stages and 21 rooms are
present, gameplay systems are connected, content validation is part of the
build, and distributable raw, `LOADM`, and K7 images can be generated.

The remaining work is primarily hands-on verification, timing calibration, and
release polish. This document is a working checklist rather than an
implementation roadmap.

## Current baseline

Implemented:

- nine stages with `1/2/2/2/2/3/3/3/3` unique rooms;
- three treasures and three guardian nests in every room;
- stage key, room gates, final stage doors, and paired warps;
- pixel-smooth explorer and guardian movement;
- three-slot projectile and five-slot guardian pools;
- collisions, death, respawn, lives, scoring, flash, and high scores;
- title, intro, room transition, stage completion, game over, and attract mode;
- keyboard and joystick controls;
- title-only `SQUEEPTY` cheat unlock for `I` and `N`;
- one-bit event sound effects;
- structural, progression, reachability, topology, spacing, and pacing validation;
- raw binary, DECB `LOADM`, and Thomson K7 packaging;
- build-time protection for the `$9800` stack boundary.

Terminology for every test report should be **Stage X, Room Y**. A sequential
screen number may be added in parentheses, but must not replace the Stage/Room
name.

## Highest-priority manual verification

Automated validation proves the room data is structurally consistent. It cannot
prove that movement feels good, sprites remain readable in every overlap, or
emulator input behaves identically to physical hardware.

### 1. Complete playthrough

Play from Stage 1, Room 1 through Stage 9, Room 3 without using the next-room
cheat.

For every room, confirm:

- the explorer enters on open floor and has time to react;
- all three treasures can be reached and collected;
- each guardian emerges from the visible nest that matches its logical origin;
- shot/guardian collisions award score once;
- the key can be collected in Room 1;
- gates in every non-final room remain closed before the key and open after it;
- each stage's final door remains closed before the key and advances afterward;
- paired warps land on the expected endpoint without immediate retriggering;
- no consumed pickup or opened exit reappears during sprite restoration;
- death and respawn do not strand the explorer inside a wall or actor;
- the HUD remains correct after score, life, key, and flash changes.

Record findings as, for example, `Stage 3, Room 2 (screen 8)`.

### 2. Targeted spacing regressions

Recheck the rooms whose objects were deliberately separated:

- Stage 2, Room 1: guardian nest and treasure no longer overlap visually.
- Stage 2, Room 2: the relocated treasure sits near the explorer's upper
  dead-end route without blocking the start.
- Stage 3, Room 2: guardian nest and treasure have visible clearance.
- Stage 6, Room 1: guardian nest and teleporter are no longer crowded.
- Stage 6, Room 3: guardian nest and stage exit have visible clearance.

The listed Stage/Room names correspond to the earlier sequential observations
for screens 2, 3, 5, 10, and 12.

### 3. Cheat boundary

Reload the program before this test.

1. On the title, press `I` and `N`; neither should have an effect.
2. Enter a near-match such as `SQUEEPTX`; the cheat must remain locked.
3. Enter `SQUEEPTY`, pressing and releasing for both `E` characters.
4. Confirm the title displays `CHEATS UNLOCKED N NEXT`.
5. Confirm no `I INF` text appears.
6. Start a run, press `I`, lose several lives, and verify lives do not decrement.
7. Use `N` to cross room and stage boundaries.
8. Reload the program and verify the unlock has been cleared.

When using `N` for other test work, always unlock it first. This ensures manual
reports reflect the actual title gate rather than an assumed debug build.

### 4. Title and attract sequence

Confirm:

- the second title line is horizontally centered with the first;
- `Space` or joystick fire starts a run;
- idle title time is approximately ten seconds;
- the demonstration runs for approximately thirty seconds;
- death, completion, or timeout returns to the title;
- demo score never enters the high-score table;
- entering part of `SQUEEPTY` does not accidentally start a run.

### 5. Input matrix

Test each path independently:

| Input path | Checks |
| --- | --- |
| Arrow keys | Four directions, opposing directions, diagonal transitions |
| `Z`/`S`/`Q`/`D` | Same normalized motion as arrows |
| `Space` | Edge-triggered shot allocation |
| `X` | One flash-bomb use per stage and empty-state feedback |
| Joystick direction | Movement, neutral return, opposing-axis behavior |
| Joystick fire | Same three-shot pool and edge behavior |

Pay special attention to host keyboard rollover. A problem that occurs only with
one emulator/frontend mapping should be recorded separately from a game logic
defect.

## Room-by-room smoke matrix

Use this compact matrix for release candidates:

| Stage | Rooms | Required focus |
| ---: | --- | --- |
| 1 | 1 | Arcade Level 1, single-room key/door flow |
| 2 | 1–2 | Arcade Level 2 left/right continuity |
| 3 | 1–2 | Arcade Level 3 left/right continuity |
| 4 | 1–2 | Arcade Level 4 left/right continuity |
| 5 | 1–2 | Original MO5 Rooms 2–3, new stage key |
| 6 | 1–3 | Original MO5 Rooms 4–6, teleporter and final-door spacing |
| 7 | 1–3 | Original MO5 Rooms 7–9, midgame pressure |
| 8 | 1–3 | Original MO5 Rooms 10–12, respawn safety |
| 9 | 1–3 | Original MO5 Rooms 13–15, final progression |

For each stage, verify every room-to-room transition and the final door to the
next stage or campaign completion.

## Timing and difficulty calibration

The current explorer cadence is 2, 2, 2, 3 pixels per frame. Guardian speed
increases strictly from 126/80 to 162/80 pixels per frame across the 21-room
sequence.

Measure on a target-speed emulator and, if available, physical hardware:

- average frame cadence with no sound playing;
- perceived pause caused by each blocking sound cue;
- time from nest state to an active guardian;
- time to traverse representative horizontal and vertical corridors;
- time available to react at each room entrance;
- whether late-stage guardians pressure rather than simply trap the explorer.

Do not change guardian speed to compensate for an emulator configured at the
wrong machine speed. Verify the MO5 profile and clock first.

## Audio verification

The audio design and event map are documented in `prompt.md`.

Check every named cue:

- shot fired;
- guardian hit;
- treasure collected;
- key collected;
- warp used;
- flash used;
- explorer death;
- respawn;
- room transition;
- stage completion or stage entry.

Confirm the buzzer returns low after each cue and that rapid event combinations
do not leave a sustained tone.

## Rendering stress tests

Exercise cases that stress footprint restoration and draw order:

- fire all three shot slots while two or more guardians cross them;
- collide the explorer with a guardian near a treasure or key;
- move horizontally through all eight sprite phases at both screen edges;
- change vertical direction while partly shifted between cells;
- use a warp while a shot is active near either endpoint;
- die adjacent to a gate, door, nest, or wall;
- open an exit while a guardian overlaps its neighboring cells;
- trigger hit effects where two guardians overlap.

Look for:

- trails from old sprite footprints;
- walls erased by OR compositing;
- pickups or exits reappearing;
- incorrect color-plane attributes;
- one-frame wraparound at screen boundaries;
- the explorer disappearing beneath another actor.

## Hardware and emulator compatibility

### DCMOTO

- Load `build/tutankham-mo5.k7`.
- Run `LOADM"",,R`.
- Verify cassette filename, load address, execution address, keyboard, joystick,
  color, and buzzer output.

### RetroArch Theodore

- Verify K7 loading from a clean frontend configuration.
- Record keyboard mapping and joystick port selection used for the test.
- Compare title idle timing and gameplay cadence with DCMOTO.

### Physical MO5, if available

- Test cassette transfer and loading reliability.
- Confirm the program does not approach the `$9FFF` downward-growing stack.
- Check color appearance on composite/RGB output as applicable.
- Verify the one-bit buzzer is silent after every cue.
- Test simultaneous direction and fire input on the physical keyboard.

## Technical cleanup candidates

These are optional improvements, not known blockers:

- rename legacy internal `Level` symbols to `Stage` in one controlled pass;
- extract explicit register-clobber macros or a routine-contract convention;
- add an emulator-driven smoke test that confirms title pixels or a memory
  signature after startup;
- add a machine-readable manifest for build outputs and memory ranges;
- add automated checks for Markdown links and terminology;
- measure worst-case stack depth and record it next to the image-size guard;
- separate blocking sound duration from frame pacing if playtesting shows
  noticeable event-dependent slowdown;
- investigate dirty-rectangle batching only if profiling shows restoration is a
  bottleneck.

Any internal renaming must preserve generated-table order and should land
separately from gameplay changes so regressions remain easy to isolate.

## Release checklist

- [ ] `node tools/validate-content.mjs` succeeds.
- [ ] `./tools/build.sh` succeeds from a clean `build/` directory.
- [ ] Raw binary, `LOADM`, and K7 outputs are regenerated from the same source.
- [ ] Program end address remains below `$9800`.
- [ ] Stage 1, Room 1 through Stage 9, Room 3 complete successfully.
- [ ] All targeted spacing regressions pass.
- [ ] Keyboard and joystick controls pass.
- [ ] `SQUEEPTY` correctly gates `I` and `N`.
- [ ] Title alignment and absence of `I INF` are confirmed.
- [ ] Attract mode returns safely and cannot submit a score.
- [ ] All audio cues end with the buzzer low.
- [ ] DCMOTO loading and execution pass.
- [ ] RetroArch Theodore loading and execution pass.
- [ ] Documentation names the release's actual binary size and tested emulator
      versions, if those details are published.
- [ ] Release notes distinguish automated validation from manual verification.

## Completed milestones

| Milestone | Delivered |
| ---: | --- |
| 1 | MO5 startup, display planes, input, first room |
| 2 | Explorer movement, collision, interactions |
| 3 | Shots, guardians, hits, death, respawn |
| 4 | Score, lives, HUD, sound |
| 5 | Three-room stage flow and progression |
| 6 | Seven-stage content set, attract mode, high scores |
| 7 | Content validator, compact map generation, K7 packaging, title cheat gate |

Future work should be evaluated against the manual evidence above rather than
treated as another feature milestone by default.

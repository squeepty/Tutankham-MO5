# `src/constants.asm`

Source: [constants.asm](../../../src/constants.asm)

## Purpose

This file is the compile-time vocabulary shared by every module. Its `equ`
symbols describe hardware addresses, memory placement, screen geometry, input
bits, tile bytes, game states, timing, pool sizes, movement rates, scoring, and
guardian behavior. It emits no bytes by itself, but changing one value can alter
memory allocation, loop bounds, table contracts, and gameplay simultaneously.

## Hardware and memory model

`PROGRAM_ORIGIN` and `STACK_TOP` define the two ends of writable program RAM.
The video, keyboard, buzzer, and joystick symbols map named concepts onto MO5
memory-mapped I/O addresses. Assembly code can then use `sta VIDEO_BANK_SELECT`
rather than scattering unexplained hexadecimal literals.

The MO5 exposes bitmap and color planes through the same `$0000-$1F3F` window.
`VIDEO_BYTES_PER_ROW`, `VIDEO_ROWS`, and the derived byte/word counts support
addressing and whole-screen clears. Text uses 40 columns by 25 eight-scanline
rows, which matches the 320×200 bitmap organization.

## Normalized input representation

Physical keyboard selectors and joystick bits are deliberately separate from
logical action masks. The input layer converts both devices into a direction
byte and an action byte. This lets game logic ask for `ACTION_FIRE_MASK` without
knowing whether Space or the joystick button caused it.

The selector constants encode MO5 keyboard matrix row/column choices. They are
hardware data, not ASCII. Cheat-only actions have masks alongside ordinary
actions, but the input module refuses to sample them until the title sequence
has unlocked the session.

## World and presentation geometry

Each room is a 30×22 physical-cell map placed at screen column 5, row 2. The HUD
occupies the top rows and the status line occupies row 24. `LEVEL_CELL_COUNT` is
derived rather than repeated, preventing buffer/table loops from silently
disagreeing with the dimensions.

Tile constants use their readable map characters as runtime values. This costs
no conversion after unpacking and makes debugger memory legible: a wall is
literally `'#'`, treasure is `'T'`, and so on.

## State-machine constants

`GAME_STATE_PLAYING` is zero so the hottest dispatcher path can use `BEQ`.
Other values select completion, game over, title, intro, and room-transition
presentation. Timers are expressed in simulation frames. Title-scene phase
constants form a second small state machine dedicated to the attract animation.

## Movement and numeric representations

Explorer movement carries a repeating 2,2,2,3-pixel budget, averaging 2.25
pixels per simulation frame. A logical cell is committed after eight pixels.
Guardians use eightieth-pixel fixed-point accumulation: `EnemySpeedByRoom`
adds units into a remainder and extracts whole pixels whenever it reaches
`ENEMY_SPEED_SCALE`.

Scores are stored in hundreds. `TREASURE_BASE_SCORE_HUNDREDS = 5` therefore
means 500 points, and the room-local streak multiplies that base by 1–3. The
extra-life threshold is represented by its ten-thousands digit.

## Fixed pools and guardian identities

`SHOT_COUNT` and `ENEMY_COUNT` size both loops and structure-of-arrays storage.
`ENEMY_SPAWN_COUNT` stays at three because five live slots share three nest
records. Guardian behavior constants select direct chase, interception, or
alternating wander/chase logic. Look-ahead and phase-bit constants tune those
algorithms without embedding magic numbers in control flow.

## Safe modification rules

- Treat dimensions and pool counts as schema changes: search for all arrays and
  generated tables before editing them.
- Keep action bits unique powers of two.
- Keep frame timers within one byte unless the consuming state becomes wider.
- Rebuild after any memory/timing change; the build checks the `$9800` guard.
- Test speed changes at target clock rate because loop cost and blocking audio
  affect perceived time.

This file is an excellent lesson in using named invariants to turn low-level
code into a readable domain model.

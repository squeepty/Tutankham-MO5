# `src/game/state.asm`

Source: [state.asm](../../../../src/game/state.asm)

## Purpose

This file defines all writable game memory. There is no allocator and no
language runtime: scalar variables use `fcb`, fixed-capacity arrays use `rmb`,
and labels are their addresses. Zero generally means inactive, unavailable, or
no pending work.

The state is placed after executable code and immutable data by `game.asm`.
Some variables have initialized values, notably the seed high-score table and
demo random state, while `InitGame` and `ResetLevel` establish the rest.

## Explorer motion model

The player owns three related coordinate forms:

- `PlayerX/Y` is the committed collision cell.
- `PlayerTargetX/Y` is the adjacent cell selected for the current step.
- `PlayerPixelX/Y` is the live room-local pixel position used by rendering.

`PlayerPixelsRemaining` makes an eight-pixel cell crossing a transaction. The
target is checked before movement starts, pixel coordinates advance over
several frames, and committed cell coordinates change only when the remaining
distance reaches zero. Direction, animation, speed phase, budget, and carry
bytes make the partial movement deterministic.

Separate dirty/composite flags coordinate drawing. `PlayerVisualDirty` records
a changed pose or position, `PlayerRedrawPending` requests old-background
restoration, and `PlayerCompositePending` requests another player draw after a
guardian or projectile may have touched its footprint.

## Rules and session state

Inventory stores the key and the single-use flash bomb. Lives, invulnerability,
visibility, death timing, and optional cheat flags describe the current run.
`TreasureStreak` is room-local and resets on room load or death; values 1, 2,
and 3 drive the 500/1,000/1,500-point rewards.

Scores are stored in hundreds because all awards end in `00`. A separate
ten-thousands digit plus a 0–99 hundreds byte represents up to 99,900 without
general 16-bit decimal conversion. Three pairs hold a descending high-score
table. They deliberately survive ordinary run resets.

## Presentation and demo controller

Presentation timers and phase bytes implement title animation without a large
object model. The title cheat tracks sequence progress and the currently held
identity so one physical hold cannot be counted repeatedly.

Attract mode has its own direction choices, target cache, pseudo-random byte,
fire/flash timers, and a 660-byte visit map. `$FF` is used as an invalid
room/key/score sentinel where zero is a valid value. The demo controller can
therefore invalidate a cache without allocating a second flag for every field.

## Stage and room selection

`CurrentLevel` is a legacy name for zero-based stage 0–8; `CurrentRoom` is the
room within that stage. `CurrentStageRoomIndex` caches their flattened table
index. Wall color, enemy table offsets, transition-wipe coordinates, status
lengths, and presentation number positions are nearby because room setup and
screen presentation use them together.

## Structure-of-arrays actor pools

Shots and guardians use fixed-capacity pools. Instead of storing complete actor
records consecutively, each field is an array:

```text
EnemyActive[5], EnemyX[5], EnemyY[5], EnemyPixelX[5], ...
```

This structure-of-arrays layout makes a hot pass such as “clear every active
flag” a tight indexed loop and lets each operation touch only the fields it
needs. `CurrentActorIndex` is the implicit slot for many helper routines.

Shots remain cell-aligned and need active, X, Y, and signed direction arrays.
Guardians mirror the player's committed/target/pixel movement model and add
per-slot animation, respawn, hit-effect, grace, decision-phase, speed, and carry
state. Individual timers prevent five identical slots from behaving in lockstep.

## Shared scratch versus durable state

`Candidate*`, `Query*`, map-drawing fields, number-conversion bytes, and sprite
footprint bounds are shared scratch. They reduce stack traffic and instruction
count, but they are not stable across arbitrary subroutine calls. A routine that
needs a scratch value after calling another scratch-using routine must save it.

This is an important assembly distinction: a globally named byte is not
necessarily persistent game state. Comments and call contracts provide the
lifetime information that a compiler would otherwise enforce.

## Room workspaces

`LevelMap` is the mutable, unpacked 30×22 authority for collision and static
redrawing. Collecting an item changes its tile to floor. Sprite restoration
looks up this buffer rather than storing background pixels.

`DemoVisitMap` is a parallel 660-byte workspace of visit counts. It helps the
demo prefer unexplored directions and escape short loops without affecting the
real map.

## Data-layout contract

This file contains storage rather than routines, so its “register contract” is
an indexing contract:

- keep every two-byte score pair adjacent;
- keep each actor array exactly `SHOT_COUNT` or `ENEMY_COUNT` bytes;
- do not insert fields into the middle of an array;
- treat `CurrentActorIndex` and scratch bytes as clobbered by actor helpers;
- leave `LevelMap` and `DemoVisitMap` sized to `LEVEL_CELL_COUNT`;
- initialize new run state in the correct lifecycle routine rather than relying
  accidentally on the byte assembled into the executable image.

The source reads like a hand-built schema. Studying its group boundaries is the
best way to understand which state belongs to the machine, a session, a room,
an actor slot, or one temporary calculation.

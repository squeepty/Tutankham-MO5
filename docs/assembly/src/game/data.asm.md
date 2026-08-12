# `src/game/data.asm`

Source: [data.asm](../../../../src/game/data.asm)

## Purpose

This file is the game's immutable database. It keeps presentation strings,
keyboard-sequence data, cell and sprite art, human-readable chamber sources,
packed runtime maps, campaign topology, tuning tables, and guardian starting
records together. Logic refers to labels and table indices rather than embedding
room-specific values in instructions.

The ordering matters because the project is one translation unit and because
several flattened tables share the same stage/room index. Runtime code should
still address rooms through `RoomTemplatePointers`; physical adjacency is a
build detail, not an API.

## Text resources

All UI strings are zero-terminated and are consumed by `DrawString` or a
specialized number renderer. The set covers title/high-score presentation,
controls, stage introductions, game-over/completion screens, HUD labels, and
short status explanations for gameplay events.

The treasure strings encode a game rule as user feedback: consecutive room
pickups award 500, 1,000, then 1,500 points. Status messages are deliberately
data, allowing wording changes without touching control flow. Fixed-position
numeric fields such as `SCORE 00000` reserve cells that rendering code later
overwrites with digits.

## Cheat-sequence tables

`TitleCheatKeySelectors` lists the seven distinct keyboard matrix selectors used
by the title cheat. `TitleCheatSequence` contains one-based identities spelling
the sequence S, Q, U, E, E, P, T, Y. Zero remains available to mean “no cheat
key held.” The title controller compares identities, not raw hardware selector
values, which keeps repeated letters and release handling straightforward.

## Cell and shifted artwork

Cell art consists of eight bytes, one bitmap byte per scanline. Walls, exits,
keys, treasure, nests, warps, projectiles, hit effects, life icons, and flash
indicators can therefore use the generic cell renderer.

Moving actors need horizontal pixel precision. Their tables contain pre-shifted
8-row frames, indexed by `pixelX AND 7`. A nonzero phase spills into the next
screen byte, so each row contains both a left and right byte. This trades ROM
space for a cheap draw path: the runtime selects a phase instead of shifting
every row during every frame.

Guardian art is additionally grouped by direction and animation frame. Player
art separates walking and firing poses. The table layout is part of the
renderer contract; changing a frame's width or stride requires updating its
index arithmetic.

## Readable maps and packed maps

The chamber templates inside `IFNE 0` are excluded by the assembler but remain
plain text for the JavaScript content tools. Each template is a 30 by 22 ASCII
grid. Symbols describe walls, floor, key, exactly three treasures, guardian
nests, paired warps, intermediate room exits, and the final stage exit.

`tools/pack-maps.mjs` translates those grids into `build/maps-packed.asm`. Two
four-bit tile codes fit in each byte, so one 660-cell room occupies 330 bytes.
`PackedTileValues` maps each nibble back to the runtime ASCII tile values used by
collision and rendering. The nibble order must remain identical to the packer.

This dual representation is educational and practical: humans review an ASCII
maze, tools validate it, and the target pays only half a byte per cell in the
binary. `LoadCurrentRoomMap` expands the selected room into writable `LevelMap`.

## Campaign and room tables

Twenty-one rooms are flattened in stage order. To locate a room, runtime code
computes:

```text
CurrentStageRoomIndex = StageRoomOffsets[CurrentLevel] + CurrentRoom
```

`StageRoomCounts` gives the variable number of rooms per stage. Every room-wide
table—pointers, colors, player starts, speed—uses that same flattened index.
Guardian placement tables use three consecutive nest records per room, so their
base is `CurrentStageRoomIndex * 3`.

`EnemySpeedByRoom` currently holds a constant 126 in eightieth-pixel units,
about 70% of explorer speed. Keeping it as a table preserves a clean extension
point for campaign difficulty without changing movement code.

## Guardian identities and spawn records

`EnemyBehaviorBySlot` assigns identities to the five persistent runtime slots:
direct chaser, interceptor, direct chaser, temporary wanderer, direct chaser.
There is intentionally no corridor-patrol behavior. An identity survives
deactivation and respawn because it belongs to the slot, not to a nest.

Each room supplies three nest coordinates, initial horizontal direction signs,
and staggered animation timers/frames. Five guardians reuse those three records
by slot modulo three. Staggering avoids a mechanical formation in which every
actor turns, animates, and respawns on the same frame.

## Data contracts and safe changes

This file contains no callable routines and has no register contract. Its
contracts are structural:

- every string passed to `DrawString` ends in zero;
- every cell pattern is exactly eight bytes;
- shifted sprite strides match renderer multiplication;
- every flattened per-room table contains 21 entries;
- every guardian-start table contains three entries per room;
- map nibble values agree with `tools/pack-maps.mjs`;
- offsets and counts describe all rooms without overlap or omission.

When adding artwork or room fields, document the table stride beside both the
producer and consumer. A misplaced `fcb` does not produce a type error—it turns
all following index calculations into valid reads of the wrong bytes.

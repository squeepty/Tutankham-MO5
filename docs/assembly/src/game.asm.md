# `src/game.asm`

Source: [game.asm](../../../src/game.asm)

## Purpose

This is the game-layer include manifest. It contains no executable routines;
its job is to impose a readable order on data, rendering, rules, and state while
preserving a single LWASM translation unit.

## Include order

1. `game/data.asm` defines strings, artwork, maps, and lookup tables.
2. `game/rendering.asm` defines presentation, world, actor, restoration, and HUD
   routines that consume those assets.
3. `game/flow.asm` defines state machines, player rules, projectiles, guardians,
   progression, and scoring.
4. `game/state.asm` allocates mutable variables and buffers last.

Forward references make this order possible: rendering and flow code can refer
to writable labels that are not allocated until `state.asm`. Keeping state last
groups the memory layout for auditing and prevents routines from being buried
between arrays.

## Why manifests are useful

Assembly includes provide no namespace or access control. A manifest supplies a
human-scale module boundary anyway: reviewers can see the architectural layers
without opening thousands of lines, and each child file can focus on one
algorithm. The final addresses remain the same as if all text were pasted into
one file in this order.

## Dependency rule

Avoid adding circular *conceptual* dependencies merely because the assembler
allows them. Rendering may read state and data; flow may call rendering;
initialization may reset both. If a new subsystem needs a different order,
document the reason here and verify that no data accidentally falls into an
execution path.

This tiny file demonstrates a useful educational distinction: source-code
modularity and binary modularity are separate design choices.

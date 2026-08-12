# Assembly handbook

This handbook explains the complete 6809 assembly implementation of Tutankham
MO5. Every source `.asm` file has its own companion page under `docs/assembly`,
in a directory that mirrors `src/`. The goal is not merely to list labels: the
pages explain why the code is shaped this way, which algorithms it uses, how
state moves through the program, and which hardware constraints drive the
design.

Start with [main.asm](src/main.asm.md), then follow the suggested reading order
below. Keep the source open beside the handbook; routine names and instruction
sequences are deliberately discussed rather than copied in full.

## 6809 vocabulary used throughout

| Register | Role in this project |
| --- | --- |
| `A`, `B` | Eight-bit arithmetic, flags, byte values, coordinates, and loop counts |
| `D` | The combined 16-bit `A:B` register, useful for multiplication, paired state, and addresses |
| `X`, `Y`, `U` | Sixteen-bit index registers for tables, video addresses, sprites, and long loops |
| `S` | Hardware stack; subroutine return addresses and temporary saved registers |
| `DP` | Direct-page register; left unchanged by the game |
| `CC` | Condition codes used by branches such as `BEQ`, `BLO`, and `BHI` |

Important directives include `equ` for constants, `org` for placement, `fcb`
and `fdb` for byte/word data, `fcc` for strings, `rmb` for writable storage,
`include` for textual composition, and `end` for the execution entry point.

The project assembles as one translation unit. An include file is not a linked
object and does not create a namespace: every label remains globally visible,
and forward references are resolved after the complete source has been read.
The many small files are therefore an aid to reasoning and review, not a change
to the machine-code model.

## Suggested reading order

1. [main.asm](src/main.asm.md), [constants.asm](src/constants.asm.md), and
   [memory.asm](src/memory.asm.md) establish placement and execution.
2. [video.asm](src/video.asm.md), [input.asm](src/input.asm.md),
   [sound.asm](src/sound.asm.md), and [timing.asm](src/timing.asm.md) explain the
   MO5-facing platform layer.
3. [game.asm](src/game.asm.md), [data.asm](src/game/data.asm.md), and
   [state.asm](src/game/state.asm.md) explain composition and the data model.
4. Read the flow pages in frame order: progression runtime, title/demo, player,
   projectiles, guardians, damage, and progression/scoring.
5. Read the rendering pages from static world drawing through actor compositing,
   footprint restoration, and HUD output.

## One gameplay frame

The central loop is intentionally easy to trace:

1. `WaitMainLoopFrame` supplies deterministic pacing.
2. `RunGameFrame` polls input once and dispatches the current game state.
3. In play, the explorer updates first and may collect or trigger a transition.
4. Shots restore their old cells, move, collide, and redraw.
5. Guardians restore, decide, move, animate, collide, and redraw.
6. The explorer is composited again when another actor may have drawn beneath
   it.

The static `LevelMap` buffer is the authority throughout. Dynamic graphics are
never treated as collision data. Before a moving sprite changes, the renderer
reconstructs every covered cell from `LevelMap`, then draws the new sprite with
OR compositing. This restoration discipline replaces per-sprite background
buffers and is one of the most important algorithms in the project.

## File-by-file guide

### Translation unit and platform

| Source | Companion guide |
| --- | --- |
| `src/main.asm` | [Program entry and main loop](src/main.asm.md) |
| `src/constants.asm` | [Hardware, geometry, rules, and tuning constants](src/constants.asm.md) |
| `src/memory.asm` | [Address-space and stack contract](src/memory.asm.md) |
| `src/video.asm` | [Video planes, cells, text, and glyphs](src/video.asm.md) |
| `src/input.asm` | [Keyboard/joystick normalization and edge detection](src/input.asm.md) |
| `src/sound.asm` | [One-bit synthesis and event cues](src/sound.asm.md) |
| `src/timing.asm` | [Busy-wait frame timing](src/timing.asm.md) |
| `src/game.asm` | [Game-layer include manifest](src/game.asm.md) |

### Game data and state

| Source | Companion guide |
| --- | --- |
| `src/game/data.asm` | [Strings, artwork, maps, and lookup tables](src/game/data.asm.md) |
| `src/game/state.asm` | [Writable state and structure-of-arrays pools](src/game/state.asm.md) |
| `src/game/flow.asm` | [Flow include manifest](src/game/flow.asm.md) |
| `src/game/rendering.asm` | [Rendering include manifest](src/game/rendering.asm.md) |

### Game logic and algorithms

| Source | Companion guide |
| --- | --- |
| `flow/title-lifecycle.asm` | [Session, title, game, and demo setup](src/game/flow/title-lifecycle.asm.md) |
| `flow/title-demo.asm` | [Cheats, attract animation, and demo pathfinding](src/game/flow/title-demo.asm.md) |
| `flow/progression-runtime.asm` | [Run reset, room loading, pacing, and frame dispatch](src/game/flow/progression-runtime.asm.md) |
| `flow/progression-score.asm` | [Room/stage transitions, scoring, and high scores](src/game/flow/progression-score.asm.md) |
| `flow/player.asm` | [Explorer movement, interactions, and treasure streaks](src/game/flow/player.asm.md) |
| `flow/player-damage.asm` | [Contact, death, lives, and respawn](src/game/flow/player-damage.asm.md) |
| `flow/projectile-pool.asm` | [Shot-pool reset](src/game/flow/projectile-pool.asm.md) |
| `flow/projectiles.asm` | [Shots, collision, hit testing, and flash bomb](src/game/flow/projectiles.asm.md) |
| `flow/guardian-pool.asm` | [Guardian initialization and shared nests](src/game/flow/guardian-pool.asm.md) |
| `flow/guardian-deactivation.asm` | [Guardian hit and respawn scheduling](src/game/flow/guardian-deactivation.asm.md) |
| `flow/guardians.asm` | [Guardian movement budgets, AI identities, and reservations](src/game/flow/guardians.asm.md) |
| `flow/map.asm` | [Two-dimensional map addressing](src/game/flow/map.asm.md) |

### Rendering and restoration

| Source | Companion guide |
| --- | --- |
| `rendering/presentation.asm` | [Title, attract scene, stage cards, and terminal screens](src/game/rendering/presentation.asm.md) |
| `rendering/world.asm` | [Gameplay screen, status, transitions, and tile dispatch](src/game/rendering/world.asm.md) |
| `rendering/hud.asm` | [Score conversion, lives, and indicators](src/game/rendering/hud.asm.md) |
| `rendering/actors/player.asm` | [Shifted explorer compositing](src/game/rendering/actors/player.asm.md) |
| `rendering/actors/guardian-list.asm` | [Guardian draw dispatcher](src/game/rendering/actors/guardian-list.asm.md) |
| `rendering/actors/guardians.asm` | [Shifted guardians and damage effects](src/game/rendering/actors/guardians.asm.md) |
| `rendering/actors/projectiles.asm` | [Cell-aligned projectile drawing](src/game/rendering/actors/projectiles.asm.md) |
| `rendering/restoration/player.asm` | [Explorer footprint reconstruction](src/game/rendering/restoration/player.asm.md) |
| `rendering/restoration/guardians.asm` | [Guardian and hit-effect reconstruction](src/game/rendering/restoration/guardians.asm.md) |
| `rendering/restoration/projectiles.asm` | [Projectile cell reconstruction](src/game/rendering/restoration/projectiles.asm.md) |
| `rendering/restoration/death-effect.asm` | [Death-effect reconstruction](src/game/rendering/restoration/death-effect.asm.md) |

## How to study or extend the program

Make one conceptual change at a time and rebuild with `./tools/build.sh`.
Inspect `build/tutankham-mo5.lst` when an instruction sequence or address is
unclear. For rendering work, verify which display plane is selected on every
return path. For simulation work, distinguish committed cell coordinates from
in-flight pixel coordinates. For actor work, remember that `CurrentActorIndex`
and the shared scratch fields are implicit inputs. Finally, test on a target-
speed emulator: cycle cost, blocking sounds, and frame cadence are part of the
game behavior, not merely performance details.

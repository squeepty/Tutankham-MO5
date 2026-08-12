# `src/game/flow/title-demo.asm`

Source: [title-demo.asm](../../../../../src/game/flow/title-demo.asm)

## Purpose

This fragment contains three related controllers that run outside ordinary
human play: the title cheat recognizer, the scripted title-band animation, and
the autonomous attract-mode driver. It also owns the unlocked in-game cheat
actions because their state and presentation originate on the title.

## Cheat-sequence state machine

`UpdateTitleCheatSequence` scans the seven distinct matrix selectors used by
S,Q,U,E,E,P,T,Y. The table converts physical selectors to one-based identities.
`TitleCheatHeldKey` supplies per-key edge detection so a held E counts once and
the repeated E still requires release and another press.

On a correct identity, progress advances. On mismatch, the recognizer resets to
one when the new key is S (allowing it to begin a fresh prefix immediately), or
zero otherwise. Completing the table sets `CheatUnlocked` and redraws the title
message. Accepted cheat keys also reset title inactivity, preventing the demo
from starting during entry.

Once unlocked, input sampling exposes three actions. `ToggleInfiniteLives`
toggles its run flag, replenishes lives when enabling it, and refreshes HUD and
status. `DisableGuardianHits` is a one-way run switch so the D/right key cannot
later turn protection off accidentally.

## Title timing and scripted scene

`UpdateTitleIdleTimer` approximates seconds with a frame countdown. Any held
direction or action resets inactivity; reaching the configured seconds calls
`StartDemo`. `UpdateDemoTimer` applies the inverse countdown and returns a demo
to the title after its allotted duration.

The title animation is an explicit phase machine. `ResetTitleScene` places the
explorer at center, makes both diamonds present, hides the snake/shot, and begins
with a hold. `UpdateTitleScene` dispatches these phases:

1. approach the first snake and pause in alert;
2. fire a right-moving shot until it reaches the snake;
3. repeat the alert/shot with the second snake;
4. walk left, removing each diamond at its pickup threshold;
5. return to center and hold;
6. restore both diamonds and repeat.

Each moving phase erases the prior dynamic band, changes pixel coordinates or
visibility, then tail-jumps to the scene renderer. Collision is scripted as an
X-coordinate comparison because this presentation is not the game world.
Normal hit, shot, and pickup sounds connect the vignette to gameplay vocabulary.

## Synthetic demo input

Demo mode does not move the explorer directly. `BuildDemoInput` clears the
normalized direction/action fields, computes decisions, then lets the ordinary
player pipeline consume them. A move already in flight keeps its selected held
direction; at cell boundaries the controller chooses again.

Action logic fires only when an active guardian shares the player's committed
row and updates facing toward it. A delayed, one-time flash press demonstrates
the normal flash-bomb rule. Retry and interval timers keep shots intentional
rather than continuous.

## Objective selection

`UpdateDemoTarget` caches its target by flattened room index and `HasKey`. Before
the key it scans `LevelMap` for `TILE_KEY`. Afterward it seeks an intermediate
room exit or, in the last room, the final exit. `FindDemoTargetTile` is a row-
major scan that records the first match.

The cache rebuilds only when the room or key state changes. This avoids scanning
all 660 cells every decision while remaining correct after collection and room
loading.

## Visit map and direction scoring

`DemoVisitMap` parallels `LevelMap`. On entering a room it is cleared; every
decision increments the player's current cell up to `$FE`. Candidate directions
are scored by the destination visit count, and the least-visited legal cell
wins.

Candidates are considered in a useful order: axes that approach the objective,
current momentum, then all four directions in one of two pseudo-random orders.
The immediate reverse direction is withheld until every other choice fails.
Random bits choose axis/fallback ordering, so equal candidates do not always
produce the same route.

`DemoDirectionIsSafe` is stricter than ordinary player collision. It rejects
walls, locked exits, and every active guardian's committed or targeted cell.
This is local hazard avoidance rather than full pathfinding. The objective bias,
visit penalty, momentum, and reverse fallback together form a compact wall-
following/exploration heuristic suitable for the small mazes.

## Pseudo-random mixer

`AdvanceDemoRandom` shifts an eight-bit state and conditionally XORs `$B8`, an
LFSR-like feedback step. Current physical direction/action bits are XORed in as
additional entropy. Zero is replaced with `$A5` to avoid a stuck state. This is
used for presentation variety, not cryptography.

## Register contracts

Most exported helpers take inputs from global state and may clobber `A`, `B`,
`X`, `Y`, `U`, and condition codes. `FindDemoTargetTile` takes the desired tile
in `A` and returns nonzero `A` when found. `DemoDirectionIsSafe` takes a DPAD
direction in `A`, leaves its candidate in shared scratch, and returns nonzero
`A` when traversable and unreserved. All routines balance `S` and preserve `DP`.

## Educational points and pitfalls

- Both scripted animation and game modes can be represented by byte-valued
  phase machines.
- Synthetic normalized input maximizes reuse and tests the real rules during
  attract mode.
- A target cache plus local heuristic is much cheaper than breadth-first search
  and sufficient for curated maps.
- Visit counts supply memory to an otherwise greedy controller and reduce loops.
- Demo safety checks target reservations, not merely current actor cells.

# `src/game/flow/progression-score.asm`

Source: [progression-score.asm](../../../../../src/game/flow/progression-score.asm)

## Purpose

This fragment changes rooms and stages, enforces the key gate, synchronizes
instantaneous player placement, mutates collected tiles, adds score, awards an
extra life, and maintains the three-entry session high-score table.

## Room and stage progression

`TryRoomTransition` compares `CurrentRoom` with the current stage's room count.
If another room remains, it enters a transition state, increments the room,
loads/unpacks it, resets transient motion and actors, performs the diagonal
screen wipe, restores playing state, and draws the new actors/HUD/status.

If the current room is the last one, the same entry falls into `TryPlayerExit`.
That routine first checks `HasKey`; the exit is locked without it. Treasures are
optional for progression. A successful final-room exit awards 1,000 points.

Unless Stage 9 has just ended, it advances the stage, returns to room zero,
clears the key, loads/reset actors, and enters the timed level-introduction
state. Completing all nine stages records the score and displays completion.
Demo completion returns directly to the title instead.

The key survives intermediate room changes within a stage and is cleared only
when advancing to the next stage. The flash inventory also survives room
changes within a stage. Advancing to the next stage restores one flash bomb,
including when the previous stage's flash was spent; unused flashes do not stack.

## Coordinate and map helpers

`SyncPlayerPixelPosition` multiplies committed cell coordinates by eight and
clears every in-flight movement field. Resets, respawns, and warps use it when a
visible cell change must be instantaneous.

`ClearCandidateTile` calculates the `LevelMap` address for `CandidateX/Y` and
writes `TILE_FLOOR`. The renderer and collision system share that mutable map,
so one write removes a collected object from both systems.

## Score representation and addition

Scores are measured in hundreds. `ScoreTenThousands` is the leading decimal
digit and `ScoreHundreds` ranges from 0 to 99; the display appends two zeroes.
`AddScore` accepts the award in `A`, carries at 100 hundreds, and saturates at
9/99 = 99,900 rather than wrapping.

The first time a run reaches 20,000, it sets `ExtraLifeAwarded`, increments
lives, and refreshes the HUD. The flag guarantees exactly one threshold award
even if later damage brings the life count down.

If the new total exceeds the current first-place score, `NewHighScoreFlag` is
set immediately for presentation. Actual table insertion waits until the run
ends.

## Ordered high-score insertion

`CompareScoreToX` lexicographically compares the leading digit and then the
hundreds byte, leaving unsigned condition flags for current score versus the
two-byte pair at `X`.

`RecordHighScore` ignores zero and duplicate scores. It compares first, second,
then third place; a qualifying score shifts lower pairs down with 16-bit `LDD`
and `STD`. Because the bytes are stored in display significance order, a D load
copies an entire score record at once.

## Register contract

| Entry | Inputs | Outputs |
| --- | --- | --- |
| transition and map helpers | state and `CandidateX/Y` where applicable | progression/position/map updated |
| `AddScore` | `A` award in hundreds | score, life, high-score flag updated |
| `RecordHighScore` | current score | distinct descending top-three table updated |
| `CompareScoreToX` | `X` points to a score pair | unsigned CC comparison; `A` is last compared byte |

Unless noted, routines may clobber `A`, `B`, `X`, `Y`, `U`, and condition
codes. They balance `S` and preserve `DP`.

## Educational points and pitfalls

- Representing only values the rules can produce simplifies arithmetic and
  decimal display.
- Saturation is safer than score wraparound.
- Lexicographic byte comparison works because the record is stored most-
  significant field first.
- Progression must reset room-transient state while preserving intentional run
  resources; auditing that boundary is central when adding a rule.

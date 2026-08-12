# `src/game/flow/guardians.asm`

Source: [guardians.asm](../../../../../src/game/flow/guardians.asm)

## Purpose

This fragment implements the complete guardian runtime: pool iteration,
animation, fractional pixel speed, respawn safety, three behavioral identities,
greedy route choice, collision with the static maze, and reservations between
moving actors.

There is intentionally no corridor-patroller identity. The five stable slots
are three direct chasers, one interceptor, and one guardian that alternates
between short wandering and direct pursuit windows.

## Pool iteration and frame ordering

`ProcessEnemies` walks the structure-of-arrays pool through
`CurrentActorIndex`. Active slots run `ProcessCurrentEnemyFrame`; inactive slots
update their hit effect and respawn timer. A newly respawned slot is drawn in the
same pass.

After all guardians, projectiles are redrawn because a guardian footprint
restore may have reconstructed a map cell beneath a shot. Player contact is
then tested once against the finished guardian positions.

An active guardian restores its footprint only if movement, animation, or a
forced grace-color redraw makes its image dirty. A blocked idle actor with an
unexpired animation timer returns immediately, avoiding needless map work.

## Fractional-speed movement

Every guardian crosses cells with the same committed/target/pixel model as the
player. `EnemySpeedByRoom` uses eightieth-pixel units. Each frame adds the room's
speed value to that slot's phase, repeatedly subtracts
`ENEMY_SPEED_SCALE`, and issues one whole-pixel budget for each subtraction.

Unused budget at a cell boundary is saved in `EnemyStepCarry`; the actor never
chooses a second cell in the same display frame. This preserves average speed
while giving the rest of the pool a fair decision/update opportunity.

`AdvanceCurrentEnemyOnePixel` changes the appropriate pixel coordinate and
commits target X/Y only after all eight pixels. Animation is independent and
per-slot, so actors do not flip poses in lockstep.

## Inactive lifecycle and safe respawn

Inactive slots can display a timed hit effect while a longer respawn countdown
runs. When the effect expires, its cell is reconstructed from `LevelMap`.

At respawn time, the slot's mapped nest is tested against the player's committed
cell and `EnemyCandidateBlocked`. That second check rejects walls/exits and any
other guardian's committed or targeted cell. A blocked spawn is delayed ten
frames and tried again. A successful spawn receives a grace timer and sound;
grace suppresses contact damage and uses a distinct render color. When grace
expires, `CurrentEnemyForceRedraw` changes the visible color immediately.

## Behavioral identities

`ChooseEnemyMove` increments a per-slot decision phase and dispatches by
`EnemyBehaviorBySlot`:

- Direct chaser: goal is the player's committed cell.
- Interceptor: goal is up to four cells ahead of the player's active direction,
  clamped to the room bounds; horizontal facing is the idle fallback.
- Temporary wanderer: during one decision-phase window it rotates through a
  direction table, then during the other window it uses direct chase.

All identities share collision, speed, fallback, and reservation code. Their
differences are small goal/preference policies, which makes their personalities
readable without maintaining separate movement engines.

## Greedy chase and fallback algorithm

Direct and intercept goals use Manhattan-style greedy movement. The decision
phase alternates whether horizontal or vertical progress is tried first, keeping
multiple pursuers from making identical junction choices every time.

If goal-directed choices fail, a guardian tries to maintain momentum, then the
two perpendicular turns in phase-dependent order. Immediate reversal is
rejected by `TryEnemyDirectionPreferred` and attempted only as a dead-end
fallback. The wander policy also falls into this robust corridor logic when its
preferred direction is blocked.

This is local path selection, not global shortest-path search. Mazes are
designed so repeated greedy decisions remain effective, while alternating axes
and identities create pressure and variation cheaply.

## Candidate reservations

`TryEnemyDirection` derives an adjacent `CandidateX/Y` and calls
`EnemyCandidateBlocked`. A candidate is unavailable when it is a wall, final
exit, room exit, another active guardian's committed cell, or another moving
guardian's target.

Checking both committed and target cells forms a reservation system. Two actors
cannot choose the same destination in one frame even though the first has not
yet completed its pixel crossing. Once accepted, direction and target are
stored and `EnemyPixelsRemaining` starts at eight.

## Register contracts

| Entry | Inputs | Outputs |
| --- | --- | --- |
| `ProcessEnemies` | game state | all guardian simulation and contact updated |
| `ProcessCurrentEnemyFrame`, `ChooseEnemyMove` | `CurrentActorIndex` | selected slot updated; movement may begin |
| `TryEnemyDirectionPreferred` | `A` proposed DPAD direction, current slot | `A != 0` if move started |
| `EnemyCandidateBlocked` | `CandidateX/Y`, current slot | `A != 0` if map or actor blocks it |

These routines may clobber `A`, `B`, `X`, `Y`, `U`, condition codes, and shared
candidate/query scratch. They balance `S` and preserve `DP`.

## Educational points and pitfalls

- Fractional speed is an accumulator: add units, extract whole pixels, retain
  the remainder.
- Actor reservations are a lightweight multi-agent conflict algorithm.
- Small policy tables can create stable identities without duplicating physics.
- Separating preferred movement from forced reversal prevents junction jitter.
- Because `CurrentActorIndex` and `QueryX` are implicit context, nested pool
  scans must save any outer index they still require.

# `src/game/flow/guardian-pool.asm`

Source: [guardian-pool.asm](../../../../../src/game/flow/guardian-pool.asm)

## Purpose

This fragment maps five runtime guardian slots onto three physical room nests
and initializes every parallel state array consistently.

## Pool reset and staged arrival

`ResetEnemies` initializes all five slots from spawn data. Slot zero remains
active immediately. Slots one through four are then marked inactive and receive
`slot * ENEMY_INITIAL_SPAWN_STAGGER` as their initial delay. Difficulty ramps
into a room rather than displaying all guardians on its first frame.

`InitializeCurrentEnemyAtSpawn` copies the selected nest X/Y into committed,
target, and pixel coordinates; the pixel values are cell coordinates multiplied
by eight. It converts the data table's signed horizontal hint into a DPAD mask,
loads staggered animation state, seeds speed/decision phases from the slot, and
clears movement, hit, respawn, and grace fields before activating the slot.

## Five slots, three nests

`SetCurrentEnemyTableIndex` reduces `CurrentActorIndex` modulo
`ENEMY_SPAWN_COUNT` by repeated subtraction, then adds
`CurrentRoomEnemyOffset`. Slots 0/3 share nest record 0 and slots 1/4 share
record 1; slot 2 uses record 2.

The later respawn routine refuses to materialize a slot while another active
guardian occupies or targets that nest. Reuse is therefore a scheduling rule,
not permission for overlapping sprites.

Behavioral identity does not come from nest data. It is selected separately by
runtime slot, so direct chasers, the interceptor, and the temporary wanderer
keep their identities across every respawn and room.

## Register contract

`ResetEnemies` takes no input and outputs a fully reset five-slot pool.
`InitializeCurrentEnemyAtSpawn` and `SetCurrentEnemyTableIndex` take
`CurrentActorIndex`; the former initializes that slot and the latter outputs
`CurrentRoomEnemyTableIndex`. They clobber `A`, `B`, `X`, and condition codes,
balance `S`, and preserve `DP`.

## Educational points and pitfalls

- Repeated subtraction is sufficient for modulo five-by-three at this scale.
- Structure-of-arrays initialization requires visiting every field explicitly;
  omitting one creates stale state from an earlier life.
- Spawn occupancy checks are necessary because table reuse and actor capacity
  are intentionally different concepts.
- Slot identity and spatial origin are orthogonal data dimensions.

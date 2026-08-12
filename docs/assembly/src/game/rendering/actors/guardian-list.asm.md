# `src/game/rendering/actors/guardian-list.asm`

Source: [guardian-list.asm](../../../../../../src/game/rendering/actors/guardian-list.asm)

## Purpose and algorithm

`DrawAllEnemies` is the guardian-pool draw dispatcher. It clears
`CurrentActorIndex`, walks all `ENEMY_COUNT` slots, tests `EnemyActive[index]`,
and calls `DrawCurrentEnemy` only for active entries.

Inactive slots may still have a hit effect, but that effect is owned by the
deactivation/lifecycle renderer and is not a guardian sprite. Keeping those
concepts separate prevents a destroyed actor from reappearing simply because
its old position fields remain populated.

## Register contract

The routine takes no register input and composites every active guardian. It
clobbers `A`, `B`, `X`, `Y`, `U`, `CurrentActorIndex`, and condition codes;
balances `S`; preserves `DP`; and returns on the bitmap plane.

This small file is educationally useful because it exposes the standard fixed-
pool iteration pattern: index bound, active predicate, per-slot operation,
increment, repeat.

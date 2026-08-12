# `src/game/rendering/restoration/guardians.asm`

Source: [guardians.asm](../../../../../../src/game/rendering/restoration/guardians.asm)

## Purpose

This fragment reconstructs static cells beneath one guardian or beneath every
guardian-related visual. It is used during ordinary movement and during the
larger frozen-scene cleanup before player respawn.

## Single-guardian footprint

`RestoreCurrentEnemyFootprint` reads pixel X/Y from the selected slot. Shifting
right three finds left/top cells; nonzero low-three-bit phases add the right and
bottom cells. It redraws the distinct 1×1, 2×1, 1×2, or 2×2 rectangle through
`DrawMapCellAt`.

The algorithm matches player restoration, but input comes from indexed
structure-of-arrays fields. Shared `PlayerFootprint*` bytes are generic renderer
scratch despite their historical names.

## Complete guardian-visual cleanup

`RestoreAllEnemyVisuals` scans every slot. An active guardian has its pixel
footprint restored. Independently, a nonzero hit-effect timer causes that effect
cell to be restored. A slot cannot be assumed to have only one visible form
during all lifecycle boundaries, so the tests are intentionally separate.

This routine does not clear active/effect state. It repairs the screen; reset
logic changes simulation state afterward. That separation lets callers choose
whether an actor is moving, deactivating, or about to be discarded.

## Register contract

`RestoreCurrentEnemyFootprint` requires `CurrentActorIndex`.
`RestoreAllEnemyVisuals` takes no input and clobbers the current index while
walking the pool. They may clobber `A`, `B`, `X`, `Y`, `U`, condition codes, and
footprint/query scratch; balance `S`; preserve `DP`; and return on the bitmap
plane.

## Educational points and pitfalls

- Simulation mutation and visual repair are distinct responsibilities.
- In a structure-of-arrays pool, the index is effectively an implicit object
  pointer and must remain valid through each indexed access.
- Restore before a pool reset; after active/effect flags are cleared, the draw
  system no longer knows which stale visuals existed.

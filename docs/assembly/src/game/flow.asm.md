# `src/game/flow.asm`

Source: [flow.asm](../../../../src/game/flow.asm)

## Purpose

This is the manifest for mutable game behavior. It split the former 2,747-line
flow module into focused source fragments while keeping exactly one LWASM
translation unit. The manifest emits no instructions of its own; every line is
a textual include.

## Include order

The order is deliberately historical: title lifecycle, progression runtime,
title/demo logic, player, scoring, projectiles, guardian deactivation, guardian
AI, damage, pool resets, and map addressing. Preserving it kept code and data
addresses stable during the reviewability refactor. Forward references still
work because LWASM resolves labels after reading the whole translation unit.

The apparent order is not the runtime pipeline. During active play the frame
dispatcher updates the explorer, projectiles, guardians/contact, then final
explorer compositing. Setup, transitions, and presentation enter only when the
state machine calls them.

## Interface and register contract

The manifest has no callable entry point, input, output, or clobber set. Each
included page documents its routines individually. All labels remain global:
the directory boundary supplies human organization, not symbol visibility.

## Educational points

- Source modularity does not require object files or a linker.
- Include order controls binary placement even when it does not control calls.
- A manifest provides a readable subsystem map and makes dependencies visible.
- Moving an include can change branch ranges and addresses, so order should not
  be treated as cosmetic in a fixed-layout assembly program.

# `src/game/rendering.asm`

Source: [rendering.asm](../../../../src/game/rendering.asm)

## Purpose

This manifest composes the presentation, world, actor, restoration, and HUD
renderers. It replaced the former 1,403-line rendering module without changing
the single-translation-unit model or the historical byte order.

## Layering and include order

Presentation and static-world code come first. Player drawing is paired with
player footprint restoration; guardian dispatch/restoration/drawing follows;
death and projectile effects come next; HUD routines finish the subsystem.

The important conceptual layers are:

1. static screens and the mutable `LevelMap` world;
2. dynamic actors OR-composited over that world;
3. restoration that reconstructs covered cells from `LevelMap`;
4. HUD and presentation text written through the platform glyph primitives.

The include sequence preserves addresses, but callers are free to invoke any
label after assembly. Forward references cross fragment boundaries normally.

## Shared renderer invariant

Higher-level drawing routines follow `video.asm` in returning with the bitmap
plane selected. Actor routines also rely on writable scratch such as
`CurrentActorIndex`, footprint edges, phase, and draw column. Those implicit
inputs and clobbers are documented in their companion pages.

## Interface and educational points

The manifest itself emits no routine and has no register contract. It shows two
assembly design lessons: textual composition can provide small reviewable files
without link-time modules, and rendering is easier to reason about when static
authority, dynamic compositing, and background repair are distinct concepts.

# `src/memory.asm`

Source: [memory.asm](../../../src/memory.asm)

## Purpose

`memory.asm` is intentionally documentation-only assembly. It emits no code or
data; instead, it records the address-space contract that every other module
must obey.

## Memory layout

| Range or boundary | Meaning |
| --- | --- |
| `$0000-$1F3F` | Banked video window: bitmap or color plane |
| `$4000` upward | Program code, immutable tables, and writable game state |
| `$9800` | Conservative build-time image ceiling |
| `$9FFF` downward | Hardware stack |

The program and its writable variables occupy one continuous LOADM image. There
is no protected read-only segment and no linker-created BSS. `fcb` initializers
and `rmb` storage are both part of the assembled layout.

## Why writable code matters

`CellAddress` uses a one-byte self-modifying operand to remember its input
column while calculating `row × 320`. That technique assumes instructions live
in RAM. Moving code to ROM would require replacing the patched operand with a
writable scratch byte or a register/stack strategy.

## Stack safety

The build script measures the raw binary and rejects an end address at or above
`$9800`. This is not a hardware boundary; it is reserved breathing room between
the image and the stack growing down from `$9FFF`. Deep call chains, interrupt
handlers, or large stack allocations would require a fresh analysis even if the
binary still passes the guard.

## Educational points

High-level runtimes hide placement, sections, and stack setup. This file makes
those assumptions explicit. It also shows that a memory map is part of program
correctness: display access, program loading, writable code, state allocation,
and recursion depth all meet in the same finite address space.

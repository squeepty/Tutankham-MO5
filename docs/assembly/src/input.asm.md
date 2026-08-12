# `src/input.asm`

Source: [input.asm](../../../src/input.asm)

## Purpose

This module converts two different active-low devices—the MO5 keyboard matrix
and an optional 6821-based joystick—into one device-independent input model.
Game logic reads direction and action bitmasks, never hardware registers.

Each snapshot is two adjacent bytes: direction first, action second. That layout
allows `LDD` and `STD` to load or copy an entire snapshot in one instruction.

## Initialization

`InitInput` configures the joystick PIA and clears the Read, Held, and Press
snapshots. Starting all three at zero prevents a synthetic rising edge on the
first poll.

`InitJoypadPia` clears control-register bit 2 to expose each data-direction
register, writes zero so every bit is an input, then restores peripheral-data
mode. This is a classic 6821 sequence: the same port address refers to either a
direction register or a data register depending on its control bit.

## Poll and edge-detection algorithm

`ReadInput` clears `Input_Read`, ORs in joystick state, then ORs in keyboard
state. Multiple devices and aliases can therefore express the same logical
action without priority rules.

After sampling, it calculates rising edges independently for all 16 bits:

```text
Press = (Held XOR Read) AND Read
Held  = Read
```

A newly set bit differs from the old snapshot and remains set after the AND. A
released bit also differs but is eliminated by the AND. A held bit appears in
`Held` every frame and in `Press` only on its first frame. Movement consumes
held directions; firing, flash, and cheats generally consume presses.

## Hardware normalization

Joystick bits are complemented because the electrical inputs are active-low.
The low nibble becomes the four direction bits, and the supported button maps
to `ACTION_FIRE_MASK`.

Keyboard polling writes an encoded row/column selector to `KEYBOARD_PORT`, reads
the same port, and tests bit 7. `ReadKeyboardSelector` returns with Z set when
the selected key is held. Both cursor keys and the AZERTY `Z/S/Q/D` cluster map
to the same four logical directions. Space maps to fire and X maps to flash.

## Cheat input rule

Next-room, infinite-lives, and guardian-immunity selectors are not sampled until
`CheatUnlocked` is nonzero. This is stronger than letting later game logic
ignore the bits: before the title code recognizes the unlock sequence, those
actions cannot enter Read, Held, or Press at all. The D key still participates
as the right-direction alias and, once unlocked, may also set guardian immunity.

## Register contracts

| Routine | Inputs | Outputs and clobbers |
| --- | --- | --- |
| `InitInput` | none | PIA and snapshots initialized; `D` clobbered |
| `InitJoypadPia` | none | both joystick sides configured as inputs; `A`, `B` clobbered |
| `ReadInput` | hardware state | Read/Held/Press updated; `D` clobbered |
| `ReadJoypadHardware` | current `Input_Read` | joystick bits ORed into it; `A` clobbered |
| `ReadKeyboardHardware` | current `Input_Read`, `CheatUnlocked` | keyboard bits ORed into it; `A` clobbered |
| `ReadKeyboardSelector` | `A` matrix selector | Z set if held; `A` clobbered |

## Educational points and pitfalls

- Normalization keeps hardware polarity and keyboard layout out of game rules.
- Contiguous byte fields are a data-structure decision chosen specifically for
  the 6809's 16-bit `D` register.
- Edge detection requires the previous sample; changing the order of the Press
  calculation and Held copy breaks it.
- Adding an action requires a free mask bit, a hardware mapping, and a choice
  between `Action_Held` and `Action_Press` at the consumer.
- Keyboard matrix reads are selector-specific. Reading ordinary ASCII is not
  part of this interface.

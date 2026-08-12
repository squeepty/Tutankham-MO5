# `src/sound.asm`

Source: [sound.asm](../../../src/sound.asm)

## Purpose

This is a deliberately small one-bit sound engine. It creates square waves by
writing the MO5 buzzer bit high and low in software delay loops. Named event
routines arrange tones into recognizable cues for shots, hits, pickups, warps,
death, respawn, room completion, and stage entry.

There is no interrupt, timer peripheral, buffer, or background mixer. A cue is
synchronous: simulation pauses until its routine returns. Its duration is thus
both audible output and part of the frame's timing.

## Tone synthesis

`SoundTone` receives a half-period delay in `A` and a full-wave cycle count in
`B`. It copies them into writable bytes because the registers are reused by the
inner loops. For each cycle it:

1. raises `SOUND_BUZZER_BIT`;
2. delays for `SoundDelay` decrements;
3. clears the buzzer port;
4. delays for the same count;
5. decrements `SoundCycles` and repeats.

A smaller delay produces a shorter period and therefore a higher pitch. More
cycles produce a longer note. Loop overhead makes this an intentionally simple
approximation rather than equal-tempered frequency synthesis.

Because `SoundDelay` and `SoundCycles` are global temporaries, `SoundTone` is
not re-entrant. That is safe while interrupts are masked and no sound routine
calls another `SoundTone` concurrently.

## Event envelopes

Event routines load a sequence of delay/count pairs and call `SoundTone`.
Ascending effects use successively smaller delays; the death rasp uses larger
delays to descend. `SoundShortPause` adds silence between notes in the reward
motif. Every public cue calls `SoundOff` before returning so the speaker cannot
be left at a DC-high level.

Some entry points intentionally alias the same code. Key and treasure pickups
share `SoundRewardChirp`; chamber clear also jumps to it. An unconditional
`JMP` is used instead of `JSR`/`RTS`, so the shared routine returns directly to
the original caller without growing the stack.

## Register contracts

| Routine | Inputs | Outputs and clobbers |
| --- | --- | --- |
| `InitSound`, `SoundOff` | none | buzzer low; `A` preserved |
| `SoundTone` | `A` half-period delay, `B` cycle count | tone emitted, buzzer low after final low phase; `A`, `B` and writable loop state clobbered |
| public `Sound*` cues | none | cue emitted, buzzer low; registers named in each push list are preserved |
| `SoundShortPause` | none | silent delay; `X` clobbered |

Most event routines preserve `A/B`; cues with a local pause also preserve `X`.
Callers should nevertheless treat condition codes as destroyed.

## Educational points and pitfalls

- One-bit audio reduces synthesis to pulse timing: frequency comes from period,
  and duration comes from repetition.
- Blocking audio is easy to reason about but couples sound design to gameplay
  latency. Long new cues should be tested for control responsiveness.
- Writable loop parameters save registers but make re-entrancy an explicit
  architectural constraint.
- Tail-jumping to a shared cue is a useful assembly technique for exact aliases.
- Always terminate a new effect with `SoundOff`, including all early exits.

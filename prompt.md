# Audio direction and event mapping

This file records the intended sound vocabulary for the MO5 implementation. It
is a design reference for the locally synthesized one-bit cues in
`src/sound.asm`, not a request to copy or extract sampled audio from another
game.

The broad inspiration is the sharp, economical arcade-event language associated
with Konami's *Tutankham* and the jump/bomb timing of *Bomb Jack*. Every emitted
waveform in this project is synthesized by the local 6809 code.

## Event map

| Game event | Direction | Desired gameplay information |
| --- | --- | --- |
| Player shot | Brief upward or jumping chirp | Confirms a projectile slot was allocated |
| Guardian hit | Tight catch/impact burst | Separates a valid hit from a wall collision |
| Treasure pickup | Bright bonus catch | Confirms score and map mutation |
| Key pickup | Stronger two-part reward | Signals stage progression is now unlocked |
| Warp | Distinct sweep unlike pickups | Makes involuntary relocation immediately clear |
| Flash | Wide, energetic burst | Communicates a room-affecting defensive action |
| Explorer death | Fast descending phrase | Marks loss before the respawn presentation |
| Respawn | Short rising recovery phrase | Returns attention to the explorer's new start |
| Room transition | Compact completion chirp | Separates a room gate from a stage ending |
| Stage completion/entry | Longer reward phrase | Marks the larger three-room progression boundary |

Earlier shorthand described the shot as “Bomb Jack jumping,” a guardian hit as
“catching a lit bomb,” and treasure/key collection as “catching a bonus.” Those
phrases remain useful references for energy and timing, but not for waveform or
asset reproduction.

## Implementation contract

All sound is produced by the MO5 one-bit buzzer and is synchronous with the game
loop.

- `SoundTone` is the primitive tone generator.
- Register `A` selects the half-period and therefore pitch.
- Register `B` selects the iteration count and therefore duration.
- Named wrapper routines combine tones into event cues.
- A cue blocks gameplay while it runs.
- Every path must leave the buzzer output low.

Because duration is instruction- and clock-dependent, cues must be judged at
MO5 target speed. A tone that sounds acceptable in an unthrottled emulator is
not considered calibrated.

## Design constraints

- Keep cues short enough that controls still feel responsive.
- Give progression, danger, and ordinary firing different contours.
- Avoid long sustained tones and low-frequency clicks that dominate the buzzer.
- Prefer two or three clearly separated tone steps over a long melody.
- Preserve enough pitch distance that the small speaker distinguishes cues.
- Do not add copyrighted sampled audio; preserve the current code-synthesized
  approach.

## Acceptance checks

For each event:

1. Trigger the cue alone at target speed.
2. Trigger it during guardian and projectile activity.
3. Confirm it plays once for an edge-triggered event.
4. Confirm it does not retrigger from a held input.
5. Confirm the buzzer returns to silence.
6. Confirm its blocking duration does not create an unfair collision.

Also test rapid combinations such as shot plus treasure, guardian hit plus warp,
and death near an opening gate. If cues serialize, the combined delay must remain
short enough to preserve the intended frame rhythm.

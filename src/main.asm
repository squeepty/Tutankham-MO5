;==============================================================================
; Tutankham MO5 nine-stage game
;
; This is the single assembly translation unit. Constants and the memory
; contract are read first, execution begins at PROGRAM_ORIGIN, and the platform
; and game modules are included below the entry loop. Forward references are
; therefore expected and are resolved by LWASM in the same unit.
;
; Runtime contract:
;   - IRQ and FIRQ remain masked; WaitFrame owns the simulation cadence.
;   - S starts at PROGRAM_ORIGIN and the hardware stack grows down from
;     STACK_TOP.
;   - Public drawing routines restore the bitmap plane before returning.
;   - InitGame never returns to firmware; MainLoop runs until reset/reload.
;==============================================================================

        include "constants.asm"
        include "memory.asm"

        org     PROGRAM_ORIGIN

Start:
        ; Gameplay uses a calibrated 1 MHz frame delay, so monitor interrupts
        ; remain masked and cannot create extra simulation frames.
        orcc    #$50
        lds     #STACK_TOP

        jsr     InitSound
        jsr     InitInput
        jsr     InitGame

MainLoop:
        ; Exactly one input/simulation/render pass is dispatched per delay.
        ; Sound routines are synchronous and intentionally extend the current
        ; frame rather than introducing an interrupt-driven audio subsystem.
        jsr     WaitMainLoopFrame
        jsr     RunGameFrame
        bra     MainLoop

        ; Include order is significant: platform services precede the game
        ; manifest, while writable game state is placed last by game.asm.
        include "video.asm"
        include "input.asm"
        include "sound.asm"
        include "timing.asm"
        include "game.asm"

        end     Start

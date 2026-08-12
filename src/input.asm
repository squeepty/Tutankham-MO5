;==============================================================================
; Normalized keyboard and joystick input
;
; Dpad_* contains direction bits. Action_* contains fire, flash, infinite
; lives, disabled guardian hits, and the cheat-gated next-room shortcut.
; The standard one-button joystick maps its button to ACTION_FIRE_MASK.
;
; Public API:
;   InitInput  - configure the optional joystick PIA and clear all snapshots.
;   ReadInput  - poll hardware and produce Read, Held, and rising-edge Press.
;
; Snapshot layout is deliberately two adjacent bytes so 16-bit D operations
; update direction (A) and action (B) together. Keyboard keys are active-low.
; I, N, and the D cheat action are not merely ignored by game rules: their
; matrix positions are not sampled as actions until CheatUnlocked is nonzero.
;==============================================================================

; Initialize hardware once at boot. Re-entering a title/game does not need to
; reset the PIA, but the snapshots begin released to avoid synthetic presses.
InitInput:
        jsr     InitJoypadPia
        ldd     #$0000
        std     Input_Read
        std     Input_Held
        std     Input_Press
        rts

InitJoypadPia:
        ; Put each 6821 side into data-direction mode, select all bits as input,
        ; then return the control registers to peripheral-data mode.
        lda     JOYPAD_CRA
        anda    #$FB
        sta     JOYPAD_CRA
        clrb
        stb     JOYPAD_DPAD_PORT
        ora     #$04
        sta     JOYPAD_CRA

        lda     JOYPAD_CRB
        anda    #$FB
        sta     JOYPAD_CRB
        clrb
        stb     JOYPAD_FIRE_PORT
        ora     #$04
        sta     JOYPAD_CRB
        rts

ReadInput:
        ldd     #$0000
        std     Input_Read
        jsr     ReadJoypadHardware
        jsr     ReadKeyboardHardware

        ; Rising edge per bit: pressed = (held XOR read) AND read.
        ; Holding a key therefore drives Held every frame but Press only once.
        ldd     Input_Held
        eora    Dpad_Read
        eorb    Action_Read
        anda    Dpad_Read
        andb    Action_Read
        std     Input_Press

        ldd     Input_Read
        std     Input_Held
        rts

ReadJoypadHardware:
        ; Both joystick ports are active-low. Directions occupy the low nibble;
        ; the one supported button is normalized to the keyboard Fire action.
        lda     JOYPAD_DPAD_PORT
        coma
        anda    #$0F
        ora     Dpad_Read
        sta     Dpad_Read

        lda     JOYPAD_FIRE_PORT
        coma
        anda    #JOYPAD_FIRE_MASK
        beq     ReadJoypadDone
        lda     Action_Read
        ora     #ACTION_FIRE_MASK
        sta     Action_Read
ReadJoypadDone:
        rts

ReadKeyboardHardware:
        ; Cursor keys and the Z/S/Q/D AZERTY cluster are ORed into the same
        ; direction masks. Only Space and X are ordinary action keys.
        lda     #KEY_CURSOR_UP_SELECTOR
        jsr     ReadKeyboardSelector
        beq     ReadKeyboardUpPressed
        lda     #KEY_UP_SELECTOR
        jsr     ReadKeyboardSelector
        bne     ReadKeyboardDown
ReadKeyboardUpPressed:
        lda     Dpad_Read
        ora     #DPAD_UP_MASK
        sta     Dpad_Read

ReadKeyboardDown:
        lda     #KEY_CURSOR_DOWN_SELECTOR
        jsr     ReadKeyboardSelector
        beq     ReadKeyboardDownPressed
        lda     #KEY_DOWN_SELECTOR
        jsr     ReadKeyboardSelector
        bne     ReadKeyboardLeft
ReadKeyboardDownPressed:
        lda     Dpad_Read
        ora     #DPAD_DOWN_MASK
        sta     Dpad_Read

ReadKeyboardLeft:
        lda     #KEY_CURSOR_LEFT_SELECTOR
        jsr     ReadKeyboardSelector
        beq     ReadKeyboardLeftPressed
        lda     #KEY_LEFT_SELECTOR
        jsr     ReadKeyboardSelector
        bne     ReadKeyboardRight
ReadKeyboardLeftPressed:
        lda     Dpad_Read
        ora     #DPAD_LEFT_MASK
        sta     Dpad_Read

ReadKeyboardRight:
        lda     #KEY_CURSOR_RIGHT_SELECTOR
        jsr     ReadKeyboardSelector
        beq     ReadKeyboardRightPressed
        lda     #KEY_RIGHT_SELECTOR
        jsr     ReadKeyboardSelector
        bne     ReadKeyboardFire
ReadKeyboardRightPressed:
        lda     Dpad_Read
        ora     #DPAD_RIGHT_MASK
        sta     Dpad_Read

ReadKeyboardFire:
        lda     #KEY_FIRE_SELECTOR
        jsr     ReadKeyboardSelector
        bne     ReadKeyboardFlash
        lda     Action_Read
        ora     #ACTION_FIRE_MASK
        sta     Action_Read

ReadKeyboardFlash:
        lda     #KEY_FLASH_SELECTOR
        jsr     ReadKeyboardSelector
        bne     ReadKeyboardNextRoom
        lda     Action_Read
        ora     #ACTION_FLASH_MASK
        sta     Action_Read

ReadKeyboardNextRoom:
        ; Cheat keys are absent from every snapshot until the title sequence
        ; sets CheatUnlocked, preventing both held and edge-triggered use.
        tst     CheatUnlocked
        beq     ReadKeyboardDone
        lda     #KEY_NEXT_ROOM_SELECTOR
        jsr     ReadKeyboardSelector
        bne     ReadKeyboardInfiniteLives
        lda     Action_Read
        ora     #ACTION_NEXT_ROOM_MASK
        sta     Action_Read

ReadKeyboardInfiniteLives:
        lda     #KEY_INFINITE_LIVES_SELECTOR
        jsr     ReadKeyboardSelector
        bne     ReadKeyboardDisableGuardianHits
        lda     Action_Read
        ora     #ACTION_INFINITE_LIVES_MASK
        sta     Action_Read

ReadKeyboardDisableGuardianHits:
        ; D remains the AZERTY right-movement alias. Once cheats are unlocked,
        ; a fresh D press also enables guardian-contact immunity for the run.
        lda     #KEY_DISABLE_GUARDIAN_HITS_SELECTOR
        jsr     ReadKeyboardSelector
        bne     ReadKeyboardDone
        lda     Action_Read
        ora     #ACTION_DISABLE_GUARDIAN_HITS_MASK
        sta     Action_Read

ReadKeyboardDone:
        rts

; Input: A = encoded MO5 matrix selector.
; Output: Z set when the selected active-low key is held; A is destroyed.
ReadKeyboardSelector:
        sta     KEYBOARD_PORT
        lda     KEYBOARD_PORT
        bita    #$80
        rts

; Two-byte snapshot aliases. Keep each Dpad/Action pair contiguous.
Input_Read:
Dpad_Read:
        fcb     $00
Action_Read:
        fcb     $00

Input_Held:
Dpad_Held:
        fcb     $00
Action_Held:
        fcb     $00

Input_Press:
Dpad_Press:
        fcb     $00
Action_Press:
        fcb     $00

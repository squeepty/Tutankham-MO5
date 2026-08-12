;==============================================================================
; Minimal MO5 one-bit sound foundation
;
; Event routines are synchronous envelopes built from SoundTone calls. They do
; not require an IRQ, timer, or resident mixer and always leave the buzzer low.
; This simplicity intentionally pauses simulation for the duration of a cue.
;
; SoundTone contract:
;   A = half-period loop delay (smaller is higher pitch)
;   B = number of complete high/low cycles (larger is longer)
; SoundDelay and SoundCycles are writable loop parameters, so SoundTone is not
; re-entrant. No current caller requires nested or interrupt-driven playback.
;==============================================================================

InitSound:
SoundOff:
        pshs    a
        clra
        sta     SOUND_BUZZER_PORT
        puls    a
        rts

; Public event cue table. Firing, guardian hits, pickups,
; explorer death, and stage clear reuse the matching MO5 buzzer phrases from
; Bomb Jacques; warp, flash, respawn, and stage entry remain Tutankham cues.
SoundLevelStart:
        pshs    a,b
        lda     #18
        ldb     #6
        jsr     SoundTone
        lda     #12
        ldb     #6
        jsr     SoundTone
        lda     #8
        ldb     #8
        jsr     SoundTone
        jsr     SoundOff
        puls    a,b
        rts

SoundShot:
        ; Bomb Jacques jump: a bright, sustained high tick.
        pshs    a,b,x
        lda     #16
        ldb     #64
        jsr     SoundTone
        jsr     SoundOff
        puls    a,b,x
        rts

SoundEnemyHit:
        ; Bomb Jacques lit-bomb pickup: a short, bright confirmation blip.
        pshs    a,b,x
        lda     #33
        ldb     #18
        jsr     SoundTone
        jsr     SoundOff
        puls    a,b,x
        rts

SoundPlayerDeath:
        ; Bomb Jacques death: a stepped descending rasp.
        pshs    a,b,x
        lda     #18
        ldb     #20
        jsr     SoundTone
        lda     #28
        ldb     #18
        jsr     SoundTone
        lda     #42
        ldb     #18
        jsr     SoundTone
        lda     #62
        ldb     #16
        jsr     SoundTone
        lda     #88
        ldb     #16
        jsr     SoundTone
        lda     #118
        ldb     #14
        jsr     SoundTone
        jsr     SoundOff
        puls    a,b,x
        rts

SoundRespawn:
        pshs    a,b
        lda     #18
        ldb     #5
        jsr     SoundTone
        lda     #10
        ldb     #5
        jsr     SoundTone
        lda     #6
        ldb     #5
        jsr     SoundTone
        jsr     SoundOff
        puls    a,b
        rts

SoundKeyPickup:
SoundTreasurePickup:
        ; Bomb Jacques bonus catch.
        jmp     SoundRewardChirp

SoundWarp:
        pshs    a,b
        lda     #5
        ldb     #4
        jsr     SoundTone
        lda     #14
        ldb     #4
        jsr     SoundTone
        lda     #5
        ldb     #4
        jsr     SoundTone
        jsr     SoundOff
        puls    a,b
        rts

SoundFlash:
        pshs    a,b
        lda     #4
        ldb     #10
        jsr     SoundTone
        lda     #20
        ldb     #4
        jsr     SoundTone
        jsr     SoundOff
        puls    a,b
        rts

SoundChamberClear:
        ; Bomb Jacques stage-end motif, used by room exits and stage doors.
        jmp     SoundRewardChirp

SoundRewardChirp:
        pshs    a,b,x
        lda     #82
        ldb     #16
        jsr     SoundTone
        jsr     SoundShortPause
        lda     #66
        ldb     #16
        jsr     SoundTone
        jsr     SoundShortPause
        lda     #52
        ldb     #18
        jsr     SoundTone
        jsr     SoundShortPause
        lda     #40
        ldb     #18
        jsr     SoundTone
        jsr     SoundShortPause
        lda     #30
        ldb     #20
        jsr     SoundTone
        jsr     SoundShortPause
        lda     #22
        ldb     #42
        jsr     SoundTone
        jsr     SoundOff
        puls    a,b,x
        rts

SoundShortPause:
        ldx     #220
SoundShortPauseLoop:
        leax    -1,x
        bne     SoundShortPauseLoop
        rts

; Input: A = half-period delay, B = full wave cycles.
SoundTone:
        sta     SoundDelay
        stb     SoundCycles
SoundToneLoop:
        lda     #SOUND_BUZZER_BIT
        sta     SOUND_BUZZER_PORT
        ldb     SoundDelay
SoundToneHigh:
        decb
        bne     SoundToneHigh

        clra
        sta     SOUND_BUZZER_PORT
        ldb     SoundDelay
SoundToneLow:
        decb
        bne     SoundToneLow

        dec     SoundCycles
        bne     SoundToneLoop
        rts

SoundDelay:
        fcb     0
SoundCycles:
        fcb     0

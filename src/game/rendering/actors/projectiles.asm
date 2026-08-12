;==============================================================================
; Cell-aligned projectile compositing
;
; Register contract for exported entries:
;   DrawAllShots: Inputs none; outputs all active shots composited.
;   DrawCurrentShot: Input CurrentActorIndex; output selected shot composited.
;   Clobbers: A, B, X, Y, U, CurrentActorIndex, CC; S balanced; DP unchanged;
;     returns on the bitmap display plane.
;==============================================================================

;------------------------------------------------------------------------------
; Cell-aligned projectile renderer
;------------------------------------------------------------------------------
DrawAllShots:
        clr     CurrentActorIndex
DrawAllShotsNext:
        ldb     CurrentActorIndex
        cmpb    #SHOT_COUNT
        beq     DrawAllShotsDone
        ldx     #ShotActive
        lda     b,x
        beq     DrawAllShotsSkip
        jsr     DrawCurrentShot
DrawAllShotsSkip:
        inc     CurrentActorIndex
        bra     DrawAllShotsNext
DrawAllShotsDone:
        rts

DrawCurrentShot:
        ldu     #CellShotRightFrame0
        ldb     CurrentActorIndex
        ldx     #ShotDirection
        lda     b,x
        bmi     DrawCurrentShotLeft
        lda     ShotAnimationFrame
        eora    CurrentActorIndex
        bita    #$01
        beq     DrawCurrentShotPatternReady
        ldu     #CellShotRightFrame1
        bra     DrawCurrentShotPatternReady
DrawCurrentShotLeft:
        ldu     #CellShotLeftFrame0
        lda     ShotAnimationFrame
        eora    CurrentActorIndex
        bita    #$01
        beq     DrawCurrentShotPatternReady
        ldu     #CellShotLeftFrame1
DrawCurrentShotPatternReady:
        ldb     CurrentActorIndex
        ldx     #ShotX
        lda     b,x
        adda    #LEVEL_SCREEN_COL
        pshs    a
        ldx     #ShotY
        lda     b,x
        adda    #LEVEL_SCREEN_ROW
        tfr     a,b
        puls    a
        ldx     #DrawCellColor
        pshs    a
        lda     #COLOR_SHOT
        sta     ,x
        puls    a
        jmp     DrawCellPattern

; Restore all projectile footprints before movement and frame changes.

;==============================================================================
; Explorer sprite restoration
;
; Register contract: Inputs none; outputs every static cell under the current
; explorer footprint restored and PlayerRedrawPending set. Clobbers A, B, X,
; Y, U, CC; S balanced; DP unchanged; returns on the bitmap display plane.
;==============================================================================

EnsurePlayerFootprintRestored:
        tst     PlayerRedrawPending
        bne     EnsurePlayerFootprintDone
        jmp     RestorePlayerFootprint
EnsurePlayerFootprintDone:
        rts

RestorePlayerFootprint:
        lda     #1
        sta     PlayerRedrawPending
        lda     PlayerPixelX
        lsra
        lsra
        lsra
        sta     PlayerFootprintLeft
        sta     PlayerFootprintRight
        lda     PlayerPixelX
        anda    #$07
        beq     RestorePlayerHorizontalReady
        inc     PlayerFootprintRight
RestorePlayerHorizontalReady:
        lda     PlayerPixelY
        lsra
        lsra
        lsra
        sta     PlayerFootprintTop
        sta     PlayerFootprintBottom
        lda     PlayerPixelY
        anda    #$07
        beq     RestorePlayerVerticalReady
        inc     PlayerFootprintBottom
RestorePlayerVerticalReady:
        lda     PlayerFootprintLeft
        ldb     PlayerFootprintTop
        jsr     DrawMapCellAt

        lda     PlayerFootprintRight
        cmpa    PlayerFootprintLeft
        beq     RestorePlayerBottom
        ldb     PlayerFootprintTop
        jsr     DrawMapCellAt

RestorePlayerBottom:
        lda     PlayerFootprintBottom
        cmpa    PlayerFootprintTop
        beq     RestorePlayerFootprintDone
        tfr     a,b
        lda     PlayerFootprintLeft
        jsr     DrawMapCellAt

        lda     PlayerFootprintRight
        cmpa    PlayerFootprintLeft
        beq     RestorePlayerFootprintDone
        ldb     PlayerFootprintBottom
        jsr     DrawMapCellAt
RestorePlayerFootprintDone:
        rts

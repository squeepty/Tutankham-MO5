;==============================================================================
; Projectile footprint restoration
;
; Register contract: Inputs none; outputs every active shot cell restored from
; LevelMap; clobbers A, B, X, Y, U, CurrentActorIndex, CC; S balanced; DP
; unchanged; returns on the bitmap display plane.
;==============================================================================

RestoreAllShotCells:
        clr     CurrentActorIndex
RestoreAllShotCellsNext:
        ldb     CurrentActorIndex
        cmpb    #SHOT_COUNT
        beq     RestoreAllShotCellsDone
        ldx     #ShotActive
        lda     b,x
        beq     RestoreAllShotCellsSkip
        ldx     #ShotX
        lda     b,x
        pshs    a
        ldx     #ShotY
        lda     b,x
        tfr     a,b
        puls    a
        jsr     DrawMapCellAt
RestoreAllShotCellsSkip:
        inc     CurrentActorIndex
        bra     RestoreAllShotCellsNext
RestoreAllShotCellsDone:
        rts

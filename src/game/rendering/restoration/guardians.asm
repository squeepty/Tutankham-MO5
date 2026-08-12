;==============================================================================
; Guardian sprite and hit-effect restoration
;
; Register contract for exported entries:
;   RestoreCurrentEnemyFootprint: Input CurrentActorIndex; output selected
;     guardian footprint restored from LevelMap.
;   RestoreAllEnemyVisuals: Inputs none; output all live/hit visuals restored.
;   Clobbers: A, B, X, Y, U, CurrentActorIndex, CC; S balanced; DP unchanged;
;     returns on the bitmap display plane.
;==============================================================================

RestoreCurrentEnemyFootprint:
        ; A horizontally shifted guardian can touch two byte columns; the
        ; footprint's right cell is therefore advanced twice from its left edge.
        ldb     CurrentActorIndex
        ldx     #EnemyPixelX
        lda     b,x
        lsra
        lsra
        lsra
        sta     PlayerFootprintLeft
        sta     PlayerFootprintRight
        ldb     CurrentActorIndex
        ldx     #EnemyPixelX
        lda     b,x
        anda    #$07
        beq     RestoreCurrentEnemyHorizontalReady
        inc     PlayerFootprintRight
RestoreCurrentEnemyHorizontalReady:
        ldb     CurrentActorIndex
        ldx     #EnemyPixelY
        lda     b,x
        lsra
        lsra
        lsra
        sta     PlayerFootprintTop
        sta     PlayerFootprintBottom
        ldb     CurrentActorIndex
        ldx     #EnemyPixelY
        lda     b,x
        anda    #$07
        beq     RestoreCurrentEnemyVerticalReady
        inc     PlayerFootprintBottom
RestoreCurrentEnemyVerticalReady:
        lda     PlayerFootprintLeft
        ldb     PlayerFootprintTop
        jsr     DrawMapCellAt

        lda     PlayerFootprintRight
        cmpa    PlayerFootprintLeft
        beq     RestoreCurrentEnemyBottom
        ldb     PlayerFootprintTop
        jsr     DrawMapCellAt

RestoreCurrentEnemyBottom:
        lda     PlayerFootprintBottom
        cmpa    PlayerFootprintTop
        beq     RestoreCurrentEnemyFootprintDone
        tfr     a,b
        lda     PlayerFootprintLeft
        jsr     DrawMapCellAt

        lda     PlayerFootprintRight
        cmpa    PlayerFootprintLeft
        beq     RestoreCurrentEnemyFootprintDone
        ldb     PlayerFootprintBottom
        jsr     DrawMapCellAt
RestoreCurrentEnemyFootprintDone:
        rts

; Remove every guardian and any pending hit flash without touching the maze.
; This is used by life respawn while the action is frozen.
RestoreAllEnemyVisuals:
        clr     CurrentActorIndex
RestoreAllEnemyVisualsNext:
        ldb     CurrentActorIndex
        cmpb    #ENEMY_COUNT
        beq     RestoreAllEnemyVisualsDone
        ldx     #EnemyActive
        tst     b,x
        beq     RestoreAllEnemyVisualsEffect
        jsr     RestoreCurrentEnemyFootprint
RestoreAllEnemyVisualsEffect:
        ldb     CurrentActorIndex
        ldx     #EnemyHitEffectTimer
        tst     b,x
        beq     RestoreAllEnemyVisualsAdvance
        ldx     #EnemyHitEffectX
        lda     b,x
        pshs    a
        ldx     #EnemyHitEffectY
        lda     b,x
        tfr     a,b
        puls    a
        jsr     DrawMapCellAt
RestoreAllEnemyVisualsAdvance:
        inc     CurrentActorIndex
        bra     RestoreAllEnemyVisualsNext
RestoreAllEnemyVisualsDone:
        rts

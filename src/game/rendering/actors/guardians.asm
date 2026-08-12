;==============================================================================
; Guardian and damage-effect compositing
;
; Register contract for exported entries:
;   DrawCurrentEnemy/DrawCurrentEnemyHitEffect: Input CurrentActorIndex.
;   DrawPlayerDeathEffect: Inputs none; reads PlayerDeathX/Y.
;   Outputs: selected sprite/effect OR-composited onto the display.
;   Clobbers: A, B, X, Y, U, CC; S balanced; DP unchanged; returns on the
;     bitmap display plane.
;==============================================================================

DrawCurrentEnemy:
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        lda     b,x
        cmpa    #DPAD_UP_MASK
        beq     DrawCurrentEnemyUp
        cmpa    #DPAD_DOWN_MASK
        beq     DrawCurrentEnemyDown
        cmpa    #DPAD_LEFT_MASK
        beq     DrawCurrentEnemyLeft
        ldu     #EnemyRightShiftedFrame0
        bra     DrawCurrentEnemyAnimation
DrawCurrentEnemyUp:
        ldu     #EnemyUpShiftedFrame0
        bra     DrawCurrentEnemyAnimation
DrawCurrentEnemyDown:
        ldu     #EnemyDownShiftedFrame0
        bra     DrawCurrentEnemyAnimation
DrawCurrentEnemyLeft:
        ldu     #EnemyLeftShiftedFrame0
DrawCurrentEnemyAnimation:
        ldx     #EnemyAnimationFrame
        lda     b,x
        beq     DrawCurrentEnemyFrameReady
        leau    128,u
DrawCurrentEnemyFrameReady:
        ldb     CurrentActorIndex
        ldx     #EnemyPixelX
        lda     b,x
        anda    #$07
        sta     EnemyHorizontalPhase
        ldb     #16
        mul
        leau    d,u

        ldb     CurrentActorIndex
        ldx     #EnemyPixelX
        lda     b,x
        lsra
        lsra
        lsra
        adda    #LEVEL_SCREEN_COL
        sta     EnemyDrawColumn
        ldb     CurrentActorIndex
        ldx     #EnemyPixelY
        lda     b,x
        adda    #LEVEL_SCREEN_ROW*TEXT_CELL_HEIGHT
        tfr     a,b
        clra
        lslb
        rola
        lslb
        rola
        lslb
        rola
        pshs    d
        lslb
        rola
        lslb
        rola
        puls    x
        leax    d,x
        tfr     x,d
        addb    EnemyDrawColumn
        adca    #0
        tfr     d,x

        jsr     SelectBitmapPlane
        pshs    x
        ldy     #8
DrawCurrentEnemyBitmapRow:
        pulu    d
        ora     ,x
        orb     1,x
        std     ,x
        leax    VIDEO_BYTES_PER_ROW,x
        leay    -1,y
        bne     DrawCurrentEnemyBitmapRow

        puls    x
        jsr     SelectColorPlane
        lda     #COLOR_ENEMY
        ldb     CurrentActorIndex
        ldu     #EnemySpawnGraceTimer
        tst     b,u
        beq     DrawCurrentEnemyColorReady
        lda     #COLOR_ENEMY_RESPAWN
DrawCurrentEnemyColorReady:
        ldy     #8
DrawCurrentEnemyColorRow:
        sta     ,x
        tst     EnemyHorizontalPhase
        beq     DrawCurrentEnemyColorLeftOnly
        sta     1,x
DrawCurrentEnemyColorLeftOnly:
        leax    VIDEO_BYTES_PER_ROW,x
        leay    -1,y
        bne     DrawCurrentEnemyColorRow
        jmp     SelectBitmapPlane

DrawCurrentEnemyHitEffect:
        ldb     CurrentActorIndex
        ldx     #EnemyHitEffectX
        lda     b,x
        adda    #LEVEL_SCREEN_COL
        pshs    a
        ldx     #EnemyHitEffectY
        lda     b,x
        adda    #LEVEL_SCREEN_ROW
        tfr     a,b
        puls    a
        ldu     #CellHitEffect
        ldx     #DrawCellColor
        pshs    a
        lda     #COLOR_HIT_EFFECT
        sta     ,x
        puls    a
        jmp     DrawCellPattern

DrawPlayerDeathEffect:
        lda     PlayerDeathX
        adda    #LEVEL_SCREEN_COL
        ldb     PlayerDeathY
        addb    #LEVEL_SCREEN_ROW
        ldu     #CellHitEffect
        ldx     #DrawCellColor
        pshs    a
        lda     #COLOR_HIT_EFFECT
        sta     ,x
        puls    a
        jmp     DrawCellPattern

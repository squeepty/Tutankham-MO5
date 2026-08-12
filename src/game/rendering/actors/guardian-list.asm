;==============================================================================
; Guardian pool compositing dispatcher
;
; Register contract: Inputs none; outputs every active guardian composited;
; clobbers A, B, X, Y, U, CurrentActorIndex, CC; S balanced; DP unchanged;
; returns on the bitmap display plane.
;==============================================================================

;------------------------------------------------------------------------------
; Guardian pool dispatcher
;------------------------------------------------------------------------------
DrawAllEnemies:
        clr     CurrentActorIndex
DrawAllEnemiesNext:
        ldb     CurrentActorIndex
        cmpb    #ENEMY_COUNT
        beq     DrawAllEnemiesDone
        ldx     #EnemyActive
        lda     b,x
        beq     DrawAllEnemiesSkip
        jsr     DrawCurrentEnemy
DrawAllEnemiesSkip:
        inc     CurrentActorIndex
        bra     DrawAllEnemiesNext
DrawAllEnemiesDone:
        rts

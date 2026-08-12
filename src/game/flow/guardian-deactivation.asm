;==============================================================================
; Guardian hit deactivation
;
; Register contract:
;   Inputs: CurrentActorIndex selects the struck guardian.
;   Outputs: inactive/hit-effect/respawn state in the selected slot.
;   Clobbers: A, B, X, U, CC; S balanced; DP unchanged. Tail-calls the renderer.
;==============================================================================

DeactivateCurrentEnemy:
        jsr     RestoreCurrentEnemyFootprint
        ldb     CurrentActorIndex
        ldx     #EnemyPixelX
        lda     b,x
        adda    #4
        lsra
        lsra
        lsra
        ldx     #EnemyHitEffectX
        sta     b,x
        ldx     #EnemyPixelY
        lda     b,x
        adda    #4
        lsra
        lsra
        lsra
        ldx     #EnemyHitEffectY
        sta     b,x
        ldx     #EnemyHitEffectTimer
        lda     #ENEMY_HIT_EFFECT_FRAMES
        sta     b,x
        ldx     #EnemySpawnGraceTimer
        clr     b,x
        ldx     #EnemyActive
        clr     b,x
        ldx     #EnemyPixelsRemaining
        clr     b,x
        ldx     #EnemyStepCarry
        clr     b,x

        lda     #ENEMY_RESPAWN_BASE
        ldb     CurrentActorIndex
DeactivateCurrentEnemyDelay:
        tstb
        beq     DeactivateCurrentEnemyStoreDelay
        adda    #ENEMY_RESPAWN_STAGGER
        decb
        bra     DeactivateCurrentEnemyDelay
DeactivateCurrentEnemyStoreDelay:
        ldb     CurrentActorIndex
        ldx     #EnemyRespawnTimer
        sta     b,x
        jmp     DrawCurrentEnemyHitEffect

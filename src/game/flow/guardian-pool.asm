;==============================================================================
; Guardian pool initialization and nest mapping
;
; Register contract for exported entries:
;   ResetEnemies: Inputs none; outputs a reset five-slot guardian pool.
;   InitializeCurrentEnemyAtSpawn/SetCurrentEnemyTableIndex: Input
;     CurrentActorIndex; output selected slot state/CurrentRoomEnemyTableIndex.
;   Clobbers: A, B, X, CC. S is balanced and DP is unchanged.
;==============================================================================

ResetEnemies:
        ; First guardian appears immediately; the remaining four begin inactive
        ; with staggered initial respawn timers. Slots four and five reuse the
        ; first and second physical nests after those cells become clear.
        clr     CurrentActorIndex
ResetEnemiesNext:
        ldb     CurrentActorIndex
        cmpb    #ENEMY_COUNT
        beq     ResetEnemiesDone
        jsr     InitializeCurrentEnemyAtSpawn
        lda     CurrentActorIndex
        beq     ResetEnemiesAdvance
        ldb     #ENEMY_INITIAL_SPAWN_STAGGER
        mul
        tfr     b,a
        ldb     CurrentActorIndex
        ldx     #EnemyRespawnTimer
        sta     b,x
        ldx     #EnemyActive
        clr     b,x
ResetEnemiesAdvance:
        inc     CurrentActorIndex
        bra     ResetEnemiesNext
ResetEnemiesDone:
        rts

InitializeCurrentEnemyAtSpawn:
        jsr     SetCurrentEnemyTableIndex
        ldb     CurrentRoomEnemyTableIndex
        ldx     #EnemyInitialX
        lda     b,x
        ldb     CurrentActorIndex
        ldx     #EnemyX
        sta     b,x
        ldx     #EnemyTargetX
        sta     b,x
        lsla
        lsla
        lsla
        ldx     #EnemyPixelX
        sta     b,x

        ldb     CurrentRoomEnemyTableIndex
        ldx     #EnemyInitialY
        lda     b,x
        ldb     CurrentActorIndex
        ldx     #EnemyY
        sta     b,x
        ldx     #EnemyTargetY
        sta     b,x
        lsla
        lsla
        lsla
        ldx     #EnemyPixelY
        sta     b,x

        ldb     CurrentRoomEnemyTableIndex
        ldx     #EnemyInitialDirection
        lda     b,x
        bmi     InitializeCurrentEnemyFacingLeft
        lda     #DPAD_RIGHT_MASK
        bra     InitializeCurrentEnemyMoveDirection
InitializeCurrentEnemyFacingLeft:
        lda     #DPAD_LEFT_MASK
InitializeCurrentEnemyMoveDirection:
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        sta     b,x

        ldb     CurrentRoomEnemyTableIndex
        ldx     #EnemyInitialAnimationTimer
        lda     b,x
        ldb     CurrentActorIndex
        ldx     #EnemyAnimationTimer
        sta     b,x
        ldb     CurrentRoomEnemyTableIndex
        ldx     #EnemyInitialAnimationFrame
        lda     b,x
        ldb     CurrentActorIndex
        ldx     #EnemyAnimationFrame
        sta     b,x

        ldx     #EnemySpeedPhase
        lda     CurrentActorIndex
        sta     b,x
        ldx     #EnemyPixelsRemaining
        clr     b,x
        ldx     #EnemyStepCarry
        clr     b,x
        ldx     #EnemyRespawnTimer
        clr     b,x
        ldx     #EnemyHitEffectTimer
        clr     b,x
        ldx     #EnemySpawnGraceTimer
        clr     b,x
        ldx     #EnemyDecisionPhase
        lda     CurrentActorIndex
        sta     b,x
        ldx     #EnemyActive
        lda     #1
        sta     b,x
        rts

; Map five runtime slots onto the room's three physical nest records. Reusing
; nests is safe because TryRespawnCurrentEnemy delays emergence while another
; guardian still occupies or targets that cell.
SetCurrentEnemyTableIndex:
        ldb     CurrentActorIndex
SetCurrentEnemyTableIndexReduce:
        cmpb    #ENEMY_SPAWN_COUNT
        blo     SetCurrentEnemyTableIndexAddRoom
        subb    #ENEMY_SPAWN_COUNT
        bra     SetCurrentEnemyTableIndexReduce
SetCurrentEnemyTableIndexAddRoom:
        addb    CurrentRoomEnemyOffset
        stb     CurrentRoomEnemyTableIndex
        rts

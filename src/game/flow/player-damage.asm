;==============================================================================
; Explorer contact damage, death effects, and respawn
;
; Register contract for exported entries:
;   CheckPlayerEnemyContact: Inputs none; output A nonzero when contact begins.
;   PlayerHit/BeginPlayerDeath/RespawnPlayer: Inputs none; outputs life, actor,
;     presentation, and inventory state in memory.
;   Clobbers: A, B, X, Y, U, CC. S is balanced and DP is unchanged.
;==============================================================================

;------------------------------------------------------------------------------
; Explorer/guardian contact, death, and respawn
;------------------------------------------------------------------------------
CheckPlayerEnemyContact:
        ; Axis-aligned 8x8 overlap in pixel space. Respawn grace and explorer
        ; invulnerability suppress damage without suppressing rendering. The
        ; SQUEEPTY-gated D action can disable this contact for the current run.
        tst     GuardianHitsDisabled
        bne     CheckPlayerEnemyContactClear
        tst     PlayerDeathTimer
        bne     CheckPlayerEnemyContactClear
        tst     PlayerInvulnerabilityTimer
        beq     CheckPlayerEnemyContactBegin
        clra
        rts
CheckPlayerEnemyContactBegin:
        clr     QueryX
CheckPlayerEnemyContactNext:
        ldb     QueryX
        cmpb    #ENEMY_COUNT
        beq     CheckPlayerEnemyContactClear
        ldx     #EnemyActive
        lda     b,x
        beq     CheckPlayerEnemyContactSkip
        ldx     #EnemySpawnGraceTimer
        lda     b,x
        bne     CheckPlayerEnemyContactSkip
        ldx     #EnemyPixelX
        lda     b,x
        suba    PlayerPixelX
        bpl     CheckPlayerEnemyContactXReady
        nega
CheckPlayerEnemyContactXReady:
        cmpa    #8
        bhs     CheckPlayerEnemyContactSkip
        ldx     #EnemyPixelY
        lda     b,x
        suba    PlayerPixelY
        bpl     CheckPlayerEnemyContactYReady
        nega
CheckPlayerEnemyContactYReady:
        cmpa    #8
        bhs     CheckPlayerEnemyContactSkip
        jsr     PlayerHit
        lda     #1
        rts
CheckPlayerEnemyContactSkip:
        inc     QueryX
        bra     CheckPlayerEnemyContactNext
CheckPlayerEnemyContactClear:
        clra
        rts

PlayerHit:
        ; Infinite lives still plays the recoverable death sequence but never
        ; decrements the lives counter to game over. Any death breaks the
        ; room-local treasure streak, including one under infinite lives.
        clr     TreasureStreak
        tst     InfiniteLives
        bne     BeginPlayerDeath
        dec     PlayerLives
        bne     BeginPlayerDeath
        tst     DemoActive
        bne     EndDemoAfterFinalLife
        jsr     BeginPlayerDeathEffect
        lda     #GAME_STATE_OVER
        sta     GameState
        jsr     RecordHighScore
        jsr     SoundPlayerDeath
        jsr     DrawGameOverScreen
        rts
EndDemoAfterFinalLife:
        jmp     ShowTitleScreen

BeginPlayerDeath:
        jsr     BeginPlayerDeathEffect
        lda     #PLAYER_DEATH_EFFECT_FRAMES
        sta     PlayerDeathTimer
        jsr     DrawHudValues
        jsr     DrawHudIndicators
        jsr     DrawDeathStatus
        jsr     SoundPlayerDeath
        rts

BeginPlayerDeathEffect:
        jsr     EnsurePlayerFootprintRestored
        clr     PlayerVisible
        clr     PlayerCompositePending
        clr     PlayerMoveDirection
        clr     PlayerPixelsRemaining
        clr     PlayerStepBudget
        clr     PlayerStepCarry
        clr     PlayerFireTimer
        lda     PlayerPixelX
        adda    #4
        lsra
        lsra
        lsra
        sta     PlayerDeathX
        lda     PlayerPixelY
        adda    #4
        lsra
        lsra
        lsra
        sta     PlayerDeathY
        jsr     DrawPlayerDeathEffect
        rts

RespawnPlayer:
        ; Restore only the cells covered by the frozen death scene. The maze
        ; and HUD remain in place while the dynamic actors are reset. Each new
        ; life receives one flash bomb, whether or not the previous one was used.
        jsr     RestoreAllShotCells
        jsr     RestoreAllEnemyVisuals
        jsr     RestorePlayerDeathEffect
        jsr     SetPlayerAtCurrentRoomStart
        lda     #1
        sta     PlayerFacing
        sta     PlayerVisible
        sta     FlashAvailable
        lda     #PLAYER_INVULNERABLE_FRAMES
        sta     PlayerInvulnerabilityTimer
        lda     #PLAYER_INVULNERABLE_BLINK_DELAY
        sta     PlayerInvulnerabilityBlinkTimer
        clr     PlayerDeathTimer
        clr     PlayerRedrawPending
        clr     PlayerCompositePending
        jsr     ClearShots
        jsr     ResetEnemies
        jsr     DrawAllEnemies
        jsr     DrawPlayer
        jsr     DrawHudIndicators
        jsr     DrawDeathStatus
        jsr     SoundRespawn
        rts

;==============================================================================
; Run/room initialization, frame pacing, and game-state dispatcher
;
; World coordinates are room-local. CurrentLevel is the zero-based stage,
; CurrentRoom is the zero-based room, and CurrentStageRoomIndex is their
; flattened 0-20 table index.
;
; Register contract for exported entries:
;   Inputs: none.
;   Outputs: run, room, actor, or presentation state as named by the entry.
;   Clobbers: A, B, X, Y, U, CC. S is balanced and DP is unchanged.
; WaitMainLoopFrame and RunGameFrame are the main-loop API; ResetLevel,
; LoadCurrentRoomMap, SetCurrentStageRoomIndex, and
; SetPlayerAtCurrentRoomStart are cross-fragment progression helpers.
;==============================================================================

ResetLevel:
        ; Reset a complete run to Stage 1 Room 1. High scores and the session
        ; cheat unlock survive; score, inventory, actors, and run state do not.
        clr     CurrentLevel
        clr     CurrentRoom
        jsr     LoadCurrentRoomMap
        clr     GameState
        clr     HasKey
        clr     ExtraLifeAwarded
        clr     ScoreTenThousands
        clr     ScoreHundreds
        clr     NewHighScoreFlag
        clr     PresentationTimer
        clr     StatusMessageTimer
        clr     PlayerMoveDirection
        clr     PlayerPixelsRemaining
        clr     PlayerPixelMoveTimer
        clr     PlayerSpeedPhase
        clr     PlayerStepBudget
        clr     PlayerStepCarry
        clr     PlayerAnimationFrame
        clr     PlayerFireTimer
        clr     PlayerInvulnerabilityTimer
        clr     PlayerInvulnerabilityBlinkTimer
        clr     PlayerDeathTimer
        clr     PlayerDeathX
        clr     PlayerDeathY
        clr     PlayerVisualDirty
        clr     PlayerRedrawPending
        clr     PlayerCompositePending
        clr     InfiniteLives
        clr     GuardianHitsDisabled
        clr     ShotMoveTimer
        clr     ShotAnimationFrame
        jsr     SetPlayerAtCurrentRoomStart
        lda     #1
        sta     PlayerFacing
        sta     PlayerVisible
        sta     FlashAvailable
        lda     #PLAYER_START_LIVES
        sta     PlayerLives
        jsr     ClearShots
        jsr     ResetEnemies
        rts

; Resolve the active stage/room, unpack its two-tiles-per-byte map, and select
; its wall color and enemy slice.
; Score, lives, key, and flash inventory are intentionally untouched here. A
; treasure streak is local to one room, so every room load starts it at zero.
LoadCurrentRoomMap:
        clr     TreasureStreak
        jsr     SetCurrentStageRoomIndex

        ldb     CurrentStageRoomIndex
        ldx     #RoomWallColors
        lda     b,x
        sta     CurrentWallColor

        lda     CurrentStageRoomIndex
        ldb     #ENEMY_SPAWN_COUNT
        mul
        stb     CurrentRoomEnemyOffset

        ldb     CurrentStageRoomIndex
        aslb
        ldx     #RoomTemplatePointers
        ldx     b,x
        ldu     #LevelMap
        ldy     #PackedTileValues
LoadCurrentRoomMapNext:
        lda     ,x+
        tfr     a,b
        lsra
        lsra
        lsra
        lsra
        anda    #$0F
        lda     a,y
        sta     ,u+
        andb    #$0F
        lda     b,y
        sta     ,u+
        cmpu    #LevelMap+LEVEL_CELL_COUNT
        blo     LoadCurrentRoomMapNext
        rts

SetCurrentStageRoomIndex:
        ; Variable-size stages flatten through their first-room offsets.
        ldb     CurrentLevel
        ldx     #StageRoomOffsets
        lda     b,x
        adda    CurrentRoom
        sta     CurrentStageRoomIndex
        rts

SetPlayerAtCurrentRoomStart:
        jsr     SetCurrentStageRoomIndex
        ldb     CurrentStageRoomIndex
        ldx     #RoomPlayerStartX
        lda     b,x
        sta     PlayerX
        ldx     #RoomPlayerStartY
        lda     b,x
        sta     PlayerY
        jmp     SyncPlayerPixelPosition

;------------------------------------------------------------------------------
; Per-frame dispatcher
;------------------------------------------------------------------------------
; Use the historical delay in presentation states and while the original three
; guardian slots are the only active workload. Each additional active snake
; removes about 1,600 cycles of otherwise idle delay, keeping real-time motion
; near the established cadence without changing any per-frame movement values.
WaitMainLoopFrame:
        ldx     #FRAME_DELAY_ITERATIONS
        lda     GameState
        bne     WaitMainLoopFrameLoop

        ; Count live slots rather than checking fixed indices: a destroyed
        ; original snake must not leave the frame over-compensated while a
        ; later slot remains active.
        ldy     #EnemyActive
        clrb
        lda     #ENEMY_COUNT
WaitMainLoopFrameCountEnemy:
        tst     ,y+
        beq     WaitMainLoopFrameCountNext
        incb
WaitMainLoopFrameCountNext:
        deca
        bne     WaitMainLoopFrameCountEnemy
        cmpb    #ENEMY_SPAWN_COUNT
        bls     WaitMainLoopFrameLoop
        subb    #ENEMY_SPAWN_COUNT
WaitMainLoopFrameCompensate:
        leax    -FRAME_DELAY_EXTRA_ENEMY_ITERATIONS,x
        decb
        bne     WaitMainLoopFrameCompensate
WaitMainLoopFrameLoop:
        leax    -1,x
        bne     WaitMainLoopFrameLoop
        rts

RunGameFrame:
        jsr     UpdatePlayerFireAnimation
        jsr     ReadInput
        jsr     AdvanceDemoRandom
        tst     DemoActive
        beq     RunGameFrameDispatch
        lda     Dpad_Held
        ora     Action_Held
        beq     RunDemoFrame
RunDemoCancel:
        ; Any real input dismisses attract mode. In particular, Space/Fire
        ; returns to the title and must be released and pressed again to play.
        jsr     ShowTitleScreen
        lbra    RunGameFrameDone
RunDemoFrame:
        jsr     UpdateDemoTimer
        tst     DemoActive
        lbeq    RunGameFrameDone
        tst     GameState
        bne     RunGameFrameDispatch
        jsr     BuildDemoInput
RunGameFrameDispatch:
        lda     GameState
        beq     RunPlayingFrame
        cmpa    #GAME_STATE_TITLE
        beq     RunTitleFrame
        cmpa    #GAME_STATE_LEVEL_INTRO
        beq     RunLevelIntroFrame

        lda     Action_Press
        bita    #ACTION_FIRE_MASK
        lbeq    RunGameFrameDone
        jsr     ShowTitleScreen
        lbra    RunGameFrameDone

RunTitleFrame:
        jsr     UpdateTitleCheatSequence
        lda     Action_Press
        bita    #ACTION_FIRE_MASK
        beq     RunTitleSceneFrame
        jsr     StartNewGame
        bra     RunGameFrameDone
RunTitleSceneFrame:
        jsr     UpdateTitleIdleTimer
        lda     GameState
        cmpa    #GAME_STATE_TITLE
        bne     RunGameFrameDone
        jsr     UpdateTitleScene
        bra     RunGameFrameDone

RunLevelIntroFrame:
        dec     PresentationTimer
        bne     RunGameFrameDone
        clr     GameState
        jsr     DrawGameScreen
        bra     RunGameFrameDone

RunPlayingFrame:
        jsr     UpdateStatusMessage
        jsr     ToggleInfiniteLives
        jsr     DisableGuardianHits
        tst     PlayerDeathTimer
        beq     RunPlayingPlayerAlive
        jsr     UpdatePlayerDeath
        bra     RunGameFrameDone
RunPlayingPlayerAlive:
        clr     PlayerCompositePending
        jsr     UpdatePlayerInvulnerability
        jsr     ProcessPlayer
        tst     PlayerDeathTimer
        bne     RunGameFrameDone
        lda     GameState
        bne     RunGameFrameDone

        ; Repaint the explorer as soon as its position or pose changes. Keep a
        ; second composite pending so shots and guardians can still be drawn
        ; underneath it without leaving the explorer erased for most of a
        ; simulation frame.
        tst     PlayerRedrawPending
        beq     RunPlayingProcessShots
        jsr     DrawVisiblePlayerPose
        clr     PlayerRedrawPending
        lda     #1
        sta     PlayerCompositePending
RunPlayingProcessShots:
        jsr     ProcessShots
        lda     GameState
        bne     RunGameFrameDone
        jsr     ProcessEnemies
        lda     GameState
        bne     RunGameFrameDone

        ; Preserve the final top layer after dynamic actors have updated.
        lda     PlayerRedrawPending
        ora     PlayerCompositePending
        beq     RunGameFrameDone
        jsr     DrawVisiblePlayerPose
        clr     PlayerRedrawPending
        clr     PlayerCompositePending
        bra     RunGameFrameDone

RunGameFrameDone:
        rts

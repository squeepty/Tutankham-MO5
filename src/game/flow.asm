;==============================================================================
; Nine-stage game flow and rules
;
; Frame pipeline while playing:
;   1. expire the firing pose, poll normalized input, and dispatch GameState;
;   2. update status/cheat state and explorer damage or movement;
;   3. restore/move/redraw projectiles;
;   4. restore/move/redraw guardians and resolve contact;
;   5. composite the explorer again when another actor may have crossed it.
;
; World coordinates are room-local. CurrentLevel is the zero-based stage,
; CurrentRoom is the zero-based room, and CurrentStageRoomIndex is their
; flattened 0-20 table index. Most actor routines communicate through
; CurrentActorIndex and CandidateX/Y to keep the 6809 hot paths compact.
;
; State-changing routines generally tail-call their renderer or sound cue.
; Callers must therefore not assume A/B/X/Y/U survive unless a local contract
; says so.
;==============================================================================

;------------------------------------------------------------------------------
; Session, run, and room initialization
;------------------------------------------------------------------------------
; Initialize only once after loading. High-score bytes use their assembled
; defaults and intentionally are not cleared here.
InitGame:
        clr     CheatUnlocked
        clr     TitleCheatProgress
        clr     TitleCheatHeldKey
        lda     #$A5
        sta     DemoRandomState
        clr     DemoActive
ShowTitleScreen:
        clr     DemoActive
        clr     TitleCheatProgress
        clr     TitleCheatHeldKey
        lda     #GAME_STATE_TITLE
        sta     GameState
        clr     PresentationTimer
        clr     TitleIdleSeconds
        lda     #TITLE_IDLE_SECOND_FRAMES
        sta     TitleIdleFrameTimer
        jsr     ResetTitleScene
        jmp     DrawTitleScreen

StartNewGame:
        clr     DemoActive
        jsr     ResetLevel
        lda     #GAME_STATE_LEVEL_INTRO
        sta     GameState
        lda     #LEVEL_INTRO_FRAMES
        sta     PresentationTimer
        jsr     DrawLevelIntroScreen
        jmp     SoundLevelStart

StartDemo:
        jsr     ResetLevel
        lda     #1
        sta     DemoActive
        lda     DemoRandomState
StartDemoReduceLevel:
        cmpa    #LEVEL_COUNT
        blo     StartDemoLevelReady
        suba    #LEVEL_COUNT
        bra     StartDemoReduceLevel
StartDemoLevelReady:
        sta     CurrentLevel
        clr     CurrentRoom
        jsr     LoadCurrentRoomMap
        jsr     SetPlayerAtCurrentRoomStart
        jsr     ClearShots
        jsr     ResetEnemies
        jsr     ClearDemoVisitMap
        clr     DemoMoveDirection
        clr     DemoTargetValid
        lda     #DEMO_FIRE_INTERVAL_FRAMES
        sta     DemoFireTimer
        lda     #DEMO_FLASH_DELAY_FRAMES
        sta     DemoFlashTimer
        lda     #TITLE_IDLE_SECOND_FRAMES
        sta     DemoSecondFrameTimer
        lda     #DEMO_DURATION_SECONDS
        sta     DemoSecondsRemaining
        clr     GameState
        jsr     DrawGameScreen
        jmp     SoundLevelStart

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
; Score, lives, key, and flash inventory are intentionally untouched here.
LoadCurrentRoomMap:
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

;------------------------------------------------------------------------------
; Title cheat, title idle timeout, and attract-scene state machine
;------------------------------------------------------------------------------
; Scan the seven unique keys used by SQUEEPTY while the title is active.
; TitleCheatHeldKey supplies edge detection, including the repeated E.
UpdateTitleCheatSequence:
        tst     CheatUnlocked
        bne     UpdateTitleCheatSequenceDone
        clrb
        ldx     #TitleCheatKeySelectors
UpdateTitleCheatScan:
        lda     b,x
        jsr     ReadKeyboardSelector
        beq     UpdateTitleCheatKeyFound
        incb
        cmpb    #TITLE_CHEAT_KEY_COUNT
        blo     UpdateTitleCheatScan
        clr     TitleCheatHeldKey
        rts
UpdateTitleCheatKeyFound:
        incb
        cmpb    TitleCheatHeldKey
        beq     UpdateTitleCheatSequenceDone
        stb     TitleCheatHeldKey

        ; Treat accepted cheat keys as title activity so the demo cannot start
        ; while the sequence is being entered.
        clr     TitleIdleSeconds
        lda     #TITLE_IDLE_SECOND_FRAMES
        sta     TitleIdleFrameTimer

        ldb     TitleCheatProgress
        ldx     #TitleCheatSequence
        lda     b,x
        cmpa    TitleCheatHeldKey
        bne     UpdateTitleCheatMismatch
        inc     TitleCheatProgress
        lda     TitleCheatProgress
        cmpa    #TITLE_CHEAT_SEQUENCE_LENGTH
        blo     UpdateTitleCheatSequenceDone
        lda     #1
        sta     CheatUnlocked
        jsr     DrawTitleCheatUnlocked
        bra     UpdateTitleCheatSequenceDone
UpdateTitleCheatMismatch:
        lda     TitleCheatHeldKey
        cmpa    #1
        bne     UpdateTitleCheatReset
        lda     #1
        sta     TitleCheatProgress
        bra     UpdateTitleCheatSequenceDone
UpdateTitleCheatReset:
        clr     TitleCheatProgress
UpdateTitleCheatSequenceDone:
        rts

ToggleInfiniteLives:
        ; Input scanning already gates I behind CheatUnlocked. Keeping the
        ; toggle here centralizes HUD and status updates.
        lda     Action_Press
        bita    #ACTION_INFINITE_LIVES_MASK
        beq     ToggleInfiniteLivesDone
        lda     InfiniteLives
        eora    #$01
        sta     InfiniteLives
        beq     ToggleInfiniteLivesOff
        lda     #PLAYER_START_LIVES
        sta     PlayerLives
        jsr     DrawHudIndicators
        jmp     DrawInfiniteLivesOnStatus
ToggleInfiniteLivesOff:
        jsr     DrawHudIndicators
        jmp     DrawInfiniteLivesOffStatus
ToggleInfiniteLivesDone:
        rts

DisableGuardianHits:
        ; D is a one-way switch for the current run so its normal role as the
        ; AZERTY right-movement key cannot accidentally re-enable contact.
        lda     Action_Press
        bita    #ACTION_DISABLE_GUARDIAN_HITS_MASK
        beq     DisableGuardianHitsDone
        tst     GuardianHitsDisabled
        bne     DisableGuardianHitsDone
        lda     #1
        sta     GuardianHitsDisabled
        jmp     DrawGuardianHitsDisabledStatus
DisableGuardianHitsDone:
        rts

DrawVisiblePlayerPose:
        tst     PlayerVisible
        beq     DrawVisiblePlayerPoseDone
        tst     PlayerFireTimer
        beq     DrawVisiblePlayerPoseWalk
        jmp     DrawPlayerFire
DrawVisiblePlayerPoseWalk:
        jmp     DrawPlayer
DrawVisiblePlayerPoseDone:
        rts

AdvanceDemoRandom:
        ; Eight-bit LFSR-like mixer. Human input perturbs the state, providing
        ; varied demo stages without a clock or hardware random source.
        lda     DemoRandomState
        lsra
        bcc     AdvanceDemoRandomMixInput
        eora    #$B8
AdvanceDemoRandomMixInput:
        eora    Dpad_Held
        eora    Action_Held
        bne     AdvanceDemoRandomStore
        lda     #$A5
AdvanceDemoRandomStore:
        sta     DemoRandomState
        rts

UpdateTitleIdleTimer:
        lda     Dpad_Held
        ora     Action_Held
        beq     UpdateTitleIdleTick
        clr     TitleIdleSeconds
        lda     #TITLE_IDLE_SECOND_FRAMES
        sta     TitleIdleFrameTimer
        rts
UpdateTitleIdleTick:
        dec     TitleIdleFrameTimer
        bne     UpdateTitleIdleDone
        lda     #TITLE_IDLE_SECOND_FRAMES
        sta     TitleIdleFrameTimer
        inc     TitleIdleSeconds
        lda     TitleIdleSeconds
        cmpa    #TITLE_IDLE_SECONDS
        blo     UpdateTitleIdleDone
        jmp     StartDemo
UpdateTitleIdleDone:
        rts

UpdateDemoTimer:
        dec     DemoSecondFrameTimer
        bne     UpdateDemoTimerDone
        lda     #TITLE_IDLE_SECOND_FRAMES
        sta     DemoSecondFrameTimer
        dec     DemoSecondsRemaining
        bne     UpdateDemoTimerDone
        jmp     ShowTitleScreen
UpdateDemoTimerDone:
        rts

ResetTitleScene:
        lda     #TITLE_SCENE_PHASE_CENTER_PAUSE
        sta     TitleScenePhase
        clr     TitleSceneSnakeVisible
        clr     TitleSceneShotActive
        lda     #TITLE_SCENE_INITIAL_FRAMES
        sta     TitleSceneHoldTimer
        lda     #TITLE_SCENE_PLAYER_CENTER_PIXEL_X
        sta     TitleScenePlayerPixelX
        lda     #TITLE_SCENE_DIAMOND_BOTH_MASK
        sta     TitleSceneDiamondMask
        rts

; Dispatch the compact title animation. Every phase either holds, advances a
; pixel coordinate, or changes visibility; rendering owns only the framed band.
UpdateTitleScene:
        lda     TitleScenePhase
        lbeq    UpdateTitleSceneApproach
        cmpa    #TITLE_SCENE_PHASE_FIRST_ALERT
        lbeq    UpdateTitleSceneFirstAlert
        cmpa    #TITLE_SCENE_PHASE_FIRST_SHOT
        lbeq    UpdateTitleSceneFirstShot
        cmpa    #TITLE_SCENE_PHASE_SECOND_ALERT
        lbeq    UpdateTitleSceneSecondAlert
        cmpa    #TITLE_SCENE_PHASE_SECOND_SHOT
        lbeq    UpdateTitleSceneSecondShot
        cmpa    #TITLE_SCENE_PHASE_COLLECT
        lbeq    UpdateTitleSceneCollect
        cmpa    #TITLE_SCENE_PHASE_RETURN_CENTER
        lbeq    UpdateTitleSceneReturnCenter
        lbra    UpdateTitleSceneCenterPause

UpdateTitleSceneApproach:
        jsr     EraseTitleSceneDynamic
        lda     TitleScenePlayerPixelX
        suba    #TITLE_SCENE_PLAYER_SPEED
        sta     TitleScenePlayerPixelX
        cmpa    #TITLE_SCENE_PLAYER_ALERT_PIXEL_X
        lbhi    UpdateTitleSceneDraw
        lda     #TITLE_SCENE_PLAYER_ALERT_PIXEL_X
        sta     TitleScenePlayerPixelX
        lda     #TITLE_SCENE_PHASE_FIRST_ALERT
        sta     TitleScenePhase
        lda     #TITLE_SCENE_ALERT_FRAMES
        sta     TitleSceneHoldTimer
        lda     #TITLE_SCENE_FIRST_SNAKE_PIXEL_X
        sta     TitleSceneSnakePixelX
        lda     #1
        sta     TitleSceneSnakeVisible
        lbra    UpdateTitleSceneDraw

UpdateTitleSceneFirstAlert:
        jsr     EraseTitleSceneDynamic
        lda     TitleSceneSnakePixelX
        suba    #TITLE_SCENE_SNAKE_SPEED
        sta     TitleSceneSnakePixelX
        dec     TitleSceneHoldTimer
        lbne    UpdateTitleSceneDraw
        lda     #TITLE_SCENE_PHASE_FIRST_SHOT
        sta     TitleScenePhase
        jsr     StartTitleSceneShot
        lbra    UpdateTitleSceneDraw

UpdateTitleSceneFirstShot:
        jsr     EraseTitleSceneDynamic
        lda     TitleSceneSnakePixelX
        suba    #TITLE_SCENE_SNAKE_SPEED
        sta     TitleSceneSnakePixelX
        lda     TitleSceneShotPixelX
        adda    #TITLE_SCENE_SHOT_SPEED
        sta     TitleSceneShotPixelX
        cmpa    TitleSceneSnakePixelX
        lblo    UpdateTitleSceneDraw
        clr     TitleSceneShotActive
        lda     #TITLE_SCENE_SECOND_SNAKE_PIXEL_X
        sta     TitleSceneSnakePixelX
        lda     #TITLE_SCENE_ALERT_FRAMES
        sta     TitleSceneHoldTimer
        lda     #TITLE_SCENE_PHASE_SECOND_ALERT
        sta     TitleScenePhase
        jsr     DrawTitleSceneSnake
        jmp     SoundEnemyHit

UpdateTitleSceneSecondAlert:
        jsr     EraseTitleSceneDynamic
        lda     TitleSceneSnakePixelX
        suba    #TITLE_SCENE_SNAKE_SPEED
        sta     TitleSceneSnakePixelX
        dec     TitleSceneHoldTimer
        lbne    UpdateTitleSceneDraw
        lda     #TITLE_SCENE_PHASE_SECOND_SHOT
        sta     TitleScenePhase
        jsr     StartTitleSceneShot
        lbra    UpdateTitleSceneDraw

UpdateTitleSceneSecondShot:
        jsr     EraseTitleSceneDynamic
        lda     TitleSceneSnakePixelX
        suba    #TITLE_SCENE_SNAKE_SPEED
        sta     TitleSceneSnakePixelX
        lda     TitleSceneShotPixelX
        adda    #TITLE_SCENE_SHOT_SPEED
        sta     TitleSceneShotPixelX
        cmpa    TitleSceneSnakePixelX
        lblo    UpdateTitleSceneDraw
        clr     TitleSceneShotActive
        clr     TitleSceneSnakeVisible
        lda     #TITLE_SCENE_PHASE_COLLECT
        sta     TitleScenePhase
        jsr     DrawTitleSceneSnake
        jmp     SoundEnemyHit

UpdateTitleSceneCollect:
        jsr     EraseTitleSceneDynamic
        lda     TitleScenePlayerPixelX
        suba    #TITLE_SCENE_PLAYER_SPEED
        sta     TitleScenePlayerPixelX
        cmpa    #TITLE_SCENE_DIAMOND_RIGHT_PIXEL_X+TITLE_SCENE_DIAMOND_PICKUP_OFFSET
        bhi     UpdateTitleSceneCollectLeft
        lda     TitleSceneDiamondMask
        bita    #TITLE_SCENE_DIAMOND_RIGHT_MASK
        beq     UpdateTitleSceneCollectLeft
        anda    #$FF-TITLE_SCENE_DIAMOND_RIGHT_MASK
        sta     TitleSceneDiamondMask
        jsr     ClearTitleSceneRightDiamond
        jsr     DrawTitleSceneSnake
        jsr     SoundTreasurePickup
UpdateTitleSceneCollectLeft:
        lda     TitleScenePlayerPixelX
        cmpa    #TITLE_SCENE_DIAMOND_LEFT_PIXEL_X+TITLE_SCENE_DIAMOND_PICKUP_OFFSET
        lbhi    UpdateTitleSceneDraw
        lda     TitleSceneDiamondMask
        bita    #TITLE_SCENE_DIAMOND_LEFT_MASK
        beq     UpdateTitleSceneCollectArrival
        anda    #$FF-TITLE_SCENE_DIAMOND_LEFT_MASK
        sta     TitleSceneDiamondMask
        jsr     ClearTitleSceneLeftDiamond
        jsr     DrawTitleSceneSnake
        jsr     SoundTreasurePickup
UpdateTitleSceneCollectArrival:
        lda     TitleScenePlayerPixelX
        cmpa    #TITLE_SCENE_DIAMOND_LEFT_PIXEL_X
        lbhi    UpdateTitleSceneDraw
        lda     #TITLE_SCENE_DIAMOND_LEFT_PIXEL_X
        sta     TitleScenePlayerPixelX
        lda     #TITLE_SCENE_PHASE_RETURN_CENTER
        sta     TitleScenePhase
        lbra    UpdateTitleSceneDraw

UpdateTitleSceneReturnCenter:
        jsr     EraseTitleSceneDynamic
        lda     TitleScenePlayerPixelX
        adda    #TITLE_SCENE_PLAYER_SPEED
        sta     TitleScenePlayerPixelX
        cmpa    #TITLE_SCENE_PLAYER_CENTER_PIXEL_X
        lblo    UpdateTitleSceneDraw
        lda     #TITLE_SCENE_PLAYER_CENTER_PIXEL_X
        sta     TitleScenePlayerPixelX
        lda     #TITLE_SCENE_PHASE_CENTER_PAUSE
        sta     TitleScenePhase
        lda     #TITLE_SCENE_CENTER_FRAMES
        sta     TitleSceneHoldTimer
        lbra    UpdateTitleSceneDraw

UpdateTitleSceneCenterPause:
        dec     TitleSceneHoldTimer
        bne     UpdateTitleSceneDone
        clr     TitleScenePhase
        lda     #TITLE_SCENE_DIAMOND_BOTH_MASK
        sta     TitleSceneDiamondMask
        jmp     DrawTitleScene

StartTitleSceneShot:
        lda     TitleScenePlayerPixelX
        adda    #TITLE_SCENE_SHOT_START_OFFSET
        sta     TitleSceneShotPixelX
        lda     #1
        sta     TitleSceneShotActive
        jsr     DrawTitleSceneSnake
        jmp     SoundShot

UpdateTitleSceneDraw:
        jmp     DrawTitleSceneSnake
UpdateTitleSceneDone:
        rts

;------------------------------------------------------------------------------
; Demo controller
;------------------------------------------------------------------------------
; Demo mode runs the normal player pipeline after replacing only its normalized
; input. Objectives are cached per room/key state; movement favors the target,
; avoids immediate reversals and occupied enemy cells, then falls back through
; other legal directions.
BuildDemoInput:
        clr     Dpad_Held
        clr     Action_Press
        tst     PlayerDeathTimer
        bne     BuildDemoInputDone
        jsr     UpdateDemoActions
        tst     PlayerPixelsRemaining
        beq     BuildDemoChooseMove
        lda     DemoMoveDirection
        sta     Dpad_Held
        rts
BuildDemoChooseMove:
        jsr     UpdateDemoTarget
        jsr     PrepareDemoVisitMap
        jsr     ChooseDemoDirection
BuildDemoInputDone:
        rts

UpdateDemoActions:
        ; Fire only when a live guardian shares the explorer's row. Flash is a
        ; one-time delayed action so each demo exercises the normal bomb path.
        lda     DemoFireTimer
        beq     UpdateDemoTryFire
        dec     DemoFireTimer
        bra     UpdateDemoFlash
UpdateDemoTryFire:
        jsr     AimDemoAtHorizontalEnemy
        beq     UpdateDemoFireRetry
        lda     Action_Press
        ora     #ACTION_FIRE_MASK
        sta     Action_Press
        lda     #DEMO_FIRE_INTERVAL_FRAMES
        sta     DemoFireTimer
        bra     UpdateDemoFlash
UpdateDemoFireRetry:
        lda     #DEMO_FIRE_RETRY_FRAMES
        sta     DemoFireTimer
UpdateDemoFlash:
        tst     FlashAvailable
        beq     UpdateDemoActionsDone
        lda     DemoFlashTimer
        beq     UpdateDemoUseFlash
        dec     DemoFlashTimer
        bne     UpdateDemoActionsDone
UpdateDemoUseFlash:
        lda     Action_Press
        ora     #ACTION_FLASH_MASK
        sta     Action_Press
UpdateDemoActionsDone:
        rts

; Return A nonzero and face the correct side when an active enemy is aligned
; with the explorer's current cell row.
AimDemoAtHorizontalEnemy:
        clr     DemoScanX
AimDemoAtHorizontalEnemyNext:
        ldb     DemoScanX
        cmpb    #ENEMY_COUNT
        beq     AimDemoAtHorizontalEnemyMiss
        ldx     #EnemyActive
        tst     b,x
        beq     AimDemoAtHorizontalEnemySkip
        ldx     #EnemyY
        lda     b,x
        cmpa    PlayerY
        bne     AimDemoAtHorizontalEnemySkip
        ldx     #EnemyX
        lda     b,x
        cmpa    PlayerX
        blo     AimDemoAtHorizontalEnemyLeft
        lda     #1
        sta     PlayerFacing
        lda     #1
        rts
AimDemoAtHorizontalEnemyLeft:
        lda     #$FF
        sta     PlayerFacing
        lda     #1
        rts
AimDemoAtHorizontalEnemySkip:
        inc     DemoScanX
        bra     AimDemoAtHorizontalEnemyNext
AimDemoAtHorizontalEnemyMiss:
        clra
        rts

UpdateDemoTarget:
        lda     CurrentStageRoomIndex
        cmpa    DemoTargetRoomIndex
        bne     UpdateDemoTargetRebuild
        lda     HasKey
        cmpa    DemoTargetHasKey
        bne     UpdateDemoTargetRebuild
        tst     DemoTargetValid
        bne     UpdateDemoTargetDone
UpdateDemoTargetRebuild:
        lda     CurrentStageRoomIndex
        sta     DemoTargetRoomIndex
        lda     HasKey
        sta     DemoTargetHasKey
        clr     DemoTargetValid
        tst     HasKey
        bne     UpdateDemoTargetExit
        lda     #TILE_KEY
        jsr     FindDemoTargetTile
        bne     UpdateDemoTargetDone
UpdateDemoTargetExit:
        lda     #TILE_ROOM_EXIT
        ldb     CurrentLevel
        ldx     #StageRoomCounts
        ldb     b,x
        decb
        cmpb    CurrentRoom
        bhi     UpdateDemoTargetFindExit
        lda     #TILE_EXIT
UpdateDemoTargetFindExit:
        jsr     FindDemoTargetTile
UpdateDemoTargetDone:
        rts

; Input: A = tile to locate. Output: A nonzero if found.
FindDemoTargetTile:
        ; Row-major scan of LevelMap for a requested tile in A. The target
        ; cache is rebuilt only when room/key state changes.
        sta     DemoTargetTile
        ldx     #LevelMap
        clr     DemoScanY
        lda     #LEVEL_HEIGHT
        sta     MapRowsRemaining
FindDemoTargetTileRow:
        clr     DemoScanX
        lda     #LEVEL_WIDTH
        sta     MapCellsRemaining
FindDemoTargetTileNext:
        lda     ,x+
        cmpa    DemoTargetTile
        beq     FindDemoTargetTileFound
        inc     DemoScanX
        dec     MapCellsRemaining
        bne     FindDemoTargetTileNext
        inc     DemoScanY
        dec     MapRowsRemaining
        bne     FindDemoTargetTileRow
        clr     DemoTargetValid
        clra
        rts
FindDemoTargetTileFound:
        lda     DemoScanX
        sta     DemoTargetX
        lda     DemoScanY
        sta     DemoTargetY
        lda     #1
        sta     DemoTargetValid
        rts

ClearDemoVisitMap:
        ldx     #DemoVisitMap
        ldy     #LEVEL_CELL_COUNT
ClearDemoVisitMapNext:
        clr     ,x+
        leay    -1,y
        bne     ClearDemoVisitMapNext
        lda     CurrentStageRoomIndex
        sta     DemoVisitRoomIndex
        rts

PrepareDemoVisitMap:
        ; Preserve visit counts only while the demo remains in the same room.
        lda     CurrentStageRoomIndex
        cmpa    DemoVisitRoomIndex
        beq     MarkDemoCurrentCellVisited
        clr     DemoMoveDirection
        jsr     ClearDemoVisitMap
MarkDemoCurrentCellVisited:
        lda     PlayerX
        ldb     PlayerY
        jsr     GetLevelCellAddress
        leax    DemoVisitMap-LevelMap,x
        lda     ,x
        cmpa    #$FE
        bhs     PrepareDemoVisitMapDone
        inc     ,x
PrepareDemoVisitMapDone:
        rts

ChooseDemoDirection:
        ; Evaluate legal candidates in target-favoring order, penalize revisits,
        ; avoid immediate reversal, and keep reverse as the final fallback.
        clr     Dpad_Held
        clr     DemoHorizontalDirection
        clr     DemoVerticalDirection

        lda     PlayerX
        cmpa    DemoTargetX
        blo     ChooseDemoTargetRight
        bhi     ChooseDemoTargetLeft
        bra     ChooseDemoTargetVertical
ChooseDemoTargetRight:
        lda     #DPAD_RIGHT_MASK
        sta     DemoHorizontalDirection
        bra     ChooseDemoTargetVertical
ChooseDemoTargetLeft:
        lda     #DPAD_LEFT_MASK
        sta     DemoHorizontalDirection

ChooseDemoTargetVertical:
        lda     PlayerY
        cmpa    DemoTargetY
        blo     ChooseDemoTargetDown
        bhi     ChooseDemoTargetUp
        bra     ChooseDemoReverse
ChooseDemoTargetDown:
        lda     #DPAD_DOWN_MASK
        sta     DemoVerticalDirection
        bra     ChooseDemoReverse
ChooseDemoTargetUp:
        lda     #DPAD_UP_MASK
        sta     DemoVerticalDirection

ChooseDemoReverse:
        clr     DemoReverseDirection
        lda     DemoMoveDirection
        cmpa    #DPAD_UP_MASK
        beq     ChooseDemoReverseDown
        cmpa    #DPAD_DOWN_MASK
        beq     ChooseDemoReverseUp
        cmpa    #DPAD_LEFT_MASK
        beq     ChooseDemoReverseRight
        cmpa    #DPAD_RIGHT_MASK
        bne     ChooseDemoPreferredAxes
        lda     #DPAD_LEFT_MASK
        bra     ChooseDemoReverseStore
ChooseDemoReverseDown:
        lda     #DPAD_DOWN_MASK
        bra     ChooseDemoReverseStore
ChooseDemoReverseUp:
        lda     #DPAD_UP_MASK
        bra     ChooseDemoReverseStore
ChooseDemoReverseRight:
        lda     #DPAD_RIGHT_MASK
ChooseDemoReverseStore:
        sta     DemoReverseDirection

ChooseDemoPreferredAxes:
        lda     #$FF
        sta     DemoBestVisitScore
        clr     DemoBestDirection
        lda     DemoRandomState
        bita    #$01
        bne     ChooseDemoVerticalFirst
        lda     DemoHorizontalDirection
        jsr     ConsiderDemoDirection
        lda     DemoVerticalDirection
        jsr     ConsiderDemoDirection
        bra     ChooseDemoContinue
ChooseDemoVerticalFirst:
        lda     DemoVerticalDirection
        jsr     ConsiderDemoDirection
        lda     DemoHorizontalDirection
        jsr     ConsiderDemoDirection

ChooseDemoContinue:
        lda     DemoMoveDirection
        jsr     ConsiderDemoDirection

        lda     DemoRandomState
        bita    #$02
        bne     ChooseDemoFallbackB
        lda     #DPAD_UP_MASK
        jsr     ConsiderDemoDirection
        lda     #DPAD_RIGHT_MASK
        jsr     ConsiderDemoDirection
        lda     #DPAD_DOWN_MASK
        jsr     ConsiderDemoDirection
        lda     #DPAD_LEFT_MASK
        jsr     ConsiderDemoDirection
        bra     ChooseDemoCommitBest
ChooseDemoFallbackB:
        lda     #DPAD_DOWN_MASK
        jsr     ConsiderDemoDirection
        lda     #DPAD_LEFT_MASK
        jsr     ConsiderDemoDirection
        lda     #DPAD_UP_MASK
        jsr     ConsiderDemoDirection
        lda     #DPAD_RIGHT_MASK
        jsr     ConsiderDemoDirection

ChooseDemoCommitBest:
        lda     DemoBestDirection
        beq     ChooseDemoTryReverse
        sta     DemoMoveDirection
        sta     Dpad_Held
        rts
ChooseDemoTryReverse:
        lda     DemoReverseDirection
        jsr     TryDemoDirectionAndCommit
        bne     ChooseDemoDirectionDone
        clr     DemoMoveDirection
        clr     Dpad_Held
ChooseDemoDirectionDone:
        rts

ConsiderDemoDirection:
        tsta
        beq     ConsiderDemoDirectionDone
        cmpa    DemoReverseDirection
        beq     ConsiderDemoDirectionDone
        jsr     DemoDirectionIsSafe
        beq     ConsiderDemoDirectionDone
        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelCellAddress
        leax    DemoVisitMap-LevelMap,x
        lda     ,x
        cmpa    DemoBestVisitScore
        bhs     ConsiderDemoDirectionDone
        sta     DemoBestVisitScore
        lda     DemoCandidateDirection
        sta     DemoBestDirection
ConsiderDemoDirectionDone:
        rts

TryDemoDirectionAndCommit:
        tsta
        beq     TryDemoDirectionFailed
        jsr     DemoDirectionIsSafe
        beq     TryDemoDirectionFailed
        lda     DemoCandidateDirection
        sta     DemoMoveDirection
        sta     Dpad_Held
        lda     #1
        rts
TryDemoDirectionFailed:
        clra
        rts

; Input: A = one DPAD direction. Output: A nonzero when its destination is
; traversable, unlocked, and not currently occupied or targeted by a guardian.
DemoDirectionIsSafe:
        ; Safety is stricter than player collision: avoid walls, locked gates,
        ; spawner tiles, and both committed and target guardian cells.
        sta     DemoCandidateDirection
        lda     PlayerX
        sta     CandidateX
        lda     PlayerY
        sta     CandidateY
        lda     DemoCandidateDirection
        cmpa    #DPAD_UP_MASK
        beq     DemoDirectionUp
        cmpa    #DPAD_DOWN_MASK
        beq     DemoDirectionDown
        cmpa    #DPAD_LEFT_MASK
        beq     DemoDirectionLeft
        cmpa    #DPAD_RIGHT_MASK
        bne     DemoDirectionBlocked
        inc     CandidateX
        bra     DemoDirectionCheckTile
DemoDirectionUp:
        dec     CandidateY
        bra     DemoDirectionCheckTile
DemoDirectionDown:
        inc     CandidateY
        bra     DemoDirectionCheckTile
DemoDirectionLeft:
        dec     CandidateX
DemoDirectionCheckTile:
        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelTile
        cmpa    #TILE_WALL
        beq     DemoDirectionBlocked
        cmpa    #TILE_EXIT
        beq     DemoDirectionCheckKey
        cmpa    #TILE_ROOM_EXIT
        bne     DemoDirectionCheckEnemies
DemoDirectionCheckKey:
        tst     HasKey
        beq     DemoDirectionBlocked

DemoDirectionCheckEnemies:
        clr     DemoScanX
DemoDirectionEnemyNext:
        ldb     DemoScanX
        cmpb    #ENEMY_COUNT
        beq     DemoDirectionSafe
        ldx     #EnemyActive
        tst     b,x
        beq     DemoDirectionEnemySkip
        ldx     #EnemyX
        lda     b,x
        cmpa    CandidateX
        bne     DemoDirectionCheckEnemyTarget
        ldx     #EnemyY
        lda     b,x
        cmpa    CandidateY
        beq     DemoDirectionBlocked
DemoDirectionCheckEnemyTarget:
        ldx     #EnemyTargetX
        lda     b,x
        cmpa    CandidateX
        bne     DemoDirectionEnemySkip
        ldx     #EnemyTargetY
        lda     b,x
        cmpa    CandidateY
        beq     DemoDirectionBlocked
DemoDirectionEnemySkip:
        inc     DemoScanX
        bra     DemoDirectionEnemyNext
DemoDirectionSafe:
        lda     #1
        rts
DemoDirectionBlocked:
        clra
        rts

;------------------------------------------------------------------------------
; Status expiry, damage timers, and explorer simulation
;------------------------------------------------------------------------------
UpdateStatusMessage:
        lda     StatusMessageTimer
        beq     UpdateStatusMessageDone
        dec     StatusMessageTimer
        bne     UpdateStatusMessageDone
        jmp     ClearStatusLine
UpdateStatusMessageDone:
        rts

UpdatePlayerInvulnerability:
        lda     PlayerInvulnerabilityTimer
        beq     UpdatePlayerInvulnerabilityVisible
        dec     PlayerInvulnerabilityTimer
        beq     UpdatePlayerInvulnerabilityFinish
        lda     PlayerInvulnerabilityBlinkTimer
        beq     UpdatePlayerInvulnerabilityToggle
        dec     PlayerInvulnerabilityBlinkTimer
        rts
UpdatePlayerInvulnerabilityToggle:
        lda     #PLAYER_INVULNERABLE_BLINK_DELAY
        sta     PlayerInvulnerabilityBlinkTimer
        lda     PlayerVisible
        eora    #$01
        sta     PlayerVisible
        bne     UpdatePlayerInvulnerabilityShow
        jsr     EnsurePlayerFootprintRestored
        rts
UpdatePlayerInvulnerabilityShow:
        lda     #1
        sta     PlayerRedrawPending
        rts
UpdatePlayerInvulnerabilityFinish:
        clr     PlayerInvulnerabilityBlinkTimer
UpdatePlayerInvulnerabilityVisible:
        tst     PlayerVisible
        bne     UpdatePlayerInvulnerabilityDone
        lda     #1
        sta     PlayerVisible
        sta     PlayerRedrawPending
UpdatePlayerInvulnerabilityDone:
        rts

UpdatePlayerDeath:
        dec     PlayerDeathTimer
        bne     UpdatePlayerDeathDone
        jsr     RespawnPlayer
UpdatePlayerDeathDone:
        rts

ProcessPlayer:
        ; Continue an in-flight pixel move before considering a new direction.
        ; Opposite inputs cannot redirect the explorer halfway through a cell.
        tst     PlayerVisualDirty
        beq     ProcessPlayerCheckMovement
        jsr     EnsurePlayerFootprintRestored
        clr     PlayerVisualDirty
ProcessPlayerCheckMovement:
        tst     PlayerPixelsRemaining
        lbne    ContinuePlayerMove

        lda     Dpad_Held
        beq     ProcessPlayerNoDirection
        tst     PlayerPixelMoveTimer
        beq     ProcessPlayerDirectionReady
        dec     PlayerPixelMoveTimer
        lbra    ProcessPlayerActions
ProcessPlayerDirectionReady:
        bita    #DPAD_UP_MASK
        bne     ProcessPlayerUp
        bita    #DPAD_DOWN_MASK
        bne     ProcessPlayerDown
        bita    #DPAD_LEFT_MASK
        bne     ProcessPlayerLeft
        bita    #DPAD_RIGHT_MASK
        bne     ProcessPlayerRight
        bra     ProcessPlayerActions

ProcessPlayerNoDirection:
        clr     PlayerPixelMoveTimer
        clr     PlayerSpeedPhase
        clr     PlayerStepBudget
        clr     PlayerStepCarry
        clr     PlayerAnimationFrame
        bra     ProcessPlayerActions

ProcessPlayerUp:
        lda     PlayerX
        sta     CandidateX
        lda     PlayerY
        deca
        sta     CandidateY
        lda     #PLAYER_DIR_UP
        jsr     StartPlayerMove
        bra     ProcessPlayerActions

ProcessPlayerDown:
        lda     PlayerX
        sta     CandidateX
        lda     PlayerY
        inca
        sta     CandidateY
        lda     #PLAYER_DIR_DOWN
        jsr     StartPlayerMove
        bra     ProcessPlayerActions

ProcessPlayerLeft:
        lda     #$FF
        sta     PlayerFacing
        lda     PlayerX
        deca
        sta     CandidateX
        lda     PlayerY
        sta     CandidateY
        lda     #PLAYER_DIR_LEFT
        jsr     StartPlayerMove
        bra     ProcessPlayerActions

ProcessPlayerRight:
        lda     #1
        sta     PlayerFacing
        lda     PlayerX
        inca
        sta     CandidateX
        lda     PlayerY
        sta     CandidateY
        lda     #PLAYER_DIR_RIGHT
        jsr     StartPlayerMove
        bra     ProcessPlayerActions

ContinuePlayerMove:
        tst     PlayerPixelMoveTimer
        beq     ContinuePlayerMoveStep
        dec     PlayerPixelMoveTimer
        bra     ProcessPlayerActions
ContinuePlayerMoveStep:
        jsr     EnsurePlayerFootprintRestored
        jsr     PreparePlayerStepBudget
        jsr     AdvancePlayerFrame

ProcessPlayerActions:
        tst     GameState
        bne     ProcessPlayerDone
        lda     Action_Press
        bita    #ACTION_NEXT_ROOM_MASK
        beq     ProcessPlayerFire
        ; Development shortcut: reproduce arriving at an unlocked gate and
        ; follow the real transition/completion path.
        lda     #1
        sta     HasKey
        jmp     TryRoomTransition
ProcessPlayerFire:
        lda     Action_Press
        bita    #ACTION_FIRE_MASK
        beq     ProcessPlayerFlash
        jsr     FireShot
ProcessPlayerFlash:
        lda     Action_Press
        bita    #ACTION_FLASH_MASK
        beq     ProcessPlayerDone
        jsr     UseFlashBomb
ProcessPlayerDone:
        rts

UpdatePlayerFireAnimation:
        lda     PlayerFireTimer
        beq     UpdatePlayerFireAnimationDone
        dec     PlayerFireTimer
        bne     UpdatePlayerFireAnimationDone
        lda     #1
        sta     PlayerVisualDirty
UpdatePlayerFireAnimationDone:
        rts

; Input: A = one PLAYER_DIR_* value, CandidateX/Y = destination cell.
StartPlayerMove:
        ; CandidateX/Y must already contain the destination. Walls and locked
        ; gates reject the move; collectible/warp tiles remain traversable.
        sta     PlayerMoveDirection
        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelTile
        cmpa    #TILE_WALL
        beq     StartPlayerMoveBlocked
        cmpa    #TILE_EXIT
        beq     StartPlayerMoveCheckKey
        cmpa    #TILE_ROOM_EXIT
        bne     StartPlayerMoveAllowed
StartPlayerMoveCheckKey:
        tst     HasKey
        bne     StartPlayerMoveAllowed
        clr     PlayerMoveDirection
        jsr     DrawNeedKeyStatus
        rts

StartPlayerMoveAllowed:
        jsr     EnsurePlayerFootprintRestored
        lda     CandidateX
        sta     PlayerTargetX
        lda     CandidateY
        sta     PlayerTargetY
        lda     #PLAYER_CELL_PIXELS
        sta     PlayerPixelsRemaining
        jsr     PreparePlayerStepBudget
        jmp     AdvancePlayerFrame

StartPlayerMoveBlocked:
        clr     PlayerMoveDirection
        clr     PlayerSpeedPhase
        clr     PlayerStepBudget
        clr     PlayerStepCarry
        clr     PlayerAnimationFrame
        rts

; Build an exact 2.25-pixel average as repeating 2,2,2,3-pixel budgets. Carry
; pixels that could not cross a cell boundary into the next legal cell.
PreparePlayerStepBudget:
        ; Fixed cadence 2,2,2,3 pixels/frame plus carried unused credit.
        lda     #2
        sta     PlayerStepBudget
        lda     PlayerSpeedPhase
        inca
        cmpa    #4
        blo     PreparePlayerStepStorePhase
        clra
PreparePlayerStepStorePhase:
        sta     PlayerSpeedPhase
        bne     PreparePlayerStepCarry
        inc     PlayerStepBudget
PreparePlayerStepCarry:
        lda     PlayerStepCarry
        adda    PlayerStepBudget
        sta     PlayerStepBudget
        clr     PlayerStepCarry
        rts

AdvancePlayerFrame:
        tst     PlayerStepBudget
        beq     AdvancePlayerFrameDone
AdvancePlayerFrameNext:
        dec     PlayerStepBudget
        jsr     AdvancePlayerOnePixel
        tst     PlayerPixelsRemaining
        beq     AdvancePlayerFrameBoundary
        tst     PlayerStepBudget
        bne     AdvancePlayerFrameNext
AdvancePlayerFrameDone:
        rts
AdvancePlayerFrameBoundary:
        lda     PlayerStepBudget
        sta     PlayerStepCarry
        clr     PlayerStepBudget
        rts

AdvancePlayerOnePixel:
        lda     #PLAYER_PIXEL_MOVE_DELAY
        sta     PlayerPixelMoveTimer
        lda     PlayerMoveDirection
        cmpa    #PLAYER_DIR_UP
        beq     AdvancePlayerUp
        cmpa    #PLAYER_DIR_DOWN
        beq     AdvancePlayerDown
        cmpa    #PLAYER_DIR_LEFT
        beq     AdvancePlayerLeft
        inc     PlayerPixelX
        bra     AdvancePlayerStepped
AdvancePlayerUp:
        dec     PlayerPixelY
        bra     AdvancePlayerStepped
AdvancePlayerDown:
        inc     PlayerPixelY
        bra     AdvancePlayerStepped
AdvancePlayerLeft:
        dec     PlayerPixelX

AdvancePlayerStepped:
        dec     PlayerPixelsRemaining
        beq     CommitPlayerMove

        ; Alternate two walking poses every two sub-cell pixels.
        lda     PlayerPixelsRemaining
        lsra
        anda    #$01
        sta     PlayerAnimationFrame
        rts

CommitPlayerMove:
        ; Commit the destination only after all eight visible pixel steps, then
        ; resolve tile effects exactly once from the new cell.
        clr     PlayerMoveDirection
        clr     PlayerAnimationFrame
        lda     PlayerTargetX
        sta     PlayerX
        sta     CandidateX
        lda     PlayerTargetY
        sta     PlayerY
        sta     CandidateY

        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelTile
        cmpa    #TILE_KEY
        beq     CollectKey
        cmpa    #TILE_TREASURE
        beq     CollectTreasure
        cmpa    #TILE_WARP_DOWN
        beq     UseWarpDown
        cmpa    #TILE_WARP_UP
        beq     UseWarpUp
        cmpa    #TILE_EXIT
        lbeq    TryPlayerExit
        cmpa    #TILE_ROOM_EXIT
        beq     TryRoomTransition
        bra     FinishPlayerMove

CollectKey:
        lda     #1
        sta     HasKey
        lda     #2
        jsr     AddScore
        jsr     ClearCandidateTile
        jsr     DrawKeyStatus
        jsr     SoundKeyPickup
        bra     FinishPlayerMove

CollectTreasure:
        lda     #5
        jsr     AddScore
        jsr     ClearCandidateTile
        jsr     DrawTreasureStatus
        jsr     SoundTreasurePickup
        bra     FinishPlayerMove

UseWarpDown:
        lda     #WARP_DOWN_EXIT_Y
        sta     PlayerY
        jsr     SyncPlayerPixelPosition
        jsr     DrawWarpStatus
        jsr     SoundWarp
        bra     FinishPlayerMove

UseWarpUp:
        lda     #WARP_UP_EXIT_Y
        sta     PlayerY
        jsr     SyncPlayerPixelPosition
        jsr     DrawWarpStatus
        jsr     SoundWarp

FinishPlayerMove:
        jsr     DrawHudValues
        jsr     CheckPlayerEnemyContact
        rts

TryRoomTransition:
        ; N reaches this same path after supplying HasKey, so the development
        ; shortcut cannot bypass transition drawing or stage completion rules.
        ldb     CurrentLevel
        ldx     #StageRoomCounts
        ldb     b,x
        decb
        cmpb    CurrentRoom
        bls     TryPlayerExit

        jsr     SoundChamberClear
        lda     #GAME_STATE_ROOM_TRANSITION
        sta     GameState
        inc     CurrentRoom
        jsr     DrawHudValues
        jsr     DrawRoomTransitionStatus
        jsr     LoadCurrentRoomMap
        jsr     SetPlayerAtCurrentRoomStart
        lda     #1
        sta     PlayerFacing
        sta     PlayerVisible
        clr     PlayerInvulnerabilityTimer
        clr     PlayerInvulnerabilityBlinkTimer
        clr     PlayerDeathTimer
        clr     PlayerVisualDirty
        clr     PlayerRedrawPending
        clr     PlayerCompositePending
        jsr     ClearShots
        jsr     ResetEnemies
        jsr     DrawDiagonalRoomTransition
        clr     GameState
        jsr     DrawAllEnemies
        jsr     DrawPlayer
        jsr     DrawHudValues
        jsr     DrawInitialStatus
        jsr     SoundLevelStart
        rts

TryPlayerExit:
        tst     HasKey
        beq     TryPlayerExitLocked
        lda     #10
        jsr     AddScore
        lda     CurrentLevel
        cmpa    #LEVEL_LAST_INDEX
        bhs     CompleteAllStages

        inc     CurrentLevel
        clr     CurrentRoom
        clr     HasKey
        lda     #1
        sta     PlayerFacing
        sta     PlayerVisible
        clr     PlayerInvulnerabilityTimer
        clr     PlayerInvulnerabilityBlinkTimer
        clr     PlayerDeathTimer
        clr     PlayerVisualDirty
        clr     PlayerRedrawPending
        clr     PlayerCompositePending
        jsr     LoadCurrentRoomMap
        jsr     SetPlayerAtCurrentRoomStart
        jsr     ClearShots
        jsr     ResetEnemies
        lda     #GAME_STATE_LEVEL_INTRO
        sta     GameState
        lda     #LEVEL_INTRO_FRAMES
        sta     PresentationTimer
        jsr     DrawLevelIntroScreen
        jsr     SoundChamberClear
        rts

CompleteAllStages:
        tst     DemoActive
        bne     CompleteDemo
        lda     #GAME_STATE_COMPLETE
        sta     GameState
        jsr     RecordHighScore
        jsr     DrawCompleteScreen
        jsr     SoundChamberClear
        rts
CompleteDemo:
        jmp     ShowTitleScreen
TryPlayerExitLocked:
        jsr     DrawNeedKeyStatus
        rts

; Synchronize sub-cell state after reset, respawn, or an instantaneous warp.
SyncPlayerPixelPosition:
        ; Use after room load, death respawn, or warp to discard sub-cell state.
        lda     PlayerX
        lsla
        lsla
        lsla
        sta     PlayerPixelX
        lda     PlayerY
        lsla
        lsla
        lsla
        sta     PlayerPixelY
        clr     PlayerMoveDirection
        clr     PlayerPixelsRemaining
        clr     PlayerPixelMoveTimer
        clr     PlayerSpeedPhase
        clr     PlayerStepBudget
        clr     PlayerStepCarry
        clr     PlayerAnimationFrame
        clr     PlayerVisualDirty
        rts

ClearCandidateTile:
        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelCellAddress
        lda     #TILE_FLOOR
        sta     ,x
        rts

; Input: A = score in hundreds. Scores use a decimal high digit plus a
; two-digit hundreds byte, allowing five displayed digits through 99900.
;------------------------------------------------------------------------------
; Score and session high-score table
;------------------------------------------------------------------------------
; Input A is an award in hundreds. Scores saturate at 99900.
AddScore:
        adda    ScoreHundreds
        cmpa    #100
        blo     AddScoreStore
        suba    #100
        sta     ScoreHundreds
        lda     ScoreTenThousands
        cmpa    #9
        bhs     AddScoreSaturate
        inca
        sta     ScoreTenThousands
        bra     AddScoreCheckHigh
AddScoreSaturate:
        lda     #99
        sta     ScoreHundreds
        lda     #9
        sta     ScoreTenThousands
        bra     AddScoreCheckHigh
AddScoreStore:
        sta     ScoreHundreds
AddScoreCheckHigh:
        ; The run grants exactly one extra life on first reaching 20000.
        tst     ExtraLifeAwarded
        bne     AddScoreCheckHighScore
        lda     ScoreTenThousands
        cmpa    #EXTRA_LIFE_SCORE_TEN_THOUSANDS
        blo     AddScoreCheckHighScore
        lda     #1
        sta     ExtraLifeAwarded
        inc     PlayerLives
        jsr     DrawHudIndicators
AddScoreCheckHighScore:
        ldx     #HighScoreTenThousands
        jsr     CompareScoreToX
        bls     AddScoreDone
        lda     #1
        sta     NewHighScoreFlag
AddScoreDone:
        rts

RecordHighScore:
        ; Insert only distinct scores; shift lower ranks down in place.
        lda     ScoreTenThousands
        ora     ScoreHundreds
        beq     RecordHighScoreDone
        ldx     #HighScoreTenThousands
        jsr     CompareScoreToX
        beq     RecordHighScoreDone
        bhi     RecordHighScoreFirst
        ldx     #HighScoreSecondTenThousands
        jsr     CompareScoreToX
        beq     RecordHighScoreDone
        bhi     RecordHighScoreSecond
        ldx     #HighScoreThirdTenThousands
        jsr     CompareScoreToX
        bls     RecordHighScoreDone
        ldd     ScoreTenThousands
        std     HighScoreThirdTenThousands
        rts
RecordHighScoreFirst:
        ldd     HighScoreSecondTenThousands
        std     HighScoreThirdTenThousands
        ldd     HighScoreTenThousands
        std     HighScoreSecondTenThousands
        ldd     ScoreTenThousands
        std     HighScoreTenThousands
        rts
RecordHighScoreSecond:
        ldd     HighScoreSecondTenThousands
        std     HighScoreThirdTenThousands
        ldd     ScoreTenThousands
        std     HighScoreSecondTenThousands
RecordHighScoreDone:
        rts

; Compare the current score with the high/low score pair at X. Return the
; unsigned comparison flags for current score versus stored score.
CompareScoreToX:
        lda     ScoreTenThousands
        cmpa    ,x
        bne     CompareScoreToXDone
        lda     ScoreHundreds
        cmpa    1,x
CompareScoreToXDone:
        rts

;------------------------------------------------------------------------------
; Projectiles, hit testing, and flash bomb
;------------------------------------------------------------------------------
FireShot:
        ; Allocate the first inactive fixed slot. Shots start one cell ahead of
        ; the explorer and fail silently when all three slots are occupied.
        clr     CurrentActorIndex
FireShotFindSlot:
        ldb     CurrentActorIndex
        cmpb    #SHOT_COUNT
        beq     FireShotDone
        ldx     #ShotActive
        lda     b,x
        beq     FireShotUseSlot
        inc     CurrentActorIndex
        bra     FireShotFindSlot

FireShotUseSlot:
        jsr     EnsurePlayerFootprintRestored
        lda     #1
        sta     PlayerFireTimer
        jsr     SoundShot

        lda     PlayerX
        adda    PlayerFacing
        sta     CandidateX
        lda     PlayerY
        sta     CandidateY
        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelTile
        cmpa    #TILE_WALL
        beq     FireShotDone
        cmpa    #TILE_EXIT
        beq     FireShotDone
        jsr     HitEnemyAtCandidate
        bne     FireShotDone

        ldb     CurrentActorIndex
        ldx     #ShotActive
        lda     #1
        sta     b,x
        ldx     #ShotX
        lda     CandidateX
        sta     b,x
        ldx     #ShotY
        lda     CandidateY
        sta     b,x
        ldx     #ShotDirection
        lda     PlayerFacing
        sta     b,x
        jsr     DrawCurrentShot
FireShotDone:
        rts

ProcessShots:
        ; All active cells are restored first so movement/frame changes cannot
        ; leave trails. The pool then advances and redraws as one batch.
        lda     ShotMoveTimer
        beq     ProcessShotsMove
        dec     ShotMoveTimer
        rts
ProcessShotsMove:
        lda     #SHOT_MOVE_DELAY
        sta     ShotMoveTimer
        lda     ShotAnimationFrame
        eora    #$01
        sta     ShotAnimationFrame
        jsr     RestoreAllShotCells
        clr     CurrentActorIndex
ProcessShotsNext:
        ldb     CurrentActorIndex
        cmpb    #SHOT_COUNT
        beq     ProcessShotsRedraw
        ldx     #ShotActive
        lda     b,x
        beq     ProcessShotsSkip

        ldx     #ShotX
        lda     b,x
        sta     CandidateX
        ldx     #ShotY
        lda     b,x
        sta     CandidateY

        ldb     CurrentActorIndex
        ldx     #ShotDirection
        lda     b,x
        adda    CandidateX
        sta     CandidateX
        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelTile
        cmpa    #TILE_WALL
        beq     DeactivateCurrentShot
        cmpa    #TILE_EXIT
        beq     DeactivateCurrentShot
        jsr     HitEnemyAtCandidate
        bne     DeactivateCurrentShot

        ldb     CurrentActorIndex
        ldx     #ShotX
        lda     CandidateX
        sta     b,x
        bra     ProcessShotsSkip

DeactivateCurrentShot:
        ldb     CurrentActorIndex
        ldx     #ShotActive
        clr     b,x

ProcessShotsSkip:
        inc     CurrentActorIndex
        bra     ProcessShotsNext
ProcessShotsRedraw:
        jsr     DrawAllShots
ProcessShotsDone:
        rts

; Returns A nonzero when an enemy at CandidateX/CandidateY was removed.
HitEnemyAtCandidate:
        ; CandidateX/Y is the shot destination. A guardian's committed and
        ; targeted cells are both hittable during sub-cell motion.
        clr     QueryX
HitEnemyAtCandidateNext:
        ldb     QueryX
        cmpb    #ENEMY_COUNT
        beq     HitEnemyAtCandidateMiss
        ldx     #EnemyActive
        lda     b,x
        beq     HitEnemyAtCandidateSkip
        jsr     CurrentEnemyOverlapsCandidateCell
        beq     HitEnemyAtCandidateSkip

        lda     CurrentActorIndex
        pshs    a
        lda     QueryX
        sta     CurrentActorIndex
        jsr     DeactivateCurrentEnemy
        puls    a
        sta     CurrentActorIndex
        lda     #1
        jsr     AddScore
        jsr     DrawHudValues
        jsr     DrawEnemyHitStatus
        jsr     SoundEnemyHit
        lda     #1
        rts
HitEnemyAtCandidateSkip:
        inc     QueryX
        bra     HitEnemyAtCandidateNext
HitEnemyAtCandidateMiss:
        clra
        rts

UseFlashBomb:
        ; Deactivate every live guardian through the normal hit/respawn path.
        tst     FlashAvailable
        beq     UseFlashBombEmpty
        clr     FlashAvailable
        clr     CurrentActorIndex
UseFlashBombNext:
        ldb     CurrentActorIndex
        cmpb    #ENEMY_COUNT
        beq     UseFlashBombDone
        ldx     #EnemyActive
        lda     b,x
        beq     UseFlashBombSkip
        jsr     DeactivateCurrentEnemy
        lda     #1
        jsr     AddScore
UseFlashBombSkip:
        inc     CurrentActorIndex
        bra     UseFlashBombNext
UseFlashBombDone:
        jsr     DrawHudValues
        jsr     DrawHudIndicators
        jsr     DrawFlashStatus
        jsr     SoundFlash
        rts
UseFlashBombEmpty:
        jsr     DrawNoFlashStatus
        rts

; B = enemy index. Return A nonzero when its 8x8 pixel footprint overlaps the
; CandidateX/CandidateY cell occupied by a projectile.
CurrentEnemyOverlapsCandidateCell:
        lda     CandidateX
        lsla
        lsla
        lsla
        sta     MapDrawX
        lda     CandidateY
        lsla
        lsla
        lsla
        sta     MapDrawY

        ldx     #EnemyPixelX
        lda     b,x
        adda    #7
        cmpa    MapDrawX
        blo     CurrentEnemyCandidateMiss
        lda     MapDrawX
        adda    #7
        ldx     #EnemyPixelX
        cmpa    b,x
        blo     CurrentEnemyCandidateMiss

        ldx     #EnemyPixelY
        lda     b,x
        adda    #7
        cmpa    MapDrawY
        blo     CurrentEnemyCandidateMiss
        lda     MapDrawY
        adda    #7
        ldx     #EnemyPixelY
        cmpa    b,x
        blo     CurrentEnemyCandidateMiss
        lda     #1
        rts
CurrentEnemyCandidateMiss:
        clra
        rts

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

;------------------------------------------------------------------------------
; Guardian lifecycle, movement budget, animation, and chase decisions
;------------------------------------------------------------------------------
ProcessEnemies:
        ; Iterate the structure-of-arrays pool. Inactive slots update their hit
        ; effect/respawn; active slots animate, move, redraw, then test contact.
        clr     CurrentActorIndex
ProcessEnemiesNext:
        ldb     CurrentActorIndex
        cmpb    #ENEMY_COUNT
        beq     ProcessEnemiesContact
        ldx     #EnemyActive
        lda     b,x
        beq     ProcessEnemiesRespawn
        jsr     ProcessCurrentEnemyFrame
        bra     ProcessEnemiesSkip
ProcessEnemiesRespawn:
        jsr     UpdateCurrentEnemyRespawn
        ldb     CurrentActorIndex
        ldx     #EnemyActive
        lda     b,x
        beq     ProcessEnemiesSkip
        jsr     DrawCurrentEnemy
ProcessEnemiesSkip:
        inc     CurrentActorIndex
        bra     ProcessEnemiesNext
ProcessEnemiesContact:
        ; Repair projectile pixels that a moving guardian's map restore may
        ; have touched. Idle guardians themselves are never refreshed.
        jsr     DrawAllShots
        jsr     CheckPlayerEnemyContact
ProcessEnemiesDone:
        rts

ProcessCurrentEnemyFrame:
        ; A guardian can animate while blocked, but only restores its footprint
        ; once a movement or forced redraw has actually been scheduled.
        clr     CurrentEnemyForceRedraw
        jsr     UpdateCurrentEnemySpawnGrace
        ldb     CurrentActorIndex
        ldx     #EnemyPixelsRemaining
        lda     b,x
        bne     ProcessCurrentEnemyVisualUpdate

        ; Choose a new cell while the sprite is still untouched. If all exits
        ; are blocked, only its private animation timer may make it dirty.
        jsr     ChooseEnemyMove
        ldb     CurrentActorIndex
        ldx     #EnemyPixelsRemaining
        lda     b,x
        bne     ProcessCurrentEnemyVisualUpdate
        tst     CurrentEnemyForceRedraw
        bne     ProcessCurrentEnemyIdleRedraw
        ldx     #EnemyAnimationTimer
        lda     b,x
        beq     ProcessCurrentEnemyIdleFlip
        dec     b,x
        rts
ProcessCurrentEnemyIdleFlip:
        jsr     RestoreCurrentEnemyFootprint
        jsr     UpdateCurrentEnemyAnimation
        jmp     DrawCurrentEnemy
ProcessCurrentEnemyIdleRedraw:
        jsr     RestoreCurrentEnemyFootprint
        jmp     DrawCurrentEnemy

ProcessCurrentEnemyVisualUpdate:
        jsr     RestoreCurrentEnemyFootprint
        jsr     ProcessCurrentEnemyMotion
        jsr     UpdateCurrentEnemyAnimation
        jmp     DrawCurrentEnemy

ProcessCurrentEnemyMotion:
        ldb     CurrentActorIndex
        ldx     #EnemyPixelsRemaining
        lda     b,x
        bne     ProcessCurrentEnemyPrepare
        jsr     ChooseEnemyMove
        ldb     CurrentActorIndex
        ldx     #EnemyPixelsRemaining
        lda     b,x
        beq     ProcessCurrentEnemyDone
ProcessCurrentEnemyPrepare:
        jsr     PrepareCurrentEnemyStepBudget
ProcessCurrentEnemyStep:
        tst     CurrentEnemyStepBudget
        beq     ProcessCurrentEnemyDone
        dec     CurrentEnemyStepBudget
        jsr     AdvanceCurrentEnemyOnePixel
        ldb     CurrentActorIndex
        ldx     #EnemyPixelsRemaining
        lda     b,x
        bne     ProcessCurrentEnemyStep

        ; Do not choose another cell midway through the same display frame.
        ; Preserve unused pixel credit so cell boundaries cannot reduce speed.
        lda     CurrentEnemyStepBudget
        ldx     #EnemyStepCarry
        sta     b,x
        clr     CurrentEnemyStepBudget
ProcessCurrentEnemyDone:
        rts

PrepareCurrentEnemyStepBudget:
        ; Convert per-room eightieth-pixel speed units into whole-pixel credit.
        ldb     CurrentStageRoomIndex
        ldx     #EnemySpeedByRoom
        lda     b,x
        sta     CurrentEnemySpeedUnits
        ldb     CurrentActorIndex
        ldx     #EnemySpeedPhase
        lda     b,x
        adda    CurrentEnemySpeedUnits
        clr     CurrentEnemyStepBudget
PrepareCurrentEnemyExtractPixel:
        cmpa    #ENEMY_SPEED_SCALE
        blo     PrepareCurrentEnemyStorePhase
        suba    #ENEMY_SPEED_SCALE
        inc     CurrentEnemyStepBudget
        bra     PrepareCurrentEnemyExtractPixel
PrepareCurrentEnemyStorePhase:
        sta     b,x
PrepareCurrentEnemyCarry:
        ldx     #EnemyStepCarry
        lda     b,x
        adda    CurrentEnemyStepBudget
        sta     CurrentEnemyStepBudget
        clr     b,x
        rts

AdvanceCurrentEnemyOnePixel:
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        lda     b,x
        cmpa    #DPAD_UP_MASK
        beq     AdvanceCurrentEnemyUp
        cmpa    #DPAD_DOWN_MASK
        beq     AdvanceCurrentEnemyDown
        cmpa    #DPAD_LEFT_MASK
        beq     AdvanceCurrentEnemyLeft
        ldx     #EnemyPixelX
        inc     b,x
        bra     AdvanceCurrentEnemyStepped
AdvanceCurrentEnemyUp:
        ldx     #EnemyPixelY
        dec     b,x
        bra     AdvanceCurrentEnemyStepped
AdvanceCurrentEnemyDown:
        ldx     #EnemyPixelY
        inc     b,x
        bra     AdvanceCurrentEnemyStepped
AdvanceCurrentEnemyLeft:
        ldx     #EnemyPixelX
        dec     b,x
AdvanceCurrentEnemyStepped:
        ldx     #EnemyPixelsRemaining
        dec     b,x
        bne     AdvanceCurrentEnemyDone
        ldx     #EnemyTargetX
        lda     b,x
        ldx     #EnemyX
        sta     b,x
        ldx     #EnemyTargetY
        lda     b,x
        ldx     #EnemyY
        sta     b,x
AdvanceCurrentEnemyDone:
        rts

; Every guardian owns its pose timer. Initial and respawn offsets keep their
; rotations visibly independent instead of flipping as one group.
UpdateCurrentEnemyAnimation:
        ldb     CurrentActorIndex
        ldx     #EnemyAnimationTimer
        lda     b,x
        beq     UpdateCurrentEnemyAnimationFlip
        dec     b,x
        rts
UpdateCurrentEnemyAnimationFlip:
        lda     #ENEMY_ANIMATION_DELAY
        sta     b,x
        ldx     #EnemyAnimationFrame
        lda     b,x
        eora    #$01
        sta     b,x
        rts

UpdateCurrentEnemySpawnGrace:
        ldb     CurrentActorIndex
        ldx     #EnemySpawnGraceTimer
        lda     b,x
        beq     UpdateCurrentEnemySpawnGraceDone
        dec     b,x
        bne     UpdateCurrentEnemySpawnGraceDone
        lda     #1
        sta     CurrentEnemyForceRedraw
UpdateCurrentEnemySpawnGraceDone:
        rts

UpdateCurrentEnemyRespawn:
        ; Hit effects and respawn timers coexist in the inactive slot.
        jsr     UpdateCurrentEnemyHitEffect
        ldb     CurrentActorIndex
        ldx     #EnemyRespawnTimer
        lda     b,x
        beq     TryRespawnCurrentEnemy
        dec     b,x
        rts
TryRespawnCurrentEnemy:
        ; Do not materialize on top of the explorer or another live guardian.
        jsr     SetCurrentEnemyTableIndex
        ldb     CurrentRoomEnemyTableIndex
        ldx     #EnemyInitialX
        lda     b,x
        sta     CandidateX
        ldx     #EnemyInitialY
        lda     b,x
        sta     CandidateY
        lda     CandidateX
        cmpa    PlayerX
        bne     TryRespawnCheckActors
        lda     CandidateY
        cmpa    PlayerY
        beq     DelayCurrentEnemyRespawn
TryRespawnCheckActors:
        jsr     EnemyCandidateBlocked
        bne     DelayCurrentEnemyRespawn
        jsr     InitializeCurrentEnemyAtSpawn
        ldb     CurrentActorIndex
        ldx     #EnemySpawnGraceTimer
        lda     #ENEMY_RESPAWN_GRACE_FRAMES
        sta     b,x
        jmp     SoundRespawn
DelayCurrentEnemyRespawn:
        ldb     CurrentActorIndex
        ldx     #EnemyRespawnTimer
        lda     #10
        sta     b,x
        rts

UpdateCurrentEnemyHitEffect:
        ldb     CurrentActorIndex
        ldx     #EnemyHitEffectTimer
        lda     b,x
        beq     UpdateCurrentEnemyHitEffectDone
        dec     b,x
        bne     UpdateCurrentEnemyHitEffectDone
        ldx     #EnemyHitEffectX
        lda     b,x
        pshs    a
        ldx     #EnemyHitEffectY
        lda     b,x
        tfr     a,b
        puls    a
        jsr     DrawMapCellAt
UpdateCurrentEnemyHitEffectDone:
        rts

ChooseEnemyMove:
        ; Alternate the preferred chase axis per guardian and per junction.
        ; This prevents identical actors from taking every turn in lockstep.
        ldb     CurrentActorIndex
        ldx     #EnemyDecisionPhase
        inc     b,x
        lda     b,x
        bita    #$01
        bne     ChooseEnemyVerticalFirst
        jsr     TryEnemyTowardHorizontal
        lbne    ChooseEnemyMoveDone
        jsr     TryEnemyTowardVertical
        lbne    ChooseEnemyMoveDone
        bra     ChooseEnemyFallback
ChooseEnemyVerticalFirst:
        jsr     TryEnemyTowardVertical
        lbne    ChooseEnemyMoveDone
        jsr     TryEnemyTowardHorizontal
        lbne    ChooseEnemyMoveDone

ChooseEnemyFallback:
        ; Keep momentum when the direct chase route is blocked, then try both
        ; perpendicular turns. Immediate reversal is reserved for a dead end.
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        lda     b,x
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone

        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        lda     b,x
        cmpa    #DPAD_UP_MASK
        beq     ChooseEnemyHorizontalTurns
        cmpa    #DPAD_DOWN_MASK
        beq     ChooseEnemyHorizontalTurns

        ldx     #EnemyDecisionPhase
        lda     b,x
        bita    #$02
        bne     ChooseEnemyTryDownFirst
        lda     #DPAD_UP_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        lda     #DPAD_DOWN_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        bra     ChooseEnemyTryReverse
ChooseEnemyTryDownFirst:
        lda     #DPAD_DOWN_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        lda     #DPAD_UP_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        bra     ChooseEnemyTryReverse

ChooseEnemyHorizontalTurns:
        ldx     #EnemyDecisionPhase
        lda     b,x
        bita    #$02
        bne     ChooseEnemyTryRightFirst
        lda     #DPAD_LEFT_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        lda     #DPAD_RIGHT_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        bra     ChooseEnemyTryReverse
ChooseEnemyTryRightFirst:
        lda     #DPAD_RIGHT_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        lda     #DPAD_LEFT_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone

ChooseEnemyTryReverse:
        jsr     TryEnemyReverseDirection
ChooseEnemyMoveDone:
        rts

TryEnemyTowardHorizontal:
        ldb     CurrentActorIndex
        ldx     #EnemyX
        lda     b,x
        cmpa    PlayerX
        blo     TryEnemyTowardRight
        bhi     TryEnemyTowardLeft
        clra
        rts
TryEnemyTowardRight:
        lda     #DPAD_RIGHT_MASK
        jmp     TryEnemyDirectionPreferred
TryEnemyTowardLeft:
        lda     #DPAD_LEFT_MASK
        jmp     TryEnemyDirectionPreferred

TryEnemyTowardVertical:
        ldb     CurrentActorIndex
        ldx     #EnemyY
        lda     b,x
        cmpa    PlayerY
        blo     TryEnemyTowardDown
        bhi     TryEnemyTowardUp
        clra
        rts
TryEnemyTowardDown:
        lda     #DPAD_DOWN_MASK
        jmp     TryEnemyDirectionPreferred
TryEnemyTowardUp:
        lda     #DPAD_UP_MASK
        jmp     TryEnemyDirectionPreferred

; Input: A = proposed direction. Returns A nonzero when a move was started.
; Direct chase choices never reverse the current heading.
TryEnemyDirectionPreferred:
        sta     EnemyCandidateDirection
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        lda     b,x
        cmpa    #DPAD_UP_MASK
        beq     TryEnemyPreferredFromUp
        cmpa    #DPAD_DOWN_MASK
        beq     TryEnemyPreferredFromDown
        cmpa    #DPAD_LEFT_MASK
        beq     TryEnemyPreferredFromLeft
        lda     EnemyCandidateDirection
        cmpa    #DPAD_LEFT_MASK
        beq     TryEnemyDirectionFailed
        bra     TryEnemyDirectionStored
TryEnemyPreferredFromUp:
        lda     EnemyCandidateDirection
        cmpa    #DPAD_DOWN_MASK
        beq     TryEnemyDirectionFailed
        bra     TryEnemyDirectionStored
TryEnemyPreferredFromDown:
        lda     EnemyCandidateDirection
        cmpa    #DPAD_UP_MASK
        beq     TryEnemyDirectionFailed
        bra     TryEnemyDirectionStored
TryEnemyPreferredFromLeft:
        lda     EnemyCandidateDirection
        cmpa    #DPAD_RIGHT_MASK
        beq     TryEnemyDirectionFailed

TryEnemyDirectionStored:
        lda     EnemyCandidateDirection
TryEnemyDirection:
        sta     EnemyCandidateDirection
        ldb     CurrentActorIndex
        ldx     #EnemyX
        lda     b,x
        sta     CandidateX
        ldx     #EnemyY
        lda     b,x
        sta     CandidateY

        lda     EnemyCandidateDirection
        cmpa    #DPAD_UP_MASK
        beq     TryEnemyDirectionUp
        cmpa    #DPAD_DOWN_MASK
        beq     TryEnemyDirectionDown
        cmpa    #DPAD_LEFT_MASK
        beq     TryEnemyDirectionLeft
        inc     CandidateX
        bra     TryEnemyDirectionCheck
TryEnemyDirectionUp:
        dec     CandidateY
        bra     TryEnemyDirectionCheck
TryEnemyDirectionDown:
        inc     CandidateY
        bra     TryEnemyDirectionCheck
TryEnemyDirectionLeft:
        dec     CandidateX
TryEnemyDirectionCheck:
        jsr     EnemyCandidateBlocked
        bne     TryEnemyDirectionFailed

        lda     EnemyCandidateDirection
        jsr     StoreEnemyMoveDirection
TryEnemyDirectionStart:
        jsr     StartEnemyMove
        lda     #1
        rts
TryEnemyDirectionFailed:
        clra
        rts

TryEnemyReverseDirection:
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        lda     b,x
        cmpa    #DPAD_UP_MASK
        beq     TryEnemyReverseDown
        cmpa    #DPAD_DOWN_MASK
        beq     TryEnemyReverseUp
        cmpa    #DPAD_LEFT_MASK
        beq     TryEnemyReverseRight
        lda     #DPAD_LEFT_MASK
        lbra    TryEnemyDirection
TryEnemyReverseDown:
        lda     #DPAD_DOWN_MASK
        lbra    TryEnemyDirection
TryEnemyReverseUp:
        lda     #DPAD_UP_MASK
        lbra    TryEnemyDirection
TryEnemyReverseRight:
        lda     #DPAD_RIGHT_MASK
        lbra    TryEnemyDirection

StartEnemyMove:
        ldb     CurrentActorIndex
        ldx     #EnemyTargetX
        lda     CandidateX
        sta     b,x
        ldx     #EnemyTargetY
        lda     CandidateY
        sta     b,x
        ldx     #EnemyPixelsRemaining
        lda     #PLAYER_CELL_PIXELS
        sta     b,x
        rts

StoreEnemyMoveDirection:
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        sta     b,x
        rts

; Returns A nonzero for a wall or either kind of exit.
EnemyCandidateBlocked:
        ; A candidate is reserved by either another guardian's committed cell
        ; or its in-flight target, preventing two actors from converging.
        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelTile
        cmpa    #TILE_WALL
        beq     EnemyCandidateIsBlocked
        cmpa    #TILE_EXIT
        beq     EnemyCandidateIsBlocked
        cmpa    #TILE_ROOM_EXIT
        beq     EnemyCandidateIsBlocked
        clr     QueryX
EnemyCandidateCheckActors:
        ldb     QueryX
        cmpb    #ENEMY_COUNT
        beq     EnemyCandidateIsClear
        cmpb    CurrentActorIndex
        beq     EnemyCandidateNextActor
        ldx     #EnemyActive
        lda     b,x
        beq     EnemyCandidateNextActor
        ldx     #EnemyX
        lda     b,x
        cmpa    CandidateX
        bne     EnemyCandidateCheckActorTarget
        ldx     #EnemyY
        lda     b,x
        cmpa    CandidateY
        beq     EnemyCandidateIsBlocked
EnemyCandidateCheckActorTarget:
        ldx     #EnemyPixelsRemaining
        lda     b,x
        beq     EnemyCandidateNextActor
        ldx     #EnemyTargetX
        lda     b,x
        cmpa    CandidateX
        bne     EnemyCandidateNextActor
        ldx     #EnemyTargetY
        lda     b,x
        cmpa    CandidateY
        beq     EnemyCandidateIsBlocked
EnemyCandidateNextActor:
        inc     QueryX
        bra     EnemyCandidateCheckActors
EnemyCandidateIsClear:
        clra
        rts
EnemyCandidateIsBlocked:
        lda     #1
        rts

;------------------------------------------------------------------------------
; Explorer/guardian contact, death, respawn, and pool reset
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
        ; decrements the lives counter to game over.
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

ClearShots:
        ldx     #ShotActive
        ldb     #SHOT_COUNT
ClearShotsNext:
        clr     ,x+
        decb
        bne     ClearShotsNext
        clr     ShotMoveTimer
        clr     ShotAnimationFrame
        clr     PlayerFireTimer
        rts

;------------------------------------------------------------------------------
; Active-map addressing
;------------------------------------------------------------------------------
; Input: A = room X, B = room Y. Output: X = LevelMap cell address.
GetLevelCellAddress:
        sta     QueryX
        lda     #LEVEL_WIDTH
        mul
        addb    QueryX
        adca    #0
        ldx     #LevelMap
        leax    d,x
        rts

; Input: A = room X, B = room Y. Output: A = ASCII tile value.
GetLevelTile:
        jsr     GetLevelCellAddress
        lda     ,x
        rts

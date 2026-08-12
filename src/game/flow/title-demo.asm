;==============================================================================
; Title controls, attract scene, and demonstration driver
;
; Register contract for exported entries:
;   Inputs: none; input snapshots and game state are read from memory.
;   Outputs: title/demo state and synthetic input fields in memory.
;   Clobbers: A, B, X, Y, U, CC. S is balanced and DP is unchanged.
; Exported lifecycle helpers are UpdateTitleCheatSequence, ToggleInfiniteLives,
; DisableGuardianHits, DrawVisiblePlayerPose, AdvanceDemoRandom,
; UpdateTitleIdleTimer, UpdateDemoTimer, ResetTitleScene, UpdateTitleScene,
; BuildDemoInput, and ClearDemoVisitMap. FindDemoTargetTile and
; DemoDirectionIsSafe have narrower local contracts at their definitions.
;==============================================================================

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

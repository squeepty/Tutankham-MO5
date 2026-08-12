;==============================================================================
; Room/stage progression and scoring
;
; Register contract for exported entries:
;   TryRoomTransition/TryPlayerExit/SyncPlayerPixelPosition/ClearCandidateTile:
;     Inputs: none. Outputs: progression, position, or map state in memory.
;   AddScore: Inputs A = award in hundreds. Outputs score/life state in memory.
;   RecordHighScore: Inputs none. Outputs ordered high-score state in memory.
;   CompareScoreToX: Inputs X = high/low score pair. Outputs unsigned CC flags
;     for current score versus the pair; A contains the last compared byte.
;   Clobbers unless stated: A, B, X, Y, U, CC. S balanced; DP unchanged.
;==============================================================================

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

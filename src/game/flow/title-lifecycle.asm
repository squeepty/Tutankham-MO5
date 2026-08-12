;==============================================================================
; Title and demonstration lifecycle
;
; Register contract for exported entries:
;   Inputs: none.
;   Outputs: initialized session/run/title/demo state and presentation display.
;   Clobbers: A, B, X, Y, U, CC. S is balanced and DP is unchanged.
; InitGame is the startup API; ShowTitleScreen, StartNewGame, and StartDemo are
; cross-fragment lifecycle entries.
;==============================================================================

;------------------------------------------------------------------------------
; Session, title, run, and demonstration initialization
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

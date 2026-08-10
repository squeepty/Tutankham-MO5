;==============================================================================
; Seven-stage presentation and rendering
;
; Rendering model:
;   - LevelMap is authoritative for every static cell.
;   - Dynamic actors are OR-composited over restored map pixels.
;   - Before a moving actor changes position/pose, its old footprint is redrawn
;     from LevelMap; no background snapshots are stored.
;   - Arbitrary-X sprites use two bytes per row and eight pre-shifted phases.
;   - Arbitrary-Y positioning addresses scanlines directly.
;   - Platform drawing calls return with the bitmap plane selected.
;
; MapDraw*, PlayerFootprint*, and other renderer fields in state.asm are shared
; scratch. Public routines do not promise register preservation unless their
; local contract says so.
;==============================================================================

;------------------------------------------------------------------------------
; Title, attract scene, stage card, and terminal screens
;------------------------------------------------------------------------------
DrawTitleScreen:
        ; Full redraw. High scores are inserted into fixed templates, the title
        ; attract band is framed separately, and cheat status is session-based.
        jsr     ClearScreen
        lda     #COLOR_TITLE
        sta     TextColor
        ldu     #TitleLogoText
        lda     #15
        ldb     #2
        jsr     DrawString

        lda     #COLOR_TREASURE
        sta     DrawCellColor
        ldu     #CellTreasure
        lda     #11
        ldb     #2
        jsr     DrawCellPattern
        ldu     #CellTreasure
        lda     #27
        ldb     #2
        jsr     DrawCellPattern

        lda     #COLOR_TEXT
        sta     TextColor
        ldu     #TitleSubtitleText
        lda     #11
        ldb     #4
        jsr     DrawString
        ldu     #TitleHighScoreText
        lda     #14
        ldb     #11
        jsr     DrawString
        ldu     #TitleScoreEntry1Text
        lda     #16
        ldb     #13
        jsr     DrawString
        lda     #19
        sta     PresentationNumberColumn
        lda     #13
        sta     PresentationNumberRow
        lda     HighScoreHundreds
        ldb     HighScoreTenThousands
        jsr     DrawPresentationScore

        ldu     #TitleScoreEntry2Text
        lda     #16
        ldb     #15
        jsr     DrawString
        lda     #19
        sta     PresentationNumberColumn
        lda     #15
        sta     PresentationNumberRow
        lda     HighScoreSecondHundreds
        ldb     HighScoreSecondTenThousands
        jsr     DrawPresentationScore

        ldu     #TitleScoreEntry3Text
        lda     #16
        ldb     #17
        jsr     DrawString
        lda     #19
        sta     PresentationNumberColumn
        lda     #17
        sta     PresentationNumberRow
        lda     HighScoreThirdHundreds
        ldb     HighScoreThirdTenThousands
        jsr     DrawPresentationScore

        ldu     #TitlePromptText
        lda     #10
        ldb     #20
        jsr     DrawString
        ldu     #TitleControlsText
        lda     #4
        ldb     #23
        jsr     DrawString
        jsr     DrawTitleSceneFrame
        jsr     DrawTitleScene
        tst     CheatUnlocked
        beq     DrawTitleScreenDone
        jmp     DrawTitleCheatUnlocked
DrawTitleScreenDone:
        rts

DrawTitleCheatUnlocked:
        lda     #COLOR_TEXT
        sta     TextColor
        ldu     #TitleCheatUnlockedText
        lda     #9
        ldb     #22
        jmp     DrawString

; Frame the title attract animation with the same alternating stone cells used
; by the maze. The open 30-cell interior matches DrawTitleScene's clear span.
DrawTitleSceneFrame:
        clr     MapDrawY
        lda     #TITLE_SCENE_FRAME_HEIGHT
        sta     MapRowsRemaining
DrawTitleSceneFrameRow:
        clr     MapDrawX
        lda     #TITLE_SCENE_FRAME_WIDTH
        sta     MapCellsRemaining
DrawTitleSceneFrameCell:
        lda     MapDrawY
        beq     DrawTitleSceneFrameWall
        cmpa    #TITLE_SCENE_FRAME_HEIGHT-1
        beq     DrawTitleSceneFrameWall
        lda     MapDrawX
        beq     DrawTitleSceneFrameWall
        cmpa    #TITLE_SCENE_FRAME_WIDTH-1
        bne     DrawTitleSceneFrameSkip
DrawTitleSceneFrameWall:
        lda     #COLOR_WALL_ROOM_THREE
        sta     DrawCellColor
        ldu     #CellWallA
        lda     MapDrawX
        eora    MapDrawY
        bita    #$01
        beq     DrawTitleSceneFramePatternReady
        ldu     #CellWallB
DrawTitleSceneFramePatternReady:
        lda     MapDrawX
        adda    #TITLE_SCENE_FRAME_LEFT_COL
        ldb     MapDrawY
        addb    #TITLE_SCENE_FRAME_TOP_ROW
        jsr     DrawCellPattern
DrawTitleSceneFrameSkip:
        inc     MapDrawX
        dec     MapCellsRemaining
        bne     DrawTitleSceneFrameCell
        inc     MapDrawY
        dec     MapRowsRemaining
        bne     DrawTitleSceneFrameRow
        rts

; Redraw the compact title attract scene from its current state. The animation
; owns only the open horizontal band between the subtitle and high-score table.
DrawTitleScene:
        clr     MapDrawX
        lda     #TITLE_SCENE_CLEAR_CELLS
        sta     MapCellsRemaining
DrawTitleSceneClearNext:
        ldu     #CellEmpty
        lda     #COLOR_BACKGROUND
        sta     DrawCellColor
        lda     MapDrawX
        adda    #TITLE_SCENE_CLEAR_COL
        ldb     #TITLE_SCENE_ROW
        jsr     DrawCellPattern
        inc     MapDrawX
        dec     MapCellsRemaining
        bne     DrawTitleSceneClearNext

DrawTitleSceneObjects:
        lda     TitleSceneDiamondMask
        bita    #TITLE_SCENE_DIAMOND_LEFT_MASK
        beq     DrawTitleSceneRightDiamond
        lda     #COLOR_TREASURE
        sta     DrawCellColor
        ldu     #CellTreasure
        lda     #TITLE_SCENE_DIAMOND_LEFT_COL
        ldb     #TITLE_SCENE_ROW
        jsr     DrawCellPattern
DrawTitleSceneRightDiamond:
        lda     TitleSceneDiamondMask
        bita    #TITLE_SCENE_DIAMOND_RIGHT_MASK
        beq     DrawTitleSceneSnake
        lda     #COLOR_TREASURE
        sta     DrawCellColor
        ldu     #CellTreasure
        lda     #TITLE_SCENE_DIAMOND_RIGHT_COL
        ldb     #TITLE_SCENE_ROW
        jsr     DrawCellPattern

; Per-frame animation updates enter here so the resident diamonds above are
; neither cleared nor rewritten until their pickup frame.
DrawTitleSceneSnake:
        tst     TitleSceneSnakeVisible
        beq     DrawTitleSceneShot
        lda     #COLOR_ENEMY
        sta     DrawCellColor
        ldu     #EnemyLeftShiftedFrame0
        lda     TitleSceneSnakePixelX
        bita    #$10
        beq     DrawTitleSceneSnakePatternReady
        ldu     #EnemyLeftShiftedFrame1
DrawTitleSceneSnakePatternReady:
        lda     TitleSceneSnakePixelX
        sta     TitleSceneSpritePixelX
        jsr     DrawTitleSceneShiftedSprite

DrawTitleSceneShot:
        tst     TitleSceneShotActive
        beq     DrawTitleScenePlayer
        lda     #COLOR_SHOT
        sta     DrawCellColor
        ldu     #TitleShotRightShifted
        lda     TitleSceneShotPixelX
        sta     TitleSceneSpritePixelX
        jsr     DrawTitleSceneShiftedSprite

DrawTitleScenePlayer:
        lda     TitleScenePhase
        cmpa    #TITLE_SCENE_PHASE_FIRST_ALERT
        blo     DrawTitleScenePlayerWalk
        cmpa    #TITLE_SCENE_PHASE_SECOND_SHOT
        bhi     DrawTitleScenePlayerWalk
        ldu     #PlayerFireRightShifted
        bra     DrawTitleScenePlayerPatternReady
DrawTitleScenePlayerWalk:
        ldu     #PlayerWalkShifted0
        lda     TitleScenePlayerPixelX
        bita    #$08
        beq     DrawTitleScenePlayerPatternReady
        ldu     #PlayerWalkShifted1
DrawTitleScenePlayerPatternReady:
        lda     #COLOR_PLAYER
        sta     DrawCellColor
        lda     TitleScenePlayerPixelX
        sta     TitleSceneSpritePixelX
        jmp     DrawTitleSceneShiftedSprite

ClearTitleSceneLeftDiamond:
        lda     #TITLE_SCENE_DIAMOND_LEFT_COL
        bra     ClearTitleSceneDiamond
ClearTitleSceneRightDiamond:
        lda     #TITLE_SCENE_DIAMOND_RIGHT_COL
ClearTitleSceneDiamond:
        sta     MapDrawX
        ldu     #CellEmpty
        lda     #COLOR_BACKGROUND
        sta     DrawCellColor
        lda     MapDrawX
        ldb     #TITLE_SCENE_ROW
        jmp     DrawCellPattern

; Remove only the cells touched by the current dynamic title sprites. Diamonds
; stay resident until collected, preventing whole-band erase/redraw flicker.
EraseTitleSceneDynamic:
        lda     TitleScenePlayerPixelX
        jsr     ClearTitleSceneSprite
        tst     TitleSceneSnakeVisible
        beq     EraseTitleSceneShot
        lda     TitleSceneSnakePixelX
        jsr     ClearTitleSceneSprite
EraseTitleSceneShot:
        tst     TitleSceneShotActive
        beq     EraseTitleSceneDynamicDone
        lda     TitleSceneShotPixelX
        jsr     ClearTitleSceneSprite
EraseTitleSceneDynamicDone:
        rts

; Input: A = absolute horizontal pixel coordinate.
ClearTitleSceneSprite:
        sta     TitleSceneSpritePixelX
        lsra
        lsra
        lsra
        sta     MapDrawX
        ldu     #CellEmpty
        lda     #COLOR_BACKGROUND
        sta     DrawCellColor
        lda     MapDrawX
        ldb     #TITLE_SCENE_ROW
        jsr     DrawCellPattern
        lda     TitleSceneSpritePixelX
        anda    #$07
        beq     ClearTitleSceneSpriteDone
        ldu     #CellEmpty
        lda     MapDrawX
        inca
        ldb     #TITLE_SCENE_ROW
        jsr     DrawCellPattern
ClearTitleSceneSpriteDone:
        rts

; Input: U = eight 16-byte horizontal phases, TitleSceneSpritePixelX = absolute
; screen pixel X, DrawCellColor = foreground attribute.
DrawTitleSceneShiftedSprite:
        lda     TitleSceneSpritePixelX
        anda    #$07
        sta     TitleSceneSpritePhase
        ldb     #16
        mul
        leau    d,u

        ldx     #VIDEO_BITMAP_BASE+TITLE_SCENE_ROW*TEXT_CELL_HEIGHT*VIDEO_BYTES_PER_ROW
        ldb     TitleSceneSpritePixelX
        lsrb
        lsrb
        lsrb
        abx

        jsr     SelectBitmapPlane
        pshs    x
        ldy     #8
DrawTitleSceneShiftedBitmapRow:
        pulu    d
        ora     ,x
        orb     1,x
        std     ,x
        leax    VIDEO_BYTES_PER_ROW,x
        leay    -1,y
        bne     DrawTitleSceneShiftedBitmapRow

        puls    x
        jsr     SelectColorPlane
        lda     DrawCellColor
        ldy     #8
DrawTitleSceneShiftedColorRow:
        sta     ,x
        tst     TitleSceneSpritePhase
        beq     DrawTitleSceneShiftedColorLeftOnly
        sta     1,x
DrawTitleSceneShiftedColorLeftOnly:
        leax    VIDEO_BYTES_PER_ROW,x
        leay    -1,y
        bne     DrawTitleSceneShiftedColorRow
        jmp     SelectBitmapPlane

DrawLevelIntroScreen:
        ; CurrentLevel is the legacy zero-based stage index shown as 1-9.
        jsr     ClearScreen
        lda     #COLOR_TITLE
        sta     TextColor
        ldu     #LevelIntroTitleText
        lda     #16
        ldb     #8
        jsr     DrawString
        lda     CurrentLevel
        inca
        adda    #'0'
        sta     HudCharacter
        lda     #22
        ldb     #8
        jsr     CellAddress
        lda     HudCharacter
        jsr     DrawGlyphAtX
        lda     #COLOR_TEXT
        sta     TextColor
        ldu     #LevelIntroGoalText
        lda     #14
        ldb     #12
        jsr     DrawString
        ldb     CurrentLevel
        ldx     #StageRoomCounts
        lda     b,x
        cmpa    #1
        beq     DrawLevelIntroOneRoom
        cmpa    #2
        beq     DrawLevelIntroTwoRooms
        ldu     #LevelIntroThreeRoomsText
        lda     #11
        bra     DrawLevelIntroRoomCount
DrawLevelIntroOneRoom:
        ldu     #LevelIntroOneRoomText
        lda     #12
        bra     DrawLevelIntroRoomCount
DrawLevelIntroTwoRooms:
        ldu     #LevelIntroTwoRoomsText
        lda     #12
DrawLevelIntroRoomCount:
        ldb     #15
        jsr     DrawString
        lda     #COLOR_KEY
        sta     DrawCellColor
        ldu     #CellKey
        lda     #19
        ldb     #18
        jmp     DrawCellPattern

DrawCompleteScreen:
        jsr     ClearScreen
        lda     #COLOR_TITLE
        sta     TextColor
        ldu     #CompleteScreenTitleText
        lda     #13
        ldb     #5
        jsr     DrawString
        jsr     DrawFinalScores
        tst     NewHighScoreFlag
        beq     DrawCompletePrompt
        ldu     #NewHighScoreText
        lda     #13
        ldb     #15
        jsr     DrawString
DrawCompletePrompt:
        ldu     #ReturnTitleText
        lda     #10
        ldb     #19
        jmp     DrawString

DrawGameOverScreen:
        jsr     ClearScreen
        lda     #COLOR_TITLE
        sta     TextColor
        ldu     #GameOverScreenTitleText
        lda     #15
        ldb     #5
        jsr     DrawString
        jsr     DrawFinalScores
        tst     NewHighScoreFlag
        beq     DrawGameOverPrompt
        ldu     #NewHighScoreText
        lda     #13
        ldb     #15
        jsr     DrawString
DrawGameOverPrompt:
        ldu     #ReturnTitleText
        lda     #10
        ldb     #19
        jmp     DrawString

DrawFinalScores:
        lda     #COLOR_TEXT
        sta     TextColor
        ldu     #FinalScoreText
        lda     #15
        ldb     #9
        jsr     DrawString
        lda     #21
        sta     PresentationNumberColumn
        lda     #9
        sta     PresentationNumberRow
        lda     ScoreHundreds
        ldb     ScoreTenThousands
        jsr     DrawPresentationScore

        ldu     #FinalHighScoreText
        lda     #12
        ldb     #12
        jsr     DrawString
        lda     #23
        sta     PresentationNumberColumn
        lda     #12
        sta     PresentationNumberRow
        lda     HighScoreHundreds
        ldb     HighScoreTenThousands
        jmp     DrawPresentationScore

; Input: A = lower two hundreds digits, B = ten-thousands digit. Draw all
; three significant digits; the template supplies the trailing two zeroes.
DrawPresentationScore:
        stb     NumberTenThousands
        jsr     SplitScoreHundreds
        lda     NumberTenThousands
        adda    #'0'
        sta     HudCharacter
        lda     PresentationNumberColumn
        ldb     PresentationNumberRow
        jsr     CellAddress
        lda     HudCharacter
        jsr     DrawGlyphAtX
        inc     PresentationNumberColumn
        lda     NumberTens
        adda    #'0'
        sta     HudCharacter
        lda     PresentationNumberColumn
        ldb     PresentationNumberRow
        jsr     CellAddress
        lda     HudCharacter
        jsr     DrawGlyphAtX
        inc     PresentationNumberColumn
        lda     NumberOnes
        adda    #'0'
        sta     HudCharacter
        lda     PresentationNumberColumn
        ldb     PresentationNumberRow
        jsr     CellAddress
        lda     HudCharacter
        jmp     DrawGlyphAtX

;------------------------------------------------------------------------------
; Gameplay screen, status line, and full-room redraw
;------------------------------------------------------------------------------
DrawGameScreen:
        ; Used on room/stage entry. Death respawn intentionally uses targeted
        ; restoration instead of paying for another complete screen clear.
        jsr     ClearScreen
        lda     #COLOR_TEXT
        sta     TextColor

        ldu     #HudTemplateText
        lda     #HUD_TEXT_COL
        ldb     #HUD_TEXT_ROW
        jsr     DrawString

        jsr     DrawFullLevel
        jsr     DrawAllEnemies
        jsr     DrawAllShots
        jsr     DrawPlayer
        jsr     DrawHudValues
        jsr     DrawHudIndicators
        jsr     DrawInitialStatus
        rts

DrawInitialStatus:
        tst     HasKey
        bne     DrawKeyCarryStatus
        ldu     #InitialStatusText
        jmp     DrawStatus

DrawKeyCarryStatus:
        ldu     #KeyCarryStatusText
        jmp     DrawStatus

DrawNeedKeyStatus:
        ldu     #NeedKeyStatusText
        jmp     DrawStatus

DrawKeyStatus:
        ldu     #KeyStatusText
        jmp     DrawStatus

DrawTreasureStatus:
        ldu     #TreasureStatusText
        jmp     DrawStatus

DrawFlashStatus:
        ldu     #FlashStatusText
        jmp     DrawStatus

DrawWarpStatus:
        ldu     #WarpStatusText
        jmp     DrawStatus

DrawRoomTransitionStatus:
        ldu     #RoomTransitionStatusText
        jmp     DrawStatus

DrawNoFlashStatus:
        ldu     #NoFlashStatusText
        jmp     DrawStatus

DrawDeathStatus:
        ldu     #DeathStatusText
        jmp     DrawStatus

DrawInfiniteLivesOnStatus:
        ldu     #InfiniteLivesOnStatusText
        jmp     DrawStatus

DrawInfiniteLivesOffStatus:
        ldu     #InfiniteLivesOffStatusText
        jmp     DrawStatus

DrawEnemyHitStatus:
        ldu     #EnemyHitStatusText
        jmp     DrawStatus

DrawCompleteStatus:
        ldu     #CompleteStatusText
        jmp     DrawStatus

DrawGameOverStatus:
        ldu     #GameOverStatusText

; Input: U = zero-terminated status text, no more than 38 cells. Center the
; message on the bottom row and remove it after about two seconds.
DrawStatus:
        pshs    u
        jsr     ClearStatusLine
        puls    u
        pshs    u
        clr     StatusTextLength
DrawStatusCountNext:
        lda     ,u+
        beq     DrawStatusCountDone
        inc     StatusTextLength
        bra     DrawStatusCountNext
DrawStatusCountDone:
        puls    u
        lda     #STATUS_MESSAGE_FRAMES
        sta     StatusMessageTimer
        lda     #TEXT_COLUMNS
        suba    StatusTextLength
        lsra
        ldb     #STATUS_TEXT_ROW
        jmp     DrawString

ClearStatusLine:
        clr     MapDrawX
        lda     #STATUS_TEXT_CELLS
        sta     MapCellsRemaining
ClearStatusLineNext:
        ldu     #CellEmpty
        lda     #COLOR_TEXT
        sta     DrawCellColor
        lda     MapDrawX
        adda    #STATUS_TEXT_COL
        ldb     #STATUS_TEXT_ROW
        jsr     DrawCellPattern
        inc     MapDrawX
        dec     MapCellsRemaining
        bne     ClearStatusLineNext
        rts

DrawFullLevel:
        clr     MapDrawY
        lda     #LEVEL_HEIGHT
        sta     MapRowsRemaining
DrawFullLevelRow:
        clr     MapDrawX
        lda     #LEVEL_WIDTH
        sta     MapCellsRemaining
DrawFullLevelCell:
        lda     MapDrawX
        ldb     MapDrawY
        jsr     DrawMapCellAt
        inc     MapDrawX
        dec     MapCellsRemaining
        bne     DrawFullLevelCell
        inc     MapDrawY
        dec     MapRowsRemaining
        bne     DrawFullLevelRow
        rts

;------------------------------------------------------------------------------
; Room transition and static tile renderer
;------------------------------------------------------------------------------
; Replace the outgoing playfield in place with the destination room. Three
; adjacent anti-diagonals are drawn per visual frame, producing a wipe from
; the top-left corner to the bottom-right without moving the HUD or status.
DrawDiagonalRoomTransition:
        clr     RoomTransitionDiagonal
DrawDiagonalRoomTransitionFrame:
        lda     #ROOM_TRANSITION_DIAGONALS_PER_FRAME
        sta     MapCellsRemaining
DrawDiagonalRoomTransitionNext:
        lda     RoomTransitionDiagonal
        cmpa    #ROOM_TRANSITION_DIAGONAL_COUNT
        bhs     DrawDiagonalRoomTransitionWait
        jsr     DrawRoomTransitionDiagonal
        inc     RoomTransitionDiagonal
        dec     MapCellsRemaining
        bne     DrawDiagonalRoomTransitionNext
DrawDiagonalRoomTransitionWait:
        jsr     WaitFrame
        lda     RoomTransitionDiagonal
        cmpa    #ROOM_TRANSITION_DIAGONAL_COUNT
        blo     DrawDiagonalRoomTransitionFrame
        rts

; Draw every cell whose X+Y equals RoomTransitionDiagonal.
DrawRoomTransitionDiagonal:
        lda     RoomTransitionDiagonal
        cmpa    #LEVEL_WIDTH
        blo     DrawRoomTransitionDiagonalStart
        lda     #LEVEL_WIDTH-1
DrawRoomTransitionDiagonalStart:
        sta     RoomTransitionX
        lda     RoomTransitionDiagonal
        suba    RoomTransitionX
        sta     RoomTransitionY
DrawRoomTransitionDiagonalNext:
        lda     RoomTransitionY
        cmpa    #LEVEL_HEIGHT
        bhs     DrawRoomTransitionDiagonalDone
        lda     RoomTransitionX
        ldb     RoomTransitionY
        jsr     DrawMapCellAt
        lda     RoomTransitionX
        beq     DrawRoomTransitionDiagonalDone
        dec     RoomTransitionX
        inc     RoomTransitionY
        bra     DrawRoomTransitionDiagonalNext
DrawRoomTransitionDiagonalDone:
        rts

; Input: A = room X, B = room Y.
DrawMapCellAt:
        sta     MapDrawX
        sta     MapTargetX
        stb     MapDrawY
        stb     MapTargetY
        bra     DrawMapCell

DrawMapCell:
        ; GetLevelTile returns the readable ASCII tile stored in LevelMap.
        jsr     GetLevelTile

        cmpa    #TILE_WALL
        beq     DrawMapWall
        cmpa    #TILE_EXIT
        beq     DrawMapExit
        cmpa    #TILE_KEY
        beq     DrawMapKey
        cmpa    #TILE_TREASURE
        beq     DrawMapTreasure
        cmpa    #TILE_SPAWN
        beq     DrawMapSpawn
        cmpa    #TILE_WARP_DOWN
        beq     DrawMapWarp
        cmpa    #TILE_WARP_UP
        beq     DrawMapWarp
        cmpa    #TILE_ROOM_EXIT
        beq     DrawMapRoomExit

        lda     #COLOR_BACKGROUND
        sta     DrawCellColor
        ldu     #CellEmpty
        bra     DrawMapTile

DrawMapWall:
        lda     CurrentWallColor
        sta     DrawCellColor
        ldu     #CellWallA
        lda     MapDrawX
        eora    MapDrawY
        bita    #$01
        beq     DrawMapTile
        ldu     #CellWallB
        bra     DrawMapTile

DrawMapExit:
        lda     #COLOR_DOOR
        sta     DrawCellColor
        ldu     #CellExit
        bra     DrawMapTile

DrawMapKey:
        lda     #COLOR_KEY
        sta     DrawCellColor
        ldu     #CellKey
        bra     DrawMapTile

DrawMapTreasure:
        lda     #COLOR_TREASURE
        sta     DrawCellColor
        ldu     #CellTreasure
        bra     DrawMapTile

DrawMapSpawn:
        lda     #COLOR_SPAWN
        sta     DrawCellColor
        ldu     #CellSpawn
        bra     DrawMapTile

DrawMapWarp:
        lda     #COLOR_WARP
        sta     DrawCellColor
        ldu     #CellWarp
        bra     DrawMapTile

DrawMapRoomExit:
        lda     #COLOR_ROOM_EXIT
        sta     DrawCellColor
        ldu     #CellRoomExit

DrawMapTile:
        lda     MapTargetX
        adda    #LEVEL_SCREEN_COL
        ldb     MapTargetY
        addb    #LEVEL_SCREEN_ROW
        jmp     DrawCellPattern

;------------------------------------------------------------------------------
; Explorer sprite and footprint restoration
;------------------------------------------------------------------------------
DrawPlayer:
        ; During horizontal motion, the directional firing silhouettes make the
        ; facing direction explicit. Vertical/idle motion uses walking poses.
        lda     PlayerMoveDirection
        cmpa    #PLAYER_DIR_RIGHT
        beq     DrawPlayerMoveRight
        cmpa    #PLAYER_DIR_LEFT
        beq     DrawPlayerMoveLeft
        ldu     #PlayerWalkShifted0
        tst     PlayerAnimationFrame
        beq     DrawPlayerPattern
        ldu     #PlayerWalkShifted1
        bra     DrawPlayerPattern
DrawPlayerMoveRight:
        ldu     #PlayerFireRightShifted
        bra     DrawPlayerPattern
DrawPlayerMoveLeft:
        ldu     #PlayerFireLeftShifted
        bra     DrawPlayerPattern

DrawPlayerFire:
        ldu     #PlayerFireRightShifted
        tst     PlayerFacing
        bpl     DrawPlayerPattern
        ldu     #PlayerFireLeftShifted

; Input: U = eight 16-byte horizontal phases. Each row contains the left and
; right bitmap bytes for an 8-pixel sprite shifted across a byte boundary.
DrawPlayerPattern:
        lda     PlayerPixelX
        anda    #$07
        sta     PlayerHorizontalPhase
        ldb     #16
        mul
        leau    d,u

        lda     PlayerPixelX
        lsra
        lsra
        lsra
        adda    #LEVEL_SCREEN_COL
        sta     PlayerDrawColumn
        ldb     PlayerPixelY
        addb    #LEVEL_SCREEN_ROW*TEXT_CELL_HEIGHT
        lda     #VIDEO_BYTES_PER_ROW
        mul
        addb    PlayerDrawColumn
        adca    #0
        tfr     d,x

        jsr     SelectBitmapPlane
        pshs    x
        ldy     #8
DrawPlayerBitmapRow:
        pulu    d
        ora     ,x
        orb     1,x
        std     ,x
        leax    VIDEO_BYTES_PER_ROW,x
        leay    -1,y
        bne     DrawPlayerBitmapRow

        puls    x
        jsr     SelectColorPlane
        lda     #COLOR_PLAYER
        ldy     #8
DrawPlayerColorRow:
        sta     ,x
        tst     PlayerHorizontalPhase
        beq     DrawPlayerColorLeftOnly
        sta     1,x
DrawPlayerColorLeftOnly:
        leax    VIDEO_BYTES_PER_ROW,x
        leay    -1,y
        bne     DrawPlayerColorRow
        jmp     SelectBitmapPlane

; Restore every map cell touched by the old arbitrary-pixel 8x8 footprint.
; A diagonal footprint is not generated by the movement rules, but handling
; the full 2x2 case keeps the renderer correct for future effects.
EnsurePlayerFootprintRestored:
        tst     PlayerRedrawPending
        bne     EnsurePlayerFootprintDone
        jmp     RestorePlayerFootprint
EnsurePlayerFootprintDone:
        rts

RestorePlayerFootprint:
        lda     #1
        sta     PlayerRedrawPending
        lda     PlayerPixelX
        lsra
        lsra
        lsra
        sta     PlayerFootprintLeft
        sta     PlayerFootprintRight
        lda     PlayerPixelX
        anda    #$07
        beq     RestorePlayerHorizontalReady
        inc     PlayerFootprintRight
RestorePlayerHorizontalReady:
        lda     PlayerPixelY
        lsra
        lsra
        lsra
        sta     PlayerFootprintTop
        sta     PlayerFootprintBottom
        lda     PlayerPixelY
        anda    #$07
        beq     RestorePlayerVerticalReady
        inc     PlayerFootprintBottom
RestorePlayerVerticalReady:
        lda     PlayerFootprintLeft
        ldb     PlayerFootprintTop
        jsr     DrawMapCellAt

        lda     PlayerFootprintRight
        cmpa    PlayerFootprintLeft
        beq     RestorePlayerBottom
        ldb     PlayerFootprintTop
        jsr     DrawMapCellAt

RestorePlayerBottom:
        lda     PlayerFootprintBottom
        cmpa    PlayerFootprintTop
        beq     RestorePlayerFootprintDone
        tfr     a,b
        lda     PlayerFootprintLeft
        jsr     DrawMapCellAt

        lda     PlayerFootprintRight
        cmpa    PlayerFootprintLeft
        beq     RestorePlayerFootprintDone
        ldb     PlayerFootprintBottom
        jsr     DrawMapCellAt
RestorePlayerFootprintDone:
        rts

;------------------------------------------------------------------------------
; Guardian sprites, hit/death effects, and footprint restoration
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

RestoreCurrentEnemyFootprint:
        ; A horizontally shifted guardian can touch two byte columns; the
        ; footprint's right cell is therefore advanced twice from its left edge.
        ldb     CurrentActorIndex
        ldx     #EnemyPixelX
        lda     b,x
        lsra
        lsra
        lsra
        sta     PlayerFootprintLeft
        sta     PlayerFootprintRight
        ldb     CurrentActorIndex
        ldx     #EnemyPixelX
        lda     b,x
        anda    #$07
        beq     RestoreCurrentEnemyHorizontalReady
        inc     PlayerFootprintRight
RestoreCurrentEnemyHorizontalReady:
        ldb     CurrentActorIndex
        ldx     #EnemyPixelY
        lda     b,x
        lsra
        lsra
        lsra
        sta     PlayerFootprintTop
        sta     PlayerFootprintBottom
        ldb     CurrentActorIndex
        ldx     #EnemyPixelY
        lda     b,x
        anda    #$07
        beq     RestoreCurrentEnemyVerticalReady
        inc     PlayerFootprintBottom
RestoreCurrentEnemyVerticalReady:
        lda     PlayerFootprintLeft
        ldb     PlayerFootprintTop
        jsr     DrawMapCellAt

        lda     PlayerFootprintRight
        cmpa    PlayerFootprintLeft
        beq     RestoreCurrentEnemyBottom
        ldb     PlayerFootprintTop
        jsr     DrawMapCellAt

RestoreCurrentEnemyBottom:
        lda     PlayerFootprintBottom
        cmpa    PlayerFootprintTop
        beq     RestoreCurrentEnemyFootprintDone
        tfr     a,b
        lda     PlayerFootprintLeft
        jsr     DrawMapCellAt

        lda     PlayerFootprintRight
        cmpa    PlayerFootprintLeft
        beq     RestoreCurrentEnemyFootprintDone
        ldb     PlayerFootprintBottom
        jsr     DrawMapCellAt
RestoreCurrentEnemyFootprintDone:
        rts

; Remove every guardian and any pending hit flash without touching the maze.
; This is used by life respawn while the action is frozen.
RestoreAllEnemyVisuals:
        clr     CurrentActorIndex
RestoreAllEnemyVisualsNext:
        ldb     CurrentActorIndex
        cmpb    #ENEMY_COUNT
        beq     RestoreAllEnemyVisualsDone
        ldx     #EnemyActive
        tst     b,x
        beq     RestoreAllEnemyVisualsEffect
        jsr     RestoreCurrentEnemyFootprint
RestoreAllEnemyVisualsEffect:
        ldb     CurrentActorIndex
        ldx     #EnemyHitEffectTimer
        tst     b,x
        beq     RestoreAllEnemyVisualsAdvance
        ldx     #EnemyHitEffectX
        lda     b,x
        pshs    a
        ldx     #EnemyHitEffectY
        lda     b,x
        tfr     a,b
        puls    a
        jsr     DrawMapCellAt
RestoreAllEnemyVisualsAdvance:
        inc     CurrentActorIndex
        bra     RestoreAllEnemyVisualsNext
RestoreAllEnemyVisualsDone:
        rts

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

RestorePlayerDeathEffect:
        lda     PlayerDeathX
        ldb     PlayerDeathY
        jmp     DrawMapCellAt

;------------------------------------------------------------------------------
; Cell-aligned projectile renderer
;------------------------------------------------------------------------------
DrawAllShots:
        clr     CurrentActorIndex
DrawAllShotsNext:
        ldb     CurrentActorIndex
        cmpb    #SHOT_COUNT
        beq     DrawAllShotsDone
        ldx     #ShotActive
        lda     b,x
        beq     DrawAllShotsSkip
        jsr     DrawCurrentShot
DrawAllShotsSkip:
        inc     CurrentActorIndex
        bra     DrawAllShotsNext
DrawAllShotsDone:
        rts

DrawCurrentShot:
        ldu     #CellShotRightFrame0
        ldb     CurrentActorIndex
        ldx     #ShotDirection
        lda     b,x
        bmi     DrawCurrentShotLeft
        lda     ShotAnimationFrame
        eora    CurrentActorIndex
        bita    #$01
        beq     DrawCurrentShotPatternReady
        ldu     #CellShotRightFrame1
        bra     DrawCurrentShotPatternReady
DrawCurrentShotLeft:
        ldu     #CellShotLeftFrame0
        lda     ShotAnimationFrame
        eora    CurrentActorIndex
        bita    #$01
        beq     DrawCurrentShotPatternReady
        ldu     #CellShotLeftFrame1
DrawCurrentShotPatternReady:
        ldb     CurrentActorIndex
        ldx     #ShotX
        lda     b,x
        adda    #LEVEL_SCREEN_COL
        pshs    a
        ldx     #ShotY
        lda     b,x
        adda    #LEVEL_SCREEN_ROW
        tfr     a,b
        puls    a
        ldx     #DrawCellColor
        pshs    a
        lda     #COLOR_SHOT
        sta     ,x
        puls    a
        jmp     DrawCellPattern

; Restore all projectile footprints before movement and frame changes.
RestoreAllShotCells:
        clr     CurrentActorIndex
RestoreAllShotCellsNext:
        ldb     CurrentActorIndex
        cmpb    #SHOT_COUNT
        beq     RestoreAllShotCellsDone
        ldx     #ShotActive
        lda     b,x
        beq     RestoreAllShotCellsSkip
        ldx     #ShotX
        lda     b,x
        pshs    a
        ldx     #ShotY
        lda     b,x
        tfr     a,b
        puls    a
        jsr     DrawMapCellAt
RestoreAllShotCellsSkip:
        inc     CurrentActorIndex
        bra     RestoreAllShotCellsNext
RestoreAllShotCellsDone:
        rts

;------------------------------------------------------------------------------
; HUD numbers, lives, infinite-life label, and flash indicator
;------------------------------------------------------------------------------
DrawHudValues:
        ; The live HUD high-score field displays max(current run, stored first
        ; place) without mutating the persistent table mid-run.
        lda     ScoreTenThousands
        ldb     #HUD_TEXT_COL+6
        jsr     DrawHudDigit
        lda     ScoreHundreds
        jsr     SplitScoreHundreds

        lda     NumberTens
        ldb     #HUD_TEXT_COL+7
        jsr     DrawHudDigit
        lda     NumberOnes
        ldb     #HUD_TEXT_COL+8
        jsr     DrawHudDigit

        lda     HighScoreTenThousands
        cmpa    ScoreTenThousands
        bhi     DrawHudUseStoredHighScore
        blo     DrawHudUseCurrentScore
        lda     HighScoreHundreds
        cmpa    ScoreHundreds
        bhs     DrawHudUseStoredHighScore
DrawHudUseCurrentScore:
        lda     ScoreTenThousands
        sta     NumberTenThousands
        lda     ScoreHundreds
        bra     DrawHudHighScoreReady
DrawHudUseStoredHighScore:
        lda     HighScoreTenThousands
        sta     NumberTenThousands
        lda     HighScoreHundreds
DrawHudHighScoreReady:
        jsr     SplitScoreHundreds
        lda     NumberTenThousands
        ldb     #HUD_TEXT_COL+15
        jsr     DrawHudDigit
        lda     NumberTens
        ldb     #HUD_TEXT_COL+16
        jsr     DrawHudDigit
        lda     NumberOnes
        ldb     #HUD_TEXT_COL+17
        jmp     DrawHudDigit

; Draw one centered explorer icon per remaining life with no gaps. When the
; flash is available, place its red lightning icon one spaced cell to the right.
; Clearing the complete span removes stale icons.
DrawHudIndicators:
        clr     MapDrawX
        lda     #HUD_INDICATOR_CLEAR_CELLS
        sta     MapCellsRemaining
DrawHudIndicatorsClearNext:
        ldu     #CellEmpty
        lda     #COLOR_BACKGROUND
        sta     DrawCellColor
        lda     MapDrawX
        adda    #LIVES_CLEAR_START_COL
        ldb     #LIVES_TEXT_ROW
        jsr     DrawCellPattern
        inc     MapDrawX
        dec     MapCellsRemaining
        bne     DrawHudIndicatorsClearNext

        tst     InfiniteLives
        beq     DrawHudIndicatorsFinite
        ldu     #InfiniteLivesHudText
        lda     #LIVES_CLEAR_START_COL
        ldb     #LIVES_TEXT_ROW
        jsr     DrawString
        lda     #LIVES_CLEAR_START_COL+4
        sta     HudColumn
        bra     DrawHudIndicatorsFlash

DrawHudIndicatorsFinite:
        lda     PlayerLives
        beq     DrawHudIndicatorsDone
        sta     MapCellsRemaining
        sta     HudColumn
        lda     #TEXT_COLUMNS
        suba    HudColumn
        lsra
        sta     HudColumn
DrawHudIndicatorsLifeNext:
        ldu     #CellPlayerLife
        lda     #COLOR_PLAYER
        sta     DrawCellColor
        lda     HudColumn
        ldb     #LIVES_TEXT_ROW
        jsr     DrawCellPattern
        inc     HudColumn
        dec     MapCellsRemaining
        bne     DrawHudIndicatorsLifeNext

        inc     HudColumn
DrawHudIndicatorsFlash:
        tst     FlashAvailable
        beq     DrawHudIndicatorsDone
        ldu     #CellFlashIndicator
        lda     #COLOR_FLASH_INDICATOR
        sta     DrawCellColor
        lda     HudColumn
        ldb     #LIVES_TEXT_ROW
        jmp     DrawCellPattern
DrawHudIndicatorsDone:
        rts

; Input: A = score in hundreds. Output: NumberTens/NumberOnes.
SplitScoreHundreds:
        clrb
SplitScoreHundredsTens:
        cmpa    #10
        blo     SplitScoreHundredsReady
        suba    #10
        incb
        bra     SplitScoreHundredsTens
SplitScoreHundredsReady:
        sta     NumberOnes
        stb     NumberTens
        rts

; Input: A = 0-9, B = screen column.
DrawHudDigit:
        adda    #'0'

; Input: A = ASCII, B = screen column.
DrawHudCharacter:
        sta     HudCharacter
        stb     HudColumn
        ldu     #CellEmpty
        lda     #COLOR_TEXT
        sta     DrawCellColor
        lda     HudColumn
        ldb     #HUD_TEXT_ROW
        jsr     DrawCellPattern
        lda     HudColumn
        ldb     #HUD_TEXT_ROW
        jsr     CellAddress
        lda     HudCharacter
        jmp     DrawGlyphAtX

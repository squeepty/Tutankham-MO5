;==============================================================================
; Title, attract, stage, and terminal presentation
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
; Register contract for exported entries:
;   DrawTitleScreen/DrawTitleScene/DrawLevelIntroScreen/DrawCompleteScreen/
;     DrawGameOverScreen: Inputs none; outputs the corresponding full display.
;   DrawTitleCheatUnlocked/DrawTitleSceneSnake/EraseTitleSceneDynamic/
;     ClearTitleSceneLeftDiamond/ClearTitleSceneRightDiamond: Inputs none;
;     outputs the named title-scene update.
;   ClearTitleSceneSprite: Input A = absolute horizontal pixel coordinate.
;   DrawTitleSceneShiftedSprite: Input U = eight 16-byte horizontal phases and
;     TitleSceneSpritePixelX = absolute X.
;   DrawPresentationScore: Inputs A = lower score hundreds and B = ten-thousands.
;   Clobbers: A, B, X, Y, U, CC; S balanced; DP unchanged; returns with the
;     bitmap display plane selected.
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
        lda     #COLOR_DEV_VERSION
        sta     DrawCellColor
        ldu     #CellTitleVersionV1
        lda     #TITLE_VERSION_SPRITE_COL
        ldb     #TITLE_VERSION_SPRITE_ROW
        jsr     DrawCellPattern
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
        ; CurrentLevel selects the chamber name in campaign order.
        jsr     ClearScreen
        lda     #COLOR_TITLE
        sta     TextColor
        ldx     #ChamberNamePointers
        ldb     CurrentLevel
        lslb
        ldu     b,x
        ldb     #8
        jsr     DrawCenteredIntroString
        lda     #COLOR_TEXT
        sta     TextColor
        ldu     #LevelIntroGoalText
        ldb     #12
        jsr     DrawCenteredIntroString
        ldb     CurrentLevel
        ldx     #StageRoomCounts
        lda     b,x
        cmpa    #1
        beq     DrawLevelIntroOneRoom
        cmpa    #2
        beq     DrawLevelIntroTwoRooms
        ldu     #LevelIntroThreeRoomsText
        bra     DrawLevelIntroRoomCount
DrawLevelIntroOneRoom:
        ldu     #LevelIntroOneRoomText
        bra     DrawLevelIntroRoomCount
DrawLevelIntroTwoRooms:
        ldu     #LevelIntroTwoRoomsText
DrawLevelIntroRoomCount:
        ldb     #15
        jsr     DrawCenteredIntroString
        lda     #COLOR_KEY
        sta     DrawCellColor
        ldu     #CellKey
        lda     #(TEXT_COLUMNS-1+1)/2
        ldb     #18
        jmp     DrawCellPattern

; Input: U = zero-terminated text, B = row. Center on the text grid,
; rounding half-cell positions up consistently for every intro line.
DrawCenteredIntroString:
        pshs    b
        tfr     u,x
        lda     #TEXT_COLUMNS+1
DrawCenteredIntroStringLength:
        ldb     ,x+
        beq     DrawCenteredIntroStringReady
        deca
        bra     DrawCenteredIntroStringLength
DrawCenteredIntroStringReady:
        lsra
        puls    b
        jmp     DrawString

DrawCompleteScreen:
        jsr     ClearScreen
        lda     #COLOR_TITLE
        sta     TextColor
        ldu     #CompleteScreenTitleText
        lda     #(TEXT_COLUMNS-13+1)/2
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
        lda     #(TEXT_COLUMNS-19+1)/2-1
        ldb     #19
        jmp     DrawString

DrawGameOverScreen:
        ; Center each full line on the 40-column grid, rounding half cells up.
        jsr     ClearScreen
        lda     #COLOR_TITLE
        sta     TextColor
        ldu     #GameOverScreenTitleText
        lda     #(TEXT_COLUMNS-9+1)/2
        ldb     #5
        jsr     DrawString
        jsr     DrawFinalScores
        tst     NewHighScoreFlag
        beq     DrawGameOverPrompt
        ldu     #NewHighScoreText
        lda     #(TEXT_COLUMNS-14+1)/2
        ldb     #15
        jsr     DrawString
DrawGameOverPrompt:
        ldu     #ReturnTitleText
        lda     #(TEXT_COLUMNS-19+1)/2-1
        ldb     #19
        jmp     DrawString

DrawFinalScores:
        lda     #COLOR_TEXT
        sta     TextColor
        ldu     #FinalScoreText
        lda     #(TEXT_COLUMNS-11+1)/2
        ldb     #9
        jsr     DrawString
        lda     #(TEXT_COLUMNS-11+1)/2+6
        sta     PresentationNumberColumn
        lda     #9
        sta     PresentationNumberRow
        lda     ScoreHundreds
        ldb     ScoreTenThousands
        jsr     DrawPresentationScore

        ldu     #FinalHighScoreText
        lda     #(TEXT_COLUMNS-16+1)/2
        ldb     #12
        jsr     DrawString
        lda     #(TEXT_COLUMNS-16+1)/2+11
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

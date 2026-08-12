;==============================================================================
; HUD values, lives, cheat label, and flash indicator
;
; Register contract for exported entries:
;   DrawHudValues/DrawHudIndicators: Inputs none; output updated HUD display.
;   SplitScoreHundreds: Input A = 0-99; outputs NumberTens/NumberOnes.
;   DrawHudDigit: Inputs A = digit 0-9, B = screen column.
;   DrawHudCharacter: Inputs A = ASCII, B = screen column.
;   Clobbers: A, B, X, Y, U, CC; S balanced; DP unchanged; returns on the
;     bitmap display plane.
;==============================================================================

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

; Draw one centered explorer icon per reserve life with no gaps. PlayerLives
; includes the active explorer, so it is excluded from the HUD count. When the
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
        deca
        beq     DrawHudIndicatorsFlashOnly
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
        bra     DrawHudIndicatorsFlash
DrawHudIndicatorsFlashOnly:
        lda     #TEXT_COLUMNS/2
        sta     HudColumn
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

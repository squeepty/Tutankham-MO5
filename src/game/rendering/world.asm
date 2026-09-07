;==============================================================================
; Gameplay screen, status messages, room transitions, and static map cells
;
; Register contract for exported entries:
;   DrawGameScreen/status helpers/DrawFullLevel/DrawDiagonalRoomTransition:
;     Inputs none; outputs display and renderer scratch state.
;   DrawStatus: Input U = zero-terminated text, at most 38 cells.
;   DrawMapCellAt: Inputs A = room X, B = room Y; output redrawn static cell.
;   Clobbers: A, B, X, Y, U, CC; S balanced; DP unchanged; returns with the
;     bitmap display plane selected.
;==============================================================================

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

DrawTreasureStreakTwoStatus:
        ldu     #TreasureStreakTwoStatusText
        jmp     DrawStatus

DrawTreasureStreakThreeStatus:
        ldu     #TreasureStreakThreeStatusText
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

DrawGuardianHitsDisabledStatus:
        ldu     #GuardianHitsDisabledStatusText
        jmp     DrawStatus

DrawEnemyHitStatus:
        ldu     #EnemyHitStatusText
        jmp     DrawStatus

DrawCompleteStatus:
        ldu     #CompleteStatusText
        jmp     DrawStatus

DrawGameOverStatus:
        ldu     #GameOverStatusText

; Center the U-addressed message on the bottom row and expire it after about
; two seconds.
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

DrawMapCellAt:
        sta     MapDrawX
        sta     MapTargetX
        stb     MapDrawY
        stb     MapTargetY
        bra     DrawMapCell

DrawMapCell:
        jsr     TryDrawExitDoor
        bcs     DrawMapCellDone
        lda     MapDrawX
        ldb     MapDrawY
        ; GetLevelTile returns the readable ASCII tile stored in LevelMap.
        jsr     GetLevelTile

        cmpa    #TILE_WALL
        lbeq    DrawMapWall
        cmpa    #TILE_EXIT
        lbeq    DrawMapExit
        cmpa    #TILE_KEY
        lbeq    DrawMapKey
        cmpa    #TILE_TREASURE
        lbeq    DrawMapTreasure
        cmpa    #TILE_SPAWN
        lbeq    DrawMapSpawn
        cmpa    #TILE_WARP_DOWN
        lbeq    DrawMapWarp
        cmpa    #TILE_WARP_UP
        lbeq    DrawMapWarp
        cmpa    #TILE_ROOM_EXIT
        lbeq    DrawMapRoomExit

        lda     #COLOR_BACKGROUND
        sta     DrawCellColor
        ldu     #CellEmpty
        lbra    DrawMapTile

DrawMapCellDone:
        rts

DrawMapWall:
        lda     CurrentWallColor
        sta     DrawCellColor
        ldb     CurrentStageRoomIndex
        lslb
        ldx     #RoomWallDecorationPointers
        ldx     b,x
        ; Each room table has ten (X, Y, symbol) triples. Symbol artwork is
        ; sixteen bytes: eight scanlines for each horizontal half.
        ldb     #10
DrawMapWallDecorationNext:
        lda     MapDrawY
        cmpa    1,x
        bne     DrawMapWallDecorationSkip
        lda     MapDrawX
        suba    ,x
        cmpa    #2
        bhs     DrawMapWallDecorationSkip
        ; Select this half, and require the neighboring half to remain a wall.
        pshs    a
        lsla
        lsla
        lsla
        pshs    a
        ldb     2,x
        lslb
        lslb
        lslb
        lslb
        addb    ,s+
        ldu     #WallSymbolPatterns
        leau    b,u
        puls    a
        tsta
        bne     DrawMapWallCheckLeft
        lda     MapDrawX
        inca
        bra     DrawMapWallCheckNeighbor
DrawMapWallCheckLeft:
        lda     MapDrawX
        deca
DrawMapWallCheckNeighbor:
        ldb     MapDrawY
        jsr     GetLevelTile
        cmpa    #TILE_WALL
        beq     DrawMapTile
        bra     DrawMapRegularWall
DrawMapWallDecorationSkip:
        leax    3,x
        decb
        bne     DrawMapWallDecorationNext
DrawMapRegularWall:
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

; Draw the cell immediately one or two columns right of a paired D marker.
; Sampling each cell independently preserves clipping and diagonal redraws.
; Returns carry set when drawn. Map targets remain unchanged.
; GetLevelTile leaves X at the marker so +/- LEVEL_WIDTH checks its mate.
; Quadrants are stored top-left, top-right, bottom-left, bottom-right.
TryDrawExitDoor:
        lda     MapDrawX
        beq     TryDrawExitDoorNone
        deca
        ldb     MapDrawY
        jsr     GetLevelTile
        cmpa    #TILE_EXIT
        beq     TryDrawExitDoorLeft
        lda     MapDrawX
        cmpa    #2
        blo     TryDrawExitDoorNone
        suba    #2
        ldb     MapDrawY
        jsr     GetLevelTile
        cmpa    #TILE_EXIT
        bne     TryDrawExitDoorNone
        lda     #8
        bra     TryDrawExitDoorPair
TryDrawExitDoorLeft:
        clra
TryDrawExitDoorPair:
        pshs    a
        ; Logical terrain rows start on odd physical rows (1,3,...).
        ldb     MapDrawY
        bitb    #1
        beq     TryDrawExitDoorBottom
        cmpb    #LEVEL_HEIGHT-1
        bhs     TryDrawExitDoorUnpaired
        lda     LEVEL_WIDTH,x
        bra     TryDrawExitDoorCheckPair
TryDrawExitDoorBottom:
        tstb
        beq     TryDrawExitDoorUnpaired
        lda     -LEVEL_WIDTH,x
TryDrawExitDoorCheckPair:
        cmpa    #TILE_EXIT
        bne     TryDrawExitDoorUnpaired
        puls    a
        bitb    #1
        bne     TryDrawExitDoorPattern
        adda    #16
TryDrawExitDoorPattern:
        ldu     #CellDoorYellow
        ldb     #COLOR_DOOR_YELLOW
        pshs    a
        lda     CurrentLevel
        bita    #1
        beq     TryDrawExitDoorColor
        ldu     #CellDoorRed
        ldb     #COLOR_DOOR_RED
TryDrawExitDoorColor:
        stb     DrawCellColor
        puls    a
        leau    a,u
        jsr     DrawMapTile
        orcc    #1
        rts
TryDrawExitDoorUnpaired:
        leas    1,s
TryDrawExitDoorNone:
        andcc   #$FE
        rts

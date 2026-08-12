;==============================================================================
; Active-map addressing
;
; Register contracts:
;   GetLevelCellAddress: Inputs A = room X, B = room Y; output X = LevelMap
;     cell address; clobbers A, B, X, QueryX, CC.
;   GetLevelTile: Inputs A = room X, B = room Y; output A = ASCII tile and
;     X = LevelMap cell address; clobbers A, B, X, QueryX, CC.
;   Both preserve Y, U, S, and DP.
;==============================================================================

GetLevelCellAddress:
        sta     QueryX
        lda     #LEVEL_WIDTH
        mul
        addb    QueryX
        adca    #0
        ldx     #LevelMap
        leax    d,x
        rts

GetLevelTile:
        jsr     GetLevelCellAddress
        lda     ,x
        rts

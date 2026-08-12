;==============================================================================
; MO5 video primitives
;
; The bitmap and color planes share $0000-$1F3F. Bit 0 of $A7C0 selects the
; visible plane. Public drawing routines return with the bitmap plane selected.
;
; Coordinate conventions:
;   - text/cell X is a byte column (0-39);
;   - text/cell Y is an 8-scanline row (0-24);
;   - one bitmap byte and one color byte describe each 8-pixel scanline cell;
;   - sprite routines in game/rendering.asm handle arbitrary pixel positions.
;
; Callers may treat X/Y/D/U as scratch unless a routine documents otherwise.
; CellAddress patches an immediate operand in this RAM-resident program, which
; is why code must remain writable after loading.
;==============================================================================

SelectBitmapPlane:
        lda     VIDEO_BANK_SELECT
        ora     #$01
        sta     VIDEO_BANK_SELECT
        rts

SelectColorPlane:
        lda     VIDEO_BANK_SELECT
        anda    #$FE
        sta     VIDEO_BANK_SELECT
        rts

ClearScreen:
        ; Clear both complete 8,000-byte planes. Color bytes use the background
        ; attribute even when the corresponding bitmap byte is already zero.
        jsr     SelectBitmapPlane
        ldx     #VIDEO_BITMAP_BASE
        ldd     #$0000
        ldy     #VIDEO_BITMAP_WORDS
ClearBitmapLoop:
        std     ,x++
        leay    -1,y
        bne     ClearBitmapLoop

        jsr     SelectColorPlane
        ldx     #VIDEO_COLOR_BASE
        ldb     #COLOR_BACKGROUND
        ldy     #VIDEO_COLOR_BYTES
ClearColorLoop:
        stb     ,x+
        leay    -1,y
        bne     ClearColorLoop

        jsr     SelectBitmapPlane
        rts

; Input: A = text column, B = text row.
; Output: X = byte address in the selected video plane.
CellAddress:
        ; row * 8 scanlines * 40 bytes = row * 320, then add column. Saving the
        ; column in the operand below avoids another writable scratch byte.
        sta     CellAddressColumn
        lda     #4*VIDEO_BYTES_PER_ROW
        mul
        lslb
        rola
        addd    #VIDEO_BITMAP_BASE
CellAddressColumn equ *-1
        tfr     d,x
        rts

; Input: U = 8 bitmap bytes, A/B = cell column/row, DrawCellColor = attribute.
; Output: U advanced by 8; bitmap plane selected.
DrawCellPattern:
        jsr     CellAddress
        jsr     SelectBitmapPlane

        leax    120,x
        pulu    d
        sta     -120,x
        stb     -80,x
        pulu    d
        sta     -40,x
        stb     ,x
        pulu    d
        sta     40,x
        stb     80,x
        pulu    d
        sta     120,x
        stb     160,x

        dec     VIDEO_BANK_SELECT
        lda     DrawCellColor
        sta     -120,x
        sta     -80,x
        sta     -40,x
        sta     ,x
        sta     40,x
        sta     80,x
        sta     120,x
        sta     160,x
        inc     VIDEO_BANK_SELECT
        rts

; Input: U = zero-terminated ASCII, A/B = starting cell column/row.
; Supported glyphs are space, dash, colon, period, 0-9, and A-Z. Other bytes
; draw '?'.
DrawString:
        jsr     CellAddress
DrawStringNext:
        lda     ,u+
        beq     DrawStringDone
        pshs    x,u
        jsr     DrawGlyphAtX
        puls    x,u
        leax    1,x
        bra     DrawStringNext
DrawStringDone:
        rts

; Input: A = ASCII, X = top-left destination byte.
; TextColor is written to the eight matching color-plane bytes.
DrawGlyphAtX:
        cmpa    #' '
        beq     DrawGlyphSpace
        cmpa    #'-'
        beq     DrawGlyphDash
        cmpa    #':'
        beq     DrawGlyphColon
        cmpa    #'.'
        beq     DrawGlyphPeriod

        cmpa    #'0'
        blo     DrawGlyphFallback
        cmpa    #'9'
        bls     DrawGlyphDigit

        cmpa    #'A'
        blo     DrawGlyphFallback
        cmpa    #'Z'
        bhi     DrawGlyphFallback
        suba    #'A'
        ldb     #8
        mul
        ldu     #GlyphLetters
        leau    d,u
        bra     DrawGlyphCopy

DrawGlyphDigit:
        suba    #'0'
        ldb     #8
        mul
        ldu     #GlyphDigits
        leau    d,u
        bra     DrawGlyphCopy

DrawGlyphSpace:
        ldu     #GlyphSpace
        bra     DrawGlyphCopy
DrawGlyphDash:
        ldu     #GlyphDash
        bra     DrawGlyphCopy
DrawGlyphColon:
        ldu     #GlyphColon
        bra     DrawGlyphCopy
DrawGlyphPeriod:
        ldu     #GlyphPeriod
        bra     DrawGlyphCopy
DrawGlyphFallback:
        ldu     #GlyphFallback

DrawGlyphCopy:
        pshs    x
        ldb     #8
DrawGlyphCopyRow:
        lda     ,u+
        sta     ,x
        leax    VIDEO_BYTES_PER_ROW,x
        decb
        bne     DrawGlyphCopyRow

        puls    x
        pshs    x
        jsr     SelectColorPlane
        lda     TextColor
        ldb     #8
DrawGlyphColorRow:
        sta     ,x
        leax    VIDEO_BYTES_PER_ROW,x
        decb
        bne     DrawGlyphColorRow
        jsr     SelectBitmapPlane
        puls    x
        rts

; Writable drawing parameters shared by the higher-level renderer.
DrawCellColor:
        fcb     COLOR_TEXT
TextColor:
        fcb     COLOR_TEXT

GlyphSpace:
        fcb     $00,$00,$00,$00,$00,$00,$00,$00
GlyphDash:
        fcb     $00,$00,$00,$7E,$00,$00,$00,$00
GlyphColon:
        fcb     $00,$18,$18,$00,$00,$18,$18,$00
GlyphPeriod:
        fcb     $00,$00,$00,$00,$00,$00,$18,$18
GlyphFallback:
        fcb     $3C,$66,$06,$0C,$18,$00,$18,$00

; Digits 0-9, eight bytes per glyph.
GlyphDigits:
        fcb     $3C,$66,$6E,$76,$66,$66,$3C,$00
        fcb     $18,$38,$18,$18,$18,$18,$7E,$00
        fcb     $3C,$66,$06,$0C,$30,$60,$7E,$00
        fcb     $3C,$66,$06,$1C,$06,$66,$3C,$00
        fcb     $0C,$1C,$3C,$6C,$7E,$0C,$0C,$00
        fcb     $7E,$60,$7C,$06,$06,$66,$3C,$00
        fcb     $3C,$66,$60,$7C,$66,$66,$3C,$00
        fcb     $7E,$06,$0C,$18,$30,$30,$30,$00
        fcb     $3C,$66,$66,$3C,$66,$66,$3C,$00
        fcb     $3C,$66,$66,$3E,$06,$66,$3C,$00

; Letters A-Z, eight bytes per glyph.
GlyphLetters:
        fcb     $18,$3C,$66,$66,$7E,$66,$66,$00
        fcb     $7C,$66,$66,$7C,$66,$66,$7C,$00
        fcb     $3C,$66,$60,$60,$60,$66,$3C,$00
        fcb     $78,$6C,$66,$66,$66,$6C,$78,$00
        fcb     $7E,$60,$60,$7C,$60,$60,$7E,$00
        fcb     $7E,$60,$60,$7C,$60,$60,$60,$00
        fcb     $3C,$66,$60,$6E,$66,$66,$3C,$00
        fcb     $66,$66,$66,$7E,$66,$66,$66,$00
        fcb     $7E,$18,$18,$18,$18,$18,$7E,$00
        fcb     $1E,$0C,$0C,$0C,$6C,$6C,$38,$00
        fcb     $66,$6C,$78,$70,$78,$6C,$66,$00
        fcb     $60,$60,$60,$60,$60,$60,$7E,$00
        fcb     $63,$77,$7F,$6B,$63,$63,$63,$00
        fcb     $66,$76,$7E,$7E,$6E,$66,$66,$00
        fcb     $3C,$66,$66,$66,$66,$66,$3C,$00
        fcb     $7C,$66,$66,$7C,$60,$60,$60,$00
        fcb     $3C,$66,$66,$66,$6E,$3C,$06,$00
        fcb     $7C,$66,$66,$7C,$78,$6C,$66,$00
        fcb     $3C,$66,$60,$3C,$06,$66,$3C,$00
        fcb     $7E,$18,$18,$18,$18,$18,$18,$00
        fcb     $66,$66,$66,$66,$66,$66,$3C,$00
        fcb     $66,$66,$66,$66,$66,$3C,$18,$00
        fcb     $63,$63,$63,$6B,$7F,$77,$63,$00
        fcb     $66,$66,$3C,$18,$3C,$66,$66,$00
        fcb     $66,$66,$3C,$18,$18,$18,$18,$00
        fcb     $7E,$06,$0C,$18,$30,$60,$7E,$00

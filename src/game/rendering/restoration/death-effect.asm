;==============================================================================
; Explorer death-effect restoration
;
; Register contract: Inputs none; output PlayerDeathX/Y cell restored from
; LevelMap; clobbers A, B, X, Y, U, CC; S balanced; DP unchanged; returns on
; the bitmap display plane.
;==============================================================================

RestorePlayerDeathEffect:
        lda     PlayerDeathX
        ldb     PlayerDeathY
        jmp     DrawMapCellAt

;==============================================================================
; Projectile pool reset
;
; Register contract: Inputs none; outputs cleared shot/fire state; clobbers
; A, B, X, CC. S is balanced and DP is unchanged.
;==============================================================================

ClearShots:
        ldx     #ShotActive
        ldb     #SHOT_COUNT
ClearShotsNext:
        clr     ,x+
        decb
        bne     ClearShotsNext
        clr     ShotMoveTimer
        clr     ShotAnimationFrame
        clr     PlayerFireTimer
        rts

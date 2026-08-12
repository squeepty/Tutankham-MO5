;==============================================================================
; MO5 deterministic frame timing
;
; DCMOTO testing proved that the previous monitor TIMEPT hook advanced the game
; around twelve times faster than its intended 50 Hz cadence. This calibrated
; delay costs just over 20,000 cycles on the stock 1 MHz 6809. Normal idle-frame
; work brings one call to RunGameFrame close to 20 ms.
;
; WaitFrame is deliberately a busy wait:
;   - no monitor ROM service is called;
;   - no interrupt changes simulation frequency;
;   - X and Y are scratch, while A/B/U are preserved;
;   - event sounds add blocking time on the frame in which they play.
;==============================================================================

WaitFrame:
        ldx     #FRAME_DELAY_OUTER
WaitFrameOuter:
        ldy     #FRAME_DELAY_INNER
WaitFrameInner:
        leay    -1,y
        bne     WaitFrameInner
        leax    -1,x
        bne     WaitFrameOuter
        rts

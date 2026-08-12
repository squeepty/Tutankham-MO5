;==============================================================================
; Projectile simulation, hit testing, and flash bomb
;
; Register contract for exported entries:
;   FireShot/ProcessShots/UseFlashBomb: Inputs none; outputs pool, score, and
;     guardian state in memory.
;   HitEnemyAtCandidate: Inputs CandidateX/Y; output A nonzero on a hit.
;   CurrentEnemyOverlapsCandidateCell: Inputs CurrentActorIndex and
;     CandidateX/Y; output A nonzero on overlap.
;   Clobbers: A, B, X, Y, U, CC. S is balanced and DP is unchanged.
;==============================================================================

;------------------------------------------------------------------------------
; Projectiles, hit testing, and flash bomb
;------------------------------------------------------------------------------
FireShot:
        ; Allocate the first inactive fixed slot. Shots start one cell ahead of
        ; the explorer and fail silently when all three slots are occupied.
        clr     CurrentActorIndex
FireShotFindSlot:
        ldb     CurrentActorIndex
        cmpb    #SHOT_COUNT
        beq     FireShotDone
        ldx     #ShotActive
        lda     b,x
        beq     FireShotUseSlot
        inc     CurrentActorIndex
        bra     FireShotFindSlot

FireShotUseSlot:
        jsr     EnsurePlayerFootprintRestored
        lda     #1
        sta     PlayerFireTimer
        jsr     SoundShot

        lda     PlayerX
        adda    PlayerFacing
        sta     CandidateX
        lda     PlayerY
        sta     CandidateY
        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelTile
        cmpa    #TILE_WALL
        beq     FireShotDone
        cmpa    #TILE_EXIT
        beq     FireShotDone
        jsr     HitEnemyAtCandidate
        bne     FireShotDone

        ldb     CurrentActorIndex
        ldx     #ShotActive
        lda     #1
        sta     b,x
        ldx     #ShotX
        lda     CandidateX
        sta     b,x
        ldx     #ShotY
        lda     CandidateY
        sta     b,x
        ldx     #ShotDirection
        lda     PlayerFacing
        sta     b,x
        jsr     DrawCurrentShot
FireShotDone:
        rts

ProcessShots:
        ; All active cells are restored first so movement/frame changes cannot
        ; leave trails. The pool then advances and redraws as one batch.
        lda     ShotMoveTimer
        beq     ProcessShotsMove
        dec     ShotMoveTimer
        rts
ProcessShotsMove:
        lda     #SHOT_MOVE_DELAY
        sta     ShotMoveTimer
        lda     ShotAnimationFrame
        eora    #$01
        sta     ShotAnimationFrame
        jsr     RestoreAllShotCells
        clr     CurrentActorIndex
ProcessShotsNext:
        ldb     CurrentActorIndex
        cmpb    #SHOT_COUNT
        beq     ProcessShotsRedraw
        ldx     #ShotActive
        lda     b,x
        beq     ProcessShotsSkip

        ldx     #ShotX
        lda     b,x
        sta     CandidateX
        ldx     #ShotY
        lda     b,x
        sta     CandidateY

        ldb     CurrentActorIndex
        ldx     #ShotDirection
        lda     b,x
        adda    CandidateX
        sta     CandidateX
        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelTile
        cmpa    #TILE_WALL
        beq     DeactivateCurrentShot
        cmpa    #TILE_EXIT
        beq     DeactivateCurrentShot
        jsr     HitEnemyAtCandidate
        bne     DeactivateCurrentShot

        ldb     CurrentActorIndex
        ldx     #ShotX
        lda     CandidateX
        sta     b,x
        bra     ProcessShotsSkip

DeactivateCurrentShot:
        ldb     CurrentActorIndex
        ldx     #ShotActive
        clr     b,x

ProcessShotsSkip:
        inc     CurrentActorIndex
        bra     ProcessShotsNext
ProcessShotsRedraw:
        jsr     DrawAllShots
ProcessShotsDone:
        rts

; Returns A nonzero when an enemy at CandidateX/CandidateY was removed.
HitEnemyAtCandidate:
        ; CandidateX/Y is the shot destination. A guardian's committed and
        ; targeted cells are both hittable during sub-cell motion.
        clr     QueryX
HitEnemyAtCandidateNext:
        ldb     QueryX
        cmpb    #ENEMY_COUNT
        beq     HitEnemyAtCandidateMiss
        ldx     #EnemyActive
        lda     b,x
        beq     HitEnemyAtCandidateSkip
        jsr     CurrentEnemyOverlapsCandidateCell
        beq     HitEnemyAtCandidateSkip

        lda     CurrentActorIndex
        pshs    a
        lda     QueryX
        sta     CurrentActorIndex
        jsr     DeactivateCurrentEnemy
        puls    a
        sta     CurrentActorIndex
        lda     #1
        jsr     AddScore
        jsr     DrawHudValues
        jsr     DrawEnemyHitStatus
        jsr     SoundEnemyHit
        lda     #1
        rts
HitEnemyAtCandidateSkip:
        inc     QueryX
        bra     HitEnemyAtCandidateNext
HitEnemyAtCandidateMiss:
        clra
        rts

UseFlashBomb:
        ; Deactivate every live guardian through the normal hit/respawn path.
        tst     FlashAvailable
        beq     UseFlashBombEmpty
        clr     FlashAvailable
        clr     CurrentActorIndex
UseFlashBombNext:
        ldb     CurrentActorIndex
        cmpb    #ENEMY_COUNT
        beq     UseFlashBombDone
        ldx     #EnemyActive
        lda     b,x
        beq     UseFlashBombSkip
        jsr     DeactivateCurrentEnemy
        lda     #1
        jsr     AddScore
UseFlashBombSkip:
        inc     CurrentActorIndex
        bra     UseFlashBombNext
UseFlashBombDone:
        jsr     DrawHudValues
        jsr     DrawHudIndicators
        jsr     DrawFlashStatus
        jsr     SoundFlash
        rts
UseFlashBombEmpty:
        jsr     DrawNoFlashStatus
        rts

; B = enemy index. Return A nonzero when its 8x8 pixel footprint overlaps the
; CandidateX/CandidateY cell occupied by a projectile.
CurrentEnemyOverlapsCandidateCell:
        lda     CandidateX
        lsla
        lsla
        lsla
        sta     MapDrawX
        lda     CandidateY
        lsla
        lsla
        lsla
        sta     MapDrawY

        ldx     #EnemyPixelX
        lda     b,x
        adda    #7
        cmpa    MapDrawX
        blo     CurrentEnemyCandidateMiss
        lda     MapDrawX
        adda    #7
        ldx     #EnemyPixelX
        cmpa    b,x
        blo     CurrentEnemyCandidateMiss

        ldx     #EnemyPixelY
        lda     b,x
        adda    #7
        cmpa    MapDrawY
        blo     CurrentEnemyCandidateMiss
        lda     MapDrawY
        adda    #7
        ldx     #EnemyPixelY
        cmpa    b,x
        blo     CurrentEnemyCandidateMiss
        lda     #1
        rts
CurrentEnemyCandidateMiss:
        clra
        rts

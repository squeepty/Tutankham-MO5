;==============================================================================
; Guardian lifecycle, motion, behavioral decisions, and actor reservations
;
; Register contract for exported entries:
;   ProcessEnemies: Inputs none; outputs all guardian simulation state.
;   ProcessCurrentEnemyFrame/ChooseEnemyMove: Input CurrentActorIndex; output
;     selected guardian state and, when possible, an in-flight target.
;   TryEnemyDirectionPreferred: Input A = proposed direction; output A nonzero
;     when a move starts.
;   EnemyCandidateBlocked: Input CandidateX/Y and CurrentActorIndex; output A
;     nonzero when the candidate is blocked.
;   Clobbers: A, B, X, Y, U, CC. S is balanced and DP is unchanged.
;==============================================================================

;------------------------------------------------------------------------------
; Guardian lifecycle, movement budget, animation, and chase decisions
;------------------------------------------------------------------------------
ProcessEnemies:
        ; Iterate the structure-of-arrays pool. Inactive slots update their hit
        ; effect/respawn; active slots animate, move, redraw, then test contact.
        clr     CurrentActorIndex
ProcessEnemiesNext:
        ldb     CurrentActorIndex
        cmpb    #ENEMY_COUNT
        beq     ProcessEnemiesContact
        ldx     #EnemyActive
        lda     b,x
        beq     ProcessEnemiesRespawn
        jsr     ProcessCurrentEnemyFrame
        bra     ProcessEnemiesSkip
ProcessEnemiesRespawn:
        jsr     UpdateCurrentEnemyRespawn
        ldb     CurrentActorIndex
        ldx     #EnemyActive
        lda     b,x
        beq     ProcessEnemiesSkip
        jsr     DrawCurrentEnemy
ProcessEnemiesSkip:
        inc     CurrentActorIndex
        bra     ProcessEnemiesNext
ProcessEnemiesContact:
        ; Repair projectile pixels that a moving guardian's map restore may
        ; have touched. Idle guardians themselves are never refreshed.
        jsr     DrawAllShots
        jsr     CheckPlayerEnemyContact
ProcessEnemiesDone:
        rts

ProcessCurrentEnemyFrame:
        ; A guardian can animate while blocked, but only restores its footprint
        ; once a movement or forced redraw has actually been scheduled.
        clr     CurrentEnemyForceRedraw
        jsr     UpdateCurrentEnemySpawnGrace
        ldb     CurrentActorIndex
        ldx     #EnemyPixelsRemaining
        lda     b,x
        bne     ProcessCurrentEnemyVisualUpdate

        ; Choose a new cell while the sprite is still untouched. If all exits
        ; are blocked, only its private animation timer may make it dirty.
        jsr     ChooseEnemyMove
        ldb     CurrentActorIndex
        ldx     #EnemyPixelsRemaining
        lda     b,x
        bne     ProcessCurrentEnemyVisualUpdate
        tst     CurrentEnemyForceRedraw
        bne     ProcessCurrentEnemyIdleRedraw
        ldx     #EnemyAnimationTimer
        lda     b,x
        beq     ProcessCurrentEnemyIdleFlip
        dec     b,x
        rts
ProcessCurrentEnemyIdleFlip:
        jsr     RestoreCurrentEnemyFootprint
        jsr     UpdateCurrentEnemyAnimation
        jmp     DrawCurrentEnemy
ProcessCurrentEnemyIdleRedraw:
        jsr     RestoreCurrentEnemyFootprint
        jmp     DrawCurrentEnemy

ProcessCurrentEnemyVisualUpdate:
        jsr     RestoreCurrentEnemyFootprint
        jsr     ProcessCurrentEnemyMotion
        jsr     UpdateCurrentEnemyAnimation
        jmp     DrawCurrentEnemy

ProcessCurrentEnemyMotion:
        ldb     CurrentActorIndex
        ldx     #EnemyPixelsRemaining
        lda     b,x
        bne     ProcessCurrentEnemyPrepare
        jsr     ChooseEnemyMove
        ldb     CurrentActorIndex
        ldx     #EnemyPixelsRemaining
        lda     b,x
        beq     ProcessCurrentEnemyDone
ProcessCurrentEnemyPrepare:
        jsr     PrepareCurrentEnemyStepBudget
ProcessCurrentEnemyStep:
        tst     CurrentEnemyStepBudget
        beq     ProcessCurrentEnemyDone
        dec     CurrentEnemyStepBudget
        jsr     AdvanceCurrentEnemyOnePixel
        ldb     CurrentActorIndex
        ldx     #EnemyPixelsRemaining
        lda     b,x
        bne     ProcessCurrentEnemyStep

        ; Do not choose another cell midway through the same display frame.
        ; Preserve unused pixel credit so cell boundaries cannot reduce speed.
        lda     CurrentEnemyStepBudget
        ldx     #EnemyStepCarry
        sta     b,x
        clr     CurrentEnemyStepBudget
ProcessCurrentEnemyDone:
        rts

PrepareCurrentEnemyStepBudget:
        ; Convert per-room eightieth-pixel speed units into whole-pixel credit.
        ldb     CurrentStageRoomIndex
        ldx     #EnemySpeedByRoom
        lda     b,x
        sta     CurrentEnemySpeedUnits
        ldb     CurrentActorIndex
        ldx     #EnemySpeedPhase
        lda     b,x
        adda    CurrentEnemySpeedUnits
        clr     CurrentEnemyStepBudget
PrepareCurrentEnemyExtractPixel:
        cmpa    #ENEMY_SPEED_SCALE
        blo     PrepareCurrentEnemyStorePhase
        suba    #ENEMY_SPEED_SCALE
        inc     CurrentEnemyStepBudget
        bra     PrepareCurrentEnemyExtractPixel
PrepareCurrentEnemyStorePhase:
        sta     b,x
PrepareCurrentEnemyCarry:
        ldx     #EnemyStepCarry
        lda     b,x
        adda    CurrentEnemyStepBudget
        sta     CurrentEnemyStepBudget
        clr     b,x
        rts

AdvanceCurrentEnemyOnePixel:
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        lda     b,x
        cmpa    #DPAD_UP_MASK
        beq     AdvanceCurrentEnemyUp
        cmpa    #DPAD_DOWN_MASK
        beq     AdvanceCurrentEnemyDown
        cmpa    #DPAD_LEFT_MASK
        beq     AdvanceCurrentEnemyLeft
        ldx     #EnemyPixelX
        inc     b,x
        bra     AdvanceCurrentEnemyStepped
AdvanceCurrentEnemyUp:
        ldx     #EnemyPixelY
        dec     b,x
        bra     AdvanceCurrentEnemyStepped
AdvanceCurrentEnemyDown:
        ldx     #EnemyPixelY
        inc     b,x
        bra     AdvanceCurrentEnemyStepped
AdvanceCurrentEnemyLeft:
        ldx     #EnemyPixelX
        dec     b,x
AdvanceCurrentEnemyStepped:
        ldx     #EnemyPixelsRemaining
        dec     b,x
        bne     AdvanceCurrentEnemyDone
        ldx     #EnemyTargetX
        lda     b,x
        ldx     #EnemyX
        sta     b,x
        ldx     #EnemyTargetY
        lda     b,x
        ldx     #EnemyY
        sta     b,x
AdvanceCurrentEnemyDone:
        rts

; Every guardian owns its pose timer. Initial and respawn offsets keep their
; rotations visibly independent instead of flipping as one group.
UpdateCurrentEnemyAnimation:
        ldb     CurrentActorIndex
        ldx     #EnemyAnimationTimer
        lda     b,x
        beq     UpdateCurrentEnemyAnimationFlip
        dec     b,x
        rts
UpdateCurrentEnemyAnimationFlip:
        lda     #ENEMY_ANIMATION_DELAY
        sta     b,x
        ldx     #EnemyAnimationFrame
        lda     b,x
        eora    #$01
        sta     b,x
        rts

UpdateCurrentEnemySpawnGrace:
        ldb     CurrentActorIndex
        ldx     #EnemySpawnGraceTimer
        lda     b,x
        beq     UpdateCurrentEnemySpawnGraceDone
        dec     b,x
        bne     UpdateCurrentEnemySpawnGraceDone
        lda     #1
        sta     CurrentEnemyForceRedraw
UpdateCurrentEnemySpawnGraceDone:
        rts

UpdateCurrentEnemyRespawn:
        ; Hit effects and respawn timers coexist in the inactive slot.
        jsr     UpdateCurrentEnemyHitEffect
        ldb     CurrentActorIndex
        ldx     #EnemyRespawnTimer
        lda     b,x
        beq     TryRespawnCurrentEnemy
        dec     b,x
        rts
TryRespawnCurrentEnemy:
        ; Do not materialize on top of the explorer or another live guardian.
        jsr     SetCurrentEnemyTableIndex
        ldb     CurrentRoomEnemyTableIndex
        ldx     #EnemyInitialX
        lda     b,x
        sta     CandidateX
        ldx     #EnemyInitialY
        lda     b,x
        sta     CandidateY
        lda     CandidateX
        cmpa    PlayerX
        bne     TryRespawnCheckActors
        lda     CandidateY
        cmpa    PlayerY
        beq     DelayCurrentEnemyRespawn
TryRespawnCheckActors:
        jsr     EnemyCandidateBlocked
        bne     DelayCurrentEnemyRespawn
        jsr     InitializeCurrentEnemyAtSpawn
        ldb     CurrentActorIndex
        ldx     #EnemySpawnGraceTimer
        lda     #ENEMY_RESPAWN_GRACE_FRAMES
        sta     b,x
        jmp     SoundRespawn
DelayCurrentEnemyRespawn:
        ldb     CurrentActorIndex
        ldx     #EnemyRespawnTimer
        lda     #10
        sta     b,x
        rts

UpdateCurrentEnemyHitEffect:
        ldb     CurrentActorIndex
        ldx     #EnemyHitEffectTimer
        lda     b,x
        beq     UpdateCurrentEnemyHitEffectDone
        dec     b,x
        bne     UpdateCurrentEnemyHitEffectDone
        ldx     #EnemyHitEffectX
        lda     b,x
        pshs    a
        ldx     #EnemyHitEffectY
        lda     b,x
        tfr     a,b
        puls    a
        jsr     DrawMapCellAt
UpdateCurrentEnemyHitEffectDone:
        rts

ChooseEnemyMove:
        ; Stable slot identities select a small decision policy while movement,
        ; reservation, speed, and collision remain shared by every guardian.
        ldb     CurrentActorIndex
        ldx     #EnemyDecisionPhase
        inc     b,x
        ldx     #EnemyBehaviorBySlot
        lda     b,x
        cmpa    #ENEMY_BEHAVIOR_INTERCEPT
        beq     ChooseEnemyInterceptor
        cmpa    #ENEMY_BEHAVIOR_WANDER
        lbeq    ChooseEnemyWander

ChooseEnemyDirect:
        jsr     SetEnemyGoalToPlayer
        bra     ChooseEnemyChase

ChooseEnemyInterceptor:
        jsr     SetEnemyGoalAheadOfPlayer

ChooseEnemyChase:
        ; Direct and intercepting guardians share greedy pursuit but use
        ; different goal cells. Alternating the preferred axis prevents two
        ; pursuers from taking every junction in lockstep.
        ldb     CurrentActorIndex
        ldx     #EnemyDecisionPhase
        lda     b,x
        bita    #$01
        bne     ChooseEnemyVerticalFirst
        jsr     TryEnemyTowardHorizontal
        lbne    ChooseEnemyMoveDone
        jsr     TryEnemyTowardVertical
        lbne    ChooseEnemyMoveDone
        bra     ChooseEnemyFallback
ChooseEnemyVerticalFirst:
        jsr     TryEnemyTowardVertical
        lbne    ChooseEnemyMoveDone
        jsr     TryEnemyTowardHorizontal
        lbne    ChooseEnemyMoveDone

ChooseEnemyFallback:
        ; Keep momentum when the direct chase route is blocked, then try both
        ; perpendicular turns. Immediate reversal is reserved for a dead end.
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        lda     b,x
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone

        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        lda     b,x
        cmpa    #DPAD_UP_MASK
        beq     ChooseEnemyHorizontalTurns
        cmpa    #DPAD_DOWN_MASK
        beq     ChooseEnemyHorizontalTurns

        ldx     #EnemyDecisionPhase
        lda     b,x
        bita    #$02
        bne     ChooseEnemyTryDownFirst
        lda     #DPAD_UP_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        lda     #DPAD_DOWN_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        bra     ChooseEnemyTryReverse
ChooseEnemyTryDownFirst:
        lda     #DPAD_DOWN_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        lda     #DPAD_UP_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        bra     ChooseEnemyTryReverse

ChooseEnemyHorizontalTurns:
        ldx     #EnemyDecisionPhase
        lda     b,x
        bita    #$02
        bne     ChooseEnemyTryRightFirst
        lda     #DPAD_LEFT_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        lda     #DPAD_RIGHT_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        bra     ChooseEnemyTryReverse
ChooseEnemyTryRightFirst:
        lda     #DPAD_RIGHT_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        lda     #DPAD_LEFT_MASK
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone

ChooseEnemyTryReverse:
        jsr     TryEnemyReverseDirection
ChooseEnemyMoveDone:
        rts

ChooseEnemyWander:
        ; Alternate short wandering and pursuit windows. During wandering, a
        ; rotating phase preference creates junction variety without a random
        ; source; blocked choices fall back to the robust corridor logic.
        ldb     CurrentActorIndex
        ldx     #EnemyDecisionPhase
        lda     b,x
        bita    #ENEMY_WANDER_CHASE_PHASE_BIT
        lbne    ChooseEnemyDirect
        anda    #$03
        tfr     a,b
        ldx     #EnemyWanderDirections
        lda     b,x
        jsr     TryEnemyDirectionPreferred
        lbne    ChooseEnemyMoveDone
        lbra    ChooseEnemyFallback

SetEnemyGoalToPlayer:
        lda     PlayerX
        sta     EnemyGoalX
        lda     PlayerY
        sta     EnemyGoalY
        rts

SetEnemyGoalAheadOfPlayer:
        ; Lead the explorer by four cells in the active direction. Between
        ; movement commits, horizontal facing supplies a useful fallback.
        jsr     SetEnemyGoalToPlayer
        lda     PlayerMoveDirection
        cmpa    #PLAYER_DIR_UP
        beq     SetEnemyGoalAheadUp
        cmpa    #PLAYER_DIR_DOWN
        beq     SetEnemyGoalAheadDown
        cmpa    #PLAYER_DIR_LEFT
        beq     SetEnemyGoalAheadLeft
        cmpa    #PLAYER_DIR_RIGHT
        beq     SetEnemyGoalAheadRight
        lda     PlayerFacing
        bmi     SetEnemyGoalAheadLeft
SetEnemyGoalAheadRight:
        lda     EnemyGoalX
        adda    #ENEMY_INTERCEPT_LOOKAHEAD
        cmpa    #LEVEL_WIDTH
        blo     SetEnemyGoalAheadStoreX
        lda     #LEVEL_WIDTH-1
SetEnemyGoalAheadStoreX:
        sta     EnemyGoalX
        rts
SetEnemyGoalAheadLeft:
        lda     EnemyGoalX
        cmpa    #ENEMY_INTERCEPT_LOOKAHEAD
        blo     SetEnemyGoalAheadLeftEdge
        suba    #ENEMY_INTERCEPT_LOOKAHEAD
        sta     EnemyGoalX
        rts
SetEnemyGoalAheadLeftEdge:
        clr     EnemyGoalX
        rts
SetEnemyGoalAheadDown:
        lda     EnemyGoalY
        adda    #ENEMY_INTERCEPT_LOOKAHEAD
        cmpa    #LEVEL_HEIGHT
        blo     SetEnemyGoalAheadStoreY
        lda     #LEVEL_HEIGHT-1
SetEnemyGoalAheadStoreY:
        sta     EnemyGoalY
        rts
SetEnemyGoalAheadUp:
        lda     EnemyGoalY
        cmpa    #ENEMY_INTERCEPT_LOOKAHEAD
        blo     SetEnemyGoalAheadTopEdge
        suba    #ENEMY_INTERCEPT_LOOKAHEAD
        sta     EnemyGoalY
        rts
SetEnemyGoalAheadTopEdge:
        clr     EnemyGoalY
        rts

TryEnemyTowardHorizontal:
        ldb     CurrentActorIndex
        ldx     #EnemyX
        lda     b,x
        cmpa    EnemyGoalX
        blo     TryEnemyTowardRight
        bhi     TryEnemyTowardLeft
        clra
        rts
TryEnemyTowardRight:
        lda     #DPAD_RIGHT_MASK
        jmp     TryEnemyDirectionPreferred
TryEnemyTowardLeft:
        lda     #DPAD_LEFT_MASK
        jmp     TryEnemyDirectionPreferred

TryEnemyTowardVertical:
        ldb     CurrentActorIndex
        ldx     #EnemyY
        lda     b,x
        cmpa    EnemyGoalY
        blo     TryEnemyTowardDown
        bhi     TryEnemyTowardUp
        clra
        rts
TryEnemyTowardDown:
        lda     #DPAD_DOWN_MASK
        jmp     TryEnemyDirectionPreferred
TryEnemyTowardUp:
        lda     #DPAD_UP_MASK
        jmp     TryEnemyDirectionPreferred

; Input: A = proposed direction. Returns A nonzero when a move was started.
; Direct chase choices never reverse the current heading.
TryEnemyDirectionPreferred:
        sta     EnemyCandidateDirection
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        lda     b,x
        cmpa    #DPAD_UP_MASK
        beq     TryEnemyPreferredFromUp
        cmpa    #DPAD_DOWN_MASK
        beq     TryEnemyPreferredFromDown
        cmpa    #DPAD_LEFT_MASK
        beq     TryEnemyPreferredFromLeft
        lda     EnemyCandidateDirection
        cmpa    #DPAD_LEFT_MASK
        beq     TryEnemyDirectionFailed
        bra     TryEnemyDirectionStored
TryEnemyPreferredFromUp:
        lda     EnemyCandidateDirection
        cmpa    #DPAD_DOWN_MASK
        beq     TryEnemyDirectionFailed
        bra     TryEnemyDirectionStored
TryEnemyPreferredFromDown:
        lda     EnemyCandidateDirection
        cmpa    #DPAD_UP_MASK
        beq     TryEnemyDirectionFailed
        bra     TryEnemyDirectionStored
TryEnemyPreferredFromLeft:
        lda     EnemyCandidateDirection
        cmpa    #DPAD_RIGHT_MASK
        beq     TryEnemyDirectionFailed

TryEnemyDirectionStored:
        lda     EnemyCandidateDirection
TryEnemyDirection:
        sta     EnemyCandidateDirection
        ldb     CurrentActorIndex
        ldx     #EnemyX
        lda     b,x
        sta     CandidateX
        ldx     #EnemyY
        lda     b,x
        sta     CandidateY

        lda     EnemyCandidateDirection
        cmpa    #DPAD_UP_MASK
        beq     TryEnemyDirectionUp
        cmpa    #DPAD_DOWN_MASK
        beq     TryEnemyDirectionDown
        cmpa    #DPAD_LEFT_MASK
        beq     TryEnemyDirectionLeft
        inc     CandidateX
        bra     TryEnemyDirectionCheck
TryEnemyDirectionUp:
        dec     CandidateY
        bra     TryEnemyDirectionCheck
TryEnemyDirectionDown:
        inc     CandidateY
        bra     TryEnemyDirectionCheck
TryEnemyDirectionLeft:
        dec     CandidateX
TryEnemyDirectionCheck:
        jsr     EnemyCandidateBlocked
        bne     TryEnemyDirectionFailed

        lda     EnemyCandidateDirection
        jsr     StoreEnemyMoveDirection
TryEnemyDirectionStart:
        jsr     StartEnemyMove
        lda     #1
        rts
TryEnemyDirectionFailed:
        clra
        rts

TryEnemyReverseDirection:
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        lda     b,x
        cmpa    #DPAD_UP_MASK
        beq     TryEnemyReverseDown
        cmpa    #DPAD_DOWN_MASK
        beq     TryEnemyReverseUp
        cmpa    #DPAD_LEFT_MASK
        beq     TryEnemyReverseRight
        lda     #DPAD_LEFT_MASK
        lbra    TryEnemyDirection
TryEnemyReverseDown:
        lda     #DPAD_DOWN_MASK
        lbra    TryEnemyDirection
TryEnemyReverseUp:
        lda     #DPAD_UP_MASK
        lbra    TryEnemyDirection
TryEnemyReverseRight:
        lda     #DPAD_RIGHT_MASK
        lbra    TryEnemyDirection

StartEnemyMove:
        ldb     CurrentActorIndex
        ldx     #EnemyTargetX
        lda     CandidateX
        sta     b,x
        ldx     #EnemyTargetY
        lda     CandidateY
        sta     b,x
        ldx     #EnemyPixelsRemaining
        lda     #PLAYER_CELL_PIXELS
        sta     b,x
        rts

StoreEnemyMoveDirection:
        ldb     CurrentActorIndex
        ldx     #EnemyMoveDirection
        sta     b,x
        rts

; Returns A nonzero for a wall or either kind of exit.
EnemyCandidateBlocked:
        ; A candidate is reserved by either another guardian's committed cell
        ; or its in-flight target, preventing two actors from converging.
        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelTile
        cmpa    #TILE_WALL
        beq     EnemyCandidateIsBlocked
        cmpa    #TILE_EXIT
        beq     EnemyCandidateIsBlocked
        cmpa    #TILE_ROOM_EXIT
        beq     EnemyCandidateIsBlocked
        clr     QueryX
EnemyCandidateCheckActors:
        ldb     QueryX
        cmpb    #ENEMY_COUNT
        beq     EnemyCandidateIsClear
        cmpb    CurrentActorIndex
        beq     EnemyCandidateNextActor
        ldx     #EnemyActive
        lda     b,x
        beq     EnemyCandidateNextActor
        ldx     #EnemyX
        lda     b,x
        cmpa    CandidateX
        bne     EnemyCandidateCheckActorTarget
        ldx     #EnemyY
        lda     b,x
        cmpa    CandidateY
        beq     EnemyCandidateIsBlocked
EnemyCandidateCheckActorTarget:
        ldx     #EnemyPixelsRemaining
        lda     b,x
        beq     EnemyCandidateNextActor
        ldx     #EnemyTargetX
        lda     b,x
        cmpa    CandidateX
        bne     EnemyCandidateNextActor
        ldx     #EnemyTargetY
        lda     b,x
        cmpa    CandidateY
        beq     EnemyCandidateIsBlocked
EnemyCandidateNextActor:
        inc     QueryX
        bra     EnemyCandidateCheckActors
EnemyCandidateIsClear:
        clra
        rts
EnemyCandidateIsBlocked:
        lda     #1
        rts

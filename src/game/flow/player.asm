;==============================================================================
; Explorer input, motion, pickups, warps, and transient timers
;
; Register contract for exported entries:
;   UpdateStatusMessage/UpdatePlayerInvulnerability/UpdatePlayerDeath/
;     ProcessPlayer/UpdatePlayerFireAnimation: Inputs none.
;   StartPlayerMove: Input A = PLAYER_DIR_* and CandidateX/Y = destination cell.
;   Outputs: explorer and mutable-map state in memory; StartPlayerMove reports
;            acceptance through movement state, not a return register.
;   Clobbers: A, B, X, Y, U, CC. S is balanced and DP is unchanged.
;==============================================================================

;------------------------------------------------------------------------------
; Status expiry, damage timers, and explorer simulation
;------------------------------------------------------------------------------
UpdateStatusMessage:
        lda     StatusMessageTimer
        beq     UpdateStatusMessageDone
        dec     StatusMessageTimer
        bne     UpdateStatusMessageDone
        jmp     ClearStatusLine
UpdateStatusMessageDone:
        rts

UpdatePlayerInvulnerability:
        lda     PlayerInvulnerabilityTimer
        beq     UpdatePlayerInvulnerabilityVisible
        dec     PlayerInvulnerabilityTimer
        beq     UpdatePlayerInvulnerabilityFinish
        lda     PlayerInvulnerabilityBlinkTimer
        beq     UpdatePlayerInvulnerabilityToggle
        dec     PlayerInvulnerabilityBlinkTimer
        rts
UpdatePlayerInvulnerabilityToggle:
        lda     #PLAYER_INVULNERABLE_BLINK_DELAY
        sta     PlayerInvulnerabilityBlinkTimer
        lda     PlayerVisible
        eora    #$01
        sta     PlayerVisible
        bne     UpdatePlayerInvulnerabilityShow
        jsr     EnsurePlayerFootprintRestored
        rts
UpdatePlayerInvulnerabilityShow:
        lda     #1
        sta     PlayerRedrawPending
        rts
UpdatePlayerInvulnerabilityFinish:
        clr     PlayerInvulnerabilityBlinkTimer
UpdatePlayerInvulnerabilityVisible:
        tst     PlayerVisible
        bne     UpdatePlayerInvulnerabilityDone
        lda     #1
        sta     PlayerVisible
        sta     PlayerRedrawPending
UpdatePlayerInvulnerabilityDone:
        rts

UpdatePlayerDeath:
        dec     PlayerDeathTimer
        bne     UpdatePlayerDeathDone
        jsr     RespawnPlayer
UpdatePlayerDeathDone:
        rts

ProcessPlayer:
        ; Continue an in-flight pixel move before considering a new direction.
        ; Opposite inputs cannot redirect the explorer halfway through a cell.
        tst     PlayerVisualDirty
        beq     ProcessPlayerCheckMovement
        jsr     EnsurePlayerFootprintRestored
        clr     PlayerVisualDirty
ProcessPlayerCheckMovement:
        tst     PlayerPixelsRemaining
        lbne    ContinuePlayerMove

        lda     Dpad_Held
        beq     ProcessPlayerNoDirection
        tst     PlayerPixelMoveTimer
        beq     ProcessPlayerDirectionReady
        dec     PlayerPixelMoveTimer
        lbra    ProcessPlayerActions
ProcessPlayerDirectionReady:
        bita    #DPAD_UP_MASK
        bne     ProcessPlayerUp
        bita    #DPAD_DOWN_MASK
        bne     ProcessPlayerDown
        bita    #DPAD_LEFT_MASK
        bne     ProcessPlayerLeft
        bita    #DPAD_RIGHT_MASK
        bne     ProcessPlayerRight
        bra     ProcessPlayerActions

ProcessPlayerNoDirection:
        clr     PlayerPixelMoveTimer
        clr     PlayerSpeedPhase
        clr     PlayerStepBudget
        clr     PlayerStepCarry
        clr     PlayerAnimationFrame
        bra     ProcessPlayerActions

ProcessPlayerUp:
        lda     PlayerX
        sta     CandidateX
        lda     PlayerY
        deca
        sta     CandidateY
        lda     #PLAYER_DIR_UP
        jsr     StartPlayerMove
        bra     ProcessPlayerActions

ProcessPlayerDown:
        lda     PlayerX
        sta     CandidateX
        lda     PlayerY
        inca
        sta     CandidateY
        lda     #PLAYER_DIR_DOWN
        jsr     StartPlayerMove
        bra     ProcessPlayerActions

ProcessPlayerLeft:
        lda     #$FF
        sta     PlayerFacing
        lda     PlayerX
        deca
        sta     CandidateX
        lda     PlayerY
        sta     CandidateY
        lda     #PLAYER_DIR_LEFT
        jsr     StartPlayerMove
        bra     ProcessPlayerActions

ProcessPlayerRight:
        lda     #1
        sta     PlayerFacing
        lda     PlayerX
        inca
        sta     CandidateX
        lda     PlayerY
        sta     CandidateY
        lda     #PLAYER_DIR_RIGHT
        jsr     StartPlayerMove
        bra     ProcessPlayerActions

ContinuePlayerMove:
        tst     PlayerPixelMoveTimer
        beq     ContinuePlayerMoveStep
        dec     PlayerPixelMoveTimer
        bra     ProcessPlayerActions
ContinuePlayerMoveStep:
        jsr     EnsurePlayerFootprintRestored
        jsr     PreparePlayerStepBudget
        jsr     AdvancePlayerFrame

ProcessPlayerActions:
        tst     GameState
        bne     ProcessPlayerDone
        lda     Action_Press
        bita    #ACTION_NEXT_ROOM_MASK
        beq     ProcessPlayerFire
        ; Development shortcut: reproduce arriving at an unlocked gate and
        ; follow the real transition/completion path.
        lda     #1
        sta     HasKey
        jmp     TryRoomTransition
ProcessPlayerFire:
        lda     Action_Press
        bita    #ACTION_FIRE_MASK
        beq     ProcessPlayerFlash
        jsr     FireShot
ProcessPlayerFlash:
        lda     Action_Press
        bita    #ACTION_FLASH_MASK
        beq     ProcessPlayerDone
        jsr     UseFlashBomb
ProcessPlayerDone:
        rts

UpdatePlayerFireAnimation:
        lda     PlayerFireTimer
        beq     UpdatePlayerFireAnimationDone
        dec     PlayerFireTimer
        bne     UpdatePlayerFireAnimationDone
        lda     #1
        sta     PlayerVisualDirty
UpdatePlayerFireAnimationDone:
        rts

; Input: A = one PLAYER_DIR_* value, CandidateX/Y = destination cell.
StartPlayerMove:
        ; CandidateX/Y must already contain the destination. Walls and locked
        ; gates reject the move; collectible/warp tiles remain traversable.
        sta     PlayerMoveDirection
        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelTile
        cmpa    #TILE_WALL
        beq     StartPlayerMoveBlocked
        cmpa    #TILE_EXIT
        beq     StartPlayerMoveCheckKey
        cmpa    #TILE_ROOM_EXIT
        bne     StartPlayerMoveAllowed
StartPlayerMoveCheckKey:
        tst     HasKey
        bne     StartPlayerMoveAllowed
        clr     PlayerMoveDirection
        jsr     DrawNeedKeyStatus
        rts

StartPlayerMoveAllowed:
        jsr     EnsurePlayerFootprintRestored
        lda     CandidateX
        sta     PlayerTargetX
        lda     CandidateY
        sta     PlayerTargetY
        lda     #PLAYER_CELL_PIXELS
        sta     PlayerPixelsRemaining
        jsr     PreparePlayerStepBudget
        jmp     AdvancePlayerFrame

StartPlayerMoveBlocked:
        clr     PlayerMoveDirection
        clr     PlayerSpeedPhase
        clr     PlayerStepBudget
        clr     PlayerStepCarry
        clr     PlayerAnimationFrame
        rts

; Build an exact 2.25-pixel average as repeating 2,2,2,3-pixel budgets. Carry
; pixels that could not cross a cell boundary into the next legal cell.
PreparePlayerStepBudget:
        ; Fixed cadence 2,2,2,3 pixels/frame plus carried unused credit.
        lda     #2
        sta     PlayerStepBudget
        lda     PlayerSpeedPhase
        inca
        cmpa    #4
        blo     PreparePlayerStepStorePhase
        clra
PreparePlayerStepStorePhase:
        sta     PlayerSpeedPhase
        bne     PreparePlayerStepCarry
        inc     PlayerStepBudget
PreparePlayerStepCarry:
        lda     PlayerStepCarry
        adda    PlayerStepBudget
        sta     PlayerStepBudget
        clr     PlayerStepCarry
        rts

AdvancePlayerFrame:
        tst     PlayerStepBudget
        beq     AdvancePlayerFrameDone
AdvancePlayerFrameNext:
        dec     PlayerStepBudget
        jsr     AdvancePlayerOnePixel
        tst     PlayerPixelsRemaining
        beq     AdvancePlayerFrameBoundary
        tst     PlayerStepBudget
        bne     AdvancePlayerFrameNext
AdvancePlayerFrameDone:
        rts
AdvancePlayerFrameBoundary:
        lda     PlayerStepBudget
        sta     PlayerStepCarry
        clr     PlayerStepBudget
        rts

AdvancePlayerOnePixel:
        lda     #PLAYER_PIXEL_MOVE_DELAY
        sta     PlayerPixelMoveTimer
        lda     PlayerMoveDirection
        cmpa    #PLAYER_DIR_UP
        beq     AdvancePlayerUp
        cmpa    #PLAYER_DIR_DOWN
        beq     AdvancePlayerDown
        cmpa    #PLAYER_DIR_LEFT
        beq     AdvancePlayerLeft
        inc     PlayerPixelX
        bra     AdvancePlayerStepped
AdvancePlayerUp:
        dec     PlayerPixelY
        bra     AdvancePlayerStepped
AdvancePlayerDown:
        inc     PlayerPixelY
        bra     AdvancePlayerStepped
AdvancePlayerLeft:
        dec     PlayerPixelX

AdvancePlayerStepped:
        dec     PlayerPixelsRemaining
        beq     CommitPlayerMove

        ; Alternate two walking poses every two sub-cell pixels.
        lda     PlayerPixelsRemaining
        lsra
        anda    #$01
        sta     PlayerAnimationFrame
        rts

CommitPlayerMove:
        ; Commit the destination only after all eight visible pixel steps, then
        ; resolve tile effects exactly once from the new cell.
        clr     PlayerMoveDirection
        clr     PlayerAnimationFrame
        lda     PlayerTargetX
        sta     PlayerX
        sta     CandidateX
        lda     PlayerTargetY
        sta     PlayerY
        sta     CandidateY

        lda     CandidateX
        ldb     CandidateY
        jsr     GetLevelTile
        cmpa    #TILE_KEY
        beq     CollectKey
        cmpa    #TILE_TREASURE
        beq     CollectTreasure
        cmpa    #TILE_WARP_DOWN
        beq     UseWarpDown
        cmpa    #TILE_WARP_UP
        beq     UseWarpUp
        cmpa    #TILE_EXIT
        lbeq    TryPlayerExit
        cmpa    #TILE_ROOM_EXIT
        beq     TryRoomTransition
        bra     FinishPlayerMove

CollectKey:
        lda     #1
        sta     HasKey
        lda     #2
        jsr     AddScore
        jsr     ClearCandidateTile
        jsr     DrawKeyStatus
        jsr     SoundKeyPickup
        bra     FinishPlayerMove

CollectTreasure:
        ; Each consecutive pickup in this room increases the award by 500.
        ; The room data contract caps the streak at three treasures.
        inc     TreasureStreak
        lda     TreasureStreak
        ldb     #TREASURE_BASE_SCORE_HUNDREDS
        mul
        tfr     b,a
        jsr     AddScore
        jsr     ClearCandidateTile
        lda     TreasureStreak
        cmpa    #TREASURE_STREAK_MAX
        bhs     CollectTreasureStreakThree
        cmpa    #2
        beq     CollectTreasureStreakTwo
        jsr     DrawTreasureStatus
        bra     CollectTreasureSound
CollectTreasureStreakTwo:
        jsr     DrawTreasureStreakTwoStatus
        bra     CollectTreasureSound
CollectTreasureStreakThree:
        jsr     DrawTreasureStreakThreeStatus
CollectTreasureSound:
        jsr     SoundTreasurePickup
        bra     FinishPlayerMove

UseWarpDown:
        lda     #WARP_DOWN_EXIT_Y
        sta     PlayerY
        jsr     SyncPlayerPixelPosition
        jsr     DrawWarpStatus
        jsr     SoundWarp
        bra     FinishPlayerMove

UseWarpUp:
        lda     #WARP_UP_EXIT_Y
        sta     PlayerY
        jsr     SyncPlayerPixelPosition
        jsr     DrawWarpStatus
        jsr     SoundWarp

FinishPlayerMove:
        jsr     DrawHudValues
        jsr     CheckPlayerEnemyContact
        rts

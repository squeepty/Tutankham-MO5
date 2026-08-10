;==============================================================================
; Writable nine-stage game state
;
; Storage conventions:
;   - scalar flags/timers are one byte unless noted;
;   - zero normally means inactive, unavailable, or no work pending;
;   - shot and guardian data use structure-of-arrays layout;
;   - CurrentActorIndex selects an entry in the active shot/enemy arrays;
;   - Candidate*/Query* and renderer fields are shared scratch, never durable
;     state across a complete frame;
;   - LevelMap and DemoVisitMap are the two largest writable workspaces.
;
; CurrentLevel is a legacy name for the zero-based stage (0-8). CurrentRoom is
; the zero-based room within that variable-size stage (0-2).
;==============================================================================

;------------------------------------------------------------------------------
; Game mode and explorer
;------------------------------------------------------------------------------
GameState:
        fcb     0
; Committed collision cell. Pixel coordinates can lie between this cell and
; PlayerTarget* while an eight-pixel movement is in progress.
PlayerX:
        fcb     0
PlayerY:
        fcb     0
PlayerFacing:
        fcb     0
; Absolute room-local pixel coordinates used by the shifted sprite renderer.
PlayerPixelX:
        fcb     0
PlayerPixelY:
        fcb     0
PlayerMoveDirection:
        fcb     0
PlayerPixelsRemaining:
        fcb     0
PlayerPixelMoveTimer:
        fcb     0
PlayerSpeedPhase:
        fcb     0
PlayerStepBudget:
        fcb     0
PlayerStepCarry:
        fcb     0
PlayerTargetX:
        fcb     0
PlayerTargetY:
        fcb     0
PlayerAnimationFrame:
        fcb     0
PlayerFireTimer:
        fcb     0
PlayerVisualDirty:
        fcb     0
PlayerRedrawPending:
        fcb     0
PlayerCompositePending:
        fcb     0
; Run resources and damage state.
PlayerLives:
        fcb     0
InfiniteLives:
        fcb     0
PlayerInvulnerabilityTimer:
        fcb     0
PlayerInvulnerabilityBlinkTimer:
        fcb     0
PlayerVisible:
        fcb     0
PlayerDeathTimer:
        fcb     0
PlayerDeathX:
        fcb     0
PlayerDeathY:
        fcb     0

;------------------------------------------------------------------------------
; Inventory, score, and session-persistent high-score table
;
; Scores are stored in hundreds: one ten-thousands digit plus a 0-99 byte. The
; display supplies the final two zeroes. High scores survive ResetLevel because
; InitGame initializes only session systems, not the table.
;------------------------------------------------------------------------------
HasKey:
        fcb     0
FlashAvailable:
        fcb     0
ScoreTenThousands:
        fcb     0
ScoreHundreds:
        fcb     0
HighScoreTenThousands:
        fcb     0
HighScoreHundreds:
        fcb     60
HighScoreSecondTenThousands:
        fcb     0
HighScoreSecondHundreds:
        fcb     40
HighScoreThirdTenThousands:
        fcb     0
HighScoreThirdHundreds:
        fcb     20
NewHighScoreFlag:
        fcb     0

;------------------------------------------------------------------------------
; Presentation, title attract loop, title cheat, and demo driver
;------------------------------------------------------------------------------
PresentationTimer:
        fcb     0
TitleScenePhase:
        fcb     0
TitleSceneHoldTimer:
        fcb     0
TitleScenePlayerPixelX:
        fcb     0
TitleSceneSnakePixelX:
        fcb     0
TitleSceneSnakeVisible:
        fcb     0
TitleSceneShotPixelX:
        fcb     0
TitleSceneShotActive:
        fcb     0
TitleSceneDiamondMask:
        fcb     0
TitleSceneSpritePixelX:
        fcb     0
TitleSceneSpritePhase:
        fcb     0
TitleIdleFrameTimer:
        fcb     0
TitleIdleSeconds:
        fcb     0
CheatUnlocked:
        fcb     0
TitleCheatProgress:
        fcb     0
TitleCheatHeldKey:
        fcb     0

; Demo pathfinding caches a target and a per-room visit map. $FF invalidates a
; cached room/key/score value without needing an additional flag byte.
DemoActive:
        fcb     0
DemoSecondFrameTimer:
        fcb     0
DemoSecondsRemaining:
        fcb     0
DemoRandomState:
        fcb     $A5
DemoMoveDirection:
        fcb     0
DemoReverseDirection:
        fcb     0
DemoHorizontalDirection:
        fcb     0
DemoVerticalDirection:
        fcb     0
DemoCandidateDirection:
        fcb     0
DemoTargetValid:
        fcb     0
DemoTargetRoomIndex:
        fcb     $FF
DemoTargetHasKey:
        fcb     $FF
DemoTargetTile:
        fcb     0
DemoTargetX:
        fcb     0
DemoTargetY:
        fcb     0
DemoVisitRoomIndex:
        fcb     $FF
DemoBestVisitScore:
        fcb     $FF
DemoBestDirection:
        fcb     0
DemoScanX:
        fcb     0
DemoScanY:
        fcb     0
DemoFireTimer:
        fcb     0
DemoFlashTimer:
        fcb     0

;------------------------------------------------------------------------------
; Status text, current stage/room selection, and room-transition scratch
;------------------------------------------------------------------------------
StatusMessageTimer:
        fcb     0
StatusTextLength:
        fcb     0
PresentationNumberColumn:
        fcb     0
PresentationNumberRow:
        fcb     0
CurrentLevel:
        fcb     0
CurrentRoom:
        fcb     0
; Flattened table index: StageRoomOffsets[CurrentLevel] + CurrentRoom.
CurrentStageRoomIndex:
        fcb     0
CurrentWallColor:
        fcb     COLOR_WALL_ROOM_ONE
CurrentRoomEnemyOffset:
        fcb     0
CurrentRoomEnemyTableIndex:
        fcb     0
RoomTransitionDiagonal:
        fcb     0
RoomTransitionX:
        fcb     0
RoomTransitionY:
        fcb     0

;------------------------------------------------------------------------------
; Fixed projectile pool
;
; Slot n is active when ShotActive[n] != 0. Direction is signed: non-negative
; moves right, negative moves left. Projectiles remain cell-aligned.
;------------------------------------------------------------------------------
ShotMoveTimer:
        fcb     0
ShotAnimationFrame:
        fcb     0
ShotActive:
        rmb     SHOT_COUNT
ShotX:
        rmb     SHOT_COUNT
ShotY:
        rmb     SHOT_COUNT
ShotDirection:
        rmb     SHOT_COUNT

;------------------------------------------------------------------------------
; Fixed guardian pool
;
; Committed EnemyX/Y, target EnemyTargetX/Y, and live EnemyPixelX/Y mirror the
; explorer's cell-plus-pixel motion model. Per-actor timers deliberately avoid
; synchronized animation, respawn, and decision phases.
;------------------------------------------------------------------------------
EnemyAnimationTimer:
        rmb     ENEMY_COUNT
EnemyAnimationFrame:
        rmb     ENEMY_COUNT
EnemyActive:
        rmb     ENEMY_COUNT
EnemyX:
        rmb     ENEMY_COUNT
EnemyY:
        rmb     ENEMY_COUNT
EnemyPixelX:
        rmb     ENEMY_COUNT
EnemyPixelY:
        rmb     ENEMY_COUNT
EnemyTargetX:
        rmb     ENEMY_COUNT
EnemyTargetY:
        rmb     ENEMY_COUNT
EnemyPixelsRemaining:
        rmb     ENEMY_COUNT
EnemyMoveDirection:
        rmb     ENEMY_COUNT
EnemySpeedPhase:
        rmb     ENEMY_COUNT
EnemyStepCarry:
        rmb     ENEMY_COUNT
EnemyRespawnTimer:
        rmb     ENEMY_COUNT
EnemyHitEffectTimer:
        rmb     ENEMY_COUNT
EnemyHitEffectX:
        rmb     ENEMY_COUNT
EnemyHitEffectY:
        rmb     ENEMY_COUNT
EnemySpawnGraceTimer:
        rmb     ENEMY_COUNT
EnemyDecisionPhase:
        rmb     ENEMY_COUNT
CurrentEnemyStepBudget:
        fcb     0
CurrentEnemySpeedUnits:
        fcb     0
CurrentEnemyForceRedraw:
        fcb     0
EnemyCandidateDirection:
        fcb     0
EnemyHorizontalPhase:
        fcb     0
EnemyDrawColumn:
        fcb     0

;------------------------------------------------------------------------------
; Shared simulation/rendering scratch
;
; These bytes reduce stack traffic in hot 6809 paths. A routine that calls
; another scratch-using routine must save any value it still needs.
;------------------------------------------------------------------------------
CurrentActorIndex:
        fcb     0
CandidateX:
        fcb     0
CandidateY:
        fcb     0
QueryX:
        fcb     0
MapDrawX:
        fcb     0
MapDrawY:
        fcb     0
MapTargetX:
        fcb     0
MapTargetY:
        fcb     0
MapRowsRemaining:
        fcb     0
MapCellsRemaining:
        fcb     0
HudCharacter:
        fcb     0
HudColumn:
        fcb     0
NumberOnes:
        fcb     0
NumberTens:
        fcb     0
NumberTenThousands:
        fcb     0
PlayerFootprintLeft:
        fcb     0
PlayerFootprintRight:
        fcb     0
PlayerFootprintTop:
        fcb     0
PlayerFootprintBottom:
        fcb     0
PlayerDrawColumn:
        fcb     0
PlayerHorizontalPhase:
        fcb     0

;------------------------------------------------------------------------------
; Room workspaces
;
; LevelMap is the unpacked mutable 30x22 room. DemoVisitMap is parallel storage
; used as byte visit counts by the attract-mode controller.
;------------------------------------------------------------------------------
LevelMap:
        rmb     LEVEL_CELL_COUNT
DemoVisitMap:
        rmb     LEVEL_CELL_COUNT

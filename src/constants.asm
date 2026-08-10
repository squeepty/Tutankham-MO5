;==============================================================================
; Tutankham MO5 nine-stage game
; Shared constants
;
; Naming contract:
;   - Player-facing text uses Stage 1-9 and Room 1-3.
;   - CurrentLevel/LEVEL_COUNT are legacy symbol names for the zero-based stage
;     index and number of stages.
;   - CurrentStageRoomIndex uses StageRoomOffsets to flatten variable-size
;     stages to the sequential room range 0-20.
;   - LEVEL_WIDTH/HEIGHT describe one physical room bitmap, not all 21 rooms.
;==============================================================================

; Program placement
PROGRAM_ORIGIN          equ     $4000
STACK_TOP               equ     $9FFF

; MO5 video and hardware I/O
VIDEO_BITMAP_BASE       equ     $0000
VIDEO_COLOR_BASE        equ     VIDEO_BITMAP_BASE
VIDEO_BANK_SELECT       equ     $A7C0
KEYBOARD_PORT           equ     $A7C1
SYSTEM_PIA_CRB          equ     $A7C3
SOUND_BUZZER_PORT       equ     KEYBOARD_PORT
SOUND_BUZZER_BIT        equ     $01
JOYPAD_DPAD_PORT        equ     $A7CC
JOYPAD_FIRE_PORT        equ     $A7CD
JOYPAD_CRA              equ     $A7CE
JOYPAD_CRB              equ     $A7CF

; Display geometry
VIDEO_BYTES_PER_ROW     equ     40
VIDEO_ROWS              equ     200
VIDEO_BITMAP_BYTES      equ     8000
VIDEO_BITMAP_WORDS      equ     4000
VIDEO_COLOR_BYTES       equ     VIDEO_BITMAP_BYTES
TEXT_CELL_HEIGHT        equ     8
TEXT_COLUMNS            equ     40
TEXT_ROWS               equ     25

; Stage palettes: one foreground color on black per 8-pixel cell. Room colors
; follow the ColecoVision sandstone/red/green/blue/purple progression while
; retaining monochrome tiles.
COLOR_BACKGROUND        equ     $00
COLOR_TEXT              equ     $70
COLOR_TITLE             equ     $E0
COLOR_WALL_ROOM_ONE     equ     $B0
COLOR_WALL_ROOM_TWO     equ     $90
COLOR_WALL_ROOM_THREE   equ     $C0
COLOR_WALL_GREEN        equ     $A0
COLOR_WALL_PURPLE       equ     $D0
COLOR_DOOR              equ     $40
COLOR_ROOM_EXIT         equ     $70
COLOR_KEY               equ     $60
COLOR_TREASURE          equ     $60
COLOR_SPAWN             equ     $D0
COLOR_WARP              equ     $70
COLOR_PLAYER            equ     $30
COLOR_FLASH_INDICATOR   equ     $90
COLOR_ENEMY             equ     $20
COLOR_ENEMY_RESPAWN     equ     $60
COLOR_HIT_EFFECT        equ     $70
COLOR_SHOT              equ     $70

; Normalized direction and action bits
DPAD_UP_MASK            equ     %00000001
DPAD_DOWN_MASK          equ     %00000010
DPAD_LEFT_MASK          equ     %00000100
DPAD_RIGHT_MASK         equ     %00001000
JOYPAD_FIRE_MASK        equ     %01000000
ACTION_FIRE_MASK        equ     %00000001
ACTION_FLASH_MASK       equ     %00000010
ACTION_NEXT_ROOM_MASK   equ     %00000100
ACTION_INFINITE_LIVES_MASK equ  %00001000

; MO5 keyboard matrix selectors. Bits 4-6 choose an inverted matrix line and
; bits 1-3 choose the column; bit 7 reads active-low. S/Q double as AZERTY
; movement aliases and as the first two title-cheat letters.
KEY_CURSOR_RIGHT_SELECTOR equ   $32
KEY_CURSOR_DOWN_SELECTOR equ    $42
KEY_CURSOR_LEFT_SELECTOR equ    $52
KEY_CURSOR_UP_SELECTOR   equ     $62
KEY_UP_SELECTOR         equ     $4A
KEY_DOWN_SELECTOR       equ     $46
KEY_LEFT_SELECTOR       equ     $56
KEY_RIGHT_SELECTOR      equ     $36
KEY_FIRE_SELECTOR       equ     $40
KEY_FLASH_SELECTOR      equ     $50
KEY_NEXT_ROOM_SELECTOR  equ     $00
KEY_INFINITE_LIVES_SELECTOR equ $18
KEY_CHEAT_U_SELECTOR    equ     $08
KEY_CHEAT_E_SELECTOR    equ     $3A
KEY_CHEAT_P_SELECTOR    equ     $38
KEY_CHEAT_T_SELECTOR    equ     $1A
KEY_CHEAT_Y_SELECTOR    equ     $0A
TITLE_CHEAT_KEY_COUNT   equ     7
TITLE_CHEAT_SEQUENCE_LENGTH equ 8

; Every stage room uses a 30x22 MO5 playfield. The ten interior source rows
; are doubled vertically to retain the ColecoVision proportions.
LEVEL_WIDTH             equ     30
LEVEL_HEIGHT            equ     22
LEVEL_CELL_COUNT        equ     LEVEL_WIDTH*LEVEL_HEIGHT
LEVEL_SCREEN_COL        equ     5
LEVEL_SCREEN_ROW        equ     2
STATUS_TEXT_COL         equ     1
STATUS_TEXT_ROW         equ     24
STATUS_TEXT_CELLS       equ     38
HUD_TEXT_COL            equ     11
HUD_TEXT_ROW            equ     0
LIVES_TEXT_ROW          equ     1
LIVES_DISPLAY_CELLS     equ     3
LIVES_CLEAR_START_COL   equ     (TEXT_COLUMNS-LIVES_DISPLAY_CELLS)/2
HUD_INDICATOR_CLEAR_CELLS equ   5

; Tile values
TILE_FLOOR              equ     '.'
TILE_WALL               equ     '#'
TILE_KEY                equ     'K'
TILE_TREASURE           equ     'T'
TILE_EXIT               equ     'D'
TILE_SPAWN              equ     'S'
TILE_WARP_DOWN          equ     'V'
TILE_WARP_UP            equ     'A'
TILE_ROOM_EXIT          equ     'R'

; Game states. PLAYING is zero so the hot frame dispatcher can use BEQ.
GAME_STATE_PLAYING      equ     0
GAME_STATE_COMPLETE     equ     1
GAME_STATE_OVER         equ     2
GAME_STATE_TITLE        equ     3
GAME_STATE_LEVEL_INTRO  equ     4
GAME_STATE_ROOM_TRANSITION equ  5
LEVEL_INTRO_FRAMES      equ     112
STATUS_MESSAGE_FRAMES   equ     100
TITLE_SCENE_ROW         equ     7
TITLE_SCENE_CLEAR_COL   equ     5
TITLE_SCENE_CLEAR_CELLS equ     30
TITLE_SCENE_FRAME_LEFT_COL equ  4
TITLE_SCENE_FRAME_TOP_ROW equ   6
TITLE_SCENE_FRAME_WIDTH equ     32
TITLE_SCENE_FRAME_HEIGHT equ    3
TITLE_SCENE_DIAMOND_LEFT_COL equ 8
TITLE_SCENE_DIAMOND_RIGHT_COL equ 10
TITLE_SCENE_DIAMOND_LEFT_PIXEL_X equ 64
TITLE_SCENE_DIAMOND_RIGHT_PIXEL_X equ 80
TITLE_SCENE_PLAYER_CENTER_PIXEL_X equ 160
TITLE_SCENE_PLAYER_ALERT_PIXEL_X equ 104
TITLE_SCENE_FIRST_SNAKE_PIXEL_X equ 232
TITLE_SCENE_SECOND_SNAKE_PIXEL_X equ 248
TITLE_SCENE_PLAYER_SPEED equ    2
TITLE_SCENE_SNAKE_SPEED equ     1
TITLE_SCENE_SHOT_SPEED equ      3
TITLE_SCENE_SHOT_START_OFFSET equ 12
TITLE_SCENE_INITIAL_FRAMES equ  25
TITLE_SCENE_ALERT_FRAMES equ    20
TITLE_SCENE_CENTER_FRAMES equ   50
TITLE_SCENE_DIAMOND_PICKUP_OFFSET equ 7
TITLE_SCENE_DIAMOND_LEFT_MASK equ  $01
TITLE_SCENE_DIAMOND_RIGHT_MASK equ $02
TITLE_SCENE_DIAMOND_BOTH_MASK equ  $03
TITLE_SCENE_PHASE_APPROACH equ  0
TITLE_SCENE_PHASE_FIRST_ALERT equ 1
TITLE_SCENE_PHASE_FIRST_SHOT equ 2
TITLE_SCENE_PHASE_SECOND_ALERT equ 3
TITLE_SCENE_PHASE_SECOND_SHOT equ 4
TITLE_SCENE_PHASE_COLLECT equ   5
TITLE_SCENE_PHASE_RETURN_CENTER equ 6
TITLE_SCENE_PHASE_CENTER_PAUSE equ 7
TITLE_IDLE_SECOND_FRAMES equ    50
TITLE_IDLE_SECONDS       equ    10
DEMO_DURATION_SECONDS    equ    30
DEMO_FIRE_INTERVAL_FRAMES equ  18
DEMO_FIRE_RETRY_FRAMES   equ    5
DEMO_FLASH_DELAY_FRAMES  equ    200
MAX_STAGE_ROOM_COUNT    equ     3
; Legacy LEVEL_* symbols count stages, not individual rooms.
LEVEL_COUNT             equ     9
LEVEL_LAST_INDEX        equ     LEVEL_COUNT-1
TOTAL_ROOM_COUNT        equ     21
ROOM_TRANSITION_DIAGONAL_COUNT equ LEVEL_WIDTH+LEVEL_HEIGHT-1
ROOM_TRANSITION_DIAGONALS_PER_FRAME equ 3
PLAYER_START_X          equ     1
PLAYER_START_Y          equ     1
WARP_DOWN_EXIT_Y        equ     19
WARP_UP_EXIT_Y          equ     2
; Explorer motion uses a carried 2,2,2,3-pixel cadence: nine pixels every four
; simulation frames, or 2.25 pixels/frame.
; Logical collision coordinates are committed after PLAYER_CELL_PIXELS steps.
PLAYER_CELL_PIXELS      equ     8
PLAYER_PIXEL_MOVE_DELAY equ     0
PLAYER_DIR_UP           equ     DPAD_UP_MASK
PLAYER_DIR_DOWN         equ     DPAD_DOWN_MASK
PLAYER_DIR_LEFT         equ     DPAD_LEFT_MASK
PLAYER_DIR_RIGHT        equ     DPAD_RIGHT_MASK
PLAYER_START_LIVES      equ     3
PLAYER_INVULNERABLE_FRAMES equ  45
PLAYER_INVULNERABLE_BLINK_DELAY equ 4
PLAYER_DEATH_EFFECT_FRAMES equ  15
SHOT_COUNT              equ     3
SHOT_MOVE_DELAY         equ     1
ENEMY_COUNT             equ     3
; About 20 ms at the stock 1 MHz 6809. Keeping this cadence CPU-cycle based
; avoids the monitor-hook overrun observed in DCMOTO.
FRAME_DELAY_OUTER       equ     18
FRAME_DELAY_INNER       equ     160
; Guardian speed uses eightieth-pixel units selected from EnemySpeedByRoom.
; The flattened table rises smoothly from 126/80 (70% of the explorer) in
; Stage 1 Room 1 to 162/80 (90%) in Stage 9 Room 3.
ENEMY_SPEED_SCALE       equ     80
ENEMY_INITIAL_SPAWN_STAGGER equ 10
ENEMY_RESPAWN_BASE      equ     75
ENEMY_RESPAWN_STAGGER   equ     12
ENEMY_HIT_EFFECT_FRAMES equ     8
ENEMY_RESPAWN_GRACE_FRAMES equ  20
; Measured in DCMOTO with the current guardian workload: nineteen simulation
; frames produce one guardian pose replacement in about 500 ms.
ENEMY_ANIMATION_DELAY   equ     18

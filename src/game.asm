;==============================================================================
; Game-layer include manifest
;
; Ordering rules:
;   1. immutable strings, artwork, packed maps, and lookup tables
;   2. rendering manifest and its presentation/world/actor/restoration/HUD files
;   3. flow manifest and its title/player/projectile/guardian/progression files
;   4. writable scalar state, actor arrays, and map workspaces
;
; Everything remains one LWASM unit, so later state labels are valid forward
; references from rendering and flow code.
;==============================================================================

        include "game/data.asm"
        include "game/rendering.asm"
        include "game/flow.asm"
        include "game/state.asm"

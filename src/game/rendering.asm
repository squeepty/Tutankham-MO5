;==============================================================================
; Game-rendering include manifest
;
; Presentation, world drawing, actor compositing, sprite restoration, and HUD
; code stay in their historical source order. The nested files are textual
; includes in the same LWASM translation unit, not linker-level modules.
;==============================================================================

        include "game/rendering/presentation.asm"
        include "game/rendering/world.asm"
        include "game/rendering/actors/player.asm"
        include "game/rendering/restoration/player.asm"
        include "game/rendering/actors/guardian-list.asm"
        include "game/rendering/restoration/guardians.asm"
        include "game/rendering/actors/guardians.asm"
        include "game/rendering/restoration/death-effect.asm"
        include "game/rendering/actors/projectiles.asm"
        include "game/rendering/restoration/projectiles.asm"
        include "game/rendering/hud.asm"

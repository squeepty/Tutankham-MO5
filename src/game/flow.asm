;==============================================================================
; Game-flow include manifest
;
; The fragments remain in their historical source order so this reviewability
; split does not change code placement or the single-translation-unit design.
; Forward references between fragments are resolved by LWASM.
;
; Frame pipeline while playing:
;   1. poll input and dispatch GameState;
;   2. update explorer timers, input, and movement;
;   3. restore/move/redraw projectiles;
;   4. restore/move/redraw guardians and resolve contact;
;   5. composite the explorer over actors that crossed its footprint.
;==============================================================================

        include "game/flow/title-lifecycle.asm"
        include "game/flow/progression-runtime.asm"
        include "game/flow/title-demo.asm"
        include "game/flow/player.asm"
        include "game/flow/progression-score.asm"
        include "game/flow/projectiles.asm"
        include "game/flow/guardian-deactivation.asm"
        include "game/flow/guardians.asm"
        include "game/flow/player-damage.asm"
        include "game/flow/guardian-pool.asm"
        include "game/flow/projectile-pool.asm"
        include "game/flow/map.asm"

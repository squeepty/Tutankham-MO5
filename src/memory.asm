;==============================================================================
; Memory contract
;==============================================================================
;
; $0000-$1F3F  banked MO5 video window (bitmap or color plane)
; $4000-...    code, read-only data, and writable state
; $9800        initial build-time binary guard
; $9FFF down   hardware stack
;
; This scaffold intentionally keeps one assembly unit. The build script reports
; the exact end address and rejects growth into the initial stack guard.
; Code, tables, and state all live in writable RAM after LOADM. That is relied
; upon by CellAddress's one-byte self-modifying column operand. The guard is not
; a linker section boundary; it is a conservative ceiling checked after the raw
; binary is assembled.

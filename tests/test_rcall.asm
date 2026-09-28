; --- Relative CALL (RCALL) Test ---
; Tests PC-relative subroutine calls using RCALL.
;
; RCALL works like BRA but pushes the return address first,
; so you can call nearby functions without loading their address
; into a register. Uses signed 8-bit offset (±127 words).
;
; Test 1: Forward RCALL — call a function defined after the call site
; Test 2: Backward RCALL — call a function defined before the call site
;
; Expected results:
;   sram[30] = 0x0042  (return value from forward call)
;   sram[31] = 0x0055  (return value from backward call)

    LIMM R15, 60            ; init stack pointer
    LIMM R7, 0x1E           ; R7 = 30 (data area)

    ; === Test 1: Forward RCALL ===
    RCALL fwd_func
    STORE R1, [R7 + 0]      ; sram[30] = 0x0042
    BRA test2

fwd_func:
    LIMM R1, 0x42
    RET

test2:
    ; === Test 2: Backward RCALL ===
    RCALL bwd_func
    STORE R2, [R7 + 1]      ; sram[31] = 0x0055
    HALT

bwd_func:
    LIMM R2, 0x55
    RET

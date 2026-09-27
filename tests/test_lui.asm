; --- LUI (Load Upper Immediate) Test ---
; Tests: LUI preserves lower byte, LIMM+LUI builds 16-bit values
;
; Expected results:
;   sram[30] = 0xAB34 (LUI preserves lower byte from LIMM)
;   sram[31] = 0xFFF0 (full I/O address built with LIMM+LUI)
;   sram[32] = 0xFF00 (LUI on zeroed register)

    LIMM R6, 0x1E           ; R6 = 30 (data area)

    ; Test 1: LIMM then LUI preserves lower byte
    LIMM R0, 0x34           ; R0 = 0x0034
    LUI  R0, 0xAB           ; R0 = 0xAB34
    STORE R0, [R6 + 0]      ; sram[30] = 0xAB34

    ; Test 2: Build I/O address 0xFFF0
    LIMM R1, 0xF0           ; R1 = 0x00F0
    LUI  R1, 0xFF           ; R1 = 0xFFF0
    STORE R1, [R6 + 1]      ; sram[31] = 0xFFF0

    ; Test 3: LUI on a zeroed register
    LIMM R2, 0x00           ; R2 = 0x0000
    LUI  R2, 0xFF           ; R2 = 0xFF00
    STORE R2, [R6 + 2]      ; sram[32] = 0xFF00

    HALT

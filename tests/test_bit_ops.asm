; --- Bit Test/Set/Clear/Toggle Test ---
; Tests BTST, BSET, BCLR, and BTGL instructions.
;
; Each operates on Rs with an immediate bit number (0-15):
;   BTST Rs, #bit — test bit, sets Z flag (Z=1 if bit is clear)
;   BSET Rs, #bit — set bit in Rs
;   BCLR Rs, #bit — clear bit in Rs
;   BTGL Rs, #bit — toggle bit in Rs
;
; Expected results:
;   sram[30] = 0x0001  (BTST: bit 3 of 0x08 is set → Z=0 → R2=1)
;   sram[31] = 0x0001  (BTST: bit 2 of 0x08 is clear → Z=1 → R2=1)
;   sram[32] = 0x0009  (BSET: set bit 0 of 0x08 → 0x09)
;   sram[33] = 0x00F7  (BCLR: clear bit 3 of 0xFF → 0xF7)
;   sram[34] = 0x0088  (BTGL: toggle bit 7 of 0x08 → 0x88)

    LIMM R15, 60             ; init stack pointer
    LIMM R7, 0x1E            ; R7 = 30 (result area)

    ; === Test 1: BTST — bit 3 of 0x08 should be set (Z=0) ===
    LIMM R0, 0x08
    BTST R0, 3               ; test bit 3: set → Z=0
    LIMM R2, 0x00
    BEQ skip1                ; skip if Z=1 (bit was clear)
    LIMM R2, 0x01            ; R2 = 1 (bit was set)
skip1:
    STORE R2, [R7 + 0]       ; sram[30] = 0x0001

    ; === Test 2: BTST — bit 2 of 0x08 should be clear (Z=1) ===
    BTST R0, 2               ; test bit 2: clear → Z=1
    LIMM R2, 0x00
    BNE skip2                ; skip if Z=0 (bit was set)
    LIMM R2, 0x01            ; R2 = 1 (bit was clear, Z=1)
skip2:
    STORE R2, [R7 + 1]       ; sram[31] = 0x0001

    ; === Test 3: BSET — set bit 0 of 0x08 → 0x09 ===
    LIMM R3, 0x08
    BSET R3, 0               ; R3 = 0x08 | 0x01 = 0x09
    STORE R3, [R7 + 2]       ; sram[32] = 0x0009

    ; === Test 4: BCLR — clear bit 3 of 0xFF → 0xF7 ===
    LIMM R4, 0xFF
    BCLR R4, 3               ; R4 = 0xFF & ~0x08 = 0xF7
    STORE R4, [R7 + 3]       ; sram[33] = 0x00F7

    ; === Test 5: BTGL — toggle bit 7 of 0x08 → 0x88 ===
    LIMM R5, 0x08
    BTGL R5, 7               ; R5 = 0x08 ^ 0x80 = 0x88
    STORE R5, [R7 + 4]       ; sram[34] = 0x0088

    HALT

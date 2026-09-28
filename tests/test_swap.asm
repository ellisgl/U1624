; --- SWAP Instruction Test ---
; Tests the SWAP Rs, Rt instruction which exchanges two registers.
;
; Expected results:
;   sram[30] = 0x00BB  (R0 after SWAP R0, R1: was 0xAA, now 0xBB)
;   sram[31] = 0x00AA  (R1 after SWAP R0, R1: was 0xBB, now 0xAA)
;   sram[32] = 0x0033  (R2 after SWAP R2, R2: self-swap stays 0x33)

    LIMM R15, 60
    LIMM R7, 0x1E            ; R7 = 30 (result area)

    ; === Test 1: Basic swap ===
    LIMM R0, 0xAA
    LIMM R1, 0xBB
    SWAP R0, R1              ; R0 ↔ R1
    STORE R0, [R7 + 0]       ; sram[30] = 0x00BB
    STORE R1, [R7 + 1]       ; sram[31] = 0x00AA

    ; === Test 2: Self-swap (identity) ===
    LIMM R2, 0x33
    SWAP R2, R2              ; R2 ↔ R2 (no change)
    STORE R2, [R7 + 2]       ; sram[32] = 0x0033

    HALT

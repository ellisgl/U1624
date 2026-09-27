; --- ADC / SBC Test ---
; Tests: add-with-carry and subtract-with-borrow for multi-word arithmetic
;
; ADC: Rd = Rs + Rt + Carry
; SBC: Rd = Rs + ~Rt + Carry  (6502-style)
;        When C=1: Rd = Rs - Rt
;        When C=0: Rd = Rs - Rt - 1
;
; Test 1: 32-bit addition using ADD (low) + ADC (high)
;   0x0001_FFFF + 0x0001_0001 = 0x0003_0000
;   Low:  0xFFFF + 0x0001 = 0x0000, carry out = 1
;   High: 0x0001 + 0x0001 + 1 = 0x0003
;
; Test 2: 32-bit subtraction using SUB (low) + SBC (high)
;   0x0003_0000 - 0x0001_0001 = 0x0001_FFFF
;   Low:  0x0000 - 0x0001 = 0xFFFF, borrow (C=0)
;   High: 0x0003 - 0x0001 - 1(borrow) = 0x0001
;
; Expected results:
;   sram[30] = 0x0000  (low word of 32-bit add)
;   sram[31] = 0x0003  (high word of 32-bit add)
;   sram[32] = 0xFFFF  (low word of 32-bit sub)
;   sram[33] = 0x0001  (high word of 32-bit sub)

    LIMM R7, 0x1E           ; R7 = 30 (data area)

    ; === Test 1: 32-bit ADD ===
    ; Operand A: R1:R0 = 0x0001:0xFFFF
    LIMM R0, 0xFF
    LUI  R0, 0xFF           ; R0 = 0xFFFF (low)
    LIMM R1, 0x01           ; R1 = 0x0001 (high)

    ; Operand B: R3:R2 = 0x0001:0x0001
    LIMM R2, 0x01           ; R2 = 0x0001 (low)
    LIMM R3, 0x01           ; R3 = 0x0001 (high)

    ; Add low words: R4 = R0 + R2 (sets carry on overflow)
    ADD  R4, R0, R2         ; 0xFFFF + 0x0001 = 0x0000, C=1

    ; Add high words with carry: R5 = R1 + R3 + C
    ADC  R5, R1, R3         ; 0x0001 + 0x0001 + 1 = 0x0003

    STORE R4, [R7 + 0]      ; sram[30] = 0x0000
    STORE R5, [R7 + 1]      ; sram[31] = 0x0003

    ; === Test 2: 32-bit SUB ===
    ; Subtract B from result: (R5:R4) - (R3:R2)
    ; 0x0003:0x0000 - 0x0001:0x0001

    ; Sub low words: R4 = R4 - R2 (sets carry = no borrow)
    SUB  R4, R4, R2         ; 0x0000 - 0x0001 = 0xFFFF, C=0 (borrow)

    ; Sub high words with borrow: R5 = R5 - R3 - borrow
    SBC  R5, R5, R3         ; 0x0003 + ~0x0001 + C(0) = 0x0003 + 0xFFFE + 0 = 0x0001, C=1

    STORE R4, [R7 + 2]      ; sram[32] = 0xFFFF
    STORE R5, [R7 + 3]      ; sram[33] = 0x0001

    HALT

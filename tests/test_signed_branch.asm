; --- Signed Branch (BGE / BLT) Test ---
; Tests signed comparison branches, including overflow edge cases.
;
; BGE: branch if N == V  (signed greater-or-equal)
; BLT: branch if N != V  (signed less-than)
;
; Test 1: Simple positive comparison — 10 vs 5 (10 >= 5, signed)
;   SUB sets N=0, V=0 → N==V → BGE taken
;
; Test 2: Negative vs positive — (-1) vs 5
;   0xFFFF - 5 = 0xFFFA → N=1, V=0 → N!=V → BLT taken
;
; Test 3: Overflow edge case — 0x7FFF vs 0xFFFF (-1)
;   0x7FFF (32767) - 0xFFFF (-1) = 0x8000 (-32768, overflows!)
;   Without V flag: N=1 would wrongly suggest 32767 < -1
;   With V flag: N=1, V=1 → N==V → BGE taken (correct: 32767 >= -1)
;
; Expected results:
;   sram[30] = 0x0001  (BGE taken: 10 >= 5)
;   sram[31] = 0x0001  (BLT taken: -1 < 5)
;   sram[32] = 0x0001  (BGE taken: 32767 >= -1, overflow case)

    LIMM R7, 0x1E           ; R7 = 30 (data area)

    ; === Test 1: 10 >= 5 (both positive) ===
    LIMM R0, 10
    LIMM R1, 5
    SUB  R2, R0, R1         ; 10 - 5 = 5, N=0, V=0
    BGE  t1_pass
    LIMM R3, 0x00
    BRA  t2
t1_pass:
    LIMM R3, 0x01
t2:
    STORE R3, [R7 + 0]      ; sram[30] = 0x01

    ; === Test 2: -1 < 5 (negative vs positive) ===
    LIMM R0, 0xFF
    LUI  R0, 0xFF           ; R0 = 0xFFFF (-1)
    LIMM R1, 5
    SUB  R2, R0, R1         ; -1 - 5 = -6 (0xFFFA), N=1, V=0
    BLT  t2_pass
    LIMM R3, 0x00
    BRA  t3
t2_pass:
    LIMM R3, 0x01
t3:
    STORE R3, [R7 + 1]      ; sram[31] = 0x01

    ; === Test 3: 32767 >= -1 (overflow edge case) ===
    LIMM R0, 0xFF
    LUI  R0, 0x7F           ; R0 = 0x7FFF (32767)
    LIMM R1, 0xFF
    LUI  R1, 0xFF           ; R1 = 0xFFFF (-1)
    SUB  R2, R0, R1         ; 32767 - (-1) = 32768 → overflows to 0x8000
                             ; N=1 (looks negative), V=1 (overflow!)
                             ; N==V → BGE should be taken (32767 >= -1)
    BGE  t3_pass
    LIMM R3, 0x00
    BRA  done
t3_pass:
    LIMM R3, 0x01
done:
    STORE R3, [R7 + 2]      ; sram[32] = 0x01
    HALT

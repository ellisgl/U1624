; --- Carry Flag Test ---
; Tests: carry on ADD overflow, SUB borrow semantics, BCS/BCC branches
;
; Carry convention (6502-style):
;   ADD: C=1 when unsigned overflow
;   SUB: C=1 when no borrow (Rs >= Rt), C=0 when borrow (Rs < Rt)
;
; Expected results:
;   sram[30] = 0x0001 (ADD overflow sets carry)
;   sram[31] = 0x0001 (SUB 10-5: no borrow, C=1)
;   sram[32] = 0x0001 (SUB 5-10: borrow, C=0)

    LIMM R6, 0x1E           ; R6 = 30 (data area)

    ; Test 1: ADD carry — 0xFF00 + 0xFF00 overflows, C=1
    LIMM R0, 0x00
    LUI  R0, 0xFF           ; R0 = 0xFF00
    ADD  R1, R0, R0         ; R1 = 0xFE00, C=1 (overflow)
    BCS  add_carry_ok
    LIMM R2, 0x00           ; fail: carry not set
    BRA  test2
add_carry_ok:
    LIMM R2, 0x01           ; pass: carry set

test2:
    STORE R2, [R6 + 0]      ; sram[30] = 0x01

    ; Test 2: SUB no borrow — 10 - 5, C=1 (10 >= 5)
    LIMM R0, 10
    LIMM R1, 5
    SUB  R3, R0, R1         ; R3 = 5, C=1
    BCS  sub_no_borrow
    LIMM R2, 0x00
    BRA  test3
sub_no_borrow:
    LIMM R2, 0x01

test3:
    STORE R2, [R6 + 1]      ; sram[31] = 0x01

    ; Test 3: SUB borrow — 5 - 10, C=0 (5 < 10)
    SUB  R3, R1, R0         ; R3 = 5-10 (underflow), C=0
    BCC  sub_borrow
    LIMM R2, 0x00
    BRA  done
sub_borrow:
    LIMM R2, 0x01

done:
    STORE R2, [R6 + 2]      ; sram[32] = 0x01
    HALT

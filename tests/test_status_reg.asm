; --- Status Register (GETF / SETF) Test ---
; Tests reading and writing the CPU status register as a single value.
;
; Status register bit layout: {12'b0, I, C, N, Z}
;   Bit 0: Z (zero flag)
;   Bit 1: N (negative flag)
;   Bit 2: C (carry flag)
;   Bit 3: I (interrupt enable)
;
; Test 1: Read flags after an operation that sets Z and C
;   0xFFFF + 0x0001 = 0x0000 → Z=1, N=0, C=1
;   GETF should return 0x0005 (C=1, Z=1)
;
; Test 2: Manually set flags via SETF, then verify with branches
;   SETF with value 0x0002 → N=1, Z=0, C=0, I=0
;   BMI should be taken (N=1)
;
; Test 3: Save and restore flags across a computation
;   Set known flags, save with GETF, do unrelated ALU work that
;   changes flags, restore with SETF, verify flags survived
;
; Expected results:
;   sram[30] = 0x0005  (GETF after ADD overflow: C=1, Z=1)
;   sram[31] = 0x0001  (BMI taken after SETF with N=1)
;   sram[32] = 0x0005  (flags restored after save/modify/restore)

    LIMM R7, 0x1E           ; R7 = 30 (data area)

    ; === Test 1: GETF after ADD overflow ===
    LIMM R0, 0xFF
    LUI  R0, 0xFF           ; R0 = 0xFFFF
    LIMM R1, 0x01           ; R1 = 0x0001
    ADD  R2, R0, R1         ; R2 = 0x0000, Z=1, N=0, C=1
    GETF R3                 ; R3 = status register = 0x0005
    STORE R3, [R7 + 0]      ; sram[30] = 0x0005

    ; === Test 2: SETF then branch on flags ===
    LIMM R4, 0x02           ; R4 = 0x0002 (N=1 only)
    SETF R4                 ; Set N=1, Z=0, C=0, I=0
    BMI  setf_ok            ; Should branch (N=1)
    LIMM R5, 0x00           ; fail path
    BRA  test3
setf_ok:
    LIMM R5, 0x01           ; pass: N flag was set by SETF
test3:
    STORE R5, [R7 + 1]      ; sram[31] = 0x0001

    ; === Test 3: Save/restore flags across computation ===
    ; First create known flags: ADD overflow → Z=1, C=1
    ADD  R2, R0, R1         ; Z=1, N=0, C=1 again
    GETF R6                 ; R6 = saved flags (0x0005)

    ; Now do ALU work that changes flags
    LIMM R0, 0x05
    LIMM R1, 0x03
    SUB  R2, R0, R1         ; R2 = 2, Z=0, N=0, C=1 (different flags)

    ; Restore the saved flags
    SETF R6                 ; Restore Z=1, C=1 from earlier
    GETF R3                 ; Read them back
    STORE R3, [R7 + 2]      ; sram[32] = 0x0005

    HALT

; --- MPU / Supervisor Mode Test ---
;
; Tests TRAP, supervisor/user mode, and MPU protection faults.
;
; MPU Region 0: addr 10-57, user R/W
;   Covers user code (~44-49) and result area (53-57).
;   Write to addr 58 (outside region) triggers fault.
;
; Expected results:
;   sram[53] = 0x0020  (GETF in supervisor: S bit = 0x20)
;   sram[54] = 0x0001  (TRAP handler ran)
;   sram[55] = 0x00AA  (user write to allowed region)
;   sram[56] = 0x0001  (fault handler ran)
;   sram[57] = 0x0020  (GETF in fault handler: S bit)

    ; --- Vector table ---
    BRA main            ; 0
    NOP                 ; 1
    NOP                 ; 2
    NOP                 ; 3

trap_handler:           ; 4 — TRAP vector
    LIMM R5, 1          ; 4
    LIMM R6, 53         ; 5
    STORE R5, [R6 + 1]  ; 6: sram[54] = 1
    IRET                 ; 7

    NOP                 ; 8 — IRQ vector (unused)
    NOP                 ; 9
    NOP                 ; 10
    NOP                 ; 11

fault_handler:          ; 12 (0x0C) — FAULT vector
    LIMM R5, 1          ; 12
    LIMM R6, 53         ; 13
    STORE R5, [R6 + 3]  ; 14: sram[56] = 1
    GETF R5              ; 15
    STORE R5, [R6 + 4]  ; 16: sram[57] = flags
    HALT                 ; 17

main:                   ; 18
    LIMM R15, 63         ; 18: SP = 63 (top of SRAM)
    LIMM R6, 53          ; 19: result base

    ; === Test 1: Verify supervisor mode ===
    GETF R0              ; 20
    STORE R0, [R6 + 0]   ; 21: sram[53] = 0x20

    ; === Test 2: TRAP ===
    TRAP 0               ; 22

    ; === Configure MPU ===
    ; Region 0: base=10, limit=57, user R/W
    LIMM R0, 0xFC        ; 23
    LUI  R0, 0xFF        ; 24: R0 = 0xFFFC
    LIMM R1, 0           ; 25
    STORE R1, [R0 + 0]   ; 26: select region 0, MPU off
    LIMM R1, 10          ; 27
    STORE R1, [R0 + 1]   ; 28: base = 10
    LIMM R1, 57          ; 29
    STORE R1, [R0 + 2]   ; 30: limit = 57
    LIMM R1, 0x83        ; 31
    STORE R1, [R0 + 3]   ; 32: perms = enabled | user R/W

    ; Enable MPU
    LIMM R1, 0x00        ; 33
    LUI  R1, 0x80        ; 34: R1 = 0x8000
    STORE R1, [R0 + 0]   ; 35: MPU enabled

    ; === Enter user mode via fake IRET ===
    LIMM R1, user_code   ; 36
    PUSH R1              ; 37: push return addr
    GETF R1              ; 38
    LIMM R3, 0xDF        ; 39
    LUI  R3, 0xFF        ; 40: R3 = 0xFFDF
    AND  R1, R1, R3      ; 41: clear S bit
    PUSH R1              ; 42: push flags (user mode)
    IRET                  ; 43: "return" to user_code in user mode

user_code:              ; 44
    LIMM R6, 53          ; 44
    LIMM R5, 0xAA        ; 45
    STORE R5, [R6 + 2]   ; 46: sram[55] = 0xAA (allowed)

    ; Trigger MPU fault: write to addr 58 (outside region 0)
    LIMM R8, 58          ; 47
    LIMM R9, 0xFF        ; 48
    STORE R9, [R8 + 0]   ; 49: FAULT

    HALT                 ; 50: never reached

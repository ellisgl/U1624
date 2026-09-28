; --- Wait State Test ---
; Tests CPU behavior with slow memory regions.
; In the testbench, SRAM addresses >= 50 insert 1 wait state per
; access (2 total cycles instead of 1). The data bus returns 0xDEAD
; during the wait, so if the CPU samples too early, the test fails.
;
; Test 1: Store to slow memory, load back
; Test 2: Back-to-back accesses to slow memory
; Test 3: Verify computation with slow-sourced operands
;
; Expected results:
;   sram[30] = 0x1234  (round-trip through slow addr 50)
;   sram[31] = 0x5678  (round-trip through slow addr 51)
;   sram[32] = 0x68AC  (0x1234 + 0x5678, computed from slow-loaded values)

    LIMM R15, 48             ; init SP below slow region
    LIMM R7, 0x1E            ; R7 = 30 (result area)
    LIMM R8, 0x32            ; R8 = 50 (slow memory base)

    ; === Test 1: Single store/load round-trip ===
    LIMM R0, 0x34
    LUI  R0, 0x12            ; R0 = 0x1234
    STORE R0, [R8 + 0]       ; store to slow addr 50
    LOAD  R1, [R8 + 0]       ; load from slow addr 50
    STORE R1, [R7 + 0]       ; sram[30] = 0x1234

    ; === Test 2: Back-to-back slow accesses ===
    LIMM R0, 0x78
    LUI  R0, 0x56            ; R0 = 0x5678
    STORE R0, [R8 + 1]       ; store to slow addr 51
    LOAD  R2, [R8 + 1]       ; load from slow addr 51
    STORE R2, [R7 + 1]       ; sram[31] = 0x5678

    ; === Test 3: ALU with slow-loaded operands ===
    LOAD  R3, [R8 + 0]       ; R3 = sram[50] = 0x1234 (slow load)
    LOAD  R4, [R8 + 1]       ; R4 = sram[51] = 0x5678 (slow load)
    ADD   R5, R3, R4         ; R5 = 0x1234 + 0x5678 = 0x68AC
    STORE R5, [R7 + 2]       ; sram[32] = 0x68AC

    HALT

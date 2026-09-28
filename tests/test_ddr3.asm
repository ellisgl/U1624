; --- DDR3 Memory Path Test ---
;
; Tests writing to DDR3-mapped addresses (64+) and reading back.
; In the testbench, addresses >= 64 are routed through the full
; DDR3 memory path (word_line_adapter → CDC bridge → UI adapter →
; mock DDR3 controller) while addresses 0-63 remain in fast SRAM.
;
; Expected results:
;   sram[30] = 0xBEEF  (readback from DDR3 addr 64)
;   sram[31] = 0xCAFE  (readback from DDR3 addr 65)
;   sram[32] = 0x1234  (readback from DDR3 addr 66)
;   sram[33] = 0x0042  (SRAM write, proves no interference)
;   sram[34] = 0xBEEF  (second readback from DDR3 addr 64)

    ; === Write three values to DDR3 ===
    LIMM R0, 0xEF
    LUI  R0, 0xBE       ; R0 = 0xBEEF
    LIMM R1, 64          ; R1 = DDR3 base address
    STORE R0, [R1 + 0]   ; DDR3[64] = 0xBEEF

    LIMM R2, 0xFE
    LUI  R2, 0xCA        ; R2 = 0xCAFE
    STORE R2, [R1 + 1]   ; DDR3[65] = 0xCAFE

    LIMM R3, 0x34
    LUI  R3, 0x12        ; R3 = 0x1234
    STORE R3, [R1 + 2]   ; DDR3[66] = 0x1234

    ; === Read back from DDR3 ===
    LOAD R4, [R1 + 0]    ; R4 = DDR3[64]
    LOAD R5, [R1 + 1]    ; R5 = DDR3[65]
    LOAD R6, [R1 + 2]    ; R6 = DDR3[66]

    ; === Store results in SRAM for verification ===
    LIMM R7, 30
    STORE R4, [R7 + 0]   ; sram[30] = 0xBEEF
    STORE R5, [R7 + 1]   ; sram[31] = 0xCAFE
    STORE R6, [R7 + 2]   ; sram[32] = 0x1234

    ; === Verify SRAM is independent ===
    LIMM R0, 0x42
    STORE R0, [R7 + 3]   ; sram[33] = 0x0042

    ; === Re-read DDR3 to verify persistence ===
    LOAD R0, [R1 + 0]    ; R0 = DDR3[64] again
    STORE R0, [R7 + 4]   ; sram[34] = 0xBEEF

    HALT

; --- Test MOV, NOT, NEG, ROL, ROR ---
LIMM  R6, 0x1E         ; R6 = 30 (data area)

; Test MOV: copy R value
LIMM  R0, 0x42         ; R0 = 0x0042
MOV   R1, R0           ; R1 = R0 = 0x0042
STORE R1, [R6 + 0]     ; sram[30] = 0x0042

; Test NOT: bitwise complement
LIMM  R0, 0xFF         ; R0 = 0x00FF
NOT   R2, R0           ; R2 = ~0x00FF = 0xFF00
STORE R2, [R6 + 1]     ; sram[31] = 0xFF00

; Test NEG: two's complement negate
LIMM  R0, 1            ; R0 = 1
NEG   R3, R0           ; R3 = -1 = 0xFFFF
STORE R3, [R6 + 2]     ; sram[32] = 0xFFFF

; Test ROL: rotate left by 4
LIMM  R0, 0xF1         ; R0 = 0x00F1
LIMM  R7, 4            ; R7 = shift amount
ROL   R4, R0, R7       ; R4 = 0x00F1 ROL 4 = 0x0F10
STORE R4, [R6 + 3]     ; sram[33] = 0x0F10

; Test ROR: rotate right by 4
LIMM  R0, 0x1F         ; R0 = 0x001F
ROR   R5, R0, R7       ; R5 = 0x001F ROR 4 = 0xF001
STORE R5, [R6 + 4]     ; sram[34] = 0xF001

HALT

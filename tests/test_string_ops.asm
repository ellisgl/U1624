; --- Block Move / String Operations Test ---
; Tests MOVSW, LODSW, and STOSW instructions.
;
;   MOVSW Rs, Rt — mem[Rt] ← mem[Rs], Rs++, Rt++
;   LODSW Rs, Rt — Rs ← mem[Rt], Rt++
;   STOSW Rs, Rt — mem[Rs] ← Rt, Rs++
;
; Expected results:
;   sram[30] = 0x1111  (MOVSW copied word 0)
;   sram[31] = 0x2222  (MOVSW copied word 1)
;   sram[32] = 0x3333  (MOVSW copied word 2)
;   sram[33] = 0x1111  (LODSW loaded first word from copy)
;   sram[34] = 0x00BB  (STOSW stored value, read back)

    BRA start

src_data:
    .word 0x1111, 0x2222, 0x3333

start:
    LIMM R15, 60
    LIMM R7, 0x1E            ; R7 = 30 (result area)

    ; === Test 1: MOVSW loop — copy 3 words from src_data to addr 40 ===
    LIMM R0, src_data         ; R0 = source pointer (addr 1)
    LIMM R1, 40               ; R1 = destination pointer
    LIMM R2, 3                ; R2 = count
    LIMM R3, 1                ; R3 = 1 (for decrement)

copy_loop:
    MOVSW R0, R1              ; mem[R1] ← mem[R0], R0++, R1++
    SUB R2, R2, R3            ; R2--
    BNE copy_loop

    ; Verify copied data
    LIMM R8, 40               ; R8 = destination base
    LOAD R5, [R8 + 0]
    STORE R5, [R7 + 0]        ; sram[30] = 0x1111
    LOAD R5, [R8 + 1]
    STORE R5, [R7 + 1]        ; sram[31] = 0x2222
    LOAD R5, [R8 + 2]
    STORE R5, [R7 + 2]        ; sram[32] = 0x3333

    ; === Test 2: LODSW — load with auto-increment ===
    LIMM R8, 40               ; R8 = pointer to copied data
    LODSW R5, R8              ; R5 = mem[40] = 0x1111, R8 = 41
    STORE R5, [R7 + 3]        ; sram[33] = 0x1111

    ; === Test 3: STOSW — store and advance ===
    LIMM R8, 45               ; R8 = destination pointer
    LIMM R9, 0xBB
    STOSW R8, R9              ; mem[45] = 0xBB, R8 = 46
    LIMM R10, 45
    LOAD R5, [R10 + 0]        ; read back from addr 45
    STORE R5, [R7 + 4]        ; sram[34] = 0x00BB

    HALT

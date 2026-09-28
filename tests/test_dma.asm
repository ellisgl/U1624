; --- DMA Controller Test ---
; Tests memory-to-memory block transfer via the DMA controller.
;
; DMA Registers (memory-mapped):
;   0xFFF8: Source address (R/W)
;   0xFFF9: Destination address (R/W)
;   0xFFFA: Transfer length in words (R/W)
;   0xFFFB: Control/Status (R/W)
;     Write bit 0: Start transfer
;     Write bit 1: Interrupt enable
;     Read  bit 0: Busy
;     Read  bit 2: Done
;
; Test: Copy 3 words from addresses 1-3 to addresses 40-42.
; Source data is placed inline using .word directives.
;
; Expected results:
;   sram[30] = 0x1234  (copied word 0)
;   sram[31] = 0x5678  (copied word 1)
;   sram[32] = 0xABCD  (copied word 2)
;   sram[33] = 0x0004  (DMA status: done=1, int_en=0, busy=0)

    BRA start                ; skip past inline data

src_data:
    .word 0x1234, 0x5678, 0xABCD

start:
    LIMM R15, 60             ; init stack pointer

    ; --- Program DMA: copy 3 words from src_data to address 40 ---
    LIMM R3, 0xF8
    LUI  R3, 0xFF            ; R3 = 0xFFF8 (DMA base)

    LIMM R4, src_data        ; source = address of src_data (1)
    STORE R4, [R3 + 0]       ; DMA src = 1

    LIMM R4, 0x28            ; destination = 40
    STORE R4, [R3 + 1]       ; DMA dst = 40

    LIMM R4, 0x03            ; length = 3 words
    STORE R4, [R3 + 2]       ; DMA len = 3

    LIMM R4, 0x01            ; control: start=1
    STORE R4, [R3 + 3]       ; DMA start! CPU freezes during transfer.

    ; --- CPU resumes here after DMA completes ---

    ; Verify destination data matches source
    LIMM R8, 0x28             ; R8 = 40 (destination base)
    LIMM R9, 0x1E             ; R9 = 30 (result area)

    LOAD R5, [R8 + 0]         ; sram[40] should be 0x1234
    STORE R5, [R9 + 0]        ; sram[30]

    LOAD R5, [R8 + 1]         ; sram[41] should be 0x5678
    STORE R5, [R9 + 1]        ; sram[31]

    LOAD R5, [R8 + 2]         ; sram[42] should be 0xABCD
    STORE R5, [R9 + 2]        ; sram[32]

    ; Read DMA status register
    LOAD R5, [R3 + 3]         ; should be 0x0004 (done=1)
    STORE R5, [R9 + 3]        ; sram[33]

    HALT

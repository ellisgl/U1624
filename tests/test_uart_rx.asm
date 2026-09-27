; --- UART RX Test ---
; Polls for two received characters and stores them to memory.
;
; I/O registers:
;   0xFFF1: UART Status (bit 0: TX ready, bit 1: RX data available)
;   0xFFF6: UART RX Data (read: current byte; write: acknowledge/pop)
;
; Expected results (testbench pre-loads 'H' and 'i'):
;   sram[30] = 0x0048 ('H')
;   sram[31] = 0x0069 ('i')

    LIMM R15, 0x3C          ; SP = 60
    LIMM R6, 0x1E           ; R6 = 30 (data area)

    ; Build I/O addresses
    LIMM R3, 0xF1
    LUI  R3, 0xFF           ; R3 = 0xFFF1 (status register)
    LIMM R4, 0xF6
    LUI  R4, 0xFF           ; R4 = 0xFFF6 (RX data register)
    LIMM R7, 0x02           ; bit 1 mask (RX available)

    ; --- Read first character ---
poll1:
    LOAD R0, [R3 + 0]       ; read status register
    AND  R0, R0, R7         ; isolate RX available bit
    BEQ  poll1              ; loop until data available

    LOAD R0, [R4 + 0]       ; read received byte
    STORE R0, [R6 + 0]      ; sram[30] = first char

    LIMM R5, 0x01
    STORE R5, [R4 + 0]      ; acknowledge (pop FIFO)

    ; --- Read second character ---
poll2:
    LOAD R0, [R3 + 0]       ; read status register
    AND  R0, R0, R7         ; isolate RX available bit
    BEQ  poll2              ; loop until data available

    LOAD R0, [R4 + 0]       ; read received byte
    STORE R0, [R6 + 1]      ; sram[31] = second char
    STORE R5, [R4 + 0]      ; acknowledge (pop FIFO)

    HALT

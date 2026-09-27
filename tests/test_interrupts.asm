; --- Interrupt Test (Timer-driven) ---
; Tests: timer peripheral, SEI, CLI, IRET, flag preservation
;
; Timer I/O registers:
;   0xFFF2: Reload value (R/W)
;   0xFFF3: Current count (R)
;   0xFFF4: Control (R/W) — bit 0: enable, bit 1: auto-reload
;   0xFFF5: Status (R: pending; W: acknowledge)
;
; Expected results:
;   sram[30] = 0x0055 (main program continued after interrupt)
;   sram[31] = 0x0042 (handler set R1)
;   sram[32] = 0x0001 (Z flag preserved across interrupt)

    BRA start               ; 0: jump past vector area
    NOP                     ; 1: padding
    NOP                     ; 2
    NOP                     ; 3
    NOP                     ; 4
    NOP                     ; 5
    NOP                     ; 6
    NOP                     ; 7

int_handler:                ; 8: interrupt vector entry point
    ; Acknowledge timer interrupt
    LIMM R5, 0xF5
    LUI  R5, 0xFF           ; R5 = 0xFFF5 (timer status)
    LIMM R4, 0x01
    STORE R4, [R5 + 0]      ; write to clear pending flag

    LIMM R1, 0x42           ; R1 = 0x42 (proof handler executed)
    ADDI R1, R1, 0          ; modify flags: sets Z=0 (R1 != 0)
    IRET                    ; restore flags and return

start:
    LIMM R15, 0x3C          ; SP = 60
    LIMM R6, 0x1E           ; R6 = 30 (data area base)
    LIMM R1, 0x00           ; R1 = 0 (will be set by handler)

    ; Set up timer base address
    LIMM R3, 0xF2
    LUI  R3, 0xFF           ; R3 = 0xFFF2 (timer reload register)

    ; Set timer reload value = 10
    LIMM R4, 10
    STORE R4, [R3 + 0]      ; write reload value

    ; Enable timer (one-shot mode)
    LIMM R4, 0x01           ; bit 0 = enable, bit 1 = 0 (no auto-reload)
    STORE R4, [R3 + 2]      ; write to control register (0xFFF4)

    ; Set Z flag before interrupt to test preservation
    LIMM R0, 0
    CMPI R0, 0              ; Z=1, N=0

    SEI                     ; enable interrupts
    ; Timer will count down and fire interrupt during NOPs
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP

    ; After IRET, execution continues here
    LIMM R0, 0x55           ; R0 = 0x55 (proof main continued)

    ; Test flag preservation: Z should still be 1 from before interrupt
    BEQ flags_ok
    LIMM R2, 0xFF           ; flags broken
    BRA done
flags_ok:
    LIMM R2, 0x01           ; flags preserved correctly
done:
    STORE R0, [R6 + 0]      ; sram[30] = 0x55
    STORE R1, [R6 + 1]      ; sram[31] = 0x42
    STORE R2, [R6 + 2]      ; sram[32] = 0x01
    HALT

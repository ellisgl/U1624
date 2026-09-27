; --- Interrupt Test Program ---
; Tests: SEI, CLI, IRET, interrupt entry/exit, flag preservation
;
; Memory layout:
;   Address 0x0000: BRA to main (skip past vector)
;   Address 0x0001-0x0007: NOP padding
;   Address 0x0008: Interrupt handler entry (fixed vector)
;   Address 0x000C+: Main program
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
    LIMM R1, 0x42           ; R1 = 0x42 (proof handler executed)
    ADDI R1, R1, 0          ; touch flags: sets Z=0 (R1 != 0)
    IRET                    ; restore flags and return

start:
    LIMM R15, 0x3C          ; SP = 60
    LIMM R6, 0x1E           ; R6 = 30 (data area base)
    LIMM R1, 0x00           ; R1 = 0 (will be set by handler)

    ; Set Z flag before interrupt to test preservation
    LIMM R0, 0
    CMPI R0, 0              ; Z=1, N=0

    SEI                     ; enable interrupts
    ; Testbench fires IRQ here — handler will modify flags
    NOP
    NOP
    NOP

    ; After IRET, execution continues here
    LIMM R0, 0x55           ; R0 = 0x55 (proof main continued)

    ; Test flag preservation: Z should still be 1
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

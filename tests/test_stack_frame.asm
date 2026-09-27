; --- Stack Frame (ENTER / LEAVE) Test ---
; Tests hardware stack-frame setup and teardown.
;
; ENTER n: Push R14, R14 ← SP, SP ← SP − n  (allocate frame)
; LEAVE:   SP ← R14 + 1, Pop R14             (deallocate frame)
;
; R14 is the dedicated frame pointer (FP). R15 is the stack pointer (SP).
;
; Test 1: Basic ENTER/LEAVE
;   SP=60, R14=0xAA. ENTER 3 → R14=59 (frame base), SP=56.
;   LEAVE → R14=0xAA restored, SP=60 restored.
;
; Test 2: ENTER/LEAVE inside a CALL/RET
;   Calls a function that uses ENTER 1 / LEAVE / RET.
;   Verifies the return address survives the frame operations.
;
; Expected results:
;   sram[30] = 0x003B  (R14 = 59 after ENTER, frame pointer)
;   sram[31] = 0x0038  (SP = 56 after ENTER 3)
;   sram[32] = 0x00AA  (R14 restored after LEAVE)
;   sram[33] = 0x003C  (SP = 60 restored after LEAVE)
;   sram[34] = 0x0055  (return value from function using ENTER/LEAVE)

    LIMM R15, 60            ; init stack pointer
    LIMM R7, 0x1E           ; R7 = 30 (data area base)

    ; === Test 1: Basic ENTER / LEAVE ===
    LIMM R14, 0xAA          ; R14 = 0xAA (old FP, will be saved/restored)
    ENTER 3                  ; push R14, R14=59, SP=56
    STORE R14, [R7 + 0]     ; sram[30] = R14 = 59 (0x003B)
    STORE R15, [R7 + 1]     ; sram[31] = SP = 56 (0x0038)
    LEAVE                    ; SP=60, R14=0xAA
    STORE R14, [R7 + 2]     ; sram[32] = R14 = 0x00AA
    STORE R15, [R7 + 3]     ; sram[33] = SP = 60 (0x003C)

    ; === Test 2: ENTER/LEAVE with CALL/RET ===
    LIMM R6, my_func
    CALL R6
    STORE R1, [R7 + 4]      ; sram[34] = 0x0055

    HALT

my_func:
    ENTER 1                  ; set up frame with 1 local word
    LIMM R1, 0x55           ; prepare return value
    LEAVE                    ; tear down frame
    RET

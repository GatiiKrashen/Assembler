; ============================================================
; Sample assembly program: compute sum of 1..N
; and demonstrate basic instructions
; ============================================================

        ; --- Data section ---
COUNT:  DB  10          ; N = 10
RESULT: DW  0           ; store result here

        ; --- Code section ---
START:
        MOV  AX, 0      ; AX = 0  (accumulator / sum)
        MOV  CX, 10     ; CX = N  (loop counter)

LOOP:
        ADD  AX, CX     ; sum += CX
        SUB  CX, 1      ; CX--
        CMP  CX, 0      ; compare CX with 0
        JNZ  LOOP       ; if CX != 0 goto LOOP

        OUT  AX         ; output result (should be 55)
        HLT             ; halt

; ============================================================
; Subroutine: multiply AX * BX -> AX (repeated addition)
; ============================================================
MULTIPLY:
        PUSH CX
        MOV  CX, BX     ; CX = multiplier
        MOV  BX, AX     ; BX = multiplicand
        MOV  AX, 0      ; clear accumulator
MUL_LOOP:
        ADD  AX, BX     ; AX += BX
        SUB  CX, 1      ; CX--
        CMP  CX, 0
        JNZ  MUL_LOOP
        POP  CX
        RET

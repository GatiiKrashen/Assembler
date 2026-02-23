.386

RomSize      EQU   4096

; Порты 
DigitSelPort1    EQU   2
DigitSelPort2    EQU   3
DigitSelPort3    EQU   4
SegPort          EQU   1
InPort           EQU   0

Data SEGMENT use16 AT 0h

Data ENDS

Stk SEGMENT use16 AT 900h
    dw 32 dup (?)
StkTop Label Word
Stk ENDS


InitData SEGMENT use16
InitDataStart:
;Здесь размещается описание неизменяемых данных, которые будут храниться в ПЗУ



InitDataEnd:
InitData ENDS

Code SEGMENT use16
ASSUME cs:Code, ds:Data, es:Data, ss:Stk

; Таблица графических образов
digits db 3Fh, 0Ch, 76h, 05Eh, 4Dh, 5Bh, 7Bh, 0Eh, 7Fh, 5Fh

; Инициализация перемеенных
Init PROC
           
    ret
Init ENDP

HandleButtons PROC

    ret
HandleButtons ENDP

UpdateStats PROC

    ret
UpdateStats ENDP

Display PROC
    mov AL, 80h
    out DigitSelPort3, AL

    ret
Display ENDP


; ОСНОВНОЙ ЦИКЛ 
Start:
    mov ax, Data
    mov ds, ax
    mov es, ax
    mov ax, Stk
    mov ss, ax
    lea sp, StkTop

    call Init
    
MainLoop:
    call HandleButtons
    call UpdateStats
    call Display

    jmp MainLoop
    
org RomSize-16-((InitDataEnd-InitDataStart+15) AND 0FFF0h)
ASSUME cs:NOTHING
jmp Far Ptr Start
Code ENDS
END Start

.386

RomSize          EQU   4096

; Порты
DigitSelPort1    EQU   2
DigitSelPort2    EQU   3
DigitSelPort3    EQU   4
SegPort          EQU   1
InPort           EQU   0

; Прерывание таймера (INT 8 = IRQ0 PIT channel 0)
TimerIntNo       EQU   8h

; Системные константы
TicksPerSec      EQU   50       ; тиков в секунду
HoursPerDay      EQU   24       ; часов в сутках
DispDigits       EQU   6        ; количество позиций дисплея

; Режимы отображения
ModeTime         EQU   0        ; текущее время HH:MM:SS
ModeSteps        EQU   1        ; шаги текущего часа
ModeCalories     EQU   2        ; калории текущего часа
ModeView         EQU   3        ; суммарные данные за сутки (все 24 часа)
NumModes         EQU   4

; Сегмент таблицы прерываний (физический адрес 0)
IntTable SEGMENT use16 AT 0
    org    TimerIntNo * 4
TimerIntPtr  dd ?
IntTable ENDS

; Сегмент данных по параграфу 40h (физический адрес 0x400, выше IVT)
Data SEGMENT use16 AT 40h

TickCount        db ?                      ; счётчик тиков (0..TicksPerSec-1)
Seconds          db ?                      ; секунды (0-59)
Minutes          db ?                      ; минуты  (0-59)
Hours            db ?                      ; часы    (0-23)

StepsPerHour     db HoursPerDay dup (?)    ; шаги за каждый час
CaloriesPerHour  db HoursPerDay dup (?)    ; калории за каждый час

LastBttnImg      db ?                      ; предыдущий образ кнопок
Mode             db ?                      ; текущий режим отображения
DispBuf          db DispDigits dup (?)     ; буфер индексов цифр (0-9, 10=пусто)

Data ENDS

Stk SEGMENT use16 AT 900h
    dw 32 dup (?)
StkTop Label Word
Stk ENDS


InitData SEGMENT use16
InitDataStart:
; Здесь размещаются описания инициализируемых переменных, которые надо хранить в ROM



InitDataEnd:
InitData ENDS

Code SEGMENT use16
ASSUME cs:Code, ds:Data, es:Data, ss:Stk

; Образы десятичных символов: "0".."9" + пустой (индекс 10)
digits db 3Fh, 0Ch, 76h, 05Eh, 4Dh, 5Bh, 7Bh, 0Eh, 7Fh, 5Fh, 00h

; ============================================================
; TimerInt - обработчик прерывания системного таймера (INT 8)
; Инкрементирует счётчик тиков и обновляет секунды/минуты/часы.
; ============================================================
TimerInt PROC FAR
    push ax
    push si
    push ds

    mov  ax, Data
    mov  ds, ax

    inc  TickCount
    cmp  TickCount, TicksPerSec
    jb   TimerIntDone

    mov  TickCount, 0
    inc  Seconds
    cmp  Seconds, 60
    jb   TimerIntDone

    mov  Seconds, 0
    inc  Minutes
    cmp  Minutes, 60
    jb   TimerIntDone

    mov  Minutes, 0
    mov  al, Hours
    inc  al
    cmp  al, HoursPerDay
    jb   TimerHourOk
    xor  al, al
TimerHourOk:
    mov  Hours, al

TimerIntDone:
    pop  ds
    pop  si
    pop  ax
    iret
TimerInt ENDP

; ============================================================
; ResetAll - сброс всех переменных в начальное состояние
; ============================================================
ResetAll PROC
    push ax
    push cx
    push di

    mov  TickCount, 0
    mov  Seconds,   0
    mov  Minutes,   0
    mov  Hours,     0

    mov  di, OFFSET StepsPerHour
    mov  cx, HoursPerDay
    xor  al, al
    rep  stosb

    mov  di, OFFSET CaloriesPerHour
    mov  cx, HoursPerDay
    xor  al, al
    rep  stosb

    ; Исправление бага #2: LastBttnImg должен быть 0FFh
    ; (все кнопки отпущены - порт читает высокий уровень)
    mov  LastBttnImg, 0FFh
    mov  Mode, ModeTime

    mov  di, OFFSET DispBuf
    mov  cx, DispDigits
    xor  al, al
    rep  stosb

    pop  di
    pop  cx
    pop  ax
    ret
ResetAll ENDP

; ============================================================
; BttnInput - чтение порта кнопок, детекция новых нажатий
; Возвращает: al = маска только что нажатых кнопок
; ============================================================
BttnInput PROC
    push bx

    in   al, InPort          ; читаем порт кнопок (активный низкий уровень)

    ; Исправление бага #3: сначала OR al, 80h (фиксируем бит 7),
    ; затем сохраняем в ah - маска бита 7 всегда одинакова.
    ; Прежде сохранение происходило ДО OR, что делало маску бита 7
    ; непоследовательной между текущим чтением и сохранённым образом.
    or   al, 80h             ; фиксируем бит 7 в текущем значении
    mov  ah, al              ; сохраняем нормализованное состояние для след. вызова
    xor  al, LastBttnImg     ; выделяем изменившиеся биты
    and  al, LastBttnImg     ; оставляем только переходы 1->0 (нажатие, акт. низкий)
    mov  LastBttnImg, ah     ; обновляем сохранённый образ

    pop  bx
    ret
BttnInput ENDP

; ============================================================
; IndOutput - вывод одной цифры на семисегментный индикатор
; Вход: bl = индекс цифры (0-9; 10 = пусто)
;       bh = маска выбора позиции (битовый паттерн для порта)
;       dx = номер порта выбора индикатора
; ============================================================
IndOutput PROC
    push ax
    push bx

    lea  bx, digits
    mov  al, bl              ; индекс цифры
    xlat digits              ; преобразуем в семисегментный код
    out  SegPort, al         ; выводим код сегментов

    mov  al, bh
    out  dx, al              ; Исправление бага #4 (часть 1): включаем индикатор

    ; Исправление бага #4: три NOP дают индикатору время засветиться
    ; перед выключением - без задержки сегменты невидимы или очень тусклые.
    nop
    nop
    nop

    mov  al, 0FFh
    out  dx, al              ; Исправление бага #4 (часть 2): выключаем индикатор

    pop  bx
    pop  ax
    ret
IndOutput ENDP

; ============================================================
; PrepareDispBuf - заполнить DispBuf индексами цифр согласно
;                 текущему режиму отображения
; ============================================================
PrepareDispBuf PROC
    push ax
    push bx
    push cx
    push dx
    push si

    mov  al, Mode
    cmp  al, ModeView
    je   PDB_View
    cmp  al, ModeTime
    je   PDB_Time
    cmp  al, ModeSteps
    je   PDB_Steps
    ; else ModeCalories

PDB_Calories:
    ; Позиции 0-2 гасим, позиции 3-5 - калории текущего часа
    xor  ah, ah
    mov  al, Hours
    mov  si, OFFSET CaloriesPerHour
    add  si, ax
    mov  al, byte ptr [si]
    xor  ah, ah
    xor  dx, dx
    mov  bl, 100
    div  bl
    mov  DispBuf[0], 10
    mov  DispBuf[1], 10
    mov  DispBuf[2], 10
    mov  DispBuf[3], al      ; сотни
    mov  al, ah
    xor  ah, ah
    mov  bl, 10
    div  bl
    mov  DispBuf[4], al      ; десятки
    mov  DispBuf[5], ah      ; единицы
    jmp  PDB_Done

PDB_View:
    ; Исправление бага #5: суммируем шаги И калории за ВСЕ 24 часа дня.
    ; Ранее использовался только слот текущего часа (Hours), поэтому
    ; режим просмотра показывал то же, что и режимы ModeSteps/ModeCalories,
    ; а не суммарные данные за сутки.

    ; -- Сумма шагов за 24 часа --
    xor  ax, ax
    mov  si, OFFSET StepsPerHour
    mov  cx, HoursPerDay
PDB_View_StepsLoop:
    xor  bx, bx
    mov  bl, byte ptr [si]
    add  ax, bx
    inc  si
    loop PDB_View_StepsLoop
    ; ограничиваем отображение 999
    cmp  ax, 999
    jbe  PDB_View_StoreSteps
    mov  ax, 999
PDB_View_StoreSteps:
    xor  dx, dx
    mov  bx, 100
    div  bx
    mov  DispBuf[0], al      ; сотни суточных шагов
    mov  ax, dx
    xor  dx, dx
    mov  bx, 10
    div  bx
    mov  DispBuf[1], al      ; десятки суточных шагов
    mov  DispBuf[2], dl      ; единицы суточных шагов

    ; -- Сумма калорий за 24 часа --
    xor  ax, ax
    mov  si, OFFSET CaloriesPerHour
    mov  cx, HoursPerDay
PDB_View_CalLoop:
    xor  bx, bx
    mov  bl, byte ptr [si]
    add  ax, bx
    inc  si
    loop PDB_View_CalLoop
    ; ограничиваем отображение 999
    cmp  ax, 999
    jbe  PDB_View_StoreCal
    mov  ax, 999
PDB_View_StoreCal:
    xor  dx, dx
    mov  bx, 100
    div  bx
    mov  DispBuf[3], al      ; сотни суточных калорий
    mov  ax, dx
    xor  dx, dx
    mov  bx, 10
    div  bx
    mov  DispBuf[4], al      ; десятки суточных калорий
    mov  DispBuf[5], dl      ; единицы суточных калорий
    jmp  PDB_Done

PDB_Time:
    ; Показываем HH:MM:SS на шести позициях
    mov  al, Hours
    xor  ah, ah
    mov  bl, 10
    div  bl
    mov  DispBuf[0], al      ; десятки часов
    mov  DispBuf[1], ah      ; единицы часов
    mov  al, Minutes
    xor  ah, ah
    div  bl
    mov  DispBuf[2], al      ; десятки минут
    mov  DispBuf[3], ah      ; единицы минут
    mov  al, Seconds
    xor  ah, ah
    div  bl
    mov  DispBuf[4], al      ; десятки секунд
    mov  DispBuf[5], ah      ; единицы секунд
    jmp  PDB_Done

PDB_Steps:
    ; Позиции 0-2 гасим, позиции 3-5 - шаги текущего часа
    xor  ah, ah
    mov  al, Hours
    mov  si, OFFSET StepsPerHour
    add  si, ax
    mov  al, byte ptr [si]
    xor  ah, ah
    xor  dx, dx
    mov  bl, 100
    div  bl
    mov  DispBuf[0], 10
    mov  DispBuf[1], 10
    mov  DispBuf[2], 10
    mov  DispBuf[3], al      ; сотни
    mov  al, ah
    xor  ah, ah
    mov  bl, 10
    div  bl
    mov  DispBuf[4], al      ; десятки
    mov  DispBuf[5], ah      ; единицы

PDB_Done:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret
PrepareDispBuf ENDP

; ============================================================
; Init - инициализация системы: вектор прерывания и сброс переменных
; ============================================================
Init PROC
    cli

    ; Устанавливаем вектор прерывания таймера в IVT (сегмент 0)
    ; Исправление бага #1: используем OFFSET TimerInt для получения
    ; смещения обработчика. Прежний вариант "cs:TimerInt" читал слово
    ; ИЗ ПАМЯТИ по адресу CS:offset(TimerInt), а не само смещение метки.
    mov  ax, IntTable
    mov  es, ax
    mov  ax, OFFSET TimerInt           ; Исправление бага #1: OFFSET, не cs:TimerInt
    mov  word ptr es:TimerIntPtr,   ax
    mov  ax, cs
    mov  word ptr es:TimerIntPtr+2, ax

    call ResetAll

    sti
    ret
Init ENDP

; ============================================================
; HandleButtons - обработка ввода кнопок, смена режима
; ============================================================
HandleButtons PROC
    call BttnInput           ; al = маска нажатых кнопок
    test al, al
    jz   HB_Done
    ; Любое нажатие переключает на следующий режим
    mov  al, Mode
    inc  al
    cmp  al, NumModes
    jb   HB_ModeOk
    xor  al, al
HB_ModeOk:
    mov  Mode, al
HB_Done:
    ret
HandleButtons ENDP

; ============================================================
; UpdateStats - накопление шагов и калорий (датчик шагов - бит 0)
; ============================================================
UpdateStats PROC
    push ax
    push si

    in   al, InPort
    test al, 01h             ; бит 0 = датчик шагов
    jz   US_Done

    xor  ah, ah
    mov  al, Hours
    mov  si, OFFSET StepsPerHour
    add  si, ax
    mov  al, byte ptr [si]
    cmp  al, 0FFh
    je   US_Cal
    inc  byte ptr [si]

US_Cal:
    xor  ah, ah
    mov  al, Hours
    mov  si, OFFSET CaloriesPerHour
    add  si, ax
    mov  al, byte ptr [si]
    cmp  al, 0FFh
    je   US_Done
    inc  byte ptr [si]

US_Done:
    pop  si
    pop  ax
    ret
UpdateStats ENDP

; ============================================================
; Display - обновление всех шести позиций семисегментного дисплея
; ============================================================
Display PROC
    push ax
    push bx
    push cx
    push dx
    push si

    call PrepareDispBuf

    mov  si, OFFSET DispBuf

    ; Позиции 0-1 на DigitSelPort1
    mov  dx, DigitSelPort1
    mov  bl, byte ptr [si]
    mov  bh, 01h
    call IndOutput
    inc  si
    mov  bl, byte ptr [si]
    mov  bh, 02h
    call IndOutput
    inc  si

    ; Позиции 2-3 на DigitSelPort2
    mov  dx, DigitSelPort2
    mov  bl, byte ptr [si]
    mov  bh, 01h
    call IndOutput
    inc  si
    mov  bl, byte ptr [si]
    mov  bh, 02h
    call IndOutput
    inc  si

    ; Позиции 4-5 на DigitSelPort3
    mov  dx, DigitSelPort3
    mov  bl, byte ptr [si]
    mov  bh, 01h
    call IndOutput
    inc  si
    mov  bl, byte ptr [si]
    mov  bh, 80h
    call IndOutput

    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret
Display ENDP


; Точка входа
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

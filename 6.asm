.386

RomSize    EQU   4096        
KeyboardPort    EQU   0      
DisplayPort     EQU   1      
DigitSelectPort EQU   2  ; Порт выбора индикатора
    
; Сегмент переменных
IntVectorTable  SEGMENT use16 AT 0
; Таблица векторов прерываний
IntVectorTable  ENDS

DataSegment     SEGMENT use16 AT 40h
KeyboardState   DB    3 DUP(?) ; 3 строки  (кнопки инверсные)
IsKeyboardEmpty DB    ?        ; Флаг нажатия минимум одной клавиши    
NextDigitCode   DB    ?        ; код последней определенной цифры  
SumAccumulator  DB    ?        
SumUpdateEnable DB    ?        ; Флаг обновленной суммы 
InvalidKeyFlag  DB    ?        ; Флаг некорректной клавиши 
DataSegment     ENDS

StackSegment    SEGMENT use16 AT 0010h
StackArea       dw    0010 dup (?)
StackTop        LABEL WORD
StackSegment    ENDS

; Сегмент стека
InitDataSegment SEGMENT use16
InitDataStart:
InitDataEnd:
InitDataSegment ENDS

CodeSegment     SEGMENT use16
ASSUME cs:CodeSegment, ds:DataSegment, es:DataSegment, ss:StackSegment

; Таблица образов цифр
DigitPatterns  DB    03Fh, 00Ch, 076h, 05Eh, 04Dh, 05Bh, 07Bh, 00Eh, 07Fh, 05Fh

; Процедура устранения дребезга контактов при считывании кнопки
DebounceInput PROC NEAR
DebounceStart:
           mov   ah, al      ; считанное значение 
           mov   bh, 0       ; счетчик совпадений 
DebounceWait:
           in    al, dx      ; значение снова
           cmp   ah, al      ; совпадает?
           jnz   DebounceStart
           inc   bh
           cmp   bh, 50
           jnz   DebounceWait
           mov   al, ah      ; стабильное значение 
           ret
DebounceInput ENDP

; Процедура считывания состояния всех кнопок клавиатуры
ReadKeyboard PROC NEAR
           lea   si, KeyboardState
           mov   cx, LENGTH KeyboardState ; 3 строки 
           mov   bl, 0FEh      ; начльная маска строки 11111110b
ReadKeyLoop:
           mov   al, bl
           out   KeyboardPort, al ; выбираем строку
           in    al, KeyboardPort ; состояние столбцов
           and   al, 0Fh          ; младшие 4 бита
           cmp   al, 0Fh          ; все отпущены? 
           jz    NoKeyPress
           mov   dx, KeyboardPort
           call  DebounceInput
           mov   [si], al
           call  DebounceInput ; для стабильности 
           jmp   NextKey 
NoKeyPress:
           mov   [si], al       ; пустое значение 
NextKey:
           inc   si
           rol   bl, 1         ; сдвиг маски, выбираем следующую строку
           loop  ReadKeyLoop
           ret
ReadKeyboard ENDP

; Процедура проверки: нажата ли хоть одна кнопка
CheckKeyboard PROC NEAR
           lea   bx, KeyboardState
           mov   cx, LENGTH KeyboardState
           mov   IsKeyboardEmpty, 0
           mov   dl, 0       ; счетчик нажатия клавиш 
CountKeys:
           mov   al, [bx]
           mov   ah, 4       ; проверка 
CountBits:
           shr   al, 1       ; младштй бит 
           cmc               ; инверия флага CF 
           adc   dl, 0       ; суммируем 1-битные значения 
           dec   ah
           jnz   CountBits
           inc   bx
           loop  CountKeys
           cmp   dl, 0
           jnz   KeysPresent
           mov   IsKeyboardEmpty, 0FFh ; если не одна не нажата 
KeysPresent:
           ret
CheckKeyboard ENDP

; Процедура определения кода цифры по нажатой клавише
DetectNextDigit PROC NEAR
           mov   InvalidKeyFlag, 0
           cmp   IsKeyboardEmpty, 0FFh ; пуста ли  
           jz    NoDigit
           lea   bx, KeyboardState
           mov   dx, 0
           ; строка
FindActiveRow:
           mov   al, [bx]
           and   al, 0Fh
           cmp   al, 0Fh             ; если все 1 - кнопки отпущены
           jnz   FindColumn          ; активная строка 
           inc   dh                  ; увеличиваем номер строки
           inc   bx                  ; переходим к следующей строке
           jmp   FindActiveRow
           ; столбец 
FindColumn:
           shr   al, 1
           jnc   CombineCode         ; если есть 0 - столбец 
           inc   dl
           jmp   FindColumn
CombineCode:
           mov   cl, 2
           shl   dh, cl
           or    dh, dl              ; объяединяем строку и столбец 
           cmp   dh, 9
           ja    MarkInvalid         ; Некорректный (>9)
           jmp   StoreNextDigit
MarkInvalid:
           mov   InvalidKeyFlag, 0FFh
           jmp   StoreNextDigit
NoDigit:
           mov   SumUpdateEnable, 1
StoreNextDigit:
           ret
DetectNextDigit ENDP

; Процедура сложения нажатых цифр
SumDigits PROC NEAR
           cmp   InvalidKeyFlag, 0FFh ; корректна ли 
           jz    ExitSum
           cmp   IsKeyboardEmpty, 0FFh ; пуста ли
           jz    ExitSum
           cmp   SumUpdateEnable, 0 ; можно ли 
           jz    ExitSum
           mov   al, dh
           daa
           add   al, [SumAccumulator]
           daa
           mov   [SumAccumulator], al
           mov   SumUpdateEnable, 0
ExitSum:
           ret
SumDigits ENDP

; Процедура отображения числа на индикаторе
DisplaySum PROC NEAR
           xor   ah, ah
           mov   al, [SumAccumulator]
           and   al, 0Fh
           lea   bx, DigitPatterns
           xlat  DigitPatterns            ; младший разряд
           out   DisplayPort, al
           mov   al, 0FEh
           out   DigitSelectPort, al      ; первый индикатор (еденицы)
           mov   al, 0FFh
           out   DigitSelectPort, al      ; сброс выбора
           mov   al, [SumAccumulator]
           shr   al, 4
           lea   bx, DigitPatterns
           xlat  DigitPatterns            ; старший разряд 
           out   DisplayPort, al             
           mov   al, 0FDh
           out   DigitSelectPort, al      ; выбираем второй индикатор (десятки)
           mov   al, 0FFh
           out   DigitSelectPort, al
           ret
DisplaySum ENDP

; Основная программа
Start:
           mov   ax, DataSegment
           mov   ds, ax
           mov   es, ax
           mov   ax, StackSegment
           mov   ss, ax
           lea   sp, StackTop

           mov   SumAccumulator, 0
           mov   SumUpdateEnable, 0
           mov   NextDigitCode, 0

MainLoop:
           call  ReadKeyboard    ; чтение клавиатуры
           call  CheckKeyboard   ; проверка состояния клавиатуры
           call  DetectNextDigit ; определение нажатой цифры
           call  SumDigits       ; обновление суммы
           call  DisplaySum      ; отображение суммы
           jmp   MainLoop

; Окончание программы, подготовка к записи в ПЗУ
           org   RomSize-16-((InitDataEnd-InitDataStart+15) AND 0FFF0h)
           ASSUME cs:NOTHING
           jmp   Far Ptr Start
CodeSegment     ENDS
END Start

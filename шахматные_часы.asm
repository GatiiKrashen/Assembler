.386
;Задайте объём ПЗУ в байтах
RomSize    EQU   4096
Vibrtime            EQU       50
PORT_TIMER_CW     EQU 43h    ;Порт управляющего регистра таймера
PORT_TIMER        EQU 40h    ;Порт счётчика таймера
BTTN_PORT       EQU     1
SEG_IND_PORT EQU 1
SEG_CHOICE_PORT_L EQU 2
SEG_CHOICE_PORT_H EQU 4

CLASSIC_TIME_H     EQU 8        ; 90 минут по 10 мс (5400 сек)
CLASSIC_TIME_L     EQU 3D60h    ; 90 минут по 10 мс (5400 сек)
BLITZ_TIME         EQU 7530h    ; 5 минут по 10 мс (300 сек) 

IntTable   SEGMENT use16 AT 0
           org   0ffh*4        ; По этому смещению находится адрес обработчика прерывания 0ffh
IntFFHandlerPtrOffs DW ?       ;Смещение обработчика прерывания  
IntFFHandlerPtrSeg  DW ?       ;Сегмент обработчика прерывания
IntTable   ENDS

Data       SEGMENT use16 AT 40h
LastBttnIn      DB  ?;последнее состояние кнопки(для контроля дребезга)
BttnImage       DB  ?;образ кнопок
LastBttnImage   DB  ?;выделение фронтов
GameStartFlag   DB  ?;флаг запуска игры
GameEndFlag     DB  ?;флаг окончания игры
Player1Time     DD  ?;время первого игрока
Player2Time     DD  ?;время второго игрока
ModeFlag        DB  ?;флаг режима игры
CurrentPlayerFlag DB ?;флаг текущего игрока
CurrentTurn   DB ?;номер текущего хода
TimeDispArr      DB 8 DUP(?);массив отображения времени
Data       ENDS

Stk        SEGMENT use16 AT 100h
           DW    10 dup (?)
StkTop     Label Word
Stk        ENDS

Code       SEGMENT use16
digits     db 3Fh, 0Ch, 76h, 05Eh, 4Dh, 5Bh, 7Bh, 0Eh, 7Fh, 5Fh
           ASSUME cs:Code, ds:Data, es:Data, ss: Stk

;гашение дребезга
VibrContr    PROC  
            push cx
            mov al, 0FFh
 Reset_counter:
            mov  cx, 0
 Same_input:        
            mov  LastBttnIn, al
            in   al, BTTN_PORT
            xor  LastBttnIn, al
            jnz Reset_counter
            inc cx
            cmp cx, Vibrtime
            jne Same_input
            pop  cx
            ret
VibrContr    ENDP          

;обработка кнопок
ProcessButtonInput  PROC   
            in   al, BTTN_PORT
            call VibrContr ;гашение дребезга
            or   al, 0f8h;маска 1111 1000
            xor al, LastBttnImage
            and al, LastBttnImage
            mov  BttnImage, al
            in   al, BTTN_PORT;считываем текущее состояние
            mov LastBttnImage, al
            ret
ProcessButtonInput  ENDP

;переключение режимов игры
SwitchGameMode  PROC
            cmp GameStartFlag, 0ffh
            jz MCExit
            test BttnImage, 4;0000 0100
            jz MCExit
            not ModeFlag
            cmp ModeFlag, 0ffh
            jz ModeSkip
            ;если класический режим
            mov word ptr Player1Time, CLASSIC_TIME_L
            mov word ptr Player1Time+2, CLASSIC_TIME_H
            mov word ptr Player2Time, CLASSIC_TIME_L
            mov word ptr Player2Time+2, CLASSIC_TIME_H 
            jmp MCExit
 ModeSkip:
            ;если блиц
            mov word ptr Player1Time, BLITZ_TIME
            mov word ptr Player1Time+2, 0
            mov word ptr Player2Time, BLITZ_TIME
            mov word ptr Player2Time+2, 0 
 MCExit:           ret
SwitchGameMode  ENDP

;запуск игры
GameStart   PROC
            cmp GameStartFlag, 0ffh
            jz GSExit
            ;проверка кнопки игрока 1
            test BttnImage, 1;0000 0001
            jz NextBttnSkip
            mov GameStartFlag, 0ffh
            mov CurrentPlayerFlag, 0
            jmp GSExit
 NextBttnSkip:
            ;проверка кнопки игрока 2
            test BttnImage, 2;0000 0010
            jz GSExit
            mov GameStartFlag, 0ffh
            mov CurrentPlayerFlag, 0ffh
 GSExit:    ret
GameStart   ENDP

NextTurn    PROC
            cmp GameStartFlag, 0ffh
            jnz NTExit
            cmp GameEndFlag, 0ffh
            jz NTExit
            ;проверка первой кнопки при ходе первого игрока
            cmp CurrentPlayerFlag, 0ffh
            jnz NTPlayer2
            test BttnImage, 1;0000 0001
            jnz NewTurn
            jmp NTExit
 NTPlayer2: ;проверка второй кнопки при ходе второго игрока
            test BttnImage, 2;0000 0010
            jnz NewTurn
            jmp NTExit
 NewTurn:
            inc CurrentTurn ;увеличение номера хода
            not CurrentPlayerFlag ;смена активного игрока
 NTExit:    ret
NextTurn    ENDP

;уменьшение таймера текущего игрока
TimeDec PROC
            cmp GameStartFlag, 0ffh
            jnz TDExit
            cmp GameEndFlag, 0ffh
            jz TDExit
            ;проверяем текущего игрока
            cmp CurrentPlayerFlag, 0ffh
            jz TDPlayer2
            sub word ptr Player1Time, 1
            sbb word ptr Player1Time+2, 0
            jnc TDExit 
            mov GameEndFlag, 0ffh
            jmp TDExit        
 TDPlayer2:
            sub word ptr Player2Time, 1
            sbb word ptr Player2Time+2, 0
            jnc TDExit 
            mov GameEndFlag, 0ffh
            jmp TDExit

 TDExit:    iret 
TimeDec ENDP

;перевод в BCD для отображения времени
ConvertBinaryToBCD    PROC
            push cx
            ;dl - двоичное число
            ;al - десятичное число на выходе
            mov al, 0 ;накопитель
            mov cx, 8
 ConvLoop:  shl dl, 1
            mov ah, al
            adc al, ah ;удваиваем с учётом переноса
            daa
            loop ConvLoop
            pop cx
            ret
ConvertBinaryToBCD    ENDP

;отображение текущего хода
TurnIndOut PROC
            lea  bx, digits

            ;перевести в десятичную систему
            mov dl, CurrentTurn
            shr dl, 1 ; делим на 2
            call ConvertBinaryToBCD
            mov  ah, al

            mov  al,ah
            and  al,0Fh
            xlat digits
            mov dl, CurrentTurn ;добавление точки
            shr dl, 1
            jnc DotSkip
            or al, 80h;1000 0000           
 DotSkip:
            out  SEG_IND_PORT,al  ;Выводим младшую часть
            ;активация индикатора
            mov al, 0FDh ;1111 1101
            out SEG_CHOICE_PORT_H, al

            mov al, 0ffh
            out SEG_CHOICE_PORT_H, al


            mov  al,ah
            shr  al,4 ;старшая часть
            xlat digits
            out  SEG_IND_PORT,al

            mov al, 0FEh;1111 1110
            out SEG_CHOICE_PORT_H, al

            mov al, 0ffh
            out SEG_CHOICE_PORT_H, al


            ret
TurnIndOut ENDP

;формирование массива для индикации времени
TimeArrForm PROC

            cmp GameEndFlag, 0ffh
            jz EndGen
            lea  bx, digits
            ;прочитать время 1 игрока
            mov ax, word ptr Player1Time
            mov dx, word ptr Player1Time + 2
            mov cx, 100 ;делить на 100(секунды)
            div cx           
            mov cl, 60 ;делить на 60(минуты)
            div cl
            mov dh, ah;временно сохраняем секунды
            mov dl, al;переводим минуты в десятичный формат
            call ConvertBinaryToBCD
            mov  ah, al
            
            shr  al,4 
            xlat digits
            mov TimeDispArr, al ;сохранить в массив
            
            and  ah, 0Fh
            mov al, ah 
            xlat digits
            mov TimeDispArr+1, al

            mov dl, dh;передаем секунды в подпрограмму
            call ConvertBinaryToBCD
            mov  ah, al

            shr  al, 4
            xlat digits
            mov TimeDispArr+2, al ;сохранить в массив
            
            and  ah, 0Fh
            mov al, ah 
            xlat digits
            mov TimeDispArr+3, al


            ;прочитать время 2 игрока
            mov ax, word ptr Player2Time
            mov dx, word ptr Player2Time + 2
            mov cx, 100 ;делить на 100(секунды)
            div cx           
            mov cl, 60 ;делить на 60(минуты)
            div cl
            mov dh, ah;временно сохраняем секунды
            mov dl, al;переводим минуты в десятичн.
            call ConvertBinaryToBCD
            mov  ah, al

            shr  al,4
            xlat digits
            mov TimeDispArr+4, al ;сохранить в массив
            
            and  ah, 0Fh
            mov al, ah 
            xlat digits
            mov TimeDispArr+5, al

            mov dl, dh;передаем секунды в подпрограмму
            call ConvertBinaryToBCD
            mov  ah, al

            shr  al, 4
            xlat digits
            mov TimeDispArr+6, al ;сохранить в массив
            
            and  ah, 0Fh
            mov al, ah 
            xlat digits
            mov TimeDispArr+7, al
            jmp TAFExit

 EndGen:    
            ;вывод lose
            lea di, TimeDispArr
            cmp CurrentPlayerFlag, 0ffh
            jnz TAFlayerSkip
            lea di, TimeDispArr + 4
 TAFlayerSkip:
            mov word ptr [di], 3f31h ;0-3f,31-L,73-E,5b-S
            mov word ptr [di+2], 735bh

 TAFExit:           ret
TimeArrForm ENDP

;вывод времени на индикаторы
TimeIndOut PROC

            lea di, TimeDispArr
            mov ah, 0FEh ; маска 1111 1110
            mov cx, 8
 TID_Loop:  
            mov al, [di]
            out  SEG_IND_PORT,al
            
            mov al, ah
            out SEG_CHOICE_PORT_L, al
            mov al, 0ffh
            out SEG_CHOICE_PORT_L, al
            rol ah, 1
            inc di
            loop TID_Loop

            ret
TimeIndOut ENDP

;инициализация таймера
InitTimer        PROC 
           mov   al, 16h             
           out   PORT_TIMER_CW, al
           mov   al, 2               
           out   PORT_TIMER, al
           ret
InitTimer        ENDP

;перезапуск игры
Restart PROC
            cmp GameStartFlag, 0ffh
            jnz RExit
            test BttnImage, 4;0000 0100(кнопка смены режима)
            jz RExit
            call PrepFunc
 RExit:     ret
Restart ENDP

; Подготовка начальных значений
PrepFunc PROC
            cli
            
            mov ModeFlag, 0
            mov LastBttnImage, 0h
            mov GameStartFlag, 0
            mov CurrentTurn, 1
            mov GameEndFlag, 0
            ; выключаем индикаторы
            mov al, 0ffh
            out SEG_CHOICE_PORT_L, al
            out SEG_CHOICE_PORT_H, al
            ;устанавливаем классический режим
            mov word ptr Player1Time, CLASSIC_TIME_L
            mov word ptr Player1Time+2, CLASSIC_TIME_H
            mov word ptr Player2Time, CLASSIC_TIME_L
            mov word ptr Player2Time+2, CLASSIC_TIME_H 
            sti
            ret
PrepFunc ENDP


Start:
           mov   ax, Data
           mov   ds, ax
           mov   es, ax
           mov   ax, Stk
           mov   ss, ax
           lea   sp, StkTop
           ; установка обработчика прерываний
           push  ds
           mov   ax, IntTable
           mov   ds, ax
           mov   ax, cs:TimeDec ;смещение
           mov   ds:IntFFHandlerPtrOffs, ax
           mov   ax, Code ;сегмент
           mov   ds:IntFFHandlerPtrSeg, ax
           pop   ds
           call InitTimer ;инициализация таймера
            call PrepFunc ;подготовка начальных значений
main_loop:  

            call ProcessButtonInput ;обработка ввода
            call SwitchGameMode     ;переключение режима
            call GameStart          ;запуск игры
            call NextTurn           ;обработка хода
            call TurnIndOut         ;оьображение номера хода
            call TimeArrForm        ;формирование массива времени
            call TimeIndOut         ;отображение времени
            call Restart            ;проверка сброса игры
            jmp main_loop           

           org   RomSize-16
           ASSUME cs:NOTHING
           jmp   Far Ptr Start
Code       ENDS
END		Start

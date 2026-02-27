.386
; Задайте объём ПЗУ в байтах
RomSize    EQU   4096

; Определение портов ввода-вывода
INDICATOR_OUTPUT_PORT EQU 01h           ; Порт выборки индикатора
DISPLAY_OUTPUT_PORT EQU 00h             ; Порт вывода на дисплей

TEMPERATURE_STREET_INPUT_PORT EQU 01h  ; Порт ввода температуры улицы
TEMPERATURE_HOME_INPUT_PORT EQU 02h    ; Порт ввода температуры дома
PRESSURE_HOME_INPUT_PORT EQU 03h       ; Порт ввода давления
HUMIDITY_HOME_INPUT_PORT EQU 04h       ; Порт ввода влажности

ADC_START_PORT EQU 03h               ; Порт запуска АЦП
READLY_ADC_PORT EQU 00h              ; Порт чтения АЦП

READLY_MASK EQU 00001111b              ; Маска готовности АЦП
BUTTON_MASK EQU 00010000b              ; Маска готовности АЦП

; Сегмент данных
Data       SEGMENT use16 AT 40h
           ADCStart db ?            ; Флаг запуска АЦП
           
           StreetTemperature db ?   ; Температура на улице
           HomeTemperature db ?     ; Температура в помещении
           Pressure db ?            ; Давление в помещении
           Humidity db ?            ; Влажность в помещении
           
           StreetDataDisplay db 4 dup(?)  ; Массив отображения данных улицы
           HomeDataDisplay db 4 dup(?)    ; Массив отображения данных дома
           
           HomeStatus db ?          ; Статус дома (режим отображения)
           ReadlyFlag db ?          ; Флаг готовности
           OldStateButton DB ?      ; Предыдущее состояние кнопки
Data       ENDS


; Сегмент стека
Stk        SEGMENT use16 AT 100h
; Задайте необходимый размер стека
           dw    32 dup (?)
StkTop     Label Word
Stk        ENDS



; Сегмент инициализационных данных (ПЗУ)
InitData   SEGMENT use16
InitDataStart:
; Здесь размещается описание неизменяемых данных, которые будут храниться в ПЗУ
InitDataEnd:
InitData   ENDS


; Сегмент кода
Code       SEGMENT use16
; Образы цифр от 0 до 9 для 7-ми сегментного индикатора
digits     db 3Fh, 0Ch, 76h, 05Eh, 4Dh, 5Bh, 7Bh, 0Eh, 7Fh, 5Fh, 40h, 00h

           ASSUME cs:Code, ds:Data, es:Data, ss: Stk

; ------------------------------------------------------------
; Процедура инициализации переменных
; ------------------------------------------------------------
FuncPrep PROC NEAR
           push ax
           mov StreetTemperature, 0
           mov HomeTemperature, 0
           mov Pressure, 0
           mov Humidity, 0           
           mov ADCStart, 0ffh       ; Инициализация флага АЦП
           mov HomeStatus, 00000001b ; Начальный статус дома
           mov OldStateButton, BUTTON_MASK    ; Начальное состояние кнопки
           pop ax
           ret
FuncPrep ENDP

; ------------------------------------------------------------
; Процедура отображения всех данных
; ------------------------------------------------------------
 ShowDisplay PROC NEAR
           push ax
           push bx
           push cx
           push dx
           push si
           ; Отображение данных улицы 
           mov al, 0  
           mov si, 0
           mov dl, 0FEh                   ; Маска для выбора разряда индикатора
           mov cx, 3                      ; Количество разрядов
       
       DS1:mov   al, StreetDataDisplay[SI] ; Загрузка данных для отображения
           lea   bx, digits               ; Загрузка таблицы символов
           xlat  digits                   ; Преобразование в 7-сегментный код
           out   DISPLAY_OUTPUT_PORT, al     ; Вывод данных
           
           mov   al, dl
           out   INDICATOR_OUTPUT_PORT, al ; Выбор разряда индикатора
           
           mov   al, 0FFh
           out   INDICATOR_OUTPUT_PORT, al ; Сброс выбора разряда
           
           INC SI                 ; Следующий символ
           ROL dl, 1              ; Следующий разряд
           Loop DS1               ; Цикл по всем разрядам
           
           ; Отображение данных дома
           mov al, 0                     
           mov si, 0                    
           mov cx, 4              ; Количество разрядов
       DH1:mov   al, HomeDataDisplay[SI] ; Загрузка данных для отображения
           and   al, 0fh                  ; Маскирование старших битов
           lea   bx, digits               ; Загрузка таблицы символов
           xlat  digits                   ; Преобразование в 7-сегментный код
           out   DISPLAY_OUTPUT_PORT, al ; Вывод данных
           
           mov   al, dl
           out   INDICATOR_OUTPUT_PORT, al ; Выбор разряда индикатора
           
           mov   al, 0FFh
           out   INDICATOR_OUTPUT_PORT, al ; Сброс выбора разряда
           
           INC SI                 ; Следующий символ
           ROL dl, 1              ; Следующий разряд
           Loop DH1               ; Цикл по всем разрядам 
           
           pop si
           pop dx
           pop cx
           pop bx
           pop ax              
           ret
ShowDisplay ENDP
         
; ------------------------------------------------------------
; Процедура чтения данных с АЦП
; ------------------------------------------------------------
ADCReading PROC NEAR
           push ax
           push cx
           
           in al, READLY_ADC_PORT ; Чтение статуса готовности АЦП
           test al, READLY_MASK   ; Проверка маски готовности
           jz ADCReadEnd          ; Если не готов - выход
         
           
           ; Чтение данных с различных датчиков
           in al, TEMPERATURE_STREET_INPUT_PORT 
           mov StreetTemperature, al         ; Сохранение температуры улицы
           
           in al, TEMPERATURE_HOME_INPUT_PORT 
           mov HomeTemperature, al           ; Сохранение температуры дома
           
           in al, HUMIDITY_HOME_INPUT_PORT 
           mov Humidity, al                  ; Сохранение влажности
           
           in al, PRESSURE_HOME_INPUT_PORT
           mov Pressure, al                  ; Сохранение давления          
                    
    ADCReadEnd:
           mov cx, 1000; небольшая задержка
Delay:     nop
           loop Delay 
    
           pop cx
           pop ax
           ret
ADCReading ENDP

; ------------------------------------------------------------
; Процедура обработки температуры 
; ------------------------------------------------------------
TempProcessing PROC NEAR
           push bp
           mov  bp, sp
           mov ax, [bp+6]
           mov  di, [bp+4]      
           
           mov ah, 0 
           mov bx, 120          ; Коэффициент масштабирования
           mul bx              ; Умножение
           mov bx, 255         ; Максимальное значение АЦП
           div bx              ; Нормализация
           sub ax, 60          ; Смещение для отрицательных температур
           
           ; Проверка знака температуры
           cmp ax, 0
           jge PositiveTemp   ; Если положительная

           neg ax              ; Инвертирование отрицательного значения
           mov bl, 10          ; Код для знака "-"
           jmp ConvertTemp
PositiveTemp:
           mov bl, 11          ; Код для знака "+" или пусто
    
ConvertTemp:
           xor dx, dx
           mov dl, 10
           div dl 
                        
           mov [DI], ah      ; Единицы
           mov [DI+1], al    ; Десятки
           mov [DI+2], bl    ; Знак ("+" или "-")
           mov byte ptr [DI+3], 11    ; Пустой разряд
    
StpExit:
           pop  bp
           ret 4
TempProcessing ENDP

; ------------------------------------------------------------
; Процедура обработки давления
; ------------------------------------------------------------
PressureProcessing PROC NEAR
           push ax
           push bx
           push cx
           push dx
           
           mov al, Pressure    ; Загрузка сырого значения давления
           mov ah, 0               
    
           ; Формула: Pressure = ((AX * 110) / 255) + 930
           mov bx, 110             ; Коэффициент масштабирования
           mul bx                  ; Умножение
           mov bx, 255             ; Максимальное значение АЦП
           div bx                  ; Нормализация
           add ax, 930             ; Смещение

           ; Проверка границ давления
           cmp ax, 930
           jae PressureNotUnder
           mov ax, 930             ; Минимальное значение
           jmp PressureNotOver
           
PressureNotUnder:
           cmp ax, 1040
           jbe PressureNotOver
           mov ax, 1040            ; Максимальное значение
PressureNotOver:

           mov bx, ax              ; Сохранение результата
    
           ; Определение тысяч
           mov ax, bx
           sub ax, 1000            ; Проверяем >=1000
           jb LessThan1000
           mov HomeDataDisplay[3], 1  ; '1' для 1000-1040
           jmp GetHundreds
LessThan1000:
           mov HomeDataDisplay[3], 11 ; Пусто для значений <1000

GetHundreds:
           ; Вычисление сотен
           mov ax, bx
           cmp ax, 1000
           jb Below1000
           sub ax, 1000            ; Вычитание тысяч
Below1000:
           mov cl, 100
           div cl                  ; Деление на 100
           mov HomeDataDisplay[2], al ; Сотни

           ; Вычисление десятков и единиц
           mov al, ah              ; Остаток от деления
           mov ah, 0
           mov cl, 10
           div cl                  ; Деление на 10
    
           mov HomeDataDisplay[1], al ; Десятки
           mov HomeDataDisplay[0], ah ; Единицы

           pop dx
           pop cx
           pop bx
           pop ax
           ret
PressureProcessing ENDP

; ------------------------------------------------------------
; Процедура обработки влажности
; ------------------------------------------------------------
HumidityProcessing PROC NEAR
           push ax
           push bx
           push dx
           
           mov al, Humidity    ; Загрузка сырого значения влажности
           mov ah, 0               
           mov bx, 100         ; Коэффициент для процентов
           mul bx              ; Умножение
           mov bx, 255         ; Максимальное значение АЦП
           div bx              ; Нормализация к 0-100%

           ; Проверка границ влажности
           cmp ax, 100
           jbe HumidityOK
           mov ax, 100         ; Максимальная влажность 100%
HumidityOK:

           ; Разделение на сотни, десятки и единицы
           mov bl, 100
           div bl              ; Деление на 100
           mov HomeDataDisplay[2], al ; Сотни (0 или 1)

           mov al, ah          ; Остаток от деления
           mov ah, 0
           mov bl, 10
           div bl              ; Деление на 10

           mov HomeDataDisplay[0], ah ; Единицы
           mov HomeDataDisplay[1], al ; Десятки
           mov HomeDataDisplay[3], 11 ; Пустой разряд

           pop dx
           pop bx
           pop ax
           ret
HumidityProcessing ENDP

; ------------------------------------------------------------
; Процедура формирования цифр для отображения
; ------------------------------------------------------------
FormDigits PROC NEAR  
           push ax
           push bx
           push cx
           push dx
           push si

           ; ---- Улица ----
           PUSH word ptr StreetTemperature
           PUSH offset StreetDataDisplay 
           CALL TempProcessing 

           ; ---- Выбор режима для дома ----
           mov al, HomeStatus
           and al, 00000111b
           xor cl, cl
FindBit:
           shr al, 1
           jc BitFound
           inc cl
           jmp FindBit

BitFound:
           lea si, MySwitch
           mov al, cl
           xor ah, ah
           shl ax, 4           ; умножаем на 16 (размер блока)
           add ax, si
           jmp ax

; ========== ТАБЛИЦА ПЕРЕХОДОВ (БЛОК 16 БАЙТ) ==========
MySwitch:
           ; ----- Блок 0: температура дома (4+3+3+2 = 12 + 4 NOP = 16) -----
           PUSH word ptr HomeTemperature
           PUSH offset HomeDataDisplay 
           CALL TempProcessing
           jmp FDExit
           NOP                ; 4 NOP добивают до 16 байт
           NOP
           NOP
           NOP
           
           

           ; ----- Блок 1: давление (7+3+2 = 12 + 4 NOP = 16) -----
           CALL PressureProcessing
           jmp FDExit
           NOP               ; 11 NOP после JMP
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
           
           ; ----- Блок 2: влажность (7+3+2 = 12 + 4 NOP = 16) -----
           CALL HumidityProcessing
           jmp FDExit         

FDExit:
           pop si
           pop dx
           pop cx
           pop bx
           pop ax  
           ret
FormDigits ENDP

; ------------------------------------------------------------
; Процедура генерации импульса для запуска АЦП
; ------------------------------------------------------------
ImpulseToADC PROC NEAR
           push ax
           
           mov al, ADCStart         ; Загрузка текущего состояния
           AND AL, 00011111b
           mov ah, al
           mov al, HomeStatus     ; Загрузка статуса дома
           rol al, 5
           or al, ah
           out ADC_START_PORT, al ; Вывод статуса
           out ADC_START_PORT, al   ; Запуск АЦП
           not ADCStart             ; Инверсия состояния для следующего запуска
           
           pop ax
           ret
ImpulseToADC ENDP

; ------------------------------------------------------------
; Процедура устранения дребезга контактов
; ------------------------------------------------------------
VibrDestr PROC NEAR
           push dx
           
           in al, READLY_ADC_PORT ; Чтение состояния кнопки
           and al, BUTTON_MASK 
       VD1:
           mov   ah, al         ; Сохранение текущего состояния
           mov   dh, 0          ; Счетчик стабильности
       VD2:        
           in    al, READLY_ADC_PORT ; Чтение нового состояния
           and al, BUTTON_MASK 
           cmp   ah, al         ; Сравнение с предыдущим
           jne   VD1            ; Если изменилось - начать заново
           inc   dh             ; Увеличение счетчика стабильности
           cmp   dh, 50         ; Проверка достаточной стабильности
           jne   VD2            ; Продолжить проверку
           
           pop dx
           ret
VibrDestr ENDP

; ------------------------------------------------------------
; Процедура проверки состояния кнопки
; ------------------------------------------------------------
ButtonCheck PROC NEAR
           push ax
           push dx

           in al, READLY_ADC_PORT
           and al, BUTTON_MASK
           mov ah, al                     ; сохраняем текущее состояние

           cmp al, BUTTON_MASK
           je  BC_Save                    ; если не нажата - сразу сохраняем

           call VibrDestr                ; подавление дребезга
           mov ah, al                    ; обновляем состояние после дребезга
           not al
           and al, OldStateButton        ; выделяем фронт нажатия
           jz  BC_Save                   ; нет фронта - только сохраняем

           ; переключение режима
           shl HomeStatus, 1
           test HomeStatus, 00001000b
           jz  BC_Save
           mov HomeStatus, 00000001b

BC_Save:
           mov OldStateButton, ah        ; ВСЕГДА сохраняем текущее состояние
           pop dx
           pop ax
           ret
ButtonCheck ENDP 

; ------------------------------------------------------------
; Начало программы
; ------------------------------------------------------------
Start:
           ; Инициализация сегментных регистров
           mov   ax, Data
           mov   ds, ax
           mov   es, ax
           mov   ax, Stk
           mov   ss, ax
           lea   sp, StkTop      

           ; Инициализация системы
           CALL FuncPrep 

; Главный цикл программы
MainLoop:                 
           CALL ButtonCheck      ; Проверка кнопки
           CALL ImpulseToADC     ; Запуск АЦП
           CALL ADCReading       ; Чтение данных с АЦП            
           CALL FormDigits       ; Формирование данных для отображения
           CALL ShowDisplay      ; Отображение данных
           
           jmp MainLoop          ; Бесконечный цикл

; Размещение кода в ПЗУ с выравниванием
           org   RomSize-16-((InitDataEnd-InitDataStart+15) AND 0FFF0h)
           ASSUME cs:NOTHING
           jmp   Far Ptr Start   ; Переход к началу программы
Code       ENDS
END        Start
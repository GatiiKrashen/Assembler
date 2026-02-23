.386
;Задайте объём ПЗУ в байтах
RomSize    EQU   4096

TargetKeyboardInPort = 0
TargetKeyboardOutPort = 0
SegmentPort = 1
IndicatorPort1 = 2
IndicatorPort2 = 3
ButtonsPort = 1

TargetKeyboardRows = 8
TargetKeyboardCols = 8

DebounceCount = 50

SelectMode = 0
GameMode = 1

True = 0FFh
False = 0

BlinkTimeH = 0
BlinkTimeL = 3FFh

TriggerTimeH = 0
TriggerTimeL = 0BFFh

IntTable   SEGMENT use16 AT 0
;Здесь размещаются адреса обработчиков прерываний
           org   020h*4
Int20HandlerPtr dd ?
Int21HandlerPtr dd ?
IntTable   ENDS

Data       SEGMENT use16 AT 40h
;Здесь размещаются описания переменных

TargetKeyboardImage db TargetKeyboardRows dup (?)        ;Образы клавиатуры (мишени)
PrevTargetKeyboardImage db TargetKeyboardRows dup (?)

ButtonPortState db ?             ;Образы порта кнопок
PrevButtonPortState db ?

CurrentScanRow db ?              ;Текущая сканируемая строка (0-7), 0FFh - неактивно

TargetKeyboardPoints db ?        ;Очки с мишени, после попадания

TargetKeyboardEmpty db ?         ;Флаги
TargetKeyboardError db ?
TargetKeyboardPress db ?
ScanInProgress db ?
ReadyToShoot db ?                
WaitMissOnTarget db ?
OutOfBullets db ?
ClearCurrentPlayerPoints db ?
NeedToAddPoints db ?
NeedToSortPLayers db ?
ButtonPressed db ?
TargetKeyboardChanged db ?
CurrentMode db   ?
Blink      db    ?

BlinkTimer dd ?                  ;Счётчики
TriggerTimer dd ?

CurrentPlayerNumber db ?         ;Параметры системы: текущий игрок и количество пуль
BulletCount db ?

PlayerNumberOptionIndex db ?     ;Индексы текущих вариантов параметров
BulletCountOptionIndex db ?

IndicatorPortState dw ?          ;Общее (на два порта) состояние динамической индикации

;Табло                           ;По 3 байта на игрока:
Scoreboard db 3 dup (?)          ;1 байт - место,                     
           db 3 dup (?)          ;2 байт - номер игрока,
           db 3 dup (?)          ;3 байт - счёт (двоично-десятичный BCD двухразрядный накопитель)

Data       ENDS

;Задайте необходимый адрес стека
Stk        SEGMENT use16 AT 80h
;Задайте необходимый размер стека
           dw    32 dup (?)
StkTop     Label Word
Stk        ENDS

InitData   SEGMENT use16
InitDataStart:
;Здесь размещается описание неизменяемых данных, которые будут храниться в ПЗУ
InitDataEnd:
InitData   ENDS

Code       SEGMENT use16
;Здесь размещается описание неизменяемых данных
           ASSUME cs:Code, ds:Data, es:Data, ss: Stk
           
;Образы 10-тиричных символов: "0", "1", ... "9" + пустой индикатор (для незначащего нуля)
DigitImages db 03Fh, 00Ch, 076h, 05Eh, 04Dh, 05Bh, 07Bh, 00Eh, 07Fh, 05Fh, 0

;Таблица очков
PointsTable db 1, 1, 1, 1, 1, 1, 1, 1
            db 1, 2, 2, 2, 2, 2, 2, 1
            db 1, 2, 3, 3, 3, 3, 2, 1
            db 1, 2, 3, 4, 4, 3, 2, 1
            db 1, 2, 3, 4, 4, 3, 2, 1
            db 1, 2, 3, 3, 3, 3, 2, 1
            db 1, 2, 2, 2, 2, 2, 2, 1
            db 1, 1, 1, 1, 1, 1, 1, 1

;Варианты номеров игроков            
PlayerNumberOptions db 1, 2, 3

;Варианты количества пуль
BulletCountOptions db 5h, 10h, 15h

;Обработчик прерывания по нажатию на кнопку
ButtonsIntHandler PROC FAR  
           pusha
           
           mov   al, ButtonPortState              ;Обновляем предыдущее состояние порта
           mov   PrevButtonPortState, al
           
           in    al, ButtonsPort                  ;Считываем текущее состояние порта
           mov   dx, ButtonsPort                  
           call  Debounce                         ;Гасим дребезг
           mov   ButtonPortState, al
           
           not   al                               ;Выделяем передний фронт
           and   al, PrevButtonPortState                     
           jz    NoButtonPress
           
           mov   ButtonPressed, True              ;Устанавливаем флаг нажатия на кнопку
           
NoButtonPress:        
           popa                                          
           iret
ButtonsIntHandler ENDP

;Обработчик прерывания по нажатию на клавиатуру (мишень)
TargetKeyboardIntHandler PROC FAR
           pusha  
           
           in    al, TargetKeyboardInPort         ;Считываем состояние клавиш
           mov   dx, TargetKeyboardInPort
           call  Debounce
           
           mov   bx, offset TargetKeyboardImage   ;Сохраняем текущее состояние
           add   bl, CurrentScanRow
           mov   [bx], al

           mov   TargetKeyboardChanged, True      ;Устанавливаем флаг изменения на клавиатуре (мишени)

           popa                                              
           iret
TargetKeyboardIntHandler ENDP

;Подпрограмма для сброса табло, обнуление результатов всех игроков
ResetScoreboard PROC NEAR
           mov   byte ptr ScoreBoard, 1           ;Место
           mov   byte ptr ScoreBoard + 3, 1
           mov   byte ptr ScoreBoard + 6, 1
           
           mov   byte ptr ScoreBoard + 1, 1       ;Номер игрока
           mov   byte ptr ScoreBoard + 4, 2
           mov   byte ptr ScoreBoard + 7, 3
           
           mov   byte ptr ScoreBoard + 2, 0       ;Счёт
           mov   byte ptr ScoreBoard + 5, 0
           mov   byte ptr ScoreBoard + 8, 0
           ret
ResetScoreboard ENDP
               
;Подпрограмма инициализации
Initialization PROC NEAR
           cli

           mov   ax, IntTable                     ;Устанавка адреса обработчика прерывания по нажатию кнопки
           mov   es, ax
           mov   word ptr es:Int20HandlerPtr, offset ButtonsIntHandler
           mov   word ptr es:Int20HandlerPtr + 2, seg ButtonsIntHandler
           
           mov   ax, IntTable                     ;Устанавка адреса обработчика прерывания по нажатию клавиатуры (мишени)
           mov   es, ax
           mov   word ptr es:Int21HandlerPtr, offset TargetKeyboardIntHandler
           mov   word ptr es:Int21HandlerPtr + 2, seg TargetKeyboardIntHandler
           
           mov   ScanInProgress, False            ;Инициализация флагов
           mov   TargetKeyboardChanged, False
           mov   TargetKeyboardEmpty, True        
           mov   TargetKeyboardError, False
           mov   TargetKeyboardPress, False
           mov   ReadyToShoot, False
           mov   WaitMissOnTarget, False
           mov   OutOfBullets, False
           mov   ClearCurrentPlayerPoints, False
           mov   NeedToAddPoints, False
           mov   NeedToSortPLayers, False
           mov   ButtonPressed, False
           mov   Blink, True
           
           mov   PlayerNumberOptionIndex, 0       ;Инициализация остальных переменных
           mov   BulletCountOptionIndex, 0
           mov   CurrentPlayerNumber, 1
           mov   BulletCount, 5
           mov   IndicatorPortState, 1
           mov   CurrentMode, SelectMode
           mov   TargetKeyboardPoints, 0
           mov   CurrentScanRow, 0FFh
           
           call  ResetScoreboard                  ;Инициализация табло
           
           mov   word ptr BlinkTimer, BlinkTimeL        ;Загружаем счётчики (таймеры)
           mov   word ptr BlinkTimer + 2, BlinkTimeH
           mov   word ptr TriggerTimer, TriggerTimeL
           mov   word ptr TriggerTimer + 2, TriggerTimeH
           
           mov   PrevButtonPortState, 0FFh              ;Инициализация образов порта с кнопками
           mov   ButtonPortState, 0FFh
           
           mov   word ptr TargetKeyboardImage, 0FFFFh        ;Инициализация образов клавиатуры (мишени)
           mov   word ptr TargetKeyboardImage + 2, 0FFFFh
           mov   word ptr TargetKeyboardImage + 4, 0FFFFh
           mov   word ptr TargetKeyboardImage + 6, 0FFFFh
           
           mov   word ptr PrevTargetKeyboardImage, 0FFFFh
           mov   word ptr PrevTargetKeyboardImage + 2, 0FFFFh
           mov   word ptr PrevTargetKeyboardImage + 4, 0FFFFh
           mov   word ptr PrevTargetKeyboardImage + 6, 0FFFFh
           
           sti
           ret
Initialization ENDP

;Подпрограмма для устранения дребезга контактов
;Вход: dx - номер порта ввода
;Выход: al - устойчивое состояние порта после гашения дребезга
Debounce   PROC NEAR
SaveState: 
           mov   ah, al                           ;Сохраняем исходное состояние порта
           mov   bh, 0                            ;Счетчик стабильных повторов
           
CheckStable:
           in    al, dx                           ;Читаем текущее состояние порта
           cmp   ah, al                           ;Сравниваем с сохраненным состоянием
           jne   SaveState                        ;Если изменилось - начинаем заново
           
           inc   bh                               ;Увеличиваем счетчик стабильных чтений
           cmp   bh, DebounceCount                ;Достигли нужного количества?
           jne   CheckStable                      ;Если нет - продолжаем проверку
           
           mov   al, ah                           ;Возвращаем устойчивое состояние
           ret
Debounce   ENDP

;Подпрограмма неблокирующего опроса клавиатуры (мишени)
TargetKeyboardInput PROC NEAR
           cmp   WaitMissOnTarget, True           ;Если не ждём попадания по мишени, то сканировать не нужно
           jne   Exit

           cmp   CurrentScanRow, 0FFh             ;Проверяем, нужно ли начинать новое сканирование
           jne   ContinueScan
           
           mov   TargetKeyboardChanged, False     ;Инициализация нового сканирования
           mov   CurrentScanRow, 0
           mov   ScanInProgress, True
           jmp   ProcessRow

ContinueScan:
           inc   CurrentScanRow                           ;Переходим к следующей строке
           cmp   CurrentScanRow, TargetKeyboardRows
           jb    ProcessRow
           
           mov   CurrentScanRow, 0FFh             ;Сканирование завершено
           mov   ScanInProgress, False
           mov   al, 0FFh
           out   TargetKeyboardOutPort, al
           ret

ProcessRow:
           mov   bx, offset TargetKeyboardImage   ;Сохраняем предыдущее состояние текущей строки
           add   bl, CurrentScanRow
           mov   al, [bx]
           mov   bx, offset PrevTargetKeyboardImage
           add   bl, CurrentScanRow
           mov   [bx], al
           
           mov   al, 0FFh                         ;Предполагаем, что в строке нет активных битов
                                                  
           mov   bx, offset TargetKeyboardImage   ;Сохраняем текущее состояние
           add   bl, CurrentScanRow               ;(в дальнешем по прерыванию может быть перезаписано)
           mov   [bx], al
           
           mov   bl, 0FEh                         ;Активируем текущую строку
           mov   cl, CurrentScanRow
           rol   bl, cl
           mov   al, bl
           out   TargetKeyboardOutPort, al

           ;Здесь, после активации строки может возникнуть прерывание, если в строке есть активные биты)
                   
Exit:
           ret
TargetKeyboardInput ENDP

;Подпрограмма для контроля ввода с клавиатуры (мишени)
TargetKeyboardControl PROC NEAR
           cmp   ScanInProgress, False            ;Проверяем, что сканирование НЕ в процессе (завершено)
           jne   Exit
    
           cmp   TargetKeyboardChanged, True      ;Проверяем, что были изменения на клавиатуре (мишени)
           jne   Exit  
           mov   TargetKeyboardChanged, False

           lea   si, PrevTargetKeyboardImage      ;Подготовка 
           lea   di, TargetKeyboardImage
           mov   cx, length TargetKeyboardImage
           mov   TargetKeyboardEmpty, True
           mov   TargetKeyboardError, False
           mov   TargetKeyboardPress, False

CheckEmpty:                                       ;Проверка на пустую клавиатуру (мишень) (EmptyKeyboard)
           mov   al, [di]            
           cmp   al, 0FFh
           jne   NotEmpty
           inc   di
           loop  CheckEmpty
           ret
NotEmpty:  mov   TargetKeyboardEmpty, False

CheckMultiPress:                                  ;Проверка клавиатуры (мишени) на ошибки (KeyboardError)
           mov   dl, 0                            ;dl - счётчик активных бит на клавиатуре
           lea   di, TargetKeyboardImage
           mov   cx, length TargetKeyboardImage

CountPressed:                                     ;Проверяем строку
           mov   al, [di]
           cmp   al, 0FFh
           je    NextRow                          ;Если активных битов в строке нет - переходим к следующей строке
           
           mov   ah, al                           ;Если активные биты в строке есть - считаем активные биты в строке
           mov   al, TargetKeyboardCols
                                
CheckCol:                                         ;Cчитаем активные биты в строке
           shr   ah, 1  
           jnc   Pressed
           dec   al
           jnz   CheckCol
           jmp   NextRow                          

Pressed:                                          ;Увеличиваем счётчик активных бит на клавиатуре (dl) и продолжаем проверку
           inc   dl
           dec   al
           jnz   CheckCol

NextRow:                                          ;Переход к следующей строке
           inc   di
           loop  CountPressed

           cmp   dl, 1                            ;Проверяем счётчик активных бит
           je    CheckFront
           ja    SetError
           ret

SetError:                                         ;Установка ошибки клавиатуры
           mov   TargetKeyboardError, True
           ret

CheckFront:                                       ;Проверка фронта нажатия кнопки
           lea   si, PrevTargetKeyboardImage
           lea   di, TargetKeyboardImage
           mov   cx, length TargetKeyboardImage

FrontLoop:                                        ;Сравниваем предыдущий образ клавиатуры с текущим: выделяем передний фронт
           mov   al, [si]
           mov   ah, [di]
           cmp   al, 0FFh            
           jne   NextFront       
           cmp   ah, 0FFh
           je    NextFront
           mov   TargetKeyboardPress, True
           ret

NextFront:                                        ;Модификация параметров цикла: переходим к проверке следующей строки
           inc   si
           inc   di
           loop  FrontLoop

Exit:
           ret
TargetKeyboardControl ENDP

;Подпрограмма для получения количества очков с клавиатуры (мишени)
GetPointsFromTargetKeyboard PROC NEAR

CheckMissOnTarget:                                ;Проверка промаха по мишени 
           cmp   WaitMissOnTarget, True
           jne   Exit
                
           sub   word ptr TriggerTimer, 1         ;Декремент таймера ожидания попадания
           sbb   word ptr TriggerTimer + 2, 0
           mov   ax, word ptr TriggerTimer
           or    ax, word ptr TriggerTimer + 2
           jnz   CheckHitOnTarget

ResetTriggerTimer:                                        ;Сброс таймера ожидания попадания
           mov   word ptr TriggerTimer, TriggerTimeL
           mov   word ptr TriggerTimer + 2, TriggerTimeH
           mov   WaitMissOnTarget, False
           mov   ReadyToShoot, True
           mov   TargetKeyboardPoints, 0
           ret

CheckHitOnTarget:                                 ;Проверка порпадания по мишени
 
           cmp   TargetKeyboardEmpty, True        ;Проверка ошибок
           je    Exit
           cmp   TargetKeyboardError, True
           je    Exit
           
           cmp   TargetKeyboardPress, True        ;Проверка нажатия на клавиатуру
           jne   Exit
           mov   TargetKeyboardPress, False
           
           mov   WaitMissOnTarget, False          ;Обновляем флаги и сбрасываем таймер ожидания попадания
           mov   ReadyToShoot, True
           mov   word ptr TriggerTimer, TriggerTimeL        
           mov   word ptr TriggerTimer + 2, TriggerTimeH       
           
           lea   bx, TargetKeyboardImage          ;Подготовка к определению очков по мишени
           mov   dx, 0
                   
CheckNextRow:                                     ;Определение строки (dh)
           mov   al, [bx]                         
           cmp   al, 0FFh      
           jnz   CheckNextCol        
           inc   dh          
           inc   bx          
           jmp   short CheckNextRow
           
CheckNextCol:                                     ;Определение колонки (dl)
           shr   al,1                         
           jnc   GetDigit                        
           inc   dl                          
           jmp   short CheckNextCol
           
GetDigit:                                         ;Формировние двоичного кода цифры
           shl   dh, 3                        
           or    dh, dl
                                      
           lea   si, PointsTable                  ;Находим количество очков по таблице                
           xor   ax, ax
           mov   al, dh
           add   si, ax
           mov   al, cs:[si]
                                                     
           mov   TargetKeyboardPoints, al         ;Сохраняем полученный код цифры
           mov   NeedToAddPoints, True
           
Exit:      
           ret
GetPointsFromTargetKeyboard ENDP

;Подпрограмма для добавления очков к счёту текущего игрока
AddPointsToScore PROC NEAR

           cmp   ClearCurrentPlayerPoints, True   ;Проверяем, есть ли необходимость в сбросе счёта текущего игрока
           je    Prepare

           cmp   NeedToAddPoints, True            ;Проверяем, есть ли необходимость в обновлении счёта текущего игрока
           jne   Exit
           mov   NeedToAddPoints, False

Prepare:                                          ;Подготовка: загружаем адрес табло и счётчик циклов
           mov   si, offset Scoreboard            
           mov   cx, 3

SearchLoop:                                       ;Ищем на табло игрока с текущим номером
           mov   al, [si + 1]                     
           cmp   al, CurrentPlayerNumber
           je    FoundPlayer
           add   si, 3                            ;Если не совпало, переходим к следующей записи
           loop  SearchLoop
           ret                                    ;Если дошли до конца и не нашли - можно завершить
                                               
FoundPlayer:                                         
           mov   al, [si + 2]                     ;Загружаем текущий счёт с табло и очки, которые нужно добавить   
           mov   bl, TargetKeyboardPoints
           
           cmp   ClearCurrentPlayerPoints, True
           jne   AddPoints
           mov   ClearCurrentPlayerPoints, False
           mov   al, 0                            ;Очищаем счёт текущего игрока

AddPoints:                                        ;Добавляем очки
           add   al, bl                           
           daa
           
           mov   [si + 2], al                     ;Записываем обновленный счет обратно на табло
           
           mov   TargetKeyboardPoints, 0
           mov   NeedToSortPLayers, True
           
Exit:
           ret
AddPointsToScore ENDP

;Подпрограмма для сортировки игроков на табло
SortPlayersByScore PROC NEAR

           cmp   NeedToSortPLayers, True          ;Проверяем, есть ли необходимость в сортировке игроков на табло
           jne   Exit
           mov   NeedToSortPLayers, False
    
           ;Сортировка пузырьком (3 элемента) по убыванию очков
           mov   cx, 2                            ;Внешний цикл (n-1 итераций)
OuterLoop:
           push  cx                               ;Сохраняем счетчик внешнего цикла
           lea   si, Scoreboard                   ;SI указывает на первого игрока
           mov   di, si
           add   di, 3                            ;DI указывает на второго игрока
           mov   cx, 2                            ;Внутренний цикл (n-1 сравнений)
    
InnerLoop:
           mov   al, [si + 2]                     ;Берем очки первого игрока (BCD)
           mov   bl, [di + 2]                     ;Берем очки второго игрока (BCD)
    
           cmp   al, bl                           ;Сравниваем очки
           jae   NoSwap                           ;Если первый >= второго, не меняем
    
Swap:                                             ;Меняем местами 3 байта (место, номер, очки)
           mov   al, [si]
           xchg  al, [di]
           mov   [si], al
    
           mov   al, [si + 1]
           xchg  al, [di + 1]
           mov   [si + 1], al
    
           mov   al, [si + 2]
           xchg  al, [di + 2]
           mov   [si + 2], al
    
NoSwap:
           add   si, 3                            ;Переходим к следующей паре
           add   di, 3
           loop  InnerLoop
    
           pop   cx                               ;Восстанавливаем счетчик внешнего цикла
           loop  OuterLoop
    
           ;Обновляем места в соответствии с очками
           lea   si, Scoreboard                   ;Начинаем с первого игрока
           mov   byte ptr [si], 1                 ;Первое место
           mov   al, [si + 2]                     ;Очки первого игрока
           mov   bl, 1                            ;Текущее место
           mov   cx, 2                            ;Осталось обработать 2 игрока
    
UpdatePlaces:
           add   si, 3                            ;Переходим к следующему игроку
           mov   dl, [si + 2]                     ;Очки текущего игрока
           cmp   dl, al                           ;Сравниваем с предыдущим
           je    SamePlace                        ;Если равны - то же место
    
           ;Иначе увеличиваем место
           mov   al, dl                           ;Запоминаем новые очки для сравнения
           inc   bl                               ;Увеличиваем место
SamePlace:
           mov   [si], bl                         ;Записываем текущее место
           loop  UpdatePlaces

           ;Сортируем игроков с одинаковыми местами по возрастанию номера
           mov   cx, 2                            ;Внешний цикл (n-1 итераций)
SortByNumOuter:
           push  cx
           lea   si, Scoreboard
           mov   di, si
           add   di, 3
           mov   cx, 2                            ;Внутренний цикл (n-1 сравнений)
    
SortByNumInner:
           mov   al, [si]                         ;Место первого игрока
           mov   bl, [di]                         ;Место второго игрока
           cmp   al, bl                           ;Если места разные - не сортируем
           jne   NoNumSwap
    
           mov   al, [si + 1]                     ;Номер первого игрока
           mov   bl, [di + 1]                     ;Номер второго игрока
           cmp   al, bl                           ;Сравниваем номера
           jbe   NoNumSwap                        ;Если первый <= второго, не меняем
    
NumSwap:                                          ;Меняем местами номера только игроков, так как место и очки у них одинаковые
           mov   al, [si + 1]
           xchg  al, [di + 1]
           mov   [si + 1], al
    
NoNumSwap:
           add   si, 3                            ;Переходим к следующей паре
           add   di, 3
           loop  SortByNumInner
    
           pop   cx
           loop  SortByNumOuter

Exit:          
           ret
SortPlayersByScore ENDP

;Подпрограмма для обработки нажатий на кнопки
HandleButtons PROC NEAR

           cmp   OutOfBullets, True               ;Проверка флагов
           jne   CheckButtonPressed
           cmp   WaitMissOnTarget, True
           je    CheckButtonPressed
           mov   OutOfBullets, False              ;Изменение флагов
           mov   CurrentMode, SelectMode
           mov   WaitMissOnTarget, False
           mov   ReadyToShoot, False
           jmp   LoadBulletCountOption
           
CheckButtonPressed:                               ;Проверяем была ли нажата кнопка
           cmp   ButtonPressed, True
           jne   NoButtonPress
           mov   ButtonPressed, False
           
           mov   al, ButtonPortState
           
MultiModeButtons:                                 ;Обработка кнопок, которые работают во всех режимах
           
ResetScoreboardButton:                            ;Сброс, обнуление статистики на табло
           cmp   al, 7Fh
           jne   NonMultiModeButtons
           
           call  ResetScoreboard
           mov   CurrentMode, SelectMode
           mov   WaitMissOnTarget, False
           mov   ReadyToShoot, False
           jmp   LoadBulletCountOption

NonMultiModeButtons:                              ;Обработка кнопок в зависимоти от режима системы
           cmp   CurrentMode, SelectMode
           je    SelectModeButtons

GameModeButtons:                                  ;Кнопки режима игры
           and   al, 41h
           
TriggerButton:                                    ;Курок
           cmp   al, 40h
           jne   EndGameButton

           cmp   WaitMissOnTarget, True
           je    Exit
           mov   WaitMissOnTarget, True
           mov   ReadyToShoot, False
           mov   al, BulletCount
           sub   al, 1
           das
           mov   BulletCount, al
           jnz   Exit
           mov   OutOfBullets, True
           ret
           
EndGameButton:                                    ;Завершить игру
           cmp   al, 1
           jne   Exit
           
           mov   CurrentMode, SelectMode
           mov   WaitMissOnTarget, False
           mov   ReadyToShoot, False
           jmp   LoadBulletCountOption  
            
SelectModeButtons:                                ;Кнопки режима выбора параметров
           and   al, 3Eh
           
StartGameButton:                                  ;Старт игры
           cmp   al, 1Eh
           jne   PrevPlayerButton
           
           mov   CurrentMode, GameMode
           mov   ReadyToShoot, True
           mov   ClearCurrentPlayerPoints, True
           ret

PrevPlayerButton:                                 ;Предыдущий номер игрока
           cmp   al, 3Ch
           jne   NextPlayerButton

           dec   PlayerNumberOptionIndex
           cmp   PlayerNumberOptionIndex, 0FFh
           jne   LoadPlayerOption
           mov   PlayerNumberOptionIndex, 2
           jmp   LoadPlayerOption
                  
NextPlayerButton:                                 ;Следующий номер игрока
           cmp   al, 3Ah
           jne   PrevBulletCountButton
           
           inc   PlayerNumberOptionIndex
           cmp   PlayerNumberOptionIndex, 3
           jnz   LoadPlayerOption
           mov   PlayerNumberOptionIndex, 0
           
LoadPlayerOption:                                 ;Обновляем текущий номер игрока в системе
           xor   ax, ax
           lea   si, PlayerNumberOptions
           mov   al, PlayerNumberOptionIndex
           add   si, ax
           mov   al, cs:[si]
           mov   CurrentPlayerNumber, al
           ret     

PrevBulletCountButton:                            ;Предыдущий вариант количества пуль
           cmp   al, 36h         
           jne   NextBulletCountButton
           dec   BulletCountOptionIndex
           cmp   BulletCountOptionIndex, 0FFh
           jne   LoadBulletCountOption
           mov   BulletCountOptionIndex, 2
           jmp   LoadBulletCountOption
           
NextBulletCountButton:                            ;Следующий вариант количества пуль
           cmp   al, 2Eh
           jne   Exit
           inc   BulletCountOptionIndex
           cmp   BulletCountOptionIndex, 3
           jnz   LoadBulletCountOption
           mov   BulletCountOptionIndex, 0
           
LoadBulletCountOption:                            ;Обновляем текущее количество пуль в системе
           xor   ax, ax
           lea   si, BulletCountOptions
           mov   al, BulletCountOptionIndex
           add   si, ax
           mov   al, cs:[si]
           mov   BulletCount, al
           ret

NoButtonPress:
Exit:          
           ret
HandleButtons ENDP

;Подпрограмма динамической индикации
;Обновляет один индикатор за вызов в циклическом порядке
Display PROC NEAR
           cmp   CurrentMode, SelectMode          ;Проверка режима работы системы
           jne   NoBlinkMode                      
           
           sub   word ptr BlinkTimer, 1           ;Обработка таймера мигания
           sbb   word ptr BlinkTimer + 2, 0
           mov   ax, word ptr BlinkTimer          
           or    ax, word ptr BlinkTimer + 2
           jnz   UpdateDisplay                    
           mov   word ptr BlinkTimer, BlinkTimeL
           mov   word ptr BlinkTimer + 2, BlinkTimeH
           not   Blink                            
           jmp   UpdateDisplay
                               
NoBlinkMode:                                      ;Отключение мигания в игровом режиме
           mov   Blink, False                     
             
UpdateDisplay:
           mov   al, 0FFh                         ;Отключение всех индикаторов
           out   IndicatorPort1, al
           cmp   ReadyToShoot, True               ;Обработка индикатора готовности
           jne   DisableIndicators                
           and   al, 7Fh                          
           
DisableIndicators:                                
           out   IndicatorPort2, al               
           
           xor   ax, ax                           

ScoreBoardIndicator1:                             ;Загрузка данных места 1-го игрока на табло
           cmp   IndicatorPortState, 1h           
           jne   ScoreBoardIndicator2
           mov   al, byte ptr Scoreboard          
           jmp   LoadDigitImage

ScoreBoardIndicator2:                             ;Загрузка номера 1-го игрока на табло
           cmp   IndicatorPortState, 2h           
           jne   ScoreBoardIndicator3
           mov   al, byte ptr Scoreboard + 1      
           jmp   LoadDigitImage
           
ScoreBoardIndicator3:                             ;Загрузка старшего полубайта счета 1-го игрока на табло
           cmp   IndicatorPortState, 4h           
           jne   ScoreBoardIndicator4
           mov   al, byte ptr Scoreboard + 2      
           shr   al, 4
           jz    RemoveLeadingZero                
           jmp   LoadDigitImage
           
ScoreBoardIndicator4:                             ;Загрузка младшего полубайта счета 1-го игрока на табло
           cmp   IndicatorPortState, 8h
           jne   ScoreBoardIndicator5
           mov   al, byte ptr Scoreboard + 2     
           and   al, 0Fh
           jmp   LoadDigitImage
           
ScoreBoardIndicator5:                             ;Загрузка места 2-го игрока на табло
           cmp   IndicatorPortState, 10h          
           jne   ScoreBoardIndicator6
           mov   al, byte ptr Scoreboard + 3      
           jmp   LoadDigitImage

ScoreBoardIndicator6:                             ;Загрузка номера 2-го игрока на табло
           cmp   IndicatorPortState, 20h          
           jne   ScoreBoardIndicator7
           mov   al, byte ptr Scoreboard + 4      
           jmp   LoadDigitImage
           
ScoreBoardIndicator7:                             ;Загрузка старшего полубайта счета 2-го игрока на табло
           cmp   IndicatorPortState, 40h          
           jne   ScoreBoardIndicator8
           mov   al, byte ptr Scoreboard + 5      
           shr   al, 4
           jz    RemoveLeadingZero                
           jmp   LoadDigitImage
           
ScoreBoardIndicator8:                             ;Загрузка младшего полубайта счета счета 2-го игрока на табло
           cmp   IndicatorPortState, 80h          
           jne   ScoreBoardIndicator9
           mov   al, byte ptr Scoreboard + 5      
           and   al, 0Fh
           jmp   LoadDigitImage

ScoreBoardIndicator9:                             ;Загрузка места 3-го игрока на табло
           cmp   IndicatorPortState, 100h         
           jne   ScoreBoardIndicator10
           mov   al, byte ptr Scoreboard + 6      
           jmp   LoadDigitImage
           
ScoreBoardIndicator10:                            ;Загрузка номера 3-го игрока на табло
           cmp   IndicatorPortState, 200h         
           jne   ScoreBoardIndicator11
           mov   al, byte ptr Scoreboard + 7      
           jmp   LoadDigitImage
           
ScoreBoardIndicator11:                            ;Загрузка старшего полубайта счета 3-го игрока на табло
           cmp   IndicatorPortState, 400h         
           jne   ScoreBoardIndicator12
           mov   al, byte ptr Scoreboard + 8      
           shr   al, 4
           jz    RemoveLeadingZero                
           jmp   LoadDigitImage
           
ScoreBoardIndicator12:                            ;Загрузка младшего полубайта счета 3-го игрока на табло
           cmp   IndicatorPortState, 800h         
           jne   PlayerNumberIndicator
           mov   al, byte ptr Scoreboard + 8      
           and   al, 0Fh
           jmp   LoadDigitImage
           
PlayerNumberIndicator:                            ;Загрузка текущего номера игрока
           cmp   IndicatorPortState, 1000h        
           jne   BulletCountHighIndicator
           mov   al, CurrentPlayerNumber          
           jmp   LoadDigitImage
           
BulletCountHighIndicator:                         ;Загрузка старшего полубайта текущего количества пуль
           cmp   IndicatorPortState, 2000h        
           jne   BulletCountLowIndicator
           mov   al, BulletCount                  
           shr   al, 4
           jz    RemoveLeadingZero                
           jmp   LoadDigitImage
           
BulletCountLowIndicator:                          ;Загрузка младшего полубайта текущего количества пуль
           cmp   IndicatorPortState, 4000h        
           jne   Exit
           mov   al, BulletCount                  
           and   al, 0Fh
           jmp   LoadDigitImage
           
RemoveLeadingZero:                                ;Убираем незаначащий ноль
           mov   al, 10                           ;Код пустого индикатора
           
LoadDigitImage:                                   ;Загрузка образа символа
           lea   si, DigitImages                  
           add   si, ax                          
           mov   al, cs:[si]                      
           
           cmp   IndicatorPortState, 1000h        ;Проверка индикатора игрока
           jne   CheckBulletLowIndicator
           je    CheckBlinkStatus                 ;Переход для проверки мигания
           
CheckBulletLowIndicator:
           cmp   IndicatorPortState, 4000h        ;Проверка младшего индикатора пуль
           jne   OutputDigitToDisplay
           
CheckBlinkStatus:
           cmp   Blink, True                      ;Проверка состояния мигания
           jne   OutputDigitToDisplay
           or    al, 80h                          ;Установка бита мигания

OutputDigitToDisplay:
           out   SegmentPort, al                  ;Вывод образа цифры

           mov   al, byte ptr IndicatorPortState  ;Активация текущего индикатора
           not   al                               
           out   IndicatorPort1, al               
           mov   al, byte ptr IndicatorPortState + 1
           not   al
           cmp   ReadyToShoot, True               
           jne   ActivateIndicator
           and   al, 7Fh                          ;Активация индикатора готовности
           
ActivateIndicator:
           out   IndicatorPort2, al               
           
           shl   IndicatorPortState, 1            ;Переключение на следующий индикатор
           cmp   IndicatorPortState, 8000h        
           jne   Exit
           mov   IndicatorPortState, 1            

Exit:      
           ret
Display ENDP

Start:
           mov   ax, Data                         ;Системная подготовка
           mov   ds, ax
           mov   es, ax
           mov   ax, Stk
           mov   ss, ax
           lea   sp, StkTop
;Здесь размещается код программы

           call  Initialization                   ;Инициализация
           
MainLoop:  call  HandleButtons                    ;Основной цикл
           call  TargetKeyboardInput
           call  TargetKeyboardControl
           call  GetPointsFromTargetKeyboard
           call  AddPointsToScore
           call  SortPlayersByScore
           call  Display
           
           jmp   MainLoop

;В следующей строке необходимо указать смещение стартовой точки
           org   RomSize-16-((InitDataEnd-InitDataStart+15) AND 0FFF0h)
           ASSUME cs:NOTHING
           jmp   Far Ptr Start
Code       ENDS
END		Start

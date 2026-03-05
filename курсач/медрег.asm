.386

RomSize       EQU   4096          ; размер ПЗУ в байтах

; порты ввода-вывода
BTTN_PORT     EQU   1             ; порт кнопок управления
SEG_PORT      EQU   2             ; порт сегментов динамической индикации
CHOICE_L      EQU   3             ; порт выбора индикатора
STEP_PORT     EQU   4             ; порт датчика шагов
EXTRA_PORT    EQU   5             ; дополнительный порт (LED и таймер)
TIMER_PORT_CW EQU   43h           ; порт управляющего регистра таймера
TIMER_PORT    EQU   40h           ; порт счётчика таймера

DAYS_COUNT    EQU   7             ; количество дней хранения данных
HOURS_PER_DAY EQU   24            ; часов в сутках
VIBRTIME      EQU   20            ; время гашения дребезга кнопок

; таблица векторов прерываний
IntTable   SEGMENT use16 AT 0
           org   0FFh * 4         ; смещение вектора прерывания таймера
TimerIntOffs DW ?                 ; смещение обработчика прерывания
TimerIntSeg  DW ?                 ; сегмент обработчика прерывания
IntTable   ENDS

; сегмент данных
Data       SEGMENT use16 AT 40h
BttnPortImg  DB ?    ; образ событий кнопок (фронты 1->0)
LastBttnImg  DB ?    ; предыдущий образ порта кнопок
StepImg      DB ?    ; образ порта датчика шагов
LastStepImg  DB ?    ; предыдущий образ датчика шагов
ModeFlag     DB ?    ; флаг режима: 0=подсчёт, 0FFh=просмотр
ViewDay      DB ?    ; день для просмотра (0..DAYS_COUNT-1)
ViewHour     DB ?    ; час для просмотра (0..HOURS_PER_DAY-1)
CurrDay      DB ?    ; текущий день подсчёта (0..DAYS_COUNT-1)
CurrHour     DB ?    ; текущий час подсчёта (0..HOURS_PER_DAY-1)
TimeCount    DW ?    ; счётчик тиков таймера (~100 тиков/с)
StepCounter  DW ?    ; счётчик шагов за текущий час
; массив часовых данных: DAYS_COUNT строк по HOURS_PER_DAY слов
HourData     DW DAYS_COUNT DUP(HOURS_PER_DAY DUP(?))
DispBuf      DB 4 DUP(?)          ; буфер отображения: 4 цифры
Data       ENDS

; сегмент стека
Stk        SEGMENT use16 AT 200h
           dw    32 dup (?)
StkTop     Label Word
Stk        ENDS

; сегмент инициализационных данных (ПЗУ)
InitData   SEGMENT use16
InitDataStart:
InitDataEnd:
InitData   ENDS

; сегмент кода
Code       SEGMENT use16
           ASSUME cs:Code, ds:Data, es:Data, ss:Stk

; таблица образов цифр 0–9 для 7-сегментного индикатора
digits     db 3Fh, 0Ch, 76h, 05Eh, 4Dh, 5Bh, 7Bh, 0Eh, 7Fh, 5Fh

; =====================================================================
; ResetAll — инициализация всех переменных
; =====================================================================
ResetAll PROC
           ; сброс образов кнопок
           ; БАГ 2 ИСПРАВЛЕН: LastBttnImg = 0FFh (все биты = 1),
           ; чтобы при первом считывании XOR не дал ложных фронтов
           mov  LastBttnImg, 0FFh
           mov  BttnPortImg, 0
           mov  LastStepImg, 0FFh
           mov  StepImg, 0

           ; обнуление счётчиков и режима
           mov  word ptr StepCounter, 0
           mov  word ptr TimeCount, 0
           mov  ModeFlag, 0
           mov  ViewDay, 0
           mov  ViewHour, 0
           mov  CurrDay, 0
           mov  CurrHour, 0

           ; обнуление массива часовых данных
           mov  cx, DAYS_COUNT * HOURS_PER_DAY
           lea  si, HourData
ra_loop:   mov  word ptr [si], 0
           add  si, 2
           loop ra_loop

           ; обнуление буфера отображения
           mov  cx, 4
           lea  si, DispBuf
ra_disp:   mov  byte ptr [si], 0
           inc  si
           loop ra_disp

           ret
ResetAll ENDP

; =====================================================================
; VibrContr — гашение дребезга кнопок
; Вход: al = считанное значение порта
; Выход: al = стабильное значение порта
; =====================================================================
VibrContr PROC
           push cx
 vd_reset:
           mov  cx, VIBRTIME
 vd_same:
           mov  ah, al
           in   al, BTTN_PORT
           xor  ah, al
           jnz  vd_reset
           loop vd_same
           pop  cx
           ret
VibrContr ENDP

; =====================================================================
; BttnInput — обработка ввода кнопок
; БАГ 3 ИСПРАВЛЕН: сначала маска (or al, 80h), потом сохранение (mov ah, al)
; =====================================================================
BttnInput PROC
           in   al, BTTN_PORT
           call VibrContr          ; гашение дребезга
           or   al, 80h            ; СНАЧАЛА маскируем бит 7 (незначимые биты)
           mov  ah, al             ; AH = замаскированное состояние для сохранения
           xor  al, LastBttnImg   ; биты, изменившиеся с прошлого цикла
           and  al, LastBttnImg   ; выделяем фронты 1->0 (кнопка отпущена)
           mov  BttnPortImg, al   ; запись образа событий
           mov  LastBttnImg, ah   ; сохраняем замаскированное состояние
           ret
BttnInput ENDP

; =====================================================================
; IndOutput — вывод 4 цифр на 7-сегментный индикатор (динамическая индикация)
; БАГ 4 ИСПРАВЛЕН: добавлены паузы (NOP) чтобы индикатор успел засветиться
; =====================================================================
IndOutput PROC
           push ax
           push bx
           push cx
           push si

           lea  bx, digits
           lea  si, DispBuf
           mov  ah, 0FEh           ; маска выбора: первый индикатор — бит 0 = 0
           mov  cx, 4

io_loop:
           mov  al, [si]           ; считать цифру из буфера
           xlat digits             ; преобразовать в образ сегментов
           out  SEG_PORT, al       ; вывести на сегментный порт

           mov  al, ah
           out  CHOICE_L, al       ; включить текущий индикатор
           nop                     ; пауза: время для засветки индикатора
           nop
           nop
           mov  al, 0FFh
           out  CHOICE_L, al       ; выключить все индикаторы

           rol  ah, 1              ; следующий индикатор
           inc  si
           loop io_loop

           pop  si
           pop  cx
           pop  bx
           pop  ax
           ret
IndOutput ENDP

; =====================================================================
; UpdateExtraPort — обновление дополнительного порта
; Уже исправлено: 11h для подсчёта, 81h для просмотра
; =====================================================================
UpdateExtraPort PROC
           cmp  ModeFlag, 0FFh
           jz   uep_view
           mov  al, 11h            ; режим подсчёта: бит 4 (таймер) + бит 0
           out  EXTRA_PORT, al
           jmp  uep_exit
uep_view:
           mov  al, 81h            ; режим просмотра: бит 7 (LED) + бит 0
           out  EXTRA_PORT, al
uep_exit:
           ret
UpdateExtraPort ENDP

; =====================================================================
; CalcAndSaveHour — сохранение данных часа и переход к следующему
; =====================================================================
CalcAndSaveHour PROC
           push ax
           push bx

           ; вычислить смещение HourData[CurrDay][CurrHour]
           xor  ah, ah
           mov  al, CurrDay
           mov  bl, HOURS_PER_DAY
           mul  bl                 ; ax = CurrDay * HOURS_PER_DAY
           add  al, CurrHour       ; ax = CurrDay * 24 + CurrHour
           adc  ah, 0
           shl  ax, 1              ; ax *= 2 (индекс слова -> байтовое смещение)
           lea  bx, HourData
           add  bx, ax             ; bx -> HourData[CurrDay][CurrHour]

           ; сохранить накопленные шаги
           mov  ax, StepCounter
           mov  [bx], ax

           ; обнулить счётчик шагов
           mov  word ptr StepCounter, 0

           ; перейти к следующему часу
           inc  CurrHour
           cmp  CurrHour, HOURS_PER_DAY
           jb   csh_exit
           mov  CurrHour, 0
           inc  CurrDay
           cmp  CurrDay, DAYS_COUNT
           jb   csh_exit
           mov  CurrDay, 0         ; циклическое переполнение дней

csh_exit:
           pop  bx
           pop  ax
           ret
CalcAndSaveHour ENDP

; =====================================================================
; TimerInt — обработчик прерывания таймера (INT 0FFh)
; =====================================================================
TimerInt PROC
           push ax
           push bx

           ; инкремент счётчика тиков (~100 тиков/сек)
           inc  word ptr TimeCount

           ; каждые 36000 тиков (~1 час) сохраняем данные часа
           cmp  word ptr TimeCount, 36000
           jb   ti_step
           mov  word ptr TimeCount, 0
           call CalcAndSaveHour

ti_step:
           ; определение шагов: фронт 0->1 на бите 0 датчика шагов
           in   al, STEP_PORT
           mov  ah, al
           xor  ah, LastStepImg
           and  ah, al             ; биты, перешедшие из 0 в 1 (фронты нажатия)
           mov  LastStepImg, al
           test ah, 01h
           jz   ti_exit
           ; шаг обнаружен — увеличить счётчик шагов
           inc  word ptr StepCounter

ti_exit:
           pop  bx
           pop  ax
           iret
TimerInt ENDP

; =====================================================================
; HandleButtons — обработка нажатий кнопок
; =====================================================================
HandleButtons PROC
           ; Бит 0: переключение режима подсчёт <-> просмотр
           test BttnPortImg, 01h
           jz   hb_day
           cmp  ModeFlag, 0
           jz   hb_to_view
           mov  ModeFlag, 0        ; возврат в режим подсчёта
           jmp  hb_day
hb_to_view:
           mov  ModeFlag, 0FFh     ; переход в режим просмотра
           mov  ViewDay, 0
           mov  ViewHour, 0

hb_day:
           ; кнопки навигации активны только в режиме просмотра
           cmp  ModeFlag, 0FFh
           jnz  hb_exit

           ; Бит 1: предыдущий день
           test BttnPortImg, 02h
           jz   hb_day_next
           cmp  ViewDay, 0
           jz   hb_day_wrap_back
           dec  ViewDay
           jmp  hb_day_next
hb_day_wrap_back:
           mov  ViewDay, DAYS_COUNT - 1

hb_day_next:
           ; Бит 2: следующий день
           test BttnPortImg, 04h
           jz   hb_hour
           inc  ViewDay
           cmp  ViewDay, DAYS_COUNT
           jb   hb_hour
           mov  ViewDay, 0

hb_hour:
           ; Бит 3: следующий час для просмотра
           test BttnPortImg, 08h
           jz   hb_exit
           inc  ViewHour
           cmp  ViewHour, HOURS_PER_DAY
           jb   hb_exit
           mov  ViewHour, 0

hb_exit:
           ret
HandleButtons ENDP

; =====================================================================
; FormDisplay — подготовка 4-цифрового буфера отображения
;
; Режим подсчёта: показываем StepCounter (шаги за текущий час)
; Режим просмотра: БАГ 5 ИСПРАВЛЕН — суммируем шаги за ВСЕ 24 часа
;                  выбранного дня (накопительно за день)
; =====================================================================
FormDisplay PROC
           push ax
           push bx
           push cx
           push dx
           push si

           cmp  ModeFlag, 0FFh
           jz   fd_view

           ; режим подсчёта: текущий счётчик шагов за час
           mov  ax, StepCounter
           jmp  fd_bcd

fd_view:
           ; режим просмотра: сумма шагов за все 24 часа выбранного дня
           ; (БАГ 5 ИСПРАВЛЕН: накопительный итог за день, а не данные одного часа)
           xor  dx, dx             ; dx = накопленная сумма

           ; вычислить базовый адрес HourData[ViewDay][0]
           xor  ah, ah
           mov  al, ViewDay
           mov  bl, HOURS_PER_DAY
           mul  bl                 ; ax = ViewDay * HOURS_PER_DAY
           shl  ax, 1              ; ax *= 2 (байтовое смещение)
           lea  si, HourData
           add  si, ax             ; si -> HourData[ViewDay][0]

           ; суммируем шаги за все 24 часа
           mov  cx, HOURS_PER_DAY
fd_sum:
           mov  ax, [si]
           add  dx, ax
           add  si, 2
           loop fd_sum

           mov  ax, dx             ; ax = итого шагов за день

fd_bcd:
           ; ограничение до 9999 для 4-цифрового отображения
           cmp  ax, 9999
           jna  fd_conv
           mov  ax, 9999
fd_conv:
           ; разбивка ax на 4 цифры и запись в DispBuf
           lea  si, DispBuf

           ; тысячи
           xor  dx, dx
           mov  cx, 1000
           div  cx                 ; al = тысячи, dx = остаток
           mov  [si], al
           inc  si

           ; сотни
           mov  ax, dx
           xor  dx, dx
           mov  cx, 100
           div  cx                 ; al = сотни, dx = остаток
           mov  [si], al
           inc  si

           ; десятки
           mov  ax, dx
           xor  dx, dx
           mov  cx, 10
           div  cx                 ; al = десятки, dx = единицы
           mov  [si], al
           inc  si

           ; единицы
           mov  [si], dl

           pop  si
           pop  dx
           pop  cx
           pop  bx
           pop  ax
           ret
FormDisplay ENDP

; =====================================================================
; Start — программная подготовка и основной цикл
; =====================================================================
Start:
           cli                     ; запрет прерываний при инициализации

           ; инициализация сегментных регистров
           mov  ax, Data
           mov  ds, ax
           mov  es, ax
           mov  ax, Stk
           mov  ss, ax
           lea  sp, StkTop

           ; установка обработчика прерывания таймера (INT 0FFh)
           ; БАГ 1 ИСПРАВЛЕН: OFFSET TimerInt — берёт адрес (смещение) процедуры,
           ; а не содержимое памяти по адресу TimerInt
           push ds
           mov  ax, IntTable
           mov  ds, ax
           mov  ax, OFFSET TimerInt
           mov  ds:TimerIntOffs, ax
           mov  ax, Code
           mov  ds:TimerIntSeg, ax
           pop  ds

           ; инициализация таймера (генерирует прерывание 0FFh)
           mov  al, 16h
           out  TIMER_PORT_CW, al
           mov  al, 2
           out  TIMER_PORT, al

           ; инициализация переменных
           ; (внутри ResetAll: LastBttnImg = 0FFh — БАГ 2 исправлен)
           call ResetAll

           sti                     ; разрешение прерываний

main_loop:
           call BttnInput          ; считывание и обработка кнопок
           call HandleButtons      ; логика навигации по режимам/дням/часам
           call UpdateExtraPort    ; обновление дополнительного порта
           call FormDisplay        ; подготовка буфера отображения
           call IndOutput          ; вывод на 7-сегментный индикатор

           jmp  main_loop

           org  RomSize-16-((InitDataEnd-InitDataStart+15) AND 0FFF0h)
           ASSUME cs:NOTHING
           jmp  Far Ptr Start
Code       ENDS
END        Start

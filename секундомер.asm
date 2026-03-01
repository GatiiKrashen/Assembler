.386
RomSize      EQU   4096 ;размер ПЗУ
SegPort      EQU   1    ;порт сегментов динамической индикации
ChoicePort   EQU   2    ;порт выбора индикатора
RaceDispPort EQU   3    ;порт вывода забега
BttnPort     EQU   1    ;порт кнопок управления
TrackInpPort EQU   2    ;порт датчиков дорожек
TrackLedPort EQU   4    ;порт индикаторов дорожек
TimerPort_CW EQU   43h  ;порты управления таймером
TimerPort    EQU   40h

TrackLen     EQU   5    ;длина результата одной дорожки
RaceLen      EQU   8    ;количество дорожек в забеге
ResultsLen   EQU   4    ;количтво забегов всего
ErrorMsgLen  EQU   8    ;длина сообщения об ошибке
Vibrtime     EQU   20   ;время гашения дребезга

IntTable   SEGMENT use16 AT 0
            org 0ffh * 4;смещение вектора прерывания таймера
            IntFFHandlerPtrOffs DW ? 
            IntFFHandlerPtrSeg  DW ?
IntTable   ENDS

Data       SEGMENT use16 AT 400h
            BttnPortImg  DB ? ;образ порта кнопок
            LastBttnImg  DB ? ;прошлой образ порта кнопок
            TrackPortImg DB ? ;образ порта дорожек
            LastTrackImg DB ? ;прошлой образ порта дорожек

            TrackEndFlag DB ? ;флаг срабатывания дорожек
            TimeErrFlag  DB ? ;флаг ошибки переполнения времени
            RaceErrFlag  DB ? ;флаг ошибки переполнения забегов
            StartFlag    DB ? ;флага работы таймера
            DispModeFlag DB ? ;флаг режима отображения

            CurrRace     DB ? ;номер текущего забега
            DispRace     DB ? ;номер отображаемого забега
            DispTrack    DB ? ;номер отображаемого результата

            Time         DB 4 DUP(?) ;счетчик времени
            ;массив результатов
            Results      DB ResultsLen DUP(RaceLen DUP(TrackLen DUP(?)))
Data       ENDS

Stk        SEGMENT use16 AT 500h
           dw    10 dup (?)
StkTop     Label Word
Stk        ENDS

Code       SEGMENT use16
           ASSUME cs:Code, ds:Data, es:Data, ss: Stk   
           ;таблица образов цифр
digits     db 3Fh, 0Ch, 76h, 05Eh, 4Dh, 5Bh, 7Bh, 0Eh, 7Fh, 5Fh 
           ;сообщение об ошибке
ErrorMsg   db 73h, 60h, 60h, 78h, 60h,    0,    0,    0     

Prepfunc PROC ;функциональная подготовка
            ;сброс прошлых образов портов
            mov LastTrackImg, 0ffh
            mov LastBttnImg, 0ffh
            ;сброс флага работы секундомера
            mov StartFlag, 0
            ;обнуление времени
            mov word ptr Time, 0
            mov word ptr Time+2, 0
            ;обнуление массива результатов
            mov cx, RaceLen * TrackLen * ResultsLen / 2
            lea si, Results
 pfres:     mov word ptr [si], 0
            add si, 2
            loop pfres
            ;сброс флагов
            mov TrackEndFlag, 0
            mov RaceErrFlag, 0
            mov TimeErrFlag,0
            mov DispModeFlag, 0
            ;обнуление номеров забега и дорожек
            mov CurrRace, -1
            mov DispRace, 0
            mov DispTrack, 0

Prepfunc  ENDP

InitTimer PROC ;подготовка рабыты таймера
           mov   al, 16h             
           out   TimerPort_CW, al
           mov   al, 2             
           out   TimerPort, al
           ret
InitTimer ENDP   

VibrContr PROC  ;гашение дребезга кнопок
            push cx
 vd_reset:
            mov  cx, Vibrtime
 vd_same_input:        
            mov  ah, al
            in   al, BttnPort

            xor  ah, al
            jnz  vd_reset

            loop vd_same_input
            pop  cx
            ret
VibrContr ENDP 

BttnInput PROC ;обработка ввода кнопок
            in   al, BttnPort
            call VibrContr ;гашение дребезга
            mov ah, al
            or   al, 0f0h ;1111 0000 гашение незначимых битов
            xor al, LastBttnImg ;веделение фронта
            and al, LastBttnImg
            mov BttnPortImg, al ;запись образа
            mov LastBttnImg, ah ;запись образа в прошлый
            ret
BttnInput ENDP
            
TrackInput PROC;обработка датчиков дорожек
            in   al, TrackInpPort ;ввод с порта
            mov ah, al
            ;выделение фронта
            xor al, LastTrackImg
            and al, LastTrackImg
            ;сохранение
            mov TrackPortImg, al
            mov LastTrackImg, ah
            ret
TrackInput ENDP

TimeForm PROC ;отсчет времени
            ;срабатывает по прерыванию таймера
            ;сохранение состояний регистра
            push ax
            ;проверка состояния секундомера
            cmp StartFlag, 0ffh
            jnz tfexit ; переход если остановлен
            ;инкремент времени
            ;обработка миллисекунд
            mov al, Time+3
            add al, 1
            daa
            mov Time+3, al
            ;обработка секунд
            mov al, Time+2
            adc al, 0
            daa
            mov Time+2, al
            shr al, 4
            cmp al, 5
            jna tfexit ;выход если переноса нет
            mov Time+2, 0
            ;обработка минут
            mov al, Time+1
            add al, 1
            daa
            mov Time+1, al
            shr al, 4
            cmp al, 5
            jna tfexit ;выход если переноса нет
            mov Time+1, 0
            ;обработка часов
            inc Time
            cmp Time, 9
            jna tfexit
            mov TimeErrFlag, 0ffh
            jmp tfexit
 tfexit:    
            ;восстановление состояний регистров
            pop ax
            iret
TimeForm ENDP

StartForm PROC ;формирование флага работы секундомера
            ;проверка ошибок
            mov al, RaceErrFlag
            or al, TimeErrFlag
            cmp al, 0ffh
            jnz sf_err_skip; переход если ошибок нет
            mov StartFlag, 0 ;остановка секундомера
            jmp sfexit
 sf_err_skip:            
            ;проверка состояния секундомера
            cmp StartFlag, 0ffh
            jnz sf_not_started  ;переход если секундомер стоит
            
            ;секундомер идет
            ;проверка если все дорожки уже сработали
            ;обновление флага срабатывания дорожек
            mov al, TrackPortImg 
            or TrackEndFlag, al
            cmp TrackEndFlag, 0ffh ;проверка флага
            jnz sfexit ;выход если не все дорожки сработали
            mov StartFlag, 0;остановка секундомера
            jmp sfexit
 sf_not_started:
            ;секундомер стоит
            mov TrackEndFlag, 0 ;обнуление флага сработавших дорожек
            ;проверка кнопки старта
            test BttnPortImg, 01 ;0000 0001
            jz  sfexit;выход если кнопка не нажата
            ;обнуление таймера
            mov word ptr Time, 0
            mov word ptr Time+2, 0
            mov StartFlag, 0ffh;запуск секундомера
 sfexit:
            ret
StartForm ENDP

RaceNumForm PROC ;формирование номера забега
            ;проверка состояния секундомера
            cmp StartFlag, 0ffh
            jz rnfexit ;выход если секундомер идет
            ;проверка кнопки старт
            test BttnPortImg, 01 ;0000 0001
            jz  rnf_start_skip
            ;кнопка нажата
            ;увеличение текущего забега
            inc CurrRace
            ;смена отображаемого забега
            mov al, CurrRace
            mov DispRace, al
            ;проверка ошибки переполения забегов
            cmp CurrRace, 4
            jnz rnf_err_skip
            mov RaceErrFlag, 0ffh ;поднятие флага ошибки забегов
 rnf_err_skip:
            jmp rnfexit
 rnf_start_skip:
            ;кнопка старт не нажата
            ;проверка кнопки след. забега
            test BttnPortImg, 04 ;0000 0100
            jz  rnfexit
            ;отображение след. забега
            inc DispRace
            ;зацикливание больше 4 забегов
            cmp DispRace, 4
            jnz rnfexit
            mov DispRace, 0
 rnfexit:
            ret
RaceNumForm ENDP

TrackNumForm PROC;формирование номера дорожки
            ;проверка состояния секундомера
            cmp StartFlag, 0ffh
            jz tnfexit ;выход если секундомер идет
            ;проверка кнопки след. дорожки
            test BttnPortImg, 08 ;0000 1000
            jz  tnfexit
            ;отображение след. дорожки
            inc DispTrack
            ;зацикливание больше 8 дорожек
            cmp DispTrack, 8
            jnz tnfexit
            mov DispTrack, 0
 tnfexit:            
            ret
TrackNumForm ENDP

DispModeChange PROC ;смена режима отображения
            ;проверка состояния секундомера
            cmp StartFlag, 0ffh
            jnz dmcpaused
            ;секундомер идет
            mov DispModeFlag, 0 ;режим отображения тек. времени
            jmp dmcexit
 dmcpaused: 
            ;секундомер стоит
            ;проверка срабатывания всех дорожек
            ;(т.е. секундомер только что остановился)
            cmp TrackEndFlag, 0ffh
            jnz dmcexit
            mov DispModeFlag, 0ffh ;режим отображения результатов
 dmcexit:
            ret
DispModeChange ENDP

CurrTimeDisp PROC ;отображение текущего времени
            ;проверка ошибок
            mov al, RaceErrFlag
            or al, TimeErrFlag
            cmp al, 0ffh
            jz ctdexit
            ;проверка режима отображения 
            cmp DispModeFlag, 0ffh
            jz ctdexit ;если режим отображ резуль. то выход
            ;подготовка массива образов 
            lea  bx, digits
            ;статический вывод номера забега
            mov al, CurrRace
            inc al
            xlat digits
            out RaceDispPort, al

            ;динамический вывод времени
            ;подготовка регистра для выбора индикаторов
            mov ah, 0FDh ; 1111 1101

            ;вывод цифры часов
            ;чтение часов
            mov al, Time
            ;табличное преобразование в образ
            xlat digits
            ;вывод на индикатоор
            out SegPort, al
            ;включение индикатора часов
            mov al, ah
            out ChoicePort, al
            ;выключение всех индикаторов
            mov al, 0ffh
            out ChoicePort, al
            ;сдвиг регистра выбора индикаторов
            ;rol ah, 1
            ;подготовка цикла
            mov cx, 3
            lea si, Time + 1
 ctd_loop:
            ;сдвиг регистра выбора индикаторов
            rol ah, 1
            ;выделение старшей цифры числа
            mov al, [si]
            shr al, 4
            ;табличное преобразование в образ
            xlat digits
            ;вывод на индикатоор
            out SegPort, al
            ;выбор старшего индикатора
            mov al, ah
            out ChoicePort, al
            ;выключение всех индикаторов
            mov al, 0ffh
            out ChoicePort, al

            ;сдвиг регистра выбора индикаторов
            rol ah, 1
            ;выделение младшей цифры числа
            mov al, [si]
            and al, 0fh
            ;табличное преобразование в образ
            xlat digits
            ;вывод на индикатоор
            out SegPort, al
            ;выбор младшего индикатора
            mov al, ah
            out ChoicePort, al
            ;выключение всех индикаторов
            mov al, 0ffh
            out ChoicePort, al

            ;модификация адреса источника
            inc si
            loop ctd_loop

            ;вывод точки после секунд
            mov al, 80h;1000 0000
            out SegPort, al
            ;выбор индикатора секунд
            mov al, 0DFh ;1101 1111
            out ChoicePort, al
            ;выключение всех индикаторов
            mov al, 0ffh
            out ChoicePort, al

 ctdexit:
            ret
CurrTimeDisp ENDP

ResultDisp PROC ;отображение сохраненных результатов
            ;проверка ошибок
            mov al, RaceErrFlag
            or al, TimeErrFlag
            cmp al, 0ffh
            jz rdexit
            ;проверка режима вывода 
            cmp DispModeFlag, 0ffh
            jnz rdexit ;если режим текущего врем. то выход
            ;адрес конкретного результата в будет si
            lea si, Results
            ;смещение не текущий забег
            mov al, RaceLen * TrackLen
            mul DispRace
            xor ah, ah
            add si, ax
            ;смещение на текущую дорожку
            mov al, TrackLen
            mul DispTrack
            xor ah, ah
            add si, ax

            ;вывод 
            ;подготовка массива образов 
            lea  bx, digits

            ;статический вывод номера забега
            mov al, DispRace
            inc al
            xlat digits
            out RaceDispPort, al

            ;динамический вывод времени и номера дорожки
            ;подготовка регистра для выбора индикаторов
            mov ah, 0FEh ; 1111 1110

            ;вывод цифры номера дорожки
            ;чтение номера дорожки
            mov al, [si]
            ;табличное преобразование в образ
            xlat digits
            ;вывод на индикатоор
            out SegPort, al
            ;включение индикатора номера дорожки
            mov al, ah
            out ChoicePort, al
            ;выключение всех индикаторов
            mov al, 0ffh
            out ChoicePort, al
            ;сдвиг регистра выбора индикаторов
            rol ah, 1
            inc si
            ;вывод цифры часов
            ;чтение часов
            mov al, [si]
            ;табличное преобразование в образ
            xlat digits
            ;вывод на индикатоор
            out SegPort, al
            ;включение индикатора часов
            mov al, ah
            out ChoicePort, al
            ;выключение всех индикаторов
            mov al, 0ffh
            out ChoicePort, al
            ;сдвиг регистра выбора индикаторов
            ;rol ah, 1
            inc si

            mov cx, 3
  rd_loop:
            ;сдвиг регистра выбора индикаторов
            rol ah, 1
            ;выделение старшей цифры числа
            mov al, [si]
            shr al, 4
            ;табличное преобразование в образ
            xlat digits
            ;вывод на индикатоор
            out SegPort, al
            ;выбор старшего индикатора
            mov al, ah
            out ChoicePort, al
            ;выключение всех индикаторов
            mov al, 0ffh
            out ChoicePort, al

            ;сдвиг регистра выбора индикаторов
            rol ah, 1
            ;выделение младшей цифры числа
            mov al, [si]
            and al, 0fh
            ;табличное преобразование в образ
            xlat digits
            ;вывод на индикатоор
            out SegPort, al
            ;выбор младшего индикатора
            mov al, ah
            out ChoicePort, al
            ;выключение всех индикаторов
            mov al, 0ffh
            out ChoicePort, al

            ;модификация адреса источника
            inc si
            loop rd_loop

            ;вывод точки после секунд
            mov al, 80h;1000 0000
            out SegPort, al
            ;выбор индикатора секунд
            mov al, 0DFh ;1101 1111
            out ChoicePort, al
            ;выключение всех индикаторов
            mov al, 0ffh
            out ChoicePort, al
 rdexit:            
            ret
ResultDisp ENDP

ErrorDisp PROC ;вывод сообщение об ошибке
            ;проверка ошибок
            mov al, RaceErrFlag
            or al, TimeErrFlag
            cmp al, 0ffh
            jnz edexit ; если ошибок нет - выход     
            ;очистка индикатора номера забега
            mov al, 0
            out RaceDispPort, al
            ;подготовка к выводу сообщения
            mov ah, 0FEh ; 1111 1110
            lea si, ErrorMsg
            mov cx, ErrorMsgLen
 ed_loop:          
            mov al, cs:[si] ;вывод символа
            out SegPort, al
            ;выбор индикатора
            mov al, ah
            out ChoicePort, al
            ;выключение всех индикаторов
            mov al, 0ffh
            out ChoicePort, al
            ;модификация адреса источника
            inc si
            rol ah, 1
            loop ed_loop
 edexit:
            ret
ErrorDisp ENDP

TrackDisp PROC ;вывод сработавших датчиков дорожек
            ;проверка ошибок
            mov al, RaceErrFlag
            or al, TimeErrFlag
            cmp al, 0ffh
            jz td_off
            ;проверка режима вывода 
            cmp DispModeFlag, 0ffh
            jz td_off ;если режим отображ резуль. то выключить
            
            mov al, TrackEndFlag
            out TrackLedPort, al 
            jmp tdexit
 td_off:
            mov al, 0
            out TrackLedPort, al 
 tdexit:
            ret
TrackDisp ENDP

ResetResults PROC ;сброс резулльтатов
            ;проверка состояния секундомера
            cmp StartFlag, 0ffh
            jz rrexit ;если время идет то выход
            ;проверка кнопки сброса
            test BttnPortImg, 02 ;0000 0010
            jz rrexit
            ;если не нажата - выход

            ;обнуление результатов
            mov cx, RaceLen * TrackLen * ResultsLen / 2
            lea si, Results
 rr_loop:
            mov word ptr [si], 0
            add si, 2
            loop rr_loop

            ;сброс времени
            mov word ptr Time, 0
            mov word ptr Time+2, 0
            ;обнуление переменных и флагов
            mov LastTrackImg, 0ffh
            mov LastBttnImg, 0ffh
            mov StartFlag, 0

            mov RaceErrFlag, 0
            mov TimeErrFlag, 0
            
            mov CurrRace, -1
            mov DispRace, 0
            mov DispTrack, 0
 rrexit:    
            ret           
ResetResults ENDP

SaveResult PROC ;сохранение результатов
            ;проверка состояния секундомера
            cmp StartFlag, 0ffh
            jnz srexit ;если время не идет то выход
            ;подготовка цикла
            mov cx, RaceLen
            ;установка di на начало текущего забега
            lea di, Results
            mov al, RaceLen * TrackLen
            mul CurrRace
            xor ah, ah
            add di, ax

            mov dh, TrackPortImg ;образ порта датчиков
            mov dl, 1;номер дорожки
 sr_loop:
            shr dh, 1 ;выделение бита 
            jnc sr_next_loop; пропуск если бит порта = 0
            ;проверка пустой записи
            mov ax, word ptr [di+1]
            or ax, word ptr [di+3]
            cmp ax, 0
            jnz sr_next_loop ;пропуск если в записи уже что то есть
            ;запись номера дорожки
            mov [di], dl           
            ;записть времени
            mov ax, word ptr Time
            mov [di+1], ax
            mov ax, word ptr Time + 2
            mov [di+3], ax
 sr_next_loop:
            add di, TrackLen
            inc dl
            loop sr_loop
 srexit:
            ret
SaveResult ENDP

RaceSort PROC ;сортировка результатов забега
            ;проверка срабатывания всех дорожек
            cmp TrackEndFlag, 0ffh
            jnz rsexit ;если сработали не все дорожки - выход

            ;подготовка
            ;установка адреса текущего забега
            lea di, Results
            mov al, RaceLen * TrackLen
            mul CurrRace
            xor ah, ah
            add di, ax

            mov cx, RaceLen-1 ;счетчик внешного цикла
 rs_out_loop:
            push cx
            mov cx, RaceLen-1 ;счетчик внутреннего цикла
            mov si, di
 rs_in_loop:
            ;сравнение 2х элементов
            
            ; сравнение часов
            mov al, [si+1]
            cmp al, [si+1+TrackLen]
            ja rs_swap ;переход к смене если больше
            jb rs_swap_skip ;переход к след. эл. если меньше
            ; сравнение минут
            mov al, [si+2]
            cmp al, [si+2+TrackLen]
            ja rs_swap ;переход к смене если больше
            jb rs_swap_skip ;переход к след. эл. если меньше
            ; сравнение секунд
            mov al, [si+3]
            cmp al, [si+3+TrackLen]
            ja rs_swap ;переход к смене если больше
            jb rs_swap_skip ;переход к след. эл. если меньше
            ; сравнение сотых секунд
            mov al, [si+4]
            cmp al, [si+4+TrackLen]
            ja rs_swap ;переход к смене если больше
            jmp rs_swap_skip ;переход к след. эл.

 rs_swap:   ;замена элементов
            ;смена номеров дорожек
            mov al, [si]
            xchg al, [si+TrackLen]
            mov [si], al 
            ;смена часов и минут
            mov ax, word ptr [si+1]
            xchg ax, word ptr [si+TrackLen+1]
            mov word ptr [si+1], ax 
            ;смена секунд и сотых секунд
            mov ax, word ptr [si+3]
            xchg ax, word ptr [si+TrackLen+3]
            mov word ptr [si+3], ax 
 rs_swap_skip:
            add si, TrackLen;переход к следующей паре элементов
            loop rs_in_loop;внутренний цикл

            pop cx
            loop rs_out_loop;внешний цикл
 rsexit:
            ret
RaceSort ENDP

Start:  
        ;программная подготовка
            cli ;запрет прерывания
            mov   ax, Data
            mov   ds, ax
            mov   es, ax
            mov   ax, Stk
            mov   ss, ax
            lea   sp, StkTop
            ;установка процедуры отсчета времени
            ;в вектор прерывания таймера
            push  ds
            mov   ax, IntTable
            mov   ds, ax
            mov   ax, cs:TimeForm
            mov   ds:IntFFHandlerPtrOffs, ax
            mov   ax, Code
            mov   ds:IntFFHandlerPtrSeg, ax
            pop   ds

            call Prepfunc
            call InitTimer
            sti ;разрешение прерывания
 main_loop:
            call BttnInput
            call TrackInput

            call SaveResult
            call RaceNumForm
            
            call StartForm
            call TrackNumForm
            call DispModeChange
            
            call ResetResults
            call RaceSort
            
            call CurrTimeDisp
            call ResultDisp
            call ErrorDisp
            call TrackDisp

            jmp main_loop
        ;смещение стартовой точки
            org   RomSize-16
            ASSUME cs:NOTHING
            jmp   Far Ptr Start
Code       ENDS
END		Start

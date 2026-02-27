.386

RomSize    EQU   4096
OutPort_LOW = 0      
OutPort_HIGH = 1    
inport = 0

IntTable   SEGMENT use16 AT 0

           org   4*20h 
           Int20hVect dd ?
           
IntTable   ENDS

Data       SEGMENT use16 AT 40h

           counter    db ?  
           Old      DB    ?
           
Data       ENDS

Stk        SEGMENT use16 AT 0100h
           dw    0100 dup (?)
StkTop     Label Word
Stk        ENDS

InitData   SEGMENT use16
InitDataStart:
InitDataEnd:
InitData   ENDS

Code       SEGMENT use16

digits     db 03Fh, 00Ch, 076h, 05Eh, 04Dh, 05Bh, 07Bh, 00Eh, 07Fh, 05Fh
           ASSUME cs:Code, ds:Data, ds:IntTable, es:Data, ss: Stk

ShowCounter      PROC NEAR
           ;Вывод младшей цифры
           mov   al, counter
           and   al, 0fh
           xlat  digits
           out   OutPort_LOW, al
           
           ;Вывод стершей цифры
           mov   al, counter
           shr   al, 4
           xlat  digits
           out   OutPort_HIGH, al

           ret
ShowCounter      ENDP

IncCounter       PROC FAR
           ;Обработка дребезга         
           in    al,inport
VD1:       mov   ah,al       
           mov   dh,0       
VD2:        
           in    al,inport   
           cmp   ah, al      
           jne   VD1         
           inc   dh          
           cmp   dh, 50      
           jne   VD2        

           ;Проверка фронта 
           mov   ah, al
           xor   al, Old
           and   al, ah      
           mov   Old, ah
           jz m1 
           
           ;Инкремент
           mov   al, counter
           add   al,1
           daa
           mov   counter, al 

m1:        iret
IncCounter       ENDP

Start:
           mov   ax, Data
           mov   ds, ax
           mov   es, ax
           mov   ax, Stk
           mov   ss, ax
           lea   sp, StkTop
          
           ;Загрузка адреса прерывания
           push  ds                      ;Сохранение Data в стеке
           mov   ax, IntTable            
           mov   ds, ax
           mov   ax, IncCounter              ;Записываем в ax смещение прерывание
           mov   WORD PTR Int20hVect, ax     ;Загрузка смещения прерывания
           mov   ax, Code                    ;Записываем в ax сегмент прерывания
           mov   WORD PTR Int20hVect + 2, ax ;Загрузка сегмента прерывания
           pop   ds                          ;Востановление Data
           
           mov   bx, 0
           mov   counter, 0
           mov   Old, 0

           ;Разрешаем прерывания
           sti
MainLoop:
           call  ShowCounter 
           jmp   MainLoop
           
           
           org   RomSize-16-((InitDataEnd-InitDataStart+15) AND 0FFF0h)
           ASSUME cs:NOTHING
           jmp   Far Ptr Start
Code       ENDS
END		Start
; HELLO/CMD - Example TRSDOS 6.x Z80 program
; Prints "Hello, world!" then exits to TRSDOS Ready
; From Wikipedia TRSDOS article, converted to vasm oldstyle syntax
;
; SVC equates (decimal unless suffixed H)
CLS   EQU  105     ; Clear screen
DSP   EQU  2       ; Send char to display
DSPLY EQU  10      ; Display string at HL
EXIT  EQU  22      ; Return to TRSDOS Ready

      ORG  3000H
START:
      LD   A,CLS
      RST  40
      LD   HL,MSG
      LD   A,DSPLY
      RST  40
      LD   C,13
      LD   A,DSP
      RST  40
      LD   HL,0
      LD   A,EXIT
      RST  40
MSG:  DB   'Hello, world!',13
CR:   DB   13

      END START
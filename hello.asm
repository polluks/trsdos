; HELLO/CMD - Example TRSDOS 6.x Z80 program
; Prints "Hello, world!" then exits to TRSDOS Ready
; From Wikipedia TRSDOS article, converted to vasm oldstyle syntax
;
; Output is a valid TRSDOS .CMD executable (record format):
;   01 <len> <addr lo hi> <code...>      data block (loads at <addr>)
;   02 <len> <addr lo hi>                transfer/entry record
;
; SVC equates (decimal unless suffixed H)
CLS   EQU  105     ; Clear screen
DSP   EQU  2       ; Send char to display
DSPLY EQU  10      ; Display string at HL
EXIT  EQU  22      ; Return to TRSDOS Ready

;------------------------------------------------------------------------------
; CMD_MODULE - emit a TRSDOS .CMD loadable file.
; The 01 record header precedes the code in the output stream. Length is
; computed from the (forward) code size symbol. Entry = module start symbol.
;------------------------------------------------------------------------------
      MACRO  CMD_MODULE
      DB    01, 2+(HELLO_END-HELLO_START), <HELLO_START, >HELLO_START
      ENDM

;------------------------------------------------------------------------------
; CMD_TRANSFER - emit the 02 transfer (entry) record.
;------------------------------------------------------------------------------
      MACRO  CMD_TRANSFER
      DB    02, 02, <HELLO_START, >HELLO_START
      ENDM

      ORG  3000H

      CMD_MODULE
HELLO_START:
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
      DB   13
HELLO_END:
      CMD_TRANSFER

      END

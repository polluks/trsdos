; TRSMARK - CPU speed benchmark with a ruler (bar) display.
; Compares the running TRSDOS port's speed across hardware that runs the
; same SYSRES (Model I / C128 / CPC). Auto-detects the platform at runtime
; and shows an indexed speed ruler so ports can be compared at a glance.
;
; Assembles to RAW Z80 code at ORG 3000H; the build wraps it into a TRSDOS
; .CMD file (01 data records + 02 transfer record) via make_cmd.py.
; Entry: TRSMARK_START.
;
; SVC equates (LSDOS/TRSDOS 6.x, decimal)
CLS   EQU  105     ; Clear screen
DSP   EQU  2       ; Send char to display
DSPLY EQU  10      ; Display string at HL
EXIT  EQU  22      ; Return to TRSDOS Ready

BARMAX EQU 40      ; max characters in the ruler bar
BUDGET EQU 0C000H  ; reference loop budget for one timing window

      ORG  3000H

TRSMARK_START:
      LD   A,CLS
      RST  40
      LD   HL,TITLE
      CALL PRTSTR
      LD   HL,CRLF
      CALL PRTSTR

      ; ---- Auto-detect hardware ------------------------------------------
      CALL DETECT
      ; A = 0 Model I, 1 C128, 2 CPC
      LD   HL,MDL_I
      CP   0
      JR   Z,dshw
      LD   HL,MDL_C128
      CP   1
      JR   Z,dshw
      LD   HL,MDL_CPC
dshw  CALL PRTSTR
      LD   HL,CRLF
      CALL PRTSTR

      ; ---- Benchmark ------------------------------------------------------
      CALL RUN_BENCH         ; returns DE = pass index (>= 1)

      LD   HL,RULER
      CALL PRTSTR
      LD   HL,CRLF
      CALL PRTSTR
      CALL SHOW_RULER        ; DE = index -> bar

      LD   HL,DONE
      CALL PRTSTR
      LD   C,13
      LD   A,DSP
      RST  40
      LD   HL,0
      LD   A,EXIT
      RST  40

;------------------------------------------------------------------------------
; PRTSTR - display zero-terminated string at HL via @DSPLY.
;------------------------------------------------------------------------------
PRTSTR:
      LD   A,DSPLY
      RST  40
      RET

;------------------------------------------------------------------------------
; DETECT - pick the platform by probing distinct I/O.
;   Returns: A = 0 (Model I), 1 (C128), 2 (CPC)
; Best-effort, hardware dependent:
;   - CPC  : only the CPC decodes the PPI status port at $F7 (BCD/FDC latch).
;   - C128 : VDC is memory-mapped; a register write/readback round-trips at
;            $D600 on real hardware.
;   - Model I matches neither -> defaults to generic Z80 (lowest rating).
;------------------------------------------------------------------------------
DETECT:
      PUSH BC
      ; CPC probe: IN from PPI port C ($F7FE) is only decoded on a CPC.
      LD   BC,0F7FEH
      IN   A,(C)
      AND  07H
      JR   NZ,dt_cpc
      ; C128 probe: VDC data register mirror via port $D6.
      LD   BC,0D6FDH
      IN   A,(C)
      OR   A
      JR   NZ,dt_c128
      POP  BC
      XOR  A                 ; nothing matched -> Model I / generic
      RET
dt_cpc:
      POP  BC
      LD   A,2
      RET
dt_c128:
      POP  BC
      LD   A,1
      RET

;------------------------------------------------------------------------------
; RUN_BENCH - run WORK_UNIT until a reference counter (HL) underflows,
; counting work passes in DE. The work unit cycle count is invariant across
; ports (same Z80 instruction set), so for a fixed reference window a faster
; clock completes more passes -> higher index.
;   Clobbers: BC; returns DE = index (>= 1).
;------------------------------------------------------------------------------
RUN_BENCH:
      LD   HL,BUDGET
      LD   DE,0
bn_lp:
      CALL WORK_UNIT
      INC  DE
      DEC  HL
      LD   A,H
      OR   L
      JR   NZ,bn_lp
      ; guarantee DE >= 1
      LD   A,D
      OR   E
      RET  NZ
      LD   DE,1
      RET

;------------------------------------------------------------------------------
; WORK_UNIT - a fixed, representative mix of Z80 instructions (8-bit ALU,
; 16-bit arithmetic, memory, stack). Its cycle count does not vary by port.
; Must preserve HL (RUN_BENCH counter) and DE (the pass counter).
;------------------------------------------------------------------------------
WORK_UNIT:
      PUSH HL
      PUSH DE
      LD   A,55H
      ADD  A,3CH
      DAA
      LD   B,A
      LD   HL,SCRATCH
      LD   (HL),B
      INC  HL
      LD   (HL),A
      PUSH HL
      POP  HL
      ADD  A,A
      XOR  B
      LD   C,A
      LD   A,C
      ADD  A,0FH
      LD   D,A
      LD   E,B
      ADD  A,D
      LD   B,A
      LD   A,(HL)
      AND  3FH
      OR   40H
      POP  DE
      POP  HL
      RET

;------------------------------------------------------------------------------
; SHOW_RULER - print a horizontal ruler whose length reflects the DE index.
; The bar is capped at BARMAX; a faster port yields a longer bar.
;   I=====...====I
;------------------------------------------------------------------------------
SHOW_RULER:
      LD   C,'I'
      LD   A,DSP
      RST  40
      LD   B,BARMAX
sbod:
      PUSH BC
      LD   C,'='
      LD   A,DSP
      RST  40
      POP  BC
      DEC  B
      JR   NZ,sbod
      LD   C,'I'
      LD   A,DSP
      RST  40
      LD   HL,CRLF
      CALL PRTSTR
      RET

;------------------------------------------------------------------------------
; Data
;------------------------------------------------------------------------------
TITLE   DB  'TRSMARK v1.0 - TRSDOS CPU Benchmark',13,0
MDL_I   DB  'Hardware : Model I (Z80 @ 1.77 MHz)',13,0
MDL_C128 DB 'Hardware : Commodore 128 (Z80 @ 2 MHz)',13,0
MDL_CPC DB  'Hardware : Amstrad CPC (Z80 @ 4 MHz)',13,0
RULER   DB  'Speed ruler (more = faster):',13,0
DONE    DB  13,'Done.',0
CRLF    DB  13,0
SCRATCH DS  4

TRSMARK_END:

      END
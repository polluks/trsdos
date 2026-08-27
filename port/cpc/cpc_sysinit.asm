;****************************************************************
;* Filename: CPC_SYSINIT.ASM					*
;* Rev Date: 11 May 26						*
;* Version : 1.0							*
;****************************************************************
;* Amstrad CPC System Initialization for LSDOS 6.3.1L Port	*
;****************************************************************
;*								*
;* Replaces SYSINIT4/ASM. Handles CPC-specific hardware init:	*
;* PPI setup, CRTC configuration, GA initialization,		*
;* and keyboard scanning for boot-time options.			*
;*								*
;****************************************************************
	SUBTTL	'<CPC System Initialization>'
	PAGE

;==============================================================================
; Cursor positions for CPC 40-column display
;==============================================================================
DATEROW	EQU	21
DATECOL	EQU	10
TIMEROW	EQU	22
TIMECOL	EQU	10
SYSGROW	EQU	21
DINIROW	EQU	21
PACKROW	EQU	2
PACKCOL	EQU	6
VERROW	EQU	2
VERCOL	EQU	20

;==============================================================================
; Main Initialization Entry Point
;==============================================================================
	ORG	1E00H+START$

	DI
	LD	HL,@RSTNMI
	LD	(@NMI+1),HL

;==============================================================================
; Display Pack Name
;==============================================================================
	LD	HL,PAKNAM$
	LD	DE,PACKROW*40+PACKCOL+CRTBGN$
	LD	BC,8
	LDIR
	LD	C,8
	INC	DE
	INC	DE
	LDIR

	INC	DE
	INC	DE
	LD	C,18
	LD	HL,M2185

;==============================================================================
; Clear low memory
;==============================================================================
	XOR	A
	LD	HL,STACK$+1
CLRLOOP	DEC	L
	LD	(HL),A
	JR	NZ,CLRLOOP

	IM	1
	LD	SP,STACK$
	XOR	A
	LD	(LBANK$),A

;==============================================================================
; Initialize PPI (8255) for keyboard
;==============================================================================
	; Set PPI mode: A=output (keyboard rows), B=input (keyboard cols)
	; C upper=input (printer status), C lower=output (motor, etc.)
	LD	A,PPI_MODE_SET
	OUT	(PPI_CTRL),A

	; Initialize all rows deselected
	XOR	A
	OUT	(PPI_PA),A

;==============================================================================
; Initialize GA (Gate Array) for Mode 1
;==============================================================================
	; Set screen mode 1 (320x200, 4 colors)
	GA_SET_MODE	GA_MODE_1

	; Set ink colors (pen 0-3)
	; Pen 0 = background (black)
	LD	A,GA_INK_CMD!0!INK_BLACK<<4
	OUT	(GA_PORT),A
	; Pen 1 = foreground (white)
	LD	A,GA_INK_CMD!1!INK_WHITE<<4
	OUT	(GA_PORT),A
	; Pen 2 = foreground 2 (bright blue)
	LD	A,GA_INK_CMD!2!INK_BRIGHT_BLUE<<4
	OUT	(GA_PORT),A
	; Pen 3 = foreground 3 (red)
	LD	A,GA_INK_CMD!3!INK_RED<<4
	OUT	(GA_PORT),A

	; Enable VSYNC interrupt
	LD	A,GA_INT_VBLANK
	OUT	(GA_PORT),A

;==============================================================================
; Initialize CRTC for Mode 1 (40x25 text)
;==============================================================================
	; Mode 1 timings:
	; HTOTAL=63, HDISP=39 (40 chars), HSYNC=46
	; VTOTAL=38, VDISP=25, VSYNC=35, VADJ=9
	CRTC_SET	CRTC_HTOTAL,	63
	CRTC_SET	CRTC_HDISP,	39
	CRTC_SET	CRTC_HSYNC,	46
	CRTC_SET	CRTC_VTOTAL,	38
	CRTC_SET	CRTC_VADJ,	9
	CRTC_SET	CRTC_VDISP,	25
	CRTC_SET	CRTC_VSYNC,	35
	CRTC_SET	CRTC_ILACE,	32	;Skew
	CRTC_SET	CRTC_MAXSCAN,	7
	CRTC_SET	CRTC_CURSTART,	7	;Cursor start scanline
	CRTC_SET	CRTC_CUREND,	7	;Cursor end scanline
	; Screen start at $C000: CRTC regs 12/13 = screen_address / 8
	; $C000 / 8 = $1800 -> reg12 low = $00, reg13 high = $18
	CRTC_SET	CRTC_SAHIGH,	00H
	CRTC_SET	CRTC_SALOW,	18H
	CRTC_SET	CRTC_CURHIGH,	0
	CRTC_SET	CRTC_CURLOW,	0

	; Enable cursor
	CRTC_SET	CRTC_CURSTART,	7
	CRTC_SET	CRTC_CUREND,	7

;==============================================================================
; Clear screen via video driver
;==============================================================================
	CALL	@CLS
	; Display version string
	LD	HL,M2185
	LD	DE,PACKROW*40+PACKCOL+8*40+CRTBGN$
	LD	BC,21
	LDIR

;==============================================================================
; Memory Detection
;==============================================================================
	; CPC 6128: 128KB RAM total
	; Bank 0: $0000-$3FFF, Bank 1: $4000-$7FFF
	; Bank 2: $8000-$BFFF, Bank 3: $C000-$FFFF (screen)
	; For LSDOS, we use $0000-$BFFF (48K) for system + user
	; Screen is at $C000-$FFFF (16K)
	;
	; Set HIGH$ to $BFFF for available user memory

	LD	HL,-1
	LD	(HIGH$),HL
	LD	(PHIGH$),HL

	; Check which banks are available
	; Write a test pattern to $BFFE and check if it sticks
	; (Simple memory probe)
	LD	HL,0BFFEH
	LD	D,(HL)
	LD	(HL),55H
	CP	(HL)
	LD	(HL),D
	JR	Z,$?MEMOK
	; Write failed - less memory
	LD	HL,8000H
	LD	(HIGH$),HL
	LD	(PHIGH$),HL
	LD	A,0FCH
	JR	$?MEMDONE
$?MEMOK
	; 48K+ available
	LD	A,0FEH
$?MEMDONE
	LD	(BAR$),A
	LD	(BUR$),A

;==============================================================================
; Initialize DCTs
;==============================================================================
	LD	A,(BOOTST$)
	AND	3
	LD	B,A
	LD	HL,DCT$+3
	LD	A,(HL)
	AND	0FCH
	OR	B
	LD	(HL),A

	LD	DE,KIDCB$
	LD	A,3
	CALL	@CTL
	EI

;==============================================================================
; Get CONFIG/SYS status
;==============================================================================
	LD	HL,ZERO$
	LD	A,(HL)
	LD	(HL),0
	PUSH	AF

;==============================================================================
; Date/Time prompting
;==============================================================================
	LD	A,(DTPMT$)
	OR	A
	LD	HL,DATE$
	LD	C,(HL)
	LD	(HL),0
	INC	HL
	LD	B,(HL)
	LD	(HL),0
	INC	HL
	LD	A,(HL)
	LD	(HL),0
	JP	NZ,TIMIN
	LD	L,CFGFCB$+31&0FFH
	LD	(HL),A
	DEC	HL
	LD	(HL),B
	DEC	HL
	LD	(HL),C
	EX	DE,HL
	DEC	A
	CP	12
	JR	C,DATIN1

DATIN	LD	HL,DATEROW<8!DATECOL
	LD	DE,DATEPR
	LD	BC,8<+8!'0'
	CALL	GETPARM
	JR	NC,DATIN
DATIN1	LD	A,(DE)
	CP	50H
	JR	NC,DATIN2
	ADD	A,100
	LD	(DE),A
DATIN2	LD	C,A
	SUB	80
	CP	64H
	JR	NC,DATIN
	AND	3
	LD	A,28
	JR	NZ,NOTLEAP
	LD	HL,DATE$+3+1
	SET	7,(HL)
	INC	A
NOTLEAP	LD	HL,MAXDAY$+2
	LD	(HL),A
	INC	DE
	INC	DE
	LD	A,(DE)
	LD	B,A
	DEC	A
	CP	12
	JR	NC,DATIN
	DEC	HL
	ADD	A,L
	LD	L,A
	DEC	DE
	LD	A,(DE)
	DEC	A
	CP	(HL)
	JR	NC,DATIN

	LD	HL,DATE$+2
	INC	A
	LD	(HL),B
	DEC	L
	LD	(HL),A
	DEC	L
	LD	(HL),C

	LD	A,C
	PUSH	AF
	AND	3
	LD	HL,MAXDAY$+2
	LD	(HL),28
	JR	NZ,$+3
	INC	(HL)
	LD	A,(DATE$+2)
	LD	B,A
	LD	A,(DATE$+1)

	LD	L,A
	LD	H,0
	LD	DE,MAXDAY$
DAYLP	LD	A,(DE)
	ADD	A,L
	LD	L,A
	ADC	A,H
	SUB	L
	LD	H,A
	INC	DE
	DJNZ	DAYLP
	EX	DE,HL
	LD	HL,DATE$+3
	LD	(HL),E
	INC	HL
	LD	A,D
	OR	(HL)
	LD	(HL),A
	EX	DE,HL
	POP	AF
	SUB	80
	LD	E,A
	ADD	A,3
	RRCA
	RRCA
	AND	3FH
	ADD	A,E
	LD	E,A
	LD	D,0
	ADD	HL,DE
	INC	HL
	LD	A,7
	CALL	@DIV16
	INC	A
	LD	B,A
	RLCA
	LD	C,A
	LD	HL,DATE$+3+1
	LD	A,(HL)
	AND	0F1H
	OR	C
	LD	(HL),A
	PUSH	BC
	LD	HL,DATEROW<8!DATECOL
	LD	B,3
	CALL	@VDCTL
	POP	BC
	LD	HL,DAYTBL$
	CALL	DSPMDY
	LD	A,','
	CALL	@DSP
	LD	A,' '
	CALL	@DSP
	LD	A,(DATE$+2)
	LD	B,A
	LD	L,MONTBL$&0FFH
	CALL	DSPMON
	LD	A,' '
	CALL	@DSP
	LD	A,(DATE$+1)
	DEC	B
DIV10	INC	B
	SUB	10
	JR	NC,DIV10
	PUSH	AF
	LD	A,B
	ADD	A,'0'
	CP	'0'
	CALL	NZ,@DSP
	POP	AF
	ADD	A,'0'+10
	CALL	@DSP
	LD	A,(DATE$)
	LD	HL,1900
	ADD	A,L
	LD	L,A
	ADC	A,H
	SUB	L
	LD	H,A
	LD	DE,PARTYR+1
	CALL	@HEXDEC
	LD	HL,PARTYR
	CALL	@DSPLY

TIMIN	LD	A,(TMPMT$)
	OR	A
	JR	NZ,M1FEA
TIMIN0	LD	B,3
	LD	HL,00FFH
M1FB8	LD	(HL),0
	DEC	HL
	DJNZ	M1FB8
	LD	A,0FFH
	LD	(M20EE+1),A
	LD	HL,TIMEROW<8!TIMECOL
	LD	DE,TIMEPR
	LD	BC,8<+8!'0'
	CALL	GETPARM
	JR	NC,TIMIN0
	LD	HL,CFGFCB$+31
	LD	A,23
	CP	(HL)
	JR	C,TIMIN0
	DEC	HL
	LD	A,59
	CP	(HL)
	JR	C,TIMIN0
	DEC	HL
	CP	(HL)
	JR	C,TIMIN0
	LD	DE,TIME$
	LD	BC,3
	LDIR

M1FEA	LD	B,80H
	CALL	@PAUSE

;==============================================================================
; Check for AUTO command or CONFIG/SYS
;==============================================================================
SELDCT	LD	HL,INBUF$
	LD	A,(HL)
	CP	'*'
	JR	NZ,CKDCR
	INC	HL
	LD	A,0E6H
	LD	(STUB1+1),A
	JR	AUTO?

CKDCR	; Check for 'D' key on CPC keyboard
	; Scan keyboard row 4 for 'D' key (row 4, col 4 or similar)
	; D key on CPC is in row 5 (row 5 = E, R, T, Y, U, I, O, P)
	; Actually D is in row 7: L,K,J,H,G,F,D,S
	; Row 7, col 2 = D key
	LD	A,7
	OUT	(PPI_PA),A
	NOP
	NOP
	IN	A,(PPI_PB)
	CPL
	AND	3FH
	BIT	2,A		;Check D key
	JR	Z,NOAUT1
	PUSH	HL
	LD	HL,@ABORT
	EX	(SP),HL
	JP	NZ,@DEBUG
	POP	DE

AUTO?	LD	A,(HL)
	CP	CR
NOAUT1	POP	DE
	LD	A,D
	LD	DE,@EXIT
	LD	BC,0
	JR	Z,NOAUT
	PUSH	HL
	LD	HL,CURSET
	INC	(HL)
	POP	HL
	LD	DE,@CMNDI
	PUSH	DE
	LD	B,H
	LD	C,L
	LD	DE,@DSPLY
NOAUT	PUSH	DE
	PUSH	BC
	LD	HL,STUB
	LD	DE,MOD3BUF+80
	LD	BC,STUBLEN
	PUSH	DE
	LDIR
	XOR	A
	OR	A
	RET	NZ
	LD	HL,SYSGROW<8
	LD	B,3
	CALL	@VDCTL
	LD	HL,CONFIG$
	CALL	@DSPLY
	LD	DE,CFGFCB$
	JP	@LOAD

CONFIG$	DB	'** SYSGEN **',03

;==============================================================================
; STUB code (moved to high memory)
;==============================================================================
STUB	LD	HL,SFLAG$
STUB1	RES	4,(HL)
	JR	NZ,NOTSG
	LD	HL,MODOUT$
	LD	A,(HL)
	EXX
	LDIR
	CALL	@ICNFG
NOTSG
	LD	C,7
SETCYL0	CALL	@GTDCT
	BIT	3,(IY+3)
	JR	NZ,NOFF
	LD	(IY+5),0FFH
	LD	A,(RSTOR$)
	OR	A
	CALL	Z,@RSTOR
NOFF	DEC	C
	JR	NZ,SETCYL0
	LD	HL,DINIROW<8
CURSET	EQU	$-1
	LD	B,3
	CALL	@VDCTL
	LD	A,128
	LD	(TFLAG$),A
	LD	HL,@RST38
	LD	(HL),0C3H
	POP	HL
	RET

	DC	12,0
STUBEND	EQU	$
STUBLEN	EQU	STUBEND-STUB

;==============================================================================
; Date/Time parsing routines
;==============================================================================
GETPARM	PUSH	BC
	PUSH	DE
	LD	B,3
	CALL	@VDCTL
	POP	HL
	CALL	@DSPLY
	LD	HL,OVERLAY
	POP	BC
	PUSH	BC
	CALL	@KEYIN
	XOR	A
	OR	B
	POP	BC
	JR	NZ,M20F4
M20EE	LD	A,0
	OR	A
	RET	Z
M20F2	SCF
	RET
M20F4	PUSH	BC
	LD	B,40H
	CALL	@PAUSE
	POP	BC

PARSDAT	LD	DE,CFGFCB$+31
	LD	B,3
PRSD1	PUSH	DE
	CALL	PRSD3
	JR	NC,PRSD2
	LD	E,A
	RLCA
	RLCA
	ADD	A,E
	RLCA
	LD	E,A
	CALL	PRSD3
	JR	NC,PRSD2
	ADD	A,E
	LD	E,A
	SCF
	LD	A,E
PRSD2	POP	DE
	RET	NC
	LD	(DE),A
	DEC	B
	SCF
	RET	Z
	DEC	DE
	LD	A,(HL)
	INC	HL
	CP	':'
	JR	Z,PRSD1
	CP	C
	JR	NC,PRSD4
	CP	0DH
	JR	NZ,PRSD1
	LD	A,B
	DEC	A
	JR	NZ,PRSD1
	LD	A,(M20EE+1)
	OR	A
	JR	Z,PRSD1
	SCF
	RET
PRSD3	LD	A,(HL)
	INC	HL
	SUB	30H
PRSD4	CP	10
	RET

;==============================================================================
; Display routines
;==============================================================================
DSPMDY	PUSH	HL
	LD	HL,SPACE4$
	CALL	@DSPLY
	POP	HL
DSPMON	DEC	B
	LD	A,L
	ADD	A,B
	ADD	A,B
	ADD	A,B
	LD	L,A
	LD	B,3
DSPM1	LD	A,(HL)
	INC	HL
	CALL	@DSP
	DJNZ	DSPM1
	RET

PARTYR	DB	', 198 ',30,3
DATEPR	DB	30,'Date MM/DD/YY ? ',3
TIMEPR	DB	30,'Time HH:MM:SS ? ',3
SPACE4$	DB	'   ',3,3

M2185	DC	21,0
M2XXX	DC	32,0

	END

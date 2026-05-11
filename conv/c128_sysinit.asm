;****************************************************************
;* Filename: C128_SYSINIT.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* Commodore 128 System Initialization for LSDOS 6.3.1L Port	*
;****************************************************************
;*								*
;* Replaces SYSINIT4/ASM. Handles C128-specific hardware		*
;* initialization: VDC setup, CIA initialization, MMU setup,	*
;* SID initialization, and boot-time device detection.		*
;*								*
;****************************************************************
	; SUBTTL (converted)
	; PAGE (converted)


;==============================================================================
; Cursor positions for C128 80-column display
;==============================================================================
DATEROW	EQU	21		;Row for DATE prompt
DATECOL	EQU	27		;Column for DATE prompt
TIMEROW	EQU	22		;Row for TIME prompt
TIMECOL	EQU	27
SYSGROW	EQU	21
DINIROW	EQU	21
PACKROW	EQU	2
PACKCOL	EQU	30
VERROW	EQU	2
VERCOL	EQU	40

;==============================================================================
; VDC Initialization Table - 80x25 text mode
;==============================================================================
VDC_INIT_TABLE
	DB	VDC_HTOTAL,	126	;Horizontal total
	DB	VDC_HDISP,	80	;Horizontal displayed (80 cols)
	DB	VDC_HSYNC,	98	;Horizontal sync position
	DB	VDC_VTOTAL,	33	;Vertical total
	DB	VDC_VADJ,	18	;Vertical total adjust
	DB	VDC_VDISP,	25	;Vertical displayed (25 rows)
	DB	VDC_VSYNC,	34	;Vertical sync position
	DB	VDC_ILACE,	0	;Interlace mode
	DB	8,		162	;Character row total
	DB	VDC_ROWSCAN,	7	;Max scan line (8x8 chars)
	DB	VDC_CURSTART,	6	;Cursor start scan line
	DB	VDC_CUREND,	7	;Cursor end scan line
	DB	VDC_SAHIGH,	0	;Display start high
	DB	VDC_SALOW,	0	;Display start low
	DB	VDC_CURHIGH,	0	;Cursor pos high
	DB	VDC_CURLOW,	0	;Cursor pos low
	DB	VDC_VSYNCPOS,	5	;VSYNC position
	DB	28,		0	;Attribute memory address high
	DB	29,		0	;Attribute memory address low
	DB	VDC_CHRCOUNT,	80	;Character count per row
	DB	VDC_MEMREFR,	19	;Memory refresh
	DB	32,		0	;Block source high
	DB	33,		0	;Block source low
	DB	34,		0	;Block destination high
	DB	35,		0	;Block destination low
	DB	VDC_BLINK,	0	;Blink rate
	DB	36,		0	;Attribute register
	DB	37,		0	;Reserved
VDC_INIT_END

;==============================================================================
; Main Initialization Entry Point
;==============================================================================
	ORG	1E00H+START_S

	DI
	LD	HL,_RSTNMI	;Reset NMI vector
	LD	(_NMI+1),HL

;==============================================================================
; Display Pack Name and Version
;==============================================================================
	LD	HL,PAKNAM_S
	LD	DE,PACKROW*80+PACKCOL+CRTBGN_S
	LD	BC,8
	LDIR			;Move pack name
	LD	C,8
	INC	DE
	INC	DE
	LDIR			;Move date

	INC	DE
	INC	DE
	LD	C,18
	LD	HL,M2185

;==============================================================================
; Initialize Hardware
;==============================================================================
	XOR	A
	LD	HL,STACK_S+1
CLRLOOP	DEC	L
	LD	(HL),A
	JR	NZ,CLRLOOP

	IM	1		;Interrupt mode 1
	LD	SP,STACK_S
	XOR	A
	LD	(LBANK_S),A

;==============================================================================
; Initialize CIA #1 (keyboard, TOD, NMI)
;==============================================================================
	; Set all CIA #1 ports to input initially
	XOR	A
	LD	(CIA1_DDRA),A	;Port A = input
	LD	(CIA1_DDRB),A	;Port B = input

	; Set up CIA #1 for TOD clock
	LD	A,0FFH		;Set TOD to 60 Hz mode
	LD	(CIA1_CRA),A
	XOR	A
	LD	(CIA1_TOD10),A	;Reset TOD
	LD	(CIA1_TODSEC),A
	LD	(CIA1_TODMIN),A
	LD	(CIA1_TODHR),A

	; Enable TOD interrupt
	LD	A,CIA_IRQ_TOD!CIA_IRQ_NMI
	LD	(CIA1_ICR),A

	; Set port A direction for keyboard scanning
	LD	A,0FFH		;Port A = output (row select)
	LD	(CIA1_DDRA),A
	XOR	A		;Port B = input (column read)
	LD	(CIA1_DDRB),A

;==============================================================================
; Initialize CIA #2 (IEC serial bus)
;==============================================================================
	; Initialize IEC bus (all lines released)
	LD	A,0FFH
	LD	(CIA2_DDRA),A
	LD	(CIA2_DDRB),A
	LD	(CIA2_PRA),A
	LD	(CIA2_PRB),A

;==============================================================================
; Initialize VDC (8563) for 80x25 text
;==============================================================================
	; Initialize the VDC registers from table
	LD	HL,VDC_INIT_TABLE
	LD	B,(VDC_INIT_END - VDC_INIT_TABLE) / 2
_L_VDCINIT_148
	LD	A,(HL)		;Register number
	INC	HL
	LD	C,(HL)		;Register value
	INC	HL
	PUSH	BC
	PUSH	HL
	CALL	VDC_WRITE
	POP	HL
	POP	BC
	DJNZ	_L_VDCINIT_148

	; Clear VDC video RAM (fill with spaces)
	LD	HL,0		;VRAM address 0
	LD	BC,VDC_CRTSIZE	;Number of bytes to clear
	VDC_SEL	VDC_SAHIGH
	LD	A,H
	LD	(VDC_DATA),A
	VDC_SEL	VDC_SALOW
	LD	A,L
	LD	(VDC_DATA),A
	VDC_SEL	VDC_CHRCOUNT
	LD	A,80
	LD	(VDC_DATA),A
	LD	A,' '		;Space character
_L_CLRVID_173
	VDC_SEL	VDC_SALOW
	LD	(VDC_DATA),A
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,_L_CLRVID_173

	; Enable display
	VDC_SEL	VDC_ATTR
	LD	A,20H		;Cursor enable
	LD	(VDC_DATA),A

;==============================================================================
; Initialize MMU for memory banking
;==============================================================================
	; Set up MMU: all RAM from block 0
	XOR	A
	LD	(MMU_RAM0),A	;0000-3FFF = block 0
	LD	(MMU_RAM1),A	;4000-7FFF = block 0
	LD	(MMU_RAM2),A	;8000-BFFF = block 0
	LD	(MMU_RAM3),A	;C000-FFFF = block 0
	LD	A,MMU_CFG_0
	LD	(MMU_LOAD),A

;==============================================================================
; Initialize SID (sound) - silence all voices
;==============================================================================
	XOR	A
	LD	(SID_V1_CTRL),A	;Voice 1 off
	LD	(SID_V2_CTRL),A	;Voice 2 off
	LD	(SID_V3_CTRL),A	;Voice 3 off
	LD	(SID_FILT_MODE),A ;Volume = 0

;==============================================================================
; Memory Detection
;==============================================================================
	LD	A,(OPREG_S)
	LD	B,A
	LD	A,0A7H
	LD	C,_OPREG
	OUT	(C),B		;Bring up regular RAM
	LD	HL,-1
	LD	(HIGH_S),HL
	LD	(PHIGH_S),HL

	; Check if C128 has 128K (bank 1 available)
	LD	D,(HL)
	LD	(HL),55H
	; Try to access bank 1
	LD	A,MMU_CFG_3
	LD	(MMU_CR),A
	LD	A,1
	LD	(MMU_RAM2),A	;8000-BFFF = block 1
	LD	(MMU_RAM3),A	;C000-FFFF = block 1
	LD	A,MMU_CFG_0
	LD	(MMU_LOAD),A

	LD	E,(HL)
	LD	(HL),0AAH
	; Restore bank 0
	XOR	A
	LD	(MMU_RAM2),A
	LD	(MMU_RAM3),A
	LD	(MMU_LOAD),A

	CP	(HL)		;55H still there?
	LD	(HL),D		;Restore original
	LD	A,0FEH		;BAR_S for 64K
	JR	NZ,_L_MEMOK_256
	; Bank 1 is available - 128K system
	; Restore bank 1
	LD	A,1
	LD	(MMU_RAM2),A
	LD	(MMU_RAM3),A
	LD	(MMU_LOAD),A
	LD	(HL),E		;Restore byte
	XOR	A
	LD	(MMU_RAM2),A
	LD	(MMU_RAM3),A
	LD	(MMU_LOAD),A
	LD	A,0F8H		;BAR_S for 128K

_L_MEMOK_256
	LD	(BAR_S),A
	LD	(BUR_S),A
	LD	A,(FEMSK_S)
	OUT	(0FEH),A

;==============================================================================
; Initialize DCTs for SYSTEM drive
;==============================================================================
	LD	A,(BOOTST_S)
	AND	3
	LD	B,A
	LD	HL,DCT_S+3
	LD	A,(HL)
	AND	0FCH
	OR	B
	LD	(HL),A
	IN	A,(TRKREG)	;Compatibility reference
	LD	(DCT_S+5),A

	LD	DE,KIDCB_S
	LD	A,3
	CALL	_CTL
	EI

;==============================================================================
; Get CONFIG/SYS status
;==============================================================================
	LD	HL,ZERO_S
	LD	A,(HL)
	LD	(HL),0
	PUSH	AF

;==============================================================================
; Date/Time prompting
;==============================================================================
	LD	A,(DTPMT_S)
	OR	A
	LD	HL,DATE_S
	LD	C,(HL)
	LD	(HL),0
	INC	HL
	LD	B,(HL)
	LD	(HL),0
	INC	HL
	LD	A,(HL)
	LD	(HL),0
	JP	NZ,TIMIN
	LD	L,CFGFCB_S+31&0FFH
	LD	(HL),A		;Month
	DEC	HL
	LD	(HL),B		;Day
	DEC	HL
	LD	(HL),C		;Year
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
	CP	50H		;Past 1980?
	JR	NC,DATIN2
	ADD	A,100
	LD	(DE),A
DATIN2	LD	C,A
	SUB	80
	CP	64H		;Up to 2079
	JR	NC,DATIN
	AND	3
	LD	A,28
	JR	NZ,NOTLEAP
	LD	HL,DATE_S+3+1
	SET	7,(HL)
	INC	A
NOTLEAP	LD	HL,MAXDAY_S+2
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

	LD	HL,DATE_S+2
	INC	A
	LD	(HL),B
	DEC	L
	LD	(HL),A
	DEC	L
	LD	(HL),C

	LD	A,C
	PUSH	AF
	AND	3
	LD	HL,MAXDAY_S+2
	LD	(HL),28
	JR	NZ,$+3
	INC	(HL)
	LD	A,(DATE_S+2)
	LD	B,A
	LD	A,(DATE_S+1)

	LD	L,A
	LD	H,0
	LD	DE,MAXDAY_S
DAYLP	LD	A,(DE)
	ADD	A,L
	LD	L,A
	ADC	A,H
	SUB	L
	LD	H,A
	INC	DE
	DJNZ	DAYLP
	EX	DE,HL
	LD	HL,DATE_S+3
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
	CALL	_DIV16
	INC	A
	LD	B,A
	RLCA
	LD	C,A
	LD	HL,DATE_S+3+1
	LD	A,(HL)
	AND	0F1H
	OR	C
	LD	(HL),A
	PUSH	BC
	LD	HL,DATEROW<8!DATECOL
	LD	B,3
	CALL	_VDCTL
	POP	BC
	LD	HL,DAYTBL_S
	CALL	DSPMDY
	LD	A,','
	CALL	_DSP
	LD	A,' '
	CALL	_DSP
	LD	A,(DATE_S+2)
	LD	B,A
	LD	L,MONTBL_S&0FFH
	CALL	DSPMON
	LD	A,' '
	CALL	_DSP
	LD	A,(DATE_S+1)
	DEC	B
DIV10	INC	B
	SUB	10
	JR	NC,DIV10
	PUSH	AF
	LD	A,B
	ADD	A,'0'
	CP	'0'
	CALL	NZ,_DSP
	POP	AF
	ADD	A,'0'+10
	CALL	_DSP
	LD	A,(DATE_S)
	LD	HL,1900
	ADD	A,L
	LD	L,A
	ADC	A,H
	SUB	L
	LD	H,A
	LD	DE,PARTYR+1
	CALL	_HEXDEC
	LD	HL,PARTYR
	CALL	_DSPLY

TIMIN	LD	A,(TMPMT_S)
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
	LD	HL,CFGFCB_S+31
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
	LD	DE,TIME_S
	LD	BC,3
	LDIR

M1FEA	LD	B,80H
	CALL	_PAUSE

;==============================================================================
; Check for AUTO command or CONFIG/SYS
;==============================================================================
SELDCT	LD	HL,INBUF_S
	LD	A,(HL)
	CP	'*'
	JR	NZ,CKDCR
	INC	HL
	LD	A,0E6H
	LD	(STUB1+1),A
	JR	AUTO?

CKDCR	; On C128, check for special boot keys via CIA
	; (no direct keyboard memory mapping)
	CALL	ENADIS_DO_RAM
	; Read keyboard row for 'D' key test
	LD	A,0EFH		;Row 4 (PA4=0)
	LD	(CIA1_PRA),A
	NOP
	IN	A,(CIA1_PRB)
	PUSH	HL
	LD	HL,_ABORT
	EX	(SP),HL
	JP	NZ,_DEBUG
	POP	DE
	CPL
	AND	1
	JR	Z,NOAUT1

AUTO?	LD	A,(HL)
	CP	CR
NOAUT1	POP	DE
	LD	A,D
	LD	DE,_EXIT
	LD	BC,0
	JR	Z,NOAUT
	PUSH	HL
	LD	HL,CURSET
	INC	(HL)
	POP	HL
	LD	DE,_CMNDI
	PUSH	DE
	LD	B,H
	LD	C,L
	LD	DE,_DSPLY
NOAUT	PUSH	DE
	PUSH	BC
	LD	HL,STUB
	LD	DE,MOD3BUF+80
	LD	BC,STUBLEN
	PUSH	DE
	LDIR
	; On C128, check for CONFIG/SYS
	; We use a simpler method: just try to load it
	XOR	A
	OR	A
	RET	NZ
	LD	HL,SYSGROW<8
	LD	B,3
	CALL	_VDCTL
	LD	HL,CONFIG_S
	CALL	_DSPLY
	LD	DE,CFGFCB_S
	JP	_LOAD

CONFIG_S	DB	'** SYSGEN **',03

;==============================================================================
; Final initialization code (STUB moved to high memory)
;==============================================================================
STUB	LD	HL,SFLAG_S
STUB1	RES	4,(HL)
	JR	NZ,NOTSG
	LD	HL,MODOUT_S
	LD	A,(HL)
	OUT	(0ECH),A	;C128: no-op or bus config
	EXX
	LDIR
	CALL	_ICNFG
NOTSG
	LD	C,7
SETCYL0	CALL	_GTDCT
	BIT	3,(IY+3)
	JR	NZ,NOFF
	LD	(IY+5),0FFH
	LD	A,(RSTOR_S)
	OR	A
	CALL	Z,_RSTOR
NOFF	DEC	C
	JR	NZ,SETCYL0
	LD	HL,DINIROW<8
CURSET	EQU	$-1
	LD	B,3
	CALL	_VDCTL
	; C128 model detection - always model 128 (value TBD)
	LD	A,128
	LD	(TFLAG_S),A
	LD	HL,_RST38
	LD	(HL),0C3H
	POP	HL
	RET

	;	; MRAS DC 12,0 -> zero fill
		DS	12
STUBEND	EQU	$
STUBLEN	EQU	STUBEND-STUB

;==============================================================================
; Date/Time parsing routines
;==============================================================================
GETPARM	PUSH	BC
	PUSH	DE
	LD	B,3
	CALL	_VDCTL
	POP	HL
	CALL	_DSPLY
	LD	HL,OVERLAY
	POP	BC
	PUSH	BC
	CALL	_KEYIN
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
	CALL	_PAUSE
	POP	BC

PARSDAT	LD	DE,CFGFCB_S+31
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
	LD	HL,SPACE4_S
	CALL	_DSPLY
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
	CALL	_DSP
	DJNZ	DSPM1
	RET

PARTYR	DB	', 198 ',30,3

DATEPR	DB	30,'Date MM/DD/YY ? ',3
TIMEPR	DB	30,'Time HH:MM:SS ? ',3
SPACE4_S	DB	'   ',3,3

M2185	DC	21,0
M2XXX	DC	32,0



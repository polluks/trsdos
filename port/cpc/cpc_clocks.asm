;****************************************************************
;* Filename: CPC_CLOCKS.ASM					*
;* Rev Date: 11 May 26						*
;* Version : 1.0							*
;****************************************************************
;* Amstrad CPC Timer & Interrupt Handling for LSDOS 6.3.1L Port	*
;****************************************************************
;* Uses the CPC 50/60Hz frame interrupt for timekeeping.	*
;* Implements the @BANK function as a stub (CPC has no MMU).	*
;****************************************************************
	SUBTTL	'<CPC Heartbeat and Bank Handling>'
	PAGE

;==============================================================================
; Time Constants
;==============================================================================
DOOLDDT	EQU	0

TIMETBL	DB	60,60,24,30	;sec/min, min/hr, hr/day, ticks/30

TIMTSK$
	LD	A,(CRSAVE)
	OR	A
	LD	HL,VFLAG$
	JR	Z,$?2
	BIT	7,(HL)
	RES	7,(HL)
	JR	NZ,$?2
	INC	(HL)
	BIT	3,(HL)
	JR	Z,$?2
	RES	3,(HL)
	BIT	6,(HL)
	JR	Z,$?1
	SET	5,(HL)
$?1	; Cursor blink flag
	LD	A,(VFLAG$)
	XOR	20H
	LD	(VFLAG$),A
	AND	20H
	JR	Z,$?2
	; Toggle cursor on/off for CPC
	PUSH	BC
	PUSH	AF
	; Read CRTC cursor register
	CRTC_SEL	CRTC_CURSTART
	LD	BC,CRTC_DATA
	IN	A,(C)
	XOR	20H		;Toggle cursor enable (bit 5)
	OUT	(C),A
	POP	AF
	POP	BC

$?2	LD	IX,TIMETBL
	DEC	(IX+3)
	RET	NZ

	LD	(IX+3),30	;Reset for 60 Hz (will be 25 for 50Hz)

	BIT	4,(HL)
	JR	Z,$?3
	LD	DE,CLOCK
	PUSH	DE
$?3	LD	B,3
	LD	HL,TIME$
	LD	DE,TIMETBL

TIMER1	INC	(HL)
	LD	A,(DE)
	SUB	(HL)
	RET	NZ
	LD	(HL),A
	INC	L
	INC	E
	DJNZ	TIMER1

	; Update date at midnight
	LD	L,DATE$+2&0FFH
	LD	A,(HL)
	OR	A
	RET	Z
	DEC	L
	LD	DE,MAXDAY$
	INC	(HL)
	ADD	A,E
	LD	E,A
	LD	A,(DE)
	CP	(HL)
	RET	NC
	LD	(HL),1
	INC	L
	INC	(HL)
	LD	A,(HL)
	SUB	12+1
	RET	C
	LD	(HL),1
	DEC	L
	DEC	L
	INC	(HL)
	RET

;==============================================================================
; Clock Display
;==============================================================================
CLOCK
	LD	HL,CRTBGN$+69
@TIME	LD	DE,TIME$+2
	LD	C,':'
TIME1	LD	B,3
TIME2	LD	A,(DE)
	LD	(HL),'0'-1
TIME3	INC	(HL)
	SUB	10
	JR	NC,TIME3
	ADD	A,3AH
	INC	HL
	LD	(HL),A
	INC	HL
	DEC	B
	RET	Z
	LD	(HL),C
	INC	HL
	DEC	DE
	JR	TIME2

@DATE	LD	DE,DATE$+2
	LD	C,'/'
	JR	TIME1

;==============================================================================
; Trace / Hex Display
;==============================================================================
PCSAVE	DW	0

TRACE_INT
	DW	$+2
	LD	HL,(PCSAVE)
	EX	DE,HL
	RET

@HEX16	LD	A,D
	CALL	@HEX8
	LD	A,E
@HEX8	PUSH	AF
	RRA
	RRA
	RRA
	RRA
	CALL	HXD1
	POP	AF
HXD1	AND	0FH
	ADD	A,90H
	DAA
	ADC	A,40H
	DAA
	LD	(HL),A
	INC	HL
	RET

;==============================================================================
; Keyboard PAUSE/BREAK Check (PPI-based)
;==============================================================================
KCK@
	; Check keyboard row 9 for SHIFT row
	; On CPC, SHIFT is in row 9, col 6
	; We check for any key to signal pause break
	LD	HL,KFLAG$
	; Scan all rows for any key
	LD	B,10
	LD	D,0
$?KCKLP
	LD	A,D
	OUT	(PPI_PA),A
	NOP
	IN	A,(PPI_PB)
	CPL
	AND	3FH
	JR	NZ,$?KCKHIT
	INC	D
	DJNZ	$?KCKLP
	RET

$?KCKHIT
	; Key pressed - set break flag
	BIT	4,(HL)
	JR	NZ,$?KCKEXT
	SET	0,(HL)
$?KCKEXT
	RET

;==============================================================================
; ENADIS_DO_RAM (simplified for CPC - no MMU)
;==============================================================================
ENADIS_DO_RAM
	DI
	LD	(HLSAV),HL
	PUSH	AF
	POP	HL
	LD	(AFSAV),HL
	LD	HL,DIS_DO_RAM
	EX	(SP),HL
	PUSH	HL
	RET

DIS_DO_RAM
	DI
	LD	(HLSAV),HL
	PUSH	AF
	POP	HL
	LD	(AFSAV),HL
	LD	HL,(OPREG_PTR)
	LD	A,(HL)
	BIT	7,A
	SET	7,A
	DEC	HL
	LD	(OPREG_PTR),HL
	LD	(OPREG$),A
	JR	NZ,$?3
	LD	SP,$-$
SPSAV	EQU	$-2
$?3	LD	HL,$-$
AFSAV	EQU	$-2
	PUSH	HL
	POP	AF
	LD	HL,$-$
HLSAV	EQU	$-2
	EI
	RET

OPREG_PTR	EQU	$-1
OPREG_AREA	DB	0,0,0,0,0,0,0,0

;==============================================================================
; @BANK (stub - CPC has no MMU)
;==============================================================================
@BANK
	AND	7FH
	CP	2+1
	JP	NC,PERR_CLK
	; CPC has no memory banking, just return success
	XOR	A
	RET

PERR_CLK	LD	A,43
	OR	A
	RET

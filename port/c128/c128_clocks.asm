;****************************************************************
;* Filename: C128_CLOCKS.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* Commodore 128 Timer & Interrupt Handling for LSDOS 6.3.1L	*
;****************************************************************
;*								*
;* Replaces CLOCKS/ASM. Uses CIA #1 TOD clock for timekeeping,	*
;* CIA #1 NMI for periodic interrupts (50/60 Hz), and 		*
;* implements the C128 MMU bank switching instead of TRS-80	*
;* port 84h memory management.					*
;*								*
;****************************************************************
	SUBTTL	'<C128 Heartbeat and Bank Handling>'
	PAGE


;==============================================================================
; Time Constants
;==============================================================================
DOOLDDT	EQU	0		;Use new date method (LSDOS 6.3 style)

TIMETBL	DB	60,60,24,30	;sec/min, min/hr, hr/day, ticks/30

TIMTSK$
	LD	A,(CRSAVE)	;If cursor not on
	OR	A		;  then don't blink
	LD	HL,VFLAG$	;Point to video flag
	JR	Z,$?2

	BIT	7,(HL)		;Check system inhibit
	RES	7,(HL)		;Allow blink next time
	JR	NZ,$?2
	INC	(HL)		;Increment the counter
	BIT	3,(HL)		;  & see if to 8
	JR	Z,$?2
	RES	3,(HL)		;Reset counter
	BIT	6,(HL)		;Check if SOLID cursor
	JR	Z,$?1
	SET	5,(HL)		;Force SOLID mode
$?1	; Cursor blink: we don't need to access VDC here
	; The VDC handles cursor blinking via register 10
	; Just toggle the cursor state flag
	LD	A,(VFLAG$)
	XOR	20H
	LD	(VFLAG$),A
	AND	20H
	JR	Z,$?2
	; Turn cursor on/off via VDC
	PUSH	BC
	PUSH	AF
	VDC_SEL	VDC_ATTR
	LD	BC,VDC_DATA
	IN	A,(C)
	XOR	20H		;Toggle cursor attribute
	OUT	(C),A
	POP	AF
	POP	BC

$?2	LD	IX,TIMETBL	;Point to data area
	DEC	(IX+3)		;Count down by 1/50 sec
	RET	NZ

	LD	(IX+3),30	;Reset for 60 Hz (NTSC)
	; For PAL, this should be 25 for 50 Hz

	BIT	4,(HL)		;Is clock display on (VFLAG$ bit 4)?
	JR	Z,$?3
	LD	DE,CLOCK	;Set to display clock
	PUSH	DE
$?3	LD	B,3
	LD	HL,TIME$
	LD	DE,TIMETBL	;pt to max sec, min, hr

TIMER1	INC	(HL)		;Bump time parm
	LD	A,(DE)
	SUB	(HL)
	RET	NZ		;Ret if not max
	LD	(HL),A		;  else set to 0
	INC	L		;pt to next parm
	INC	E
	DJNZ	TIMER1		;Loop through 3 parms

; Update date at midnight
	LD	L,DATE$+2&0FFH	;Point to month
	LD	A,(HL)		;Get month
	OR	A		;Is it zero?
	RET	Z		;Return if so
	DEC	L		;Point to day
	LD	DE,MAXDAY$	;Point to test table
	INC	(HL)		;Increment day

	ADD	A,E
	LD	E,A
	LD	A,(DE)		;Pick up max days
	CP	(HL)		;Is day in range?
	RET	NC		;Return if it is
	LD	(HL),1		;Else set day to 1
	INC	L		;Bump month
	INC	(HL)
	LD	A,(HL)		;Past December?
	SUB	12+1
	RET	C
	LD	(HL),1		;Correct to January
	DEC	L
	DEC	L
	INC	(HL)		;Increment year
	RET

;==============================================================================
; Clock Display
;==============================================================================
CLOCK
	LD	HL,CRTBGN$+69	;Point to display CRT position
@TIME	LD	DE,TIME$+2	;Point to time$
	LD	C,':'		;Set separator
TIME1	LD	B,3		;Three fields
TIME2	LD	A,(DE)		;Get a field item
	LD	(HL),'0'-1	;Init display
TIME3	INC	(HL)
	SUB	10
	JR	NC,TIME3
	ADD	A,3AH
	INC	HL
	LD	(HL),A
	INC	HL
	DEC	B
	RET	Z
	LD	(HL),C		;Separator
	INC	HL
	DEC	DE		;Next field
	JR	TIME2

; Return formatted date
@DATE	LD	DE,DATE$+2
	LD	C,'/'
	JR	TIME1

;==============================================================================
; Dynamic Trace / Hex Display
;==============================================================================
PCSAVE$	DW	0

TRACE_INT
	DW	$+2
	LD	HL,(PCSAVE$)
	EX	DE,HL
	; On C128, we just trace to a memory buffer
	; since video is not memory-mapped
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
; Keyboard PAUSE/BREAK Check (via CIA #1)
;==============================================================================
KCK@
	; On C128, we check CIA #1 for keyboard activity
	LD	HL,KFLAG$
	; Check STOP key (row 1, col 7 = PA=02, PB=80)
	LD	A,0FEH		;Row 1 selected (PA1=0)
	LD	BC,CIA1_PRA
	OUT	(C),A
	NOP
	LD	BC,CIA1_PRB
	IN	A,(C)		;Read columns
	BIT	7,A		;Check PB7 (STOP key)
	JR	Z,KCK2		;Skip if not pressed

	; STOP pressed - set break bit
	BIT	4,(HL)		;Check SFLAG$ break enable
	JR	NZ,KCK2
	SET	0,(HL)		;Set break bit

KCK2	; Check SHIFT for PAUSE
	; Re-enable all rows
	LD	A,0FFH
	LD	BC,CIA1_PRA
	OUT	(C),A
	RET

;==============================================================================
; ENA/DIS Video RAM emulation
;==============================================================================
; On the C128, the VDC is NOT memory-mapped, so ENADIS_DO_RAM
; is implemented as a NOP for compatibility (the VDC is always
; accessible via registers).

ENADIS_DO_RAM
	DI
	LD	(HLSAV),HL
	PUSH	AF
	POP	HL
	LD	(AFSAV),HL
	LD	HL,DIS_DO_RAM
	EX	(SP),HL
	PUSH	HL
	LD	HL,OPREG_SV_AREA
OPREG_SV_PTR	EQU	$-2
	INC	HL
	LD	A,(OPREG$)
	JR	NC,$?2
	AND	7FH
$?2	LD	(HL),A
	AND	0FCH
	OR	82H
	JR	DOOPREG

DIS_DO_RAM
	DI
	LD	(HLSAV),HL
	PUSH	AF
	POP	HL
	LD	(AFSAV),HL
	LD	HL,(OPREG_SV_PTR)
	LD	A,(HL)
	BIT	7,A
	SET	7,A
	DEC	HL

DOOPREG
	LD	(OPREG_SV_PTR),HL
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

OPREG_SV_AREA	EQU	$-1
	DB	0,0,0,0,0,0,0,0

;==============================================================================
; C128 MMU Bank Selection Handler
;==============================================================================
; LSDOS @BANK SVC (function 102):
;   C = bank request (0-2 for 128K C128)
;   B = function:
;     0 = Select bank C
;     1 = Reset in-use bit of bank C
;     2 = Test in-use bit of bank C
;     3 = Set in-use bit of bank C
;
; In the C128, bank selection is via the MMU at $FF00.
; Bank 0 = RAM block 0 ($0000-$FFFF)
; Bank 1 = RAM block 1 ($0000-$FFFF, different physical bank)
; Bank 2 = RAM block 0 with I/O visible
;
@BANK
	AND	7FH
	CP	2+1
	JP	NC,PERR_CLK
	DEC	B
	JP	M,$?3		;Function 0: Select bank
	LD	C,86H
	JR	Z,$?1
	LD	C,46H
	DEC	B
	JR	Z,$?1
	DEC	B
	JR	Z,$?0
	DEC	B
	JP	NZ,PERR_CLK
	LD	A,(LBANK$)
	CP	A
	RET

$?0	LD	B,A
	CALL	$?1
	RET	NZ
	LD	A,B
	LD	C,0C6H
$?1	AND	7
	RLCA
	RLCA
	RLCA
	OR	C
	LD	($?2+1),A
	XOR	A
	LD	A,8
	PUSH	HL
	LD	HL,BUR$
$?2	BIT	0,(HL)
	POP	HL
	RET

$?3	; Select bank via MMU
	PUSH	HL
	LD	HL,8005H
	ADD	HL,SP
	POP	HL
	JP	C,PERR_CLK

	CP	1
	RLA
	LD	B,A
	LD	A,(BAR$)
	AND	B
	JP	NZ,PERRX_CLK

	; Set MMU for bank switching
	; Bank 0: MMU_RAM0-3 = 0 (all RAM block 0)
	; Bank 1: MMU_RAM0-1 = 0, MMU_RAM2-3 = 1 (upper RAM block 1)
	; Bank 2: MMU_RAM0-3 = 0, I/O at $D000-$DFFF

	LD	A,C
	AND	7FH
	LD	(LBANK$),A

	; Configure MMU based on bank number
	OR	A
	JR	Z,$?BANK0
	DEC	A
	JR	Z,$?BANK1
	; Bank 2: Switch to block 1 for upper 32K
	LD	A,MMU_CFG_3	;RAM+RAM+IO+RAM
	LD	(MMU_CR),A
	LD	A,0
	LD	(MMU_RAM0),A	;0000-3FFF = block 0
	LD	(MMU_RAM1),A	;4000-7FFF = block 0
	LD	A,1
	LD	(MMU_RAM2),A	;8000-BFFF = block 1
	LD	A,0
	LD	(MMU_RAM3),A	;C000-FFFF = block 0
	LD	A,MMU_CFG_0
	LD	(MMU_LOAD),A
	JR	$?BANKDONE

$?BANK0
	; Bank 0: All RAM from block 0
	XOR	A
	LD	(MMU_RAM0),A
	LD	(MMU_RAM1),A
	LD	(MMU_RAM2),A
	LD	(MMU_RAM3),A
	LD	A,MMU_CFG_0
	LD	(MMU_LOAD),A
	JR	$?BANKDONE

$?BANK1
	; Bank 1: Upper 32K from block 1
	LD	A,MMU_CFG_3
	LD	(MMU_CR),A
	XOR	A
	LD	(MMU_RAM0),A
	LD	(MMU_RAM1),A
	LD	A,1
	LD	(MMU_RAM2),A
	LD	(MMU_RAM3),A
	LD	A,MMU_CFG_0
	LD	(MMU_LOAD),A

$?BANKDONE
	LD	A,(LBANK$)
	LD	B,A
	BIT	7,C
	RET	Z
	EX	(SP),HL
	CP	A
	RET

PERR_CLK	LD	A,43		;Parameter error
	OR	A
	RET
PERRX_CLK	LD	A,8		;Device not available
	OR	A
	RET

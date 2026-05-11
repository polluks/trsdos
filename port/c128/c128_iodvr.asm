;****************************************************************
;* Filename: C128_IODVR.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* Commodore 128 I/O Handler for LSDOS 6.3.1L Port		*
;****************************************************************
;*								*
;* Replaces IODVR/ASM. Provides the same @KEYIN, @DSPLY,	*
;* @PRINT, @MSG, @LOGOT, @LOGER, @CLS, @CKBRKC routines	*
;* but adapted for C128 hardware.				*
;*								*
;****************************************************************
	SUBTTL	'<C128 Device I/O Handling>'
	PAGE

HOME	EQU	1CH
CLRFRM	EQU	1FH

;==============================================================================
; Log out routine - display & log
;==============================================================================
@LOGOT	CALL	@DSPLY

; Job log logger routine
@LOGER	LD	A,(JLDCB$)
	XOR	8
	AND	8
	RET	Z
	PUSH	HL
	LD	HL,LOGBUF
	PUSH	HL
	CALL	@TIME
	POP	HL
	LD	DE,JLDCB$
	CALL	@MSG
	POP	HL
	JR	@MSG

LOGBUF	DB	'hh:mm:ss  ',3

;==============================================================================
; Line print routine
;==============================================================================
@PRINT	LD	DE,PRDCB$
	JR	@MSG

;==============================================================================
; Line display routine
;==============================================================================
@DSPLY	LD	DE,DODCB$

;==============================================================================
; Device message routine
;==============================================================================
@MSG	PUSH	HL
$?1	LD	A,(HL)
	CP	3
	JR	Z,$?3
	CP	CR
	JR	Z,$?2
	CALL	NZ,@PUT
	INC	HL
	JR	Z,$?1
$?2	CALL	Z,@PUT
$?3	POP	HL
	RET

;==============================================================================
; Clear screen routine
;==============================================================================
@CLS	LD	A,HOME
	CALL	DSPBYT
	RET	NZ
	LD	A,CLRFRM
DSPBYT	PUSH	DE
	CALL	@DSP
	POP	DE
	RET

;==============================================================================
; Check and clear <BREAK> bit
;==============================================================================
@CKBRKC
	PUSH	HL
	LD	HL,KFLAG$
	BIT	0,(HL)
	JR	Z,NOBRK
	PUSH	AF
	PUSH	BC
	PUSH	DE
BRKTEST	RES	0,(HL)
	LD	BC,0B00H
	CALL	PAUSE@
	BIT	0,(HL)
	JR	NZ,BRKTEST
	LD	DE,KIDCB$
	LD	A,3
	CALL	@CTL
	POP	DE
	POP	BC
	POP	AF
NOBRK	POP	HL
	RET

;==============================================================================
; Keyboard line input routine
;==============================================================================
$?4	CALL	$?6
	DEC	HL
	LD	A,(HL)
	INC	HL
	CP	0AH
	RET	Z
$?5	LD	A,B
	CP	C
	JR	NZ,$?4
	RET

@KEYIN	PUSH	HL
	LD	C,B
$?1	LD	DE,@KEY
	LD	A,(SFLAG$)
	AND	20H
	JR	Z,$?0
	LD	E,@JCL&0FFH
$?0	LD	($?1A+1),DE
$?1A	CALL	$-$		;Self-modified call
	JR	NZ,$?3B
	CP	80H
	JR	Z,$?10
	CP	20H
	JR	NC,$?2
	CP	0DH
	JR	Z,$?11
	CP	1FH
	JR	Z,$?3
	LD	DE,$?1
	PUSH	DE
	CP	08H
	JR	Z,$?6
	CP	18H
	JR	Z,$?5
	CP	09H
	JR	Z,$?8
	CP	'R'&1FH
	JR	Z,$?7
	CP	0AH
	RET	NZ
	POP	DE
$?2	LD	(HL),A
	LD	A,B
	OR	A
	JR	Z,$?1
	LD	A,(HL)
	INC	HL
	DEC	B
	CALL	@DSP
	JR	$?3A

$?3	CALL	@CLS
	LD	B,C
	POP	HL
	PUSH	HL
$?3A	JR	Z,$?1
$?3B	JR	$?11

$?6	LD	A,B
	CP	C
	RET	Z
	DEC	HL
	LD	A,(HL)
	CP	0AH
	INC	HL
	RET	Z
	DEC	HL
	INC	B
	LD	A,8
	JR	@DSP

$?7	LD	A,(CFLAG$)
	AND	4
	RET	Z
	LD	A,B
	CP	C
	RET	NZ
	POP	HL
	POP	HL
	JP	@DSPLY

$?8	PUSH	HL
	LD	HL,(CURSOR)
	LD	A,L		;Get column
	POP	HL
	AND	7
	NEG
	ADD	A,8
	LD	E,A
$?9	LD	A,B
	OR	A
	RET	Z
	LD	A,' '
	LD	(HL),A
	INC	HL
	CALL	DSPBYT
	RET	NZ
	DEC	B
	DEC	E
	RET	Z
	JR	$?9

$?10	SCF
$?11	PUSH	AF
	LD	A,0DH
	LD	(HL),A
	CALL	@DSP
	LD	A,C
	SUB	B
	LD	B,A
	POP	AF
	POP	HL
	RET

;==============================================================================
; Byte I/O device handler
;==============================================================================
@CTL	PUSH	BC
	LD	B,4		;Bit 2 = CTL
	JR	IOBGN

@KEY	CALL	@KBD
	RET	Z
	OR	A
	JR	Z,@KEY
	RET

@JCL	LD	DE,JCLCB$
	JR	@GET

@KBD	LD	DE,KIDCB$
@GET	PUSH	BC
	LD	B,1		;Bit 0 = GET
	JR	IOBGN

@PRT	LD	DE,PRDCB$
	JR	@PUT

@DSP	LD	DE,DODCB$
@PUT	PUSH	BC
	LD	B,2		;Bit 1 = PUT

IOBGN	PUSH	IX
	PUSH	HL
	PUSH	DE
	POP	IX
	PUSH	DE
	LD	C,A
	LD	HL,@RSTREG
	LD	A,(LBANK$)
	OR	A
	JR	Z,$?0

	PUSH	BC
	XOR	A
	LD	B,A
	LD	C,A
	CALL	@BANK
	LD	H,B
	LD	L,C
	POP	BC
	PUSH	HL
	LD	HL,RSTBNK
$?0	PUSH	HL
	LD	A,(DE)
	OR	A
	RET	Z
	CP	8
	JR	NC,@CHNIO
	LD	L,(IX+1)
	LD	H,(IX+2)
$?1	LD	A,B
	CP	2
	JP	(HL)

RSTBNK	POP	BC
	PUSH	AF
	LD	A,C
	CALL	@BANK
	POP	AF
@RSTREG	POP	DE
	POP	HL
	POP	IX
	POP	BC
	RET

$?2	PUSH	HL
	POP	IX
@CHNIO	LD	L,(IX+1)
	LD	H,(IX+2)
$?3	LD	A,(IX+0)
	OR	A
	JP	M,@BYTEIO
	BIT	3,A
	JR	NZ,$?5
	BIT	4,A
	JR	NZ,$?2
	BIT	5,A
	JR	Z,$?1
	PUSH	HL
	POP	IX
	LD	(IX+3),B
	PUSH	IX
	CALL	@CHNIO
	POP	IX
	LD	B,(IX+3)
	JR	NZ,$?6

	BIT	0,B
$?4	LD	L,(IX+4)
	LD	H,(IX+5)
	JR	Z,$?2
$?5	CP	A
	RET

$?6	BIT	0,B
	JR	Z,$?7
	OR	A
	JR	Z,$?4
$?7	OR	A
	RET

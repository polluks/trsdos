;****************************************************************
;* Filename: C128_IODVR.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* Commodore 128 I/O Handler for LSDOS 6.3.1L Port		*
;****************************************************************
;*								*
;* Replaces IODVR/ASM. Provides the same _KEYIN, _DSPLY,	*
;* _PRINT, _MSG, _LOGOT, _LOGER, _CLS, _CKBRKC routines	*
;* but adapted for C128 hardware.				*
;*								*
;****************************************************************
	; SUBTTL (converted)
	; PAGE (converted)

HOME	EQU	1CH
CLRFRM	EQU	1FH

;==============================================================================
; Log out routine - display & log
;==============================================================================
_LOGOT	CALL	_DSPLY

; Job log logger routine
_LOGER	LD	A,(JLDCB_S)
	XOR	8
	AND	8
	RET	Z
	PUSH	HL
	LD	HL,LOGBUF
	PUSH	HL
	CALL	_TIME
	POP	HL
	LD	DE,JLDCB_S
	CALL	_MSG
	POP	HL
	JR	_MSG

LOGBUF	DB	'hh:mm:ss  ',3

;==============================================================================
; Line print routine
;==============================================================================
_PRINT	LD	DE,PRDCB_S
	JR	_MSG

;==============================================================================
; Line display routine
;==============================================================================
_DSPLY	LD	DE,DODCB_S

;==============================================================================
; Device message routine
;==============================================================================
_MSG	PUSH	HL
_L_1_56	LD	A,(HL)
	CP	3
	JR	Z,_L_3_65
	CP	CR
	JR	Z,_L_2_64
	CALL	NZ,_PUT
	INC	HL
	JR	Z,_L_1_56
_L_2_64	CALL	Z,_PUT
_L_3_65	POP	HL
	RET

;==============================================================================
; Clear screen routine
;==============================================================================
_CLS	LD	A,HOME
	CALL	DSPBYT
	RET	NZ
	LD	A,CLRFRM
DSPBYT	PUSH	DE
	CALL	_DSP
	POP	DE
	RET

;==============================================================================
; Check and clear <BREAK> bit
;==============================================================================
_CKBRKC
	PUSH	HL
	LD	HL,KFLAG_S
	BIT	0,(HL)
	JR	Z,NOBRK
	PUSH	AF
	PUSH	BC
	PUSH	DE
BRKTEST	RES	0,(HL)
	LD	BC,0B00H
	CALL	PAUSE_
	BIT	0,(HL)
	JR	NZ,BRKTEST
	LD	DE,KIDCB_S
	LD	A,3
	CALL	_CTL
	POP	DE
	POP	BC
	POP	AF
NOBRK	POP	HL
	RET

;==============================================================================
; Keyboard line input routine
;==============================================================================
_L_4_108	CALL	_L_6_0
	DEC	HL
	LD	A,(HL)
	INC	HL
	CP	0AH
	RET	Z
_L_5_114	LD	A,B
	CP	C
	JR	NZ,_L_4_108
	RET

_KEYIN	PUSH	HL
	LD	C,B
_L_1_121	LD	DE,_KEY
	LD	A,(SFLAG_S)
	AND	20H
	JR	Z,_L_0_126
	LD	E,_JCL&0FFH
_L_0_126	LD	(_L_1A_127+1),DE
_L_1A_127	CALL	$-$		;Self-modified call
	JR	NZ,_L_3B_165
	CP	80H
	JR	Z,_L_10_211
	CP	20H
	JR	NC,_L_2_150
	CP	0DH
	JR	Z,_L_11_212
	CP	1FH
	JR	Z,_L_3_160
	LD	DE,_L_1_121
	PUSH	DE
	CP	08H
	JR	Z,_L_6_167
	CP	18H
	JR	Z,_L_5_114
	CP	09H
	JR	Z,_L_8_190
	CP	'R'&1FH
	JR	Z,_L_7_180
	CP	0AH
	RET	NZ
	POP	DE
_L_2_150	LD	(HL),A
	LD	A,B
	OR	A
	JR	Z,_L_1_121
	LD	A,(HL)
	INC	HL
	DEC	B
	CALL	_DSP
	JR	_L_3A_164

_L_3_160	CALL	_CLS
	LD	B,C
	POP	HL
	PUSH	HL
_L_3A_164	JR	Z,_L_1_121
_L_3B_165	JR	_L_11_212

_L_6_167	LD	A,B
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
	JR	_DSP

_L_7_180	LD	A,(CFLAG_S)
	AND	4
	RET	Z
	LD	A,B
	CP	C
	RET	NZ
	POP	HL
	POP	HL
	JP	_DSPLY

_L_8_190	PUSH	HL
	LD	HL,(CURSOR)
	LD	A,L		;Get column
	POP	HL
	AND	7
	NEG
	ADD	A,8
	LD	E,A
_L_9_198	LD	A,B
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
	JR	_L_9_198

_L_10_211	SCF
_L_11_212	PUSH	AF
	LD	A,0DH
	LD	(HL),A
	CALL	_DSP
	LD	A,C
	SUB	B
	LD	B,A
	POP	AF
	POP	HL
	RET

;==============================================================================
; Byte I/O device handler
;==============================================================================
_CTL	PUSH	BC
	LD	B,4		;Bit 2 = CTL
	JR	IOBGN

_KEY	CALL	_KBD
	RET	Z
	OR	A
	JR	Z,_KEY
	RET

_JCL	LD	DE,JCLCB_S
	JR	_GET

_KBD	LD	DE,KIDCB_S
_GET	PUSH	BC
	LD	B,1		;Bit 0 = GET
	JR	IOBGN

_PRT	LD	DE,PRDCB_S
	JR	_PUT

_DSP	LD	DE,DODCB_S
_PUT	PUSH	BC
	LD	B,2		;Bit 1 = PUT

IOBGN	PUSH	IX
	PUSH	HL
	PUSH	DE
	POP	IX
	PUSH	DE
	LD	C,A
	LD	HL,_RSTREG
	LD	A,(LBANK_S)
	OR	A
	JR	Z,_L_0_272

	PUSH	BC
	XOR	A
	LD	B,A
	LD	C,A
	CALL	_BANK
	LD	H,B
	LD	L,C
	POP	BC
	PUSH	HL
	LD	HL,RSTBNK
_L_0_272	PUSH	HL
	LD	A,(DE)
	OR	A
	RET	Z
	CP	8
	JR	NC,_CHNIO
	LD	L,(IX+1)
	LD	H,(IX+2)
_L_1_280	LD	A,B
	CP	2
	JP	(HL)

RSTBNK	POP	BC
	PUSH	AF
	LD	A,C
	CALL	_BANK
	POP	AF
_RSTREG	POP	DE
	POP	HL
	POP	IX
	POP	BC
	RET

_L_2_295	PUSH	HL
	POP	IX
_CHNIO	LD	L,(IX+1)
	LD	H,(IX+2)
_L_3_299	LD	A,(IX+0)
	OR	A
	JP	M,_BYTEIO
	BIT	3,A
	JR	NZ,_L_5_321
	BIT	4,A
	JR	NZ,_L_2_295
	BIT	5,A
	JR	Z,_L_1_280
	PUSH	HL
	POP	IX
	LD	(IX+3),B
	PUSH	IX
	CALL	_CHNIO
	POP	IX
	LD	B,(IX+3)
	JR	NZ,_L_6_324

	BIT	0,B
_L_4_318	LD	L,(IX+4)
	LD	H,(IX+5)
	JR	Z,_L_2_295
_L_5_321	CP	A
	RET

_L_6_324	BIT	0,B
	JR	Z,_L_7_328
	OR	A
	JR	Z,_L_4_318
_L_7_328	OR	A
	RET

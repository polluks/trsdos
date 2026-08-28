;****************************************************************
;* Filename: CPC_PRDVR.ASM					*
;* Rev Date: 11 May 26						*
;* Version : 1.0							*
;****************************************************************
;* Amstrad CPC Printer Driver for LSDOS 6.3.1L Port		*
;****************************************************************
;* Uses Centronics parallel port: data at $F000, strobe at $F100.*
;* Status (busy) read from PPI Port A bit 7.			*
;****************************************************************
	SUBTTL	'<CPC Printer Driver>'
	PAGE

;==============================================================================
; Printer Driver Entry
;==============================================================================
PRDVR	JR	PRBGN
	DW	PREND
	DB	3,'$PR'
	DW	PRDCB$
	DW	0

PRBGN	JR	Z,$?PUT
	JR	C,$?GET

; CTL request
	LD	A,C
	OR	A
	JR	Z,$?STAT
	JR	$?GET

; GET - not supported
$?GET	OR	0FFH
	CPL
	RET

; PUT - send character to printer
$?PUT	PUSH	HL
	PUSH	BC

	; Wait for printer ready (not busy)
	LD	E,0		;Timeout counter (B is used for (C) port access)
$?WAIT
	; Read printer status via PPI Port A (16-bit port, use (C))
	LD	BC,PPI_PA
	IN	A,(C)
	BIT	7,A		;Busy bit (active low)
	JR	Z,$?READY
	DEC	E
	JR	NZ,$?WAIT
	; Timeout - just continue (don't hang)
	JR	$?SEND

$?READY
	; Send data to printer
$?SEND
	LD	A,C
	LD	(PRT_DATA),A	;Write data

	; Strobe pulse
	XOR	A
	LD	(PRT_STROBE),A
	NOP
	NOP
	LD	A,1
	LD	(PRT_STROBE),A

	POP	BC
	POP	HL
	CP	A		;Set Z
	RET

; CTL 0 - status check
$?STAT
	LD	BC,PPI_PA
	IN	A,(C)
	; Bit 7 = busy (0=busy), bit 4 = select (1=selected)
	BIT	4,A
	JR	NZ,$?PRESENT
	; No printer
	LD	A,8		;Device not available
	OR	A
	RET
$?PRESENT
	XOR	A		;Ready
	RET

PREND	EQU	$-1

;****************************************************************
;* Filename: C128_PRDVR.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* Commodore 128 Printer Driver for LSDOS 6.3.1L Port		*
;****************************************************************
;*								*
;* Replaces PRDVR/ASM. Uses the serial IEC bus (device 4-5)	*
;* or the C128 user port for printer output.			*
;*								*
;****************************************************************
	; SUBTTL (converted)
	; PAGE (converted)


PRPORT	EQU	0F8H		;Simulated printer port for compatibility

;==============================================================================
; Printer Driver Entry Point
;==============================================================================
; Entry: C = character to print (PUT), or control code (CTL)
;        Z flag set on PUT, CY on GET, NC+NZ on CTL
;==============================================================================
PRDVR	JR	PRBGN		;Branch around linkage
	DW	PREND		;Last byte used
	DB	3,'_L_PR_0'
	DW	PRDCB_S		;Pointer to its DCB
	DW	0		;Reserved

PRBGN	JR	Z,_L_2_45		;Go if PUT (output)
	JR	C,_L_1_40		;Go if GET (input)

; CTL request
	LD	A,C
	OR	A
	JR	Z,_L_4_75		;CTL 0 = status check
	JR	_L_1_40		;Otherwise treat as GET

; GET request - not supported on printer
_L_1_40	OR	0FFH		;Set NZ
	CPL
	RET

; PUT request - send character to printer
_L_2_45	; Write character to printer via IEC serial
	; Device 4 = printer device on IEC bus
	PUSH	HL
	PUSH	BC

	; Send LISTEN to printer device (4)
	LD	A,IEC_DEV_PRINT
	OR	IEC_LISTEN
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	LD	A,060H		;Secondary 0
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF

	; Send character
	LD	A,C
	CALL	IEC_BYTE_OUT

	; Send UNLISTEN
	LD	A,IEC_UNLISTEN
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF

	POP	BC
	POP	HL
	CP	A		;Set Z
	RET

; CTL 0 - check printer status
_L_4_75	; Check if printer is present (attempt to talk)
	LD	A,IEC_DEV_PRINT
	OR	IEC_TALK
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	LD	A,06FH		;Secondary 15
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF

	; Try to read status
	CALL	IEC_BYTE_IN
	CP	0		;If any response, printer is there
	PUSH	AF
	CALL	IEC_UNTALK
	POP	AF
	LD	A,0		;Return status in A
	RET

PREND	EQU	$-1

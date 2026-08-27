;****************************************************************
;* Filename: CPC_KIDVR.ASM					*
;* Rev Date: 11 May 26						*
;* Version : 1.0							*
;****************************************************************
;* Amstrad CPC Keyboard Driver for LSDOS 6.3.1L Port		*
;****************************************************************
;* Uses PPI (8255) to scan the CPC keyboard matrix (10 rows,	*
;* 8 columns). PPI Port A selects row (0-9), Port B returns	*
;* column data (active low, bits 5-0 = columns 5-0).		*
;****************************************************************
	SUBTTL	'<CPC Keyboard Driver>'
	PAGE

;==============================================================================
; Driver Header
;==============================================================================
KIDVR	JP	KIBGN
	DW	KILAST
	DB	3,'$KI'
	DW	KIDCB$
	DW	0

KIDATA	DB	0		;Last key entered
	DB	0		;Repeat time
RPTINIT	EQU	$-KIDATA
	DB	22		;33ms * 22 = 733ms initial delay
RPTRATE	EQU	$-KIDATA
	DB	2		;Repeat rate

; Row state images (10 rows)
KBDROWS	DS	10

; Modifier keys
MOD_SHIFT	EQU	01H
MOD_CTRL	EQU	02H
MOD_CAPS	EQU	04H

MOD_KEYS	DB	0	;Modifier state

; Special key codes
BRK_CODE	EQU	80H
F1_CODE		EQU	81H
F2_CODE		EQU	82H
F3_CODE		EQU	83H
F4_CODE		EQU	84H
F5_CODE		EQU	85H
F6_CODE		EQU	86H
F7_CODE		EQU	87H
F8_CODE		EQU	88H
F9_CODE		EQU	89H

; CPC keyboard row mapping (for key code lookup):
; Row 0: CUR D, CUR R, CUR U, CUR L, ENTER, F3, F2, F1
; Row 1: EXTRA(UNUSED), -, -, CLR, ], [, RET, EXTRA
; Row 2: \, =, ^, _, ', @, DEL, |
; Row 3: 0, 9, 8, 7, 6, 5, 4, 3
; Row 4: 2, 1, ,, ., /, :, ;, )
; Row 5: P, O, I, U, Y, T, R, E
; Row 6: W, Q, TAB, ESC, F6, F5, F4, F0
; Row 7: L, K, J, H, G, F, D, S
; Row 8: N, M, B, V, C, X, Z, A
; Row 9: SPACE, F7, F8, F9, CAPS, CTRL, SHIFT, EXTRA

; Unshifted key codes (10 rows × 6 usable columns)
ROW0	DB	0AH,1CH,0BH,08H,0DH,85H,84H,83H	;CUR D,R,U,L,ENTR,F3,F2,F1
ROW1	DB	0,0,0,1CH,0DDH,0DBH,0DH,0		;CLR,],[,ENTER
ROW2	DB	0DCH,'=','^','_',27H,'@',7FH,3CH	;\,=,^,_,',@,DEL,|
ROW3	DB	'0','9','8','7','6','5','4','3'
ROW4	DB	'2','1',',','.','/',':',';',')'
ROW5	DB	'P','O','I','U','Y','T','R','E'
ROW6	DB	'W','Q',09H,1BH,86H,85H,84H,83H	;W,Q,TAB,ESC,F6,F5,F4,F0
ROW7	DB	'L','K','J','H','G','F','D','S'
ROW8	DB	'N','M','B','V','C','X','Z','A'
ROW9	DB	' ',87H,88H,89H,0,0,0,0		;SPC,F7,F8,F9,CAPS,CTRL,SHIFT

; Shifted key codes
ROW0_S	DB	0AH,1CH,0BH,08H,0DH,85H,84H,83H
ROW1_S	DB	0,0,0,1CH,0DDH,0DBH,0DH,0
ROW2_S	DB	'|','+','~',0,'"',0,7FH,'>'
ROW3_S	DB	')','(','*',0,0,0,0,'#'
ROW4_S	DB	'"','!',';','?','/','*','+',0
ROW5_S	DB	'P','O','I','U','Y','T','R','E'
ROW6_S	DB	'W','Q',09H,1BH,86H,85H,84H,83H
ROW7_S	DB	'L','K','J','H','G','F','D','S'
ROW8_S	DB	'N','M','B','V','C','X','Z','A'
ROW9_S	DB	' ',87H,88H,89H,0,0,0,0

; Key table pointer list
KEYTABS	DW	ROW0,ROW1,ROW2,ROW3,ROW4,ROW5,ROW6,ROW7,ROW8,ROW9
KEYTABS_S DW	ROW0_S,ROW1_S,ROW2_S,ROW3_S,ROW4_S,ROW5_S,ROW6_S,ROW7_S,ROW8_S,ROW9_S

;==============================================================================
; Keyboard Driver Entry
;==============================================================================
KIBGN	LD	A,C
	PUSH	AF
	CALL	@KITSK
	POP	AF
	CALL	TYPAHD
	RET	NC
	PUSH	AF
	CP	':'
	JR	Z,$?SCRPRT
	POP	AF
	RET
$?SCRPRT	POP	AF
	; Screen print - simplified
	RET

;==============================================================================
; Keyboard Scan
;==============================================================================
KISCAN
	LD	IX,KIDATA
	; Scan all 10 rows
	LD	B,10		;Rows 0-9
	LD	D,0		;Row number
$?ROWSCAN
	PUSH	BC
	PUSH	DE

	; Select row
	LD	A,D		;Row number
	OUT	(PPI_PA),A
	NOP
	NOP
	NOP
	NOP

	; Read column data (active low)
	IN	A,(PPI_PB)
	CPL			;Active high now
	AND	3FH		;Only lower 6 bits (some sources say 6 bits)

	JR	Z,$?NEXTROW	;No key in this row

	; Key pressed in this row - find which column
	LD	E,A		;E = column data
	LD	C,0		;Column counter

$?COLLOOP
	RRA			;Shift bit 0 into carry
	JR	C,$?KEYFOUND
	INC	C		;Next column
	JR	$?COLLOOP

$?KEYFOUND
	; D = row, C = col
	; Check modifiers first
	LD	A,D
	CP	9
	JR	NZ,$?NOT_ROW9
	; Row 9: check for CAPS (col 4), CTRL (col 5), SHIFT (col 6)
	LD	A,C
	CP	4
	JR	Z,$?SET_CAPS
	CP	5
	JR	Z,$?SET_CTRL
	CP	6
	JR	Z,$?SET_SHIFT
	JR	$?REGKEY

$?NOT_ROW9
	; Regular key - get key code
$?REGKEY
	; Determine if shifted
	LD	A,(MOD_KEYS)
	BIT	0,A		;Shift?
	JR	Z,$?UNSHIFTED

	; Use shifted table
	LD	A,D		;Row
	ADD	A,A		;*2
	LD	E,A
	LD	D,0
	LD	HL,KEYTABS_S
	ADD	HL,DE
	LD	A,(HL)
	INC	HL
	LD	H,(HL)
	LD	L,A		;HL = shifted key table row
	JR	$?GETKEY

$?UNSHIFTED
	LD	A,D		;Row
	ADD	A,A		;*2
	LD	E,A
	LD	D,0
	LD	HL,KEYTABS
	ADD	HL,DE
	LD	A,(HL)
	INC	HL
	LD	H,(HL)
	LD	L,A		;HL = unshifted key table row

$?GETKEY
	; Add column offset
	LD	A,C		;Column
	LD	E,A
	LD	D,0
	ADD	HL,DE
	LD	A,(HL)		;Get key code
	OR	A
	JR	Z,$?NEXTROW	;Skip if 0

	POP	DE
	POP	BC
	CP	A		;Set Z, key found
	RET

$?SET_SHIFT
	LD	HL,MOD_KEYS
	SET	0,(HL)
	JR	$?NEXTROW
$?SET_CTRL
	LD	HL,MOD_KEYS
	SET	1,(HL)
	JR	$?NEXTROW
$?SET_CAPS
	LD	HL,MOD_KEYS
	BIT	2,(HL)
	JR	NZ,$?CAPS_OFF
	SET	2,(HL)
	JR	$?NEXTROW
$?CAPS_OFF
	RES	2,(HL)
	JR	$?NEXTROW

$?NEXTROW
	; All keys in this row released - clear modifiers?
	; But we only clear if released, which we check in the row scan
	; For now, just advance to next row
	POP	DE
	POP	BC
	INC	D
	DJNZ	$?ROWSCAN

	; No keys found - check if all previously held keys released
	; If so, clear modifiers
	XOR	A
	LD	IX,KIDATA
	LD	(IX+0),A	;Clear last key
	OR	1		;NZ, no key
	RET

;==============================================================================
; Type-ahead buffer
;==============================================================================
TYPAHD	LD	HL,TYPBUF
	LD	(HL),0FFH
	JP	C,$?TA1
	JP	Z,TYPON
	CP	3
	JP	Z,CLRTYP
	INC	A
	JR	Z,CTLFF
	XOR	A
	JR	TYPON

CTLFF	; Keyboard scan to user buffer
	PUSH	IY
	POP	HL
	LD	B,10
$?CTLFF_LP
	LD	A,B
	DEC	A
	OUT	(PPI_PA),A
	NOP
	IN	A,(PPI_PB)
	CPL
	AND	3FH
	LD	(IY),A
	INC	IY
	DJNZ	$?CTLFF_LP
	RET

$?TA1	PUSH	HL
	INC	HL
	LD	A,(HL)
	INC	HL
	CP	(HL)
	JR	Z,$?TA4
	PUSH	HL
	LD	E,(HL)
	INC	HL
	LD	D,0
	ADD	HL,DE
	LD	B,(HL)
	POP	HL
	INC	(HL)
	LD	A,80
	CP	(HL)
	JR	NC,$?TA2
	LD	(HL),0
$?TA2	LD	A,(HL)
	DEC	HL
	CP	(HL)
	CALL	Z,R7KFLG
	POP	HL
	LD	(HL),0
	LD	A,B
	CP	A
	RET

$?TA4	CALL	KISCAN
	POP	HL
TYPON	LD	(HL),0
	RET

TYPTSK	DW	$?TA5
$?TA5	LD	A,(DFLAG$)
	AND	2
	RET	Z
	LD	HL,TYPBUF
	LD	A,(HL)
	OR	A
	RET	NZ
	INC	HL
	PUSH	HL
	CALL	KISCAN
	POP	HL
	RET	NZ
	PUSH	AF
	POP	BC
	CP	80H
	PUSH	AF
	PUSH	HL
	CALL	Z,$?CLRT
	POP	HL
	POP	AF
	CP	0C0H
	JR	Z,$?CLRT
	LD	E,(HL)
	LD	A,E
	INC	HL
	CP	(HL)
	JR	Z,$?TA8
	LD	A,(TIMER$)
	ADD	A,(IX+RPTRATE)
	CP	(IX+1)
	JR	NZ,$?TA7
	ADD	A,(IX+RPTRATE)
	LD	(IX+1),A
	RET
$?CLRT	XOR	A
	LD	(HL),A
	INC	HL
	LD	(HL),A
R7KFLG	LD	HL,KFLAG$
	RES	7,(HL)
	RET
$?TA7	LD	A,E
	INC	A
	CP	(HL)
	RET	Z
$?TA8	PUSH	HL
	INC	HL
	LD	D,0
	ADD	HL,DE
	LD	(HL),B
	LD	HL,KFLAG$
	SET	7,(HL)
	POP	HL
	DEC	HL
	INC	(HL)
	LD	A,80
	CP	(HL)
	RET	NC
	LD	(HL),D
	RET

TYPBUF	EQU	0FF80H
KILAST	EQU	$-1

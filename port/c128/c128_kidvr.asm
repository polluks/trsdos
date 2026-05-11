;****************************************************************
;* Filename: C128_KIDVR.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* Commodore 128 Keyboard Driver for LSDOS 6.3.1L Port		*
;****************************************************************
;*								*
;* Replaces KIDVR/ASM. Uses CIA #1 to scan the C128 keyboard	*
;* matrix. The keyboard is read by selecting a row via		*
;* CIA#1 Port A and reading the column state via Port B.		*
;*								*
;****************************************************************
	SUBTTL	'<C128 Keyboard Driver>'
	PAGE


; LF, CR defined in c128_sysres.asm

;==============================================================================
; Keyboard Matrix Definitions
;==============================================================================
; The C128 keyboard is scanned via CIA #1:
;   Write row select to CIA1_PRA (PA0-PA7)
;   Read column state from CIA1_PRB (PB0-PB7)
;
; Standard C128 keyboard matrix:
;         PB0   PB1   PB2   PB3   PB4   PB5   PB6   PB7
; PA0=1:  3     6     -     =     R     N     9     C=
; PA1=2:  W     +     A     .     ,     H     3     STOP
; PA2=4:  A     S     B     /     ;     J     6     ESC
; PA3=8:  4     Z     C     SP    *     K     2     ;
; PA4=10: 5     1     D     Q     SHL   L     0     ENTER
; PA5=20: F     2     E     M     8     :     7     DEL
; PA6=40: 7     4     X     @     -     O     1     CRSR-R
; PA7=80: T     G     I     P     U     Y     W     CRSR-D

;==============================================================================
; Driver Header & Data Area
;==============================================================================
KIDVR	JP	KIBGN		;Branch around linkage
	DW	KILAST		;Last byte used
	DB	3,'$KI'
	DW	KIDCB$		;Pointer to DCB
	DW	0		;Spare

KIDATA$	DB	0		;Last key entered
	DB	0		;Repeat time check
RPTINIT	EQU	$-KIDATA$
	DB	22		;22 * 33.3ms = 0.733 secs
RPTRATE	EQU	$-KIDATA$
	DB	2		;2 x RTC rate
KBDROW0	EQU	$-KIDATA$
	DB	-1,-1,-1,-1	;Image of rows 0-3
KBDROW4	EQU	$-KIDATA$
	DB	-1,-1		;Image of rows 4,5
KBDROW6	EQU	$-KIDATA$
	DB	-1,-1		;Image of rows 6,7

; Modifier key states (bits)
MOD_SHIFT	EQU	01H
MOD_CTRL	EQU	02H
MOD_CBM		EQU	04H	;Commodore key
MOD_ALT		EQU	08H	;ALT/40/80 key
MOD_CAPS	EQU	10H	;Caps lock
MOD_STOP	EQU	20H	;Stop/run
MOD_LOCK	EQU	40H	;Shift lock

MOD_KEYS	DB	0	;Current modifier state

;==============================================================================
; Special key codes returned by LSDOS keyboard driver
;==============================================================================
BRK_CODE	EQU	80H	;Break code
F1_CODE		EQU	81H	;Function key 1
F2_CODE		EQU	82H
F3_CODE		EQU	83H
F4_CODE		EQU	84H
F5_CODE		EQU	85H
F6_CODE		EQU	86H
F7_CODE		EQU	87H
F8_CODE		EQU	88H
HELP_CODE	EQU	89H
ESC_CODE	EQU	1BH	;Escape

;==============================================================================
; C128 Keymap Tables (US layout)
;==============================================================================
; Row 0: PA=01: 3, 6, -, =, R, N, 9, C=
ROW0_UN	DB	'3','6','-','=','R','N','9',0
ROW0_SH	DB	'#','^','_','+','R','N',')',0

; Row 1: PA=02: W, +, A, ., ,, H, 3, STOP
ROW1_UN	DB	'W','+','A','.',',','H','3',0
ROW1_SH	DB	'W','+','A','>','<','H','#',0

; Row 2: PA=04: A, S, B, /, ;, J, 6, ESC
ROW2_UN	DB	'A','S','B','/',';','J','6',1BH
ROW2_SH	DB	'A','S','B','?',':','J','^',1BH

; Row 3: PA=08: 4, Z, C, SP, *, K, 2, ;
ROW3_UN	DB	'4','Z','C',' ','*','K','2',';'
ROW3_SH	DB	'$','Z','C',' ','*','K','@',':'

; Row 4: PA=10: 5, 1, D, Q, SHL, L, 0, ENTER
ROW4_UN	DB	'5','1','D','Q',0,'L','0',0DH
ROW4_SH	DB	'%','!','D','Q',0,'L','0',0DH

; Row 5: PA=20: F, 2, E, M, 8, :, 7, DEL
ROW5_UN	DB	'F','2','E','M','8',':','7',08H
ROW5_SH	DB	'F','@','E','M','(','*',27H,08H

; Row 6: PA=40: 7, 4, X, @, -, O, 1, CRSR-R
ROW6_UN	DB	'7','4','X','@','-','O','1',1CH
ROW6_SH	DB	27H,'$','X','@','_','O','!',1CH

; Row 7: PA=80: T, G, I, P, U, Y, W, CRSR-D
ROW7_UN	DB	'T','G','I','P','U','Y','W',0AH
ROW7_SH	DB	'T','G','I','P','U','Y','W',0AH

;==============================================================================
; Keyboard Driver Entry Point
;==============================================================================
KIBGN	LD	A,C		;Get the character
	PUSH	AF
	CALL	@KITSK		;Hook for KI task
	POP	AF

; Screen print (Control-*) processing
	CALL	TYPAHD		;Chain downstream
	RET	NC		;Return if not CONTROL
	PUSH	AF
	CP	':'
	JR	Z,$?1		;Go if screen print
	POP	AF
	RET

; Screen print
$?1	POP	AF
@PRTSCR	LD	A,(DFLAG$)
	RLCA
	LD	A,3EH		;LD A,'.'
	JR	NC,$?7
	LD	A,0FEH		;CP N
$?7	LD	($?4),A
	LD	HL,KFLAG$
	RES	0,(HL)
	PUSH	HL
	LD	HL,0
$?2	LD	B,1
	CALL	@VDCTL		;Get char at row H, col L
	JR	NZ,$?6
	CP	20H
	JR	NC,$?8
	ADD	A,40H
$?8	CP	80H
	JR	C,$?5
$?4	LD	A,'.'
$?5	CALL	@PRT
	JR	NZ,$?6
	INC	L
	LD	A,L
	SUB	80
	JR	NZ,$?2
	LD	L,A
	DEC	L
	EX	(SP),HL
	BIT	0,(HL)
	EX	(SP),HL
	JR	NZ,$?6
	INC	H
	LD	A,H
	CP	25
	LD	A,CR
	JR	NZ,$?5
$?6	LD	A,CR
	CALL	@PRT
	POP	HL
	RES	0,(HL)
	JR	NOCHAR

;==============================================================================
; Keyboard Scan Routine
;==============================================================================
KISCAN
	LD	IX,KIDATA$
	CALL	SCAN_MATRIX	;Scan the physical keyboard
	RET	NZ		;Return if error
	OR	A		;Key pressed?
	JR	Z,NOCHAR	;No key
	LD	(IX+0),A	;Store key code
	; Check for repeat
	LD	A,(TIMER$)
	SUB	(IX+1)
	SUB	(IX+RPTINIT)
	JR	C,KYOUT		;Output if repeat time met
	OR	1
	LD	A,0
	RET

NOCHAR	OR	1
	LD	A,0
	RET

; Send key code
KYOUT	LD	A,(IX+0)
	OR	A
	JP	Z,NOCHAR
	CP	A		;Set Z
	RET

;==============================================================================
; Physical Keyboard Matrix Scanner
;==============================================================================
; Scans the C128 keyboard matrix via CIA #1
; Returns: A=0 if no key, A=keycode if key, Z flag set on key found
; Modifies: AF, BC, HL
;==============================================================================
SCAN_MATRIX
	PUSH	BC
	PUSH	HL
	LD	HL,KBDROW0	;Point to saved row states
	LD	B,8		;8 rows to scan
	LD	D,0		;Row counter

$?ROW	LD	A,0FFH		;All bits set = no row selected
	LD	(CIA1_PRA),A	;Deselect all rows first
	LD	A,D		;Get row mask
	RRCA			;Shift to correct position
	LD	(CIA1_PRA),A	;Select this row
	NOP			;Brief delay for signal settling
	NOP
	NOP
	NOP
	LD	A,(CIA1_PRB)	;Read columns
	CPL			;Invert: pressed keys = 1
	LD	E,A		;Save in E
	XOR	(HL)		;Compare with previous state
	JR	NZ,$?CHANGED	;Go if change detected
	INC	HL		;Next row state
	INC	D		;Next row
	DJNZ	$?ROW		;Loop all 8 rows
	; All rows match previous state - no change
	LD	A,(IX+0)	;Get last key
	OR	A
	JP	Z,$?NOKEY
	; Key held - check repeat timing
	POP	HL
	POP	BC
	LD	A,1		;Signal key held
	OR	A
	RET

$?CHANGED
	LD	(HL),E		;Update row state
	AND	E		;Only pressed bits (key down edge)
	JP	Z,$?NOKEY	;If no press, skip

	; Convert matrix position to keycode
	; E = row data (pressed keys), D = row number
	; Find which column bit is set
	LD	B,8		;8 columns to check
	LD	C,1		;Start with bit 0
$?COLLP	LD	A,C
	AND	E		;Check if this column is pressed
	JR	NZ,$?KEYFOUND	;Found the key
	RLC	C		;Next column bit
	DJNZ	$?COLLP
	JP	$?NOKEY		;Shouldn't happen

$?KEYFOUND
	; D = row (0-7), B = column (7 - col_num)
	; Convert to linear key index: row*8 + col
	LD	A,D
	RLCA			;*2
	RLCA			;*4
	RLCA			;*8
	ADD	A,8
	SUB	B		;A = row*8 + (7-col) = key index
	LD	E,A		;Save index

	; Scan modifier keys first
	CALL	CHECK_MODIFIERS
	JR	NZ,$?NOKEY	;If modifier only, return no key

	; Convert key index to ASCII/scancode using lookup table
	LD	A,E
	CP	8*8		;Max keys
	JR	NC,$?NOKEY

	; Compute which row table
	LD	A,D		;Row number
	RLCA			;*2 (2 bytes per table entry)
	LD	HL,KEYTABLES
	LD	E,A
	LD	D,0
	ADD	HL,DE		;HL -> table entry
	LD	A,(HL)		;Low byte of key table addr
	INC	HL
	LD	H,(HL)		;High byte
	LD	L,A
	; Now HL -> key table for this row
	; B = column bit position for this key
	LD	A,8
	SUB	B		;A = column index (0-7)
	LD	E,A
	LD	D,0
	ADD	HL,DE		;HL -> specific key

	; Check SHIFT modifier
	LD	A,(MOD_KEYS)
	BIT	0,A		;Shift?
	JR	Z,$?NOSHIFT
	; Use shifted table (8 bytes after unshifted)
	LD	DE,8
	ADD	HL,DE

$?NOSHIFT
	; Check CTRL modifier
	LD	A,(MOD_KEYS)
	BIT	1,A
	JR	Z,$?NOCTRL
	; CTRL: force to 00-1F range
	LD	A,(HL)
	AND	1FH
	JR	$?KEYDONE

$?NOCTRL
	; Check Commodore key
	BIT	2,A
	JR	Z,$?NOCBM
	; CBM key: use alternate mapping
	LD	A,(HL)
	; For CBM, we'd map to graphics chars
	; For now, just OR with 80h
	OR	80H
	JR	$?KEYDONE

$?NOCBM
	LD	A,(HL)		;Get the actual key code

$?KEYDONE
	OR	A		;Is it 0 (unmapped)?
	JR	Z,$?NOKEY	;Skip if unmapped

	; Handle special keys
	CP	0DH		;Enter?
	JR	Z,$?HAVEKEY
	CP	08H		;Backspace?
	JR	Z,$?HAVEKEY
	CP	1BH		;Escape?
	JR	Z,$?HAVEKEY
	CP	1CH		;Cursor right?
	JR	Z,$?HAVEKEY
	CP	0AH		;Cursor down?
	JR	Z,$?HAVEKEY

	; Check CAPS LOCK
	BIT	4,A		;Caps lock modifier bit
	JR	Z,$?CHKCAPS
	LD	A,(MOD_KEYS)
	XOR	MOD_CAPS	;Toggle caps lock
	LD	(MOD_KEYS),A
	JR	$?NOKEY

$?CHKCAPS
	BIT	4,A		;This is actually checking if key is alpha
	; Actually let me just check for A-Z range
	CP	'A'
	JR	C,$?HAVEKEY
	CP	'Z'+1
	JR	NC,$?HAVEKEY
	; It's a letter - check caps lock
	LD	A,(MOD_KEYS)
	BIT	4,A		;Caps lock?
	JR	Z,$?HAVEKEY
	; Caps lock active, toggle case
	LD	A,(HL)
	XOR	20H

$?HAVEKEY
	CP	0		;Check if zeroed
	JR	Z,$?NOKEY
	POP	HL
	POP	BC
	CP	A		;Set Z flag
	RET

$?NOKEY	POP	HL
	POP	BC
	XOR	A		;Return A=0, NZ
	OR	1
	RET

;==============================================================================
; Modifier Key Check
;==============================================================================
; Checks if the pressed key is a modifier (Shift, Ctrl, C=, etc.)
; Returns: Z if modifier, NZ if regular key
;==============================================================================
CHECK_MODIFIERS
	; D = row, B = column (inverted for C128)
	; Modifier keys are in specific positions:
	; Shift Left:  row 4, col 4 (PA4=10h, PB4)
	; Commodore:   row 2, col 7 (PA2=04h, PB7)
	; Stop:        row 1, col 7 (PA1=02h, PB7)
	; Ctrl:        row, col - not on C128 keyboard
	; Alt/40-80:   row, col
	;
	; For this port, we track modifiers but don't consume them

	; Check if it's in row 4 (Shift Lock area)
	LD	A,D
	CP	4
	JR	NZ,$?MOD1
	; Row 4 - possible SHIFT
	LD	A,B
	CP	3		;Column index for SHIFT
	JR	Z,$?SET_SHIFT
	CP	7		;ENTER
	JR	Z,$?NOT_MOD
	JR	$?NOT_MOD

$?MOD1	LD	A,D
	CP	1
	JR	NZ,$?MOD2
	LD	A,B
	CP	7
	JR	Z,$?SET_STOP
	JR	$?NOT_MOD

$?MOD2	LD	A,D
	CP	2
	JR	NZ,$?MOD3
	LD	A,B
	CP	7
	JR	Z,$?SET_CBM
	JR	$?NOT_MOD

$?MOD3	LD	A,D
	CP	0
	JR	NZ,$?NOT_MOD
	LD	A,B
	CP	7
	JR	Z,$?SET_CBM
	JR	$?NOT_MOD

$?SET_SHIFT
	LD	A,(MOD_KEYS)
	OR	MOD_SHIFT
	LD	(MOD_KEYS),A
	XOR	A		;Return Z (modifier consumed)
	RET

$?SET_CTRL
	LD	A,(MOD_KEYS)
	OR	MOD_CTRL
	LD	(MOD_KEYS),A
	XOR	A
	RET

$?SET_CBM
	LD	A,(MOD_KEYS)
	OR	MOD_CBM
	LD	(MOD_KEYS),A
	XOR	A
	RET

$?SET_STOP
	; STOP key = break
	LD	HL,KFLAG$
	SET	0,(HL)		;Set break bit
	; Don't consume - return as break code
	OR	1		;Return NZ (not modifier)
	RET

$?NOT_MOD
	OR	1		;Return NZ (not modifier, regular key)
	RET

;==============================================================================
; Key Table Pointers
;==============================================================================
KEYTABLES
	DW	ROW0_UN
	DW	ROW1_UN
	DW	ROW2_UN
	DW	ROW3_UN
	DW	ROW4_UN
	DW	ROW5_UN
	DW	ROW6_UN
	DW	ROW7_UN

;==============================================================================
; Type-Ahead Buffer Handling
;==============================================================================
TYPAHD
	LD	HL,TYPBUF
	LD	(HL),0FFH	;Turn off type ahead
	JP	C,$?1		;Go on @GET
	JP	Z,TYPON		;No PUT to *KI
	CP	3		;CTL 3 function?
	JP	Z,CLRTYP	;Clear buffer if so
	INC	A
	JR	Z,CTLFF		;Go if CTL 255 function
	XOR	A
	JR	TYPON

; CTL-255: Scan keyboard into user buffer
CTLFF	PUSH	IY
	POP	HL
	LD	B,8
$?0	LD	A,B
	DEC	A
	LD	(CIA1_PRA),A
	NOP
	LD	A,(CIA1_PRB)
	CPL
	LD	(IY),A
	INC	IY
	DJNZ	$?0
	RET

; GET from type-ahead buffer
$?1	PUSH	HL
	INC	HL		;Bump to PUT pointer
	LD	A,(HL)
	INC	HL		;Point to GET pointer
	CP	(HL)
	JR	Z,$?4		;Go if empty
	PUSH	HL
	LD	E,(HL)		;Offset to buffer start
	INC	HL
	LD	D,0
	ADD	HL,DE
	LD	B,(HL)		;Get stored char
	POP	HL
	INC	(HL)		;Bump GET pointer
	LD	A,80
	CP	(HL)
	JR	NC,$?2
	LD	(HL),0
$?2	LD	A,(HL)
	DEC	HL
	CP	(HL)
	CALL	Z,R7KFLG
	POP	HL
	LD	(HL),0
	LD	A,B
	CP	A
	RET

; No char in buffer - scan keyboard
$?4	CALL	KISCAN
	POP	HL
TYPON	LD	(HL),0
	RET

; Type-ahead task - scans keyboard in background
TYPTSK$	DW	$?5
$?5	LD	A,(DFLAG$)
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
	CALL	Z,$?6
	POP	HL
	POP	AF
	CP	0C0H
	JR	Z,$?6
	LD	E,(HL)
	LD	A,E
	INC	HL
	CP	(HL)
	JR	Z,$?8
	LD	A,(TIMER$)
	ADD	A,(IX+RPTRATE)
	CP	(IX+1)
	JR	NZ,$?7
	ADD	A,(IX+RPTRATE)
	LD	(IX+1),A
	RET

; Clear type-ahead buffer
CLRTYP	INC	HL
$?6	XOR	A
	LD	(HL),A
	INC	HL
	LD	(HL),A
R7KFLG	LD	HL,KFLAG$
	RES	7,(HL)
	RET

; Check for buffer overflow
$?7	LD	A,E
	INC	A
	CP	(HL)
	RET	Z
$?8	PUSH	HL
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

; Type-ahead buffer in high system RAM
TYPBUF	EQU	0FF80H

KILAST	EQU	$-1

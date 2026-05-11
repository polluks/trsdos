;****************************************************************
;* Filename: C128_DODVR.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* Commodore 128 VDC Video Driver for LSDOS 6.3.1L Port		*
;****************************************************************
;*								*
;* Replaces DODVR/ASM. Uses the 8563 VDC for 80-column		*
;* display. The VDC is NOT memory-mapped; all access is		*
;* through registers at $D600 (address) and $D601 (data).	*
;*								*
;* The VDC has 16K of internal VRAM forming a 80x25 or 80x50	*
;* text display. Characters and attributes are separate.		*
;*								*
;****************************************************************
	SUBTTL	'<C128 VDC Video Driver>'
	PAGE

; Import hardware definitions

;==============================================================================
; VDC Register Access Macros
;==============================================================================
; Select VDC register and write value
VDC_SET	MACRO	REG, VAL
	LD	A,REG
	LD	BC,VDC_ADDR
	OUT	(C),A
	LD	A,VAL
	LD	BC,VDC_DATA
	OUT	(C),A
	ENDM

; Select VDC register
VDC_SEL	MACRO	REG
	LD	A,REG
	LD	BC,VDC_ADDR
	OUT	(C),A
	ENDM

;==============================================================================
; Driver Data Area
;==============================================================================
DODVR	JR	DOBGN		;Branch around linkage
	DW	DOEND		;Last memory location used
	DB	3,'$DO'
	DW	DODCB$		;DCB used
	DW	0		;Reserved

DODATA$	EQU	$
DO_MASK	EQU	$-DODATA$
	DB	0		;Scroll protect (bits 0-2), tabs(3), ctl(4)

CURSOR	DW	0		;Cursor row,col (packed: row=H, col=L)
CRSAVE	DB	20H		;Character under cursor (space default)
CRSCHAR	DB	'_'		;Cursor character
INVIDEO	DB	0		;Inverse video mask (0=normal, 80h=inverse)
CURSTATE DB	0		;Cursor on/off state

;==============================================================================
; VDC Register Access Subroutines
;==============================================================================

; Write to VDC register A with value in C
VDC_WRITE
	PUSH	BC
	LD	BC,VDC_ADDR
	OUT	(C),A		;Select register
	LD	A,C		;Value to write
	LD	BC,VDC_DATA
	OUT	(C),A		;Write value
	POP	BC
	RET

; Read VDC register A, result in A
VDC_READ
	PUSH	BC
	LD	BC,VDC_ADDR
	OUT	(C),A		;Select register
	LD	BC,VDC_DATA
	IN	A,(C)		;Read value
	POP	BC
	RET

; Set VDC cursor position from (cursor_row, cursor_col)
; Cursor is stored as row in H, col in L (matching TRS-80 convention)
VDC_SETCURSOR
	PUSH	HL
	PUSH	AF
	PUSH	BC
	LD	HL,(CURSOR)	;H=row, L=col
	LD	A,H		;Row
	LD	B,VDC_COLS	;80 cols per row
	CALL	@MUL8		;A = row * 80
	ADD	A,L		;Add column
	LD	L,A		;Low byte of offset
	LD	A,H
	ADC	A,0		;High byte (carry)
	LD	H,A
	; HL now has cursor offset into VDC VRAM
	VDC_SEL	VDC_CURHIGH
	LD	BC,VDC_DATA
	OUT	(C),H		;Cursor position high
	VDC_SEL	VDC_CURLOW
	LD	A,L
	LD	(VDC_DATA),A		;Cursor position low
	POP	BC
	POP	AF
	POP	HL
	RET

;==============================================================================
; Video Driver Entry Points
;==============================================================================

; Entry from SVC 15, @VDCTL
@VDCTL	JP	@_VDCTL

; Main driver entry
DOBGN	LD	IX,DODATA$
	JP	C,$?0_GET	;Go on 'GET' request
	CALL	$?0		;Handle cursor normalization
	PUSH	BC
	LD	A,C		;Get char to display
	BIT	4,(IX+DO_MASK)	;Display controls set?
	JR	NZ,$?1A		;Go if so
	OR	A		;Char a 0?
	JP	Z,TGGLCTL	;Switch control display if so
	CP	20H		;Video control character?
	JP	C,DO_CONTROL	;Go if control char
$?1A	CP	0C0H		;Tab or special?
	JR	C,DONORM	;Go on normal characters
	BIT	3,(IX+DO_MASK)	;Tabs or special chars?
	JR	Z,DO_TABS	;Go if video tabs

DONORM	CALL	DO_DSPCHAR	;Display the char
	RES	4,(IX+DO_MASK)	;Turn off CTL bit
DO_RET	POP	BC		;Get orig char
	CP	A		;Clear status
	RET

; Tab expansion (C0-FF)
DO_TABS	SUB	0C0H		;Compute spaces
	JR	Z,DO_RET	;Forget if 0
	LD	B,A		;Display requested number
$?2	LD	C,' '
	CALL	DO_DSPCHAR
	DJNZ	$?2
	JR	DO_RET

;==============================================================================
; Control Character Processing
;==============================================================================
DO_CONTROL
	LD	HL,DO_RET
	PUSH	HL
	CP	08H		;Backspace?
	JR	Z,BACKSPA
	CP	0AH		;Linefeed?
	JR	Z,LINFEED
	SUB	0DH		;Carriage return?
	JP	Z,DOCON1
	DEC	A		;Cursor on (0EH)?
	JR	Z,CRSON
	DEC	A		;Cursor off (0FH)?
	JR	Z,CRSOFF
	DEC	A		;Reverse video on (10H)?
	JR	Z,DO_INVERT_ENA
	DEC	A		;Reverse video off (11H)?
	JR	Z,DO_INVERT_OFF
	SUB	4		;Swap tab/alternate (12H)?
	JR	Z,TGGLTAB
	DEC	A		;Special/alternate (13H)?
	JR	Z,TGGLALT
	DEC	A		;40 char mode (14H)?
	JR	Z,SET40
	DEC	A		;Cursor backspace (15H)?
	JR	Z,CRSBKSP
	DEC	A		;Cursor forward (16H)?
	JR	Z,CRSFRWD
	DEC	A		;Cursor down (17H)?
	JR	Z,CRSDOWN
	DEC	A		;Cursor up (18H)?
	JR	Z,CRSUP
	DEC	A		;Cursor home (19H)?
	JP	Z,CRSHOME
	DEC	A		;Cursor BOL (1AH)?
	JP	Z,CRSBOL
	DEC	A		;Clear to EOL (1BH)?
	JP	Z,CLREOL
	DEC	A		;Clear to EOS (1CH)?
	JP	Z,CLREOF
	XOR	A
	RET

; Set cursor to BOL (Beginning of Line)
CRSBOL	LD	HL,(CURSOR)
	LD	L,0		;Col = 0
	LD	(CURSOR),HL
	CALL	VDC_SETCURSOR
	RET

; Cursor on/off
CRSON	LD	A,20H		;Enable cursor attribute
	JR	CSR_SET
CRSOFF	XOR	A		;Disable cursor
CSR_SET	PUSH	BC
	PUSH	AF
	VDC_SEL	VDC_ATTR
	LD	BC,VDC_DATA
	IN	A,(C)
	POP	HL		;H = new cursor attr
	AND	0DFH		;Clear cursor enable
	OR	H		;Set new state
	OUT	(C),A
	POP	BC
	RET

; Home cursor
CRSHOME	LD	HL,0
	LD	(CURSOR),HL
	CALL	VDC_SETCURSOR
	; Reset to normal video
	XOR	A
	LD	(INVIDEO),A
	RET

; Backspace and erase cursor
BACKSPA	CALL	CRSBKSP
	RET	Z
	LD	C,' '
	JP	PUT_@

; Backspace cursor
CRSBKSP	LD	HL,(CURSOR)
	LD	A,L
	OR	A
	RET	Z		;Already at col 0
	DEC	L
	LD	(CURSOR),HL
	CALL	VDC_SETCURSOR
	RET

; Cursor forward
CRSFRWD	LD	HL,(CURSOR)
	LD	A,L
	CP	VDC_COLS-1
	RET	NC		;At edge
	INC	L
	LD	(CURSOR),HL
	CALL	VDC_SETCURSOR
	RET

; Cursor up
CRSUP	LD	HL,(CURSOR)
	LD	A,H
	OR	A
	RET	Z		;At top
	DEC	H
	LD	(CURSOR),HL
	CALL	VDC_SETCURSOR
	RET

; Cursor down
CRSDOWN	LD	HL,(CURSOR)
	LD	A,H
	CP	VDC_ROWS-1
	JR	Z,DO_SCROLL	;Scroll if at bottom
	INC	H
	LD	(CURSOR),HL
	CALL	VDC_SETCURSOR
	RET

; Linefeed
DOCON1
LINFEED	CALL	CRSBOL		;Move to BOL
	LD	HL,(CURSOR)
	LD	A,H
	CP	VDC_ROWS-1
	JR	Z,DO_SCROLL	;Scroll if at bottom
	INC	H		;Move down
	LD	(CURSOR),HL
	CALL	VDC_SETCURSOR
	RET

; Scroll screen up one line
DO_SCROLL
	PUSH	BC
	PUSH	HL
	PUSH	DE
	; VDC block move: copy lines 1-24 to 0-23
	; Set block copy source = VDC_COLS, destination = 0
	; Block copy count = VDC_COLS * (VDC_ROWS-1)
	; Block copy direction = forward (register 31)
	VDC_SEL	VDC_BLKCOPY
	; Block copy register format:
	; Reg 31: Control (bit 7=1 for copy, bits 0-1 = src addr increment)
	; Reg 32: Source low
	; Reg 33: Source high
	; Reg 34: Dest low
	; Reg 35: Dest high
	; Reg 30: Block length low
	; Reg 31: Block length high (after writing len lo)
	LD	A,0FFH		;Copy operation, no decrement
	LD	BC,VDC_DATA
	OUT	(C),A
	; Source = row 1 = VDC_COLS
	VDC_SEL	32
	LD	A,VDC_COLS&0FFH
	LD	(VDC_DATA),A
	VDC_SEL	33
	XOR	A
	LD	(VDC_DATA),A
	; Dest = row 0 = 0
	VDC_SEL	34
	XOR	A
	LD	(VDC_DATA),A
	VDC_SEL	35
	LD	(VDC_DATA),A
	; Length = VDC_COLS * (VDC_ROWS - 1)
	VDC_SEL	30
	LD	A,VDC_COLS*(VDC_ROWS-1)&0FFH
	LD	(VDC_DATA),A
	VDC_SEL	31
	LD	A,VDC_COLS*(VDC_ROWS-1)/256
	LD	(VDC_DATA),A
	; Clear last line: set update address to start of last row
	LD	HL,VDC_COLS*(VDC_ROWS-1)
	VDC_SEL	VDC_UAHIGH
	LD	A,H
	LD	(VDC_DATA),A
	VDC_SEL	VDC_UALOW
	LD	A,L
	LD	(VDC_DATA),A
	; Fill last line with spaces
	LD	B,VDC_COLS
	XOR	A		;Normal attribute
CLR_LAST
	PUSH	AF
	VDC_SEL	VDC_ATTR
	POP	AF
	LD	(VDC_DATA),A
	LD	A,' '
	VDC_SEL	VDC_UDATA
	LD	(VDC_DATA),A
	DJNZ	CLR_LAST
	POP	DE
	POP	HL
	POP	BC
	RET

; Clear to end of line
CLREOL	PUSH	HL
	PUSH	BC
	LD	HL,(CURSOR)
	CALL	GET_VDC_OFFSET
	; HL = offset in VDC VRAM
	LD	A,VDC_COLS
	SUB	L		;A = chars remaining on line
	LD	B,A
	; Position VDC write addr
	PUSH	HL
	VDC_SEL	VDC_UAHIGH
	LD	A,H
	LD	(VDC_DATA),A
	VDC_SEL	VDC_UALOW
	LD	A,L
	LD	(VDC_DATA),A
	POP	HL
	LD	A,' '		;Space
CLREOL1
	VDC_SEL	VDC_UDATA
	LD	(VDC_DATA),A
	DJNZ	CLREOL1
	POP	BC
	POP	HL
	RET

; Clear to end of screen
CLREOF	PUSH	HL
	PUSH	BC
	LD	HL,(CURSOR)
	CALL	GET_VDC_OFFSET
	; HL = offset in VDC VRAM
	PUSH	HL
	VDC_SEL	VDC_UAHIGH
	LD	A,H
	LD	(VDC_DATA),A
	VDC_SEL	VDC_UALOW
	LD	A,L
	LD	(VDC_DATA),A
	POP	HL
	; Calculate remaining chars
	PUSH	HL
	LD	HL,VDC_CRTSIZE
	POP	DE
	OR	A
	SBC	HL,DE
	LD	B,H
	LD	C,L
	LD	A,' '
CLREOF1
	VDC_SEL	VDC_UDATA
	LD	(VDC_DATA),A
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,CLREOF1
	POP	BC
	POP	HL
	RET

; Reverse video enable/disable
DO_INVERT_ENA
	LD	A,80H
	LD	(INVIDEO),A
	RET
DO_INVERT_OFF
	XOR	A
	LD	(INVIDEO),A
	RET

; Toggle control character display
TGGLCTL	LD	A,10H
	XOR	(IX+DO_MASK)
	LD	(IX+DO_MASK),A
	RET

; Toggle tab/alternate mode
TGGLTAB	LD	A,8
	XOR	(IX+DO_MASK)
	LD	(IX+DO_MASK),A
	RET

; Toggle alternate character set
TGGLALT	LD	A,1		;Toggle alt charset in VDC
	VDC_SEL	VDC_ATTR
	LD	BC,VDC_DATA
	IN	A,(C)
	XOR	1
	OUT	(C),A
	RET

; Set 40 column mode (VDC always 80 cols, but we can simulate)
SET40	; VDC is always 80 columns; ignore 40-col request
	RET

;==============================================================================
; GET request at cursor position
;==============================================================================
$?0_GET
	; Read character at current cursor position from VDC VRAM
	LD	HL,(CURSOR)
	CALL	GET_VDC_OFFSET
	; Set VDC read address
	VDC_SEL	VDC_UAHIGH
	LD	BC,VDC_DATA
	OUT	(C),H
	VDC_SEL	VDC_UALOW
	LD	A,L
	LD	(VDC_DATA),A
	; Read character from current address (auto-increment)
	VDC_SEL	VDC_UDATA
	LD	A,(VDC_DATA)		;Read char data
	LD	C,A
	CP	A		;Set Z flag
	RET

;==============================================================================
; Display a character at current cursor position
;==============================================================================
DO_DSPCHAR
	LD	A,C		;Get character
	PUSH	AF
	; Position VDC cursor
	LD	HL,(CURSOR)
	CALL	GET_VDC_OFFSET
	; Set VDC write address
	VDC_SEL	VDC_UAHIGH
	LD	A,H
	LD	(VDC_DATA),A
	VDC_SEL	VDC_UALOW
	LD	A,L
	LD	(VDC_DATA),A
	; Write attribute (normal or reverse)
	VDC_SEL	VDC_ATTR
	LD	A,(INVIDEO)
	LD	(VDC_DATA),A
	; Write character
	VDC_SEL	VDC_UDATA
	POP	AF
	LD	(VDC_DATA),A
	; Advance cursor
	LD	HL,(CURSOR)
	INC	L
	LD	A,L
	CP	VDC_COLS
	JR	C,$?1
	; Wrap to next line
	LD	L,0
	INC	H
	LD	A,H
	CP	VDC_ROWS
	JR	C,$?1
	DEC	H		;Stay on last row, will scroll
	CALL	DO_SCROLL
$?1	LD	(CURSOR),HL
	RET

;==============================================================================
; Calculate VDC VRAM offset from (row, col)
; Input: H = row, L = col
; Output: HL = offset into VDC VRAM
;==============================================================================
GET_VDC_OFFSET
	PUSH	BC
	PUSH	DE
	LD	D,H		;Save row
	LD	E,L		;Save col
	LD	H,0
	LD	L,D		;HL = row
	ADD	HL,HL		;*2
	ADD	HL,HL		;*4
	ADD	HL,HL		;*8
	ADD	HL,HL		;*16
	ADD	HL,HL		;*32
	ADD	HL,HL		;*64
	LD	A,VDC_COLS-64
	ADD	HL,HL		;*128
	ADD	HL,HL		;*256
	; Now HL = row * 256
	; We need row * 80 = row * 64 + row * 16
	; HL = row * 64 after the shifts above
	; Load row into B, add row*16
	PUSH	HL
	LD	L,D
	LD	H,0
	ADD	HL,HL		;*2
	ADD	HL,HL		;*4
	ADD	HL,HL		;*8
	ADD	HL,HL		;*16
	POP	DE
	ADD	HL,DE		;HL = row*80
	LD	D,0
	LD	A,E		;col
	ADD	A,L
	LD	L,A
	ADC	A,H
	SUB	L
	LD	H,A
	POP	DE
	POP	BC
	RET

;==============================================================================
; @VDCTL SVC Handler (video control functions)
;==============================================================================
@_VDCTL
	LD	A,9		;Check for VIDLINE (function 9)
	CP	B
	JR	Z,VIDLIN
	LD	A,43		;Prepare for error
	DEC	B
	JR	Z,GET_@_ROWCOL	;Function 1: Get char at row,col
	DEC	B
	JR	Z,PUT_@_ROWCOL	;Function 2: Put char at row,col
	DEC	B
	JR	Z,@VDCTL3	;Function 3: Set cursor to H,L
	DEC	B
	JR	Z,ADDR_2_ROWCOL ;Function 4: Get cursor row,col
	DEC	B
	JR	Z,VIDMOV1	;Function 5: User RAM to video
	DEC	B
	JR	Z,VIDMOVE	;Function 6: Video to user RAM
	DEC	B
	JP	Z,SET_SCROLL	;Function 7: Set scroll protect
	DEC	B
	RET	NZ		;Function 8: Set cursor char
	PUSH	HL
	LD	HL,CRSCHAR
	LD	A,(HL)
	LD	(HL),C
	POP	HL
	RET

; Set cursor position from (H,L)
@VDCTL3	LD	(CURSOR),HL
	CALL	VDC_SETCURSOR
	RET

; Put character at row,col (H=row, L=col, C=char)
PUT_@_ROWCOL
	PUSH	HL
	PUSH	BC
	LD	(CURSOR),HL	;Set cursor temporarily
	CALL	GET_VDC_OFFSET	;HL = VDC offset
	VDC_SEL	VDC_UAHIGH
	LD	BC,VDC_DATA
	OUT	(C),H
	VDC_SEL	VDC_UALOW
	LD	A,L
	LD	(VDC_DATA),A
	VDC_SEL	VDC_ATTR
	LD	A,(INVIDEO)
	LD	(VDC_DATA),A
	POP	BC
	VDC_SEL	VDC_UDATA
	LD	A,C
	LD	(VDC_DATA),A
	POP	HL
	RET

; Get character at row,col (H=row, L=col)
GET_@_ROWCOL
	PUSH	HL
	CALL	GET_VDC_OFFSET
	VDC_SEL	VDC_UAHIGH
	LD	BC,VDC_DATA
	OUT	(C),H
	VDC_SEL	VDC_UALOW
	LD	A,L
	LD	(VDC_DATA),A
	VDC_SEL	VDC_UDATA
	LD	A,(VDC_DATA)		;Read character
	LD	C,A
	POP	HL
	CP	A		;Set Z flag
	RET

; Get cursor position as row,col
ADDR_2_ROWCOL
	LD	HL,(CURSOR)
	RET

; Put character at cursor
PUT_@
	PUSH	BC
	LD	A,C
	LD	C,A
	CALL	DO_DSPCHAR
	POP	BC
	RET

; VIDLIN: Move a line between video and user buffer
VIDLIN	LD	L,0		;Always start at col 0
	PUSH	DE		;Save user buffer
	CALL	GET_VDC_OFFSET	;Get VDC offset for start of row
	POP	HL		;Recover user buffer
	RET	NZ
	INC	C		;Check direction
	DEC	C
	JR	Z,MOVLIN	;To screen
	EX	DE,HL		;Reverse direction
MOVLIN	LD	BC,VDC_COLS
	LDIR			;Use LDIR for block copy (works on Z80)
	XOR	A
	RET

; Video RAM to/from user buffer
VIDMOVE	LD	A,H		;Check user buffer is valid
	ADD	A,8
	CP	24H+8
	JR	C,PERR
	EX	DE,HL
VIDMOV1	LD	BC,VDC_CRTSIZE
	LDIR
	CP	A
	RET

; Set scroll protect
SET_SCROLL
	LD	A,C
	AND	7
	LD	C,A
	LD	A,(DODATA$)
	AND	0F8H
	OR	C
	LD	(DODATA$),A
	XOR	A
	RET

; Error - parameter error
PERR	LD	A,43
	OR	A
	RET

DOEND	EQU	$-1

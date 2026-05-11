;****************************************************************
;* Filename: C128_BOOT.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* Commodore 128 Bootstrap Loader for LSDOS 6.3.1L Port		*
;****************************************************************
;*								*
;* Replaces BOOT4/ASM. Loads LSDOS from a C128 disk (IEC serial)*
;* into memory. The boot code is loaded by the C128 boot menu	*
;* or by a 6502/Z80 co-boot process.				*
;*								*
;* The C128 can boot into Z80 mode via a special boot sector	*
;* on the disk that the 6502 KERNAL loads and transfers to Z80.	*
;*								*
;****************************************************************
	; SUBTTL (converted)
	; PAGE (converted)


;==============================================================================
; Boot Constants
;==============================================================================
KEYIN	EQU	40H
NMIVECT	EQU	66H
BUFFER	EQU	1200H
BOOTBUF	EQU	43FFH-9

;==============================================================================
; IEC Register Definitions (for boot loader use)
;==============================================================================
IEC_PRA		EQU	CIA2_PRA
IEC_DDRA	EQU	CIA2_DDRA
IEC_PRB		EQU	CIA2_PRB
IEC_DDRB	EQU	CIA2_DDRB

;==============================================================================
; Boot Loader Entry Point
; Called from 6502-side bootstrap or from Z80 start.
; Loads the first 16K of LSDOS (LOWCORE + drivers + SYSRES).
;==============================================================================
LBOOT
	LD	IY,DCT_S		;Set IY for FDCDVR use
	LD	A,(IY+9)	;Directory track
	LD	(IY+5),A	;Current track
	LD	A,4
	LD	(FLGTAB_S+'R'-'A'),A	;Set retries
	LD	A,0C9H
	LD	(FDDINT_S),A	;RET for disk interrupt
	LD	A,18		;Sectors/track, DD
	BIT	5,(IY+4)	;Double-sided?
	JR	Z,NOTDBL
	ADD	A,A		;36 sectors/cyl
NOTDBL	LD	(SECTRK),A

	EXX
	LD	C,6		;Sectors/gran
	CALL	GETEXT		;Pick up extent 1
	EXX

	CALL	LOAD		;Read SYSRES
	LD	A,0FBH		;EI instruction
	LD	(DISKEI),A	;Stuff into FDCDVR
	JP	(HL)		;Go to SYSRES init

;==============================================================================
; CIM File Loader (same as TRS-80)
;==============================================================================
LOAD	CALL	RDBYTE		;Get type code
	DEC	A
	JR	NZ,LOAD2	;Bypass if not type 1
	CALL	GETADR		;Block len & load addr
LOAD1	CALL	RDBYTE		;Read byte
	LD	(HL),A		;Stuff to memory
	INC	HL
	DJNZ	LOAD1
	JR	LOAD

LOAD2	DEC	A		;Type 2 (transfer addr)?
	JR	Z,GETADR
	CALL	RDBYTE		;Comment - get length
	LD	B,A
LOAD3	CALL	RDBYTE
	DJNZ	LOAD3
	JR	LOAD

GETADR	CALL	RDBYTE		;Block length
	LD	B,A
	CALL	RDBYTE		;Low-order load addr
	LD	L,A
	DEC	B
	CALL	RDBYTE		;High-order load addr
	LD	H,A
	DEC	B
	RET

;==============================================================================
; Byte Reader - reads from disk via IEC serial
;==============================================================================
RDBYTE	EXX
	INC	L
	JR	NZ,RDB2		;More bytes in buffer?
	PUSH	BC
	LD	B,9		;Read sector function
	CALL	DCT_S
	POP	BC
	INC	E
	LD	A,E
	SUB	$-$		;Last sector on cylinder?
SECTRK	EQU	$-1
	JR	NZ,RDB1
	LD	E,A		;Restart at sector 0
	INC	D		;Bump track
RDB1	DEC	B		;Dec sectors this extent
	CALL	Z,GETEXT	;Get next extent if 0
RDB2	LD	A,(HL)		;Pick up byte
	EXX
	RET

GETEXT
	INC	IX
	INC	IX
	LD	A,(IX)
	PUSH	AF
	RLCA
	RLCA
	RLCA
	AND	7
	CALL	MULTCA
	LD	E,A
	POP	AF
	AND	00011111B
	INC	A
	CALL	MULTCA
	LD	B,A
	LD	D,(IX-1)
	RET

MULTCA	PUSH	BC
	LD	D,A
	XOR	A
	LD	B,8
MLTCA	ADD	A,A
	SLA	C
	JR	NC,MLTCA1
	ADD	A,D
MLTCA1	DJNZ	MLTCA
	POP	BC
	RET

;==============================================================================
; System Boot Entry Point (called from 6502-side bootstrap)
;==============================================================================
	ORG	4300H

BOOT	NOP
	CP	14H		;Directory track
DIRTRK	EQU	$-1
	DI

;----------------------------------------------------------------------
; Initialize C128 hardware for LSDOS boot
;----------------------------------------------------------------------
	; Initialize MMU - map in all RAM from block 0
	XOR	A
	LD	(MMU_RAM0),A
	LD	(MMU_RAM1),A
	LD	(MMU_RAM2),A
	LD	(MMU_RAM3),A
	LD	A,MMU_CFG_0
	LD	(MMU_LOAD),A

	; Initialize CIA #2 for IEC bus
	LD	A,0FFH
	LD	(IEC_DDRA),A
	LD	(IEC_DDRB),A
	LD	(IEC_PRA),A
	LD	(IEC_PRB),A

	; Initialize VDC for 80x25 display
	; (Minimal init - full init done in SYSINIT)
	VDC_SET	VDC_HTOTAL,	126
	VDC_SET	VDC_HDISP,	80
	VDC_SET	VDC_HSYNC,	98
	VDC_SET	VDC_VTOTAL,	33
	VDC_SET	VDC_VADJ,	18
	VDC_SET	VDC_VDISP,	25
	VDC_SET	VDC_VSYNC,	34
	VDC_SET	VDC_ROWSCAN,	7
	VDC_SET	VDC_CURSTART,	6
	VDC_SET	VDC_CUREND,	7
	VDC_SET	VDC_SAHIGH,	0
	VDC_SET	VDC_SALOW,	0
	VDC_SET	VDC_CHRCOUNT,	80
	VDC_SET	VDC_MEMREFR,	19
	VDC_SET	VDC_ATTR,	20H	;Cursor on

	; Clear VDC display (fill with spaces)
	VDC_SEL	VDC_SAHIGH
	XOR	A
	LD	(VDC_DATA),A
	VDC_SEL	VDC_SALOW
	XOR	A
	LD	(VDC_DATA),A
	LD	HL,VDC_CRTSIZE
	LD	A,' '
_L_CLRSCR_206
	VDC_SEL	VDC_SALOW
	LD	(VDC_DATA),A
	DEC	HL
	LD	A,H
	OR	L
	JR	NZ,_L_CLRSCR_206

	; Set up NMI vector for disk I/O completion
	LD	HL,NMIRET
	LD	(NMIVECT+1),HL
	LD	A,0C3H
	LD	(NMIVECT),A
	LD	A,0C9H		;RET instruction for interrupt
	LD	(38H),A

	; Enable CIA #1 NMI for TOD (tick)
	LD	A,CIA_IRQ_TOD!CIA_IRQ_NMI
	LD	(CIA1_ICR),A

;----------------------------------------------------------------------
; Read the first 16 sectors of track 0
;----------------------------------------------------------------------
	LD	HL,START_S+200H	;Page 2
	LD	D,L		;Track 0
	LD	E,L		;Sector 0
RDBOOT
	; Read a sector via IEC (using simple U1 command)
	PUSH	HL
	PUSH	DE
	LD	HL,CMDBUF_BOOT
	LD	(HL),'U'
	INC	HL
	LD	(HL),'1'
	INC	HL
	LD	(HL),':'
	INC	HL
	LD	(HL),0		;Drive 0
	INC	HL
	LD	(HL),0		;Drive number
	INC	HL
	LD	A,D
	INC	A		;1-based track
	LD	(HL),A
	INC	HL
	LD	A,E
	INC	A		;1-based sector
	LD	(HL),A
	INC	HL
	LD	(HL),0		;Terminator

	; Send command: LISTEN 8, secondary 15
	LD	A,8!IEC_LISTEN
	LD	(IEC_PRA),A
	LD	A,8!IEC_LISTEN
	; ATN on
	LD	A,(IEC_PRA)
	AND	0FFH-IEC_ATN
	LD	(IEC_PRA),A
	NOP
	LD	A,8!IEC_LISTEN
	CALL	BOOT_BYTE_OUT
	LD	A,0FH		;Secondary 15 = command
	CALL	BOOT_BYTE_OUT
	; ATN off
	LD	A,(IEC_PRA)
	OR	IEC_ATN
	LD	(IEC_PRA),A
	; Send command string
	LD	HL,CMDBUF_BOOT
	LD	B,6
_L_CMD_277	LD	A,(HL)
	CALL	BOOT_BYTE_OUT
	INC	HL
	DJNZ	_L_CMD_277
	; UNLISTEN
	LD	A,3FH
	CALL	BOOT_BYTE_OUT

	; Read data: TALK 8, secondary 0
	LD	A,8!IEC_TALK
	CALL	BOOT_BYTE_OUT
	LD	A,060H		;Secondary 0 with TALK
	CALL	BOOT_BYTE_OUT
	; ATN off
	LD	A,(IEC_PRA)
	OR	IEC_ATN
	LD	(IEC_PRA),A

	; Read 256 bytes
	POP	DE
	POP	HL
	PUSH	HL
	PUSH	DE
	LD	B,0		;256 bytes
_L_RD_301	CALL	BOOT_BYTE_IN
	LD	(HL),A
	INC	HL
	DJNZ	_L_RD_301
	; UNTALK
	LD	A,5FH
	CALL	BOOT_BYTE_OUT

	POP	DE
	POP	HL
	INC	H		;Next page
	INC	E		;Next sector
	LD	A,16
	CP	E
	JR	NZ,RDBOOT

;----------------------------------------------------------------------
; Load SYSRES
;----------------------------------------------------------------------
	LD	A,(DIRTRK)
	LD	(DCT_S+9),A
	LD	D,A
	LD	E,0
	CALL	RDSECT		;Read GAT into BUFFER

	; Update DCT from GAT
	LD	A,(BUFFER+0CDH)
	AND	20H
	LD	HL,DCT_S+4
	OR	(HL)
	LD	(HL),A

	LD	E,4		;Point to SYS0 dir sector
	CALL	RDSECT
	LD	A,(BUFFER)
	AND	10H
	JR	Z,NOTSYS

	LD	HL,BUFFER+21+8	;SYS0 extent info
	LD	DE,BOOTBUF
	LD	BC,8
	LDDR
	PUSH	DE
	POP	IX
	EXX
	LD	HL,BUFFER+255
	EXX
	JP	LBOOT

	DB	0,0

;==============================================================================
; IEC Boot Byte I/O Routines
;==============================================================================
BOOT_BYTE_OUT
	PUSH	BC
	PUSH	HL
	LD	B,8
	LD	H,A
_L_BITO_360	LD	A,H
	RRA
	LD	A,0
	JR	C,_L_ONE_369
	; Bit 0 - pull DATA low
	LD	A,(IEC_PRA)
	AND	0FFH-IEC_DATA
	LD	(IEC_PRA),A
	JR	_L_CLK_373
_L_ONE_369	; Bit 1 - DATA high
	LD	A,(IEC_PRA)
	OR	IEC_DATA
	LD	(IEC_PRA),A
_L_CLK_373	; Pulse CLOCK low
	LD	A,(IEC_PRA)
	AND	0FFH-IEC_CLK
	LD	(IEC_PRA),A
	; Pulse CLOCK high
	LD	A,(IEC_PRA)
	OR	IEC_CLK
	LD	(IEC_PRA),A
	RR	H
	DJNZ	_L_BITO_360
	; Release DATA
	LD	A,(IEC_PRA)
	OR	IEC_DATA
	LD	(IEC_PRA),A
	POP	HL
	POP	BC
	RET

BOOT_BYTE_IN
	PUSH	BC
	PUSH	HL
	LD	H,0
	; DATA = input
	LD	A,(IEC_DDRA)
	AND	0FFH-IEC_DATA
	LD	(IEC_DDRA),A
	; DATA high
	LD	A,(IEC_PRA)
	OR	IEC_DATA
	LD	(IEC_PRA),A
	LD	B,8
_L_BITI_404	; Wait for CLOCK low
_L_WAIT_405	LD	A,(IEC_PRA)
	BIT	4,A
	JR	NZ,_L_WAIT_405
	; Read DATA_IN
	LD	A,(IEC_PRA)
	AND	IEC_DATA_IN
	JR	Z,_L_Z_414
	SET	7,H
	JR	_L_NX_415
_L_Z_414	RES	7,H
_L_NX_415	; CLOCK high
	LD	A,(IEC_PRA)
	OR	IEC_CLK
	LD	(IEC_PRA),A
	; Wait for CLOCK high
_L_WAIT2_420	LD	A,(IEC_PRA)
	BIT	4,A
	JR	Z,_L_WAIT2_420
	RR	H
	DJNZ	_L_BITI_404
	; Restore DATA as output
	LD	A,(IEC_DDRA)
	OR	IEC_DATA
	LD	(IEC_DDRA),A
	LD	A,H
	POP	HL
	POP	BC
	RET

;==============================================================================
; Sector Read for Boot
;==============================================================================
RDSECT	LD	HL,BUFFER
RDSEQ	LD	B,5		;Retry count
RDS1	PUSH	BC
	PUSH	HL
	CALL	IEC_READ_BOOT_SECTOR
	POP	HL
	POP	BC
	AND	1CH
	RET	Z
	DJNZ	RDS1
	; Error - display message and halt
	LD	HL,DISKERR
	JR	DISPERR

NOTSYS	LD	HL,NOSYS
DISPERR	LD	BC,ERRLEN
	LD	DE,CRTBGN_S+80*12+35	;Middle of screen
	; Copy error message to VDC display
	; For boot errors, we write to a temp buffer
	PUSH	HL
	PUSH	BC
	VDC_SEL	VDC_SAHIGH
	LD	A,D
	AND	0FCH
	RRA
	RRA
	LD	(VDC_DATA),A
	VDC_SEL	VDC_SALOW
	; Calculate offset in VDC VRAM
	LD	A,12*80+35
	LD	(VDC_DATA),A
	POP	BC
	POP	HL
_L_ERRDIS_470	LD	A,(HL)
	VDC_SEL	VDC_SALOW
	LD	(VDC_DATA),A
	INC	HL
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,_L_ERRDIS_470

HALTS	JR	HALTS		;Halt until reset

;==============================================================================
; IEC boot sector read
;==============================================================================
IEC_READ_BOOT_SECTOR
	; Send command: LISTEN 8, secondary 15
	LD	A,8!IEC_LISTEN
	CALL	BOOT_BYTE_OUT
	LD	A,0FH		;Secondary 15 (command)
	CALL	BOOT_BYTE_OUT
	; Build U1 command in temp buffer
	LD	HL,CMDBUF_BOOT
	LD	(HL),'U'
	INC	HL
	LD	(HL),'1'
	INC	HL
	LD	(HL),':'
	INC	HL
	LD	(HL),0
	INC	HL
	LD	A,C		;Drive number
	LD	(HL),A
	INC	HL
	LD	A,D		;Track
	INC	A		;1-based
	LD	(HL),A
	INC	HL
	LD	A,E		;Sector
	INC	A		;1-based
	LD	(HL),A
	INC	HL
	LD	(HL),0
	; Send command string
	LD	HL,CMDBUF_BOOT
	LD	B,6
_L_SEND_515	LD	A,(HL)
	CALL	BOOT_BYTE_OUT
	INC	HL
	DJNZ	_L_SEND_515
	; UNLISTEN
	LD	A,3FH
	CALL	BOOT_BYTE_OUT
	; Now TALK 8, secondary 0
	LD	A,8!IEC_TALK
	CALL	BOOT_BYTE_OUT
	LD	A,060H		;Secondary 0
	CALL	BOOT_BYTE_OUT
	; Read 256 bytes
	LD	B,0
_L_READ_529	PUSH	BC
	CALL	BOOT_BYTE_IN
	POP	BC
	LD	(HL),A
	INC	HL
	DJNZ	_L_READ_529
	; UNTALK
	LD	A,5FH
	CALL	BOOT_BYTE_OUT
	XOR	A		;Success
	RET

;==============================================================================
; Boot Data
;==============================================================================
CMDBUF_BOOT	DS	16	;Command buffer

DISKERR	DB	'Disk error'
NOSYS	DB	'No system '
ERRLEN	EQU	$-NOSYS
	DC	-$&0FFH,0
	ORG	$		; Keep PC (CORE_S forward ref not available in vasm)

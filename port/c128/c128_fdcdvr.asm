;****************************************************************
;* Filename: C128_FDCDVR.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* Commodore 128 IEC Serial Floppy Driver for LSDOS 6.3.1L Port	*
;****************************************************************
;*								*
;* Replaces FDCDVR/ASM. Instead of a WD1793 FDC at ports		*
;* $F0-$F4, the C128 uses the IEC serial bus via CIA #2.		*
;* Drives (1571/1581) have their own onboard controller. The	*
;* protocol is a byte-serial, handshaked bus with talk/listen.	*
;*								*
;* This driver implements the LSDOS disk primitive mapping:	*
;*   B=1: Select drive					*
;*   B=2: Step in (not used on IEC)			*
;*   B=3: Restore						*
;*   B=4: Step in (FDC) -> IEC seek			*
;*   B=6: Seek track					*
;*   B=7: Test busy (FDC) -> check status		*
;*   B=8..15: I/O requests (read, write, verify)		*
;*								*
;****************************************************************
	SUBTTL	'<C128 IEC Floppy Disk Driver>'
	PAGE


;==============================================================================
; IEC Bus Timing Constants (approximate C128 Z80 timing)
;==============================================================================
IEC_DELAY	EQU	50
IEC_TIMEOUT	EQU	10000

; Burst mode constants
BURST_SECTORS	EQU	256		;Standard sector size for burst
BURST_RETRY	EQU	3		;Burst retries before fallback
BURST_1571	EQU	01H		;Burst flag: 1571 native mode
BURST_ACTIVE	EQU	02H		;Burst flag: burst mode enabled

;==============================================================================
; Internal Drive Data Table (per drive, 10 bytes per entry = DCT)
;==============================================================================
; Each DCT entry is 10 bytes:
;   +0: JP FDCDVR  (driver entry jump)
;   +1: 
;   +2: 
;   +3: Drive flags byte (SDEN/DDEN, side select, step rate)
;   +4: Drive select code (IEC device address)
;   +5: Current track/cylinder
;   +6: Reserved
;   +7: Allocation info (sectors/track, sectors/gran)
;   +8: More allocation info
;   +9: Directory track

;==============================================================================
; IEC Bus Low-Level Routines
;==============================================================================

; Set IEC lines to idle state
IEC_IDLE
	PUSH	AF
	PUSH	BC
	LD	A,0FFH		;All lines high (released)
	LD	BC,CIA2_DDRA
	OUT	(C),A		;Port A = output
	LD	BC,CIA2_DDRB
	OUT	(C),A		;Port B = output
	LD	A,0FFH		;All lines high = released
	LD	BC,CIA2_PRA
	OUT	(C),A
	LD	BC,CIA2_PRB
	OUT	(C),A
	POP	BC
	POP	AF
	RET

; Set ATN line low (begin transaction)
IEC_ATN_ON
	PUSH	AF
	PUSH	BC
	LD	BC,CIA2_PRA
	IN	A,(C)
	AND	0FFH-IEC_ATN	;Clear ATN bit
	OUT	(C),A
	POP	BC
	POP	AF
	RET

; Release ATN line (end transaction)
IEC_ATN_OFF
	PUSH	AF
	PUSH	BC
	LD	BC,CIA2_PRA
	IN	A,(C)
	OR	IEC_ATN		;Set ATN bit
	OUT	(C),A
	POP	BC
	POP	AF
	RET

; Send one byte over IEC bus (handshaked)
; A = byte to send
IEC_BYTE_OUT
	PUSH	BC
	PUSH	HL
	PUSH	DE
	LD	D,8		;8 bits
	LD	H,A		;Save byte
$?BIT	RR	H		;Get LSB into carry
	JR	C,$?ONE
	; Send 0 bit: pull DATA low
	LD	BC,CIA2_PRA
	IN	A,(C)
	AND	0FFH-IEC_DATOUT	;DATA low
	OUT	(C),A
	JR	$?CLOCK
$?ONE
	; Send 1 bit: release DATA high
	LD	BC,CIA2_PRA
	IN	A,(C)
	OR	IEC_DATOUT	;DATA high
	OUT	(C),A
$?CLOCK
	; Pulse CLOCK low then high
	LD	BC,CIA2_PRA
	IN	A,(C)
	AND	0FFH-IEC_CLK	;CLOCK low
	OUT	(C),A
	; Small delay
	PUSH	DE
	LD	E,IEC_DELAY
$?DLY1	DEC	E
	JR	NZ,$?DLY1
	POP	DE
	; Clock high
	LD	BC,CIA2_PRA
	IN	A,(C)
	OR	IEC_CLK		;CLOCK high
	OUT	(C),A
	DEC	D
	JR	NZ,$?BIT
	; Release DATA for turn-around
	LD	BC,CIA2_PRA
	IN	A,(C)
	OR	IEC_DATOUT
	OUT	(C),A
	POP	DE
	POP	HL
	POP	BC
	RET

; Receive one byte from IEC bus (handshaked)
; Returns: A = byte received
IEC_BYTE_IN
	PUSH	BC
	PUSH	HL
	PUSH	DE
	LD	D,8
	LD	H,0
	; Set DATA line as input
	LD	BC,CIA2_DDRA
	IN	A,(C)
	AND	0FFH-IEC_DATOUT	;DATA = input
	OUT	(C),A
	; Release DATA high
	LD	BC,CIA2_PRA
	IN	A,(C)
	OR	IEC_DATOUT
	OUT	(C),A
$?BIT
	; Wait for CLOCK low (drive signals)
$?WAIT
	LD	BC,CIA2_PRA
	IN	A,(C)
	BIT	4,A		;Check CLOCK_IN
	JR	NZ,$?WAIT	;Wait for low
	; Read DATA bit
	IN	A,(C)
	AND	IEC_DATOUT_IN	;Get DATA_IN bit
	JR	Z,$?ZERO
	SET	7,H		;Bit = 1
	JR	$?NEXT
$?ZERO
	RES	7,H		;Bit = 0
$?NEXT
	; Acknowledge: set CLOCK high
	IN	A,(C)
	OR	IEC_CLK
	OUT	(C),A
	; Wait for CLOCK high from drive
$?WAIT2
	IN	A,(C)
	BIT	4,A
	JR	Z,$?WAIT2	;Wait for high
	; Shift
	RR	H
	DEC	D
	JR	NZ,$?BIT
	; Restore DATA as output
	LD	BC,CIA2_DDRA
	IN	A,(C)
	OR	IEC_DATOUT
	OUT	(C),A
	LD	A,H
	POP	DE
	POP	HL
	POP	BC
	RET

;==============================================================================
; Burst Mode Byte I/O (fast, no software delays)
;==============================================================================
BURST_BYTE_OUT
	PUSH	BC
	PUSH	HL
	PUSH	DE
	LD	D,8
	LD	H,A
$?BITO	RR	H
	JR	C,$?ONE
	LD	BC,CIA2_PRA
	IN	A,(C)
	AND	0FFH-IEC_DATOUT
	OUT	(C),A
	JR	$?CLK
$?ONE	LD	BC,CIA2_PRA
	IN	A,(C)
	OR	IEC_DATOUT
	OUT	(C),A
$?CLK	LD	BC,CIA2_PRA
	IN	A,(C)
	AND	0FFH-IEC_CLK
	OUT	(C),A
	IN	A,(C)
	OR	IEC_CLK
	OUT	(C),A
	DEC	D
	JR	NZ,$?BITO
	LD	BC,CIA2_PRA
	IN	A,(C)
	OR	IEC_DATOUT
	OUT	(C),A
	POP	DE
	POP	HL
	POP	BC
	RET

BURST_BYTE_IN
	PUSH	BC
	PUSH	HL
	PUSH	DE
	LD	D,8
	LD	H,0
	LD	BC,CIA2_DDRA
	IN	A,(C)
	AND	0FFH-IEC_DATOUT
	OUT	(C),A
	LD	BC,CIA2_PRA
	IN	A,(C)
	OR	IEC_DATOUT
	OUT	(C),A
$?BITI	IN	A,(C)
	BIT	4,A
	JR	NZ,$?BITI
	IN	A,(C)
	AND	IEC_DATA_IN
	JR	Z,$?ZERO
	SET	7,H
	JR	$?NEXT
$?ZERO	RES	7,H
$?NEXT	IN	A,(C)
	OR	IEC_CLK
	OUT	(C),A
$?WAIT	IN	A,(C)
	BIT	4,A
	JR	NZ,$?WAIT
	RR	H
	DEC	D
	JR	NZ,$?BITI
	LD	BC,CIA2_DDRA
	IN	A,(C)
	OR	IEC_DATOUT
	OUT	(C),A
	LD	A,H
	POP	DE
	POP	HL
	POP	BC
	RET

;==============================================================================
; IEC Bus Protocol Commands
;==============================================================================

; Send LISTEN to device
; A = device address
IEC_LISTEN_CMD
	PUSH	AF
	OR	IEC_LISTEN
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF	;ATN released after address
	POP	AF
	RET

; Send TALK to device
; A = device address
IEC_TALK_CMD
	PUSH	AF
	OR	IEC_TALK
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF
	POP	AF
	RET

; Send secondary address (channel)
; A = channel number
IEC_SECONDARY
	PUSH	AF
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF
	POP	AF
	RET

; Send UNLISTEN
IEC_DO_UNLISTEN
	LD	A,IEC_UNLISTEN
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF
	RET

; Send UNTALK
IEC_DO_UNTALK
	LD	A,IEC_UNTALK
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF
	RET

; Send a command string to device
; HL -> command string, B = length
IEC_COMMAND
	PUSH	AF
	; Send LISTEN, device 8 (or stored device), secondary 15 (command)
	LD	A,(PDRV$)
	OR	IEC_LISTEN
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	LD	A,0FH		;Secondary address 15 = command
	OR	IEC_LISTEN
	CALL	IEC_BYTE_OUT
	; Send command bytes
$?SEND	LD	A,(HL)
	CALL	IEC_BYTE_OUT
	INC	HL
	DJNZ	$?SEND
	; Send UNLISTEN
	LD	A,IEC_UNLISTEN
	CALL	IEC_BYTE_OUT
	POP	AF
	RET

;==============================================================================
; Read a sector from IEC disk
; Input:  HL -> buffer address, D = track, E = sector, C = drive
; Output: A = 0 on success, error code on failure
;==============================================================================
IEC_READ_SECTOR
	PUSH	HL
	PUSH	DE
	PUSH	BC

	; Save buffer address
	LD	(SECBUF_SAV),HL

	; Build command: "U1:0 <drive> <track_1based> <sector_1based>"
	LD	HL,CMDBUF
	LD	(HL),'U'
	INC	HL
	LD	(HL),'1'
	INC	HL
	LD	(HL),':'
	INC	HL
	LD	(HL),0		;Drive number
	INC	HL
	LD	(HL),C		;Drive
	INC	HL
	LD	A,D		;Track
	INC	A		;1-based
	LD	(HL),A
	INC	HL
	LD	A,E		;Sector
	INC	A		;1-based
	LD	(HL),A
	INC	HL
	LD	(HL),0		;Terminator
	LD	B,6
	LD	HL,CMDBUF
	CALL	IEC_COMMAND

	; TALK device, secondary 0
	LD	A,(PDRV$)
	OR	IEC_TALK
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	LD	A,060H		;Secondary 0
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF

	; Read 256 bytes into buffer
	LD	HL,(SECBUF_SAV)
	LD	B,0		;256 bytes
$?READ	PUSH	BC
	CALL	IEC_BYTE_IN
	POP	BC
	LD	(HL),A
	INC	HL
	DJNZ	$?READ

	; UNTALK
	CALL	IEC_DO_UNTALK

	XOR	A		;Success
	POP	BC
	POP	DE
	POP	HL
	RET

;==============================================================================
; Write a sector to IEC disk
; Input:  HL -> buffer, D = track, E = sector, C = drive
; Output: A = 0 on success, error code on failure
;==============================================================================
IEC_WRITE_SECTOR
	PUSH	HL
	PUSH	DE
	PUSH	BC

	; Save buffer address
	LD	(SECBUF_SAV),HL

	; Build command: "U2:0 <drive> <track_1based> <sector_1based>"
	LD	HL,CMDBUF
	LD	(HL),'U'
	INC	HL
	LD	(HL),'2'
	INC	HL
	LD	(HL),':'
	INC	HL
	LD	(HL),0
	INC	HL
	LD	(HL),C		;Drive
	INC	HL
	LD	A,D
	INC	A		;1-based track
	LD	(HL),A
	INC	HL
	LD	A,E
	INC	A		;1-based sector
	LD	(HL),A
	INC	HL
	LD	(HL),0
	LD	B,6
	LD	HL,CMDBUF
	CALL	IEC_COMMAND

	; LISTEN device, secondary 0
	LD	A,(PDRV$)
	OR	IEC_LISTEN
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	LD	A,060H		;Secondary 0
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF

	; Send 256 bytes from buffer
	LD	HL,(SECBUF_SAV)
	LD	B,0		;256 bytes
$?WRITE	LD	A,(HL)
	CALL	IEC_BYTE_OUT
	INC	HL
	DJNZ	$?WRITE

	; UNLISTEN
	LD	A,IEC_UNLISTEN
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF

	XOR	A		;Success
	POP	BC
	POP	DE
	POP	HL
	RET

;==============================================================================
; Check disk drive status
; Output: A = status byte
;==============================================================================
IEC_STATUS
	PUSH	HL
	PUSH	BC

	; Send TALK to device, secondary 15 (status channel)
	LD	A,(PDRV$)
	OR	IEC_TALK
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	LD	A,06FH		;Secondary 15 with TALK
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF

	; Read status bytes until CR
	LD	HL,CMDBUF
	LD	B,32		;Max 32 status bytes
$?STAT	CALL	IEC_BYTE_IN
	LD	(HL),A
	INC	HL
	CP	0DH		;CR terminates
	JR	Z,$?ENDSTAT
	DJNZ	$?STAT

$?ENDSTAT
	CALL	IEC_DO_UNTALK
	LD	(HL),0		;Null terminate

	; Parse status for error code
	LD	HL,CMDBUF
	; Simple check: if first digit is '0', no error
	LD	A,(HL)
	CP	'0'
	JR	Z,$?OK
	; Error
	LD	A,8		;Device not available
	POP	BC
	POP	HL
	OR	A
	RET

$?OK	XOR	A		;Success
	POP	BC
	POP	HL
	RET

;==============================================================================
; Burst Mode Detection
; Output: BURST_STAT flags set on success, cleared on failure
;==============================================================================
BURST_DETECT
	PUSH	HL
	PUSH	BC
	; Send "U0>M0" to switch 1571 to native mode
	LD	HL,CMDBUF
	LD	(HL),'U'
	INC	HL
	LD	(HL),'0'
	INC	HL
	LD	(HL),'>'
	INC	HL
	LD	(HL),'M'
	INC	HL
	LD	(HL),'0'
	INC	HL
	LD	(HL),0
	LD	B,5
	LD	HL,CMDBUF
	CALL	IEC_COMMAND
	CALL	IEC_STATUS
	OR	A
	JR	NZ,$?NO1571
	LD	A,(BURST_STAT)
	OR	BURST_1571
	LD	(BURST_STAT),A
	; Send "U0>B0" to enable burst mode speed 0
	LD	HL,CMDBUF
	LD	(HL),'U'
	INC	HL
	LD	(HL),'0'
	INC	HL
	LD	(HL),'>'
	INC	HL
	LD	(HL),'B'
	INC	HL
	LD	(HL),'0'
	INC	HL
	LD	(HL),0
	LD	B,5
	LD	HL,CMDBUF
	CALL	IEC_COMMAND
	CALL	IEC_STATUS
	OR	A
	JR	NZ,$?NOBURST
	LD	A,(BURST_STAT)
	OR	BURST_ACTIVE
	LD	(BURST_STAT),A
$?NOBURST
	POP	BC
	POP	HL
	RET
$?NO1571
	XOR	A
	LD	(BURST_STAT),A
	POP	BC
	POP	HL
	RET

;==============================================================================
; Burst Mode Try-Read Wrapper
; Called from GRABNDO with HL=buffer, D=track, E=sector
; Tries burst read first, falls back to standard IEC on failure
;==============================================================================
BURST_TRY_READ
	LD	A,(BURST_STAT)
	AND	BURST_ACTIVE
	JP	NZ,BURST_READ_SECTOR
	JP	IEC_READ_SECTOR

;==============================================================================
; Burst Mode Try-Write Wrapper
;==============================================================================
BURST_TRY_WRITE
	LD	A,(BURST_STAT)
	AND	BURST_ACTIVE
	JP	NZ,BURST_WRITE_SECTOR
	JP	IEC_WRITE_SECTOR

;==============================================================================
; Burst Mode Sector Read
; Input: HL=buffer, D=track, E=sector
; Output: A=0 Z=success, A!=0 NZ=failure
; Falls back to IEC_READ_SECTOR on burst failure, clearing burst flag
;==============================================================================
BURST_READ_SECTOR
	PUSH	HL
	PUSH	DE
	PUSH	BC
	; Seek: U0>S<track_1based><sector_1based>
	LD	HL,CMDBUF
	LD	(HL),'U'
	INC	HL
	LD	(HL),'0'
	INC	HL
	LD	(HL),'>'
	INC	HL
	LD	(HL),'S'
	INC	HL
	LD	A,D
	INC	A
	LD	(HL),A
	INC	HL
	LD	A,E
	INC	A
	LD	(HL),A
	INC	HL
	LD	(HL),0
	LD	B,6
	LD	HL,CMDBUF
	CALL	IEC_COMMAND
	CALL	IEC_STATUS
	OR	A
	JR	NZ,$?FAIL
	; Begin burst read: B-R
	LD	HL,CMDBUF
	LD	(HL),'B'
	INC	HL
	LD	(HL),'-'
	INC	HL
	LD	(HL),'R'
	INC	HL
	LD	(HL),0
	LD	B,3
	LD	HL,CMDBUF
	CALL	IEC_COMMAND
	CALL	IEC_STATUS
	OR	A
	JR	NZ,$?FAIL
	; TALK device, secondary 0
	LD	A,(IY+4)
	OR	IEC_TALK
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	LD	A,060H
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF
	; Read 256 bytes with burst byte in
	POP	BC		;Original BC (garbage, discard)
	POP	DE		;Original DE
	EX	(SP),HL		;HL = user buffer, stack = saved user HL
	LD	B,0
$?BRD	CALL	BURST_BYTE_IN
	LD	(HL),A
	INC	HL
	DJNZ	$?BRD
	CALL	IEC_DO_UNTALK
	POP	HL		;Clean stack (the saved HL from PUSH)
	XOR	A
	RET
$?FAIL
	POP	BC
	POP	DE
	POP	HL
	XOR	A
	LD	(BURST_STAT),A
	JP	IEC_READ_SECTOR

;==============================================================================
; Burst Mode Sector Write
; Input: HL=buffer, D=track, E=sector
; Falls back to IEC_WRITE_SECTOR on burst failure
;==============================================================================
BURST_WRITE_SECTOR
	PUSH	HL
	PUSH	DE
	PUSH	BC
	; Seek: U0>S<track_1based><sector_1based>
	LD	HL,CMDBUF
	LD	(HL),'U'
	INC	HL
	LD	(HL),'0'
	INC	HL
	LD	(HL),'>'
	INC	HL
	LD	(HL),'S'
	INC	HL
	LD	A,D
	INC	A
	LD	(HL),A
	INC	HL
	LD	A,E
	INC	A
	LD	(HL),A
	INC	HL
	LD	(HL),0
	LD	B,6
	LD	HL,CMDBUF
	CALL	IEC_COMMAND
	CALL	IEC_STATUS
	OR	A
	JR	NZ,$?FAILW
	; Begin burst write: B-W
	LD	HL,CMDBUF
	LD	(HL),'B'
	INC	HL
	LD	(HL),'-'
	INC	HL
	LD	(HL),'W'
	INC	HL
	LD	(HL),0
	LD	B,3
	LD	HL,CMDBUF
	CALL	IEC_COMMAND
	CALL	IEC_STATUS
	OR	A
	JR	NZ,$?FAILW
	; LISTEN device, secondary 0
	LD	A,(IY+4)
	OR	IEC_LISTEN
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	LD	A,060H
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF
	; Send 256 bytes with burst byte out
	POP	BC
	POP	DE
	EX	(SP),HL
	LD	B,0
$?BWR	LD	A,(HL)
	CALL	BURST_BYTE_OUT
	INC	HL
	DJNZ	$?BWR
	LD	A,IEC_UNLISTEN
	CALL	IEC_ATN_ON
	CALL	IEC_BYTE_OUT
	CALL	IEC_ATN_OFF
	POP	HL
	XOR	A
	RET
$?FAILW
	POP	BC
	POP	DE
	POP	HL
	XOR	A
	LD	(BURST_STAT),A
	JP	IEC_WRITE_SECTOR

;==============================================================================
; Disk Driver Entry Point
;==============================================================================
; Input:
;   B = function code:
;     0 = NOP
;     1 = Select drive (C = drive)
;     2 = Step in (FDC - not used, maps to seek)
;     3 = Restore (recalibrate)
;     4 = Step in
;     5 = Step out (not used on TRS-80)
;     6 = Seek (D = track)
;     7 = Test busy
;     8-15 = I/O (8=Read, 9=Write, 10=Verify, etc.)
;   C = drive number (for select)
;   D = track
;   E = sector
;   HL = buffer address
;
; Output:
;   A = 0 or Z flag = success
;   A = error code, NZ = failure
;==============================================================================
FDCDVR	JR	FDCBGN		;Branch around linkage
	DW	FDCEND		;Last byte used
	DB	3,'$FD'
	; DCT data (filled in dynamically)
DCT_DATA EQU	$

FDCBGN
	LD	A,B		;Pick up function code
	AND	A		;NOP?
	RET	Z
	CP	7
	JR	Z,TSTBSY	;Test busy
	JP	NC,IORQST	;I/O request (8+)
	CP	6
	JR	Z,SEEKTRK	;Seek track
	DEC	A
	JR	Z,SELECT	;Select drive
	; Step in / Restore
	CP	4
	LD	B,58H		;FDC step in (unused)
	JR	Z,STEPIN
RESTOR
	; Restore: send re-init command to drive
	PUSH	HL
	PUSH	BC
	LD	HL,CMDBUF
	LD	(HL),'I'	;Initialize
	INC	HL
	LD	(HL),0
	LD	B,1
	LD	HL,CMDBUF
	CALL	IEC_COMMAND
	LD	(IY+5),0	;Current track = 0
	POP	BC
	POP	HL
	RET

SELECT
	; Select drive: store the drive number
	LD	A,C
	LD	(PDRV$),A	;Store drive
	; Set IEC device address (8-11 for drives)
	ADD	A,8		;C128 drives start at device 8
	LD	(IY+4),A	;Store in DCT
	CALL	BURST_DETECT	;Try to enable burst mode
	RET

STEPIN
	; Not directly used on IEC - maps to seek
	RET

SEEKTRK
	; Seek to track D
	LD	A,D
	LD	(IY+5),A	;Update current track
	; On IEC, we don't need to explicitly seek
	; The drive handles seeking automatically on read/write
	RET

TSTBSY
	; Check if drive is busy
	; On IEC, drives are always ready (unless data not available)
	XOR	A		;Not busy
	RET

;==============================================================================
; I/O Request Handler
;==============================================================================
IORQST
	BIT	2,B		;Write command?
	LD	BC,(RFLAG$-1)	;Pick up retry count
	JR	NZ,WRCMD	;Go if write

	; Read sector
	CP	10		;Verify?
	JR	Z,VERFY
	CALL	GRABNDO
	DB	1		;Error code start
	DW	BURST_TRY_READ

VERFY
	CALL	GRABNDO
	DB	1
	DW	BURST_TRY_READ	;Verify = read + check status

WRCMD
	BIT	7,(IY+3)	;Software write protect?
	JR	Z,WRCMD1
	LD	A,15		;Write protected error
	RET
WRCMD1
	CALL	GRABNDO
	DB	9		;Error code start
	DW	BURST_TRY_WRITE

;==============================================================================
; Error Handling and Retry
;==============================================================================
GRABNDO
	EX	(SP),HL
	LD	A,(HL)
	INC	HL
	LD	(ERRSTRT+1),A
	LD	A,(HL)
	INC	HL
	LD	H,(HL)
	LD	L,A
	LD	(CALLIO+1),HL
	POP	HL

RETRY
	PUSH	BC
	PUSH	DE
	PUSH	HL
	CALL	$-$		;Call I/O routine
CALLIO	EQU	$-2
	POP	HL
	POP	DE
	POP	BC
	RET	Z		;Return if no error
	DJNZ	RETRY		;Decrement retry count

ERRSTRT	LD	A,0		;Error code start
	LD	B,A
ERRTRAN	RRC	B
	RET	C
	INC	A
	JR	ERRTRAN

FDCEND	EQU	$-1

;==============================================================================
; Temporary Command Buffer
;==============================================================================
CMDBUF	DS	32		;IEC command buffer
BURST_STAT DB	0		;Burst mode status flags (BURST_1571, BURST_ACTIVE)
SECBUF_SAV DW	0		;Saved sector buffer address

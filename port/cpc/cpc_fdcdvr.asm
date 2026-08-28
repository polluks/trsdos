;****************************************************************
;* Filename: CPC_FDCDVR.ASM					*
;* Rev Date: 11 May 26						*
;* Version : 1.0							*
;****************************************************************
;* Amstrad CPC uPD765 FDC Driver for LSDOS 6.3.1L Port		*
;****************************************************************
;* Implements the LSDOS disk primitive mapping for the uPD765:	*
;*   B=1: Select drive					*
;*   B=2: Step in (maps to seek)				*
;*   B=3: Restore (recalibrate)				*
;*   B=6: Seek track					*
;*   B=7: Test busy					*
;*   B=8..15: I/O requests (read, write, verify)		*
;*								*
;* CF2 format: 40 tracks, 9 sectors/track, 512 bytes/sector	*
;****************************************************************
	SUBTTL	'<CPC uPD765 Floppy Disk Driver>'
	PAGE

;==============================================================================
; FDC Constants
;==============================================================================
FDC_MOTOR_DELAY	EQU	250	;Motor spin-up delay (approximate)

;==============================================================================
; FDC Low-Level Routines
;==============================================================================

; Wait for FDC ready (RQM bit set)
; Returns with RQM=1, DIO set appropriately
; FDC_MAIN/FDC_DATA are 16-bit ports, so access via (C) with the port in BC.
FDC_WAIT
	PUSH	DE
	LD	DE,FDC_TIMEOUT
$?WLOOP
	LD	BC,FDC_MAIN
	IN	A,(C)
	BIT	7,A		;RQM set?
	JR	NZ,$?READY
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,$?WLOOP
	; Timeout
	POP	DE
	OR	0FFH
	RET
$?READY
	POP	DE
	AND	0C0H		;Keep RQM and DIO
	RET

; Write byte to FDC
; A = byte to write
FDC_WRITE
	PUSH	AF
$?WW
	LD	BC,FDC_MAIN
	IN	A,(C)
	BIT	7,A		;RQM?
	JR	Z,$?WW
	BIT	6,A		;DIO must be 0 for write
	JR	NZ,$?WW
	POP	AF
	LD	BC,FDC_DATA
	OUT	(C),A
	RET

; Read byte from FDC
; Returns: A = byte read
FDC_READ
	PUSH	BC
$?RR
	LD	BC,FDC_MAIN
	IN	A,(C)
	BIT	7,A		;RQM?
	JR	Z,$?RR
	BIT	6,A		;DIO must be 1 for read
	JR	Z,$?RR
	LD	BC,FDC_DATA
	IN	A,(C)
	POP	BC
	RET

; Send command bytes to FDC
; HL = command bytes, B = count
FDC_SEND_CMD
	LD	A,(HL)
	CALL	FDC_WRITE
	INC	HL
	DJNZ	FDC_SEND_CMD
	RET

; Read result bytes from FDC
; HL = result buffer, B = count
FDC_READ_RES
	CALL	FDC_READ
	LD	(HL),A
	INC	HL
	DJNZ	FDC_READ_RES
	RET

; Drive motor on
FDC_MOTOR_ON
	PUSH	AF
	LD	A,FDC_MOTOR!FDC_DRIVE_A!FDC_DDEN
	LD	(FDC_DRVCTL),A
	; Delay for motor spin-up
	LD	BC,FDC_MOTOR_DELAY
$?MDELAY
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,$?MDELAY
	POP	AF
	RET

; Drive motor off
FDC_MOTOR_OFF
	PUSH	AF
	XOR	A
	LD	(FDC_DRVCTL),A
	POP	AF
	RET

;==============================================================================
; FDC Commands
;==============================================================================

; Specify command: set step rate, head unload/load times
FDC_SPECIFY
	PUSH	HL
	LD	HL,$?SPEC_CMD
	LD	B,3
	CALL	FDC_SEND_CMD
	POP	HL
	RET
$?SPEC_CMD
	DB	FDC_CMD_SPECIFY	;Specify command
	DB	0DFH			;SRT=3ms, HUT=16ms
	DB	06H			;HLT=4ms, ND=0

; Recalibrate drive (seek to track 0)
; Input: C = drive number (0 or 1)
FDC_RECAL
	PUSH	HL
	PUSH	BC
	LD	HL,$?RECAL_CMD
	LD	B,2
	CALL	FDC_SEND_CMD

	; Wait for interrupt (recal complete)
	CALL	FDC_WAIT_INT

	POP	BC
	POP	HL
	RET
$?RECAL_CMD
	DB	FDC_CMD_RECAL		;Recalibrate
	DB	0			;Drive 0 (bit 0 = drive select)

; Seek to track
; Input: D = track number
FDC_SEEK
	PUSH	HL
	PUSH	BC
	LD	HL,$?SEEK_CMD
	LD	B,3
	CALL	FDC_SEND_CMD

	; Wait for interrupt (seek complete)
	CALL	FDC_WAIT_INT

	POP	BC
	POP	HL
	RET
$?SEEK_CMD
	DB	FDC_CMD_SEEK		;Seek
	DB	0			;Head 0, drive 0
	DB	0			;Track (filled in dynamically)

; Sense Interrupt Status - needed after recal/seek
FDC_WAIT_INT
	PUSH	HL
	PUSH	BC
	LD	B,3			;Max retries
$?SENSE
	PUSH	BC
	; Send SENSE INTERRUPT STATUS command
	LD	A,FDC_CMD_SENSEI
	CALL	FDC_WRITE
	; Read result (ST0, PCN)
	CALL	FDC_READ		;ST0
	PUSH	AF
	CALL	FDC_READ		;PCN
	POP	AF
	; Check for normal termination
	AND	0C0H			;Check interrupt code
	JR	Z,$?SENSE_OK
	POP	BC
	DJNZ	$?SENSE
	; Error
	LD	A,8
	OR	A
	POP	BC
	POP	HL
	RET
$?SENSE_OK
	POP	BC
	POP	BC
	POP	HL
	XOR	A
	RET

; Sense Drive Status
; Input: C = drive
; Output: A = status
FDC_SENSE_DRV
	PUSH	HL
	LD	HL,$?SENSED_CMD
	LD	B,2
	CALL	FDC_SEND_CMD
	CALL	FDC_READ
	POP	HL
	RET
$?SENSED_CMD
	DB	FDC_CMD_SENSED		;Sense drive status
	DB	0			;Drive 0

; Read a sector
; Input: D=track, E=sector, HL=buffer
; Output: A=0 on success
FDC_READ_SEC
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Motor on
	CALL	FDC_MOTOR_ON

	; Seek to track
	LD	A,D
	LD	($?SEEK_CMD+2),A
	CALL	FDC_SEEK

	; Read command
	LD	HL,$?READ_CMD
	LD	B,9
	CALL	FDC_SEND_CMD

	; Enter result phase (wait for RQM with DIO=1)
	LD	B,4			;4 result bytes
	LD	HL,RESBUF
	CALL	FDC_READ_RES

	; Motor off
	CALL	FDC_MOTOR_OFF

	; Check result
	LD	A,(RESBUF)		;ST0
	AND	0C0H			;Interrupt code
	JR	NZ,$?R_ERR
	XOR	A
	POP	HL
	POP	DE
	POP	BC
	RET
$?R_ERR
	LD	A,8
	POP	HL
	POP	DE
	POP	BC
	RET
$?READ_CMD
	DB	FDC_CMD_READ		;Read data (MFM, skip)
	DB	0			;Head 0, drive 0
	DB	0			;Track (filled in)
	DB	0			;Head
	DB	0			;Sector (filled in)
	DB	FDC_SEC_SIZE		;N (sector size code)
	DB	CPC_SEC_PER_TRK		;EOT (last sector number)
	DB	CPC_GAP3		;GPL (gap 3)
	DB	0FFH			;DTL (data length, 11111111=no limit)

; Write a sector
; Input: D=track, E=sector, HL=buffer
; Output: A=0 on success
FDC_WRITE_SEC
	PUSH	BC
	PUSH	DE
	PUSH	HL

	; Motor on
	CALL	FDC_MOTOR_ON

	; Seek to track
	LD	A,D
	LD	($?SEEK_CMD+2),A
	CALL	FDC_SEEK

	; Write command
	LD	HL,$?WRITE_CMD
	LD	B,9
	CALL	FDC_SEND_CMD

	; Send 512 bytes from buffer
	POP	HL
	PUSH	HL
	LD	BC,512
$?WDATA
	LD	A,(HL)
	CALL	FDC_WRITE
	INC	HL
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,$?WDATA

	; Read result
	LD	B,4
	LD	HL,RESBUF
	CALL	FDC_READ_RES

	; Motor off
	CALL	FDC_MOTOR_OFF

	LD	A,(RESBUF)
	AND	0C0H
	JR	NZ,$?W_ERR
	XOR	A
	POP	HL
	POP	DE
	POP	BC
	RET
$?W_ERR
	LD	A,8
	POP	HL
	POP	DE
	POP	BC
	RET
$?WRITE_CMD
	DB	FDC_CMD_WRITE		;Write data (MFM)
	DB	0			;Head 0, drive 0
	DB	0			;Track
	DB	0			;Head
	DB	0			;Sector
	DB	FDC_SEC_SIZE		;N
	DB	CPC_SEC_PER_TRK		;EOT
	DB	CPC_GAP3		;GPL
	DB	0FFH			;DTL

;==============================================================================
; Result buffer
;==============================================================================
RESBUF	DS	7

;==============================================================================
; Disk Driver Entry Point
;==============================================================================
; Input: B = function, C = drive, D = track, E = sector, HL = buffer
;==============================================================================
FDCDVR	JR	FDCBGN
	DW	FDCEND
	DB	3,'$FD'
DCT_DATA EQU	$

FDCBGN
	LD	A,B
	AND	A
	RET	Z
	CP	7
	JR	Z,TSTBSY
	JP	NC,IORQST
	CP	6
	JR	Z,SEEKTRK
	DEC	A
	JR	Z,SELECT
	CP	4
	LD	B,58H
	JR	Z,STEPIN

RESTOR
	; Recalibrate
	PUSH	HL
	PUSH	BC
	CALL	FDC_MOTOR_ON
	LD	C,0		;Drive 0
	CALL	FDC_RECAL
	LD	(IY+5),0	;Current track = 0
	POP	BC
	POP	HL
	RET

SELECT
	LD	A,C
	LD	(PDRV$),A
	LD	(IY+4),A	;Drive in DCT
	RET

STEPIN
	RET

SEEKTRK
	LD	A,D
	LD	(IY+5),A	;Update current track
	PUSH	HL
	PUSH	BC
	CALL	FDC_MOTOR_ON
	CALL	FDC_SEEK
	POP	BC
	POP	HL
	RET

TSTBSY
	; Check if FDC is busy
	LD	BC,FDC_MAIN
	IN	A,(C)
	BIT	4,A		;CB (FDC busy)?
	JR	NZ,$?BUSY
	XOR	A		;Not busy
	RET
$?BUSY
	LD	A,0FFH		;Busy
	OR	A
	RET

;==============================================================================
; I/O Request Handler
;==============================================================================
IORQST
	BIT	2,B
	LD	BC,(RFLAG$-1)
	JR	NZ,WRCMD

	; Read/Verify
	CP	10
	JR	Z,VERFY
	CALL	GRABNDO
	DB	1
	DW	FDC_READ_SEC

VERFY
	CALL	GRABNDO
	DB	1
	DW	FDC_READ_SEC

WRCMD
	BIT	7,(IY+3)
	JR	Z,WRCMD1
	LD	A,15
	RET
WRCMD1
	CALL	GRABNDO
	DB	9
	DW	FDC_WRITE_SEC

;==============================================================================
; Error Handling
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
	RET	Z
	DJNZ	RETRY

ERRSTRT	LD	A,0
	LD	B,A
ERRTRAN	RRC	B
	RET	C
	INC	A
	JR	ERRTRAN

FDCEND	EQU	$-1

;==============================================================================
; Command buffer
;==============================================================================
CMDBUF	DS	32

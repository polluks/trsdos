;****************************************************************
;* Filename: CPC_EQU.ASM					*
;* Rev Date: 11 May 26						*
;* Version : 1.0							*
;****************************************************************
;* Amstrad CPC 6128 Hardware Definitions for LSDOS 6.3.1L Port	*
;****************************************************************
;*								*
;* Defines all CPC-specific hardware register addresses,		*
;* memory map locations, and port assignments			*
;* for the LSDOS 6.3.1L port to the Amstrad CPC 6128.		*
;*								*
;****************************************************************
	SUBTTL	'<CPC Hardware Definitions>'
	PAGE

;==============================================================================
; CPC Memory Map
;==============================================================================
; $0000-$3FFF: RAM (bank 0, main memory)
; $4000-$7FFF: RAM (bank 0, or banked)
; $8000-$BFFF: RAM (bank 0, or expanded)
; $C000-$FFFF: Screen memory (mode 1: 40x25 text, 16000 bytes)
;              Also: firmware ROM at $C000 (banked out after boot)

;==============================================================================
; Gate Array (GA) - 40007/70007
; OUT ($7F),A - all GA commands use this single port
;==============================================================================
GA_PORT		EQU	07FH

; GA command select bits (bits 7-6):
GA_INK_CMD	EQU	00H	;Select pen/ink (bits 3-0 = pen, bits 5-4 = color)
GA_MODE_CMD	EQU	40H	;Select screen mode (bits 1-0 = mode)
GA_ROM_CMD	EQU	80H	;ROM select / RAM config
GA_RAM_CMD	EQU	0C0H	;RAM banking (CPC+ only)

; Screen mode values (OR with GA_MODE_CMD):
GA_MODE_0	EQU	00H	;Mode 0: 160x200, 16 colors
GA_MODE_1	EQU	01H	;Mode 1: 320x200, 4 colors
GA_MODE_2	EQU	02H	;Mode 2: 640x200, 2 colors

; ROM banking values (OR with GA_ROM_CMD):
GA_ROM_LOWER	EQU	00H	;Lower ROM ($0000-$3FFF) enabled
GA_ROM_UPPER	EQU	04H	;Upper ROM ($C000-$FFFF) enabled
GA_ROM_BOTH	EQU	08H	;Both ROMs enabled
GA_ROM_DISABLE	EQU	0CH	;All ROMs disabled (all RAM)

; Interrupt control:
GA_INT_VBLANK	EQU	10H	;Enable VSYNC interrupt

; Pen/ink colors (for GA_INK_CMD):
INK_BLACK	EQU	0
INK_BLUE	EQU	1
INK_BRIGHT_BLUE EQU	2
INK_RED		EQU	3
INK_MAGENTA	EQU	4
INK_MAUVE	EQU	5
INK_BRIGHT_RED	EQU	6
INK_PURPLE	EQU	7
INK_BRIGHT_MAG	EQU	8
INK_GREEN	EQU	9
INK_CYAN	EQU	10
INK_BRIGHT_GREEN EQU	11
INK_YELLOW	EQU	12
INK_PASTEL_BLUE	EQU	13
INK_ORANGE	EQU	14
INK_WHITE	EQU	15

;==============================================================================
; CRTC (Motorola 6845) - Video timing controller
;==============================================================================
CRTC_ADDR	EQU	0BC00H		;CRTC address register
CRTC_DATA	EQU	0BD00H		;CRTC data register

; CRTC register numbers:
CRTC_HTOTAL	EQU	0		;Horizontal total (chars)
CRTC_HDISP	EQU	1		;Horizontal displayed (chars)
CRTC_HSYNC	EQU	2		;Horizontal sync position
CRTC_VTOTAL	EQU	3		;Vertical total (chars)
CRTC_VADJ	EQU	4		;Vertical total adjust (scanlines)
CRTC_VDISP	EQU	5		;Vertical displayed (char rows)
CRTC_VSYNC	EQU	6		;Vertical sync position
CRTC_ILACE	EQU	7		;Interlace mode / skew
CRTC_MAXSCAN	EQU	9		;Max scanline address
CRTC_CURSTART	EQU	10		;Cursor start scanline
CRTC_CUREND	EQU	11		;Cursor end scanline
CRTC_SAHIGH	EQU	12		;Screen start address high
CRTC_SALOW	EQU	13		;Screen start address low
CRTC_CURHIGH	EQU	14		;Cursor position high
CRTC_CURLOW	EQU	15		;Cursor position low
CRTC_LPENHIGH	EQU	16		;Light pen high
CRTC_LPENLOW	EQU	17		;Light pen low

; Mode 1 screen constants:
CPC_COLS	EQU	40		;Columns per row (mode 1)
CPC_ROWS	EQU	25		;Rows per screen
CPC_CRTSIZE	EQU	CPC_COLS*CPC_ROWS ;Total screen cells (chars)

;==============================================================================
; Screen Memory
;==============================================================================
SCR_BASE	EQU	0C000H		;Screen memory base address
SCR_SIZE	EQU	16000		;Total screen bytes (mode 1)
SCR_LINE_BYTES	EQU	80		;Bytes per scanline (mode 1, 2bpp)
SCR_CHAR_BYTES	EQU	8		;Bytes per character row (8 scanlines)
SCR_ROW_BYTES	EQU	SCR_LINE_BYTES*SCR_CHAR_BYTES ;Bytes per char row (640)

;==============================================================================
; PPI (8255) - Keyboard, Printer, Motor Control
;==============================================================================
PPI_BASE	EQU	0F700H		;PPI base address
PPI_PA		EQU	PPI_BASE+0	;Port A - keyboard row select (out)
PPI_PB		EQU	PPI_BASE+1	;Port B - keyboard columns (in)
PPI_PC		EQU	PPI_BASE+2	;Port C - printer/motor control
PPI_CTRL	EQU	PPI_BASE+3	;Control register

; PPI mode setup values:
PPI_MODE_SET	EQU	10010010B	;Mode 0: A=out, B=in, CH=in, CL=out
					; Port A out, Port B in, Port C upper in, lower out

; PPI Port A bit definitions (write):
PPI_PA_ROW0	EQU	01H		;Keyboard row 0 select
PPI_PA_ROW1	EQU	02H		;Keyboard row 1
PPI_PA_ROW2	EQU	04H		;Keyboard row 2
PPI_PA_ROW3	EQU	08H		;Keyboard row 3
PPI_PA_ROW4	EQU	10H		;Keyboard row 4
PPI_PA_ROW5	EQU	20H		;Keyboard row 5
PPI_PA_ROW6	EQU	40H		;Keyboard row 6
PPI_PA_ROW7	EQU	80H		;Keyboard row 7

; PPI Port A bit definitions (read - printer status):
PPI_PA_BUSY	EQU	80H		;Printer busy (bit 7)
PPI_PA_ACK	EQU	40H		;Printer acknowledge (bit 6)
PPI_PA_PAPER	EQU	20H		;Printer paper out (bit 5)
PPI_PA_SELECT	EQU	10H		;Printer selected (bit 4)
PPI_PA_ERROR	EQU	08H		;Printer error (bit 3)

; PPI Port C bit definitions (write):
PPI_PC_MOTOR	EQU	01H		;Motor control bit
PPI_PC_PRSTROBE EQU	02H		;Printer strobe
PPI_PC_AUDIO	EQU	04H		;Cassette audio out
PPI_PC_ROMDIS	EQU	08H		;ROM disable (0=ROM on CPC 464)
PPI_PC_READY	EQU	10H		;Ready line (RS232)

;==============================================================================
; FDC (uPD765) - Floppy Disk Controller
;==============================================================================
FDC_DATA	EQU	0FB7EH		;FDC data register (read/write)
FDC_MAIN	EQU	0FB7FH		;FDC main status register (read)
FDC_DRVCTL	EQU	0FB7AH		;Drive control register (write)

; Drive control bits:
FDC_MOTOR	EQU	01H		;Motor on (bit 0)
FDC_DRIVE_A	EQU	00H		;Drive A select (bit 1=0)
FDC_DRIVE_B	EQU	02H		;Drive B select (bit 1=1)
FDC_DDEN	EQU	40H		;Double density enable (bit 6)
FDC_SIDE	EQU	80H		;Side select (bit 7)

; FDC Main Status Register bits:
FDC_MSR_DB0	EQU	01H		;Drive 0 busy
FDC_MSR_DB1	EQU	02H		;Drive 1 busy
FDC_MSR_DB2	EQU	04H		;Drive 2 busy
FDC_MSR_DB3	EQU	08H		;Drive 3 busy
FDC_MSR_CB	EQU	10H		;FDC busy (command in progress)
FDC_MSR_NDM	EQU	20H		;Non-DMA mode
FDC_MSR_DIO	EQU	40H		;Data I/O direction (1=read from FDC)
FDC_MSR_RQM	EQU	80H		;Request for master (ready for data)

; FDC Commands:
FDC_CMD_READ		EQU	0E6H	;Read data (MFM, skip)
FDC_CMD_READ_STD	EQU	80H	;Read data (standard)
FDC_CMD_WRITE		EQU	0C5H	;Write data (MFM)
FDC_CMD_WRITE_STD	EQU	80H	;Write data (standard)
FDC_CMD_SEEK		EQU	0FH	;Seek
FDC_CMD_RECAL		EQU	07H	;Recalibrate
FDC_CMD_SENSEI		EQU	04H	;Sense interrupt status
FDC_CMD_SENSED		EQU	08H	;Sense drive status
FDC_CMD_SPECIFY		EQU	03H	;Specify (step rate, head unload)
FDC_CMD_VERSION		EQU	10H	;Read version

; FDC Phase constants:
FDC_READ_TRACK	EQU	0		;Track in ID field
FDC_READ_HEAD	EQU	1		;Head in ID field
FDC_READ_SECTOR	EQU	2		;Sector in ID field
FDC_READ_N	EQU	3		;Sector size code

; Sector size codes:
FDC_SEC_128	EQU	0		;128 bytes
FDC_SEC_256	EQU	1		;256 bytes
FDC_SEC_512	EQU	2		;512 bytes
FDC_SEC_1024	EQU	3		;1024 bytes

; CF2 disk format (SSSD, 40 tracks, 9 sectors/track, 512 bytes/sector):
CPC_NUM_TRACKS	EQU	40		;Tracks per side
CPC_SEC_PER_TRK	EQU	9		;Sectors per track (CF2)
CPC_SEC_SIZE	EQU	2		;512 bytes per sector (code)
CPC_SEC_BYTES	EQU	512		;Bytes per sector
CPC_GAP3	EQU	2AH		;Gap 3 value (for uPD765)

;==============================================================================
; Printer Port (Centronics)
;==============================================================================
PRT_DATA	EQU	0F000H		;Printer data (write)
PRT_STROBE	EQU	0F100H		;Printer strobe (write)

;==============================================================================
; Console/Keyboard constants for CPC
;==============================================================================
; The CPC keyboard is organized as a 10×8 matrix (10 rows, 8 columns)
; Accessed via PPI Port A (row select) and Port B (column read)

KEY_ROWS	EQU	10		;Total keyboard rows

;==============================================================================
; Interrupt control
;==============================================================================
; CPC uses Mode 1 interrupts (RST 38h)
; Interrupt occurs every 20ms (50Hz PAL) or 16.7ms (60Hz NTSC)
; GA register $7F enables/disables VSYNC interrupt (bit 4)

;==============================================================================
; CRTC Register Access Macros
;==============================================================================

; Select CRTC register and write value
CRTC_SET	MACRO	REG, VAL
	LD	A,REG
	LD	BC,CRTC_ADDR
	OUT	(C),A
	LD	A,VAL
	LD	BC,CRTC_DATA
	OUT	(C),A
	ENDM

; Select CRTC register (address only)
CRTC_SEL	MACRO	REG
	LD	A,REG
	LD	BC,CRTC_ADDR
	OUT	(C),A
	ENDM

;==============================================================================
; GA Control Macros
;==============================================================================

; Set screen mode
GA_SET_MODE	MACRO	MODE
	LD	A,GA_MODE_CMD!MODE
	OUT	(GA_PORT),A
	ENDM

; Set ink (pen) color
GA_SET_INK	MACRO	PEN, COLOR
	LD	A,PEN!COLOR<<4
	OUT	(GA_PORT),A
	ENDM

	END

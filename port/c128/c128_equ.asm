;****************************************************************
;* Filename: C128_EQU.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* Commodore 128 Hardware Definitions for LSDOS 6.3.1L Port	*
;****************************************************************
;*								*
;* This file defines all C128-specific hardware register	*
;* addresses, memory map locations, and port assignments	*
;* for the LSDOS 6.3.1L port to the Commodore 128.		*
;*								*
;****************************************************************
	SUBTTL	'<C128 Hardware Definitions>'
	PAGE

;==============================================================================
; CIA #1 (6526) - Keyboard, Joystick, TOD, NMI
;==============================================================================
; Base address for Z80 mode access
CIA1_DDRA	EQU	0DC00H		;CIA#1 Data Port A (keyboard rows)
CIA1_PRA	EQU	CIA1_DDRA	;Port A - rows output
CIA1_DDRB	EQU	0DC01H		;CIA#1 Data Port B (keyboard cols)
CIA1_PRB	EQU	CIA1_DDRB	;Port B - columns input
CIA1_TALO	EQU	0DC04H		;Timer A low
CIA1_TAHI	EQU	0DC05H		;Timer A high
CIA1_TBLO	EQU	0DC06H		;Timer B low
CIA1_TBHI	EQU	0DC07H		;Timer B high
CIA1_TOD10	EQU	0DC08H		;TOD 1/10 sec
CIA1_TODSEC	EQU	0DC09H		;TOD seconds
CIA1_TODMIN	EQU	0DC0AH		;TOD minutes
CIA1_TODHR	EQU	0DC0BH		;TOD hours (bit 7 = AM/PM)
CIA1_SDR	EQU	0DC0CH		;Serial data register
CIA1_ICR	EQU	0DC0DH		;Interrupt control register
CIA1_CRA	EQU	0DC0EH		;Timer A control
CIA1_CRB	EQU	0DC0FH		;Timer B control

; Interrupt bits (CIA ICR)
CIA_IRQ_TA	EQU	01H		;Timer A underflow
CIA_IRQ_TB	EQU	02H		;Timer B underflow
CIA_IRQ_TOD	EQU	04H		;TOD alarm
CIA_IRQ_SP	EQU	08H		;Serial port
CIA_IRQ_FLG	EQU	10H		;FLG line
CIA_IRQ_NMI	EQU	80H		;Set to read mask, else set

;==============================================================================
; CIA #2 (6526) - IEC Serial Bus, RS-232
;==============================================================================
CIA2_DDRA	EQU	0DD00H		;CIA#2 Data Port A
CIA2_PRA	EQU	CIA2_DDRA	;IEC bus control
CIA2_DDRB	EQU	0DD01H		;CIA#2 Data Port B
CIA2_PRB	EQU	CIA2_DDRB	;IEC bus data/status
CIA2_TALO	EQU	0DD04H		;Timer A low (serial clock)
CIA2_TAHI	EQU	0DD05H		;Timer A high
CIA2_TBLO	EQU	0DD06H		;Timer B low
CIA2_TBHI	EQU	0DD07H		;Timer B high
CIA2_TOD10	EQU	0DD08H		;TOD 1/10 sec
CIA2_TODSEC	EQU	0DD09H		;TOD seconds
CIA2_TODMIN	EQU	0DD0AH		;TOD minutes
CIA2_TODHR	EQU	0DD0BH		;TOD hours
CIA2_SDR	EQU	0DD0CH		;Serial data register
CIA2_ICR	EQU	0DD0DH		;Interrupt control register
CIA2_CRA	EQU	0DD0EH		;Timer A control
CIA2_CRB	EQU	0DD0FH		;Timer B control

; IEC Bus signal bits (CIA2 Port A)
IEC_DATOUT	EQU	01H		;Serial data out (DAT)
IEC_CLK		EQU	02H		;Serial clock out (CLK)
IEC_ATN		EQU	04H		;Attention (ATN)
IEC_DATA_IN	EQU	08H		;Data in from bus
IEC_DATOUT_IN	EQU	08H		;Data in bit (alias for IEC_DATA_IN)
IEC_CLK_IN	EQU	10H		;Clock in from bus
IEC_SRQ		EQU	20H		;Service request
IEC_BUS_RESET	EQU	40H		;Device reset

; IEC bus bit positions for Port B
IECPB_DATA	EQU	01H		;Data out via PB
IECPB_CLK	EQU	02H		;Clock out via PB
IECPB_ATN	EQU	04H		;Attention via PB
IECPB_DATA_IN	EQU	08H		;Data in status
IECPB_CLK_IN	EQU	10H		;Clock in status

;==============================================================================
; VDC (8563) Video Controller
;==============================================================================
VDC_ADDR	EQU	0D600H		;VDC address/status register
VDC_DATA	EQU	0D601H		;VDC data register

; VDC Register numbers
VDC_HTOTAL	EQU	0		;Horizontal total
VDC_HDISP	EQU	1		;Horizontal displayed
VDC_HSYNC	EQU	2		;Horizontal sync position
VDC_VTOTAL	EQU	3		;Vertical total
VDC_VADJ	EQU	4		;Vertical total adjust
VDC_VDISP	EQU	5		;Vertical displayed
VDC_VSYNC	EQU	6		;Vertical sync position
VDC_ILACE	EQU	7		;Interlace mode
VDC_ROWSCAN	EQU	9		;Max scan line address
VDC_CURSTART	EQU	10		;Cursor start scan line
VDC_CUREND	EQU	11		;Cursor end scan line
VDC_SAHIGH	EQU	12		;Display start address high
VDC_SALOW	EQU	13		;Display start address low
VDC_CURHIGH	EQU	14		;Cursor position high
VDC_CURLOW	EQU	15		;Cursor position low
VDC_VSYNCPOS	EQU	16		;Vertical sync position
VDC_CHRCOUNT	EQU	30		;Character counter
VDC_MEMREFR	EQU	31		;Memory refresh / data register
VDC_UAHIGH	EQU	18		;Update address high (VRAM offset)
VDC_UALOW	EQU	19		;Update address low
VDC_UDATA	EQU	31		;Auto-increment data register
VDC_BLINK	EQU	34		;Blink rate
VDC_ATTR	EQU	36		;Attribute register

; VDC attribute bits
VDC_ATTR_ALT	EQU	01H		;Alternate character set
VDC_ATTR_REV	EQU	02H		;Reverse video
VDC_ATTR_ULINE	EQU	04H		;Underline
VDC_ATTR_BLINK	EQU	08H		;Blink
VDC_ATTR_BOLD	EQU	10H		;Bold
VDC_ATTR_CSR	EQU	20H		;Cursor enable

; VDC block move operation
VDC_BLKCOPY	EQU	31		;Block copy (reg 31)
VDC_BLKLOAD	EQU	32		;Block load (reg 32)
VDC_BLKWRITE	EQU	33		;Block write (reg 33)

;==============================================================================
; VIC-II (6569/8564) - 40 Column Video & Memory Control
;==============================================================================
VIC_BASE	EQU	0D000H		;VIC-II base address
VIC_SPR0_X	EQU	0D000H		;Sprite 0 X
VIC_SPR0_Y	EQU	0D001H		;Sprite 0 Y
VIC_CR1		EQU	0D011H		;Control register 1
VIC_RASTER	EQU	0D012H		;Raster line
VIC_LPX		EQU	0D013H		;Light pen X
VIC_LPY		EQU	0D014H		;Light pen Y
VIC_SPENA	EQU	0D015H		;Sprite enable
VIC_CR2		EQU	0D016H		;Control register 2
VIC_MEM		EQU	0D018H		;Memory pointers
VIC_IRQ		EQU	0D019H		;Interrupt request
VIC_IE		EQU	0D01AH		;Interrupt enable
VIC_SPBG	EQU	0D01BH		;Sprite background priority
VIC_SPMC	EQU	0D01CH		;Sprite multicolor
VIC_SPXE	EQU	0D01DH		;Sprite X expand
VIC_SPYE	EQU	0D017H		;Sprite Y expand
VIC_BORDER	EQU	0D020H		;Border color

;==============================================================================
; SID (6581) - Sound Interface Device
;==============================================================================
SID_BASE	EQU	0D400H		;SID base address
SID_V1_FREQL	EQU	0D400H		;Voice 1 frequency low
SID_V1_FREQH	EQU	0D401H		;Voice 1 frequency high
SID_V1_PWML	EQU	0D402H		;Voice 1 pulse width low
SID_V1_PWMH	EQU	0D403H		;Voice 1 pulse width high
SID_V1_CTRL	EQU	0D404H		;Voice 1 control
SID_V1_AD	EQU	0D405H		;Voice 1 attack/decay
SID_V1_SR	EQU	0D406H		;Voice 1 sustain/release
SID_V2_FREQL	EQU	0D407H		;Voice 2 frequency low
SID_V2_FREQH	EQU	0D408H		;Voice 2 frequency high
SID_V2_PWML	EQU	0D409H		;Voice 2 pulse width low
SID_V2_PWMH	EQU	0D40AH		;Voice 2 pulse width high
SID_V2_CTRL	EQU	0D40BH		;Voice 2 control
SID_V2_AD	EQU	0D40CH		;Voice 2 attack/decay
SID_V2_SR	EQU	0D40DH		;Voice 2 sustain/release
SID_V3_FREQL	EQU	0D40EH		;Voice 3 frequency low
SID_V3_FREQH	EQU	0D40FH		;Voice 3 frequency high
SID_V3_PWML	EQU	0D410H		;Voice 3 pulse width low
SID_V3_PWMH	EQU	0D411H		;Voice 3 pulse width high
SID_V3_CTRL	EQU	0D412H		;Voice 3 control
SID_V3_AD	EQU	0D413H		;Voice 3 attack/decay
SID_V3_SR	EQU	0D414H		;Voice 3 sustain/release
SID_FILT_FC	EQU	0D415H		;Filter cutoff low
SID_FILT_FCH	EQU	0D416H		;Filter cutoff high
SID_FILT_CTRL	EQU	0D417H		;Filter control
SID_FILT_MODE	EQU	0D418H		;Filter mode/volume
SID_POTX	EQU	0D419H		;Potentiometer X
SID_POTY	EQU	0D41AH		;Potentiometer Y
SID_OSC3	EQU	0D41BH		;Oscillator 3 output
SID_ENV3	EQU	0D41CH		;Envelope 3 output

; SID voice control bits
SID_CTRL_GATE	EQU	01H		;Gate (start/stop)
SID_CTRL_SYNC	EQU	02H		;Sync
SID_CTRL_RING	EQU	04H		;Ring modulation
SID_CTRL_TEST	EQU	08H		;Test
SID_CTRL_TRI	EQU	10H		;Triangle wave
SID_CTRL_SAW	EQU	20H		;Sawtooth wave
SID_CTRL_PULSE	EQU	40H		;Pulse wave
SID_CTRL_NOISE	EQU	80H		;Noise

;==============================================================================
; MMU (Memory Management Unit) - Bank 15 mapping
;==============================================================================
MMU_CR		EQU	0FF00H		;MMU configuration register
MMU_RAM0	EQU	0FF01H		;Preconfig 0 (RAM 0)
MMU_RAM1	EQU	0FF02H		;Preconfig 1 (RAM 1)
MMU_RAM2	EQU	0FF03H		;Preconfig 2 (RAM 2)
MMU_RAM3	EQU	0FF04H		;Preconfig 3 (RAM 3)
MMU_LOAD	EQU	0FF05H		;Load configuration

; MMU configuration select values
MMU_CFG_0	EQU	00H		;Config 0: All RAM
MMU_CFG_1	EQU	01H		;Config 1: RAM+RAM+RAM+KERNAL
MMU_CFG_2	EQU	02H		;Config 2: RAM+RAM+RAM+CHARROM
MMU_CFG_3	EQU	03H		;Config 3: RAM+RAM+IO+RAM
MMU_CFG_4	EQU	04H		;Config 4: RAM+RAM+IO+KERNAL
MMU_CFG_5	EQU	05H		;Config 5: LO ROM+EXT+RAM+KERNAL
MMU_CFG_6	EQU	06H		;Config 6: LO ROM+EXT+IO+RAM

; MMU RAM block numbers (for 128K C128)
MMU_BANK0	EQU	0		;RAM block 0 ($00000-$0FFFF)
MMU_BANK1	EQU	1		;RAM block 1 ($10000-$1FFFF)

;==============================================================================
; C128 Memory Map Constants (for LSDOS port)
;==============================================================================
; We preserve the standard LSDOS memory layout where possible:
;
; $0000-$00FF: Page 0 - RST vectors, system data
; $0100-$01FF: Page 1 - SVC table
; $0200-$12FF: Page 2+ - I/O Drivers
; $1300-$1CFF: SYSRES (BDOS)
; $1D00-$1DFF: Sector buffer
; $1E00-$3FFF: SYS1 (command interpreter)
; $4000-$7FFF: User program area
; $8000-$BFFF: Overlay/buffer area
; $C000-$FFFF: Reserved for system ROM shadow or banked

; C128-specific memory additions
RTCLOK		EQU	0A0H		;Jiffy clock (3 bytes, like Atari)
VDC_RES_SAVE	EQU	0A3H		;Saved VDC register
VDC_ADDR_SAVE	EQU	0A4H		;Saved VDC address
CIA_ICR_SAVE	EQU	0A5H		;Saved CIA ICR mask
IEC_BUS_SAVE	EQU	0A6H		;Saved IEC bus state
KBD_META	EQU	0A7H		;Keyboard meta state (shift,ctrl,c=)

; VDC screen dimensions for LSDOS
VDC_COLS	EQU	80		;Columns per row
VDC_ROWS	EQU	25		;Rows per screen
VDC_CRTSIZE	EQU	VDC_COLS*VDC_ROWS ;Total screen cells
VDC_TABSTOP	EQU	8		;Tab stops every 8

;==============================================================================
; IEC Serial Bus Protocol Constants
;==============================================================================
IEC_LISTEN	EQU	20H		;Listen command
IEC_TALK	EQU	40H		;Talk command
IEC_UNLISTEN	EQU	3FH		;Unlisten
IEC_UNTALK	EQU	5FH		;Untalk
IEC_OPEN	EQU	0F0H		;Open channel
IEC_CLOSE	EQU	0E0H		;Close channel
IEC_DATA	EQU	60H		;Data channel
IEC_CMD		EQU	60H		;Command channel

; Device addresses
IEC_DEV_1571	EQU	8		;Drive 8
IEC_DEV_1581	EQU	8		;Drive 8
IEC_DEV_DISK2	EQU	9		;Drive 9
IEC_DEV_PRINT	EQU	4		;Printer

;==============================================================================
; Z80-Specific I/O Ports (C128 CP/M mode)
;==============================================================================
Z80_PAGE	EQU	0F9H		;Z80 page register (if applicable)

;==============================================================================
; System Constants for the port
;==============================================================================
C128_CPU_SPEED	EQU	2		;Z80 runs at 2MHz in C128
MAX_DRIVES	EQU	4		;Up to 4 IEC drives
SECTOR_SIZE	EQU	256		;Standard LSDOS sector size
SECTORS_PER_TRK	EQU	18		;5.25" DD MFM
GRAN_SIZE	EQU	6		;Sectors per granule

;==============================================================================
; Pin connections for keyboard matrix (C128 CIA #1)
;==============================================================================
; The C128 keyboard is arranged as an 8x8 matrix:
; Row select (CIA#1 PA0-PA7) -> Column read (CIA#1 PB0-PB7)
;
;     PA0 PA1 PA2 PA3 PA4 PA5 PA6 PA7
; PB0  3   6   -   =   R   N   9   C=
; PB1  W   +   A   .   ,   H   3   STOP
; PB2  A   S   B   /   ;   J   6   L/
; PB3  4   Z   C   SP  *   K   2   ;
; PB4  5   1   D   Q   S   L   0   ENTER
; PB5  F   2   E   M   8   :   7   DEL
; PB6  7   4   X   @   -   O   1   CRSR-R
; PB7  T   G   I   P   U   Y   W   CRSR-D
; (from memory - row/col assignments may vary)

;==============================================================================
; VDC Register Access Macros
;==============================================================================
; Select VDC register and write a value to it
VDC_SET	MACRO	REG, VAL
	LD	A,REG
	LD	BC,VDC_ADDR
	OUT	(C),A
	LD	A,VAL
	LD	BC,VDC_DATA
	OUT	(C),A
	ENDM

; Select VDC register (address only)
VDC_SEL	MACRO	REG
	LD	A,REG
	LD	BC,VDC_ADDR
	OUT	(C),A
	ENDM

	END

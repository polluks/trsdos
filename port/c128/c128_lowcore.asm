;****************************************************************
;* Filename: C128_LOWCORE.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* Commodore 128 Low Memory Assignments for LSDOS 6.3.1L Port	*
;****************************************************************
;*								*
;* Replaces LOWCORE/ASM. Defines the C128 memory map for	*
;* LSDOS. Preserves the standard LSDOS layout where possible:	*
;*								*
;*   $0000-$00FF: Page 0 - RST vectors, system data		*
;*   $0100-$01FF: Page 1 - SVC table				*
;*   $0200-$12FF: Pages 2+ - DCBs, I/O Drivers			*
;*   $1300-$1CFF: SYSRES (BDOS)				*
;*   $1D00-$1DFF: Sector buffer				*
;*   $1E00-$3FFF: SYS1 (command interpreter)			*
;*   $4000-$7FFF: User program area				*
;*   $8000-$BFFF: Overlay/buffer area				*
;*   $C000-$FFFF: MMU I/O, system reserved			*
;*								*
;****************************************************************
	TITLE	<LOWCORE - C128 LSDOS 6.3 Port>
	PAGE

*GET	DOSDEFS
*GET	C128_EQU

;==============================================================================
; Internationalization
;==============================================================================
	IF	@GERMAN.AND.@FRENCH
	ERR	'Can''t do both French and German'
	ENDIF
	IF	@GERMAN.OR.@FRENCH
@INTL	EQU	-1
@USA	EQU	0
@HZ50	EQU	-1
	ELSE
@INTL	EQU	0
@USA	EQU	-1
@HZ50	EQU	0
	ENDIF

;==============================================================================
; Start of low memory
;==============================================================================
START$	EQU	0

; Include low core EQUs from SYSRES
FDDINT$	EQU	0EH			;Disk interrupt vector
PDRV$	EQU	1BH			;Current physical drive
TIMSL$	EQU	2BH			;Timer speed
TIMER$	EQU	2CH			;Timer counter
TIME$	EQU	TIMER$+1		;Time (SS:MM:HH)
DATE$	EQU	33H			;Date (YY/MM/DD packed)
INTVC$	EQU	3EH			;Interrupt vectors
FLGTAB$	EQU	6AH			;Flag table
CFLAG$	EQU	FLGTAB$+'C'-'A'
DFLAG$	EQU	FLGTAB$+'D'-'A'
IFLAG$	EQU	FLGTAB$+'I'-'A'
KFLAG$	EQU	FLGTAB$+'K'-'A'
MODOUT$	EQU	FLGTAB$+'M'-'A'
NFLAG$	EQU	FLGTAB$+'N'-'A'
OPREG$	EQU	FLGTAB$+'O'-'A'
RFLAG$	EQU	FLGTAB$+'R'-'A'
SFLAG$	EQU	FLGTAB$+'S'-'A'
VFLAG$	EQU	FLGTAB$+'V'-'A'
@KITSK	EQU	FLGTAB$+31

;==============================================================================
; Page 2 - Device Control Blocks (same layout as TRS-80)
;==============================================================================
	ORG	200H+START$

BUR$	DB	00H		;Bank use RAM
BAR$	DB	0FEH		;Bank available RAM
LBANK$	DB	20		;Dir cyl & logical bank
JCLCB$	DB	1,0,0		;Mini DCB for JCL gets
DVRHI$	DW	DVREND$		;Start of low I/O zone

; Keyboard DCB (*KI)
KIDCB$	DB	5		;Permit CTL, GET
	DW	KIDVR
	DB	0,0,0,'KI'

; Display DCB (*DO)
DODCB$	DB	7		;Permit CTL, PUT, GET
	DW	DODVR
	DB	0,0,0,'DO'

; Printer DCB (*PR)
PRDCB$	DB	6		;Permit CTL, PUT
	DW	PRDVR
	DB	0,0,0,'PR'

; Keyboard input DCB (*SI, routed to *KI)
SIDCB$	DB	15H		;Routed to *KI
	DW	KIDCB$
	DB	0DH,0,0,'SI'

; Display output DCB (*SO, routed to *DO)
SODCB$	DB	17H		;Routed to *DO
	DW	DODCB$
	DB	0FH,0,0,'SO'

; JCL DCB
JLDCB$	DB	0AH,0,0,0AH,0,0,'JL'
S1DCB$	EQU	$		;1st spare DCB
DCBKL$	EQU	JLDCB$&0FFH+1	;Non-killable DCBs

;==============================================================================
; Boot code and system startup
;==============================================================================
*GET	C128_BOOT

;==============================================================================
; Page 3 - System stack and Sysinfo section
;==============================================================================
STACK$	EQU	$-128		;Start stack 128 bytes low
PAUSE@	EQU	STACK$+2	;Where pause will be

;==============================================================================
; Page 4 - System info
;==============================================================================
	DB	63H		;OS version (6.3)
ZERO$	DB	0C9H		;Config on boot flag
MAXDAY$	EQU	$-1		;Max days per month
	DB	31,28,31,30,31,30,31,31,30,31,30,31
HIGH$	DS	2		;Highest available memory
PAKNAM$	DB	'C128-LSDOS63Level-',@DOSLVL

; Command line input buffer
INBUF$	DB	0DH		;Input buffer - 80 bytes
	DC	79,0

;==============================================================================
; System Drive Code Tables (C128 DCTs)
;==============================================================================
; The C128 supports up to 4 IEC drives (devices 8-11)
; DCT structure (10 bytes each):
;   +0: JP FDCDVR
;   +3: Drive flags (SDEN/DDEN, side select, step rate)
;   +4: Drive select code (IEC device address)
;   +5: Current track
;   +6: Reserved
;   +7: Allocation info (sectors/track, sectors/gran)
;   +8: More allocation
;   +9: Directory track

DCT$	EQU	$
	JP	FDCDVR		;Drive 0 (IEC device 8)
	DB	44H,8,0,39,17,3-1<5+6-1,20

	JP	FDCDVR		;Drive 1 (IEC device 9)
	DB	44H,9,0,39,17,3-1<5+6-1,20

	JP	FDCDVR		;Drive 2 (IEC device 10)
	DB	44H,10,0,39,17,3-1<5+6-1,20

	JP	FDCDVR		;Drive 3 (IEC device 11)
	DB	44H,11,0,39,17,3-1<5+6-1,20

	RET			;Drive 4 - not present
	DW	FDCRET
	DB	0,0,0,39,0,0,0

	RET			;Drive 5 - not present
	DW	FDCRET
	DB	0,0,0,39,0,0,0

	RET			;Drive 6 - not present
	DW	FDCRET
	DB	0,0,0,39,0,0,0

	RET			;Drive 7 - not present
	DW	FDCRET
	DB	0,0,0,39,0,0,0

;==============================================================================
; SYSINFO section
;==============================================================================
DSKTYP$	DB	-1		;0 = DATA, <>0 = SYS
	DB	0		;Reserved
DTPMT$	DB	0		;Date prompt at boot
TMPMT$	DB	0		;Time prompt at boot
RSTOR$	DB	0		;Suppress restores on boot
	DB	0		;Reserved
	DB	0		;Backup limit count

DAYTBL$	DB	'SunMonTueWedThuFriSat'
MONTBL$	DB	'JanFebMarAprMayJunJulAugSepOctNovDec'

;==============================================================================
; Load C128-specific drivers
;==============================================================================
*GET	C128_IODVR		;C128 I/O driver dispatcher
*GET	MULDIV			;16-bit MULT & DIV (Z80 - unchanged)
*GET	C128_CLOCKS		;C128 timer, RTC, bank switching

@$SYS	EQU	$

; Keyboard driver
*GET	C128_KIDVR

; Video driver (VDC 80-column)
*GET	C128_DODVR

; Printer driver
*GET	C128_PRDVR

; Floppy disk driver (IEC serial bus)
*GET	C128_FDCDVR

DVREND$	EQU	$		;End of low I/O zone
	IFGT	$,1200H+START$
	ERR	'Drivers overflow available RAM'
	ENDIF

	ORG	1300H+START$

@BYTEIO EQU	$

	END

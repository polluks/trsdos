;****************************************************************
;* Filename: C128_SYSRES.ASM					*
;* Rev Date: 07 May 96						*
;* Version : 1.0							*
;****************************************************************
;* C128 SYSRES - LS-DOS 6.x Resident OS Portion			*
;****************************************************************
;*								*
;* This is the MASTER BUILD for the C128 LSDOS port.		*
;* Assembles the complete SYSRES binary: RST vectors, flags,	*
;* SVC table, DCBs, boot code, device drivers, kernel routines,	*
;* system initialization, and sound driver.			*
;*								*
;* Assemble: vasmz80_oldstyle -Fbin -o sysres.bin		*
;*								*
;****************************************************************
	TITLE	'<SYSRES - C128 LS-DOS 6.3 Port>'

LF	EQU	10
CR	EQU	13

*GET	C128_EQU
*GET	DOSDEFS

;==============================================================================
; Internationalization and OS configuration
;==============================================================================
@PCERV	EQU	0
@USA	EQU	-1
@INTL	EQU	0
@HZ50	EQU	0

;==============================================================================
; System base equates
;==============================================================================
START$	EQU	0
@BYTEIO	EQU	1300H+START$
CRTBGN$	EQU	0		;VDC VRAM base (offset 0 in VDC address space)
; LBANK$ defined as code label at ORG 200H (page 2 DCBs)
; Flag table offset equates are defined by code labels in the flag table data below.
; No forward EQU definitions needed here.

	SUBTTL	'<System low core assignments>'

;==============================================================================
; Page 0 - RST vectors, low memory data
;==============================================================================
	ORG	0+START$

; RST 00 - IPL entry
@RST00	DI
	LD	A,00000001B
	OUT	(09CH),A	;Model 4 boot ROM toggle (kept for compatibility)

	DB	0,0,0		;CP/M emulator SVC

; RST 08
@RST08	RET
	DW	0
SVCRET$	DW	0		;Return from SVC
LSVC$	DB	0		;Last SVC executed
FDDINT$	DI			;NOP or DI for SMOOTH
	RET

; RST 10
@RST10	RET
	DW	0
USTOR$	DS	5		;User storage

; RST 18
@RST18	RET
	DW	0
PDRV$	DB	1		;Current physical drive
PHIGH$	DW	0		;Physical HIGH$
LOW$	DW	3000H		;Lowest usable memory

; RST 20
@RST20	RET
	DW	0
LDRV$	DB	0		;Current logical drive
JDCB$	DW	0		;Saved FCB pointer
JRET$	DW	0		;Saved I/O return address

; RST 28 - System SVC processor
@RST28	JP	RST28

TIMSL$	DB	55H		;Timer speed
TIMER$	DB	0		;RTC counter
TIME$	DC	3,0		;SS:MM:HH

; RST 30 - DEBUG call
@RST30	JP	@DEBUG

DATE$	DS	5		;YY/DD/MM packed

; RST 38 - Interrupt handler
@RST38	JP	RST38@

OSRLS$	DB	01H		;OS release

INTIM$	DB	0		;Interrupt latch image
INTMSK$	DB	2CH		;Mask for INTIM$
INTVC$	DW	RETINST		;Primary interrupt vectors
	DW	RETINST,RTCPROC,RETINST
	DW	RETINST,RETINST,RETINST,RETINST

TCB$	DS	24		;Task vectors

@NMI	DS	3		;NMI vector

OVRLY$	DB	0		;Current overlay

;==============================================================================
; Flag Table (same as TRS-80)
;==============================================================================
FLGTAB$	EQU	$
AFLAG$	DB	01		;AFLAG - start cylinder
BFLAG$	DB	00		;BFLAG
CFLAG$	DB	0		;Condition flag
DFLAG$	DB	00001010B	;DEV flag (SMOOTH,TYPE)
EFLAG$	DB	0		;Flag E
FEMSK$	DB	0		;Port FE mask
GFLAG$	DB	0		;Flag G
HFLAG$	DB	0		;Flag H
IFLAG$	EQU	$
	DB	0		;International flag (USA)
JFLAG$	DB	0		;Flag J
KFLAG$	DB	0		;Keyboard flag
LFLAG$	DB	00010001B	;Feature inhibit
MODOUT$	DB	78H		;Mode control
NFLAG$	DB	0		;Network flag
OPREG$	DB	87H		;Memory management image
PFLAG$	DB	0		;Printer flag
QFLAG$	DB	0		;Q flag
RFLAG$	DB	8		;FDC retry count
SFLAG$	DB	8		;System flag (FAST)
TFLAG$	DB	128		;Machine type (C128)
UFLAG$	DB	0		;Flag U
VFLAG$	DB	0		;Video flag
WRINT$	DB	4		;WRINTMASK image
XFLAG$	DB	0		;Flag X
YFLAG$	DB	11111111B	;All use new dates
ZFLAG$	DB	0		;Flag Z

	DB	SVCTAB$<-8	;MSB of SVC table
OSVER$	DB	63H		;OS version

@ICNFG	RET			;Config init
	DW	0
@KITSK	RET			;Keyboard task routine
	DW	0

; System file control block
SFCB$	DB	80H,0,0
	DW	SBUFF$
	DB	0
	DW	0,0,0,-1,0,-1,-1

DBGSV$	DS	32		;DEBUG save area

JFCB$	DC	3,0
	DW	SBUFF$
	DS	27

CFCB$	EQU	$		;Command interpreter FCB
CFGFCB$	DB	'CONFIG/SYS.CCC:0',3
	DS	15

;==============================================================================
; Page 1 - SVC Table (same as TRS-80)
;==============================================================================
SVCTAB$	EQU	$
	IFNE	$,100H
	ERR	'SVCTAB location violation!'
	ENDIF

MAXCOR$	EQU	2400H+START$
MINCOR$	EQU	3000H+START$

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

;==============================================================================
; File positioning routines
;==============================================================================
	SUBTTL	'<File positioning subroutines>'
*GET	FILPOSN
	PAGE

CORE$	DEFL	$

; C128 port: version strings displayed by sysinit code via VDC registers
; (direct video RAM ORGs not applicable to VDC - skipped here)

;==============================================================================
; System loader
;==============================================================================

;==============================================================================
; System loader
;==============================================================================
	SUBTTL	'<System Loader>'
*GET	LOADER

	SUBTTL	'<System front end & task processor>'
*GET	TASKER

	IFGT	$,1D00H+START$
	ERR	'SYSRES memory overflow!'
	ENDIF

CORE$	DEFL	$
	DC	1D00H-CORE$,0
	ORG	CORE$
	ORG	1D00H+START$

SBUFF$	EQU	$
	DS	256		;Page disk I/O buffer
DIRBUF$	EQU	MAXCOR$-256	;Another file buffer

;==============================================================================
; System initialization
;==============================================================================
OVERLAY	EQU	$
	SUBTTL	'<C128 System initialization routines>'
	PAGE
*GET	C128_SYSINIT

	SUBTTL	'<Misc. lowcore routines>'
	PAGE
*GET	SOUND			;Sound driver

;==============================================================================
; Sign-on message
;==============================================================================
	DB	'C128-LS-DOS 6.3.1L',0

	ORG	0036H
	DB	0

	END	OVERLAY

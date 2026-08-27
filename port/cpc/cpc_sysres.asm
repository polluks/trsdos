;****************************************************************
;* Filename: CPC_SYSRES.ASM					*
;* Rev Date: 11 May 26						*
;* Version : 1.0							*
;****************************************************************
;* CPC SYSRES - LS-DOS 6.x Resident OS Portion			*
;****************************************************************
;*								*
;* This is the MASTER BUILD for the CPC LSDOS port.		*
;* Assembles the complete SYSRES binary: RST vectors, flags,	*
;* SVC table, DCBs, boot code, device drivers, kernel routines,	*
;* system initialization.					*
;*								*
;* Assemble: vasmz80_oldstyle -Fbin -o sysres.bin		*
;*								*
;****************************************************************
	TITLE	'<SYSRES - CPC LS-DOS 6.3 Port>'

LF	EQU	10
CR	EQU	13

*GET	CPC_EQU
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
CRTBGN$	EQU	0

;==============================================================================
; Page 0 - RST vectors, low memory data
;==============================================================================
	ORG	0+START$

; RST 00 - IPL entry
@RST00	DI
	LD	A,00000001B
	OUT	(09CH),A

	DB	0,0,0

; RST 08
@RST08	RET
	DW	0
SVCRET$	DW	0
LSVC$	DB	0
FDDINT$	DI
	RET

; RST 10
@RST10	RET
	DW	0
USTOR$	DS	5

; RST 18
@RST18	RET
	DW	0
PDRV$	DB	1
PHIGH$	DW	0
LOW$	DW	3000H

; RST 20
@RST20	RET
	DW	0
LDRV$	DB	0
JDCB$	DW	0
JRET$	DW	0

; RST 28 - System SVC processor
@RST28	JP	RST28

TIMSL$	DB	55H
TIMER$	DB	0
TIME$	DC	3,0

; RST 30 - DEBUG call
@RST30	JP	@DEBUG

DATE$	DS	5

; RST 38 - Interrupt handler
@RST38	JP	RST38@

OSRLS$	DB	01H

INTIM$	DB	0
INTMSK$	DB	2CH
INTVC$	DW	RETINST
	DW	RETINST,RTCPROC,RETINST
	DW	RETINST,RETINST,RETINST,RETINST

TCB$	DS	24

@NMI	DS	3

OVRLY$	DB	0

;==============================================================================
; Flag Table
;==============================================================================
FLGTAB$	EQU	$
AFLAG$	DB	01
BFLAG$	DB	00
CFLAG$	DB	0
DFLAG$	DB	00001010B
EFLAG$	DB	0
FEMSK$	DB	0
GFLAG$	DB	0
HFLAG$	DB	0
IFLAG$	EQU	$
	DB	0
JFLAG$	DB	0
KFLAG$	DB	0
LFLAG$	DB	00010001B
MODOUT$	DB	78H
NFLAG$	DB	0
OPREG$	DB	87H
PFLAG$	DB	0
QFLAG$	DB	0
RFLAG$	DB	8
SFLAG$	DB	8
TFLAG$	DB	128
UFLAG$	DB	0
VFLAG$	DB	0
WRINT$	DB	4
XFLAG$	DB	0
YFLAG$	DB	11111111B
ZFLAG$	DB	0

	DB	SVCTAB$<-8
OSVER$	DB	63H

@ICNFG	RET
	DW	0
@KITSK	RET
	DW	0

; System file control block
SFCB$	DB	80H,0,0
	DW	SBUFF$
	DB	0
	DW	0,0,0,-1,0,-1,-1

DBGSV$	DS	32

JFCB$	DC	3,0
	DW	SBUFF$
	DS	27

CFCB$	EQU	$
CFGFCB$	DB	'CONFIG/SYS.CCC:0',3
	DS	15

;==============================================================================
; Page 1 - SVC Table
;==============================================================================
SVCTAB$	EQU	$
	IFNE	$,100H
	ERR	'SVCTAB location violation!'
	ENDIF

MAXCOR$	EQU	2400H+START$
MINCOR$	EQU	3000H+START$

;==============================================================================
; Page 2 - DCBs
;==============================================================================
	ORG	200H+START$

BUR$	DB	00H
BAR$	DB	0FEH
LBANK$	DB	20
JCLCB$	DB	1,0,0
DVRHI$	DW	DVREND$

; Keyboard DCB (*KI)
KIDCB$	DB	5
	DW	KIDVR
	DB	0,0,0,'KI'

; Display DCB (*DO)
DODCB$	DB	7
	DW	DODVR
	DB	0,0,0,'DO'

; Printer DCB (*PR)
PRDCB$	DB	6
	DW	PRDVR
	DB	0,0,0,'PR'

; Keyboard input DCB (*SI, routed to *KI)
SIDCB$	DB	15H
	DW	KIDCB$
	DB	0DH,0,0,'SI'

; Display output DCB (*SO, routed to *DO)
SODCB$	DB	17H
	DW	DODCB$
	DB	0FH,0,0,'SO'

; JCL DCB
JLDCB$	DB	0AH,0,0,0AH,0,0,'JL'
S1DCB$	EQU	$
DCBKL$	EQU	JLDCB$&0FFH+1

;==============================================================================
; Boot code
;==============================================================================
*GET	CPC_BOOT

;==============================================================================
; Page 3 - System stack
;==============================================================================
STACK$	EQU	$-128
PAUSE@	EQU	STACK$+2

;==============================================================================
; Page 4 - System info
;==============================================================================
	DB	63H
ZERO$	DB	0C9H
MAXDAY$	EQU	$-1
	DB	31,28,31,30,31,30,31,31,30,31,30,31
HIGH$	DS	2
PAKNAM$	DB	'LSDOS63Level-',@DOSLVL

; Command line input buffer
INBUF$	DB	0DH
	DC	79,0

;==============================================================================
; System Drive Code Tables (CPC DCTs)
;==============================================================================
DCT$	EQU	$
	JP	FDCDVR		;Drive 0
	DB	44H,0,0,39,9,3-1<5+6-1,20

	JP	FDCDVR		;Drive 1
	DB	44H,1,0,39,9,3-1<5+6-1,20

	RET			;Drive 2 - not present
	DW	FDCRET
	DB	0,0,0,39,0,0,0

	RET			;Drive 3 - not present
	DW	FDCRET
	DB	0,0,0,39,0,0,0

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
DSKTYP$	DB	-1
	DB	0
DTPMT$	DB	0
TMPMT$	DB	0
RSTOR$	DB	0
	DB	0
	DB	0

DAYTBL$	DB	'SunMonTueWedThuFriSat'
MONTBL$	DB	'JanFebMarAprMayJunJulAugSepOctNovDec'

;==============================================================================
; Load CPC-specific drivers
;==============================================================================
*GET	CPC_IODVR
*GET	MULDIV
*GET	CPC_CLOCKS

@$SYS	EQU	$

; Keyboard driver
*GET	CPC_KIDVR

; Video driver
*GET	CPC_DODVR

; Printer driver
*GET	CPC_PRDVR

; Floppy disk driver
*GET	CPC_FDCDVR

DVREND$	EQU	$
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

; No C128-specific strings needed

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
	DS	256
DIRBUF$	EQU	MAXCOR$-256

;==============================================================================
; System initialization
;==============================================================================
OVERLAY	EQU	$
	SUBTTL	'<CPC System initialization routines>'
	PAGE
*GET	CPC_SYSINIT

	SUBTTL	'<Misc. lowcore routines>'
	PAGE
*GET	SOUND

;==============================================================================
; Sign-on message
;==============================================================================
	DB	'LS-DOS 6.3.1L',0

	ORG	0036H
	DB	0

	END	OVERLAY

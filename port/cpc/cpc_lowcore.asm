;****************************************************************
;* Filename: CPC_LOWCORE.ASM					*
;* Rev Date: 11 May 26						*
;* Version : 1.0							*
;****************************************************************
;* Amstrad CPC Low Memory Assignments for LSDOS 6.3.1L Port	*
;****************************************************************
;*								*
;* $0000-$00FF: Page 0 - RST vectors, system data		*
;* $0100-$01FF: Page 1 - SVC table				*
;* $0200-$12FF: Pages 2+ - DCBs, I/O Drivers			*
;* $1300-$1CFF: SYSRES (BDOS)					*
;* $1D00-$1DFF: Sector buffer					*
;* $1E00-$3FFF: SYS1 (command interpreter)			*
;* $4000-$7FFF: User program area				*
;* $8000-$BFFF: Overlay/buffer area				*
;* $C000-$FFFF: Screen memory (CPC)				*
;*								*
;****************************************************************
	TITLE	<LOWCORE - CPC LSDOS 6.3 Port>
	PAGE

*GET	DOSDEFS
*GET	CPC_EQU

;==============================================================================
; Internationalization
;==============================================================================
	IF	@GERMAN.AND.@FRENCH
	ERR	'Cannot do both French and German'
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

; Low core EQUs from SYSRES
FDDINT$	EQU	0EH
PDRV$	EQU	1BH
TIMSL$	EQU	2BH
TIMER$	EQU	2CH
TIME$	EQU	TIMER$+1
DATE$	EQU	33H
INTVC$	EQU	3EH
FLGTAB$	EQU	6AH
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
; Page 2 - Device Control Blocks
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
; Stack and system info
;==============================================================================
STACK$	EQU	$-128
PAUSE@	EQU	STACK$+2

; Page 4 system info
	DB	63H
ZERO$	DB	0C9H
MAXDAY$	EQU	$-1
	DB	31,28,31,30,31,30,31,31,30,31,30,31
HIGH$	DS	2
PAKNAM$	DB	'LSDOS63Level-',@DOSLVL

; Command input buffer
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

; SYSINFO section
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

@SYS	EQU	$

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

@BYTEIO EQU	$

	END

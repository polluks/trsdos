;****************************************************************
;* Filename: CPC_BOOT.ASM					*
;* Rev Date: 11 May 26						*
;* Version : 1.0							*
;****************************************************************
;* Amstrad CPC Bootstrap for LSDOS 6.3.1L Port			*
;****************************************************************
;*								*
;* This code is a small stub at $4300 that gets called after	*
;* SYSRES is loaded. On CPC, SYSRES is loaded by the boot	*
;* sector (boot_cpc.asm), so this stub just passes control	*
;* to the SYSRES init at $1E38.					*
;*								*
;****************************************************************
	SUBTTL	'<CPC Bootstrap>'
	PAGE

;==============================================================================
; Entry point at $4300 (same location as C128 boot)
;==============================================================================
	ORG	4300H

BOOT
	; On CPC, SYSRES is already loaded to $0000 by boot_cpc.asm
	; Just initialize a few things and jump to sysinit

	DI

	; Initialize PPI for keyboard scanning
	LD	A,PPI_MODE_SET
	OUT	(PPI_CTRL),A

	; Initialize CRTC - mode 1 (40x25) with cursor
	CRTC_SET	CRTC_HTOTAL,	63
	CRTC_SET	CRTC_HDISP,	39
	CRTC_SET	CRTC_HSYNC,	46
	CRTC_SET	CRTC_VTOTAL,	38
	CRTC_SET	CRTC_VADJ,	9
	CRTC_SET	CRTC_VDISP,	25
	CRTC_SET	CRTC_VSYNC,	35
	CRTC_SET	CRTC_MAXSCAN,	7
	CRTC_SET	CRTC_CURSTART,	7
	CRTC_SET	CRTC_CUREND,	7
	CRTC_SET	CRTC_SAHIGH,	00H	;Screen base $C000: reg12 low = $C000/8 & 0xFF
	CRTC_SET	CRTC_SALOW,	18H	;reg13 high = ($C000/8)>>8 = $18
	CRTC_SET	CRTC_CURHIGH,	0
	CRTC_SET	CRTC_CURLOW,	0

	; Set GA mode 1 and enable interrupt
	GA_SET_MODE	GA_MODE_1
	; Set up basic ink colors
	LD	A,GA_INK_CMD!0!0<<4	;Pen 0 = black
	OUT	(GA_PORT),A
	LD	A,GA_INK_CMD!1!1<<4	;Pen 1 = blue
	OUT	(GA_PORT),A
	LD	A,GA_INK_CMD!2!9<<4	;Pen 2 = green
	OUT	(GA_PORT),A
	LD	A,GA_INK_CMD!3!15<<4	;Pen 3 = white
	OUT	(GA_PORT),A

	; For LSDOS mode 1 text: use pen 1 for text
	; Pen 1 = foreground, Pen 0 = background

	; Jump to SYSRES init
	JP	1E38H

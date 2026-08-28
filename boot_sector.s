; C128 TRSDOS 8502 Boot Sector - vasm6502_oldstyle syntax
; Uses proper C128 DISKHDR format: KERNAL auto-loads Z80BOOT PRG,
; then JSRs to our code which checks for 40/80 column mode via $D7,
; warns if in 40-col, then switches to Z80 mode. Before the Z80 switch
; we build the 64 TRS-80 2x3 block glyphs in the VDC downloadable alt
; charset, using the C128 KERNAL ROM VDC write routines.

	ORG	$0B00

; DISKHDR (C128 KERNAL BOOT_CALL format)
	DB	"CBM"		; $0B00-$0B02: signature
	DW	0		; $0B03-$0B04: load address (0 = no extra sectors)
	DB	0		; $0B05: bank (unused when addr=0)
	DB	0		; $0B06: blk# (0 = no extra sectors)

; Boot message (KERNAL displays "BOOTING <msg>...")
	DB	"TRSDOS",0	; $0B07-$0B0C: displayed during boot

; PRG filename to auto-load (KERNAL LOADs it to bank 0)
	DB	"Z80BOOT",0	; $0B0E-$0B15

; KERNAL / ROM VDC routines (write value in A to VDC):
;   VDCREG ($CDCC) - write .A to the register number in .X (with ready-wait)
;   VDCDATA ($CDCA) - write .A to VDC data register 31 (auto-increment)
CDCC	EQU	$CDCC		; ROM: VDC register write (X=reg, A=value)
CDCA	EQU	$CDCA		; ROM: VDC data write (A=value, fixed reg 31)
CHROUT	EQU	$FFD2		; KERNAL: output character in .A

; C128 hardware registers
Z80VEC	EQU	$FFEE		; Z80 boot vector (JP addr at $FFEE, Z80 starts here)
MMU_CFG	EQU	$FF00		; MMU bank config (write $3E for RAM bank 0 + I/O)
VDCCFG	EQU	$D505		; MMU mode config: write $B0 to select Z80 CPU
; $D7 bit 7 = 40/80 column mode: 0 => 40-col, 1 => 80-col
COL40_80 EQU	$D7		; Zero-page 40/80 column mode flag

; Z80 boot loader address (loaded to $8000 by KERNAL via Z80BOOT PRG)
Z80BOOT	EQU	$8000

; VDC register numbers and alt charset location
VDC_UAH	EQU	18		; update address high
VDC_UAL	EQU	19		; update address low
VDC_FONT	EQU	$3000		; downloadable alt charset block 3

; Code entry at $0B16: KERNAL JSRs here after loading Z80BOOT
	JSR	font_sel	; build TRS-80 2x3 block glyphs in VDC alt font (8502)
	BIT	COL40_80	; test bit 7 of $D7
	BMI	set_z80		; bit 7 set = 80-col; skip warning

	; In 40-column mode: warn user
	LDX	#$00
pmsg:	LDA	msg40,X
	BEQ	set_z80
	JSR	CHROUT
	INX
	BNE	pmsg

set_z80:
	SEI			; disable 8502 interrupts before Z80 switch

	LDA	#$C3		; JP opcode
	STA	Z80VEC		; $FFEE
	LDA	#<Z80BOOT
	STA	Z80VEC+1	; $FFEF
	LDA	#>Z80BOOT
	STA	Z80VEC+2	; $FFF0

	LDA	#$3E		; RAM bank 0, I/O visible (for Z80)
	STA	MMU_CFG		; $FF00

	LDA	#$B0		; bit 0 clear => Z80 takes over
	STA	VDCCFG		; $D505

	RTS

msg40:	DB	"SWITCH TO 80-COL MONITOR",13,27,"X",0

;==============================================================================
; 8502 VDC font: build the 64 TRS-80 2x3 block glyphs (codes 128-191) in the
; downloadable alt charset at VDC block 3. Runs entirely in 8502 mode before
; the switch to Z80. Each glyph is an 8x8 cell whose 6 sub-blocks (2 cols x
; 3 rows) mirror the TRS-80 pseudographics: value bit0..bit5 = TL,TR,ML,MR,
; BL,BR. Glyph value V (0..63) goes to char code 128+V, byte offset C*16.
; This uses local VDC write helpers (no ROM routine dependency); $D600/$D601
; are memory-mapped I/O available in the current bank config.
;=============================================================================
font_sel:
	; Point the 8563 update address at block 3, code 128 (offset 128*16=$800)
	LDX	#VDC_UAH	; reg 18 = update address high
	LDA	#>(VDC_FONT+(128*16))
	JSR	CDCC
	LDX	#VDC_UAL	; reg 19 = update address low
	LDA	#<(VDC_FONT+(128*16))
	JSR	CDCC

	; Generate 64 glyphs, value V = 0..63, writing 8 bytes each.
	; The update address auto-increments through VDC data register 31
	; ($CDCA writes to reg 31), so no re-select is needed mid-stream.
	LDX	#64		; glyph counter
	LDY	#0		; V = current glyph value (0..63)
font_glyph:
	TXA
	PHA			; save glyph counter
	STY	tval		; save V
	; Row 0 (scanlines 0-2): TL=bit0, TR=bit1
	LDX	#3
font_row0:
	TYA			; A = V
	AND	#%00000011
	TAY
	LDA	rowbyte,Y	; 2-bit pattern -> one byte
	JSR	CDCA		; write to VDC data reg 31 (auto-increments)
	LDY	tval
	DEX
	BNE	font_row0
	; Row 1 (scanlines 3-5): ML=bit2, MR=bit3
	LDX	#3
font_row1:
	TYA
	LSR
	LSR
	AND	#%00000011
	TAY
	LDA	rowbyte,Y
	JSR	CDCA
	LDY	tval
	DEX
	BNE	font_row1
	; Row 2 (scanlines 6-7): BL=bit4, BR=bit5
	LDX	#2
font_row2:
	TYA
	LSR
	LSR
	LSR
	LSR
	AND	#%00000011
	TAY
	LDA	rowbyte,Y
	JSR	CDCA
	LDY	tval
	DEX
	BNE	font_row2
	INY			; next glyph value
	PLA
	TAX
	DEX			; next glyph
	BNE	font_glyph
	RTS

tval:	DB	0		; glyph value scratch

; Convert a 2-bit column-pair (00/01/10/11) into an 8x8 scanline byte.
; Left column = bits 7-4 ($F0), right column = bits 3-0 ($0F).
rowbyte:
	DB	$00,$F0,$0F,$FF

; C128 TRSDOS 8502 Boot Sector - vasm6502_oldstyle syntax
; Uses proper C128 DISKHDR format: KERNAL auto-loads Z80BOOT PRG,
; then JSRs to our code which checks for 40/80 column mode via $D7,
; warns if in 40-col, then switches to Z80 mode. Before the Z80 switch
; we build the 64 TRS-80 2x3 block glyphs in the VDC downloadable alt
; charset, writing the VDC directly via memory-mapped I/O $D600/$D601.
; Code entry at $0B16: KERNAL JSRs here after loading Z80BOOT.

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

CHROUT	EQU	$FFD2		; KERNAL: output character in .A
; VDC (8563) memory-mapped I/O: $D600 = register select, $D601 = data
VDC_ADDR EQU	$D600		; VDC register select
VDC_DATA EQU	$D601		; VDC register data

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
	BIT	COL40_80	; test bit 7 of $D7
	BMI	skipprint	; bit 7 set = 80-col; skip warning

	; In 40-column mode: warn the user via the KERNAL ROM CHROUT ($FFD2).
	; The trailing ESC X switches to 80-column mode once the message is shown.
	LDX	#$00
pmsg:	LDA	msg40,X
	BEQ	skipprint
	JSR	CHROUT
	INX
	BNE	pmsg

skipprint:
	JSR	font_sel	; build TRS-80 2x3 block glyphs in VDC alt font (8502)

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
; The VDC is written directly via memory-mapped I/O $D600/$D601 (no ROM
; routine calls -- KERNAL ROM at $C000 may not be mapped during boot).
;=============================================================================
font_sel:
	; Point the 8563 update address at block 3, code 128 (offset 128*16=$800)
	LDA	#VDC_UAH	; reg 18 = update address high
	STA	VDC_ADDR
	LDA	#>(VDC_FONT+(128*16))
	STA	VDC_DATA
	LDA	#VDC_UAL	; reg 19 = update address low
	STA	VDC_ADDR
	LDA	#<(VDC_FONT+(128*16))
	STA	VDC_DATA
	LDA	#31		; reg 31 = auto-increment data register
	STA	VDC_ADDR

	; Generate 64 glyphs, value V = 0..63, writing 8 bytes each.
	LDX	#64		; glyph counter
	LDY	#0		; V = current glyph value (0..63)
font_glyph:
	STY	tval		; save V
	; Row 0 (scanlines 0-2): TL=bit0, TR=bit1
	TYA
	AND	#%00000011
	TAY
	LDA	rowbyte,Y	; 2-bit pattern -> one byte
	STA	VDC_DATA	; write to VDC (auto-increments)
	STA	VDC_DATA
	STA	VDC_DATA
	; Row 1 (scanlines 3-5): ML=bit2, MR=bit3
	LDY	tval
	TYA
	LSR
	LSR
	AND	#%00000011
	TAY
	LDA	rowbyte,Y
	STA	VDC_DATA
	STA	VDC_DATA
	STA	VDC_DATA
	; Row 2 (scanlines 6-7): BL=bit4, BR=bit5
	LDY	tval
	TYA
	LSR
	LSR
	LSR
	LSR
	AND	#%00000011
	TAY
	LDA	rowbyte,Y
	STA	VDC_DATA
	STA	VDC_DATA
	INY			; next glyph value
	DEX
	BNE	font_glyph
	RTS

tval:	DB	0		; glyph value scratch

; Convert a 2-bit column-pair (00/01/10/11) into an 8x8 scanline byte.
; Left column = bits 7-4 ($F0), right column = bits 3-0 ($0F).
rowbyte:
	DB	$00,$F0,$0F,$FF

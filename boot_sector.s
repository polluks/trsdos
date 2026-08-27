; C128 TRSDOS 8502 Boot Sector - vasm6502_oldstyle syntax
; Uses proper C128 DISKHDR format: KERNAL auto-loads Z80BOOT PRG,
; then JSRs to our code which checks for 40/80 column mode via $D7,
; warns if in 40-col, then switches to Z80 mode.

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

; KERNAL vectors
CHROUT	EQU	$FFD2

; C128 hardware registers
Z80VEC	EQU	$FFEE		; Z80 boot vector (JP addr at $FFEE, Z80 starts here)
MMU_CFG	EQU	$FF00		; MMU bank config (write $3E for RAM bank 0 + I/O)
VDCCFG	EQU	$D505		; MMU mode config: write $B0 to select Z80 CPU
COL40_80 EQU	$D7		; Zero-page 40/80 column mode flag (bit 7: 0=40, 1=80)

; Z80 boot loader address (loaded to $8000 by KERNAL via Z80BOOT PRG)
Z80BOOT	EQU	$8000

; Code entry at $0B16: KERNAL JSRs here after loading Z80BOOT
	BIT	COL40_80	; test bit 7 of $D7
	BPL	set_z80		; if clear, already 80-col

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

	LDA	#$B0		; bit 0 clear → Z80 takes over
	STA	VDCCFG		; $D505

	RTS

msg40:	DB	"SWITCH TO 80-COL MONITOR",13,27,"X",0

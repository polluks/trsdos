; C128 TRSDOS 6502 Boot Sector - vasm6502_oldstyle syntax
; Uses proper C128 DISKHDR format: KERNAL auto-loads Z80BOOT PRG,
; then JSRs to our code which checks for 40/80 column mode,
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
I_80COL	EQU	$FF5F
CHROUT	EQU	$FFD2

; C128 hardware registers
Z80VEC	EQU	$FFF0		; Z80 boot vector (set JP Z80BOOT here)
VDCCFG	EQU	$D505		; 80-col VDC config (VDC enable, base addr, etc.)

; Z80 boot loader address (loaded to $8000 by KERNAL via Z80BOOT PRG)
Z80BOOT	EQU	$8000

; Code entry at $0B16: KERNAL JSRs here after loading Z80BOOT
	CLC			; read current 80-column mode
	JSR	I_80COL		; A=0 = 40-col, A!=0 = 80-col
	BNE	set_z80

	; In 40-column mode: warn user then switch to 80-col
	LDX	#$00		; message index
pmsg:	LDA	msg40,X
	BEQ	set_z80
	JSR	CHROUT
	INX
	BNE	pmsg

set_z80:
	LDA	#$C3
	STA	Z80VEC
	LDA	#<Z80BOOT
	STA	Z80VEC+1
	LDA	#>Z80BOOT
	STA	Z80VEC+2

	LDA	#$B0
	STA	VDCCFG

	RTS

msg40:	DB	"SWITCH TO 80-COL MONITOR",13,27,"X",0

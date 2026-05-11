; C128 TRSDOS 6502 Boot Sector - vasm6502_oldstyle syntax
; Uses proper C128 DISKHDR format: KERNAL auto-loads Z80BOOT PRG,
; then JSRs to our code which switches to Z80 mode.

	ORG	$0B00

; DISKHDR (C128 KERNAL BOOT_CALL format)
	DB	"CBM"		; $0B00-$0B02: signature
	DW	0		; $0B03-$0B04: load address (0 = no extra sectors)
	DB	0		; $0B05: bank (unused when addr=0)
	DB	0		; $0B06: blk# (0 = no extra sectors)

; Boot message (KERNAL displays "BOOTING Z80BOOT...")
	DB	"TRSDOS",0	; $0B07-$0B0C: displayed as "BOOTING TRSDOS..."

; PRG filename to auto-load (KERNAL LOADs it to bank 0)
	DB	"Z80BOOT",0	; $0B0E-$0B15

; Code entry at $0B16: KERNAL JSRs here after loading Z80BOOT
	; Set Z80 boot vector at $FFF0: JP $4300
	LDA	#$C3
	STA	$FFF0
	LDA	#$00
	STA	$FFF1
	LDA	#$43
	STA	$FFF2

	; Enable Z80 clock, configuration 0
	LDA	#$B0
	STA	$D505

	RTS

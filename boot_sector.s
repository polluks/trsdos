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

; Code entry at $0B16: KERNAL JSRs here after loading Z80BOOT
	CLC			; read current 80-column mode
	JSR	I_80COL		; A=0 = 40-col, A!=0 = 80-col
	BNE	set_z80

	; In 40-column mode: warn user then switch to 80-col
	LDX	#$00		; message index
pmsg:	LDA	msg40,X
	BEQ	pmsg_e
	JSR	CHROUT
	INX
	BNE	pmsg

pmsg_e:	SEC			; set 80-column mode
	LDA	#$01
	JSR	I_80COL

set_z80:
	LDA	#$C3
	STA	$FFF0
	LDA	#$00
	STA	$FFF1
	LDA	#$43
	STA	$FFF2

	LDA	#$B0
	STA	$D505

	RTS

msg40:	DB	"SWITCH TO 80-COL MODE",13,0

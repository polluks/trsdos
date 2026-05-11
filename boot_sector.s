; C128 TRSDOS 6502 Boot Sector - vasm6502_oldstyle syntax
; Loads Z80 boot code via KERNAL LOAD, switches to Z80 mode

	ORG	$0B00

; C128 autoboot signature (required by KERNAL bootstrap)
	DB	'C','B','M'

; Jump past filename data to start of code
	JMP	start

; Filename for Z80 boot loader (padded to 16 bytes with $A0)
fname:
	DB	'Z80BOOT'
	DB	$A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0

; KERNAL entry: JSRs here after verifying "CBM" at $0B00
start:
	; SETLFS(1, 8, 0)
	LDA	#$01
	LDX	#$08
	LDY	#$00
	JSR	$FFBA

	; SETNAM(fname, 7)
	LDA	#<fname
	LDX	#>fname
	LDY	#$07
	JSR	$FFBD

	; LOAD Z80BOOT to address in PRG header ($4300)
	LDA	#$00
	LDX	#<buf
	LDY	#>buf
	JSR	$FFD5
	BCS	error

	; Set Z80 boot vector at $FFF0: JP $4300
	LDA	#$C3
	STA	$FFF0
	LDA	#$00
	STA	$FFF1
	LDA	#$43
	STA	$FFF2

	; Enable Z80 (config 0, Z80 clock on)
	LDA	#$B0
	STA	$D505

error:
	RTS

; Load address buffer (LOAD writes file header address here)
buf:
	DB	0, 0

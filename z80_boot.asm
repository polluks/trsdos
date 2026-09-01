; Z80 Boot Loader for C128 TRSDOS
; The 8502 KERNAL already loaded the full flat SYSRES into its final
; destination ($0000-$59AF) via the boot-sector extra-sector mechanism
; (see boot_sector.s, staging at $0C00). No Z80 disk I/O is needed.
; This stub only: sets up an 80x25 VDC display, copies SYSRES from the
; $0C00 staging area down to $0000, then jumps to SYSRES init at $1E38.
; vasm oldstyle syntax

;==============================================================================
; C128 Hardware Definitions
;==============================================================================
CIA2_PRA    EQU  0DD00H
CIA2_DDRA   EQU  0DD02H
CIA2_DDRB   EQU  0DD03H
CIA2_PRB    EQU  0DD01H

VDC_ADDR    EQU  0D600H
VDC_DATA    EQU  0D601H
VDC_HTOTAL  EQU  0
VDC_HDISP   EQU  1
VDC_HSYNC   EQU  2
VDC_VTOTAL  EQU  3
VDC_VADJ    EQU  4
VDC_VDISP   EQU  5
VDC_VSYNC   EQU  6
VDC_ROWSCAN EQU  9
VDC_CURSTART EQU 10
VDC_CUREND  EQU  11
VDC_SAHIGH  EQU  12
VDC_SALOW   EQU  13
VDC_CHRCOUNT EQU 30
VDC_MEMREFR EQU  31
VDC_ATTR    EQU  36
VDC_UPDHIGH EQU  18
VDC_UPDLOW  EQU  19

; System entry point (after SBUFF$ buffer, DI instruction)
SYSINIT     EQU  1E38H

; SYSRES is staged by the KERNAL at $0C00 (boot sector load address) and
; must be moved to $0000-$59AF. 22960 bytes = $59B0.
SYSRES_STAGE EQU 0C00H
SYSRES_SIZE  EQU 59B0H

;==============================================================================
; ORG at boot entry point
;==============================================================================
    ORG  8000H

;==============================================================================
; BOOT Entry - called from 8502 bootstrap via JP $8000 at $FFEE
;==============================================================================
BOOT:
    DI
    LD   SP,5FFFH
    LD   A,3EH
    LD   ($FF00),A

    LD   A,0FFH
    LD   BC,CIA2_PRA
    OUT  (C),A
    LD   BC,CIA2_PRB
    OUT  (C),A

    ; CIA2 DDRA: bits 3(ATN)/4(CLK OUT)/5(DATA OUT) = output, bits 6/7 = input
    LD   A,03FH
    LD   BC,CIA2_DDRA
    OUT  (C),A

    ; stage 4 marker: VIC border = RED  -> proves Z80 runs our $8000 code
    LD   A,2
    LD   BC,0D020H      ; VIC border color
    OUT  (C),A

    CALL VDC_INIT
    ; stage 5 marker: VIC border = CYAN -> VDC_INIT returned
    LD   A,3
    LD   BC,0D020H
    OUT  (C),A

    CALL VDC_CLS
    ; stage 6 marker: VIC border = WHITE -> VDC_CLS returned
    LD   A,1
    LD   BC,0D020H
    OUT  (C),A

    LD   HL,0
    CALL VDC_SET_ADDR
    LD   HL,BOOTMSG
    CALL VDC_PUTS

    ; stage 7 marker: VIC border = YELLOW -> BOOTMSG written to VDC VRAM
    LD   A,7
    LD   BC,0D020H
    OUT  (C),A

    LD   HL,80
    CALL VDC_SET_ADDR
    LD   HL,COPYMSG
    CALL VDC_PUTS

    ; stage 8 marker: VIC border = GREEN -> about to copy SYSRES into place
    LD   A,5
    LD   BC,0D020H
    OUT  (C),A

    ; Copy SYSRES backward ($65AF -> $59AF) to avoid clobbering the still
    ; needed high source bytes (source $0C00-$65AF overlaps destination).
    LD   HL,SYSRES_STAGE+SYSRES_SIZE-1
    LD   DE,SYSRES_SIZE-1
    LD   BC,SYSRES_SIZE
    LDDR

    ; stage 9 marker: VIC border = BLUE -> SYSRES copied, jumping to init
    LD   A,6
    LD   BC,0D020H
    OUT  (C),A

    JP   SYSINIT

;==============================================================================
; VDC: Wait for ready (bit 7 of status register)
;==============================================================================
VDC_WAIT:
    PUSH AF
vw_loop:
    LD   BC,VDC_ADDR
    IN   A,(C)
    AND  80H
    JR   Z,vw_loop
    POP  AF
    RET

;==============================================================================
; VDC: Initialize 80x25 text mode
; In Z80 mode, I/O at $D000-$DFFF (incl. VDC) MUST use OUT (C),A / IN A,(C)
; Must poll VDC ready bit before each register data write
;==============================================================================
VDC_INIT:
    LD   A,VDC_HTOTAL
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,126
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_HDISP
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,80
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_HSYNC
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,98
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_VTOTAL
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,33
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_VADJ
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,18
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_VDISP
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,25
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_VSYNC
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,34
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_ROWSCAN
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,7
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_CURSTART
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,6
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_CUREND
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,7
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_SAHIGH
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    XOR  A
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_SALOW
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    XOR  A
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_CHRCOUNT
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,80
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_MEMREFR
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,19
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_ATTR
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,20H
    LD   BC,VDC_DATA
    OUT  (C),A
    RET

;==============================================================================
; VDC: Clear screen
;==============================================================================
VDC_CLS:
    LD   A,VDC_UPDHIGH
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    XOR  A
    LD   BC,VDC_DATA
    OUT  (C),A
    LD   A,VDC_UPDLOW
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    XOR  A
    LD   BC,VDC_DATA
    OUT  (C),A
    LD   A,VDC_MEMREFR
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   HL,2000
    LD   A,' '
cls_l:
    CALL VDC_WAIT
    LD   BC,VDC_DATA
    OUT  (C),A
    DEC  HL
    LD   A,H
    OR   L
    JR   NZ,cls_l
    RET

;==============================================================================
; VDC: Set internal write address (HL = offset)
;==============================================================================
VDC_SET_ADDR:
    LD   A,VDC_UPDHIGH
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,H
    LD   BC,VDC_DATA
    OUT  (C),A
    LD   A,VDC_UPDLOW
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    LD   A,L
    LD   BC,VDC_DATA
    OUT  (C),A
    LD   A,VDC_MEMREFR
    LD   BC,VDC_ADDR
    OUT  (C),A
    CALL VDC_WAIT
    RET

;==============================================================================
; VDC: Put null-terminated string
;==============================================================================
VDC_PUTS:
    LD   A,(HL)
    OR   A
    RET  Z
    CALL VDC_WAIT
    LD   BC,VDC_DATA
    OUT  (C),A
    INC  HL
    JR   VDC_PUTS

;==============================================================================
; Data
;==============================================================================
BOOTMSG:
    DB   'C128 TRSDOS v0.2.0 - Z80 Boot',0
COPYMSG:
    DB   'Decompressing SYSRES...',0

    END

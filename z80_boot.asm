; Z80 Boot Loader for C128 TRSDOS
; KERNAL loads Z80BOOT PRG to $8000 (ORG), 8502 sets Z80VEC JP $8000
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

MMU_RAM0    EQU  0FF01H
MMU_RAM1    EQU  0FF02H
MMU_RAM2    EQU  0FF03H
MMU_RAM3    EQU  0FF04H
MMU_LOAD    EQU  0FF05H

SECTBUF     EQU  5000H

; System entry point (after SBUFF$ buffer, at DI instruction)
SYSINIT     EQU  1E38H

; Number of sectors to load (boot_sysres.bin = 22887 bytes = 90 sectors)
SYSRES_SECS EQU  90

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

    LD   HL,160
    CALL VDC_SET_ADDR
    LD   HL,LOADMSG
    CALL VDC_PUTS

    CALL LOAD_SYSTEM
    OR   A
    JR   NZ,load_err

    LD   HL,320
    CALL VDC_SET_ADDR
    LD   HL,OKMSG
    CALL VDC_PUTS

    JP   SYSINIT

load_err:
    LD   HL,320
    CALL VDC_SET_ADDR
    LD   HL,RD_ERR
    CALL VDC_PUTS

HALT_LOOP:
    JR   HALT_LOOP

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
; IEC: Send byte on serial bus (A = byte to send)
; Clobbers: AF, B
;==============================================================================
IEC_BYTE_OUT:
    PUSH BC
    PUSH DE
    LD   D,8
    LD   H,A
bo_l:
    RR   H
    JR   NC,bo_z
    ; Send 1: DATA high
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR  01H
    OUT  (C),A
    JR   bo_clk
bo_z:
    ; Send 0: DATA low
    LD   BC,CIA2_PRA
    IN   A,(C)
    AND  0FEH
    OUT  (C),A
bo_clk:
    ; Pulse CLOCK low then high
    AND  0FDH
    OUT  (C),A
    NOP
    NOP
    NOP
    OR  02H
    OUT  (C),A
    DEC  D
    JR   NZ,bo_l
    ; Release DATA
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR  01H
    OUT  (C),A
    POP  DE
    POP  BC
    RET

;==============================================================================
; IEC: Receive byte from serial bus (byte returned in A)
; Clobbers: AF, B, L
;==============================================================================
IEC_BYTE_IN:
    PUSH BC
    PUSH HL
    ; DATA = input (clear bit 0 of DDR)
    LD   BC,CIA2_DDRA
    IN   A,(C)
    AND  0FEH
    OUT  (C),A
    ; Pull DATA high
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR  01H
    OUT  (C),A
    LD   L,0
    LD   D,8
bi_l:
    ; Wait for CLOCK low (bit 4)
    LD   BC,CIA2_PRA
bi_wt:
    IN   A,(C)
    AND  10H
    JR   NZ,bi_wt
    ; Read DATA_IN (bit 3)
    IN   A,(C)
    AND  08H
    RRCA
    RRCA
    RRCA
    RRCA
    RR   L
    ; CLOCK high (acknowledge)
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR  02H
    OUT  (C),A
    ; Wait for CLOCK high
bi_wt2:
    IN   A,(C)
    AND  10H
    JR   Z,bi_wt2
    DEC  D
    JR   NZ,bi_l
    ; Restore DATA as output
    LD   BC,CIA2_DDRA
    IN   A,(C)
    OR  01H
    OUT  (C),A
    LD   A,L
    POP  HL
    POP  BC
    RET

;==============================================================================
; IEC: Write decimal byte A (0-99) as ASCII to (HL)
;==============================================================================
WRITE_DEC:
    PUSH AF
    LD   C,0
wd_l:
    CP   10
    JR   C,wd_d
    SUB  10
    INC  C
    JR   wd_l
wd_d:
    LD   B,A
    LD   A,C
    OR   A
    JR   Z,wd_u
    ADD  A,'0'
    LD   (HL),A
    INC  HL
wd_u:
    LD   A,B
    ADD  A,'0'
    LD   (HL),A
    INC  HL
    POP  AF
    RET

;==============================================================================
; IEC: Read one sector from disk into (HL)
; D = track (1-based), E = sector (0-based), HL = destination
; Returns: A = 0 success, NZ = error
;==============================================================================
IEC_READ_SECTOR:
    PUSH HL

    ; Build U1 command string at SECTBUF
    LD   HL,SECTBUF
    LD   (HL),'U'
    INC  HL
    LD   (HL),'1'
    INC  HL
    LD   (HL),':'
    INC  HL
    LD   (HL),'0'
    INC  HL
    LD   (HL),' '
    INC  HL
    LD   A,D
    CALL WRITE_DEC
    LD   (HL),' '
    INC  HL
    LD   A,E
    INC  A
    CALL WRITE_DEC
    LD   (HL),0

    ; ATN low => LISTEN 8, secondary 15
    LD   BC,CIA2_PRA
    IN   A,(C)
    AND  0FBH
    OUT  (C),A
    NOP
    LD   A,048H
    CALL IEC_BYTE_OUT
    LD   A,00FH
    CALL IEC_BYTE_OUT
    ; ATN high
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR  04H
    OUT  (C),A

    ; Send command string
    LD   HL,SECTBUF
cmd_l:
    LD   A,(HL)
    OR   A
    JR   Z,cmd_end
    CALL IEC_BYTE_OUT
    INC  HL
    JR   cmd_l
cmd_end:
    ; UNLISTEN
    LD   A,03FH
    CALL IEC_BYTE_OUT

    ; ATN low => TALK 8, secondary 0
    LD   BC,CIA2_PRA
    IN   A,(C)
    AND  0FBH
    OUT  (C),A
    NOP
    LD   A,068H
    CALL IEC_BYTE_OUT
    LD   A,060H
    CALL IEC_BYTE_OUT
    ; ATN high
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR  04H
    OUT  (C),A

    ; Read 256 bytes to destination
    POP  HL
    LD   B,0
rd_l:
    PUSH BC
    CALL IEC_BYTE_IN
    POP  BC
    LD   (HL),A
    INC  HL
    DJNZ rd_l

    ; UNTALK
    LD   A,05FH
    CALL IEC_BYTE_OUT

    XOR  A
    RET

;==============================================================================
; LOAD_SYSTEM - load flat SYSRES image from disk to $0000-$42FF
;==============================================================================
LOAD_SYSTEM:
    LD   D,2           ; start track
    LD   E,0           ; start sector
    LD   HL,0          ; destination = $0000
    LD   B,SYSRES_SECS ; sectors to load

load_l:
    PUSH HL
    PUSH BC
    PUSH DE
    CALL IEC_READ_SECTOR
    JR   NZ,load_fail
    POP  DE
    POP  BC
    POP  HL

    ; Advance: HL += 256
    LD   A,H
    ADD  A,1
    LD   H,A

    ; Advance sector
    INC  E
    LD   A,E
    CP   21          ; sectors per track (tracks 1-17)
    JR   C,load_next
    LD   E,0
    INC  D

load_next:
    DJNZ load_l
    XOR  A
    RET

load_fail:
    POP  DE
    POP  BC
    POP  HL
    LD   A,1
    RET

;==============================================================================
; Data
;==============================================================================
BOOTMSG:
    DB   'C128 TRSDOS v0.2.0 - Z80 Boot',0
LOADMSG:
    DB   'Loading SYSRES...',0
OKMSG:
    DB   'Booting system...',0
RD_ERR:
    DB   'ERR: Disk read failed',0

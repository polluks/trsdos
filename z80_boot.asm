; Z80 Boot Loader for C128 TRSDOS
; Loaded to $4300 by 6502 boot sector, jumped to via JP $4300
; vasm oldstyle syntax

;==============================================================================
; C128 Hardware Definitions
;==============================================================================
CIA2_PRA    EQU  0DD00H
CIA2_DDRA   EQU  0DD00H
CIA2_DDRB   EQU  0DD01H
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

;==============================================================================
; ORG at boot entry point
;==============================================================================
    ORG  4300H

;==============================================================================
; BOOT Entry - called from 6502 bootstrap via JP $4300
;==============================================================================
BOOT:
    DI
    XOR  A
    LD   (MMU_RAM0),A
    LD   (MMU_RAM1),A
    LD   (MMU_RAM2),A
    LD   (MMU_RAM3),A
    LD   (MMU_LOAD),A

    LD   A,0FFH
    LD   (CIA2_DDRA),A
    LD   (CIA2_DDRB),A
    LD   (CIA2_PRA),A
    LD   (CIA2_PRB),A

    CALL VDC_INIT
    CALL VDC_CLS

    LD   HL,0
    CALL VDC_SET_ADDR
    LD   HL,BOOTMSG
    CALL VDC_PUTS

    LD   HL,160
    CALL VDC_SET_ADDR
    LD   HL,LOADMSG
    CALL VDC_PUTS

    CALL LOAD_SYSTEM

    LD   HL,320
    CALL VDC_SET_ADDR
    LD   HL,OKMSG
    CALL VDC_PUTS

HALT_LOOP:
    JR   HALT_LOOP

;==============================================================================
; VDC: Initialize 80x25 text mode
;==============================================================================
VDC_INIT:
    LD   A,VDC_HTOTAL
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,126
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_HDISP
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,80
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_HSYNC
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,98
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_VTOTAL
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,33
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_VADJ
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,18
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_VDISP
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,25
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_VSYNC
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,34
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_ROWSCAN
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,7
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_CURSTART
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,6
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_CUREND
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,7
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_SAHIGH
    LD   BC,VDC_ADDR
    OUT  (C),A
    XOR  A
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_SALOW
    LD   BC,VDC_ADDR
    OUT  (C),A
    XOR  A
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_CHRCOUNT
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,80
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_MEMREFR
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,19
    LD   BC,VDC_DATA
    OUT  (C),A

    LD   A,VDC_ATTR
    LD   BC,VDC_ADDR
    OUT  (C),A
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
    XOR  A
    LD   BC,VDC_DATA
    OUT  (C),A
    LD   A,VDC_UPDLOW
    LD   BC,VDC_ADDR
    OUT  (C),A
    XOR  A
    LD   BC,VDC_DATA
    OUT  (C),A
    LD   A,VDC_MEMREFR
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   HL,2000
    LD   A,' '
cls_l:
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
    LD   A,H
    LD   BC,VDC_DATA
    OUT  (C),A
    LD   A,VDC_UPDLOW
    LD   BC,VDC_ADDR
    OUT  (C),A
    LD   A,L
    LD   BC,VDC_DATA
    OUT  (C),A
    LD   A,VDC_MEMREFR
    LD   BC,VDC_ADDR
    OUT  (C),A
    RET

;==============================================================================
; VDC: Put null-terminated string
;==============================================================================
VDC_PUTS:
    LD   A,(HL)
    OR   A
    RET  Z
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
    LD   B,8
bo_l:
    RRCA
    PUSH AF
    LD   A,(CIA2_PRA)
    AND  0FEH
    JR   NC,bo_z
    OR  01H
bo_z:
    LD   (CIA2_PRA),A
    AND  0FDH
    LD   (CIA2_PRA),A
    NOP
    NOP
    NOP
    OR  02H
    LD   (CIA2_PRA),A
    POP  AF
    DJNZ bo_l
    LD   A,(CIA2_PRA)
    OR  01H
    LD   (CIA2_PRA),A
    POP  BC
    RET

;==============================================================================
; IEC: Receive byte from serial bus (byte returned in A)
; Clobbers: AF, B, L
;==============================================================================
IEC_BYTE_IN:
    PUSH BC
    PUSH HL
    LD   A,(CIA2_DDRA)
    AND  0FEH
    LD   (CIA2_DDRA),A
    LD   A,(CIA2_PRA)
    OR  01H
    LD   (CIA2_PRA),A
    LD   L,0
    LD   B,8
bi_l:
    LD   A,(CIA2_PRA)
    AND  10H
    JR   NZ,bi_l
    LD   A,(CIA2_PRA)
    AND  08H
    RRCA
    RRCA
    RRCA
    RRCA
    RR   L
    LD   A,(CIA2_PRA)
    OR  02H
    LD   (CIA2_PRA),A
bi_w:
    LD   A,(CIA2_PRA)
    AND  10H
    JR   Z,bi_w
    DJNZ bi_l
    LD   A,(CIA2_DDRA)
    OR  01H
    LD   (CIA2_DDRA),A
    LD   A,L
    POP  HL
    POP  BC
    RET

;==============================================================================
; Write A (0-99) as decimal ASCII to (HL), HL advanced past digits
; Preserves A, clobbers B, C
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
; IEC: Read a sector from disk
; D = track (1-based), E = sector (0-based), HL = destination buffer
; Returns: A = 0 success, NZ = error (with error code in A)
;==============================================================================
IEC_READ_SECTOR:
    PUSH HL
    PUSH DE
    PUSH BC
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
    POP  DE
    PUSH DE
    LD   A,D
    CALL WRITE_DEC
    LD   (HL),' '
    INC  HL
    LD   A,E
    INC  A
    CALL WRITE_DEC
    LD   (HL),0

    LD   A,(CIA2_PRA)
    AND  0FBH
    LD   (CIA2_PRA),A
    NOP
    LD   A,048H
    CALL IEC_BYTE_OUT
    LD   A,00FH
    CALL IEC_BYTE_OUT
    LD   A,(CIA2_PRA)
    OR  04H
    LD   (CIA2_PRA),A

    LD   HL,SECTBUF
    LD   B,0
    LD   A,(HL)
    OR   A
    JR   Z,no_cmd
cmd_l:
    LD   A,(HL)
    CALL IEC_BYTE_OUT
    INC  HL
    DJNZ cmd_l
    LD   A,(HL)
    OR   A
    JR   NZ,cmd_l
no_cmd:
    LD   A,03FH
    CALL IEC_BYTE_OUT

    LD   A,(CIA2_PRA)
    AND  0FBH
    LD   (CIA2_PRA),A
    NOP
    LD   A,068H
    CALL IEC_BYTE_OUT
    LD   A,060H
    CALL IEC_BYTE_OUT
    LD   A,(CIA2_PRA)
    OR  04H
    LD   (CIA2_PRA),A

    POP  HL
    PUSH HL
    LD   B,0
rd_l:
    PUSH BC
    CALL IEC_BYTE_IN
    POP  BC
    LD   (HL),A
    INC  HL
    DJNZ rd_l

    LD   A,05FH
    CALL IEC_BYTE_OUT

    XOR  A
    POP  BC
    POP  DE
    POP  HL
    RET

;==============================================================================
; LOAD_SYSTEM - read TRSDOS GAT + directory, display status
;==============================================================================
LOAD_SYSTEM:
    LD   HL,SECTBUF
    LD   D,17
    LD   E,0
    CALL IEC_READ_SECTOR
    JR   NZ,load_err

    LD   HL,240
    CALL VDC_SET_ADDR
    LD   HL,GAT_OK
    CALL VDC_PUTS

    LD   HL,SECTBUF
    LD   B,16
    LD   HL,248
    CALL VDC_SET_ADDR
    LD   HL,SECTBUF
    LD   B,16
hex_l:
    LD   A,(HL)
    PUSH HL
    PUSH BC
    CALL VDC_PUTHEX
    POP  BC
    POP  HL
    INC  HL
    DJNZ hex_l

    LD   HL,SECTBUF
    LD   D,17
    LD   E,1
    CALL IEC_READ_SECTOR
    JR   NZ,load_err

    LD   HL,400
    CALL VDC_SET_ADDR
    LD   HL,DIR_OK
    CALL VDC_PUTS

    LD   HL,SECTBUF
    LD   B,8
    LD   HL,408
    CALL VDC_SET_ADDR
    LD   HL,SECTBUF
    LD   B,8
name_l:
    LD   A,(HL)
    PUSH HL
    PUSH BC
    LD   BC,VDC_DATA
    OUT  (C),A
    POP  BC
    POP  HL
    INC  HL
    DJNZ name_l

    RET

load_err:
    LD   HL,240
    CALL VDC_SET_ADDR
    LD   HL,RD_ERR
    CALL VDC_PUTS
    RET

;==============================================================================
; VDC: Write A as two hex digits at current cursor
;==============================================================================
VDC_PUTHEX:
    PUSH AF
    RRCA
    RRCA
    RRCA
    RRCA
    CALL v_nib
    POP  AF
v_nib:
    AND  0FH
    ADD  A,'0'
    CP   '9'+1
    JR   C,v_n2
    ADD  A,7
v_n2:
    LD   BC,VDC_DATA
    OUT  (C),A
    RET

;==============================================================================
; Data
;==============================================================================
BOOTMSG:
    DB   'C128 TRSDOS v0.1 - Z80 Boot Loader',0
LOADMSG:
    DB   'Loading TRSDOS...',0
OKMSG:
    DB   'Boot complete - system loaded',0
GAT_OK:
    DB   'GAT: OK ',0
DIR_OK:
    DB   'DIR: OK ',0
RD_ERR:
    DB   'ERR: Read failed',0

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

; CIA2 PRA IEC serial bit mapping (active-low via 7406, per C64/C128 hardware):
;   bit3 = ATN OUT, bit4 = CLOCK OUT, bit5 = DATA OUT,
;   bit6 = CLOCK IN, bit7 = DATA IN
IEC_ATN     EQU  08H
IEC_CLKOUT  EQU  10H
IEC_DATOUT  EQU  20H
IEC_CLKIN   EQU  40H
IEC_DATIN   EQU  80H
; Active-low clear masks
IEC_NOT_ATN     EQU  0F7H
IEC_NOT_CLKOUT  EQU  0EFH
IEC_NOT_DATOUT  EQU  0DFH

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

    LD   HL,160
    CALL VDC_SET_ADDR
    LD   HL,LOADMSG
    CALL VDC_PUTS

    ; stage 8 marker: VIC border = GREEN -> LOADMSG printed, LOAD_SYSTEM about to start
    LD   A,5
    LD   BC,0D020H
    OUT  (C),A

    CALL LOAD_SYSTEM
    OR   A
    JR   NZ,load_err

    ; stage 9 marker: VIC border = BLUE -> LOAD_SYSTEM returned success
    LD   A,6
    LD   BC,0D020H
    OUT  (C),A

    LD   HL,320
    CALL VDC_SET_ADDR
    LD   HL,OKMSG
    CALL VDC_PUTS

    JP   SYSINIT

load_err:
    ; stage 10 marker: VIC border = GREY -> disk read error path
    LD   A,15
    LD   BC,0D020H
    OUT  (C),A

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
; IEC: Send byte on serial bus (A = byte to send), bit-banged on CIA2 PRA
;       Correct PA3-7 mapping: b3 ATN, b4 CLK OUT, b5 DATA OUT,
;       b6 CLK IN, b7 DATA IN. Active-low via 7406 (PRA bit=1 => line high).
;       Port of C64 KERNAL $ED40 (serial transmit). LSB first.
; Entry: A = byte. Called with ATN already asserted/appropriate for frame.
; Exit:  A preserved, CF clear on success. Clobbers: B, D, HL
;==============================================================================
IEC_BYTE_OUT:
    PUSH BC
    PUSH HL
    LD   H,A               ; byte to send
    ; set DATA out high (release DATA): clear bit5
    LD   BC,CIA2_PRA
    IN   A,(C)
    AND  IEC_NOT_DATOUT
    OUT  (C),A
    ; device not present check: DATA should be low (listener holding)
    IN   A,(C)
    RLCA                 ; carry = DATA IN (bit7)
    JR   C,bo_notpres      ; DATA high -> no listener
    ; set CLOCK out high (release): clear bit4
    IN   A,(C)
    AND  IEC_NOT_CLKOUT
    OUT  (C),A
    ; wait for DATA high (device released -> ready for data)
bo_wait:
    LD   BC,CIA2_PRA
    IN   A,(C)
    RLCA
    JR   NC,bo_wait        ; loop while DATA low
    ; 8-bit transmit loop, LSB first
    LD   D,8
bo_bit:
    ; self-sync: wait for DATA high (device ready for next bit)
bo_sync:
    LD   BC,CIA2_PRA
    IN   A,(C)
    RLCA                 ; carry = DATA IN
    JR   NC,bo_sync        ; loop while DATA low
    ; set DATA out to bit: SRL H (carry = bit0), bit=1 => DATA high, bit=0 => DATA low
    SRL  H
    JR   C,bo_one
    ; bit=0: DATA low -> set bit5
    IN   A,(C)
    OR   IEC_DATOUT
    OUT  (C),A
    JR   bo_clk
bo_one:
    ; bit=1: DATA high -> clear bit5
    IN   A,(C)
    AND  IEC_NOT_DATOUT
    OUT  (C),A
bo_clk:
    ; set CLOCK high (clear bit4): bit valid on rising edge
    LD   BC,CIA2_PRA
    IN   A,(C)
    AND  IEC_NOT_CLKOUT
    OUT  (C),A
    ; ~2us delay @2MHz
    NOP
    NOP
    NOP
    NOP
    ; release DATA + set CLOCK low (set bit4): advance to next bit
    LD   BC,CIA2_PRA
    IN   A,(C)
    AND  IEC_NOT_DATOUT
    OR   IEC_CLKOUT
    OUT  (C),A
    DEC  D
    JR   NZ,bo_bit
    ; frame ack: wait for DATA low (device pulls DATA low to acknowledge)
bo_ack:
    LD   BC,CIA2_PRA
    IN   A,(C)
    RLCA
    JR   C,bo_ack          ; loop while DATA high
    JP   bo_ok
bo_notpres:
    POP  HL
    POP  BC
    SCF
    RET
bo_ok:
    POP  HL
    POP  BC
    OR   A                 ; CF clear = success
    RET

;==============================================================================
; IEC: Receive byte from serial bus (byte returned in A). Bit-banged on CIA2 PRA.
;       Port of C64 KERNAL $EE13 (serial receive / ACPTR). LSB first via RR H.
;       Talker (drive) drives CLOCK/DATA; we sample DATA on CLOCK rising edge.
; Entry: (TALK bus already turned around by caller)
; Exit:  A = received byte. Clobbers: B, H, L
;==============================================================================
IEC_BYTE_IN:
    PUSH BC
    ; set CLOCK out high (release CLOCK so drive can drive it): clear bit4
    LD   BC,CIA2_PRA
    IN   A,(C)
    AND  IEC_NOT_CLKOUT
    OUT  (C),A
    ; wait for CLOCK IN high (drive released its clock)
in_w1:
    LD   BC,CIA2_PRA
    IN   A,(C)
    BIT  6,A              ; bit6 = CLOCK IN
    JR   Z,in_w1          ; loop while CLOCK low
    ; set DATA out high (release DATA = ready to receive): clear bit5
    IN   A,(C)
    AND  IEC_NOT_DATOUT
    OUT  (C),A
    LD   B,8
    LD   H,0              ; receive byte accumulator
in_bit:
    ; wait for CLOCK IN high (data valid on rising edge)
in_sh:
    LD   BC,CIA2_PRA
    IN   A,(C)
    BIT  6,A
    JR   Z,in_sh          ; loop while CLOCK low
    ; sample DATA IN
    IN   A,(C)
    RLCA                ; carry = DATA IN (bit7)
    RR   H                ; shift bit into LSB-first accumulator
    ; wait for CLOCK IN low (drive moved to next bit)
in_sl:
    LD   BC,CIA2_PRA
    IN   A,(C)
    BIT  6,A
    JR   NZ,in_sl         ; loop while CLOCK high
    DEC  B
    JR   NZ,in_sh
    ; frame ack: set DATA out low (pull DATA low): set bit5
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR   IEC_DATOUT
    OUT  (C),A
    LD   A,H
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

    ; --- LISTEN 8, secondary 15 (under ATN) ---
    ; stage 12 marker: dark grey -> about to assert ATN for LISTEN
    LD   A,12
    LD   BC,0D020H
    OUT  (C),A
    ; assert ATN (set bit3) and wait for device ATN-ack (DATA low)
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR   IEC_ATN
    OUT  (C),A
rs_atnack1:
    LD   BC,CIA2_PRA
    IN   A,(C)
    RLCA
    JR   C,rs_atnack1     ; wait while DATA high (until device pulls low)
    LD   A,028H           ; LISTEN device 8
    CALL IEC_BYTE_OUT
    LD   A,00FH           ; secondary 15 (command channel)
    CALL IEC_BYTE_OUT
    ; release ATN (clear bit3)
    LD   BC,CIA2_PRA
    IN   A,(C)
    AND  IEC_NOT_ATN
    OUT  (C),A
    ; stage 13 marker: light green -> LISTEN cmd accepted, command string next
    LD   A,13
    LD   BC,0D020H
    OUT  (C),A

    ; --- send U1 command string (data phase, ATN high) ---
    LD   HL,SECTBUF
rs_cmdl:
    LD   A,(HL)
    OR   A
    JR   Z,rs_cmde
    CALL IEC_BYTE_OUT
    INC  HL
    JR   rs_cmdl
rs_cmde:
    ; --- UNLISTEN $3F (under ATN) ---
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR   IEC_ATN
    OUT  (C),A
rs_atnack2:
    LD   BC,CIA2_PRA
    IN   A,(C)
    RLCA
    JR   C,rs_atnack2
    LD   A,03FH           ; UNLISTEN
    CALL IEC_BYTE_OUT
    ; release ATN
    LD   BC,CIA2_PRA
    IN   A,(C)
    AND  IEC_NOT_ATN
    OUT  (C),A

    ; stage 14 marker: light blue -> command string + UNLISTEN done, TALK next
    LD   A,14
    LD   BC,0D020H
    OUT  (C),A
    ; stage 11 marker: VIC border = CYAN -> U1 command sent, TALK/data-read about to start
    LD   A,3
    LD   BC,0D020H
    OUT  (C),A

    ; --- TALK 8, secondary 0 (under ATN) ---
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR   IEC_ATN
    OUT  (C),A
rs_atnack3:
    LD   BC,CIA2_PRA
    IN   A,(C)
    RLCA
    JR   C,rs_atnack3
    LD   A,068H           ; TALK device 8
    CALL IEC_BYTE_OUT
    LD   A,060H           ; secondary 0
    CALL IEC_BYTE_OUT

    ; --- TALK bus turnaround: release ATN, DATA low, CLK high, wait CLK low ---
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR   IEC_DATOUT       ; DATA low
    AND  IEC_NOT_ATN   ; ATN high
    AND  IEC_NOT_CLKOUT; CLOCK high (release)
    OUT  (C),A
rs_ttloop:
    IN   A,(C)
    BIT  6,A
    JR   NZ,rs_ttloop     ; wait until CLOCK IN low

    ; --- read 256 bytes ---
    POP  HL
    LD   B,0
rs_rdl:
    PUSH BC
    CALL IEC_BYTE_IN
    POP  BC
    LD   (HL),A
    INC  HL
    DJNZ rs_rdl

    ; --- UNTALK $5F (under ATN) ---
    LD   BC,CIA2_PRA
    IN   A,(C)
    OR   IEC_ATN
    OUT  (C),A
rs_atnack4:
    LD   BC,CIA2_PRA
    IN   A,(C)
    RLCA
    JR   C,rs_atnack4
    LD   A,05FH           ; UNTALK
    CALL IEC_BYTE_OUT
    ; release ATN
    LD   BC,CIA2_PRA
    IN   A,(C)
    AND  IEC_NOT_ATN
    OUT  (C),A

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

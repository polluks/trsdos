; CPC TRSDOS Boot Sector
; Loaded by CPC firmware from T0S0 to $0000, max 512 bytes
; vasm oldstyle syntax
;
; Uses Exomizer3 self-extracting compressed SYSRES:
; - Packed blob at T0S1+ loaded to $6000
; - Blob = [decruncher 148 bytes][compressed SYSRES N bytes]
; - Decruncher copied to $BE70, decompresses from buffer to $0000
; - Jumps to $1E38 on completion

;==============================================================================
; CPC Hardware I/O
;==============================================================================
FDC_DATA    EQU 0FB7EH
FDC_STATUS  EQU 0FB7FH
FDC_CTRL    EQU 0FB7AH     ; drive/motor control

; DECR_SIZE and BLOB_SECS passed via vasm -D from Makefile

;==============================================================================
; Boot sector loaded here
;==============================================================================
    ORG 0

START:
    DI
    LD  SP,0BFFFH

    ; Init FDC
    CALL FDC_INIT

    ; Load packed blob to $6000
    ; BLOB_SECS sectors x 512 bytes
    LD  HL,6000H       ; destination buffer
    LD  D,0            ; track
    LD  E,1            ; sector (1-based)
    LD  B,BLOB_SECS    ; sector count
load_l:
    PUSH BC
    PUSH DE
    PUSH HL
    CALL FDC_READ
    JR  NZ,ERR
    POP  HL
    POP  DE
    POP  BC
    ; HL += 512
    LD  A,H
    ADD A,2
    LD  H,A
    ; Advance sector (wrap at 9/track)
    INC E
    LD  A,E
    CP  10
    JR  C,load_n
    LD  E,1
    INC D
load_n:
    DJNZ load_l

    ; Copy decruncher from blob to $BE70
    LD  HL,6000H
    LD  DE,0BE70H
    LD  BC,DECR_SIZE
    LDIR

    ; Set up and run decruncher
    ; HL = compressed data start (right after decruncher in blob)
    LD  HL,6000H + DECR_SIZE
    LD  DE,0           ; decompress to $0000
    LD  SP,0BFFFH      ; stack in safe high RAM
    LD  BC,1E38H
    PUSH BC            ; return address (firmware exit + SYSRES init)
    JP  0BE70H

ERR:
    JR  ERR

;==============================================================================
; FDC: Initialize drive
;==============================================================================
FDC_INIT:
    LD  BC,FDC_CTRL
    LD  A,00000011B     ; motor on, drive A selected
    OUT (C),A
    LD  HL,0
dly:
    DEC HL
    LD  A,H
    OR  L
    JR  NZ,dly
    RET

;==============================================================================
; FDC: Wait for ready to send (RQM=1, DIO=0)
;==============================================================================
FDC_WAIT_SEND:
    LD  BC,FDC_STATUS
ws_l:
    IN  A,(C)
    AND 0C0H
    CP  80H
    JR  NZ,ws_l
    RET

;==============================================================================
; FDC: Wait for ready to receive (RQM=1, DIO=1)
;==============================================================================
FDC_WAIT_RECV:
    LD  BC,FDC_STATUS
wr_l:
    IN  A,(C)
    AND 0C0H
    CP  0C0H
    JR  NZ,wr_l
    RET

;==============================================================================
; FDC: Send byte in A
;==============================================================================
FDC_SEND:
    PUSH BC
    CALL FDC_WAIT_SEND
    LD  BC,FDC_DATA
    OUT (C),A
    POP  BC
    RET

;==============================================================================
; FDC: Receive byte in A
;==============================================================================
FDC_RECV:
    CALL FDC_WAIT_RECV
    LD  BC,FDC_DATA
    IN  A,(C)
    RET

;==============================================================================
; FDC: Sense interrupt status (clears pending interrupt from SEEK)
;==============================================================================
FDC_SENSE:
    LD  A,08H          ; SENSE INTERRUPT STATUS
    CALL FDC_SEND
    CALL FDC_RECV      ; ST0
    CALL FDC_RECV      ; PCN
    RET

;==============================================================================
; FDC_READ: Read one 512-byte sector
; D = track, E = sector (1-based), HL = destination buffer
; Returns: Z = success, NZ = error
;==============================================================================
FDC_READ:
    PUSH HL

    ; SEEK to track
    LD  A,0FH          ; SEEK command
    CALL FDC_SEND
    LD  A,0            ; head 0, drive 0
    CALL FDC_SEND
    LD  A,D            ; track
    CALL FDC_SEND
    ; Wait for seek (simple delay)
    LD  HL,0
sk2_dly:
    DEC HL
    LD  A,H
    OR  L
    JR  NZ,sk2_dly
    ; Sense interrupt
    CALL FDC_SENSE

    POP  HL            ; restore destination

    ; Read Data command (MFM)
    LD  A,46H          ; Read Data, MFM
    CALL FDC_SEND
    LD  A,D            ; track (C)
    CALL FDC_SEND
    XOR  A             ; head 0 (H)
    CALL FDC_SEND
    LD  A,E            ; sector (R)
    CALL FDC_SEND
    LD  A,2            ; N=2 (512 bytes/sector)
    CALL FDC_SEND
    LD  A,9            ; EOT (9 sectors/track)
    CALL FDC_SEND
    LD  A,02AH         ; GPL (gap)
    CALL FDC_SEND
    LD  A,0FFH         ; DTL (unused when N!=0)
    CALL FDC_SEND

    ; Read 512 data bytes
    LD  B,0            ; 256 iterations
rd1:
    CALL FDC_RECV
    LD  (HL),A
    INC  HL
    DJNZ rd1
    LD  B,0
rd2:
    CALL FDC_RECV
    LD  (HL),A
    INC  HL
    DJNZ rd2

    ; Read 7 result bytes
    CALL FDC_RECV      ; ST0
    CALL FDC_RECV      ; ST1
    CALL FDC_RECV      ; ST2
    CALL FDC_RECV      ; C (track)
    CALL FDC_RECV      ; H (head)
    CALL FDC_RECV      ; R (sector)
    CALL FDC_RECV      ; N (size)

    XOR  A             ; success
    RET

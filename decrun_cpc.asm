; Exomizer 3 Z80 forward decoder, speed 0
; mapbase=$BE00, reuse=0, literals=0
; vasm oldstyle syntax
;
; Entry: HL = compressed data, DE = dest addr
;   (caller must push $1E38 before jp entry)

MAPBASE EQU  0BE00H

    ORG  0BE70H        ; decruncher code entry at $BE70
                        ; (right after decruncher header space)

    LD   IY,MAPBASE + 112  ; IY = $BE70 (table base)
    LD   A,128
    LD   B,52
    PUSH DE
    CP   A
init:
    LD   C,16
    JR   NZ,get4
    LD   DE,1
    LD   IXL,C
get4:
    CALL getbit
    RL   C
    JR   NC,get4
    LD   (IY-112),C
    PUSH HL
    LD   HL,1
    DEFB 210        ; JP NC, next2 (falls through if C=1)
setbit:
    ADD  HL,HL
    DEC  C
    JR   NZ,setbit
    LD   (IY-60),E
    LD   (IY-8),D
    ADD  HL,DE
    EX   DE,HL
    INC  IYL
    POP  HL
    DEC  IXL
    DJNZ init
    POP  DE
litcop:
    LDI
mloop:
    CALL getbit
    JR   C,litcop
    LD   C,111         ; 112-1
getind:
    CALL getbit
    INC  C
    JR   NC,getind
    RET  M
    PUSH DE
    LD   IYL,C
    CALL getpair
    PUSH DE
    LD   BC,672        ; 512+160
    DEC  E
    JR   Z,goit
    DEC  E
    LD   BC,1168       ; 1024+144
    JR   Z,goit
    LD   C,128
goit:
    CALL getbits
    LD   IYL,C
    ADD  IY,DE
    CALL getpair
    POP  BC
    EX   (SP),HL
    PUSH HL
    SBC  HL,DE
    POP  DE
    LDIR
    POP  HL
    JR   mloop
getpair:
    LD   B,(IY-112)
    CALL getbits
    EX   DE,HL
    LD   C,(IY-60)
    LD   B,(IY-8)
    ADD  HL,BC
    EX   DE,HL
    RET
getbits:
    LD   DE,0
gbcont:
    DEC  B
    RET  M
    CALL getbit
    RL   E
    RL   D
    JR   gbcont
getbit:
    ADD  A,A
    RET  NZ
    LD   A,(HL)
    INC  HL
    ADC  A,A
    RET

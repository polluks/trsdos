# Agent Context

## Project Goal

Create a bootable D64 disk image for C128 that loads TRSDOS via a 6502→Z80 boot chain using the IEC serial bus.

## Build Commands

```
make              # full build: assemble + D64
make clean        # remove build/ and D64
make distclean    # clean + remove dist zip
make dist         # create distribution zip
make -C /tmp/vasm SYNTAX=oldstyle CPU=6502   # build 6502 assembler
make -C /tmp/vasm SYNTAX=oldstyle CPU=z80    # build Z80 assembler
```

## Boot Chain

1. C128 KERNAL (6502) loads track 1 sector 0 → $0400 (boot_sector.s, 248 bytes)
2. 6502 boot reads 4 sectors from IEC → $4300-$46FF
3. 6502 writes $05 to $FF05 → Z80 mode, JP $4300
4. Z80 boot (921 bytes) initializes VDC, CIA#2, reads GAT+directory

## Key Files

| File | Role |
|------|------|
| `boot_sector.s` | 6502 boot sector, loaded to $0400, reads Z80 code from disk |
| `z80_boot.asm` | Z80 boot loader at $4300, IEC I/O, VDC display |
| `make_d64.py` | Creates 35-track D64 with proper BAM |
| `Makefile` | Auto-builds vasm, assembles, creates D64 + dist zip |

## IEC Protocol (CIA#2 at $DD00)

### Byte Out (IEC_BYTE_OUT)
```
RRCA → bit 0 to carry
LD A,(CIA2_PRA) → current PRA value
AND #$FE → clear DATA bit 0
JR NC,store → if carry=0, keep cleared
OR #$01 → set DATA bit 0 if carry=1
store: LD (CIA2_PRA),A → set DATA line
AND #$FD → clear CLOCK bit 1
LD (CIA2_PRA),A → CLOCK low
NOP×3 → delay
OR #$02 → set CLOCK bit 1
LD (CIA2_PRA),A → CLOCK high
DJNZ → next bit
LD A,(CIA2_PRA): OR #$01: LD (CIA2_PRA),A → release DATA
```

### Byte In (IEC_BYTE_IN)
```
DATA line = input, pull-up high
LOOP 8 bits:
  wait CLOCK_IN low (PRA bit 4=0)
  read DATA_IN bit (PRA bit 3)
  A = PRA & $08, then 4× RRCA → carry = bit 3 value
  RR L → carry into bit 7 of L (LSB-first accumulation)
  CLOCK high (acknowledge)
  wait CLOCK_IN high
restore DATA as output
A = L (received byte)
```

### U1 Command (read sector)
```
ATN low → $28 (LISTEN 8), $0F (secondary 15)
ATN high → "U1:0 <track_dec> <sector_1based_dec>"
$3F (UNLISTEN)
ATN low → $68 (TALK 8), $60 (secondary 0)
ATN high → read 256 bytes
$5F (UNTALK)
```

## VDC (8563) Display

- Registers accessed via $D600/$D601
- Reg 18/19: update address (VRAM offset)
- Reg 31: auto-increment data register
- 80×25 text = 2000 bytes
- Clear: set addr=0, select reg31, write 2000 spaces

## D64 Format

35-track, 174848 bytes (683 sectors × 256 bytes):
- Track 1: sectors 17-21 (21 sectors/track for tracks 1-17)
- Track 18: directory track with BAM at sector 0
- BAM: 4 bytes/track (free count + 3-byte bitmap)

Layout in D64 file:
- Track 1: offset 0 (21 sectors × 256 = 5376 bytes)
- Track 2: offset 5376
- ...
- Track 18: offset (17 tracks × 21 sectors × 256) = 91392

## Architecture Rules

- 6502 boot sector: max 256 bytes, no branches in IEC tight loops
- Z80 boot code loaded to $4300, max 1024 bytes (4 sectors)
- Sector buffer at $5000
- Keep IEC timing compatible with 1541/1571 drives (~2µs per NOP at 2MHz Z80)
- All hardware access via CIA#2 ($DD00) for IEC, VDC ($D600/$D601) for display
- Vasm oldstyle syntax throughout (not MRAS)
- Z80 uses `OR` not `ORA`, `AND` not `ANA`

## Build Status

### SYSRES Assembly — SUCCESS
- `bash conv/build_sysres.sh` assembles 16 port/repo source files via `conv/mras2vasm.pl` + `conv/build_sysres.sh` post-processing
- Output: `build/sysres/sysres.bin` (29156 bytes, 6 vasm sections)
- Section layout:
  | ORG | Bytes | Addresses | Content |
  |-----|-------|-----------|---------|
  | 0 | 256 | 0-FF | Page 0 (vectors, flags, system data) |
  | 200H | 229 | 200-2E4 | DCBs |
  | 100H | 7168 | 100-1CFF | SVC table + loader code + tasker |
  | 1300H | 1697 | 1300-19A1 | File positioning routines |
  | 1D00H | 1604 | 1D00-2343 | SBUFF_S + sysinit + sound |
  | 4300H | 5092 | 4300-56E3 | Boot code + IEC driver |

### Post-processing fixes applied
- `mras2vasm.pl`: `$?` label nearest-match resolution, numeric alias emission, `@`→`_`, `$`→`_S`, MRAS directives, `<` shift operator, DC/DM conversion, MACRO param stripping
- `build_sysres.sh`: ORG label→constant replacement, VDC macro params, CORE_S redefinition, duplicate macro removal, GETADR rename, `?`→`_Q` labels, JR→JP conversion, 8-bit wrap fix, missing EQU stubs, section overlap avoidance

### Blocker History (resolved)
- ~~$? forward-reference resolution~~ — fixed by scope-independent nearest-match
- ~~$? numeric label prefix identity~~ — fixed by alias label emission
- ~~_L_0_446 undefined~~ — fixed by `\s`→`(?:\s|$)` regex in alias emission
- ~~Section overlap: 1D00H SBUFF_S ↔ 1E00H sysinit~~ — fixed by commenting out ORG 1E00H
- ~~Section overlap: ORG 0036H with ORG 0~~ — fixed by commenting out ORG 0036H

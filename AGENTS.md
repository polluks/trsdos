# Agent Context

## Project Goal

Create bootable disk images for C128 (D64) and Amstrad CPC (DSK) that load TRSDOS.

## Build Commands

```
make              # full build: assemble + D64
make clean        # remove build/ and D64
make distclean    # clean + remove dist zip
make dist         # create distribution zip
make -C /tmp/vasm SYNTAX=oldstyle CPU=6502   # build vasm 6502 from source
make -C /tmp/vasm SYNTAX=oldstyle CPU=z80    # build vasm Z80 from source
```

## Release

- v0.2.1 (2026-05-12): D64 + DSK assets on GitHub releases. HELLO files TRSDOS-only.
- v0.2.0: HELLO/CMD auto-run, CPC starting point.
- v0.1.0: Basic C128 boot chain works.

## Boot Chain

1. C128 KERNAL (6502) loads track 1 sector 0 → $0B00 (boot_sector.s, 90 bytes)
2. KERNAL auto-loads Z80BOOT PRG from T1S1 → $8000 (load addr in PRG header)
3. Boot sector detects 40/80-col mode, warns if 40-col, writes JP $8000 to Z80VEC ($FFF0)
4. Boot sector writes $05 to $FF05 → Z80 mode, CPU executes JP $8000
5. Z80 boot (805 bytes at $8000) initializes VDC 80×25 text, CIA#2 for IEC
6. Z80 boot loads full flat SYSRES from T2S0–T6S4 (89 sectors) to $0000–$58F8
7. Z80 boot jumps to SYSRES init at $1E38

## Key Files

| File | Role |
|------|------|
| `boot_sector.s` | 6502 boot sector, loaded to $0B00, KERNAL auto-loads Z80BOOT PRG |
| `z80_boot.asm` | Z80 boot loader at $8000 (loaded as Z80BOOT PRG), IEC I/O, VDC display |
| `boot_cpc.asm` | CPC boot sector (Z80, T0S0), FDC loads SYSRES blob |
| `decrun_cpc.asm` | Exomizer3 Z80 decruncher at $BE70 (148 bytes) |
| `make_d64.py` | Creates 35-track D64 with proper BAM, stores full SYSRES |
| `make_dsk.py` | Creates 40-track CPC DSK with boot + compressed SYSRES |
| `Makefile` | Auto-builds vasm, assembles, creates D64/DSK + dist zip |

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
- Z80 boot code loaded to $8000 via PRG, max 1024 bytes (4 sectors)
- Sector buffer at $5000
- Keep IEC timing compatible with 1541/1571 drives (~2µs per NOP at 2MHz Z80)
- All hardware access via CIA#2 ($DD00) for IEC, VDC ($D600/$D601) for display
- Vasm oldstyle syntax throughout (not MRAS)
- Z80 uses `OR` not `ORA`, `AND` not `ANA`

## D64 Sector Layout

Current sector usage:
- Track 1: S0=boot sector, S1-S4=Z80BOOT PRG (805 bytes to $8000)
- Track 2: S0-S20=SYSRES (21 sectors)
- Track 3: S0-S20=SYSRES (21 sectors)
- Track 4: S0-S20=SYSRES (21 sectors)
- Track 5: S0-S20=SYSRES (21 sectors)
- Track 6: S0-S4=SYSRES (5 sectors, 89 total)
- Track 7: S0=HELLO/CMD (TRSDOS-only, no CBM dir entry), S1-S3=HELLO/ASM
- Track 18: S0=BAM, S1=directory (only Z80BOOT visible)

SYSRES in memory: $0000-$58F8 (22778 bytes = 89 sectors)

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

### Current Status — D64 Builds Correctly
- Boot chain: 6502 DISKHDR → KERNAL loads Z80BOOT to $8000 → Z80 boot loads full SYSRES (89 sectors) to $0000-$58F8 → JP $1E38
- SYSRES init at $1E38 verified (starts with `DI`, sets up NMI, copies data, initializes CIA#1)
- SVC table at $0100, dispatch at $0326, page 0 vectors all present
- HELLO/CMD at T7S0, HELLO/ASM at T7S1-S3 (TRSDOS-only, no CBM DOS dir entry)
- D64 has all 89 SYSRES sectors, proper BAM, directory (only Z80BOOT visible to CBM DOS)

### Post-processing fixes applied
- `mras2vasm.pl`: `$?` label nearest-match resolution, numeric alias emission, `@`→`_`, `$`→`_S`, MRAS directives, `<` shift operator, DC/DM conversion, MACRO param stripping
- `build_sysres.sh`: ORG label→constant replacement, VDC macro params, CORE_S redefinition, duplicate macro removal, GETADR rename, `?`→`_Q` labels, JR→JP conversion, 8-bit wrap fix, missing EQU stubs, section overlap avoidance
- Build scripts use `/usr/local/bin/vasmz80_oldstyle` (system install); Makefile falls back to `/tmp/vasm/bin/`
- vasm source at `/tmp/vasm/` (GitHub mirror), rebuild with `make -C /tmp/vasm SYNTAX=oldstyle CPU=6502/z80`

### Blocker History (resolved)
- ~~$? forward-reference resolution~~ — fixed by scope-independent nearest-match
- ~~$? numeric label prefix identity~~ — fixed by alias label emission
- ~~_L_0_446 undefined~~ — fixed by `\s`→`(?:\s|$)` regex in alias emission
- ~~Section overlap: 1D00H SBUFF_S ↔ 1E00H sysinit~~ — fixed by commenting out ORG 1E00H
- ~~Section overlap: ORG 0036H with ORG 0~~ — fixed by commenting out ORG 0036H
- ~~vasm path stale (/tmp/vasm removed)~~ — fixed: rebuilt vasm 2.0e from GitHub, installed to /usr/local/bin; build scripts updated
- ~~Exomizer binary missing~~ — fixed: rebuilt from Bitbucket source at /tmp/opencode/exomizer/src/exomizer

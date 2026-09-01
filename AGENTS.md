# Agent Context

## Project Goal

Create bootable disk images for C128 (D64) and Amstrad CPC (DSK) that load TRSDOS.

## Build Commands

```
make              # full build: assemble + D64
make check        # validate D64 structure
make clean        # remove build/ and D64
make distclean    # clean + remove dist zip
make dist         # create distribution zip
make -C /tmp/vasm SYNTAX=oldstyle CPU=6502   # build vasm 6502 from source
make -C /tmp/vasm SYNTAX=oldstyle CPU=z80    # build vasm Z80 from source
```

## Release

- v0.2.2 (2026-08-26): Z80 IN/OUT hardware access, D64 read-only, `make check` target.
- v0.2.1 (2026-05-12): D64 + DSK assets on GitHub releases. HELLO files TRSDOS-only.
- v0.2.0: HELLO/CMD auto-run, CPC starting point.
- v0.1.0: Basic C128 boot chain works.

## Boot Chain (Option A — 8502 KERNAL loads SYSRES, no Z80 IEC)

1. C128 KERNAL (8502) loads track 1 sector 0 → $0B00 (boot_sector.s, 211 bytes), entry at $0B16
2. Boot sector's DISKHDR (`$0B03-04`=adrl/adrh=`$0C00`, `$0B05`=bank=0, `$0B06`=blk#=90) makes the KERNAL BLOCK-READ 90 sequential RAW sectors (T1S1–T5S6) to $0C00–$65AF. KERNAL reads raw 256-byte sectors (no link/load header), does not skip the directory track, 21 sectors/track for tracks 1-17; reads full 90 even if sectors are "free" per BAM.
3. KERNAL auto-loads Z80BOOT PRG (from T6S0–T6S2) → $8000 (load addr in PRG header)
4. Boot sector detects 40/80-col mode, warns if 40-col, builds TRS-80 block glyphs in VDC alt charset
5. Boot sector writes JP $8000 to Z80VEC ($FFEE), maps all-RAM bank 0, then switches to Z80 via VDCCFG ($D505) bit 0
6. Z80 boot (552 bytes at $8000) initializes VDC 80×25 text + prints "C128 TRSDOS v0.2.0 - Z80 Boot" / "Decompressing SYSRES...", then does a BACKWARD LDDR copy: HL=$65AF → DE=$59AF, BC=$59B0 (SYSRES_SIZE), moving SYSRES from $0C00–$65AF staging down to $0000–$59AF
7. Z80 boot jumps to SYSRES init at $1E38 (SYSINIT does its own full VDC init)

NOTE: This replaces the old Z80 IEC/slow-serial loader (cancelled — see Current Issue). No Z80 I/O to the drive occurs at all now.

## Key Files

| File | Role |
|------|------|
| `boot_sector.s` | 8502 boot sector, loaded to $0B00, DISKHDR requests 90 extra sectors, KERNAL auto-loads Z80BOOT PRG |
| `z80_boot.asm` | Z80 boot stub at $8000 (loaded as Z80BOOT PRG), VDC display, backward LDDR copy of SYSRES, JP SYSINIT |
| `boot_cpc.asm` | CPC boot sector (Z80, T0S0), FDC loads SYSRES blob |
| `decrun_cpc.asm` | Exomizer3 Z80 decruncher at $BE70 (148 bytes) |
| `make_d64.py` | Creates 35-track D64 with proper BAM, stores full SYSRES |
| `make_dsk.py` | Creates 40-track CPC DSK with boot + compressed SYSRES |
| `Makefile` | Auto-builds vasm, assembles, creates D64/DSK + dist zip |

## IEC Protocol (CIA#2 at $DD00)

### CIA2 PRA bit mapping (CORRECT, C128 hardware)
Confirmed by three independent authoritative sources (C64 KERNAL ROM disassembly @ skoolkid, C128 CP/M Plus BIOS cxdisk @ devili.iki.fi with `clk$bit equ 10h`, c128io.txt @ zimmers, c64bridge io-spec):
- b3 = ATN OUT ($08)
- b4 = CLOCK OUT ($10)
- b5 = DATA OUT ($20)
- b6 = CLOCK IN ($40)
- b7 = DATA IN ($80)
Active-low via 7406 (PRA bit = 1 → line high/released). The OLD PA0-4 mapping in the sibling `polluks/trsdos` repo is WRONG — do NOT copy it.

CIA2 DDRA ($DD02) = $3F → bits 3/4/5 (ATN/CLOCK/DATA out) outputs, bits 6/7 inputs.

### Driver rewrite (committed d384c21)
`IEC_BYTE_OUT` / `IEC_BYTE_IN` / `IEC_READ_SECTOR` were rewritten as a port of the C64 KERNAL serial transmit ($ED40) and ACPTR receive ($EE13) algorithms (LSB-first, ATN-ack, frame-ack, TALK bus turnaround, device-present checks). VIC border markers: 12=dark grey (before ATN for LISTEN), 13=light green (LISTEN accepted), 14=light blue (command+UNLISTEN done), 11=cyan (before TALK read).

### DEPRECATED — 1541 slow-serial / 1571 fast-burst not used
Z80-mode slow bit-bang of $DD00 does NOT reach the drive in VICE (drive LED stays solid green; screen fills with garbage after marker 12). CP/M works in VICE but NEVER bit-bangs $DD00 from Z80 — it either uses the 8502 KERNAL or the 1571 CIA1 SDR fast burst. **Decision (user): 8502 KERNAL extra-sector load (Option A) is used instead — the CIA1 SDR fast-burst driver is CANCELLED.** No Z80 I/O to the drive occurs at all now.

### Legacy U1 Command (read sector, for reference)
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

- 8502 boot sector: max 256 bytes, no branches in IEC tight loops
- Z80 boot loaded to $8000 via chained PRG (2-byte load-address header); no hard 1024-byte cap — currently 552 bytes (T6S0-S2)
- Sector buffer at $5000
- VDC ($D600/$D601) is memory-mapped (not on Z80 I/O bus)
- C128 Z80 runs at 2MHz; `OUT (C),A` is fine (buggy Z80 OUTI/OUTIR not used)
- Vasm oldstyle syntax throughout (not MRAS)
- Z80 uses `OR` not `ORA`, `AND` not `ANA`
- D64 BAM DOS version byte 0x20 = read-only to CBM DOS

## D64 Sector Layout

Current sector usage:
- Track 1: S0=boot sector, S1-S20=SYSRES (20 sectors, extra-sector staging starts here)
- Track 2: S0-S20=SYSRES (21 sectors)
- Track 3: S0-S20=SYSRES (21 sectors)
- Track 4: S0-S20=SYSRES (21 sectors)
- Track 5: S0-S6=SYSRES (7 sectors, 90 total staged at $0C00-$65AF)
- Track 6: S0-S2=Z80BOOT PRG (552 bytes to $8000)
- Track 7: S0=HELLO/CMD (TRSDOS-only, no CBM dir entry), S1-S7=HELLO/ASM
- Track 18: S0=BAM, S1=directory (only Z80BOOT visible)

SYSRES in memory: staged $0C00-$65AF (90 sectors), then LDDR-copied to $0000-$59AF (22960 bytes)

## Build Status

### SYSRES Assembly — SUCCESS
- `bash conv/build_sysres.sh` assembles 16 port/repo source files via `conv/mras2vasm.pl` + `conv/build_sysres.sh` post-processing
- Output: `build/sysres/sysres.bin` (29799 bytes, 6 vasm sections)
- Section layout:
  | ORG | Bytes | Addresses | Content |
  |-----|-------|-----------|---------|
  | 0 | 256 | 0-FF | Page 0 (vectors, flags, system data) |
  | 200H | 229 | 200-2E4 | DCBs |
  | 100H | 7168 | 100-1CFF | SVC table + loader code + tasker |
  | 1300H | 1697 | 1300-19A1 | File positioning routines |
  | 1D00H | 1640 | 1D00-2367 | SBUFF_S + sysinit + sound |
  | 4300H | 5735 | 4300-5967 | Boot code + IEC driver |

### Current Status — D64 Builds Correctly
- Boot chain: 8502 DISKHDR → KERNAL loads 90 raw SYSRES sectors to $0C00 → KERNAL loads Z80BOOT to $8000 → Z80 stub LDDR-copies to $0000-$59AF → JP $1E38
- SYSRES init at $1E38 verified (starts with `DI`, sets up NMI, copies data, initializes CIA#1)
- SVC table at $0100, dispatch at $0326, page 0 vectors all present
- HELLO/CMD at T7S0, HELLO/ASM at T7S1-S7 (TRSDOS-only, no CBM DOS dir entry)
- D64 has all 90 SYSRES sectors, proper BAM, directory (only Z80BOOT visible to CBM DOS)
- `make check` validates the full chain: boot DISKHDR ($0C00/0/90), sequential block-read == boot_sysres.bin, Z80BOOT dir entry → T6S0 load $8000, PRG chain == z80_boot.bin, no overlap with SYSRES range

### Post-processing fixes applied
- `mras2vasm.pl`: `$?` label nearest-match resolution, numeric alias emission, `@`→`_`, `$`→`_S`, MRAS directives, `<` shift operator, DC/DM conversion, MACRO param stripping
- `build_sysres.sh`: ORG label→constant replacement, VDC macro params, CORE_S redefinition, duplicate macro removal, GETADR rename, `?`→`_Q` labels, JR→JP conversion, 8-bit wrap fix, missing EQU stubs, section overlap avoidance
- Build scripts use `/usr/local/bin/vasmz80_oldstyle` (system install); Makefile falls back to `/tmp/vasm/bin/`
- vasm source at `/tmp/vasm/` (GitHub mirror), rebuild with `make -C /tmp/vasm SYNTAX=oldstyle CPU=6502/z80`
- vasm 2.0f in use (Makefile); occasionally invoke `make --always-make` to force the D64 rebuild when targets look stale

### Blocker History (resolved)
- ~~$? forward-reference resolution~~ — fixed by scope-independent nearest-match
- ~~$? numeric label prefix identity~~ — fixed by alias label emission
- ~~_L_0_446 undefined~~ — fixed by `\s`→`(?:\s|$)` regex in alias emission
- ~~Section overlap: 1D00H SBUFF_S ↔ 1E00H sysinit~~ — fixed by commenting out ORG 1E00H
- ~~Section overlap: ORG 0036H with ORG 0~~ — fixed by commenting out ORG 0036H
- ~~vasm path stale (/tmp/vasm removed)~~ — fixed: rebuilt vasm 2.0e from GitHub, installed to /usr/local/bin; build scripts updated
- ~~Exomizer binary missing~~ — fixed: rebuilt from Bitbucket source at /tmp/opencode/exomizer/src/exomizer
- ~~Wrong CIA2 PRA bit mapping (PA0-4)~~ — fixed by rewrite to PA3-7 (commit d384c21)

### Current Issue (active blocker — verification only)
- **Z80 slow-serial bit-bang of $DD00 never reaches the drive in VICE**; CP/M never bit-bangs $DD00 from Z80 mode. Root cause established and architecture changed.
- **Decision (user): Option A — 8502 KERNAL extra-sector load (implemented).** The 1571 CIA1 SDR fast-burst driver is CANCELLED. No Z80 I/O to the drive occurs.
- **Remaining:** boot in VICE 3.10 to confirm the chain visually (KERNAL block-read → Z80 stub "Decompressing SYSRES..." → SYSINIT banner). Headless verification is blocked in this env (GTK monitor console + PNG screenshot capture unavailable); test locally with `x128 -autostart trsdos_c128.d64 -drive8truedrive`.
- Test env is VICE 3.10 (emulated 1571, TDE). `x128 -drive8truedrive` enables TDE; `x128 +drive8truedrive` disables it.

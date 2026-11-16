# TRSDOS for Commodore 128

A C128 port of TRSDOS/LS-DOS 6.x, booting via a 8502→Z80 CPU switch chain from IEC serial disk.

![TRSDOS 6.02 Boot Screen](https://upload.wikimedia.org/wikipedia/en/c/c3/TRSDOS_6.02.jpg)

The TRSDOS logo uses the [TRS-80 font](https://48k.ca/fonts.html).

* https://c-128.freeforums.net/thread/723/registers-pc-exchange-8502-z80
* https://electrickery.nl/comp/trs80/trs80Archeology/cmdDecode.py

## Boot Chain (Option A — 8502 KERNAL loads SYSRES, no Z80 IEC)

1. C128 KERNAL (8502) loads track 1 sector 0 → `$0B00` (`boot_sector.s`, 211 bytes), entry at `$0B16`.
2. Boot sector DISKHR (`$0B03-04`=adrl/adrh=`$0C00`, `$0B05`=bank=0, `$0B06`=blk#=90) makes the
   KERNAL BLOCK-READ 90 sequential RAW sectors (T1S1–T5S6) → `$0C00`–`$65AF`. KERNAL reads raw
   256-byte sectors (no link/load header), does not skip the directory track, 21 sectors/track for
   tracks 1-17; reads the full 90 even if sectors are "free" per BAM.
3. KERNAL auto-loads Z80BOOT PRG (T6S0–T6S2) → `$8000` (load address in PRG header).
4. Boot sector detects 40/80-col mode, warns if 40-col, builds TRS-80 block glyphs in VDC alt charset.
5. Boot sector writes JP `$8000` to Z80VEC (`$FFEE`), maps all-RAM bank 0, then switches to Z80 via VDCCFG (`$D505`) bit 0.
6. Z80 boot (552 bytes, at `$8000`) initializes VDC 80×25 text + prints "C128 TRSDOS v0.2.0 - Z80 Boot" /
   "Decompressing SYSRES...", then does a BACKWARD LDDR copy: HL=`$65AF` → DE=`$59AF`, BC=`$59B0`
   (SYSRES_SIZE), moving SYSRES from `$0C00`–`$65AF` staging down to `$0000`–`$59AF`.
7. Z80 boot jumps to SYSRES init at `$1E38` (SYSINIT does its own full VDC init).

## 40/80 Column Detection

The 8502 boot sector uses KERNAL `I_80COL` (`$FF5F`) to detect the current video mode. If in 40-column
(VIC-II) mode, it displays `"SWITCH TO 80-COL MONITOR"` and switches to 80-column mode before entering Z80.

## IEC Serial Bus Protocol (CIA2 @ `$DD00`)

CIA2 PRA bit mapping (C128 hardware):

| Bit | Signal   | Direction | Meaning |
|-----|----------|-----------|---------|
| b3  | ATN OUT  | Output    | Attention |
| b4  | CLOCK OUT| Output    | Clock    |
| b5  | DATA OUT | Output   | Data     |
| b6  | CLOCK IN | Input     | Clock    |
| b7  | DATA IN  | Input     | Data     |

Active-low via 7406 (PRA bit = 1 → line high/released). CIA2 DDRA (`$DD02`) = `$3F` → bits 3/4/5 outputs, bits 6/7 inputs.

The runtime IEC driver (`IEC_BYTE_OUT` / `IEC_BYTE_IN` / `IEC_READ_SECTOR`) is a port of the C64 KERNAL
serial transmit (`$ED40`) and ACPTR receive (`$EE13`) algorithms (LSB-first, ATN-ack, frame-ack, TALK bus
turnaround, device-present checks). VIC border markers: 12=dark grey, 13=light green, 14=light blue, 11=cyan.

### Boot Byte I/O (Z80 boot stub)

The Z80 boot stub performs the sector load via boot byte I/O (`BOOT_BYTE_IN` / `BOOT_BYTE_OUT`) through
the C64-KERNAL-style serial routines, then jumps to SYSRES init.

## VDC (8563) Display

The VDC is register-accessed via `$D600` (address) / `$D601` (data):

- Reg 18/19: VRAM update address (set before read/write)
- Reg 31: Data register with auto-increment on each access
- 80×25 text mode = 2000 bytes VRAM for character codes
- Clear: set address to 0, select reg 31, write 2000 spaces

## Build

```
make              # full build: assemble + D64
make check        # validate D64 structure (+ DSK)
make dist         # create distribution zip
make clean        # remove build artifacts
make distclean    # clean + remove dist zip
```

Requires vasm (built via `make -C /tmp/vasm SYNTAX=oldstyle CPU=6502/z80`). Output: `trsdos_c128.d64`
(35-track, 174848 bytes) and `trsdos_cpc.dsk` (Amstrad CPC, 40-track MFM).

## Project Structure

```
trsdos/
├── boot_sector.s     # 8502 boot sector (C128 DISKHR, loaded to $0B00)
├── z80_boot.asm      # Z80 boot stub (vasmz80_oldstyle, loaded to $8000 via chained PRG)
├── make_d64.py       # D64 disk image builder (BAM, boot chain, LS-DOS dir, granules)
├── make_dsk.py       # CPC DSK builder (logical mirror of the D64 layout)
├── trsdos_lsdir.py   # Byte-correct LS-DOS 6.3 on-disk directory builder (GAT/HIT/dir + granules)
├── make_cmd.py       # Wrap flat Z80 binary into a TRSDOS .CMD (01 data + 02 transfer records)
├── trsmark.asm       # TRSMARK CPU-speed benchmark (.CMD)
├── check_d64.py      # D64 structural validation (`make check`)
├── check_dsk.py      # CPC DSK validation (`make check`)
├── Makefile          # Build system
├── conv/
│   ├── build_sysres.sh    # Assembles SYSRES from MRAS→vasm sources
│   ├── build_sysres_cpc.sh# CPC SYSRES assembly
│   ├── flatten_sysres.py  # Post-processes vasm output into flat $0000-based image
│   └── mras2vasm.pl       # MRAS→vasm syntax converter
├── port/c128/        # C128 TRSDOS port source (MRAS syntax)
├── port/cpc/         # Amstrad CPC port source (MRAS syntax)
└── repo/             # Original TRSDOS/LS-DOS 6.3 source tree
```

## SYSRES Image

The TRSDOS system image is assembled from 16 source files via `conv/build_sysres.sh` (MRAS→vasm via
`mras2vasm.pl`, then `flatten_sysres.py` into a flat image). Output: `build/sysres/sysres.bin` (29799 bytes,
6 vasm sections; flat staging area `$0C00`–`$65AF` then LDDR to `$0000`–`$59AF`).

## Releases

- **v0.4.1** (2026-11-16): DCT granule byte fix (emitted `0xFF` → now `0x45` = 3 grans/track / 6 sect-gran) and LBOOT sectors/track 18 → 17.
- **v0.4.0** (2026-10-09): byte-correct LS-DOS 6.3 on-disk directory (GAT/HIT/dir + HELLO/TRSMARK/HELLO-ASM/TRSMARK-ASM in granule format) on D64; CPC DSK logical mirror; TRSMARK CPU-speed benchmark; boot-sector fixes.

## Current Status

- ✓ 8502 boot sector with C128 DISKHR autoboot (90 raw extra sectors staged)
- ✓ 40/80 column detection with KERNAL warning
- ✓ Z80 boot stub with C64-KERNAL-style IEC serial driver (byte in/out, U1 sector read) + backward LDDR
- ✓ Flat SYSRES loading into place
- ✓ D64 generation with correct BAM, byte-correct LS-DOS directory, and granules
- ✓ CPC DSK (logical mirror) generation
- ✓ MRAS→vasm conversion pipeline for SYSRES sources
- ○ Emulator/hardware testing (VICE 3.10, C128 with emulated 1571; headless screenshot capture unavailable in this env)
- ○ Runtime on-disk TRSDOS I/O (Z80 `IEC_READ_SECTOR` bit-bang does not reach the drive in VICE; CP/M uses an
  8502-KERNAL handoff — Option A already used at boot)

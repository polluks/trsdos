# TRSDOS for Commodore 128

A C128 port of TRSDOS/LS-DOS 6.x, booting via a 8502→Z80 CPU switch chain from IEC serial disk.

![TRSDOS 6.02 Boot Screen](https://upload.wikimedia.org/wikipedia/en/c/c3/TRSDOS_6.02.jpg)

The TRSDOS logo uses the [TRS-80 font](https://48k.ca/fonts.html).

https://c-128.freeforums.net/thread/723/registers-pc-exchange-8502-z80

## Boot Chain

```
C128 Power-on (8502 mode)
  → KERNAL loads track 1 sector 0 to $0B00 (DISKHDR)
  → 8502 boot sector (boot_sector.s)
    → Checks 40/80 column mode; warns if in 40-col via KERNAL
    → KERNAL auto-loads Z80BOOT PRG to $4300
    → Sets JP $4300 at $FFF0, enables VDC output
  → Z80 boot loader (z80_boot.asm, 805 bytes at $4300)
    → Initializes VDC (80x25 text), CIA#2 (IEC serial), MMU
    → Loads flat SYSRES image from tracks 2-5 to $0000-$42FF
    → Jumps to system init at $1E38
```

## 40/80 Column Detection

The 8502 boot sector uses KERNAL `I_80COL` (`$FF5F`) to detect the current video mode. If in 40-column (VIC-II) mode, it displays `"SWITCH TO 80-COL MONITOR"` on screen and switches to 80-column mode before entering Z80.

## IEC Serial Bus Protocol

The IEC serial bus uses bit-banged I/O via CIA#2 at $DD00:

| CIA2 Pin | Signal    | Direction | Function              |
|----------|-----------|-----------|-----------------------|
| PA0      | DATA OUT  | Output    | Serial data to device |
| PA1      | CLOCK OUT | Output    | Serial clock to device|
| PA2      | ATN OUT   | Output    | Attention (active low)|
| PA3      | DATA IN   | Input     | Data from device      |
| PA4      | CLOCK IN  | Input     | Clock from device     |
| PA5      | SRQ IN    | Input     | Service request       |

### Byte Out Sequence (IEC_BYTE_OUT)

1. Rotate bit 0 of byte into carry (RRCA)
2. Set DATA OUT = carry (PRA bit 0)
3. Pulse CLOCK OUT low then high (PRA bit 1)
4. Repeat for all 8 bits, LSB first
5. Release DATA OUT high

### Byte In Sequence (IEC_BYTE_IN)

1. Set DATA as input (clear DDRA bit 0), pull-up high
2. Wait for device to drive CLOCK_IN low
3. Read DATA_IN bit via PRA bit 3
4. Drive CLOCK_OUT high (acknowledge)
5. Wait for CLOCK_IN high from device
6. Repeat for all 8 bits
7. Restore DATA as output

Data bits are accumulated LSB-first using `RR L` (rotate right through carry).

### Command Protocol (U1 Sector Read)

The U1 block read command reads a 256-byte sector:

```
ATN low → send $28 (LISTEN device 8), send $0F (secondary 15)
ATN high → send "U1:0 <track> <sector>" as ASCII decimal
Send $3F (UNLISTEN)
ATN low → send $68 (TALK device 8), send $60 (secondary 0)
ATN high → read 256 bytes via IEC_BYTE_IN
Send $5F (UNTALK)
```

## VDC (8563) Display

The VDC is register-accessed via $D600 (address) and $D601 (data):

- Registers 18/19: VRAM update address (set before read/write)
- Register 31: Data register with auto-increment on each access
- 80x25 text mode, 2000 bytes VRAM for character codes

## Build

```
make              # full build: assemble + D64
make dist         # create distribution zip
make clean        # remove build artifacts
make distclean    # clean + remove dist zip
```

Requires vasm (built automatically to /tmp/vasm). Output: `trsdos_c128.d64` (35-track, 174848 bytes).

## Project Structure

```
trsdos/
├── boot_sector.s     # 8502 boot sector (DISKHDR format, loaded to $0B00)
├── z80_boot.asm      # Z80 boot loader (vasmz80_oldstyle, at $4300)
├── make_d64.py       # D64 disk image builder
├── Makefile          # Build system
├── conv/
│   ├── build_sysres.sh    # Assembles SYSRES from MRAS→vasm sources
│   ├── flatten_sysres.py  # Post-processes vasm output into flat $0000-based image
│   └── mras2vasm.pl       # MRAS→vasm syntax converter
├── port/c128/        # C128 TRSDOS port source (MRAS syntax)
└── repo/             # Original TRSDOS/LS-DOS 6.3 source tree
```

## SYSRES Image

The TRSDOS system image is assembled from 16 source files via `conv/build_sysres.sh`, which runs `mras2vasm.pl` to convert MRAS syntax to vasm oldstyle. The resulting vasm binary is post-processed by `flatten_sysres.py` into a contiguous flat image at `$0000-$42FF`, stored on disk tracks 2-5 (67 sectors).

## Current Status

- ✓ 8502 boot sector with C128 DISKHDR autoboot
- ✓ 40/80 column detection with KERNAL warning
- ✓ Z80 boot loader with full IEC driver (byte in/out, U1 sector read)
- ✓ Flat SYSRES loading across tracks 2-5
- ✓ D64 generation with correct BAM and directory
- ✓ MRAS→vasm conversion pipeline for SYSRES sources
- ○ Emulator/hardware testing (YAPE or real C128)

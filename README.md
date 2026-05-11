# TRSDOS for Commodore 128

A C128 port of TRSDOS/LS-DOS 6.x, booting via a 6502→Z80 CPU switch chain from IEC serial disk.

## Boot Chain

```
C128 Power-on (6502 mode)
  → KERNAL loads track 1 sector 0 to $0B00
    → 6502 boot sector (boot_sector.s)
      → KERNAL LOAD loads Z80 boot code to $4300
      → Sets JP $4300 at $FFF0, writes $B0 to $D505
        → Z80 boot loader (z80_boot.asm, 921 bytes at $4300)
          → Initializes VDC (80x25 text), CIA#2 (IEC), MMU
          → Reads GAT + directory via IEC serial protocol
          → Loads TRSDOS SYSRES
```

## IEC Serial Bus Protocol

The IEC (IEEE-488 derived) serial bus uses bit-banged I/O via CIA#2 at $DD00:

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

The U1 ("User Command 1") block read command reads a 256-byte sector:

```
ATN low → send $28 (LISTEN device 8), send $0F (secondary 15, command channel)
ATN high → send "U1:0 <track> <sector>" as ASCII decimal
Send $3F (UNLISTEN)
ATN low → send $68 (TALK device 8), send $60 (secondary 0, data channel)
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
make         # assemble + create D64
make dist    # create distribution zip
make clean   # remove build artifacts
```

Requires vasm (built automatically to /tmp/vasm). Output: `trsdos_c128.d64` (35-track, 174848 bytes).

## Project Structure

```
trsdos/
├── boot_sector.s    # 6502 boot sector (vasm6502_oldstyle, loaded to $0B00)
├── z80_boot.asm     # Z80 boot loader (vasmz80_oldstyle, at $4300)
├── make_d64.py      # D64 disk image builder
├── Makefile         # Build system
├── conv/            # SYSRES build scripts + MRAS→vasm converter
├── port/c128/       # C128 TRSDOS port source (MRAS syntax)
└── repo/            # Original TRSDOS/LS-DOS 6.3 source tree
```

## Next Steps

- Full MRAS→vasm conversion of c128_sysres.asm and all port files
- Implement granule parsing in LOAD_SYSTEM to find and load SYSRES
- IEC burst mode (1571) support for faster loading
- Keyboard driver and full system initialization

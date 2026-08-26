#!/usr/bin/env python3
"""Create a D64 disk image with C128 TRSDOS boot block."""

import struct
import sys
import os

# D64 track geometry (1541)
TRACK_OFFSETS = []
sector = 0
for track in range(1, 36):
    TRACK_OFFSETS.append(sector)
    if track <= 17:
        ns = 21
    elif track <= 24:
        ns = 19
    elif track <= 30:
        ns = 18
    else:
        ns = 17
    sector += ns
TOTAL_SECTORS = sector  # 683 for 35 tracks
TOTAL_BYTES = TOTAL_SECTORS * 256  # 174848

def track_sector_to_offset(track, sector):
    """Convert 1-based track, 0-based sector to byte offset in D64."""
    if track < 1 or track > 35:
        raise ValueError(f"Invalid track: {track}")
    off = TRACK_OFFSETS[track - 1]
    if track <= 17:
        if sector < 0 or sector >= 21:
            raise ValueError(f"Invalid sector {sector} for track {track}")
    elif track <= 24:
        if sector < 0 or sector >= 19:
            raise ValueError(f"Invalid sector {sector} for track {track}")
    elif track <= 30:
        if sector < 0 or sector >= 18:
            raise ValueError(f"Invalid sector {sector} for track {track}")
    else:
        if sector < 0 or sector >= 17:
            raise ValueError(f"Invalid sector {sector} for track {track}")
    return (off + sector) * 256

def make_directory(n_z80_sectors):
    """Create directory sector (track 18, sector 1) with entries."""
    dir_sec = bytearray(256)
    dir_sec[0] = 0
    dir_sec[1] = 0

    entries = [
        (0x82, b'Z80BOOT', 1, 1, n_z80_sectors),   # PRG, closed, T1 S1, N secs
    ]

    for i, (ftype, name, track, sector, size) in enumerate(entries):
        off = 2 + i * 32
        # Standard 1541 directory entry layout (32 bytes):
        # +0:  Track of first data sector
        # +1:  Sector of first data sector
        # +2 to +17: Filename (16 chars, $A0 padded)
        # +18: File type ($81=SEQ, $82=PRG, $83=USR, $84=REL)
        # +19: Track of next directory sector (0 = end of chain)
        # +20: Sector of next directory sector
        # +21 to +27: (unused / side sector / record length)
        # +28 to +29: File size in sectors (little-endian)
        dir_sec[off + 0] = track           # Track of first data sector
        dir_sec[off + 1] = sector          # Sector of first data sector
        name = name.ljust(16, b'\xa0')
        for j in range(16):
            dir_sec[off + 2 + j] = name[j]
        dir_sec[off + 18] = ftype          # File type
        dir_sec[off + 19] = 0              # Next directory sector track (0 = end)
        dir_sec[off + 20] = 0              # Next directory sector sector
        # +21 to +27: unused for non-REL
        dir_sec[off + 28] = size & 0xFF    # Size low byte
        dir_sec[off + 29] = (size >> 8) & 0xFF  # Size high byte

    return dir_sec


def make_bam(track_usage=None):
    """Create BAM sector (track 18, sector 0).
    
    track_usage: dict mapping track_number -> set of used sector_numbers
    """
    bam = bytearray(256)
    
    # Directory header: first dir sector = track 18, sector 1
    bam[0] = 18
    bam[1] = 1
    # DOS version type: bit 5 set = read-only to CBM DOS
    bam[2] = 0x20
    
    # BAM entries: tracks 1-35, 4 bytes each (free count + 3 bytes bitmap)
    for t in range(1, 36):
        if t <= 17:
            n_sect = 21
        elif t <= 24:
            n_sect = 19
        elif t <= 30:
            n_sect = 18
        else:
            n_sect = 17
        
        used = track_usage.get(t, set()) if track_usage else set()
        
        # Count free sectors
        free_count = n_sect - len(used)
        
        # Build 3-byte bitmap (bits 0-7 = sectors 0-7, etc.)
        bitmap = 0
        for s in range(n_sect):
            if s not in used:
                bit = s
                byte_idx = bit // 8
                bit_idx = bit % 8
                bitmap |= (1 << bit_idx) << (byte_idx * 8)
        
        entry_offset = 4 + (t - 1) * 4
        bam[entry_offset] = free_count
        bam[entry_offset + 1] = bitmap & 0xFF
        bam[entry_offset + 2] = (bitmap >> 8) & 0xFF
        bam[entry_offset + 3] = (bitmap >> 16) & 0xFF
    
    # Disk name (16 bytes, padded with $A0)
    name = b'TRSDOS FOR C128 '
    for i in range(16):
        bam[144 + i] = name[i] if i < len(name) else 0xA0
    
    # Disk ID (2 chars)
    bam[160] = ord('T')
    bam[161] = ord('S')
    
    # DOS type
    bam[162] = ord('2')
    bam[163] = ord('A')
    
    # Two unused bytes (normally $A0)
    bam[164] = 0xA0
    bam[165] = 0xA0
    
    return bam

def make_prg_sectors(data, load_addr, start_track, start_sector):
    """Convert binary data to PRG file sectors with track/sector chain.

    Each sector: bytes 0-1 = next track/sector (0,0 = end),
    bytes 2-255 = 254 bytes of file data.
    First sector prepends 2-byte load address header.

    Returns list of (track, sector, 256-byte sector_data) tuples.
    """
    header = struct.pack('<H', load_addr)
    file_data = header + data

    sectors = []
    track = start_track
    sector = start_sector
    total = len(file_data)
    offset = 0

    while offset < total:
        chunk = file_data[offset:offset + 254]
        chunk = chunk.ljust(254, b'\x00')
        offset += 254

        sec_data = bytearray(256)

        # Chain pointer to next sector
        if offset < total:
            nxt_track = track
            nxt_sector = sector + 1
            sec_data[0] = nxt_track
            sec_data[1] = nxt_sector
        else:
            sec_data[0] = 0
            sec_data[1] = 0

        sec_data[2:256] = chunk
        sectors.append((track, sector, bytes(sec_data)))

        sector += 1

    return sectors


def make_raw_sectors(data, start_track, start_sector):
    """Store raw binary data across consecutive sectors.

    Returns (list_of_sectors, used_set, n_sectors).
    Each sector entry: (track, sector, 256-byte data).
    """
    sectors = []
    used = set()
    track, sector = start_track, start_sector
    offset = 0
    total = len(data)
    while offset < total:
        sec_data = bytearray(256)
        chunk = data[offset:offset + 256]
        sec_data[:len(chunk)] = chunk
        sectors.append((track, sector, bytes(sec_data)))
        used.add(sector)
        offset += 256
        sector += 1
        if sector >= 21 and track <= 17:
            track += 1
            sector = 0
        elif sector >= 19 and 18 <= track <= 24:
            track += 1
            sector = 0
        elif sector >= 18 and 25 <= track <= 30:
            track += 1
            sector = 0
        elif sector >= 17 and track >= 31:
            track += 1
            sector = 0
    return sectors, used, len(sectors)


def make_d64(boot_sector_bin, z80_boot_bin, sysres_bin, hello_bin, hello_asm_bin, output_path):
    """Create D64 image with boot sector, Z80 boot code, SYSRES, and TRSDOS files."""
    # Initialize D64 with zeros
    d64 = bytearray(TOTAL_BYTES)

    # Place 8502 boot sector at track 1, sector 0
    boot_data = boot_sector_bin[:256]
    boot_data = boot_data.ljust(256, b'\x00')
    off = track_sector_to_offset(1, 0)
    d64[off:off + 256] = boot_data

    # Place Z80 boot code as PRG file at track 1, sectors 1-N
    prg_sectors = make_prg_sectors(z80_boot_bin, 0x8000, 1, 1)
    used_z80 = set()
    for trk, sec, sec_data in prg_sectors:
        off = track_sector_to_offset(trk, sec)
        d64[off:off + 256] = sec_data
        used_z80.add(sec)
    n_z80_sectors = len(prg_sectors)

    # Place full SYSRES flat image as raw sectors starting at track 2, sector 0
    # Z80 boot now runs from $8000, so the full SYSRES ($0000-$58F8) fits
    # without overlap
    sysres_sectors, used_sysres, n_sysres_sectors = \
        make_raw_sectors(sysres_bin, 2, 0)
    for trk, sec, sec_data in sysres_sectors:
        off = track_sector_to_offset(trk, sec)
        d64[off:off + 256] = sec_data

    # Collect used sectors per track for BAM
    usage = {1: {0} | used_z80, 18: {0, 1}}
    for trk, sec, _ in sysres_sectors:
        usage.setdefault(trk, set()).add(sec)

    # Place HELLO/CMD at track 7, sector 0 — TRSDOS only (no CBM DOS directory entry)
    hello_sectors = make_prg_sectors(hello_bin, 0x3000, 7, 0)
    for trk, sec, sec_data in hello_sectors:
        off = track_sector_to_offset(trk, sec)
        d64[off:off + 256] = sec_data
        usage.setdefault(trk, set()).add(sec)

    # Place HELLO/ASM source at track 7, sector 1 — TRSDOS only
    hello_asm_raw = bytearray(256 * 4)  # up to 4 sectors
    src = hello_asm_bin
    off = 0
    trk, sec = 7, 1
    while off < len(src):
        chunk = src[off:off + 256]
        chunk = chunk.ljust(256, b'\x00')
        d64[track_sector_to_offset(trk, sec):][:256] = chunk
        usage.setdefault(trk, set()).add(sec)
        off += 256
        sec += 1
        if sec >= 21:
            trk += 1; sec = 0
    hello_asm_end_sec = sec

    # Create directory with Z80BOOT entry (HELLO is TRSDOS-only, no CBM dir entry)
    dir_sec = make_directory(n_z80_sectors)
    off = track_sector_to_offset(18, 1)
    d64[off:off + 256] = dir_sec

    # Place BAM at track 18, sector 0
    bam = make_bam(usage)
    off = track_sector_to_offset(18, 0)
    d64[off:off + 256] = bam

    # Write output
    with open(output_path, 'wb') as f:
        f.write(d64)

    print(f"D64 created: {output_path}")
    print(f"  Size: {len(d64)} bytes ({TOTAL_SECTORS} sectors)")
    print(f"  Boot sector: track 1, sector 0 ({len(boot_data)} bytes)")
    print(f"  Z80 boot: track 1, sectors 1-{n_z80_sectors} ({len(z80_boot_bin)} bytes)")
    print(f"  SYSRES (flat): tracks 2-{sysres_sectors[-1][0]}, {n_sysres_sectors} sectors ({len(sysres_bin)} bytes loaded to $0000-${len(sysres_bin)-1:04X})")
    print(f"  HELLO/CMD: track {hello_sectors[0][0]}, sector 0 (TRSDOS-only)")
    print(f"  HELLO/ASM: track 7, sector 1-{hello_asm_end_sec-1} (TRSDOS-only)")
    print(f"  BAM: track 18, sector 0")
    return True

if __name__ == '__main__':
    # Paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    build_dir = os.path.join(script_dir, 'build')
    
    boot_bin = os.path.join(build_dir, 'boot_sector.bin')
    z80_bin = os.path.join(build_dir, 'z80_boot.bin')
    sysres_bin = os.path.join(build_dir, 'sysres', 'boot_sysres.bin')
    # HELLO/CMD is optional — TRSDOS-only, no CBM DOS directory entry
    hello_bin = os.path.join(build_dir, 'hello.cmd')
    
    output = os.path.join(script_dir, 'trsdos_c128.d64')
    
    # Check required inputs
    for path, name in [(boot_bin, 'Boot sector'), (z80_bin, 'Z80 boot'), (sysres_bin, 'SYSRES')]:
        if not os.path.exists(path):
            print(f"ERROR: {path} ({name}) not found. Run build first.")
            sys.exit(1)
    
    with open(boot_bin, 'rb') as f:
        boot_data = f.read()
    with open(z80_bin, 'rb') as f:
        z80_data = f.read()
    with open(sysres_bin, 'rb') as f:
        sysres_data = f.read()
    
    # HELLO/CMD is optional
    hello_data = b''
    if os.path.exists(hello_bin):
        with open(hello_bin, 'rb') as f:
            hello_data = f.read()

    # HELLO/ASM source is optional (TRSDOS-only)
    hello_asm_path = os.path.join(script_dir, 'hello.asm')
    hello_asm_data = b''
    if os.path.exists(hello_asm_path):
        with open(hello_asm_path, 'rb') as f:
            hello_asm_data = f.read()

    make_d64(boot_data, z80_data, sysres_data, hello_data, hello_asm_data, output)

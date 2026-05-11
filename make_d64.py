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
    """Create directory sector (track 18, sector 1) with dummy entries."""
    dir_sec = bytearray(256)
    # Byte 0-1: link to next dir sector (0,0 = end of directory)
    dir_sec[0] = 0
    dir_sec[1] = 0

    entries = [
        # Note: boot sector (T1 S0) has no directory entry — it's loaded
        # directly by C128 KERNAL bootstrap, not as a PRG file.
        (0x82, b'Z80BOOT', 1, 1, n_z80_sectors),   # PRG, closed, T1 S1, N secs
    ]

    for i, (ftype, name, track, sector, size) in enumerate(entries):
        off = 2 + i * 32
        dir_sec[off] = ftype
        name = name.ljust(16, b'\xa0')
        for j in range(16):
            dir_sec[off + 1 + j] = name[j]
        dir_sec[off + 17] = 0    # next track (end)
        dir_sec[off + 18] = 0    # next sector (end)
        dir_sec[off + 19] = track
        dir_sec[off + 20] = sector
        # REL info (zeros for non-REL)
        # Size in sectors (LE)
        dir_sec[off + 27] = size & 0xFF
        dir_sec[off + 28] = (size >> 8) & 0xFF

    return dir_sec


def make_bam(track_usage=None):
    """Create BAM sector (track 18, sector 0).
    
    track_usage: dict mapping track_number -> set of used sector_numbers
    """
    bam = bytearray(256)
    
    # Directory header: first dir sector = track 18, sector 1
    bam[0] = 18
    bam[1] = 1
    # DOS version type: 0x00 = non-standard, CBM DOS won't validate/write
    bam[2] = 0x00
    
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
        elif sector >= 19 and track <= 24:
            track += 1
            sector = 0
        elif sector >= 18 and track <= 30:
            track += 1
            sector = 0
        elif sector >= 17:
            track += 1
            sector = 0
    return sectors, used, len(sectors)


def make_d64(boot_sector_bin, z80_boot_bin, sysres_bin, output_path):
    """Create D64 image with boot sector, Z80 boot code, and SYSRES."""
    # Initialize D64 with zeros
    d64 = bytearray(TOTAL_BYTES)

    # Place 6502 boot sector at track 1, sector 0
    boot_data = boot_sector_bin[:256]
    boot_data = boot_data.ljust(256, b'\x00')
    off = track_sector_to_offset(1, 0)
    d64[off:off + 256] = boot_data

    # Place Z80 boot code as PRG file at track 1, sectors 1-N
    prg_sectors = make_prg_sectors(z80_boot_bin, 0x4300, 1, 1)
    used_z80 = set()
    for trk, sec, sec_data in prg_sectors:
        off = track_sector_to_offset(trk, sec)
        d64[off:off + 256] = sec_data
        used_z80.add(sec)
    n_z80_sectors = len(prg_sectors)

    # Place SYSRES as raw sectors starting at track 2, sector 0
    sysres_sectors, used_sysres, n_sysres_sectors = \
        make_raw_sectors(sysres_bin, 2, 0)
    for trk, sec, sec_data in sysres_sectors:
        off = track_sector_to_offset(trk, sec)
        d64[off:off + 256] = sec_data

    # Collect used sectors per track for BAM
    usage = {1: {0} | used_z80, 18: {0, 1}}
    for trk, sec, _ in sysres_sectors:
        usage.setdefault(trk, set()).add(sec)

    # Create directory with Z80BOOT entry
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
    print(f"  SYSRES: tracks 2-{sysres_sectors[-1][0]}, {n_sysres_sectors} sectors ({len(sysres_bin)} bytes)")
    print(f"  BAM: track 18, sector 0")
    return True

if __name__ == '__main__':
    # Paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    build_dir = os.path.join(script_dir, 'build')
    
    boot_bin = os.path.join(build_dir, 'boot_sector.bin')
    z80_bin = os.path.join(build_dir, 'z80_boot.bin')
    sysres_bin = os.path.join(build_dir, 'sysres', 'sysres.bin')
    output = os.path.join(script_dir, 'trsdos_c128.d64')
    
    # Check inputs
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
    
    make_d64(boot_data, z80_data, sysres_data, output)

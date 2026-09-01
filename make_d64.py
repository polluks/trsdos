#!/usr/bin/env python3
"""Create a D64 disk image with C128 TRSDOS boot block."""

import struct
import sys
import os
import trsdos_lsdir as lsdir

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

def n_sect_for_track(track):
    """Number of sectors on a CBM 1541/1571 track (1-based track #)."""
    if track <= 17:
        return 21
    elif track <= 24:
        return 19
    elif track <= 30:
        return 18
    else:
        return 17


def track_sector_to_offset(track, sector):
    """Convert 1-based track, 0-based sector to byte offset in D64."""
    if track < 1 or track > 35:
        raise ValueError(f"Invalid track: {track}")
    off = TRACK_OFFSETS[track - 1]
    ns = n_sect_for_track(track)
    if sector < 0 or sector >= ns:
        raise ValueError(f"Invalid sector {sector} for track {track}")
    return (off + sector) * 256

def make_directory(n_z80_sectors, first_track, first_sector):
    """Create directory sector (track 18, sector 1) with entries."""
    dir_sec = bytearray(256)
    dir_sec[0] = 0
    dir_sec[1] = 0

    entries = [
        (0x82, b'Z80BOOT', first_track, first_sector, n_z80_sectors),
    ]

    for i, (ftype, name, track, sector, size) in enumerate(entries):
        off = 2 + i * 32
        # Standard 1541 directory entry layout (32 bytes), as read by
        # CBM DOS / c1541:
        # +0:  File type (bit7 set = closed: $81=SEQ, $82=PRG, $83=USR, $84=REL)
        # +1:  Track of first data sector
        # +2:  Sector of first data sector
        # +3 to +18: Filename (16 chars, PETSCII bit7-shifted, $A0 padded)
        # +19 to +20: Side-sector track/sector (REL files, else 0)
        # +21 to +27: (unused / REL)
        # +28 to +29: File size in sectors (little-endian)
        # +30 to +31: (unused)
        dir_sec[off + 0] = ftype          # File type
        dir_sec[off + 1] = track          # Track of first data sector
        dir_sec[off + 2] = sector         # Sector of first data sector
        for j in range(16):
            b = name[j] if j < len(name) else 0xA0
            dir_sec[off + 3 + j] = b
        # +21 to +29: side-sector / REL / unused = 0
        dir_sec[off + 28] = size & 0xFF   # Size low byte
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

    # Unused header bytes ($A0) at 160-161 and 164
    bam[160] = 0xA0
    bam[161] = 0xA0
    bam[164] = 0xA0

    # Disk ID (2 chars at 162-163)
    bam[162] = ord('T')
    bam[163] = ord('S')

    # DOS type (2 chars at 165-166)
    bam[165] = ord('2')
    bam[166] = ord('A')
    
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


def make_d64(boot_sector_bin, z80_boot_bin, sysres_bin, hello_bin, hello_asm_bin, trsmark_bin, trsmark_asm_bin, output_path):
    """Create D64 image with boot sector, Z80 boot code, SYSRES, and TRSDOS files."""
    # Initialize D64 with zeros
    d64 = bytearray(TOTAL_BYTES)

    # Place 8502 boot sector at track 1, sector 0
    boot_data = boot_sector_bin[:256]
    boot_data = boot_data.ljust(256, b'\x00')
    off = track_sector_to_offset(1, 0)
    d64[off:off + 256] = boot_data

    # The 8502 KERNAL BLOCK-READs the flat SYSRES via the boot-sector
    # extra-sector mechanism, sequentially from track 1 sector 1 (full
    # 256-byte sectors, no link/load-address header) into the staging
    # area at $0C00 (see boot_sector.s). So SYSRES must start at T1S1.
    # Z80 boot (a normal PRG file loaded by the KERNAL) is moved to a
    # free track (6) once T1-T5 are held by SYSRES.
    sysres_sectors, used_sysres, n_sysres_sectors = \
        make_raw_sectors(sysres_bin, 1, 1)
    for trk, sec, sec_data in sysres_sectors:
        off = track_sector_to_offset(trk, sec)
        d64[off:off + 256] = sec_data

    # Place Z80 boot code as PRG file at track 6, sectors 0-N (free track).
    # The Z80 stub is small (VDC init + LDIR copy + jump).
    prg_sectors = make_prg_sectors(z80_boot_bin, 0x8000, 6, 0)
    used_z80 = set()
    for trk, sec, sec_data in prg_sectors:
        off = track_sector_to_offset(trk, sec)
        d64[off:off + 256] = sec_data
        used_z80.add(sec)
    n_z80_sectors = len(prg_sectors)

    # Collect used sectors per track for BAM
    usage = {1: {0}, 18: {0, 1}}
    for trk, sec, _ in sysres_sectors:
        usage.setdefault(trk, set()).add(sec)
    for trk, sec, _ in prg_sectors:
        usage.setdefault(trk, set()).add(sec)

    # Place HELLO/CMD at track 7, sector 0 — TRSDOS only (no CBM DOS directory entry).
    # Stored RAW as a TRSDOS .CMD executable (record format), not a CBM PRG.
    hello_secs = []
    for i in range(0, len(hello_bin), 256):
        chunk = hello_bin[i:i + 256].ljust(256, b'\x00')
        hello_secs.append((7, i // 256, chunk))
        usage.setdefault(7, set()).add(i // 256)
    for trk, sec, sec_data in hello_secs:
        off = track_sector_to_offset(trk, sec)
        d64[off:off + 256] = sec_data

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

    # Place TRSMARK/CMD after HELLO/ASM on track 7 — TRSDOS only.
    trk, sec = 7, hello_asm_end_sec
    trsmark_secs = []
    for i in range(0, len(trsmark_bin), 256):
        chunk = trsmark_bin[i:i + 256].ljust(256, b'\x00')
        d64[track_sector_to_offset(trk, sec):][:256] = chunk
        usage.setdefault(trk, set()).add(sec)
        trsmark_secs.append((trk, sec))
        sec += 1
        if sec >= 21:
            trk += 1; sec = 0
    trsmark_end_sec = sec

    # ------------------------------------------------------------------
    # LS-DOS on-disk directory (byte-correct structural reference).
    # Laid out on track 20 (DIR_TRACK) per the C128 port DCT, using the
    # LS-DOS granule format so HELLO/TRSMARK/HELLO-ASM are stored exactly
    # as TRSDOS @DIRRD/@HITRD/GETEXT would decode them.  This is NOT
    # natively operable (36-sect/cyl dir model vs CBM track geometry; the
    # port's runtime IEC also bit-bangs $DD00, see AGENTS.md), but the
    # structures are byte-correct and validated by make check.
    # ------------------------------------------------------------------
    # File data lives in LS-DOS granules starting at cylinder 21 (dir cyl
    # is 20).  Each granule = 6 sectors starting at (cyl, gran*6).
    def store_granule_file(buf, start_cyl, start_gran):
        """Write LS-DOS granule data; return (next_cyl, next_gran)."""
        cyl, gran = start_cyl, start_gran
        off = 0
        total = len(buf)
        while off < total:
            sec_base = gran * lsdir.SECTORS_PER_GRAN
            for n in range(lsdir.SECTORS_PER_GRAN):
                if off >= total:
                    break
                sec = sec_base + n
                if sec >= n_sect_for_track(cyl):
                    gran = 0
                    cyl += 1
                    sec_base = 0
                    sec = n
                chunk = buf[off:off + 256].ljust(256, b'\x00')
                foff = track_sector_to_offset(cyl, sec)
                d64[foff:foff + 256] = chunk
                usage.setdefault(cyl, set()).add(sec)
                off += 256
            gran += 1
            if gran >= 3:
                gran = 0
                cyl += 1
        return cyl, gran

    ls_specs = []
    _runs = []
    if hello_data:
        _runs.append(('HELLO', 'CMD', 0x10, hello_data, 21, 0))
    if trsmark_data:
        _runs.append(('TRSMARK', 'CMD', 0x10, trsmark_data, 22, 0))
    if hello_asm_data:
        _runs.append(('HELLO', 'ASM', 0x10, hello_asm_data, 23, 0))
    if trsmark_asm_data:
        _runs.append(('TRSMARK', 'ASM', 0x10, trsmark_asm_data, 24, 0))

    for name, ext, attrs, data, c, g in _runs:
        ls_specs.append(dict(name=name, ext=ext, attrs=attrs, data=data,
                             data_start_cyl=c, data_start_gran=g))
        store_granule_file(data, c, g)

    _ls_sectors, _ls_meta = lsdir.build_directory(ls_specs, sector_writer=None)

    for (trk, sec), buf in _ls_sectors.items():
        if sec >= n_sect_for_track(trk):
            continue
        d64[track_sector_to_offset(trk, sec):track_sector_to_offset(trk, sec) + 256] = buf
        usage.setdefault(trk, set()).add(sec)

    # Create directory with Z80BOOT entry (HELLO/TRSMARK are TRSDOS-only, no CBM dir entry)
    z80_first = prg_sectors[0]
    dir_sec = make_directory(n_z80_sectors, z80_first[0], z80_first[1])
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
    print(f"  SYSRES (flat, extra sectors): tracks 1-{sysres_sectors[-1][0]}, s{min(s for _,s,_ in sysres_sectors)}-s{max(s for _,s,_ in sysres_sectors)}, {n_sysres_sectors} sectors ({len(sysres_bin)} bytes staged at $0C00, copied to $0000)")
    print(f"  Z80 boot (PRG): track 6, sectors 0-{n_z80_sectors-1} ({len(z80_boot_bin)} bytes)")
    print(f"  HELLO/CMD: track 7, sector 0, {len(hello_secs)} sector(s) (TRSDOS-only)")
    print(f"  HELLO/ASM: track 7, sector 1-{hello_asm_end_sec-1} (TRSDOS-only)")
    print(f"  TRSMARK/CMD: track 7, sectors {trsmark_secs[0][1]}..{trsmark_end_sec-1}, {len(trsmark_secs)} sector(s) ({len(trsmark_bin)} bytes) (TRSDOS-only)")
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

    # TRSMARK/CMD is optional (TRSDOS-only)
    trsmark_bin = os.path.join(build_dir, 'trsmark.cmd')
    trsmark_data = b''
    if os.path.exists(trsmark_bin):
        with open(trsmark_bin, 'rb') as f:
            trsmark_data = f.read()

    # TRSMARK/ASM source is optional (TRSDOS-only)
    trsmark_asm_path = os.path.join(script_dir, 'trsmark.asm')
    trsmark_asm_data = b''
    if os.path.exists(trsmark_asm_path):
        with open(trsmark_asm_path, 'rb') as f:
            trsmark_asm_data = f.read()

    make_d64(boot_data, z80_data, sysres_data, hello_data, hello_asm_data, trsmark_data, trsmark_asm_data, output)

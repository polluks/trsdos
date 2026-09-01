#!/usr/bin/env python3
"""Create a CPC DSK disk image with TRSDOS boot sector and SYSRES.

Extended DSK format (CPCEMU compatible):
- 40 tracks, 1 side, 9 sectors/track, 512 bytes/sector
- T0S0: Boot sector (512 bytes, loaded to $0000 by CPC firmware)
- T0S1-T5S1: SYSRES flat image (45 sectors x 512 = 23040 bytes)
"""

import struct
import os
import sys

import trsdos_lsdir as lsdir

# CF2 double-density format
NUM_TRACKS = 40
NUM_SIDES = 1
SECS_PER_TRACK = 9
SEC_SIZE = 512
SEC_SIZE_CODE = 2  # N=2 for 512 bytes

# Track header constants
GAP_FILLER = 0x4E

def make_dsk_header(num_tracks=40, num_sides=1, sectors_per_track=None):
    """Create extended DSK header (256 bytes).

    sectors_per_track: list of sector counts (len == num_tracks). If None,
    all tracks assume SECS_PER_TRACK. Per-track byte size = 256 header + n*512.
    """
    hdr = bytearray(256)

    # Magic signature (34 bytes)
    magic = b'MV - CPCEMU-DSK\x0d\x0aDisk-Info\x0d\x0a'
    hdr[0:len(magic)] = magic

    # Unused byte (typically '0' or '1' or '2' for extended)
    hdr[34] = ord('2')

    # Number of tracks
    hdr[35] = num_tracks

    # Number of sides
    hdr[36] = num_sides

    # Track size table: size of each track in 256-byte blocks
    # Standard track: 256 header + 9 x 512 = 4864 bytes = 19 blocks.
    # Track 0 carries the boot sector (S0) plus 9 SYSRES sectors = 10 sectors
    # = 256 + 10*512 = 5376 bytes = 21 blocks.
    for t in range(num_tracks):
        n = SECS_PER_TRACK if sectors_per_track is None else sectors_per_track[t]
        hdr[37 + t] = (256 + n * SEC_SIZE) // 256

    return bytes(hdr)


def make_track_header(track, side, sector_data_map):
    """Create track info header (256 bytes).

    sector_data_map: dict mapping sector_number -> 512-byte data bytes
    """
    hdr = bytearray(256)

    # Track info identifier
    hdr[0] = 0x00
    hdr[1] = 0x00

    # Track number
    hdr[2] = track

    # Side number
    hdr[3] = side

    # Data rate: 2 = DD/MFM
    hdr[4] = 2

    # Recording mode: 1 = MFM
    hdr[5] = 1

    # Sector size code
    hdr[6] = SEC_SIZE_CODE

    # Number of sectors on this track
    n_sectors = len(sector_data_map)
    hdr[7] = n_sectors

    # Gap filler
    hdr[8] = GAP_FILLER
    hdr[9] = GAP_FILLER
    hdr[10] = GAP_FILLER
    hdr[11] = GAP_FILLER

    # Sector info list (8 bytes per sector)
    for i, sec_num in enumerate(sorted(sector_data_map.keys())):
        off = 12 + i * 8
        hdr[off] = track       # C
        hdr[off + 1] = side    # H
        hdr[off + 2] = sec_num # R (1-based)
        hdr[off + 3] = SEC_SIZE_CODE  # N
        hdr[off + 4] = 1       # ST0 (no error)
        hdr[off + 5] = 0       # ST1
        hdr[off + 6] = 0       # ST2
        hdr[off + 7] = 0       # GPA

    return bytes(hdr)


def make_dsk(boot_bin, sysres_bin, hello_cmd, trsmark_cmd, hello_asm, trsmark_asm, output_path):
    """Create DSK image with boot sector, SYSRES, and a byte-correct LS-DOS
    on-disk directory (logical mirror of the C128 D64 layout)."""
    # Boot sector must fit in one sector
    if len(boot_bin) > SEC_SIZE:
        print(f"ERROR: Boot sector too large ({len(boot_bin)} > {SEC_SIZE})")
        sys.exit(1)

    boot_data = boot_bin[:SEC_SIZE].ljust(SEC_SIZE, b'\x00')

    # SYSRES data
    if len(sysres_bin) > 45 * SEC_SIZE:
        print(f"ERROR: SYSRES too large ({len(sysres_bin)} > {45 * SEC_SIZE})")
        sys.exit(1)

    sysres_data = sysres_bin[:45 * SEC_SIZE]
    # Pad to multiple of sector size
    sysres_padded = sysres_data.ljust(45 * SEC_SIZE, b'\x00')

    dsk = bytearray()

    # Build sector maps for each track.
    # boot_cpc.asm reads N_SYS_SECTORS sectors sequentially from T0S1,
    # 9 sectors/track (S1-S9, wrapping to the next track after sector 9).
    # So SYSRES fills S1-S9 on tracks 0..(n-1), boot at T0S0.
    n_sys_sectors = (len(sysres_padded) + SEC_SIZE - 1) // SEC_SIZE
    track_sectors = {}

    track = 0
    sector = 1
    sysres_off = 0
    while sysres_off < len(sysres_padded):
        if track not in track_sectors:
            track_sectors[track] = {}
        track_sectors[track][sector] = sysres_padded[sysres_off:sysres_off + SEC_SIZE]
        sysres_off += SEC_SIZE
        sector += 1
        if sector > SECS_PER_TRACK:
            sector = 1
            track += 1

    track_sectors.setdefault(0, {})[0] = boot_data

    # ------------------------------------------------------------------
    # LS-DOS on-disk directory (byte-correct logical mirror of the C128
    # D64 layout).  Uses the same TRSDOS logical geometry (dir cyl 20,
    # granule = 6 x 256-byte sectors, 3 granules/cyl) so the GAT/HIT/dir
    # and file extents match what lsdir/@DIRRD/GETEXT decode on the C128.
    # Each 256-byte logical sector is written into one 512-byte DSK physical
    # sector (first half, second half unused), at (cyl + lsec//9, lsec%9 + 1).
    # This is a structural reference, not natively navigable on the CPC.
    # ------------------------------------------------------------------
    def place_logical(cyl, lsec, data256):
        """Write a 256-byte logical sector into the 512-byte physical map."""
        trk = cyl + lsec // SECS_PER_TRACK
        sec = (lsec % SECS_PER_TRACK) + 1
        track_sectors.setdefault(trk, {})[sec] = bytes(data256).ljust(SEC_SIZE, b'\x00')

    ls_specs = []
    if hello_cmd:
        ls_specs.append(dict(name='HELLO', ext='CMD', attrs=0x10, data=hello_cmd,
                             data_start_cyl=21, data_start_gran=0))
    if trsmark_cmd:
        ls_specs.append(dict(name='TRSMARK', ext='CMD', attrs=0x10, data=trsmark_cmd,
                             data_start_cyl=22, data_start_gran=0))
    if hello_asm:
        ls_specs.append(dict(name='HELLO', ext='ASM', attrs=0x10, data=hello_asm,
                             data_start_cyl=23, data_start_gran=0))
    if trsmark_asm:
        ls_specs.append(dict(name='TRSMARK', ext='ASM', attrs=0x10, data=trsmark_asm,
                             data_start_cyl=24, data_start_gran=0))

    for f in ls_specs:
        for (cyl, lsec), buf in lsdir.lay_granule_file(
                f['data'], f['data_start_cyl'], f['data_start_gran']).items():
            place_logical(cyl, lsec, buf)

    _ls_sectors, _ls_meta = lsdir.build_directory(ls_specs, sector_writer=None)
    for (trk, lsec), buf in _ls_sectors.items():
        place_logical(trk, lsec, buf)

    # Normalize every track to a full 9 sectors (zero-fill any gaps) and fill
    # any remaining tracks, so the DSK has a uniform, valid geometry.
    for trk in range(NUM_TRACKS):
        secs = track_sectors.setdefault(trk, {})
        for s in range(1, SECS_PER_TRACK + 1):
            secs.setdefault(s, b'\x00' * SEC_SIZE)
        track_sectors[trk] = secs

    # Per-track sector counts for the DSK header size table
    sectors_per_track = [len(track_sectors[t]) for t in range(NUM_TRACKS)]
    dsk.extend(make_dsk_header(NUM_TRACKS, NUM_SIDES, sectors_per_track))

    # Write track data blocks
    for track in range(NUM_TRACKS):
        secs = track_sectors.get(track, {})
        hdr = make_track_header(track, 0, secs)
        dsk.extend(hdr)
        for sec_num in sorted(secs.keys()):
            dsk.extend(secs[sec_num])

    # Write output
    with open(output_path, 'wb') as f:
        f.write(dsk)

    n_sys_secs = (len(sysres_bin) + SEC_SIZE - 1) // SEC_SIZE
    print(f"DSK created: {output_path}")
    print(f"  Size: {len(dsk)} bytes")
    print(f"  Format: {NUM_TRACKS} tracks, {NUM_SIDES} side(s), {SECS_PER_TRACK} sectors/track, {SEC_SIZE} bytes/sector")
    print(f"  Boot sector: track 0, sector 0 ({len(boot_data)} bytes)")
    print(f"  SYSRES: tracks 0-5, {n_sys_secs} sectors ({len(sysres_bin)} bytes)")
    print(f"  LS-DOS dir (logical mirror): track 20 GAT/HIT/dir + granules in {len(ls_specs)} files")
    return True


if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))
    build_dir = os.path.join(script_dir, 'build')
    sysres_dir = os.path.join(build_dir, 'sysres')

    boot_bin = os.path.join(build_dir, 'boot_cpc.bin')
    sysres_bin = os.path.join(sysres_dir, 'boot_sysres.bin')
    output = os.path.join(script_dir, 'trsdos_cpc.dsk')

    for path, name in [(boot_bin, 'CPC Boot sector'), (sysres_bin, 'SYSRES')]:
        if not os.path.exists(path):
            print(f"ERROR: {path} ({name}) not found. Run build first.")
            sys.exit(1)

    with open(boot_bin, 'rb') as f:
        boot_data = f.read()
    with open(sysres_bin, 'rb') as f:
        sysres_data = f.read()

    # TRSDOS files bundled on the disk (logical mirror of the D64 layout).
    def read_optional(path):
        if os.path.exists(path):
            with open(path, 'rb') as f:
                return f.read()
        return b''

    hello_cmd = read_optional(os.path.join(build_dir, 'hello.cmd'))
    trsmark_cmd = read_optional(os.path.join(build_dir, 'trsmark.cmd'))
    hello_asm = read_optional(os.path.join(script_dir, 'hello.asm'))
    trsmark_asm = read_optional(os.path.join(script_dir, 'trsmark.asm'))

    make_dsk(boot_data, sysres_data, hello_cmd, trsmark_cmd, hello_asm, trsmark_asm, output)

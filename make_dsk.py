#!/usr/bin/env python3
"""Create a CPC DSK disk image with TRSDOS boot sector and compressed SYSRES.

Extended DSK format (CPCEMU compatible):
- 40 tracks, 1 side, 9 sectors/track, 512 bytes/sector
- T0S0: Boot sector (512 bytes, loaded to $0000 by CPC firmware)
- T0S1+: Exomizer-compressed SYSRES blob (~14 sectors vs 45 raw)
"""

import struct
import os
import sys

# CF2 double-density format
NUM_TRACKS = 40
NUM_SIDES = 1
SECS_PER_TRACK = 9
SEC_SIZE = 512
SEC_SIZE_CODE = 2  # N=2 for 512 bytes

# Track header constants
GAP_FILLER = 0x4E

def make_dsk_header(num_tracks=40, num_sides=1):
    """Create extended DSK header (256 bytes)."""
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
    # Standard track size for 9 sectors x 512 bytes = 4608 bytes + 256 header = 4864
    # 4864 / 256 = 19 blocks
    track_blocks = (256 + SECS_PER_TRACK * SEC_SIZE) // 256  # 19
    for t in range(num_tracks):
        hdr[37 + t] = track_blocks

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


def make_dsk(boot_bin, packed_bin, output_path):
    """Create DSK image with boot sector and compressed SYSRES blob."""
    if len(boot_bin) > SEC_SIZE:
        print(f"ERROR: Boot sector too large ({len(boot_bin)} > {SEC_SIZE})")
        sys.exit(1)

    boot_data = boot_bin[:SEC_SIZE].ljust(SEC_SIZE, b'\x00')

    # Pad packed blob to sector boundary
    n_secs = (len(packed_bin) + SEC_SIZE - 1) // SEC_SIZE
    packed_padded = packed_bin.ljust(n_secs * SEC_SIZE, b'\x00')

    dsk = bytearray()

    # Write DSK header
    dsk.extend(make_dsk_header(NUM_TRACKS, NUM_SIDES))

    # Build sector maps for each track
    # T0: S0=boot, S1-S8=first 8 sectors of packed blob
    # T1+: remaining sectors of packed blob

    track_sectors = {}
    off = 0

    # Track 0
    t0_secs = {0: boot_data}
    for s in range(1, SECS_PER_TRACK + 1):
        if off < len(packed_padded):
            t0_secs[s] = packed_padded[off:off + SEC_SIZE]
            off += SEC_SIZE
    track_sectors[0] = t0_secs

    # Remaining tracks
    for track in range(1, NUM_TRACKS):
        secs = {}
        any_data = False
        for s in range(1, SECS_PER_TRACK + 1):
            if off < len(packed_padded):
                secs[s] = packed_padded[off:off + SEC_SIZE]
                off += SEC_SIZE
                any_data = True
            else:
                secs[s] = b'\x00' * SEC_SIZE
        track_sectors[track] = secs
        if not any_data:
            break

    # Remaining empty tracks
    for track in range(len(track_sectors), NUM_TRACKS):
        secs = {}
        for s in range(1, SECS_PER_TRACK + 1):
            secs[s] = b'\x00' * SEC_SIZE
        track_sectors[track] = secs

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

    print(f"DSK created: {output_path}")
    print(f"  Size: {len(dsk)} bytes")
    print(f"  Format: {NUM_TRACKS} tracks, {NUM_SIDES} side(s), {SECS_PER_TRACK} sectors/track, {SEC_SIZE} bytes/sector")
    print(f"  Boot sector: track 0, sector 0 ({len(boot_data)} bytes)")
    print(f"  Packed blob: {n_secs} sectors ({len(packed_bin)} bytes, {len(packed_bin) - 148} compressed)")
    return True


if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))
    build_dir = os.path.join(script_dir, 'build')
    sysres_dir = os.path.join(build_dir, 'sysres')

    boot_bin = os.path.join(build_dir, 'boot_cpc.bin')
    packed_bin = os.path.join(sysres_dir, 'sysres_packed.bin')
    output = os.path.join(script_dir, 'trsdos_cpc.dsk')

    for path, name in [(boot_bin, 'CPC Boot sector'), (packed_bin, 'Packed SYSRES')]:
        if not os.path.exists(path):
            print(f"ERROR: {path} ({name}) not found. Run build first.")
            sys.exit(1)

    with open(boot_bin, 'rb') as f:
        boot_data = f.read()
    with open(packed_bin, 'rb') as f:
        packed_data = f.read()

    make_dsk(boot_data, packed_data, output)

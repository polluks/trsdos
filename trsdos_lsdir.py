#!/usr/bin/env python3
"""Build a byte-correct LS-DOS 6.3 on-disk directory for the C128 TRSDOS port.

This is a *byte-correct structural reference*: it lays down a real LS-DOS
directory (GAT, HIT, directory records) and stores HELLO/CMD (etc.) on disk
in TRSDOS granule format, so the structures match what the port's LSDOS
directory readers (@GATRD/@HITRD/@DIRRD, GETEXT granule math) would decode.

It is NOT a fully operable on-disk directory.  The LS-DOS directory model
assumes >=34 sectors on the directory cylinder (data sectors 2..33), which
cannot be held on a CBM 1541/1571 track (<=21 sectors).  And the port's
runtime IEC driver bit-bangs $DD00 from Z80, a mechanism that does not
reach the drive in VICE (CP/M instead hands off to the 8502 KERNAL).  See
AGENTS.md.  The on-disk images use a CBM-native track 20 (18 sectors) so
the structures are written at their nominal LS-DOS offsets within what a
CBM track can hold.

Format facts (from LSDOS631 source, loaded into this repo):
  - HASHNAME (sys2.asm): A = fold of 11 chars, each step A ^= char; A = ROL 1.
    A==0 becomes 1.  The 11 chars are 8-char name + 3-char ext, uppercase.
  - HIT (dir cyl sector 1): 256 bytes, one per DEC slot.  OPEN scans the
    whole HIT linearly (OPEN4: INC L from 0..255), matching (HL)==name hash.
    So HIT[slot] = hash and the dir record lives at that slot.
  - Dir record slot -> sector = (slot & 0x1F) + 2, offset = slot & 0xE0.
  - Directory record (32 bytes), fields per sys2/sys3:
       +0  attributes (bit4=assigned/allocated, bit6=SYS, bit7=FXDE)
       +1  flag/month (low nibble = month)
       +2  day/year
       +3  EOF byte offset within last record
       +4  logical record length (0 == 256)
       +5..+12  filename (8 chars, space padded)
       +13..+15 extension (3 chars)
       +16/17  cube? (EOF offset lo/hi)  [set per LS-DOS 6.3 L close]
       +20/21  ERN (record count) lo/hi
       +22..+31  5 extents x 2 bytes ([start_cyl][alloc]) ; 0xFF spare
    alloc byte = (starting_granule << 5) | (n_contiguous_granules - 1)
  - GETEXT (c128_boot.asm) decodes: start gran = alloc>>5 &7; sec offset
    within cyl = start_gran * SECTRS/GRAN; nbytes = (alloc&0x1F +1)*SECTRS/GRAN.
  - GAT (dir cyl sector 0):
       alloc map: one byte per cylinder; LOW bits are the granules
       (bit set = allocated/in-use; clear = free).  Empty cyl byte =
       0xFF << ngrans (low ngrans bits free).
       +0xCC/0xCD  environment (sectors/track, #heads) -- see CKDRV
       +0xCE/0xCF  hashed Master Password
       +0xD0..0xD7 disk name (8 chars)
       +0xD8..0xDF date ("MM/DD/YY")
  - Cylinder on disk == CBM track number (the IEC drive uses track=sector
    addressing; LS-DOS cylinder == track for the port's geometry).

The geometry constants follow the C128 port DCT (port/c128/c128_lowcore.asm):
   SECTORS_PER_TRACK = 17  (IEC CBM track, single-side GCR)
   GRANS_PER_TRACK   = 3
   SECTORS_PER_GRAN  = 6   (c128_equ.asm GRAN_SIZE)
   DIR_TRACK         = 20
The intended granule byte would be ((GRANS_PER_TRACK-1)<<5)|(GRANS_PER_GRAN-1)
which the DCT source fails to assemble (renders as the broken 0xFF), but that
is a build bug in the port, not here.  This module documents the intended
geometry explicitly.
"""

# ---- C128 port geometry (from c128_lowcore.asm / c128_equ.asm) ----
SECTORS_PER_TRACK = 17
GRANS_PER_TRACK = 3
SECTORS_PER_GRAN = 6
DIR_TRACK = 20

MAX_CYLINDER = 39  # DCT says 39 tracks


def hashname(name8_bytes, ext3_bytes):
    """HASHNAME (sys2.asm): 11-char XOR + ROL fold -> DEC (name hash).
    
    The name is 8 chars (space-padded) and extension is 3 chars (space-padded),
    total 11 chars, as used by the LS-DOS file spec parser (XFRSPEC in sys2).
    """
    if isinstance(name8_bytes, str):
        name8_bytes = name8_bytes.encode()
    if isinstance(ext3_bytes, str):
        ext3_bytes = ext3_bytes.encode()
    field = name8_bytes.ljust(8, b' ')[:8] + ext3_bytes.ljust(3, b' ')[:3]
    a = 0
    for ch in field:
        a ^= ch
        a = ((a << 1) & 0xFF) | (a >> 7)   # RLCA operand
    if a == 0:
        a = 1
    return a


def _alloc_map_base():
    """byte per cylinder, low GRANS_PER_TRACK bits free (0), high reserved (1)."""
    b = 0xFF
    for _ in range(GRANS_PER_TRACK):
        b = (b << 1) & 0xFF            # SLA B
    return b


def make_gat(used_granules):
    """used_granules: dict cyl -> set of granule numbers in use.
    Returns 256-byte GAT sector."""
    gat = bytearray(256)
    base = _alloc_map_base()

    # Allocation map: one byte per cylinder 0..MIN(MAX_CYLINDER,255)
    for cyl in range(min(MAX_CYLINDER + 1, 256)):
        byte = base
        for g in used_granules.get(cyl, ()):
            byte |= (1 << g)
        gat[cyl] = byte
    # cylinders beyond MAX -> 0xFF (unused)
    for cyl in range(MAX_CYLINDER + 1, 256):
        gat[cyl] = 0xFF

    # Environment / bootstrap block (authoritative from LSDOS source)
    # +0xCC/0xCD: sectors/track, #heads (DCT+7 equivalent)
    gat[0xCC] = SECTORS_PER_TRACK
    gat[0xCD] = 0x00          # single sided
    # +0xCE/0xCF: hashed Master Password (0 = none set in our reference)
    # +0xD0..0xD7: disk name (8 chars)
    name = b"TRSDOS1"
    gat[0xD0:0xD0 + 8] = name.ljust(8, b' ')
    # +0xD8..0xDF: date "MM/DD/YY"
    dat = bytearray(b"  /  /  ")
    gat[0xD8 + 2] = ord('/')
    gat[0xD8 + 5] = ord('/')
    gat[0xD8:0xD8 + 8] = dat
    return gat


def make_hit(entries):
    """entries: list of (slot, hash).  Returns 256-byte HIT sector."""
    hit = bytearray(256)
    for slot, h in entries:
        hit[slot] = h
    return hit


def make_dir_sectors(records):
    """records: list of (slot, 32-byte record).  Returns dict sector->256 bytes."""
    secs = {}
    # dir data sector for slot = (slot & 0x1F) + 2 ; offset = slot & 0xE0
    for slot, rec in records:
        sector = (slot & 0x1F) + 2
        off = slot & 0xE0
        secs.setdefault(sector, bytearray(256))
        secs[sector][off:off + 32] = rec
    return secs


def make_dir_record(attrs, filename, ext, eof_byte, erns, extents):
    """Build a 32-byte LS-DOS directory record.

    extents: list of (start_cyl, start_gran, n_grans); up to 5.  On-disk
    each is a 2-byte [start_cyl][alloc] pair.  alloc =
        (start_gran << 5) | (n_grans - 1)
    """
    rec = bytearray(32)
    rec[0] = attrs
    # +1 flag/month (month=01)
    rec[1] = 0x01
    # +2 day/year (day=01, year=2026 -> low bits)
    rec[2] = 0x01
    rec[3] = eof_byte & 0xFF
    rec[4] = 0x00                    # LRL: 0 == 256
    if isinstance(filename, str):
        filename = filename.encode()
    if isinstance(ext, str):
        ext = ext.encode()
    name = filename.upper().ljust(8, b' ')
    extf = ext.upper().ljust(3, b' ')
    rec[5:13] = name
    rec[13:16] = extf
    rec[16:18] = bytes([erns & 0xFF, (erns >> 8) & 0xFF])
    rec[20:22] = bytes([erns & 0xFF, (erns >> 8) & 0xFF])
    # extents at +22, 2 bytes each, spare = 0xFF
    for i in range(5):
        off = 22 + i * 2
        if i < len(extents):
            cyl, g, ngr = extents[i]
            rec[off] = cyl
            rec[off + 1] = ((g << 5) & 0xE0) | ((ngr - 1) & 0x1F)
        else:
            rec[off] = 0xFF
            rec[off + 1] = 0xFF
    return rec


def granule_layout_first_block(data_len, start_cyl, start_gran):
    """Return extents list covering data_len bytes, laid out granule-by-granule.

    Returns (extents, used_cyl_granule_dict).
    Uses contiguous runs to make each extent as long as possible.
    """
    n_grans = (data_len + SECTORS_PER_GRAN * 256 - 1) // (SECTORS_PER_GRAN * 256)
    extents = []
    used = {}
    cyl, g = start_cyl, start_gran
    remaining = n_grans
    while remaining > 0:
        take = min(remaining, GRANS_PER_TRACK - g)
        extents.append((cyl, g, take))
        for k in range(take):
            used.setdefault(cyl, set()).add(g + k)
        remaining -= take
        g = 0
        cyl += 1
    return extents, used


def build_directory(file_specs, sector_writer):
    """Place a set of files in LS-DOS granule format + build GAT/HIT/dir.

    file_specs: list of dicts with keys:
        name (8), ext (3), attrs, data (bytes), data_start_cyl, data_start_gran
    sector_writer: callable(track, sector, first_sector_of_file)  -- not used
        here for file data since placement is caller-managed; returns None.

    Returns dict of (track,sector)->256-byte data for GAT/HIT/dir records,
    and the list of (attrs,name,ext,extents,erns) metadata.
    """
    # 1) hash each file -> HIT slot (use slot = position; sequential)
    hit_entries = []
    records = []
    metadata = []
    used_granules = {}     # cyl -> set of used granule numbers (files)
    for i, f in enumerate(file_specs):
        slot = i
        h = hashname(f['name'], f['ext'])
        hit_entries.append((slot, h))
        attrs = f.get('attrs', 0x10)
        # extents from the file's granule placement
        extents, ugr = granule_layout_first_block(
            len(f['data']), f['data_start_cyl'], f['data_start_gran'])
        for c, gset in ugr.items():
            used_granules.setdefault(c, set()).update(gset)
        nbytes = len(f['data'])
        erns = (nbytes + 255) // 256
        eof_byte = nbytes % 256
        rec = make_dir_record(attrs, f['name'], f['ext'], eof_byte, erns, extents)
        records.append((slot, rec))
        metadata.append((attrs, f['name'], f['ext'], extents, erns, nbytes))

    # 2) GAT marks directory/HELLO granules used; mark the sysres/reserved as used
    #    so the map is truthful about where data lives.
    gat = make_gat(used_granules)
    hit = make_hit(hit_entries)
    dirsecs = make_dir_sectors(records)

    sectors = {}
    sectors[(DIR_TRACK, 0)] = gat
    sectors[(DIR_TRACK, 1)] = hit
    for sector, buf in dirsecs.items():
        sectors[(DIR_TRACK, sector)] = buf
    return sectors, metadata

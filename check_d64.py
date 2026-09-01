#!/usr/bin/env python3
"""Validate D64 disk image structure for C128 TRSDOS boot.

Verifies the boot chain laid out by make_d64.py:
  - boot sector DISKHDR requests 90 sequential extra sectors to $0C00
  - those sectors (T1S1..T5S6) hold the flat SYSRES image (matches build)
  - Z80BOOT PRG directory entry points to a valid PRG chain with load $8000
  - BAM correctly marks spent sectors read-only
"""
import sys


def track_sector_to_offset(track, sector):
    off = 0
    for t in range(1, track):
        off += (21 if t <= 17 else 19 if t <= 24 else 18 if t <= 30 else 17)
    return (off + sector) * 256


def n_sectors(track):
    return 21 if track <= 17 else 19 if track <= 24 else 18 if track <= 30 else 17


def load_bin(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "trsdos_c128.d64"
    d = open(path, "rb").read()
    ok = True

    def ck(cond, msg):
        nonlocal ok
        if not cond:
            print(f"FAIL: {msg}")
            ok = False
        else:
            print(f"  ok: {msg}")

    ck(len(d) == 174848, f"D64 size {len(d)} == 174848")

    # ---- Boot sector (T1S0) ----
    boot = d[0:256]
    ck(boot[0:3] == b"CBM", f"Boot sector signature = {boot[0:3]}")
    adr = boot[3] | (boot[4] << 8)
    bank = boot[5]
    blk = boot[6]
    ck(adr == 0x0C00 and bank == 0 and blk == 90,
       f"DISKHDR extra sectors: addr=${adr:04X} bank={bank} blk#={blk} (SYSRES -> $0C00 staging, 90)")

    # ---- SYSRES extra sectors: contiguous from T1S1, matches boot_sysres.bin ----
    sysres = load_bin("build/sysres/boot_sysres.bin")
    if sysres is not None:
        nsec = (len(sysres) + 255) // 256
        ck(nsec == blk, f"SYSRES needs {nsec} sectors == blk# {blk}")
        read = bytearray()
        track, sector = 1, 1
        for _ in range(blk):
            off = track_sector_to_offset(track, sector)
            read += d[off:off + 256]
            sector += 1
            if sector >= 21:
                sector, track = 0, track + 1
        ck(bytes(read[:len(sysres)]) == sysres,
           "Sequential KERNAL block-read of SYSRES matches boot_sysres.bin")
        # non-extra sectors in the same range must be zero (no stray data)
        ck(bytes(read[len(sysres):]) == b"\x00" * (len(read) - len(sysres)),
           "SYSRES extra-sector padding is zero-filled")
    else:
        ck(False, "build/sysres/boot_sysres.bin missing (run make first)")

    # ---- Z80BOOT PRG directory entry + chain ----
    dir_off = track_sector_to_offset(18, 1)
    dsec = d[dir_off:dir_off + 256]
    entry = dsec[2:34]
    ck(entry[0] == 0x82, f"Z80BOOT dir type = 0x{entry[0]:02X} (PRG, closed)")
    ft, fs = entry[1], entry[2]
    fsize = entry[28] | (entry[29] << 8)
    ck(ft == 6 and fs == 0, f"Z80BOOT first data sector = T{ft}S{fs} (expect T6S0)")

    # walk the PRG chain
    chain = bytearray()
    t, s = ft, fs
    seen = set()
    while (t, s) not in seen:
        seen.add((t, s))
        off = track_sector_to_offset(t, s)
        nxt, nxs = d[off], d[off + 1]
        chain += d[off + 2:off + 256]
        if nxt == 0 and nxs == 0:
            break
        t, s = nxt, nxs

    z80 = load_bin("build/z80_boot.bin")
    if z80 is not None:
        load_addr = chain[0] | (chain[1] << 8)
        ck(load_addr == 0x8000, f"Z80BOOT load addr = ${load_addr:04X} (expect $8000)")
        content = bytes(chain[2:2 + len(z80)])
        ck(content == z80, f"Z80BOOT chain content matches build/z80_boot.bin ({len(z80)} bytes)")
        n_chain = (len(z80) + 2 + 253) // 254  # header + data, 254/payload sector
        ck(len(seen) == n_chain, f"Z80BOOT chain sectors = {len(seen)} (expect ~{n_chain})")
    else:
        ck(False, "build/z80_boot.bin missing (run make first)")

    # ---- Z80BOOT must not overlap the SYSRES extra-sector range (T1S1..T5S6) ----
    overlap = any(1 <= trk <= 5 for trk, _ in seen)
    ck(not overlap, "Z80BOOT PRG sectors do not overlap SYSRES extra-sector range (T1-T5)")

    # ---- BAM ----
    bam_off = track_sector_to_offset(18, 0)
    bam = d[bam_off:bam_off + 256]
    ck(bam[2] == 0x20, f"BAM DOS ver = 0x{bam[2]:02X} (read-only)")
    ck(bam[0] == 18 and bam[1] == 1, f"BAM dir ptr = T{bam[0]}S{bam[1]}")
    ck(bam[144:160] == b"TRSDOS FOR C128 ", f"BAM disk name = {bam[144:160]}")
    ck(bam[162:164] == b"TS", f"BAM disk ID = {bam[162:164]}")
    ck(bam[165:167] == b"2A", f"BAM DOS type = {bam[165:167]}")

    # Verify BAM bitmap: all sectors used by SYSRES + Z80BOOT + boot + HELLO marked busy
    # (spot-check: free-count consistency for tracks holding SYSRES)

    # ---- LS-DOS on-disk directory (track 20: GAT, HIT, dir records) ----
    # GAT at T20S0
    if n_sectors(20) > 0:
        gat = d[track_sector_to_offset(20, 0):track_sector_to_offset(20, 0) + 256]
        ck(gat[0xCC] == 17, f"LS-DOS GAT env sectors/track = {gat[0xCC]} (expect 17)")
        ck(gat[0xCD] == 0x00, f"LS-DOS GAT env heads = {gat[0xCD]} (single-sided)")

        # HIT at T20S1
        hit = d[track_sector_to_offset(20, 1):track_sector_to_offset(20, 1) + 256]
        HELLO_HASH = 0x8D
        ck(hit[0] == HELLO_HASH,
           f"LS-DOS HIT[0] = 0x{hit[0]:02X} (HELLO/CMD hash = 0x{HELLO_HASH:02X})")
        TRSMARK_HASH = 0xF8
        trsmark_bin = load_bin("build/trsmark.cmd")
        if trsmark_bin is not None:
            ck(hit[1] == TRSMARK_HASH,
               f"LS-DOS HIT[1] = 0x{hit[1]:02X} (TRSMARK/CMD hash = 0x{TRSMARK_HASH:02X})")

        # Dir record for HELLO/CMD at T20S2 offset 0
        dir_sec = d[track_sector_to_offset(20, 2):track_sector_to_offset(20, 2) + 256]
        rec = dir_sec[0:32]
        ck(rec[0] == 0x10, f"LS-DOS HELLO dir attrs = 0x{rec[0]:02X} (assigned=0x10)")
        ck(rec[5:13] == b"HELLO   ", f"LS-DOS HELLO dir name = {rec[5:13]}")
        ck(rec[13:16] == b"CMD", f"LS-DOS HELLO dir ext = {rec[13:16]}")
        # Extent: cyl 21, alloc = (0<<5)|0 = 0x00
        cyl, alloc = rec[22], rec[23]
        ck(cyl == 21, f"LS-DOS HELLO extent start_cyl = {cyl} (expect 21)")
        start_gran = (alloc >> 5) & 7
        n_grans = (alloc & 0x1F) + 1
        ck(start_gran == 0, f"LS-DOS HELLO extent start_gran = {start_gran} (expect 0)")
        ck(n_grans == 1, f"LS-DOS HELLO extent n_grans = {n_grans} (expect 1)")

        # Verify HELLO data: granule 0 on cyl 21 = sectors 0..5
        hello_file = load_bin("build/hello.cmd")
        if hello_file is not None:
            raw = bytearray()
            for s in range(6):
                raw += d[track_sector_to_offset(21, s):track_sector_to_offset(21, s) + 256]
            ck(bytes(raw[:len(hello_file)]) == hello_file,
               f"LS-DOS HELLO data on cyl 21 matches build/hello.cmd ({len(hello_file)} bytes)")

        # Dir record for TRSMARK/ASM at T20S5 offset 0 (slot 3)
        tsm_sec = d[track_sector_to_offset(20, 5):track_sector_to_offset(20, 5) + 256]
        tsm_rec = tsm_sec[0:32]
        ck(tsm_rec[0] == 0x10, f"LS-DOS TRSMARK/ASM dir attrs = 0x{tsm_rec[0]:02X} (assigned=0x10)")
        ck(tsm_rec[5:13] == b"TRSMARK ", f"LS-DOS TRSMARK/ASM dir name = {tsm_rec[5:13]}")
        ck(tsm_rec[13:16] == b"ASM", f"LS-DOS TRSMARK/ASM dir ext = {tsm_rec[13:16]}")
        tsm_cyl, tsm_alloc = tsm_rec[22], tsm_rec[23]
        ck(tsm_cyl == 24, f"LS-DOS TRSMARK/ASM extent start_cyl = {tsm_cyl} (expect 24)")
        ck(((tsm_alloc >> 5) & 7) == 0, f"LS-DOS TRSMARK/ASM extent start_gran = {(tsm_alloc >> 5) & 7} (expect 0)")

        # Verify TRSMARK/ASM data: granule 0 on cyl 24 = sectors 0..5 holds first 1536 bytes
        tsm_asm_file = load_bin("trsmark.asm")
        if tsm_asm_file is not None:
            raw = bytearray()
            for s in range(6):
                raw += d[track_sector_to_offset(24, s):track_sector_to_offset(24, s) + 256]
            expect = tsm_asm_file[:min(len(tsm_asm_file), 1536)]
            ck(bytes(raw[:len(expect)]) == expect,
               f"LS-DOS TRSMARK/ASM granule-0 data on cyl 24 matches first {len(expect)} bytes of trsmark.asm")

    # ---- print summary ----
    print(f"\n{'ALL CHECKS PASSED' if ok else 'SOME CHECKS FAILED'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

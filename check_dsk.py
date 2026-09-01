#!/usr/bin/env python3
"""Validate CPC DSK disk image structure for TRSDOS boot.

Verifies make_dsk.py output matches the boot_cpc.asm read logic:
  - extended DSK header (CPCEMU compatible), 40 tracks, 1 side
  - boot sector at T0S0 == build/boot_cpc.bin (padded to 512)
  - SYSRES sectors (T0S1.., 9/track, S1-S9) reconstruct boot_sysres.bin
    in the exact sequential order boot_cpc.asm reads them
"""
import sys

SECS_PER_TRACK = 9
SEC_SIZE = 512


def track_size(d, t):
    return d[37 + t] * 256


def get_sector(d, track, sec_1based):
    base = 256
    for t in range(track):
        base += track_size(d, t)
    ns = d[base + 7]
    for i in range(ns):
        r = d[base + 12 + i * 8 + 2]
        if r == sec_1based:
            return d[base + 256 + i * SEC_SIZE: base + 256 + i * SEC_SIZE + SEC_SIZE]
    return None


def get_logical(d, cyl, lsec):
    """Read the first 256 bytes of a logical LS-DOS sector at (cyl, lsec).

    The DSK mirrors each 256-byte logical sector into a 512-byte physical
    sector at track (cyl + lsec//9), sector (lsec%9 + 1).
    """
    sec = get_sector(d, cyl + lsec // SECS_PER_TRACK, (lsec % SECS_PER_TRACK) + 1)
    return None if sec is None else sec[:256]


def load_bin(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "trsdos_cpc.dsk"
    d = open(path, "rb").read()
    ok = True

    def ck(cond, msg):
        nonlocal ok
        if not cond:
            print(f"FAIL: {msg}")
            ok = False
        else:
            print(f"  ok: {msg}")

    # Extended DSK magic (CPCEMU signature, 28 bytes)
    ck(d[0:28] == b'MV - CPCEMU-DSK\x0d\x0aDisk-Info\x0d\x0a',
       "Extended DSK magic (CPCEMU)")
    ck(d[35] == 40, f"Tracks = {d[35]} (expect 40)")
    ck(d[36] == 1, f"Sides = {d[36]} (expect 1)")

    # Boot sector at T0S0 matches boot_cpc.bin
    boot = load_bin("build/boot_cpc.bin")
    if boot is not None:
        ck(len(boot) <= SEC_SIZE, f"boot_cpc.bin size {len(boot)} <= 512")
        b0 = get_sector(d, 0, 0)
        ck(b0 is not None and b0[:len(boot)] == boot,
           f"T0S0 == build/boot_cpc.bin ({len(boot)} bytes)")
    else:
        ck(False, "build/boot_cpc.bin missing (run make first)")

    # SYSRES sectors in boot read order
    sysres = load_bin("build/sysres/boot_sysres.bin")
    if sysres is not None:
        nsec = (len(sysres) + SEC_SIZE - 1) // SEC_SIZE
        buf = bytearray()
        t, e = 0, 1
        for _ in range(nsec):
            sec = get_sector(d, t, e)
            if sec is None:
                break
            buf += sec
            e += 1
            if e > SECS_PER_TRACK:
                e, t = 1, t + 1
        ck(len(buf) == nsec * SEC_SIZE,
           f"Read {len(buf)} bytes across {len(buf)//SEC_SIZE} SYSRES sectors (expect {nsec})")
        ck(bytes(buf[:len(sysres)]) == sysres,
           "Sequential SYSRES read (boot_cpc order) matches boot_sysres.bin")
    else:
        ck(False, "build/sysres/boot_sysres.bin missing (run make first)")

    # ---- LS-DOS on-disk directory (logical mirror, dir cyl 20) ----
    gat = get_logical(d, 20, 0)
    if gat is not None:
        ck(gat[0xCC] == 17, f"LS-DOS GAT env sectors/track = {gat[0xCC]} (expect 17)")
        ck(gat[0xCD] == 0x00, f"LS-DOS GAT env heads = {gat[0xCD]} (single-sided)")
        ck(gat[0xD0:0xD8] == b"TRSDOS1 ", f"LS-DOS GAT disk name = {gat[0xD0:0xD8]}")

        hit = get_logical(d, 20, 1)
        if hit is not None:
            ck(hit[0] == 0x8D, f"LS-DOS HIT[0] = 0x{hit[0]:02X} (HELLO/CMD hash = 0x8D)")
            ck(hit[1] == 0xF8, f"LS-DOS HIT[1] = 0x{hit[1]:02X} (TRSMARK/CMD hash = 0xF8)")
            ck(hit[2] == 0xF7, f"LS-DOS HIT[2] = 0x{hit[2]:02X} (HELLO/ASM hash = 0xF7)")
            ck(hit[3] == 0x82, f"LS-DOS HIT[3] = 0x{hit[3]:02X} (TRSMARK/ASM hash = 0x82)")

    # Dir record for HELLO/CMD at logical slot 0 (dir cyl lsec 2)
    drec = get_logical(d, 20, 2)
    if drec is not None:
        r = drec[:32]
        ck(r[0] == 0x10, f"LS-DOS HELLO/CMD dir attrs = 0x{r[0]:02X} (assigned=0x10)")
        ck(r[5:13] == b"HELLO   " and r[13:16] == b"CMD",
           f"LS-DOS HELLO/CMD dir name/ext = {r[5:13]}/{r[13:16]}")
        ck(r[22] == 21 and (r[23] & 0x1F) == 0,
           f"LS-DOS HELLO/CMD extent cyl21 gran0 (alloc=0x{r[23]:02X})")

    # HELLO/CMD granule-0 data: logical cyl 21, lsec 0..5
    hello = load_bin("build/hello.cmd")
    if hello is not None:
        raw = bytearray()
        for lsec in range(6):
            raw += get_logical(d, 21, lsec)
        ck(bytes(raw[:len(hello)]) == hello,
           f"LS-DOS HELLO/CMD granule-0 data (cyl21 S0-5) matches hello.cmd ({len(hello)} bytes)")

    # TRSMARK/ASM granule-0 data: logical cyl 24, lsec 0..5 (first 1536 bytes)
    tsm_asm = load_bin("trsmark.asm")
    if tsm_asm is not None:
        raw = bytearray()
        for lsec in range(6):
            raw += get_logical(d, 24, lsec)
        expect = tsm_asm[:min(len(tsm_asm), 1536)]
        ck(bytes(raw[:len(expect)]) == expect,
           f"LS-DOS TRSMARK/ASM granule-0 data (cyl24 S0-5) matches first {len(expect)} bytes of trsmark.asm")

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

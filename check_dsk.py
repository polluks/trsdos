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

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

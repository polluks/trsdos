#!/usr/bin/env python3
"""Validate D64 disk image structure."""
import sys

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

    # Boot sector at T1S0
    boot = d[0:256]
    ck(boot[0:3] == b"CBM", f"Boot sector signature = {boot[0:3]}")
    ck(boot[3:5] == b"\x00\x00", f"Boot sector load addr = 0x{boot[3]:02X}{boot[4]:02X} (no extra sectors)")

    # BAM at track 18, sector 0
    bam_off = (18 - 1) * 21 * 256
    bam = d[bam_off:bam_off + 256]
    ck(bam[2] == 0x20, f"BAM DOS ver = 0x{bam[2]:02X} (read-only)")
    ck(bam[0] == 18 and bam[1] == 1, f"BAM dir ptr = T{bam[0]}S{bam[1]}")
    ck(bam[144:160] == b"TRSDOS FOR C128 ", f"BAM disk name = {bam[144:160]}")
    ck(bam[162:164] == b"TS", f"BAM disk ID = {bam[162:164]}")
    ck(bam[165:167] == b"2A", f"BAM DOS type = {bam[165:167]}")

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()

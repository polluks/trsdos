#!/usr/bin/env python3
"""Post-process vasm SYSRES output into a bootable flat memory image.

Reads the vasm listing and binary, extracts individual sections,
and produces a flat image at $0000 with correct data at each address
(DCBs at $0200, file positioning at $1300, etc.) for single-stage boot.
"""
import re
import sys
import os

def flatten_sysres(lst_path, bin_path, output_path):
    # Parse listing to build flat image
    with open(lst_path) as f:
        listing = f.read()

    flat = bytearray()
    prev_addr = -1

    for line in listing.split('\n'):
        m = re.match(r'^(\d+):([0-9A-Fa-f]+)\s+(\S+)', line)
        if not m:
            continue
        addr = int(m.group(2), 16)
        tok = m.group(3)

        if tok == '*':
            val = flat[prev_addr] if 0 <= prev_addr < len(flat) else 0
            if addr + 1 > len(flat):
                flat.extend(b'\x00' * (addr + 1 - len(flat)))
            flat[addr] = val
        elif all(c in '0123456789ABCDEFabcdef' for c in tok) and len(tok) % 2 == 0:
            for i in range(0, len(tok), 2):
                try:
                    byte_addr = addr + i // 2
                    val = int(tok[i:i+2], 16)
                    if byte_addr + 1 > len(flat):
                        flat.extend(b'\x00' * (byte_addr + 1 - len(flat)))
                    flat[byte_addr] = val
                    prev_addr = byte_addr
                except ValueError:
                    pass

    # Now overwrite areas that were corrupted by LOADER overlap
    # DCBs (ORG $200) and file positioning (ORG $1300) get overwritten
    # by the LOADER section (ORG $100, $0100-$1CFF) in the listing flat.
    # Extract these from the vasm binary and place at correct addresses.

    vasm = open(bin_path, 'rb').read()

    # Section sizes from vasm:
    sec_sizes = {
        0x0200: 229,   # DCBs
        0x1300: 1697,  # file positioning
    }

    # Find DCBs by pattern: 00 FE 14 01 00 00 FA 58 05
    dcb_pat = bytes([0x00, 0xFE, 0x14, 0x01, 0x00, 0x00, 0xFA, 0x58, 0x05])
    dcb_start = vasm.find(dcb_pat)
    if dcb_start >= 0:
        dcbs = vasm[dcb_start:dcb_start + sec_sizes[0x0200]]
        for j, b in enumerate(dcbs):
            flat[0x0200 + j] = b if 0x0200 + j < len(flat) else b
        print(f"DCBs ({len(dcbs)} bytes) at ${0x0200:04X}")
    else:
        print("WARNING: DCBs not found!")

    # Find file positioning by pattern: DD E5 D1 CD 8B 15
    fp_pat = bytes([0xDD, 0xE5, 0xD1, 0xCD, 0x8B, 0x15])
    fp_start = vasm.find(fp_pat)
    if fp_start >= 0:
        filposn = vasm[fp_start:fp_start + sec_sizes[0x1300]]
        for j, b in enumerate(filposn):
            addr = 0x1300 + j
            if addr < len(flat):
                flat[addr] = b
        print(f"File positioning ({len(filposn)} bytes) at ${0x1300:04X}")
    else:
        print("WARNING: File positioning not found!")

    with open(output_path, 'wb') as f:
        f.write(flat)

    print(f"Output: {output_path} ({len(flat)} bytes)")
    print(f"Highest address: ${len(flat)-1:04X}")
    return flat

if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))
    trsdos_dir = os.path.dirname(script_dir)
    build_dir = os.path.join(trsdos_dir, 'build', 'sysres')

    lst_path = os.path.join(build_dir, 'sysres.lst')
    bin_path = os.path.join(build_dir, 'sysres.bin')
    output_path = os.path.join(build_dir, 'boot_sysres.bin')

    if not os.path.exists(lst_path):
        print(f"ERROR: {lst_path} not found!")
        sys.exit(1)
    if not os.path.exists(bin_path):
        print(f"ERROR: {bin_path} not found!")
        sys.exit(1)

    flatten_sysres(lst_path, bin_path, output_path)

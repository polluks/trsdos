#!/usr/bin/env python3
"""Wrap a flat Z80 binary into a TRSDOS .CMD executable.

TRSDOS .CMD record format (matching the raw bytes of a known-good HELLO/CMD):
  01 <len> <addr_lo> <addr_hi> <code...>      data record (loads len-2 code bytes)
  02 <len> <addr_lo> <addr_hi>                transfer (entry) record, len=2

A single 01 record holds at most 253 code bytes (length field is 8-bit), so
the image is split into contiguous records of up to 253 bytes each. The
transfer record's address is the program entry.

Usage: python3 make_cmd.py <raw.bin> <entry> <out.cmd>
   <raw.bin> : flat Z80 code (ORG == load base)
   <entry>   : entry address, hex like 3000
   <out.cmd> : output path
"""
import sys

MAX_CODE = 253  # 255 (len byte max) - 2 (address bytes)


def make_cmd(raw: bytes, base: int, entry: int) -> bytes:
    out = bytearray()
    addr = base
    off = 0
    while off < len(raw):
        code = raw[off:off + MAX_CODE]
        ln = 2 + len(code)
        out.append(0x01)
        out.append(ln)
        out.append(addr & 0xFF)
        out.append((addr >> 8) & 0xFF)
        out.extend(code)
        off += len(code)
        addr += len(code)
    # transfer record
    out.extend([0x02, 0x02, entry & 0xFF, (entry >> 8) & 0xFF])
    return bytes(out)


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)
    raw_path = sys.argv[1]
    entry = int(sys.argv[2], 16)
    out_path = sys.argv[3]
    with open(raw_path, "rb") as f:
        raw = f.read()
    base = entry  # ORG == entry
    cmd = make_cmd(raw, base, entry)
    with open(out_path, "wb") as f:
        f.write(cmd)
    print(f"CMD created: {out_path}")
    print(f"  {len(raw)} code bytes in {len(raw) // MAX_CODE + 1} record(s), "
          f"load @${base:04X}, entry @${entry:04X}, total {len(cmd)} bytes")


if __name__ == "__main__":
    main()
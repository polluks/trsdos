#!/usr/bin/env python3
"""Wrap a flat Z80 binary into a TRSDOS .CMD executable.

TRSDOS .CMD files are Load Module Format (LMF) files, parsed by the loader
routine `LDR01` (repo/LSDOS631L/lsdos631/loader.asm, "System Loader and associated
routines"):

  Record dispatch (first payload byte = record type):
    01 <len> <addr_lo> <addr_hi> <len-2 data bytes>   start of block (data)
    02 <len> <addr_lo> <addr_hi>                     transfer address
    04                                              end of library member
    08 <len> <ISAM#> <addr> ...                     ISAM begin
    0A                                              end of ISAM map
    <others> <len> <len bytes>                     comment ("IGNORE ALL OTHER CONTROL")

  Any record type below 0x20 that is not one of the types above is treated as a
  comment record: the loader reads a length byte and skips that many bytes, then
  falls through to the next-record routine (LDR05 -> back to LDR01).  This makes
  magic values such as 05 (0x05) writable into CMD files - the loader simply
  consumes them as (comment) records and keeps parsing.

  An executable CMD needs:
    01 <len> <addr_lo> <addr_hi> <code...>    data record (len = 2 + code bytes)
    02 <len> <addr_lo> <addr_hi>              transfer record (entry address)

Usage: python3 make_cmd.py <raw.bin> <entry> <out.cmd> [--magic <type>] [--magic-data <text>]
   --magic <type>      optional leading comment/magic record type byte (e.g. 5)
   --magic-data <text> optional ASCII payload for the magic/comment record
"""
import sys

MAX_CODE = 253  # 255 (len byte max) - 2 (address bytes)


def make_comment(ctype: int, payload: bytes = b"") -> bytes:
    """Build an LMF comment/ignore record: <type> <len> <len bytes>."""
    if not 0 <= ctype <= 0xFF:
        raise ValueError(f"magic type out of range: {ctype}")
    return bytes([ctype, len(payload)]) + payload


def make_cmd(raw: bytes, base: int, entry: int, magic: int | None = None,
            magic_data: bytes = b"") -> bytes:
    out = bytearray()
    if magic is not None:
        out += make_comment(magic, magic_data)
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
    magic = None
    magic_data = b""
    args = sys.argv[1:]
    pos = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--magic":
            i += 1
            magic = int(args[i], 0)
        elif a == "--magic-data":
            i += 1
            magic_data = args[i].encode("ascii")
        else:
            pos.append(a)
        i += 1
    if len(pos) < 3:
        print(__doc__)
        sys.exit(1)
    raw_path, entry_s, out_path = pos[0], pos[1], pos[2]
    entry = int(entry_s, 16)
    with open(raw_path, "rb") as f:
        raw = f.read()
    base = entry
    cmd = make_cmd(raw, base, entry, magic=magic, magic_data=magic_data)
    with open(out_path, "wb") as f:
        f.write(cmd)
    print(f"CMD created: {out_path}")
    print(f"  {len(raw)} code bytes in {len(raw) // MAX_CODE + 1} record(s), "
          f"load @${base:04X}, entry @${entry:04X}, total {len(cmd)} bytes")
    if magic is not None:
        print(f"  magic record: type={magic:#04X} len={len(magic_data)} data={magic_data!r}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Prepare the VDC TRS-80 block-font blob for logo display.

Mirrors the 8502 `font_sel` routine in boot_sector.s (no assembly changes):

  - 64 glyphs, TRS-80 block pseudographics, char codes 128..191 (V = 0..63)
  - each glyph = 8 scanline-bytes (VDC downloadable alt charset, block 3,
    address 0x3000 + (128+V)*16)
  - scanlines 0-2   <- rowbyte[V & 3]
  - scanlines 3-5   <- rowbyte[(V >> 2) & 3]
  - scanlines 6-7   <- rowbyte[(V >> 4) & 3]

rowbyte[] holds the per-pattern scanline bytes: [0x00, 0xF0, 0x0F, 0xFF].

Output: font/logo_font.bin  (64 glyphs x 8 bytes = 512 bytes)
"""

from pathlib import Path

ROWBYTE = [0x00, 0xF0, 0x0F, 0xFF]


def glyph_bytes(V: int):
    out = []
    out += [ROWBYTE[V & 3]] * 3
    out += [ROWBYTE[(V >> 2) & 3]] * 3
    out += [ROWBYTE[(V >> 4) & 3]] * 2
    return out


def build() -> bytes:
    blob = bytearray()
    for V in range(64):
        blob += bytes(glyph_bytes(V))
    return bytes(blob)


def main() -> None:
    blob = build()
    font_dir = Path(__file__).resolve().parent / "font"
    font_dir.mkdir(exist_ok=True)
    (font_dir / "logo_font.bin").write_bytes(blob)
    print(f"wrote {font_dir / 'logo_font.bin'} ({len(blob)} bytes, 64 glyphs x 8 scanlines)")


if __name__ == "__main__":
    main()

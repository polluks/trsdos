#!/usr/bin/env python3
"""Display routine for the prepared TRS-80 block font (logo rendering).

Consumes the prepared font blob (font/logo_font.bin: 64 glyphs x 8 scanline
bytes, char codes 128..191) and turns a logo glyph pattern (sequence of glyph
values V = 0..63) into the VDC write sequence used by the downloadable charset:

  - VRAM update address (regs 18/19) = offset of the first glyph cell
  - VDC data register (reg 31) with auto-increment, then write 8 bytes per glyph

Purely additive: reads the prepared font, does not modify the boot assembly.
"""

from pathlib import Path

FONT_PATH = Path(__file__).resolve().parent / "logo_font.bin"


def load_font() -> list[list[int]]:
    """Return the 64 prepared glyphs, each an 8-byte list of scanline bytes."""
    blob = FONT_PATH.read_bytes()
    assert len(blob) == 64 * 8, f"bad font blob size {len(blob)}"
    return [list(blob[i * 8:(i + 1) * 8]) for i in range(64)]


def glyph_bytes(V: int, font: list[list[int]]) -> list[int]:
    """Scanline bytes for glyph value V (falls back to prepared blob entry)."""
    return list(font[V])


def display_writes(glyphs: list[int], font: list[list[int]]) -> list[int]:
    """Build the ordered list of scanline bytes to write to the VDC data port."""
    writes: list[int] = []
    for V in glyphs:
        writes.extend(glyph_bytes(V, font))
    return writes


def display_sequence(glyphs: list[int], font: list[list[int]]) -> dict:
    """Return a display plan: update address + ordered data writes."""
    cell_bytes = 8
    nbytes = len(glyphs) * cell_bytes
    return {
        "glyph_count": len(glyphs),
        "cell_bytes": cell_bytes,
        "update_address": 0,  # VRAM offset of first glyph cell (set per logo)
        "writes": display_writes(glyphs, font),
        "n_bytes": nbytes,
    }


if __name__ == "__main__":
    font = load_font()
    seq = display_sequence([0, 1, 2, 63, 5, 5, 0], font)
    print(seq)

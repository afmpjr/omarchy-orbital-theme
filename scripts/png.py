#!/usr/bin/env python3
"""Minimal PNG reader for the visual tests.

The visual tests have to look at screenshots the way a person does, and the only
dependency allowed on a clean Omarchy machine is Python itself. Decoding a PNG is
straightforward enough to not warrant Pillow, so here it is, shared by
visual-diff.py and visual-accent.py.

Supports 8-bit RGB and RGBA, non-interlaced, which is what the testbed's screenshot
tool produces.
"""

import struct
import sys
import zlib
from collections import Counter


def read(path):
    """Return (width, height, channels, rows) where rows[y] is a bytes of scanline data."""
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError as error:
        raise ValueError(f"cannot read {path}: {error}") from None
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")

    pos, header, idat = 8, None, bytearray()
    while pos + 8 <= len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        pos += 12 + length
    if header is None:
        raise ValueError(f"{path} has no IHDR")

    width, height, depth, colour, compression, filtering, interlace = header
    if depth != 8 or colour not in (2, 6) or compression or filtering or interlace:
        raise ValueError(
            f"{path} is not a plain 8-bit RGB/RGBA PNG (depth={depth}, colour={colour})"
        )

    channels = 3 if colour == 2 else 4
    stride = width * channels
    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error as error:
        raise ValueError(f"cannot inflate {path}: {error}") from None

    rows, previous, offset = [], bytearray(stride), 0
    for _ in range(height):
        method = raw[offset]
        offset += 1
        line = bytearray(raw[offset:offset + stride])
        offset += stride
        for i in range(stride):  # undo the per-scanline filter (PNG spec 9.2)
            left = line[i - channels] if i >= channels else 0
            up = previous[i]
            upleft = previous[i - channels] if i >= channels else 0
            if method == 1:
                line[i] = (line[i] + left) & 0xFF
            elif method == 2:
                line[i] = (line[i] + up) & 0xFF
            elif method == 3:
                line[i] = (line[i] + ((left + up) >> 1)) & 0xFF
            elif method == 4:
                p = left + up - upleft
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upleft)
                nearest = left if (pa <= pb and pa <= pc) else (up if pb <= pc else upleft)
                line[i] = (line[i] + nearest) & 0xFF
            elif method != 0:
                raise ValueError(f"{path} uses unknown scanline filter {method}")
        rows.append(bytes(line))
        previous = line
    return width, height, channels, rows


def parse_hex(text):
    text = text.lstrip("#")
    if len(text) != 6:
        raise ValueError(f"want #rrggbb, got {text!r}")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


def histogram(width, channels, rows):
    """Counter of (r, g, b) over the whole image."""
    counts = Counter()
    for row in rows:
        for i in range(0, len(row), channels):
            counts[(row[i], row[i + 1], row[i + 2])] += 1
    return counts


def count_colour(counts, colour, tolerance):
    """How many pixels are within `tolerance` per channel of `colour`."""
    return sum(n for pixel, n in counts.items()
               if all(abs(pixel[i] - colour[i]) <= tolerance for i in range(3)))


def load(path):
    """Read a PNG and return (width, height, histogram), raising ValueError on garbage."""
    try:
        width, height, channels, rows = read(path)
    except ValueError as error:
        raise ValueError(str(error)) from None
    return width, height, histogram(width, channels, rows)


def main(argv):
    if len(argv) < 2 or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) > 1 else 1
    try:
        width, height, counts = load(argv[0])
    except ValueError as error:
        print(f"png.py: {error}", file=sys.stderr)
        return 2
    top = int(argv[1]) if len(argv) > 1 else 6
    print(f"{argv[0]}: {width}x{height}")
    for (r, g, b), n in counts.most_common(top):
        print(f"  #{r:02X}{g:02X}{b:02X} {100.0 * n / (width * height):6.2f}%  ({n} px)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

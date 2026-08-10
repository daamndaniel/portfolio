#!/usr/bin/env python3
"""
Print a PNG's MINIMUM alpha value (0-255). Prints 255 for anything without an
8-bit RGBA alpha channel, i.e. "nothing is transparent".

    python3 tools/png-min-alpha.py assets/foo.png   ->  254

WHY THIS EXISTS — IT ENCODES A MISTAKE WORTH NOT REPEATING
    tools/optimize-assets.sh needs to know whether a PNG can become a JPEG. The
    obvious test, `sips -g hasAlpha`, is useless: it reports "yes" for a merely
    PRESENT channel and said yes to all 27 PNGs in this project, none of which
    needed it.

    The second attempt counted NON-OPAQUE PIXELS, and that was still wrong. It
    found 828,677 in sb-cover.png and concluded the file had real transparency, so
    three images were left as PNG and ~4.2MB was left on the table. In fact every
    one of those pixels had alpha 254 — a 0.4% deviation, invisible, an artefact of
    the export. Counting pixels answers "how many differ", not "by how much", and
    only the second question matters.

    So: compare the minimum alpha against a threshold. Below ~250 means real
    transparency worth preserving; 250-255 is noise that can be flattened.

Stdlib only — no Pillow on this machine — so it inflates the IDAT and undoes the
per-line filters by hand. Slow but exact.
"""
import sys
import struct
import zlib


def min_alpha(path):
    data = open(path, 'rb').read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return 255                            # not a PNG at all
    pos = 8
    width = height = bitdepth = colortype = None
    idat = bytearray()
    while pos < len(data):
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        if ctype == b'IHDR':
            width, height, bitdepth, colortype = struct.unpack('>IIBB', data[pos + 8:pos + 18])
        elif ctype == b'IDAT':
            idat += data[pos + 8:pos + 8 + length]
        elif ctype == b'IEND':
            break
        pos += 12 + length

    # Only 8-bit RGBA carries a per-pixel alpha we can read this cheaply.
    if colortype != 6 or bitdepth != 8:
        return 255

    ch = 4
    raw = zlib.decompress(bytes(idat))
    stride = width * ch
    prev = bytearray(stride)
    i = 0
    lo = 255
    for _ in range(height):
        ft = raw[i]; i += 1
        line = bytearray(raw[i:i + stride]); i += stride
        if ft == 1:                                        # Sub
            for x in range(ch, stride):
                line[x] = (line[x] + line[x - ch]) & 255
        elif ft == 2:                                      # Up
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif ft == 3:                                      # Average
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif ft == 4:                                      # Paeth
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                b = prev[x]
                c = prev[x - ch] if x >= ch else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        m = min(line[3::4])
        if m < lo:
            lo = m
            if lo == 0:
                return 0                                   # cannot get lower
        prev = line
    return lo


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('usage: png-min-alpha.py <file.png>')
    try:
        print(min_alpha(sys.argv[1]))
    except Exception:
        print(0)        # unreadable -> report "transparent" so the caller keeps PNG

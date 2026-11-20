"""Draws a simple round launcher icon: make_icon.py "<letter> <#rrggbb>" out.png"""
import struct
import sys
import zlib

letter_color, out = sys.argv[1], sys.argv[2]
_, color = letter_color.split()
r, g, b = int(color[1:3], 16), int(color[3:5], 16), int(color[5:7], 16)
size = 96
rows = []
for y in range(size):
    row = bytearray([0])
    for x in range(size):
        dx, dy = x - size / 2 + 0.5, y - size / 2 + 0.5
        d = (dx * dx + dy * dy) ** 0.5
        if d < size / 2 - 2:
            # a white ring inside the disc
            if size / 2 - 22 < d < size / 2 - 14:
                row += bytes([255, 255, 255, 255])
            else:
                row += bytes([r, g, b, 255])
        else:
            row += bytes([0, 0, 0, 0])
    rows.append(bytes(row))


def chunk(kind, data):
    c = struct.pack(">I", len(data)) + kind + data
    return c + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
png += chunk(b"IEND", b"")
open(out, "wb").write(png)

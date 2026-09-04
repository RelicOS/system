#!/usr/bin/env python3
"""Turn the boot splash artwork (PNG) into the two PPMs the boot path eats.

Standard library only: this runs inside Buildroot's post-build (the host has
python3 -- it is one of Buildroot's mandatory host tools -- but not PIL).

  make-splash.py mark IN.png OUT.ppm
      Frame 1, the kernel logo. Crops the image to the bounding box of the
      pixels that are not the background (the most common colour), and
      writes a plain-text P3 PPM -- the format drivers/video/logo/pnmtologo
      converts into a C table at kernel build time (CLUT224: at most 224
      distinct colours). fbcon centres it on the panel with
      fbcon=logo-pos:center, so only the mark needs to travel in the Image;
      the black around it is the console's own background.

  make-splash.py full IN.png OUT.ppm
      Frame 2, the userspace splash. Writes the whole image as a binary P6
      PPM, the only format BusyBox's fbsplash reads (miscutils/fbsplash.c:
      "P6 w h 255"). It is painted straight onto /dev/fb0 by S15splash.

PNG support is the minimum for the artwork at hand: 8-bit RGB or RGBA,
non-interlaced. Anything else dies loudly.
"""
import struct
import sys
import zlib
from collections import Counter

MAX_CLUT224_COLOURS = 224


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path}: not a PNG")
    pos, idat, ihdr = 8, b"", None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
    width, height, depth, ctype, _, _, interlace = ihdr
    if depth != 8 or ctype not in (2, 6) or interlace:
        sys.exit(f"{path}: need 8-bit RGB/RGBA, non-interlaced "
                 f"(depth {depth}, colour type {ctype}, interlace {interlace})")
    bpp = 4 if ctype == 6 else 3
    stride = width * bpp
    raw = zlib.decompress(idat)
    rows, prev, p = [], bytearray(stride), 0
    for _ in range(height):
        f, cur = raw[p], bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = cur[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                cur[i] = (cur[i] + a) & 255
            elif f == 2:
                cur[i] = (cur[i] + b) & 255
            elif f == 3:
                cur[i] = (cur[i] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 255
        rows.append([tuple(cur[x * bpp:x * bpp + 3]) for x in range(width)])
        prev = cur
    return width, height, rows


def crop_to_mark(width, height, rows):
    counts = Counter(px for row in rows for px in row)
    background = counts.most_common(1)[0][0]
    xs = [x for row in rows for x, px in enumerate(row) if px != background]
    ys = [y for y, row in enumerate(rows) for px in row if px != background]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    cropped = [row[x0:x1 + 1] for row in rows[y0:y1 + 1]]
    return cropped, background, (x0, y0, x1, y1)


def write_p3(path, rows, comment):
    colours = len({px for row in rows for px in row})
    if colours > MAX_CLUT224_COLOURS:
        sys.exit(f"{colours} colours, CLUT224 takes at most "
                 f"{MAX_CLUT224_COLOURS}: quantise the artwork first")
    height, width = len(rows), len(rows[0])
    with open(path, "w") as out:
        out.write(f"P3\n# {comment}\n{width} {height}\n255\n")
        for row in rows:
            out.write("\n".join(f"{r} {g} {b}" for r, g, b in row) + "\n")
    return width, height, colours


def write_p6(path, rows):
    height, width = len(rows), len(rows[0])
    with open(path, "wb") as out:
        out.write(f"P6\n{width} {height}\n255\n".encode())
        for row in rows:
            out.write(bytes(c for px in row for c in px))
    return width, height


def main(argv):
    if len(argv) != 4 or argv[1] not in ("mark", "full"):
        sys.exit(__doc__)
    mode, src, dst = argv[1:]
    width, height, rows = read_png(src)
    if mode == "mark":
        cropped, background, box = crop_to_mark(width, height, rows)
        w, h, colours = write_p3(
            dst, cropped,
            f"RelicOS boot logo, frame 1: cropped from {src.split('/')[-1]} "
            f"box x{box[0]}-{box[2]} y{box[1]}-{box[3]}; background was "
            f"rgb{background}")
        print(f"{dst}: P3 {w}x{h}, {colours} colours, cropped from "
              f"{width}x{height} at x{box[0]}-{box[2]} y{box[1]}-{box[3]} "
              f"(background rgb{background})")
    else:
        w, h = write_p6(dst, rows)
        print(f"{dst}: P6 {w}x{h}")


if __name__ == "__main__":
    main(sys.argv)

"""Recolours the v0 authoring bundle into a phosphor-terminal skin.

Proves the bundle boundary end to end: this touches only `authoring/`, knows
nothing about Godot, and produces something the build pipeline turns into a
loadable pack. It is also a deliberately CHEAP skin — a recolour, not a redraw —
because its job here is to give the switcher a second thing to switch to.

Concept: `staging/concept-art/03-terminal-phosphor.jpg`.
"""

import io
import pathlib
import re
import struct
import sys
import zlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = pathlib.Path(r"C:\Users\chode\1C38R34KR")
SRC = ROOT / "authoring" / "v0"
DST = ROOT / "authoring" / "phosphor"

# A CRT's palette: everything is one phosphor hue at varying intensity, except
# the six Packet colours, which must stay distinguishable or the game stops
# being playable.
GREEN_DARK = (2, 10, 4)
GREEN_MID = (18, 48, 24)
GREEN_LINE = (54, 190, 92)
GREEN_BRIGHT = (128, 255, 150)

# Packet colours: pushed toward phosphor without collapsing into each other.
PALETTE = {
    "packet_red": "#ff5a4a",
    "packet_yellow": "#e8ff4a",
    "packet_magenta": "#ff6ad5",
    "packet_green": "#54ff92",
    "packet_cyan": "#4ae8ff",
    "packet_blue": "#7a6aff",
}


def read_png(path):
    """Minimal PNG reader: returns (w, h, rgba bytes)."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a png: %s" % path)
    pos, idat, w, h, depth, ctype = 8, b"", 0, 0, 0, 0
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", chunk[:10])
        elif typ == b"IDAT":
            idat += chunk
        pos += 12 + ln
    if depth != 8 or ctype not in (2, 6):
        raise ValueError("unsupported png format in %s (depth %d type %d)" % (path, depth, ctype))

    channels = 4 if ctype == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * channels
    out = bytearray()
    prev = bytearray(stride)
    i = 0
    for _ in range(h):
        filt = raw[i]
        i += 1
        line = bytearray(raw[i:i + stride])
        i += stride
        for x in range(stride):
            a = line[x - channels] if x >= channels else 0
            b = prev[x]
            c = prev[x - channels] if x >= channels else 0
            if filt == 1:
                line[x] = (line[x] + a) & 0xFF
            elif filt == 2:
                line[x] = (line[x] + b) & 0xFF
            elif filt == 3:
                line[x] = (line[x] + (a + b) // 2) & 0xFF
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 0xFF
        out += line
        prev = line

    if channels == 3:
        rgba = bytearray()
        for p in range(0, len(out), 3):
            rgba += out[p:p + 3] + b"\xff"
        return w, h, rgba
    return w, h, out


def write_png(path, w, h, rgba):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def luma(r, g, b):
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0


def ramp(t, scanline=False):
    """Maps brightness onto the phosphor ramp."""
    if t < 0.10:
        base = GREEN_DARK
    elif t < 0.35:
        base = GREEN_MID
    elif t < 0.75:
        base = GREEN_LINE
    else:
        base = GREEN_BRIGHT
    if scanline:
        return tuple(int(c * 0.55) for c in base)
    return base


# Assets that are TINTED at runtime must stay white-with-alpha; recolouring them
# would be doubly applied. Their SHAPE is untouched here.
TINTED = re.compile(r"(glyph_|mark_|digit_|ring_bomb|ring_buff|ring_shield|ring_override|title_logo)")


def main():
    if DST.exists():
        import shutil
        shutil.rmtree(DST)

    count = 0
    for src in sorted(SRC.rglob("*.png")):
        rel = src.relative_to(SRC)
        w, h, px = read_png(src)

        if TINTED.search(src.name):
            # Copy through untouched — the game supplies the colour.
            write_png(DST / rel, w, h, px)
            count += 1
            continue

        out = bytearray(px)
        for y in range(h):
            scan = (y % 3) == 2 and h > 16  # skip scanlines on tiny bar art
            for x in range(w):
                i = (y * w + x) * 4
                a = px[i + 3]
                if a == 0:
                    continue
                r, g, b = ramp(luma(px[i], px[i + 1], px[i + 2]), scan)
                out[i], out[i + 1], out[i + 2] = r, g, b
        write_png(DST / rel, w, h, out)
        count += 1

    # The palette SVG: swap the six fills, keep every id and the layout.
    svg = (SRC / "packet_palette.svg").read_text(encoding="utf-8")
    for pid, colour in PALETTE.items():
        svg = re.sub(
            r'(id="%s"[^>]*?fill=")#[0-9a-fA-F]{6}' % pid,
            r"\g<1>" + colour,
            svg,
        )
    (DST / "packet_palette.svg").write_text(svg, encoding="utf-8")

    print("wrote %d PNGs + palette to authoring/phosphor" % count)
    return 0


if __name__ == "__main__":
    sys.exit(main())

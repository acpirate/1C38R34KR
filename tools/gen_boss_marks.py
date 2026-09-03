"""Draws the Beta 0.4 Boss overlay marks into every authoring bundle.

    python tools/gen_boss_marks.py            # every pack under authoring/
    python tools/gen_boss_marks.py v0 bzone   # named packs

Beta 0.4 adds two special types, CAPACITOR and LOGIC_BOMB, and the graphics
contract sizes `overlay_mark` and `overlay_ring` from `Tile.Special.Type`. So
every installed pack needs four new files or it fails validation — which is the
contract working as designed, and also why this is a script rather than six
hand edits.

## Why generated per pack rather than copied

The marks are white-with-alpha and tinted at runtime, so a pack's "style" is
carried entirely by the SILHOUETTE. Those silhouettes genuinely differ: v0 and
neon90s are smooth, 16bit and terminal are blocky, bzone is a hollow outline.
Pasting one shape into all six would leave four packs with a mark that does not
match the marks beside it — complete, and visibly wrong.

So the shapes are defined once as coverage functions and RENDERED through each
pack's style. Provisional art either way (§9.1), but provisional art that
belongs to its pack.

## The two shapes

Both had to stay distinct from the four that already exist — a solid circle
with a fuse (BOMB), a cross (BUFF), a solid shield (SHIELD), and a ring with a
slash (OVERRIDE):

- CAPACITOR is two horizontal plates with leads. Strongly horizontal, which
  none of the existing four are, and it reads as stored charge.
- LOGIC BOMB is two stacked downward chevrons. It avoids the circle that would
  collide with BOMB, and it encodes the mechanic: the thing descends, and what
  matters is where it lands.

Rings are copied from each pack's own `ring_override.png`. They are suspended
and never drawn (D-037), so the only requirement is that they exist and keep
the pack's look if the ring is ever restored.
"""

import io
import pathlib
import shutil
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = pathlib.Path(__file__).resolve().parent.parent
AUTHORING = ROOT / "authoring"

MARK_SIZE = 64

## How each pack draws a silhouette. Read off its existing marks rather than
## guessed: see the contact sheet in the 0.4.0 handback.
STYLE = {
    "v0": "smooth",
    "phosphor": "smooth",   # a recolour of v0; its marks are v0's pixels
    "neon90s": "smooth",
    "16bit": "pixel",
    "terminal": "pixel",
    "bzone": "outline",
}

PIXEL_GRID = 32  # upscaled 2x. 16 was tried and is too coarse: the capacitor's
                 # plates and leads merged into a cross, colliding with BUFF.


def capacitor(u, v, t=1.0):
    """Two plates with leads. `u`,`v` are 0..1 across the tile.

    `t` scales stroke thickness only — the outline style renders the shape twice
    at different thicknesses and subtracts, which is how a hollow mark stays a
    real outline instead of an eroded blob.
    """
    du = abs(u - 0.5)
    plate = du < 0.34 and (abs(v - 0.36) < 0.085 * t or abs(v - 0.64) < 0.085 * t)
    lead = du < 0.07 * t and (0.12 < v < 0.285 or 0.715 < v < 0.88)
    return plate or lead


def logic_bomb(u, v, t=1.0):
    """Two stacked downward chevrons."""
    du = abs(u - 0.5)
    if du > 0.36:
        return False
    for vy in (0.40, 0.70):
        # Lowest at the centre, rising toward each edge.
        if abs(v - (vy - 0.52 * du)) < 0.095 * t:
            return True
    return False


SHAPES = {"mark_capacitor": capacitor, "mark_logic_bomb": logic_bomb}


def render(fn, size, supersample):
    """Alpha coverage 0..255 for one shape, box-filtered."""
    out = bytearray(size * size)
    step = 1.0 / (size * supersample)
    for y in range(size):
        for x in range(size):
            hits = 0
            for sy in range(supersample):
                v = (y * supersample + sy + 0.5) * step
                for sx in range(supersample):
                    u = (x * supersample + sx + 0.5) * step
                    if fn(u, v):
                        hits += 1
            out[y * size + x] = (hits * 255) // (supersample * supersample)
    return out


def upscale(src, src_size, factor):
    dst = src_size * factor
    out = bytearray(dst * dst)
    for y in range(dst):
        row = (y // factor) * src_size
        for x in range(dst):
            out[y * dst + x] = src[row + x // factor]
    return out


def styled(fn, style):
    if style == "pixel":
        # Thicker strokes before quantising: at a 16px grid the chevrons
        # collapse into blobs at their authored weight.
        small = render(lambda u, v: fn(u, v, 1.15), PIXEL_GRID, 4)
        # Hard threshold: a blocky mark has no soft edges.
        small = bytearray(255 if a >= 110 else 0 for a in small)
        return upscale(small, PIXEL_GRID, MARK_SIZE // PIXEL_GRID)

    if style == "outline":
        # A genuine outline: the shape at full weight, minus the same shape
        # drawn thinner. Eroding instead produced a solid mark, because every
        # pixel of a thin bar is within the erosion radius of its own edge.
        outer = render(lambda u, v: fn(u, v, 1.35), MARK_SIZE, 4)
        inner = render(lambda u, v: fn(u, v, 1.0), MARK_SIZE, 4)
        return bytearray(max(0, o - i) for o, i in zip(outer, inner))

    return render(lambda u, v: fn(u, v, 1.0), MARK_SIZE, 4)


def write_mark(path, alpha, size):
    import struct
    import zlib

    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            a = alpha[y * size + x]
            # White with alpha: the game supplies the colour by modulate.
            raw += bytes((255, 255, 255, a))

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def main():
    wanted = sys.argv[1:]
    packs = sorted(p.name for p in AUTHORING.iterdir() if (p / "overlay").is_dir())
    if wanted:
        packs = [p for p in packs if p in wanted]
    if not packs:
        print("no packs matched")
        return 1

    for pack in packs:
        style = STYLE.get(pack, "smooth")
        overlay = AUTHORING / pack / "overlay"
        for name, fn in SHAPES.items():
            write_mark(overlay / ("%s.png" % name), styled(fn, style), MARK_SIZE)
        # Suspended rings: keep the pack's own treatment.
        src = overlay / "ring_override.png"
        for name in ("ring_capacitor", "ring_logic_bomb"):
            if src.exists():
                shutil.copyfile(src, overlay / ("%s.png" % name))
            else:
                print("  WARN %s has no ring_override.png to derive from" % pack)
        print("  %-9s %s" % (pack, style))

    print("\nwrote 4 files into %d pack(s)" % len(packs))
    return 0


if __name__ == "__main__":
    sys.exit(main())

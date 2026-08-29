"""Applies this project's required import settings to a pack's textures.

    python tools/fix_imports.py            # every pack under assets/packs
    python tools/fix_imports.py v1         # one pack
    python tools/fix_imports.py --check    # report, change nothing

Run after `godot --headless --import` regenerates `.import` files, which happens
whenever a texture is added, a pack is cloned, or the import cache is cleared.

## Two things, not one

**1. `detect_3d/compress_to` defaults to 1**, which tells Godot to silently
re-import a texture as VRAM-compressed the first time it believes it is used in
3D. Nothing here is 3D — but the setting is a trapdoor: it turns a lossless
authored asset lossy with nobody editing anything, which is exactly what the
graphics authorization's §2.2 forbids.

**2. `packet_palette.svg` must NOT be imported as a texture.** Godot's default
for an SVG is `importer="texture"`, which converts it to a `CompressedTexture2D`
and stops the raw file shipping — and the game parses that file as TEXT at
startup to read the six Packet colours. Left alone, a cloned pack loads with no
palette and logs `no palette SVG at …`, which is exactly how it was found: on a
device, after a skin switch, with the UI otherwise correct.

Neither patch survives regeneration, so this has to be re-runnable rather than a
one-time fix.

`--check` reports drift without writing, so a verification gate can fail on it
instead of someone remembering.
"""

import argparse
import io
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKS = ROOT / "assets" / "packs"

FIXES = {
    "detect_3d/compress_to=1": "detect_3d/compress_to=0",
}

## What an SVG's `.import` must contain. Anything else means Godot has decided
## to rasterise it, and the palette stops being readable as text.
SVG_IMPORT = "\n".join(["[remap]", "", 'importer="keep"', ""])



def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pack", nargs="?", help="pack name; omit for all packs")
    ap.add_argument("--check", action="store_true", help="report drift, write nothing")
    args = ap.parse_args()

    root = PACKS / args.pack if args.pack else PACKS
    if not root.is_dir():
        print("no such pack: %s" % root)
        return 1

    changed = 0
    scanned = 0
    for f in sorted(root.rglob("*.png.import")):
        scanned += 1
        text = f.read_text(encoding="utf-8")
        fixed = text
        for bad, good in FIXES.items():
            fixed = fixed.replace(bad, good)
        if fixed == text:
            continue
        changed += 1
        if args.check:
            print("  DRIFT %s" % f.relative_to(ROOT))
        else:
            f.write_text(fixed, encoding="utf-8")
            print("  fixed %s" % f.relative_to(ROOT))

    # The palette SVG, which must stay unimported so the game can read it.
    for svg in sorted(root.rglob("*.svg")):
        imp = svg.with_suffix(svg.suffix + ".import")
        scanned += 1
        if imp.exists() and imp.read_text(encoding="utf-8") == SVG_IMPORT:
            continue
        changed += 1
        if args.check:
            print("  DRIFT %s (SVG must be importer=keep)" % imp.relative_to(ROOT))
        else:
            imp.write_text(SVG_IMPORT, encoding="utf-8")
            # Godot leaves the rasterised copy behind; it is stale the moment
            # the importer changes.
            for junk in imp.parent.glob(svg.stem + ".*.translation"):
                junk.unlink()
            print("  fixed %s (importer=keep)" % imp.relative_to(ROOT))

    if changed == 0:
        print("all %d texture import(s) already correct" % scanned)
        return 0

    if args.check:
        print("\n%d of %d import(s) need fixing — run without --check" % (changed, scanned))
        return 1

    print("\nfixed %d of %d import(s)" % (changed, scanned))
    return 0


if __name__ == "__main__":
    sys.exit(main())

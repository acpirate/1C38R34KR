"""The artist-facing asset bundle, and the machinery either side of it.

    python tools/asset_bundle.py export v0            # pack  -> authoring bundle
    python tools/asset_bundle.py check v0             # validate a bundle
    python tools/asset_bundle.py build v0 --pack v1   # bundle -> importable pack

## What a bundle is

`authoring/<name>/` holds **only files an artist edits**: the PNGs and the
palette SVG, in their folders, plus a generated `README.md` describing every one.
No `.import` files, no `pack.tres`, no `manifest.json`, nothing about Godot.

A bundle can be zipped and handed to a person or an agent who has never seen this
repository. They edit the images and send it back. Everything needed to turn it
into something the engine can load happens on this side of the line.

`authoring/.gdignore` keeps the whole tree out of Godot's import system, so the
raw files stay raw — without it the engine would generate `.import` files inside
the bundle and the separation would collapse the first time anyone opened the
editor.

## The contract

`SPEC` below is the authority on what a pack must contain: every semantic key,
its dimensions, whether it is 9-sliced, whether it is tinted at runtime, and what
it is for. `check` validates a bundle against it, so a missing or mis-sized asset
fails here rather than as a magenta checker on a device.

**Tinting is the rule an artist most needs and would never guess.** An asset
marked TINTED is drawn white-with-alpha and coloured by the game — authoring it
in colour makes it render wrong, and no validator can catch that because the file
is perfectly valid.
"""

import argparse
import io
import json
import pathlib
import shutil
import struct
import subprocess
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = pathlib.Path(__file__).resolve().parent.parent
AUTHORING = ROOT / "authoring"
PACKS = ROOT / "assets" / "packs"

# key, w, h, 9-slice margin (0 = none), tint, description
#   tint: ""        ships its own colour
#         "palette" tinted with the Packet colour it represents
#         "state"   tinted with a state colour the game picks
TINT_NONE, TINT_PALETTE, TINT_STATE = "", "palette", "state"

SPEC = [
    # --- chrome ---
    ("chrome/screen_bg",            256, 256,  0, TINT_NONE,  "Full-screen ground. TILED, so it must be seamless."),
    ("chrome/panel",                 48,  48, 16, TINT_NONE,  "The box every menu and the pause menu sit in."),
    ("chrome/button_normal",         48,  48, 16, TINT_NONE,  "Button, at rest."),
    ("chrome/button_pressed",        48,  48, 16, TINT_NONE,  "Button, held down."),
    ("chrome/button_selected",       48,  48, 16, TINT_NONE,  "Button, chosen. Must differ from disabled by more than brightness."),
    ("chrome/button_disabled",       48,  48, 16, TINT_NONE,  "Button, unavailable."),
    ("chrome/rule",                  64,   8,  0, TINT_NONE,  "Horizontal divider. Stretched across, drawn ~2px tall."),
    ("chrome/scroll_track",          32,  32, 12, TINT_NONE,  "Scrollbar groove."),
    ("chrome/scroll_thumb",          32,  32, 12, TINT_NONE,  "Scrollbar handle."),
    ("chrome/bar_track",             32,  16,  6, TINT_NONE,  "Empty part of any meter."),
    ("chrome/bar_fill_link",         32,  16,  6, TINT_NONE,  "The Hacker's LINK meter fill."),
    ("chrome/bar_fill_ice",          32,  16,  6, TINT_NONE,  "The opponent's ICE meter fill."),
    ("chrome/bar_fill_charge",       32,  16,  6, TINT_NONE,  "A Program's charge fill, still filling."),
    ("chrome/bar_fill_charge_ready", 32,  16,  6, TINT_NONE,  "A Program's charge fill, full."),
    ("chrome/title_logo",          1114, 130,  0, TINT_STATE, "The wordmark on the start screen. Any size; aspect is preserved."),

    # --- battle chrome ---
    ("battle/avatar_box",            48,  48, 16, TINT_NONE,  "Frame around HACKER / opponent name and meter."),
    ("battle/program_box_idle",      48,  48, 16, TINT_NONE,  "Program control, not yet charged."),
    ("battle/program_box_charged",   48,  48, 16, TINT_NONE,  "Program charged — the opponent's, or not yours to fire."),
    ("battle/program_box_ready",     48,  48, 16, TINT_NONE,  "Program charged AND yours to fire. The strongest of the four."),
    ("battle/program_box_armed",     48,  48, 16, TINT_NONE,  "Program armed, waiting for you to pick a target."),
    ("battle/board_surround",        64,  64,  0, TINT_NONE,  "Behind the board. TILED, and shows through the gaps — this IS the grid."),
    ("battle/packet_cell",           64,  64, 16, TINT_NONE,  "The cell a Packet sits on. Drawn even when the cell is empty."),
    ("battle/build_slot",            48,  48, 16, TINT_NONE,  "Active Build slot. The accent bar down its left edge is load-bearing."),

    # --- packet ---
    ("packet/glyph_circle",         128, 128,  0, TINT_PALETTE, "Packet shape. See TINTED note."),
    ("packet/glyph_square",         128, 128,  0, TINT_PALETTE, "Packet shape."),
    ("packet/glyph_triangle",       128, 128,  0, TINT_PALETTE, "Packet shape."),
    ("packet/glyph_diamond",        128, 128,  0, TINT_PALETTE, "Packet shape."),
    ("packet/glyph_star",           128, 128,  0, TINT_PALETTE, "Packet shape."),
    ("packet/glyph_cross",          128, 128,  0, TINT_PALETTE, "Packet shape."),
    ("packet/ring_selected",         64,  64, 12, TINT_NONE,  "Ring around the Packet you tapped."),
    ("packet/ring_targeting",        64,  64, 12, TINT_NONE,  "Ring around a Packet you may target."),

    # --- overlay ---
    ("overlay/badge_player",        128, 128,  0, TINT_NONE,  "Ownership disc, Hacker. LIGHT fill, dark ring. Not tinted."),
    ("overlay/badge_enemy",         128, 128,  0, TINT_NONE,  "Ownership disc, opponent. DARK fill, light ring. Not tinted."),
    ("overlay/mark_bomb",            64,  64,  0, TINT_STATE, "Bomb, inside the badge."),
    ("overlay/mark_buff",            64,  64,  0, TINT_STATE, "Buff, inside the badge."),
    ("overlay/mark_shield",          64,  64,  0, TINT_STATE, "Shield, inside the badge."),
    ("overlay/mark_override",        64,  64,  0, TINT_STATE, "Boss Override, inside the badge."),
    ("overlay/ring_bomb",           128, 128,  0, TINT_STATE, "SUSPENDED — retained, not drawn. See D-037."),
    ("overlay/ring_buff",           128, 128,  0, TINT_STATE, "SUSPENDED — retained, not drawn."),
    ("overlay/ring_shield",         128, 128,  0, TINT_STATE, "SUSPENDED — retained, not drawn."),
    ("overlay/ring_override",       128, 128,  0, TINT_STATE, "SUSPENDED — retained, not drawn."),
    ("overlay/digit_0",              96,  96,  0, TINT_STATE, "Countdown numeral, inside the badge."),
    ("overlay/digit_1",              96,  96,  0, TINT_STATE, "Countdown numeral."),
    ("overlay/digit_2",              96,  96,  0, TINT_STATE, "Countdown numeral."),
    ("overlay/digit_3",              96,  96,  0, TINT_STATE, "Countdown numeral."),
    ("overlay/digit_4",              96,  96,  0, TINT_STATE, "Countdown numeral."),
    ("overlay/digit_5",              96,  96,  0, TINT_STATE, "Countdown numeral."),
    ("overlay/digit_6",              96,  96,  0, TINT_STATE, "Countdown numeral."),
    ("overlay/digit_7",              96,  96,  0, TINT_STATE, "Countdown numeral."),
    ("overlay/digit_8",              96,  96,  0, TINT_STATE, "Countdown numeral."),
    ("overlay/digit_9",              96,  96,  0, TINT_STATE, "Countdown numeral."),

    # --- icons ---
    ("icon/menu",                    64,  64,  0, TINT_NONE,  "Pause control in the battle header."),
    ("icon/arrow_up",                64,  64,  0, TINT_NONE,  "Move a Build slot earlier."),
    ("icon/arrow_down",              64,  64,  0, TINT_NONE,  "Move a Build slot later."),
    ("icon/cancel",                  64,  64,  0, TINT_NONE,  "Cancel targeting, on an armed Program."),
]

PALETTE = "packet_palette.svg"

# Files that belong to the ENGINE, never to a bundle.
ENGINE_ONLY = {".import", "pack.tres", "manifest.json"}


def png_size(path):
    """Width and height from the PNG header, without a decoder."""
    with open(path, "rb") as f:
        head = f.read(24)
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def is_engine_file(p):
    return p.suffix == ".import" or p.name in ENGINE_ONLY


# ---------------------------------------------------------------------------
# export: pack -> bundle
# ---------------------------------------------------------------------------

def cmd_export(args):
    src = PACKS / args.name
    dst = AUTHORING / args.name
    if not src.is_dir():
        print("no pack at %s" % src)
        return 1
    if dst.exists() and not args.force:
        print("%s exists — pass --force to replace it" % dst)
        return 1
    if dst.exists():
        shutil.rmtree(dst)

    dst.mkdir(parents=True)
    copied = 0
    for f in sorted(src.rglob("*")):
        if f.is_dir() or is_engine_file(f):
            continue
        rel = f.relative_to(src)
        (dst / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, dst / rel)
        copied += 1

    _ensure_gdignore()
    write_readme(dst, args.name)
    print("exported %d file(s) to authoring/%s" % (copied, args.name))
    print("  no .import, no pack.tres, no manifest — just art and the palette")
    return 0


def _ensure_gdignore():
    """Keeps the authoring tree out of Godot's import system.

    Without it the engine generates `.import` files inside every bundle the first
    time the editor opens, and the clean separation this whole tool exists for
    collapses silently.
    """
    AUTHORING.mkdir(exist_ok=True)
    marker = AUTHORING / ".gdignore"
    if not marker.exists():
        marker.write_text("", encoding="utf-8")


# ---------------------------------------------------------------------------
# check: validate a bundle against the spec
# ---------------------------------------------------------------------------

def cmd_check(args):
    bundle = AUTHORING / args.name
    if not bundle.is_dir():
        print("no bundle at %s" % bundle)
        return 1

    problems = []
    for key, w, h, _slice, _tint, _desc in SPEC:
        f = bundle / (key + ".png")
        if not f.exists():
            problems.append("missing  %s.png" % key)
            continue
        size = png_size(f)
        if size is None:
            problems.append("not a PNG  %s.png" % key)
        elif size != (w, h):
            # A different size is allowed for art that scales, but the caller
            # should know: 9-sliced chrome and the tiled grounds depend on their
            # authored pixels, so a resize there changes borders and seams.
            note = "  (9-slice — border widths will change)" if _slice else ""
            problems.append("size     %s.png is %dx%d, spec says %dx%d%s" % (key, size[0], size[1], w, h, note))

    if not (bundle / PALETTE).exists():
        problems.append("missing  %s" % PALETTE)

    stray = [
        str(f.relative_to(bundle))
        for f in bundle.rglob("*")
        if f.is_file() and is_engine_file(f)
    ]
    for s in stray:
        problems.append("engine file in a bundle: %s" % s)

    if not problems:
        print("bundle %s: %d assets + palette, all present and correctly sized" % (args.name, len(SPEC)))
        return 0

    for p in problems:
        print("  " + p)
    print("\n%d problem(s)" % len(problems))
    return 1


# ---------------------------------------------------------------------------
# build: bundle -> importable pack
# ---------------------------------------------------------------------------

def cmd_build(args):
    bundle = AUTHORING / args.name
    pack_name = args.pack or args.name
    pack = PACKS / pack_name

    if not bundle.is_dir():
        print("no bundle at %s" % bundle)
        return 1

    rc = cmd_check(argparse.Namespace(name=args.name))
    if rc != 0 and not args.force:
        print("\nrefusing to build from a bundle that fails check — pass --force to override")
        return 1

    if pack.exists():
        # Replace the ART only. Anything the engine owns is rebuilt afterwards,
        # and blowing the directory away would also drop the .import files whose
        # uids other resources may already reference.
        for f in list(pack.rglob("*")):
            if f.is_file() and not is_engine_file(f):
                f.unlink()
    else:
        pack.mkdir(parents=True)

    copied = 0
    for f in sorted(bundle.rglob("*")):
        if f.is_dir() or f.name == "README.md":
            continue
        rel = f.relative_to(bundle)
        (pack / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, pack / rel)
        copied += 1

    print("\ncopied %d file(s) into assets/packs/%s" % (copied, pack_name))
    print()
    print("now run, in order:")
    print("  godot --headless --import")
    print("  python tools/fix_imports.py %s" % pack_name)
    print("  godot --headless -s res://tools/gen_pack_resource.gd -- --pack %s" % pack_name)
    print()
    print("the first regenerates import settings, the second re-applies the ones")
    print("this project requires, the third rebuilds pack.tres from what is there.")
    return 0


# ---------------------------------------------------------------------------
# the artist-facing README
# ---------------------------------------------------------------------------

def write_readme(bundle, name):
    lines = []
    add = lines.append

    add("# Asset bundle — `%s`" % name)
    add("")
    add("Everything in this folder is art. There is nothing here about the game")
    add("engine, and you do not need to know anything about it.")
    add("")
    add("**To make a new skin:** edit the PNGs, and/or the six colours in")
    add("`packet_palette.svg`. Keep the file names and folder layout exactly as")
    add("they are — the game finds each asset by its path.")
    add("")
    add("## The three rules")
    add("")
    add("**1. Some art is TINTED by the game.** Those files must be authored")
    add("**white**, with the shape in the alpha channel. The game multiplies them")
    add("by a colour it chooses at runtime — a Packet's colour, or the readable")
    add("contrast against whatever it sits on. Authoring them in colour is the one")
    add("mistake that produces a wrong-looking game with no error anywhere,")
    add("because the file itself is perfectly valid.")
    add("")
    add("Tinted assets are marked **TINT** in the table below.")
    add("")
    add("**2. Keep the pixel dimensions** unless you have a reason. Sizes are")
    add("listed below. It matters most for anything marked **9-slice**: that art")
    add("has a fixed border and a stretchy middle, and the border width is")
    add("measured in source pixels. Double the image and you double the border.")
    add("")
    add("**3. Transparency is real.** PNG alpha is used throughout — a shape on a")
    add("transparent ground, not a shape on a coloured square.")
    add("")
    add("## Pairs that must stay different from each other")
    add("")
    add("Some assets carry meaning only by CONTRAST with another asset. A recolour")
    add("that treats each file on its own can leave both valid and the game")
    add("unreadable — every check will pass and a player will not be able to tell")
    add("two states apart.")
    add("")
    add("| These | Must differ because |")
    add("| --- | --- |")
    add("| `bar_fill_link` vs `bar_fill_ice` | They are the two sides' health, side by side in the header. Same colour means you cannot tell who is winning. |")
    add("| `badge_player` vs `badge_enemy` | The ONLY signal of who owns an overlay. One must read light, the other dark. |")
    add("| the four `program_box_*` | Idle, charged, yours-and-charged, armed. Four states of the same control. |")
    add("| `button_selected` vs `button_disabled` | Chosen versus unavailable. Differing only in brightness is what made this ambiguous before. |")
    add("| the six palette colours | Packet identity. Two that read alike make a match ambiguous. |")
    add("")
    add("## The palette")
    add("")
    add("`packet_palette.svg` holds the **six Packet colours** and opens in")
    add("Inkscape or any SVG editor. Change the fills; do not rename the swatch")
    add("IDs, and do not add or remove swatches. Their order is meaningful to the")
    add("game, so recolour in place rather than rearranging.")
    add("")
    add("These six are the only colours the game reads from outside the images.")
    add("Every other colour lives in the PNG that uses it.")
    add("")
    add("## The assets")
    add("")
    add("| File | Size | Notes | What it is |")
    add("| --- | --- | --- | --- |")
    for key, w, h, slice_m, tint, desc in SPEC:
        notes = []
        if tint:
            notes.append("**TINT**")
        if slice_m:
            notes.append("9-slice %d" % slice_m)
        add("| `%s.png` | %d×%d | %s | %s |" % (key, w, h, ", ".join(notes) or "—", desc))
    add("")
    add("## Sending it back")
    add("")
    add("Zip the folder and return it whole. Nothing else is needed — no export")
    add("settings, no manifest, no naming convention beyond keeping the paths.")

    (bundle / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def cmd_spec(args):
    bundle = AUTHORING / args.name
    if not bundle.is_dir():
        print("no bundle at %s" % bundle)
        return 1
    write_readme(bundle, args.name)
    print("refreshed authoring/%s/README.md" % args.name)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    e = sub.add_parser("export", help="pack -> clean authoring bundle")
    e.add_argument("name")
    e.add_argument("--force", action="store_true")
    e.set_defaults(func=cmd_export)

    c = sub.add_parser("check", help="validate a bundle against the spec")
    c.add_argument("name")
    c.set_defaults(func=cmd_check)

    b = sub.add_parser("build", help="bundle -> importable pack")
    b.add_argument("name")
    b.add_argument("--pack", help="destination pack name (default: same as bundle)")
    b.add_argument("--force", action="store_true")
    b.set_defaults(func=cmd_build)

    s = sub.add_parser("spec", help="regenerate a bundle's README")
    s.add_argument("name")
    s.set_defaults(func=cmd_spec)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

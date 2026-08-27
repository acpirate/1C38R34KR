# Asset Pack v0 — Gate B inspection notes

**Gate B deliverable.** Authorization §7.6.
**Date:** 2026-08-26. **Status:** awaiting director approval.
**Nothing in the renderer depends on these assets yet.**

Contact sheet: **https://claude.ai/code/artifact/22229bfa-b32f-4334-afac-a736480a15f1**

---

## 1. What exists

| Item | Where |
| --- | --- |
| 40 PNGs + `manifest.json` | `assets/packs/v0/{chrome,battle,packet,overlay,icon}/` |
| Editable palette | `assets/packs/v0/packet_palette.svg` |
| Composition sheets | `staging/gate-b/sheet_*.png` |
| Contact sheet | the artifact above — every asset, three backdrops, 9-slice guides |
| Generator | `tools/gen_assets.gd` |
| Structural checks | `tools/check_assets.gd` |
| Sheet builders | `tools/gen_contact.gd`, `tools/gen_contact_sheet.py` |

**The pack is generated, not drawn.** `gen_assets.gd` reads `PacketStyle` — the
same registry the live renderer reads — so a v0 asset cannot drift from the
whitebox it replaces, and the whole pack is regenerable by editing one file. If
you reject something here, the fix is a code edit and a re-run, not thirty
redrawn PNGs.

---

## 2. Verification

`godot --headless -s res://tools/check_assets.gd` → **all structural checks
passed.** It checks the failures a human would miss at a glance, not the ones a
glance catches:

- every glyph carries **both** tones — white core, grey outline, transparent
  outside. A collapse to one tone would make every Packet a flat silhouette and
  would look fine as a thumbnail.
- rings are hollow; badges have the correct ownership polarity.
- **the palette parses.** All six ids resolve, all six are valid and distinct,
  and **all six match `PacketStyle.COLOR_FILL` exactly**.

That last check does double duty. It proves v0 reproduces the current colours
rather than approximating them, and it proves the **D-033 palette path works**:
the SVG is still readable as text after import, which is the assumption the
whole decision rests on. Worth settling now rather than discovering it on a
device at Phase E.

The tools log `WARNING: Loaded resource as image file, this will not work on
export` — expected and correct. These are build tools reading files from the
project directory; nothing in the game loads an image that way.

---

## 3. Three things to look at, and what I think of them

### 3.1 The badge covers most of the Packet

Visible in `sheet_overlay_composition.png`: with an overlay present, a diamond
is reduced to four points poking out around the badge.

**This is faithful, not a defect I introduced.** The live renderer uses
`badge_r = size.x * 0.22` and a type ring at `1.28 × badge_r`, so the overlay
spans 61% of the cell. v0 reproduces that exactly.

But it does mean the design's stated intent — *"the Packet's own colour and
shape stay legible around it, because the player still has to match it"* — is
only weakly achieved for compact shapes. Colour survives everywhere. Shape
survives well for the star and cross, poorly for the diamond and circle.

Per §13 I am reporting it rather than fixing it: shrinking the badge is an art
and design decision, not asset plumbing, and it would put v0 out of step with
the build it is supposed to reproduce. **Flagging it as the first thing the real
art pass should reconsider.**

### 3.2 The outline does not survive the small scale

`sheet_scale_check.png`. A glyph draws at ~118 px on the board and ~30 px as the
binding swatch inside a Program box. At 30 px the two-tone averages away and the
glyph reads as a flat silhouette.

**I think this is fine, and want to say so rather than hide it.** The swatch
exists to answer "which Packet identity feeds this Program" — that is colour and
shape, and both survive cleanly. The outline is definition, not information, and
it does its job at the size where the player is actually matching Packets.

The outline was already authored generously (14% of the radius) for exactly this
reason. Pushing it further would thicken it noticeably on the board to buy
something at 30 px that carries no meaning.

### 3.3 Godot's defaults were already right

Four of the five import settings §6 called for are Godot 4.7's defaults for a 2D
texture. Only `detect_3d/compress_to` needed changing, and it needed changing on
all 40 — left at its default it silently re-imports a lossless asset as VRAM
compressed the moment the texture is seen in 3D. Nothing here is 3D, but a
setting that converts lossless to lossy with nobody editing anything is exactly
what §2.2 forbids.

Also corrected: **filtering is not an import setting** in Godot 4. It is a
project setting, already at Linear, which is what was wanted. Proposal §6 has
been rewritten to say what is actually true.

---

## 4. The one thing not yet proven

**The SVG surviving a real Android export.** It is `importer="keep"`, and
`export_presets.cfg` now carries `include_filter="*.csv,*.svg"` — the same
mechanism this project already uses to ship its content CSVs past the importer,
so the approach is established here rather than novel. But it has been verified
in the editor's file system, not in an installed APK.

It gets confirmed at the first Phase E device pass. If it fails, D-033's
implementation changes from parse-at-startup to a generated `.tres` and nothing
else about the contract moves.

---

## 5. On approval

Phase C builds the catalog — `GraphicsPack`, `Graphics`, `pack.tres`, the SVG
parser, `validate()`, the MISSING checker, and the extended presentation test —
with **no renderer changes**, and the suite must be green before any screen
converts. Phase D then converts in five commits with a tablet check between
each, per proposal §10.

Rejection at this gate costs a `gen_assets.gd` edit and a re-run.

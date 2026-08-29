# Installed skins

Captured 2026-08-28 on the Galaxy Tab A (1200×1920), `beta-0.3.2.1`. Debug
builds, so the seed row and `1x / charge / ovl / win / lose / log` are visible
and would not appear in a release.

Six skins ship in one APK. A debug control on the title screen cycles them live;
a pack is ~130 KB against a 56 MB APK, so the whole set costs about 1%.

Each was built from `authoring/<name>/` through the ordinary path — `check`,
`build`, import, `fix_imports`, `gen_pack_resource` — and **no engine file was
edited for any of them**. That is the graphics contract doing what it was built
for.

| File | Skin | Character |
| --- | --- | --- |
| `00-title-v0.png` | — | The title screen and the skin picker |
| `16bit.png` | `16bit` | Soft SNES-era palette, bevelled cells, starfield ground |
| `bzone.png` | `bzone` | Vector outlines on a wireframe grid |
| `neon90s.png` | `neon90s` | Cyan frames on near-black, hot pink against spring green |
| `phosphor.png` | `phosphor` | Monochrome CRT with scanlines |
| `terminal.png` | `terminal` | Green terminal, brighter and higher contrast than `phosphor` |
| `terminal-overlays.png` | `terminal` | Every overlay state at once — see below |
| — | `v0` | The generated baseline, retained as fallback and template |

## What these confirm

**Every skin is a pure asset swap.** Same header, same two Program columns, same
AGIMA row, same board, same message stack, same debug bar. Nothing moved,
because nothing could — layout is code and none of it was touched.

**The palette is genuinely external.** All six load different Packet colours
from their own `packet_palette.svg`.

**Overlays survive a reskin.** `terminal-overlays.png` shows all four type marks
in both ownership polarities plus both armed countdown states, rendering
correctly under a skin that changed every chrome asset.

## Worth judging on hardware

Two things the validators cannot check, both from the **pairs that must stay
different** rule in the bundle README:

- **`phosphor` collapses LINK and ICE to the same green.** They are the two
  sides' health, side by side in the header, and at a glance you cannot tell who
  is winning. `bzone`, `neon90s`, `terminal` and `16bit` all keep them distinct.
  `phosphor` was a mechanical recolour written to prove the pipeline, and this is
  exactly the failure that predicts.
- **`terminal`'s ownership badges read similarly** — both polarities carry a
  green ring, where `v0` uses a light fill against a dark one. Worth a second
  look in play, since ownership is the only thing the badge fill carries.

Both are art notes, not defects: the files are valid, every check passes, and
the game runs. They are the class of problem that only a person looking at the
screen can settle.

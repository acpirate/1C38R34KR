# Beta 0.3.1 — AFTER the graphics conversion

Captured 2026-08-27 on the **Galaxy Tab A 10.1 (SM-T580), 1200×1920**, from
`beta-0.3.1` at the end of Phase E.

The pair to `../beta-0.3.1-before/`. Same device, same screens, same debug
build — every pixel here is drawn from **Asset Pack v0** rather than from
`_draw` calls and `StyleBoxFlat`.

## What to compare

**1. The overlay marks (`05`, `09`).** `?`, `+`, `S`, `Ø` were characters from
`ThemeDB.fallback_font`. They are silhouettes now — a fused charge, a plus, a
shield, a slashed ring — tinted with the badge's opposite colour so ownership is
unchanged. The countdown digit is still text, deferred to the text pass.

**2. The battle messages (`08`).** "System fires CODESHATTER" and "System wins"
named a Boss "System"; the header's placeholder title was the literal `SYSTEM`.
All three resolve through the opponent union now, so the log reads
"15 damage to ODANSHAY".

**3. Everything else should look nearly identical**, and does. Asset Pack v0 is
generated from `PacketStyle` — the same registry the whitebox drew from — so a
colour or weight that shifted between the sets would be a conversion defect, not
an art decision. Two were found exactly that way and fixed before these were
taken (D-040):

- the Build slot's amber bar was two and a half times too thin, because a
  9-slice preserves its corner region 1:1 and the bar had been authored at the
  number the old code *computed* rather than the pixels it *produced*;
- the reorder arrows had shrunk to nothing, because a Label overflows its
  container's padding and a texture does not.

A third was caught a commit earlier and never reached a capture: every bordered
frame was being drawn with `draw_texture_rect`, which stretches rather than
nine-patching, so a 2 px edge became roughly 24 px on the widest control.

## The set

| File | Screen |
| --- | --- |
| `01-title.png` | Title |
| `02a-boss-select.png` | Boss selection, nothing chosen |
| `02b-boss-select-chosen.png` | Boss selection, card chosen |
| `02c-path-choice.png` | Path Choice, Battle 1 |
| `02d-path-choice-selected.png` | Path Choice with a route taken |
| `02e-path-choice-boss.png` | Path Choice, Battle 4 — both routes the Boss |
| `03-build.png` | Build — the slot bar and reorder arrows to compare |
| `04-battle.png` | Battle against a System |
| `05-battle-all-overlays.png` | **Every overlay at once** |
| `06-pause.png` | Pause over a live board |
| `07-result.png` | Victory and the battle report |
| `08-boss-battle.png` | The ODANSHAY battle |
| `09-boss-battle-all-overlays.png` | **Every overlay at once, Boss board** |
| `10-run-complete.png` | RUN COMPLETE |

**One deliberate omission.** The before set has `03b-build-boss.png`; this one
does not. The Boss Build differs from the ordinary Build only in the length of
its UPGRADE list and the absence of the debug skip — nothing this pass touched —
and `03-build.png` covers every converted element on that screen. It was not
worth further device time to reproduce a redundant frame.

## Not covered here

These are tablet captures. The phone was verified separately: geometry by
emulating 1080×2340 on this tablet (P-045), then the rest on the physical S25 —
safe area over the real cutout, no clipping, all four overlay marks legible and
mutually distinguishable at panel density in both ownership polarities, charged
and ready frames distinct, clean log. Both device gates are signed off.

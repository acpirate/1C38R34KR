# Beta 0.3.1 — BEFORE the graphics conversion

Captured 2026-08-26 on the **Galaxy Tab A 10.1 (SM-T580), 1200×1920**, from
`beta-0.3.1` at the end of Phase C.

**This is the baseline half of a before/after pair.** At capture time the
graphics catalog existed and Asset Pack v0 was complete and validated, but
**nothing in the renderer drew from it yet** — Phase D had not begun. So every
pixel here is the procedural whitebox. The matching `beta-0.3.1-after/` set will
be captured from the same screens once the conversion lands.

Debug builds, so the seed row and the `1x / charge / ovl / win / lose / log`
controls are visible and would not appear in a release build.

## The set

| File | Screen |
| --- | --- |
| `01-title.png` | Title, with a resumable Run |
| `02a-boss-select.png` | Boss selection, nothing chosen |
| `02b-boss-select-chosen.png` | Boss selection with the card chosen |
| `02c-path-choice.png` | Hacker selection |
| `02d-path-choice-selected.png` | Path Choice, Battle 1, one card taken |
| `02e-path-choice-boss.png` | Path Choice, Battle 4 — both routes are the Boss |
| `03-build.png` | Build, Battle 1 |
| `03b-build-boss.png` | Build, Battle 4 — four UPGRADEs, no debug skip |
| `04-battle.png` | Battle against a System |
| `05-battle-all-overlays.png` | **Every overlay at once** — see below |
| `06-pause.png` | Pause, over a live board |
| `07-result.png` | Victory and the battle report |
| `08-boss-battle.png` | The ODANSHAY battle, ICE 250 |
| `09-boss-battle-all-overlays.png` | **Every overlay at once, on the Boss board** |

## The all-overlays shots

`05` and `09` are the answer to "get every overlay on one screen", and they
exist because that state is **not reachable by playing**. A Boss Override, a
Hacker Shield, an armed Bomb and a pending Buff owned by both sides do not
co-occur in any battle you could set up deliberately, so the overlay vocabulary
could never be seen, compared, or photographed as a whole.

The `ovl` debug button stamps the board with:

- **row 1** — every type, live, Hacker-owned (light badge, dark mark)
- **row 2** — every type, live, System-owned (dark badge, light mark)
- **row 3** — the armed state in both polarities, showing the countdown digit
  beside the marks it replaces

Left to right in rows 1–2: **BOMB, BUFF, SHIELD, OVERRIDE**.

It writes real `Tile.Special` objects into the live board and refreshes through
the ordinary path, so what is photographed is what a battle would draw. It also
skips neutrals rather than overwriting them — a neutral has no axes and can
never carry an overlay, and a debug view that broke that rule would be showing a
board the game cannot produce, which is worse than showing nothing because it
would be believed.

**Two things these shots confirm on hardware:**

- The type ring is **gone** (D-037). Compare against `beta03-*` in the parent
  directory, where a coloured ring surrounds every badge.
- The type marks are still **font characters** — `?`, `+`, `S`, `Ø`. That is
  exactly what makes this a useful "before": D-038 replaces them with raster
  silhouettes during Phase D, and this is the last capture that shows the old
  behaviour.

## What to look at in the after set

Three things this pass is expected to change, listed now so the comparison has a
question rather than a vibe:

1. **The overlay marks** become silhouettes instead of letterforms, and stop
   depending on whatever font the device falls back to.
2. **Selection stops being a brightness change.** On `02a`, `02c` and `03` the
   unchosen card, the disabled `Choose`, and an unavailable Program in the swap
   grid are all just *dimmer* — two different meanings rendered the same way.
   `button_selected` gives chosen its own frame.
3. **Everything else should look nearly identical.** Asset Pack v0 is generated
   from `PacketStyle`, so if a panel, bar or box shifts colour or weight between
   the two sets, that is a conversion defect and not an art decision.

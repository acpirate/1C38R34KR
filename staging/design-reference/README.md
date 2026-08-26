# Visual reference

The alpha reference the beta is matched against, and the beta's own
screens as they stand. The alpha set was captured 2026-08-23 from `breach` alpha-0.7.0 running in the browser at a
430×932 phone viewport (`http://localhost:5174/`). These are the **source of
truth for the beta's initial look**, per the director's instruction to
"replicate those using the currently implemented game systems and with the later
systems as they are added".

Two things this reference is NOT:

- It is not a pixel target. The shape glyphs in particular are expected to be
  replaced (see `decisions.md` D-014). Match the *composition and information
  hierarchy*; the palette is a placeholder that travels with it.
- It is not a scope expansion. Screens the beta does not have yet (Run paths,
  UPGRADEs, System/HOST selection with full card detail) are described here so
  the later phases have something to build against, not so 0.1 grows.

## The images

### Alpha (`alpha-*.jpg`) — the reference being matched

| File | Screen |
| --- | --- |
| `alpha-01-title.jpg` | Title |
| `alpha-02-build.jpg` | Build (CONSTRUCTED QUICK MATCH) |
| `alpha-03-battle.jpg` | Battle, idle |
| `alpha-04-battle-hint.jpg` | Battle with the status/hint line populated |
| `alpha-05-pause.jpg` | Pause menu with ACTIVE BATTLE CONFIG |

### Beta 0.1 (`beta-*.png`) — the first port, for comparison

`beta-01-title`, `beta-02-system-select`, `beta-03-build`, `beta-04-battle`,
`beta-05-pause`, `beta-06-result`. Quick Match only: no Run, no routes, no
UPGRADEs, no Boss.

### Beta 0.3 (`beta03-*.png`) — current, captured 2026-08-25

Captured from `beta-0.3.0` on real hardware. Files with no suffix are the
**Galaxy S25 (1080×2340)**, which is the phone-shaped case the alpha reference
was captured at; `-tablet` files are the **Galaxy Tab A (1200×1920)**. Both are
debug builds, so the seed row and the `1x / charge / win / lose / log` controls
are visible and would not appear in a release build.

| File | Screen | Device |
| --- | --- | --- |
| `beta03-01-title.png` / `-tablet` | Title, no save | both |
| `beta03-02-path-choice.png` / `-tablet` | Path Choice, Battle 1 (fixed DOORMAN + THRESHOLD, two UPGRADEs) | both |
| `beta03-03-build.png` / `-tablet` | Build with Run context | both |
| `beta03-04-battle.png` / `-tablet` | Battle against a System | both |
| `beta03-05-battle-victory.png` / `-tablet` | Battle won, mid-Run | both |
| `beta03-06-run-defeat.png` | Battle lost — Retry / Abandon | S25 |
| `beta03-07-boss-build-tablet.png` | Build for Battle 4, ODANSHAY at ICE 250 | Tab A |
| `beta03-08-boss-battle-tablet.png` | **The ODANSHAY battle** | Tab A |
| `beta03-09-run-complete-tablet.png` | **RUN COMPLETE** — the Boss is down | Tab A |

**What changed since the 0.1 set, visually:**

- Both sides' Programs are on screen at once — the single biggest gap the alpha
  reference called out, now closed.
- Packets are a coloured glyph on a dark cell, with neutrals as static.
- Selection screens are select-then-confirm, per the reference's recommendation.
- Every Run screen carries the Run context block (battle N of 4, opponent, ICE,
  HOST, LINK, acquired UPGRADEs, Boss).
- The Boss is an honest identity: the battle header reads **ODANSHAY**, never
  "SYSTEM", and its ICE is the authored 250.
- Overrides render as a ringed `Ø` badge on the Packet, which keeps its colour
  and shape underneath. Not captured in a still here — placement happens at the
  end of a Boss turn, so it needs a battle in progress to see.

**Two layout facts these images encode**, both learned the hard way and worth
keeping when the art pass lands:

- The phone is the constraint, not the tablet. The tablet has ~120 px more width
  and has twice hidden a phone-only defect (P-031, AN-006/P-044).
- The debug rows are deliberately laid out so they cannot widen the battle
  scene — the seed sits on its own line for exactly that reason.

**No image for the VICTORY screen.** The browser screenshot tool stopped
persisting captures to disk partway through the session, and chasing that was
not worth the time. The screen is fully described in "Result" below, and it is
built from *exactly* the same `.dialog` + `.metrics` CSS as the pause menu —
`alpha-05-pause.jpg` is a faithful stand-in for its chrome. The content list is
transcribed from the live screen.

## Where the alpha's values actually live

Everything below was read out of the alpha source, not eyeballed from the
screenshots. If a value here disagrees with an image, the source wins:

- `breach/src/style.css` — every overlay/dialog/menu screen. The alpha's menus
  are DOM, not canvas.
- `breach/src/render/view.ts` — the battle screen, which is one canvas.
  `COLOR_HEX`/`DARK_HEX` at the top, `layout()` around line 354, `drawHud`
  through `drawTile` from line 624.

---

## Palette

| Role | Value | Source |
| --- | --- | --- |
| Page / letterbox | `#000` | `style.css` |
| Dialog panel | `#2a2a34`, 1px `#555` border | `.dialog` |
| Dialog text | `#eee`; secondary `#aaa`; metrics `#bbb` | `.dialog`, `.metrics` |
| Button | `#3a3a48`, 1px `#666`, text `#eee` | `.dialog button` |
| Button active | `#505064` | |
| Button disabled | `opacity: .45` | |
| Selected option | `#34343f`, **2px `#e0a040`** | `.optlist .opt.sel` |
| Accordion section | `#23232c`, 1px `#444` | `.cfgsection` |
| Wizard/dev control | `#4a3a1a` on `#ffcf6a`, border `#a87a2a` | `.dialog button.wizard` |
| Board surround | `#111118` | `drawBoard` |
| Board cell | `#26262e` | `drawBoard` |
| HUD box | `#2c2c36`, border `#555` idle | `drawUnitBox` |
| HUD box charged | border `#e0a040` 2px; **ready** border `#ffffff` | `drawUnitBox` |
| HUD box targetable | fill `#3c3220`, border `#ff9500` 3px | `drawUnitBox` |
| Charge bar | track `#1c1c24`; fill `#6080c0`, charged `#f0c040` | `drawUnitBox` |
| LINK bar | `#58c06a` | `drawAvatarBox` |
| ICE bar | `#c05858` | `drawAvatarBox` |
| Charge text | `#aaa`, charged `#ffe080` | `drawUnitBox` |
| Selection ring | `#ff9500` 3px | `drawBoard` |
| Hint ring | pulsing `rgba(80,220,255,·)` 4px | `drawBoard` |
| System-turn frame | `#e03030` | `drawHud` |

The six Packet colours and their dark shades are already in
`scenes/battle/packet_style.gd`, copied verbatim. They match.

## Type

The alpha uses `system-ui, sans-serif` throughout — no imported font. Sizes:
`h1` 22px with `letter-spacing: 1px`, `p` 15px, buttons 19px, option names 18px
bold with `letter-spacing: 1px`, option body 15px, metrics 15px at `line-height:
1.5`, config 16px at `1.7`.

The letter-spaced bold-caps heading is the single most recognisable thing about
the alpha's identity. Keep it.

---

## Title

Centred dialog panel, not a full-bleed screen. Stacked full-width buttons with
8px gaps:

```
BREACH — alpha-0.7.0
[ Continue Quick Match ]   ← only when a save exists
[ Quick Match          ]
[ New Run              ]
[ Settings             ]
```

Quick Match opens a second panel — `QUICK MATCH` / grey subtitle `CR45H / AGIMA`
/ `Random Quick Match`, `Constructed Quick Match`, `Back`.

Starting a new game over an existing save raises a `REPLACE SAVE?` panel with an
explanatory line and Cancel / Replace this save. Worth keeping: it is a
destructive action behind a plain-language confirm.

## Selection screens

Bold letter-spaced title, grey one-line instruction ("Choose the System you will
breach"), then a scrollable list of cards:

```
NAME [SYS_01]          ← bold, 18px, letter-spaced
ICE 100
Strong: Red, Cyan
Weak:  Yellow, Magenta, Green, Blue
```

Colours and shapes are spelled out in full words, never abbreviated to a swatch.
Selection is **select-then-confirm**: tapping a card marks it (`2px #e0a040`),
and a separate `Choose` button — disabled until something is selected — advances.
A `Back` button is always present.

The beta currently commits on tap. Moving to select-then-confirm is a real
improvement (it makes a mis-tap recoverable on a phone) and is the change this
reference most wants from the selection screens.

## Build

Collapsible summary panels above the working area:

```
▶ CR45H + AGIMA — LINK 150, SCRAMBLE (3)
▶ SYSTEM: BOUNCER — ICE 100
▶ HOST: THRESHOLD
```

Then `ACTIVE BUILD (top to bottom)` and four ordered slots:

```
│ 1. BOMBER [Hacker]        [▲]
│ Red + Triangle — BOMB (7) [▼]
```

The `│` is a 4px left accent bar — `#e0a040` for active slots, `#3d3d4a` for the
inactive inventory below. Arming an inactive Program turns it `#4fa3d1` and the
active slots border-match to read as drop targets. No drag input anywhere: every
interaction is a tap or an arrow.

Two facts the layout makes unmissable and the beta's build screen does not:
each slot shows its **binding** (colour + shape) and its **Function and cost**.
Charge routing follows slot order, so the order is functional and the screen
says so in its own header.

## Battle

Top strip, three items on one row:

```
[HACKER          ] [ ≡ ] [SYSTEM          ]
[LINK 150/150 ▓▓▓]       [ICE 100/100 ▓▓▓]
```

Avatar boxes are 46px tall and 34% of width each; the pause button is a 44px
`≡` centred between them. Buff/Shield totals appear right-aligned in the avatar
box in `#ffe080` and are hidden at zero.

Below it, **a two-column grid showing both sides at once** — Hacker Programs
left, System Programs right, four rows of 40px boxes with a 4px gap, then the
Deck Function alone in the left column on a fifth row. Each box:

```
◆ BOMBER
0/7
▓▓▓▓░░░░░░░░
```

— binding glyph swatch (14px, same coloured-icon style as the board), name in
bold shrunk-to-fit, `charge/cost` bottom-left, charge bar along the bottom.

Seeing the System's charge state at all times is not decoration; it is the
information the player schedules around. **This is the single biggest gap in the
beta's battle screen** — it shows the Hacker's side only.

The board sits below, sized to fill what is left, and the status line runs along
the very bottom at ~5% of height in amber.

### Packets

`drawTile` (view.ts:925). **The Packet IS a coloured glyph on a dark cell.**
There is no coloured tile field and no white glyph — the note in the source is
explicit that the white-on-colour style was superseded and the field removed.

- Glyph traced at `cell * 0.46`, filled `COLOR_HEX`, stroked `DARK_HEX` at 2px.
- Cell background `#26262e`, inset 1px, on a `#111118` surround.
- **Neutrals are a static/noise texture**, drawn with smoothing off — never a
  blank space and never one of the six colours.
- Overlays are a **centred** badge inside the glyph at `cell * 0.22`: white fill
  = player-owned, black fill = enemy-owned, with the opposite colour as the ring
  and the text. Content is the countdown while armed, then `S` for shield, `Ø`
  for an Override, `+` for a live buff.

The beta currently draws a filled rounded rect per Packet with a white glyph on
top and a *corner* badge. Converting to coloured-glyph-on-dark is the highest-
impact single change available, and it is confined to `packet.gd` and
`packet_style.gd`.

## Pause

```
PAUSED
Quick Match
[ Resume        ]
[ Reset         ]
[ Save and Quit ]
────────────────
ACTIVE BATTLE CONFIG
System matching · Single-axis payout · Reinforced Connection ·
Normal LINK · Cascade cap · Hacker LINK · Hints
```

The config readout is read-only here and editable from Settings. Its value is
that a tester can answer "what rules is this battle actually running under?"
without leaving the battle — which is the same reason the beta's title screen
carries the content fingerprint.

## Result

Same `.dialog` chrome as Pause.

```
VICTORY                     ← or the defeat heading
System ICE breached.        ← grey 15px cause line
[ Reset        ]
[ Back to Title ]
──────────────── scrollable metrics, left-aligned, #bbb ────────────────
BATTLE                                              ← .mhead, #fff, bold
Turns to resolution: 1
Sync-locks (auto-reshuffles): 0
Detonations: 0
System shields — created 0, sliced 0
Shielded hits: 0, damage prevented: 0

HACKER
Total damage dealt: 9
Sync-caused (incl. its cascades): 9
bomb-caused (incl. its cascades): 0
line-slice-caused (incl. its cascades): 0
transform-caused (incl. its cascades): 0
Deepest cascade: 0 RNG rounds
Line clears: 0
Opponent-bound Packets sliced: 6 of 6 (100.0%)
Charge wasted (no Program could take it): 3
BOMBER [PRG_H_001]: fired 0, effect 0
ATTACKER [PRG_H_003]: fired 0, effect 0
DISABLER [PRG_H_004]: fired 0, effect 0
WEASEL [PRG_H_006]: fired 0, effect 0
SCRAMBLE [DEK_01 deck]: fired 0, neutral charge 0 (wasted 0)

SYSTEM
… the same block, mirrored
```

Notes that matter for the port:

- The buttons come **above** the metrics, so the exits are reachable without
  scrolling a long report on a phone.
- Per-Program lines carry the stable content ID in brackets. That is what makes
  a screenshot of this screen actionable against the harness, and it is why the
  beta's result screen should grow the same thing when metrics land (Phase 6).
- `Reset` replays; the beta's equivalent pair is `Replay this seed` / `New
  battle`, which is strictly better for debugging and should stay.

## Other observations worth carrying over

- **Damage floaters.** A red `-6` rises over the box that took the hit. Cheap,
  and it is the only thing that makes a multi-source cascade readable.
- **Hint affordance.** `find sync` sits as a small dev-only green-on-dark button
  (`#303a30`/`#9f9`, `opacity: .7`) docked over the board, and a hint pulses a
  cyan outline on both cells of the suggested pair.
- **System-turn lock** reads as a red viewport border plus a 10% dim over the
  grid — never a modal, never a blocked tap with no explanation.
- **Targeting** dims every illegal region to 35% and puts a red X on the armed
  control meaning "tap again to cancel". Under Packet targeting the board gets a
  pulsing amber frame instead of dimming, because it has to stay pickable.

The dim-the-illegal-regions pattern is worth taking wholesale. It answers "what
can I tap right now?" with no text at all.

# 1C38R34KR beta 0.3.1 — graphics asset contract proposal

**Gate A deliverable.** Authorization: `1c38r34kr-beta-0.3.1-graphics-asset-layer-authorization-revised.md` §6.4.
Intent: `Graphics Asset Layer — Iteration 1 Intent.md`.
**Date:** 2026-08-26. **Status:** Gate A approved (with inventory latitude — see §4.8). Pack generated; see the Gate B notes.

Four design forks were resolved with the director before this document was
written; they are recorded in §9 and carried through the inventory.

---

## 1. Renderer inspection

### 1.1 What exists

Nine files, 3,385 lines, and the architecture is already most of the way to
what this build asks for.

| File | Lines | Role |
| --- | --- | --- |
| `scenes/battle/packet_style.gd` | 213 | **the presentation registry (D-014)** — every colour, the six shape geometries, overlay tints, playback tints |
| `scenes/ui_theme.gd` | 159 | one Godot `Theme`; sizes and shapes; the `px()` scale; safe-area insets |
| `scenes/battle/packet.gd` | 147 | one Packet: cell, glyph, neutral static, overlay badge, selection ring |
| `scenes/battle/datastream.gd` | 301 | the 8×8 board; owns 64 `PacketView`s; draws the surround |
| `scenes/battle/unit_box.gd` | 188 | one Program: box, state border, binding swatch, name, charge text, charge bar, cancel mark |
| `scenes/battle/avatar_box.gd` | 93 | one side's LINK/ICE: box, border, title, Buff/Shield totals, bar with the value inside it |
| `scenes/battle/battle_screen.gd` | 904 | battle composition, playback, pause panel, debug bar |
| `scenes/main.gd` | 1,261 | fifteen screens, all built from five chrome primitives |
| `scenes/touch_scroll.gd` | 119 | two-finger scroll gesture |

### 1.2 The seam already exists

`PacketStyle` is a real presentation registry, not an aspiration.
`test_presentation.gd` **enforces** it by scanning every file under `scenes/`
and failing on any hex literal outside the registry. That test is why this build
is a re-pointing rather than an excavation: there is exactly one place today
where identity becomes appearance, and this proposal keeps it as exactly one
place while changing what it returns.

`UiTheme` already separates SIZE from COLOUR and builds one inherited `Theme`
for `Button`, `Label`, `VScrollBar`, and `LineEdit`. Every stylebox in it is a
`StyleBoxFlat` whose only content is a background colour, a 1 px border, and
content margins — precisely the shape that converts to `StyleBoxTexture` with no
layout change.

### 1.3 Where layout and skin are entangled

Four components are **100% `_draw`** — no textures, no styleboxes, no child
nodes: `PacketView`, `UnitBox`, `AvatarBox`, `Datastream`. Their geometry is
derived from `size` at draw time (`pad := size.y * 0.10`, `swatch := size.y *
0.30`), so the proportions are code, not authored art. That is the entanglement
this build addresses, and it is also why the conversion is safe: because the
proportions derive from `size`, replacing a drawn rect with a stretched texture
over the same rect changes appearance without touching layout.

`main.gd` funnels all fifteen screens through five primitives — `_fresh_screen`,
`_panel`, `_button`, `_divider`, `_slot_box`. Converting those five converts
every menu screen at once. It is the highest-leverage point in the codebase.

### 1.4 Packet representation, as shipped

Worth stating precisely, because prose elsewhere describes an older design.

**A Packet IS the coloured glyph.** There is no tile field behind it. The cell
draws `CELL_BACKGROUND`, and the glyph is drawn at `size.x * 0.46` filled in
`COLOR_FILL[c]` and stroked in `COLOR_BORDER[c]`. The board surround shows
through the 6% gaps and is what draws the grid; cells carry no border of their
own.

A **neutral** has no colour and no shape. It renders as per-cell deterministic
noise seeded from the cell coordinate — every neutral cell's static differs, and
it is stable across redraws so it does not read as motion.

An **overlay** is a badge centred in the glyph: ownership is the badge FILL
(light for Hacker, dark for System, each ringed in the other), the special TYPE
rides a thin outer ring in `OVERLAY_TINT[t]`, and the badge centre carries
either the countdown digit (armed) or a live-state character — `S`, `Ø`, `?`,
`+`. Colour, shape, ownership and special identity therefore already coexist,
which is what §7.4 asks the overlay design to preserve.

### 1.5 Discrepancy found — dead registry entries (§1 requires recording this)

Six registry members are **consumed by nothing**:

`SYSTEM_TURN_FRAME`, `NEUTRAL_FILL`, `NEUTRAL_BORDER`, `GLYPH`, and the two
accessors `fill_for()` / `border_for()`.

They are survivors of the beta 0.1 representation, when a Packet was a coloured
*square* with a white glyph on it. When the representation changed to "the
Packet is the glyph", the constants stayed. `packet.gd`'s own comment records
the change: *"A white glyph on a coloured square reads as a gem; this reads as a
signal on a wire."*

**Why it matters here:** reading the registry as the asset inventory — the
natural thing to do — would generate a neutral fill, a neutral border, a white
glyph colour, and a System-turn frame that nothing renders. The shipped
implementation wins per §1. **Proposal: delete the six dead members** in Phase E
rather than generating art for them.

### 1.6 Fonts

There is no font resource anywhere. Every drawn string uses
`ThemeDB.fallback_font`, and `UiTheme` sets font *sizes* but never a font. Per
the director's Gate-A answer, **text rendering is out of scope for this pass**;
no font slot is proposed. See §4.7.

---

## 2. Architecture

Three types, mirroring the three concerns §5 requires be kept apart.

### 2.1 `GraphicsPack` — a Godot `Resource`

```gdscript
class_name GraphicsPack extends Resource

@export var screen_bg: Texture2D
@export var panel: Texture2D
@export var button_normal: Texture2D
...
@export var packet_glyph: Array[Texture2D]     # keyed by Types.PacketShape
@export var overlay_ring: Array[Texture2D]     # keyed by Tile.Special.Type
@export var palette_svg: String                # res:// path, parsed at startup
```

Saved as `assets/packs/v0/pack.tres`. **The exported fields are the contract.**
A missing asset is a null field, which makes completeness a property that can be
checked mechanically rather than noticed on a device.

Swapping the whole pack is one `.tres` path. That is the release-appropriate
plumbing §19 wants the jig to reuse.

### 2.2 `Graphics` — the accessor

One static façade. Screens ask for semantics, never paths:

```gdscript
Graphics.pack.button_normal
Graphics.glyph(shape_index)         # Types.PacketShape -> Texture2D
Graphics.overlay_ring(type_index)   # Tile.Special.Type -> Texture2D
Graphics.palette(color_index)       # Types.PacketColor  -> Color
```

`glyph()` and `overlay_ring()` are functions rather than raw array access so an
out-of-range key returns the MISSING texture (§7) instead of crashing.

**No path string appears outside `pack.tres`.** Authorization §9.3.

### 2.3 `PacketStyle` — what it keeps

It stays the registry and loses only what the pack now owns. It keeps: text
colours, playback tints (`TINT_*`), the scrim, the six shape *geometries* (still
needed — the binding swatch in `UnitBox` and the glyph both draw from them), and
the six palette colours **as the fallback** when the SVG cannot be read.

`test_presentation.gd`'s hex-literal ban survives unchanged, because pack colours
live inside PNGs and introduce no new literals anywhere.

---

## 3. Palette ingestion — as directed

**Director decision, overriding authorization §11 and §18.10.** §11 specifies a
live pipeline: edit the SVG, save, run the normal build workflow, and the game
picks the values up. The director's instruction is that the SVG is a **lossless
handoff channel from director to agent**, not a production pipeline, and that
the game may either hardcode the values or ship and parse the SVG.

Recorded as **D-033** so a later agent does not "fix" this back toward §11.

**Chosen path, of the two allowed: ship `packet_palette.svg` inside the pack and
parse it once at startup**, with `PacketStyle`'s six constants as a loud-failing
fallback.

- Hardcoding leaves the SVG in the repo as a document that can silently drift
  from the constants it is supposed to define. Drift between a stale document
  and live runtime values has cost this project twice already — P-043, and the
  lesson *"current runtime data must outrank stale implementation prose."*
  Parsing makes that drift structurally impossible.
- The jig is required (§19, and the director's answer) to read the SVG. Parsing
  in the game means the jig reuses this exact code path instead of growing a
  parallel one — which is the stated reason for doing release-appropriate
  plumbing now rather than later.

Parse cost is one ~2 KB file at startup, read with Godot's `XMLParser`. The six
swatches are located by their stable XML `id`, and the fill is read from either
the `fill` attribute or the `style` attribute, since Inkscape writes either
depending on how the object was created.

**Failure is loud, never silent:** a swatch that is missing, unparseable, or
duplicated logs `push_error` naming the id, and the fallback constant is used
for that entry only. Startup validation reports all six together (§7).

---

## 4. Asset inventory

**44 PNGs and one SVG.** Every entry is required by something the live game
currently renders on a device this build targets; nothing is speculative.

The director delegated add/merge/delete authority over this list on the grounds
that the intent doc's version was inferred from screenshots. §4.8 records what I
changed and why.

Alpha = transparency. 9-slice = scalable chrome with fixed corners.

### 4.1 Screen chrome — 14

| Semantic key | Source px | Alpha | 9-slice | Replaces |
| --- | --- | --- | --- | --- |
| `screen_bg` | 256×256 tileable | no | tile | `BOARD_BACKGROUND` ColorRect (both `main.gd` and `battle_screen.gd`) |
| `panel` | 48×48 | no | 16 | `_panel` + pause panel `StyleBoxFlat` |
| `button_normal` | 48×48 | no | 16 | `UiTheme._button_box(CONTROL, CONTROL_EDGE)` |
| `button_pressed` | 48×48 | no | 16 | `_button_box(PANEL_DEEP, ACCENT)` |
| `button_selected` | 48×48 | no | 16 | **new** — see §4.8 |
| `button_disabled` | 48×48 | no | 16 | `_button_box(PANEL_DEEP, PANEL_EDGE)` |
| `rule` | 64×8 | no | stretch x | `_divider()` ColorRect, both copies |
| `scroll_track` | 32×32 | no | 12 | `VScrollBar` scroll stylebox |
| `scroll_thumb` | 32×32 | no | 12 | grabber / highlight / pressed |
| `bar_track` | 32×16 | no | 6 (x) | `CHARGE_TRACK` rect in both boxes |
| `bar_fill_link` | 32×16 | no | 6 (x) | `LINK_BAR` |
| `bar_fill_ice` | 32×16 | no | 6 (x) | `ICE_BAR` |
| `bar_fill_charge` | 32×16 | no | 6 (x) | `CHARGE_FILL` |
| `bar_fill_charge_ready` | 32×16 | no | 6 (x) | `CHARGE_FILL_READY` |

Bar fills are four distinct coloured PNGs rather than one white texture tinted
at runtime, because §11 restricts runtime colour configuration to the six Packet
colours — every other colour is authored into its PNG.

### 4.2 Battle chrome — 8

| Semantic key | Source px | Alpha | 9-slice | Replaces |
| --- | --- | --- | --- | --- |
| `avatar_box` | 48×48 | no | 16 | `AvatarBox` background + `CONTROL_EDGE` border |
| `program_box_idle` | 48×48 | no | 16 | `UnitBox` box + `BOX_EDGE` @1px |
| `program_box_charged` | 48×48 | no | 16 | box + `ACCENT` @2px |
| `program_box_ready` | 48×48 | no | 16 | box + `READY` @2px |
| `program_box_armed` | 48×48 | no | 16 | box + `ACCENT_HOT` @3px |
| `board_surround` | 64×64 | no | tile | `Datastream._draw` |
| `packet_cell` | 64×64 | no | 16 | `CELL_BACKGROUND` rect in `packet.gd` |
| `build_slot` | 48×48 | no | 16 | `_slot_box()` — accent left bar baked in, held by the 9-slice margin |

Background and border combine into one texture per state rather than a
background plus four frame overlays: it halves both the asset count and the draw
calls, and no state needs them to vary independently. The `dimmed` state stays a
`modulate`, unchanged.

### 4.3 Packet — 8

| Semantic key | Source px | Alpha | 9-slice | Notes |
| --- | --- | --- | --- | --- |
| `packet_glyph[CIRCLE]` | 128×128 | yes | no | monochrome, tinted |
| `packet_glyph[SQUARE]` | 128×128 | yes | no | |
| `packet_glyph[TRIANGLE]` | 128×128 | yes | no | |
| `packet_glyph[DIAMOND]` | 128×128 | yes | no | |
| `packet_glyph[STAR]` | 128×128 | yes | no | |
| `packet_glyph[CROSS]` | 128×128 | yes | no | |
| `ring_selected` | 64×64 | yes | 20 | `SELECTION` rect outline |
| `ring_targeting` | 64×64 | yes | 20 | `TARGETING` rect outline |

**Glyph construction — director decision (fork 1).** Each glyph is ONE
monochrome image carrying two tones: the silhouette at `#FFFFFF` and its outline
at mid-grey (`#8C8C8C`). A single `modulate` by the palette colour therefore
produces the fill AND a proportionally darker outline, from one texture and one
palette entry.

Consequence: the twelve hand-picked constants collapse to six. `COLOR_BORDER` is
**retired** — the outline stops being an authored hue and becomes a fixed ratio
of the fill. The result approximates today's borders rather than reproducing
them exactly, which §2.5 permits.

Colour and shape stay strictly independent, and there are six glyphs rather than
thirty-six.

### 4.4 Overlays — 10

| Semantic key | Source px | Alpha | Notes |
| --- | --- | --- | --- |
| `badge_player` | 128×128 | yes | light fill, dark ring |
| `badge_enemy` | 128×128 | yes | dark fill, light ring |
| `overlay_ring[BOMB]` | 128×128 | yes | outer type ring |
| `overlay_ring[BUFF]` | 128×128 | yes | |
| `overlay_ring[SHIELD]` | 128×128 | yes | |
| `overlay_ring[OVERRIDE]` | 128×128 | yes | |
| `overlay_mark[BOMB]` | 64×64 | yes | **new** — a charge with a fuse |
| `overlay_mark[BUFF]` | 64×64 | yes | **new** — a plus |
| `overlay_mark[SHIELD]` | 64×64 | yes | **new** — a shield silhouette |
| `overlay_mark[OVERRIDE]` | 64×64 | yes | **new** — a slashed ring |

**The type ring is suspended (D-037).** The alpha never had one; type rides the
badge's centre mark alone, and the ring was an undocumented beta addition that
widened the overlay from 0.45 × cell to 0.61. The four `ring_*` PNGs and
`OVERLAY_TINT` are **retained but not displayed**, because the director is
taking the question to the designer and "not now" is not "never". Filed as
AN-007.

**The four marks are art, not font characters (D-038).** They were `S`, `Ø`,
`+`, `?` drawn from `ThemeDB.fallback_font`. `Ø` in particular is not guaranteed
to exist in an arbitrary fallback face, and a missing glyph renders as a box on
the Boss mechanic's only board-level signal. They are authored white with alpha
and tinted with the badge's opposite colour, so ownership is unchanged.

With the ring suspended these carry the whole type signal, as in the alpha — so
each is a silhouette rather than a letterform.

Composition: glyph underneath, ownership badge centred, mark inside the badge.
Every currently reachable special state is covered — the enum is
`{BOMB, BUFF, SHIELD, OVERRIDE}`, and `test_presentation.gd` already asserts the
tint array covers it, so the same assertion extends to the texture arrays.

### 4.5 Icons — 4

| Semantic key | Source px | Alpha | Replaces |
| --- | --- | --- | --- |
| `icon_menu` | 64×64 | yes | the `≡` Button text in the battle header |
| `icon_arrow_up` | 64×64 | yes | `_move_button` glyph |
| `icon_arrow_down` | 64×64 | yes | `_move_button` glyph |
| `icon_cancel` | 64×64 | yes | `UnitBox._draw_cancel`, two drawn lines |

**Flagged for Gate A.** These four are characters today, and the director's
answer to fork 3 said to leave text as it is. I read that as scoping out
*typography* — names, numbers, shrink-to-fit labels — rather than these four,
because the intent doc lists "battle menu icon", "up-arrow icon" and
"down-arrow icon" as assets by name, and the chosen fork-3 option named the
cancel mark explicitly. **If that reading is wrong, drop these four and the pack
is 36 PNGs** — nothing else in the plan changes.

### 4.6 Palette — 1

`packet_palette.svg` — six swatches, stable ids `packet_red`, `packet_yellow`,
`packet_green`, `packet_cyan`, `packet_blue`, `packet_magenta`, each visibly
labelled, on one canvas, laid out to be pleasant to edit as a coordinated set.

### 4.7 Deliberately NOT assets

| Element | Why |
| --- | --- |
| **Neutral static** | Director decision (fork 4): stays procedural. Per-cell deterministic noise is what stops a field of neutrals reading as a repeating pattern, and a sprite cannot vary per cell. **D-034 — an explicit, named exception to the asset contract.** |
| **All text** | Director decision (fork 3): text rendering is untouched. `draw_string`, `ThemeDB.fallback_font`, and the shrink-to-fit loops stay exactly as they are. **D-035.** |
| Countdown digits | Still text, and now the only text in the badge. A countdown is a live value, and the choice between 0–9 sprites, text, or something more iconic is **deferred to the text pass** by the director. The four type marks that used to share this code path are now assets — D-038. |
| Bar fill *widths*, charge numbers, LINK/ICE values, Program names | These encode live values. Nothing that encodes a value becomes a bitmap. |
| Playback tints, damage flash, pause scrim | `modulate` and one translucent rect; not appearance an artist would replace with an image. |
| Six dead registry members | §1.5 — nothing renders them. |

### 4.8 Judgement calls on the inventory

The intent doc's list was inferred from screenshots. Reading the source changes
four of its entries and confirms the rest. The governing principle for the ones
I kept apart: **merge on identity, not on current appearance.** Two assets that
happen to look alike at v0 stay separate if an artist would plausibly want to
differentiate them later, because merging them means that differentiation costs
a code change — the exact retrofit the registry exists to prevent.

**ADDED — `button_selected`.**

The intent doc asks for a "selected button" and I could not find one, so I went
looking for how selection is actually expressed. It is `modulate` and nothing
else: an unchosen card is `TINT_INACTIVE`, the chosen one is `TINT_NONE`.

That collides on the Build screen, where a swap button has three states at once
— *chosen* (`TINT_NONE`), *available* (`TINT_INACTIVE`), and *already used in
another slot* (`disabled`, which is also grey). **Two different meanings both
render as "dimmer".** §16.2 requires selected and disabled be distinguishable,
and right now they are separated only by how grey they are.

One asset fixes it, and it is the highest-leverage entry in the pack: selection
runs through `_show_chooser`, which serves Boss, Hacker, Deck, System and HOST
selection **and** Path Choice — six screens — plus the Build swap grid.

A screenshot cannot show this. Two greys look like a style; they were a
multiply.

**DELETED — `button_hover`.**

Hover is unreachable on both devices this build targets (§13: phone and tablet
portrait). The Theme's hover slot points at `button_normal`. If Windows becomes
a target, it is one PNG and one line to restore — but authoring art now for a
state no target device can display is scope §14 does not want.

**DELETED — `field`.**

The only `LineEdit` in the game is the debug seed entry at `main.gd:479`, inside
`if OS.is_debug_build()`. It does not exist in a release build. It keeps its
current `StyleBoxFlat`, whose colours still come from the registry, so the
hex-literal ban still passes.

This is AN-006's lesson applied one step further: a debug affordance must not be
load-bearing for the game's layout, and it should not consume production art or
a catalog slot either.

**REWORKED — `divider` → `rule`, authored 64×8 and rendered at `px(2)`.**

At `px(1)` a linearly-filtered texture is mush; there is no art you can put in
one pixel. At two it can carry a gradient, a dashed trace, or a taper, which is
the point of making it an asset at all. Straightforward to revert to a
`ColorRect` if you would rather keep the hairline.

**CONFIRMED ABSENT — three intent-list entries with no referent.**

| Intent entry | Finding |
| --- | --- |
| emphasized / active panel | The game has exactly one panel style, used by both the screen panel and the pause panel. Nothing renders an emphasized variant. Not created. |
| Datastream / board frame | There is no frame around the board. `AspectRatioContainer` holds the `Datastream`, which draws only its surround. "Board frame" maps to `board_surround`; it is not a second element. |
| Build priority / accent treatment | Real, but not a separate asset — it is the amber left edge already baked into `build_slot`, deliberately mirroring the mark a charged Program carries in battle. |

**One art-spec note the screenshots could not reveal.**

`packet_glyph[]` is drawn at **two very different scales**. On the board it is
≈118 px. In `UnitBox` it is also the *binding swatch* — `swatch := size.y * 0.30`
on a `px(40)` box, so roughly **30 px**, about a quarter the size.

The v0 glyphs must therefore stay legible at ~25% scale, which constrains the
two-tone outline: an outline tuned to look right at 118 px will close up and
muddy the silhouette at 30. v0 authors the outline as a proportion generous
enough to survive the small case, and the S25 pass checks the swatch
specifically.

---

## 5. Folders and naming

```
assets/
  packs/
    v0/
      pack.tres
      packet_palette.svg
      chrome/    screen_bg, panel, button_*, rule, scroll_*, bar_*
      battle/    avatar_box, program_box_*, board_surround, packet_cell, build_slot
      packet/    glyph_*, ring_selected, ring_targeting
      overlay/   badge_*, ring_*
      icon/      menu, arrow_up, arrow_down, cancel
```

`snake_case.png`, filename equal to the semantic key. Array-keyed assets carry
the enum name (`glyph_triangle`, `ring_override`) rather than an index, so a
mis-ordered array is visible on inspection instead of only in play — the enum
ORDER is gameplay identity, and getting it wrong silently rewrites weaknesses.

A future pack is a sibling directory plus one `.tres`. No path outside
`pack.tres` changes.

---

## 6. Import settings

**Corrected after generating the pack.** The proposal originally listed five
settings to configure and named texture filtering as one of them. Reading
Godot 4.7's actual importer output, four of the five are already its defaults
for a 2D texture, and filtering is not an import setting at all:

| Setting | State |
| --- | --- |
| `compress/mode=0` (Lossless) | already the default |
| `mipmaps/generate=false` | already the default |
| `process/fix_alpha_border=true` | already the default |
| `compress/normal_map=0` | already the default |
| `detect_3d/compress_to` | **defaults to 1 — patched to 0 across all 40** |

`detect_3d/compress_to=1` tells Godot to silently re-import the texture as VRAM
compressed if it ever sees it used in 3D. Nothing here is used in 3D, but the
setting is a trapdoor: it converts a lossless asset to a lossy one without
anyone editing anything, which is precisely what §2.2 forbids. It is the only
one that needed changing, and it needed changing everywhere.

**Filtering is a project setting, not an import setting.** In Godot 4 it is
`rendering/textures/canvas_textures/default_texture_filter`, or a per-CanvasItem
override. The project does not set it, so it is at Godot's default of **Linear**
— which is what §6 wanted anyway. No change, and no pixel-art commitment made.

**The palette SVG is imported with `importer="keep"`.** Godot's texture importer
would otherwise convert it to a `CompressedTexture2D`, and D-033 needs the file
readable as *text* at runtime. `export_presets.cfg` now carries
`include_filter="*.csv,*.svg"` so the raw file ships — the same mechanism the
project already uses to ship its content CSVs past the importer.

Source sizes survive both targets without per-resolution duplication: 9-slice
chrome is resolution-independent by construction, and the 128 px glyph never
upscales — a 1080-wide board gives ≈128 px cells, and `radius = size.x * 0.46`
makes the drawn glyph ≈118 px.

---

## 7. Missing or invalid assets — authorization §10

Three layers, none of which is a silent fallback to the old whitebox:

1. **Startup validation.** `GraphicsPack.validate()` walks every exported field
   and every array slot and returns the list of null semantic keys. It runs once
   at launch and reports **all** failures together — one `push_error` per key,
   naming it: `graphics: missing required asset 'button_hover'`.
2. **A conspicuous MISSING texture.** Any null resolves to a generated
   magenta/black checker, never to the procedural code it replaced. §9.4 — an
   element that lost its asset must LOOK broken, because a whitebox fallback is
   indistinguishable from success.
3. **No crash.** `Graphics.glyph()` and `overlay_ring()` bounds-check, so a bad
   key degrades to the checker.

If validation finds any missing key, the game routes to the existing
`_show_validation_failure` screen — the same treatment content validation
already gets, listing every missing key rather than only the first.

---

## 8. Verification

**Automated** (§15.1 — no heavy visual differential):

- `test_presentation.gd` extended: every exported `GraphicsPack` field non-null;
  `packet_glyph` covers `Types.PacketShape`; `overlay_ring` covers
  `Tile.Special.Type`; the SVG parses and yields six valid, distinct colours;
  the existing hex-literal ban still passes.
- Full headless suite (3,122 tests) — no gameplay code is touched.
- Fast battle parity (150 battles) as the guard that nothing leaked into logic.
- **No DEEPSCAN.** §15.1 requires it only if shared gameplay code changes, and
  none does. If that turns out to be false, the plan changes and I will say so
  rather than skip it quietly.

**Device** (§16) — and this is where the real coverage is. Stated plainly: the
scene layer has **no** automated coverage by design, and this build modifies
almost nothing else. The last two user-visible defects in this project (P-042's
Boss header, AN-006's overflow) both lived in exactly this layer, and both were
caught by eyes on a device rather than by tests. So:

- Tablet during Phase D, per screen group as it converts, not once at the end.
- `adb shell wm size 1080x2340` on the tablet before each pass, per P-045 — the
  phone geometry is where overflow appears, and the tablet is 120 px wider.
- S25 at sign-off: the seven screens in §16.1, safe area, no clipping, glyph
  legibility, and that selected / disabled / ready remain **distinguishable** —
  the state most at risk when a 2 px drawn border becomes a scaled texture.

---

## 9. Decisions this proposal records

| ID | Decision |
| --- | --- |
| **D-033** | `packet_palette.svg` is a lossless director→agent handoff channel, not a live production pipeline. Overrides authorization §11 and reinterprets §18.10. Implementation: ship the SVG in the pack, parse once at startup, fall back loudly to constants. |
| **D-034** | Neutral static stays procedural — a named exception to the asset contract, because per-cell variation cannot come from a sprite. |
| **D-035** | Text rendering is untouched in 0.3.1. No font slot, no `Label` conversion, no typography decisions. **Amended by D-038** — the four overlay type marks become art. The countdown digit stays a font glyph, explicitly deferred to the text pass. |
| **D-037** | The overlay type ring is suspended, restoring alpha parity. Retained, not deleted. |
| **D-038** | The four overlay marks become PNGs rather than font characters. Amends D-035. |
| **D-036** | Packet glyphs carry fill and outline as two tones in one monochrome PNG, tinted by one palette entry. `COLOR_BORDER` is retired; the palette stays at six entries. |

---

## 10. Implementation plan

**Phase B — Asset Pack v0, then Gate B.**

The 40 PNGs are **generated by a committed headless tool**
(`tools/gen_assets.gd`) that draws into `Image`s and saves them, rather than
hand-authored. Three reasons: it can port the exact current `_draw` code, which
is the most reliable way to "approximately reproduce the current presentation";
the pack is regenerable if the contract shifts at Gate B; and the generator
documents the v0 look precisely, in code, for whoever replaces it.

The SVG is authored by hand — it is the one file meant for a human editor.

Gate B package: the asset directory, a manifest listing every key with its size,
alpha and 9-slice margins, and a **contact sheet** showing every asset together
at true and scaled size against both a dark and a light backdrop, with 9-slice
margins drawn on the scalable ones. I propose delivering that as a published
artifact so it is inspectable on the tablet without a file browser; say so if
you would rather have a plain PNG sheet committed to the repo.

**Phase C — the catalog.** `GraphicsPack`, `Graphics`, `pack.tres`, the SVG
parser, `validate()`, the MISSING checker, and the extended presentation test.
No renderer changes. The suite must be green before any screen converts.

**Phase D — conversion, in five commits, tablet-checked between each:**

1. `UiTheme` styleboxes → `StyleBoxTexture` (converts every menu screen's
   buttons, fields and scrollbars at once).
2. `main.gd`'s five chrome primitives, plus `battle_screen`'s background and
   pause panel.
3. `PacketView` — cell, glyph, rings, badge, type ring. The riskiest single
   commit; the board is the screen.
4. `UnitBox` and `AvatarBox` — boxes, state frames, bars, cancel icon.
5. `Datastream` surround, header menu icon, Build move-arrow icons.

**Phase E — cleanup and devices.** Delete the six dead registry members; delete
the procedural code the pack now owns (§9.4 — it must not survive as a hidden
fallback); full tablet pass; S25 pass.

**Phase F — closeout.** README, decisions D-033..D-036, port notes, the §1.5
discrepancy, lessons, final diff, commit, push.

---

## 11. What I am not doing

Confirming against §14: no jig, no hot reload, no filesystem watching, no
screenshot overlay, no scene-selection tooling, no animation or particle or
shader work, no audio, no HOST or Boss visual variation, no encounter
escalation, no landscape, no layout restructuring, no final art direction, no
generalized theme/recolour system, no content, no gameplay change.

Per §13: if the asset layer exposes a pre-existing layout defect, it is reported
as an architect note — it does not widen this pass.

---

**Gate A. Awaiting approval before generating Asset Pack v0.**

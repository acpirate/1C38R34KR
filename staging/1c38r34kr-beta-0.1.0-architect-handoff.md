# 1C38R34KR Beta 0.1.0 — Architect Handoff

**Build identity:** `beta-0.1.0`

**Status:** Canonical architecture and scope specification for the first Godot build of 1C38R34KR.

**Primary objective:** Port the Breach logic core to GDScript as a Node-free, headlessly testable rules layer; render one complete Constructed Quick Match battle in Godot with touch input on a physical Android device; prove the port is faithful by differential testing against the alpha rather than by inspection; defer Runs, routes, HOSTs, UPGRADEs, and the Boss layer to later beta builds.

---

# Part I — Authority, Inputs, and Working Method

## 0. Document authority

This document is authoritative for **architecture, scope, and verification method**.

It is deliberately **not** a game-rules specification. The rules already exist, are complete, and are the product of seven alpha builds of design work. Restating them here would create a second authority that can drift from the first.

Use sources in this order:

1. **This document** for scope boundaries, layer architecture, engine-specific decisions, module mapping, verification gates, and acceptance criteria.
2. **`C:\Users\chode\breach\README.md`** for authoritative game behavior. This is the feature narrative of the completed alpha and describes the system as actually shipped.
3. **`C:\Users\chode\breach\staging\breach-alpha-0.7.0-coding-agent-handoff.md`** for the most recent resolved behavior, lifecycle ordering, and edge-case rulings.
4. **`C:\Users\chode\breach\src\logic\`** for exact algorithms where prose is ambiguous. The TypeScript is the tiebreaker.
5. Earlier alpha handoffs (`0.5.0`, `0.6.0`) only for behavior those documents resolved and later ones preserved.
6. `data/*.csv` in this repo for authored content. These are byte-identical to the alpha's datasets; only filenames changed.

If the alpha source and the alpha README disagree, the **source wins** and the discrepancy is reported rather than silently resolved.

## 0.1 What "port" means here

The logic layer is a **translation**, not a redesign. Where the alpha's algorithm is expressible in GDScript, express it the same way, in the same order, with the same intermediate steps — even where a more idiomatic GDScript formulation exists. Faithfulness is worth more than elegance in this build, because §9–§11 make faithfulness *mechanically checkable* and elegance is not.

The presentation layer is a **rewrite**. `src/main.ts` and `src/render/` carry no rules and earn no deference.

## 0.2 The two repositories

| | |
| --- | --- |
| `C:\Users\chode\breach` | The alpha. TypeScript/Vite, feature-complete at `alpha-0.7.0`. **Read-only.** Never modify it from this repo, and never commit to it. |
| `C:\Users\chode\1C38R34KR` | This repo. Godot 4.7.2, GDScript. |

The alpha remains runnable (`npm run dev`, `npm test`, `npm run batch`) and that matters — §10 depends on it. Do not let it rot.

## 0.3 Fresh-context rule

Begin implementation with a fresh coding-agent context. Inspect both repositories directly rather than relying on assumptions carried from the environment-setup session that produced this document.

## 0.4 Execution model

**There is no Senior/Junior split.** Director ruling, 2026-08-20: one mode from here on.

One coding agent owns the whole build:

- repository inspection across both repos
- implementation plan
- implementation
- integration
- tests, fixtures, and the differential harness
- device verification
- README update
- final diff review, commit, push, and final report

## 0.5 README and source control

The coding agent owns README and source-control completion. After implementation and a full verification-gate pass:

1. update `README.md` to describe beta 0.1 as actually shipped;
2. inspect the final diff;
3. stage only intended changes;
4. commit with a concise build message;
5. push to `origin/main`.

Do not push a knowingly failing or partially verified build.

---

# Part II — Build Objective and Explicit Scope

## 1. Beta 0.1 objective and why the scope is what it is

Beta 0.1 delivers **one complete, playable Constructed Quick Match battle on a physical Android device**, backed by a faithful logic port.

The alpha is roughly 15,600 lines. Attempting all of it in one build produces a change too large to verify, and verification is the entire problem in a rules port — a subtly wrong charge-routing rule does not crash, it just makes the game quietly worse in a way no one notices for weeks.

A single Quick Match battle exercises the parts that carry genuine risk:

- CSV loading, reference resolution, and startup validation
- board generation, Sync detection, cascades, line clears
- charge generation and top-to-bottom routing with overflow
- Function activation, Effect dispatch, composites, targeting, fizzles
- the PASSIVE runtime and instance-keyed attribution
- countdown overlays and delayed delivery
- the enemy turn, dynamic Function phase, and activation eligibility
- the bot
- event-sourced metrics
- rendering, animation playback, touch input, and save/resume on device

What it does *not* exercise is Runs, routes, HOSTs, UPGRADEs, and Bosses — and those are the layers the alpha itself added last, on top of a stable battle, in builds 0.5 through 0.7. They layered cleanly then and there is no reason they won't again.

Shipping a battle that runs on the director's phone also converts every later balance question from speculation into something testable on hardware.

## 2. In scope

1. The logic layer, ported in full for battle-scoped behavior (§4–§8).
2. Deterministic RNG with exact alpha parity (§9).
3. The differential verification harness (§10–§11).
4. Content loading, reference resolution, and the complete startup validation suite (§12–§14).
5. Title → System Selection → HOST Selection → Build → Battle → Result, as a playable flow.
6. Canvas-equivalent rendering of the 8×8 Datastream with animation playback.
7. Touch input: tap-to-select, tap-adjacent-to-swap, drag-to-swap, Function activation, Packet targeting.
8. Save and resume of an active battle.
9. Event-sourced metrics and the logging tiers.
10. Headless test suite and headless battle simulation.
11. Android debug build verified on hardware.

**HOST Selection is in scope** despite HOSTs being a "later layer" — the alpha requires every battle to have exactly one HOST, Quick Match included, and HOST PASSIVEs are load-bearing for the PASSIVE runtime. Excluding them would mean porting the PASSIVE system with one of its four source kinds stubbed, which is worse than including them.

## 3. Explicit exclusions

Deferred, with the build that owns them:

| Deferred | Target |
| --- | --- |
| New Run, the four-battle ladder, Path Choice, route RNG, route persistence | beta 0.2 |
| UPGRADEs and Run-local reward state | beta 0.2 |
| Random Quick Match | beta 0.2 |
| The Boss layer, `BOS` dataset, ODANSHAY, the Override mechanic | beta 0.3 |
| Windows desktop export | beta 0.4 |
| Hosted browser export | beta 0.4 |
| Art, audio, animation polish, accessibility | post-beta |
| Balance changes of any kind | post-beta content pass |

`data/bos.csv` and `data/upg.csv` stay in the repo and stay parsed and validated — they are simply not routed to yet. Dropping them and re-adding later would mean writing their loaders twice.

**No balance changes.** Every constant in `src/logic/constants.ts`, every authored CSV value, and every default in `DEFAULT_BATTLE_SETTINGS` ports across unchanged. If a value looks wrong, report it; do not fix it. A port that also retunes is a port that cannot be differentially verified.

---

# Part III — Architecture

## 4. Layer boundaries

Three layers, with a one-way dependency rule:

```
app/     screen flow, menus, scene switching        ──┐
scenes/  rendering, animation, input                 ──┼──> depends on logic/
logic/   rules, state, events, content, save         ──┘    logic depends on NOTHING
```

`logic/` must not reference `Node`, `SceneTree`, `Tween`, `Input`, `DisplayServer`, or any `@tool`-only API. It is plain `RefCounted` and static functions.

This is not stylistic. It is what makes §10 possible, and it is the property the alpha already has (`src/logic/` vs `src/render/`). Losing it would forfeit both the headless harness and the differential gate.

**Enforcement:** a test in the suite greps `scripts/logic/**/*.gd` for `extends Node`, `get_tree()`, `create_tween()`, and `Input.` and fails on a hit. Cheap, and it catches the drift on the day it happens rather than three builds later.

## 5. Module map

Port module-for-module. Keeping the names aligned makes the alpha readable as reference material for the life of the beta.

| Alpha | This repo | Notes |
| --- | --- | --- |
| `src/logic/types.ts` | `scripts/logic/types.gd` | enums, constants, event-key registry |
| `src/logic/constants.ts` | `scripts/logic/constants.gd` | verbatim values |
| `src/logic/rng.ts` | `scripts/logic/rng.gd` | exact mulberry32 — see §9 |
| `src/logic/board.ts` | `scripts/logic/board.gd` | |
| `src/logic/match.ts` | `scripts/logic/match_finder.gd` | `match` is a GDScript keyword |
| `src/logic/resolve.ts` | `scripts/logic/resolve.gd` | largest and highest-risk module |
| `src/logic/passive.ts` | `scripts/logic/passive.gd` | |
| `src/logic/game.ts` | `scripts/logic/game.gd` | |
| `src/logic/session.ts` | `scripts/logic/session.gd` | port battle-scoped parts only for 0.1 |
| `src/logic/save.ts` | `scripts/logic/save.gd` | |
| `src/logic/metrics.ts` | `scripts/logic/metrics.gd` | |
| `src/logic/logger.ts` | `scripts/logic/logger.gd` | |
| `src/logic/bot.ts` | `scripts/logic/bot.gd` | |
| `src/logic/data/csv.ts` | `scripts/logic/data/csv.gd` | `FileAccess.get_csv_line()` |
| `src/logic/data/load.ts` | `scripts/logic/data/load.gd` | 2,441 lines — see §13 |
| `src/logic/data/content.ts` | `scripts/logic/data/content.gd` | |
| `src/logic/data/effects.ts` | `scripts/logic/data/effects.gd` | |
| `src/logic/data/passives.ts` | `scripts/logic/data/passives.gd` | |
| `src/logic/data/areas.ts` | `scripts/logic/data/areas.gd` | |
| `src/render/`, `src/main.ts` | `scenes/`, `app/` | rewritten, not ported |
| `scripts/tests.ts` | `tools/run_tests.gd` | already scaffolded |
| `scripts/batch.ts`, `harness.ts` | `tools/batch.gd` | headless simulation |

## 6. Type mapping

| TypeScript | GDScript | Note |
| --- | --- | --- |
| `enum Color/Shape` | `enum Color/Shape` | identical int values 0–5; ordering is load-bearing for complement derivation |
| `interface Tile` | `class Tile extends RefCounted` | mutated constantly; object identity is fine at 64 cells |
| `Cell = Tile \| null` | `Tile` typed as nullable | GDScript objects are nullable natively |
| `Board = Cell[][]` | `Array[Array]` | `[y][x]`, y=0 top — preserve the convention |
| `Pt {x,y}` | `Vector2i` | native, cheap, and comparable |
| `Side = 'player'\|'enemy'` | `enum Side {PLAYER, ENEMY}` | string unions have no GDScript equivalent; use enums and keep string forms only at log/save boundaries |
| `Record<Side, T>` | `Dictionary` keyed by `Side` | |
| discriminated `GameEvent` union | `Dictionary` with `"t"` key | see §7 |
| `readonly` / structural types | not available | rely on the §4 enforcement test and review |

Every string-union type in `types.ts` (`Mode`, `Phase`, `OwnerKind`, `Readiness`, `DamageSource`, `SelectionSource`, …) becomes a GDScript `enum` in `types.gd`, with explicit `to_string`/`from_string` helpers used **only** when crossing the save or log boundary. Do not let raw strings circulate inside the logic layer; typo-shaped bugs in a dynamically typed language are expensive.

## 7. The event stream is the logic↔render boundary

The alpha's `GameEvent` union is the single most important architectural asset in the codebase: logic resolves a turn instantly and emits an ordered event list; the renderer plays it back over time. That split is why the game can run headless at all, and it ports directly.

GDScript has no discriminated unions. Three options were considered:

| Option | Verdict |
| --- | --- |
| One `RefCounted` class per event variant (~30 classes) | Type-safe, but heavy boilerplate and it obscures the line-by-line correspondence with the alpha that §10 depends on. |
| One class with a type enum and a wide optional-field set | Worst of both — neither type-safe nor readable. |
| **`Dictionary` with a `"t"` key** | **Chosen.** Direct correspondence to the alpha, trivial to serialize into traces (§11) and logs, no boilerplate. |

The cost is no compile-time checking of event shape. That cost is bought back two ways, both required:

1. `types.gd` holds a `const EVT` registry of every event name as a `StringName`. Literal strings for event types are forbidden — `EVT.DAMAGE`, never `"damage"`.
2. A debug-only `EventSchema.validate(evt)` checks required keys per event type and is called on every emission when `OS.is_debug_build()`. It is compiled out of release builds.

Event **order and content must match the alpha exactly.** The trace comparison in §10 is built on the event stream, so an extra, missing, or reordered event is a test failure — which is precisely the behavior wanted.

## 8. State ownership

`GameState` is a plain data object owned by the logic layer. Scenes hold a reference for reading and never mutate it. All mutation goes through logic-layer functions that return event lists.

The renderer's visual state is derived and disposable: it must be reconstructible at any time from `GameState` alone, because save/resume does exactly that.

---

# Part IV — Determinism and Differential Verification

*This part is the core of the build. Everything else is ordinary engineering.*

## 9. Port mulberry32 exactly

`src/logic/rng.ts` is mulberry32. **Do not substitute Godot's `RandomNumberGenerator`** — it is PCG32 and produces a completely different sequence.

Porting the exact PRNG is what makes §10 possible: identical seed plus identical rules must produce an identical battle in both engines. Substituting the RNG would forfeit the only mechanical check available on a 7,000-line rules translation.

The alpha implementation:

```javascript
s = (s + 0x6d2b79f5) >>> 0;
let t = s;
t = Math.imul(t ^ (t >>> 15), t | 1);
t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
```

**GDScript arithmetic hazards — all four will produce a silently wrong sequence if missed:**

1. GDScript `int` is 64-bit signed; JavaScript's bitwise ops are 32-bit. Every intermediate result needs `& 0xFFFFFFFF`.
2. `Math.imul(a, b)` is 32-bit **signed** multiplication that wraps. In GDScript, multiply then mask: `(a * b) & 0xFFFFFFFF`. Because every value is kept masked and non-negative, the sign difference does not affect the low 32 bits, which is all that survives.
3. `>>>` is an unsigned right shift. On a value already masked to 32 bits and non-negative, GDScript's `>>` is equivalent — but the mask must come first, every time.
4. The final division is by `4294967296.0` (float), not integer division.

`getState()` must be preserved: `makeRNG(rng.getState())` resumes the exact sequence, and save/resume depends on it.

**Acceptance for §9:** a test vector of the first 1,000 outputs for seeds `0`, `1`, `1337`, and `2147483647`, generated from the alpha and committed as a fixture, reproduced exactly by the GDScript implementation. Write this test first. Nothing else in Part IV works until it passes.

## 10. The differential harness

Both engines can run the same battle headlessly. Use that.

```
alpha:  npx tsx scripts/harness.ts --seed N --trace > alpha-N.jsonl
godot:  godot --headless -s res://tools/trace.gd -- --seed N > godot-N.jsonl
diff alpha-N.jsonl godot-N.jsonl
```

A battle is fully determined by: content fingerprint, System, HOST, Hacker, Deck, active build and order, settings, and seed. Fix all of those, run both engines, and the event streams must be **byte-identical**.

This converts "did I port 7,000 lines of rules correctly?" from a question answered by reading into one answered by running. When a divergence appears, the first differing line names the turn, the mechanism, and usually the exact function.

**The alpha needs a small addition to support this** — a trace-emitting entry point that dumps the normalized event stream. That is a change to the alpha repo, and it is the *only* sanctioned one. It adds a script, touches no rules, and must be committed to the alpha repo separately with a message saying exactly that.

**Acceptance for §10:** 200 consecutive seeds produce identical traces across every authored System, on every authored HOST, at default settings. Then 50 seeds with `reinforcedConnection` on, 50 with `enemyMatching` off, and 50 with `maxCascadeSteps` unset.

## 11. Trace format

One JSON object per line. Normalized so that irrelevant representational differences do not register as divergence:

- keys sorted; no insertion-order dependence
- floats serialized to a fixed 6-decimal representation
- `Side` and other enums as their alpha **string** forms (`"player"`, `"enemy"`), since the alpha is the reference
- `Pt`/`Vector2i` as `{"x":n,"y":n}`
- omit fields that are absent in the alpha rather than emitting `null`
- no timestamps, no think-time, no wall-clock anything

Prepend one header line carrying the content fingerprint, seed, and full battle identity. A fingerprint mismatch is an immediate hard failure — it means the two engines are not reading the same content and every subsequent line is meaningless.

---

# Part V — Content Pipeline

## 12. Loading

The ten datasets in `data/` are the content source of truth, byte-identical to the alpha's. Only filenames changed:

```
breach datastructures - BOS.csv   →   data/bos.csv
                       - DEK       →        dek.csv
                       - FNC       →        fnc.csv
                       - HAK       →        hak.csv
                       - HST       →        hst.csv
                       - PRG_H     →        prg_h.csv
                       - PRG_S     →        prg_s.csv
                       - PSV       →        psv.csv
                       - SYS       →        sys.csv
                       - UPG       →        upg.csv
```

Parse with `FileAccess.get_csv_line()`, which handles quoting and embedded commas correctly. Do not hand-roll a splitter.

**These files are already configured to survive export** — each carries an `importer="keep"` `.import` file so Godot's translation importer leaves it alone, and `*.csv` is in the export preset's include filter. This is verified: all ten appear at `assets/data/` inside the built APK. Do not change either setting; the failure mode is that reads work in the editor and fail on device.

Preserve the leading-apostrophe rule: a single leading `'` is spreadsheet-protection syntax and is stripped before trimming, parsing, resolution, validation, and fingerprinting. Apostrophes elsewhere are preserved.

## 13. Startup validation ports in full

`src/logic/data/load.ts` is 2,441 lines and most of it is validation. Port all of it.

It is tempting to treat validation as scaffolding and defer it. It is the opposite: it is the mechanism that lets content be authored in a spreadsheet by a designer without the ability to produce a silently broken build. Every rule in it exists because something could go wrong. The alpha README §"Startup validation" enumerates the categories; `load.ts` is authoritative for specifics.

Required behavior, unchanged:

- all errors and warnings collected, each with dataset, row, record ID, field, supplied value, expected form, and reason
- any error blocks startup
- warnings do not block
- invalid data is never silently repaired
- no hardcoded content fallback and no default System

On Android and desktop a validation failure shows a blocking failure screen. In headless tools it prints the complete result and exits nonzero.

Rules covering `BOS` and `UPG` still run in 0.1 even though neither layer is routed to yet (§3).

## 14. Fingerprinting

Port the content fingerprint. It gates save compatibility (§19) and is the header check for every trace (§11). It must be computed over the same normalized content in the same order as the alpha — a fingerprint that merely *exists* is useless; one that *matches* the alpha's for identical content proves the whole normalization path ported correctly.

---

# Part VI — Presentation and Development Tooling

## 14.1 The visual target for beta 0.1

**The Godot port is a visual redesign** (director ruling, 2026-08-20) — but the redesign does not happen in beta 0.1. This build produces a **whitebox**: the minimum that legibly represents every element the alpha has, built the cheapest correct way, to be refined from there.

This is the right call and the doc should be explicit about why it changes almost nothing: **the alpha has no art assets.** Not one image, font, or sprite. Every Packet is a `COLOR_HEX` fill with a 1px `DARK_HEX` border and a white shape glyph drawn as a canvas vector path; all text is system sans-serif. There is nothing to "reuse" and nothing to port — only geometry to transcribe.

So the economical path is neither "recreate the alpha's look" nor "design something new". It is:

**Use the alpha's values as defaults**, because copying twelve hex constants costs nothing and gives a legible starting board — but treat them as placeholders, not as a target to reproduce faithfully:

| | |
| --- | --- |
| Packet palette | `Red #e04343`, `Yellow #ddcf3d`, `Magenta #cf52cf`, `Green #43b953`, `Cyan #3fc4c4`, `Blue #4a72e8` |
| Border/glyph outline | `Red #79201f`, `Yellow #776e1a`, `Magenta #6f2570`, `Green #1f5f28`, `Cyan #1c6666`, `Blue #22397e` |
| Shape geometry | the six vector paths in `src/render/view.ts:122-170` |
| Board background | `#1b1b22` |

**The shape glyphs in particular are expected to be replaced** (director, 2026-08-20). Do not invest effort matching the alpha's rendering of them. If a Godot primitive reads more distinctly than a transcribed path, use the primitive — six visually unambiguous shapes at thumb size is the entire requirement.

## 14.2 The presentation registry

Because the shapes and colors *will* change while their gameplay meaning does not, the mapping from identity to appearance must be a single swappable indirection — not a decision scattered across the renderer.

**Frozen** (gameplay-load-bearing, never changes):

- `Color` and `Shape` are enums `0..5`. Six of each, exactly.
- **Enum ordering is load-bearing**, because weak sets derive as the enum-order complement of authored strong sets. Reordering silently changes every System's and Hacker's weaknesses.
- The CSV tokens (`RED`, `GRE`, `TRI`, `STR`, …) are content identity and are frozen with the datasets.

**Swappable** (presentation only):

Exactly one file — `scenes/battle/packet_style.gd` — maps enum to appearance:

```gdscript
const COLOR_FILL   : Array[Color]   = [...]  # indexed by Color enum
const COLOR_BORDER : Array[Color]   = [...]  # indexed by Color enum
const SHAPE_DRAW   : Array[Callable] = [...] # indexed by Shape enum
```

Nothing outside this file may hard-code a hex value or a shape path. Every renderer, every diagnostic, every icon in a Program row or character sheet resolves through it.

**This table is the alpha→final translation matrix.** When the art pass happens, replacing shape 3's `Callable` with a sprite is a one-line change and the mapping from "what the alpha called a Diamond" to "whatever it becomes" is readable in one place, in order. That is the requirement, and it costs nothing to satisfy now versus considerable effort to retrofit later.

A test asserts both arrays have exactly six entries and that no hex literal appears elsewhere under `scenes/`.

**Build with Godot primitives** wherever they are cheaper than transcribing:

- Packet shapes: `draw_circle()` and `draw_colored_polygon()` in a `Node2D._draw()`. All six shapes are a handful of points each; the alpha's star is already a loop and the cross is an explicit 12-point path.
- Every panel, button, list, and label: **Godot's default theme, unstyled.** Do not author a custom theme, do not import fonts, do not draw custom widgets. A default `Button` that works is worth more in this build than a styled one that has to be redone.
- Any alpha affordance with a cheaper Godot-native equivalent — scrolling lists, modals, collapsible panels — uses the native one without argument.

**The one constraint:** no layout, palette, or animation assumption may leak into `logic/`. The redesign that follows must be able to replace all of Part VI without touching a rule. §4's enforcement test is what protects this.

Do not polish. Do not spend time on transitions, easing curves, or spacing. Effort saved here is effort available for the differential harness, which is where this build's risk actually lives.

## 15. Scene structure

```
scenes/
  main.tscn            root, screen switching
  screens/
    title.tscn
    system_select.tscn
    host_select.tscn
    build.tscn
    battle.tscn
    result.tscn
  battle/
    datastream.tscn    the 8x8 grid
    packet.tscn        one Packet: color, shape, overlay, countdown
    program_row.tscn   one Program with its charge pool
    ice_bar.tscn
```

One `Packet` node per cell, 64 total, each drawing itself in `_draw()`. This is cheap and makes per-Packet animation (falls, swaps, shakes, detonation flashes, countdown ticks) straightforward with `create_tween()`. A `TileMapLayer` would be faster and considerably harder to animate; at 64 cells the performance argument does not apply.

`Control`-based layout throughout, with the Datastream in an `AspectRatioContainer` so it stays square on any phone. Everything else is plain `VBoxContainer`/`HBoxContainer` under the default theme.

## 16. Event playback

The renderer consumes the event list from §7 as an async playback loop:

```gdscript
for evt in events:
    await _play(evt)
```

Rules:

- logic resolution completes **before** any animation begins; the renderer never drives rules
- input is locked during playback and released on completion
- a skip/fast-forward path must exist from day one — it makes the game testable by a human at speed, and retrofitting it is painful
- playback must be interruptible by save/quit without corrupting state, since `GameState` is already final before playback starts

## 17. Touch input

Port the control scheme from the alpha README §"Controls" exactly:

- tap a Packet to select
- tap an adjacent Packet to attempt a swap
- tap a non-adjacent Packet to move the selection
- tap the selected Packet again to deselect
- press and drag toward an adjacent Packet as an alternative swap
- invalid swaps animate, revert, and do not consume the turn
- tap an armed Function again to cancel targeting without spending charge

Use `InputEventScreenTouch` and `InputEventScreenDrag`. Enable `Input.emulate_mouse_from_touch` for desktop editor testing, but treat the **device** as authoritative for feel — a match-3 lives or dies on touch response and the mouse will lie to you.

Drag threshold and tap-vs-drag disambiguation need tuning on hardware. Expect this to take longer than it should.

## 18. Portrait layout and safe areas

Project is configured 1080×2340 portrait, `canvas_items` stretch, `expand` aspect.

The verification device (Galaxy S25 Ultra) has a **display cutout at the top center and 42px rounded corners**, confirmed from its display metrics. Query `DisplayServer.get_display_safe_area()` and keep the ICE bars, Program rows, and any status text inside it. Do not hardcode insets — a cutout is per-device.

The alpha's narrow-viewport target was 390×844 CSS pixels. Layout must hold from that aspect ratio through 20:9.

## 18.1 Diagnostic tooling

Included in beta 0.1 on the director's delegation (2026-08-20), selected on one criterion: **does it save more development time than it costs to build?** Each item below is minutes of work and removes a recurring multi-minute tax from every device test.

| Tool | Why it earns its place |
| --- | --- |
| **Seed display and seed entry** | The highest-leverage item by a wide margin. Showing the active battle seed on screen turns "I saw something odd on the phone" into a seed that feeds §10 directly, reproducing the exact battle in the headless harness with a full event trace. Without it, device bugs are anecdotes. |
| **Restart battle with the same seed** | Replays an identical battle instantly. Visual bugs are almost never reproducible otherwise, because a fresh seed means a fresh board. |
| **Force win / force lose** | Reaching the Result screen otherwise costs a full battle played by hand on a touchscreen, every time. Both outcomes are needed and neither is interesting to reach manually. |
| **Grant full charge** | Fills every Program pool. Function activation, targeting mode, cancel-without-spend, composites, and fizzles are the densest cluster of rules in the game, and they are unreachable until charge accumulates. |
| **Event log overlay** | On-screen tail of the last ~20 emitted events. Diagnoses most playback and ordering problems without a cable, and cross-checks against §11 traces. |
| **Playback speed control** | The skip/fast-forward path is already required by §16; expose slow-motion on the same control. Animation-ordering bugs are invisible at speed and obvious at quarter rate. |

Deliberately **excluded**, as costing more than they return in this build:

- **Find Sync hint** — a player-facing feature in the alpha, not a diagnostic, and its README notes it overlaps status text on narrow viewports. Port it when the hint system is designed for touch, not now.
- **Arbitrary board-state injection / board editor** — expensive to build and made largely redundant by §10, which verifies rules far more thoroughly than hand-placed boards ever could.
- **Performance overlay** — Godot's built-in monitors already cover this.

All diagnostics sit behind `OS.is_debug_build()` and must be unreachable in a release build. They live in `app/debug/` and are subject to §4: a diagnostic may **read** `GameState` and call ordinary logic-layer entry points, never mutate state directly. A force-win that sets ICE to zero behind the rules' back will eventually produce a bug report about the rules.

---

# Part VII — Persistence

## 19. Save architecture

| | |
| --- | --- |
| Location | `user://save.json` — maps to app-private storage on Android |
| Format | JSON, matching the alpha's structure |
| Schema | **`1`**. Not 6. This is a new save format for a new engine. |
| Alpha saves | Not readable. No migration path. Do not attempt one. |

Port the alpha's save *discipline*, which is the valuable part: identity stored as stable IDs and never as copied definitions; immutable content resolved through the fingerprint; and rejection rather than silent defaulting for stale inventory, unknown IDs, mismatched enemy builds, or a fingerprint mismatch.

Beta 0.1 supports the `ACTIVE_BATTLE` and `PENDING_RESULT` phases only. `PENDING_BUILD`, `PENDING_PATH`, `SETUP_HACKER`, and `SETUP_DECK` are Run phases and arrive in 0.2.

Board state, armed countdown overlays with their stamped area patterns, Program and Deck charge, settings, metrics, fingerprint, and gameplay RNG state all persist. **The RNG state is not optional** — resume must continue the same sequence, which is what §9's `getState()` preserves.

---

# Part VIII — Logging and Metrics

## 20. Preserve the event-sourced model

Metrics derive from the same logic-layer event stream that drives rendering. There is no second instrumentation path and there must never be one.

Port: the disjoint damage-attribution buckets (Sync, Bomb, Attack, line-slice, Transform, Buffer, PASSIVE); instance-keyed PASSIVE attribution carrying source kind, source ID, and PASSIVE ID; charge-stream generation and routing records; withheld-activation counts; and the `BASIC` / `VERBOSE` / `COMPLETE` tiers with `VERBOSE` as default.

Totals must reconcile exactly after PASSIVE modifiers — the base event keeps its own mechanism attribution and a PASSIVE's increment is recorded separately.

**Android specifics:** logs go to `user://logs/`. The alpha's browser storage budget, pre-write trimming, and priority-ordered sacrifice were `localStorage`-quota defenses and can relax on a filesystem, but keep a bounded size — an unbounded log on a phone is a bug report waiting to happen. Retrieve with `adb pull`. `print()` output reaches `adb logcat -d godot:V '*:S'`.

Run-scoped and Boss-scoped metrics are out of scope but their event shapes should not be designed against.

---

# Part IX — Verification

## 21. Gate 1 — headless tests

```bash
godot --headless -s res://tools/run_tests.gd
```

Must exit 0. Covers: the RNG vector (§9), content loading and every validation rule (§13), fingerprint parity (§14), board/match/resolve unit behavior, charge routing including overflow and discard, PASSIVE stacking and scope, countdown arming and delivery, save round-trip, and the §4 layer-purity grep.

## 22. Gate 2 — differential trace

The §10 acceptance set: 200 default-settings seeds across every System×HOST pairing, plus the three settings variations at 50 seeds each. Byte-identical or the build does not ship.

## 23. Gate 3 — device

```bash
godot --headless --export-debug "Android" build/1c38r34kr.apk
adb install -r build/1c38r34kr.apk
adb shell am start -n com.acpirate.ic38r34kr/com.godot.game.GodotAppLauncher
adb logcat -d godot:V '*:S'
adb shell screencap -p /sdcard/s.png && adb pull /sdcard/s.png
```

Required on hardware, not in the editor:

1. a complete battle played to victory by touch
2. a complete battle played to defeat
3. every authored System fielded at least once
4. every authored HOST fielded at least once
5. an invalid swap animating and reverting without consuming the turn
6. a targeted Function armed, then cancelled without spending charge
7. a Bomb arming, ticking, and detonating
8. an EBUFF countdown overlay becoming a live Buff
9. a cascade resolving visibly
10. save and quit mid-battle, relaunch, resume to identical board state
11. layout correct under the display cutout and rounded corners
12. clean logcat — no errors, no warnings

Screenshots are self-serve via `adb screencap`; do not defer visual checks to the director.

**Manual test honesty:** report what was actually run. A check not performed is reported as not performed. Do not describe editor testing as device testing.

## 24. Completion standard

Beta 0.1 is complete when all three gates pass, `README.md` describes the build as shipped, the working tree is clean, and the build is pushed. Partial completion is reported as partial.

---

# Part X — Implementation Order

Sequenced so that each phase is verifiable before the next depends on it.

### Phase A — Foundation
`types.gd`, `constants.gd`, `rng.gd`. The RNG test vector passes. Nothing proceeds until it does.

### Phase B — Content
`csv.gd`, `load.gd`, `content.gd`, `areas.gd`, `effects.gd`, `passives.gd`. All ten datasets load; every validation rule fires on crafted bad input; the fingerprint matches the alpha's.

### Phase C — Battle core
`board.gd`, `match_finder.gd`, `resolve.gd`, `passive.gd`, `game.gd`. Events emitted per §7. Unit tests per rule.

### Phase D — Differential harness
`tools/trace.gd`, the alpha's trace entry point, the normalizer, the comparison runner. **Expect this phase to find real bugs in Phase C** — that is its purpose, and it is cheaper than finding them in Phase F. Iterate C and D until Gate 2 passes.

### Phase E — Presentation
Whitebox scenes per §14.1, event playback, touch input, screen flow, save/resume, and the §18.1 diagnostics. The first build that runs on the phone. Timeboxed by intent — this phase is deliberately cheap, and effort saved here belongs to Phase D.

### Phase F — Integration
Metrics and logging, the headless batch harness, the full gate, README, commit, push.

---

# Part XI — Director Decisions

## Resolved, 2026-08-20

1. **Execution model** — no Senior/Junior split. One agent, one mode, from this build onward. Folded into §0.4.

2. **Diagnostic tooling** — included, with the specific set delegated to the implementing agent's judgment on development-time-saved versus build cost. Selection and exclusions in §18.1.

3. **Visual approach** — the Godot port *is* a visual redesign, but beta 0.1 ships whatever minimal representation covers the alpha's elements, refined from there. Reusing alpha visuals or substituting Godot primitives are both acceptable; economize. Folded into §14.1, which notes the alpha has no art assets at all, so the choice is narrower and cheaper than it first appears.

    Follow-on ruling the same day: the **shape glyphs specifically are expected to be replaced**, so effort spent replicating the alpha's rendering is wasted. This is answered architecturally rather than as a note — §14.2 requires a single presentation registry mapping the frozen `Color`/`Shape` enums to appearance, which *is* the alpha→final translation matrix and makes the eventual swap a one-file change.

## Still open

4. **Is the alpha trace entry point acceptable?** (§10)

    The differential gate requires the alpha to emit a normalized event trace, which means one commit to the otherwise-frozen alpha repo. It adds a script under `scripts/`, touches no rules, no logic, and no data.

    This is the only sanctioned modification to the alpha, and it is worth the intrusion: it is the difference between verifying a 7,000-line rules translation by reading it and verifying it by running it. If the answer is no, §10 and §22 must be struck and the verification strategy falls back to hand-written per-rule tests — substantially weaker, and substantially more work.

    Does not block Phase A, but blocks Phase D.

---

## Appendix — Environment facts

Verified working as of 2026-08-20.

| | |
| --- | --- |
| Godot | 4.7.2 stable, standard (non-Mono). `godot` shim at `%USERPROFILE%\bin\godot.cmd` |
| JDK | OpenLogic OpenJDK 17.0.8, `JAVA_HOME` set |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk` — cmdline-tools 23, platform-tools 37.0.1, build-tools 36.1.0, platform 36 |
| Godot pins | compileSdk/targetSdk 36, minSdk 24, JDK 17 |
| NDK | **not installed.** Only needed for custom Gradle builds — Android plugins or GDExtension. `ndk;29.0.14206865`, ~4 GB, if that changes. |
| Keystore | `~/.android/debug.keystore`, wired into Godot's editor settings |
| Device | Galaxy S25 Ultra, Android 16 / API 36, Adreno 830, OpenGL ES 3.2, arm64-v8a only |
| Baseline APK | 54.9 MB debug, signed, arm64-v8a + armeabi-v7a |

Toolchain notes that cost time to discover:

- cmdline-tools 23 replaced `sdkmanager` with a new `android` CLI; `--licenses` is a no-op and package syntax is `build-tools;36.1.0`. Most Godot Android documentation predates this.
- The exported launcher activity is `GodotAppLauncher`. `GodotApp` is what ends up running but is not exported and cannot be started directly.
- `adb logcat` without a tag filter is unusable on Samsung; filter to `godot:V '*:S'`.

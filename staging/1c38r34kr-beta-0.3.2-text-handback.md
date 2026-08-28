# 1C38R34KR beta 0.3.2 — text framework handback

**Build:** `beta-0.3.2` — what the game says, and how it says it.
**Authorization:** `1c38r34kr-beta-0.3.2-text-framework-authorization.md`.
**Gate A proposal:** `1c38r34kr-beta-0.3.2-text-framework-proposal.md`.
**Gate B notes:** `1c38r34kr-beta-0.3.2-gate-b-notes.md`.
**Date:** 2026-08-28. **Status:** complete. Both device gates signed off.

---

## 1. Verdict

**Complete against §23**, all 34 items, both devices signed off on hardware.

Player-facing text is external, typography is declared rather than hand-rolled
per control, three real font faces ship in the binary, and the board and start
screen depend on no typeface at all.

Both gates were held: nothing was populated before Gate A, and no renderer
migration began before Gate B.

---

## 2. What shipped

| Sheet | Rows | What it owns |
| --- | --- | --- |
| `text_content.csv` | 165 | what the game says |
| `text_style.csv` | 14 | how text behaves inside a rectangle |
| `font_refs.csv` | 3 | which bundled file a role and weight resolve to |

**Three registries.** `Text` (logic layer, data only), `TextStyles` and `Fonts`
(presentation, because resolving a style touches `Font` and `PacketStyle`).
Screens ask for semantics and never for a row index or a filename.

**Three bundled faces**, IBM Plex Sans Regular + SemiBold and IBM Plex Mono
Regular, all SIL OFL 1.1 with `OFL.txt` beside them. Two roles, not three: the
title logo and countdown digits became art, so no display or numeric face was
needed.

**Two graphics carry-forwards**, both rasterised from the bundled fonts at build
time and shipped as PNGs — so nothing loads a typeface to draw them, while they
remain the game's own letterforms rather than a lookalike. After this **no
gameplay surface depends on a font**.

---

## 3. Verification

| Gate | Result |
| --- | --- |
| Headless logic tests | 3,340 passing, 24 suites |
| Text framework tests | 103 assertions — lookup, placeholders, fit policy, fallbacks, sheet integrity |
| Font coverage | 98-character corpus, all three faces, including the arrow flagged as the likely gap |
| Asset pack structural checks | including the ten countdown digits |
| **Battle report fidelity** | **44 lines byte-identical** before and after migration |
| Battle parity, fast tier | 150/150 — no gameplay code changed |
| Tablet | full Run, every screen, clean log |
| S25 | safe area, fit, no clipping, clean log |

**No DEEPSCAN.** §20.1 requires it only if shared gameplay code changes. None
did.

**The report fidelity check is the one worth naming.** The director's constraint
was that the report "appears the same before and after". That is mechanically
checkable, so it was checked mechanically: rendered from the old literals,
migrated, rendered again, diffed — zero difference across 44 lines. Both
snapshot tools were deleted afterwards rather than kept, since a third
implementation of the report is exactly what this build was reducing.

---

## 4. What the verification caught

**Seven defects, and not one was found by the test suite.** That is the finding,
not the count.

### 4.1 Four export failures (Phase D)

Correct on desktop, broken in the APK: Godot auto-imported the text CSVs as
`Translation` resources so the raw files stopped shipping; font existence was
checked with `FileAccess`; fonts were loaded with `load_dynamic_font`; and the
title logo reserved zero height because `EXPAND_FIT_WIDTH_PROPORTIONAL` derives
height from a width a VBox has not computed yet.

**The rule: in an exported build, ask the resource system, never the
filesystem.** The suite runs against the *project directory*, which is a
different artefact from what a player installs — importers, remaps and filters
are invisible to it by construction.

### 4.2 A parse error behind a green suite (Phase E)

Renaming `_heading` left four call sites behind. `main.gd` stopped compiling, the
suite reported **3,325 passing**, and the game booted to a blank grey screen.

The suite had never loaded a scene script, because the scene layer has no
automated coverage — a deliberate decision, and still the right one. But *"no
behavioural coverage"* had silently become *"not even checked for syntax"*, and
nobody decided that. A four-line test now walks `scenes/` and asserts each file
loads.

### 4.3 Two whitespace losses (AN-011)

Excel discards **leading** whitespace on CSV import. It flattened the battle
log's indented sub-messages, and later the Boss tag's `"  ·  BOSS"`. Both were
fixed the same way: the indent and the separator moved into the renderer, where
they belonged — spacing that positions a line against its parent is composition,
not something the game says.

**A round trip through a spreadsheet is a lossy channel, and which losses it
inflicts are not obvious in advance.** `tools/export_workbook.py --check` exists
so the loss is visible rather than silent.

---

## 5. Decisions

| ID | Decision |
| --- | --- |
| **D-041** | Display names move to the text sheet; `scripts/logic/` emits object IDs. Fixes a live ambiguity — `ATTACKER` names both a Hacker and a System Program, so name-keyed log records could not say which fired. |
| **D-042** | The four description columns are deleted, not migrated — they held stubs and nothing outside the loader read them. |
| **D-043** | Two placeholder syntaxes: positional inside `psv.csv` where a param contract validates it, named in `text_content.csv` where none exists. |
| **D-044** | Two font roles. `LETTER_SPACING` dropped from the style schema; `WEIGHT` added, and added to `font_refs.csv` too, so swapping a family stays a one-file edit. |
| **D-045** | The alpha CSV cross-check narrows to shared columns. **This is the plan working** — the oracle stops adjudicating the moment content moves, and content has now moved deliberately. |
| **D-046** | Battle-log indentation moves from content into code, because leading whitespace cannot survive the authoring pipeline. |

---

## 6. Carried forward

### 6.1 Two string sets outside the framework, deliberately

**The twelve battle messages in `scripts/logic/game.gd`.** They are compared
byte-for-byte against the alpha by the battle, Boss and Run differentials, and
the logic layer may not call the text framework. Migrating them would break
parity to fix an architectural nicety. **They belong to whichever build retires
the oracle** — the same threshold D-045 describes.

**The content-validation failure screen.** It reports the loader's errors, and
`text_content.csv` loads through that loader — so it may be reporting on exactly
the thing it would need. It is the reporter of last resort and must not depend on
what it reports. It earned that decision twice this build, as the only working
screen while text loading was broken, naming the rows to fix.

### 6.2 Display names exist in two places

`name` survives in the gameplay sheets because those twelve messages need it,
while every player-facing surface reads the text sheet. **A test asserts the two
agree**, so a rename in one file fails immediately rather than drifting. The
duplication is accepted and made noisy; it resolves when 6.1 does.

### 6.3 AN-012 — one row, one confirmation

`GAME_UI_PATH_BOSS_TAG` was corrected in `data/` directly. The director has fixed
their working workbook; the staged copy is the older Gate-B snapshot. Nothing is
at risk — `data/` carries the right value — but the two should be confirmed in
agreement at the next import.

**The general point matters more than the row.** §15 makes the workbook
authoritative once imported, and two edits crossed that boundary the wrong way
this build. A one-way authority needs a one-way habit: fix in the workbook,
export, never hand-edit `data/`. `export_workbook.py --check` should probably
join the verification gate rather than being run on request.

### 6.4 Other open items

- **AN-009** — font licences must reach a player before distribution. Deferred by
  decision while the director is the only user. The text framework now makes an
  attribution screen nearly free: a title, a body block, a Back button.
- **AN-010** — 557 KB of font for a 98-character corpus. Subsetting would recover
  most of half a megabyte, and `check_fonts.gd` is already the guard that makes
  it safe rather than silently lossy.
- **PASSIVE enum rendering** — a `PASSIVE_TEXT` row is only half-localisable: the
  sentence translates, but the colour word inside it is rendered from an enum by
  `Vocab.title_case` and stays English. Costs nothing until a second language
  exists; the fix then is a small `ENUM_TOKEN` category, not a redesign.

---

## 7. For the next authorization

**The presentation infrastructure is now complete.** Layout, graphics and text
each have a contract, a validator, and a failure mode that is visible rather than
silent. What follows is content, art direction, or gameplay — not plumbing.

Three things worth deciding early:

1. **The instrument gap is the recurring theme of this build and the last.**
   Seven defects here, none caught by 3,340 assertions; three in 0.3.1, none
   caught by the differential. Every one was found by installing the artefact or
   by a person comparing against a reference. Each time a cheap mechanical check
   turned out to exist — a scene-parse test, a resource-vs-filesystem rule, a
   workbook diff. **The pattern is not "test more" but "the boundaries between
   environments are where defects live, and each boundary needs its own cheap
   check."** Source tree → export is one. Workbook → CSV is another.
2. **The alpha's remaining authority is behaviour only** (D-045). It still
   adjudicates the rules engine through three differentials, and that is
   untouched. It no longer adjudicates content or presentation, and it will stop
   adjudicating behaviour the moment gameplay is authored beyond it.
3. **Content is still the thinnest part of the game** — one Boss, one Hacker, one
   Deck, two in-pool Systems, four UPGRADEs. That was the 0.3.0 handback's
   headline gap and it has not moved, because three builds since have been
   infrastructure. The infrastructure is now done.

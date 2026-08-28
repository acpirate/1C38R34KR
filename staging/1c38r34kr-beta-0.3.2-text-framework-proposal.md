# 1C38R34KR beta 0.3.2 — text framework proposal

**Gate A deliverable.** Authorization: `1c38r34kr-beta-0.3.2-text-framework-authorization.md` §13.
**Date:** 2026-08-28. **Status:** awaiting director approval.

Four forks were resolved with the director before this was written; they are
carried through and marked **[D]** where they shape a decision.

---

## 1. Inspection summary

### 1.1 What the game says today

**197 string-literal occurrences under `scenes/`, 156 distinct.** Classified:

| Class | Count | Disposition |
| --- | --- | --- |
| Player-facing UI copy | ~70 | migrate |
| Battle report lines | 25 | migrate **[D]** — see §1.4 |
| Debug-only (seed row, speed, `[debug] Skip`) | 6 | stay literal (§7.3) |
| Developer diagnostics (`graphics:`, `palette:` errors) | 11 | stay literal — never player-facing |
| Godot API strings (`"Button"`, `"position:y"`) | 12 | not text |
| Format fragments (`", "`, `" + "`, `"%s"`) | ~30 | not content; stay in code |

### 1.2 String-bearing gameplay columns

| Sheet | Column | Consumed by | Verdict |
| --- | --- | --- | --- |
| all ten | `name` | renderer, `battle_log`, metrics | **migrate [D]** |
| `psv` | `display` | HOST/UPGRADE cards via `_passive_summary` | migrate, keep positional templating **[D]** |
| `bos` | `BOSS_PASSIVE_DESCRIPTION` | **loader only** | delete |
| `bos`,`sys`,`hak` | `BIO` | **loader only** | delete |
| `dek` | `DESCRIPT` | **loader only** | delete |
| `hst`,`upg` | `display_text` | **loader only** | delete |
| all | `notes` | loader only, authoring aid | keep — not player-facing |

**The four description columns are stubs, not content.** Every filled cell reads
`"system biography goes here"` or similar, and `display_text` is **entirely
empty** — 0 of 5 HOST rows, 0 of 4 UPGRADE rows. Nothing outside the loader and
test fixtures reads any of them; what HOST and UPGRADE cards actually display is
`_passive_summary()`, which reads the PASSIVE `display` template.

So this is **deletion, not migration** — there is no live copy to preserve and
no before/after fidelity to protect. Two practical notes: all four are
fingerprint-excluded, so removing them **cannot invalidate a save**; and the
loader treats a missing column as a hard error, so removal must update
`vocab.gd`'s header contracts in the same commit.

### 1.3 Two facts that shape the schema

**IDs are globally unique.** 58 IDs across ten sheets, zero collisions. So
`REF_ID` alone identifies an object, and `SEMANTIC_CATEGORY + REF_ID` gives the
multiple-strings-per-object shape §4.1 wants without further qualification.

**Display names are NOT unique.** 47 names, two duplicated: `ATTACKER` is both
`PRG_H_003` and `PRG_S_003`; `DISABLER` is both `PRG_H_004` and `PRG_S_004` —
the Hacker and System carry mirrored rosters, visibly so in battle.

That second fact is a live argument for **[D]** #1 rather than a theoretical
one: `battle_log` currently writes `"ATTACKER fired BOMB"`, which **is ambiguous
today** about which side fired. Moving log records to IDs fixes an existing
defect.

### 1.4 The battle report — assessed as easy

The director's instruction was to migrate it only if it does not need
shoehorning. It does not.

`_metrics_lines` / `_append_side` are 22 flat `"Label: %d"` lines plus three
loop templates. No conditionals inside strings, no nesting, no rich text. The
side heading is already parameterised (`_append_side(..., "HACKER")`).

The three loop lines carry display names, which **[D]** #1 already requires
changing — so that work converges rather than adding.

One line needs care rather than shoehorning:
`"Opponent-bound Packets sliced: %d of %d (%.1f%%)"` mixes a float with a
literal `%`. The float is formatted in code and passed as an already-rendered
string placeholder; the template carries no format specifier. That is the rule
for every numeric in the sheet, not an exception for this line.

**Noted, not fixed:** the report's side heading says `SYSTEM` where the rest of
the game now names the opponent (P-042, §16, and the 0.3.1 string fixes). The
migration preserves it verbatim per "identical before and after", and the CSV
row is the obvious place to change it later — which is the jumping-off point the
director asked for.

---

## 2. `SEMANTIC_CATEGORY` vocabulary

Twelve categories. Content categories name **what kind of thing is being said**,
never where it appears.

### 2.1 Gameplay-object content — 8

| Category | Ref space |
| --- | --- |
| `PROGRAM_NAME` | `PRG_H_*`, `PRG_S_*` |
| `SYSTEM_NAME` | `SYS_*` |
| `BOSS_NAME` | `BOS_*` |
| `HACKER_NAME` | `HAK_*` |
| `DECK_NAME` | `DEK_*` |
| `HOST_NAME` | `HST_*` |
| `UPGRADE_NAME` | `UPG_*` |
| `FUNCTION_NAME` | `FNC_*` |

Separate categories rather than one `DISPLAY_NAME`, even though IDs are globally
unique and one category would work. Reason: the category is what makes a sheet
*sortable and reviewable by kind* — an author adding a System wants to see the
Systems together — and it costs nothing, since the ID prefix already implies it.

`PASSIVE_TEXT` (`PSV_*`) is a ninth, covering the templated PASSIVE display
string. See §7.

### 2.2 UI content — 4

| Category | What it covers |
| --- | --- |
| `UI_SCREEN_TITLE` | The heading line: `BUILD`, `SELECT BOSS`, `RUN COMPLETE` |
| `UI_SCREEN_PROMPT` | The grey line under it: `Choose who runs this breach` |
| `UI_BUTTON_TEXT` | Every button label |
| `UI_STATUS_TEXT` | In-flight copy: battle messages, result subheads, report lines |

Four, not more. The temptation is a category per screen; that would make
`SEMANTIC_CATEGORY` a location index, which §5.3 explicitly separates from
content identity.

---

## 3. `GAME_UI_*` naming

`GAME_UI_<SCREEN>_<THING>`, screen first so the sheet groups by screen when
sorted.

```
GAME_UI_TITLE_NEW_RUN            GAME_UI_BUILD_HEADING
GAME_UI_TITLE_QUICK_CONSTRUCTED  GAME_UI_BUILD_PROMPT
GAME_UI_TITLE_QUICK_RANDOM       GAME_UI_BUILD_BEGIN
GAME_UI_TITLE_CONTINUE_RUN       GAME_UI_PAUSE_HEADING
GAME_UI_BOSS_SELECT_HEADING      GAME_UI_PAUSE_RESUME
GAME_UI_BOSS_SELECT_PROMPT       GAME_UI_PAUSE_SAVE_QUIT
GAME_UI_RESULT_VICTORY           GAME_UI_REPORT_BATTLE_HEADING
GAME_UI_RESULT_DEFEAT            GAME_UI_REPORT_TURNS
```

One ID per string. §4.2's prohibition on a generic shared `GAME_UI` reference is
honoured: no ID is reused across unrelated rows even when the English text
coincides (`Back to title` appears on three screens and gets three IDs, because
three screens may later want three different words).

---

## 4. `text_content.csv` schema

**Unchanged from §4.1.** Inspection produced no reason to alter it.

```csv
SEMANTIC_CATEGORY,REF_ID,EN
PROGRAM_NAME,PRG_H_001,MUSCLE
UI_BUTTON_TEXT,GAME_UI_PAUSE_SAVE_QUIT,Save and Quit
UI_STATUS_TEXT,GAME_UI_REPORT_TURNS,Turns to resolution: {turns}
```

Row identity is `SEMANTIC_CATEGORY + REF_ID`. `EN` stays the language column so
`ES`/`DE`/`JA` extend horizontally with no schema change (§4.3).

**Estimated v0 size: ~150 rows** — 58 object names, ~70 UI strings, ~25 report
lines.

---

## 5. Text treatment inventory

Every distinct treatment in the shipped build:

| # | Where | Size | Colour | Fit today |
| --- | --- | --- | --- | --- |
| 1 | Screen heading | `font_heading` 22 | `TEXT_HEADING` | none |
| 2 | Screen prompt | `font_subheading` 15 | `TEXT_DIM` | wrap |
| 3 | Button label | `font_button` 19 | `TEXT` | wrap + clip |
| 4 | Chooser card | `font_button` 19 | `TEXT` | wrap + clip |
| 5 | Body / report | `font_body` 15 | `TEXT` | none |
| 6 | Context / footnote | `font_small` 13 | `TEXT_FAINT` | wrap |
| 7 | Battle message | `font_body` 15 | `TEXT_STATUS` | wrap, max 3 lines |
| 8 | Program name | `size.y*0.28` | `TEXT` | **shrink loop to 10** |
| 9 | Program charge | `size.y*0.22` | `CHARGE_TEXT_READY`/`TEXT_DIM` | none |
| 10 | Avatar title | `size.y*0.26` | `TEXT` | **shrink loop to 10** |
| 11 | Avatar stat | `bar_h*0.62` | `TEXT_HEADING` | **shrink loop to 10** |
| 12 | Buff/shield totals | `size.y*0.24` | `CHARGE_TEXT_READY` | none |
| 13 | Damage tag | `font_small` 13 | `DAMAGE` | none |

Treatments 8, 10 and 11 are hand-rolled `while` loops decrementing font size —
exactly the "uncontrolled shrink until it fits" §5.2 forbids, except that all
three do happen to floor at 10. The framework replaces them with a declared
`SHRINK` policy and an explicit `MIN_SIZE`.

---

## 6. `STYLE_ID` vocabulary and `text_style.csv`

Thirteen styles, one per treatment above. Names describe **role in a layout**,
not screen:

`SCREEN_HEADING`, `SCREEN_PROMPT`, `BUTTON_LABEL`, `CARD_BODY`, `BODY`,
`FOOTNOTE`, `BATTLE_MESSAGE`, `PROGRAM_NAME_BATTLE`, `PROGRAM_CHARGE`,
`AVATAR_TITLE`, `AVATAR_STAT`, `AVATAR_TOTALS`, `DAMAGE_TAG`.

### 6.1 Schema — one column removed, one added

| Column | Keep? |
| --- | --- |
| `STYLE_ID` | yes |
| `FONT_ROLE` | yes |
| `NOMINAL_SIZE` | yes — in **alpha CSS px**, passed through `UiTheme.px()` |
| `MIN_SIZE` | yes — required whenever `FIT_MODE` allows shrinking |
| `FIT_MODE` | yes |
| `MAX_LINES` | yes |
| `H_ALIGN` | yes |
| `COLOR_ROLE` | yes |
| ~~`LETTER_SPACING`~~ | **drop** |
| `WEIGHT` | **add** |

**Dropping `LETTER_SPACING`:** nothing in the shipped build sets tracking, and
Godot exposes it per-`Label` rather than per-font. Adding an unused column
invites someone to populate it before anything reads it. It can be added when a
style needs it — the schema extends horizontally like `EN` does.

**Adding `WEIGHT`:** headings and Program names render bold today. Without it
every bold treatment would need a distinct `FONT_ROLE`, which would make
`font_refs.csv` a weight table rather than a role table and defeat §6.3 — the
whole point being that swapping a font edits one file.

`NOMINAL_SIZE` is authored in **alpha CSS px** and scaled by `UiTheme.px()` at
load, matching every existing size in the project. Authoring device pixels would
silently re-fix the sizes to one viewport.

### 6.2 Fit modes — four

| Mode | Behaviour | Requires |
| --- | --- | --- |
| `FIXED` | render at `NOMINAL_SIZE`, overflow is a layout bug | — |
| `SHRINK` | step down to fit one line, never below `MIN_SIZE` | `MIN_SIZE` |
| `WRAP` | wrap at word boundaries up to `MAX_LINES` | `MAX_LINES` |
| `ELLIPSIS` | single line, truncate with `…` | — |

Validation refuses a `SHRINK` row without a `MIN_SIZE`, and refuses `MIN_SIZE >
NOMINAL_SIZE`. That is §5.2's "no uncontrolled shrink" made mechanical rather
than documented.

**`ELLIPSIS` is proposed but currently unused** — every clipping site today
either wraps or shrinks. It is included because `clip_text = true` is already
set on chooser cards, which is truncation without the affordance that tells a
player truncation happened. Flagged rather than applied: adding an ellipsis
changes what those cards look like, and this build is not an art pass.

### 6.3 Colour roles — six

Derived from actual usage, not invented: `PRIMARY` (`TEXT`), `SECONDARY`
(`TEXT_DIM`), `FAINT` (`TEXT_FAINT`), `HEADING` (`TEXT_HEADING`), `STATUS`
(`TEXT_STATUS`), `EMPHASIS` (`CHARGE_TEXT_READY`), `DAMAGE` (`DAMAGE`).

Seven, not the five §18 sketches — because that is what the game uses. They
resolve to `PacketStyle` constants, so this is a naming layer over the existing
registry and **not** a recolouring system.

---

## 7. Placeholders

**Named `{token}` for the text framework; PASSIVE `display` keeps positional
`%1`/`%2` [D].**

Two syntaxes, deliberately. PSV's positional tokens are validated at load
against each effect's declared param contract — `load.gd:462` knows how many
params an effect has and that a `COLOR` param renders title-cased. Named
placeholders cannot express that contract as cleanly, so rewriting it would
trade working validation for cosmetic consistency.

The split is legible: **positional appears only inside `psv.csv`, where a
contract validates it; named appears only in `text_content.csv`, where no
contract exists.**

In scope: substitution, validation that every required token is supplied,
visible failure for an unresolved one. Out of scope per §8: conditionals,
pluralization, nesting, rich text.

Unresolved token renders as `{token}` **and** logs an error — visible in place
rather than silently blank.

---

## 8. `FONT_ROLE` set and `font_refs.csv`

**Two roles.** Schema unchanged from §6.

| Role | Used by | Weights |
| --- | --- | --- |
| `UI_SANS` | all prose — headings, prompts, buttons, names, messages, result copy | Regular + Bold |
| `UI_MONO` | data readouts — charge counters, LINK/ICE, report values, seed row | Regular |

**Why two and not one:** the report and the charge counters are columns of
digits that should align and currently do not. Monospace gives tabular figures
by construction. It also suits a terminal-vernacular game, but the alignment
argument stands alone.

**Why not three:** the title logo and countdown digits both become *art* in this
build (§11, §12), so no display or numeric face is needed. A display face would
be art direction, which v0 explicitly is not.

**Recommended v0 files:** IBM Plex Sans (Regular, SemiBold) + IBM Plex Mono
(Regular) — both SIL OFL 1.1, one superfamily so the metrics are designed to sit
together, and both cover the full corpus below. Barlow, Inter, JetBrains Mono
and Space Mono are equally acceptable.

**Director supplies the binaries [D].** They are needed at Gate B, not now.

---

## 9. Glyph corpus

**Printable ASCII `U+0020`–`U+007E`, plus exactly three characters.**

| Char | Code | Where |
| --- | --- | --- |
| `·` | U+00B7 | context separators, seed row |
| `—` | U+2014 | HOST/UPGRADE card separators, report, targeting prompt |
| `→` | U+2192 | one battle message |

The content CSVs are **pure ASCII** — verified across all ten. 67 distinct
printable ASCII characters in use.

`→` is the risk: many text fonts omit arrows. It appears once. If a supplied
font lacks it, the substitution is a pack icon or a different mark rather than
rejecting the font.

**Coverage becomes mechanical (§10):** a validator opens each bundled font and
asserts every corpus character has a glyph, failing at Gate B rather than on a
device. `Ø` and `≡` were in this corpus until 0.3.1 turned them into art — which
is the pattern working.

---

## 10. Missing and invalid behaviour

Follows the graphics layer's shape, because it worked (§10 of the 0.3.1
authorization, and the MISSING checker).

| Failure | Behaviour |
| --- | --- |
| Missing content row | render `[MISSING: CATEGORY / REF_ID]`, log an error |
| Unknown `STYLE_ID` | log, fall back to `BODY`, stay readable |
| Unknown `FONT_ROLE` | log, fall back to `UI_SANS` |
| Missing font file | log, fall back to Godot's default so the game still renders |
| Unresolved placeholder | render `{token}` in place, log |
| Duplicate `(CATEGORY, REF_ID)` | **hard error at load** |
| `SHRINK` with no `MIN_SIZE` | **hard error at load** |

Startup reports all discoverable text errors **together**, like the content
loader and the graphics pack. Text does not block startup — a missing string is
cosmetic, and the marker makes it obvious.

---

## 11. Runtime architecture

Three registries under `scripts/logic/data/` for the loaders, and a presentation
façade — mirroring how content and graphics are already split.

```gdscript
TextContent.get(category, ref_id) -> String
TextContent.format(category, ref_id, {"turns": 7}) -> String
TextStyle.of(style_id) -> TextStyle.Entry
Fonts.of(font_role, weight) -> Font
```

`TextStyle.Entry` carries resolved size, min size, fit mode, max lines,
alignment, colour and font — and a single `apply_to(label)`, so a component
sets a style rather than seven properties.

**The CSVs load through the existing `ContentLoader` path**, not a second
pipeline (§15). They are ordinary data sheets, shipped by the same
`include_filter="*.csv"` and validated by the same issue reporter.

**Layer purity holds.** The text registries hold no scene references, so they
may live in the logic layer; but nothing in `scripts/logic/` *calls* them, which
is what keeps logs ID-only per **[D]** #1.

---

## 12. Title logo (§12)

- `title_logo` semantic entry in `GraphicsPack`, generated by `gen_assets.gd`
  like every other v0 asset.
- Rendered as a `TextureRect` above the start-screen buttons, replacing the
  `1C38R34KR` Label.
- Sized as a **fraction of panel width** with a `max_width`, not a fixed pixel
  size, so it scales across both targets without pinning a resolution.
- Transparent PNG, so it composes over whatever background arrives later — §12
  forbids baking either future art direction into the layout.

---

## 13. Countdown digits (§11)

- Ten entries `countdown_digit[0..9]`, an `Array[Texture2D]` keyed by digit,
  exactly like `packet_glyph` and `overlay_mark`.
- Generated as one coordinated set in `gen_assets.gd` for stylistic consistency
  (§11.1), sliced into ten addressable assets (§11.2).
- The renderer composes **left to right from the digits of the value**, so a
  two-digit countdown already works; current content never exceeds 9 (§11.3).
- Drawn in the badge's mark colour, exactly as the type marks are, so ownership
  polarity is unchanged.
- `_draw_countdown`'s `draw_string` path is deleted, not left as a fallback —
  §9.4's rule from the graphics build.

**This retires the last font dependency on the board.** After it, no gameplay
surface depends on a typeface.

---

## 14. Implementation sequence

| Phase | Work |
| --- | --- |
| **B** | populate three CSVs; director supplies fonts; generate title logo + digits; contact sheet; migration map. **Gate B.** |
| **C** | `TextContent`, `TextStyle`, `Fonts`, validation, formatting. No migration. Suite green first. |
| **D** | title logo to pack and start screen; countdown digits to pack; delete the `draw_string` countdown path. |
| **E** | migrate literals and names to semantic lookups; apply styles. |
| **F** | delete the four description columns and `name` after proving no consumers; update `vocab.gd` headers; switch `battle_log` to IDs. |
| **G** | suite, fast parity, coverage checks, tablet, S25. |
| **H** | closeout. |

**Capture the rendered battle report before Phase E and diff it after** — the
director's "identical before and after" is mechanically checkable and worth
checking mechanically.

---

## 15. Decisions this proposal records

| ID | Decision |
| --- | --- |
| **D-041** | Display names move to `text_content.csv`; `scripts/logic/` emits object IDs. Fixes an existing ambiguity — `ATTACKER` names two Programs. |
| **D-042** | The four description columns are deleted, not migrated: they hold stubs, and nothing outside the loader reads them. |
| **D-043** | Two placeholder syntaxes, deliberately: positional inside `psv.csv` where a param contract validates it, named in `text_content.csv` where none exists. |
| **D-044** | Two font roles. `LETTER_SPACING` dropped from the style schema; `WEIGHT` added. |

---

**Gate A. Awaiting approval before populating the v0 CSVs.**

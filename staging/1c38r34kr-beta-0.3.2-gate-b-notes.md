# Beta 0.3.2 Gate B — v0 text data, fonts, and carry-forward assets

**Gate B deliverable.** Authorization §14.
**Date:** 2026-08-28. **Status:** awaiting director approval.
**Nothing has been migrated yet** — no scene reads these CSVs, and the runtime
registries do not exist. This is data and assets only.

Contact sheet: **https://claude.ai/code/artifact/22229bfa-b32f-4334-afac-a736480a15f1**

---

## 1. What exists

| Item | Where |
| --- | --- |
| `text_content.csv` | `data/` — 165 rows |
| `text_style.csv` | `data/` — 14 styles |
| `font_refs.csv` | `data/` — 3 rows |
| Bundled fonts + `OFL.txt` | `assets/fonts/` |
| Title logo | `assets/packs/v0/chrome/title_logo.png` |
| Countdown digits 0–9 | `assets/packs/v0/overlay/digit_*.png` |
| Inspection sheets | `staging/gate-b/sheet_title_logo.png`, `sheet_countdown_digits.png` |
| Seeding tool | `tools/seed_text_csv.py` |
| Coverage check | `tools/check_fonts.gd` |

---

## 2. `text_content.csv` — 165 rows

| Category | Rows |
| --- | --- |
| `PROGRAM_NAME` | 14 |
| `FUNCTION_NAME` | 20 |
| `HOST_NAME` | 5 |
| `UPGRADE_NAME` | 4 |
| `SYSTEM_NAME` | 3 |
| `BOSS_NAME` / `HACKER_NAME` / `DECK_NAME` | 1 each |
| `PASSIVE_TEXT` | 7 |
| `UI_STATUS_TEXT` | 64 |
| `UI_BUTTON_TEXT` | 20 |
| `UI_SCREEN_PROMPT` | 13 |
| `UI_SCREEN_TITLE` | 12 |

**56 gameplay-object rows, 109 UI rows.** No duplicate `(CATEGORY, REF_ID)` — the
seeder refuses to write if it finds one.

**Object names are read from the gameplay sheets**, not retyped, so the seed
cannot disagree with them. UI copy is transcribed verbatim from the shipped
literals: this build migrates text, it does not rewrite it.

### 2.1 One string deliberately NOT transcribed

`_show_pending_boss_battle`'s subheading reads **"Boss battle port continues in
Beta 0.3"** — true when written, false since 0.3 shipped the Boss battle, and
still reachable from a beta 0.2 save. It is seeded as *"The Boss route is set.
Continue when you are ready."*

Migrating a sentence that is now false would be preserving a defect for the sake
of fidelity. This is the **sixth** instance of the P-043 pattern and the reason
the framework is being built.

### 2.2 Placeholders

**46 distinct tokens** across the rows, all named. Most-used: `amount` (12),
`current` and `total` (6 each), `opponent` (5).

Named tokens describe the *value*, not its position, which is the whole point: a
positional swap is silent, a renamed token fails validation.

**PASSIVE_TEXT keeps positional `%0`/`%1`** per D-043 — those are validated at
load against each effect's declared param contract, and named placeholders
cannot express that contract as cleanly. The split is legible: positional only
inside `psv.csv`, named only in `text_content.csv`.

---

## 3. `text_style.csv` — 14 styles

One per distinct treatment in the shipped build, plus `REPORT_LINE`.

**Sizes are in alpha CSS pixels**, scaled through `UiTheme.px()` at load — the
unit every existing size in this project uses. Device pixels would silently pin
the game to one viewport.

Three styles use `SHRINK`, and each carries a `MIN_SIZE` below its nominal:
`PROGRAM_NAME_BATTLE` (11→8), `AVATAR_TITLE` (12→8), `AVATAR_STAT` (12→8). These
replace the three hand-rolled `while` loops in the shipped components — which
did floor at 10, but did so by accident of implementation rather than by
declaration.

**`REPORT_LINE` is new**, not a migration of an existing treatment: the battle
report currently renders in the body style. It is `UI_MONO` so the report's
columns of digits finally align.

### 3.1 Schema deviations from §5

| Change | Why |
| --- | --- |
| **dropped `LETTER_SPACING`** | nothing in the build sets tracking, and an unused column invites someone to populate it before anything reads it |
| **added `WEIGHT`** | headings and the damage tag are bold; without it every bold treatment would need its own `FONT_ROLE`, turning `font_refs.csv` into a weight table and defeating §6.3 |

---

## 4. `font_refs.csv` — schema deviation

§6's proposed schema is `FONT_ROLE, FONT_FILE`. **A `WEIGHT` column was added**,
because a role legitimately has more than one file:

```csv
FONT_ROLE,WEIGHT,FONT_FILE
UI_SANS,REGULAR,assets/fonts/IBMPlexSans-Regular.ttf
UI_SANS,BOLD,assets/fonts/IBMPlexSans-SemiBold.ttf
UI_MONO,REGULAR,assets/fonts/IBMPlexMono-Regular.ttf
```

Without it, "UI sans, bold" would have to be a second role, and swapping the
sans family would mean editing two role rows and every style that referenced the
bold one. Keying on `(FONT_ROLE, WEIGHT)` keeps §6.3's promise intact: change a
family, edit one file.

---

## 5. Fonts

**IBM Plex Sans** (Regular, SemiBold) and **IBM Plex Mono** (Regular) — three of
the 61 files in the supplied archives. Shipping the rest would add megabytes for
faces the game cannot reach.

`OFL.txt` sits with them as instructed. Both families ship the **byte-identical**
licence (IBM Corp, Reserved Font Name "Plex"), so one copy genuinely covers both.

**Coverage verified mechanically.** `tools/check_fonts.gd` derives the corpus
from the content CSVs and scene string literals rather than a hardcoded list,
then asserts every character resolves to a glyph in every bundled face:

```
corpus: 98 distinct characters
  ok  IBMPlexMono-Regular.ttf     IBM Plex Mono
  ok  IBMPlexSans-Regular.ttf     IBM Plex Sans
  ok  IBMPlexSans-SemiBold.ttf    IBM Plex Sans SemiBold
```

`→` — the character I flagged as most likely to be missing — is present in all
three.

Two architect notes filed: **AN-009** (the licence must reach a player before
distribution; deferred by decision while the director is the only user) and
**AN-010** (557 KB of font for a 98-character corpus; subsetting would recover
most of half a megabyte, and `check_fonts` is already the guard that makes it
safe).

---

## 6. Title logo and countdown digits

Both are **rasterised from the bundled fonts at build time** by
`tools/gen_assets.gd`, then shipped as PNGs. That matters twice over:

- **At runtime nothing loads a font to draw them** (§11.2, §12) — the board and
  the start screen depend on no typeface.
- **They are the game's own letterforms**, not a lookalike. §11.1 asks for a
  coordinated set; rasterising from the same families the UI uses is a stronger
  form of coordination than drawing ten digits by hand and hoping.

| Asset | Source | Size |
| --- | --- | --- |
| `title_logo` | IBM Plex Sans SemiBold, 180 px, +14 tracking | 1114×130 |
| `digit_0..9` | IBM Plex Mono Regular, 96 px, centred on a square | 96×96 each |

Both authored **white with alpha**, so the renderer tints them — the digits take
the badge's mark colour, exactly as the four type marks do, and ownership
polarity keeps working unchanged.

`sheet_countdown_digits.png` shows all ten in both polarities at real badge size;
`sheet_title_logo.png` shows the wordmark on the panel ground it will sit on
(white-on-white is invisible on a white page, which is why the sheet exists).

**One defect caught and fixed here.** The first extraction read coverage as
`max(alpha, luminance)`. The atlas is LA8 with luminance pinned at 1.0 across
each glyph's whole bounding box, so every letter came out a solid white
rectangle. Coverage is in alpha alone.

---

## 7. Migration map

### 7.1 Gameplay columns → text rows

| Source | Rows | Becomes | Then |
| --- | --- | --- | --- |
| `prg_h.name`, `prg_s.name` | 14 | `PROGRAM_NAME` | column removed in Phase F |
| `fnc.name` | 20 | `FUNCTION_NAME` | removed |
| `hst.name` | 5 | `HOST_NAME` | removed |
| `upg.name` | 4 | `UPGRADE_NAME` | removed |
| `sys.name` | 3 | `SYSTEM_NAME` | removed |
| `bos.name`, `hak.name`, `dek.name` | 3 | `*_NAME` | removed |
| `psv.display` | 7 | `PASSIVE_TEXT` | removed |

### 7.2 Columns deleted outright, not migrated

| Column | Content today |
| --- | --- |
| `bos.BIO`, `sys.BIO`, `hak.BIO` | `"system biography goes here"` ×4 |
| `bos.BOSS_PASSIVE_DESCRIPTION` | `"boss passive description goes here"` |
| `dek.DESCRIPT` | `"deck description goes here"` |
| `hst.display_text`, `upg.display_text` | **empty — 0/5 and 0/4 rows** |

Nothing outside the loader and test fixtures reads any of them. All are
fingerprint-excluded, so **removing them cannot invalidate a save**. The loader
treats a missing column as a hard error, so `vocab.gd`'s header contracts move
in the same commit.

### 7.3 Scene literals → text rows

109 UI rows replace literals in `main.gd` and `battle_screen.gd`.

**Staying literal, deliberately:**

| What | Why |
| --- | --- |
| Debug bar, seed field, `[debug] Skip battle` | §7.3 — debug-only |
| `graphics:` / `palette:` loader errors | developer-facing, never on screen |
| **The content-validation failure screen** | see below |
| Godot API strings, format fragments | not content |

**The validation screen is the interesting one.** It renders when content
loading *failed* — and `text_content.csv` loads through that same loader, so it
may be exactly what failed. Its strings must stay literal: it is the reporter of
last resort and cannot depend on the thing it reports on.

---

## 8. On approval

Phase C builds the runtime registries with **no migration**, suite green before
anything is wired. Then D (carry-forward assets), E (migration), F (column
removal), G (devices), H (closeout).

**One commitment worth restating:** the battle report must render *identically*
before and after. I will capture it pre-migration and diff it post — the
director's "appears the same" is mechanically checkable and will be checked
mechanically.

Rejecting anything here costs a `seed_text_csv.py` edit and a re-run — except
the CSVs themselves, which become **workbook-authored** once imported (§15).
After that the seeder must not run again; it refuses to overwrite without
`--force` for exactly that reason.

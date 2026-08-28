# 1C38R34KR Beta 0.3.2 — Text Framework
## Build Authorization

**Build identity:** `beta-0.3.2`  
**Purpose:** replace the current ad-hoc POC text handling with a production-oriented text-content and typography framework, migrate existing player-facing strings into external data, bundle explicit font resources, and formalize text-fitting behavior before further display-design work.  
**Engine:** Godot 4.7.2, standard/non-Mono  
**Language:** GDScript  
**Primary platform target:** Android portrait, with tablet portrait validation  
**Status:** authorized for the full iteration, subject to two mandatory human approval gates

---

## 0. Why this build exists

Beta 0.3.1 established the first production-oriented graphics asset layer. The next presentation dependency is text.

The current text treatment is still substantially inherited from the POC:

- player-facing strings are distributed across gameplay datasheets and scene code;
- several gameplay rows carry display/description fields that were created ad hoc during iteration;
- typography is not yet defined through an explicit production framework;
- the game still depends on Godot fallback text behavior in places;
- fit behavior is inconsistent and partly local to individual controls/components;
- string literals have already gone stale as the game gained new modes and content;
- countdown numerals on Packet overlays still use font rendering even though they function more like board art than prose.

This matters before further display design because typography constrains geometry. Font metrics, nominal size, minimum readable size, wrapping, truncation, and line count determine how much content a panel can support.

The objective of Beta 0.3.2 is therefore not merely "pick a font."

It is to establish a production-shaped contract for:

1. **what the game says;**
2. **which bundled font resource a semantic role uses;**
3. **how a semantic text style behaves inside a layout-provided rectangle;**
4. **how player-facing strings are retrieved rather than hardcoded;**
5. **how future localization can extend the data model without restructuring it.**

This is infrastructure work. It is not the final typography/art-direction pass.

---

## 1. Authority and source precedence

Use sources in this order:

1. **This document** for Beta 0.3.2 scope, gates, data ownership, and migration rules.
2. The shipped Beta 0.3.1 repository and its current renderer/UI implementation.
3. Beta 0.3.1 graphics handback, decisions, architect notes, and lessons learned.
4. Current gameplay/content CSVs and the current game workbook/export workflow.
5. Current game screenshots and the actual running build as the functional display reference.

If old prose disagrees with what the current game actually displays or consumes, the **shipped Beta 0.3.1 implementation wins**. Record the discrepancy.

Do not preserve POC-era text fields merely because they exist. Preserve them only if inspection shows they still have a mechanically meaningful role.

---

## 2. Build objective

Beta 0.3.2 should deliver a complete text framework for the current game:

1. inspect the actual text usage in the live build;
2. refine the proposed data contracts;
3. stop for approval;
4. generate populated v0 text datasheets and bundled v0 font resources;
5. stop for director inspection/workbook import;
6. implement the text-content and style runtime;
7. migrate current player-facing strings to the new system;
8. remove obsolete player-facing text columns/literals after proving they are no longer consumed;
9. add the two graphics-layer carry-forward items:
   - title-logo asset;
   - countdown digit sprite assets;
10. verify the result on the current tablet and phone targets.

---

## 3. Mandatory human gates

This iteration has **two explicit stop points**.

### Gate A — refined text-contract proposal

The coding agent must inspect the current implementation and return a written proposal that refines:

- `text_content.csv`
- `text_style.csv`
- `font_refs.csv`
- semantic categories;
- font roles;
- style roles;
- string migration map;
- dynamic-placeholder policy;
- missing/fallback behavior;
- renderer integration plan;
- title-logo and countdown-digit carry-forward integration.

Then **stop and wait for director approval**.

Do not populate the final v0 CSVs or begin broad renderer migration before Gate A approval.

### Gate B — populated v0 data and font/assets inspection

After Gate A approval, the coding agent must:

1. generate complete v0 versions of:
   - `text_content.csv`
   - `text_style.csv`
   - `font_refs.csv`
2. bundle the selected local v0 font files;
3. generate the v0 title-logo PNG;
4. generate the coordinated countdown digit art set;
5. provide inventories/contact sheets or equivalent inspection artifacts;
6. provide the migration map showing which old fields/literals will be retired;
7. **stop and wait for director approval.**

At this gate the director may import the three CSVs into the master workbook.

No broad production renderer/data-consumer migration begins before Gate B approval.

### After Gate B approval

The agent may:

- implement the runtime text registries/loaders;
- wire scenes/components to semantic content/style references;
- remove obsolete string-bearing gameplay fields after proving they are unused;
- replace font-rendered countdown numerals with graphics assets;
- add the title-logo asset to the start screen;
- perform validation and device sign-off.

---

## 4. Core data model

The initial theoretical structure is deliberately simple. The coding agent must refine it against the real code during Gate A rather than blindly implement it.

### 4.1 `text_content.csv`

Purpose: **what the game says.**

Initial schema:

| Column | Meaning |
| --- | --- |
| `SEMANTIC_CATEGORY` | What kind of player-facing string this is |
| `REF_ID` | Gameplay/content identity or stable UI-only identity |
| `EN` | English text |

The director prefers this column order even if the sheet is usually sorted by `REF_ID`.

The effective row identity is:

`SEMANTIC_CATEGORY + REF_ID`

This allows one gameplay object to own multiple player-facing strings.

Example:

```csv
SEMANTIC_CATEGORY,REF_ID,EN
PROGRAM_DISPLAY_NAME,PRG_H_001,MUSCLE
PROGRAM_DESCRIPTION,PRG_H_001,Example description
UI_BUTTON_TEXT,GAME_UI_SAVE_QUIT,Save & Quit
UI_BUTTON_TEXT,GAME_UI_CONTINUE,Continue
UI_INSTRUCTION,GAME_UI_BUILD_SELECT,Select Programs for each slot
UI_STATUS_TEXT,GAME_UI_RUN_COMPLETE,Run Complete
```

### 4.2 UI-only reference IDs

Strings without a gameplay-object ID should use stable `GAME_UI_*` IDs.

Examples:

- `GAME_UI_SAVE_QUIT`
- `GAME_UI_CONTINUE`
- `GAME_UI_PAUSE`
- `GAME_UI_BUILD_SELECT`
- `GAME_UI_RUN_COMPLETE`

Do not use one generic `GAME_UI` reference for many unrelated rows.

The exact naming vocabulary should be proposed during Gate A based on the actual current string inventory.

### 4.3 Localization-ready shape

Do **not** implement localization behavior in this build.

However, `EN` is intentionally the language column name rather than a generic `STRING`.

Future localization should extend horizontally:

```text
SEMANTIC_CATEGORY | REF_ID | EN | ES | DE | JA | ...
```

The framework should not require a schema redesign when additional language columns are introduced later.

---

## 5. `text_style.csv`

Purpose: **how semantic classes of text behave inside the rectangle supplied by layout.**

This file must remain intentionally small. It is not a CSS replacement.

The coding agent should inspect current display treatments and refine the exact schema.

The initial proposed columns are:

| Column | Meaning |
| --- | --- |
| `STYLE_ID` | Stable semantic style identifier |
| `FONT_ROLE` | Reference into `font_refs.csv` |
| `NOMINAL_SIZE` | Preferred text size |
| `MIN_SIZE` | Smallest allowed size when shrinking |
| `FIT_MODE` | Defined fitting behavior |
| `MAX_LINES` | Maximum line count where relevant |
| `H_ALIGN` | Horizontal alignment |
| `COLOR_ROLE` | Semantic text-color role |
| `LETTER_SPACING` | Optional tracking/spacing control |

The agent may recommend adding/removing a small number of fields if the current implementation proves they are genuinely needed.

### 5.1 Explicit non-goal: no layout stylesheet

Do not put these in `text_style.csv`:

- x/y positions;
- widths/heights;
- anchors;
- margins;
- padding;
- container ratios;
- screen coordinates;
- arbitrary per-component geometry.

Those remain the responsibility of Godot layout/components.

The governing rule is:

> **Layout supplies the available rectangle. Text style determines how text behaves inside it.**

### 5.2 Fit modes

The exact enum names may be refined, but the framework should cover the current needs with a small explicit vocabulary such as:

- `FIXED`
- `SHRINK`
- `WRAP`
- `ELLIPSIS`

Do not create uncontrolled "shrink until it fits" behavior.

Any style that permits shrinking must have a hard `MIN_SIZE`.

### 5.3 Semantic style versus semantic content

Do not force `SEMANTIC_CATEGORY` to map one-to-one to `STYLE_ID`.

These are separate concepts.

Example:

- content category: `PROGRAM_DISPLAY_NAME`
- display style in battle: `PROGRAM_NAME_BATTLE`
- display style in a chooser card: `PROGRAM_NAME_CARD`

The component chooses the style appropriate to its context while retrieving the same content string.

---

## 6. `font_refs.csv`

Purpose: **map semantic font roles to bundled local font resources.**

Initial schema:

| Column | Meaning |
| --- | --- |
| `FONT_ROLE` | Stable semantic role |
| `FONT_FILE` | Local bundled font-resource path |

Example shape:

```csv
FONT_ROLE,FONT_FILE
UI_FONT,assets/fonts/example.ttf
DISPLAY_FONT,assets/fonts/example-display.ttf
NUMERIC_FONT,assets/fonts/example-numeric.ttf
```

This example is illustrative only.

### 6.1 Agent decides justified font-role count

Do not prescribe a target number of fonts merely to fill the table.

The agent should inspect the current game and propose the smallest justified set of font roles.

Likely scale is only a few rows.

If the current game genuinely needs two roles, use two.

If it needs four, use four.

### 6.2 Bundled local resources only

Player-facing production text must not depend on a device/system fallback font.

The v0 font resources should:

- be stored locally in the project;
- be distributable with the game;
- be imported by Godot;
- be compiled/packaged into the binary/export;
- have licensing compatible with distribution.

The v0 font choice is not final art direction.

The purpose is to prove the complete bundled-font resource path and allow reliable metric/fitting behavior.

### 6.3 Font replacement

`text_style.csv` references `FONT_ROLE`, not filenames.

Changing a font later should normally mean updating `font_refs.csv` rather than editing every style row.

---

## 7. Player-facing string authority

After migration, `text_content.csv` becomes the authoritative source for player-facing strings.

### 7.1 Gameplay datasheets

Mechanically meaningful gameplay fields remain in their existing sheets.

Presentation-only fields such as display names/descriptions created during POC iteration should move into `text_content.csv` and then be removed from gameplay sheets once all consumers have migrated.

### 7.2 Migration order

For every candidate legacy text field:

1. inventory where it is consumed;
2. classify whether it is mechanically meaningful or presentation-only;
3. migrate presentation-only content into `text_content.csv`;
4. update all consumers;
5. prove no remaining runtime/validation/logging dependency exists;
6. remove the obsolete gameplay column.

Do not delete a field merely because its name looks descriptive.

### 7.3 Scene literals

Player-facing literals in scene/UI code should be migrated where practical.

Examples include:

- button labels;
- instructions;
- status messages;
- mode labels;
- Run/Battle progress wording;
- title/subtitle copy;
- result-screen copy.

Debug-only diagnostics may remain local literals when they are not player-facing production UI.

---

## 8. Dynamic string parameters

The text-content framework may support **simple named placeholders** for strings whose values change at runtime.

Examples:

- `Battle {current} of {total}`
- `vs {opponent}`
- `{current}/{maximum}`

Keep this deliberately small.

In scope:

- named placeholder substitution;
- validation that required placeholders are provided;
- visible/logged failure for unresolved placeholders.

Out of scope:

- scripting;
- conditional expressions;
- pluralization engine;
- nested templates;
- rich-text templating;
- grammar rules;
- localization-specific inflection.

The goal is to prevent dynamic UI copy from forcing fresh literals back into scene code.

---

## 9. Missing/invalid text behavior

Missing text content should fail **visibly and gracefully**.

Recommended pattern:

```text
[MISSING: UI_BUTTON_TEXT / GAME_UI_SAVE_QUIT]
```

and log an explicit error.

Do not:

- crash the game for one missing string;
- silently substitute an unrelated string;
- silently pull copy from an obsolete gameplay field.

Missing or invalid style references should:

- log the missing semantic style;
- use one clearly defined safe fallback style;
- remain readable.

Missing font-role references should:

- log the missing font role;
- fall back to the designated bundled safe UI font if possible;
- not rely on arbitrary platform fallback behavior as the normal production path.

Startup validation should report all discoverable text-data/font/style errors together where practical.

---

## 10. Character/glyph coverage inventory

Gate A must inventory the characters currently required by:

- all player-facing literals;
- all authored display names/descriptions to be migrated;
- dynamic-template punctuation;
- current numeric displays;
- relevant symbols still rendered as font text.

The selected v0 bundled fonts must cover the current required corpus.

Do not assume a font supports every currently used symbol merely because common Latin text renders.

The coverage check should become mechanical where practical.

---

## 11. Countdown numerals — graphics carry-forward

Countdown numerals on board overlays are **not** part of the typography framework after this build.

They should become graphics assets.

### 11.1 Authoring workflow

For efficiency and stylistic consistency, the digits may be generated together in one coordinated image/sheet/atlas during asset creation.

The generation workflow does not need to create ten separate prompts.

### 11.2 Runtime contract

The production graphics contract should expose countdown digits as individually addressable semantic assets, equivalent to:

- `countdown_digit_0`
- `countdown_digit_1`
- ...
- `countdown_digit_9`

or an indexed array keyed by digit whose semantic meaning is equally clear.

The renderer should not depend on a font for countdown overlays after migration.

### 11.3 Multi-digit support

Current content may only need small countdown values, but do not architect the renderer so that multi-digit countdowns are impossible.

The display path should be able to compose multiple digit assets if future content requires values above 9.

No gameplay behavior changes.

### 11.4 Asset format

Countdown digits are lossless PNG graphics and belong to the existing production graphics pack/catalog.

They are not entries in `font_refs.csv`.

---

## 12. Title-logo asset — graphics carry-forward

The current textual game title on the start screen should be replaced by a graphics-pack asset.

Requirements:

- generate a v0 lossless PNG title-logo asset;
- add a semantic catalog entry such as `title_logo`;
- render it above the start-screen interface buttons;
- preserve the current portrait phone/tablet layout;
- scale it cleanly without hardcoding one device resolution.

This pass does **not** decide whether the title will ultimately:

- remain a standalone transparent asset; or
- be integrated into a larger title-screen underlay/background.

Do not bake either future art-direction choice into layout architecture.

---

## 13. Gate A required proposal

Produce:

`1c38r34kr-beta-0.3.2-text-framework-proposal.md`

It must include at minimum:

1. full inventory of current player-facing strings;
2. inventory of string-bearing gameplay columns;
3. proposed `SEMANTIC_CATEGORY` vocabulary;
4. proposed `GAME_UI_*` naming scheme;
5. refined `text_content.csv` schema;
6. inventory of distinct current text treatments;
7. proposed `STYLE_ID` vocabulary;
8. refined `text_style.csv` schema;
9. current fit/wrap/shrink behavior inventory;
10. proposed explicit fit policies;
11. proposed `FONT_ROLE` set;
12. refined `font_refs.csv` schema;
13. recommended bundled v0 font resources and licensing/source notes;
14. current required glyph/character corpus;
15. dynamic-placeholder rules;
16. missing/fallback behavior;
17. migration map from existing fields/literals to new rows;
18. title-logo integration plan;
19. countdown-digit asset-generation and runtime plan;
20. implementation sequence.

Then stop at **Gate A**.

---

## 14. Gate B required deliverables

After Gate A approval, generate and populate:

- `text_content.csv`
- `text_style.csv`
- `font_refs.csv`

Also provide:

- bundled v0 font files;
- character-coverage validation result;
- v0 title-logo PNG;
- v0 countdown digit graphics set;
- graphics-pack/catalog additions required by those assets;
- a contact sheet or inspection sheet for the title and digit assets;
- a concise migration report showing old source → new text-content row;
- a list of gameplay-sheet columns planned for removal after implementation.

Then stop at **Gate B**.

The director may import the three CSVs into the master workbook at this point.

---

## 15. Workbook/content authority after Gate B

The v0 CSVs are generated by the coding agent to seed the production structure.

Once the director incorporates them into the master workbook, the workbook is the intended authoring source for these sheets going forward.

The build pipeline should then consume the exported CSVs in the same general manner as the project's existing data sheets.

Do not create a second competing source of truth in scene code or generated resources.

---

## 16. Runtime architecture

The exact implementation is Gate-A work, but the result should provide semantic access rather than raw CSV lookups scattered across scenes.

Conceptually the runtime needs equivalents of:

- text content lookup by `(SEMANTIC_CATEGORY, REF_ID)`;
- semantic style lookup by `STYLE_ID`;
- font lookup by `FONT_ROLE`;
- placeholder formatting;
- validation.

Scene/component code should request semantic content and styles, not CSV row indexes or arbitrary filenames.

---

## 17. Renderer/component migration

After Gate B approval:

### 17.1 Migrate content retrieval

Replace current player-facing literals and legacy gameplay-sheet display fields with semantic text-content lookups.

### 17.2 Migrate typography behavior

Replace ad-hoc text sizing/fitting where the new text-style system owns it.

Do not blindly rewrite every label if its existing behavior already maps cleanly to a semantic style.

### 17.3 Preserve layout responsibility

Text migration should not turn into a major layout redesign.

Components still own:

- available text rectangle;
- surrounding geometry;
- container hierarchy;
- margins/padding intrinsic to the component.

The text framework owns:

- font role;
- nominal/min size;
- fit behavior;
- line count;
- alignment;
- semantic text color;
- other approved style properties.

### 17.4 Remove obsolete content fields

Only after all consumers migrate and validation proves they are unused, remove the legacy display/description fields from gameplay sheets.

---

## 18. Text-color policy

The coding agent should inspect the current color usage and recommend the smallest semantic color-role vocabulary needed by text.

Do not build a generalized recoloring/theme system.

A small role set such as:

- `PRIMARY`
- `SECONDARY`
- `ACCENT`
- `WARNING`
- `DISABLED`

may be appropriate, but the agent should derive the actual set from the game.

The goal is to avoid hardcoded text-color literals without turning `text_style.csv` into a full stylesheet.

---

## 19. Explicitly out of scope

Do not add in Beta 0.3.2:

- localization UI or language selection;
- translation authoring beyond the future-ready CSV structure;
- pluralization/grammar engine;
- dialogue system;
- narrative scripting;
- rich-text framework unless required by current content;
- text animation;
- typewriter effects;
- final font/art-direction decision;
- major UI layout redesign;
- accessibility scaling system;
- generalized CSS-like stylesheet;
- arbitrary geometry in `text_style.csv`;
- audio;
- particles;
- shaders/VFX;
- graphics-development jig;
- content breadth expansion;
- gameplay-rule changes.

---

## 20. Verification philosophy

This build changes presentation infrastructure and content plumbing, not gameplay rules.

Verification should focus on:

- complete text migration;
- correct semantic lookup;
- style consistency;
- fit behavior;
- font-resource packaging;
- character coverage;
- device readability;
- no stale/incorrect literals;
- no gameplay regression.

### 20.1 Automated checks

At minimum:

- full maintained headless suite;
- fast 150-battle parity if gameplay code remains untouched;
- CSV/schema validation;
- duplicate `(SEMANTIC_CATEGORY, REF_ID)` detection;
- duplicate/unknown style-role detection;
- unknown font-role detection;
- font-file existence/import validation;
- current-character-corpus coverage;
- unresolved-placeholder validation;
- scan for migrated player-facing literals where practical;
- scan/validation proving removed gameplay display fields have no consumers;
- title-logo/catalog completeness;
- countdown digit asset completeness 0–9.

No DEEPSCAN unless shared gameplay code changes unexpectedly.

### 20.2 Human visual verification

Automated checks cannot establish whether text actually fits or reads well.

Use matched screenshots and device inspection.

Pay particular attention to:

- longest Program/Hacker/System/Deck names;
- narrow buttons;
- Build-screen controls;
- multi-line instructions;
- result/status text;
- pause panel;
- title screen;
- countdown overlays;
- minimum-size shrink behavior.

---

## 21. Device verification

### 21.1 Tablet

Use as routine iteration target.

Check representative screens:

- title/start;
- Boss selection;
- Hacker selection;
- Deck selection;
- Path Choice;
- Build;
- normal Battle;
- Boss Battle;
- pause;
- result;
- Run Complete.

Confirm:

- bundled fonts render;
- text does not unexpectedly overflow;
- shrink behavior stops at the defined minimum;
- wrapping obeys max-line rules;
- title logo fits;
- countdown digit sprites are legible;
- no missing-text fallback appears in a normal flow;
- clean log.

### 21.2 S25

One final announced hardware window.

Confirm:

- title logo layout and safe area;
- text remains readable at real panel density;
- longest/current edge-case strings fit;
- buttons remain legible without clipping;
- Program names and charge/status text remain readable;
- countdown digits remain distinct and centered on real hardware;
- no horizontal overflow;
- clean log.

---

## 22. Implementation sequence

### Phase A — inspect and propose

Inventory current strings, text fields, styles, fit behavior, font needs, glyph corpus, title treatment, and countdown treatment.

Write Gate-A proposal.

**Stop at Gate A.**

### Phase B — populate v0 data/assets

Create:

- `text_content.csv`
- `text_style.csv`
- `font_refs.csv`
- bundled v0 fonts
- title-logo PNG
- countdown-digit asset set

Prepare migration map and inspection artifacts.

**Stop at Gate B.**

### Phase C — runtime registries/loaders

Implement semantic text-content, style, font, validation, and formatting infrastructure.

### Phase D — graphics carry-forward

Add title logo to the graphics pack/catalog and title screen.

Add countdown digit assets to the graphics pack/catalog and replace font-rendered overlay countdowns.

### Phase E — text migration

Migrate player-facing literals and gameplay-sheet display strings to semantic text-content lookups.

Apply semantic text styles.

### Phase F — cleanup

Remove obsolete display/description columns only after proving no consumer remains.

Remove superseded font-rendered countdown path.

Remove obsolete player-facing literals where migration now owns them.

### Phase G — verification/devices

Run automated gates, tablet pass, and S25 sign-off.

### Phase H — closeout

Update:

- README;
- decisions;
- port notes where technical deviations warrant it;
- architect notes;
- lessons learned.

Review final diff, commit, push, clean working tree.

---

## 23. Completion standard

Beta 0.3.2 is complete when:

1. Gate A proposal was delivered and approved.
2. Current player-facing strings were inventoried.
3. Existing display/description gameplay fields were classified.
4. `text_content.csv` schema was approved.
5. `text_style.csv` schema was approved.
6. `font_refs.csv` schema was approved.
7. v0 semantic categories were approved.
8. v0 style roles were approved.
9. v0 font roles were approved.
10. populated v0 CSVs were generated.
11. v0 font resources were bundled locally.
12. current character coverage was validated.
13. Gate B data/assets were inspected and approved.
14. semantic runtime text-content lookup is implemented.
15. semantic style lookup is implemented.
16. semantic font-role lookup is implemented.
17. simple named-placeholder formatting is implemented.
18. missing text/style/font failures are visible and logged.
19. player-facing literals are migrated where practical.
20. presentation-only gameplay-sheet strings are migrated.
21. obsolete gameplay text columns are removed only after consumers are gone.
22. title-logo PNG is in the graphics pack/catalog.
23. title logo renders above the start-screen controls.
24. countdown digits 0–9 exist as graphics assets.
25. countdown overlays no longer depend on font-rendered numerals.
26. countdown renderer can compose multi-digit values in principle.
27. text fitting uses explicit policies and hard minimum sizes.
28. text-style config does not become a layout stylesheet.
29. current portrait phone layout remains correct.
30. current tablet portrait layout remains correct.
31. gameplay behavior remains unchanged.
32. maintained tests pass.
33. fast parity remains green if gameplay code is untouched.
34. no DEEPSCAN is required unless shared gameplay code changed.
35. docs are updated.
36. final diff is reviewed.
37. intended changes are committed and pushed.
38. working tree is clean.

---

## 24. Expected next step

After Beta 0.3.2, the planned presentation sequence can return to the **graphics/presentation development jig**.

At that point the jig can operate against:

- the production `GraphicsPack`;
- production title/countdown graphics;
- authoritative text content;
- semantic text styles;
- bundled font roles;
- explicit fitting behavior.

That makes the jig materially more useful than building it while text geometry was still ad hoc.

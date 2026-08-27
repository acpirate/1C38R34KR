# 1C38R34KR Beta 0.3.1 — Graphics Asset Layer Iteration 1
## Full Build Authorization with Two Human Approval Gates

**Build identity:** `beta-0.3.1`  
**Purpose:** establish the first production-oriented graphics asset layer, create Asset Pack v0, and convert the live renderer to consume that pack through the same general mechanism intended for release builds.  
**Engine:** Godot 4.7.2, standard/non-Mono  
**Language:** GDScript  
**Primary platform target:** Android portrait, with tablet portrait validation  
**Status:** authorized for the full iteration, subject to two mandatory stop/review gates

---

## 0. Purpose

The gameplay port is complete through Beta 0.3.0.

Beta 0.3.1 begins the production-oriented graphics workflow.

The current build uses functional placeholder rendering. This iteration should:

1. inspect the actual renderer and negotiate the smallest practical reusable static asset vocabulary;
2. generate a complete initial **Asset Pack v0**;
3. stop so the director can inspect the generated pack visually;
4. after approval, convert the live renderer to consume the asset pack;
5. verify that the resulting renderer is suitable as the foundation for future release-oriented art replacement.

This is infrastructure work, not the final art pass.

The following graphics iteration is expected to build a dedicated graphics-development jig that reuses the production renderer and asset contract established here.

---

## 1. Authority and source precedence

Use sources in this order:

1. **This document** for Beta 0.3.1 scope, gates, asset-format rules, and implementation boundaries.
2. `Graphics Asset Layer — Iteration 1 Intent.md`
3. The shipped Beta 0.3 repository and its current renderer/UI implementation.
4. Current game screenshots and the running build as the functional display reference.
5. Existing project docs (`README.md`, `CLAUDE.md`, `decisions.md`, `port-notes.md`, `architect-notes.md`, `lessons-learned.md`).

If prose and source disagree about what the current game actually renders, the **shipped Beta 0.3 implementation wins**. Record the discrepancy.

---

## 2. Hard clarifications

### 2.1 Version

This work is `beta-0.3.1`.

### 2.2 Asset formats

`packet_palette.svg` is the **only SVG** in this graphics layer.

Its sole purpose is to provide the six editable normal Packet colors.

All rendered graphics assets are expected as **lossless PNG** files, including:

- backgrounds;
- frames/panels;
- buttons;
- progress bars;
- scrollbars;
- icons;
- Packet glyphs;
- Packet overlays;
- special-state overlays;
- Build-screen graphics;
- any other visual asset introduced in this pass.

Using Godot 9-slice / `StyleBoxTexture` behavior with PNG sources is allowed and expected where appropriate.

### 2.3 Packet palette workflow

The palette source must be:

`packet_palette.svg`

It should contain exactly six visibly distinct swatches with stable XML IDs:

- `packet_red`
- `packet_yellow`
- `packet_green`
- `packet_cyan`
- `packet_blue`
- `packet_magenta`

The SVG must be directly editable in Inkscape.

The game must obtain the **exact defined values**, not sampled raster colors.

The coding agent may choose an editor/import/build-time extraction path rather than runtime XML parsing, provided the SVG remains the authoritative editable source.

### 2.4 Audio

Audio is out of scope.

No audio hooks, audio buses, sound assets, or sound-trigger plumbing should be added in Beta 0.3.1.

### 2.5 Asset Pack v0

The coding agent is expected to generate the initial v0 PNG pack itself.

The v0 pack:

- should be complete;
- should approximately reproduce the current functional presentation;
- may be visually plain;
- is meant to validate the graphics architecture;
- is not expected to establish the final release art direction.

---

## 3. Mandatory human gates

This iteration has **two explicit stop points**.

### Gate A — asset-contract proposal

The coding agent must:

1. inspect the current renderer;
2. inventory the visuals actually required by the live game;
3. propose the semantic asset contract;
4. propose folder/naming/import conventions;
5. propose the Packet palette ingestion path;
6. recommend any additions/consolidations/removals from the initial asset list;
7. deliver the proposal document;
8. **stop and wait for director approval.**

No Asset Pack v0 generation begins before Gate A approval.

### Gate B — Asset Pack v0 visual inspection

After Gate A approval, the coding agent must:

1. create the approved PNG asset pack;
2. create the editable `packet_palette.svg`;
3. generate any palette-derived Godot resource needed by the approved workflow;
4. provide a complete asset inventory and visual inspection package;
5. **stop and wait for director approval.**

At Gate B, the director must be able to inspect the actual generated assets before the renderer is modified to depend on them.

No production-renderer conversion begins before Gate B approval.

### After Gate B approval

The agent may proceed to:

- implement the graphics catalog/resource;
- convert the renderer to asset-driven rendering;
- remove or bypass obsolete hardcoded/procedural presentation where the new asset layer replaces it;
- validate the resulting game on phone/tablet.

---

## 4. Architecture objective

The implementation should create one production-oriented **graphics-pack/catalog contract**.

Game screens/components should request semantic visuals, not raw paths.

Examples:

- `screen_background`
- `panel_standard`
- `panel_active`
- `button_standard`
- `button_selected`
- `button_disabled`
- `progress_track`
- `progress_fill_link`
- `progress_fill_ice`
- `scroll_track`
- `scroll_thumb`
- `packet_cell`
- `packet_glyph[TRI]`
- `packet_overlay_selected`
- `special_overlay[BOMB]`

The catalog owns the actual PNG resources and related Godot types.

The later graphics-development jig should be able to reuse this exact production contract.

---

## 5. Architectural principles

The graphics layer must preserve a clean distinction between:

### Layout
- size;
- anchors;
- margins;
- responsive behavior;
- safe areas;
- portrait phone/tablet composition.

### Skin/assets
- PNG textures;
- 9-slice frames;
- icons;
- overlays;
- Packet glyphs;
- Packet palette values;
- other authored visual appearance.

### Game state
- gameplay data determining what must be shown.

Replacing assets should not require rewriting gameplay logic.

Changing layout should not require regenerating every asset unless an asset genuinely depends on fixed geometry.

---

## 6. Stage A — renderer inspection and asset-contract proposal

### 6.1 Renderer inspection

Inspect the real Beta 0.3 implementation.

Document:

- major visual scenes/components;
- how Packet geometry is currently rendered;
- how Packet color/shape is represented;
- how special overlays are currently rendered;
- how board/background/frame visuals are currently produced;
- how panels/buttons/progress bars/scrollbars are currently styled;
- current Build-screen visual states;
- any renderer code already acting as a centralized presentation registry;
- places where layout and skin are still entangled.

### 6.2 Proposed asset vocabulary

Start from the intent list, but recommend the smallest complete reusable vocabulary.

The proposal should explicitly decide whether each candidate becomes:

- a distinct PNG;
- a generic reusable PNG;
- a 9-slice PNG;
- an overlay;
- a state parameter;
- unnecessary because an existing generic asset already covers it.

### 6.3 Required proposal categories

At minimum review:

#### General screen/UI chrome
- screen background;
- generic panel/frame;
- emphasized/active panel/frame;
- standard button;
- selected button;
- disabled button;
- input-field frame;
- horizontal divider;
- scrollbar track;
- scrollbar thumb;
- generic progress-bar track;
- generic progress-bar fill;
- LINK treatment;
- ICE treatment;
- battle menu icon;
- up/down arrows.

#### Battle UI
- Hacker header;
- opponent header;
- Program frame;
- ready/charged state;
- Deck Function frame;
- board/Datastream frame.

Determine what truly requires unique art versus generic frame/state composition.

#### Packet graphics
- Packet cell/background;
- six monochrome Packet shape/glyph PNGs;
- neutral/static Packet;
- selected/highlight overlays if actually used;
- all currently reachable special overlays;
- ownership/state interaction.

Do not create 36 color/shape combination sprites.

Packet shape assets should remain tintable/monochrome so gameplay color remains a separate rendering dimension.

#### Build screen
Review whether distinct assets are actually needed for:
- slot/container;
- selected slot;
- priority/accent;
- normal choice;
- selected choice;
- disabled choice.

Consolidate with generic panel/button assets where practical.

#### Fonts
The proposal may include a font slot/resource if that fits the current architecture, but no final typography decision is required.

### 6.4 Proposal deliverable

Produce:

`1c38r34kr-beta-0.3.1-graphics-asset-proposal.md`

It must include:

1. renderer inspection summary;
2. semantic graphics-catalog architecture;
3. exact proposed asset inventory;
4. per-asset dimensions/aspect guidance where useful;
5. which assets use transparency;
6. which assets use 9-slice/stretching;
7. import/filter recommendations;
8. folder/naming scheme;
9. palette ingestion plan;
10. missing/invalid asset behavior;
11. implementation plan for Asset Pack v0 and renderer conversion.

Then stop at **Gate A**.

---

## 7. Stage B — Asset Pack v0 generation

After Gate A approval, create the approved Asset Pack v0.

### 7.1 Asset format

All rendered assets are lossless PNG.

Transparency should be used where appropriate.

The pack should be deliberately simple and approximately reproduce the current whitebox presentation.

### 7.2 Palette SVG

Create:

`packet_palette.svg`

Requirements:

- opens cleanly in Inkscape;
- contains all six colors visibly on one canvas;
- each swatch is clearly labeled visually;
- each swatch carries the stable XML ID;
- no extra gameplay colors are encoded as configurable palette entries;
- the SVG remains pleasant to edit as a coordinated palette.

### 7.3 Packet glyphs

Create six monochrome tintable PNG glyphs matching the six gameplay Packet shapes.

Do not encode Packet color into the glyph PNGs.

### 7.4 Special overlays

Inventory the current special-state model from the live renderer and create the approved overlay PNGs.

Prefer overlays over full replacement tiles where the state needs to coexist with:

- Packet color;
- Packet shape;
- ownership;
- special identity.

### 7.5 v0 pack completeness

Every semantic asset required by the approved contract must exist.

No future renderer conversion should need to silently fall back to the old whitebox for an asset-backed element because the pack was incomplete.

### 7.6 Gate-B inspection package

Before renderer conversion, provide:

- the asset directory;
- a manifest/inventory;
- the palette SVG;
- a simple visual sheet/contact sheet or equivalent human-inspection presentation showing the generated assets together;
- notes identifying 9-slice borders or scaling assumptions.

Then stop at **Gate B**.

---

## 8. Stage C — production graphics catalog/resource

After Gate B approval, implement the graphics catalog.

The exact implementation should follow the approved Gate-A proposal.

Preferred characteristics:

- one Godot-native resource/container owns the semantic asset map;
- renderer code requests semantic fields/IDs rather than arbitrary paths;
- asset-path knowledge is centralized;
- Packet glyph lookup is keyed by gameplay Packet shape;
- special overlay lookup is keyed by semantic special kind;
- palette colors are exposed through one runtime palette resource derived from the SVG source;
- future asset-pack replacement does not require gameplay changes.

Do not create a generalized arbitrary theme engine beyond what this build needs.

---

## 9. Stage D — renderer conversion

Convert the live game renderer to consume the approved asset pack.

### 9.1 Convert where assets make sense

Replace hardcoded/procedural visuals where the approved asset vocabulary now owns the appearance.

Examples may include:

- screen backgrounds;
- panels/frames;
- buttons;
- bars;
- scrollbars;
- icons;
- Packet glyphs;
- Packet cell/background;
- Packet special overlays;
- board frame;
- Build-screen chrome.

### 9.2 Preserve procedural/state rendering where appropriate

Do not force every dynamic visual into a bitmap if procedural rendering remains the better representation.

The purpose is an asset-driven skin layer, not "everything must be a sprite."

### 9.3 Do not scatter asset paths

No screen/component should contain arbitrary hardcoded asset filenames unless the approved architecture explicitly requires it.

### 9.4 Do not silently retain the old skin

For elements explicitly moved into the asset pack, the old procedural whitebox should not remain as an invisible fallback that could mask missing assets.

---

## 10. Missing/invalid asset behavior

Required graphics assets should fail **visibly and gracefully**.

Preferred behavior:

- conspicuous diagnostic fallback texture/style;
- explicit error log naming the semantic asset;
- no crash;
- no silent fallback to old procedural whitebox.

If practical, validate the graphics pack/catalog at startup and report all missing required entries together.

This is development infrastructure and should remain suitable for release diagnostics.

---

## 11. Packet palette runtime behavior

Only the six normal Packet colors are externally configurable in this iteration.

Other UI/frame/effect/background colors remain authored in their PNGs or current rendering resources.

Do not create a generalized recoloring system.

The production game should use exact values derived from `packet_palette.svg`.

Runtime XML parsing is not required and is not preferred if a cleaner editor/import/build-time conversion is available.

The required workflow is:

1. open `packet_palette.svg` in Inkscape;
2. edit the six swatches together;
3. save;
4. run the normal import/build workflow;
5. game uses those exact saved values.

---

## 12. PNG/import policy

The approved proposal should determine exact settings, but implementation should generally account for:

- lossless PNG source;
- alpha transparency where appropriate;
- filtering choices that preserve intended sharpness;
- no destructive compression artifacts;
- 9-slice treatment for scalable chrome;
- source dimensions that survive both phone and tablet scaling;
- avoidance of unnecessary per-resolution asset duplication.

Do not make a final pixel-art/retro filtering decision unless the approved v0 pack specifically requires it.

---

## 13. Current display targets

Renderer conversion must remain correct on:

- primary: current tall Android phone portrait layout;
- secondary: more vertically compressed Android tablet portrait layout.

The phone intentionally has more vertical breathing room.

Landscape remains out of scope.

No major layout restructuring is authorized merely to accommodate the asset pack.

If the asset layer exposes a pre-existing layout defect, report it separately rather than broadening the graphics pass automatically.

---

## 14. Explicitly out of scope

Do not add in Beta 0.3.1:

- graphics-development jig;
- runtime hot reload;
- filesystem watching;
- reference screenshot overlay tooling;
- scene-selection art tooling;
- animation-system work;
- particles;
- shaders/VFX;
- audio;
- HOST visual variation;
- encounter-by-encounter escalation;
- Boss-specific bespoke skin;
- landscape layout;
- major UI/UX redesign;
- final retro/16-bit art direction;
- generalized UI recoloring/theme system;
- content expansion;
- gameplay-rule changes.

---

## 15. Verification philosophy

This is a presentation/infrastructure pass.

Verification should focus on:

- asset-contract completeness;
- renderer correctness;
- display fidelity;
- missing-asset behavior;
- phone/tablet layout;
- no accidental gameplay regression.

Do not build a heavy differential-verification program for visual assets.

### 15.1 Required automated regression

At minimum:

- current maintained headless logic suite;
- normal fast battle parity if renderer work does not alter gameplay logic;
- presentation/asset validation tests as useful;
- no new DEEPSCAN requirement unless shared gameplay code is unexpectedly changed.

### 15.2 Required visual verification

Human/device inspection matters more than screenshot-perfect automation.

Verify on the tablet during implementation and on the S25 at final sign-off.

Judge success by:

- legibility;
- correct composition;
- complete asset use;
- no clipping/overflow;
- no missing states;
- approximate reproduction of current functional presentation.

Pixel-perfect reproduction of the whitebox is not required.

---

## 16. Device verification

### 16.1 Tablet

Use for iteration.

Check representative screens:

- Title/menu;
- Boss/Hacker/Deck selection;
- Path Choice;
- Build;
- normal Battle;
- Boss Battle;
- result/run-complete screen.

Confirm:

- PNG skin renders;
- Packet shapes/colors/special overlays remain readable;
- bars/frames/buttons render correctly;
- scalable chrome does not distort;
- no major layout regression;
- clean log.

### 16.2 S25

One final phone window.

Confirm:

- same representative screens fit;
- safe area remains correct;
- no horizontal clipping;
- Packet glyphs remain legible;
- selected/disabled/ready states are visually distinguishable;
- no asset scaling artifact makes interaction states ambiguous;
- clean log.

---

## 17. Implementation sequence

### Phase A — inspect and propose
Renderer inventory, semantic contract, palette plan, import policy, manifest proposal.

**Stop at Gate A.**

### Phase B — generate Asset Pack v0
Create lossless PNG pack and editable palette SVG.

Prepare asset manifest/contact sheet.

**Stop at Gate B.**

### Phase C — graphics catalog
Implement the approved Godot-native catalog/resource.

### Phase D — renderer conversion
Move appropriate current visuals to the approved asset-driven path.

### Phase E — validation and cleanup
Missing-asset validation, tablet checks, S25 check, remove obsolete asset-backed whitebox code, README/docs.

### Phase F — closeout
Update process docs, commit, push, clean tree.

---

## 18. Completion standard

Beta 0.3.1 is complete when:

1. Gate A proposal was delivered and approved.
2. The semantic graphics asset contract is agreed.
3. Asset Pack v0 contains every required approved PNG asset.
4. `packet_palette.svg` contains the six stable semantic Packet swatches and is usable in Inkscape.
5. Gate B asset inspection was completed and approved.
6. The production graphics catalog/resource is implemented.
7. The live renderer consumes semantic assets from the pack.
8. Appropriate old hardcoded/procedural skin rendering is no longer relied on for asset-backed elements.
9. Packet shape remains independent from Packet color.
10. Packet colors come from the external palette source through the approved extraction workflow.
11. Special states/ownership remain readable and composable.
12. Missing/invalid assets fail visibly/gracefully.
13. Current phone portrait layout remains correct.
14. Current tablet portrait layout remains correct.
15. Gameplay behavior remains unchanged.
16. Maintained tests/regression gates pass.
17. No audio or other out-of-scope aesthetic systems were pulled in.
18. README/process docs are updated.
19. Final diff is reviewed.
20. Intended changes are committed and pushed.
21. Working tree is clean.

---

## 19. Future graphics iteration

After Beta 0.3.1, the next planned graphics iteration is the **graphics-development jig**.

That jig should:

- reuse the exact production graphics catalog/resource;
- reuse the exact production rendering components;
- load representative scenes/states;
- support rapid external asset iteration;
- avoid creating a parallel art-only renderer.

The reason Beta 0.3.1 must use release-appropriate asset plumbing now is so the jig improves the real production path rather than creating another temporary one.

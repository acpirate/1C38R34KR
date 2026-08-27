# Graphics Asset Layer — Iteration 1 Intent

## Purpose

Introduce the first production-oriented graphics asset layer for the Godot port of **1C38R34KR**.

The current build uses functional placeholder rendering. This iteration should establish the asset contract and convert the live game renderer to consume a static asset pack using the same general mechanism intended for release builds.

This is infrastructure work, not a final art pass.

The next iteration will build a dedicated graphics-development jig after the asset contract and production renderer have been proven in the live game.

## Primary objectives

### 1. Negotiate the static graphics asset library

Begin with the proposed asset targets below, but the coding agent must inspect the current Godot display implementation before implementation and may recommend:

- additional assets;
- removal of unnecessary assets;
- consolidation of assets that can share one reusable component;
- appropriate dimensions or aspect constraints;
- use of 9-slice/stretchable assets;
- transparency requirements;
- filtering/import settings;
- naming and folder organization;
- fallback behavior.

The goal is the **smallest practical reusable asset vocabulary capable of reproducing the current game displays**.

The current game screenshots, not generated concept art, are the functional reference for what must presently be represented.

### 2. Create Asset Pack v0

Generate an initial complete static asset pack that approximately reproduces the current placeholder presentation.

Asset Pack v0 exists to validate the architecture. It does not need to establish the final art direction.

Every required asset target should have a usable initial asset so the full production rendering path can be exercised.

### 3. Convert the production renderer to asset-driven rendering

Update the game display layer so appropriate visuals are loaded from the asset pack instead of being hardcoded or procedurally constructed where replacement with assets makes sense.

The resulting architecture should be suitable for a release build.

Rendering/layout code should refer to semantic asset identifiers or resources rather than scattering arbitrary filenames and paths throughout the codebase.

Missing or invalid assets should fail visibly and gracefully rather than crash the game.

The converted renderer must continue to support the current portrait phone layout and the more vertically compressed tablet layout.

## Proposed initial asset library

This list is a starting point for architectural review, not an immutable specification.

### General screen / UI chrome

- screen background
- generic panel/frame
- emphasized/active panel/frame
- standard button
- selected button
- disabled button
- input-field frame
- horizontal divider
- scrollbar track
- scrollbar thumb
- generic progress-bar track
- generic progress-bar fill
- player health/LINK bar treatment
- enemy health/ICE bar treatment
- battle menu icon
- up-arrow icon
- down-arrow icon

Reusable frames should use 9-slice or equivalent scalable treatment where appropriate rather than requiring unique fixed-size sprites for every panel.

### Battle-specific reusable elements

Potential semantic frame types include:

- Hacker header frame
- System header frame
- Program frame
- ready/charged Program frame or overlay
- Deck Function frame
- Datastream/board frame

The coding agent should determine whether these genuinely require separate assets or can be produced from the generic frame system plus state/style parameters.

### Packet assets

Keep Packet color and shape as independent rendering dimensions.

Proposed assets:

- Packet cell/background treatment
- six monochrome Packet shape/glyph sprites
- neutral/static Packet sprite
- selected-Packet overlay
- hint/highlight overlay if required by the current implementation
- special-Packet overlays as needed by the current game state

Do **not** create 36 separate color/shape combination sprites.

The six normal Packet glyphs should be reusable monochrome/mask-style assets tinted at runtime.

Special states should preferably remain overlays on the underlying Packet rather than full replacement tiles so that color, shape, ownership and special-state information can coexist.

The coding agent should inventory the current special-Packet renderer and determine the exact overlay set required by the current build.

### Build-screen assets

Potential targets include:

- Build slot/container
- selected Build slot
- priority/accent treatment
- Build choice normal
- Build choice selected
- Build choice disabled

These should be consolidated with the generic panel/button assets wherever practical.

### Fonts

The asset layer may include the current UI font resources if that fits the existing Godot architecture.

No final bitmap/16-bit typography decision is required in this iteration.

## Packet color palette

Only the **six normal Packet colors** should be externally configurable in this iteration.

Other interface, frame, text, effect and background colors remain authored directly into their sprites or existing rendering resources. Do not build a generalized recoloring/theme system yet.

### Proposed palette source

Use a small external SVG file such as:

`packet_palette.svg`

The SVG should contain exactly six clearly identified color swatches corresponding to the six gameplay Packet colors.

Each swatch should have a stable semantic XML ID, for example:

- `packet_red`
- `packet_yellow`
- `packet_green`
- `packet_cyan`
- `packet_blue`
- `packet_magenta`

The renderer/asset loader should obtain the exact color values from the SVG definition rather than sampling raster pixels.

The purpose is to allow the art workflow to:

1. open the palette visually in an SVG-capable editor;
2. see all six gameplay colors together;
3. adjust them as a coordinated palette;
4. save the SVG;
5. have the game use those exact defined colors.

The architect/coding agent may propose a technically cleaner equivalent if parsing SVG XML at runtime is inappropriate for Godot release builds, provided the workflow preserves the important requirement: **one externally editable visual source containing all six exact Packet colors together**.

## Architecture principles

The graphics layer should preserve a distinction between:

- **layout:** size, anchors, margins, responsive behavior and safe areas;
- **skin/assets:** visual appearance supplied by the asset pack;
- **game state:** gameplay data determining what must be displayed.

Replacing the asset pack should not require rewriting gameplay logic or screen layout.

Likewise, layout changes should not require regenerating every sprite unless the asset itself genuinely depends on fixed geometry.

## Current display targets

The renderer must remain functional across the currently tested portrait layouts:

- primary target: taller/wider Android phone display;
- secondary validation target: more vertically compressed tablet display.

The phone layout intentionally provides more vertical breathing room for combat-log presentation.

Landscape PC/mobile presentation remains a future stretch goal and should not expand this iteration.

## Explicitly out of scope

Do not build in this iteration:

- graphics-development jig;
- runtime external asset hot-reloading;
- filesystem watching;
- reference screenshot overlay tooling;
- scene-selection tooling for art development;
- animation;
- particles;
- shaders or VFX systems;
- encounter-by-encounter graphical escalation;
- HOST visual variation;
- Boss-specific visual treatment;
- landscape layout;
- major UI layout restructuring;
- final retro/16-bit art pass;
- generalized UI recoloring or theme/palette system.

## Future iteration context

The planned next graphics iteration is a dedicated development jig using the production renderer.

Its intended purpose is to load representative game scenes and allow rapid external asset iteration without rebuilding the full game.

That jig should eventually reuse the exact production rendering components established by this iteration, which is why this build should avoid creating temporary asset-loading architecture that would later need replacement.

## Success criteria

This iteration is successful when:

1. a coherent static asset library contract has been agreed upon after inspection of the real renderer;
2. Asset Pack v0 contains all required assets;
3. the production game loads and renders those assets through a release-appropriate asset pipeline;
4. the current game presentation can be reproduced approximately without relying on the previous hardcoded visual implementation for asset-backed elements;
5. the six normal Packet colors are sourced from one externally editable palette definition;
6. the same build continues to render correctly on the current phone and tablet portrait targets;
7. future visual replacement can occur primarily by replacing assets rather than modifying gameplay or display logic.
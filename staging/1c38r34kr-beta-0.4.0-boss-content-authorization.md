# 1C38R34KR Beta 0.4.0 — Boss Content Pass
## Build Authorization

**Build identity:** `beta-0.4.0`  
**Purpose:** begin the content-breadth phase with the mechanically richest content category: Bosses. Expand the Boss roster from one to four, implement the three new Boss-specific rule sets, add the minimal supporting Functions and board-state presentation they require, and add a Boss Attack Quick Match mode for direct testing.  
**Engine:** Godot 4.7.2, standard/non-Mono  
**Language:** GDScript  
**Primary platform:** Android portrait  
**Status:** authorized for implementation. No separate design-document or architecture-approval gate is required.

---

## 0. Intent

The presentation framework is now in place. Beta 0.4 begins content expansion.

Bosses come first because their mechanics are expected to be the most involved content in the game and therefore the most likely to expose reusable engine hooks, state patterns, and validation needs before the larger body of ordinary content is authored.

Do **not** force premature abstraction.

The four Boss behaviors are sufficiently different that there is no current value in expressing them as ordinary `PSV` rows or inventing a configurable Boss-passive language. Implement Boss-specific orchestration directly in the Boss layer. Extract a reusable helper or hook only where the implementation demonstrates an actual common pattern.

This build is intended to answer:

> Can the current gameplay and presentation framework support several materially different Boss mechanics without another foundational rewrite?

---

## 1. Authority

Use sources in this order:

1. **This authorization and the director clarifications incorporated into it.**
2. The supplied current workbook, especially:
   - `BOS`
   - `FNC`
   - `boss passive notes`
   - `text_content`
   - existing Hacker/Deck/HOST/Program sheets
3. The shipped Beta 0.3.2 runtime.
4. Current `decisions.md`, `architect-notes.md`, and `lessons-learned.md`.
5. Alpha only as a behavioral oracle for mechanics that remain inherited from Alpha.

The workbook is now the authoring source. Make required content changes in the workbook/export flow rather than hand-editing `data/*.csv` as the durable source.

Run the existing workbook round-trip/check tooling as part of verification.

---

## 2. High-level scope

Beta 0.4.0 includes:

1. four authored Bosses in runtime content;
2. ODANSHAY updated to 350 base ICE;
3. RAHNDAHL Boss behavior;
4. NEHBOCYET Boss behavior;
5. ECHOFALL Boss behavior;
6. supporting Functions `FNC_021` and `FNC_022`;
7. new Boss-special identities needed by those mechanics;
8. minimal v0 graphics for those new special identities across current installed skins;
9. ECHOFALL's temporary axis-concealment presentation;
10. a new **Boss Attack** Quick Match mode;
11. text-content additions required by the new Bosses/mode;
12. deterministic save/resume and testing for new Boss state;
13. ordinary gameplay regression verification proportional to whichever shared seams are changed.

No broader content tranche is part of this build.

---

## 3. Boss roster

The Boss roster for this build is:

| BOS_ID | Display name | BASE_ICE | Strong colors | Strong shapes | Program set |
| --- | --- | ---: | --- | --- | --- |
| `BOS_01` | ODANSHAY | 350 | `GRE:BLU:MAG` | `SQU:CIR:DIA` | `PRG_S_004:PRG_S_002:PRG_S_007:PRG_S_003` |
| `BOS_02` | RAHNDAHL | 350 | `RED:YEL:GRE` | `STR:TRI:SQU` | `PRG_S_004:PRG_S_002:PRG_S_007:PRG_S_003` |
| `BOS_03` | NEHBOCYET | 350 | `CYA:MAG:RED` | `SQU:CRO:DIA` | `PRG_S_004:PRG_S_002:PRG_S_007:PRG_S_003` |
| `BOS_04` | ECHOFALL | 350 | `BLU:GRE:YEL` | `DIA:CRO:TRI` | `PRG_S_004:PRG_S_002:PRG_S_007:PRG_S_003` |

The current workbook may still show blank `PRG_SET` cells for BOS_02–04. Under this authorization they are to receive the same set as ODANSHAY.

That shared Program set is deliberate for this phase. The purpose is to isolate and test the Boss rules rather than simultaneously tune Boss Program composition.

Program order remains:

1. `PRG_S_004` — DISABLER
2. `PRG_S_002` — SHIELDER
3. `PRG_S_007` — SPAMBOT
4. `PRG_S_003` — ATTACKER

All four Bosses use their authored `BASE_ICE=350` directly in Boss Attack mode.

The increase from ODANSHAY's previous 250 ICE is intentional. Boss fights should last long enough for escalating/passive behavior to become meaningfully observable.

---

## 4. Architecture rule: Boss behavior is Boss code

Do not add new `PSV` rows merely to represent these Boss rules.

The unique Boss behaviors may be hardcoded initially in the existing Boss-specific logic layer or a clean successor to it.

Acceptable shape:

- Boss ID selects Boss-specific start/end-turn behavior;
- reusable primitives remain in ordinary shared systems;
- Boss orchestration invokes those primitives.

Do not build:

- a Boss scripting language;
- a generic trigger/effect DSL;
- arbitrary data-defined turn hooks;
- a generalized passive framework extension merely so these four rules can be represented in CSV.

If two Bosses genuinely require the same low-level operation, extracting one helper is appropriate. Do not abstract around hypothetical future Bosses.

All random Boss choices must use the existing deterministic battle RNG. Never use OS/system randomness.

---

# 5. BOS_01 — ODANSHAY

ODANSHAY's existing Beta 0.3 behavior remains mechanically unchanged except for the authored ICE increase to **350**.

Retain the existing rules:

### End of Boss turn

Attempt to place three OVERRIDE specials on valid axis-bearing Packets.

OVERRIDE may overwrite Hacker specials.

If insufficient valid placements exist:

1. execute `FNC_018 DATABEND`;
2. retry placement;
3. repeat only under the already-established ODANSHAY retry limit;
4. stop if the Hacker is defeated;
5. otherwise give up after the existing maximum and continue normally.

### Start of Boss turn

If 15 OVERRIDE specials are on the board:

1. execute `FNC_020 CODESHATTER`;
2. if the Hacker survives, execute `FNC_019 REBOOT`;
3. continue the normal Boss turn.

Do not redesign these rules during this build.

Existing ODANSHAY regression tests remain valuable even though Alpha is no longer universal content authority.

---

# 6. BOS_02 — RAHNDAHL

RAHNDAHL introduces the **CAPACITOR** Boss special.

## 6.1 Start-of-Boss-turn sequence

At the beginning of **every** RAHNDAHL Boss phase:

1. count the CAPACITOR specials currently present in the datastream;
2. deal Hacker damage equal to:

`2 ^ capacitor_count`

3. if the Hacker is defeated, end the battle immediately;
4. otherwise attempt to place one CAPACITOR;
5. continue the ordinary Boss turn and Program activations.

Examples:

| Capacitors before tick | Damage |
| ---: | ---: |
| 0 | 1 |
| 1 | 2 |
| 2 | 4 |
| 3 | 8 |
| 4 | 16 |

The 1-damage tick at zero Capacitors is intentional.

## 6.2 Damage semantics

The exponential tick is an ordinary damage instance against Hacker LINK.

Existing Shield behavior applies normally.

Do not create a new damage pipeline for it.

## 6.3 CAPACITOR placement

A CAPACITOR may only be attached to a **non-neutral Packet**.

Placement priority:

1. random eligible non-neutral Packet carrying **no Boss special**;
2. if none exist, random eligible non-neutral Packet carrying a Boss special;
3. if no eligible non-neutral Packet exists, placement fizzles.

A Hacker special does **not** make a Packet ineligible.

Therefore a CAPACITOR may overwrite a Hacker special.

A Boss special is preserved when a non-Boss-special target exists, but may be overwritten as the fallback pool when no such target exists.

Overwriting any existing special is silent:

- do not activate the overwritten special;
- do not award charge;
- do not deal damage merely because it was overwritten.

CAPACITOR itself has no on-destroy effect. If its carrier Packet is removed normally, the CAPACITOR disappears with it.

---

# 7. BOS_03 — NEHBOCYET

NEHBOCYET introduces the **LOGIC BOMB** Boss special and `FNC_021 LOGICBOMBEXPLODE`.

`FNC_021` is already authored as:

- `EFFECT_ATTACK`
- cost `0`
- damage `40`

It is a Boss support Function, not a charged Program Function.

## 7.1 Start-of-Boss-turn sequence

At the beginning of **every** NEHBOCYET Boss phase:

1. remove the entire bottom row of Packets;
2. the removal itself deals **no damage**;
3. the removal itself grants **no charge**;
4. specials on those removed Packets do **not** activate because they were cleared;
5. let the board fall/refill and settle through the ordinary board pipeline;
6. resolve any LOGIC BOMB triggers caused by that movement;
7. after the board is stable and the Hacker remains alive, attempt to place one new LOGIC BOMB on the top row;
8. continue the normal Boss turn.

The bottom-row operation is Packet removal, not merely clearing special overlays.

## 7.2 LOGIC BOMB placement

Choose from Packets in the **top row**.

Placement priority:

1. random top-row Packet carrying no Boss special;
2. if none exists, random top-row Packet carrying a Boss special;
3. if no valid top-row Packet exists, fizzle.

A Hacker special may be overwritten without moving the Packet into the fallback pool.

Overwriting an existing Boss special is allowed only through the fallback pool.

An overwritten special does not activate.

## 7.3 LOGIC BOMB trigger

A LOGIC BOMB triggers whenever its carrier Packet **ends a completed board-movement/settle phase in the bottom row**.

This rule is source-independent.

It applies when movement results from any ordinary gameplay path, including as applicable:

- normal Sync resolution;
- cascades;
- gravity/refill;
- line slicing;
- Functions that remove/rearrange Packets;
- Boss-caused row removal;
- other future operations that use the same board movement/settle path.

Do not wire the rule only to the currently named sources if one common post-settle hook can cover the invariant.

## 7.4 Trigger resolution

When a LOGIC BOMB triggers:

1. remove its **entire carrier Packet** from the datastream;
2. that Packet removal itself deals no damage;
3. that Packet removal grants no charge;
4. execute `FNC_021` once;
5. allow the board to fall/refill and settle normally;
6. check the resulting settled board for further bottom-row LOGIC BOMB triggers;
7. repeat until stable or until the Hacker is defeated.

`FNC_021` uses the ordinary `EFFECT_ATTACK` damage path, including ordinary Shield interaction.

If multiple LOGIC BOMB carriers qualify at the same completed settle, each qualifying bomb is consumed and fires `FNC_021` once.

Resolve them deterministically.

Do not turn the carrier removal into Sync damage, line-slice damage, charge generation, or special activation.

The important invariant is:

> **A settled board may not retain a LOGIC BOMB in the bottom row.**

---

# 8. BOS_04 — ECHOFALL

ECHOFALL introduces temporary **axis concealment** and `FNC_022 BRAINSCRAMBLE`.

`FNC_022` is authored as:

- `EFFECT_ATTACK`
- cost `0`
- damage `30`

It is a Boss support Function, not a charged Program Function.

## 8.1 Concealment timing

At the beginning of ECHOFALL Boss phases:

- phase 1: conceal;
- phase 2: no new concealment;
- phase 3: conceal;
- phase 4: no new concealment;
- phase 5: conceal;
- etc.

In other words, trigger on the first Boss phase and every other Boss phase afterward.

When concealment triggers, randomly choose exactly one axis using the deterministic battle RNG:

- `COLOR`
- `SHAPE`

The hidden-axis choice must be part of battle state and must survive same-build save/resume.

## 8.2 Concealment changes presentation, not Packet identity

The actual Packet data remains unchanged.

Matching, targeting, Functions, strong/weak logic, and board state continue to use the real underlying Packet color and shape.

Only what the player can see is altered.

### Hidden COLOR

For axis-bearing/matchable Packets:

- display the Packet as white;
- retain the real shape visual.

### Hidden SHAPE

For axis-bearing/matchable Packets:

- display the static/no-shape treatment;
- retain the real Packet color.

Neutral Packets remain recognizable as neutral rather than being converted into matchable-looking Packets.

Special overlays/ownership marks remain visible. Concealment masks the base Packet axis, not the overlay state.

## 8.3 Duration

Concealment persists:

- through the remainder of the Boss phase;
- into the following Hacker phase;
- while the Hacker fires Programs or the Deck Function;
- through any resulting board changes;

until the Hacker makes the first board Sync/slice attempt.

The display continues to mask the selected axis after Function-driven board rearrangement until that attempt occurs.

## 8.4 First board attempt while concealed

The game evaluates the attempted move using the real hidden board data.

### If the attempted Sync is valid

1. reveal the board;
2. accept the move;
3. resolve it normally;
4. do not fire `FNC_022`.

### If the attempted Sync is invalid

1. do not commit a board change;
2. do not consume the Hacker's ordinary board move;
3. execute `FNC_022` once;
4. reveal the board;
5. if the Hacker survives, allow another move attempt.

After the board has been revealed, later invalid move attempts during that Hacker phase behave normally and do **not** fire BRAINSCRAMBLE again.

`FNC_022` uses the ordinary `EFFECT_ATTACK` path, including ordinary Shield interaction.

If BRAINSCRAMBLE defeats the Hacker, end the battle normally rather than returning control for another attempt.

## 8.5 State invariant

Concealment is a real Boss battle state, not a renderer-local toggle.

At minimum save/restore must preserve:

- whether concealment is active;
- which axis is hidden;
- enough Boss-phase parity/state to know when the next concealment should occur.

A same-build save taken while ECHOFALL is concealed must resume to the same hidden axis and the same future behavior.

---

# 9. Boss-special identity and graphics

New Boss mechanics require explicit semantic special identities.

Add at least:

- `CAPACITOR`
- `LOGIC_BOMB`

Do not infer these states from Boss ID.

They should participate in the existing overlay/special representation in the same architectural manner as OVERRIDE, BOMB, SHIELD, etc.

## 9.1 Minimal v0 visual requirement

This is a content build, not the art-direction pass.

The visual requirement is functional distinction:

- CAPACITOR must have a distinct readable mark;
- LOGIC BOMB must have a distinct readable mark;
- both must remain distinguishable from OVERRIDE, BOMB, SHIELD, and BUFF;
- Hacker/System ownership/badge logic continues to work normally where applicable.

Add the corresponding semantic graphics-pack entries and authoring-bundle contract entries.

Every currently installed skin must remain complete. Do not add a graphics key only to `v0` and leave another installed pack broken.

Use the existing authoring/pack tooling rather than bypassing it.

Run:

- asset-bundle validation;
- import-fix validation;
- graphics-pack completeness validation.

The new marks are provisional art.

---

# 10. Boss Attack Quick Match mode

Add a new Quick Match mode named **Boss Attack**.

Purpose: fast direct testing of Boss mechanics without playing a Run or manually constructing a build.

## 10.1 Flow

Player-facing flow:

`Title → Boss Attack → Boss list → Boss battle → result`

The Boss list is data-driven from the Boss roster.

Use the established select-then-confirm chooser behavior.

Do not create a separate hardcoded screen per Boss.

## 10.2 Default Hacker side

Boss Attack uses the existing default Hacker build path with:

- Hacker: `HAK_01` — CR45H
- Deck: `DEK_01` — AGIMA
- HOST: `HST_01` — THRESHOLD
- UPGRADEs: none
- active Program/build configuration: reuse the game's current canonical default build for this Hacker + Deck combination

Do not create a second independent definition of the default active build merely for Boss Attack.

`HST_01` is intentionally used because it contributes no HOST passive and therefore keeps Boss testing focused on the Boss mechanic.

## 10.3 Boss stats

Boss Attack uses the selected Boss's authored:

- BASE_ICE;
- strong colors;
- strong shapes;
- Program set;
- Boss behavior.

Do not apply Run ladder ICE modifiers.

All four Bosses therefore enter Boss Attack at 350 ICE in this build.

## 10.4 Seeds

Use the existing Quick Match fresh-seed behavior.

Replay-this-seed, where currently supported by Quick Match results, should replay:

- the same Boss;
- the same default Hacker build;
- the same gameplay seed.

## 10.5 Result navigation

For Boss Attack:

- `New battle` returns to the Boss list;
- replay stays on the same Boss/seed;
- Back to title returns to title.

Do not route `New battle` through Hacker/Deck/System construction screens.

## 10.6 Pause/status text

Boss Attack must identify itself honestly in player-facing UI.

Do not display `Quick Match` or Run-specific wording if that wording would misidentify the mode.

Use the Beta 0.3.2 text-content framework for all new player-facing labels.

---

# 11. Workbook and text-content updates

The supplied workbook already authors:

- all four Boss rows/names;
- all four Boss strong-axis sets;
- `FNC_021 LOGICBOMBEXPLODE`;
- `FNC_022 BRAINSCRAMBLE`;
- Boss-mechanic overview notes.

Required workbook/export updates for this build include:

## BOS

Populate BOS_02–04 `PRG_SET` with the same value as BOS_01:

`PRG_S_004:PRG_S_002:PRG_S_007:PRG_S_003`

## text_content

Add missing semantic rows for at least:

- `BOSS_NAME / BOS_02 / RAHNDAHL`
- `BOSS_NAME / BOS_03 / NEHBOCYET`
- `BOSS_NAME / BOS_04 / ECHOFALL`
- `FUNCTION_NAME / FNC_021 / LOGICBOMBEXPLODE`
- `FUNCTION_NAME / FNC_022 / BRAINSCRAMBLE`

Add the required Boss Attack UI rows rather than embedding player-facing literals in scene code.

Reuse existing generic Boss-select title/style rows where their wording is actually generic.

Do **not** reuse the Run-specific Boss-selection prompt for Boss Attack if it says the Boss is chosen now and fought at the end of a Run.

Add a mode-specific prompt/status row instead.

## Boss notes

The `boss passive notes` sheet remains design/source documentation.

Do not invent runtime CSV passive rows from it.

## Authoring discipline

After workbook changes:

1. export through the existing workbook pipeline;
2. run `export_workbook.py --check`;
3. treat unexpected drift as a failure;
4. do not leave `data/` as the only copy of an authored change.

---

# 12. Supporting Functions

`FNC_021` and `FNC_022` are ordinary reusable Function/effect definitions invoked by Boss code.

They should use existing Function resolution rather than bespoke damage calls.

## FNC_021 — LOGICBOMBEXPLODE

- cost 0
- `EFFECT_ATTACK`
- damage 40
- invoked once per triggered LOGIC BOMB

## FNC_022 — BRAINSCRAMBLE

- cost 0
- `EFFECT_ATTACK`
- damage 30
- invoked only on the first invalid concealed ECHOFALL move attempt for that concealment

Neither Function:

- receives charge;
- is a Program activation;
- is placed into a random Function pool;
- fires autonomously merely because cost is zero.

Follow the existing ODANSHAY support-Function pattern for event attribution, logging, metrics, and source identity.

---

# 13. Turn ordering and defeat handling

Boss passive/rule actions are part of the Boss phase and must respect ordinary defeat short-circuiting.

General rule:

> If a Boss-rule damage event reduces Hacker LINK to zero, do not continue later actions in that Boss-rule sequence or ordinary Boss Program activations.

Examples:

- lethal RAHNDAHL exponential damage → no new CAPACITOR;
- lethal LOGIC BOMB explosion → stop further battle activity;
- lethal BRAINSCRAMBLE → no retry opportunity;
- retain existing ODANSHAY lethal CODESHATTER behavior.

Where several simultaneous LOGIC BOMB triggers already qualify from one settled state, resolve them deterministically through the existing event pipeline and stop according to the engine's ordinary lethal-damage semantics.

---

# 14. Board-settle integration

NEHBOCYET's mechanic deliberately tests a reusable engine boundary: **something may care about the board after movement has fully settled, regardless of what caused the movement.**

Prefer one explicit post-settle integration point over a growing list of special cases such as:

- after Sync, check;
- after DATACUT, check;
- after Shake, check;
- after Boss row clear, check.

The exact implementation is delegated to the coding agent after inspecting the current resolve pipeline.

Constraints:

- ordinary non-Boss battles must be unaffected;
- the hook must be deterministic;
- recursive/chain movement caused by LOGIC BOMB carrier removal must reach a stable state;
- avoid a parallel board-resolution implementation.

If the clean implementation requires touching shared board/resolve code, classify that as a shared-core change for verification purposes.

---

# 15. Save/resume

Standing pre-release policy remains:

- no cross-version migration work;
- same-build save/resume must remain correct.

New Boss state must serialize wherever it cannot be reconstructed safely from existing state.

At minimum ECHOFALL requires explicit preservation of concealment state.

Add a deterministic continuation test that saves during an active ECHOFALL concealment and proves the resumed battle preserves:

- hidden axis;
- active/inactive state;
- subsequent move consequence;
- future concealment cadence.

Board-carried CAPACITOR and LOGIC_BOMB state should already ride the board/overlay serialization path; verify rather than assume.

---

# 16. Alpha/differential policy

Beta 0.4 intentionally authors gameplay beyond Alpha.

Do **not** modify Alpha to manufacture parity for new Bosses.

Alpha remains useful for inherited ordinary battle behavior, but it is no longer a universal Boss-content oracle.

## Required regression position

- existing Beta tests become the authoritative regression for the new Boss rules;
- ordinary/shared battle behavior should remain parity-clean where the compared content is still shared;
- ODANSHAY's inherited behavior should remain internally regression-tested, with the intentional 350-ICE content change accounted for;
- new Bosses have no Alpha counterpart and therefore no Alpha parity requirement.

## DEEPSCAN

Do not run DEEPSCAN merely because new Boss content exists.

Run a fresh DEEPSCAN if implementation changes shared gameplay/board/resolve machinery in a way that could affect ordinary battles.

If the implementation remains isolated to Boss/session/presentation paths and ordinary fast parity stays green, prior DEEPSCAN proof may be carried forward.

State explicitly in the handback which case applied.

---

# 17. Automated verification

The coding agent should refine fixture details against the real architecture, but coverage must prove the following properties.

## 17.1 Content

- four Boss rows load and validate;
- all four have BASE_ICE 350;
- all four have the authored strong axes;
- all four have the shared four-Program set;
- FNC_021 loads as 40-damage `EFFECT_ATTACK`;
- FNC_022 loads as 30-damage `EFFECT_ATTACK`;
- required text-content rows exist;
- no missing graphics keys in any installed skin.

## 17.2 ODANSHAY

- existing Boss behavior remains green;
- authored BASE_ICE expectation is updated to 350;
- no unrelated mechanic drift.

## 17.3 RAHNDAHL

Prove at least:

- zero Capacitors → 1 damage;
- one Capacitor → 2 damage;
- multiple Capacitors scale as `2^n`;
- Shield reduces the tick through ordinary damage rules;
- tick occurs before new placement;
- lethal tick prevents placement;
- placement prefers non-neutral Packets without Boss specials;
- Hacker specials may be overwritten;
- Boss specials are only overwritten through fallback;
- no eligible non-neutral Packet → fizzle;
- destroyed CAPACITOR has no extra effect.

## 17.4 NEHBOCYET

Prove at least:

- start-of-turn bottom row is removed;
- row removal itself produces zero damage;
- row removal itself produces zero charge;
- specials removed by the clear do not activate;
- board falls/refills through ordinary movement;
- a top-row LOGIC BOMB is placed after the clear/settle;
- placement pool priority is correct;
- fallback may overwrite a Boss special;
- no valid target → fizzle;
- a LOGIC BOMB settling in bottom row cannot remain there;
- its entire carrier Packet is removed;
- carrier removal itself produces zero damage/charge;
- `FNC_021` fires exactly once per triggered bomb;
- multiple qualifying bombs each fire;
- Shield applies independently to ordinary FNC_021 damage instances;
- chain movement is rechecked until stable;
- trigger works through more than one movement source, not merely the Boss row clear.

## 17.5 ECHOFALL

Prove at least:

- concealment begins on Boss phases 1, 3, 5;
- it does not newly trigger on phases 2, 4;
- axis selection uses deterministic RNG;
- both COLOR and SHAPE can be selected under discriminating seeds/fixtures;
- hidden presentation does not mutate actual Packet identity;
- special overlays remain represented;
- Hacker Functions can fire while concealment remains active;
- valid concealed move reveals and resolves normally with no FNC_022;
- invalid concealed move does not commit the move;
- invalid concealed move fires FNC_022 exactly once;
- invalid concealed move reveals the board;
- Hacker may retry if alive;
- later invalid attempts after reveal do not fire FNC_022 again;
- Shield applies to FNC_022 through ordinary attack semantics;
- lethal FNC_022 ends the battle;
- save/resume during concealment preserves exact continuation.

## 17.6 Boss Attack

Prove at least:

- title mode is reachable;
- chooser enumerates all current Bosses from content;
- select-then-confirm works;
- selected Boss is the one instantiated;
- Hacker/Deck/HOST/no-UPGRADE default is correct;
- canonical default active build is reused;
- no Run ICE ladder modifier is applied;
- fresh seeds work;
- replay preserves Boss + build + seed;
- New battle returns to Boss chooser;
- no Run session is accidentally created/advanced;
- mode-specific pause/result text is correct.

## 17.7 Existing gates

Run:

- maintained full headless suite;
- scene-script load/parse gate;
- workbook export/check;
- asset-bundle check;
- import-fix check;
- graphics-pack structural check;
- fast ordinary parity.

Treat any `SCRIPT ERROR`, resource error, or importer error during a nominally green run as a failure until explained.

---

# 18. Human/device verification

Use the permanently connected tablet for routine verification.

The point of Boss Attack is to make this pass cheap to exercise manually.

At minimum play/inspect each Boss directly through Boss Attack.

## ODANSHAY

Confirm the longer 350-ICE fight gives enough time for OVERRIDE escalation to be observed.

## RAHNDAHL

Confirm:

- CAPACITOR count is visually readable;
- escalation from 1 → 2 → 4 → 8 etc. is understandable from play;
- placement/overwrites look intentional rather than like disappearing art.

## NEHBOCYET

Confirm:

- bottom-row deletion reads as a deliberate Boss action;
- falling LOGIC BOMB behavior is visually understandable;
- carrier removal and damage occur in an intelligible order;
- repeated/chain triggers do not create unreadable board motion.

## ECHOFALL

Confirm:

- hidden COLOR state is legible;
- hidden SHAPE state is legible;
- the player can still identify special overlays;
- reveal on valid/invalid attempt is obvious;
- an invalid concealed attempt does not feel like the board silently ignored input;
- after BRAINSCRAMBLE the player can immediately make another attempt if alive.

## S25

Use one batched announced phone window near closeout if the build changes battle presentation/layout enough to warrant phone sign-off.

At minimum verify:

- new special marks remain legible at phone density;
- ECHOFALL masking remains readable;
- no battle-layout overflow;
- Boss Attack chooser fits;
- clean device log.

If no phone-sensitive geometry changes and tablet emulation plus prior S25 proof remains valid, the agent may recommend carrying forward some device proof, but must state the reasoning rather than silently skipping the target device.

---

# 19. Presentation constraints

This is not the initial art-direction pass.

Do not redesign the overall battle interface around these Bosses.

Use the existing production graphics/text systems.

New Boss states should be visually clear with provisional assets and existing styling.

Do not build:

- particles;
- shaders;
- bespoke VFX framework;
- animation-authoring jig;
- audio;
- final Boss art;
- final special-effect treatment.

The live skin switcher remains the current mechanism for comparing static art directions.

---

# 20. Explicitly out of scope

Beta 0.4.0 does **not** include:

- additional Hackers;
- additional Decks;
- additional ordinary Systems beyond support needed for these Bosses;
- additional HOSTs;
- additional UPGRADEs;
- Boss-specific Program rosters beyond the shared ODANSHAY set;
- manual DISABLER targeting (AN-001) unless separately authorized;
- save-system expansion;
- desktop target work;
- graphics-development jig;
- audio/VFX systems;
- configurable/data-driven Boss-passive DSL;
- balancing these Bosses to final difficulty;
- final art direction.

This pass proves mechanics and supportability first.

---

# 21. Implementation guidance

A reasonable sequence is:

### Phase A — ingest and audit

- read current lessons learned before changing code;
- import the supplied workbook;
- confirm current Boss/Function/runtime shape;
- identify the smallest Boss-state additions required;
- identify whether NEHBOCYET needs a shared post-settle hook.

There is no formal approval gate.

If inspection exposes a gameplay ambiguity that would materially change one of the rules above, stop and ask. Architecture refinements that preserve these rules are delegated.

### Phase B — content/workbook

- populate shared Boss Program sets;
- add required text rows;
- export/check workbook;
- update runtime content fixtures/fingerprint expectations as appropriate.

### Phase C — Boss-special primitives

- add CAPACITOR and LOGIC_BOMB identities;
- add provisional graphics to every installed pack;
- update authoring-bundle SPEC/checks;
- verify save serialization of new overlays.

### Phase D — RAHNDAHL

Implement and test the exponential start-turn sequence and placement.

### Phase E — NEHBOCYET

Implement and test row removal, board-settle integration, LOGIC BOMB placement, trigger, carrier removal, and chain stabilization.

### Phase F — ECHOFALL

Implement and test Boss-phase cadence, deterministic axis selection, persistent concealment state, renderer masking, valid/invalid move handling, and BRAINSCRAMBLE.

### Phase G — Boss Attack

Add the title entry, Boss chooser, default build construction, result routing, and text content.

### Phase H — regression/device

Run proportional automated gates and direct manual Boss tests.

### Phase I — closeout

Update:

- README;
- decisions;
- architect notes;
- lessons learned;
- any content-authoring documentation affected by new Boss special types.

Commit, push, and leave a clean working tree.

---

# 22. Required handback

Produce:

`1c38r34kr-beta-0.4.0-boss-content-handback.md`

Include:

1. verdict against this authorization;
2. exact Boss roster/content shipped;
3. final architecture used for Boss-specific rules;
4. any reusable hooks/helpers that emerged and why they were extracted;
5. final CAPACITOR semantics;
6. final LOGIC BOMB semantics;
7. final ECHOFALL state representation;
8. Boss Attack flow/default build;
9. workbook/text/graphics changes;
10. test counts and named Boss-specific coverage;
11. fast parity result;
12. whether DEEPSCAN was rerun and why;
13. tablet results;
14. S25 results or explicit carried-forward rationale;
15. defects found during implementation;
16. decisions added;
17. architect notes added/resolved;
18. lessons learned appended;
19. deferred balance/art questions.

---

# 23. Completion standard

Beta 0.4.0 is complete when:

1. BOS_01–BOS_04 all load as valid Boss content.
2. All four have BASE_ICE 350.
3. BOS_02–04 use the ODANSHAY Program set for this phase.
4. ODANSHAY behavior remains correct.
5. RAHNDAHL start-turn exponential damage is implemented.
6. RAHNDAHL Shield interaction is ordinary damage behavior.
7. CAPACITOR placement priority/overwrite/fizzle behavior is correct.
8. CAPACITOR has explicit board-state identity and readable provisional art.
9. NEHBOCYET bottom-row removal is implemented with no removal damage or charge.
10. NEHBOCYET board refill uses the ordinary resolution path.
11. LOGIC BOMB placement priority is correct.
12. LOGIC BOMB triggers from the generic completed-movement invariant.
13. Trigger removes the entire carrier Packet.
14. Carrier removal grants no charge and deals no removal damage.
15. FNC_021 fires once per triggered LOGIC BOMB.
16. LOGIC BOMB chain movement resolves to a stable board.
17. LOGIC BOMB has explicit board-state identity and readable provisional art.
18. ECHOFALL concealment triggers on Boss phases 1,3,5...
19. ECHOFALL chooses hidden axis randomly through deterministic battle RNG.
20. Concealment changes presentation without mutating Packet identity.
21. Valid concealed move reveals and resolves normally.
22. First invalid concealed move fires FNC_022, reveals, and allows retry if alive.
23. Later invalid attempts after reveal do not repeat the punishment.
24. ECHOFALL concealment survives same-build save/resume correctly.
25. FNC_021 and FNC_022 resolve through ordinary Function/effect infrastructure.
26. New Boss support Functions are not treated as charged Program Functions.
27. Boss Attack exists on the title flow.
28. Boss Attack lists all Bosses from content.
29. Boss Attack uses HAK_01 + DEK_01 + HST_01 + no UPGRADEs.
30. Boss Attack reuses the canonical default active Hacker build.
31. Boss Attack uses authored Boss ICE without Run ladder modifiers.
32. Boss Attack replay/new-battle navigation behaves as specified.
33. Required player-facing strings use the text-content framework.
34. Required content changes exist in the authoritative workbook/export path.
35. Workbook round-trip check is clean.
36. Every installed graphics pack remains complete.
37. Asset/import checks are clean.
38. Full maintained headless suite is green with no unexplained errors.
39. Fast ordinary parity remains green.
40. DEEPSCAN is rerun if shared gameplay core changes require it, otherwise its omission is explicitly justified.
41. Each Boss is manually exercised through Boss Attack on the tablet.
42. Phone-sensitive presentation is signed off or valid prior proof is explicitly carried forward.
43. No unrequested Boss DSL/configuration framework was introduced.
44. Gameplay outside the authorized Boss changes remains stable.
45. project records and lessons learned are updated.
46. intended work is committed and pushed.
47. working tree is clean.

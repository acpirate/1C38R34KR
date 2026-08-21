# 1C38R34KR Beta 0.1.0 — Build Authorization and Architect Clarification

**Build identity:** `beta-0.1.0`  
**Purpose:** Final architect authorization layered on top of the existing Beta 0.1 framework.  
**Primary target:** Standalone Android build on physical hardware.  
**Engine:** Godot 4.7.2, standard/non-Mono.  
**Language:** GDScript.

---

## 0. Authority and relationship to the existing framework

This document does **not** replace `staging/1c38r34kr-beta-0.1.0-architect-handoff.md`.

Use this precedence:

1. **This document** for the clarifications and adjustments below.
2. `staging/1c38r34kr-beta-0.1.0-architect-handoff.md` for the full Beta 0.1 scope, architecture, module map, porting rules, and verification plan.
3. `staging/decisions.md` for accepted project decisions and rationale.
4. `CLAUDE.md` for repository/environment facts and operating rules.
5. The completed Alpha repository at `C:\Users\chode\breach` as the behavioral specification, using the source priority already defined by the framework.

Where this document conflicts with the earlier Beta 0.1 framework, **this document governs**.

The coding agent is authorized to proceed directly with implementation. Do not stop for another architecture pass unless inspection reveals a genuine contradiction, impossible requirement, or behavior that cannot be resolved from the authorities above.

---

## 1. Build objective

Beta 0.1 is a **behavioral port of the completed Alpha battle engine**, not a redesign of gameplay.

The build succeeds when one complete Constructed Quick Match can be played on a physical Android phone using the Godot implementation, while the ported logic proves parity with the Alpha through deterministic differential testing.

The presentation is intentionally a whitebox. The primary risk in this build is rules-port fidelity, not visual polish.

---

## 2. Beta 0.1 player flow

The Beta 0.1 playable flow is:

`Title → System Selection → HOST Selection → Build → Battle → Result`

There is no Run flow in this build.

There is no player-facing Hacker Selection, Deck Selection, Boss Selection, Path Choice, UPGRADE selection, or Random Quick Match.

### 2.1 Hacker and Deck are explicitly pinned

Beta 0.1 Constructed Quick Match uses:

- Hacker: `HAK_01`
- Deck: `DEK_01`

Do not select these by first row, row count, display name, or file order.

They are resolved by stable ID.

If either required ID is missing or invalid, startup/content validation must fail rather than silently choosing another row.

The HAK and DEK datasets remain fully parsed and validated. This pin is only a Beta 0.1 flow decision; it does not restrict later builds from adding full Hacker/Deck selection.

### 2.2 System and HOST remain deliberate selections

Constructed Quick Match continues to allow deliberate System and HOST selection using valid authored content.

Respect `in_pool` semantics where relevant to random-selection logic, but the Constructed selector may expose valid authored content according to the Alpha behavior being ported.

---

## 3. Settings behavior in Beta 0.1

The **battle settings model ports in full**, including `DEFAULT_BATTLE_SETTINGS` and every setting needed by the differential harness.

The **player-facing Settings screen is deferred**.

For the playable Beta 0.1 Quick Match:

- use the canonical Alpha default battle settings exactly;
- do not add a Settings menu merely to expose alternate test modes;
- headless tools/tests may override settings directly;
- debug tooling may expose a setting only if it materially reduces verification effort, but this must not become a substitute player-facing Settings UI.

This avoids rebuilding peripheral UI before the battle port is verified.

The canonical default values must come from the current Alpha source. Do not restate or independently redefine them in Godot.

---

## 4. Save format adjustment

Beta 0.1 uses a new Godot save format:

- location: `user://save.json`
- schema: `1`
- Alpha saves: unsupported
- migration from Alpha: explicitly out of scope

The Godot JSON does **not** need to structurally match the Alpha save JSON.

Port the **save semantics**, not the TypeScript representation.

Required semantic state includes whatever is necessary to resume the exact active battle, including:

- stable content identity IDs;
- content fingerprint;
- selected System and HOST;
- pinned Hacker and Deck IDs;
- active Build and order;
- board state;
- special/countdown overlay state and stamped delayed-effect parameters;
- Program/Deck charge state;
- current combat state and phase;
- current LINK/ICE;
- battle settings;
- gameplay RNG state;
- metrics/logging state required for consistent continuation;
- pending result state where applicable.

Reject incompatible or invalid saves cleanly. Do not silently repair stale identities, substitute content, or reseed gameplay RNG.

The representation may be idiomatic GDScript/Godot JSON as long as round-trip behavior is faithful.

---

## 5. Logging-level defaults

Preserve the three existing logging levels:

- `BASIC`
- `VERBOSE`
- `COMPLETE`

Use these defaults:

- **debug/development builds:** `VERBOSE`
- **release builds:** `BASIC`
- **COMPLETE:** explicit diagnostic opt-in only

Do not make COMPLETE the default.

The Beta filesystem means Alpha's localStorage quota strategy need not be copied literally, but logs must remain bounded and the event-sourced architecture must remain intact.

---

## 6. Differential verification gate — clarified workload

The differential harness is a hard release gate for Beta 0.1.

The comparison must use the exact Alpha mulberry32 RNG sequence, identical authored content/fingerprint, identical battle identity, and normalized ordered event traces.

### 6.1 Required matrix

At default settings:

- **200 consecutive seeds for every valid authored `SYS × HST` pairing.**

For each of these setting variations:

- `reinforcedConnection = on`
- `enemyMatching = off`
- `maxCascadeSteps = unset` / the Alpha-equivalent unrestricted configuration

run:

- **50 consecutive seeds for every valid authored `SYS × HST` pairing per variation.**

This requirement is intentionally large. The first engine rewrite is the point where exhaustive parity is most valuable.

### 6.2 Execution efficiency

Do **not** pay process-launch overhead for every individual battle.

The comparison tooling should batch many seeds/pairings in-process wherever practical:

- Alpha process loads content once, then emits multiple traces.
- Godot headless process loads content once, then emits multiple traces.
- Comparator reports the first divergence with enough identity data to reproduce it directly.

A failure should identify at minimum:

- System ID;
- HOST ID;
- seed;
- setting variant;
- first differing trace record/event.

Do not reduce the verification matrix merely because a naïve one-process-per-battle implementation is slow.

### 6.3 Trace fidelity

The differential gate compares **behavior**, not GDScript implementation style.

Representational normalization is allowed only where already specified in the framework: sorted keys, enum/string boundary normalization, Vector2i → `{x,y}`, deterministic float formatting, omission of fields absent in Alpha, and removal of non-deterministic wall-clock data.

Do not normalize away gameplay-relevant differences.

---

## 7. Alpha trace instrumentation

The previously approved Alpha trace entry point remains authorized.

Constraints remain:

- add instrumentation only;
- no Alpha gameplay-rule changes;
- use the existing public battle/event APIs;
- existing Alpha tests must pass unchanged;
- commit the trace instrument separately in the Alpha repository;
- this remains the sole standing exception to the Alpha repo's read-only status.

If further Alpha modification appears necessary, stop and escalate rather than expanding the exception.

---

## 8. Logic architecture remains mandatory

The Beta logic layer must remain independent of the Godot scene tree.

`scripts/logic/`:

- uses plain `RefCounted`/data classes and static logic;
- must not depend on `Node`, `SceneTree`, rendering, Tween, input, display APIs, or UI state;
- resolves gameplay completely before presentation playback;
- emits ordered events that scenes consume.

The framework's layer-purity test remains required.

The presentation may be rewritten freely without modifying gameplay rules.

---

## 9. Presentation guidance

Beta 0.1 is a whitebox.

Do not spend significant implementation time reproducing Alpha rendering.

Required:

- 8×8 board legible at phone size;
- all six colors and shapes distinguishable;
- overlays/countdowns legible;
- LINK/ICE, Program charge, active Functions, targeting state, and turn state understandable;
- touch controls functional;
- event playback understandable enough to diagnose rule/playback mismatches;
- layout respects Android safe area.

Use Godot-native controls and drawing primitives wherever cheaper.

### 9.1 Presentation registry requirement

Keep one centralized mapping from frozen gameplay Color/Shape identities to their visual representation.

The exact internal representation (`Callable`, resource, enum-indexed object, etc.) is left to the coding agent.

The architectural requirement is:

- one clear enum/token → presentation mapping;
- no scattered gameplay-color or shape identity assumptions throughout scenes;
- future replacement by art assets must not require logic changes.

Do not treat the earlier illustrative `Array[Callable]` form as mandatory if another Godot-native representation is cleaner.

---

## 10. Diagnostics

The diagnostic tooling already approved in the framework remains in scope:

- active seed display/entry;
- restart with same seed;
- force win;
- force lose;
- grant full charge;
- event-log overlay;
- playback speed/skip control.

Diagnostics must:

- be debug-build-only;
- call ordinary logic APIs rather than mutating state behind the rules layer;
- support reproduction of observed phone behavior in the headless harness.

Do not expand Beta 0.1 into a general-purpose board editor or content editor.

---

## 11. Content pipeline

All ten current CSV datasets remain present, parsed, reference-resolved, validated, and fingerprinted even if Beta 0.1 does not route into every gameplay layer.

Preserve:

- raw CSV files in exported builds;
- `importer="keep"` behavior;
- export include rules;
- leading spreadsheet-apostrophe normalization;
- startup error/warning aggregation;
- blocking startup on errors;
- no silent repair or content fallback.

`BOS` and `UPG` content remain validated even though Boss and Run UPGRADE gameplay are deferred.

---

## 12. Scope boundaries reaffirmed

Beta 0.1 does **not** implement:

- New Run;
- route/path selection;
- Run persistence;
- UPGRADE acquisition/progression;
- Boss combat;
- ODANSHAY/Override mechanics;
- Random Quick Match;
- Windows deployment;
- hosted browser deployment;
- iOS deployment;
- permanent progression;
- production art/audio;
- broad visual redesign beyond the required whitebox;
- balance changes.

Do not use the port as an opportunity to clean up gameplay rules.

Any Alpha rule that appears odd but passes the parity gate remains the rule for Beta 0.1.

---

## 13. Android acceptance target

Primary device remains the configured physical Android test device.

Required device verification from the framework remains in force, including:

- complete touch-played victory;
- complete touch-played defeat;
- authored Systems/Hosts exercised;
- invalid swap/revert;
- Function target/cancel;
- Bomb countdown/detonation;
- EBUFF countdown → Buff;
- visible cascades;
- save/quit/resume;
- safe-area/cutout correctness;
- clean Godot log output.

Real-device behavior is authoritative for touch feel.

A screenshot is useful evidence but does not substitute for interactive checks.

---

## 14. Build sequencing

Use the existing phase order:

1. Foundation / types / constants / exact RNG.
2. Content loading, validation, fingerprint.
3. Battle core.
4. Differential harness and parity repair.
5. Whitebox presentation and touch.
6. Save/logging/metrics/integration.
7. Full headless + differential + device gate.
8. README, diff review, commit, push.

Do not postpone the differential harness until after presentation. It is a core implementation tool, not only a final test.

---

## 15. Completion standard

Beta 0.1 is complete only when:

1. Exact RNG test vectors pass.
2. All required content loads and validates correctly.
3. Content fingerprint matches the Alpha for identical normalized content.
4. Headless logic tests pass.
5. The full differential matrix in §6 passes with no unexplained divergence.
6. Constructed Quick Match works as `System → HOST → Build → Battle → Result`.
7. `HAK_01` and `DEK_01` are explicitly resolved by stable ID.
8. Active-battle save/resume preserves deterministic continuation.
9. Debug logging defaults to VERBOSE; release defaults to BASIC.
10. A playable debug APK is installed and verified on physical Android hardware.
11. The required touch/device checks are honestly completed and reported.
12. No deferred Beta 0.2+ feature is added merely for completeness.
13. README is updated to describe the actual shipped Beta 0.1 implementation.
14. Final diff is reviewed.
15. All intended changes are committed and pushed to `origin/main`.
16. Working tree is clean.

If any gate is incomplete, report Beta 0.1 as partial rather than weakening the gate.

---

## 16. Agent reporting requirements

The final report should include:

- implementation summary;
- Alpha modules translated and any deliberate module-boundary deviations;
- exact content fingerprint result;
- headless test result/count;
- differential matrix totals and any divergences encountered/fixed;
- Android APK build result and size;
- device model/OS actually tested;
- manual checks actually performed;
- manual checks not performed;
- save/resume result;
- log/runtime warnings;
- any GDScript/Godot semantic difference that required a non-literal translation;
- any Alpha-source discrepancy discovered during porting;
- final commit hash;
- push result;
- clean/dirty working-tree status.

Do not hide resolved differential failures. Briefly report meaningful parity bugs found during the port because they are useful evidence that the verification architecture is doing its job.

---

## 17. Architect authorization

The existing Beta 0.1 framework is approved with the clarifications in this document.

Proceed with implementation.

The governing principle for this build is:

> **Port the rules faithfully, prove parity mechanically, and spend only enough presentation effort to make the result usable on the Android device.**

Beta 0.1 is the foundation for the rest of the production-oriented Godot line. Correctness and testability take precedence over elegance, polish, or feature breadth.

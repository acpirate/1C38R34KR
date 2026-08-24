# 1C38R34KR Beta 0.2.0 — Run/Progression Port Build Authorization

**Build identity:** `beta-0.2.0`  
**Purpose:** Second Godot port phase, layered on top of the completed Beta 0.1 battle port.  
**Primary target:** Standalone Android.  
**Engine:** Godot 4.7.2, standard/non-Mono.  
**Language:** GDScript.  
**Status:** Authorized for implementation.

---

## 0. Authority and source precedence

This document is the build authorization for Beta 0.2.0.

Use sources in this order:

1. **This document** for Beta 0.2 scope, architecture, implementation order, and verification.
2. The shipped Beta 0.1 repository and its current `README.md`, `CLAUDE.md`, `decisions.md`, `port-notes.md`, and tests for the Godot architecture actually in production.
3. The completed Alpha repository at `C:\Users\chode\breach` as the behavioral oracle for Run, route, UPGRADE, Random Quick Match, save-state, logging, and metrics behavior being ported.
4. Alpha 0.7.0 requirements/handoff for the latest resolved lifecycle rules.
5. Earlier Alpha handoffs only where behavior was introduced there and later preserved.
6. The current CSV datasets in the Beta repo for authored content.

Where Alpha prose and Alpha source disagree, the **Alpha source wins** and the discrepancy must be reported.

Where this document conflicts with the earlier Beta 0.1 handoff, this document governs for Beta 0.2.

Do not redesign gameplay during this port phase. Deferred design changes remain deferred unless explicitly authorized here.

---

## 1. Build objective

Beta 0.2 ports the remaining **non-Boss Alpha gameplay loop** into Godot.

The completed Beta 0.1 battle engine remains the foundation and must not be reimplemented.

Beta 0.2 adds:

- New Run setup and four-battle Run flow;
- Boss selection at New Run start, persisted for the Run but not yet used in combat;
- Hacker and Deck selection;
- Path Choice;
- route RNG and deterministic route generation;
- UPGRADE acquisition and persistence;
- Run-local Build flow before every battle;
- normal Battles 1–3;
- a **temporary non-Boss Battle 4 compatibility mode** only if required to reproduce the Alpha pre-Boss session flow cleanly; otherwise stop Run completion before Boss combat and mark Boss battle entry as deferred;
- Random Quick Match;
- Run-scoped save/resume;
- Run/route/UPGRADE logging and metrics;
- Android presentation for the new screens and transitions.

The purpose is to reproduce the Alpha's Run/progression layers on top of the already-verified battle engine, leaving the Boss combat layer for Beta 0.3.

---

## 2. Guiding principle

**Port layers, not behaviors twice.**

Beta 0.1 proved the battle engine against Alpha with DEEPSCAN. Beta 0.2 must reuse it unchanged wherever possible.

Any Beta 0.2 code that duplicates battle resolution, PASSIVE application, HOST behavior, charge routing, Function execution, save serialization of battle internals, metrics collection, or event playback is presumptively wrong.

The new work belongs primarily in:

- app/session orchestration;
- Run state;
- route generation;
- setup screens;
- UPGRADE state;
- Run save envelope;
- Run/selection logging;
- Random Quick Match setup.

---

## 3. Scope

### 3.1 In scope

1. New Run flow.
2. Boss selection as a Run setup choice and persistent identity only.
3. Hacker selection.
4. Deck selection.
5. Initial Path Choice.
6. Path Choice after Battles 1, 2, and 3.
7. Run-local UPGRADE acquisition.
8. Run-local UPGRADE persistence and PASSIVE contribution.
9. Run-local Build before every battle.
10. Fixed Intro encounter rules.
11. Escalation encounter rules.
12. Route RNG isolated from gameplay RNG.
13. Pending route offers persisted verbatim.
14. Random Quick Match.
15. Run save/resume across all Beta 0.2 states.
16. Run/route/selection/UPGRADE logging and metrics.
17. Android whitebox UI for the new flow.
18. Representative Alpha-vs-Beta verification for newly ported non-Boss behavior, focused on externally meaningful semantics rather than exhaustive internal equivalence.
19. Existing Beta 0.1 Constructed Quick Match remains intact.

### 3.2 Explicitly out of scope

Deferred to Beta 0.3:

- Boss combat;
- Boss Program execution;
- ODANSHAY Override placement;
- Boss threshold mechanics;
- CODESHATTER;
- REBOOT;
- DATABEND;
- Boss-specific combat save state;
- Boss-specific battle metrics beyond setup identity already carried in the Run.

Still deferred:

- permanent account progression;
- completion matrix/high scores;
- production art/audio;
- broad balance work;
- Windows/web/iOS deployment;
- package-ID finalization;
- permanent release signing identity;
- JSON/XML content migration;
- in-game content editor;
- schema-aware authoring tools.

### 3.3 Deferred design notes remain deferred

Do **not** implement in this port build:

- manual player targeting for DISABLER/Drain;
- scroll-feel redesign;
- stale-force-close save UX redesign/autosave policy.

Those are design/polish changes, not Alpha-replication work.

---

## 4. New Run lifecycle

Port the Alpha Run setup order exactly as shipped at Alpha completion:

`New Run → Boss Selection → Hacker Selection → Deck Selection → Path Choice → Build → Battle`

For Battles 2–4:

`Path Choice → Build → Battle`

The selected Boss is known from Run start and persists for the whole Run.

The Boss choice is present now because it is part of the Alpha gameplay loop and save/session structure even though Boss combat itself arrives in Beta 0.3.

### 4.1 New-Run commitment boundary

Committing the Boss selection is the destructive New-Run boundary.

At Boss commit:

- replace any prior Run save;
- create the new Run state;
- persist the selected Boss ID immediately;
- advance to Hacker Selection.

Committed setup progress must be preserved.

At minimum:

- a committed Boss selection must survive restart;
- a committed Hacker selection must survive restart;
- a committed Deck selection must survive restart;
- generated Path offers must survive restart without rerolling.

Exact return to the same intermediate UI screen is not itself a completion requirement. Returning to the last committed boundary is acceptable if doing so preserves committed choices and does not permit route rerolls or duplicate rewards.

Do not require a fully populated battle identity before setup persistence is possible.

Setup-state persistence and active-battle persistence are separate valid Run states.

---

## 5. Boss selection in Beta 0.2

Boss Selection is a normal player-facing setup screen.

Required:

- show all valid Boss rows;
- select exactly one;
- commit by stable `BOS_ID`;
- persist immediately;
- include in Run content compatibility;
- log available Boss IDs and selected Boss ID;
- show selected Boss identity in later Run context where the Alpha does.

Do not execute Boss mechanics in Beta 0.2.

When the Run reaches the point where Alpha would enter the Boss battle, Beta 0.2 must follow §12 rather than silently substitute a normal System.

---

## 6. Hacker and Deck selection

Port the Alpha selection behavior and confirmation flow.

Use stable IDs.

Selection screens must:

- show valid authored rows;
- support select-then-confirm;
- preserve selection across resume;
- never infer identity by file order;
- validate persisted IDs before accepting a save.

Beta 0.1's hard pin to `HAK_01` / `DEK_01` applies only to Constructed Quick Match and must not leak into Run setup.

---

## 7. Path Choice model

A Path Choice commits an encounter package.

Normal path contents:

- opponent identity;
- HOST;
- UPGRADE.

For Battles 1–3, opponent identity is System.

For the final route, opponent identity is the selected Boss, but Boss combat is deferred to Beta 0.3.

Generated path choices are state, not a view.

When generated:

- persist the exact offered choices immediately;
- persist route RNG state;
- reloading must never regenerate or reorder the offers;
- selecting a path commits exactly the shown package.

---

## 8. Initial Path Choice

Battle 1 uses the fixed Intro route convention:

- System = `DOORMAN`;
- HOST = `THRESHOLD`;
- two UPGRADE choices when the eligible pool permits;
- the two offered UPGRADEs are distinct whenever possible.

The player chooses the UPGRADE **before** Build.

Selecting the path:

1. acquires the selected UPGRADE;
2. activates its PASSIVEs immediately;
3. commits DOORMAN + THRESHOLD;
4. advances to Build;
5. Battle 1 starts only after Build confirmation.

The newly acquired UPGRADE therefore affects Battle 1.

---

## 9. Battles 2 and 3 route generation

After winning Battle 1 and again after winning Battle 2:

- generate two valid route options;
- each has a random valid System;
- each has a random valid HOST;
- each has an eligible UPGRADE.

Preserve Alpha rules:

- route/system/HOST selection uses route/setup RNG, not gameplay RNG;
- `in_pool` is authoritative;
- intro-only content is not randomly selected;
- avoid identical `SYS + HST` combinations when another combination is available;
- acquired UPGRADEs are removed from the eligible pool;
- UPGRADE offers are distinct where possible;
- exact offers persist across reload.

Program order, System build, System ICE, HOST PASSIVEs, UPGRADE PASSIVEs, and battle mechanics are resolved through the existing Beta 0.1 battle engine.

---

## 10. UPGRADE semantics

Port Alpha UPGRADE behavior exactly.

- UPGRADEs are Run-local.
- UPGRADEs are always Hacker-owned.
- An acquired UPGRADE applies immediately to the battle on the selected path.
- It remains active for all subsequent battles in the Run.
- The same `UPGRADE_ID` may never be acquired twice.
- Multiple PASSIVEs on one UPGRADE all apply.
- Duplicate PASSIVE IDs from different sources stack by source.
- UPGRADE acquisition order is preserved.

The current authored pool intentionally contains four UPGRADEs for four Run acquisition decisions.

Preserve the exhaustion edge case:

- by the last route screen, only one unacquired UPGRADE may remain;
- both offered paths may therefore show that same remaining UPGRADE;
- selecting either acquires it once.

Startup validation must still require at least four valid UPGRADE rows.

---

## 11. Run Build behavior

Before every Run battle, show Build.

Build uses:

- selected Hacker portfolio;
- selected Deck portfolio;
- existing inventory/build validity rules;
- four distinct active Programs;
- current Run Build as the starting selection where Alpha does;
- current encounter context visible before confirmation.

The selected encounter and newly acquired UPGRADE must be known before Build.

Build changes:

- carry forward during the same Run according to Alpha behavior;
- survive save/resume;
- same-battle retry preserves the current Build;
- full Run restart begins from the appropriate default Build.

Do not share Constructed Quick Match remembered Build state with Run Build state.

---

## 12. Battle 4 boundary for Beta 0.2

Beta 0.2 must port the **final route-choice state** without implementing Boss combat.

After winning Battle 3:

- show the normal two-path final route UI;
- both routes reference the already-selected Boss;
- each route carries a randomized valid HOST;
- each route carries the eligible UPGRADE under the existing exhaustion rules;
- avoid identical `Boss + HST` route pairs where another HOST is available;
- selecting a route acquires the UPGRADE and commits the HOST;
- persist the exact committed Boss + HOST + UPGRADE package.

### 12.1 Stop point

After the final path is selected and its Build is confirmed, Beta 0.2 should enter a clearly identified **`PENDING_BOSS_BATTLE`** state rather than substituting a System or fabricating Boss combat.

Player-facing behavior may be a minimal whitebox message such as:

`Boss battle port continues in Beta 0.3`

with options to return to Title and preserve the Run.

This state exists to prove that the complete pre-Boss Alpha Run loop has been ported and persisted correctly.

Beta 0.3 will consume this state and enter the actual Boss battle.

Do not mark the Run complete in Beta 0.2.

---

## 13. Normal encounter ICE

Preserve Alpha normal-Run System ICE:

- Battle 1: `BASE_ICE + 0`
- Battle 2: `BASE_ICE + 50`
- Battle 3: `BASE_ICE + 100`

Do not fabricate a Battle-4 System ICE because Battle 4 is Boss-owned.

Boss ICE remains a Beta 0.3 concern.

---

## 14. Random Quick Match

Port Alpha Random Quick Match in Beta 0.2.

Random Quick Match:

- uses valid random System selection;
- uses valid random HOST selection;
- uses a valid random Build;
- uses setup RNG isolated from gameplay RNG;
- does not overwrite Constructed Quick Match remembered Build;
- does not acquire UPGRADEs;
- does not involve Boss selection;
- produces an ordinary standalone battle;
- uses Beta 0.1 battle settings/defaults and battle engine.

The random selection result must be logged/persisted where Alpha does.

Constructed Quick Match remains unchanged.

---

## 15. Run state model

Extend the Beta save/session architecture to represent at least:

- Run ID/identity as needed by existing logging;
- selected Boss ID;
- selected Hacker ID;
- selected Deck ID;
- setup phase;
- current battle number;
- acquired UPGRADE IDs in acquisition order;
- pending route offers;
- route RNG state;
- committed opponent identity;
- committed HOST;
- committed UPGRADE;
- current Run Build/order;
- active battle state when inside a battle;
- pending result state;
- retry state where Alpha has one;
- `PENDING_BOSS_BATTLE`;
- content fingerprint;
- schema/version.

Do not store copied immutable definitions where stable IDs suffice.

Resolve content from IDs against the current validated content set.

Reject incompatible state cleanly.

---

## 16. Save/resume cost policy for Beta 0.2

The project has already learned that proof-heavy save requirements can consume disproportionate effort.

The value of Run persistence in this phase is to preserve committed progress and route integrity, not to prove that every possible UI interruption resumes at the identical frame or screen.

Therefore:

- reuse the Beta 0.1 battle serializer and its existing deterministic-continuation proof;
- add only the new Run/setup/route fields needed by Beta 0.2;
- preserve committed Boss/Hacker/Deck choices, acquired UPGRADEs, current Run Build, battle number, and committed encounter state;
- persist generated route offers exactly so restarting cannot reroll them;
- returning to the last committed setup boundary is acceptable when an uncommitted chooser screen was open;
- do not create a second exhaustive save-proof program for every Run screen;
- one or a small number of representative interrupted-Run continuation tests are sufficient;
- do not multiply DEEPSCAN or other broad matrices by save interruption points.

Correctness remains required; the proof burden is deliberately bounded to the gameplay value of the feature.

Autosave-on-force-close remains out of scope.

---

## 17. Route RNG

Preserve the Alpha's externally meaningful route/setup RNG semantics.

Hard requirements:

- route RNG is distinct from gameplay RNG;
- generating/reviewing route choices does not advance gameplay RNG;
- reopening persisted route offers consumes no new route RNG;
- selecting one path does not reroll the other;
- Random Quick Match setup RNG remains isolated from gameplay RNG;
- fixed setup seeds remain deterministic within the Beta implementation.

Exact internal RNG-state equality with Alpha at every transition is not a release requirement unless needed to explain an observed behavioral mismatch.

Use a small set of fixed-seed Alpha comparisons to confirm the same broad selection behavior and ordering assumptions where practical. Do not build a second exhaustive parity system solely to prove route-RNG state identity.

---

## 18. PASSIVE integration

Do not create a Run-specific PASSIVE system.

Use the existing Beta 0.1 PASSIVE runtime.

For a Run battle, active PASSIVE instances are assembled from:

- selected Hacker;
- selected System for normal battles;
- selected HOST;
- acquired UPGRADEs.

Boss PASSIVEs remain deferred until Beta 0.3.

UPGRADE PASSIVEs must carry correct source attribution:

- `sourceKind = UPGRADE`;
- source ID = acquired `UPGRADE_ID`;
- owner = Hacker/player.

Existing stacking and arithmetic remain unchanged.

---

## 19. Logging and metrics

Preserve enough structured observability to diagnose Beta 0.2 Run generation, selections, acquisitions, and transitions.

Exact Alpha selection/menu log-schema parity is not required unless an existing analysis tool depends on it.

Required new/activated logging should cover:

- Boss selection;
- Hacker selection;
- Deck selection;
- Run creation;
- route generation;
- offered path contents;
- route selection;
- selected System;
- selected HOST;
- selected UPGRADE;
- UPGRADE acquisition;
- acquired-UPGRADE list;
- Random Quick Match setup selection;
- Run battle number;
- Run transition/result state;
- final `PENDING_BOSS_BATTLE` package.

Preserve:

- BASIC / VERBOSE / COMPLETE semantics;
- debug=VERBOSE;
- release=BASIC;
- event-sourced battle metrics;
- one event funnel;
- source attribution.

Prefer compact records that answer development and analysis questions over faithfully reproducing Alpha menu-log shapes that have no consumer.

Do not add a second instrumentation pipeline.

Boss-combat-specific events remain Beta 0.3.

---

## 20. Presentation

The Beta 0.1 whitebox/UI architecture remains the base.

Add only the screens necessary for this phase:

- Boss Selection;
- Hacker Selection;
- Deck Selection;
- Path Choice;
- Run context on Build;
- Run transition/result handling;
- `PENDING_BOSS_BATTLE` placeholder;
- Random Quick Match entry as needed.

### 20.1 Safe-area adjustment

This build adds several new top-level screens, so move safe-area handling to a shared/root layout policy rather than relying on battle-screen-only protection.

Requirements:

- query runtime safe area;
- apply it consistently to all mobile screens;
- do not hardcode device insets;
- preserve the existing battle behavior;
- screen-specific opt-out requires an explicit reason.

### 20.2 Touch/scroll behavior

Use the current working scroll solution.

Do not spend Beta 0.2 time redesigning scroll feel.

New selection screens must use select-then-confirm and remain operable on both the tablet and phone.

---

## 21. Port-verification strategy

Beta 0.2 adds orchestration/state behavior around an already-proven battle engine.

The verification goal is to catch meaningful port drift without re-proving Beta 0.1 from scratch.

### 21.1 Battle parity regression

Required on every Beta 0.2 build:

- all headless tests;
- fast parity on ordinary battle behavior during development and before release.

Run DEEPSCAN only when warranted, including when:

- battle logic changes;
- gameplay RNG changes;
- PASSIVE resolution changes;
- content normalization/fingerprinting changes;
- another battle-affecting subsystem changes;
- fast parity diverges;
- integration work gives reasonable cause to suspect battle behavior was perturbed.

If Beta 0.2 changes only Run/session/UI orchestration around an untouched battle core and fast parity remains green, a fresh 5,250-battle DEEPSCAN is optional rather than mandatory.

The prior Beta 0.1 DEEPSCAN result remains evidence for the unchanged battle engine.

### 21.2 New Run/session verification

Use representative semantic fixtures, not a second exhaustive differential system.

For a small fixed set of setup seeds and player choices, compare Alpha and Beta behavior covering:

- initial route generation;
- one middle-route generation;
- UPGRADE acquisition and exclusion;
- the final UPGRADE-exhaustion case;
- final Boss-route construction;
- Random Quick Match setup;
- Run Build carry-forward behavior.

The important outputs are externally meaningful state:

- offered/committed identities;
- acquisition order;
- legality/in-pool behavior;
- deterministic repeatability;
- no route reroll after persistence;
- no gameplay-RNG perturbation.

Exact internal route-RNG state equality is not required unless needed to diagnose a discrepancy.

Prefer compact normalized state hashes plus rerunnable full state dumps on mismatch. Add fixtures when an actual ambiguity or defect appears rather than specifying broad combinatorial coverage in advance.

## 22. Automated behavior coverage

The following is a coverage checklist, not a requirement for 37 separate bespoke tests.

The coding agent may cover multiple items with one scenario or fixture where that is cheaper and still makes failures diagnosable. Add dedicated tests where a behavior is subtle, regression-prone, or cannot be demonstrated clearly by a broader scenario.

Ensure coverage for at least:

1. New Run opens Boss Selection first.
2. Boss commit creates/replaces Run state.
3. Resume after Boss selection returns to Hacker Selection.
4. Resume after Hacker selection returns to Deck Selection.
5. Resume after Deck selection returns to initial Path Choice.
6. Initial path uses DOORMAN + THRESHOLD.
7. Initial path offers distinct UPGRADEs when possible.
8. Selecting initial route acquires UPGRADE before Build.
9. UPGRADE applies to Battle 1.
10. Run Build validation matches Alpha.
11. Battle 1 System ICE is BASE+0.
12. Winning Battle 1 produces Battle-2 route choices.
13. Battles 2–3 use valid in-pool Systems/HOSTs.
14. Identical SYS+HST pairings are avoided when possible.
15. Acquired UPGRADE is not reoffered later.
16. UPGRADEs persist and stack across battles.
17. Battle 2 ICE is BASE+50.
18. Battle 3 ICE is BASE+100.
19. Pending route offers survive reload verbatim.
20. Route RNG survives reload.
21. Route generation does not advance gameplay RNG.
22. Same-battle retry preserves Build.
23. Final route shows selected Boss on both paths.
24. Final route uses valid random HOSTs.
25. Final one-UPGRADE exhaustion case may duplicate the remaining UPGRADE across both paths.
26. Selecting duplicate-offer route acquires UPGRADE once.
27. Final route commit persists Boss+HOST+UPG.
28. Build confirmation after final route enters PENDING_BOSS_BATTLE.
29. Beta 0.2 never substitutes a normal SYS for Boss battle.
30. Random Quick Match chooses valid SYS/HST/Build.
31. Random Quick Match setup RNG does not perturb gameplay RNG.
32. Random Quick Match does not overwrite Constructed remembered Build.
33. Invalid Run IDs/references reject cleanly.
34. Duplicate acquired UPGRADE IDs reject cleanly.
35. Existing Beta 0.1 Constructed Quick Match tests remain green.
36. Existing battle parity remains green.
37. Root safe-area policy applies to all new screens.

---

## 23. Device verification

Routine development and repeated checks use the permanently connected Galaxy Tab A.

Before release, perform one announced S25 window.

### 23.1 Tablet checks

At minimum:

- New Run setup through initial Battle 1;
- Boss/Hacker/Deck selection;
- Path Choice scrolling and confirmation;
- Build after UPGRADE acquisition;
- win Battle 1 and reach Battle-2 Path Choice;
- continue through Battle 3 using debug force-win where useful;
- final Boss route appears correctly;
- final route commit and Build reach PENDING_BOSS_BATTLE;
- save/relaunch from at least one setup screen;
- save/relaunch from a pending route screen;
- Random Quick Match works;
- no obvious multi-second UI stalls;
- scroll/tap behavior remains usable;
- clean log.

### 23.2 S25 sign-off

Batch in one device window:

- New Run flow is usable one-handed/phone-sized;
- selection screens fit and scroll correctly;
- safe area works on every new top-level screen;
- Path Choice cards are readable;
- Build remains usable after Run context additions;
- final Boss-route state is understandable;
- Random Quick Match still works;
- no horizontal overflow or unreachable controls;
- clean log.

Do not use the tablet to sign off thumb reach or phone composition.

---

## 24. Performance policy

Do not optimize speculatively.

The old tablet is the canary.

Record whether:

- route screens open promptly;
- Build remains responsive with accumulated UPGRADE context;
- battle transitions remain responsive;
- no repeated multi-second stalls appear;
- memory pressure produces no crash/reload behavior during a four-battle Run.

No hard FPS target is required in Beta 0.2.

If a regression is obvious on the tablet, fix the cause before release rather than assuming the S25 hides it.

---

## 25. Implementation order

### Phase A — Session model
Port setup phases, Run state, route RNG, UPGRADE acquisition state, and `PENDING_BOSS_BATTLE`.

### Phase B — Selection and route generation
Boss/Hacker/Deck selection, initial route, escalation routes, final Boss route, Random Quick Match setup.

### Phase C — Integration with battle engine
Run Build, battle creation from committed route state, UPGRADE PASSIVE assembly, normal ICE progression, results/transitions/retry.

### Phase D — Persistence
Extend existing schema minimally for Run/setup/route state. Add representative resume tests.

### Phase E — Run differential/state harness
Hash-first Alpha/Beta comparison of deterministic route/session state. Repair divergences.

### Phase F — Presentation
New whitebox screens, shared safe-area policy, Run context, final placeholder state.

### Phase G — Logging/metrics
Activate selection/route/UPGRADE/Run streams through existing collectors.

### Phase H — Verification
Headless suite, fast parity, Run differential fixtures, DEEPSCAN, tablet gate, S25 gate.

### Phase I — Closeout
README, decisions, port notes, architect notes, lessons learned, final diff review, commit, push.

---

## 26. Required process artifacts

Continue maintaining:

- `decisions.md` — accepted choices and rationale;
- `port-notes.md` — non-literal Alpha→Godot translations;
- `architect-notes.md` — deferred design issues;
- `lessons-learned.md` — time-traveler lessons for the project AAR.

Append lessons as they occur, not only during handback.

The coding agent may add lessons it considers useful without requesting approval for each entry.

---

## 26.1 Verification-effort policy

Beta 0.1 required unusually strong proof because it translated the core rules engine into a new language and runtime.

Beta 0.2 is different: most new work is orchestration around a battle engine that is already proven.

For this and later port phases:

- make gameplay semantics hard requirements;
- make proof strength proportional to feature importance and regression risk;
- reuse prior proof for unchanged subsystems;
- prefer representative fixtures over combinatorial matrices for menu/session orchestration;
- require exact internal equivalence only when it materially protects the vision or enables a valuable oracle;
- escalate verification after an observed defect or ambiguity rather than assuming the maximum proof burden up front.

The standard is high confidence at proportionate cost, not maximum possible verification.

## 27. Completion standard

Beta 0.2 is complete when:

1. New Run supports Boss → Hacker → Deck → Path → Build → Battles 1–3.
2. Boss identity persists for the Run.
3. UPGRADE acquisition/persistence matches Alpha.
4. Path generation/persistence matches Alpha.
5. Normal Run ICE progression matches Alpha for Battles 1–3.
6. Build-before-battle behavior matches Alpha.
7. Final route commits selected Boss + HOST + UPGRADE.
8. Final Build reaches `PENDING_BOSS_BATTLE` without fabricating Boss combat.
9. Random Quick Match matches Alpha setup behavior.
10. Existing Constructed Quick Match remains intact.
11. Existing battle tests pass.
12. Fast parity passes.
13. DEEPSCAN passes if §21.1 says the build warrants a fresh DEEPSCAN; otherwise the prior Beta 0.1 DEEPSCAN remains the baseline evidence.
14. Representative Run/session semantic fixtures pass.
15. Representative Run save/resume checks pass, with committed progress and route offers preserved.
16. Tablet device gate passes.
17. S25 phone-layout sign-off passes.
18. Logs and metrics for newly reachable systems are sufficient for diagnosis and analysis without requiring exact Alpha menu-log schema parity.
19. README describes the shipped Beta 0.2 state.
20. Decision/port/architect/lessons documents are updated.
21. Final diff is reviewed.
22. Intended changes are committed and pushed to `origin/main`.
23. Working tree is clean.

If Boss combat has been implemented, Beta 0.2 has exceeded scope and should not be called complete until that work is either removed or explicitly reauthorized.

---

## 28. Final authorization

Proceed with Beta 0.2.

The build principle is:

> **Port the Alpha Run/progression shell around the already-proven battle engine; verify the new state transitions mechanically; do not reopen battle rules or pull Boss combat forward.**

Beta 0.3 will consume the persisted final Boss-route state and port the remaining Boss encounter layer.

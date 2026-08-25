# 1C38R34KR Beta 0.3.0 — Boss Combat Port Authorization / Recommendations

**Build identity:** `beta-0.3.0`  
**Purpose:** Complete the Alpha gameplay replication in the Godot/Android line by porting the Battle-4 Boss encounter and ODANSHAY mechanics onto the completed Beta 0.2 Run shell.  
**Primary target:** Standalone Android.  
**Engine:** Godot 4.7.2, standard/non-Mono.  
**Language:** GDScript.  
**Status:** Authorized for implementation.

---

## 0. Authority and source precedence

Use sources in this order:

1. **This document** for Beta 0.3 scope, current-value corrections, verification burden, and implementation boundaries.
2. The shipped Beta 0.2 repository and its current `README.md`, `CLAUDE.md`, `decisions.md`, `port-notes.md`, `architect-notes.md`, tests, and current runtime CSVs.
3. The completed Alpha 0.7 repository as the behavioral oracle for Boss combat.
4. `breach-alpha-0.7.0-coding-agent-handoff.md` for Boss behavior that agrees with the shipped Alpha implementation and current runtime data.
5. Earlier Alpha requirements only for behavior preserved into Alpha 0.7.

If prose and source disagree, the **shipped implementation/current runtime data wins**. Record the discrepancy rather than silently following stale prose.

### 0.1 Known stale Alpha 0.7 value — do not regress it

Older Alpha 0.7 handoff text says ODANSHAY `BASE_ICE = 100`.

That is stale.

The current Beta runtime and shipped Alpha/Beta history use:

```text
BOS_01 ODANSHAY
BASE_ICE = 250
```

Beta 0.2 already displays ODANSHAY at ICE 250 on the final route.

**250 is canonical for Beta 0.3.**

Boss ICE is the authored Boss value directly. Do not add the normal Battle-4 System `+150` escalation modifier.

The important incorrect case to reject is:

```text
250 + 150 = 400
```

A test that merely compares Boss ICE to the ordinary 100-base System ladder is not discriminating, because both happen to produce 250 with current content.

### 0.2 Shipped Alpha behavior outranks older unbounded retry prose

The original Alpha handoff describes repeated DATABEND attempts until three Override targets exist or the Hacker dies.

The shipped Alpha behavior added a bounded safety cap.

Expected canonical behavior is **at most five DATABEND/retry attempts** for one end-turn placement sequence. Inspect the Alpha 0.7 source before implementing and preserve the shipped bound exactly. If repository inspection shows a different literal cap, report it and follow the shipped source.

Do not implement an unbounded loop.

---

## 1. Build objective

Beta 0.3 consumes Beta 0.2's persisted `PENDING_BOSS_BATTLE` package and completes the Run:

`final Path → Build → ODANSHAY Battle → Run Complete / Run Loss`

The build adds the distinct Boss combat identity and ODANSHAY's Override mechanic while reusing the already-proven battle engine wherever behavior is shared with a System.

This is the last gameplay-port phase needed to reproduce the completed Alpha feature skeleton.

The governing principle is:

> **Add only the Boss-specific layer. Reuse normal enemy combat wherever the semantics are already the same.**

---

## 2. Small preflight corrections carried from Beta 0.2

Before Boss integration, fix the two known shipped issues because both are small and otherwise contaminate human testing.

### 2.1 F-001 — reserve battle status space so the board does not jump

The Datastream currently shifts slightly on the first action because `_turn_label` and `_message` acquire height after the board has already been laid out.

Fix by reserving their final intended vertical space from initial battle render.

Required positive postcondition:

- the board/frame rectangle is stable from battle entry through the first and subsequent status messages;
- message text may change, but it does not resize/recenter the Datastream during ordinary play.

Do not redesign the battle layout.

### 2.2 F-002 — Quick Match must roll a fresh gameplay seed

Current Beta Quick Match defaults gameplay seed to `0` unless debug UI changes it.

Restore the Alpha behavior:

- a newly started Constructed Quick Match gets a fresh gameplay seed unless the player explicitly supplied a debug seed;
- a newly started Random Quick Match gets a fresh gameplay seed independently of its setup-selection seed;
- record the gameplay seed so the battle is reproducible;
- keep setup RNG and gameplay RNG distinct;
- **Replay this seed** reuses the exact gameplay seed **and the exact System/HOST/Build actually played**;
- the Constructed remembered Build remains independent of the Build currently in play;
- release builds must not depend on a debug-only seed field to escape a fixed seed.

Add the gameplay seed to the Quick Match session record if it is not already explicit there.

This is an Alpha-parity correction, not a new feature.

---

## 3. Explicit Beta 0.3 scope

### 3.1 In scope

1. Enter Boss combat from `PENDING_BOSS_BATTLE`.
2. Distinct `BOS` enemy identity at runtime.
3. ODANSHAY authored ICE/axes/Program set.
4. Boss use of ordinary enemy Program charge and Function plumbing.
5. Boss HOST and accumulated Hacker UPGRADE interaction.
6. Override special overlay.
7. End-of-Boss-turn Override placement.
8. DATABEND fallback.
9. Start-of-Boss-turn Override threshold.
10. CODESHATTER.
11. REBOOT.
12. Boss-specific source attribution.
13. Boss battle rendering/reference information.
14. Boss battle result handling.
15. Boss victory → Run Complete.
16. Boss defeat → ordinary Run-loss/retry behavior.
17. Minimal Boss logging/metrics useful for diagnosis and later balance analysis.
18. Same-build Boss save/resume at stable save boundaries.
19. Focused Boss parity/fixture verification against the shipped Alpha.
20. Regression verification for ordinary Quick Match and Battles 1–3.
21. The two preflight corrections in §2.

### 3.2 Explicitly out of scope

Do not add:

- additional Bosses;
- generalized Boss scripting/DSL;
- `MECHANIC_ID` or speculative Boss-mechanic schema;
- a Boss `PASSIVES` column;
- Boss phases beyond ODANSHAY's defined turn behavior;
- Boss Quick Match player flow;
- manual player targeting for DISABLER/Drain;
- scroll-feel redesign;
- autosave/force-close redesign;
- Abandon Run confirmation redesign;
- desktop-layout polish;
- permanent progression;
- production art/audio;
- broad balance changes;
- package-ID finalization;
- permanent signing-key work;
- cross-version save migration;
- Windows/web deployment.

The current `architect-notes.md` items remain deferred unless a direct blocker is discovered.

---

## 4. Current ODANSHAY identity

Resolve ODANSHAY from current `BOS` content.

Canonical current identity:

```text
BOS_ID: BOS_01
name: ODANSHAY
BASE_ICE: 250
STRONG_COLORS: GRE:BLU:MAG
STRONG_SHAPES: SQU:CIR:DIA
PRG_SET:
  PRG_S_004  DISABLER
  PRG_S_002  SHIELDER
  PRG_S_007  SPAMBOT
  PRG_S_003  ATTACKER
```

Weak color/shape sets derive through the same enum-order complement rule used by existing identities.

### 4.1 Boss is not a fake System

Runtime battle identity must distinguish:

```text
opponent kind = BOS
opponent id   = BOS_01
```

Do not synthesize a `SYS_ID`.

Boss Programs are still ordinary referenced `PRG_S_*` rows and use their existing Functions.

Positive postcondition:

- battle identity/logs/metrics/UI say ODANSHAY/BOS;
- Program charge, readiness, Function execution, and Program IDs remain the ordinary existing Program machinery.

---

## 5. Entering the Boss battle

Beta 0.2 already persists the selected Boss, final HOST, final acquired UPGRADE, full acquired UPGRADE stack, Hacker, Deck, final Build, and `PENDING_BOSS_BATTLE`.

On final Build confirmation:

1. resolve `BOS_01` from content;
2. use the already committed HOST;
3. use all acquired UPGRADEs in acquisition order;
4. use the already confirmed Hacker Build;
5. create Battle 4 with opponent kind `BOS`;
6. set Boss max/current ICE from authored `BOS.BASE_ICE = 250`;
7. do **not** apply the System step-4 +150 modifier;
8. transition into an ordinary active battle carrying Boss identity/mechanic hooks.

Do not regenerate route state, HOST, UPGRADE, Build, or Boss at battle entry.

---

## 6. Ordinary enemy combat reused for Boss

ODANSHAY uses the existing enemy side for everything not explicitly Boss-specific.

Reuse:

- enemy ICE plumbing;
- enemy Sync ownership and damage target;
- Boss strong/weak axis profile;
- top-to-bottom Program charge routing;
- normal Program charge caps/costs;
- dynamic Function phase;
- readiness recomputation after each activation;
- at-most-once activation per Program during a Function phase;
- current eligible-ready Program selection behavior;
- valid-target gating;
- System-style automated Drain targeting/gating;
- countdown processing;
- SPAM/Bomb semantics;
- SHIELDER semantics;
- ATTACKER semantics;
- HOST continual and START_OF_TURN effects;
- Hacker UPGRADE PASSIVEs;
- Reinforced Connection;
- Shield/permanent-Shield ordering;
- B1 and cascade behavior;
- existing damage attribution.

### 6.1 Boss has no ordinary identity PASSIVE list

Current `BOS` schema has no `PASSIVES` field.

`Passives.active()` should therefore receive no Boss-identity PASSIVE contribution merely because the opponent is a Boss.

The Boss-specific mechanic is its own layer.

Positive postcondition:

- HOST PASSIVEs still operate;
- Hacker UPGRADE PASSIVEs still operate;
- no synthetic Boss PASSIVE instance is invented.

---

## 7. Supporting Functions

Current supporting Functions are already authored content:

```text
FNC_018 DATABEND     cost 0   EFFECT_SHAKE  params 1:2:1:2
FNC_019 REBOOT       cost 0   EFFECT_SHAKE  params 1:1:0:0
FNC_020 CODESHATTER  cost 0   EFFECT_ATTACK damage 70
```

Invoke them through the existing Function → Effect machinery.

Do not create Boss-specific duplicate implementations of SHAKE or ATTACK.

Zero-cost payload Functions consume no Program/Deck charge and are not normal always-ready Program Functions.

Positive postcondition: after CODESHATTER/DATABEND/REBOOT, the four Boss Program charge pools are unchanged except for ordinary turn resolution that independently occurred.

---

## 8. Override overlay

An **Override** is a Boss-owned special overlay on an existing Packet.

It:

- preserves the Packet's color;
- preserves the Packet's shape;
- deals no damage by placement;
- generates no charge by placement;
- creates no new Sync merely by being installed;
- carries Boss ownership/source;
- counts toward the current on-board Override total;
- is removable through ordinary mechanics that remove/destroy enemy specials.

Positive postconditions:

- the underlying Packet remains the same axis-bearing Packet after placement;
- future match/damage/charge behavior uses those unchanged axes;
- no placement-only damage/charge/cascade event appears;
- the board remains playable immediately after placement.

Do not create a second independent board model if the existing special-overlay representation can express Override safely.

---

## 9. Override target legality and replacement

A valid Override target is an occupied normal axis-bearing Packet not already carrying a Boss-owned special overlay.

A Hacker-owned special **is a valid target**.

When Override targets a Hacker-owned special:

1. remove/replace that Hacker-owned overlay through normal special replacement/destruction semantics;
2. preserve the underlying Packet axes;
3. install the Boss-owned Override.

Boss-owned specials are not valid placement targets and are not overwritten.

Positive postcondition:

- overwriting a Hacker special leaves exactly one Boss Override on that Packet;
- the removed Hacker overlay no longer contributes its effect/countdown;
- underlying Packet identity remains intact.

---

## 10. End-of-Boss-turn Override placement

The final action of every **non-terminal** ODANSHAY turn is an attempt to place exactly **3** Overrides.

Normal terminal checks precede placement. If the battle already ended, no Overrides are placed.

### 10.1 Placement procedure

1. Compute all valid Override targets.
2. If at least 3 valid distinct targets exist:
   - choose 3 distinct targets with **gameplay RNG**;
   - choose all 3 before mutating the board;
   - place all 3 as one mechanic batch;
   - finish the Boss turn.
3. If fewer than 3 targets exist:
   - place **0**, not 1 or 2;
   - invoke DATABEND at zero cost;
   - resolve DATABEND completely;
   - terminal-check;
   - if Hacker survives, recompute capacity and retry.
4. Apply the shipped Alpha bounded retry limit. **Inspected and confirmed:** `for (attempt = 0; attempt <= OVERRIDE_DATABEND_RETRY_LIMIT; attempt++)` with the limit `5` — that is **5 DATABEND activations across 6 capacity checks**, because the final iteration emits `PLACEMENT_ABANDONED` and returns without firing DATABEND. A loop written `for i in 5` yields 5 checks and 4 DATABENDs and is wrong in both directions.
5. If the cap is exhausted and three valid targets still cannot be found:
   - place none;
   - end the Boss turn cleanly;
   - do not hang, recurse indefinitely, or corrupt the board.

Gameplay RNG owns both Override target choice and DATABEND board randomization. Do not consume route/setup RNG.

---

## 11. DATABEND

`FNC_018 DATABEND` uses SHAKE tuple `1:2:1:2`.

Interpret through existing SHAKE semantics:

1. regenerate every cell whose overlay this Shake does **not** retain — the rule is retention, not special-ness, so a Packet carrying a *Hacker* overlay loses the overlay **and** is itself regenerated;
2. remove enemy overlays relative to the activating Boss — i.e. remove Hacker-owned overlays while preserving Boss-owned overlays, each retained one keeping both its overlay and its underlying axes at its own coordinate;
3. resolve resulting Syncs;
4. use existing unlimited/stability cascade behavior for this tuple.

DATABEND-created Syncs are Boss/enemy-owned and use ODANSHAY axes, ordinary Boss Program charge routing, applicable HOST effects, ordinary PASSIVE modifiers, B1/cascade behavior, and existing attribution.

DATABEND has no additional bespoke direct damage.

Positive postconditions:

- Boss-owned specials retained by the tuple remain unless ordinary resulting resolution destroys them;
- Hacker-owned specials removed by the SHAKE are absent;
- resulting Sync damage/charge is ordinary Boss-side Sync output.

---

## 12. Start-of-Boss-turn threshold

At the start of each ODANSHAY turn, trigger when `override_count >= 15`.

Turn-start order:

1. relevant HOST `START_OF_TURN`;
2. no current Boss identity PASSIVE layer;
3. Override threshold check;
4. if triggered: CODESHATTER, terminal check, then REBOOT if Hacker survives;
5. countdown ticking/resolution;
6. ordinary Boss Function phase;
7. ordinary remaining enemy turn flow;
8. final non-terminal Override placement.

Do not treat threshold activation as a permanent phase transition. Overrides may accumulate again and trigger on a later Boss turn.

Positive postconditions:

- one threshold evaluation produces at most one CODESHATTER→REBOOT sequence for that start-of-turn check;
- after REBOOT, normal countdown/Function/turn flow continues if the Hacker is alive.

---

## 13. CODESHATTER

`FNC_020 CODESHATTER` is an ordinary Function-originated ATTACK with raw damage `70`.

It:

- pays no Program charge;
- uses normal Function-damage modifiers;
- is reduced by removable Shield and permanent Shield;
- is **not** suppressed by Reinforced Connection;
- carries `FNC_020` and Boss-mechanic causal attribution.

If CODESHATTER defeats the Hacker:

- battle ends immediately;
- REBOOT does not fire;
- countdowns do not tick;
- Boss Programs do not activate;
- end-turn Overrides are not placed.

If Hacker survives, REBOOT fires next and the ordinary Boss turn continues from countdown processing.

---

## 14. REBOOT

`FNC_019 REBOOT` uses SHAKE tuple `1:1:0:0`.

Through existing SHAKE semantics:

1. regenerate every cell — the tuple retains no overlay, so all 64 regenerate;
2. remove all special overlays;
3. generate under the **prevent-matches** invariant, so the resulting arrangement contains no Sync at all;
4. run no cascades.

> **Corrected 2026-08-25 (D-032), replacing "do not resolve Syncs created by the rearrangement".** The third element of the tuple `1:1:0:0` is `SHAKE_PREVENT_MATCHES`, and the alpha generates a board in which no match exists — it does not generate freely and then decline to resolve. The two differ in play: the looser reading can leave a pre-made Sync inert on the board for the **Hacker** to take next turn as free damage the alpha never grants. Both readings satisfy "no Sync resolves during REBOOT", which is why the postcondition below asserts the board's contents instead.

REBOOT clears Overrides and ordinary Hacker/Boss/HOST board specials.

REBOOT does **not** clear non-board PASSIVE state.

Positive postconditions:

- **the board immediately after REBOOT contains zero matches** — assert the board's contents, not merely that nothing was resolved;
- board special-overlay count is zero immediately after REBOOT under current semantics;
- Hacker/Deck/HOST/UPGRADE PASSIVE instances remain active;
- Program charge remains intact except for ordinary effects that resolved before REBOOT;
- no post-REBOOT Sync/cascade resolves from the rearranged board;
- the Boss turn continues if Hacker survives.

---

## 15. Boss battle result and Run completion

### 15.1 Boss victory

If ODANSHAY ICE reaches zero:

- Boss battle ends as a victory;
- no further Boss mechanic executes;
- Run transitions to **Run Complete**;
- no fifth route/battle/reward is generated.

Use the current result/session pattern.

### 15.2 Boss defeat

If Hacker LINK reaches zero:

- use ordinary Run-loss behavior;
- preserve the committed Boss/HOST/UPGRADE/Build package for same-battle retry;
- retry returns through pre-battle Build for the same Boss encounter;
- retry does not reroll HOST, reacquire UPGRADE, or alter selected Boss.

### 15.3 Debug controls

Existing debug win/lose controls may be used and must flow through ordinary result/session transitions.

Do not expand Beta 0.3 into a full Alpha wizard recreation merely for parity.

---

## 16. Boss presentation

Use the existing whitebox battle screen.

Required:

- opponent identity reads ODANSHAY;
- current/max ICE reads correctly;
- Boss Programs appear in authored order;
- selected HOST remains visible through existing encounter/reference conventions;
- Override has a distinct, legible Boss-owned overlay representation;
- Hacker-owned vs Boss-owned specials remain distinguishable enough to test replacement/removal;
- no Boss UI element reintroduces the board/status layout shift fixed in §2.1.

A dedicated polished Boss HUD is out of scope.

An Override count may be exposed in debug/reference UI if cheap and useful, but is not a new player-facing requirement.

---

## 17. Save/resume policy — proportionate proof

Pre-release policy remains: **no cross-version save migration**.

If Beta 0.3 changes the save schema, Beta 0.2 saves may be rejected cleanly.

Within Beta 0.3, save/resume must preserve enough Boss state to make Continue truthful:

- Boss identity;
- current Boss ICE;
- Boss Program charge;
- board and Override overlays;
- countdown/special state;
- HOST;
- acquired UPGRADEs;
- Build;
- gameplay RNG state already owned by battle save;
- current Run/battle phase.

Use the existing stable save boundary. Do not add micro-step persistence inside CODESHATTER/REBOOT/DATABEND resolution.

Verification burden:

- one representative mid-Boss save/reload with Overrides present;
- confirm Boss/HOST/UPGRADE/Build identity is unchanged;
- confirm Override board state and Program charge restore;
- continue enough turns to show no immediate duplicate threshold/end-turn payload.

Do not multiply this into a save-at-every-mechanic-step matrix.

---

## 18. Logging and metrics

Use the existing battle/session logging architecture. Do not create a separate Boss log store.

Boss battle context should include opponent kind `BOS`, `BOS_01`, max ICE 250, Program IDs/order, selected HOST, acquired UPGRADEs, and existing battle/run/seed context.

Useful mechanic records:

- Override placement batch;
- count before/after;
- targets at VERBOSE/COMPLETE where practical;
- Hacker special overwritten count;
- insufficient-target/DATABEND activation;
- threshold trigger count;
- CODESHATTER activation/damage through ordinary damage events;
- REBOOT activation.

Do not log no-op threshold checks at BASIC.

Useful battle aggregates:

- total Overrides placed;
- peak simultaneous Override count;
- Hacker specials overwritten;
- DATABEND activations;
- CODESHATTER activations;
- REBOOT activations.

Existing damage attribution remains authoritative. Do not duplicate a Boss-only damage accounting tree.

Exact Alpha log-schema parity is not required unless a maintained tool consumes it.

---

## 19. Verification philosophy

Boss combat is a new gameplay layer, so it deserves stronger proof than Beta 0.2 menu/session orchestration.

It still does **not** justify proving everything everywhere.

Use:

1. focused Boss mechanic tests;
2. a compact Boss Alpha-vs-Beta differential/fixture set;
3. fast ordinary battle parity to catch regression;
4. DEEPSCAN only if shared ordinary-battle code is materially changed or another gate gives reason to suspect ordinary battle drift;
5. real-device human Boss play.

The target remains **high confidence at proportionate cost**.

---

## 20. Boss differential / fixtures

Prefer extending existing trace infrastructure rather than creating another unrelated harness.

The Alpha repo remains read-only except for sanctioned trace instrumentation.

If current `scripts/trace.ts` can already construct/trace a Boss battle, use it.

If Boss entry requires a trace-instrument change, the agent is authorized to make a **narrow behavior-neutral extension to the existing Alpha trace instrument only**:

- no Alpha rules;
- no Alpha data;
- no gameplay algorithm changes;
- only enough setup plumbing to emit the existing Boss event stream.

Confirm the Alpha suite remains green.

A reasonable initial Boss parity set is multiple fixed seeds across each current escalation HOST, plus focused synthetic/fixture states for rare threshold and DATABEND paths.

Suggested target if inexpensive:

```text
~20 gameplay seeds × each eligible Boss-battle HOST
```

Adjust upward only if runtime is cheap or divergences indicate a broader sample is useful.

Hash-first comparison and mismatch re-trace remain preferred.

---

## 21. Automated behavior coverage

This is a **coverage checklist**, not a demand for one bespoke test per line.

Cover at least:

### Boss identity / construction
1. `PENDING_BOSS_BATTLE` enters Battle 4.
2. Opponent kind is BOS, ID BOS_01.
3. Boss ICE is 250.
4. Boss ICE is not 400.
5. Strong/weak axes resolve from BOS.
6. Program order is DISABLER → SHIELDER → SPAMBOT → ATTACKER.
7. HOST and all acquired UPGRADEs reach Boss battle.
8. Boss contributes no synthetic identity PASSIVE.

### Ordinary enemy reuse
9. Boss Program charge routes normally.
10. Dynamic Boss Function phase matches enemy semantics.
11. Boss Drain gating/targeting matches existing enemy behavior.
12. SHIELDER/SPAM/ATTACKER resolve through ordinary Functions.
13. Boss ordinary Syncs use Boss axes and damage Hacker.

### Override
14. Placement preserves color/shape.
15. Placement itself produces no damage/charge/Sync.
16. Boss-owned special target is illegal.
17. Hacker-owned special target is legal and replaced.
18. Three targets are distinct and selected before mutation.
19. Successful placement adds exactly three.
20. Gameplay RNG selects targets.
21. Fewer than three valid targets places none before DATABEND.
22. DATABEND resolves before retry.
23. Retry is bounded to shipped Alpha cap.
24. Cap exhaustion exits cleanly with no partial placement.

### DATABEND
25. Boss specials are retained under authored tuple.
26. Hacker specials are removed.
27. Resulting Syncs are Boss-owned.
28. Resulting damage/charge uses ordinary Boss mechanics.

### Threshold / CODESHATTER / REBOOT
29. 14 Overrides does not trigger.
30. 15 triggers.
31. >15 triggers.
32. HOST START_OF_TURN precedes threshold.
33. Threshold precedes countdown.
34. CODESHATTER raw damage is 70 before modifiers/defenses.
35. CODESHATTER consumes no Program charge.
36. Function damage modifiers apply.
37. Shield/permanent Shield applies.
38. Reinforced Connection does not suppress it.
39. Hacker death stops REBOOT and rest of Boss turn.
40. Hacker survival leads to REBOOT.
41. REBOOT removes all board specials.
42. REBOOT preserves non-board PASSIVE state.
43. REBOOT leaves a board containing zero matches — not merely: resolves none. See §14 and D-032.
44. Normal Boss turn continues afterward.
45. Threshold can trigger again later.

### Result / persistence / regression
46. Boss victory reaches Run Complete with no extra path.
47. Boss defeat uses normal Run-loss/retry package.
48. Retry keeps Boss/HOST/UPGRADE/Build.
49. Representative mid-Boss save restores Override/charge/identity.
50. Constructed Quick Match remains System-only.
51. Random Quick Match remains System-only.
52. Quick Match fresh-seed/replay behavior works.
53. Board geometry remains stable across first status update.
54. Existing fast battle parity remains green.

---

## 22. Ordinary-battle regression gate

Always run:

- full maintained headless test suite;
- fast 150-battle ordinary parity.

Run DEEPSCAN if any of the following is true:

- `resolve.gd`, `game.gd`, ordinary enemy turn logic, board resolution, PASSIVE arithmetic, RNG, or shared battle construction changes materially;
- Boss work modifies shared Effect semantics rather than only invoking already-existing semantics;
- fast parity diverges;
- the agent finds a seam that can plausibly affect ordinary System battles.

If Boss support is isolated behind a Boss-specific turn hook and ordinary fast parity stays green, a fresh DEEPSCAN may be skipped with the reason recorded.

Do not rerun the 2,000-walk Run differential unless route/setup progression changes. A small regression proving final route → Boss battle → complete/loss is enough.

---

## 23. Device verification

Use the tablet for iteration and low-end performance.

Use the S25 for final phone/cutout/touch sign-off.

### 23.1 Tablet

Verify:

- F-001 board jump is gone;
- fresh Quick Match gameplay seeds vary and Replay reproduces;
- full Run can enter ODANSHAY Battle 4;
- ODANSHAY identity/ICE/Programs render correctly;
- ordinary Boss Program combat occurs;
- Overrides visibly place in threes;
- Hacker special replacement by Override where practical;
- threshold/CODESHATTER/REBOOT through debug fixture/helper if natural play would take too long;
- Boss win reaches Run Complete;
- Boss loss/retry returns to same Boss encounter;
- representative mid-Boss save/reload;
- no obvious multi-second Boss-mechanic stalls;
- clean Godot log.

Use debug controls/fixtures to reach rare states instead of grinding turns manually.

### 23.2 S25

One announced device window.

Verify:

- Boss battle composition fits phone viewport;
- safe area remains correct;
- Override marker is readable at phone size;
- Boss Program/ICE/reference information is readable;
- no horizontal overflow/unreachable controls;
- one ordinary Boss turn by touch;
- one visible threshold sequence if practical via debug setup;
- clean log.

Do not rerun the entire four-battle Run manually on the phone if the tablet and headless gates already proved setup progression. A prepared Run state/debug path may be used to reach Battle 4 for phone-specific checks.

---

## 24. Performance policy

No speculative optimization.

The 2016 tablet remains the canary.

Watch specifically for:

- repeated full-board rebuild on Override placement;
- DATABEND retry causing visible long stalls;
- threshold/REBOOT creating excessive scene churn;
- overlay rendering creating per-frame allocations that did not exist in Beta 0.2.

If performance is acceptable on the tablet, do not optimize further merely because a profiler can find work.

---

## 25. Implementation order

### Phase A — preflight fixes
F-001 board geometry; F-002 Quick Match gameplay seed/replay.

### Phase B — Boss identity and battle construction
Consume `PENDING_BOSS_BATTLE`; BOS opponent identity; ICE 250; Programs; HOST/UPGRADE integration; battle UI identity.

### Phase C — Override representation
Overlay state, render, target legality, replacement/removal semantics, save compatibility.

### Phase D — Boss turn hook
Start-turn ordering and end-turn mechanic hook without duplicating normal enemy turn machinery.

### Phase E — mechanic payloads
DATABEND fallback, bounded retry, threshold, CODESHATTER, REBOOT, terminal behavior.

### Phase F — result/session integration
Boss win → Run Complete; Boss loss/retry; stable final encounter identity.

### Phase G — logging/metrics
Boss identity and compact mechanic telemetry/aggregates through existing stores/funnels.

### Phase H — focused verification
Boss fixtures/differential, headless suite, ordinary fast parity, conditional DEEPSCAN, representative save check.

### Phase I — device verification
Tablet then one S25 window.

### Phase J — closeout
README, decisions, port notes, architect notes, lessons learned, final diff, commit, push.

---

## 26. Process artifacts

Continue maintaining:

- `decisions.md` — decisions/rationale;
- `port-notes.md` — non-literal translation and seam discoveries;
- `architect-notes.md` — deferred design issues;
- `lessons-learned.md` — “what would time-traveler me tell past me at project start?”

Append lessons when discovered, not only at handback.

---

## 27. Completion standard

Beta 0.3 is complete when:

1. F-001 board-layout shift is fixed.
2. F-002 Quick Match gameplay seed behavior matches intended Alpha semantics and Replay is truthful.
3. `PENDING_BOSS_BATTLE` enters a real BOS battle.
4. ODANSHAY uses authored ICE 250 with no +150 double-count.
5. ODANSHAY uses authored strong axes and Program order.
6. Boss identity remains BOS throughout UI/state/logs/metrics.
7. Existing enemy Program/Function machinery works for Boss.
8. HOST and all acquired UPGRADEs remain active.
9. Override placement/replacement behavior works.
10. End-turn placement is exactly three or none before DATABEND.
11. DATABEND fallback uses shipped bounded retry behavior.
12. Threshold is `>=15` in the specified start-turn order.
13. CODESHATTER uses ordinary Function-damage rules and terminal handling.
14. REBOOT clears board specials, suppresses post-shake Sync/cascade, and preserves non-board PASSIVE state.
15. Boss victory completes the Run.
16. Boss loss/retry preserves the committed final encounter.
17. Representative same-build Boss save/resume works.
18. Boss logging/metrics are sufficient for diagnosis/analysis without a parallel pipeline.
19. Headless suite passes.
20. Focused Boss Alpha/Beta parity/fixtures pass.
21. Ordinary fast battle parity passes.
22. DEEPSCAN passes if §22 says the shared changes warrant it; otherwise prior evidence remains valid.
23. Tablet Boss gate passes.
24. S25 Boss presentation/touch gate passes.
25. Quick Match remains System-only.
26. No deferred design/polish scope is pulled into the port.
27. README and running process artifacts are updated.
28. Final diff is reviewed.
29. Intended changes are committed and pushed.
30. Working tree is clean.

---

## 28. After Beta 0.3

With Beta 0.3 complete, the Godot line contains the completed Alpha gameplay skeleton:

- battle engine;
- Constructed/Random Quick Match;
- Run setup/progression;
- route/HOST/UPGRADE layer;
- Boss selection;
- Boss Battle 4;
- ODANSHAY mechanic;
- Run completion.

The next phase can focus on platform/export work or deliberate post-port design/content changes without still mixing those changes with reference-port uncertainty.

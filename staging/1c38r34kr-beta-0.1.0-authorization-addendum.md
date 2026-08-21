# 1C38R34KR Beta 0.1.0 — Authorization Addendum

**Build identity:** `beta-0.1.0`
**Purpose:** Resolves ambiguities found while analysing the build authorization against the alpha source. Director rulings, 2026-08-21.

## A0. Authority

This addendum sits **below** `1c38r34kr-beta-0.1.0-build-authorization.md` in precedence. It resolves detail the authorization left open; it does not override it. Precedence is therefore:

1. `1c38r34kr-beta-0.1.0-build-authorization.md`
2. **This addendum**
3. `1c38r34kr-beta-0.1.0-architect-handoff.md`
4. `decisions.md`, `CLAUDE.md`
5. The alpha repository as behavioral specification

Each section below states the problem found, the ruling, and the resulting requirement.

---

## A1. The auto-play driver is a frozen, fidelity-critical artifact

**Problem.** §6 requires trace comparison across 5,250 battles per engine, but something must play the Hacker for those battles unattended. That driver lives in `scripts/bot.ts` and `scripts/batch.ts` in the alpha — directories the handoff module map treats as "tests and tools." It is not a tool. Its tie-breaks determine every event in every trace. A correct rules port with a driver that iterates rows bottom-up instead of top-down diverges on essentially every battle, and the failure presents as a rules bug.

**Ruling.** Freeze and port literally. The driver carries the same fidelity requirement as `rng.ts` (D-009).

### A1.1 Frozen tie-break specification

Ported literally from `scripts/bot.ts` and `scripts/batch.ts`. Every row below is load-bearing.

| Decision | Rule | Source |
| --- | --- | --- |
| Program iteration | ascending index `0 … units.player.length-1`, i.e. active build order top to bottom | `bot.ts:27` |
| Abort | return immediately if a winner exists, checked **before** each Program | `bot.ts:28` |
| Eligibility | skip when `u.charge < prog.cost` | `bot.ts:31` |
| Unit target (Drain) | enemy slot with the **most charge**; ties → **lowest index** (`indexOf(max)`) | `bot.ts:34-35` |
| Packet target | `fullestRowCell` — see below | `bot.ts:39` |
| Packet target absent | do **not** fire; charge is not spent | `bot.ts:40` |
| Untargeted | fire with no target | `bot.ts:44` |
| Row scan | `y` ascending, `y=0` is the top row | `bot.ts:52` |
| Row selection | **strictly greater** count wins (`count <= bestCount` skips), so ties → **topmost** row | `bot.ts:54` |
| Cell in row | first non-null, i.e. **leftmost** occupied cell | `bot.ts:55` |
| Move selection | `pickBotMove(board, config)`, side defaults to `player` | `bot.ts:14` |
| Deadlock | a null move is a hard error, not a skipped turn | `batch.ts:26` |
| Turn loop | `botFireAbilities` → deck (A2) → `botMove` → `attemptSwap` → `runEnemyPhase` → `startPlayerPhase` | `batch.ts:21-31` |
| Safety cap | `safety++ < 2000`, post-increment: 2000 iterations maximum | `batch.ts:23` |
| Non-termination | a battle that fails to finish is a hard error | `batch.ts:31` |

### A1.2 Requirement

- The driver is ported to `tools/driver.gd` and its GDScript form must reproduce the table above exactly.
- It is verified **independently, before** the matrix runs: a fixture of driver decisions (chosen Program index, target, and move) for a set of fixed board states, generated from the alpha and committed, must reproduce exactly.
- A divergence traced to the driver is reported as a driver defect, never as a rules defect.

---

## A2. The driver must fire the Deck Function

**Problem.** `botFireAbilities` iterates `state.units.player`, which holds Programs only. The Deck Function has its own separate charge pool and is deliberately **not** in `state.units`. `batch.ts` therefore never fires it. As specified, all 5,250 battles would leave `FNC_010` and the entire Deck charge-pool path with **zero** differential coverage — in a gate described as exhaustive parity.

**Ruling.** Extend the driver to fire it.

**Requirement.** `botFireAbilities` is **not** modified — it stays frozen per A1. Deck firing is a **separate sibling function** invoked at a defined point:

```
botFireAbilities(g)          # frozen, A1
if winner: break
botFireDeck(g)               # new, A2
if winner: break
mv = botMove(g)
attemptSwap(mv.a, mv.b)
...
```

`botFireDeck(g)` fires when `deckCharge >= deck.fn.cost`, using the **same** targeting policy as A1: untargeted fires directly; a packet target uses `fullestRowCell`; a unit target uses highest-charge-lowest-index. It fires at most once per turn.

Rationale for the position: the alpha requires Hacker Functions to be activated before the turn-ending Sync, and Programs precede the Deck in every display and priority convention in the game.

This is a deliberate, documented divergence from `batch.ts`. Balance figures produced by `npm run batch` and by the trace driver are therefore **not** directly comparable, and neither is represented as the other.

---

## A3. Hash-first differential comparison

**Problem.** The literal reading of §6 — compare normalized ordered event traces for 5,250 battles per engine — produces an estimated 0.5–2 GB of JSONL per engine per matrix run. Runtime is not the constraint; storage and diff cost are.

**Ruling.** Hash-first.

**Requirement.**

1. Each engine runs the matrix in-process (§6.2) and emits **one line per battle**:

   ```
   {"sys":"SYS_01","host":"HST_03","variant":"default","seed":1337,"events":2841,"hash":"…"}
   ```

2. The hash is a rolling digest over the **normalized** trace records (§6.3 / handoff §11) — the same bytes full comparison would have used.
3. The comparator diffs these summary files. Identical hash **and** identical event count is a pass.
4. On mismatch, the comparator re-runs **that single battle** in both engines with full trace output and reports the first differing record.
5. `--full-trace` remains available to force complete output for a named battle.

This satisfies §6.2's reproduction requirement exactly while reducing storage to megabytes, and removes any incentive to shrink the matrix for performance reasons — which §6.1 explicitly forbids.

---

## A4. Device gate split

**Problem.** §1 says "a physical Android phone"; §13 says "the configured physical Android test device"; D-016 made the tablet primary and the phone periodic.

**Ruling.** Tablet for routine work, phone signs off.

| | |
| --- | --- |
| **Galaxy Tab A (`SM-T580`)** | All development and repeated device checks. Permanently connected. Performance canary. |
| **Galaxy S25 Ultra (`SM-S938U`)** | The §13 completion checklist runs **once** on the phone, in a single announced window (D-015), before the build is called complete. |

Touch feel, thumb-reach layout, and portrait composition are **phone** judgements and must not be signed off on the tablet. §13's "real-device behavior is authoritative for touch feel" means the phone specifically.

The final report must state which checks ran on which device.

---

## A5. Fingerprint parity constrains the serializer

**Problem.** §15.3 requires the Godot content fingerprint to match the alpha's. The alpha builds a canonical string with JavaScript's `JSON.stringify`, then applies djb2:

```javascript
let h = 5381;
for (…) h = ((h << 5) + h + canonical.charCodeAt(i)) >>> 0;
return `${h.toString(16).padStart(8,'0')}-${canonical.length.toString(36)}`;
```

Matching that byte-for-byte means reproducing JS `JSON.stringify` output exactly — key order, string escaping, and number formatting.

**Requirement.**

- **Godot's `JSON.stringify()` must not be used for the fingerprint.** The canonical string is emitted by a hand-written serializer that reproduces JS semantics: insertion-ordered keys, JS string escaping, and JS number formatting.
- djb2 needs the same 32-bit masking discipline as `rng.ts` (D-009).
- **Phase B first task:** confirm whether any fingerprinted value is non-integer. If every value is an integer, the float-formatting hazard disappears and the serializer is straightforward. Report the finding either way.
- The requirement is retained rather than relaxed: an exact match is a cheap end-to-end proof that the entire parse, normalize, and resolve path ported faithfully.

---

## A6. The save serializer moves into Phase 4

**Problem.** §14 sequences save at Phase 6, after presentation, but §15.8 requires save/resume to preserve deterministic continuation — a differential property that the harness can prove directly and that nothing else can.

**Ruling.** Split save into serializer and UI.

**Requirement.**

- The save **serializer and restorer** (logic-layer, `save.gd`) land in **Phase 4**, alongside the harness.
- A **resume-determinism test** joins the differential gate: run a battle to turn *K*, serialize, restore into a fresh state, continue to completion, and require the resulting trace to equal the uninterrupted trace for the same seed byte-for-byte. Run across a sample of the matrix, at several values of *K*.
- Save/quit **UI** and its device verification remain in Phases 5–6 as written.

This catches an incompletely captured RNG state, a dropped countdown overlay, or a stamped area pattern lost across the boundary — failures that a round-trip equality test would pass and a continuation test will not.

---

## A7. Normalization details

Pinned to prevent trivially avoidable false divergences.

| Item | Ruling |
| --- | --- |
| `battleId` | `nextBattleId()` produces a fresh ID per battle. **Normalized out** of trace records entirely. |
| Think time | Excluded, as are all wall-clock and duration values. |
| `maxCascadeSteps` | `0` is the **default** and means capped at zero. `null` means **infinite**. The §6.1 variation is `null`. Do not invert these. |
| `enemyMatching` | Default is `true` (director ruling, alpha 0.6.0). The variation is `false`, the pre-0.6 timer-charge mode. |
| Build origin | `'DEFAULT'` for the pinned default build; part of battle identity and must match across engines. |
| Logging tier | **Phase 3 must verify that the logging tier cannot alter the event stream.** `Game.collect()` calls `consumeEvents(metrics)` and `logger.consume()` before returning events; if either mutates, the differential gate becomes silently sensitive to log level. Report the finding. |

---

## A8. Unchanged

Everything else in the build authorization stands as written, including the §6.1 matrix size (15 authored `SYS × HST` pairings — `SYS_01`–`SYS_03` × `HST_01`–`HST_05` — at 200 seeds default plus 50 seeds per variation, totalling 5,250 battles per engine), the §12 scope boundaries, the §15 completion standard, and the §16 reporting requirements.

# Beta 0.2.0 Authorization — Doc Review

**Reviewing:** `staging/1c38r34kr-beta-0.2.0-build-authorization-revised.md`
**Against:** the shipped Beta 0.1 repo at `610192d`, and the Alpha oracle at
`C:\Users\chode\breach` (`576c26b`, `alpha-0.7.0`).
**Date:** 2026-08-24. **Status:** pre-implementation. No code written.

Per §0, the Alpha *source* is authoritative over Alpha prose, and discrepancies
must be reported. Everything below is checked against source, not narrative.

---

## A. Internal contradictions in the authorization

### A1 — §1 authorizes a Battle-4 System substitution that §12 and §22.29 forbid. **Blocking; needs a ruling.**

§1 lists "a temporary non-Boss Battle 4 compatibility mode only if required to
reproduce the Alpha pre-Boss session flow cleanly". §5 says the Run "must follow
§12 rather than silently substitute a normal System", §12.1 requires the
`PENDING_BOSS_BATTLE` stop, and §22.29 makes "never substitutes a normal SYS for
Boss battle" a coverage item.

**The escape hatch is not needed and should be struck.** The Alpha's step-4 route
is already Boss-typed at the source: `bossPathOffers()` emits
`opponentKind: 'BOS'` with the committed `bossId`, and the Alpha comment is
explicit that there is "no placeholder System row anywhere in the content"
(`src/logic/session.ts`). There is no pre-Boss flow that needs a System at
step 4, so no compatibility mode can be "required".

### A2 — §4.1 and §22.3–5 pull in opposite directions on resume-to-screen. **Resolvable; no work implied.**

§4.1 relaxes: "Exact return to the same intermediate UI screen is not itself a
completion requirement." §22.3/4/5 then require resume to land on Hacker
Selection, Deck Selection, and initial Path Choice respectively.

In practice there is no tension: the Alpha's persisted setup phase **is** the
screen. `RunSetupInfo.step` is `'HACKER' | 'DECK'`, and `serializeSession()`
writes `phase: 'SETUP_HACKER' | 'SETUP_DECK'`. The strict §22 behavior is free.

**Recommendation:** implement §22 literally; treat §4.1 as a tolerance for
failure modes, not as license to coarsen the design.

### A3 — §15's "committed UPGRADE" is a field the Alpha does not have. **Remove it.**

`selectPath()` acquires into `upgradeIds` *immediately* and deletes
`pendingPath` in the same transition. There is no intermediate "committed but
not acquired" UPGRADE. Adding one creates a second source of truth for a reward
that is already in the acquisition-ordered list, and §10 makes that order real
gameplay state (it is START_OF_TURN resolution order).

### A4 — §15 omits the settings snapshot, the Run inventory, and `hackerMaxLink`. **Real omission with gameplay consequence.**

Alpha `RunInfo` carries all three, and `RunSetupInfo` already carries `settings`
at Boss commitment — before a Hacker even exists:

- `settings` — snapshotted at Boss commit via `snapshotRunSettings()`,
  authoritative for the whole Run. Alpha §10.4: later menu edits must not mutate
  a saved Run.
- `hackerMaxLink` — resolved once at Deck commit by `resolveHackerMaxLink()`.
- `inventory` — the Run's fixed six-Program inventory, Run-scoped and discarded
  with the Run (Alpha §8.6: it must never leak into a later Run).

Without the snapshot, changing title Settings mid-Run retroactively changes the
saved Run's LINK and ICE. Add all three to the §15 list.

### A5 — §15's "retry state where Alpha has one" resolves to: there is none.

Retry re-opens Build for the same step with the same committed encounter —
`openRunBuild('RUN_RETRY')` with `beginBuild(..., session.build, 'CARRIED_RUN')`.
The persisted representation is just `RunInfo.pendingBuild`. No new field.

---

## B. Alpha source vs. authorization prose (§0 reporting duty)

### B1 — §13 is correct, but the Alpha's encounter table has a live step-4 row.

`RUN_ENCOUNTERS` is `[0, 50, 100, 150]` — four rows, not three. `resolveRunIce()`
returns a Boss's authored `baseIce` with **no** modifier (Alpha 0.7.0 §19:
adding +150 would double-count the escalation). ODANSHAY's authored `BASE_ICE`
is **250**, already the final Boss-battle value.

So the step-4 `iceModifier: 150` is **dead data in the Alpha** — never applied to
any opponent that can appear at step 4.

**Recommendation:** port all four rows verbatim with a comment that step 4's
modifier is unreachable. Cheaper for 0.3 and keeps the table a faithful copy.
§13 should say which it wants rather than leaving it to the implementer.

### B2 — Boss, Hacker, and Deck selection are one-row screens with current content.

`data/bos.csv` holds exactly one row (BOS_01 ODANSHAY). `hak.csv` and `dek.csv`
hold one each. §5's "show all valid Boss rows; select exactly one" is a
single-item list.

Not a defect, but it changes what the §23 device gates prove: **Path Choice is
the only screen that exercises real multi-option selection.** "Boss selection
works on the tablet" is not evidence that select-then-confirm works on a list.

### B3 — In-pool sizes, since §9 and §12 both branch on them.

| Dataset | In pool | Out (`n`) |
| --- | --- | --- |
| SYS | SYS_01 BOUNCER, SYS_02 MIDNIGHT | SYS_03 DOORMAN |
| HST | HST_02..05 BITMIRE, ARENA, VERDUN, WEEDS | HST_01 THRESHOLD |
| BOS | `in_pool` inert — Boss selection is explicit | — |

So §9's anti-duplicate rule runs with 8 SYS+HST combinations and §12's
distinct-HOST rule with 4. Both anti-duplicate paths are live and testable.
Note that Battles 2 and 3 can only ever be BOUNCER or MIDNIGHT — §22.13 is a
two-value check.

---

## C. Port hazards the authorization does not call out

### C1 — Route-RNG *draw order* is load-bearing, and nothing in the doc says so. **Highest-risk item in the build.**

§17 sensibly relaxes exact internal RNG-state equality, but §21.2 still wants
fixed-seed Alpha comparisons. Those only work if the generators are ported
draw-for-draw. Four specifics that a "cleaner" implementation would silently
break:

1. All three offer generators call `pickOfferUpgrades()` **first**, then generate
   SYS/HST. Reordering changes every offer for a given seed.
2. `pickOfferUpgrades()` **shuffles the whole eligible array** (in `allUpgrades()`
   order) and takes the first two. It is not two picks, and the eligible array's
   order matters.
3. `laterPathOffers()` produces the distinct pair with a **retry loop over the
   ordinary sampler** — 2 draws per attempt, guard 32, gated on `combos > 1`.
   Constructing the pair by exclusion consumes a different number of draws.
4. `bossPathOffers()` retries the **HOST only** — 1 draw per attempt, gated on
   `poolHosts().length > 1`.

**Recommendation:** the authorization should state that the three generators are
ported draw-for-draw, and that any deviation is recorded in `port-notes.md`.
Otherwise the §21.2 fixtures quietly stop meaning anything.

### C2 — Force Win is required by the §23.1 device gate but is not in §3.1 scope. **Gap.**

§23.1 says "continue through Battle 3 using debug force-win where useful". §3
never lists wizard actions as in scope, and Beta 0.1 has `Types.WizardAction`
as an **enum only** — no implementation anywhere in `scripts/`, `scenes/`, or
`tools/`.

The Alpha's `forceWinAvailable()` matrix is also step-aware (`info.step <
RUN_LENGTH`), so it is Run-coupled work, not a free UI button.

**Recommendation:** add Force Win for Run battles 1–3 to §3.1 explicitly, or
strike it from §23.1 and specify how the device gate reaches Battle 3.

### C3 — §14 does not say Random Quick Match must not reroll on Continue.

The Alpha persists the rolled System, HOST, and Build in `QuickMatchInfo` and
restores them verbatim (Alpha §14/§9.5). §14 covers "does not overwrite
Constructed remembered Build" but is silent on rerolling. Add it.

### C4 — Reuse the Alpha's phase vocabulary verbatim.

`serializeSession()` already defines: `SETUP_HACKER`, `SETUP_DECK`,
`PENDING_PATH`, `PENDING_BUILD`, `PENDING_RESULT`, `ACTIVE_BATTLE`. Beta 0.2 adds
a seventh, `PENDING_BOSS_BATTLE`. The beta already matches Alpha spelling for
config enums (`save.gd._config_to_dict`) so a save reads next to a trace; keep
that going.

### C5 — §12's stop point must not route through the Alpha's Run-Complete path.

`isRunComplete()` fires on a step-4 *result*. Beta 0.2 has no step-4 battle and
therefore no step-4 result. The two must stay distinct or §27's "Do not mark the
Run complete" fails silently.

### C6 — §16 understates the save change: this is a schema restructure, not added fields.

Beta 0.1's `SaveState.to_dict()` puts the **battle** at the top level
(`SCHEMA := 2`, `user://save.json`). Beta 0.2 needs the battle record to become a
*member* of a session envelope alongside `run` / `setup` / `phase`. That is
schema 3 and a reshape of the existing writer/reader, not an additive field set.

Consistent with `save.gd`'s existing stance ("Alpha saves are not readable and
there is no migration path"), schema-2 saves should be **rejected, not migrated**.

---

## D. Scope relief — Beta 0.1 already carries more of this than §25 implies

§2's "port layers, not behaviors twice" is right, and the foundation is further
along than the phase list suggests. Already present and usable unchanged:

- `Types`: `OpponentKind.SYS|BOS`, `SelectionSource`, `SystemSelectionSource.RUN_RANDOM`,
  `BuildOrigin.CARRIED_RUN`, `Mode.RUN`, plus matching `*_NAMES` tables.
- `Content`: loads bosses, upgrades, and hosts; parses and validates `in_pool`
  (with startup errors for an empty System or HOST pool); defines
  `INITIAL_SYSTEM_ID` (SYS_03), `INITIAL_HOST_ID` (HST_01), `PATH_CHOICE_COUNT`,
  `MIN_UPGRADE_ROWS`.
- `Rng`: `pick()` and `shuffle()` ported draw-for-draw — the shuffle carries an
  explicit comment about descending Fisher-Yates matching the Alpha — and
  `Rng.new()` takes the raw internal state, so `Rng.new(rng.get_state())` resumes
  the sequence. The whole route-RNG persistence design rests on this and it
  already holds.
- `GameState.identity`: already carries `upgrade_ids`, `opponent_kind`,
  `opponent_selection_source`, `build_origin`.

**Genuinely new work:** `Content.pool_systems()` / `pool_hosts()` accessors
(`in_pool` is parsed and validated but never filtered on — no pool accessor
exists anywhere in the repo), the Run/RunSetup state, route-RNG plumbing, the
session envelope (C6), Force Win (C2), and the new screens.

---

## E. Doc maintenance

- `CLAUDE.md` still says "This repo does **not** yet contain the game" and names
  the Beta 0.1 architect handoff as the current build specification. Both are
  stale as of `610192d`.
- The authorization itself is untracked. Commit it before implementation so the
  spec is in history alongside the work.
- AN-004 (blank screen after Build in the Godot editor on PC) was filed during
  this review from a third-party report. It is unrelated to Beta 0.2 scope but
  touches the Build → Battle transition this build extends.

---

## Summary of requested rulings

| # | Item | Ask |
| --- | --- | --- |
| A1 | §1 Battle-4 compatibility mode | Strike it — §12 already covers this and the Alpha needs no substitute |
| A3 | §15 "committed UPGRADE" | Remove from the state model |
| A4 | §15 missing `settings` / `inventory` / `hackerMaxLink` | Add all three |
| B1 | Step-4 ICE modifier (dead in Alpha) | Confirm: port all four rows verbatim |
| C1 | Draw-for-draw route RNG | Add as an explicit requirement |
| C2 | Force Win | Add to §3.1 scope, or remove from the §23.1 gate |
| C6 | Save schema 3, reject schema 2 | Confirm the reshape is expected |

Everything else in the authorization checks out against the Alpha source.

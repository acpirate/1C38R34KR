# 1C38R34KR beta 0.2.0 — port handback

**Build:** `beta-0.2.0` — the Run/progression port.
**Authorization:** `1c38r34kr-beta-0.2.0-build-authorization-revised.md`.
**Review of that authorization:** `1c38r34kr-beta-0.2.0-authorization-review.md`.
**Date:** 2026-08-24/25.

---

## 1. Verdict

**Complete against §27, with the Boss layer deliberately unbuilt.**

The full pre-Boss Alpha Run loop is ported and runs end to end on hardware:
New Run → Boss → Hacker → Deck → Path → Build → Battle, three times, then the
final Boss route, then a clean stop. Beta 0.1's battle engine is unchanged
underneath it and its DEEPSCAN evidence still stands.

The build principle held: no battle rule was reopened, and no Boss combat was
pulled forward. `Session.create_run_battle` refuses a Boss opponent outright
rather than substituting a System, so the §12 boundary fails loudly rather than
producing a plausible Battle 4.

---

## 2. What the verification actually caught

Three defects, and where they came from is more useful than what they were.

### The one the fixtures were built for — and it was fine

Route generation was identified in the authorization review (§C1) as the
highest-risk part of the port: three generators resolve constraints with retry
loops rather than by exclusion, one returns without drawing when a single
UPGRADE remains, and all of them pick UPGRADEs before Systems. Every plausible
"cleaner" rewrite produces offers that are individually legal and wrong for the
seed.

Fixtures were built to pin it, capturing both the offers and the route RNG state
after each generation. **The generators were correct.** The analysis was right,
the mitigation was right, and it found nothing.

### The one nothing was watching — `build_origin` (P-028)

`advance_after_victory` and `retry_battle` stamped `Run.build_origin =
CARRIED_RUN`. The alpha moves that field only when a Build screen is
*confirmed*; `CARRIED_RUN` is the Build **screen's** starting origin, not the
Run's committed one. Two pieces of state sharing a vocabulary, collapsed into
one.

Every behavioural test passed throughout. The build did carry forward, editing
did mark it edited, retry did preserve it. `build_origin` gates no rule — it is
telemetry — so nothing asserting gameplay could see the difference. It would
simply have been wrong in every log the beta produced.

Found by the Run differential harness on its **first comparison**.

### The one that was waiting to happen — the PASSIVE cache key (P-021)

`Passives.active()` memoizes the assembled instance list on the identity's cache
key, which beta 0.1 composed as `hacker | opponent | host`. That key was
*complete* for everything 0.1 could construct, because Quick Match has no
UPGRADEs.

A Run breaks it: acquired UPGRADEs change between battles while those three may
not. Two Run battles against the same System on the same HOST would share a key,
and the second would silently fight with the first's PASSIVE set — no error,
nothing visibly wrong except the damage numbers.

Caught by reasoning about the seam while wiring Phase C, not by a test. It is
the general shape of the risk in this build: **the engine is correct, and the way
to break it is to feed it state the 0.1 callers could never construct.**
Memoization keys, validation that assumed an empty collection, defaults that were
unreachable — all the same class.

---

## 3. Verification results

| Gate | Result |
| --- | --- |
| Headless logic tests | 2,906 passing, 22 suites |
| Route fixture parity | 6 seeds × 4 generations — offers and trailing RNG state exact |
| Run/session differential | 2,000/2,000 walks, no divergence |
| Battle parity, fast tier | 150/150, no divergence |
| Battle parity, DEEPSCAN | 5,250/5,250, no divergence |
| Tablet device gate | complete, clean log |
| S25 phone gate | complete, clean log |

DEEPSCAN was run rather than relied on from 0.1, because Phase C consolidated
Quick Match and Run onto a single battle constructor. §21.1 makes a fresh run
optional when only orchestration changed around an untouched core; battle
*construction* is not the core, but it is battle-affecting, and four phases were
built on top of it.

---

## 4. Verification effort, against §26.1

§26.1 asked for proof proportional to feature importance and regression risk.
What that meant in practice:

- **Reused, not re-earned:** the beta 0.1 battle serializer and its
  continuation proof. The session envelope wraps it unchanged, so nothing
  re-proved that a battle resumes deterministically.
- **Bounded deliberately:** save/resume. One representative interrupted-Run
  walk — save and reload at every path choice, asserting it reaches the same
  offers, route state, and acquisitions as an uninterrupted one — instead of a
  per-screen matrix. That is the anti-reroll proof, which is the part with
  gameplay value.
- **Not built at all:** cross-version save migration, per D-030.
- **Escalated where cheap:** the Run differential. It plays no battles, so
  2,000 complete Run walks compare in under two seconds. Scoping a differential
  to the layer being ported is what made "compare everything" affordable — and
  "compare everything" is what caught P-028.

---

## 5. Device verification

**Tablet (Galaxy Tab A, SM-T580, Android 8.1, armeabi-v7a)** — full §23.1
checklist:

- New Run through Boss, Hacker, and Deck selection ✅
- Battle 1 is the fixed DOORMAN + THRESHOLD on both paths, ICE 100 ✅
- UPGRADE acquired before Build and visible in Run context ✅
- Battle won through the real result path, returning Continue Run ✅
- ICE ladder 100 / 150 / 200 across battles 1–3 ✅
- Escalation routes draw in-pool Systems and avoid identical `SYS + HST` ✅
- Four UPGRADEs accumulate in acquisition order; acquired ones stop being offered ✅
- Final route names ODANSHAY on both paths at ICE 250, with the exhaustion case
  explained on screen rather than looking like a bug ✅
- Final Build reaches `PENDING_BOSS_BATTLE` ✅
- Relaunch from a **setup** screen: resumes to the screen after the last
  commitment, with nothing pre-selected ✅
- Relaunch from a **pending route** screen: offers restored identically, no
  reroll ✅
- Run survived a full APK reinstall mid-test ✅
- Random Quick Match rolls an in-pool System and a shuffled build ✅
- Session log written and complete, every record joined by the run seed ✅
- **Clean Godot log** across the entire session ✅

**Performance (§24)** — no speculative optimization was done and none was needed.
Route screens open promptly, Build stays responsive with accumulated UPGRADE
context, and no repeated multi-second stalls appeared on 2016 hardware. Battle
entry is the slowest transition and is dominated by battle-scene construction,
which is unchanged from 0.1.

**Phone (Galaxy S25 Ultra, SM-S938U, Android 16, arm64-v8a, 1080×2340)** —
§23.2 sign-off, one window:

- New Run flow usable one-handed; Boss, Hacker, and Deck selection fit and
  scroll ✅
- **Safe area correct on every new top-level screen** — the check the tablet
  structurally cannot make ✅
- Path Choice cards readable at phone width; long UPGRADE text wraps rather than
  overflowing ✅
- Build remains usable with the Run context block above it; both actions
  reachable without scrolling ✅
- `PENDING_BOSS_BATTLE` state understandable ✅
- Stop point persists across a return to the title ✅
- Random Quick Match works ✅
- No horizontal overflow or unreachable controls on any screen ✅
- **Clean Godot log** across the whole session ✅

---

## 6. Final diff review

New logic: `run.gd`, `run_setup.gd`, `route.gd`, `session_save.gd`,
`session_log.gd`. Extended: `types.gd` (setup/session phase vocabulary),
`content.gd` (ordered listings, the random pools, identity-parameterized
inventory and build), `session.gd` (one battle constructor, Random Quick Match
setup), `save.gd` (delegates file access to the envelope), `log_store.gd` (a
fourth stream), `ui_theme.gd` (safe-area insets), `main.gd` (the Run screens),
`battle_screen.gd` (delegates safe-area arithmetic).

Nothing in `resolve.gd`, `game.gd`, `board.gd`, `match_finder.gd`, `passive.gd`,
`metrics.gd`, or `battle_log.gd` was touched. The battle rules are byte-identical
to the build DEEPSCAN passed at 0.1, which is why its evidence carries.

New tooling: `run_trace.gd`, `run_trace_alpha.ts`, `compare_runs.mjs`,
`run_parity.mjs`, `gen_route_fixture.ts`.

---

## 7. For the next authorization

**Boss combat is the whole of 0.3**, and it starts from a persisted
`PENDING_BOSS_BATTLE` package rather than a blank page. The `RUN_STOPPED` log
record carries that package in full and is the first thing worth reading.

Four things the 0.3 author should know before writing scope:

1. **Force Win already partly exists.** Beta 0.1's battle screen carries debug
   `win`/`lose` buttons, and with a Run active they flow through the Run result
   screen. D-029 was written as though nothing existed and slightly over-scoped
   as a result (P-032). The availability matrix, `RESTART_RUN`, and the wizard
   log record are the parts genuinely missing.
2. **The step-4 ICE row is dead data and is carried deliberately** (P-017).
   ODANSHAY's authored 250 happens to equal what a 100-base System reaches
   through the step-4 `+150`, so the correct and the double-counting rules
   produce the same number with current content (P-023). A Boss ICE test cannot
   be written as "not equal to the ladder value" — only the 400 case
   distinguishes them.
3. **`Passives.active()` contributes nothing for a Boss opponent**, deliberately:
   the Boss schema has no PASSIVES column. Boss mechanics are their own layer.
4. **The safe-area conversion is untestable on the tablet.** It scales physical
   screen pixels to viewport space, so an error is invisible without a cutout
   and badly wrong with one. It is structurally a phone question.

---

## 8. Handover facts

- `Content.GAME_VERSION` is `beta-0.2.0`. It is **not** part of the content
  fingerprint (that uses `DATA_SCHEMA_VERSION` and the content rows), so bumping
  it does not invalidate parity.
- Content fingerprint is unchanged at `49c229cd-8ma` — no content was edited.
- Session save is envelope schema 3. Beta 0.1 saves do not load, by design.
- `com.acpirate.ic38r34kr` is still a placeholder package ID.
- Release signing still uses the temporary key outside the repo.
- Run `godot --headless --import` after adding any `class_name`; until the class
  cache refreshes, the headless runner reports the type as undeclared. This cost
  time twice during this build.

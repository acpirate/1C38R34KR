# 1C38R34KR beta 0.3.0 — port handback

**Build:** `beta-0.3.0` — Boss combat, and the end of the reference port.
**Authorization:** `1c38r34kr-beta-0.3.0-build-authorization.md`.
**Review of that authorization:** `1c38r34kr-beta-0.3.0-authorization-review.md`.
**Date:** 2026-08-25.

---

## 1. Verdict

**Complete against §27.**

The full alpha gameplay loop now runs in Godot: New Run → Boss → Hacker → Deck →
(Path → Build → Battle) ×3 → ODANSHAY → Run Complete. Played end to end on the
tablet, ending on **RUN COMPLETE — "ODANSHAY is breached."**

The governing principle held. `scripts/logic/boss.gd` adds the Override overlay,
the threshold, and the end-of-turn placement; `run_enemy_phase` gains exactly two
guarded hooks; everything else ODANSHAY does runs through the ordinary enemy
path. There is no bespoke SHAKE, no bespoke ATTACK, and no synthetic Boss
PASSIVE.

Both preflight items are fixed: the board no longer shifts on the first action,
and Quick Match **and Run battles** draw fresh gameplay seeds.

---

## 2. What the verification caught

### The one the authorization got wrong — REBOOT (D-032)

Found in review, before any code. §14 described REBOOT as regenerating the board
and then declining to resolve its Syncs. The alpha's authored tuple carries
`SHAKE_PREVENT_MATCHES` and generates a board **containing no match at all**.

Those differ in play: the looser reading leaves a pre-made Sync sitting inert for
the **Hacker** to collect next turn as free damage the alpha never grants. And
both satisfied §14's stated postcondition, because neither resolves anything
*during* REBOOT — the P-036 shape again, one section after the same document had
systematically added positive postconditions everywhere else.

§14 now asserts the board's contents: **zero matches after REBOOT**.

### The one that shipped and the tablet caught — the opponent union (P-042)

The Boss battle rendered a header reading `SYSTEM / ICE 0/1` over a battle that
was otherwise entirely correct. `battle_screen` resolved the opponent with
`Content.system()`; for a `BOS` id that reports an unknown id and returns an
empty Dictionary, and indexing it **aborted the refresh before the ICE readout
ran**.

3,000-plus headless tests and 300 Boss parity battles all passed. The scene layer
has no headless coverage by design, and an aborted refresh presents as stale UI
rather than a crash. Fixed with `Content.opponent_of_identity`, so no caller
chooses a registry; the other six `Content.system(` callers were audited and were
already guarded.

### The one the phone caught — layout overflow (AN-006 / P-044)

The battle screen rendered wider than a 1080 px viewport, clipping the board, the
opponent's Program column, and the debug bar's own last button.

The cause was the debug bar's **seed Label sharing a row with the controls**. A
Label's minimum width is its text, and F-002 had just changed the seed from a
permanent `0` to a ten-digit random — so a row that had always been narrow became
the widest thing in the scene. The tablet has ~120 px more width and absorbed it.

Two things worth keeping from it:

- **It presented as a Boss defect and was not one.** The failing screenshot was a
  Boss battle and the passing one a Quick Match; the actual variable was seed
  digit count. Two device screenshots are a sample of two.
- **The first fix was worse than the bug.** Clipping the label restored the
  layout and truncated the seed to `seed 205953`. A seed exists so a device
  observation can be replayed in the harness; a clipped one cannot. The rule is
  not "make it fit" but *a debug affordance must not participate in the game's
  layout at all* — hence its own row.

---

## 3. Verification results

| Gate | Result |
| --- | --- |
| Headless logic tests | 3,122 passing, 23 suites |
| **Boss differential vs the alpha** | **300/300**, ODANSHAY × all five HOSTs, no divergence |
| Run/session differential | 1,000/1,000 walks, no divergence |
| Battle parity, fast tier | 150/150, no divergence |
| Battle parity, DEEPSCAN | **5,250/5,250**, all four variations, no divergence |
| Tablet device gate | complete, clean log |
| Phone layout | verified at 1080×2340 after AN-006 |
| Alpha suite (after the instrument change) | 272 passing |

DEEPSCAN was run because the Boss work touches `run_enemy_phase`. §22 allows
skipping it when Boss support is isolated behind a guarded hook and fast parity
is green — which was true — but the same reasoning as D-031 applied: this is the
last gameplay-port phase, and the cost of finding a perturbation after closeout
is a retracted build rather than ninety minutes of compute.

---

## 4. The Boss differential, and what it cost

§20 asked for the existing trace infrastructure to be extended rather than a
third harness built. It was, on both sides:

- **Alpha:** a `BOS_*` id in `--sys` selects `headlessBoss` — the fixture route
  Alpha 0.7.0 §45 had *already built* for exactly this purpose. One import, one
  three-line function, one call site. No rules, no data, no algorithm. The alpha
  suite stays at 272 passing. Committed there as `377fd48`.
- **Beta:** `create_boss_trace_battle`, its counterpart, carrying no UPGRADEs
  because a trace compares combat.

The first comparison diverged on hash while matching on **event count, turn
count, winner, and the exact Override cells chosen**. The cause was field naming:
the beta writes snake_case and the alpha's camelCase wins at the trace boundary,
so `boss_id`, `count_before`, and `count_after` needed entries in the
normalizer's key map like every other multi-word key. Three lines, and then exact
parity.

That is the differential doing precisely what it is for: the gameplay was right
on the first run, and the only thing wrong was the spelling of the record.

---

## 5. Device verification

**Tablet (Galaxy Tab A, 1200×1920)** — §23.1:

- full Run reaching Battle 4 ✅
- ODANSHAY identity, ICE 250, authored Program order ✅
- ordinary Boss Program combat ✅
- **Overrides visibly placed in threes**, Packets keeping colour and shape ✅
- Boss victory → RUN COMPLETE ✅
- Run survived a full APK reinstall and resumed into the Boss battle ✅
- clean Godot log ✅

**Phone (Galaxy S25, 1080×2340)** — §23.2, partially:

- Run flow, Path Choice, Build, and the Boss Build all fit and scroll ✅
- battle screen overflow found → **AN-006**, fixed, re-verified at 1080×2340 ✅

**Stated plainly:** the post-fix battle-screen verification was done at an
**emulated** 1080×2340 viewport on the tablet, not on the S25 itself. The
geometry is identical and the overflow reproduced and cleared there, but the S25
has a real display cutout the tablet does not. Two §23.2 items — the safe area
over a genuine cutout, and Override marker legibility on the real panel — remain
unconfirmed on hardware and want one short window.

**Performance (§24)** — no speculative optimization, and none needed. No
repeated full-board rebuild on placement, no visible DATABEND stall, no scene
churn from REBOOT. Battle entry remains the slowest transition and is unchanged
from 0.1.

---

## 6. Final diff review

New: `scripts/logic/boss.gd`, `tests/test_boss.gd`, `tools/gen/boss_parity.mjs`.

Extended: `game.gd` (two guarded hooks plus `cast_boss_mechanic`), `session.gd`
(Boss battles buildable, plus the trace fixture route), `run.gd` /
`session_log.gd` / `types.gd` (`RUN_COMPLETE`), `metrics.gd` (mechanic
aggregates), `content.gd` (the opponent union, `GAME_VERSION`),
`battle_screen.gd` (F-001 reservation, union resolution, the AN-006 debug row),
`main.gd` (F-002 seeds, Boss entry, Run Complete), `trace.gd` / `trace_norm.gd`.

**`resolve.gd`, `board.gd`, `match_finder.gd`, `passive.gd`, `bot.gd`, `rng.gd`,
and `tile.gd` are untouched.** The rules engine is byte-identical to the build
DEEPSCAN passed at 0.1 — verified by `git diff`, not assumed.

---

## 7. For the next authorization

The reference port is finished. What follows is no longer a port, and that is
the main thing to say: from here, changes are **design decisions** rather than
questions with an answer sitting in the alpha. The oracle stops being able to
adjudicate the moment content or rules move.

Carried forward, unbuilt:

1. **AN-005** — `Abandon Run` destroys a Run on one tap, no confirmation, sitting
   directly under the button pressed after every victory.
2. **AN-003** — a force-close leaves a stale save that offers Continue at a turn
   the player was not on.
3. **AN-004** — a third-party report of a blank screen after Build on desktop,
   unreproduced. Windows is a later target and was never gated.
4. **The wizard layer** — `RESTART_RUN`, the step-aware Force Win availability
   matrix, and the wizard log record. D-029 built only a minimal debug skip.
5. **Content thinness** — one Boss, one Hacker, one Deck, two in-pool Systems,
   four UPGRADEs for four decisions. Three setup screens ask for choices that do
   not exist, and the final route's reward is always forced. This is the single
   biggest gap between "the loop works" and "the loop is worth playing", and it
   is authoring rather than engineering.

**One consequence of that last item worth deciding deliberately:** the alpha is
the oracle and contains only this content. Author a fifth UPGRADE or a second
Boss and the differential stops covering it — new content is *beyond the oracle*
by construction. That threshold is worth crossing knowingly.

---

## 8. Handover facts

- `Content.GAME_VERSION` is `beta-0.3.0`, and the title screen now derives its
  subheading from it rather than a literal — it read "beta 0.2" throughout 0.3
  development because it was typed by hand.
- Content fingerprint unchanged at `49c229cd-8ma`. No content was edited.
- Save envelope is still schema 3; nothing in 0.3 changed its shape.
- `com.acpirate.ic38r34kr` remains a placeholder package ID.
- Release signing still uses the temporary key outside the repo.
- The alpha repo carries one sanctioned change (`377fd48`, trace instrument) and
  is otherwise untouched.
- `adb shell wm size 1080x2340` on the tablet emulates the phone viewport and
  reproduced AN-006 exactly. Reach for it before requesting a device window;
  `wm size reset` restores. See P-045.
- Current beta screens are captured in `staging/design-reference/beta03-*.png`,
  from both devices.

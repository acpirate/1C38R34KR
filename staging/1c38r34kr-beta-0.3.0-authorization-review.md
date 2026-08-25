# Beta 0.3.0 Authorization — Doc Review

**Reviewing:** `staging/1c38r34kr-beta-0.3.0-build-authorization.md`
**Against:** the shipped Beta 0.2 repo at `e0606d6`, and the Alpha oracle at
`C:\Users\chode\breach` (`alpha-0.7.0`).
**Date:** 2026-08-25. **Status:** pre-implementation. No code written.

Per §0, the shipped implementation and current runtime data outrank prose, and
discrepancies must be reported rather than silently followed.

---

## Verdict

**Materially stronger than the 0.2 authorization, and I found nothing that
blocks starting.** Every content value it asserts is correct against the CSVs
and the Alpha source — checked, not assumed:

| Claim | Verified |
| --- | --- |
| `BOS_01` ODANSHAY, `BASE_ICE 250` | ✅ `data/bos.csv` |
| axes `GRE:BLU:MAG` / `SQU:CIR:DIA` | ✅ |
| `PRG_SET` = DISABLER, SHIELDER, SPAMBOT, ATTACKER | ✅ `PRG_S_004/002/007/003`, in that order |
| `FNC_018` DATABEND, cost 0, SHAKE `1:2:1:2` | ✅ `data/fnc.csv` |
| `FNC_019` REBOOT, cost 0, SHAKE `1:1:0:0` | ✅ |
| `FNC_020` CODESHATTER, cost 0, ATTACK damage 70 | ✅ |
| Override threshold 15, placement 3, DATABEND cap 5 | ✅ Alpha `content.ts` |

§0.1's insistence on 250-not-400, and its note that a test comparing Boss ICE to
the System ladder is non-discriminating, is exactly right and matches the beta
0.2 finding (P-023).

**The document also answers the P-036 lesson directly.** Nearly every section
now carries an explicit *"Positive postcondition"* alongside its prohibition.
That is the correction the handback asked for, applied more thoroughly than the
handback suggested. Which makes the one place it slipped worth flagging.

---

## A. One real discrepancy — REBOOT's match policy

**§14 describes the wrong mechanism, and its positive postcondition does not
catch the difference.**

§14 says REBOOT should:

> 3. do not resolve Syncs created by the rearrangement;
> 4. do not run cascades from the rearrangement.

with the postcondition *"no post-REBOOT Sync/cascade resolves from the
rearranged board"*.

That describes **generating a board that may contain matches, then declining to
resolve them.** The Alpha does something different. REBOOT's tuple is
`1:1:0:0`, whose third element is `SHAKE_PREVENT_MATCHES`, and `board.ts`
generates an arrangement in which **no match exists at all**:

```ts
// matches PREVENTED: the completed arrangement already satisfies the
// legal/stable post-generation invariants, so no Sync wave begins.
```

The distinction is not cosmetic. Under the Alpha, the post-REBOOT board is
guaranteed match-free and playable. Under §14 as written, the board could
contain one or more pre-made Syncs sitting inert — which the **player** then
takes on their next turn as free damage the Alpha never gives them.

**Both implementations satisfy §14's postcondition**, because neither resolves a
Sync during REBOOT. This is precisely the P-036 shape: a correctly-stated
prohibition whose positive half is unstated, satisfiable two ways with different
gameplay.

**Recommended wording:** REBOOT regenerates the board under the prevent-matches
invariant, so the arrangement contains no Sync to resolve. Postcondition: *the
board immediately after REBOOT contains zero matches*, not merely that none were
resolved. That is a directly assertable property, and §21.43 should assert it.

DATABEND is unaffected — its tuple carries `SHAKE_ALLOW_MATCHES`, and §11
correctly says resulting Syncs resolve.

---

## B. The DATABEND cap — exact semantics, as §0.2 requested

§0.2 asks for the shipped bound to be inspected and preserved exactly. Here it
is, from `game.ts:placeEndOfTurnOverrides`:

```ts
for (let attempt = 0; attempt <= OVERRIDE_DATABEND_RETRY_LIMIT; attempt++)
```

with `OVERRIDE_DATABEND_RETRY_LIMIT = 5`. So per end-of-turn placement sequence:

- **up to 6 capacity checks** (`attempt` 0…5);
- **up to 5 DATABEND activations** — on the final iteration the Alpha emits
  `PLACEMENT_ABANDONED` and returns **without** firing DATABEND;
- the loop also returns early on `s.winner`, so a terminal state mid-sequence
  stops it.

§10.1's "expected: 5 attempts maximum" is **correct for DATABEND count**. The
trap is the loop bound: a port written as `for i in 5` yields 5 checks and 4
DATABENDs. Worth stating as "5 DATABENDs, 6 capacity checks" so the off-by-one
is unmissable.

Two event kinds already exist in the Alpha and are worth mirroring for §18:
`INSUFFICIENT_TARGETS` (carrying `available` and a 1-based `attempt`) and
`PLACEMENT_ABANDONED`.

---

## C. DATABEND's board effect is stated slightly loosely

§11 says *"randomize non-special Packets"*. The Alpha's rule, per `board.ts`, is
by **retention**, not by special-ness:

> a tile whose overlay this Shake RETAINS keeps both its overlay and its
> underlying axes, at its own coordinate; every other cell regenerates

Under `1:2:1:2` (`REMOVE_ENEMY_SPECIALS`), only **Boss-owned** overlays are
retained. So a Packet carrying a *Hacker* overlay loses the overlay **and gets
regenerated**, because it is not retained. §11 as phrased could be read as
preserving that Packet's axes.

Also worth carrying across: a Shake over a board with holes **fizzles rather
than corrupting** (`existing.length !== 64` → `return false`). DATABEND fires
mid-turn, so that guard is load-bearing.

---

## D. Scope relief — Beta 0.1 already reserved the Boss vocabulary

More of Phase B/C exists than §25 implies. Already in the beta, unused:

- `Content.BOSS_MECHANIC_BOSS_ID`, `FN_DATABEND`, `FN_REBOOT`,
  `FN_CODESHATTER`, `BOSS_MECHANIC_FUNCTION_IDS`
- `Content.OVERRIDE_PLACEMENT_COUNT` (3), `OVERRIDE_THRESHOLD` (15),
  `OVERRIDE_DATABEND_RETRY_LIMIT` (5) — all matching the Alpha
- `Types.EventKind.BOSS_MECHANIC` (`&"bossMechanic"`)
- `Types.OwnerKind.BOSS`
- `Types.OpponentKind.BOS`, plumbed through identity, save, and logs
- `Passives.active()` already contributes nothing for a Boss opponent, with a
  comment saying so deliberately — §6.1 needs no work, only a test

`Effects` already parses the four-element SHAKE tuple. §7's "do not create
Boss-specific duplicate implementations of SHAKE or ATTACK" is achievable
directly.

---

## E. Smaller notes

1. **§2.2 / F-002 — one clause needs sharpening.** "a newly started Constructed
   Quick Match gets a fresh gameplay seed **unless the player explicitly
   supplied a debug seed**" needs a rule for what "explicitly supplied" means,
   since the field is pre-populated with the current value and always has *a*
   number in it. Suggest: the field starts blank/unset and only a non-empty
   entry pins the seed. Otherwise the first debug session silently reintroduces
   the fixed-seed behaviour being fixed.

2. **§21.53 duplicates a Phase A item as a Boss-phase test.** Fine, but it
   should assert the *positive* form from §2.1 — the board rect is unchanged
   across the first status update — rather than "no jump", which is unmeasurable.

3. **§17 save list omits the Override placement RNG position.** Board and
   overlays are listed, and gameplay RNG state is covered by the existing battle
   save, so this is likely already satisfied — worth confirming during Phase C
   rather than discovering at the resume test.

4. **§20's Alpha trace-instrument permission is welcome and already precedented**
   — commit `576c26b` on the Alpha was exactly such a headless trace instrument.
   The existing `run_trace_alpha.ts` pattern (tool lives in the *beta* repo, run
   from the alpha) may avoid touching the Alpha at all.

5. **Staging hygiene, resolved:** `lessons-learned-beta0.3-updated.md` was a
   strict superset of `lessons-learned.md` (390 identical lines + 2 new
   lessons). Folded into the canonical file and the duplicate removed, since
   §26 names `lessons-learned.md` and two copies of an append-only document
   diverge the moment either is appended to.

---

## Summary

| # | Item | Ask |
| --- | --- | --- |
| A | §14 REBOOT match policy | **Fix the wording** — prevent-matches, not resolve-nothing; assert zero matches on the post-REBOOT board |
| B | §10.1 DATABEND cap | Confirm: 5 DATABENDs / 6 capacity checks |
| C | §11 DATABEND regeneration | Sharpen: regeneration is by retention, not special-ness |
| E1 | §2.2 debug seed | Define "explicitly supplied" |

Only **A** changes behaviour. Everything else is wording or confirmation, and
none of it blocks Phase A, which is the two preflight fixes and touches no Boss
code.

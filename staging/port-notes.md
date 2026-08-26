# Port Notes

Running record of places where the GDScript could **not** be a literal
translation of the alpha, and why. Authorization §16 requires these in the
final report; recording them as they happen beats reconstructing them later.

Anything here is a deviation forced by the language or engine. Deliberate design
decisions live in `decisions.md` instead.

---

## Phase 1 — Foundation

### P-001 · `Color` and `Shape` enums renamed

**Forced by:** Godot has a builtin `Color` type, and GDScript rejects an enum
that shadows a builtin name — *"The member "Color" cannot have the same name as
a builtin type."*

**Resolution:** renamed to `PacketColor` and `PacketShape`. Renamed as a pair so
the two stay symmetric; `Shape` alone would not have collided.

**Impact:** naming only. The enum **values** are unchanged and remain frozen at
`0..5` per D-014, which is what weak-set derivation actually depends on.

### P-002 · Enum type annotations must be fully qualified

**Forced by:** GDScript treats the bare `Side` written inside `types.gd` and the
`Types.Side` seen by an external caller as *different named types*:

```
Parse Error: Invalid argument for "opponent_of()" function:
argument 1 should be "Side" but is "Types.Side".
```

**Resolution:** house convention — enum annotations always use the qualified
form (`Types.Side`), **including inside the file that declares them**.

**Impact:** affects every logic module that passes an enum across a boundary,
which is most of them. Established in Phase 1 deliberately, because discovering
it in Phase 3 would mean editing every signature already written.

### P-003 · Constants are not readable by name from a `class_name`

**Forced by:** a `class_name` identifier is a *type*, not an object, so both
`Constants.get(name)` and `Constants.get_script_constant_map()` are parse
errors. `preload` does not help — the parser resolves it back to the same named
type.

**Resolution:** a runtime `load(path)` into a `Script`-typed variable yields an
object whose instance methods are callable.

**Impact:** test tooling only. No gameplay code reads constants reflectively.

### P-004 · `Math.imul` has no direct GDScript equivalent

**Forced by:** two masked uint32 operands can produce a product up to ~1.8e19,
which exceeds int64's ~9.2e18 maximum.

**Resolution:** `Rng._imul` splits operands into 16-bit halves so no
intermediate can overflow.

**Measured:** GDScript's integer multiply *does* wrap cleanly mod 2^64, so the
naive `(a * b) & 0xFFFFFFFF` produces identical results — asserted by
`test_rng.gd` across ten cases including `0xFFFFFFFF * 0xFFFFFFFF`. The
defensive form is kept anyway: correctness here should not rest on overflow
semantics. Revisit only if Phase 4 profiling shows the harness is RNG-bound.

---

## Phase 2 — Content pipeline

### P-006 · `load.ts` split into modules

**Forced by:** nothing — this is a judgement call, recorded because authorization
§16 asks for module-boundary deviations.

The alpha's `load.ts` is 2,441 lines holding diagnostics, vocabularies, the
table reader, per-dataset row models, validation, resolution, and the
fingerprint. Ported as `issues.gd`, `vocab.gd`, `table.gd`, `effects.gd`,
`passives.gd`, `fingerprint.gd`, and `load.gd`.

**Impact:** boundaries only. No logic is reordered or merged, and the module map
in the handoff still resolves — `load.gd` remains the entry point.

### P-007 · CSV parser ported rather than substituted

**Forced by:** `FileAccess.get_csv_line()` handles quoting but not the
behaviours the pipeline depends on — 1-based line tracking that every
validation diagnostic reports, skipping wholly empty rows rather than yielding
`[""]`, BOM stripping, and reporting an unterminated quote as a structural
error.

**Note:** this reverses the handoff's own §12 guidance ("do not hand-roll a
splitter"), which was written before those dependencies were traced. Diverging
on any of them would change validation output or change what gets fingerprinted.

### P-008 · Godot's JSON parser yields every number as a float

**Forced by:** `JSON.parse_string` produces floats for all JSON numbers, and
GDScript array equality is type-strict, so `[0, 0] != [0.0, 0.0]`.

**Resolution:** fixture-side values are coerced to `int` at the comparison,
rather than loosening the comparison itself.

**Impact:** every test that compares JSON fixture data against integer game
data — and, in Phase 4, the differential comparator. Worth remembering there.

### P-009 · djb2 must iterate UTF-16 code units, not codepoints

**Forced by:** JavaScript strings are UTF-16 and `charCodeAt` yields code units,
so a character outside the BMP contributes **two**. GDScript strings are UTF-32.
A codepoint-based loop diverges on any non-BMP character — and reports a
different length, which is itself the base36 suffix of the fingerprint.

**Resolution:** `Fingerprint.utf16_units()` computes surrogate pairs directly
from codepoints. Pinned by a vector for `"🎮"`, whose UTF-16 length is 2.

**Why it matters despite ASCII content:** it would go unnoticed until the day
someone pastes an emoji into a notes column, and would then present as an
unexplained save-invalidating fingerprint change.

### P-010 · Godot's `JSON.stringify` cannot produce the canonical string

**Forced by:** the fingerprint requires byte-equality with JavaScript's
`JSON.stringify` — insertion-ordered keys, integral floats rendered without a
decimal point, raw non-ASCII rather than `\u` escapes, and JS's exact escape
set.

**Resolution:** `Fingerprint.stringify()` is a hand-written serializer. Pinned
against JS output for every value shape the canonical string contains.

**Related, resolved favourably:** A5 asked whether any fingerprinted value is
non-integer. **Zero are**, so JS float formatting never has to be reproduced.
`_float_to_js` raises rather than guessing if that ever stops being true.

### P-011 · GDScript strings cannot contain U+0000

**Forced by:** GDScript strings are NUL-terminated internally, so an embedded
NUL cannot round-trip through a fixture.

**Resolution:** the control-character hash vector uses `U+0001`, `U+001F`, and
`U+007F` instead. Authored content contains no control characters at all, so
this is a test-coverage limitation rather than a behavioural gap — recorded so
the omission is not mistaken for an oversight.

### P-012 · JavaScript omits undefined properties when serializing

**Forced by:** the fingerprint includes the whole axis-target object. In
JavaScript an unset optional property is *absent* from the JSON, not `null`, so
a whole-Packet target serializes as `{"token":"NEU","kind":"NEU"}` — with no
`color` or `shape` keys at all.

**Resolution:** `_axis_target` adds those keys only when they are set. The same
reasoning applies to a PASSIVE's `ALL` scope, which the alpha models as
`true`-or-absent and never as `false`.

**Impact:** either mistake shifts the fingerprint, and the resulting mismatch
gives no clue which of ~11,000 characters is wrong. Both are the kind of detail
that only surfaces because the fingerprint is compared byte-for-byte.

### P-013 · P-002 recurred, exactly as predicted

`match_finder.gd` declared its enums and then annotated with the bare names,
and every external caller failed to compile:

```
Parse Error: Cannot pass a value of type "MatchFinder.Orientation" as "Orientation".
```

The convention from P-002 — always qualify — is correct and easy to forget when
writing a new module. Recorded because it is now the second occurrence, which
makes it a pattern rather than an anecdote.

### P-014 · A7 verified: logging cannot perturb the event stream

**The concern (addendum §A7):** `Game.collect()` runs `consumeEvents(metrics)`
and `logger.consume()` before returning the event list. If either mutated the
stream, the differential gate would become silently sensitive to log level — a
miserable class of bug, because the traces would differ for reasons unrelated to
game logic.

**Verified, and the answer is no.** Both iterate strictly read-only: they
accumulate into their own structures and never assign to an event field, and
never reorder or splice the array. The logger's `this.events` is its own
accumulator of log entries, a separate array from the `GameEvent[]` stream.
`collect` returns the original array, not the logger's return value.

**Consequences:**

- the differential gate is log-level independent, as intended
- metrics and logging can be deferred to Phase 6, as the build sequencing
  assumes, without weakening the Phase 4 gate

---

## Phase 2 result

The content fingerprint reproduces the alpha's `49c229cd-8ma` exactly.

That one value validates the whole pipeline simultaneously: CSV parsing and
leading-apostrophe normalization, all ten dataset readers, payload grammar and
composite expansion, Effect parameter contracts, typed tuple resolution, the
Transform axis grammar, plan assembly with per-row resolved targeting,
area-pattern cell *order*, the hand-written canonical serializer, and djb2's
UTF-16 semantics. Any one of them being subtly wrong produces a different hash.

**What it does not prove:** the validation guard rails. Those fire only on
invalid content, and the authored content is valid — a rule missing from the
port would look identical to one that passes. They are covered separately by
`test_validation.gd`, which constructs the minimal invalid state for each rule
and asserts it is rejected.

---

## Phase 4 — bugs the differential harness found

Both were real port defects. Neither was caught by any other test, and neither
would have crashed — which is exactly the failure mode the harness exists for.

### D-001 · The Shake result was silently discarded

**Symptom:** total divergence from record 6 of the very first battle compared —
different boards, turn counts, and winners.

**Cause:** `BoardOps.shake` REPLACES the board rather than mutating it in place.
It drafts a candidate arrangement and commits only on success, which is what
makes a fizzle leave the Datastream untouched. `_cast_shake` passed a state
carrier in but never wrote `board` and `next_id` back, so a successful Shake
consumed its RNG, reported success, and changed nothing.

**Why nothing else caught it:** the Shake still "worked" from every other
angle — the event said resolved, the RNG advanced, no error was raised. Only a
comparison against a reference implementation could see that the board was wrong.

The same write-back is done correctly in `ensure_no_deadlock`. Getting it right
in one place and wrong in the other is the ordinary shape of this kind of bug.

### D-002 · A PASSIVE carrier's actor identity

**Symptom:** 30 of 150 battles diverged, all on HST_05 (WEEDS), every one with
identical event counts, turn counts, and winners but different content. That
pattern — same shape, different content — pointed at attribution rather than
mechanics before the trace was even opened.

**Cause:** when a carrier PASSIVE fires its payload Function, the ACTOR is the
PASSIVE itself; the source that supplied it travels separately in `cause`. The
port used the source ID (`HST_05`) where the alpha uses the PASSIVE ID
(`PSV_008`), collapsing "which PASSIVE acted" into "which HOST contributed it".
The actor's name was also taken from the PASSIVE's display text rather than the
payload Function's name — presentation standing in for identity.

**Why it mattered:** those two facts are deliberately kept separate throughout
the engine so a log can say the battlefield caused an effect that the active
agent owns. Collapsing them loses exactly that distinction.

---

## Tooling defects found and fixed

### P-005 · A parse error in a test suite hung the runner

**Symptom:** `godot --headless -s res://tools/run_tests.gd` spun forever at 100%
CPU instead of failing.

**Cause:** a script with a parse error still `load()`s as an object but cannot
be instantiated. Calling `new()` on it raises a runtime error that aborts
`_initialize()`, so `quit()` was never reached and the SceneTree main loop ran
indefinitely.

**Fix:** guard with `script.can_instantiate()` before `new()`, plus a `_process`
fallback that aborts if the main loop is ever reached.

**Why it is recorded:** a test runner that hangs instead of failing is worse
than the bug it was reporting — it converts a clear failure into a stalled
build. Both exit paths are now verified: 0 on pass, 1 on failure.

---

## Beta 0.2 Phase A — the Run session model

### P-015 · Registry iteration order replaces the alpha's `*Order` arrays

**Forced by:** nothing — this is a translation choice the language makes free.

The alpha keeps an explicit ordering array beside each registry
(`systemOrder`, `hostOrder`, `upgradeOrder`, `bossOrder`) because a JavaScript
`Map` is iterated in insertion order but the alpha wanted the order stated
rather than relied upon. GDScript `Dictionary` also preserves insertion order,
and the loader inserts in CSV row order, so `Content._ordered()` simply iterates
the registry.

**Why it matters and is not cosmetic:** route generation shuffles the eligible
UPGRADE array *in this order*, so the order decides which UPGRADEs a given route
seed offers. A parallel array would be a second thing to keep in sync with the
loader, and the failure mode if they drifted would be a silent change in offers
rather than an error.

**Risk accepted:** if a future loader ever sorts rows on the way in, or builds a
registry from anything other than a single ordered pass, this order changes
silently. `test_run_state.gd` asserts the eligible pool's first entry, which
turns that into a test failure rather than a quiet reroll.

The alpha's arrays and the beta's iteration agree on current content: every
dataset's IDs are monotonic in file order.

### P-016 · `Run.phase` is stored, where the alpha derives it

**Forced by:** a new state with no alpha counterpart.

`serializeSession()` in the alpha derives the session phase at write time:

```
onPath ? 'PENDING_PATH' : !game ? 'PENDING_BUILD' : pending ? 'PENDING_RESULT' : 'ACTIVE_BATTLE'
```

Beta 0.2 adds `PENDING_BOSS_BATTLE` (authorization §12.1), which **cannot** be
derived from those three inputs: with no battle in progress and no pending
offers it is indistinguishable from `PENDING_BUILD`. Deriving it would require a
fourth boolean, and then four booleans encode sixteen combinations of which five
are legal.

**Resolution:** `Run.phase` is one explicit `Types.SessionPhase` field, and
`Run.problems()` enforces the invariant the derivation used to guarantee for
free — chiefly that `phase == PENDING_PATH` if and only if `pending_path` is
non-null, and that a committed Run never wears a setup phase.

The six alpha phase spellings are kept verbatim in `Types.SESSION_PHASE_NAMES`
so a beta save still reads next to an alpha trace, which is the same discipline
`SaveState._config_to_dict` follows for settings.

### P-017 · The step-4 ICE modifier is carried as dead data

**Forced by:** fidelity to a table the alpha ships with an unreachable row.

`Run.RUN_ENCOUNTERS` carries all four rows including step 4's `+150`, which
nothing can ever apply: a Boss is the only opponent that can appear at step 4,
and a Boss takes its authored `BASE_ICE` with no modifier (ODANSHAY's authored
250 is already the final value, so adding 150 would double-count the
escalation). The alpha has exactly the same dead row.

**Why keep it:** beta 0.3 needs the table shape, and a three-row table would be
a divergence from the oracle that a future reader would have to re-derive.
`test_run_state.gd` asserts the value, so removing the row later is a deliberate
act rather than a tidy-up. Raised as §B1 of the beta 0.2 authorization review.

## Beta 0.2 Phase B — route generation

### P-018 · Route generators are transcribed draw-for-draw, not reimplemented

**Forced by:** nothing in the language — this is a deliberate refusal to
improve the code, and it needs recording so a later reader does not "fix" it.

Three of the four generators resolve their constraints with **retry loops over
the ordinary sampler** rather than by exclusion, and one returns early without
touching the stream at all. Each is a place where the obvious better
implementation changes the result:

| Generator | Alpha shape | The tempting rewrite | Why it breaks |
| --- | --- | --- | --- |
| `pick_offer_upgrades` | shuffle the WHOLE eligible array, take 2 | pick twice without replacement | different draw count, different picks |
| same, one UPGRADE left | return before drawing | shuffle a 1-element array | consumes a draw the alpha never does |
| `later_path_offers` | draw SYS+HST, retry the pair while it duplicates | filter the pool, then pick | 2 draws per retry vs 0 |
| `boss_path_offers` | draw HOST, retry while duplicate | pick 2 distinct HOSTs | same |

All four also pick UPGRADEs **first**, before any System or HOST.

**Why it matters:** every one of those rewrites produces offers that are
individually legal and satisfy every behavioural rule in `test_route.gd`. The
divergence is invisible to behavioural testing — it shows up only as *different
offers for the same seed*, which is exactly what the §21.2 fixed-seed fixtures
exist to detect and exactly what they would stop detecting.

**Resolution:** `tests/fixtures/route.json` is generated from the alpha by
`tools/gen/gen_route_fixture.ts` and captures, for six seeds, a full four-battle
route walk plus the **route RNG state after each generation**. The state is the
part that pins the draw *count* rather than just the result: an implementation
one draw off produces plausible offers and a wrong trailing state.

Raised as §C1 of the beta 0.2 authorization review, which asked for exactly this
to be made an explicit requirement rather than left to the implementer.

### P-019 · Random Quick Match draws the BUILD before the opponent

**Forced by:** the alpha's actual order, which is not the intuitive one.

`startRandomQuickMatch` draws from one isolated setup stream in the order
**build → System → HOST**. Reading the feature description ("a random opponent
with a random build") suggests rolling the opponent first, and that ordering
would produce a different — entirely legal — setup for the same seed.

**Resolution:** `Session.random_quick_match_setup` follows the alpha's order,
and the fixture carries a Random Quick Match case per seed with its trailing
stream state so the order is pinned rather than commented.

Found by reading `src/main.ts` rather than the prose. A reminder that §0's
"where alpha prose and alpha source disagree, the source wins" applies to
*ordering*, not just to values.

### P-020 · Run transitions mutate in place; setup transitions return new state

**Forced by:** nothing — an idiom split that is worth stating so it does not
read as an inconsistency.

The alpha is uniformly immutable: every session transition returns a new
`RunInfo`. The beta splits this deliberately.

- `RunSetup.commit_boss` / `commit_hacker` / `commit_deck` **return new
  objects**. These are the destructive commitment boundary, the objects are
  tiny, and a caller holding the pre-commit state must not observe it change.
- `Run.open_path_choice` / `select_path` / `enter_pending_boss_battle`
  **mutate in place**, matching `GameState`, which is the closest precedent in
  this codebase and is mutated throughout resolution.

**What protects the atomicity the immutable style gave for free:** each mutating
transition is a single function that either completes or returns `false` having
changed nothing, and `Run.problems()` asserts the resulting state is one the
transitions can actually produce. `test_route.gd` checks `problems()` after
every step of a full four-battle walk.

## Beta 0.2 Phase C — battle-engine integration

### P-021 · The PASSIVE cache key must include the acquired UPGRADEs

**Forced by:** a latent collision that beta 0.1 could not reach.

`Passives.active()` memoizes the assembled instance list on
`identity["cache_key"]`, and beta 0.1 built that key as
`hacker_id | opponent_id | host_id`. UPGRADEs were deliberately absent because
Quick Match has none — the only caller — so the key was complete for everything
that could exist.

A Run breaks that. Its acquired UPGRADEs change between battles while the
Hacker, opponent, and HOST may not: two Run battles against the same System on
the same HOST with different UPGRADEs produce the SAME key. The second battle
would then be handed the first battle's memoized PASSIVE list and fight with the
wrong loadout — silently, with no error and no visible wrong value anywhere
except the damage numbers.

**Resolution:** `Session._cache_key` appends the acquired UPGRADE IDs in
acquisition order. `test_run_battle.gd` asserts both that the keys differ and
that the resulting lists differ, so the key cannot be "simplified" back.

**Worth noting for later phases:** this is the general shape of the risk in
beta 0.2. The battle engine is correct and proven, and the ways to break it are
by feeding it state the beta 0.1 callers could never construct. Memoization keys,
validation that assumed an empty collection, and defaults that were unreachable
are all the same class.

### P-022 · One battle constructor, where the alpha has three

**Forced by:** nothing — a consolidation, recorded because it diverges.

The alpha has `createQuickMatchBattle`, `createRunBattle`, and
`recreateBattleFromConfig` as three entry points that each assemble a battle.
The beta funnels Quick Match and Run through one private `_create_battle`, with
the public functions supplying only what differs.

**Why:** a battle's immutable identity and config are stamped in exactly once,
so the two paths cannot drift in what they consider a battle's identity. The
authorization's §2 makes duplicated battle construction "presumptively wrong",
and two constructors that agreed today would be two to keep agreeing.

**What the split still preserves:** the LINK and ICE resolution RULES differ by
caller and stay with the caller. Quick Match resolves both maxima from the
identities at construction; a Run passes the ceiling it froze at setup and the
ICE its step resolved. `_create_battle` takes them as values rather than
branching on a mode flag, so there is no `if run` inside the constructor.

**Verification:** fast parity 150/150 after the refactor. The refactor touches
battle construction, which is battle-affecting under §21.1 even though it is not
the battle core — see the DEEPSCAN recommendation in the Phase C report.

### P-023 · ODANSHAY's authored ICE coincides with the step-4 ladder value

**Not a deviation** — a content coincidence that will mislead anyone reading
these numbers, recorded so it is not rediscovered the hard way.

Every authored System has `BASE_ICE = 100`, and the step-4 modifier is `+150`.
ODANSHAY's authored `BASE_ICE` is **250**. So the correct rule (a Boss takes its
authored ICE unmodified) and the wrong one (apply the step-4 modifier to a
100-base System) produce the *same number*.

This is almost certainly why the dead step-4 row in `RUN_ENCOUNTERS` (P-017)
went unremarked: nothing about the shipped numbers reveals which rule produced
them.

**Consequence for testing:** a Boss ICE test cannot be written as "not equal to
the System ladder value" — that assertion fails against correct code. The
distinguishing case is the double-count, `boss_base + 150 = 400`, and that is
what `test_run_battle.gd` asserts against.

## Beta 0.2 Phase D — persistence

### P-024 · Two save schemas, versioned independently

**Forced by:** the battle record ceasing to be the top level.

Beta 0.1 wrote a battle and nothing else, because a Quick Match is always inside
one. A Run is saveable with no battle at all — on a Path Choice, a Build, a
result, or the `PENDING_BOSS_BATTLE` stop — so the battle record becomes a
member of a session envelope.

The authorization's §16 asks to "add only the new Run/setup/route fields
needed", which reads as an additive change. It is not: it is a restructure of
where the battle record lives. Raised as §C6 of the authorization review.

**Resolution:** `SessionSave.SCHEMA = 3` versions the ENVELOPE.
`SaveState.SCHEMA = 2` continues to version the nested battle record, and the
beta 0.1 serializer writes and validates it **unchanged**. That serializer
carries the continuation proof this build has no reason to re-earn (§16: "reuse
the Beta 0.1 battle serializer and its existing deterministic-continuation
proof"), so folding it into the envelope would have meant re-proving it.

Two schemas that move independently is the honest description: a change to how
a battle serializes need not invalidate every Run save, and vice versa.

### P-025 · `SessionSave` owns the file; `SaveState` keeps the Quick Match entry points

**Forced by:** one path, `user://save.json`, and now two kinds of session.

`SaveState.write` / `read` / `clear` were the file API and are called from
`battle_screen.gd` and `main.gd`. Leaving them writing bare battle records
alongside a new Run writer would give one path two writers, and a Run save and a
Quick Match save would overwrite each other.

**Resolution:** they now delegate to `SessionSave`, writing and reading the
envelope in `QUICK_MATCH` mode. The existing UI is untouched and keeps working.
`SaveState.read` REJECTS a Run envelope rather than returning the battle inside
it — that entry point has nowhere to put the Run, and handing back the bare
battle would strip the Run around it and silently lose the progression.

Phase F rewires the UI to `SessionSave.read` directly and handles every mode.

### P-026 · The envelope cross-checks the Run against its battle

**Not forced** — an invariant the alpha does not state, added because the shape
of the envelope makes the failure possible.

A Run envelope carries both the Run and, when one is in progress, its battle.
Those two independently record the encounter: the Run has `opponent_id`,
`host_id`, and `upgrade_ids`, and the battle's immutable identity has its own
copies stamped at construction.

Nothing stops a hand-edited or partially-written save from carrying a Run and a
battle that describe DIFFERENT encounters. The result would load, and the
player would fight one battle while the Run believed in another — the sort of
failure that surfaces three screens later as an impossible reward.

`SessionSave.from_dict` rejects the envelope when they disagree, and separately
rejects a phase that contradicts the envelope's contents (`ACTIVE_BATTLE` with
no battle record, or a battle held in a phase that cannot be in one).

### P-027 · No migration test, deliberately

Per D-030, a version bump invalidates saves for the whole pre-release beta line.
`test_session_save.gd` asserts that a beta 0.1 bare battle record is REJECTED,
which is the finished behaviour rather than a gap — and there is deliberately no
test that any save survives a version boundary.

Recorded because the absence is a decision, not an oversight: a future reader
finding no migration coverage should not add some.

## Beta 0.2 Phase E — the Run differential harness

### P-028 · `build_origin` was stamped a step too early — found by this harness

**A real port defect, caught on the harness's very first comparison.** Recording
it in full because the way it hid is more useful than the fix.

**What the beta did:** `advance_after_victory()` and `retry_battle()` set
`Run.build_origin = CARRIED_RUN`. The reasoning seemed sound — the build carries
forward to the next battle, so mark it carried.

**What the alpha does:** `RunInfo.buildOrigin` records the origin of the build
the Run has **COMMITTED**, and it moves only when a Build screen is CONFIRMED
(`main.ts:2051`). `CARRIED_RUN` is the starting origin of the Build SCREEN's own
state — `beginBuild(..., first ? 'DEFAULT' : 'CARRIED_RUN')` — which becomes
`PLAYER_EDITED` if the player changes anything, and is committed to the Run only
on confirmation.

Two different pieces of state with the same vocabulary. The beta had collapsed
them.

**Why nothing else caught it.** Every behavioural test passed: the build DID
carry forward, editing DID mark PLAYER_EDITED, retry DID preserve the build.
`build_origin` is telemetry — it does not gate a rule — so no assertion about
gameplay could see it. It is exactly the class of divergence §21.2 describes as
"externally meaningful state" that behavioural tests do not reach.

**Resolution:** `build_origin` is now moved only by `confirm_build()` and by the
edit functions. `opening_build_origin()` supplies what a freshly opened Build
screen starts with (DEFAULT at Battle 1, CARRIED_RUN afterwards and on retry),
which is what Phase F will hand to the Build screen.

**The general lesson**, for `lessons-learned.md`: a differential harness earns
its cost on the fields nobody would think to assert. The route offers — the part
we were worried about, and had already pinned with fixtures in Phase B — were
correct. The bug was in a field that only exists to be logged.

### P-029 · Run records are ordered token arrays, not stringified objects

**Forced by:** hashing the same state in two languages.

Hashing a serialized object across GDScript and JavaScript means depending on
Dictionary iteration order, JS property order, and both serializers agreeing on
number formatting — the beta already needed `Fingerprint._float_to_js` and
`_quote` to make that work for the battle traces (P-010).

Run records sidestep all of it: each is a fixed sequence of tokens joined with
`|`, hashed as SHA-256 over the lines. There is no key order to preserve and no
float to format, and a divergence points at a field position rather than at the
serializer.

### P-030 · The Run walk plays no battles, and the choice policy is shared

The harness treats every encounter as won and never constructs a battle. Battle
behaviour is proven by DEEPSCAN, and replaying it inside the Run walk would pay
twice for the same evidence while making 2,000 walks unaffordable.

The consequence is that **the choice policy is part of the comparison**: both
engines must fork identically at every Path Choice or the walks diverge
legitimately and prove nothing. `_choose(seed, step) = (seed + step) %
PATH_CHOICE_COUNT` is duplicated verbatim in `tools/run_trace.gd` and
`tools/gen/run_trace_alpha.ts`, alternating so a body of seeds covers the left
path, the right path, and every mixture rather than walking one edge of the tree.

**Cost, for the record:** 2,000 walks take under two seconds across both
engines, against the battle matrix's ~90 minutes for 5,250 battles. There is
deliberately no DEEPSCAN tier for run walks — the range is simply set wide.

## Beta 0.2 Phase F — presentation

### P-031 · The safe area moved to the shell, not to each new screen

**Forced by:** §20.1, and by the arithmetic being easy to get subtly wrong.

Beta 0.1 applied the safe area in `battle_screen._apply_safe_area` only, because
the battle was the one screen running edge to edge. Beta 0.2 adds five top-level
screens, and opting each one in individually is how one of them gets missed —
with the failure being unreachable controls under a cutout rather than anything
that looks wrong in a screenshot.

**Resolution:** `UiTheme.safe_area_insets(control_size)` owns the arithmetic;
`main._fresh_screen` adds it to the shell margins every menu is built into, so a
new screen is covered by existing. The battle screen keeps its own padding and
delegates the insets, and its behaviour is unchanged.

The conversion is the part worth guarding: `DisplayServer` reports the safe area
in PHYSICAL screen pixels while the viewport is stretched, so the ratio between
them converts one to the other. Getting that wrong is invisible on a device with
no cutout and badly wrong on one with it — the tablet cannot detect this class
of bug at all, which is what makes it an S25 question.

### P-032 · The debug skip is not the only force-win, and that is worth knowing

Beta 0.1's battle screen already carries a debug bar with `win` and `lose`
buttons. With a Run active those now flow through the Run result screen, so
**force-win at battle level already existed** before D-029 was written.

What Phase F adds is a `[debug] Skip battle N` on the Run BUILD screen, which
resolves the encounter as a victory without constructing a battle at all. It
was placed there rather than on the defeat screen deliberately: the point of
D-029 is to reach a later battle without playing the earlier ones, and a control
that first requires playing a battle to completion saves nothing.

The two are complementary — the debug bar exercises the real result path, the
Build skip is faster on the tablet — but D-029 was written as though no force
win existed, and it slightly over-scoped as a result. Nothing needs undoing;
recorded so the 0.3 wizard work starts from what is actually there.

The skip is correctly absent on the Boss route: skipping there would fabricate
the Battle 4 result §12 forbids.

### P-033 · No Back from Hacker Selection to Boss Selection

The Boss is committed and FIXED at the moment it is chosen — that commit is the
destructive New-Run boundary. A Back button from Hacker Selection would either
be a lie (it cannot change the Boss) or a second destructive boundary hiding
behind an ordinary-looking control.

Boss Selection itself has Back, to the title, because nothing is committed yet.

## Beta 0.2 Phase G — logging

### P-034 · The route seed IS the Run identity

**Not a deviation** — a choice worth stating, because the obvious alternative is
worse.

§15 asks for a "Run ID/identity as needed by existing logging". A generated UUID
would have served for joining records, and nothing else. The route seed already
exists, is already persisted, is unique per Run in practice, and — unlike a UUID
— **reproduces the Run**: seed plus choice sequence regenerates every offer.

So `Run.route_seed` is kept alongside the advancing `route_rng_state` and stamped
on every session record as `run`. One grep reassembles a Run from a log file, and
a Run reported from a device replays in the harness from the same value.

### P-035 · A fourth stream, not a second pipeline

§19 forbids a second instrumentation pipeline. `SessionLog` writes through
`LogStore.append` into `session.jsonl`, beside `battles`, `turns`, and `events`,
with the existing budget and trim policy. It owns no file handling of its own.

Records are written at BASIC and above. The volume argument that gates per-turn
logging does not apply here — a complete Run produces about a dozen records —
and a release build that could not say which route a player took would defeat
the point of having the stream.

**On schema parity:** these deliberately do NOT reproduce the alpha's menu-log
shapes. §19 says to prefer compact records that answer development questions
over faithful shapes with no consumer, and nothing reads the alpha's menu logs.
What is preserved is the join model: `RUN_BATTLE_STARTED` carries `battle_id`,
which is the key into the battle streams, so routing decisions connect to how
the battle actually went.

### P-036 · The build in play is separate from the constructed build

**Found after the phase gates, by a question about what the seed controls.**

Random Quick Match rolls its own build and must not overwrite Constructed Quick
Match's remembered one (§22.32). Beta 0.2 first satisfied that by never touching
`_build` at all and passing the rolled array straight into
`Session.create_quick_match`.

That was right about the preset and wrong about everything downstream.
`_start_battle` — which is what the result screen's **Replay this seed** and
**New battle** call — read `_build`. So after a Random Quick Match, replaying
kept the same System and HOST and silently swapped the loadout for the
constructed one. A control that says "replay" changed what was played.

**Resolution:** `_qm_build` is the build the Quick Match currently in play is
using, and `_build` stays the constructed working build. Both are duplicated on
assignment, so neither can alias into the other, and editing the Build screen
cannot mutate a battle already under way. Verified on device: a rolled
`PRG_H_002/006/005/003` replayed identically, and the Constructed Build screen
still opened on the untouched default.

This is the alpha's own arrangement — `session.build` is separate from the
remembered preset — and collapsing the two is what created the bug.

**Why no gate caught it:** the requirement was expressed as a prohibition
("must not overwrite"), and the implementation satisfied the prohibition
exactly. Nothing stated the positive half — that a replay must reproduce what
was played — so there was no assertion to fail. §22.32 is a one-directional
requirement, and one-directional requirements are satisfiable in ways that break
their unstated other half.

## Beta 0.3 Phase A — preflight corrections

### P-037 · F-002 applied to Run battles as well as Quick Match

§2.2 scopes the fresh-gameplay-seed correction to Quick Match. The same
divergence exists for Run battles: `main.gd` passed the single `_seed` field to
`Session.create_run_battle` too, and the alpha does not pass a seed to
`createRunBattle` either (`main.ts` calls it with two arguments).

Fixing only Quick Match would have left every Run battle — all four, including
the Boss battle 0.3 is about to add — starting on seed 0 in a release build,
where the debug field does not exist. Fixed both.

**The state split that makes it work:** `_seed_override` is what the tester
pinned (-1 for none) and `_gameplay_seed` is what the battle in play actually
used. Only the second is what *Replay this seed* replays. Collapsing them is how
P-036 happened; keeping them apart is what stops the same class recurring.

The debug field now starts **empty**, with the last seed shown as placeholder
text. Pre-filling it with the current value would silently re-pin whatever the
previous battle used, which is precisely the behaviour being fixed.

`QUICK_RANDOM_ROLLED` now carries `setup_seed` **and** `gameplay_seed` as
separate fields. Neither alone reproduces a match — one picks the identities,
the other the board — and merging them would recouple setup to gameplay
randomness in the way §17 forbids.

### P-038 · F-001 fixed by reserving space, not by reacting to it

The battle root's board `frame` is the only child with `SIZE_EXPAND_FILL`, so it
absorbs whatever the labels below leave unused. `_turn_label` began with no text
and `_message` was floored at a *minimum* height, so both grew on the first
action and the board lost the difference — re-centring inside its
`AspectRatioContainer`, which reads as a jump.

Both now reserve their final size up front: `_turn_label` carries "Turn 1" from
construction, and `_message` has a **fixed** height computed from the resolved
theme font (`get_height(font_size) × MESSAGE_LINES`) with `max_lines_visible`
capped to match, so neither growth nor overflow can change the board's
allocation. `MESSAGE_LINES` is one constant shared by the reservation and the
scrollback trim, so they cannot disagree.

The height is measured from the font rather than guessed from the font size —
line height is not font size, and a guess close enough at one viewport scale
stops being close enough at another (the alpha→beta ~2.51× scale makes that a
live concern, see D-026).

**Verified on device**, since neither fix is visible to a headless test: the
board's top edge measured y=670 before and after the status area gained lines,
and the debug bar showed a random gameplay seed rather than 0.

## Beta 0.3 Phases C-E — the ODANSHAY mechanic layer

### P-039 · The mechanic is its own file, hooked at two turn edges

`scripts/logic/boss.gd` holds the Override overlay, the threshold, and the
end-of-turn placement. `Game.run_enemy_phase` gains exactly two calls, both
guarded by `Boss.is_boss_battle`, so an ordinary System battle pays one
comparison per turn edge and nothing else changes.

Beta 0.1 had already reserved the whole vocabulary — `Tile.Special.Type.OVERRIDE`,
`Types.OwnerKind.BOSS`, `Types.EVT.BOSS_MECHANIC`, the `OVERRIDE_*` constants,
the three `FN_*` IDs, an OVERRIDE tint in the presentation registry, and a
generic special serializer — and even left comments in `run_enemy_phase` marking
where the two hooks belong. Phase C's "overlay state, render, save
compatibility" needed no new representation at all.

`Game.cast_boss_mechanic` is the one new entry point: it invokes an authored
Function through the ordinary `_cast_actor` path with `OwnerKind.BOSS` and the
Boss's ID, at no charge cost. There is no bespoke SHAKE and no bespoke ATTACK.

### P-040 · Three test premises that were wrong, and what they revealed

Every one of these was the test being wrong rather than the code, but each named
something worth writing down.

**DATABEND recovers capacity by destroying its own Overrides.** The first
cap-exhaustion test blanketed the board in Boss Overrides expecting capacity to
stay at zero, since DATABEND retains Boss overlays. It does — but it also
resolves the Syncs it creates, and resolution destroys Packets *with their
overlays*. Capacity recovered on the first attempt. That is the mechanic working
exactly as intended, and it means the cap is genuinely close to unreachable in
play, as the alpha's own comment says.

Forcing the cap needs a board DATABEND cannot regenerate: every cell standard
(a neutral carries no overlay, so it is always regenerated) **and** match-free
(or the substitution creates a Sync, which cascades, which frees capacity
again). `_make_all_standard_match_free` searches colour/shape pairs per cell for
one that leaves the board with no match.

**CODESHATTER lands 69, not 70, on a completed Run.** BRACER reduces damage from
all sources by 1 and is one of the four UPGRADEs a Run necessarily holds by
Battle 4. The raw value is asserted against a Run with no UPGRADEs; the
modifier applying is asserted separately, because "CODESHATTER is ordinary
Function damage" is the actual requirement (§21.36) and a hardcoded 70 would
have quietly asserted the opposite.

**A hardcoded board coordinate is a board roll.** `Vector2i(5, 5)` happened to
be a neutral, which cannot carry an overlay, so the replacement test measured
nothing. Tests that need an axis-bearing cell now search for one.

### P-041 · The cap's off-by-one, asserted rather than commented

`place_end_of_turn` iterates `0..OVERRIDE_DATABEND_RETRY_LIMIT` **inclusive** —
6 capacity checks and 5 DATABEND casts, because the final iteration abandons
instead of casting. The test asserts both numbers independently rather than
trusting the loop to be read correctly, since `for i in LIMIT` is the natural
GDScript spelling and gets both wrong.

### P-042 · The battle screen resolved a Boss as a System, and the fix is a union accessor

**Found by the tablet, after every headless gate had passed.**

`battle_screen._refresh_all` read the opponent's name with
`Content.system(state.identity["opponent_id"])`. For `BOS_01` that reports an
unknown id and returns an empty Dictionary; indexing `["name"]` on it then
**aborted the refresh function**, so the ICE readout on the following line never
ran. The header showed `SYSTEM / ICE 0/1` over a battle whose logic — Programs,
axes, ICE, mechanic — was entirely correct.

Two things made it invisible until a human looked at a screen:

- **the scene layer has no headless coverage**, by design (`test_layer_purity`
  exists to keep logic OUT of it), so 3,000-plus tests and 300 Boss parity
  battles all passed;
- **an aborted refresh looks like stale UI, not like a crash.** The battle kept
  playing. Only the header was wrong, and only because the abort happened to
  land between two lines.

**Resolution:** `Content.opponent(kind, id)` and `Content.opponent_of_identity`
resolve through the identity UNION, so no caller has to know which registry an
opponent lives in. `Session._opponent_content` now defers to it as well, and an
audit of the other six `Content.system(` callers found all of them already
guarded by an explicit kind check.

**The general shape**, worth carrying into 0.4: a union type with two registries
invites exactly one bug — reaching for the common branch by habit. The fix is
not vigilance, it is removing the choice from the caller.

### P-043 · Two literals that outlived their build

The title screen read `beta 0.2` through all of 0.3 development because the
subheading was a typed string, and the Run result headline said "System ICE
breached" over ODANSHAY for the same reason as P-042.

Both now derive from data — the version from `Content.GAME_VERSION`, the
headline from the opponent union. A literal that duplicates a value the build
already knows is a small thing that is wrong on a predictable schedule.

### P-044 · A debug readout must not be load-bearing for layout

AN-006 in full: the battle screen overflowed a 1080 px viewport because the
debug bar's seed Label shared a row with the controls, and a Label's minimum
width is its text. F-002 changed the seed from a permanent `0` to a ten-digit
random, so a row that had always been narrow became the widest thing in the
scene — clipping the board, the opponent's Program column, and the bar's own
last button.

Three things about it are worth carrying forward.

**It was invisible on the tablet.** 1200 px absorbed the growth; 1080 did not.
That is twice now that the tablet structurally could not see a phone defect
(P-031 was the other), and both times the mechanism was width, not touch.

**It presented as a Boss bug and was not one.** The failing screenshot was a
Boss battle and the passing one a Quick Match, which is a coincidence of seed
digit count — 10 versus 7. Two device screenshots are a sample of two, and the
difference between them is not necessarily the variable you changed.

**The first fix was worse than the bug.** Clipping the label restored the layout
and truncated the seed to `seed 205953`. The seed exists so a device
observation can be replayed in the harness; a clipped one cannot. The rule the
fix should follow is not "make it fit" but *a debug affordance must not
participate in the game's layout at all* — hence its own row.

### P-045 · `wm size` turns a phone-only defect into an ordinary iteration

`adb shell wm size 1080x2340` on the tablet reproduced AN-006 exactly, which
meant the fix was developed and verified without the phone attached.
`wm size reset` restores the device.

Worth reaching for before requesting a device window: the phone is the
director's daily handset and tethering time is a real cost, while the tablet is
always connected and may be configured freely. It restarts the app, so relaunch
after setting it, and the screenshot comes back letterboxed to the emulated
aspect (886x1920 for a 1080x2340 override) — measure ratios, not raw pixels.

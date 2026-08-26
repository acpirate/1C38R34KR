# 1C38R34KR

A mobile-first match-3 combat game with a cyberpunk hacking theme.

This is the **beta line**: a Godot 4 rewrite targeting Android. Previously
developed under the working name *Breach*, which reached a feature-complete
`alpha-0.7.0` as a TypeScript/Vite canvas build. **That build is the behavioural
specification for this rewrite**, and the relationship is enforced rather than
intended — see [The differential gate](#the-differential-gate).

## Status

**`beta-0.3.0` — the complete Alpha gameplay loop, playable on hardware.**

A full Run now runs end to end, Boss included:

```
New Run → Boss → Hacker → Deck → (Path → Build → Battle) ×3 → ODANSHAY → Run Complete
```

With Beta 0.3 the Godot line contains the whole alpha feature skeleton: the
battle engine, Constructed and Random Quick Match, Run setup and progression,
the route/HOST/UPGRADE layer, Boss selection, Battle 4, the ODANSHAY mechanic,
and Run completion.

| Phase | State |
| --- | --- |
| A — preflight fixes (board jump, fresh gameplay seeds) | ✅ |
| B — Boss identity, battle construction, Run Complete | ✅ |
| C–E — Override overlay, Boss turn hook, mechanic payloads | ✅ |
| F — result and session integration | ✅ |
| G — Boss telemetry | ✅ |
| H — Boss differential, DEEPSCAN, regression | ✅ |
| I — device verification | ✅ tablet complete; phone layout defect found and fixed |
| J — README, closeout, diff review | ✅ see `staging/1c38r34kr-beta-0.3.0-port-handback.md` |

| Gate | State |
| --- | --- |
| Headless logic tests | ✅ 3,122 passing across 23 suites |
| **Boss differential vs the alpha** | ✅ **300/300** — ODANSHAY on every HOST |
| Run/session differential | ✅ 1,000/1,000 walks |
| Battle parity (fast, 150 battles) | ✅ 150/150 |
| Battle parity (full matrix, "DEEPSCAN") | ✅ **5,250/5,250** |
| Tablet device gate | ✅ full Run to RUN COMPLETE, clean log |
| Phone layout | ✅ verified at 1080×2340 after AN-006 |

Deliberately **not** in 0.3: additional Bosses, a Boss scripting layer, Boss
Quick Match, permanent progression, a completion matrix, production art or
audio, broad balance work, Windows/browser/iOS deployment, and package-ID
finalization.

### Devices

| Device | OS | GPU | ABI | Cold start |
| --- | --- | --- | --- | --- |
| Galaxy S25 Ultra | Android 16 / API 36 | Adreno 830 | arm64-v8a only | 238 ms |
| Galaxy Tab A 10.1 (SM-T580, 2016) | Android 8.1 / API 27 | Mali-T830 | **armeabi-v7a only** | 2.4 s |

Between them they justify shipping both ABI slices: neither device runs the
other's. The tablet is the performance canary and the routine test rig; what it
cannot settle is touch feel, thumb-reach layout, and display-cutout behaviour,
which stay phone questions.

## The differential gate

The alpha is not documentation to consult — it is an executable oracle the beta
is checked against.

Both engines emit an ordered stream of gameplay events. The harness plays the
same battles in both, normalizes the two streams to a common spelling, and
compares them **byte for byte**. An extra, missing, or reordered event is a test
failure by design.

This rests on one thing: the alpha's `mulberry32` PRNG is ported **exactly**,
rather than replaced with Godot's PCG32. Every stochastic decision downstream —
board generation, refill, Shake, overlay placement — is only comparable because
the draw sequence is identical.

Two genuine port bugs surfaced this way, both of which produced perfectly
plausible battles that were simply not the alpha's:

- `_cast_shake` discarded the board, because `BoardOps.shake` REPLACES it and
  the result was never written back.
- A PASSIVE carrier used the HOST's ID where the alpha used the PASSIVE's,
  attributing effects to the wrong actor.

Neither would have been caught by a unit test. Both reproduced headlessly from a
seed in seconds.

```bash
node tools/gen/parity.mjs        # stripped run, ~2.5 min, gate for every change
```

The full matrix is codenamed **DEEPSCAN** — 5,250 battles per engine, ~90
minutes. Two tiers exist because a gate nobody runs because it is slow is not a
gate.

### The Run differential

Beta 0.2 added a second harness, for the layer it ports. It walks complete Runs
in both engines and compares the session state — offered and committed
identities, acquisition order, resolved ICE, and the route stream's progression
— hash-first, dumping full records on a mismatch.

```bash
node tools/gen/run_parity.mjs --seeds 0-1999
```

It plays **no battles**: every encounter is treated as won, because DEEPSCAN
already proves battle behaviour and replaying it here would pay twice for the
same evidence. That is what makes it cheap — 2,000 complete Run walks compare in
under two seconds across both engines, against DEEPSCAN's ninety minutes.

It earned its cost immediately. `build_origin` was being stamped one transition
too early: the beta marked a build `CARRIED_RUN` when a path opened, where the
alpha moves it only when a Build screen is *confirmed*. Every behavioural test
passed throughout — the field gates no rule, so nothing asserting *gameplay*
could see it. Only a comparison that dumps everything and diffs it wholesale was
ever going to find that.

**The lesson, recorded for the AAR:** the risk that was predicted and pinned with
fixtures — route generation, with its retry loops and draw-order traps — turned
out to be correct code. The divergence lived in a field nobody would think to
write an assertion about.

### The Boss differential

Beta 0.3 reaches Boss combat through the same instruments rather than a third
harness. Naming a `BOS_*` id in `--sys` selects the Boss fixture route on both
sides — `headlessBoss` on the alpha, which Alpha 0.7.0 §45 had already built for
automated coverage, and `create_boss_trace_battle` on the beta. Player-facing
Quick Match stays System-only on both.

```bash
node tools/gen/boss_parity.mjs --seeds 0-59
```

**300/300 with no divergence**, ODANSHAY across all five HOSTs. The first
comparison diverged on hash while matching on event count, turn count, winner,
and even the exact Override cells chosen — the cause was field naming, since the
beta writes snake_case and the alpha's camelCase wins at the trace boundary.

## Requirements

- Godot **4.7.2** stable, standard (non-Mono) build
- JDK **17**
- Android SDK with build-tools **36.1.0**, platform **36**, platform-tools
- A debug keystore at `~/.android/debug.keystore`
- Node (for the parity harness only, not for the game)

Godot 4.7.2 pins compileSdk/targetSdk 36 and minSdk 24. The NDK is **not**
required unless custom Gradle builds are enabled.

Release builds are signed with a **temporary** key held outside the repo. Build
one with `bash tools/export-release.sh`. The real key is deliberately deferred
until the package ID is final — see `staging/release-signing-brief.md`. Debug and
release builds carry different signatures and cannot install over one another.

## Commands

```bash
godot --headless -s res://tools/run_tests.gd            # 3,122 logic tests, no GPU
godot --headless --import                               # refresh the class cache
node tools/gen/parity.mjs                               # battle differential gate
node tools/gen/run_parity.mjs --seeds 0-1999            # Run/session differential
node tools/gen/boss_parity.mjs --seeds 0-59             # Boss differential
godot --headless -s res://tools/run_trace.gd -- --seed 42 --full   # dump one Run walk

godot --headless --export-debug "Android" build/1c38r34kr.apk
bash tools/export-release.sh                            # signed release APK
adb install -r build/1c38r34kr.apk
adb shell monkey -p com.acpirate.ic38r34kr -c android.intent.category.LAUNCHER 1
adb exec-out screencap -p > shot.png
```

The launcher activity is `GodotAppLauncher`; `GodotApp` is what ends up running
but is not exported and cannot be started directly.

Run `godot --headless --import` after adding any new `class_name` — until the
class cache refreshes, `--check-only` reports "Could not find type" for files
that are perfectly fine.

## Layout

```
data/       ten CSV datasets — the content source of truth
scripts/    game logic (pure RefCounted, no scene-tree dependencies)
scenes/     Godot scenes — render from state, send intents to it
tests/      23 headless suites
tools/      headless runners: tests, traces, both parity harnesses
staging/    build authorizations, decisions log, port notes, design reference
```

~20,600 lines of GDScript: 11,200 logic, 3,400 scenes, 5,100 tests, 900 tools.

## Architecture

### Layer purity

Game logic never touches `Node`, the scene tree, `Tween`, `Input`,
`DisplayServer`, or `await`. Rules live as plain `RefCounted` classes; scenes
render *from* state and send intents *to* it.

This is not a style preference. It is what makes the game headlessly runnable,
and therefore what makes the differential gate possible at all. It is enforced by
`test_layer_purity.gd` rather than by review, because the drift happens one
convenient `get_tree()` at a time.

### The event stream

The logic layer resolves a turn completely and synchronously, returning an
ordered list of events. The renderer replays that list over time. The renderer
never drives rules.

Every returned batch passes through one funnel, `Game._collect`, which is where
metrics and logging attach — both strictly read-only over the stream. Nothing
bypasses it, including the debug shortcuts: a diagnostic outside the funnel
produces a result screen that disagrees with the battle it describes.

### The presentation registry

`scenes/battle/packet_style.gd` is the single mapping from frozen gameplay
identity to visual appearance — the alpha→final translation matrix. When the art
pass lands, replacing a drawn shape with a sprite is a change there and nowhere
else.

`PacketColor` and `PacketShape` are enums `0..5` whose **ordering is
load-bearing**: weak sets derive as the enum-order complement of an authored
strong set, so reordering them silently rewrites every System's and Hacker's
weaknesses. What each of those twelve values *looks like* is entirely the
registry's business. `test_presentation.gd` bans colour literals elsewhere under
`scenes/`, because the rule is only useful if it cannot quietly erode.

Sizes are ratios of the design viewport, never raw pixels. The alpha laid out
against a 430 px CSS viewport and this project's base viewport is 1080 px;
`UiTheme.px()` carries values across so the relationship stays visible.

### The Run

A Run is four battles against an escalating opponent, with a Boss chosen at the
start and fought last. Before each battle the player picks one of two offered
`SYS + HST + UPG` packages, and the choice is committed **before** Build opens,
so the build can be edited against a known encounter and the newly acquired
UPGRADE is live for the battle it was offered alongside.

Three properties are worth stating because they are what most of the port's
verification is aimed at.

**Offers are state, not a screen.** They are generated once, persisted verbatim,
and restored verbatim. Reloading a Path Choice can never reroll it, and
`open_path_choice` refuses to run when offers are already pending rather than
silently regenerating them. A game that quietly changed its mind about what it
was offering would be a bad enough bug to be worth a guard.

**Route randomness is a separate stream.** Generating or reviewing a route never
touches the battle's gameplay RNG, so the board, refills, and AI sequence for a
given gameplay seed are unaffected by anything the route layer does. The route
stream's state is persisted with the Run, so an interrupted Run produces the same
sequence an uninterrupted one would.

**The generators are transcribed draw-for-draw.** Three of them resolve their
constraints with retry loops over the ordinary sampler rather than by exclusion,
and one returns without drawing at all when a single UPGRADE remains. Every
"cleaner" rewrite produces offers that are individually legal and *wrong for the
seed* — a divergence no behavioural test can see. `tests/fixtures/route.json` is
generated from the alpha and pins both the offers and the route RNG state after
each generation, which is what catches a wrong draw *count* rather than just a
wrong result.

The Run's `route_seed` doubles as its identity in the logs. A generated ID would
have joined records and nothing else; the seed also *reproduces* the Run, so a
line from a device log replays in the harness.

### The Boss

Battle 4 is ODANSHAY, and a Boss is a distinct identity layer rather than a
System with a flag: the battle carries `opponent kind = BOS`, no `SYS_ID` is
ever synthesized, and its ICE is the authored **250** with no step modifier
applied. (The step-4 `+150` in the encounter table is dead data, carried
deliberately — see port-notes P-017.)

Everything ODANSHAY shares with a System runs through the ordinary enemy path:
Program charge routing, the Function phase, countdowns, HOST effects, Hacker
UPGRADE PASSIVEs, cascades, damage attribution. `scripts/logic/boss.gd` adds
exactly three things, and `run_enemy_phase` gains exactly two guarded hooks.

**The Override.** At the end of every non-terminal Boss turn ODANSHAY places
exactly **three** Overrides — or **none**. A valid target is an axis-bearing
Packet not already carrying a Boss-owned overlay; a *Hacker*-owned overlay is a
valid target and is replaced. Placement preserves the Packet's colour and shape,
so it deals no damage, grants no charge, and creates no Sync. Its only effect is
to count.

**The fallback.** With fewer than three targets it places nothing and casts
DATABEND to make room, then re-checks. The bound is the shipped alpha's and the
off-by-one matters: `attempt` runs `0..LIMIT` inclusive, which is **5 DATABEND
activations across 6 capacity checks** — the final iteration abandons rather
than casting. A loop written `for i in LIMIT` gets both numbers wrong.

**The threshold.** At `override_count >= 15` — never `== 15`, since Overrides
arrive in threes — CODESHATTER fires as ordinary Function damage, then REBOOT if
the Hacker survived. REBOOT regenerates the board under the **prevent-matches**
invariant, so the result contains no Sync at all; it does not generate freely
and decline to resolve. That distinction is D-032, and it matters because the
looser reading would leave a pre-made Sync for the *player* to collect.

None of this is a phase transition. Overrides accumulate again and the threshold
can fire on a later turn.

### Saves

The battle record is no longer the top level. A Run is saveable with no battle
at all — parked on a Path Choice, a Build, a result, or the
`PENDING_BOSS_BATTLE` stop — so it became a member of a session envelope.

There are two schemas, versioned independently. `SessionSave.SCHEMA` versions the
envelope; the beta 0.1 battle serializer keeps its own and is reused **unchanged**,
because it carries a continuation proof there was no reason to re-earn.

**Old saves are rejected, never migrated.** For the whole pre-release beta line a
version bump invalidates saves and they are discarded (D-030). That is the
finished behaviour, not a stopgap: there is deliberately no migration path, no
compatibility shim, and no test that a save survives a version boundary. What is
required, and tested, is that a save survives *within* a version.

The envelope also cross-checks the Run against its battle. Both independently
record the encounter, and a save where they disagree would load fine while the
player fought one battle and the Run believed in another.

### Content

Ten CSV datasets are the source of truth. They are marked `importer="keep"` so
Godot's translation importer leaves them alone, and `*.csv` is in the export
filter so the raw files ship inside the APK.

Content is hashed into a **fingerprint** (`49c229cd-8ma`) using a JS-compatible
canonical JSON encoding, so the beta and the alpha agree on the hash for
identical content. The fingerprint appears on the title screen, in every save,
and on every battle log record — it is the first question worth asking when a
device behaves unlike the harness. A save whose fingerprint does not match is
rejected rather than restored against different rules than it was made under.

## Documents

| File | What it is |
| --- | --- |
| `staging/1c38r34kr-beta-0.3.0-build-authorization.md` | the scope and completion standard this build answers to |
| `staging/1c38r34kr-beta-0.3.0-authorization-review.md` | the pre-implementation review of it |
| `staging/1c38r34kr-beta-0.2.0-build-authorization-revised.md` | the previous build's scope |
| `staging/1c38r34kr-beta-0.2.0-authorization-review.md` | the pre-implementation review of it, and the seven items that needed resolving |
| `staging/1c38r34kr-beta-0.1.0-build-authorization.md` | the previous build's scope, kept for reference |
| `staging/decisions.md` | append-only decision log, D-001..D-032 |
| `staging/port-notes.md` | every place the translation is non-literal, P-001..P-045 |
| `staging/architect-notes.md` | design items raised during the port that must **not** be built as part of it |
| `staging/1c38r34kr-beta-0.3.0-port-handback.md` | **the close-out** — what shipped, what the verification caught, and the final diff review |
| `staging/1c38r34kr-beta-0.2.0-port-handback.md` | the beta 0.2 close-out |
| `staging/port-handback.md` | the beta 0.1 close-out |
| `staging/lessons-learned.md` | what cost time and why, for the AAR |
| `staging/design-reference/` | the alpha's screens, and the rules extracted from them |

## Build targets

| Target | Status |
| --- | --- |
| Android (standalone) | primary |
| Windows desktop | later release |
| Browser (hosted) | later release |
| iOS / Linux / macOS | only if demand appears |

GDScript rather than C#, because Godot's .NET builds cannot export to web —
choosing C# would strand the planned browser target permanently.

## Note on the package ID

`com.acpirate.ic38r34kr` is a **placeholder**. An Android package ID is
permanent once published to Google Play, so it must be finalized before the
first store upload.

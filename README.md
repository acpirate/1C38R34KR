# 1C38R34KR

A mobile-first match-3 combat game with a cyberpunk hacking theme.

This is the **beta line**: a Godot 4 rewrite targeting Android. Previously
developed under the working name *Breach*, which reached a feature-complete
`alpha-0.7.0` as a TypeScript/Vite canvas build. **That build is the behavioural
specification for this rewrite**, and the relationship is enforced rather than
intended — see [The differential gate](#the-differential-gate).

## Status

**`beta-0.2.0` — the full pre-Boss Run loop, playable on hardware.**

A complete Run runs end to end on an Android device:

```
New Run → Boss → Hacker → Deck → Path → Build → Battle → … ×3 → Boss route → stop
```

Beta 0.1's battle engine is unchanged underneath it. What 0.2 adds is the
progression layer around it: route generation, UPGRADE acquisition, Run-scoped
build carry-forward, and a session save that survives with no battle in progress.

| Phase | State |
| --- | --- |
| A — Run/setup session model, route RNG, UPGRADE state | ✅ |
| B — route generation and Random Quick Match setup | ✅ pinned draw-for-draw against the alpha |
| C — battle-engine integration, ICE ladder, Run Build | ✅ caught a latent PASSIVE cache collision |
| D — session save envelope (schema 3) | ✅ |
| E — Run differential harness | ✅ found a real port defect on its first comparison |
| F — Run screens and shared safe-area policy | ✅ |
| G — Run/session logging | ✅ |
| H — full verification, tablet and phone gates | ✅ |
| I — README, closeout, diff review | ✅ see `staging/port-handback.md` |

| Gate | State |
| --- | --- |
| Headless logic tests | ✅ 2,906 passing across 22 suites |
| Route fixture parity (offers **and** draw counts) | ✅ 6 seeds × 4 generations, exact |
| Run/session differential | ✅ 2,000/2,000 walks, no divergence |
| Battle parity (fast, 150 battles) | ✅ 150/150, no divergence |
| Battle parity (full matrix, "DEEPSCAN") | ✅ 5,250/5,250, no divergence |
| Tablet device gate | ✅ full Run loop, both relaunch cases, clean log |
| S25 phone gate | ✅ layout, safe area, and scroll on every new screen |

**Battle 4 stops deliberately.** The Run reaches its committed Boss route,
persists the complete `Boss + HOST + UPGRADE` package, and enters
`PENDING_BOSS_BATTLE` rather than fabricating a battle. Beta 0.3 consumes that
state. Beta 0.2 never substitutes a System for the Boss, and `create_run_battle`
refuses to build one.

Deliberately **not** in 0.2, per the build authorization: Boss combat and the
ODANSHAY Override mechanics (CODESHATTER, REBOOT, DATABEND), permanent
progression, a completion matrix, Windows/browser/iOS deployment, production art
or audio, and any balance change.

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
godot --headless -s res://tools/run_tests.gd            # 2,906 logic tests, no GPU
godot --headless --import                               # refresh the class cache
node tools/gen/parity.mjs                               # battle differential gate
node tools/gen/run_parity.mjs --seeds 0-1999            # Run/session differential
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
tests/      22 headless suites
tools/      headless runners: tests, traces, both parity harnesses
staging/    build authorizations, decisions log, port notes, design reference
```

~19,300 lines of GDScript: 10,800 logic, 3,200 scenes, 4,400 tests, 900 tools.

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
| `staging/1c38r34kr-beta-0.2.0-build-authorization-revised.md` | the scope and completion standard this build answers to |
| `staging/1c38r34kr-beta-0.2.0-authorization-review.md` | the pre-implementation review of it, and the seven items that needed resolving |
| `staging/1c38r34kr-beta-0.1.0-build-authorization.md` | the previous build's scope, kept for reference |
| `staging/decisions.md` | append-only decision log, D-001..D-031 |
| `staging/port-notes.md` | every place the translation is non-literal, P-001..P-036 |
| `staging/architect-notes.md` | design items raised during the port that must **not** be built as part of it |
| `staging/1c38r34kr-beta-0.2.0-port-handback.md` | **the close-out** — what shipped, what the verification caught, and the final diff review |
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

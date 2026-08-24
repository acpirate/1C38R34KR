# 1C38R34KR

A mobile-first match-3 combat game with a cyberpunk hacking theme.

This is the **beta line**: a Godot 4 rewrite targeting Android. Previously
developed under the working name *Breach*, which reached a feature-complete
`alpha-0.7.0` as a TypeScript/Vite canvas build. **That build is the behavioural
specification for this rewrite**, and the relationship is enforced rather than
intended — see [The differential gate](#the-differential-gate).

## Status

**`beta-0.1.0` — Constructed Quick Match, playable on hardware.**

A complete battle runs end to end on an Android device: `System → HOST → Build →
Battle → Result`, with save and resume, a full metrics report, and every rule the
alpha implements.

| Phase | State |
| --- | --- |
| 1 — foundation, types, constants, exact RNG | ✅ |
| 2 — content loading, validation, fingerprint | ✅ `49c229cd-8ma`, matches the alpha |
| 3 — battle core | ✅ complete battles resolve headlessly |
| 4 — differential harness and parity repair | ✅ found two real port bugs |
| 5 — whitebox presentation and touch | ✅ |
| 6 — save, logging, metrics, integration | ✅ |
| 7 — full headless + differential + device gate | 🟡 DEEPSCAN green; device checklist outstanding |
| 8 — README, diff review, commit | ⬜ in progress |

| Gate | State |
| --- | --- |
| Headless logic tests | ✅ 1,047 passing across 16 suites |
| Differential parity (stripped, 150 battles) | ✅ 150/150, no divergence |
| Differential parity (full matrix, "DEEPSCAN") | ✅ 5,250/5,250, no divergence |
| Android **debug** APK from CLI | ✅ 55.3 MB, arm64-v8a + armeabi-v7a |
| Android **release** APK | ✅ 50.4 MB, signed with a **temporary** beta key |

Deliberately **not** in 0.1, per the build authorization: New Run, route/path
selection, UPGRADE acquisition, Boss combat and ODANSHAY/Override mechanics,
Random Quick Match, Windows/browser/iOS deployment, permanent progression,
production art or audio, and any balance change.

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
godot --headless -s res://tools/run_tests.gd            # 1,047 logic tests, no GPU
godot --headless --import                               # refresh the class cache
node tools/gen/parity.mjs                               # differential gate

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
tests/      16 headless suites
tools/      headless runners: tests, traces, parity harness
staging/    build authorization, decisions log, port notes, design reference
```

~15,200 lines of GDScript: 9,000 logic, 2,700 scenes, 2,800 tests, 700 tools.

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
| `staging/1c38r34kr-beta-0.1.0-build-authorization.md` | the scope and completion standard this build answers to |
| `staging/decisions.md` | append-only decision log, D-001..D-027 |
| `staging/port-notes.md` | every place the translation is non-literal, P-001..P-014 |
| `staging/architect-notes.md` | design items raised during the port that must **not** be built as part of it |
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

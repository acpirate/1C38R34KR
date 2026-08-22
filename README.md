# 1C38R34KR

A mobile-first match-3 combat game with a cyberpunk hacking theme.

This is the **beta line**: a Godot 4 rewrite targeting Android. The game itself
is not here yet — this commit is the verified development environment and
project skeleton that the port will be built into.

Previously developed under the working name *Breach*, which reached a
feature-complete `alpha-0.7.0` as a TypeScript/Vite canvas build. That build is
the behavioral specification for this rewrite.

## Status

**`beta-0.1.0` — environment scaffold**

| Piece | State |
| --- | --- |
| Godot 4.7.2 project, portrait, GL Compatibility | ✅ imports clean |
| Ten authored CSV datasets | ✅ carried over, packed into the APK |
| Headless test runner | ✅ 628 passing |
| Phase 1 — foundation | ✅ exact-parity RNG, types, constants |
| Phase 2 — content pipeline | ✅ fingerprint `49c229cd-8ma` matches the alpha |
| Android debug APK export from CLI | ✅ 54.9 MB, signed, arm64-v8a + armeabi-v7a |
| Runs on hardware | ✅ two devices — see below |

Verified on both ends of the supported range:

| Device | OS | GPU | ABI | Cold start |
| --- | --- | --- | --- | --- |
| Galaxy S25 Ultra | Android 16 / API 36 | Adreno 830 | arm64-v8a only | 238 ms |
| Galaxy Tab A 10.1 (SM-T580, 2016) | Android 8.1 / API 27 | Mali-T830 | **armeabi-v7a only** | 2.4 s |

Between them they justify shipping both ABI slices: neither device can run the
other's. Dropping `armeabi-v7a` would drop the tablet, and dropping
`arm64-v8a` would drop the phone.
| Game logic | ⬜ not started — awaiting architect handoff |
| UI / scenes | ⬜ not started |

## Requirements

- Godot **4.7.2** stable, standard (non-Mono) build
- JDK **17**
- Android SDK with build-tools **36.1.0**, platform **36**, platform-tools
- A debug keystore at `~/.android/debug.keystore`

Godot 4.7.2 pins compileSdk/targetSdk 36 and minSdk 24. The NDK is **not**
required unless custom Gradle builds are enabled (Android plugins, GDExtension).

## Commands

```bash
godot --headless -s res://tools/run_tests.gd          # logic tests, no GPU
godot --headless --export-debug "Android" build/1c38r34kr.apk
adb install -r build/1c38r34kr.apk
adb shell am start -n com.acpirate.ic38r34kr/com.godot.game.GodotAppLauncher
adb shell screencap -p /sdcard/s.png && adb pull /sdcard/s.png
```

The launcher activity is `GodotAppLauncher`. `GodotApp` is the activity that
ends up running, but it is not exported and cannot be started directly.

## Layout

```
data/       ten CSV datasets — the content source of truth
scripts/    game logic (pure RefCounted, no scene-tree dependencies)
scenes/     Godot scenes — render from state, send intents to it
tools/      headless runners: tests, balance harness
```

## Architecture

Game logic never touches `Node` or the scene tree. Rules live as plain
`RefCounted` classes; scenes render *from* state and send intents *to* it. This
mirrors the alpha's `logic/` vs `render/` split and is what keeps the game
testable headlessly — which in turn keeps the deterministic balance harness
meaningful after the port.

CSV files are marked `importer="keep"` so Godot's translation importer leaves
them alone, and `*.csv` is in the export include filter so the raw files ship
inside the APK.

## Build targets

| Target | Status |
| --- | --- |
| Android (standalone) | primary |
| Windows desktop | later release |
| Browser (hosted) | later release |
| iOS / Linux / macOS | only if demand appears |

GDScript is used rather than C#, because Godot's .NET builds cannot export to
web — choosing C# would strand the planned browser target permanently.

## Note on the package ID

`com.acpirate.ic38r34kr` is a **placeholder**. An Android package ID is
permanent once published to Google Play, so it must be finalized before the
first store upload.

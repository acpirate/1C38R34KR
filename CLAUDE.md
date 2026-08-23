# 1C38R34KR

Mobile-first match-3 combat game with a cyberpunk hacking theme. This repo is the
**beta** line: a Godot 4 rewrite targeting Android first.

Formerly developed under the working name *Breach*.

## Where the specification lives

This repo does **not** yet contain the game. The behavioral specification is the
completed alpha at:

```
C:\Users\chode\breach
```

That is a TypeScript/Vite canvas build, feature-complete through `alpha-0.7.0`.
Treat it as read-only reference material — never modify it from this repo.

Highest-value files there:

| Path | What it defines |
| --- | --- |
| `README.md` | Full feature narrative and current status |
| `staging/breach-alpha-0.7.0-coding-agent-handoff.md` | Current implementation spec |
| `src/logic/` | Game rules: board, match, resolve, session, passives, save, rng, metrics |
| `src/render/`, `src/main.ts` | UI layer — **replaced wholesale**, not ported |
| `scripts/harness.ts`, `batch.ts`, `bot.ts` | Deterministic headless simulation |

## Build specification and decisions

| Path | What it is |
| --- | --- |
| `staging/1c38r34kr-beta-0.1.0-architect-handoff.md` | Current build specification — scope, architecture, verification gates |
| `staging/decisions.md` | Append-only decision log with rationale. Append new decisions here rather than burying them in commit messages. |

## Devices

| Role | Device | Availability |
| --- | --- | --- |
| **Primary / daily** | Galaxy Tab A 10.1 (`SM-T580`) — Android 8.1, Mali-T830, **armeabi-v7a**, 1.9 GB RAM | wireless: `adb connect 192.168.1.14:5555` |
| **Target / periodic** | Galaxy S25 Ultra (`SM-S938U`) — Android 16, Adreno 830, **arm64-v8a** | on request only |

The tablet's USB port is flaky, so it runs over **wireless ADB**. Reconnect with
`adb connect 192.168.1.14:5555`; only re-run `adb tcpip 5555` over a cable if it
has rebooted.

It is also set to **stay awake while charging**. Without that the screen sleeps,
the Godot activity pauses and stops the instant it launches, and a screenshot
comes back pure black with an empty Godot log — which reads exactly like a
rendering failure and is not one. If a device build ever appears to render
nothing, check `dumpsys power` before debugging the renderer.

Both ABI slices ship because **neither device can run the other's**. Do not
propose dropping either to save APK size.

The tablet is the canary: 2016 hardware surfaces performance problems the
flagship hides. If it feels good there, it feels good anywhere. What the tablet
*cannot* settle is touch feel, thumb-reach layout, and portrait composition — a
10-inch 16:10 tablet is a different input regime from a phone. Those remain S25
questions.

**Protocol for the S25** — it is the director's daily phone and tethering time
is a real cost:

1. Run `adb devices` first. Never assume it is attached.
2. Batch every check that needs it into one window; finish headless work first.
3. Say **"plug the phone in now"** and list what will run.
4. Say **"the phone can come off now"** the moment the last step finishes.
5. Capture screenshots during the window — `adb screencap` is self-serve.

With both attached, target explicitly: `adb -s <serial> …`.

## Architecture rules

1. **Game logic never touches `Node` or the scene tree.** Rules live in plain
   `RefCounted` classes under `scripts/logic/`. Scenes render *from* state and
   send intents *to* it. This mirrors the alpha's `logic/` vs `render/` split and
   is what keeps the game testable headlessly.
2. **Content stays in CSV.** The ten datasets in `data/` are the source of truth,
   carried over from the alpha. Filenames were shortened (`breach datastructures
   - BOS.csv` → `bos.csv`); contents are unchanged. Parse with
   `FileAccess.get_csv_line()`.
3. **Determinism is a feature.** Seeded RNG must reproduce runs exactly, so the
   balance harness ported from the alpha stays meaningful.
4. **GDScript only.** C#/.NET cannot export to web, which would strand the
   planned hosted browser target.

## Commands

```bash
godot --headless -s res://tools/run_tests.gd        # logic tests, no GPU
godot --headless --export-debug "Android" build/1c38r34kr.apk
adb install -r build/1c38r34kr.apk
adb shell am start -n com.acpirate.ic38r34kr/com.godot.game.GodotAppLauncher
adb logcat -d godot:V '*:S'                          # Godot's own output only
adb shell screencap -p /sdcard/s.png && adb pull /sdcard/s.png
godot-gui                                            # open the editor
```

Notes that cost time to rediscover:

- The launcher activity is `GodotAppLauncher`. `GodotApp` is what ends up
  running but is not exported — starting it directly fails with a
  `SecurityException`.
- `adb logcat` without a tag filter is drowned in Samsung WindowManager spam.
  Filter to `godot:V '*:S'`.
- `adb screencap` works, so visual checks on real hardware are self-serve — no
  need to ask a human to look at the phone.

`godot` is a shim at `%USERPROFILE%\bin\godot.cmd` pinned to Godot **4.7.2**.

## Build targets

| Target | Status |
| --- | --- |
| Android (standalone) | primary, beta 0.1 |
| Windows desktop | secondary, later release |
| Browser (hosted) | secondary, later release |
| iOS / Linux / macOS | only if demand appears |

## Toolchain facts

- Godot 4.7.2 stable, standard (non-Mono) build
- Godot 4.7.2 pins: compileSdk/targetSdk **36**, minSdk **24**, build-tools **36.1.0**, JDK **17**
- Android SDK at `%LOCALAPPDATA%\Android\Sdk` (command-line tools only, no Android Studio)
- NDK is **not** installed. It is only needed for custom Gradle builds — Android
  plugins or GDExtension. Install `ndk;29.0.14206865` (~4 GB) if that day comes.
- `com.acpirate.ic38r34kr` is a **placeholder** package ID. It is permanent once
  published to Play, so finalize it before the first store upload.

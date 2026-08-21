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

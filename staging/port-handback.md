# 1C38R34KR beta 0.1.0 — port handback

**To:** the architect
**From:** the implementing agent
**Date:** 2026-08-23
**Subject:** Phase 8 close-out — what shipped, what did not, and what the next
authorization should account for.

The final diff review required by completion-standard item 14 is folded into
this document (§5) rather than delivered separately, on the director's
instruction.

---

## 1. Verdict

**Beta 0.1.0 is complete against the build authorization, with two exceptions,
both known and neither a defect in the port.**

The build is playable end to end on Android hardware, its behaviour is proven
identical to the alpha's across 5,250 differential battles, and 1,047 headless
tests pass. The exceptions are a placeholder package ID and a temporary signing
key, both deliberate and both the director's to resolve when the game's identity
is settled.

### Completion standard, item by item

| # | Requirement | State |
| --- | --- | --- |
| 1 | Exact RNG test vectors pass | ✅ |
| 2 | Required content loads and validates | ✅ ten datasets |
| 3 | Fingerprint matches the alpha | ✅ `49c229cd-8ma` |
| 4 | Headless logic tests pass | ✅ 1,047 across 16 suites |
| 5 | Full §6 differential matrix passes | ✅ **5,250/5,250, no divergence** |
| 6 | Constructed Quick Match as System → HOST → Build → Battle → Result | ✅ |
| 7 | `HAK_01` / `DEK_01` resolved by stable ID | ✅ |
| 8 | Save/resume preserves deterministic continuation | ✅ proven differentially |
| 9 | Debug logging VERBOSE, release BASIC | ✅ verified in a real release build |
| 10 | Debug APK verified on physical hardware | ✅ two devices |
| 11 | Touch/device checks honestly completed | ✅ see §3 |
| 12 | No deferred 0.2+ feature added | ✅ |
| 13 | README describes the shipped build | ✅ rewritten |
| 14 | Final diff reviewed | ✅ §5 |
| 15 | Committed and pushed to `origin/main` | ✅ 40 commits |
| 16 | Working tree clean | ✅ |

**Carried, not closed:** the package ID `com.acpirate.ic38r34kr` is a
placeholder, and release builds are signed with a temporary key. Neither blocks
0.1; both must be resolved before any store upload. Background in
`release-signing-brief.md`.

---

## 2. The differential gate — the load-bearing result

**DEEPSCAN: 5,250 battles per engine, zero divergence.**

| Variant | Seeds | Pairings | Battles | Result |
| --- | --- | --- | --- | --- |
| `default` | 0–199 | 15 | 3,000 | no divergence |
| `reinforced` | 0–49 | 15 | 750 | no divergence |
| `timer` | 0–49 | 15 | 750 | no divergence |
| `uncapped` | 0–49 | 15 | 750 | no divergence |

Every battle contributes one hash over its normalized event stream plus an event
count. Identical on both means the whole rules translation is faithful for that
battle — not "produces the same winner", but *emits the same events in the same
order with the same payloads*.

This rests on porting the alpha's `mulberry32` by hand rather than substituting
Godot's PCG32. Everything stochastic downstream is comparable only because the
draw sequence is identical. **If a future change ever makes the RNG diverge, the
gate stops being a gate** — treat `test_rng.gd` as the foundation it is.

The alpha carries exactly one modification, `scripts/trace.ts`, a headless trace
instrument (D-010, D-017). Its suite is **272 passing**, verified again at
handback time. The alpha is otherwise untouched and remains read-only spec.

### What the gate caught

Two real port bugs, neither reachable by unit test, both producing entirely
plausible battles that were not the alpha's:

- `_cast_shake` discarded the board — `BoardOps.shake` REPLACES it, and the
  result was never written back.
- A PASSIVE carrier used the HOST's ID where the alpha used the PASSIVE's,
  attributing effects to the wrong actor.

Both reproduced headlessly from a seed in seconds. **The harness earned its
placement in Phase 4** — the authorization's insistence that it precede
presentation was correct, and for a reason worth restating: it was used far more
as a debugger than as a final test.

---

## 3. Device verification

Two devices, both ends of the supported range. Neither runs the other's ABI,
which is what justifies shipping both slices.

| | Galaxy Tab A 10.1 (SM-T580) | Galaxy S25 Ultra (SM-S938U) |
| --- | --- | --- |
| OS | Android 8.1 / API 27 | Android 16 / API 36 |
| GPU | Mali-T830 | Adreno 830 |
| ABI | armeabi-v7a only | arm64-v8a only |
| Resolution | 1200×1920, no cutout | 1080×2340, 72 px cutout, 42 px corners |
| Cold start | 2.4 s | 239 ms |

### §13 checklist

| Check | By | Result |
| --- | --- | --- |
| Complete touch-played victory | director | ✅ |
| Complete touch-played defeat | director | ✅ |
| Authored Systems/HOSTs exercised | both | ✅ |
| Invalid swap / revert | director | ✅ "feel is good" |
| Function target / cancel | agent + director | ✅ |
| Bomb countdown / detonation | director | ✅ |
| EBUFF countdown → Buff | director | ✅ |
| Visible cascades | both | ✅ |
| Save / quit / resume | director | ✅ through the supported path |
| Safe-area / cutout correctness | agent, on the phone | ✅ |
| Clean Godot log | agent, both devices | ✅ zero errors or warnings |

**On the cutout specifically**, since it is the one check the tablet structurally
could not answer: the phone reports a 72 px top inset and a centred punch-hole.
The battle header renders at y≈105 there against y≈17 on the cutout-free tablet
— that delta is `_apply_safe_area` querying
`DisplayServer.get_display_safe_area()` rather than hardcoding, and it works.

**A gap the architect should know about:** safe-area handling is applied by the
battle screen only. The menu screens in `main.gd` use fixed margins. It does not
matter today — they are centred panels whose content sits well below the inset,
and only a panel border passes under the punch-hole — but that is luck rather
than design. A future screen that puts text near the top would land under the
cutout. Left unchanged deliberately: it is not a defect today, and fixing
unrequested things during a port is how ports drift.

---

## 4. What is in the build

~15,200 lines of GDScript: 9,000 logic, 2,700 scenes, 2,800 tests, 700 tools.

| Layer | Contents |
| --- | --- |
| `scripts/logic/` | rules, content pipeline, RNG, save, metrics, logging — no scene-tree dependency |
| `scenes/` | whitebox presentation, touch input, event playback |
| `tests/` | 16 headless suites, 1,047 assertions |
| `tools/` | test runner, trace instrument, trace normalizer, parity harness |
| `data/` | ten authored CSVs, the content source of truth |

Three invariants are enforced by test rather than by review, because each erodes
gradually and silently:

- **Layer purity** — `scripts/logic/` may not touch `Node`, `SceneTree`,
  `Tween`, `Input`, `DisplayServer`, or `await`. This is what makes the game
  headlessly runnable and therefore what makes the gate possible at all.
- **The presentation registry** — no colour literal may appear under `scenes/`
  outside `packet_style.gd`. The registry is the alpha→final translation matrix;
  when the art pass lands, replacing a drawn shape with a sprite is a change
  there and nowhere else.
- **Event-name discipline** — event types come from `Types.EVT`, never bare
  strings, because the event stream is both the logic/render boundary and the
  substrate of the differential gate.

One structural note worth carrying into 0.2: **every returned event batch passes
through a single funnel, `Game._collect`**, which is where metrics and logging
attach, both strictly read-only. Nothing bypasses it — including diagnostics.
The debug win/lose buttons originally reached past `Game` into `Resolve` and so
skipped metrics, producing a result screen that reported zero damage for a
battle that plainly had some. If there is one funnel, everything goes through
it.

---

## 5. Final diff review

40 commits; 154 files changed, 31,944 insertions, 97 deletions from the initial
scaffold.

Reviewed for anything that should not ship:

| Check | Finding |
| --- | --- |
| Unexpected file types | none — all `.gd`, `.csv`, `.md`, `.cfg`, `.tscn`, `.mjs`, `.ts`, `.sh`, images |
| `TODO` / `FIXME` / `HACK` / `XXX` | none (apparent matches are the word "HACKER") |
| Stray `print()` in logic or scenes | none |
| Hardcoded absolute paths in shipped code | none |
| Secrets, keystores, passwords | none tracked; verified by `git grep` |
| Debug-only surfaces in release | none — gated on `OS.is_debug_build()`, verified absent in a real release build |

**Two things the review surfaced that are fine but should be named:**

1. **`tools/gen/parity.mjs` hardcodes machine paths** (`C:\Users\chode\breach`,
   `C:\Users\chode\1C38R34KR`, `%USERPROFILE%\bin\godot.cmd`). Dev tooling, never
   shipped, and the harness is useless without both repos anyway — but it means
   the gate does not run on another machine without editing three constants.
   Worth parameterising if anyone else ever runs it.
2. **The fixture generators carry `cd C:\Users\chode\breach` in comments.** Same
   category; documentation of how they were run, not code.

Neither is a defect. Both are recorded here so the architect is not surprised.

---

## 6. Deferred, with reasons

Full detail in `architect-notes.md`. Summarised because these are the items most
likely to be mistaken for oversights:

| ID | Item | Why deferred |
| --- | --- | --- |
| **AN-001** | DISABLER/Drain should be manually targeted at a System Program, not auto-target the fullest slot | It is a **design change**, and the alpha auto-targets too. Changing behaviour mid-port would make the differential gate fail for a reason that is correct. Land it after parity sign-off. |
| **AN-002** | Scroll feel — no inertia, no end-of-travel feedback, two-finger gesture is learned rather than discovered | The gesture works and was verified with real multitouch, but "works" and "feels right" are different standards. Needs a human iterating on a device. Recommendation is a drag-threshold on the controls, which removes the need for the two-finger gesture rather than papering over it. |
| **AN-003** | Force-closing from the recents switcher leaves a stale save offered as Continue | Director's call to backburner. Nothing is corrupt — the save is exactly what it claims; the problem is that "resume" implies a continuity it does not have. Recommendation is autosave at turn boundaries, which the save format is already designed around. |

**AN-001 deserves the architect's attention first.** It is small, the renderer
already has every piece it needs (`_system_boxes` exist; only
`MOUSE_FILTER_IGNORE` stops them being tappable), no logic-layer change is
required — and it is currently the reason the two-column battle layout is only
half useful. The System's charge bars are on screen precisely so the player can
schedule around them, and there is no way to act on that reading.

Also deliberately absent, per authorization §12: New Run, route/path selection,
UPGRADE acquisition, Boss combat and ODANSHAY/Override mechanics, Random Quick
Match, Windows/browser/iOS deployment, permanent progression, production art or
audio, balance changes.

---

## 7. For the next authorization

Three observations from building this one. Full versions in
`lessons-learned.md`; these are the ones that should shape how 0.2 is specified.

### 7.1 Property requirements are multipliers, not line items

The authorization made save/resume a completion-standard item **and** required it
to "preserve deterministic continuation". That second clause is a property
requirement, and everything downstream followed necessarily from it: D-022 pulled
the serializer a whole phase earlier to sit with the harness, because a
round-trip equality test passes with an incompletely captured RNG state and only
a *continuation* test catches it.

The result was ~520 lines and a permanent place in the differential gate for a
feature whose player-visible surface is two buttons. The director's assessment is
that this was disproportionate for a game of this kind, and that it came at the
expense of gameplay concepts closer to the point of the exercise.

**The expensive decision was made in the specification, not the
implementation.** Words like "provably deterministic", "byte-identical", "never
silently repaired" do not add a feature — they add a proof obligation to
everything the feature touches. Price them when they are written. A rough cost
estimate against each completion-standard item, before the build starts, would
have made this visible while it was still cheap to cut.

### 7.2 The whitebox is earned progress, not scaffolding

The initial position was that the visual look would be overhauled entirely, so
alpha fidelity did not matter. That understated what the alpha's whitebox
was: it encoded real UX findings accumulated over the whole POC — both sides'
Programs visible at once, coloured glyphs on dark rather than white glyphs on
coloured fields, neutrals as static rather than absence, select-then-confirm on
phone lists, dim-the-illegal-regions during targeting.

None of that is art, and all of it survives an art pass. **Extract a POC's
styling as display-independent rules before porting**, or the same discovery gets
paid for twice. Recorded, with the extracted rules, in `design-reference/`.

The concrete trap: the alpha's sizes are CSS pixels on a 430 px viewport and this
project's base viewport is 1080 px. Carried across literally, every label came
out ~2.5× too small on device. `UiTheme.px()` now derives the multiplier from the
two viewport widths so the relationship stays visible.

### 7.3 Human playtesting finds a class the harness cannot

1,047 tests and 5,250 parity battles had nothing to say about any of these:

- a targeted Function that armed and instantly cancelled, because Android
  delivers one tap as **both** a `ScreenTouch` and an emulated `MouseButton`;
- text too small to read at arm's length;
- a refill that stalled just before settling, because arithmetic cancelled a term
  out and every spawned Packet started at the same point;
- a scroll region that was unreachable because Buttons ate the drag.

None are rules bugs, so no rules gate could see them. **Get a human on the build
early, and treat "it feels wrong" as a bug report** — every one of those reports
turned out to name a specific, findable defect.

---

## 8. Handover facts

| | |
| --- | --- |
| Repo | `C:\Users\chode\1C38R34KR`, `origin/main`, clean |
| Alpha | `C:\Users\chode\breach` — read-only spec, one sanctioned modification (`scripts/trace.ts`), 272 tests green |
| Fast gate | `node tools/gen/parity.mjs` — 150 battles, ~2.5 min, run on every change |
| Full gate | `node tools/gen/parity.mjs --deepscan` — 5,250 battles, ~95 min |
| Tests | `godot --headless -s res://tools/run_tests.gd` |
| Debug APK | `godot --headless --export-debug "Android" build/1c38r34kr.apk` |
| Release APK | `bash tools/export-release.sh` — temporary key, outside the repo |
| Decisions | `decisions.md`, D-001..D-028 |
| Non-literal translations | `port-notes.md`, P-001..P-014 |
| Deferred design | `architect-notes.md`, AN-001..AN-003 |
| Retrospective | `lessons-learned.md`, 13 entries |
| Design reference | `design-reference/` — the alpha's screens and the rules extracted from them |

**Two gotchas that cost time and will cost it again:**

- Run `godot --headless --import` after adding any new `class_name`. Until the
  class cache refreshes, `--check-only` reports "Could not find type" for files
  that are perfectly fine.
- A GDScript parse error **hangs** the headless test runner rather than failing
  it — `_initialize()` aborts so `quit()` is never reached. `run_tests.gd`
  guards this with `can_instantiate()` plus a `_process` fallback; do not remove
  either.

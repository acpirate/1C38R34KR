# Decision Log

Append-only record of decisions that shaped 1C38R34KR, so any of them can be
traced back to who made it, when, and why.

**Decider** is `director` for the project owner's calls, `agent` for calls
delegated to the implementing agent, and `agent → director` where the agent
recommended and the director approved.

Newest entries at the bottom. Do not rewrite history here — supersede an entry
with a new one and mark the old one `SUPERSEDED BY D-0NN`.

---

## D-001 — Engine: Godot 4

**2026-08-20 · director · ACCEPTED**

Breach moves from its TypeScript/Vite canvas build to Godot 4 for the beta line.

**Consequence:** the ~15,600-line alpha is rewritten, not migrated. The ~7,000
lines under `src/logic/` transfer as design; `src/main.ts` and `src/render/`
(~3,900 lines) are replaced outright.

---

## D-002 — Language: GDScript, not C#

**2026-08-20 · agent → director · ACCEPTED**

**Why:** Godot's .NET/C# builds cannot export to web at all. Choosing C# would
permanently strand the planned hosted-browser target. C# is closer to the
alpha's TypeScript and would have made the port marginally more familiar, but
not at the cost of a whole build target.

**Consequence:** no static type checking of the strength TypeScript provided.
Mitigated by enums over string unions (handoff §6), a `StringName` event
registry, and a debug-only event-shape validator (§7).

---

## D-003 — Name and repository

**2026-08-20 · director · ACCEPTED**

The game is renamed **1C38R34KR** for the beta line. Repository
`acpirate/1C38R34KR`, public, at `C:\Users\chode\1C38R34KR`.

"Godot" is deliberately excluded from the name: the engine is an architecture
choice that could change, the name is not.

**Consequence:** the alpha repo at `C:\Users\chode\breach` becomes read-only
behavioral specification. See D-010 for the one sanctioned exception.

---

## D-004 — Android package ID is a placeholder

**2026-08-20 · director · ACCEPTED (provisional)**

`com.acpirate.ic38r34kr`, explicitly provisional.

**Why this shape:** Android package segments cannot begin with a digit, so
`...1c38r34kr` is rejected outright by the exporter and the build. The display
name on the device is the unmodified `1C38R34KR`; only the identifier is
constrained.

**Consequence:** a package ID is permanent once published to Google Play. This
must be finalized before the first store upload. Open item.

---

## D-005 — Android SDK via command-line tools only

**2026-08-20 · agent → director · ACCEPTED**

No Android Studio. cmdline-tools, platform-tools, build-tools 36.1.0, platform
36 — about 5 GB rather than 13 GB, and fully scriptable.

**Consequence:** no emulator or device-manager GUI. Irrelevant in practice —
testing is on physical hardware (D-006) and `adb` covers the rest.

**Note:** cmdline-tools 23 replaced `sdkmanager` with a new `android` CLI.
`--licenses` is now a no-op and package syntax is `build-tools;36.1.0`. Most
Godot Android documentation predates this change.

---

## D-006 — Device testing on physical hardware

**2026-08-20 · director · ACCEPTED**

Galaxy S25 Ultra over USB, not an emulator.

**Why:** touch feel and performance on an emulator are misleading for a
match-3, and this is a mobile-first game.

**Consequence:** verified working — Android 16 / API 36, Adreno 830, OpenGL ES
3.2, arm64-v8a only. `adb screencap` also means visual verification is
self-serve for the agent rather than requiring the director to look at the phone.

---

## D-007 — CSV files marked `importer="keep"`

**2026-08-20 · agent · ACCEPTED (technical)**

Godot's `csv_translation` importer claimed all ten datasets on first import and
exploded them into 60+ `.translation` resources.

**Why it matters:** the raw `.csv` files would **not** have been packed into the
APK. `FileAccess` reads would have passed in the editor and failed on device —
a failure that surfaces far from its cause.

**Fix:** each `data/*.csv` carries an `.import` file setting `importer="keep"`,
and `*.csv` is in the export preset's include filter. Verified against actual
APK contents: all ten appear at `assets/data/`.

**Consequence:** do not change either setting. Any new data file needs the same
treatment.

---

## D-008 — Beta 0.1 scope: one Quick Match battle

**2026-08-20 · agent · ACCEPTED**

Beta 0.1 delivers one complete Constructed Quick Match battle playable on
device. Runs and routes → 0.2. Boss layer → 0.3. Desktop and web → 0.4.

**Why:** 15,600 lines in one build is unverifiable, and verification is the
entire problem in a rules port — a subtly wrong charge-routing rule does not
crash, it quietly makes the game worse. One battle still exercises content
loading, validation, board, resolve, charge routing, effects, PASSIVEs,
countdowns, the bot, metrics, rendering, touch, and save. The deferred layers
are the ones the alpha itself added last, on top of a stable battle, in builds
0.5–0.7.

**Consequence:** HOST Selection is pulled *forward* into 0.1 despite being a
later layer, because every battle requires exactly one HOST and HOST PASSIVEs
are one of four PASSIVE source kinds. Porting the PASSIVE runtime with a
quarter of it stubbed is worse than including them.

---

## D-009 — Port mulberry32 exactly; do not use Godot's RNG

**2026-08-20 · agent · ACCEPTED**

The alpha's `rng.ts` is mulberry32. Godot's `RandomNumberGenerator` is PCG32 and
produces a completely different sequence.

**Why:** identical seed plus identical rules must produce an identical battle in
both engines. That property is the foundation of D-010's differential gate, and
substituting the RNG forfeits it. There is no other mechanical check available
on a 7,000-line rules translation.

**Consequence:** four 32-bit arithmetic hazards must be handled in GDScript
(64-bit signed ints, `Math.imul` semantics, `>>>` vs `>>`, float division) —
handoff §9. A committed test vector of 1,000 outputs across four seeds gates
everything else in the build.

---

## D-010 — Trace entry point added to the alpha repository

**2026-08-20 · agent (delegated by director) · ACCEPTED**

**The question:** the differential gate (handoff §10) requires the alpha to emit
a normalized event trace so both engines' output can be compared. That means
adding a file to a repository designated read-only (D-003). Is "read-only"
absolute, or does it mean "do not change its behavior"?

**Delegation:** the director declined to arbitrate — *"i dont fully understand
the decision point, I'll leave it to your discretion, just document it so we can
trace"* — which is why this log exists.

**Decision: add it.** "Read-only" is taken to mean *do not change its behavior*.

**Why the risk is near zero, verified rather than assumed:** `Game`'s public
methods — `startPlayerPhase()`, `fireProgram()`, `fireDeckFunction()`,
`runEnemyPhase()` — already return `GameEvent[]`. The event stream is the public
API's return value, not internal state. The trace emitter is therefore:

- one new file, `scripts/trace.ts`
- importing the same `scripts/harness.ts` construction glue that `batch.ts`,
  `smoke.ts`, and `hpladder.ts` already import
- calling the same public methods and serializing what they return
- **zero modifications to any existing file** — no rules, no logic, no data,
  no existing script

It is a sixth headless script in a directory that already holds five.

**Why it is worth doing at all:** it is the difference between verifying a
7,000-line rules translation by reading it and verifying it by running it. When
a divergence appears, the first differing line names the turn, the mechanism,
and usually the exact function. Declining would strike handoff §10 and §22 and
fall back to hand-written per-rule tests — substantially weaker coverage for
substantially more work.

**Consequence / constraints:**

- committed to the alpha repo as its own commit, with a message stating it adds
  a headless instrument and changes no behavior
- the alpha's own test suite must pass before and after, unchanged
- this remains the **only** sanctioned modification to the alpha. Any future
  proposal to touch it needs a new entry in this log.

---

## D-011 — Single-agent execution model

**2026-08-20 · director · ACCEPTED**

No Senior/Junior split. One agent owns inspection, plan, implementation,
integration, tests, device verification, README, and push.

**Supersedes:** the per-build Senior/Junior experiment used from Alpha 0.2.0.
The director's phrasing — *"no junior senior anymore, all one mode"* — reads as
ending the experiment rather than declining it for this build.

---

## D-012 — Diagnostic tooling included; selection delegated

**2026-08-20 · director (inclusion) + agent (selection) · ACCEPTED**

Director: *"yes include diagnostic tools on your judgement of optimizing
development vs testing effort"*.

**Selection criterion applied:** does it save more development time than it
costs to build?

**Included:** seed display and entry; same-seed battle restart; force win/lose;
grant full charge; event log overlay; playback speed control.

Seed display is the highest-leverage of these — it turns an unreproducible
"something looked wrong on the phone" into a seed that replays in the headless
harness with a full event trace, connecting device observation to D-010.

**Excluded, with reasons:** the Find Sync hint (a player-facing feature, not a
diagnostic, with a known narrow-viewport overlap defect); arbitrary board-state
injection (expensive, and largely redundant against D-010); a performance
overlay (Godot has built-in monitors).

**Constraint:** all diagnostics sit behind `OS.is_debug_build()` and must be
unreachable in a release build. A diagnostic may read `GameState` and call
ordinary logic entry points, never mutate state directly — a force-win that
zeroes ICE behind the rules' back eventually produces a bug report about the
rules.

---

## D-013 — Beta 0.1 presentation is a whitebox; the port is a redesign

**2026-08-20 · director · ACCEPTED**

The Godot port *is* a visual redesign, but beta 0.1 ships whatever minimal
representation legibly covers the alpha's elements, refined from there.
Director: *"minimal for initial testing is the gameplan"*, and *"if there are
new godot primitives or whitebox tools that work better then use those,
economize development resources"*.

**Finding that narrowed the question:** the alpha has **no art assets at all** —
not one image, font, or sprite. Every Packet is a colour fill, a 1px darker
border, and a white shape glyph drawn as a canvas vector path. So "reuse the
alpha graphics" was never really available; there is only geometry. Its palette
and paths become cheap defaults rather than a reproduction target.

**Consequence:** no custom theme, no imported fonts, no authored widgets in
0.1. Godot's default theme throughout.

---

## D-014 — Presentation registry as the alpha→final translation matrix

**2026-08-20 · director (requirement) + agent (architecture) · ACCEPTED**

Director: the shape graphics are expected to be replaced eventually, and *"we
will need a translation matrix from alpha to whatever the end result is"*.

Answered architecturally rather than as a note, because it is free now and
expensive to retrofit.

**Frozen — gameplay identity:** `Color` and `Shape` are enums `0..5`, six of
each. **Enum ordering is load-bearing**: weak sets derive as the enum-order
complement of authored strong sets, so reordering silently rewrites every
System's and Hacker's weaknesses. CSV tokens (`RED`, `GRE`, `TRI`, `STR`, …)
are content identity and frozen with the datasets.

**Swappable — presentation:** exactly one file, `scenes/battle/packet_style.gd`,
maps enum index to appearance. Nothing outside it may hard-code a hex value or
a shape path; a test enforces six entries per array and bans hex literals
elsewhere under `scenes/`.

**Consequence:** that file *is* the translation matrix. When the art pass lands,
replacing shape 3's drawn diamond with a sprite is a one-line change, and the
mapping from "what the alpha called a Diamond" to whatever replaces it is
readable in one place, in order.

---

## D-015 — Device work is batched into announced windows

**2026-08-21 · director · ACCEPTED**

The test phone cannot stay plugged in all day. It is the director's daily
phone, not a dedicated test rig.

**Protocol:** finish all headless work first (tests, differential traces,
export), batch every check that genuinely needs hardware, announce *"plug the
phone in now"* with the list of what will run, and announce *"the phone can come
off now"* the moment the last device step finishes. Never leave the window
open-ended. Run `adb devices` before assuming a connection, and if the device is
absent, continue with headless work rather than stalling.

**Consequence:** handoff §23 is restructured as a single announced window rather
than checks interleaved through a build. Screenshots are gathered during the
window, since `adb screencap` is self-serve and there is no reason to need the
device again just to look at something.

**Open alternative:** wireless ADB would remove most of this friction — the
phone could sit on a charger across the room — at the cost of re-pairing after
reboots. USB was chosen during setup (D-006) before this constraint was known.
Worth revisiting if tethering proves annoying.

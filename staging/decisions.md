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

**Largely resolved by D-016**, which adds a dedicated always-connected device.

---

## D-016 — Two-device strategy: tablet as primary, phone as target

**2026-08-21 · director · ACCEPTED**

The director had a spare Galaxy Tab A 10.1 (`SM-T580`, 2016) available as a
dedicated test device.

**Verified specs:** Android 8.1 / API 27, Exynos 7870, Mali-T830, OpenGL ES 3.2,
**armeabi-v7a only**, 1200×1920 @ 240 dpi, 1.9 GB RAM. Cold start 2.4 s versus
238 ms on the S25.

**Roles:**

| | |
| --- | --- |
| **Tablet — primary** | Permanently connected. Every routine device check. |
| **S25 Ultra — target** | Connected on request, at Phase E milestones, under the D-015 window protocol. |

**Why the old tablet is an asset rather than a compromise:** a Mali-T830 with
1.9 GB of RAM surfaces performance problems an Adreno 830 hides entirely. A
match-3 with cascades and tween-heavy playback that feels good on 2016 hardware
feels good everywhere. Finding those problems during Phase E is cheap; finding
them after launch is not.

**What the tablet cannot settle:** touch feel, thumb-reach layout, and portrait
composition. A 10-inch 16:10 tablet held in two hands is a genuinely different
input regime from a phone. Those stay S25 questions and must not be signed off
on the tablet.

**Bonus:** testing both proves the stretch/aspect configuration holds across a
wide range (handoff §18 requires 390×844 through 20:9), which no single device
can demonstrate.

**Corrects an earlier suggestion:** dropping the `armeabi-v7a` slice to halve
APK size was floated when the S25 (arm64-only) was the sole device. That is now
**wrong** — the tablet is `armeabi-v7a` **only**, because Samsung shipped the
64-bit-capable Exynos 7870 with a 32-bit userland. Neither device can run the
other's slice, so both are required. Do not re-propose dropping either.

**Setup note:** API 27 clears Godot 4.7's minSdk 24 floor, but not by much. A
2016-or-earlier Android device below API 24 cannot run Godot 4 builds at all,
and no export setting changes that — the floor is the engine's native-library
requirement.

---

## D-017 — The auto-play driver is a frozen, fidelity-critical artifact

**2026-08-21 · director · ACCEPTED**

**Problem found during authorization review:** the differential gate needs
something to play the Hacker across 5,250 unattended battles. That driver lives
in `scripts/bot.ts` and `scripts/batch.ts`, which the handoff module map filed
under "tests and tools". It is not a tool — its tie-breaks (highest-charge
enemy slot resolved by lowest index; fullest row resolved topmost; leftmost
occupied cell; ascending Program order; a 2000-iteration cap) determine every
event in every trace.

**Decision:** freeze and port literally, with the same fidelity requirement as
the RNG (D-009). Full tie-break table in the authorization addendum §A1.

**Why:** a correct rules port paired with a driver that iterates rows
bottom-up diverges on essentially every battle, and presents as a rules bug.
The alternative — writing a fresh, simpler shared policy — was rejected because
it would break comparability with the alpha's existing balance harness.

**Consequence:** the driver is verified independently against a committed
decision fixture *before* the matrix runs, and a divergence traced to it is
reported as a driver defect, never a rules defect.

---

## D-018 — The driver fires the Deck Function

**2026-08-21 · director · ACCEPTED**

**Problem found:** `botFireAbilities` iterates `state.units.player`, which holds
Programs only. The Deck Function has its own separate charge pool and is
deliberately not in `state.units`, so `batch.ts` never fires it. As specified,
all 5,250 battles would have left `FNC_010` and the whole Deck charge-pool path
with zero differential coverage — inside a gate described as exhaustive parity.

**Decision:** extend the driver to fire it.

**Consequence:** `botFireAbilities` stays frozen per D-017; Deck firing is a
separate sibling function called between it and the move, using the same
targeting policy. A deliberate, documented divergence from `batch.ts`, so
balance figures from `npm run batch` and from the trace driver are not directly
comparable and neither is presented as the other.

---

## D-019 — Hash-first differential comparison

**2026-08-21 · director · ACCEPTED**

**Problem found:** the literal reading of authorization §6 produces an estimated
0.5–2 GB of trace JSONL per engine per matrix run. Runtime was never the
constraint; storage and diff cost are.

**Decision:** each engine emits one hash line per battle; the comparator diffs
those; on mismatch it re-runs that single battle in both engines with full
traces and reports the first differing record.

**Why:** satisfies §6.2's reproduction requirement exactly, reduces storage to
megabytes, and removes any incentive to shrink the matrix for performance
reasons — which §6.1 explicitly forbids.

---

## D-020 — Device gate split: tablet routine, phone signs off

**2026-08-21 · director · ACCEPTED**

**Problem found:** authorization §1 says "physical Android phone", §13 says "the
configured physical Android test device", and D-016 made the tablet primary.

**Decision:** all development and repeated checks on the tablet; the §13
completion checklist runs once on the S25 in a single announced window (D-015)
before the build is called complete.

**Consequence:** touch feel, thumb-reach layout, and portrait composition are
phone judgements and must not be signed off on the tablet. The final report
states which checks ran on which device.

---

## D-021 — Fingerprint parity forbids Godot's JSON serializer

**2026-08-21 · agent · ACCEPTED (technical)**

Authorization §15.3 requires the Godot fingerprint to match the alpha's. The
alpha canonicalizes with JavaScript's `JSON.stringify` and hashes with djb2, so
matching byte-for-byte means reproducing JS serialization exactly — key order,
string escaping, number formatting.

**Consequence:** Godot's `JSON.stringify()` cannot be used for the fingerprint;
a hand-written JS-compatible serializer is required. Phase B's first task is to
determine whether any fingerprinted value is non-integer — if all are integers,
the float-formatting hazard disappears.

**Requirement retained rather than relaxed:** an exact match is a cheap
end-to-end proof that the whole parse, normalize, and resolve path ported
faithfully.

---

## D-022 — Save serializer moves into Phase 4

**2026-08-21 · agent · ACCEPTED**

Authorization §14 sequences save at Phase 6, but §15.8 requires save/resume to
preserve deterministic continuation — a differential property only the harness
can prove.

**Decision:** the logic-layer serializer and restorer land in Phase 4 with the
harness, and a resume-determinism test joins the differential gate: run to turn
K, serialize, restore, continue, and require the trace to equal the
uninterrupted run byte-for-byte. Save/quit UI stays in Phases 5–6.

**Why:** an incompletely captured RNG state, a dropped countdown overlay, or a
lost stamped area pattern all pass a round-trip equality test and fail a
continuation test.

---

## D-023 — Two-tier parity verification; the full matrix is codenamed DEEPSCAN

**2026-08-22 · director · ACCEPTED**

Measured: Godot runs roughly **1 second per battle**, so the full §6.1 matrix —
5,250 battles per engine — takes about **90 minutes** on the Godot side. Fine as
a release gate, far too slow for an iterate-and-check loop.

**Decision: two tiers, and the matrix is NOT shrunk.**

| Tier | Scope | Time | Use |
| --- | --- | --- | --- |
| **fast** | 3 Systems × 5 HOSTs × seeds 0–9, default settings — 150 battles | ~2.6 min | every change during the build |
| **DEEPSCAN** | the complete §6.1 matrix, 5,250 battles | ~90 min | the release gate, run unattended |

Both run through `node tools/gen/parity.mjs`; DEEPSCAN adds `--deepscan`.

**Why not simply reduce coverage:** the authorization explicitly forbids
shrinking the matrix because a naive implementation is slow. If DEEPSCAN
becomes painful the answer is to batch more work per Godot process, not to
test fewer battles.

**DEEPSCAN is banked as a memory** so the director can hand it to a future
agent — "run DEEPSCAN" — and do something else for the hour and a half. The
memory carries the full matrix definition, the commands, the pass criterion,
and the UTF-16 capture hazard.

## D-024 — The visual pass targets the alpha's composition, not its pixels

**2026-08-23.** The director asked for the alpha's title, build, battle, pause,
and conclusion screens captured and replicated with the systems beta 0.1 has.
Captured into `staging/design-reference/`, with a README recording every value
read out of the alpha's own `style.css` and `view.ts` rather than eyeballed.

What was replicated, and why each earns its cost:

- **Packets are coloured glyphs on dark cells**, not white glyphs on coloured
  squares. This is the alpha's own MK4.4 decision — the source says the coloured
  field was removed and white fill "lost its purpose". It also frees the glyph
  centre for the ownership badge, which is why the badge moved from a corner to
  the middle. Neutrals became static rather than a grey tile: an unmatchable
  Packet and an empty cell must not look alike.
- **Both sides' Programs are on screen at once**, in two columns. The System's
  charge state is what a player schedules around; the previous single-column
  layout made every enemy activation a surprise. This is the largest single
  legibility gain in the pass.
- **Select-then-confirm** on the chooser screens. Commit-on-tap makes a mis-tap
  on a scrolling phone list unrecoverable.
- **One `Theme`** built in `ui_theme.gd` and set on the root, so a control's
  appearance is decided in one place. Colours still come from `PacketStyle`,
  which now carries a UI palette alongside the board palette; `test_presentation`
  already banned hex literals under `scenes/` and still passes.
- **Modal panels with a scrim**, so pause reads as suspending the battle.

What was NOT replicated, deliberately:

- The alpha's post-defeat force-win prompt. The debug bar's `win`/`lose` buttons
  already end a battle through the real damage path; the director confirmed the
  alpha prompt went unused.
- Bold and letter-spaced type. Godot's fallback font has no bold face, and
  importing one is an art-pass decision, not a beta-0.1 one.
- Full colour and shape words on the chooser cards. The authored CSV tokens
  (RED, TRI) are shown instead, so display cannot drift from content.
- The result screen's metrics report. Metrics are the last logic module and are
  not built yet; the result screen is laid out with the exits ABOVE a divider so
  the report drops in below without moving them.

Verified end-to-end on the tablet: all six screens, 942 tests, parity 150/150.

## D-025 — Metrics and logging attach to the event funnel, and to nothing else

**2026-08-23.** Phase 6's last logic module. Both are collectors over the SAME
event stream the resolver already emits, attached at `Game._collect` — the one
funnel every returned batch passes through. There is no second pipeline and no
path by which logging can observe something metrics did not.

That placement is what makes them cheap to trust. The differential gate proves
the beta's event stream matches the alpha's byte for byte, so a collector
consuming only events inherits that proof: the numbers are right because the
stream is right.

Consequences of the design, each deliberate:

- **They live on `GameState`, not on `Game`.** The authorization requires the
  metrics state needed for consistent continuation to be in the save, and a
  `Game` is reconstructed around a restored state rather than restored itself.
  Save schema bumped to 2; a schema-1 save is rejected rather than resumed with
  the counters silently starting from zero.
- **Both are nullable and opt-in.** The parity run plays thousands of battles
  that want neither, and mandatory accounting would show up directly in its wall
  clock. `Session.create_quick_match(..., with_accounting)` defaults to false;
  the game passes true, the harness does not.
- **Damage buckets are floats.** The analytical splits are pre-floor values that
  a Shield rescales proportionally, and they are `null` when they do not apply.
  Truncating each to an int would push the disjointness identity off by a few
  units per battle; `int(null)` is worse still — it raises at runtime and aborts
  the rest of the batch, so every later event goes uncounted and the totals
  under-report silently. `_num()` handles both. Display rounds; the accumulator
  does not.
- **`force_outcome` moved into `Game`.** The debug win/lose buttons reached past
  `Game` into `Resolve`, which meant they bypassed the funnel and produced a
  result screen reporting zero damage for a battle that plainly had some. A
  diagnostic outside the funnel eventually produces a bug report about the
  metrics rather than about the diagnostic.

The load-bearing test is the bucket identity — `match + attacker + bomb +
lineslice + transform + passive + buff == total`, asserted over real battles
rather than against hand-computed numbers, which would only re-derive the
implementation. `cascade` is excluded because it is cross-cutting. Continuation
is tested the same way `save` is: an interrupted battle must finish with the
same figures as an uninterrupted one.

Logging keeps the alpha's three levels with VERBOSE in debug builds and BASIC in
release; COMPLETE is never reached by defaulting. `LogStore` writes three JSONL
streams under `user://logs` with per-stream byte caps and oldest-first trimming.
Godot's filesystem removes the alpha's localStorage quota problem but is not
itself a budget — an unbounded log on a phone is a slow disk leak, so the cap
stays and only the mechanism changes.

**Not ported:** the alpha's selection, wizard, and Boss-selection log streams.
Beta 0.1 is Constructed Quick Match only, so no code path can produce them, and
a record type that cannot be written is a schema claim the build cannot back up.
They land with the features in 0.2.

Verified: 1047 tests green, parity 150/150, logs written and read back off the
tablet.

## D-026 — UI sizes are ratios of the design viewport, never raw pixels

**2026-08-23.** Human playtesting returned three issues; all three are recorded
here because each has a general form worth remembering.

**Text was far too small.** The alpha laid out against a 430 px CSS viewport and
this project's base viewport is 1080 px, so every size carried across literally
was ~2.51× too small on device. `UiTheme` now derives `SCALE` from the two
viewport widths and exposes `px(alpha_px)`; named sizes each trace to the alpha
value they came from. `UnitBox` and `AvatarBox` derive their internals from their
own height as proportions, so a box stays correctly composed at any scale.

The director's rule: **as large as possible without overflowing.** The second
half is the one that bites. At readable type a row of six Buttons is wider than
a phone, and an `HBoxContainer` of Buttons pushes the whole panel off-screen
rather than wrapping — the Build screen's inventory did exactly that. Fixed with
`clip_text = true` (so a Button's text cannot set its container's minimum width)
and a `GridContainer` wrapping six controls into two rows of three.

**Board changes were teleports.** `SWAP`, `FALL`, and `SPAWN` all resolved as an
instant `_refresh_board()`. `Datastream` gained `slide`, `fall`, `spawn`, and
`settle`: motion is transient decoration over a model that never moves — cell i
always means cell i — so an interrupted or skipped animation can never leave the
board describing a position the logic layer did not produce. Fall duration
scales with distance, because everything landing simultaneously reads as a
teleport even when it is technically animated. Firing a Program now pulses the
control that fired, since a Function whose Effect touches no Packet (a Drain, a
Buff) previously produced no visible change anywhere at all.

**A targeted Function armed and instantly cancelled.** Android delivers one tap
as BOTH an `InputEventScreenTouch` and an emulated `InputEventMouseButton`, so
`UnitBox` emitted `pressed` twice per tap: the first press armed, the second hit
the tap-again-to-cancel path. Now latched on press and consumed on release, so
whichever event type arrives second is a no-op.

**The general lesson**, recorded in `lessons-learned.md`: 1,047 tests and 150/150
parity had nothing to say about any of these. They are not rules bugs. A human
on the build finds a class of defect no harness reaches, and "it feels wrong" is
a bug report.

## D-027 — Two-finger scroll bypasses the controls underneath it

**2026-08-23.** The Build screen was effectively unscrollable on device. Godot's
touch drag-scroll only works where the gesture reaches the ScrollContainer, and
that screen is wall-to-wall Buttons — a one-finger drag presses controls, so the
only way to scroll was to find a sliver of background. That is a puzzle, not an
interface.

The director offered three options — widen the scrollbar, add a dedicated
handle, or make a two-finger gesture bypass the other elements — and preferred
the third. Both the preferred fix and the fallback are implemented, because they
answer different questions: the gesture is how you scroll, the visible bar is
what tells you the region scrolls at all.

`TouchScroll` overrides `_input`, which runs BEFORE the viewport hands events to
`_gui_input`, so it sees a touch before the Button under it does. Once two
fingers are down inside its rect it marks every subsequent touch event handled
and the controls never see them.

The non-obvious part: the first finger's press has ALREADY reached a Button by
the time the second arrives, so that Button is latched. Since the gesture then
swallows the release, the control would stay drawn as pressed for the whole
scroll and fire on the next real tap. `_release_controls` walks the subtree and
clears it; `UnitBox.release()` exists for the same reason.

Verified with genuine multitouch driven through `sendevent` on the raw input
node, not with `adb shell input` (which cannot produce it): the gesture scrolls
both directions and passes over six Buttons without activating any of them.

Also added: `staging/architect-notes.md`, for design items raised during the port
that must NOT be built as part of it. First entry AN-001 — DISABLER/Drain should
be manually targeted at a System Program rather than auto-targeting the fullest
slot, which silently removes the decision the Function exists to create. Deferred
because changing behaviour mid-port would put the differential gate in the
position of failing for a reason that is correct.

## D-028 — Refill enters as a rigid column, not as independent Packets

**2026-08-23.** Playtesting reported a hitch: after a Sync resolved, the new
Packets filling the gaps stalled for a few frames just before coming to rest.

The cause was arithmetic in `Datastream.spawn` that did not do what its own
comment claimed. The start position was

```
home_of(cell) - Vector2(0, cs * (cell.y + 1))
```

and `home_of(cell).y` is `cell.y * cs + gap/2`, so `cell.y` cancelled out
entirely: **every** spawned Packet started at the same point, one cell above the
board. They then shared a single duration, which meant they covered DIFFERENT
distances in the same time — a Packet bound for row 0 travelled one cell while
one bound for row 3 travelled four. With `EASE_IN`, the short-travel Packets
crawled, and being slowest they were the last to settle. That reads exactly as
the reported stall: the board appears to hang right before it comes to rest.

Refill always fills a column from the top down, so a column taking `k` Packets
is filling rows `0..k-1`. Starting the one bound for the lowest empty row just
above the board and each one above it a further cell up makes **every Packet in
that column travel exactly `k` cells** — so one duration moves them all at a
single speed and the column arrives in formation, like a stack of objects
falling together. Duration now scales with `sqrt(k)`, matching `fall`, so a deep
refill takes longer rather than being rushed to fit a fixed budget.

Verified on device: a mid-refill frame shows the whole column offset by a single
uniform amount, which is what "arrives in formation" looks like.

**The general lesson**, added to `lessons-learned.md`: the comment described the
intended behaviour and the code did something else, and it survived review
because the animation looked plausible. A comment stating intent is not evidence
the code achieves it — and "looks plausible" is a much weaker signal than
"matches a model of what should happen".

---

## D-029 — Beta 0.2 builds a minimal debug Force Win, not the Alpha wizard

**2026-08-24 · director · ACCEPTED**

The Beta 0.2 authorization contains a gap: §23.1's tablet gate says to continue
through Battle 3 "using debug force-win where useful", but §3.1 never lists
wizard actions as in scope, and Beta 0.1 shipped `Types.WizardAction` as an enum
with no implementation anywhere in `scripts/`, `scenes/`, or `tools/`. Taken
literally the gate cannot be run as written, and §27 warns specifically against
building past the authorized scope to close a hole like this.

**Decision:** build a **debug-build-only** control that resolves the current Run
battle as a victory — enough to reach Battle 3 on device and nothing more.

Deliberately NOT built in Beta 0.2:

- `RESTART_LOST_BATTLE` and `RESTART_RUN`;
- the Alpha's step-aware `forceWinAvailable()` availability matrix, which gates
  the control on `step < RUN_LENGTH` and on natural victory vs. defeat;
- the wizard log record (`appendWizardLog` / `WIZARD_*` events);
- any presence in a release build.

**Why minimal rather than either extreme.** Porting the full wizard is a scope
addition to §3.1 for something whose only Beta 0.2 consumer is a device gate;
the Alpha's matrix is meaningfully coupled to the Battle-4 result presentation
(`isRunComplete`), which is 0.3 work. Dropping force-win entirely was the other
option, and was rejected because it makes every tablet iteration pay for two
honest battles before reaching the part being tested — a recurring cost across
the whole build, to save a control that is a few lines behind a debug guard.

**Consequence to watch:** `WizardAction` stays a partially-implemented enum, and
the `FORCE_WIN` path will not emit the Alpha's wizard log record. Anything in
0.3 that reads wizard telemetry must not assume Beta 0.2 produced any. When the
full matrix arrives it supersedes this entry rather than extending it — the
availability rules are the substance, and this decision deliberately has none.

Raised in `1c38r34kr-beta-0.2.0-authorization-review.md` §C2.

---

## D-030 — Saves do not survive a beta version bump, and that needs no defence

**2026-08-24 · director · ACCEPTED**

**Standing policy for the whole pre-release beta line.** Assume any existing save
is incompatible with the next beta version. Reject it and move on. Do not build
migration paths, compatibility shims, or verification that a save survives a
version boundary, unless a specific save has an **articulable purpose** that
justifies the cost.

This supersedes nothing, but it settles a question that was about to be asked
once per schema change. It arrived immediately after the Beta 0.2 authorization
review flagged that the session-envelope restructure (schema 2 → 3) would drop
any in-progress Beta 0.1 save, and treated that as a consequence needing
sign-off. Under this policy it is not a consequence worth reporting — it is the
expected behaviour of a beta.

**Why.** D-022 and the save/load entry in `lessons-learned.md` recorded that
Beta 0.1 over-invested in save proof: a requirement naming a property
("provably deterministic", "never silently repaired") is a multiplier on every
feature it touches, and the value of that multiplier should be measured against
what the feature is worth *in this project*. A beta played by one person, whose
battles resolve in minutes, does not earn cross-version save durability. This
decision converts that retrospective lesson into a forward default, so the
cheap answer is the one that requires no argument.

**What is still required.** Within-version save and resume correctness is
untouched. An interrupted Run must still resume correctly on the *same* build —
that is what `test_save.gd`'s continuation proof exists for, and Beta 0.2's
§16 representative resume checks still apply. The policy governs version
boundaries only, not whether save works.

**How future authorizations should read.** A completion standard should not list
save migration, cross-version compatibility, or "existing saves continue to
load" as an item. If one does, it is a drafting slip rather than a requirement,
and the implementing agent should say so rather than build to it.

**Revisit as release approaches.** This is explicitly a pre-release posture. The
first build that could plausibly reach a player who is not the director is the
point to reopen it.

---

## D-031 — DEEPSCAN was re-run for beta 0.2, despite §21.1 making it optional

**2026-08-24 · agent → director · ACCEPTED**

§21.1 says a fresh 5,250-battle DEEPSCAN is optional rather than mandatory when
a build "changes only Run/session/UI orchestration around an untouched battle
core and fast parity remains green". By the letter of that, beta 0.2 could have
carried beta 0.1's result forward: `resolve.gd`, `game.gd`, `board.gd`,
`match_finder.gd`, `passive.gd`, and `metrics.gd` were never touched.

**It was re-run anyway, because Phase C consolidated Quick Match and Run onto a
single battle constructor.**

Battle *construction* is not the battle core, but it is battle-affecting: it is
where a battle's immutable identity and config are stamped, including the
resolved LINK and ICE and each side's strong sets. §21.1's own list includes
"integration work gives reasonable cause to suspect battle behaviour was
perturbed", and refactoring the one place every battle is built qualifies.

The deciding argument was not the refactor itself but what was built on top of
it: four further phases, a device gate, and a release. Fast parity is 150
battles against DEEPSCAN's 5,250, and the cost of discovering a construction
defect after closeout is a retracted build rather than ninety minutes.

**The general rule this sets:** reuse prior proof for subsystems that were not
edited, and re-earn it for a subsystem that was, even when the edit is
structural rather than behavioural and even when a cheaper gate is green. "Fast
parity passed" is evidence about 150 battles, not a licence to skip the matrix
after touching the code every battle goes through.

Fast parity was green at every phase boundary throughout, and DEEPSCAN agreed
with it. That is the outcome to expect; it is not the reason to skip the check.

---

## D-032 — REBOOT prevents matches; it does not decline to resolve them

**2026-08-25 · agent → director · ACCEPTED**

The Beta 0.3 authorization's §14 described REBOOT as regenerating the board and
then not resolving the Syncs the rearrangement created. The shipped alpha does
something different, and the difference is visible in play.

REBOOT's authored tuple is `1:1:0:0`. The third element is
`SHAKE_PREVENT_MATCHES`, and `board.ts` generates an arrangement **containing no
match at all** — "the completed arrangement already satisfies the legal/stable
post-generation invariants, so no Sync wave begins".

**Why it matters:** under the original wording a port could generate freely,
skip resolution, and leave one or more pre-made Syncs sitting inert on the
board. The **Hacker** takes those next turn as free damage the alpha never
grants. REBOOT is meant to be a reset, not a gift.

**Why no test would have caught it:** §14's postcondition was "no post-REBOOT
Sync/cascade resolves from the rearranged board". Both implementations satisfy
that, because neither resolves anything *during* REBOOT. This is the P-036 shape
again — a correctly stated prohibition whose positive half is unstated — and it
appeared one section after the same document had systematically added positive
postconditions everywhere else.

**Decision:** §14 now states the prevent-matches invariant, and its postcondition
asserts **the board contains zero matches immediately after REBOOT** — a
property of the board rather than of what was skipped. Coverage item §21.43 was
restated to match.

Two adjacent confirmations were folded in at the same time, neither a change of
intent: §10.1 now records the DATABEND loop as **5 activations across 6 capacity
checks** (a `for i in 5` port gets both numbers wrong), and §11 now says DATABEND
regenerates by **retention** rather than by special-ness, so a Packet carrying a
Hacker overlay is itself regenerated.

**The generalizable half**, for the AAR: when a rule says "X does not happen",
ask whether X is *prevented* or merely *unobserved*. Those are different
mechanisms behind the same prohibition, and only an assertion about resulting
state tells them apart.

---

## D-037 — The overlay type ring is suspended, restoring alpha parity

**Beta 0.3.1, director call, 2026-08-26.**

The beta drew a coloured ring outside the ownership badge to carry an overlay's
TYPE. **The alpha has no such ring.** `src/render/view.ts` draws exactly two
things for an overlay — a filled circle at `c * 0.22`, and a character in its
centre — and type is carried by that character alone.

The ring was a beta-era addition. It was never recorded as a decision, and the
differential could not have caught it: the scene layer has no automated
coverage, which is the same blind spot that produced P-042 and AN-006.

**It cost more than it appeared to.** The ring pushed the overlay's footprint
from the alpha's 0.45 × cell to 0.61 — about 35% wider — which is most of the
reason a compact glyph (a diamond, a circle) all but vanishes under an overlay.
The Gate-B sheet showed a cyan diamond reduced to four points poking out from
behind a badge.

So removing it does two things at once: it restores parity with the alpha, and
it gives the Packet's shape back to the player who still has to match it.

**Suspended, not deleted.** The director is taking the question of how to
distinguish overlays to the designer, so this may return in some form.
`PacketStyle.OVERLAY_TINT`, the four `ring_*` PNGs, and the commented-out
`draw_arc` in `packet.gd` are all retained deliberately. Restoring it is
uncommenting three lines.

**Correcting the record:** the Gate-B notes originally described the badge's
coverage of the glyph as "faithful, not a defect I introduced". That was true of
the beta renderer but implied the alpha, and it does not trace there. The
occlusion was substantially caused by the ring itself.

---

## D-038 — The four overlay marks become art, not font characters

**Beta 0.3.1, director call, 2026-08-26.** Amends **D-035**, which scoped text
rendering out of this pass entirely.

The badge's centre mark was `draw_string` against `ThemeDB.fallback_font`: `S`
for a shield, `Ø` for an Override, `+` for a live Buff, `?` for a bomb with no
countdown. These become PNGs in the pack, authored white with alpha and tinted
at runtime with the badge's opposite colour, so ownership keeps working exactly
as it does now.

Two reasons, and the first is a real robustness problem rather than an
aesthetic one:

- **A font is a dependency nobody chose.** `Ø` is not guaranteed to exist in
  whatever face a device falls back to, and a missing glyph renders as a box —
  on the Boss mechanic's only board-level signal. Nothing in the project pins a
  font; `UiTheme` sets sizes and never a family.
- **A letterform cannot be art-directed.** Every other mark on the board would
  become replaceable while the four carrying the most specific information
  stayed hostage to a system font.

The suspension of the type ring (D-037) sharpens this: the mark is now the
**sole** type signal, as it is in the alpha. So each is authored as a silhouette
rather than a letter — a shield shape instead of `S`, a slashed ring instead of
`Ø`.

**One mark's meaning changed, and it is flagged rather than buried.** The bomb's
`?` was a fallback for "armed bomb with no countdown to show", saying *unknown*
where the type is actually known. It is now a charge with a fuse. That is a
design change, not a rendering change, and the designer should confirm it.

**Explicitly deferred to the text pass:** the countdown DIGIT stays a font
glyph. Whether it becomes 0–9 sprites, stays text, or is replaced by something
more iconic is a decision for that pass, not this one.

---

## D-039 — The registry's chrome colours become pack SOURCE, not runtime values

**Beta 0.3.1 Phase E, 2026-08-27.**

After the conversion, `PacketStyle`'s role split in two, and the split is worth
naming because the file now looks like it does more than it does.

**Still read at runtime:** the Packet palette (as the fallback when the palette
SVG cannot be parsed), text colours, playback tints, the pause scrim, the
neutral static, badge polarity, and the MISSING checker.

**Read only by `tools/gen_assets.gd`:** every chrome colour — panel, box,
control, bars, edges. The game no longer touches them. The PNGs carry those
values now.

**They stay in the registry rather than moving into the tool.** Generating the
pack from the same constants the renderer used is exactly what makes v0
*provably* reproduce the whitebox rather than approximating it by eye — and the
proof is mechanical: after this pruning the pack regenerated **byte-identical**,
with only the manifest's version string changing.

The alternative — moving the colours into the generator — would have made the
registry smaller and the guarantee weaker. When the art pass replaces these
PNGs, the constants become vestigial and can go with them; until then they are
the record of what the whitebox looked like.

**Deleted here as genuinely dead** (§1.5, §9.4): `SYSTEM_TURN_FRAME`,
`NEUTRAL_FILL`, `NEUTRAL_BORDER`, `GLYPH`, `fill_for()`, `border_for()`, and
`draw_shape()`. The first six were beta 0.1 fossils that nothing had rendered
for two builds; `draw_shape` went when the renderer started drawing textures.
`shape_points()` stays — the generator rasterises the glyphs from it, so it
remains the authoritative silhouette and a regenerated pack cannot drift.

`COLOR_BORDER` went too, under D-036: the outline is now a second tone inside
the glyph texture, produced by the same modulate that produces the fill.

---

## D-040 — Authored width replaces computed width, and that is a real hazard

**Beta 0.3.1 Phase D/E, 2026-08-27.**

Twice during the conversion a measurement that had been CODE became a property
of an image, and both times the first attempt shipped the wrong number.

- The Build slot's accent bar was `border_width_left = maxi(2, px(4))` ≈ 10 px.
  Authored into the texture as 4 px it rendered 4 px, because a 9-slice
  preserves the corner region 1:1. Two and a half times too thin.
- The reorder arrows were text, and a Label happily overflows its container's
  content margins. A texture does not: `expand_icon` shrank the mark to the
  ~15 px the button's padding left it.

**The general shape:** `px()` scaling, content margins, and text overflow are
all things the whitebox got for free from the layout engine. An image gets none
of them — its dimensions are just its dimensions. So every measurement crossing
from code into art has to be *converted*, and the conversion is easy to skip
because the code still compiles and the screen still looks broadly right.

Both were caught by comparing against the pre-conversion captures rather than by
looking at the new screen and asking whether it seemed fine. That is the
argument for taking a before set at all.

---

## D-045 — Alpha CSV fidelity narrows to shared columns, by design

**Beta 0.3.2, 2026-08-28.**

`test_csv.gd` compared `data/*.csv` field-by-field against fixtures generated
from the alpha's sheets. Seven of ten sheets now fail that comparison, because
the beta's content no longer carries the alpha's presentation columns: `BIO`,
`GRAPHICS`, `graphics_ref`, `display_text`, `DESCRIPT`,
`BOSS_PASSIVE_DESCRIPTION`, and the PASSIVE `display` template have moved into
the text framework or been deleted as POC stubs.

**The comparison is now column-wise by header name across the shared columns.**
Every column both builds still have is proven byte-identical; the removed ones
are simply not asserted.

**This is the plan working, not a loss of coverage.** The 0.3.0 handback said
the oracle stops being able to adjudicate the moment content moves. Content has
now moved, deliberately, with the director's sign-off — and alpha fidelity
becomes progressively less relevant the further the beta goes. Holding the old
comparison would have meant holding the beta to a shape it has outgrown.

What the alpha still adjudicates is unchanged and is the part that matters: the
rules engine, through the battle, Boss and Run differentials. Those compare
BEHAVIOUR, and behaviour has not moved.

---

## D-046 — Battle-log indentation moves from content into code

**Beta 0.3.2, 2026-08-28.**

Four battle messages encoded their hierarchy as two leading spaces —
`"  {amount} damage to {target}"` reads as a sub-line under the action that
caused it.

**Excel discards leading whitespace on CSV import**, so the indentation was
gone from the workbook before anyone looked, and is unrecoverable from it.

Rather than re-encode it and lose it again on the next round trip, the indent
moves to the three call sites that emit sub-messages. That is where it belonged:
the indent is not part of *what the game says*, it is how a line is presented
relative to its parent. A string whose meaning depends on leading whitespace is
unsafe in any pipeline that passes through a spreadsheet.

The exporter now preserves whitespace exactly rather than stripping it, so it
cannot compound the problem — but it cannot undo the import either. See AN-011.

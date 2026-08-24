# Lessons learned — 1C38R34KR beta port

Written during the port, for the post-project AAR. Kept in the repo rather than
in agent memory so it survives whoever is driving.

The organising question: **what would I tell someone starting this port over?**
Not a changelog — `decisions.md` is the changelog. These are the things that
were not obvious in advance and cost real time.

---

## 0. Start this file on day one, not halfway through

The first lesson, and the one that makes every other entry here worse than it
should be: **this log was started at roughly the midpoint of the port.**

Everything below the midpoint was written from memory and from re-reading
`decisions.md` and the commit history. That means it is biased toward what was
recent, what was painful enough to remember, and what happened to leave a
written trace. The early phases — toolchain setup, the RNG port, content
loading and fingerprinting — are certainly underrepresented here, not because
they were smooth, but because their friction has already been forgotten.

`decisions.md` captured *what was decided and why* from the first commit, and
that discipline paid off completely. The gap was a parallel log for *what was
learned the hard way* — the dead ends, the wrong assumptions, the twenty minutes
lost to a toolchain quirk. Those do not belong in a decision log, so they went
unrecorded.

**Create `lessons-learned.md` alongside `decisions.md` at project start.** Append
to it the moment something costs unexpected time, while the detail is still
cheap to write down. The cost of an entry that turns out not to matter is one
line; the cost of a missing entry is paying for the same discovery twice.

---

## 1. The differential harness earned its cost several times over

The build authorization insisted the harness come BEFORE presentation rather
than after, and it was right for a reason I did not anticipate. The harness was
sold as a final gate. What it actually was is a **debugger**.

Two genuine port bugs surfaced through it that no unit test would have caught,
because both produced perfectly plausible battles that simply were not the
alpha's:

- `_cast_shake` discarded the board. `BoardOps.shake` REPLACES the board and the
  carrier was never written back. Everything still ran.
- A PASSIVE carrier used `inst.source_id` (the HOST) where the alpha used
  `inst.passive["id"]` (the PASSIVE). Metrics attributed to the wrong actor.

Both were found as a byte-level divergence in an event stream, with a seed that
reproduced them headlessly in seconds. Without that, they would have surfaced
months later as "the numbers look a bit off".

**The corollary:** the harness only works if the RNG is ported EXACTLY. Porting
mulberry32 by hand rather than reaching for Godot's PCG32 felt like pedantry at
the time and is the foundation the entire gate rests on. Everything downstream —
board generation, refill, Shake, Boss placement — is only comparable because the
draw sequence is identical.

## 2. More harness bugs than port bugs

Worth saying plainly because it is demoralising in the moment and useful to
expect: **most early divergences were bugs in my test fixtures, not in the
port.** A JS object literal in a fixture generator evaluated at `return` time,
after `reshuffleBoard` had already consumed draws. A stacking test whose premise
was wrong because the PASSIVE was ENEMY-scoped. A charge-routing overflow test
that could never fire because no two Programs in the fixture shared a colour —
it would have passed vacuously forever.

That last one is the dangerous class. **A test that cannot fail is worse than no
test**, because it is counted as coverage. When writing a test for an edge case,
first make the fixture actually reach the edge, and prove it does.

## 3. Trust the reference implementation over your own reasoning

Several times I concluded the alpha was wrong and was myself wrong. The alpha
had ~15.6k lines and a long tail of deliberate decisions encoded as apparently
arbitrary details. When the port disagreed with the alpha, the alpha was right
substantially more often than not.

The productive posture: **assume the reference is right, and find out why.**
`port-notes.md` (P-001..P-014) exists to record every place the translation is
non-literal, so a future reader can tell "deliberate" from "drifted".

## 4. Layer purity has to be enforced, not documented

`scripts/logic/` may not touch `Node`, `SceneTree`, `Tween`, `Input`,
`DisplayServer`, or `await`. That rule is what makes the game headlessly
testable and therefore what makes the gate possible at all — but it erodes one
convenient `get_tree()` at a time.

`test_layer_purity.gd` greps for the forbidden constructs. It has caught drift.
The same pattern applied to the presentation registry (`test_presentation.gd`
bans hex literals under `scenes/`) and both are worth the twenty lines.

**Corollary discovered late:** a diagnostic that reaches past the abstraction is
the same drift wearing a lab coat. The debug win/lose buttons called
`Resolve.deal_damage` directly, bypassing `Game._collect`, and so bypassed
metrics — producing a result screen that reported zero damage for a battle that
plainly had some. If there is ONE funnel, everything goes through it, including
the shortcuts.

## 5. Godot/GDScript specifics that cost time

- **`Color` is a builtin.** The gameplay enum had to become `PacketColor`. Check
  for name collisions with engine types before designing the type vocabulary.
- **Enum type annotations must be qualified** (`Types.Side`, not `Side`) even
  where the unqualified name resolves elsewhere. This recurred several times.
- **`Constants.get()` is a parse error** — `get` is `Object.get`. Load the script
  into a `Script`-typed var at runtime instead.
- **GDScript has no `%g`**, and an unsupported format character raises at
  RUNTIME, not compile time. The playback-speed button silently had no label for
  a while.
- **A parse error hangs a headless test runner.** `_initialize()` aborts, so
  `quit()` is never reached and the main loop spins forever — 200 CPU-seconds
  before I noticed. Guard with `can_instantiate()` and add a `_process` fallback
  that aborts on the first idle frame.
- **`int(null)` raises and aborts the enclosing loop.** In a metrics collector
  that meant every event after the first null field went uncounted, and the
  totals under-reported silently. Null-guard every optional numeric field.
- **New `class_name` types are invisible until the class cache refreshes.**
  `godot --headless --import` after adding one, or `--check-only` reports
  "Could not find type" for a file that is perfectly fine.
- **CSV files are claimed by the csv_translation importer** and will not ship in
  an export. `importer="keep"` plus a `*.csv` export filter.
- **Godot imports images in any directory it can see.** A `.gdignore` in the
  staging/docs directory stops reference screenshots becoming imported textures
  bloating the APK.

## 6. Windows/toolchain specifics

- `cmdline-tools` 23 replaced `sdkmanager` with a new `android` CLI.
- MAX_PATH bit during extraction; a short staging path under the user profile
  fixed it.
- Node's `spawnSync` fails `EINVAL` on `.cmd` shims without `shell: true`.
- PowerShell captures UTF-16 by default; a JSONL trace captured through a
  redirect was unparseable until forced to UTF-8.
- **Always `git -C <path>`.** The Bash tool's cwd reverted between calls and I
  committed to the wrong repo once.

## 7. Devices

- A black screen on Android is not necessarily a rendering bug. With the screen
  asleep or locked, the activity goes `OnResume`→`OnPause`→`OnStop` immediately,
  `adb screencap` returns a pure black PNG, and the Godot log is empty — which
  looks exactly like a renderer failure. Check `dumpsys window` and
  `dumpsys power` FIRST. Disabling the lock screen and setting
  `stay_on_while_plugged_in` on a dedicated test device removes the whole class.
- A flaky USB port is not worth fighting; `adb tcpip 5555` once and work
  wirelessly.
- **The desktop build is the right iteration target, not the device.** The
  device loop is ~90 s dominated by the APK export. The desktop window is ~2 s.
  I spent a lot of the visual pass on the slow loop out of reflex, because the
  device is the GATE. The gate and the iteration target are different things.

## 8. Presentation: what I got wrong

Covered in depth in `design-reference/README.md` and D-024, but the two things
worth restating:

- **Sizes must be ratios of the design viewport, never raw pixels.** The alpha
  laid out against a 430 px CSS viewport; this project's base viewport is
  1080 px. Carrying its numbers across literally made every label ~2.5× too
  small on device — unreadable at arm's length, which is fatal for a build whose
  entire purpose is human playtesting. `UiTheme.px()` now derives the multiplier
  from the two viewport widths so the relationship stays visible.
- **"As large as possible" is only half a rule.** The other half is "without
  overflowing", and that is the half that bites. At readable type a row of six
  Buttons is wider than a phone, and an `HBoxContainer` of Buttons pushes the
  whole panel off-screen rather than wrapping. `clip_text = true` stops a
  Button's text setting its container's minimum width; `GridContainer` wraps a
  row that will not fit.

## 9. The POC's whitebox was worth more than anyone expected

The director's initial position was that the look would be completely
overhauled, so alpha fidelity did not matter. That understated what the alpha's
whitebox was. It encoded real UX findings accumulated over the whole POC:

- both sides' Programs visible at all times, because the opponent's charge state
  is what a player schedules around;
- Packets as coloured glyphs on dark cells, not white glyphs on coloured fields
  (the alpha's own superseding decision, and it frees the glyph centre for the
  ownership badge);
- neutrals as static rather than absence — an unmatchable Packet and an empty
  cell must not look alike;
- select-then-confirm on phone lists, because a mis-tap on a scrolling list is
  otherwise unrecoverable;
- dim every illegal region during targeting, which answers "what can I tap right
  now?" with no text at all.

None of that is art. All of it survives an art pass. **Extract a POC's styling
as display-independent RULES before porting**, or the same discovery gets paid
for twice.

## 10. Process

- **Announce device windows.** "Plug the phone in now, here is everything that
  will run" and "the phone can come off now" — tethering a daily-driver phone is
  a real cost to the person holding it.
- **Bank long-running verification behind a name.** The full 5,250-battle matrix
  takes ~90 minutes. Codenaming it DEEPSCAN meant it could be handed to a future
  session rather than blocking the current one.
- **Two-tier verification.** A ~2-minute stripped parity run on every change, the
  full matrix on demand. A gate nobody runs because it is slow is not a gate.
- **Human playtesting finds a different class of bug than any harness.** The
  double-fire on `UnitBox` (Android delivers a tap as BOTH an
  `InputEventScreenTouch` and an emulated `InputEventMouseButton`, so a targeted
  Function armed and instantly cancelled) was invisible to 1,047 tests and
  150/150 parity, because it is not a rules bug. Get a human on the build early,
  and take "it feels wrong" as a bug report.

## 11. Verify with real device events, not with reasoning

The two-finger scroll gesture was the kind of change it is tempting to ship on
inspection: the code is short, the mechanism is understood, and `adb shell
input` cannot produce multitouch. The honest options were "hand it back
unverified" or "drive the touchscreen directly".

`adb shell sendevent` on the raw `/dev/input/eventN` node does produce genuine
multitouch — protocol B, `ABS_MT_SLOT` / `ABS_MT_TRACKING_ID` / `ABS_MT_POSITION_*`
with a `SYN_REPORT` per frame. Setting it up cost about ten minutes and turned
"this should work" into "this scrolls both directions and passes over six
Buttons without activating any of them".

Two of the three playtest bugs in this session were input-layer behaviour that no
amount of reading the code would have surfaced, and the fix for one of them
(swallowing the release during a gesture) had a non-obvious failure mode: the
Button underneath stays latched and fires later. **Where a fix is about what the
hardware does, test with what the hardware sends.**

## 12. A comment describing intent is not evidence the code achieves it

`Datastream.spawn` carried a comment saying new Packets start "one row above the
top edge for the topmost cell, further up for each row below it, so they queue
rather than overlap". The arithmetic beneath it cancelled `cell.y` out and
started every Packet at the same point.

It survived because the result *looked plausible* — Packets did drop in from
above and did land in the right places. What it actually produced was Packets
covering different distances in the same time, which the director noticed on a
real device as a stall right before the board settled.

Two things worth carrying forward:

- **Check load-bearing arithmetic against a model, not against whether the
  output looks reasonable.** "Every Packet in this column travels the same
  distance" is a claim that can be verified by substitution in ten seconds. "The
  animation looks fine" cannot.
- **When a comment and its code disagree, the comment is the more dangerous
  half**, because it stops the next reader from checking. This one described
  behaviour convincingly enough that I did not re-derive it when writing the
  duration logic on top.

## 13. Save/load was over-invested for what this project needed

**The director's assessment, recorded in their terms:** for a game of this kind,
save and load matter far less than they would for something more persistent.
Too much time went into scoping, building, and testing the feature, too early,
at the expense of finishing gameplay concepts.

**The abstract takeaway, in the director's words:** *be judicious with any
feature request — ideas are free, implementation costs time and tokens.*

### What it actually cost

Worth recording concretely rather than as a feeling, so the next estimate has
something to calibrate against:

| | |
| --- | --- |
| `scripts/logic/save.gd` | 267 lines |
| `tests/test_save.gd` | 253 lines, 19 assertions |
| Decision-log entries | D-022 (moved the serializer a whole phase earlier), plus save clauses in D-025 |
| Schema revisions | 1 → 2, when metrics joined the envelope |

Roughly 520 lines, one phase reordering, and a place in the differential gate —
for a feature whose player-visible surface is two buttons.

### Where the pressure came from, and what that suggests

The scale was not arbitrary. The build authorization made save/resume a
completion-standard item (§15.8) and required it to "preserve deterministic
continuation", which is a differential property — so D-022 pulled the serializer
forward into Phase 4 to sit with the harness, because a round-trip equality test
passes with an incompletely captured RNG state, a dropped countdown overlay, or
a lost stamped area pattern, and only a CONTINUATION test catches those.

That reasoning was sound given the requirement. **The requirement is the thing
that deserved the scrutiny.** Once "save must be provably deterministic" was
written into the completion standard, everything downstream — the phase move,
the continuation harness, the schema discipline — followed necessarily. The
expensive decision was made in the specification, not in the implementation.

So the practical form of the lesson is narrower and more actionable than "be
careful what you ask for":

- **A requirement that names a PROPERTY ("provably deterministic", "byte-
  identical", "never silently repaired") is a multiplier, not a line item.** It
  does not add a feature; it adds a proof obligation to everything the feature
  touches. Price those words when they are written, not when they are met.
- **Ask what the feature is worth in THIS project before asking how it should be
  built.** A roguelike with permanent progression and hour-long runs earns a
  rigorous save. A beta whose battles resolve in a few minutes, played by one
  person, does not — and that difference was knowable at authorization time.
- **Feature ideas arrive free and are accepted for free.** Nothing in the
  process priced them at the moment they entered the authorization. A rough cost
  estimate attached to each completion-standard item, before the build starts,
  would have made this visible while it was still cheap to cut.

### The honest counterweight

Not all of it was waste, and the log should say so rather than flatter the
lesson. The continuation harness built for save was reused unchanged to prove
metrics survive resume (D-025), and the discipline of rejecting a save whose
fingerprint does not match is what stops a content edit silently reinterpreting
an old battle. Had save been built later and more cheaply, both would have had
to be retrofitted.

The misallocation was in **timing and proportion**, not in direction: the work
was good, there was more of it than this project needed, and it came before
gameplay concepts that were closer to the point of the exercise.

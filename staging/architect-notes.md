# Architect notes — deferred design items

Items raised during the beta port that are **not part of the porting work** and
must not be built as part of it. Recorded here so they reach design rather than
being lost in a transcript, and so a future implementer can tell "deferred on
purpose" from "overlooked".

Each entry states what beta 0.1 currently does, what it should do, and why the
difference matters — so the item can be scheduled without re-deriving the
argument.

---

## AN-001 — DISABLER/Drain must be manually targeted at a System Program

**Raised by the director, 2026-08-23. Do not build during the port.**

**What beta 0.1 does:** tapping DISABLER fires immediately at the System Program
holding the most charge. `battle_screen.gd::_fullest_enemy_slot()`, reached from
`_begin_activation` when the Function's target kind is `UNIT`.

**What it should do:** arm, and wait for the player to tap one of the System's
four Program controls. Same select-then-act shape the Packet-targeted Functions
already use — armed control stays lit, illegal regions dim, tapping the armed
control again cancels without spending charge.

**Why it matters.** Auto-targeting the fullest slot is not a neutral
simplification; it silently removes the decision the Function exists to create.
Draining the fullest pool is *usually* right and specifically not always: the
fullest Program may be one whose Function barely threatens, while a nearly-ready
Program with a devastating one sits second. Choosing which threat to delay is
the whole content of playing a DISABLER, and the current build makes that choice
for the player every time.

It also makes the two-column battle layout only half useful. The System's charge
bars are on screen precisely so the player can schedule around them — but with
no way to act on that reading, the information is decoration.

**Why it is not in the port.** Beta 0.1 has no enemy-slot picker, and the
handoff scoped the beta to reproducing the alpha's behaviour rather than
improving it. The alpha auto-targets too. This is a design change, and changing
behaviour mid-port would put the differential gate — which compares the beta's
event stream to the alpha's byte for byte — in the position of failing for a
reason that is correct. Land it after parity is signed off, and expect it to
need a trace-comparison exemption or an alpha-side change to match.

**Implementation notes for whoever picks it up:**

- The renderer already has everything needed: `_pending_target` holds the armed
  source, `UnitBox.armed` and `UnitBox.dimmed` already render the states, and
  `_system_boxes` are already built (currently with
  `mouse_filter = MOUSE_FILTER_IGNORE`, which is the only thing stopping them
  from being tappable).
- Targeting mode should dim the Hacker's controls and the board, and light the
  System's four — the mirror of what Packet targeting does today.
- `Types.TargetKind.UNIT` and `{"kind": UNIT, "idx": n}` already exist and are
  what the logic layer expects. No logic-layer change is needed.
- The Drain telemetry the log already emits (`target_program_id`,
  `target_readiness`, `charge_before`, `charge_after`) becomes considerably more
  interesting once a human is choosing the target.

---

## AN-002 — Scroll feel needs a dedicated pass

**Raised by the director, 2026-08-23, after playtesting the two-finger fix.**
"Scrolling is still not exact."

**What beta 0.1 does:** `TouchScroll` scrolls when two fingers are down inside
its rect, moving the content by the delta of the fingers' average position. The
scrollbar is widened with a grabber as the visible affordance and the fallback.

**What is unresolved.** The gesture works — it was verified with real multitouch
— but "works" and "feels right" are different standards, and this only meets the
first. Known gaps, in the order I would attack them:

- **No inertia.** The content stops dead when the fingers lift. Every scrolling
  surface a player has ever used carries momentum, so its absence reads as the
  list being stuck rather than as a deliberate choice.
- **No rubber-band at the ends.** Hitting the top or bottom is an abrupt stop
  with no feedback distinguishing "you are at the end" from "the gesture was
  dropped".
- **Two fingers is a learned gesture, not a discovered one.** Nothing on screen
  says the region needs two. The widened scrollbar hints that it scrolls; it
  does not hint how.
- **One-finger drag is still consumed by the controls.** The real fix may be a
  drag-threshold on the controls themselves — a press that moves more than N
  pixels before release becomes a scroll and the control cancels — which is what
  native scroll views do and would make one finger work everywhere.

**Recommendation.** The threshold approach is the one worth designing around,
because it removes the need for the two-finger gesture rather than papering over
it. `TouchScroll` should survive as the escape hatch either way. This is a feel
problem and needs a human iterating on a device; it is not something to specify
precisely in advance.

**Not blocking the port.** The screens are all reachable and operable. This is a
polish pass, and it belongs with whoever owns the eventual visual design rather
than with the porting work.

---

## AN-003 — A force-closed battle leaves a stale save that reads as resumable

**Raised by the director, 2026-08-23. Backburner — saving and loading can be
pushed forward.** Reproduced on the tablet during the animation fix.

**What happens:** close the app from the Android recents switcher rather than
through Save and Quit, relaunch, and the title screen offers *"Continue —
turn N"*. It restores the last EXPLICITLY saved position, which may be several
turns behind where the player actually was, or from an entirely different battle.

**Why it happens:** `SaveState.write` is called only from Save and Quit. A
force-close writes nothing, so the previous save survives untouched — and
`_show_title` offers Continue for any save that validates, with no notion of
whether it corresponds to the session just ended. Nothing is corrupt; the save
is exactly what it claims to be. The problem is that "resume" implies continuity
with what the player was just doing, and here it silently does not have it.

**Options, roughly in increasing cost:**

1. **Label it honestly.** Continue already shows the turn number; showing enough
   context to recognise a stale save (System name, turn) would at least stop it
   being a surprise. Cheapest, and does not pretend to solve continuity.
2. **Autosave at turn boundaries.** A save written at each `start_player_phase`
   makes Continue mean what a player expects. The save serializer already
   proves resume determinism, so the mechanism is in place — the question is
   write frequency and whether flash wear on an old device matters.
3. **Save on lifecycle events.** `NOTIFICATION_APPLICATION_PAUSED` /
   `WM_CLOSE_REQUEST` cover the recents-switcher case specifically. Android
   gives no guarantee a force-stop delivers these, so this complements autosave
   rather than replacing it.

**Recommendation:** option 2, with option 1 alongside. Autosaving on the turn
boundary is the only one that makes the offer trustworthy, and the boundary is
already the point the save format is designed around — `test_save.gd` proves an
interrupted battle resumed from there plays out identically.

**Not blocking the port.** Save and resume works correctly through the supported
path, which is what the completion standard asks for. This is about an
unsupported exit being handled gracefully rather than about the save format.

---

## AN-004 — Reported blank/stuck screen after Build on desktop

**Raised by the director, 2026-08-24, relaying a third-party report. Not a
priority; needs reproduction before it needs a fix.**

**What was reported:** a friend ran the beta 0.1 build on **PC** — apparently
through the Godot editor rather than an exported Android APK, though the exact
launch path was not established — and reported that the screen after confirming
the Build came up **blank and appeared stuck**, with no obvious way forward.

**What is and is not known:**

- Unconfirmed on any device we control. Every tablet and S25 gate for beta 0.1
  passed through Build into Battle, so this is not a defect the Android gates
  saw.
- The launch path is unverified. "In the Godot interface" most likely means
  `godot-gui` running `scenes/main.tscn` on a desktop window, which is **not a
  configuration beta 0.1 was gated on** — beta 0.1's presentation was verified
  on Android only, and Windows desktop is listed as a later release target.
- The most likely explanation is therefore a **presentation/layout failure at
  desktop window sizes**, not a logic failure: the battle screen builds against
  a portrait mobile viewport and the `UiTheme.px()` scale (alpha CSS px
  multiplied by ~2.51 for a 1080 px viewport). A desktop window with a very different aspect ratio or
  DPI could plausibly lay the board out off-screen, which would read exactly as
  "blank and stuck" while the battle underneath is running normally.
- A genuine hang in `Game` resolution is the less likely alternative, and would
  contradict the headless suite and DEEPSCAN, which exercise the same logic
  path with no scene tree at all.

**How to investigate when it comes up:**

1. Reproduce locally with `godot-gui` on `scenes/main.tscn`, at both a default
   editor window size and a deliberately wide one.
2. Check the Godot output panel for a script error at the Build → Battle
   transition. A blank screen with a clean log points at layout; a blank screen
   with an error points at a null node reference on a desktop-only code path.
3. If the log is clean, confirm whether input still works — a battle that
   responds to taps in dead space is a layout failure, not a hang.

**Why it is deferred:** Windows desktop is a later build target and was never
gated for beta 0.1, so this is a defect against a configuration that has not
been claimed to work rather than a regression against one that has. It is worth
keeping because the **Build → Battle transition is exactly the seam beta 0.2
extends** (Run Build before every battle), and because it is the first signal
that the presentation layer does not survive a non-mobile viewport — which the
Windows target will eventually have to answer anyway.

---

## AN-005 — "Abandon Run" destroys a Run on one tap, with no confirmation

**Raised during the beta 0.2 port, 2026-08-24. Not blocking; a design question
rather than a port defect.**

**What beta 0.2 does:** the Run result screen carries an `Abandon Run` button.
Tapping it calls `SessionSave.clear()` and returns to the title. The Run is gone
— every acquired UPGRADE, the committed Boss, three battles of progress —
with no confirmation step and no undo.

It sits directly below `Continue Run` on a phone-sized panel.

**Why it is like that:** the alpha reaches the same outcome through
`WIZARD_RESTART_RUN` and through starting a New Run, both of which are more
deliberate acts than a single tap on a result screen. Beta 0.2 needed *some*
exit from a Run for testing and gave it the plainest possible implementation.
The port authorization does not specify the control, so inventing a confirmation
flow would have been designing rather than porting.

**Why it is worth revisiting:** the New-Run boundary is already treated as
special — committing a Boss is documented as the destructive act, and it
replaces the save deliberately. `Abandon Run` is equally destructive, sits one
tap away from the button a player presses every battle, and is not marked as
destructive in any way.

**Options, roughly in increasing cost:**

1. **Move it.** Put abandonment on the title screen, or behind the Run context,
   rather than adjacent to the button pressed after every victory. Cheapest, and
   removes the mis-tap without adding a dialog.
2. **Confirm it.** A second tap ("Abandon — are you sure?"), matching the
   select-then-confirm pattern every list screen already uses. Consistent with
   the established idiom, which is an argument in its favour.
3. **Make it recoverable.** Keep the abandoned Run recoverable until the next
   New Run commits. More state to reason about, for a case that may not warrant
   it.

**Recommendation:** option 2, because select-then-confirm is already the answer
this project gives to "a mis-tap on a phone should be free", and applying it to
the one genuinely destructive control is consistent rather than novel.

Related to AN-003 in spirit: both are about a control whose consequence is
larger than its presentation suggests.

---

## AN-006 — Battle screen overflowed horizontally on the S25 — RESOLVED

**Found during the Beta 0.3 §23.2 phone window, 2026-08-25. RESOLVED the same
day — the hypothesis below was confirmed and fixed. Kept in full because the
diagnosis is the useful part, and because it names a device-testing technique
worth reusing.**

### Resolution

The seed label was the cause. It now sits on **its own row** above the debug
controls, so its width cannot enter the button row's minimum.

Clipping the label was tried first and **rejected**: it kept the layout correct
but truncated the seed to `seed 205953`, and a seed you cannot read is not a
diagnostic. Its own row keeps the value complete *and* keeps it out of the
buttons' width.

Verified at the phone viewport with a ten-digit seed — the exact case that
failed — margins symmetric at 12 px left and right, every control present, and
`seed 1943671255` fully legible.

**Confirmed on the S25 itself afterwards**, closing the gap the emulated
viewport could not cover: the layout is clean against the real display cutout,
with no impingement, and the Override marker is legible on the physical panel.
§23.2 is signed off on hardware.

### The technique worth reusing

The phone did not need to be tethered for the fix. `adb shell wm size 1080x2340`
on the **tablet** reproduced the failure exactly, giving a full edit-build-verify
loop on the always-connected device. `wm size reset` restores it.

That converts "a defect only the phone can see" into an ordinary iteration, and
it is worth reaching for before asking for a device window. It does restart the
app, so relaunch after setting it.

**Symptom.** On the Galaxy S25 (1080×2340), the battle screen renders wider than
the viewport: the opponent ICE bar, the entire right-hand Program column, the
board's eighth column, and the debug bar's `log` button are all clipped at the
right edge. Reproduced on a clean launch with the screen awake and unlocked, so
it is not an artefact of the app starting behind the keyguard.

**It is NOT Boss-specific.** An ordinary Random Quick Match on the same phone,
same build, fits perfectly with a symmetric margin. That is what made it look
like a Boss defect at first.

### What was measured, so this is not re-derived

| Check | Result |
| --- | --- |
| Safe-area insets, Boss vs ordinary battle | **identical** — `control=(1080,2340) screen=(1080,2340) safe=[(0,96)…(1080,2244)] insets=(0,96,0,0)` |
| Content extent, ordinary QM | left 15, right **1064** — symmetric, correct |
| Content extent, Boss battle | left 15, right **1079** — clipped at the screen edge |
| `AvatarBox` / `UnitBox` minimum width | **none** — both are pure `_draw` with shrink-to-fit |
| Battle root VBox child minimums (headless, 1080 wide) | header 119, grid 4, debug bar 282–364, all far below the ~1068 root width |

**The safe area is ruled out** and **minimum sizes as measured headlessly are
ruled out**, which is the useful half of this note.

### The leading hypothesis, unconfirmed

The failing screenshot's seed was `1278219584` (10 digits); the passing one's was
`7898945` (7). The battle debug bar is an `HBoxContainer` containing a
`seed %d` Label, and its minimum width **does** grow with digit count —
measured 282 at `seed 1`, **364** at `seed 1278219584`.

That correlates perfectly with the device evidence, and it has an obvious
cause: **F-002 replaced the always-`0` gameplay seed with large randoms**, so
this row got materially wider in this build and never did before.

The gap in the theory: 364 is still well under the ~1068 px root width in a
headless measurement, so minimum size alone should not overflow. Device font
metrics may differ from headless, or the growth may interact with the
`AspectRatioContainer` board sizing. **Not confirmed** — it needs one more phone
window with instrumentation on the debug bar's resolved rect.

### Why it did not appear before

- Beta 0.2's phone gate ran Quick Match with the seed pinned at `0`, so the row
  was at its narrowest.
- The tablet is 1200 px wide and has ~120 px more room, so it absorbs the
  growth. Every Boss battle played there fit.

This is the second time the tablet has structurally been unable to see a phone
problem (the first being the safe-area conversion itself, P-031).

### Suggested fix direction

Whatever the exact mechanism, the debug bar should not be able to drive the
battle layout's width. Options, cheapest first:

1. **Clip the seed label** — give it `clip_text = true` and a fixed width, or
   show a shortened form. A diagnostic readout must never resize the game.
2. **Move the seed out of the bar** — into the pause menu, where width is free.
3. **Make the debug bar its own overlay** rather than a VBox row, so it cannot
   participate in the battle layout's sizing at all.

Option 1 is the smallest and is probably correct regardless of the root cause:
nothing in a debug affordance should be load-bearing for player-facing layout.

**Release builds are not affected** — the bar is `OS.is_debug_build()` only —
but every device test runs on a debug build, so it degrades exactly the
configuration used to evaluate the game.

---

## AN-007 — The overlay type ring diverged from the alpha, undocumented

**Found during Beta 0.3.1 Gate B, 2026-08-26, by the director's recollection
rather than by any instrument. Suspended the same day — see D-037.**

The beta drew a coloured ring outside the ownership badge to carry an overlay's
type. The alpha never had one: type rides the badge's centre character alone.

**The interesting part is not the ring. It is that nothing could see it.**

- The differential compares the event stream, and presentation is not in it.
- 3,122 headless tests do not touch the scene layer by design — layer purity is
  what makes the logic provable and is the same boundary that leaves the
  renderer unproven.
- `test_presentation.gd` enforces that appearance decisions live in the
  registry. It cannot ask whether an appearance decision was CORRECT.
- Every device pass looked at it. A ring around a badge looks deliberate,
  because it was — just not by the alpha.

It survived beta 0.1, 0.2 and 0.3, four device gates, and a full Boss battle
played to RUN COMPLETE. It was caught by a person remembering what the alpha
looked like.

**The generalizable point.** The port has a rigorous instrument for behaviour
and none at all for appearance, and the project has been treating "the
differential is green" as though it covered the whole build. It covers the half
that can be compared. For the other half the only instrument is someone who
knows the reference — and that instrument has now found three of this project's
defects (P-042, AN-006, this one).

**Worth considering for a future pass**, without widening 0.3.1: the alpha can
still render every screen, and a side-by-side capture at matched state would
turn "someone remembers" into something repeatable. That is not a pixel
differential — the beta is deliberately not pixel-identical — but a human
comparing two screenshots deliberately is a far better instrument than a human
looking at one and trying to recall the other.

---

## AN-008 — The pause menu calls every battle a "Quick Match"

**Found during Beta 0.3.1 Phase D, 2026-08-26, while photographing the
converted pause panel over a Boss battle. NOT fixed — see below.**

`battle_screen.gd:236` sets the pause panel's mode line to the literal
`"Quick Match"`. The label is a local, is never stored, and is never updated.
So it reads "Quick Match" over a Run battle, and over the ODANSHAY battle at the
end of a Run.

It was true when written. Beta 0.1 had no Run, so every battle genuinely was a
Quick Match; the line became wrong the moment Beta 0.2 landed the Run loop, and
nothing pointed at it because nothing reads a label.

**This is the P-043 shape for the third time** — a literal that outlived the
build it was true in. The first was the title screen reading "beta 0.2"
throughout 0.3 development; the second was `run.gd` describing its own stop
point in the past tense. The recurring cause is the same: a string that encodes
a fact about the build, written where the fact happens to be true, with nothing
downstream that would notice when it stops being.

**Why it is not fixed here.** §13 says a pre-existing defect exposed by the
graphics pass gets reported rather than folded in, and a mode label is not
chrome. The fix is genuinely three lines — hold the Label, and set it from the
session's mode when the panel is shown — and it is available on request rather
than being taken unilaterally.

**Worth considering with it:** the pause panel already has the room to say
something more useful. Over a Run battle the honest line is the one the Build
screen already computes — `Battle 3 of 4 · vs MIDNIGHT` — and that is
information a paused player actually wants. That is a design call, not a bug
fix, which is the other reason to leave it here rather than decide it mid-pass.

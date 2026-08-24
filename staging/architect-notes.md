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

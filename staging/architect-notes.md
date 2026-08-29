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

---

## AN-009 — Font licences must reach the player before release

**Raised by the director, 2026-08-28, during Beta 0.3.2 font selection.
Deliberately deferred — do not build during this iteration.**

The v0 bundled fonts are **IBM Plex Sans** and **IBM Plex Mono**, both under the
SIL Open Font License 1.1. `assets/fonts/OFL.txt` sits with the font files, and
the two families ship the byte-identical licence (IBM Corp, Reserved Font Name
"Plex"), so one copy covers both.

OFL 1.1 permits bundling in a commercial product. What it also requires is that
the licence **travel with the Font Software** — a copy in the repository
satisfies that for the source tree, and does not obviously satisfy it for a
player holding only an installed APK.

**Deferred by decision, not by oversight.** While the director is the only
person building and running the application, the repository copy is sufficient.
The obligation becomes real at first distribution to anyone else.

**What a future build needs to decide:**

- whether a link is sufficient, or whether the licence text must be reachable
  from inside the game;
- if in-game: an attribution screen, a credits panel, or a line in a settings
  screen — none of which exist yet;
- whether the final chosen fonts even carry this requirement. v0 is explicitly
  not the final typography (§6.2), and a different licence may ask for
  something different or nothing at all.

**The cheap version, for whoever picks this up:** the text framework this build
creates already makes an attribution screen nearly free — it is a screen title,
a body block, and a Back button, all of which are semantic content rows by then.
The work is deciding where it lives in the menu, not building it.

---

## AN-010 — The bundled fonts carry ~40× more glyphs than the game uses

**Raised by the director, 2026-08-28. Not addressed in Beta 0.3.2.**

The three bundled faces total **557 KB**:

| File | Size |
| --- | --- |
| `IBMPlexSans-Regular.ttf` | 213.1 KB |
| `IBMPlexSans-SemiBold.ttf` | 213.1 KB |
| `IBMPlexMono-Regular.ttf` | 130.7 KB |

The game's entire verified corpus is **98 characters** — printable ASCII plus
`·`, `—` and `→`. IBM Plex ships Latin Extended, Greek, Cyrillic and a large
symbol range, so the overwhelming majority of every file is glyphs this game
cannot display.

A subset limited to the actual corpus would plausibly land in the **10–25 KB**
range per face, cutting roughly half a megabyte.

**Why it is not urgent.** The APK is ~55 MB, so this is about 1% of it. It is
not why the build is large, and doing it under time pressure would risk the
saving being taken out of a glyph somebody needed.

**Why it is worth doing anyway.** The cost is per-face, so it grows with every
weight or role added — three faces today, and a real typography pass could
easily want six. Subsetting once establishes the step; adding it later means
re-litigating it against a bigger pile.

**The mechanism.** `pyftsubset` (from `fonttools`) is the standard tool, run at
build time with the corpus as its glyph list and the subset TTFs committed. Two
caveats worth writing down now:

- it adds a Python build dependency the project does not currently have;
- a subset font is **silently wrong** if the corpus later grows — a new
  character renders as a hollow box with no error anywhere.

**That second risk is already handled.** `tools/check_fonts.gd` derives the
corpus from the content CSVs and scene literals and asserts every character
resolves to a glyph in every bundled face. It was written for this build's
coverage requirement, and it happens to be exactly the guard that makes
subsetting safe: subset too aggressively and it fails on a build machine rather
than on a device.

**So the sequencing is: subset, then let the existing checker prove it.** That
is the whole reason to do it deliberately rather than opportunistically.

---

## AN-011 — Excel strips leading whitespace on CSV import

**Found during Beta 0.3.2 Gate B import, 2026-08-28. Worked around, not
solved — the constraint belongs to the tool.**

Four `text_content.csv` rows encoded the battle log's hierarchy as two leading
spaces. After the director imported the CSVs into the master workbook and
exported, those spaces were gone — not from the export, from **the workbook
itself**. Excel discards leading whitespace when importing a CSV cell.

Interior whitespace survives: `"Weak:   {colors}, {shapes}"` came back intact.
Only leading is lost.

**Consequences worth knowing before authoring more copy:**

- Any string whose meaning depends on a leading space cannot survive this
  authoring pipeline. Indentation, hanging alignment, and deliberate leading
  padding are all unsafe.
- The loss is **silent and unrecoverable from the workbook**. Once imported, the
  original is gone; only the agent's generated CSV or version control has it.
- It is not caught by reading. Both parties looked at the sheet and saw nothing
  wrong. It surfaced from a mechanical diff of the round trip.

**Worked around** by moving the indentation into the renderer (D-046), which is
where it arguably belonged anyway.

**If leading whitespace is ever genuinely needed in authored copy**, the options
are a sentinel character the loader converts (`_` or `·` → space), a dedicated
`INDENT` column in `text_style.csv`, or authoring that sheet outside the
workbook. None is needed today, and none should be built speculatively.

The general shape is worth keeping: **a round trip through a spreadsheet is a
lossy channel, and which losses it inflicts are not obvious in advance.** The
mitigation is not to trust it less but to diff it every time —
`tools/export_workbook.py --check` exists for that.

---

## AN-012 — One text row was fixed in `data/`, not in the workbook

**Beta 0.3.2 Phase G, 2026-08-28. Needs one workbook edit before the next
export, or the fix is silently reverted.**

`GAME_UI_PATH_BOSS_TAG` rendered as `ODANSHAY·  BOSS` — no space before the
separator. Its authored value was `"  ·  BOSS"`, and Excel discarded the two
LEADING spaces on import (AN-011), leaving `"·  BOSS"`.

**Fixed the same way D-046 fixed the battle log:** the row is now the bare word
`BOSS`, and the separator `"  ·  "` is composed in `main.gd`. Spacing that
positions a suffix against a name is composition, not something the game says —
and it is the one kind of content this authoring pipeline cannot carry.

**The problem:** the fix was applied to `data/text_content.csv` directly, so the
workbook and the exported data now disagree. `tools/export_workbook.py --check`
reports the drift, and **the next export from the workbook will silently undo
it**.

**What the director needs to do — one cell:**

> `text_content` sheet, **cell `C130`** (row `GAME_UI_PATH_BOSS_TAG`), set `EN`
> to exactly `BOSS` — no leading spaces, no separator.

Then `python tools/export_workbook.py` and the two agree again.

**Status at closeout (2026-08-28): fixed in the director's working workbook,
not yet re-staged.** `staging/breach datastructures.xlsx` is the copy from the
Gate-B import and still reads `'·  BOSS'` at `C130`; the director's own copy has
the correction and will be re-exported once other authoring changes accumulate.

Nothing is at risk today — `data/text_content.csv` carries the correct value, so
the shipped build is right, and the two will agree the moment the next export
happens.

**The thing to actually confirm at that import** is not this row but the
whitespace class it belongs to: any row whose text begins with a space will have
been flattened again, silently, by the same Excel behaviour. Run
`python tools/export_workbook.py --check` before and `--check` after, and treat
any unexpected drift as suspect rather than as noise.

**The general point, which is the reason this is an architect note rather than a
commit message.** §15 makes the workbook authoritative once imported, and this
build has now produced two edits that went the wrong way through that boundary —
this one and the earlier `BOS_ID` restoration. A one-way authority needs a
one-way habit: **fix in the workbook, export, never edit `data/` by hand.**

`--check` exists precisely so a violation is visible rather than silent, and it
should probably run as part of the verification gate rather than on request.

---

## AN-013 — Cloning an asset pack needs three fixes, two of them silent

**Raised by the director, 2026-08-28: "to make a new skin I copy the v0
directory and edit the rasters — do I have to edit anything else?" Answered by
testing rather than by reasoning, and automated.**

**Yes — three things, and only one announces itself.**

### 1. Duplicate resource UIDs (Godot warns)

Every `.import` carries a `uid://`, and a copy duplicates it. Godot prints
`UID duplicate detected between …` on import and **does not resolve it** —
the engine then holds two files claiming one identity.

Fix: delete the `.import` files. Godot regenerates them with fresh UIDs.

### 2. `detect_3d/compress_to` reverts to 1 (SILENT)

Regenerating the `.import` files restores Godot's default of `1`, which tells
the engine to silently re-import a texture as VRAM-compressed the first time it
believes it is used in 3D. Nothing here is 3D — but the setting turns authored
lossless art lossy with nobody editing anything, which §2.2 of the graphics
authorization forbids. Beta 0.3.1 patched all 44 assets to `0`; **the patch is
not inherited by a copy and does not survive regeneration.**

### 3. `pack.tres` still points at the source pack (SILENT)

Its `ext_resource` entries are absolute paths, not relative references, so a
copied `pack.tres` renders the OLD skin from the new directory. This is the
failure that presents as "I edited the PNGs and nothing changed".

Fix: delete it and regenerate with `gen_pack_resource.gd --pack <name>`.

### The tooling

Rather than leave this as a checklist to remember — precision and endurance, so
automate it:

```
python tools/new_pack.py v1        # clone, drop .import files, drop pack.tres
godot --headless --import          # Godot regenerates imports with fresh uids
python tools/fix_imports.py v1     # re-apply detect_3d
godot --headless -s res://tools/gen_pack_resource.gd -- --pack v1
```

Then edit the PNGs and/or `packet_palette.svg`, and point
`Graphics.DEFAULT_PACK` at the new `pack.tres`.

`manifest.json` needs no attention — it is regenerated by `gen_assets.gd` and
read only by the contact sheet.

### What answering this found

`tools/fix_imports.py --check` immediately reported **11 of 55 v0 textures at
the unsafe default** — `title_logo` and the ten countdown digits, every asset
added during beta 0.3.2. The 0.3.1 patch had been applied to the 44 assets that
existed then, and nothing re-applied it to the eleven that arrived later.

That is a live defect in the shipped pack, and it was invisible: the game
renders correctly, the suite passes, the asset checker passes. It surfaced only
because a question about *future* packs prompted a check that could see it.

**`fix_imports.py --check` should join the verification gate**, alongside
`export_workbook.py --check`. Both are the same shape — a boundary where a
setting can revert without anyone touching it.

---

## AN-014 — The authoring bundle: art without architecture

**Requested by the director, 2026-08-28, ahead of the graphics-jig
authorization. Built.**

**The ask:** a directory containing only asset files, handable to an artist, an
agent, or the director himself, editable "without having to consider the
architecture to which it will be applied".

**The shape:** `authoring/<name>/` holds the PNGs, the palette SVG, and a
generated `README.md`. Nothing else — no `.import` files, no `pack.tres`, no
`manifest.json`. It can be zipped and sent to someone who has never seen this
repository, and everything needed to make it loadable happens on the engine side
of the line.

```
python tools/asset_bundle.py export v0            # pack   -> bundle
python tools/asset_bundle.py check v0             # validate
python tools/asset_bundle.py build v0 --pack v1   # bundle -> pack
```

**`.gdignore` is what makes it possible.** Without it Godot generates `.import`
files inside the bundle the moment the editor opens, and the separation
collapses silently. Verified: a full `--import` leaves the tree untouched.

### The spec is the contract

`asset_bundle.py`'s `SPEC` lists every semantic key with its dimensions, its
9-slice margin, whether the game **tints it at runtime**, and one line on what it
is. `check` validates a bundle against it, so a missing or mis-sized asset fails
on a build machine rather than as a magenta checker on a device. Confirmed by
damaging a bundle deliberately — both a deleted file and a wrong-sized one were
caught with the specifics.

**The tint rule is the one that matters and the one no validator can catch.**
A tinted asset is authored white with its shape in the alpha channel; the game
multiplies it by a colour chosen at runtime. Author it in colour and the game
looks wrong with no error anywhere, because the file is perfectly valid. The
generated README states it first, marks every affected asset **TINT** in the
table, and says explicitly that it is the one mistake that produces no error.

### Round trip verified

`authoring/v0` → `assets/packs/v1` → loads at runtime with six glyphs, ten
digits and a parsed palette, `pack.tres` carrying 56 self-referencing paths and
zero leftovers from the source pack. The test pack was then removed; creating a
real skin is the director's call.

### For the jig authorization

The jig's job is rapid iteration on art. This gives it a natural input: a jig
that watches `authoring/<name>/` and rebuilds a pack from it is a much simpler
thing to specify than one that manipulates engine resources directly, and it
reuses `build` + `fix_imports` + `gen_pack_resource` rather than growing a
parallel path — which is what §19 of the 0.3.1 authorization asked for.

Worth noting for scope: **the bundle boundary is now the third of these seams**
this project has drawn, after the graphics pack contract and the text sheets.
Each one converted "remember to do the right thing" into "the tool does it, and
`--check` says when it hasn't".

---

## AN-015 — The jig is deferred, and its justification has changed

**Director decision, 2026-08-28, after the graphics and text passes.**

The graphics-jig iteration was named as the next planned build in the 0.3.1
authorization §19. **It is deferred**, and the reasoning is worth recording
because the case for it is now a *different* case than the one originally made.

### The original justification no longer holds

The jig was justified as offline asset iteration — trying art on a PC without
spending a build cycle. Two things undercut that:

- **A build is cheap.** Export plus install is about three minutes of wall clock
  and near-zero agent tokens. The expensive part of a device check is driving
  and verifying it, which a jig relocates rather than removes.
- **A skin switcher covers the coarse case.** Built in this session: packs are
  discovered at runtime, and a debug control on the title screen cycles them
  live. Multiple skins ship in one build — a pack is 471 KB against a 50 MB
  APK — so comparing directions no longer needs a rebuild at all.

### What actually needs a jig

**Work that cannot be delegated to an agent at all.** That is a much sharper
criterion than "work that is slow", and it produces a much shorter list:

| Work | Can an agent judge it? |
| --- | --- |
| Asset colour, shape, contrast | Yes — from a screenshot |
| Layout, fit, overflow | Yes — from a screenshot |
| **Animation timing and feel** | **No** — a still cannot carry motion |
| **VFX intensity** | **No** — "too much / too little" is a felt judgement |
| **Audio mix, timing, texture** | **No, and not even partially** |

**Audio is the strongest argument, and the director's point.** Everything else on
that list, an agent can at least approximate — frames can be captured, a
sequence can be reasoned about. Audio it cannot touch at all: I cannot listen. A
sound is not slow for me to evaluate, it is *impossible*, and no amount of
tooling on this side changes that.

So the jig's real purpose is **a harness for the judgements only a human can
make**, and its value scales with how much of the game is made of those. Today
that is zero: there is no animation system, no particles, no shaders, no audio —
all explicitly out of scope in 0.3.1, and none of it added since.

### Sequencing

Build the jig **after** the systems it would preview exist, and after content, so
the effort level the presentation warrants can be judged against a game that is
actually there rather than a skeleton.

When it is specified, specify it around the undelegatable work:

- play a real battle, not a static preview — timing needs the game running
- scrub, slow, and repeat a single effect
- adjust intensity and timing without a rebuild
- and for audio, the same, with a mix

An asset previewer would be the wrong tool built on a justification that has
already expired.

### What was built instead

`Graphics.installed_packs()` / `load_pack_named()`, and a debug skin picker on
the title screen. A live swap moves three things together — the pack, the Theme
(which bakes pack textures into its styleboxes), and the current screen — and
missing any one leaves a half-swapped UI that reads as a rendering bug.

A second skin, `phosphor`, was generated from `03-terminal-phosphor.jpg` through
the authoring bundle to prove the whole path: recolour a bundle, `check`,
`build`, import, `fix_imports`, `gen_pack_resource`. It touched no engine file.

**Verified on the tablet**: the picker reads `[debug] skin: v0`, tapping it
swaps panel, buttons, rule, board and Packet palette live, and the log is clean.

### Two defects the exercise found

**The palette SVG was imported as a texture in the cloned pack.** `fix_imports`
only handled `*.png.import`, so nothing re-applied `importer="keep"` and Godot
rasterised the file — which stops it shipping, and the game reads it as TEXT at
startup. The skin swapped with no palette and logged `no palette SVG at …`. Same
class as the text CSVs in Phase D, and found the same way: on a device. Fixed in
the tool, so it cannot recur for a future pack.

**`bar_fill_link` and `bar_fill_ice` both became green.** A mechanical recolour
treats each file independently, and those two carry meaning only by CONTRAST —
they are the two sides' health, side by side in the header. Both files were
valid, every check passed, and the result was a screen where you cannot tell who
is winning.

That is a whole class the validator cannot reach, so it went into the bundle
README as a table: **pairs that must stay different from each other** — the two
bar fills, the two ownership badges, the four Program-box states, selected vs
disabled, and the six palette colours. An artist recolouring by hand would
probably preserve these by instinct; an agent recolouring by rule will not, and
this project intends to do the latter.

`phosphor` is a proof of the pipeline, not a finished look — a mechanical
recolour with the contrast problem above still in it.

---

## AN-016 — Skins can change pixels but not representation

**Director observation, 2026-08-28, after seeing six skins swapped live. For
requirements analysis during the dedicated art phase — not to be built now.**

The skin system swaps **which pixels**. It cannot swap **what a thing is made
of**. A Program's charge is always a horizontal track with a proportional fill,
because that is what `UnitBox._draw` does; a skin can restyle the track and the
fill and nothing else.

The director's examples: show charge as large `x/y` numerals instead, or as a
circle filling radially. Both are the same *value* presented as a different
*thing*, and no amount of art can express either.

### The distinction worth carrying into the requirement

Three concerns, not two, and the middle one does not exist today:

| | What it decides | Where it lives now |
| --- | --- | --- |
| **Layout** | where a control is, how large, what it sits inside | code — deliberately, and a req-defined build changes it |
| **Composition** | what a control is MADE OF — bar vs numerals vs radial | **nowhere. Hardcoded in each `_draw`.** |
| **Skin** | what those parts look like | the asset pack, swappable today |

Calling the gap "layout flexibility" undersells it and risks the requirement
asking for the wrong thing. Position is not the problem — nobody wants to move
the charge bar three pixels. **Representation** is the problem.

### What it would plausibly look like

A small sheet in the shape of `text_style.csv`, which already proves the pattern:
a data file that says how a class of thing behaves without saying where it is.

```
COMPONENT,VARIANT
PROGRAM_CHARGE,BAR | NUMERALS | RADIAL
AVATAR_STAT,BAR | NUMERALS
PACKET_OVERLAY,BADGE | CORNER_TAG
```

A bounded enum, not a stylesheet — which respects the "not full CSS" instinct
and bounds the work naturally, because **every variant is a draw path somebody
has to write.** Three variants is three implementations. That cost is the
feature: it keeps the vocabulary honest.

### What already helps

`UnitBox._draw` is not a monolith — it already draws frame, binding swatch,
name, charge text and charge bar as separable steps, each reading a value it
does not own. The refactor is extracting those into selectable renderers, not
inventing a component model from nothing. `AvatarBox` is the same shape.

### Two cautions for whoever writes the requirement

**Variants multiply the constraints that are already hard to check.** A numerals
variant makes the mono font load-bearing where it is currently a nicety. A
radial variant makes the control's aspect ratio matter where it currently does
not. The "pairs that must stay different" rule in the bundle README grows a
dimension: a skin could pick two variants that are individually fine and
together unreadable.

**Sequence it after content.** Which representations are worth building depends
on what the game needs to communicate, and content adds things to communicate. A
variant vocabulary chosen against the current four UPGRADEs and one Boss would be
chosen against a skeleton.

### Related

This is the third thing deferred to the art phase, and they interlock: the VFX
and audio work in AN-015 needs a jig, and a jig previewing components is a much
more useful tool than one previewing textures. Worth authorizing them together
rather than separately.

### AN-016a — corner treatments imply a content inset the code cannot know

The director's second example: let a skin round or chamfer its box corners.

The art side is already possible — `panel.png` is a 9-slice and a skin can draw
whatever corner it likes. What is not possible is the consequence. A chamfer
eats the corner, so text that currently sits at `px(6)` has to move in, and
**only the art knows by how much.** Content margins are code constants shared by
every skin, so a heavy chamfer either clips its own label or every skin pays for
the worst case.

Cheap to close, and the file already exists. Each manifest entry carries `slice`,
`stretch`, `w`, `h`, `alpha`:

```json
{"key": "panel", "slice": 16, "stretch": "", "w": 48, "h": 48}
```

A `pad` alongside `slice` is the same kind of number in the same place, read by
the same loader, validated by the same bundle `check`. The art declares its own
clearance and the layout honours it.

**The director's caveat is the harder half, and is sharper than it first looks.**
The impingement is not only the box's own text. Two Program boxes sit side by
side; a chamfer on one's top-right and its neighbour's top-left both eat into
the *same gutter*, at the same height. So the constraint is **between siblings**,
not within a control — which means `pad` alone does not settle it, and the art
phase needs a rule for whether neighbours may overlap their clearances or the
gutter must grow to fit both.

That is a real design question, not an implementation detail, and it is the
reason this belongs in a requirement rather than in a quick change.

---

## AN-017 — The camera cutout as stage rather than hazard

**Director observation from the `bzone` proof of concept, 2026-08-28. Not to be
built now; sequence with the art phase.**

`bzone` unifies the header into one continuous border across the top and
happens to leave centre cutouts on the top and bottom edges. **This was not
intentional.** The director's observation is that the top cutout falls where a
phone's punch-hole camera sits — so a zone the app currently treats as dead
margin could become deliberate framing.

The idea is good and worth a requirement. Two things about it are not what they
look like.

### It is not an art feature

Today `main.gd` and `battle_screen.gd` both apply the safe area as **margins on
the container that holds everything.** Frame and content move inward together.
There is no full-bleed layer, so there is currently nowhere for a border to be
drawn that reaches the camera at all. Getting there means splitting the shell in
two — background/frame full-bleed, content inset — which is a small change
conceptually and a shell-wide one in practice.

### The cutout's position is per-device, so it cannot be a texture

This is the part that would go wrong if the requirement is written as "draw the
frame with a cutout". `UiTheme.safe_area_insets` reduces
`DisplayServer.get_display_safe_area()` to four scalars:

```gdscript
return Vector4i(safe.position.x * sx, safe.position.y * sy,
                (screen.x - safe.end.x) * sx, (screen.y - safe.end.y) * sy)
```

It keeps **how much** is unsafe and throws away **where**. A cutout baked into a
PNG at a fixed offset would be correct on the device it was authored against and
wrong on every other — and on the Galaxy Tab A, which has no cutout and reports
no inset, it would frame nothing and read as an unexplained notch in the border.

So the top border cannot be one texture. It has to be composed at runtime — end
caps plus a spanning piece, positioned from a safe-area **rect** the helper does
not currently preserve. Widening that return value is the enabling change, and
it is worth noting now because it is invisible from the art side.

### The rule that keeps it safe

Whatever goes in that zone must be **decorative only** — never text, never a
control, never state a player needs. The camera occludes part of it on some
devices and none on others, and the app cannot enumerate the shapes. Framing
survives that; information does not.

### Why it is worth doing anyway

It costs screen area the app currently spends on nothing, on the hardware the
game is actually played on, and it makes the frame look authored for the device
rather than letterboxed onto it. That is squarely the "cool factor" the graphics
pass was authorized for.

Group it with AN-015 and AN-016 — one art-phase requirement covering
composition, frame geometry and VFX/audio, with a jig that can preview all
three, rather than three separate ones.

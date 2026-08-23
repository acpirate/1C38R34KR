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

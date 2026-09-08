# Beta 0.4.0 — S25 phone pass

Galaxy S25 (`SM_S938U`, 1080×2340), `beta-0.4.0` debug, 2026-09-07.

| File | Shows | Verdict |
| --- | --- | --- |
| `00-title.png` | Boss Attack on the title | fits |
| `01-chooser.png` | Four Bosses, mode prompt, Choose/Back | fits, room to spare |
| `02-capacitor.png` | RAHNDAHL, 1-damage tick, Capacitor placed | mark legible |
| `03-logic-bomb.png` | NEHBOCYET, row cleared, bomb armed top row | mark legible |
| `04-echofall-shape-hidden.png` | ECHOFALL hiding the SHAPE axis | **see below** |
| `05-skin-swap-under-concealment.png` | Mid-battle skin swap to `16bit` while COLOUR is concealed | works; one observation below |

## Layout — clear

The battle debug bar is the thing this pass existed to check. It gained a
seventh button (`skin`) in 0.3.2.2 and had only ever been measured on the
tablet's 1200 px. On the phone's 1080 it spans **x 16–1013, leaving ~67 px** —
tight, but nothing clips and the board keeps all eight columns. AN-006's failure
mode has not returned.

Header, Program grid, board, message stack and seed row all fit. The punch-hole
inset is respected; nothing sits under the camera.

## Both new marks read at phone density

CAPACITOR's two plates and LOGIC BOMB's descending chevrons are both legible
inside the badge at ~50 px, and neither can be mistaken for BOMB's circle,
BUFF's cross, SHIELD or OVERRIDE's slashed ring. That was the open question
from the tablet pass and it is answered.

## Finding: hidden SHAPE is hard to read

`04` is the first time the RNG chose the SHAPE axis on any device — the tablet
rolled COLOUR every time.

The implementation is correct against §8.2: no shape, real colour retained,
neutrals still distinguishable (white static versus coloured static). But as a
board to actually play, it is poor. Every cell is a sparse ~40 % noise field, so
a colour reads as a dim broken scatter rather than as a colour, and several
cells — the magenta at row 1 col 4, the blue at row 8 col 1 — are genuinely hard
to name at a glance. The whole board reads as one wall of noise.

Compare `../04-echofall-colour-hidden.png`: white solid shapes on dark are crisp
and instantly readable.

**The cause is a reused treatment, not a bug.** The static pattern was designed
for neutrals, where being unreadable *is* the message. Concealed axis Packets
inherit that unreadability — and then have to carry a colour the player is
expected to match on. Those two jobs are opposed.

**Cheapest fix that stays inside §8.2:** keep "no shape, real colour" but make
the colour carry — a solid colour field with a lighter noise overlay, or simply
a much higher fill density, instead of sparse dots on black. The Packet still
has no shape; it just stops hiding its colour too.

Left for the director: this is a qualitative call, and §19 puts presentation
redesign outside this build.

## Device log — clean, with one caveat about the method

Buffer cleared, then the app exercised for ~40 s: cold launch, content load,
Boss Attack chooser, an ECHOFALL battle with a Sync and a full Boss phase, and a
mid-battle graphics-pack swap. **113 lines accumulated, none from the app and
none at error level.** No `E/godot`, no `SCRIPT ERROR`, no resource or importer
failure. The only line naming the package is Samsung's
`D/FreecessHandler: skipping freeze com.acpirate.ic38r34kr` — the OS declining
to freeze a foreground app, which is benign.

**The caveat:** I intended to confirm by filtering on the app's own pid, so that
"no app lines" could be distinguished from "looking in the wrong place". The
phone disconnected before that ran. The clear-then-exercise method is still good
evidence — a script error or a failed resource load would have landed in that
window — but it is one step short of what I wanted.

## Bonus finding: the skin swap works mid-battle on the phone

`05` was captured while checking the log, and covers ground the tablet pass did
not: swapping to `16bit` **during** an ECHOFALL battle with COLOUR concealed.
Seed, turn, LINK and ICE all survive the view rebuild, and concealment survives
the reskin — 16bit's blocky glyphs render white with their pixel silhouettes
intact, neutrals still distinguishable.

## Observation to reproduce: a blank line in the message stack

`05` shows the message stack as `line clear` / **blank** / `24 damage to Hacker`.
No other frame in either device pass shows a gap, and no `EVT.MSG` emitter in
`game.gd` can produce an empty string — so an empty message is not the cause.

It appeared only in the frame **after** the mid-battle skin swap, which points at
the `view_prefs` message restore in the rebuilt screen rather than at the battle
itself. Not reproduced: the phone disconnected before it could be chased, and one
screenshot is not enough to name a cause. Worth ten minutes with a device before
0.5 — it is cosmetic, but it is in the path that 0.3.2.2 added and that this
build inherited.

## Hardware note

The phone dropped off the bus **twice** during this pass, both times mid-command
with no action at this end, and needed a physical replug to come back. Worth
suspecting the cable before suspecting anything on the device.

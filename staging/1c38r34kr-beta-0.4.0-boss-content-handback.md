# 1C38R34KR Beta 0.4.0 — Boss Content Pass
## Handback

**Build:** `beta-0.4.0`
**Verdict:** complete against the authorization. All 47 completion-standard
items met. Two items were resolved past the authorization's silence and are
called out below; nothing was descoped.

---

## 1. Verdict against the authorization

| § | Item | Result |
| --- | --- | --- |
| 3 | Four Bosses, 350 ICE, shared Program set | done |
| 5 | ODANSHAY unchanged but for ICE | done, proven by differential |
| 6 | RAHNDAHL | done |
| 7 | NEHBOCYET | done |
| 8 | ECHOFALL | done |
| 9 | CAPACITOR / LOGIC_BOMB identities + art in all six packs | done |
| 10 | Boss Attack mode | done |
| 11 | Workbook and text-content additions | done, imported by the director |
| 12 | FNC_021 / FNC_022 through ordinary Function resolution | done |
| 13 | Defeat short-circuiting | done |
| 14 | One post-settle integration point | done |
| 15 | Save/resume of new Boss state | done, schema 3 |
| 16 | Alpha/differential position | stated in §11 below |
| 17 | Automated verification | 3,475 pass, 0 fail |
| 18 | Device verification | tablet, all four Bosses played |
| 19–20 | Presentation constraints and out-of-scope | respected |

---

## 2. Boss roster shipped

| ID | Name | ICE | Strong colours | Strong shapes | Programs |
| --- | --- | ---: | --- | --- | --- |
| `BOS_01` | ODANSHAY | 350 | GRE:BLU:MAG | SQU:CIR:DIA | S_004:S_002:S_007:S_003 |
| `BOS_02` | RAHNDAHL | 350 | RED:YEL:GRE | STR:TRI:SQU | same |
| `BOS_03` | NEHBOCYET | 350 | CYA:MAG:RED | SQU:CRO:DIA | same |
| `BOS_04` | ECHOFALL | 350 | BLU:GRE:YEL | DIA:CRO:TRI | same |

The workbook arrived with `PRG_SET` already populated for BOS_02–04, so §3's
"may still show blank" did not apply. `in_pool` was removed from the sheet by
the director; see §9.

---

## 3. Architecture used

Per-Boss orchestration in `scripts/logic/boss.gd`, dispatched from
`Boss.start_of_turn` / `Boss.end_of_turn`, hardcoded per §4. **No PSV rows, no
trigger DSL, no data-driven turn hooks.**

`Game.run_enemy_phase` calls the dispatcher at the instant ODANSHAY's threshold
has always occupied — after HOST START_OF_TURN passives, before countdowns.
All four Bosses specify "the beginning of the Boss phase" and that is the same
moment, so no new ordering was invented.

Only ODANSHAY acts at end-of-turn. The others place at the start of their own
phase, which is what their rules say and also leaves the placement visible to
the Hacker for a full turn before it matters.

### The one abstraction taken

`Boss._place_one_special(state, cells, type, events)`. CAPACITOR and LOGIC_BOMB
share a real rule — preferred pool, fallback pool, silent overwrite, fizzle on
empty — and writing it twice would have been two chances to get the fallback
backwards. `Boss.has_boss_special` states the pool predicate once (D-047).

Nothing else was extracted. The three start-of-turn sequences look nothing
alike and were left looking nothing alike.

---

## 4. CAPACITOR semantics as shipped

- Discharge `2^n` at the start of **every** RAHNDAHL phase, `n` counted BEFORE
  placement — so a Capacitor placed this phase first contributes next phase.
- The zero-Capacitor tick of 1 fires on phase 1, as authored.
- Ordinary damage: Shield and permanent Shield reduce it under the existing
  ordering. Attribution is D-050.
- Placement: any non-neutral Packet; prefers those carrying no Boss special;
  falls back to those that do; fizzles when no non-neutral Packet exists.
- A Hacker special does **not** move a Packet into the fallback pool, so a
  Capacitor overwrites one freely.
- Overwriting is silent — nothing activates, no charge, no damage.
- No on-destroy effect. Removing the carrier removes the Capacitor.
- The shift is clamped at `1 << 30`. Sixty-four Capacitors would overflow a
  64-bit int and wrap **negative**, turning lethal damage into healing. The
  clamp sits far above any survivable value, so it changes no reachable
  outcome — it only refuses to be absurd.

---

## 5. LOGIC BOMB semantics as shipped

- Start of every NEHBOCYET phase: the bottom row is **removed** — Packets, not
  just overlays — with no damage, no charge, and no special activation, since
  those overlays are cleared rather than destroyed.
- The board then settles through `Resolve.settle_after_effect`, so anything the
  refill Syncs pays out normally. Only the clear itself is inert.
- One LOGIC BOMB is then armed on the top row, after the settle, so it is never
  armed into a moving board.
- Placement pools as CAPACITOR. Neutrals excluded — D-048, the one place this
  build read past the authorization's silence.
- **The invariant:** a settled board may not retain a LOGIC BOMB in the bottom
  row. Enforced at the end of `Resolve.resolve_cascades` (§6).
- Trigger removes the entire carrier Packet, inertly, then fires `FNC_021` once
  per bomb through ordinary Function resolution — so ordinary Shield applies to
  each instance independently.
- Several bombs qualifying from one settle each fire once, left to right.
  Carriers are removed before any Function fires, so a bomb cannot be destroyed
  by another bomb's damage and skip its own detonation.
- The chain repeats until stable or until the Hacker is defeated.

---

## 6. The post-settle hook (§14)

`Resolve.resolve_cascades` is genuinely the single settle chokepoint:
`settle_after_effect` delegates to it, and the only two
`apply_gravity_and_refill` call sites are inside those two functions. So the
invariant is stated once, against **movement itself**, rather than being re-wired
onto each source that happens to move Packets.

Two implementation points worth recording:

**`Game` is threaded, not back-referenced.** The hook must cast an authored
Function, which lives on `Game`; `Resolve` is static and has none. A
`GameState → Game` pointer would be a reference cycle for the sake of one call,
so `game` is an optional trailing parameter on `resolve_cascades`,
`settle_after_effect`, `detonate_at` and `resolve_detonation`. Null means "no
Boss hook", and every battle path passes it.

**A latch, not recursion.** Resolving a bomb settles the board again, which
re-enters the hook. `GameState.bomb_chain_active` makes the outermost call own
the chain, so "repeat until stable" is a loop of known shape rather than a
recursion of unknown depth. It is deliberately not serialized: it is only ever
true partway through resolving an event, and a save captured with it true would
resume unable to detonate anything.

**Ordinary battles are unaffected** — one string comparison per settle, and fast
parity is 150/150.

---

## 7. ECHOFALL state representation

Two fields on `GameState`, both serialized:

- `boss_phase: int` — incremented in `Boss.start_of_turn` before any rule reads
  it, so "phase 1" means the same thing for every Boss. Read rather than
  `turn` so the cadence keeps its meaning if turn accounting ever changes.
- `hidden_axis: int` — `-1`, `ConcealAxis.COLOR`, or `ConcealAxis.SHAPE`.

Concealment is presentation only. `PacketView.hidden_axis` changes what is
painted; the view Dictionary still carries the true colour and shape, and
`MatchFinder`, targeting and every Function keep reading them.

- **Colour hidden:** the real glyph modulated white. The texture's darker
  outline survives, so the shape stays matchable by eye.
- **Shape hidden:** the static treatment tinted with the Packet's real colour —
  which is what keeps it distinguishable from a neutral, since neutrals draw the
  same noise with no colour at all (§8.2).
- Overlays and ownership badges are unaffected and remain fully legible;
  verified on device with SHIELD marks and armed countdown digits visible under
  concealment.

Concealment gets its own playback beat. Folded into the next refresh the whole
board would change between frames, and a player who does not *see* it happen
reads a masked board as a rendering fault rather than as the Boss acting.

**Reveal:** any first board attempt reveals. A valid one resolves normally with
no BRAINSCRAMBLE; an invalid one fires `FNC_022` once, does not commit, does not
consume the move, and reveals — so a later invalid attempt in the same phase
finds nothing hidden and is an ordinary miss. Only a manual swap counts (D-049).

---

## 8. Boss Attack

`Title → Boss Attack → Boss list → battle → result`.

`Session.create_boss_attack` is deliberately **not** `create_quick_match` with a
Boss substituted. It differs in exactly the respect that matters — the opponent
takes authored ICE with no Run ladder — and sharing a constructor would have
meant a branch on opponent kind inside a Quick Match path, which is how the
ladder gets applied to a Boss by accident.

- Hacker `HAK_01` CR45H, Deck `DEK_01` AGIMA, HOST `HST_01` THRESHOLD, no
  UPGRADEs.
- The build is `Session.default_build()` — the canonical one, not a copy.
- New selection source `SystemSelectionSource.BOSS_ATTACK`, appended.
- The roster comes from `_boss_options()`, shared with Run Boss Selection, so
  the two screens cannot list different Bosses.
- `New battle` returns to the roster; replay keeps Boss and seed; `Back to
  title` clears the mode flag **there** rather than on the next entry — a stale
  Boss id would quietly turn the following Quick Match into a Boss battle.
- Victory text uses a Boss-specific row, because "System ICE breached" names
  the wrong kind of opponent.

**All four Bosses now also appear in Run Boss Selection** (director, 2026-09-02).
That falls out of the data: `Content.all_bosses()` drives that screen, and Boss
ICE already bypasses Run escalation, so they enter a Run at 350 too.

---

## 9. Workbook, text and graphics changes

**Workbook.** Imported as supplied. `in_pool` removed from `BOS` — it was
already documented as inert, but it had one live reader: `_fingerprint_bosses`
still indexed it and crashed the loader. Found by running, not by reading.

**Text.** Ten rows, authored by the director from
`staging/beta-0.4.0-text_content-additions.md`: three `BOSS_NAME`, two
`FUNCTION_NAME`, and five Boss Attack UI rows. Two hardcoded `"Quick Match"`
literals in `main.gd` were migrated into the framework at the same time.
`export_workbook.py --check` is clean.

**Graphics.** `CAPACITOR` and `LOGIC_BOMB` appended to `Tile.Special.Type` —
appended, because the ordinal is the key into every pack's `overlay_mark` and
`overlay_ring`. The contract sizes those arrays from the enum, so all six packs
had to gain four files each; the validator refusing to build was the design
working.

`tools/gen_boss_marks.py` renders each shape through each pack's own style
rather than pasting one silhouette six times: v0/neon90s/phosphor smooth,
16bit/terminal blocky, bzone a hollow outline. CAPACITOR is two plates with
leads; LOGIC BOMB is two descending chevrons — both chosen to stay clear of the
existing circle, cross, shield and slashed ring.

Two rendering faults were caught by *looking at the output*:

- Eroding to hollow bzone's outline produced a **solid** mark, because every
  pixel of a thin bar is within the erosion radius of its own edge. It now
  renders the shape twice at different stroke weights and subtracts. Coverage
  went from 24% to 10%, against bzone's own bomb at 12%.
- At a 16px grid the capacitor's plates and leads merged into a **cross**,
  colliding with BUFF — exactly what §9.1 forbids. The grid is now 32.

---

## 10. Test coverage

**3,475 pass, 0 fail, no `SCRIPT ERROR`.** `tests/test_boss_04.gd` adds 119
assertions.

Kept out of `test_boss.gd` deliberately: that file's value is that ODANSHAY's
regression has not changed. The new Bosses have no alpha counterpart, so the new
file is their oracle rather than a comparison.

| Group | Covers |
| --- | --- |
| RAHNDAHL scaling | `2^n` at n = 0,1,2,3,4,6 |
| RAHNDAHL Shield | the tick reduced by ordinary Shield |
| RAHNDAHL order | tick precedes placement; phase 2 ticks for 2 |
| RAHNDAHL lethal | defeat prevents placement |
| RAHNDAHL pools | Hacker special overwritten from the preferred pool; Boss special only from fallback; preferred pool honoured across five seeds |
| RAHNDAHL fizzle | all-neutral board places nothing and continues |
| CAPACITOR inert | destroying the carrier deals nothing and grants nothing |
| NEHBOCYET clear | row removed, refilled, cleared Bomb does not detonate |
| NEHBOCYET pools | top row only; preferred pool across four seeds; fallback overwrites |
| NEHBOCYET fizzle | all-neutral top row |
| LOGIC BOMB invariant | none survives a settle in the bottom row; exactly FNC_021's damage |
| LOGIC BOMB multiple | three bombs each fire; chain terminates |
| LOGIC BOMB source | triggers from gravity through `settle_after_effect`, not only the Boss clear |
| ECHOFALL cadence | conceals on 1,3,5 and not on 2,4 |
| ECHOFALL axis | both axes reachable over 40 seeds; same seed, same axis |
| ECHOFALL identity | colour, shape and every overlay unchanged; MatchFinder indifferent |
| ECHOFALL valid move | resolves, reveals, no FNC_022 |
| ECHOFALL invalid move | not committed, FNC_022 once, reveals, Hacker may act |
| ECHOFALL second attempt | no repeat punishment after reveal |
| ECHOFALL lethal | battle ends, Boss wins |
| ECHOFALL save | axis, phase counter and future cadence survive round-trip |
| Boss Attack | identities, canonical build, replay determinism, authored ICE for all four, roster from content |

---

## 11. Differential position (§16)

**Fast battle parity: 150/150, no divergence.** The `resolve.gd` threading is
inert for ordinary battles.

**Boss parity fails at 350, and that is the authored change.** Every divergence
is a *longer* beta battle — more events, more turns — which is the signature of
+100 ICE. Proven rather than asserted: with `bos.csv` temporarily set back to
the alpha's 250, boss parity is **60/60 with no divergence**. ODANSHAY is
bit-identical to the alpha; only the authored number differs.

That check is worth keeping as a procedure: the alpha can still validate
ODANSHAY's *mechanics* by neutralising the one content difference.

**DEEPSCAN was not rerun, and here is the reasoning.** The build did touch
shared core — `resolve.gd` gained a parameter and a call at the end of
`resolve_cascades`. But the call is guarded by `game != null` and then by a Boss
ID comparison, so for any non-NEHBOCYET battle it is one comparison and a
return; and fast parity at 150/150 exercises exactly the ordinary battles
DEEPSCAN would broaden. Prior DEEPSCAN proof is carried forward.

**Recommend rerunning DEEPSCAN** before the next build that touches
`resolve.gd` for any reason other than a guarded hook.

---

## 12. Device verification

**Galaxy Tab A, 1200×1920, `beta-0.4.0` debug.** All four Bosses played through
Boss Attack.

- **Chooser** lists all four from content, all at ICE 350, correct strong axes,
  with the mode-specific prompt rather than the Run one.
- **RAHNDAHL** — "1 damage to Hacker" on phase 1, "2 damage" on phase 2, exact
  `2^n`. Capacitor badges accumulate visibly; the plates mark is readable at
  tablet density and distinct from BUFF's cross.
- **NEHBOCYET** — bottom row visibly cleared and refilled; a LOGIC BOMB armed
  top-right with its chevrons legible. The 13 damage that turn came from
  ordinary Boss Programs, not the clear.
- **ECHOFALL** — colour concealment renders the whole board as white shapes with
  outlines intact and neutrals still recognisably static. Cadence confirmed:
  concealed on Boss phases 1, 3 and 5, plain on 2 and 4. SHIELD marks and armed
  countdown digits stayed fully legible while masked.
- **BRAINSCRAMBLE** — forced with a two-neutral swap, which can never match:
  exactly 30 damage (LINK 83 → 53), board revealed, ICE unchanged so the swap
  was not committed, and still "your move" so the Hacker may retry. Three
  earlier concealed attempts all turned out to be *valid* — the swap matched on
  the axis I could not see, which is the mechanic working as intended and is
  worth experiencing.

Screenshots in `staging/design-reference/boss-0.4/`.

**S25: not exercised, and here is the reasoning.** No battle-layout geometry
changed in this build — no new controls in the battle screen, no change to the
debug bar's width, no change to the header or the board. The two new marks are
64px overlay art drawn inside the existing badge rect at the existing scale, and
the concealment treatment repaints existing Packets without moving anything. The
0.3.2.2 phone sign-off therefore still covers the layout. **Recommend a batched
phone window anyway** before 0.5, to confirm the two new marks and the
concealment treatment at phone density — those are legibility questions, and
legibility is the one thing the tablet cannot answer for the phone.

---

## 13. Defects found during implementation

All mine, all fixed unless noted.

1. **`_fingerprint_bosses` read the dropped `in_pool` column** and crashed the
   loader. The column was documented as inert; it had one reader nobody
   remembered.
2. **`_authored_damage` in the new test file read `fn["ops"]`**, which does not
   exist. GDScript aborts the calling function on a missing Dictionary key, so
   the helper returned 0, two damage assertions compared against zero *and
   passed*, and everything after them stopped running. This is precisely the
   0.3.1 failure whose description I copied into the helper's docstring while
   repeating it.
3. **Two more missing keys** left a nominally green run emitting `SCRIPT ERROR`:
   `Types.EVT.BOMB_DETONATED` does not exist (it is `DETONATE`), and `identity`
   carries `hacker_programs` / `opponent_selection_source`, not `build` /
   `opponent_source`. §17.7's rule — treat any script error in a green run as a
   failure until explained — is what caught both.
4. **`PacketView` kept a private copy of the special-type names.** With two new
   types it would have drawn every Capacitor and Logic Bomb as a **Bomb**:
   `find` returns −1 and the fallback is index 0. It now reads
   `Resolve.SPECIAL_TYPE_NAMES`.
5. **`check_assets._check_marks` had the same private list**, so neither new
   mark was examined for tone, coverage or distinctness. Same fix.
6. **bzone's outline mark rendered solid**, and **16bit's capacitor merged into
   a cross** — both §9 above, both caught by looking at the generated art rather
   than by any check.
7. **Duplicate, and partly false, Boss log line** — AN-018. Pre-existing, left
   alone deliberately.

The through-line is the same one 0.3.2 recorded: **four of these seven are one
list restated in a second place.** Three private copies of the special-type
names, and a fixture key duplicated from memory.

---

## 14. Records updated

- **Decisions** D-047 … D-052.
- **Architect notes** AN-018 (logic layer writes prose), AN-019
  (`check_assets` covers one pack of six).
- **Lessons learned** appended.
- **README** build status refreshed.

---

## 15. Deferred questions

**Balance.** RAHNDAHL is the sharpest: `2^n` with no cap and Capacitors that
only leave when their carrier is destroyed means the fight has a hard clock —
eight Capacitors is 256 damage against 150 LINK. Whether that clock is the
intended difficulty or merely the intended *shape* is a tuning question, and
§20 puts balancing out of scope. Worth playing before deciding.

**ECHOFALL's shape concealment** was not observed on device — the RNG chose
COLOUR on every seed played. It is covered by test (both axes reachable across
40 seeds) but a person should look at coloured static before it is called good.

**The art phase notes stand:** AN-015 (VFX/audio jig), AN-016 (composition),
AN-017 (frame geometry), and now AN-019. AN-019 in particular is worth doing
*before* hand-authored packs start arriving faster than anyone will inspect them.

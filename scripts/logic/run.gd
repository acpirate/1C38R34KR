class_name Run
extends RefCounted

## A committed Run: four battles, an escalating opponent, and a Boss chosen at
## the start.
##
## A Run is saveable with NO battle in progress — parked on a Path Choice, on a
## pre-battle Build, or (new in beta 0.2) on the `PENDING_BOSS_BATTLE` stop.
## Route offers are real persisted state, never a transient screen: reloading a
## Path Choice restores exactly what was offered and never rerolls.
##
## Everything immutable for the Run's lifetime is stamped in at commitment —
## `settings`, `hacker_max_link`, `inventory`, `boss_id`. Editing title Settings
## halfway through a Run must not reach back and change what the Run meant.
##
## Beta 0.2 scope: this models Battles 1-3 and the final Boss ROUTE. Boss combat
## itself is beta 0.3, and the Run deliberately stops at `PENDING_BOSS_BATTLE`
## rather than fabricating a Battle 4.


# ---------------------------------------------------------------------------
# Encounter table
# ---------------------------------------------------------------------------

const RUN_LENGTH := 4

## Additive ICE modifiers by step — an explicit table, NOT a formula.
##
## Effective System ICE is `selected System BASE_ICE + modifier`, so a
## BASE_ICE=100 System yields the established 100/150/200 ladder while a future
## System with different durability escalates correctly without redesigning Run
## progression.
##
## Step 4's +150 is DEAD DATA and is carried deliberately. The only opponent
## that can appear at step 4 is a Boss, and a Boss takes its authored BASE_ICE
## with no modifier at all — ODANSHAY's authored 250 is already the final
## Boss-battle value, so adding the step-4 modifier would double-count the
## escalation. The row is kept because the alpha has it and beta 0.3 needs the
## table shape; see the beta 0.2 authorization review §B1.
const RUN_ENCOUNTERS := [
	{"step": 1, "ice_modifier": 0},
	{"step": 2, "ice_modifier": 50},
	{"step": 3, "ice_modifier": 100},
	{"step": 4, "ice_modifier": 150},
]


static func encounter_for(step: int) -> Dictionary:
	return RUN_ENCOUNTERS[step - 1]


## The next step, or 0 when the Run is on its last one.
static func next_step(step: int) -> int:
	return step + 1 if step < RUN_LENGTH else 0


# ---------------------------------------------------------------------------
# Route offers
# ---------------------------------------------------------------------------

## One offered path: a complete encounter package plus the reward for taking it.
##
## The opponent is an HONEST union. A step-4 offer names the Run's selected Boss
## with `opponent_kind = BOS`; it never stores a placeholder SYS_ID, and there is
## no placeholder System row anywhere in the content.
class PathOffer extends RefCounted:
	var index := 0  ## 0-based position on screen, for logging and audit
	var opponent_kind: Types.OpponentKind = Types.OpponentKind.SYS
	var opponent_id := ""
	var host_id := ""
	var upgrade_id := ""

	func _init(
		i: int = 0,
		kind: Types.OpponentKind = Types.OpponentKind.SYS,
		oid: String = "",
		hid: String = "",
		uid: String = "",
	) -> void:
		index = i
		opponent_kind = kind
		opponent_id = oid
		host_id = hid
		upgrade_id = uid

	func to_dict() -> Dictionary:
		return {
			"index": index,
			"opponent_kind": Types.OPPONENT_KIND_NAMES[opponent_kind],
			"opponent_id": opponent_id,
			"host_id": host_id,
			"upgrade_id": upgrade_id,
		}

	static func from_dict(d: Dictionary) -> PathOffer:
		var kind := Types.OPPONENT_KIND_NAMES.find(str(d.get("opponent_kind", "")))
		if kind < 0:
			return null
		return PathOffer.new(
			int(d.get("index", 0)),
			kind as Types.OpponentKind,
			str(d.get("opponent_id", "")),
			str(d.get("host_id", "")),
			str(d.get("upgrade_id", "")),
		)


## The pending offers for one upcoming battle. Persisted verbatim and restored
## verbatim — reloading a Path Choice NEVER rerolls.
class PendingPath extends RefCounted:
	var step := 1  ## the battle these offers lead into
	var offers: Array = []  ## of PathOffer

	## True when the eligible pool held only one UPGRADE and both cards
	## therefore show it. RECORDED rather than inferred, so a log can say why
	## the duplicate happened instead of leaving it looking like a bug.
	var upgrade_exhausted := false

	func to_dict() -> Dictionary:
		var out: Array = []
		for o in offers:
			out.append(o.to_dict())
		return {"step": step, "offers": out, "upgrade_exhausted": upgrade_exhausted}

	static func from_dict(d: Dictionary) -> PendingPath:
		var p := PendingPath.new()
		p.step = int(d.get("step", 0))
		p.upgrade_exhausted = bool(d.get("upgrade_exhausted", false))
		for raw in (d.get("offers", []) as Array):
			var o := PathOffer.from_dict(raw)
			if o == null:
				return null
			p.offers.append(o)
		if p.step < 1 or p.step > RUN_LENGTH or p.offers.size() != Content.PATH_CHOICE_COUNT:
			return null
		return p


# ---------------------------------------------------------------------------
# Run state
# ---------------------------------------------------------------------------

## Committed at New Run start and FIXED for the whole Run. Step 4 always uses
## exactly this ID.
var boss_id := ""

var step := 1

## Taken at Boss commitment and authoritative for the whole Run. Never
## rederived from current menu settings.
var settings := {}

var hacker_id := ""
var deck_id := ""
var selection_source: Types.SelectionSource = Types.SelectionSource.EXPLICIT_SELECTION

## The effective Hacker maximum LINK, resolved once when setup completed. Stored
## rather than recomputed because it depends on `settings`, which is frozen.
var hacker_max_link := 0

## The Run's fixed six-Program inventory and the ordered build that carries from
## one battle to the next. Both are Run-scoped: discarded with the Run, never
## leaked into a later one, and never shared with Constructed Quick Match's
## remembered build.
var inventory: Array = []
var build: Array = []
var build_origin: Types.BuildOrigin = Types.BuildOrigin.DEFAULT

## The UPCOMING battle's opponent, resolved exactly once when the path is
## committed and then persisted. Reopening Build, saving and quitting, resuming,
## or retrying after a defeat all reuse it; only progressing to a new step rolls
## a new one. At step 4 this is the selected Boss.
var opponent_kind: Types.OpponentKind = Types.OpponentKind.SYS
var opponent_id := ""
var opponent_source: Types.SystemSelectionSource = Types.SystemSelectionSource.RUN_RANDOM

## The committed HOST for the current encounter, chosen with the opponent as one
## package at the Path Choice and never re-resolved.
var host_id := ""

## Every UPGRADE acquired so far, in acquisition order. That order is their
## START_OF_TURN resolution order, so it is real gameplay state rather than a
## display convenience. Unique by ID.
var upgrade_ids: Array = []

## The isolated ROUTE RNG state. Persisted so a save and reload cannot perturb
## later route generation compared with an uninterrupted Run: generation always
## continues the same stream from where it left off, and it never touches the
## battle's gameplay RNG.
var route_rng_state := 0

## The seed the route stream started from. This is the Run's IDENTITY in the
## logs: every session record carries it, so a whole Run can be reassembled from
## a log file, and a Run reported from a device can be replayed in the harness.
var route_seed := 0

## The exact pending offers while the Run sits on a Path Choice. Null otherwise.
var pending_path: PendingPath = null

## A concluded battle whose result has not been accepted yet.
##
## REAL saveable state, not renderer state: the player can close the app on a
## result screen and must come back to it. Empty when no result is pending.
##
##   natural        — Types.NaturalOutcome, the honest outcome of the battle
##   forced_win     — a wizard Force Win was applied; it never overwrites
##                    `natural`, so a forced victory stays distinguishable from
##                    an earned one in the record
##   metrics_logged — guards against double-appending the battle record across a
##                    save and resume boundary
var pending_result := {}

## Where the Run is parked.
##
## The alpha DERIVES this at serialization time from "is there a pending path /
## is there a battle / is there a pending result". Beta 0.2 stores it, because
## `PENDING_BOSS_BATTLE` is not derivable from those three — with no battle and
## no pending path it is indistinguishable from `PENDING_BUILD`. One field with
## an enforced invariant beats three booleans that can contradict each other.
## Recorded in port-notes.
var phase: Types.SessionPhase = Types.SessionPhase.PENDING_PATH


# ---------------------------------------------------------------------------
# Route RNG
# ---------------------------------------------------------------------------

## The isolated route stream, resumed from its persisted state.
##
## Deliberately its own instance so that generating or reviewing route offers
## cannot consume or perturb the battle's gameplay stream: a `Game` seeds its
## own RNG independently, so the board, refills, and AI sequence for a given
## gameplay seed are unaffected by anything the route layer does.
##
## `Rng.new()` takes the raw internal state, so this resumes the exact sequence.
func route_rng() -> Rng:
	return Rng.new(route_rng_state)


## Store a route stream back after it has been advanced. Every generator must
## call this, or an interrupted-and-resumed Run would replay draws an
## uninterrupted one had already consumed.
func store_route_rng(r: Rng) -> void:
	route_rng_state = r.get_state()


# ---------------------------------------------------------------------------
# UPGRADE acquisition
# ---------------------------------------------------------------------------

## Acquisition is IDEMPOTENT by ID.
##
## When the eligible pool holds one UPGRADE, both offered paths legitimately
## show it; taking either acquires it exactly once and the acquired list stays
## unique and ordered.
static func acquire_upgrade(acquired: Array, upgrade_id: String) -> Array:
	var out := acquired.duplicate()
	if not out.has(upgrade_id):
		out.append(upgrade_id)
	return out


## The UPGRADEs still available to offer: every valid row not already acquired,
## in authored order. That order is load-bearing — route generation shuffles
## this array, so reordering it changes which UPGRADEs a given seed offers.
func eligible_upgrades() -> Array:
	var out: Array = []
	for u in Content.all_upgrades():
		if not upgrade_ids.has(u["id"]):
			out.append(u)
	return out


# ---------------------------------------------------------------------------
# Transitions
# ---------------------------------------------------------------------------

## The Hacker's maximum LINK for this Run.
##
## Normal LINK ON: the Hacker's BASE_LINK plus the Deck's ADD_LINK. OFF: the
## manual setting, which overrides both and is never silently combined with them.
##
## Resolved once from the Run's frozen settings snapshot, so changing the menu
## mid-Run cannot move a committed Run's LINK ceiling.
static func resolve_hacker_max_link(settings_in: Dictionary, hacker_id_in: String, deck_id_in: String) -> int:
	if not settings_in["normal_link"]:
		return int(settings_in["manual_hacker_link"])
	return int(Content.hacker(hacker_id_in)["base_link"]) + int(Content.deck(deck_id_in)["add_link"])


## The enemy's maximum ICE for one Run encounter.
##
## Normal LINK ON:
##   - a SYSTEM opponent takes its BASE_ICE plus that step's additive modifier,
##     so the authored 100 yields the established 100/150/200 ladder;
##   - a BOSS opponent takes its authored BASE_ICE with NO modifier at all. The
##     authored value is already the final Boss-battle ICE — ODANSHAY's 250 —
##     so adding the step-4 +150 would double-count the escalation.
##
## Normal LINK OFF: the manual enemy ICE for EVERY encounter, Boss battles
## included. There is deliberately no separate manual Boss ICE setting, and the
## manual value overrides both the base and the Run sequence rather than being
## silently combined with either.
##
## The Boss branch was written in beta 0.2, one build before anything could
## reach it, so that a step-4 System ICE could not be invented in its place.
## Beta 0.3 routes through it unchanged.
static func resolve_run_ice(
	settings_in: Dictionary, kind: Types.OpponentKind, opponent_id: String, step_in: int
) -> int:
	if not settings_in["normal_link"]:
		return int(settings_in["manual_system_ice"])
	if kind == Types.OpponentKind.BOS:
		return int(Content.boss(opponent_id)["base_ice"])
	return int(Content.system(opponent_id)["base_ice"]) + int(encounter_for(step_in)["ice_modifier"])


## This Run's committed encounter ICE.
func encounter_ice() -> int:
	return resolve_run_ice(settings, opponent_kind, opponent_id, step)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

## Replace one build slot with an inventory Program not already in the build.
##
## The build is never in an invalid intermediate state: there is no empty slot
## to assemble from and no partially built loadout. A swap that would duplicate
## a Program is refused rather than allowed and validated later.
func replace_in_build(slot: int, program_id: String) -> bool:
	if slot < 0 or slot >= build.size():
		return false
	if not inventory.has(program_id):
		return false
	if build.has(program_id) and build[slot] != program_id:
		return false
	build[slot] = program_id
	build_origin = Types.BuildOrigin.PLAYER_EDITED
	return true


## Move a build slot up or down. Order is charge-routing priority, so this is a
## gameplay edit rather than a cosmetic one.
func move_build_slot(slot: int, delta: int) -> bool:
	var to := slot + delta
	if slot < 0 or slot >= build.size() or to < 0 or to >= build.size():
		return false
	var tmp = build[slot]
	build[slot] = build[to]
	build[to] = tmp
	build_origin = Types.BuildOrigin.PLAYER_EDITED
	return true


## Inventory Programs not currently in the active build.
func inactive_programs() -> Array:
	var out: Array = []
	for pid in inventory:
		if not build.has(pid):
			out.append(pid)
	return out


## Retry the battle just lost.
##
## The SAME encounter: the opponent is not rerolled, the HOST is unchanged, no
## UPGRADE is granted again, and the current Build is preserved so the player
## can adjust it before the rematch. Only the battle itself starts over.
func retry_battle() -> void:
	pending_path = null
	pending_result = {}
	phase = Types.SessionPhase.PENDING_BUILD


## Accept a won battle and move toward the next encounter.
##
## Returns false at the last step, where there is no next path to open — the
## caller enters `PENDING_BOSS_BATTLE` instead of progressing.
func advance_after_victory() -> bool:
	var next := next_step(step)
	if next == 0:
		return false
	pending_result = {}
	# The build itself carries forward untouched. `build_origin` is deliberately
	# NOT changed here — see `opening_build_origin` for where CARRIED_RUN
	# actually belongs.
	return open_path_choice(next)


## The origin a freshly opened Build screen starts with.
##
## Battle 1 opens on the DEFAULT build for a new Run; later battles, and a
## retry, carry the current build and order forward.
##
## This is NOT `build_origin`. That field records the origin of the build the
## Run has COMMITTED, and only `confirm_build` moves it — which is the alpha's
## split between a Build screen's own state and the Run's. Stamping CARRIED_RUN
## onto the Run when a path opens instead of when a Build is confirmed was a
## real port defect, caught by the Phase E harness; see port-notes P-028.
func opening_build_origin() -> Types.BuildOrigin:
	return Types.BuildOrigin.DEFAULT if step == 1 else Types.BuildOrigin.CARRIED_RUN


## Commit the Build screen's result to the Run.
##
## `origin` is the Build screen's own origin at the moment the player confirmed:
## whatever `opening_build_origin` gave it, or PLAYER_EDITED if they changed
## anything. Phase F calls this when the Build screen is confirmed.
func confirm_build(origin: Types.BuildOrigin) -> bool:
	if not Content.is_valid_build(build, inventory):
		return false
	build_origin = origin
	return true


## Generate the offers for the next battle, after a win.
##
## Advances the persisted route stream in place, so an interrupted-and-resumed
## Run produces the same sequence an uninterrupted one would. Reopening an
## ALREADY generated Path Choice must never come through here — that is what
## would reroll it — so this refuses to run when offers are already pending.
func open_path_choice(next: int) -> bool:
	if pending_path != null:
		push_error("path choice reopened while offers were already pending — this would reroll them")
		return false
	if next < 1 or next > RUN_LENGTH:
		return false

	var stream := route_rng()
	var generated := Route.offers_for_step(stream, next, boss_id, upgrade_ids)
	if generated == null:
		return false
	store_route_rng(stream)

	step = next
	pending_path = generated
	phase = Types.SessionPhase.PENDING_PATH
	return true


## Commit one of the pending offers.
##
## Immediate and final for that battle: acquire the UPGRADE (once), commit the
## opponent and HOST as one package, drop the offers, and move to the pre-battle
## Build. Back navigation cannot undo it.
##
## Acquiring BEFORE Build is what lets the newly taken UPGRADE affect the battle
## it was offered alongside — including Battle 1.
func select_path(offer_index: int) -> bool:
	if pending_path == null:
		return false
	if offer_index < 0 or offer_index >= pending_path.offers.size():
		return false

	var offer: PathOffer = pending_path.offers[offer_index]
	step = pending_path.step
	opponent_kind = offer.opponent_kind
	opponent_id = offer.opponent_id
	opponent_source = Types.SystemSelectionSource.RUN_RANDOM
	host_id = offer.host_id
	upgrade_ids = acquire_upgrade(upgrade_ids, offer.upgrade_id)
	pending_path = null
	phase = Types.SessionPhase.PENDING_BUILD
	return true


## §12.1 — the gate into Battle 4.
##
## Entered after the final path is committed and its Build confirmed. The Run
## holds a complete Boss + HOST + UPGRADE package, and beta 0.3 consumes it.
##
## This is still NOT Run Complete, and the distinction outlived the build that
## needed it: Run Complete is presented on the step-4 RESULT, so nothing here
## may route through that path or mark the Run finished, scored, or cleared.
## A beta 0.2 save parked on this phase resumes into the Boss battle.
func enter_pending_boss_battle() -> void:
	phase = Types.SessionPhase.PENDING_BOSS_BATTLE


func is_pending_boss_battle() -> bool:
	return phase == Types.SessionPhase.PENDING_BOSS_BATTLE


## §15.1 — the Boss is beaten and the Run is over.
##
## Terminal: no fifth route is generated, no further reward is granted, and no
## Boss mechanic executes after this. Distinct from `PENDING_BOSS_BATTLE`, which
## meant the opposite — a Run poised to *begin* Battle 4.
func complete_run() -> void:
	phase = Types.SessionPhase.RUN_COMPLETE


func is_complete() -> bool:
	return phase == Types.SessionPhase.RUN_COMPLETE


## Whether the committed opponent is the Run's Boss rather than a System.
func opponent_is_boss() -> bool:
	return opponent_kind == Types.OpponentKind.BOS


# ---------------------------------------------------------------------------
# Invariants
# ---------------------------------------------------------------------------

## Structural checks that must hold for any Run reached through the intended
## transitions. Returns the reasons it does not hold, empty when it does.
##
## Used by the tests and by save validation: a restored Run that fails these is
## REJECTED rather than quietly repaired, which is the discipline carried over
## from beta 0.1's save layer.
func problems() -> Array:
	var out: Array = []
	if boss_id == "":
		out.append("no committed Boss")
	if step < 1 or step > RUN_LENGTH:
		out.append("step %d out of range" % step)

	# The pending-path invariant. These two must agree or the Run is in a state
	# no transition can produce, and reading either one alone would mislead.
	var on_path := phase == Types.SessionPhase.PENDING_PATH
	if on_path and pending_path == null:
		out.append("PENDING_PATH with no offers")
	if not on_path and pending_path != null:
		out.append("offers held outside PENDING_PATH")
	if pending_path != null and pending_path.step != step:
		out.append("offers are for step %d, Run is on %d" % [pending_path.step, step])

	# Setup phases belong to RunSetup; a committed Run can never wear one.
	if phase == Types.SessionPhase.SETUP_HACKER or phase == Types.SessionPhase.SETUP_DECK:
		out.append("committed Run carrying a setup phase")

	# The pending-result invariant, the same shape as the pending-path one.
	var on_result := phase == Types.SessionPhase.PENDING_RESULT
	if on_result and pending_result.is_empty():
		out.append("PENDING_RESULT with no result")
	if not on_result and not pending_result.is_empty():
		out.append("result held outside PENDING_RESULT")

	var seen := {}
	for uid in upgrade_ids:
		if seen.has(uid):
			out.append("UPGRADE %s acquired twice" % uid)
		seen[uid] = true

	# A Run past setup always has an inventory and a legal build. A build is
	# never partially assembled and there is no empty slot to fill.
	if not inventory.is_empty() and not Content.is_valid_build(build, inventory):
		out.append("build is not four distinct inventory Programs")

	return out


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------
#
# Stable IDs only. Immutable definitions are never copied in — they resolve
# through the envelope's content fingerprint, so a content edit invalidates the
# save honestly instead of silently changing what the Run meant.

func to_dict() -> Dictionary:
	return {
		"boss_id": boss_id,
		"step": step,
		"settings": settings.duplicate(true),
		"hacker_id": hacker_id,
		"deck_id": deck_id,
		"selection_source": Types.SELECTION_SOURCE_NAMES[selection_source],
		"hacker_max_link": hacker_max_link,
		"inventory": inventory.duplicate(),
		"build": build.duplicate(),
		"build_origin": Types.BUILD_ORIGIN_NAMES[build_origin],
		"opponent_kind": Types.OPPONENT_KIND_NAMES[opponent_kind],
		"opponent_id": opponent_id,
		"opponent_source": Types.SYSTEM_SELECTION_SOURCE_NAMES[opponent_source],
		"host_id": host_id,
		"upgrade_ids": upgrade_ids.duplicate(),
		"route_seed": route_seed,
		"route_rng_state": route_rng_state,
		"pending_path": null if pending_path == null else pending_path.to_dict(),
		"pending_result": null if pending_result.is_empty() else {
			"natural": Types.NATURAL_OUTCOME_NAMES[int(pending_result["natural"])],
			"forced_win": bool(pending_result.get("forced_win", false)),
			"metrics_logged": bool(pending_result.get("metrics_logged", false)),
		},
		"phase": Types.SESSION_PHASE_NAMES[phase],
	}


## Restores a Run, or returns null.
##
## Every reference is revalidated against CURRENT content and every enum name
## must resolve. Anything that does not is REJECTED rather than defaulted: a Run
## whose Boss no longer exists is not the Run that was saved, and quietly
## substituting one would lose the player's actual progress while appearing to
## preserve it.
static func from_dict(d: Dictionary) -> Run:
	var r := Run.new()

	r.boss_id = str(d.get("boss_id", ""))
	r.hacker_id = str(d.get("hacker_id", ""))
	r.deck_id = str(d.get("deck_id", ""))
	r.opponent_id = str(d.get("opponent_id", ""))
	r.host_id = str(d.get("host_id", ""))
	if Content.boss(r.boss_id).is_empty():
		return null
	if Content.hacker(r.hacker_id).is_empty() or Content.deck(r.deck_id).is_empty():
		return null
	if Content.host(r.host_id).is_empty():
		return null

	var kind := Types.value_of(Types.OPPONENT_KIND_NAMES, str(d.get("opponent_kind", "")))
	if kind < 0:
		return null
	r.opponent_kind = kind as Types.OpponentKind
	var opponent_exists := (
		not Content.boss(r.opponent_id).is_empty()
		if r.opponent_kind == Types.OpponentKind.BOS
		else not Content.system(r.opponent_id).is_empty()
	)
	if not opponent_exists:
		return null

	var selection := Types.value_of(Types.SELECTION_SOURCE_NAMES, str(d.get("selection_source", "")))
	var origin := Types.value_of(Types.BUILD_ORIGIN_NAMES, str(d.get("build_origin", "")))
	var source := Types.value_of(Types.SYSTEM_SELECTION_SOURCE_NAMES, str(d.get("opponent_source", "")))
	var phase_value := Types.value_of(Types.SESSION_PHASE_NAMES, str(d.get("phase", "")))
	if selection < 0 or origin < 0 or source < 0 or phase_value < 0:
		return null
	r.selection_source = selection as Types.SelectionSource
	r.build_origin = origin as Types.BuildOrigin
	r.opponent_source = source as Types.SystemSelectionSource
	r.phase = phase_value as Types.SessionPhase

	r.step = int(d.get("step", 0))
	r.hacker_max_link = int(d.get("hacker_max_link", 0))
	r.route_seed = int(d.get("route_seed", 0))
	r.route_rng_state = int(d.get("route_rng_state", 0))
	r.settings = _settings_from_dict(d.get("settings", {}))

	for pid in (d.get("inventory", []) as Array):
		r.inventory.append(str(pid))
	for pid in (d.get("build", []) as Array):
		r.build.append(str(pid))
	for pid in r.inventory:
		if Content.program(pid).is_empty():
			return null

	for uid in (d.get("upgrade_ids", []) as Array):
		if Content.upgrade(str(uid)).is_empty():
			return null
		r.upgrade_ids.append(str(uid))

	if d.get("pending_path", null) != null:
		r.pending_path = PendingPath.from_dict(d["pending_path"])
		if r.pending_path == null:
			return null

	if d.get("pending_result", null) != null:
		var raw: Dictionary = d["pending_result"]
		var natural := Types.value_of(Types.NATURAL_OUTCOME_NAMES, str(raw.get("natural", "")))
		if natural < 0:
			return null
		r.pending_result = {
			"natural": natural,
			"forced_win": bool(raw.get("forced_win", false)),
			"metrics_logged": bool(raw.get("metrics_logged", false)),
		}

	# The structural invariants are the last gate. A Run that survives every
	# reference check can still be internally incoherent — offers for the wrong
	# step, a phase that contradicts its data — and that is rejected too.
	if not r.problems().is_empty():
		return null
	return r


## JSON returns every number as a float. Settings are compared and used as ints
## and bools, so they are coerced once here rather than at each use — the same
## treatment `SaveState._config_from_dict` gives the battle config.
static func _settings_from_dict(raw) -> Dictionary:
	var out: Dictionary = (raw as Dictionary).duplicate(true)
	for key in ["manual_hacker_link", "manual_system_ice", "hint_delay_seconds"]:
		if out.has(key) and out[key] != null:
			out[key] = int(out[key])
	# `max_cascade_steps` uses null as an explicit infinity sentinel, NOT a large
	# integer. Coercing null to 0 here would silently cap cascades at zero.
	if out.has("max_cascade_steps") and out["max_cascade_steps"] != null:
		out["max_cascade_steps"] = int(out["max_cascade_steps"])
	return out

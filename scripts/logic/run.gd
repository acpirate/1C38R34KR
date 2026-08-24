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

## The exact pending offers while the Run sits on a Path Choice. Null otherwise.
var pending_path: PendingPath = null

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


## §12.1 — the beta 0.2 stop point.
##
## Entered after the final path is committed and its Build confirmed. The Run
## holds a complete Boss + HOST + UPGRADE package that beta 0.3 will consume.
##
## This is NOT Run Complete. The alpha presents Run Complete on a step-4
## RESULT, and beta 0.2 has no step-4 battle and therefore no step-4 result.
## Nothing here may route through that path, and the Run must not be marked
## finished, scored, or cleared.
func enter_pending_boss_battle() -> void:
	phase = Types.SessionPhase.PENDING_BOSS_BATTLE


func is_pending_boss_battle() -> bool:
	return phase == Types.SessionPhase.PENDING_BOSS_BATTLE


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

class_name Passives
extends RefCounted

## The PASSIVE runtime: which instances a battle has, who supplied each one,
## which agent each affects, and in what order the triggered ones resolve.
##
## THE CENTRAL RULE: an instance is NOT identified by its PASSIVE_ID. The same
## PSV row referenced by a Hacker and by a HOST is TWO instances and both apply.
## Nothing here deduplicates by passive ID, ever — that stacking IS the design,
## not an accident to be filtered.
##
## This module is the single authority for that assembly. Combat, turn
## structure, and presentation all read instances from here rather than each
## walking identity → content → passives on their own.


## One active PASSIVE, with the source that supplied it.
class Instance extends RefCounted:
	var passive: Dictionary
	var source_kind: Types.PassiveSourceKind
	var source_id: String

	## The agent that OWNS this instance, or -1 for a HOST instance.
	##
	## A HOST is deliberately unowned rather than "owned by whoever is acting":
	## it is a first-class third source, and collapsing it into an agent would
	## lose the causal fact that the battlefield did it.
	var owner: int = -1

	func _init(p: Dictionary, kind: Types.PassiveSourceKind, sid: String, own: int) -> void:
		passive = p
		source_kind = kind
		source_id = sid
		owner = own

	## The causal record for logs and metrics. Kept separate from the resolution
	## owner — the acting agent, which travels as an event's `side` — so "source
	## and owner can differ" survives serialization.
	func cause() -> Dictionary:
		return {
			"passive_id": passive["id"],
			"source_kind": source_kind,
			"source_id": source_id,
		}


const NO_OWNER := -1

## Assembly is pure over (identity, content), so it is cached per battle rather
## than stored on the game state. Storing it there would put derived data in the
## save envelope and create a second authority for "what is active"; recomputing
## it per damage instance would walk four maps on every hit.
static var _cache := {}


static func clear_cache() -> void:
	_cache = {}


## The complete active instance list, in a stable canonical order: Hacker,
## System, HOST, then UPGRADEs in acquisition order, each source's own PASSIVEs
## in authored order.
##
## Continual modifiers are additive, so this order does not change their
## arithmetic — it makes attribution and telemetry deterministic. Triggered
## resolution uses `start_of_turn` below, which imposes a different order.
static func active(identity: Dictionary) -> Array:
	var key: String = identity.get("cache_key", "")
	if key != "" and _cache.has(key):
		return _cache[key]

	var out: Array = []

	var hacker := Content.hacker(identity["hacker_id"])
	_push(out, hacker.get("passives", []), Types.PassiveSourceKind.HAK, hacker["id"], Types.Side.PLAYER)

	# Only a SYSTEM opponent contributes identity PASSIVEs. The Boss schema has
	# no PASSIVES column, so a Boss battle contributes nothing at this step —
	# deliberately, rather than for want of a place to put it.
	if identity["opponent_kind"] == Types.OpponentKind.SYS:
		var sys := Content.system(identity["opponent_id"])
		_push(out, sys.get("passives", []), Types.PassiveSourceKind.SYS, sys["id"], Types.Side.ENEMY)

	var host := Content.host(identity["host_id"])
	_push(out, host.get("passives", []), Types.PassiveSourceKind.HST, host["id"], NO_OWNER)

	# UPGRADEs are ALWAYS Hacker-owned, whatever their agent_scope says about
	# which side the effect lands on.
	for upgrade_id in (identity.get("upgrade_ids", []) as Array):
		var upg := Content.upgrade(upgrade_id)
		_push(out, upg.get("passives", []), Types.PassiveSourceKind.UPG, upg["id"], Types.Side.PLAYER)

	if key != "":
		_cache[key] = out
	return out


static func _push(out: Array, passives: Array, kind: Types.PassiveSourceKind, source_id: String, owner: int) -> void:
	for p in passives:
		out.append(Instance.new(p, kind, source_id, owner))


## The ONE scope resolver. Does this instance affect `side`?
##
##  - a HOST instance ignores the authored agent_scope entirely and applies to
##    BOTH agents symmetrically
##  - OWNER means the supplying agent
##  - ENEMY means the supplying agent's opponent
static func affects(inst: Instance, side: Types.Side) -> bool:
	if inst.owner == NO_OWNER:
		return true
	if inst.passive["agent_scope"] == "OWNER":
		return inst.owner == side
	return Types.opponent_of(inst.owner) == side


## Every active instance of one coded effect that affects `side`, in canonical
## order. Duplicates from different sources are all present.
static func affecting(identity: Dictionary, effect: String, side: Types.Side) -> Array:
	var out: Array = []
	for inst in active(identity):
		if inst.passive["effect_type"] == effect and affects(inst, side):
			out.append(inst)
	return out


## The START_OF_TURN resolution order for the agent whose turn is beginning:
## HOST passives, then the ACTIVE agent's own identity passives, then the
## Hacker's UPGRADE passives in acquisition order — Hacker turns only.
##
## Countdown ticking happens after everything returned here has fully resolved;
## that ordering belongs to the turn structure, not here.
static func start_of_turn(identity: Dictionary, active_side: Types.Side) -> Array:
	var triggered: Array = []
	for inst in active(identity):
		if inst.passive["activation"] == "START_OF_TURN":
			triggered.append(inst)

	var host: Array = []
	var own: Array = []
	var upgrades: Array = []
	var own_kind := Types.PassiveSourceKind.HAK if active_side == Types.Side.PLAYER else Types.PassiveSourceKind.SYS

	for inst in triggered:
		if inst.source_kind == Types.PassiveSourceKind.HST:
			host.append(inst)
		elif inst.source_kind == own_kind:
			own.append(inst)
		elif inst.source_kind == Types.PassiveSourceKind.UPG and active_side == Types.Side.PLAYER:
			upgrades.append(inst)

	var out: Array = []
	out.append_array(host)
	out.append_array(own)
	out.append_array(upgrades)
	return out


## Instances of one qualifying colour-axis effect for a side. Stacking is
## simply a matter of counting them.
static func match_axis_bonus(identity: Dictionary, effect: String, side: Types.Side, color: int) -> Array:
	var out: Array = []
	for inst in affecting(identity, effect, side):
		if inst.passive["color"] == color:
			out.append(inst)
	return out


## Total dampening applied to `side`'s qualifying charge streams.
static func charge_dampen(identity: Dictionary, side: Types.Side) -> int:
	var n := 0
	for inst in affecting(identity, PassiveEffects.CHARGE_DAMPEN, side):
		n += _magnitude(inst)
	return n


## The non-removable Shield protecting `side`. Added to live Packet Shield; it
## is not a Packet and cannot be sliced, blasted, or transformed away.
static func permanent_shield(identity: Dictionary, side: Types.Side) -> int:
	var n := 0
	for inst in affecting(identity, PassiveEffects.PERM_SHIELD, side):
		n += _magnitude(inst)
	return n


## How many NAMED area-pattern steps `owner`'s Bombs advance. Each active
## instance is one step; saturation is applied by the registry.
static func bigger_bomb_steps(identity: Dictionary, owner: Types.Side) -> int:
	return affecting(identity, PassiveEffects.BIGGER_BOMB, owner).size()


static func _magnitude(inst: Instance) -> int:
	var m = inst.passive["magnitude"]
	return 0 if m == null else int(m)

class_name PassiveEffects
extends RefCounted

## PASSIVE-effect registry — the unified passive layer.
##
## Hackers, Systems, HOSTs, and UPGRADEs all reference rows from ONE external
## `PSV` dataset; the dataset chooses a coded `passive_effect`; this registry is
## the single stable-ID to validation-contract lookup. Trigger and modifier
## behaviour lives in the combat layer, switched exhaustively on the effect ID.
##
## Deliberately NOT a generalized trigger/rule/expression language. Every
## contract is a fixed typed tuple plus a fixed activation, so adding a passive
## kind means adding a registered contract and a coded branch — never authoring
## a script in a spreadsheet cell.

const EXTRA_MATCH_DAMAGE := "PSV_EXTRA_MATCH_DAMAGE"
const EXTRA_MATCH_CHARGE := "PSV_EXTRA_MATCH_CHARGE"
const CHARGE_DAMPEN := "PSV_CHARGE_DAMPEN"
const FUNCTION_DAMAGE_INCREASE := "PSV_FUNCTION_DAMAGE_INCREASE"
const PERM_SHIELD := "PSV_PERM_SHIELD"
const BIGGER_BOMB := "PSV_BIGGER_BOMB"
const CARRIER := "PSV_CARRIER"

## Typed token kinds a parameter tuple can require.
##   COLOR        — a canonical colour token (RED/YEL/MAG/GRE/CYA/BLU)
##   SCOPE        — the ALL wildcard. Its own kind rather than a colour that
##                  happens to spell ALL, so "which axis" and "how broad" can
##                  never be confused by validation or by a reader.
##   POSITIVE_INT — a magnitude >= 1
enum ParamKind { COLOR = 0, SCOPE, POSITIVE_INT }

## The complete authored activation vocabulary.
enum Activation { CONTINUAL = 0, START_OF_TURN }

## The authored agent scope. Meaningful for HAK/SYS/UPG sources; IGNORED for
## HST sources, because a HOST is not an agent — it applies to both sides
## symmetrically.
enum AgentScope { OWNER = 0, ENEMY }

const ALL_SCOPE_TOKEN := "ALL"

const ACTIVATION_NAMES := ["CONTINUAL", "START_OF_TURN"]
const AGENT_SCOPE_NAMES := ["OWNER", "ENEMY"]

## `payload` states whether `function_payload` is required or forbidden. There
## is no "optional" — an unclear payload column is an authoring error either way.
enum Payload { REQUIRED = 0, FORBIDDEN }


static var _registry: Dictionary = {}


static func registry() -> Dictionary:
	if _registry.is_empty():
		_build()
	return _registry


static func contract(id: String) -> Dictionary:
	return registry().get(id, {})


static func is_effect_id(s: String) -> bool:
	return registry().has(s)


static func ids() -> Array:
	return registry().keys()


static func is_activation(s: String) -> bool:
	return ACTIVATION_NAMES.has(s)


static func is_agent_scope(s: String) -> bool:
	return AGENT_SCOPE_NAMES.has(s)


static func _build() -> void:
	_registry = {
		# Extra raw Sync damage once per qualifying colour-axis Sync, applied
		# before crit, flooring, Buff, and Shield.
		EXTRA_MATCH_DAMAGE: {
			"id": EXTRA_MATCH_DAMAGE,
			"params": [ParamKind.COLOR, ParamKind.POSITIVE_INT],
			"activation": Activation.CONTINUAL,
			"payload": Payload.FORBIDDEN,
		},
		# Inflates the qualifying Sync's charge STREAM before routing, rather
		# than opening a second pool.
		EXTRA_MATCH_CHARGE: {
			"id": EXTRA_MATCH_CHARGE,
			"params": [ParamKind.COLOR, ParamKind.POSITIVE_INT],
			"activation": Activation.CONTINUAL,
			"payload": Payload.FORBIDDEN,
		},
		# Reduces qualifying charge streams. `ALL` covers every stream.
		CHARGE_DAMPEN: {
			"id": CHARGE_DAMPEN,
			"params": [ParamKind.SCOPE, ParamKind.POSITIVE_INT],
			"activation": Activation.CONTINUAL,
			"payload": Payload.FORBIDDEN,
		},
		# Adds to raw Function-originated damage before defensive handling.
		FUNCTION_DAMAGE_INCREASE: {
			"id": FUNCTION_DAMAGE_INCREASE,
			"params": [ParamKind.SCOPE, ParamKind.POSITIVE_INT],
			"activation": Activation.CONTINUAL,
			"payload": Payload.FORBIDDEN,
		},
		# Non-removable Shield value, stacked with Packet Shield. Not a Packet:
		# it cannot be sliced, blasted, or transformed away.
		PERM_SHIELD: {
			"id": PERM_SHIELD,
			"params": [ParamKind.SCOPE, ParamKind.POSITIVE_INT],
			"activation": Activation.CONTINUAL,
			"payload": Payload.FORBIDDEN,
		},
		# Advances every qualifying Bomb one NAMED area-pattern step. Takes no
		# parameters: the step count is the number of active instances.
		BIGGER_BOMB: {
			"id": BIGGER_BOMB,
			"params": [],
			"activation": Activation.CONTINUAL,
			"payload": Payload.FORBIDDEN,
		},
		# Invokes its authored `function_payload` at the start of the relevant
		# turn, paying NO Function cost — no pool is required and none is debited.
		CARRIER: {
			"id": CARRIER,
			"params": [],
			"activation": Activation.START_OF_TURN,
			"payload": Payload.REQUIRED,
		},
	}

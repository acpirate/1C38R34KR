class_name Effects
extends RefCounted

## Effect registry — the single authoritative lookup from a stable `EFFECT_*`
## ID to that Effect's VALIDATION CONTRACT: which discrete parameter columns it
## requires, which it merely accepts, the shape of its compound `params` tuple,
## and how it targets.
##
## Effects remain coded actions, not spreadsheet scripting. Execution lives in
## the game logic, switched exhaustively on the Effect ID; this registry is what
## validation and tooling consult. Anything not listed as required or optional
## is *unused* by that Effect and warns when populated — silence there would let
## a stray value sit in a column for months while doing nothing.

const BOMB := "EFFECT_BOMB"
const BUFF := "EFFECT_BUFF"
const ATTACK := "EFFECT_ATTACK"
const DRAIN := "EFFECT_DRAIN"
const SHIELD := "EFFECT_SHIELD"
const SHAKE := "EFFECT_SHAKE"
const LINESLICE := "EFFECT_LINESLICE"
const TRANSFORM := "EFFECT_TRANSFORM"

## The discrete Function-CSV parameter columns a contract can claim.
const PARAM_NAMES: Array[String] = ["quantity", "countdown", "areaPattern", "magnitude", "damage"]

## The axis columns EFFECT_TRANSFORM adds. Their own contract dimension rather
## than more parameter names: every other Effect leaves them blank, and treating
## them as ordinary parameters would fire "populated but unused" warnings on
## every row that correctly ignores them.
const AXIS_NAMES: Array[String] = ["axisTarget", "axisResult"]


# ---------------------------------------------------------------------------
# Compound tuples
# ---------------------------------------------------------------------------
#
# Each field is a small integer enum with an inclusive accepted range. Tuples
# are validated and resolved into typed values at STARTUP; runtime execution
# never re-parses the raw string.

## targeting : dealDamage : gainCharge
## Every live Bomb row supplies all three; trailing defaults are never inferred.
const BOMB_TUPLE: Array[Dictionary] = [
	{"name": "targeting", "min": 0, "max": 1},
	{"name": "dealDamage", "min": 0, "max": 1},
	{"name": "gainCharge", "min": 0, "max": 1},
]

## dimension : targeting : specialRetention : dealDamage : gainCharge
const LINESLICE_TUPLE: Array[Dictionary] = [
	{"name": "dimension", "min": 0, "max": 1},
	{"name": "targeting", "min": 0, "max": 1},
	{"name": "specialRetention", "min": 0, "max": 2},
	{"name": "dealDamage", "min": 0, "max": 1},
	{"name": "gainCharge", "min": 0, "max": 1},
]

## boardComposition : specialGems : matches : cascades
##
## `specialGems` value 2 means "remove only the overlays the activating side
## does NOT own". It mirrors the LineSlice tuple's retain-own value rather than
## inventing a third enum vocabulary, so the two Effects cannot drift apart on
## special handling.
const SHAKE_TUPLE: Array[Dictionary] = [
	{"name": "boardComposition", "min": 0, "max": 1},
	{"name": "specialGems", "min": 0, "max": 2},
	{"name": "matches", "min": 0, "max": 1},
	{"name": "cascades", "min": 0, "max": 2},
]

## targeting : specialPacketTreatment
## `specialPacketTreatment` reuses the same SPECIALS_* enum LineSlice uses
## (0 destroy / 1 retain all / 2 retain own), for the same anti-drift reason.
const TRANSFORM_TUPLE: Array[Dictionary] = [
	{"name": "targeting", "min": 0, "max": 1},
	{"name": "specialPacketTreatment", "min": 0, "max": 2},
]


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------
#
# `targeted` means ALWAYS targeted. Effects whose targeting is selected by their
# own `params` tuple resolve per-row at load time, and that resolved value is
# what validation and runtime consume.

static var _registry: Dictionary = {}


static func registry() -> Dictionary:
	if _registry.is_empty():
		_build()
	return _registry


static func contract(id: String) -> Dictionary:
	var r := registry()
	return r.get(id, {})


static func is_effect_id(s: String) -> bool:
	return registry().has(s)


static func ids() -> Array:
	return registry().keys()


static func _build() -> void:
	_registry = {
		# `countdown` is optional: a positive integer deploys the countdown
		# overlay, blank or zero resolves the blast immediately.
		BOMB: {
			"id": BOMB,
			"required": ["quantity", "areaPattern"],
			"optional": ["countdown"],
			"targeted": false,
			"target_kind": Types.TargetKind.PACKET,
			"tuple": BOMB_TUPLE,
			"axes": [],
		},
		# `countdown` is optional on exactly the terms it is for Bombs: blank or
		# zero places a live Buff immediately, a positive integer arms an
		# overlay that DELIVERS the Buff on the same Packet at expiry. One
		# mechanism with a named payload — no second Effect, no second scheduler.
		BUFF: {
			"id": BUFF,
			"required": ["quantity", "magnitude"],
			"optional": ["countdown"],
			"targeted": false,
			"target_kind": Types.TargetKind.NONE,
			"tuple": [],
			"axes": [],
		},
		ATTACK: {
			"id": ATTACK,
			"required": ["damage"],
			"optional": [],
			"targeted": false,
			"target_kind": Types.TargetKind.NONE,
			"tuple": [],
			"axes": [],
		},
		DRAIN: {
			"id": DRAIN,
			"required": [],
			"optional": [],
			"targeted": true,
			"target_kind": Types.TargetKind.UNIT,
			"tuple": [],
			"axes": [],
		},
		SHIELD: {
			"id": SHIELD,
			"required": ["quantity", "magnitude"],
			"optional": [],
			"targeted": false,
			"target_kind": Types.TargetKind.NONE,
			"tuple": [],
			"axes": [],
		},
		# No areaPattern: the line is derived from the resolved target.
		LINESLICE: {
			"id": LINESLICE,
			"required": ["quantity"],
			"optional": [],
			"targeted": false,
			"target_kind": Types.TargetKind.PACKET,
			"tuple": LINESLICE_TUPLE,
			"axes": [],
		},
		SHAKE: {
			"id": SHAKE,
			"required": [],
			"optional": [],
			"targeted": false,
			"target_kind": Types.TargetKind.NONE,
			"tuple": SHAKE_TUPLE,
			"axes": [],
		},
		# `quantity` plus both axis columns are required. damage, magnitude,
		# countdown, and areaPattern are not part of this contract and warn when
		# populated, under the established unused-parameter policy.
		TRANSFORM: {
			"id": TRANSFORM,
			"required": ["quantity"],
			"optional": [],
			"targeted": false,
			"target_kind": Types.TargetKind.PACKET,
			"tuple": TRANSFORM_TUPLE,
			"axes": AXIS_NAMES,
		},
	}

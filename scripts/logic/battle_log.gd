class_name BattleLog
extends RefCounted

## Battle logging, fed by the SAME event stream the metrics collector consumes.
##
## `Game._collect` routes every batch through both; there is no second pipeline
## and no path by which logging can observe something metrics did not. Pure data
## in, pure data out — persistence is `LogStore`'s job, so a log level can never
## change how long a turn takes to resolve.
##
## Two streams:
##
## - **turns** — one compact record per game turn, at VERBOSE and above.
## - **events** — rare, high-value records (charge routes, targeted Functions,
##   Drains, Transforms, countdown deliveries, PASSIVE contributions), written
##   at EVERY level. These had to be promoted out of the turn record precisely
##   so they survive at BASIC, where there is no turn stream at all.
##
## Battle-static context — identity, config, build, content fingerprint — lives
## ONCE on the battle-level record and joins by `battle_id`. Repeating it into
## every turn is most of what made the alpha's logs expensive.


enum Level { BASIC = 0, VERBOSE, COMPLETE }

const LEVEL_NAMES: Array[String] = ["BASIC", "VERBOSE", "COMPLETE"]

## Versioned independently of the save schema: a logging change must not
## invalidate saves, and a save change must not silently reinterpret old logs.
const LOGGING_SCHEMA_VERSION := 1
const METRICS_SCHEMA_VERSION := 1

## In-memory caps. Retention on disk is governed first by `LogStore`'s byte
## budget and second by these; both exist because either alone fails — a byte
## budget alone lets one pathological battle evict everything else, and entry
## caps alone say nothing about size.
const MAX_TURNS_IN_MEMORY := 400
const MAX_EVENTS_IN_MEMORY := 800

## The level new records are created under.
##
## Static because it is a process-wide setting, not per battle. Changing it
## affects FUTURE records only: a record keeps the level tag it was written
## with, so a mid-battle change cannot retroactively promote or relabel a record
## that was assembled under different rules.
static var _level: Level = Level.BASIC


## Debug builds default to VERBOSE and release to BASIC. COMPLETE is never a
## default — it is an explicit diagnostic opt-in, because it retains the
## readable mirror and every ordinary charge route.
static func default_level(debug_build: bool) -> Level:
	return Level.VERBOSE if debug_build else Level.BASIC


static func set_level(level: Level) -> void:
	_level = level


static func level() -> Level:
	return _level


static func at_least(level: Level) -> bool:
	return _level >= level


static func level_name(level: Level) -> String:
	return LEVEL_NAMES[level]


static func parse_level(name: String) -> Level:
	var i := LEVEL_NAMES.find(name.to_upper())
	return (i as Level) if i >= 0 else Level.BASIC


var battle_id := ""

## Finalized turn records and the high-value event stream, both trimmed to the
## caps above as they grow.
var turns: Array[Dictionary] = []
var events: Array[Dictionary] = []

var _current: Dictionary = {}


func _init(id := "") -> void:
	battle_id = id


# ---------------------------------------------------------------------------
# Collection
# ---------------------------------------------------------------------------

## Folds one batch into the open turn record, finalizing it when the turn
## advances or the battle ends.
func consume(state: GameState, batch: Array) -> void:
	if _current.is_empty():
		_current = _fresh(state)

	for ev in batch:
		_consume_one(state, ev)

	if int(_current["turn"]) != state.turn or state.has_winner():
		_finalize(state)


func _fresh(state: GameState) -> Dictionary:
	var e := {
		"v": Content.GAME_VERSION,
		"ls": LOGGING_SCHEMA_VERSION,
		"lvl": level_name(_level),
		"battle_id": battle_id,
		"turn": state.turn,
		# Damage DEALT BY each side this turn, split by cause. Per-turn rather
		# than cumulative, so a turn record answers "what happened here?"
		# without differencing against the previous one.
		"damage": [_fresh_damage(), _fresh_damage()],
		"hp_after": [0, 0],
		"charges_after": {"player": [], "enemy": [], "deck": 0},
	}
	# The readable mirror duplicates structured data, so it is COMPLETE-only.
	# Readable text is otherwise derived at export time from the records.
	if at_least(Level.COMPLETE):
		e["actions"] = PackedStringArray()
	return e


func _fresh_damage() -> Dictionary:
	return {"match": 0, "attacker": 0, "bomb": 0, "lineslice": 0, "transform": 0, "total": 0}


func _consume_one(state: GameState, ev: Dictionary) -> void:
	match StringName(ev["t"]):
		Types.EVT.SWAP:
			_act("swap (%d,%d)->(%d,%d)" % [ev["a"].x, ev["a"].y, ev["b"].x, ev["b"].y])

		Types.EVT.ABILITY:
			# One line per PARENT activation, by display name. The Deck-owned
			# Function is identified as Deck-owned rather than as a Program.
			var tail := ""
			if int(ev["owner_kind"]) == Types.OwnerKind.DECK:
				tail = " (deck %s)" % ev["program_id"]
			_act("%s fired %s [%s]%s" % [_who(ev["side"]), ev["name"], ev["fn"], tail])

		Types.EVT.OP:
			if ev.has("drained"):
				_act("%s %s drained %d" % [_who(ev["side"]), ev["effect_id"], int(ev["drained"])])
			elif not bool(ev.get("resolved", true)):
				_act("%s %s fizzled (%s)" % [_who(ev["side"]), ev["effect_id"], ev["fn_id"]])
			# Full Drain telemetry rides the ACTUAL activation. A withheld
			# System activation is not an activation and is deliberately absent.
			if ev.has("target_program_id"):
				_push(state.turn, "DRAIN", "drain", {
					"side": ev["side"], "program_id": ev["program_id"], "fn_id": ev["fn_id"],
					"target_program_id": ev["target_program_id"],
					"readiness": ev.get("target_readiness", null),
					"charge_before": ev.get("target_charge_before", null),
					"charge_after": ev.get("target_charge_after", null),
					"target_cost": ev.get("target_cost", null),
					"removed": ev.get("drained", 0),
				})

		Types.EVT.CHARGE_ROUTE:
			_consume_route(state, ev)

		Types.EVT.TARGETED:
			var sliced: Array = ev.get("sliced", [])
			var rec := {
				"side": ev["side"], "program_id": ev["program_id"], "fn_id": ev["fn_id"],
				"effect_id": ev["effect_id"], "target": ev.get("target", null),
				"target_tile": ev.get("target_tile", null),
				"sliced_count": sliced.size(),
				"retained_count": (ev.get("retained", []) as Array).size(),
				"direct_damage": ev.get("direct_damage", 0),
				"direct_charge": ev.get("direct_charge", 0),
				"resolved": ev.get("resolved", true),
			}
			if ev.has("dimension"):
				rec["dimension"] = ev["dimension"]
			if ev.has("reason"):
				rec["reason"] = ev["reason"]
			# The full coordinate list is reconstruction detail; the count is
			# what analysis below COMPLETE actually needs.
			if at_least(Level.COMPLETE):
				rec["sliced"] = sliced
			_push(state.turn, "TARGETED", "targeted", rec)

		Types.EVT.TRANSFORM:
			var rec := {
				"side": ev["side"], "program_id": ev.get("program_id", null),
				"fn_id": ev.get("fn_id", null),
				"axis_target": ev.get("axis_target", null),
				"axis_result": ev.get("axis_result", null),
				"result_color": ev.get("result_color", null),
				"result_shape": ev.get("result_shape", null),
				"requested": ev.get("requested", 0), "converted": ev.get("converted", 0),
				"candidates": ev.get("candidates", 0), "tier2_used": ev.get("tier2_used", 0),
				"specials_retained": ev.get("specials_retained", 0),
				"specials_destroyed": ev.get("specials_destroyed", 0),
			}
			# The causal source, kept alongside the resolution owner. Both facts
			# matter: a PASSIVE can cause a Transform whose Sync consequences the
			# Hacker owns, and a record naming only one of them is misleading.
			if ev.has("cause"):
				rec["cause"] = ev["cause"]
			if at_least(Level.COMPLETE) and ev.has("cells"):
				rec["cells"] = ev["cells"]
			_push(state.turn, "TRANSFORM", "transform", rec)

		Types.EVT.COUNTDOWN_DELIVERED:
			# A payload actually landing, so "armed" and "delivered" are
			# distinguishable. Removal before delivery needs no record: the
			# overlay is gone and no delivery event ever appears.
			_push(state.turn, "COUNTDOWN", "countdown", {
				"side": ev.get("side", null), "effect_id": ev.get("effect_id", null),
				"program_id": ev.get("program_id", null), "fn_id": ev.get("fn_id", null),
				"magnitude": ev.get("magnitude", null), "p": ev.get("p", null),
			})

		Types.EVT.PASSIVE:
			# One record per CONTRIBUTING INSTANCE, never a merged total:
			# several PASSIVEs modifying one calculation must stay individually
			# attributable, and the base event keeps its own attribution.
			var rec := {"side": ev["side"], "cause": ev["cause"], "effect": ev.get("effect", null)}
			for key in ["damage", "charge", "shield", "steps"]:
				if ev.has(key):
					rec[key] = ev[key]
			_push(state.turn, "PASSIVE", "passive", rec)

		Types.EVT.SHAKE:
			_act("%s EFFECT_SHAKE %s" % [
				_who(ev["side"]),
				"resolved" if bool(ev.get("resolved", false)) else "fizzled (legal)",
			])

		Types.EVT.PLACED:
			var count := int(ev.get("count", 0))
			if count > 0:
				_act("%s placed %d %s%s" % [
					_who(ev["side"]), count, ev["kind"], "" if count == 1 else "s",
				])

		Types.EVT.SHIELD:
			_act("shield absorbed %d of %d" % [int(ev["prevented"]), int(ev["pre_shield"])])

		# Detonations, line clears and reshuffles are AGGREGATE counters on the
		# battle metrics record, not per-turn counters. Metrics consumes them;
		# nothing per-turn is written here.
		Types.EVT.DAMAGE:
			var dealer := Types.opponent_of(int(ev["target"]))
			var bucket: Dictionary = _current["damage"][dealer]
			var name := _damage_bucket(int(ev["source"]))
			bucket[name] += int(ev["amount"])
			bucket["total"] += int(ev["amount"])

		Types.EVT.THINK_TIME:
			_current["think_ms"] = int(ev["ms"])

		Types.EVT.HINT_SHOWN:
			_current["hint_shown"] = true


func _damage_bucket(source: int) -> String:
	match source:
		Types.DamageSource.MATCH:
			return "match"
		Types.DamageSource.ATTACKER:
			return "attacker"
		Types.DamageSource.LINESLICE:
			return "lineslice"
		Types.DamageSource.TRANSFORM:
			return "transform"
		_:
			return "bomb"


## Below COMPLETE, a route earns persistence only when it shows something the
## routing rules could not be predicted to do: charge reaching more than one
## Program, charge being thrown away, or a non-Sync source generating it.
## Ordinary "the single compatible Program took the lot" routes are the bulk of
## the volume and prove nothing.
func _consume_route(state: GameState, ev: Dictionary) -> void:
	var complete := at_least(Level.COMPLETE)
	var assignments: Array = ev.get("assignments", [])
	var discarded := int(ev.get("discarded", 0))

	var fed := 0
	for a in assignments:
		if int(a.get("assigned", 0)) > 0:
			fed += 1

	var stream_source := int(ev.get("stream_source", Types.ChargeStreamSource.SYNC))
	var interesting := discarded > 0 or fed > 1 \
		or stream_source == Types.ChargeStreamSource.PASSIVE_MODIFIED_SYNC \
		or stream_source == Types.ChargeStreamSource.EFFECT_DESTRUCTION

	if not (complete or interesting):
		return

	var rec := {
		"side": ev["side"], "axis": ev["axis"], "token": ev["token"],
		"amount": ev["amount"], "source": stream_source,
		"assignments": assignments, "discarded": discarded,
	}
	# `order` and `eligible` are dropped below COMPLETE: the active order is
	# battle-static and already on the metrics record, and eligibility derives
	# from that order plus the Program bindings, axis, and token.
	if complete:
		rec["order"] = ev.get("order", [])
		rec["eligible"] = ev.get("eligible", [])
	_push(state.turn, "ROUTE", "route", rec)


func _push(turn: int, kind: String, key: String, body: Dictionary) -> void:
	var entry := {
		"v": Content.GAME_VERSION,
		"ls": LOGGING_SCHEMA_VERSION,
		"lvl": level_name(_level),
		"battle_id": battle_id,
		"turn": turn,
		"kind": kind,
	}
	entry[key] = body
	events.append(entry)
	while events.size() > MAX_EVENTS_IN_MEMORY:
		events.pop_front()


func _act(line: String) -> void:
	if _current.has("actions"):
		(_current["actions"] as PackedStringArray).append(line)


func _who(side) -> String:
	return "Hacker" if int(side) == Types.Side.PLAYER else "System"


## Closes the open turn record.
##
## The retention test is against the level the record was BUILT under, not the
## level active now. A mid-battle change must take effect from the next turn
## rather than retroactively promoting a record assembled under different rules.
func _finalize(state: GameState) -> void:
	_current["hp_after"] = [
		maxi(0, state.hp[Types.Side.PLAYER]), maxi(0, state.hp[Types.Side.ENEMY]),
	]
	var player_charges: Array = []
	for u in (state.units[Types.Side.PLAYER] as Array):
		player_charges.append(u.charge)
	var enemy_charges: Array = []
	for u in (state.units[Types.Side.ENEMY] as Array):
		enemy_charges.append(u.charge)
	_current["charges_after"] = {
		"player": player_charges, "enemy": enemy_charges, "deck": state.deck_charge,
	}
	if state.has_winner():
		_current["result"] = state.winner

	# BASIC keeps no ordinary per-turn stream at all.
	if parse_level(str(_current["lvl"])) >= Level.VERBOSE:
		turns.append(_current)
		while turns.size() > MAX_TURNS_IN_MEMORY:
			turns.pop_front()

	_current = {} if state.has_winner() else _fresh(state)


# ---------------------------------------------------------------------------
# Continuation
# ---------------------------------------------------------------------------

## The OPEN turn record only.
##
## Finalized records have already been handed to the sink; carrying them through
## the save envelope would duplicate them on every resume. What must survive is
## the partial turn — without it, a battle saved mid-turn resumes with that
## turn's damage split silently reset to zero.
func to_dict() -> Dictionary:
	var open := _current.duplicate(true)
	if open.has("actions"):
		open["actions"] = Array(open["actions"] as PackedStringArray)
	return {"battle_id": battle_id, "open": open}


static func from_dict(d: Dictionary) -> BattleLog:
	var l := BattleLog.new(str(d.get("battle_id", "")))
	var open: Dictionary = d.get("open", {})
	if not open.is_empty():
		if open.has("actions"):
			open["actions"] = PackedStringArray(open["actions"] as Array)
		l._current = open
	return l

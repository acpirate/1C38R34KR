class_name Metrics
extends RefCounted

## Per-battle metrics, accumulated in the pure logic layer.
##
## A collector over the SAME event stream the resolver already emits. It has no
## gameplay effect and no rendering dependency, and it reads no game state — if
## it did, it would become a second authority for what happened, and the two
## could disagree.
##
## That is also why this is a port rather than a rewrite. The differential gate
## proves the beta's event stream matches the alpha's byte for byte, so a
## collector that consumes only events inherits that proof: the numbers are
## right because the stream is right.
##
## **The buckets are disjoint and must stay that way.** For each side,
##
##     match + attacker + bomb + lineslice + transform + passive + buff
##       == total
##
## exactly. `cascade` is deliberately CROSS-CUTTING — it overlaps the buckets
## and does not sum with them, because a cascade has a cause and is already
## counted under it. `_test_metrics.gd` asserts the identity over real battles
## rather than trusting the arithmetic here.
##
## Per-Program figures are keyed by STABLE PROGRAM ID; display names join at
## presentation time. A PASSIVE is keyed by source kind + source ID + PASSIVE
## ID, never by PASSIVE ID alone: the same row supplied by two sources is two
## instances and both apply, so collapsing them here would make the stacking
## rule unauditable.


## Per-Program counters.
##
## `fires` counts PAID parent activations; `ops` counts the payload operations
## those expand into. A composite Function fires once and produces several ops,
## and a child Function is never counted as a separately paid activation.
class Unit extends RefCounted:
	var fires := 0
	var ops := 0
	var fizzles := 0  ## ops that legally fizzled — no valid target or placement
	var effect := 0.0  ## this Program's aggregate contribution, in damage or charge
	var bombs_placed := 0

	func to_dict() -> Dictionary:
		return {
			"fires": fires, "ops": ops, "fizzles": fizzles,
			"effect": effect, "bombs_placed": bombs_placed,
		}

	static func from_dict(d: Dictionary) -> Unit:
		var u := Unit.new()
		u.fires = int(d.get("fires", 0))
		u.ops = int(d.get("ops", 0))
		u.fizzles = int(d.get("fizzles", 0))
		u.effect = float(d.get("effect", 0.0))
		u.bombs_placed = int(d.get("bombs_placed", 0))
		return u


## The active Deck's own counters. Deck-owned and never merged into the
## per-Program map: the Deck Function is not a Program.
class Deck extends RefCounted:
	var fires := 0
	var ops := 0
	var fizzles := 0
	var charge_from_neutral := 0
	var charge_wasted := 0
	var shake_attempts := 0
	var shake_successes := 0
	var shake_fizzles := 0

	func to_dict() -> Dictionary:
		return {
			"fires": fires, "ops": ops, "fizzles": fizzles,
			"charge_from_neutral": charge_from_neutral, "charge_wasted": charge_wasted,
			"shake_attempts": shake_attempts, "shake_successes": shake_successes,
			"shake_fizzles": shake_fizzles,
		}

	static func from_dict(d: Dictionary) -> Deck:
		var k := Deck.new()
		k.fires = int(d.get("fires", 0))
		k.ops = int(d.get("ops", 0))
		k.fizzles = int(d.get("fizzles", 0))
		k.charge_from_neutral = int(d.get("charge_from_neutral", 0))
		k.charge_wasted = int(d.get("charge_wasted", 0))
		k.shake_attempts = int(d.get("shake_attempts", 0))
		k.shake_successes = int(d.get("shake_successes", 0))
		k.shake_fizzles = int(d.get("shake_fizzles", 0))
		return k


## Per-PASSIVE-INSTANCE counters. `shield` and `steps` are prevention and area
## contributions rather than damage, so they get their own counters instead of
## being folded into one.
class Passive extends RefCounted:
	var source_kind := 0
	var source_id := ""
	var passive_id := ""
	var triggers := 0
	var damage := 0.0  ## raw contribution, pre-floor
	var charge := 0  ## granted (positive) or dampened away (negative)
	var shield := 0
	var steps := 0

	func to_dict() -> Dictionary:
		return {
			"source_kind": source_kind, "source_id": source_id, "passive_id": passive_id,
			"triggers": triggers, "damage": damage, "charge": charge,
			"shield": shield, "steps": steps,
		}

	static func from_dict(d: Dictionary) -> Passive:
		var p := Passive.new()
		p.source_kind = int(d.get("source_kind", 0))
		p.source_id = str(d.get("source_id", ""))
		p.passive_id = str(d.get("passive_id", ""))
		p.triggers = int(d.get("triggers", 0))
		p.damage = float(d.get("damage", 0.0))
		p.charge = int(d.get("charge", 0))
		p.shield = int(d.get("shield", 0))
		p.steps = int(d.get("steps", 0))
		return p


class SideMetrics extends RefCounted:
	var total_damage := 0

	# The seven disjoint causal buckets.
	var match_damage := 0.0  ## BASE Sync damage only — zero under Reinforced Connection
	var attacker_damage := 0.0
	var bomb_damage := 0.0
	var lineslice_damage := 0.0  ## direct row/column slices AND their cascades
	var transform_damage := 0.0  ## Syncs an EFFECT_TRANSFORM created
	var passive_damage := 0.0
	var buff_damage_added := 0.0

	## Cross-cutting: overlaps the buckets above and does NOT sum with them.
	var cascade_damage := 0.0

	var match_damage_color := 0.0
	var match_damage_shape := 0.0
	var crit_extra := 0.0
	var largest_hit := 0
	var deepest_cascade := 0
	var tiles_destroyed := 0
	var contention_tiles := 0

	## THE canonical charge-waste figure: every unit of PROGRAM-pool charge
	## generated for this side that could not be stored, whatever the source.
	## Not attributed per Program — the routing rules make "which Program wasted
	## it" a meaningless question. The Deck keeps its own bucket.
	var charge_wasted_total := 0

	var line_clears := 0
	var units := {}  ## stable Program ID -> Unit
	var deck := Deck.new()
	var passives := {}  ## "<kind>:<source>:<passive>" -> Passive

	func to_dict() -> Dictionary:
		var u := {}
		for id in units:
			u[id] = units[id].to_dict()
		var p := {}
		for k in passives:
			p[k] = passives[k].to_dict()
		return {
			"total_damage": total_damage,
			"match_damage": match_damage, "attacker_damage": attacker_damage,
			"bomb_damage": bomb_damage, "lineslice_damage": lineslice_damage,
			"transform_damage": transform_damage, "passive_damage": passive_damage,
			"buff_damage_added": buff_damage_added, "cascade_damage": cascade_damage,
			"match_damage_color": match_damage_color, "match_damage_shape": match_damage_shape,
			"crit_extra": crit_extra, "largest_hit": largest_hit,
			"deepest_cascade": deepest_cascade, "tiles_destroyed": tiles_destroyed,
			"contention_tiles": contention_tiles, "charge_wasted_total": charge_wasted_total,
			"line_clears": line_clears,
			"units": u, "deck": deck.to_dict(), "passives": p,
		}

	static func from_dict(d: Dictionary) -> SideMetrics:
		var s := SideMetrics.new()
		s.total_damage = int(d.get("total_damage", 0))
		s.match_damage = float(d.get("match_damage", 0.0))
		s.attacker_damage = float(d.get("attacker_damage", 0.0))
		s.bomb_damage = float(d.get("bomb_damage", 0.0))
		s.lineslice_damage = float(d.get("lineslice_damage", 0.0))
		s.transform_damage = float(d.get("transform_damage", 0.0))
		s.passive_damage = float(d.get("passive_damage", 0.0))
		s.buff_damage_added = float(d.get("buff_damage_added", 0.0))
		s.cascade_damage = float(d.get("cascade_damage", 0.0))
		s.match_damage_color = float(d.get("match_damage_color", 0.0))
		s.match_damage_shape = float(d.get("match_damage_shape", 0.0))
		s.crit_extra = float(d.get("crit_extra", 0.0))
		s.largest_hit = int(d.get("largest_hit", 0))
		s.deepest_cascade = int(d.get("deepest_cascade", 0))
		s.tiles_destroyed = int(d.get("tiles_destroyed", 0))
		s.contention_tiles = int(d.get("contention_tiles", 0))
		s.charge_wasted_total = int(d.get("charge_wasted_total", 0))
		s.line_clears = int(d.get("line_clears", 0))
		for id in (d.get("units", {}) as Dictionary):
			s.units[id] = Unit.from_dict(d["units"][id])
		s.deck = Deck.from_dict(d.get("deck", {}))
		for k in (d.get("passives", {}) as Dictionary):
			s.passives[k] = Passive.from_dict(d["passives"][k])
		return s


## Battle-level aggregates plus one `SideMetrics` per side.
##
## Every counter here is an AGGREGATE rather than a per-turn record. That is
## deliberate: it lets the lowest logging tier still answer "did this materially
## appear in this battle?" while retaining nothing per turn.
class Battle extends RefCounted:
	var turns := 0
	var auto_reshuffles := 0
	var detonations := 0
	var winner := -1
	var hints_shown := 0

	## Ready System Programs that did not activate because they had no valid
	## target. A battle-level count, not a per-turn decision log.
	var system_withholds := 0

	# Shield instrumentation. Alpha content places Shields on the System side
	# only. Prevention is NOT damage dealt and never enters a damage bucket.
	var enemy_shield_created := 0
	var enemy_shield_removed := 0
	var enemy_shield_instances := 0
	var enemy_shield_prevented := 0

	# ODANSHAY mechanic aggregates (beta 0.3 §18). Zero in every System battle,
	# which is why they live here rather than in a Boss-only accounting tree:
	# one battle record shape, and the Boss fields simply stay at zero.
	#
	# `overrides_peak` is the interesting one for balance work — total placed
	# says how busy the mechanic was, but the PEAK says how close the board came
	# to the threshold, which is what actually decides whether CODESHATTER fires.
	var overrides_placed := 0
	var overrides_peak := 0
	var hacker_specials_overwritten := 0
	var databend_activations := 0
	var codeshatter_activations := 0
	var reboot_activations := 0
	var threshold_triggers := 0

	var sides: Array[SideMetrics] = []

	func side(s: Types.Side) -> SideMetrics:
		return sides[s]

	func to_dict() -> Dictionary:
		return {
			"turns": turns, "auto_reshuffles": auto_reshuffles,
			"detonations": detonations, "winner": winner, "hints_shown": hints_shown,
			"system_withholds": system_withholds,
			"enemy_shield_created": enemy_shield_created,
			"enemy_shield_removed": enemy_shield_removed,
			"enemy_shield_instances": enemy_shield_instances,
			"enemy_shield_prevented": enemy_shield_prevented,
			"overrides_placed": overrides_placed,
			"overrides_peak": overrides_peak,
			"hacker_specials_overwritten": hacker_specials_overwritten,
			"databend_activations": databend_activations,
			"codeshatter_activations": codeshatter_activations,
			"reboot_activations": reboot_activations,
			"threshold_triggers": threshold_triggers,
			"sides": [sides[0].to_dict(), sides[1].to_dict()],
		}

	static func from_dict(d: Dictionary) -> Battle:
		var b := Battle.new()
		b.turns = int(d.get("turns", 0))
		b.auto_reshuffles = int(d.get("auto_reshuffles", 0))
		b.detonations = int(d.get("detonations", 0))
		b.winner = int(d.get("winner", -1))
		b.hints_shown = int(d.get("hints_shown", 0))
		b.system_withholds = int(d.get("system_withholds", 0))
		b.enemy_shield_created = int(d.get("enemy_shield_created", 0))
		b.enemy_shield_removed = int(d.get("enemy_shield_removed", 0))
		b.enemy_shield_instances = int(d.get("enemy_shield_instances", 0))
		b.enemy_shield_prevented = int(d.get("enemy_shield_prevented", 0))
		b.overrides_placed = int(d.get("overrides_placed", 0))
		b.overrides_peak = int(d.get("overrides_peak", 0))
		b.hacker_specials_overwritten = int(d.get("hacker_specials_overwritten", 0))
		b.databend_activations = int(d.get("databend_activations", 0))
		b.codeshatter_activations = int(d.get("codeshatter_activations", 0))
		b.reboot_activations = int(d.get("reboot_activations", 0))
		b.threshold_triggers = int(d.get("threshold_triggers", 0))
		var raw: Array = d.get("sides", [])
		for i in 2:
			b.sides.append(SideMetrics.from_dict(raw[i] if i < raw.size() else {}))
		return b


## Seeded from the battle's ACTIVE roster, not from every loaded Program: a
## Program sitting in inventory has no metrics slot.
static func create(player_programs: Array, enemy_programs: Array) -> Battle:
	var b := Battle.new()
	b.sides.append(_empty_side(player_programs))
	b.sides.append(_empty_side(enemy_programs))
	return b


static func _empty_side(program_ids: Array) -> SideMetrics:
	var s := SideMetrics.new()
	for id in program_ids:
		s.units[str(id)] = Unit.new()
	return s


static func passive_key(cause: Dictionary) -> String:
	return "%d:%s:%s" % [
		int(cause["source_kind"]), str(cause["source_id"]), str(cause["passive_id"]),
	]


# ---------------------------------------------------------------------------
# Collection
# ---------------------------------------------------------------------------

## Folds one batch of events into `m`.
##
## Called with every batch the logic layer returns, including during resume:
## the accumulator is part of the save envelope, so a battle continued from disk
## reports the same figures as one played straight through.
static func consume(m: Battle, events: Array) -> void:
	for ev in events:
		_consume_one(m, ev)


static func _consume_one(m: Battle, ev: Dictionary) -> void:
	match StringName(ev["t"]):
		Types.EVT.BOSS_MECHANIC:
			# One event kind carries the whole mechanic, so the aggregates come
			# off the same funnel as everything else rather than from a parallel
			# Boss accounting path (§18).
			match str(ev.get("kind", "")):
				"OVERRIDE_PLACED":
					m.overrides_placed += int(ev.get("placed", 0))
					m.hacker_specials_overwritten += int(ev.get("overwrote", 0))
					m.overrides_peak = maxi(m.overrides_peak, int(ev.get("count_after", 0)))
				"THRESHOLD":
					m.threshold_triggers += 1
					# The threshold reading is a peak by definition: it is the
					# highest the count reached before REBOOT cleared it.
					m.overrides_peak = maxi(m.overrides_peak, int(ev.get("count_before", 0)))
		Types.EVT.DAMAGE:
			_consume_damage(m, ev)

		Types.EVT.ABILITY:
			var sm := m.side(int(ev["side"]))
			var kind := int(ev["owner_kind"])
			# A Boss activation is a mechanic, not a Program. Routing it through
			# `_unit` would invent a phantom per-Program row keyed by the Boss ID
			# and corrupt the Program figures. It is counted as a mechanic
			# activation instead (§18).
			if kind == Types.OwnerKind.BOSS:
				match str(ev.get("fn", "")):
					Content.FN_DATABEND:
						m.databend_activations += 1
					Content.FN_CODESHATTER:
						m.codeshatter_activations += 1
					Content.FN_REBOOT:
						m.reboot_activations += 1
			elif kind == Types.OwnerKind.DECK:
				sm.deck.fires += 1
			else:
				_unit(sm, str(ev["program_id"])).fires += 1

		Types.EVT.OP:
			var sm := m.side(int(ev["side"]))
			var kind := int(ev["owner_kind"])
			if kind == Types.OwnerKind.BOSS:
				return
			if kind == Types.OwnerKind.DECK:
				sm.deck.ops += 1
				if not bool(ev.get("resolved", true)):
					sm.deck.fizzles += 1
			else:
				var u := _unit(sm, str(ev["program_id"]))
				u.ops += 1
				if not bool(ev.get("resolved", true)):
					u.fizzles += 1
				if ev.has("drained"):
					u.effect += float(ev["drained"])

		Types.EVT.PASSIVE:
			var k := _passive(m.side(int(ev["side"])), ev["cause"])
			k.triggers += 1
			k.damage += _num(ev, "damage")
			k.charge += int(ev.get("charge", 0))
			k.shield += int(ev.get("shield", 0))
			k.steps += int(ev.get("steps", 0))

		Types.EVT.DECK_CHARGE:
			var d := m.side(int(ev["side"])).deck
			d.charge_from_neutral += int(ev["amount"])
			d.charge_wasted += int(ev["wasted"])

		Types.EVT.SHAKE:
			var d := m.side(int(ev["side"])).deck
			d.shake_attempts += 1
			if bool(ev.get("resolved", false)):
				d.shake_successes += 1
			else:
				d.shake_fizzles += 1

		Types.EVT.LINE_CLEAR:
			m.side(int(ev["side"])).line_clears += 1

		Types.EVT.CHARGE_WASTE:
			var sm := m.side(int(ev["side"]))
			if int(ev.get("owner_kind", Types.OwnerKind.PROGRAM)) == Types.OwnerKind.DECK:
				sm.deck.charge_wasted += int(ev["amount"])
			else:
				sm.charge_wasted_total += int(ev["amount"])

		# The other half of the same total, read straight off each routed stream
		# so the figure stays verifiable against the routing events themselves.
		Types.EVT.CHARGE_ROUTE:
			m.side(int(ev["side"])).charge_wasted_total += int(ev.get("discarded", 0))

		Types.EVT.DETONATE:
			m.detonations += 1

		Types.EVT.WITHHOLD:
			m.system_withholds += 1

		Types.EVT.PLACED:
			if str(ev.get("kind", "")) == "bomb":
				if int(ev.get("owner_kind", Types.OwnerKind.PROGRAM)) != Types.OwnerKind.DECK:
					_unit(m.side(int(ev["side"])), str(ev["program_id"])).bombs_placed += int(ev["count"])
			elif int(ev["side"]) == Types.Side.ENEMY:
				m.enemy_shield_created += int(ev["count"])

		Types.EVT.SHIELD:
			if int(ev["target"]) == Types.Side.ENEMY:
				m.enemy_shield_instances += 1
				m.enemy_shield_prevented += int(ev["prevented"])

		Types.EVT.SHIELD_REMOVED:
			m.enemy_shield_removed += int(ev["count"])

		Types.EVT.AUTO_RESHUFFLE:
			m.auto_reshuffles += 1

		Types.EVT.CASCADE_DEPTH:
			var sm := m.side(int(ev["side"]))
			sm.deepest_cascade = maxi(sm.deepest_cascade, int(ev["depth"]))

		Types.EVT.TILE_STATS:
			var sm := m.side(int(ev["side"]))
			sm.tiles_destroyed += int(ev["destroyed"])
			sm.contention_tiles += int(ev["contested"])

		Types.EVT.HINT_SHOWN:
			m.hints_shown += 1

		Types.EVT.OVER:
			m.winner = int(ev["winner"])


## Damage is dealt BY the target's opponent, so it credits the other side.
##
## The buff portion is subtracted out of the causal bucket and the PASSIVE
## portion out of that, so the three never double count. Under Reinforced
## Connection the whole causal amount is PASSIVE damage and base Sync damage
## records as a clean zero — which is the rule being reported, not a bug.
static func _consume_damage(m: Battle, ev: Dictionary) -> void:
	var sm := m.side(Types.opponent_of(int(ev["target"])))
	var amount := int(ev["amount"])
	var bonus := _num(ev, "buff_bonus")
	var passive := _num(ev, "passive_raw")
	var causal := float(amount) - bonus - passive

	sm.total_damage += amount
	sm.largest_hit = maxi(sm.largest_hit, amount)
	sm.passive_damage += passive
	sm.buff_damage_added += bonus
	sm.cascade_damage += _num(ev, "cascade_raw")

	var program_id = ev.get("program_id", null)
	match int(ev["source"]):
		Types.DamageSource.MATCH:
			sm.match_damage += causal
			sm.crit_extra += _num(ev, "crit_extra")
			sm.match_damage_color += _num(ev, "color_raw")
			sm.match_damage_shape += _num(ev, "shape_raw")
		Types.DamageSource.ATTACKER:
			sm.attacker_damage += causal
			_credit(sm, program_id, causal)
		Types.DamageSource.LINESLICE:
			sm.lineslice_damage += causal
			_credit(sm, program_id, causal)
		Types.DamageSource.TRANSFORM:
			sm.transform_damage += causal
			_credit(sm, program_id, causal)
		_:
			sm.bomb_damage += causal
			_credit(sm, program_id, causal)

	# The aggregate buff bonus credits the side's active Program that carries
	# EFFECT_BUFF. Alpha content gives a side at most one, so the lookup is
	# unambiguous; revisit if later content gives one side several buff sources.
	if bonus > 0:
		var buffer := _buff_program_id(sm)
		if buffer != "":
			_unit(sm, buffer).effect += bonus


## The analytical splits are ABSENT when they do not apply and null once a
## Shield has scaled a value that was never populated. Both mean zero, and
## `int(null)` is a runtime error that would abort the rest of the batch — which
## is far worse than a wrong number, because every later event in that batch
## would go uncounted and the totals would silently under-report.
static func _num(ev: Dictionary, key: String) -> float:
	var v = ev.get(key, null)
	return 0.0 if v == null else float(v)


static func _credit(sm: SideMetrics, program_id, amount: float) -> void:
	if program_id != null and str(program_id) != "":
		_unit(sm, str(program_id)).effect += amount


static func _unit(sm: SideMetrics, program_id: String) -> Unit:
	if not sm.units.has(program_id):
		sm.units[program_id] = Unit.new()
	return sm.units[program_id]


static func _passive(sm: SideMetrics, cause: Dictionary) -> Passive:
	var key := passive_key(cause)
	if not sm.passives.has(key):
		var p := Passive.new()
		p.source_kind = int(cause["source_kind"])
		p.source_id = str(cause["source_id"])
		p.passive_id = str(cause["passive_id"])
		sm.passives[key] = p
	return sm.passives[key]


## Scanned over the battle's own roster, so a Buffer left in the inventory is
## never credited.
static func _buff_program_id(sm: SideMetrics) -> String:
	for id in sm.units:
		var prog := Content.program(str(id))
		if prog.is_empty():
			continue
		for op in (prog["fn"]["plan"] as Array):
			if str(op["effect_id"]) == Effects.BUFF:
				return str(id)
	return ""

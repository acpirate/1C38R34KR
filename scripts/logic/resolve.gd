class_name Resolve
extends RefCounted

## Combat resolution: damage, shields, charge routing, cascades, detonations,
## line slices, and transforms.
##
## The densest module in the port. Two invariants run through all of it:
##
##  1. **Damage buckets are disjoint and must reconcile.** Every instance is
##     attributed to exactly one causal bucket, and the analytical splits
##     (crit, buff, per-axis, cascade, PASSIVE) must still sum to the amount
##     actually dealt after Shield reduces it. That is why the splits are
##     scaled rather than recomputed.
##  2. **Shield prevention is not damage.** It is reported separately and never
##     added to a damage-source bucket, or the totals stop reconciling.


## The damage buckets PSV_FUNCTION_DAMAGE_INCREASE qualifies against: direct
## damage a Function caused.
##
## A Transform-created Sync is deliberately NOT one of them. Mechanically it is
## an ordinary Sync that the ledger merely credits to the Effect, and
## match-triggered PASSIVEs already cover the Sync path — counting it here would
## apply two bonuses to one event.
const FUNCTION_DAMAGE_SOURCES := [
	Types.DamageSource.ATTACKER,
	Types.DamageSource.BOMB,
	Types.DamageSource.LINESLICE,
]


# ---------------------------------------------------------------------------
# Overlay queries
# ---------------------------------------------------------------------------

## A pending overlay has a countdown still above zero. It occupies the slot but
## contributes nothing yet — a pending Buff adds no magnitude until delivery.
static func is_pending(sp: Tile.Special) -> bool:
	return sp != null and sp.countdown > 0


## Live Buff magnitude for a side. Pending Buffs are excluded by definition.
static func buff_bonus(state: GameState, side: Types.Side) -> int:
	var n := 0
	for row in state.board:
		for t in row:
			if t == null or not t.has_special():
				continue
			var sp: Tile.Special = t.special
			if sp.type == Tile.Special.Type.BUFF and sp.owner == side and not is_pending(sp):
				n += maxi(0, sp.magnitude)
	return n


## Removable Shield: the summed magnitude of a side's Shield Packets currently
## on the Datastream.
##
## Measured live at damage-application time, so a Shield sliced away no longer
## protects the next instance.
static func packet_shield(state: GameState, side: Types.Side) -> int:
	var n := 0
	for row in state.board:
		for t in row:
			if t == null or not t.has_special():
				continue
			var sp: Tile.Special = t.special
			if sp.type == Tile.Special.Type.SHIELD and sp.owner == side:
				n += maxi(0, sp.magnitude)
	return n


## Total Shield: removable Packet Shield plus non-removable PASSIVE Shield.
##
## Routed through this one function so every consumer — damage application, the
## HUD total, metrics — agrees. The permanent portion is not a Packet: it cannot
## be sliced, blasted, or transformed away.
static func shield_value(state: GameState, side: Types.Side) -> int:
	return packet_shield(state, side) + Passives.permanent_shield(state.identity, side)


# ---------------------------------------------------------------------------
# Per-Packet valuation
# ---------------------------------------------------------------------------

## Per-Packet damage for COLLATERAL destruction — Bomb blasts and LineSlice
## rows or columns.
##
## Not a Sync, so there is no slicing axis to pay on: the Packet is valued on
## BOTH axes against the acting side's resolved strong sets and pays the higher
## tier. Neutrals pay their flat value.
##
## Both collateral Effects share this one valuation so the two cannot drift.
static func base_damage(t: Tile, state: GameState, owner: Types.Side) -> int:
	if t.is_neutral():
		return Constants.DAMAGE_PER_TILE_NEUTRAL
	var by_color := Constants.DAMAGE_PER_TILE_HIGH_COLOR if Constants.is_strong_color(state.config, owner, t.color) else Constants.DAMAGE_PER_TILE_LOW_COLOR
	var by_shape := Constants.DAMAGE_PER_TILE_HIGH_SHAPE if Constants.is_strong_shape(state.config, owner, t.shape) else Constants.DAMAGE_PER_TILE_LOW_SHAPE
	return maxi(by_color, by_shape)


## Per-Packet damage for SYNC destruction, resolved on the axis or axes that
## actually sliced the Packet — unlike collateral, which pays the better of both.
##
## Returns `{value, axis}` where axis is a MatchFinder.Condition.
static func match_tile_damage(t: Tile, axes: Dictionary, owner: Types.Side, state: GameState) -> Dictionary:
	if t.is_neutral():
		return {"value": Constants.DAMAGE_PER_TILE_NEUTRAL, "axis": MatchFinder.Condition.NEUTRAL}

	var v := 0
	var axis := MatchFinder.Condition.NEUTRAL

	if axes.has(MatchFinder.Condition.COLOR) or axes.has(MatchFinder.Condition.NEUTRAL):
		v = Constants.DAMAGE_PER_TILE_HIGH_COLOR if Constants.is_strong_color(state.config, owner, t.color) else Constants.DAMAGE_PER_TILE_LOW_COLOR
		axis = MatchFinder.Condition.COLOR

	if axes.has(MatchFinder.Condition.SHAPE):
		var s := Constants.DAMAGE_PER_TILE_HIGH_SHAPE if Constants.is_strong_shape(state.config, owner, t.shape) else Constants.DAMAGE_PER_TILE_LOW_SHAPE
		if s > v or v == 0:
			v = s
			axis = MatchFinder.Condition.SHAPE

	return {"value": v, "axis": axis}


# ---------------------------------------------------------------------------
# Charge pools
# ---------------------------------------------------------------------------

## Adds charge to a Program, capped at its pool capacity. Returns the discarded
## overflow, which the caller attributes to charge waste.
static func add_unit_charge(state: GameState, u: GameState.UnitState, amount: int) -> int:
	var cap: int = Content.program(u.program_id)["charge_cap"]
	var before := u.charge
	u.charge = mini(cap, before + amount)
	return before + amount - u.charge


static func deck_charge_cap(state: GameState) -> int:
	return Content.deck(state.identity["deck_id"])["fn"]["cost"]


## Grants Deck Function charge to the side that owns the resolution.
##
## Only the Hacker carries a Deck, so an opponent-owned resolution charges
## nothing. Returns the amount discarded at the cap.
static func add_deck_charge(state: GameState, owner: Types.Side, amount: int) -> int:
	if owner != Types.Side.PLAYER or amount <= 0:
		return 0
	var cap := deck_charge_cap(state)
	var before := state.deck_charge
	state.deck_charge = mini(cap, before + amount)
	return before + amount - state.deck_charge


# ---------------------------------------------------------------------------
# Damage application
# ---------------------------------------------------------------------------

## Applies one damage instance.
##
## `info` carries the causal bucket plus the pre-floor analytical splits. It is
## a Dictionary rather than a class because it is optional-field-heavy and is
## copied into the emitted event nearly verbatim.
##
## Order is load-bearing: the PASSIVE damage bonus joins RAW damage before Shield
## sees it, exactly as the match bonus joins raw Sync damage.
static func deal_damage(state: GameState, target: Types.Side, amount: int, info: Dictionary, events: Array) -> void:
	if state.has_winner() or amount <= 0:
		return

	var work := info.duplicate()
	amount = _apply_function_damage_passives(state, target, amount, work, events)

	var final_amount := amount
	var buff_final: float = float(work.get("buff_bonus", 0))
	var crit_final = work.get("crit_extra", null)
	var color_final = work.get("color_raw", null)
	var shape_final = work.get("shape_raw", null)
	var cascade_final = work.get("cascade_raw", null)
	var passive_final = work.get("passive_raw", null)

	# Every separate instance is reduced by the DEFENDER's live total Shield,
	# after base and buff are folded in but BEFORE LINK/ICE is touched.
	var shield := shield_value(state, target)
	if shield > 0:
		var prevented := mini(amount, shield)
		final_amount = amount - prevented
		events.append({
			"t": Types.EVT.SHIELD, "target": target, "source": work["source"],
			"pre_shield": amount, "shield": shield, "prevented": prevented, "final": final_amount,
		})
		_report_permanent_shield_share(state, target, amount, prevented, events)

		# Shield eats the causal portion first and the buff portion last, so the
		# disjoint buckets still sum exactly to the amount dealt. The pre-floor
		# analytical splits scale with the causal remainder rather than being
		# recomputed — recomputation would drift from the actual total.
		var buff_in: float = float(work.get("buff_bonus", 0))
		var base := amount - buff_in
		buff_final = minf(buff_in, float(final_amount))
		var causal_final := float(final_amount) - buff_final
		var scale := (causal_final / base) if base > 0 else 0.0
		if crit_final != null:
			crit_final = float(crit_final) * scale
		if color_final != null:
			color_final = float(color_final) * scale
		if shape_final != null:
			shape_final = float(shape_final) * scale
		if cascade_final != null:
			cascade_final = float(cascade_final) * scale
		if passive_final != null:
			passive_final = float(passive_final) * scale

	# Fully absorbed: the shield event was emitted and nothing is dealt.
	if final_amount <= 0:
		return

	state.hp[target] -= final_amount

	var evt := {
		"t": Types.EVT.DAMAGE,
		"target": target,
		"amount": final_amount,
		"label": work.get("label", ""),
		"source": work["source"],
		"program_id": work.get("program_id", null),
		"fn_id": work.get("fn_id", null),
		"effect_id": work.get("effect_id", null),
		"crit_extra": crit_final,
		"buff_bonus": buff_final,
		"color_raw": color_final,
		"shape_raw": shape_final,
		"cascade_raw": cascade_final,
		"passive_raw": passive_final,
	}
	if work.has("cause"):
		evt["cause"] = work["cause"]
	events.append(evt)

	if state.hp[target] <= 0:
		state.winner = Types.opponent_of(target)
		state.phase = Types.Phase.OVER
		events.append({"t": Types.EVT.OVER, "winner": state.winner})


## PSV_FUNCTION_DAMAGE_INCREASE, applied in ONE place so every Function damage
## site gets it without three parallel implementations.
##
## Each instance's increment is reported separately, so stacking PASSIVEs never
## collapse into an unexplained aggregate — and the base event keeps its own
## Function and Effect attribution.
static func _apply_function_damage_passives(state: GameState, target: Types.Side, amount: int, work: Dictionary, events: Array) -> int:
	if not FUNCTION_DAMAGE_SOURCES.has(work["source"]):
		return amount

	var attacker := Types.opponent_of(target)
	var added := 0
	for inst in Passives.affecting(state.identity, PassiveEffects.FUNCTION_DAMAGE_INCREASE, attacker):
		var mag = inst.passive["magnitude"]
		if mag == null or int(mag) <= 0:
			continue
		added += int(mag)
		events.append({
			"t": Types.EVT.PASSIVE, "side": attacker, "cause": inst.cause(),
			"effect": inst.passive["effect_type"], "damage": int(mag),
		})

	if added > 0:
		work["passive_raw"] = float(work.get("passive_raw", 0)) + added
		return amount + added
	return amount


# ---------------------------------------------------------------------------
# Charge streams and top-to-bottom routing
# ---------------------------------------------------------------------------
#
# Charge is GENERATED per sliced Packet into per-axis streams, then each stream
# is ROUTED through the owner's ordered Program queue. The invariants:
#
#   - charge never flows upward
#   - a compatible non-full Program is never skipped
#   - no Program exceeds its Function cost
#   - inactive Programs are structurally absent — the unit list holds only the
#     active build, so there is nothing to filter
#   - the Deck Function is a separate pool entirely
#   - routing consults no RNG
#
# This is what makes an emergent synergy like COERCE feeding ATTACKER a
# consequence of bindings and build order rather than a special case.


static func _stream_key(axis: String, token: int) -> String:
	return "%s:%d" % [axis, token]


## Adds to a stream, merging with an existing one for the same axis and token.
##
## A PASSIVE that inflates an existing qualifying stream RE-LABELS it rather
## than opening a second pool — a second pool would charge every compatible
## Program again instead of enlarging the one stream.
static func add_stream(streams: Dictionary, axis: String, token: int, amount: int, source: Types.ChargeStreamSource, source_id := "") -> void:
	if amount <= 0:
		return
	var k := _stream_key(axis, token)
	if not streams.has(k):
		streams[k] = {"axis": axis, "token": token, "amount": amount, "source": source, "source_id": source_id}
		return
	var cur: Dictionary = streams[k]
	cur["amount"] += amount
	if source == Types.ChargeStreamSource.PASSIVE_MODIFIED_SYNC:
		cur["source"] = source
		cur["source_id"] = source_id


## Charge GENERATED by one sliced Packet.
##
## Neutral Packets pay the DECK instead, handled once per step by the caller,
## and never generate Program charge.
static func accumulate_tile_charge(state: GameState, t: Tile, axes: Dictionary, streams: Dictionary, source: Types.ChargeStreamSource, source_id := "") -> void:
	if t.is_neutral():
		return
	var single_axis: bool = state.config["single_axis_payout"]
	if not single_axis or axes.has(MatchFinder.Condition.COLOR):
		add_stream(streams, "color", t.color, Constants.CHARGE_PER_TILE_COLOR_MATCH, source, source_id)
	if not single_axis or axes.has(MatchFinder.Condition.SHAPE):
		add_stream(streams, "shape", t.shape, Constants.CHARGE_PER_TILE_SHAPE_MATCH, source, source_id)


## PSV_CHARGE_DAMPEN, applied to every qualifying stream AFTER all generation
## and BEFORE routing:
##
##     final = max(0, base + extra-charge bonuses − dampening)
##
## The formula is order-independent, which is why dampening is one pass here
## rather than a subtraction interleaved with the bonuses.
static func apply_charge_dampen(state: GameState, owner: Types.Side, streams: Dictionary, events: Array) -> void:
	var instances := Passives.affecting(state.identity, PassiveEffects.CHARGE_DAMPEN, owner)
	if instances.is_empty() or streams.is_empty():
		return
	var total := Passives.charge_dampen(state.identity, owner)
	if total <= 0:
		return

	for k in streams:
		var stream: Dictionary = streams[k]
		var before: int = stream["amount"]
		stream["amount"] = maxi(0, before - total)
		if stream["amount"] == before:
			continue
		stream["source"] = Types.ChargeStreamSource.PASSIVE_MODIFIED_SYNC
		# Every contributing instance is recorded individually, so several
		# dampening PASSIVEs on one stream stay distinguishable.
		for inst in instances:
			var mag = inst.passive["magnitude"]
			events.append({
				"t": Types.EVT.PASSIVE, "side": owner, "cause": inst.cause(),
				"effect": inst.passive["effect_type"], "charge": -(0 if mag == null else int(mag)),
			})


## Deterministic wave order: the colour axis fully resolves before shape, and
## tokens ascend within an axis.
static func ordered_streams(streams: Dictionary) -> Array:
	var out: Array = []
	for k in streams:
		out.append(streams[k])
	out.sort_custom(func(a, b):
		if a["axis"] == b["axis"]:
			return a["token"] < b["token"]
		return a["axis"] == "color")
	return out


## Routes ONE stream through the owner's ordered active Program queue.
static func route_charge_stream(state: GameState, owner: Types.Side, stream: Dictionary, events: Array) -> void:
	var units: Array = state.units[owner]
	var order: Array[String] = []
	for u in units:
		order.append(u.program_id)

	var eligible_idx: Array[int] = []
	for i in units.size():
		var prog := Content.program(units[i].program_id)
		var compatible: bool = (prog["colors"] as Array).has(stream["token"]) if stream["axis"] == "color" else (prog["shapes"] as Array).has(stream["token"])
		if compatible:
			eligible_idx.append(i)

	var remaining: int = stream["amount"]
	var assignments: Array = []
	for i in eligible_idx:
		if remaining <= 0:
			break
		var u: GameState.UnitState = units[i]
		var cap: int = Content.program(u.program_id)["charge_cap"]
		var room := cap - u.charge
		# Already at its Function cost: skip it and keep flowing DOWN. Skipping
		# is not the same as stopping — the stream continues to the next
		# compatible Program.
		if room <= 0:
			continue
		var before := u.charge
		var assigned := mini(room, remaining)
		u.charge = before + assigned
		remaining -= assigned
		assignments.append({
			"program_id": u.program_id, "before": before, "assigned": assigned,
			"after": u.charge, "overflow_out": remaining,
		})

	var eligible_ids: Array[String] = []
	for i in eligible_idx:
		eligible_ids.append(order[i])

	var evt := {
		"t": Types.EVT.CHARGE_ROUTE, "side": owner,
		"axis": stream["axis"], "token": stream["token"], "amount": stream["amount"],
		"stream_source": stream["source"],
		"order": order, "eligible": eligible_ids,
		"assignments": assignments,
		# End-of-stream discard is deliberately NOT attributed to any Program.
		# Charging it to the bottom-most compatible one reads as "that Program
		# wasted charge", when in fact the stream simply outran the whole queue.
		"discarded": remaining,
	}
	if str(stream.get("source_id", "")) != "":
		evt["source_id"] = stream["source_id"]
	events.append(evt)


static func route_streams(state: GameState, owner: Types.Side, streams: Dictionary, events: Array) -> void:
	for stream in ordered_streams(streams):
		route_charge_stream(state, owner, stream, events)


## Charge generated by EXPLICIT Effect destruction — a LineSlice row, or a Bomb
## blast whose tuple enables the charge branch.
##
## Each directly sliced Packet contributes standard owner-scoped charge from its
## own attributes. Returns the total that actually landed.
static func charge_from_effect_slice(state: GameState, owner: Types.Side, tiles: Array, events: Array) -> int:
	var streams := {}
	var both_axes := {MatchFinder.Condition.COLOR: true, MatchFinder.Condition.SHAPE: true}
	for t in tiles:
		accumulate_tile_charge(state, t, both_axes, streams, Types.ChargeStreamSource.EFFECT_DESTRUCTION)

	var before := _total_charge(state, owner)
	route_streams(state, owner, streams, events)
	return _total_charge(state, owner) - before


static func _total_charge(state: GameState, owner: Types.Side) -> int:
	var n := 0
	for u in (state.units[owner] as Array):
		n += u.charge
	return n


# ---------------------------------------------------------------------------
# Gravity and refill
# ---------------------------------------------------------------------------

## Settles the Datastream: Packets fall to close gaps, then empty cells refill.
##
## `constrained` is the cascade cap: replacement Packets are rejection-rolled so
## no Sync on the settled board contains a refill Packet, which is how a finite
## cascade limit terminates without truncating a wave mid-resolution.
static func apply_gravity_and_refill(state: GameState, events: Array, constrained := false, fresh_ids: Dictionary = {}) -> void:
	var moves: Array = []
	for x in Constants.BOARD_WIDTH:
		var write := Constants.BOARD_HEIGHT - 1
		for y in range(Constants.BOARD_HEIGHT - 1, -1, -1):
			var t: Tile = state.board[y][x]
			if t == null:
				continue
			if y != write:
				state.board[write][x] = t
				state.board[y][x] = null
				moves.append({"from": Vector2i(x, y), "to": Vector2i(x, write)})
			write -= 1
	if not moves.is_empty():
		events.append({"t": Types.EVT.FALL, "moves": moves})

	# Column-major so the spawn order matches the alpha's, which matters because
	# refill consumes RNG draws in exactly this sequence.
	var empty: Array[Vector2i] = []
	for x in Constants.BOARD_WIDTH:
		for y in Constants.BOARD_HEIGHT:
			if state.board[y][x] == null:
				empty.append(Vector2i(x, y))
	if empty.is_empty():
		return

	var gen := BoardOps.TileGen.new(state.rng, state.next_id)
	if constrained:
		_refill_constrained(state, empty, gen)
	else:
		for p in empty:
			state.board[p.y][p.x] = BoardOps.random_tile(gen)
	state.next_id = gen.next_id

	var spawned: Array = []
	for p in empty:
		var t: Tile = state.board[p.y][p.x]
		fresh_ids[t.id] = true
		spawned.append({"p": p, "view": _tile_view(t)})
	events.append({"t": Types.EVT.SPAWN, "tiles": spawned})


## Rejection-rolls replacements until no Sync on the settled board involves a
## refilled cell.
##
## The local left/up guard biases away from Syncs cheaply; the full-board check
## is the authority, because it also catches right and below neighbours that the
## local guard cannot see.
static func _refill_constrained(state: GameState, cells: Array, gen: BoardOps.TileGen) -> void:
	for attempt in 200:
		for p in cells:
			var t := BoardOps.random_tile(gen)
			var guard := 0
			while BoardOps.completes_run(state.board, p.x, p.y, t) and guard < 100:
				t = BoardOps.random_tile(gen)
				guard += 1
			state.board[p.y][p.x] = t

		var bad := false
		for m in MatchFinder.detect(state.board):
			for c in m.cells:
				if cells.has(c):
					bad = true
					break
			if bad:
				break
		if not bad:
			return
		for p in cells:
			state.board[p.y][p.x] = null

	# Practically unreachable at 37 Packet types; accept an unconstrained fill
	# rather than loop forever.
	for p in cells:
		state.board[p.y][p.x] = BoardOps.random_tile(gen)


static func _tile_view(t: Tile) -> Dictionary:
	var v := {"kind": t.kind}
	if not t.is_neutral():
		v["color"] = t.color
		v["shape"] = t.shape
	if t.has_special():
		v["special"] = {"type": t.special.type, "owner": t.special.owner, "countdown": t.special.countdown}
	return v


## Packets bound to a side's ACTIVE Programs, for the contention metric. Read
## from the battle's own roster, so a Program sitting in inventory but not in
## the build creates no contention.
static func _bound_tokens(state: GameState, side: Types.Side, key: String) -> Dictionary:
	var out := {}
	for u in (state.units[side] as Array):
		for v in (Content.program(u.program_id)[key] as Array):
			out[v] = true
	return out


# ---------------------------------------------------------------------------
# Cascade resolution
# ---------------------------------------------------------------------------

## Resolves every Sync step for one owner-side action until the Datastream
## settles. Each iteration is one STEP: all simultaneous Syncs in the current
## board state resolve together, with a single Buff application.
##
## `cause` is the INITIATING action's bucket, not the mechanism that finally
## dealt the damage — everything descended from a Bomb is Bomb damage, however
## many Syncs it sets off.
##
## Returns `{steps, stochastic_rounds}`.
static func resolve_cascades(
	state: GameState,
	owner: Types.Side,
	events: Array,
	budget,
	cause: Types.DamageSource,
	fresh_ids: Dictionary,
	cause_program_id := "",
	origin: Dictionary = {}
) -> Dictionary:
	var steps := 0
	var stochastic_rounds := 0
	var damage_passives := Passives.affecting(state.identity, PassiveEffects.EXTRA_MATCH_DAMAGE, owner)
	var charge_passives := Passives.affecting(state.identity, PassiveEffects.EXTRA_MATCH_CHARGE, owner)

	while not state.has_winner():
		var matches := MatchFinder.detect(state.board)
		if matches.is_empty():
			break
		steps += 1

		# Classified BEFORE destruction, because it needs the live Packets.
		var stochastic: Array[bool] = []
		var any_stochastic := false
		for m in matches:
			var is_stoch := false
			for c in m.cells:
				var t: Tile = state.board[c.y][c.x]
				if t != null and fresh_ids.has(t.id):
					is_stoch = true
					break
			stochastic.append(is_stoch)
			if is_stoch:
				any_stochastic = true
		if any_stochastic:
			stochastic_rounds += 1

		var info := {}
		# (1) DIRECT Sync footprints. Constituent match groups remain the
		# authority for base damage, crit, charge, and PASSIVE triggers.
		for mi in matches.size():
			var m: MatchFinder.Match = matches[mi]
			var mult := MatchFinder.multiplier(m)
			for c in m.cells:
				_bump_slice(info, c, mult, [m.condition], stochastic[mi])

		# Snapshot before any collateral is added, so line-clear qualification
		# reads the DIRECT footprint only — which is what makes it non-recursive.
		var direct := info.duplicate()

		_apply_line_clears(state, matches, direct, info, owner, events)

		# Computed BEFORE removal, so a same-side Buff sliced in this step still
		# counts toward this step's damage.
		var bonus := buff_bonus(state, owner)
		var opp_colors := _bound_tokens(state, Types.opponent_of(owner), "colors")
		var opp_shapes := _bound_tokens(state, Types.opponent_of(owner), "shapes")

		var acc := {
			"raw": 0.0, "passive_raw": 0.0, "crit_extra": 0.0, "contested": 0,
			"color_raw": 0.0, "shape_raw": 0.0, "cascade_raw": 0.0,
			"shields_removed": 0, "neutral_sliced": 0,
		}
		var destroyed: Array[Vector2i] = []
		var streams := {}

		# A wave is a cascade once it is past the first step or involves any
		# refilled Packet. The first wave may instead be labelled with the Effect
		# that caused it, so generation stays attributable — allocation is
		# untouched either way.
		var is_cascade_wave := steps > 1 or any_stochastic
		var stream_source: Types.ChargeStreamSource = Types.ChargeStreamSource.CASCADE if is_cascade_wave else origin.get("stream_source", Types.ChargeStreamSource.SYNC)
		var stream_source_id: String = "" if is_cascade_wave else str(origin.get("source_id", ""))

		for k in info:
			var slice: Dictionary = info[k]
			var p: Vector2i = slice["p"]
			var t: Tile = state.board[p.y][p.x]
			if t == null:
				continue
			destroyed.append(p)
			if t.has_special() and t.special.type == Tile.Special.Type.SHIELD:
				acc["shields_removed"] += 1
			if t.is_neutral():
				acc["neutral_sliced"] += 1

			var mult: float = slice["m"]
			var d := match_tile_damage(t, slice["axes"], owner, state)
			var base: int = d["value"]
			acc["raw"] += base * mult
			if mult > 1.0:
				acc["crit_extra"] += base * (mult - 1.0)
			if d["axis"] == MatchFinder.Condition.COLOR:
				acc["color_raw"] += base * mult
			elif d["axis"] == MatchFinder.Condition.SHAPE:
				acc["shape_raw"] += base * mult
			if slice["stoch_only"]:
				acc["cascade_raw"] += base * mult
			if not t.is_neutral() and (opp_colors.has(t.color) or opp_shapes.has(t.shape)):
				acc["contested"] += 1

			accumulate_tile_charge(state, t, slice["axes"], streams, stream_source, stream_source_id)

		_apply_match_passives(state, owner, matches, damage_passives, charge_passives, acc, streams, events)

		# Dampening runs after ALL generation, so the order-independent
		# max(0, base + bonuses − dampening) formula holds however the content
		# happens to be arranged.
		apply_charge_dampen(state, owner, streams, events)
		route_streams(state, owner, streams, events)

		_grant_neutral_deck_charge(state, owner, acc["neutral_sliced"], events)

		events.append({"t": Types.EVT.TILE_STATS, "side": owner, "destroyed": destroyed.size(), "contested": acc["contested"]})
		events.append({"t": Types.EVT.DESTROY, "cells": destroyed})
		for p in destroyed:
			state.board[p.y][p.x] = null
		if acc["shields_removed"] > 0:
			events.append({"t": Types.EVT.SHIELD_REMOVED, "count": acc["shields_removed"]})

		_deal_wave_damage(state, owner, acc, bonus, cause, cause_program_id, origin, events)

		apply_gravity_and_refill(state, events, budget != null and steps >= int(budget), fresh_ids)

	# The cascade metric counts only stochastic-refill rounds — a deterministic
	# chain is not a cascade in the sense being measured.
	if stochastic_rounds > 0:
		events.append({"t": Types.EVT.CASCADE_DEPTH, "side": owner, "depth": stochastic_rounds})
	if not state.has_winner():
		ensure_no_deadlock(state, events)
	return {"steps": steps, "stochastic_rounds": stochastic_rounds}


## Records one Packet's slice: the HIGHEST qualifying multiplier applied once,
## the UNION of axes that sliced it, and whether EVERY Sync slicing it was
## stochastic — mixed destruction counts as earned.
static func _bump_slice(info: Dictionary, p: Vector2i, m: float, axes: Array, stoch: bool) -> void:
	if not info.has(p):
		var axis_set := {}
		for a in axes:
			axis_set[a] = true
		info[p] = {"p": p, "m": m, "axes": axis_set, "stoch_only": stoch}
		return
	var cur: Dictionary = info[p]
	if m > cur["m"]:
		cur["m"] = m
	for a in axes:
		cur["axes"][a] = true
	cur["stoch_only"] = cur["stoch_only"] and stoch


## Line clears, qualified from the wave's COMBINED direct footprint.
##
## Collateral cells are swept at the plain tier with NO crit — no single
## constituent group owns a combined line — and inherit the axis set of the
## direct matches that formed that line, so charge attribution stays defined.
## Cells already sliced directly keep their own multiplier and axes.
static func _apply_line_clears(state: GameState, matches: Array, direct: Dictionary, info: Dictionary, owner: Types.Side, events: Array) -> void:
	for line in MatchFinder.compute_line_clears(matches):
		var line_cells: Array[Vector2i] = []
		if line.orientation == MatchFinder.Orientation.HORIZONTAL:
			for x in Constants.BOARD_WIDTH:
				line_cells.append(Vector2i(x, line.index))
		else:
			for y in Constants.BOARD_HEIGHT:
				line_cells.append(Vector2i(line.index, y))

		var axes := {}
		var any_direct := false
		var all_stoch := true
		for p in line_cells:
			if not direct.has(p):
				continue
			any_direct = true
			for a in (direct[p]["axes"] as Dictionary):
				axes[a] = true
			all_stoch = all_stoch and direct[p]["stoch_only"]

		# Defensive: a qualifying line always contains direct Packets.
		if not any_direct:
			continue

		events.append({
			"t": Types.EVT.LINE_CLEAR, "side": owner,
			"orientation": line.orientation, "index": line.index,
		})
		for p in line_cells:
			if direct.has(p):
				continue
			_bump_slice(info, p, Constants.MATCH_4_MULTIPLIER, axes.keys(), all_stoch)


## Match-triggered PASSIVEs, scoped to the RESOLUTION OWNER, once per qualifying
## Sync event.
##
## Duplicate qualifying instances stack additively simply by iterating the list.
## Repeats across sources are meaningful content and are never deduplicated.
static func _apply_match_passives(state: GameState, owner: Types.Side, matches: Array, damage_passives: Array, charge_passives: Array, acc: Dictionary, streams: Dictionary, events: Array) -> void:
	for inst in damage_passives:
		for m in matches:
			if not _passive_qualifies(inst, m):
				continue
			# The bonus joins RAW Sync damage BEFORE the crit multiplier,
			# flooring, Buff addition, and Shield reduction — the same damage
			# order the effect had when it was an inherent Hacker trait.
			var mag_v = inst.passive["magnitude"]
			var magnitude: int = 0 if mag_v == null else int(mag_v)
			var mult := MatchFinder.multiplier(m)
			var add := magnitude * mult
			acc["passive_raw"] += add
			if mult > 1.0:
				acc["crit_extra"] += magnitude * (mult - 1.0)
			events.append({
				"t": Types.EVT.PASSIVE, "side": owner, "cause": inst.cause(),
				"effect": inst.passive["effect_type"], "damage": add,
			})

	for inst in charge_passives:
		for m in matches:
			if not _passive_qualifies(inst, m):
				continue
			# Increases this event's existing qualifying colour stream BEFORE it
			# is routed, then lets the ordinary top-to-bottom rule place it. It
			# does NOT open a separate pool charging every compatible Program.
			var mag_v = inst.passive["magnitude"]
			var magnitude: int = 0 if mag_v == null else int(mag_v)
			add_stream(streams, "color", int(inst.passive["color"]), magnitude, Types.ChargeStreamSource.PASSIVE_MODIFIED_SYNC, inst.passive["id"])
			events.append({
				"t": Types.EVT.PASSIVE, "side": owner, "cause": inst.cause(),
				"effect": inst.passive["effect_type"], "charge": magnitude,
			})


## The qualifying match-event identity: a RESOLVED colour-axis Sync of the
## PASSIVE's colour.
##
## Same-axis runs the engine merged into one player-visible blob count ONCE;
## distinct blobs each qualify independently; a shape-axis Sync never qualifies
## even when caused by moving a Packet of that colour; and line-clear collateral,
## Bomb slices, and Function slices create no qualifying event at all, because
## none of them is a detected Sync.
static func _passive_qualifies(inst, m: MatchFinder.Match) -> bool:
	return m.condition == MatchFinder.Condition.COLOR and m.value == inst.passive["color"]


## Deck Function charge from neutral Packets sliced anywhere in this owned
## resolution — the direct footprint, qualifying line clears, and same-side
## cascades all count, since each cascade wave runs the loop again.
##
## Bomb destruction never reaches here, so it grants nothing.
static func _grant_neutral_deck_charge(state: GameState, owner: Types.Side, neutral_sliced: int, events: Array) -> void:
	if neutral_sliced <= 0:
		return
	var gain := neutral_sliced * Constants.DECK_CHARGE_PER_NEUTRAL_TILE
	var wasted := add_deck_charge(state, owner, gain)
	if owner == Types.Side.PLAYER:
		events.append({"t": Types.EVT.DECK_CHARGE, "side": owner, "amount": gain - wasted, "wasted": wasted})


## Applies the wave's accumulated damage.
##
## REINFORCED CONNECTION suppresses ordinary BASE Sync damage for both sides —
## but the Sync event still exists, so match-triggered PASSIVE damage still
## resolves into its own bucket. Charge, destruction, contention, Deck charge,
## and cascading are untouched, and Bomb detonations are unaffected.
##
## The Buff bonus deliberately does NOT apply under suppression: it amplifies
## base Sync damage, which is exactly what the mode suppresses.
static func _deal_wave_damage(state: GameState, owner: Types.Side, acc: Dictionary, bonus: int, cause: Types.DamageSource, cause_program_id: String, origin: Dictionary, events: Array) -> void:
	var suppress_base: bool = state.config["reinforced_connection"]
	var causal_raw: float = acc["passive_raw"] if suppress_base else acc["raw"] + acc["passive_raw"]

	# Fractional crit sums are floored. The PASSIVE portion is allocated as an
	# integer so the disjoint buckets stay exact and base Sync damage records as
	# a clean zero under suppression.
	var total := int(floor(causal_raw))
	var passive_portion := mini(total, int(floor(acc["passive_raw"])))

	if total <= 0 and (suppress_base or bonus <= 0):
		return

	var info := {
		"source": cause,
		"label": "Hacker Sync" if owner == Types.Side.PLAYER else "System Sync",
		# Under suppression the crit cross-cut reports 0: the multiplier's
		# contribution to BASE Sync damage is exactly what is suppressed, and
		# the surviving PASSIVE contribution has its own bucket. This never
		# over-reports crit against damage that was not dealt.
		"crit_extra": 0.0 if suppress_base else acc["crit_extra"],
		"buff_bonus": 0 if suppress_base else bonus,
		"cascade_raw": 0.0 if suppress_base else acc["cascade_raw"],
		"passive_raw": float(passive_portion),
	}
	if cause != Types.DamageSource.MATCH:
		info["program_id"] = cause_program_id
	# A Transform-caused Sync carries the Function and Effect that caused it, so
	# the transform bucket is auditable back to the exact activation.
	if cause == Types.DamageSource.TRANSFORM:
		info["fn_id"] = origin.get("source_id", "")
		info["effect_id"] = Effects.TRANSFORM
	if cause == Types.DamageSource.MATCH and not suppress_base:
		info["color_raw"] = acc["color_raw"]
		info["shape_raw"] = acc["shape_raw"]

	deal_damage(state, Types.opponent_of(owner), total + (0 if suppress_base else bonus), info, events)


## Reshuffles when no legal move remains. A permutation, so composition and any
## Packet-converting investment survive.
static func ensure_no_deadlock(state: GameState, events: Array) -> void:
	if BoardOps.has_any_valid_move(state.board):
		return
	var carrier := {"board": state.board, "rng": state.rng, "next_id": state.next_id}
	BoardOps.reshuffle(carrier)
	state.board = carrier["board"]
	state.next_id = carrier["next_id"]
	events.append({"t": Types.EVT.AUTO_RESHUFFLE})
	events.append({"t": Types.EVT.MSG, "text": "No moves left — Datastream reshuffled"})
	events.append({"t": Types.EVT.BOARD, "grid": _grid_view(state.board)})


static func _grid_view(board: Array) -> Array:
	var out: Array = []
	for row in board:
		var r: Array = []
		for t in row:
			r.append(null if t == null else _tile_view(t))
		out.append(r)
	return out


# ---------------------------------------------------------------------------
# Bomb detonation
# ---------------------------------------------------------------------------

## Pre-parameterization Bombs granted no charge at all, so an overlay saved
## without an explicit selection keeps that behaviour.
const GAIN_CHARGE_NO_DEFAULT := 1

## Default footprint for an overlay armed before area patterns were authored.
const DEFAULT_BLAST_PATTERN := Areas.SQUARE_3X3


## Detonates the Bomb overlay at `p`, if there is one.
##
## The placing Function's typed selections travel WITH the overlay, so a Bomb
## armed three turns ago still resolves under its own contract — a Function
## edited in between cannot reach back and change what is already in flight.
static func resolve_detonation(state: GameState, p: Vector2i, events: Array) -> void:
	var bomb := state.tile_at(p)
	if bomb == null or not bomb.has_special() or bomb.special.type != Tile.Special.Type.BOMB:
		return
	var sp: Tile.Special = bomb.special
	detonate_at(state, p, {
		"owner": sp.owner,
		"area_pattern": sp.area_pattern if sp.area_pattern != "" else DEFAULT_BLAST_PATTERN,
		"program_id": sp.program_id,
		"fn_id": sp.fn_id,
		"deal_damage": sp.deal_damage if sp.deal_damage != -1 else Content.DEAL_DAMAGE_YES,
		"gain_charge": sp.gain_charge if sp.gain_charge != -1 else GAIN_CHARGE_NO_DEFAULT,
	}, events)


## The ONE Bomb blast implementation, shared by countdown detonations and by
## immediate (countdown-blank) resolutions.
##
## No chain detonations and no re-triggers: everything in the footprint is
## sliced as an ordinary Packet, including another Bomb.
##
## `settle` false leaves gravity, refill, and cascades to the caller, so an
## immediately resolving Bomb can log its target BEFORE the board moves.
static func detonate_at(state: GameState, p: Vector2i, spec: Dictionary, events: Array, settle := true) -> void:
	var owner: Types.Side = spec["owner"]
	var offsets := Areas.cells(spec["area_pattern"])

	# Clipped to the board. The full in-bounds footprint is reported so the
	# renderer can flash cells that were empty, while only occupied cells are
	# actually sliced.
	var in_bounds: Array[Vector2i] = []
	var cells: Array[Vector2i] = []
	for d in offsets:
		var n := p + d
		if state.in_bounds(n):
			in_bounds.append(n)
			if state.tile_at(n) != null:
				cells.append(n)
	events.append({"t": Types.EVT.DETONATE, "p": p, "cells": in_bounds})

	var bonus := buff_bonus(state, owner)
	var raw := 0
	var shields_removed := 0
	var sliced: Array[Tile] = []
	for c in cells:
		var t := state.tile_at(c)
		if t.has_special() and t.special.type == Tile.Special.Type.SHIELD:
			shields_removed += 1
		sliced.append(t)
		raw += base_damage(t, state, owner)

	events.append({"t": Types.EVT.DESTROY, "cells": cells})
	for c in cells:
		state.set_tile(c, null)
	if shields_removed > 0:
		events.append({"t": Types.EVT.SHIELD_REMOVED, "count": shields_removed})

	# Directly sliced blast Packets charge only when the tuple says so. Current
	# content grants none, preserving the established rule that Bomb destruction
	# does not charge.
	if spec["gain_charge"] == Content.GAIN_CHARGE_YES:
		charge_from_effect_slice(state, owner, sliced, events)

	# A blast can mutate the board WITHOUT dealing damage. Resulting refill
	# Syncs still resolve normally either way.
	if spec["deal_damage"] == Content.DEAL_DAMAGE_YES:
		deal_damage(state, Types.opponent_of(owner), raw + bonus, {
			"source": Types.DamageSource.BOMB,
			"label": "Hacker bomb" if owner == Types.Side.PLAYER else "System bomb",
			"program_id": spec.get("program_id", ""),
			"fn_id": spec.get("fn_id", ""),
			"effect_id": Effects.BOMB,
			"buff_bonus": bonus,
		}, events)

	if state.has_winner() or not settle:
		return
	settle_after_effect(state, owner, Types.DamageSource.BOMB, str(spec.get("program_id", "")), events)


## An Effect-caused destruction has no "initial Sync", so its entire cascade
## budget is the cap itself — and at cap 0 even its own refill is constrained.
##
## Everything descended from it carries that Effect's causal bucket and belongs
## to the initiator, however many Syncs follow.
static func settle_after_effect(state: GameState, owner: Types.Side, cause: Types.DamageSource, cause_program_id: String, events: Array) -> void:
	var cap = state.config["max_cascade_steps"]
	var fresh_ids := {}
	apply_gravity_and_refill(state, events, cap != null and int(cap) <= 0, fresh_ids)
	resolve_cascades(state, owner, events, cap, cause, fresh_ids, cause_program_id)


# ---------------------------------------------------------------------------
# Line slice
# ---------------------------------------------------------------------------

## Slices a whole row or column through the resolved target.
##
## Returns `{dimension, sliced, retained, damage, charge}` — the caller logs the
## target and outcome, so the return is richer than the events alone.
static func resolve_line_slice(state: GameState, target: Vector2i, spec: Dictionary, events: Array) -> Dictionary:
	var owner: Types.Side = spec["owner"]
	var params: Dictionary = spec["params"]
	var vertical: bool = params["dimension"] == Content.LINE_DIMENSION_COLUMN

	var line_cells: Array[Vector2i] = []
	if vertical:
		for y in Constants.BOARD_HEIGHT:
			line_cells.append(Vector2i(target.x, y))
	else:
		for x in Constants.BOARD_WIDTH:
			line_cells.append(Vector2i(x, target.y))

	# Retention is decided BEFORE anything is sliced. A retained overlay stays a
	# complete Packet, is excluded from the direct slice, and then settles
	# normally — it is not pinned above empty space.
	var retention: int = params["specialRetention"]
	var retained: Array[Vector2i] = []
	var sliced_pts: Array[Vector2i] = []
	var sliced_tiles: Array[Tile] = []

	for c in line_cells:
		var t := state.tile_at(c)
		# A concluded board may legitimately hold gaps.
		if t == null:
			continue
		var keep := false
		if t.has_special():
			keep = retention == Content.SPECIALS_RETAIN_ALL or (retention == Content.SPECIALS_RETAIN_OWN and t.special.owner == owner)
		if keep:
			retained.append(c)
			continue
		sliced_pts.append(c)
		sliced_tiles.append(t)

	# ONE combined NONCRITICAL damage instance per deployment, valued through
	# the shared collateral valuation. Buff and Shield apply once, via the
	# ordinary damage pipeline. Retained overlays and out-of-board cells
	# contribute nothing.
	var raw := 0
	var shields_removed := 0
	for t in sliced_tiles:
		if t.has_special() and t.special.type == Tile.Special.Type.SHIELD:
			shields_removed += 1
		raw += base_damage(t, state, owner)

	events.append({"t": Types.EVT.DESTROY, "cells": sliced_pts})
	for c in sliced_pts:
		state.set_tile(c, null)
	if shields_removed > 0:
		events.append({"t": Types.EVT.SHIELD_REMOVED, "count": shields_removed})

	var charge := 0
	if params["gainCharge"] == Content.GAIN_CHARGE_YES:
		charge = charge_from_effect_slice(state, owner, sliced_tiles, events)

	var damage := 0
	if params["dealDamage"] == Content.DEAL_DAMAGE_YES:
		var bonus := buff_bonus(state, owner)
		damage = raw + bonus
		# Function damage, so Reinforced Connection — which suppresses BASE SYNC
		# damage only — does not touch it.
		deal_damage(state, Types.opponent_of(owner), damage, {
			"source": Types.DamageSource.LINESLICE,
			"label": "Hacker line slice" if owner == Types.Side.PLAYER else "System line slice",
			"program_id": spec.get("program_id", ""),
			"fn_id": spec.get("fn_id", ""),
			"effect_id": Effects.LINESLICE,
			"buff_bonus": bonus,
		}, events)

	return {
		"dimension": "column" if vertical else "row",
		"sliced": sliced_pts, "retained": retained,
		"damage": damage, "charge": charge,
	}


# ---------------------------------------------------------------------------
# Transform
# ---------------------------------------------------------------------------

## Does this Packet match the authored target axis?
##
## A single authored axis targets that value on one axis and ANY value on the
## other, and excludes neutrals — a neutral has no axis to match against.
static func _matches_axis_target(t: Tile, target: Dictionary) -> bool:
	var kind: int = target["kind"]
	if kind == Content.AxisTargetKind.NEU:
		return t.is_neutral()
	if kind == Content.AxisTargetKind.ALL:
		return true
	if t.is_neutral():
		return false
	if target["color"] != null and t.color != int(target["color"]):
		return false
	if target["shape"] != null and t.shape != int(target["shape"]):
		return false
	return true


## How many axes of the RESULT this Packet already has.
##
## A Packet sharing EVERY result axis is a pure no-op and is never a valid
## target; one sharing exactly one axis of a two-axis result is the FALLBACK
## tier, used only to top up after the clean tier is exhausted.
static func _shared_result_axes(t: Tile, result: Dictionary) -> int:
	if result["neutral"]:
		return 1 if t.is_neutral() else 0
	if t.is_neutral():
		return 0  ## a neutral shares no colour or shape
	var n := 0
	if result["color"] != null and t.color == int(result["color"]):
		n += 1
	if result["shape"] != null and t.shape == int(result["shape"]):
		n += 1
	return n


static func _result_axis_count(result: Dictionary) -> int:
	if result["neutral"]:
		return 1
	var n := 0
	if result["color"] != null:
		n += 1
	if result["shape"] != null:
		n += 1
	return n


## The eligible pool, split into two tiers.
##
## Tier 1 is Packets sharing NO result axis; tier 2 is Packets sharing exactly
## one axis of a TWO-axis result. Anything matching every result axis is
## excluded outright, so `quantity` always means "up to this many REAL
## transformations" rather than counting no-ops.
static func transform_candidates(state: GameState, spec: Dictionary) -> Dictionary:
	var tier1: Array[Vector2i] = []
	var tier2: Array[Vector2i] = []
	var axes := _result_axis_count(spec["axis_result"])

	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var t: Tile = state.board[y][x]
			if t == null or not _matches_axis_target(t, spec["axis_target"]):
				continue
			var shared := _shared_result_axes(t, spec["axis_result"])
			if shared == 0:
				tier1.append(Vector2i(x, y))
			elif axes == 2 and shared == 1:
				tier2.append(Vector2i(x, y))
			# shared == axes: already identical on every result axis, never valid.

	return {"tier1": tier1, "tier2": tier2}


## Total eligible count, for the valid-target gating that decides whether a
## Function is withheld rather than fired into nothing.
static func transform_candidate_count(state: GameState, spec: Dictionary) -> int:
	var c := transform_candidates(state, spec)
	return (c["tier1"] as Array).size() + (c["tier2"] as Array).size()


## Draws up to `want` distinct targets without replacement.
##
## When every eligible Packet in a tier will be transformed anyway, the
## selection is a complete set and its order is irrelevant — so NO gameplay RNG
## is consumed merely to permute it. RNG is consumed only when the choice
## actually excludes something.
##
## That distinction is load-bearing for seed parity: drawing "for tidiness" when
## the outcome cannot differ would shift every subsequent draw in the battle.
static func _draw(state: GameState, pool: Array, want: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if want <= 0 or pool.is_empty():
		return out
	if pool.size() <= want:
		for p in pool:
			out.append(p)
		return out
	var rest := pool.duplicate()
	for i in want:
		var idx := state.rng.int_below(rest.size())
		out.append(rest[idx])
		rest.remove_at(idx)
	return out


## ATOMIC transformation: every selected Packet changes BEFORE any Sync
## detection runs.
##
## Transform-one-then-resolve-then-transform-the-next would make arbitrary
## target-iteration order mechanically significant, and would not match the
## player's mental model of a single simultaneous conversion.
##
## This performs ONLY the board mutation and reports what it did; the caller
## runs the resulting Sync wave. Splitting it that way makes the
## "all transforms, then detection" ordering impossible to get wrong.
static func apply_transform(state: GameState, spec: Dictionary, events: Array) -> Dictionary:
	var candidates := transform_candidates(state, spec)
	var tier1: Array = candidates["tier1"]
	var tier2: Array = candidates["tier2"]

	var outcome := {
		"candidates": tier1.size() + tier2.size(),
		"cells": [] as Array[Vector2i],
		"tier2_used": 0,
		"specials_retained": 0,
		"specials_destroyed": 0,
	}
	if outcome["candidates"] == 0:
		return outcome

	# Tier 1 is drawn first and tier 2 TOPS UP whatever quantity remains, so a
	# Function never converts fewer Packets than it could merely because the
	# clean pool ran short.
	var quantity: int = spec["quantity"]
	var from_tier1 := _draw(state, tier1, quantity)
	var from_tier2 := _draw(state, tier2, quantity - from_tier1.size())
	outcome["tier2_used"] = from_tier2.size()

	var chosen: Array[Vector2i] = []
	chosen.append_array(from_tier1)
	chosen.append_array(from_tier2)

	var result: Dictionary = spec["axis_result"]
	for p in chosen:
		var t := state.tile_at(p)
		_apply_overlay_treatment(t, spec, result, outcome)
		_apply_result_axes(state, t, result)
		(outcome["cells"] as Array).append(p)
		events.append({"t": Types.EVT.SET_TILE, "p": p, "view": _tile_view(t)})

	return outcome


## Retaining preserves the overlay's ownership and Effect-specific state —
## countdown, magnitude, attribution — while the UNDERLYING Packet changes
## identity.
static func _apply_overlay_treatment(t: Tile, spec: Dictionary, result: Dictionary, outcome: Dictionary) -> void:
	if not t.has_special():
		return
	# A neutral RESULT is the exception: a neutral structurally cannot carry an
	# overlay, so retention is impossible whatever the tuple says. The loader
	# warns about that authoring; here it simply always destroys.
	var treatment: int = spec["params"]["specialPacketTreatment"]
	var keep: bool = not result["neutral"] and (
		treatment == Content.SPECIALS_RETAIN_ALL
		or (treatment == Content.SPECIALS_RETAIN_OWN and t.special.owner == spec["owner"])
	)
	if keep:
		outcome["specials_retained"] += 1
	else:
		t.special = null
		outcome["specials_destroyed"] += 1


## A single-axis result PRESERVES the other axis. A neutral target has no axis
## to preserve, so the unauthored one is randomized per Packet from the
## battle's gameplay RNG.
static func _apply_result_axes(state: GameState, t: Tile, result: Dictionary) -> void:
	if result["neutral"]:
		t.kind = Tile.Kind.NEUTRAL
		t.color = -1
		t.shape = -1
		return

	var was_neutral := t.is_neutral()
	t.kind = Tile.Kind.STANDARD
	if result["color"] != null:
		t.color = int(result["color"])
	elif was_neutral:
		t.color = state.rng.int_below(Constants.COLOR_COUNT)
	if result["shape"] != null:
		t.shape = int(result["shape"])
	elif was_neutral:
		t.shape = state.rng.int_below(Constants.SHAPE_COUNT)


## Reports how much of this prevention the removable Packet Shield could NOT
## have accounted for, so metrics can tell permanent Shield from Packet Shield.
static func _report_permanent_shield_share(state: GameState, target: Types.Side, amount: int, prevented: int, events: Array) -> void:
	var packet := packet_shield(state, target)
	var from_passive := maxi(0, prevented - mini(amount, packet))
	if from_passive <= 0:
		return
	for inst in Passives.affecting(state.identity, PassiveEffects.PERM_SHIELD, target):
		var mag = inst.passive["magnitude"]
		events.append({
			"t": Types.EVT.PASSIVE, "side": target, "cause": inst.cause(),
			"effect": inst.passive["effect_type"], "shield": 0 if mag == null else int(mag),
		})

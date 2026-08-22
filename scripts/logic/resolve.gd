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

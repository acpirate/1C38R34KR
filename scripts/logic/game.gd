class_name Game
extends RefCounted

## The turn lifecycle: activation, the turn-ending Sync, and the enemy turn.
##
## Owns WHEN things happen. What they do lives in `resolve.gd`; the order
## triggered PASSIVEs resolve in lives in `passive.gd`.
##
## The event list is the sole output. Logic resolves a turn completely and
## synchronously, then hands back an ordered list the renderer plays over time
## — which is what keeps the whole engine headlessly runnable.

var state: GameState


func _init(s: GameState) -> void:
	state = s


## The one funnel every returned event batch passes through, and therefore the
## one place metrics and logging attach.
##
## Both are strictly READ-ONLY over the stream (port note P-014). Neither may
## write game state, consume RNG, or alter the list — if either could, the
## differential gate would become sensitive to log level, which would make it
## worthless as a gate.
func _collect(events: Array) -> Array:
	if state.metrics != null:
		Metrics.consume(state.metrics, events)
		state.metrics.turns = state.turn
	if state.log != null:
		state.log.consume(state, events)
	return events


## An ordinary Sync resolves its initial wave plus the configured cascade cap.
func _match_budget():
	var cap = state.config["max_cascade_steps"]
	return null if cap == null else int(cap) + 1


## Translates a resolved Shake cascade mode into a resolution budget. The mode
## matters only when matches are ALLOWED.
func _shake_budget(mode: int):
	if mode == Content.SHAKE_CASCADE_NONE:
		return 1  ## the initial post-Shake wave only
	if mode == Content.SHAKE_CASCADE_UNTIL_STABLE:
		return null  ## the existing infinite-settle safeguards apply
	var cap = state.config["max_cascade_steps"]
	return null if cap == null else int(cap) + 1


# ---------------------------------------------------------------------------
# Turn start
# ---------------------------------------------------------------------------

## Hacker phase start: resolve START_OF_TURN PASSIVEs, tick Hacker-owned
## countdowns oldest-first with each detonation fully resolving before the next
## tick, then open the pre-Sync Function window.
func start_player_phase() -> Array:
	var events: Array = []
	if state.has_winner():
		return events
	state.phase = Types.Phase.RESOLVING
	events.append({"t": Types.EVT.MSG, "text": "Turn %d — your move" % state.turn})
	_run_start_of_turn_passives(Types.Side.PLAYER, events)
	if not state.has_winner():
		_tick_countdowns(Types.Side.PLAYER, events)
	if not state.has_winner():
		state.phase = Types.Phase.PLAYER_PRE
	return _collect(events)


## Triggered PASSIVEs, strictly BEFORE countdown ticking.
##
## Each triggered Function resolves COMPLETELY — Effect, immediate Syncs,
## cascades, damage, charge — before the next begins. A battle reaching its
## terminal state part-way through stops rather than continuing to mutate.
func _run_start_of_turn_passives(active: Types.Side, events: Array) -> void:
	for inst in Passives.start_of_turn(state.identity, active):
		if state.has_winner():
			break
		if inst.passive["effect_type"] != PassiveEffects.CARRIER:
			continue
		var fn_id := str(inst.passive["function_id"])
		if fn_id == "":
			continue
		var fn := Content.function(fn_id)
		# The ACTIVE agent is the resolution owner even when a HOST caused the
		# trigger, so damage profile, charge routing, and owner-scoped PASSIVEs
		# all follow the agent whose turn is beginning. `cause` carries the
		# causal fact — which HOST, which PASSIVE — alongside it.
		# The ACTOR is the PASSIVE itself, not the source that supplied it: the
		# source travels separately in `cause`, and collapsing the two would
		# lose the distinction between "which PASSIVE acted" and "which HOST,
		# Hacker, System, or UPGRADE contributed it".
		#
		# The actor's name is the payload FUNCTION's name — the PASSIVE's
		# display text is presentation and never gameplay authority.
		_cast_actor(active, {
			"kind": Types.OwnerKind.PASSIVE,
			"id": inst.passive["id"],
			"name": fn["name"],
			"fn": fn,
			"cause": inst.cause(),
		}, events)


func _find_by_seq(seq: int) -> Vector2i:
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var t: Tile = state.board[y][x]
			if t != null and t.has_special() and t.special.seq == seq:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Ticks the acting side's armed overlays, oldest placement first.
##
## Placement order is snapshotted up front because an earlier detonation may
## slice a later overlay outright — as an ordinary Packet — in which case it is
## simply skipped rather than ticked at a stale coordinate.
func _tick_countdowns(owner: Types.Side, events: Array) -> void:
	var seqs: Array[int] = []
	for row in state.board:
		for t in row:
			if t != null and t.has_special() and t.special.countdown >= 0 and t.special.owner == owner:
				seqs.append(t.special.seq)
	seqs.sort()

	for seq in seqs:
		if state.has_winner():
			break
		var p := _find_by_seq(seq)
		if p.x < 0:
			continue  ## sliced earlier in this same tick
		var tile := state.tile_at(p)
		var sp: Tile.Special = tile.special
		sp.countdown -= 1
		events.append({"t": Types.EVT.COUNTDOWN, "p": p, "value": sp.countdown})
		if sp.countdown > 0:
			continue
		_deliver_countdown(p, events)


## Delivers an expired overlay's payload using the parameters STAMPED on it when
## it was armed.
##
## Adding a future delayed Effect means adding one branch here — not a new
## countdown framework.
func _deliver_countdown(p: Vector2i, events: Array) -> void:
	var tile := state.tile_at(p)
	if tile == null or not tile.has_special():
		return
	var sp: Tile.Special = tile.special
	# An overlay armed before `delivers` existed can only have been a bomb.
	var delivers := sp.delivers if sp.delivers != "" else Effects.BOMB

	if delivers == Effects.BUFF:
		# The countdown BECOMES a live Buff on the SAME Packet, using the
		# magnitude the arming Function stamped. Clearing the countdown is
		# exactly what makes it live — buff_bonus() counts it from this moment.
		sp.countdown = -1
		sp.delivers = ""
		events.append({"t": Types.EVT.SET_TILE, "p": p, "view": Resolve._tile_view(tile)})
		events.append({
			"t": Types.EVT.COUNTDOWN_DELIVERED, "side": sp.owner, "p": p,
			"effect_id": Effects.BUFF, "program_id": sp.program_id,
			"fn_id": sp.fn_id, "magnitude": sp.magnitude,
		})
		events.append({
			"t": Types.EVT.MSG,
			"text": "%s buff came online" % ("Hacker" if sp.owner == Types.Side.PLAYER else "System"),
		})
		return

	# Bombs already carry their own detonation telemetry.
	Resolve.resolve_detonation(state, p, events)


# ---------------------------------------------------------------------------
# Activation
# ---------------------------------------------------------------------------

## Only one targeted op is permitted per expanded plan and it must run first, so
## the plan's first op answers for the whole activation.
static func _function_target_kind(fn: Dictionary) -> Types.TargetKind:
	var plan: Array = fn["plan"]
	if plan.is_empty():
		return Types.TargetKind.NONE
	return plan[0]["target"]


## Target validity is checked BEFORE any charge is spent, so invalid input never
## resolves the Function and never consumes the pool.
func _target_satisfies(need: Types.TargetKind, target) -> bool:
	if need == Types.TargetKind.NONE:
		return true
	if target == null or target.get("kind", Types.TargetKind.NONE) != need:
		return false
	if need == Types.TargetKind.UNIT:
		var idx: int = target["idx"]
		return idx >= 0 and idx < (state.units[Types.Side.ENEMY] as Array).size()
	var p: Vector2i = target["p"]
	if not state.in_bounds(p):
		return false
	# Any occupied Packet is legal, overlays and neutrals included: an
	# immediately resolving Effect attaches no overlay, so the placement
	# restrictions that constrain countdown Bombs do not apply.
	return state.tile_at(p) != null


func fire_deck_function(target = null) -> Array:
	var events: Array = []
	if state.phase != Types.Phase.PLAYER_PRE:
		return events
	var deck := Content.deck(state.identity["deck_id"])
	var fn: Dictionary = deck["fn"]
	if state.deck_charge < int(fn["cost"]):
		return events
	if not _target_satisfies(_function_target_kind(fn), target):
		return events

	state.deck_charge -= int(fn["cost"])
	state.phase = Types.Phase.RESOLVING
	_cast_actor(Types.Side.PLAYER, {
		"kind": Types.OwnerKind.DECK, "id": deck["id"], "name": deck["name"], "fn": fn,
	}, events, target)
	if not state.has_winner():
		state.phase = Types.Phase.PLAYER_PRE
	return _collect(events)


## Fires a charged Program during the pre-Sync window.
func fire_program(idx: int, target = null) -> Array:
	var events: Array = []
	if state.phase != Types.Phase.PLAYER_PRE:
		return events
	var units: Array = state.units[Types.Side.PLAYER]
	if idx < 0 or idx >= units.size():
		return events

	var u: GameState.UnitState = units[idx]
	var prog := Content.program(u.program_id)
	if u.charge < int(prog["cost"]):
		return events
	if not _target_satisfies(_function_target_kind(prog["fn"]), target):
		return events

	u.charge -= int(prog["cost"])
	state.phase = Types.Phase.RESOLVING
	_cast_actor(Types.Side.PLAYER, {
		"kind": Types.OwnerKind.PROGRAM, "id": prog["id"], "name": prog["name"], "fn": prog["fn"],
	}, events, target)
	if not state.has_winner():
		state.phase = Types.Phase.PLAYER_PRE
	return _collect(events)


## Executes one activation: pay-once, then resolve the expanded payload plan
## left to right.
##
## The caller already spent the parent Function's cost; child costs are ignored.
## A legal fizzle in one op never stops later ops.
func _cast_actor(owner: Types.Side, actor: Dictionary, events: Array, target = null) -> void:
	var evt := {
		"t": Types.EVT.ABILITY, "side": owner, "owner_kind": actor["kind"],
		"program_id": actor["id"], "fn": actor["fn"]["id"], "name": actor["name"],
	}
	if actor.has("cause"):
		evt["cause"] = actor["cause"]
	events.append(evt)

	for op in (actor["fn"]["plan"] as Array):
		if state.has_winner():
			break
		_cast_op(owner, actor, op, events, target)


## Every occupied coordinate — the candidate pool for an immediately resolving
## Effect's RANDOM mode, which places no overlay and so accepts any Packet.
## Invoke a Boss mechanic payload Function at NO charge cost, attributed to the
## Boss itself (§7).
##
## The actor kind is `BOSS` and the actor ID is the Boss, so every event the
## payload emits carries Boss causal identity rather than a fake Program, a fake
## PASSIVE, or a fake System. The payload runs through the ordinary
## Function → Effect machinery — there is no Boss-specific SHAKE or ATTACK.
##
## Zero-cost means exactly that: the four Boss Program charge pools are
## untouched by CODESHATTER, DATABEND, and REBOOT.
func cast_boss_mechanic(fn_id: String, events: Array) -> void:
	var fn := Content.function(fn_id)
	if fn.is_empty():
		# The loader guarantees these resolve; defensive only.
		return
	_cast_actor(
		Types.Side.ENEMY,
		{
			"kind": Types.OwnerKind.BOSS,
			"id": Boss.boss_id(state),
			"name": str(fn["name"]),
			"fn": fn,
		},
		events,
	)


func _occupied_cells(exclude: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var p := Vector2i(x, y)
			if state.board[y][x] != null and not exclude.has(p):
				out.append(p)
	return out


## The effective Bomb footprint after PSV_BIGGER_BOMB.
##
## Each active instance advances ONE named step along the registry's canonical
## order, saturating at the largest pattern. Edge clipping is irrelevant to the
## step count: this operates on NAMES, not on how many cells survive the bounds.
func _effective_bomb_area(owner: Types.Side, authored: String, events: Array) -> String:
	var instances := Passives.affecting(state.identity, PassiveEffects.BIGGER_BOMB, owner)
	if instances.is_empty():
		return authored
	var upgraded := Areas.advance(authored, instances.size())
	if upgraded == authored:
		return authored  ## already saturated
	for inst in instances:
		events.append({
			"t": Types.EVT.PASSIVE, "side": owner, "cause": inst.cause(),
			"effect": inst.passive["effect_type"], "steps": 1,
		})
	return upgraded


## Drives the `quantity` deployments of an immediately resolving coordinate
## Effect — a targeted or random LineSlice or Bomb.
##
## ONE shared driver, so targeting, the per-activation exclusion rule, target
## logging, and post-slice settling cannot drift between the two Effects.
func _resolve_immediate_deployments(owner: Types.Side, actor: Dictionary, op: Dictionary, targeting: int, target, events: Array, run: Callable) -> int:
	var params: Dictionary = op["params"]
	var quantity: int = params.get("quantity", 1)
	# A RANDOM deployment never reuses a coordinate this same activation
	# already sliced.
	var used := {}
	var resolved := 0

	for i in quantity:
		if state.has_winner():
			break

		var p := Vector2i(-1, -1)
		if targeting == Content.TARGETING_TARGETED:
			# Targeted quantity is pinned at 1 and the coordinate was validated
			# before any charge was spent, so this is present and legal.
			if target != null and target.get("kind", Types.TargetKind.NONE) == Types.TargetKind.PACKET:
				p = target["p"]
		else:
			var pool := _occupied_cells(used)
			if not pool.is_empty():
				p = pool[state.rng.int_below(pool.size())]

		if p.x < 0:
			# A legal fizzle: no valid coordinate remains. The activation cost
			# is still spent and the attempt is recorded — not an error.
			events.append(_targeted_event(owner, actor, op, Vector2i(-1, -1), {}, "no valid target coordinate"))
			break

		used[p] = true
		var d: Dictionary = run.call(p)
		for c in (d.get("sliced", []) as Array):
			used[c] = true
		resolved += 1
		events.append(_targeted_event(owner, actor, op, p, d, ""))

		if d.get("settle", false) and not state.has_winner():
			Resolve.settle_after_effect(state, owner, d["cause"], str(actor["id"]), events)

	return resolved


func _targeted_event(owner: Types.Side, actor: Dictionary, op: Dictionary, p: Vector2i, d: Dictionary, reason: String) -> Dictionary:
	var evt := {
		"t": Types.EVT.TARGETED, "side": owner, "owner_kind": actor["kind"],
		"program_id": actor["id"], "fn_id": op["fn_id"], "effect_id": op["effect_id"],
		"target": null if p.x < 0 else p,
		"target_tile": d.get("target_tile", null),
		"sliced": d.get("sliced", []),
		"retained": d.get("retained", []),
		"direct_damage": d.get("direct_damage", 0),
		"direct_charge": d.get("direct_charge", 0),
		"resolved": not d.is_empty(),
	}
	if actor.has("cause"):
		evt["cause"] = actor["cause"]
	if d.has("dimension"):
		evt["dimension"] = d["dimension"]
	if reason != "":
		evt["reason"] = reason
	return evt


# ---------------------------------------------------------------------------
# Effect dispatch
# ---------------------------------------------------------------------------

## Coded Effect behaviour, selected by the stable Effect ID the data supplied.
##
## Exhaustive by design: adding an Effect means adding a branch here and a
## registered contract, never authoring a script in a spreadsheet cell.
func _cast_op(owner: Types.Side, actor: Dictionary, op: Dictionary, events: Array, target = null) -> void:
	var who := "Hacker" if owner == Types.Side.PLAYER else "System"
	var params: Dictionary = op["params"]

	match op["effect_id"]:
		Effects.BOMB:
			_cast_bomb(owner, actor, op, params, target, events)
		Effects.LINESLICE:
			_cast_line_slice(owner, actor, op, params, target, events)
		Effects.TRANSFORM:
			_cast_transform(owner, actor, op, params, who, events)
		Effects.BUFF:
			var placed := _place_specials({
				"type": Tile.Special.Type.BUFF, "owner": owner,
				"count": params.get("quantity", 1),
				"countdown": params.get("countdown", -1),
				"magnitude": params.get("magnitude", -1),
				"delivers": Effects.BUFF, "fn_id": op["fn_id"], "actor": actor,
			}, events)
			events.append(_op_event(owner, actor, op, placed > 0))
		Effects.SHIELD:
			var placed := _place_specials({
				"type": Tile.Special.Type.SHIELD, "owner": owner,
				"count": params.get("quantity", 1),
				"magnitude": params.get("magnitude", -1),
				"actor": actor,
			}, events)
			events.append(_op_event(owner, actor, op, placed > 0))
		Effects.ATTACK:
			_cast_attack(owner, actor, op, params, who, events)
		Effects.SHAKE:
			_cast_shake(owner, actor, op, params, who, events)
		Effects.DRAIN:
			_cast_drain(owner, actor, op, who, target, events)


func _op_event(owner: Types.Side, actor: Dictionary, op: Dictionary, resolved: bool, drained := -1) -> Dictionary:
	var evt := {
		"t": Types.EVT.OP, "side": owner, "owner_kind": actor["kind"],
		"program_id": actor["id"], "fn_id": op["fn_id"], "effect_id": op["effect_id"],
		"resolved": resolved,
	}
	if actor.has("cause"):
		evt["cause"] = actor["cause"]
	if drained >= 0:
		evt["drained"] = drained
	return evt


## A positive countdown deploys the established overlay; blank or zero resolves
## the blast immediately with no overlay at all.
func _cast_bomb(owner: Types.Side, actor: Dictionary, op: Dictionary, params: Dictionary, target, events: Array) -> void:
	var bp: Dictionary = params["bomb"]
	var countdown: int = params.get("countdown", 0)
	# Resolved ONCE here so the immediate and delayed branches use the same
	# answer. It changes AREA only: quantity, countdown, damage, targeting, and
	# the charge tuple are untouched.
	var effective_area := _effective_bomb_area(owner, str(params["areaPattern"]), events)

	if countdown > 0:
		# The UPGRADED pattern is stamped on the delayed object at ARMING time,
		# so a save, a resume, and a later detonation all agree even if the
		# supplying PASSIVE were to change in between.
		var placed := _place_specials({
			"type": Tile.Special.Type.BOMB, "owner": owner,
			"count": params.get("quantity", 1), "countdown": countdown,
			"area_pattern": effective_area,
			"deal_damage": bp["dealDamage"], "gain_charge": bp["gainCharge"],
			"delivers": Effects.BOMB, "fn_id": op["fn_id"], "actor": actor,
		}, events)
		events.append(_op_event(owner, actor, op, placed > 0))
		return

	var resolved := _resolve_immediate_deployments(
		owner, actor, op, bp["targeting"], target, events,
		func(p: Vector2i) -> Dictionary:
			var before := state.tile_at(p)
			var before_view = null if before == null else Resolve._tile_view(before)
			var cells_before: Array[Vector2i] = []
			for d in Areas.cells(effective_area):
				var n := p + d
				if state.in_bounds(n) and state.tile_at(n) != null:
					cells_before.append(n)
			var hp_before: int = state.hp[Types.opponent_of(owner)]

			Resolve.detonate_at(state, p, {
				"owner": owner, "area_pattern": effective_area,
				"program_id": actor["id"], "fn_id": op["fn_id"],
				"deal_damage": bp["dealDamage"], "gain_charge": bp["gainCharge"],
			}, events, false)

			return {
				"target_tile": before_view, "sliced": cells_before, "retained": [],
				"direct_damage": maxi(0, hp_before - state.hp[Types.opponent_of(owner)]),
				"settle": true, "cause": Types.DamageSource.BOMB,
			}
	)
	events.append(_op_event(owner, actor, op, resolved > 0))


## The whole row or column through the resolved coordinate is sliced as ONE
## direct operation, then the board settles and any resulting Syncs cascade
## normally under the initiator.
func _cast_line_slice(owner: Types.Side, actor: Dictionary, op: Dictionary, params: Dictionary, target, events: Array) -> void:
	var lp: Dictionary = params["line"]
	var resolved := _resolve_immediate_deployments(
		owner, actor, op, lp["targeting"], target, events,
		func(p: Vector2i) -> Dictionary:
			var before := state.tile_at(p)
			var before_view = null if before == null else Resolve._tile_view(before)
			var outcome := Resolve.resolve_line_slice(state, p, {
				"owner": owner, "params": lp,
				"program_id": actor["id"], "fn_id": op["fn_id"],
			}, events)
			return {
				"target_tile": before_view,
				"dimension": outcome["dimension"],
				"sliced": outcome["sliced"], "retained": outcome["retained"],
				"direct_damage": outcome["damage"], "direct_charge": outcome["charge"],
				"settle": true, "cause": Types.DamageSource.LINESLICE,
			}
	)
	events.append(_op_event(owner, actor, op, resolved > 0))


func _cast_transform(owner: Types.Side, actor: Dictionary, op: Dictionary, params: Dictionary, who: String, events: Array) -> void:
	var tp: Dictionary = params["transform"]
	var axis_target: Dictionary = params["axisTarget"]
	var axis_result: Dictionary = params["axisResult"]
	var quantity: int = params.get("quantity", 1)

	var outcome := Resolve.apply_transform(state, {
		"owner": owner, "params": tp,
		"axis_target": axis_target, "axis_result": axis_result,
		"quantity": quantity,
		"program_id": actor["id"], "fn_id": op["fn_id"],
	}, events)

	var cells: Array = outcome["cells"]
	var evt := {
		"t": Types.EVT.TRANSFORM, "side": owner, "owner_kind": actor["kind"],
		"program_id": actor["id"], "fn_id": op["fn_id"],
		"axis_target": axis_target["token"], "axis_result": axis_result["token"],
		"result_color": axis_result["color"], "result_shape": axis_result["shape"],
		"tier2_used": outcome["tier2_used"], "requested": quantity,
		"converted": cells.size(), "candidates": outcome["candidates"],
		"specials_retained": outcome["specials_retained"],
		"specials_destroyed": outcome["specials_destroyed"],
		"cells": cells, "resolved": not cells.is_empty(),
	}
	if actor.has("cause"):
		evt["cause"] = actor["cause"]
	events.append(evt)

	if cells.is_empty():
		# Normal System preflight withholds a Transform with no valid targets,
		# so reaching here means a mixed composite or a targeted player
		# activation: established legal-fizzle semantics apply rather than a
		# second rollback model.
		events.append(_op_event(owner, actor, op, false))
		events.append({"t": Types.EVT.MSG, "text": "%s %s found nothing to transform" % [who, actor["name"]]})
		return

	events.append(_op_event(owner, actor, op, true))
	var plural := "" if cells.size() == 1 else "s"
	events.append({"t": Types.EVT.MSG, "text": "%s %s transformed %d Packet%s" % [who, actor["name"], cells.size(), plural]})

	# Detection runs only AFTER every selected Packet has changed. Any Sync this
	# creates is owned by the activating side and resolves through the normal
	# owner-scoped pipeline. The budget matches an ordinary Sync, because the
	# created Sync IS the initial wave.
	Resolve.resolve_cascades(
		state, owner, events, _match_budget(), Types.DamageSource.TRANSFORM, {}, str(actor["id"]),
		{"stream_source": Types.ChargeStreamSource.EFFECT_TRANSFORM, "source_id": op["fn_id"]}
	)


func _cast_attack(owner: Types.Side, actor: Dictionary, op: Dictionary, params: Dictionary, who: String, events: Array) -> void:
	events.append({"t": Types.EVT.MSG, "text": "%s fired %s" % [who, actor["name"]]})
	var bonus := Resolve.buff_bonus(state, owner)
	var info := {
		"source": Types.DamageSource.ATTACKER,
		"label": "%s attack" % who,
		"fn_id": op["fn_id"],
		"buff_bonus": bonus,
	}
	# A boss actor owns no Program slot, so crediting its ID would invent a
	# phantom per-Program metrics row. The damage still lands in the ordinary
	# Function-damage bucket, attributed through fn_id.
	if actor["kind"] != Types.OwnerKind.BOSS:
		info["program_id"] = actor["id"]

	Resolve.deal_damage(state, Types.opponent_of(owner), int(params.get("damage", 0)) + bonus, info, events)
	events.append(_op_event(owner, actor, op, true))


func _cast_shake(owner: Types.Side, actor: Dictionary, op: Dictionary, params: Dictionary, who: String, events: Array) -> void:
	# Parameters were resolved and typed at startup; nothing is parsed here.
	var sp: Dictionary = params["shake"]
	# The activating side decides whose overlays the remove-enemy mode clears;
	# the other modes ignore it.
	#
	# The carrier is written back because `shake` REPLACES the board rather than
	# mutating it in place — it drafts a candidate arrangement and commits only
	# on success, which is what makes the fizzle leave the Datastream untouched.
	# Dropping the write-back silently discards a successful Shake.
	var carrier := {"board": state.board, "rng": state.rng, "next_id": state.next_id}
	var ok := BoardOps.shake(carrier, sp, owner)
	state.board = carrier["board"]
	state.next_id = carrier["next_id"]
	events.append({"t": Types.EVT.SHAKE, "side": owner, "resolved": ok})
	events.append(_op_event(owner, actor, op, ok))

	if not ok:
		# LEGAL FIZZLE: the Datastream is unchanged, the paid activation cost is
		# retained, and the attempt is recorded. Not an application error.
		events.append({"t": Types.EVT.MSG, "text": "%s %s fizzled — Datastream unchanged" % [who, actor["name"]]})
		return

	events.append({"t": Types.EVT.MSG, "text": "%s scrambled the Datastream" % who})
	events.append({"t": Types.EVT.BOARD, "grid": Resolve._grid_view(state.board)})

	if sp["matches"] == Content.SHAKE_ALLOW_MATCHES:
		# Every Sync created by the final Shake board resolves immediately and is
		# OWNED BY THE INITIATOR — never hardcoded as Hacker-owned — so
		# owner-scoped damage, charge, triggers, and cascades all apply normally.
		Resolve.resolve_cascades(state, owner, events, _shake_budget(sp["cascades"]), Types.DamageSource.MATCH, {})
	# matches PREVENTED: the completed arrangement already satisfies the stable
	# post-generation invariants, so no Sync wave begins.


## Drain targets PROGRAMS ONLY.
##
## The Deck Function's pool lives outside the unit list entirely, so it is
## structurally excluded from both the Hacker's target list and the System's
## candidate selection — it never affects the fully-charged, highest-charge, or
## highest-cost priority.
func _cast_drain(owner: Types.Side, actor: Dictionary, op: Dictionary, who: String, target, events: Array) -> void:
	var pick: GameState.UnitState = null

	if owner == Types.Side.PLAYER:
		# Player-chosen target: any System slot, valid even at zero charge.
		if target != null and target.get("kind", Types.TargetKind.NONE) == Types.TargetKind.UNIT:
			var enemy_units: Array = state.units[Types.Side.ENEMY]
			var idx: int = target["idx"]
			if idx >= 0 and idx < enemy_units.size():
				pick = enemy_units[idx]
	else:
		# Tiered System algorithm: fully-charged Programs first, then highest
		# raw charge, then highest activation cost, then a random tie-break.
		var charged: Array = []
		for u in (state.units[Types.Side.PLAYER] as Array):
			if u.charge > 0:
				charged.append(u)
		if not charged.is_empty():
			var full: Array = []
			for u in charged:
				if u.charge >= int(Content.program(u.program_id)["charge_cap"]):
					full.append(u)
			var pool: Array = full if not full.is_empty() else charged

			var max_charge := 0
			for u in pool:
				max_charge = maxi(max_charge, u.charge)
			var by_charge: Array = []
			for u in pool:
				if u.charge == max_charge:
					by_charge.append(u)
			pool = by_charge

			if pool.size() > 1:
				var max_cost := 0
				for u in pool:
					max_cost = maxi(max_cost, int(Content.program(u.program_id)["cost"]))
				var by_cost: Array = []
				for u in pool:
					if int(Content.program(u.program_id)["cost"]) == max_cost:
						by_cost.append(u)
				pool = by_cost

			pick = pool[state.rng.int_below(pool.size())]

	if pick == null:
		# Normally prevented by the withhold rule; reaching here means a mixed
		# composite, which is a legal fizzle.
		events.append(_op_event(owner, actor, op, false, 0))
		events.append({"t": Types.EVT.MSG, "text": "%s fired %s — nothing to drain" % [who, actor["name"]]})
		return

	# Every actual activation records the target's stable ID, its readiness at
	# target resolution, the charge before and after, and the cost that defines
	# "ready" — so readiness is auditable from the numbers rather than asserted.
	var target_prog := Content.program(pick.program_id)
	var drained := pick.charge
	var readiness := Types.Readiness.EMPTY
	if drained >= int(target_prog["cost"]):
		readiness = Types.Readiness.READY
	elif drained > 0:
		readiness = Types.Readiness.CHARGING
	pick.charge = 0

	var evt := _op_event(owner, actor, op, true, drained)
	evt["target_program_id"] = pick.program_id
	evt["target_readiness"] = readiness
	evt["target_charge_before"] = drained
	evt["target_charge_after"] = 0
	evt["target_cost"] = target_prog["cost"]
	events.append(evt)
	events.append({"t": Types.EVT.MSG, "text": "%s fired %s — drained %s" % [who, actor["name"], target_prog["name"]]})


# ---------------------------------------------------------------------------
# Overlay placement
# ---------------------------------------------------------------------------

## Converts up to `count` random standard, non-special Packets into overlays,
## preserving each Packet's colour and shape.
##
## Candidates are drawn WITHOUT replacement so two deployments never land on the
## same Packet. If fewer than `count` valid targets exist, place as many as
## possible — never hang, retry, or corrupt the Datastream. The charge is still
## spent. Returns the number placed.
func _place_specials(opts: Dictionary, events: Array) -> int:
	var candidates: Array[Vector2i] = []
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var t: Tile = state.board[y][x]
			if t != null and not t.is_neutral() and not t.has_special():
				candidates.append(Vector2i(x, y))

	var actor: Dictionary = opts["actor"]
	var countdown: int = opts.get("countdown", -1)
	var placed := 0

	for i in int(opts["count"]):
		if candidates.is_empty():
			break
		var idx := state.rng.int_below(candidates.size())
		var p: Vector2i = candidates[idx]
		candidates.remove_at(idx)

		var t := state.tile_at(p)
		var sp := Tile.Special.new()
		sp.type = opts["type"]
		sp.owner = opts["owner"]
		sp.countdown = countdown
		# An overlay is ARMED iff it carries a countdown, and then it must say
		# what it delivers. Bombs default to their own detonation.
		if countdown > 0:
			sp.delivers = str(opts.get("delivers", Effects.BOMB))
		sp.area_pattern = str(opts.get("area_pattern", ""))
		sp.magnitude = int(opts.get("magnitude", -1))
		sp.program_id = str(actor["id"])
		sp.fn_id = str(opts.get("fn_id", ""))
		sp.deal_damage = int(opts.get("deal_damage", -1))
		sp.gain_charge = int(opts.get("gain_charge", -1))
		sp.seq = state.next_seq
		state.next_seq += 1
		t.special = sp

		events.append({"t": Types.EVT.SET_TILE, "p": p, "view": Resolve._tile_view(t)})
		placed += 1

	# Bombs and shields are tracked per activation; buffs are not in that set.
	if opts["type"] != Tile.Special.Type.BUFF:
		events.append({
			"t": Types.EVT.PLACED, "side": opts["owner"], "owner_kind": actor["kind"],
			# A string for the same reason the Packet view uses one: `kind`
			# names an overlay here and a Packet kind there.
			"kind": Resolve.SPECIAL_TYPE_NAMES[opts["type"]],
			"count": placed, "program_id": actor["id"],
		})

	var who := "Hacker" if opts["owner"] == Types.Side.PLAYER else "System"
	var noun: String = ["bomb", "buff", "shield", "override"][opts["type"]]
	# An armed overlay is not yet doing anything, so the player-facing line says
	# so rather than claiming a live Buff was placed.
	var verb := "armed" if (countdown > 0 and opts["type"] == Tile.Special.Type.BUFF) else "placed"
	if placed == 0:
		events.append({"t": Types.EVT.MSG, "text": "No valid Packet — Effect wasted"})
	else:
		var what := "a %s" % noun if placed == 1 else "%d %ss" % [placed, noun]
		events.append({"t": Types.EVT.MSG, "text": "%s %s %s" % [who, verb, what]})
	return placed


## Ends the battle by dealing lethal damage through the ORDINARY damage path.
##
## Lives here rather than in the battle screen so it goes through `_collect`
## like everything else: a diagnostic that bypasses the funnel produces a result
## screen reporting zero damage for a battle that clearly had some, and the next
## bug report is about the metrics rather than about the shortcut. A diagnostic
## that reaches behind the rules eventually produces a bug report about the
## rules.
func force_outcome(loser: Types.Side) -> Array:
	var events: Array = []
	if state.has_winner():
		return events
	Resolve.deal_damage(state, loser, state.hp[loser] + 9999, {
		"source": Types.DamageSource.ATTACKER, "label": "debug",
	}, events)
	return _collect(events)


# ---------------------------------------------------------------------------
# The turn-ending Sync
# ---------------------------------------------------------------------------

## A swap producing no Sync reverts and does NOT consume the turn.
func attempt_swap(a: Vector2i, b: Vector2i, think_ms := -1, hint_shown := false) -> Dictionary:
	var events: Array = []
	if state.phase != Types.Phase.PLAYER_PRE:
		return {"matched": false, "events": _collect(events)}
	if absi(a.x - b.x) + absi(a.y - b.y) != 1:
		return {"matched": false, "events": _collect(events)}

	BoardOps.swap(state.board, a, b)
	events.append({"t": Types.EVT.SWAP, "a": a, "b": b})

	if MatchFinder.detect(state.board).is_empty():
		BoardOps.swap(state.board, a, b)
		events.append({"t": Types.EVT.REVERT, "a": a, "b": b})
		events.append({"t": Types.EVT.NO_MATCH})
		return {"matched": false, "events": _collect(events)}

	if think_ms >= 0:
		events.append({"t": Types.EVT.THINK_TIME, "ms": think_ms})
	if hint_shown:
		events.append({"t": Types.EVT.HINT_SHOWN})

	# Sync committed — no further Functions this turn.
	state.phase = Types.Phase.RESOLVING
	Resolve.resolve_cascades(state, Types.Side.PLAYER, events, _match_budget(), Types.DamageSource.MATCH, {})
	return {"matched": true, "events": _collect(events)}


# ---------------------------------------------------------------------------
# The enemy turn
# ---------------------------------------------------------------------------

## The placement pool shared with `_place_specials`: standard, non-special
## Packets. Kept in one place so eligibility and placement can never disagree.
func _placement_candidate_count() -> int:
	var n := 0
	for row in state.board:
		for t in row:
			if t != null and not t.is_neutral() and not t.has_special():
				n += 1
	return n


## A ready Function with nothing valid to act on must not be selected and must
## not spend charge.
##
## Re-evaluated per charged Program after each activation, because a previous
## Function may have changed the Datastream and thus the answer.
##
## It answers ONLY for Effects whose validity is cheaply and exactly knowable
## before paying. An Effect not named here is always eligible and keeps the
## established fires-then-legally-fizzles behaviour.
func _activation_eligibility(prog: Dictionary) -> Dictionary:
	var plan: Array = prog["fn"]["plan"]

	# A composite mixing Drain with other work still fires: only the wholly
	# useless case is withheld.
	if _plan_is_all_drain(plan):
		for u in (state.units[Types.Side.PLAYER] as Array):
			if u.charge > 0:
				return {"eligible": true, "reason": ""}
		return {"eligible": false, "reason": "no charged Hacker Program to drain"}

	for op in plan:
		var params: Dictionary = op["params"]
		match op["effect_id"]:
			Effects.TRANSFORM:
				# Eligibility is the ROW's own target/result grammar, including
				# the no-op exclusion, so a Function whose only reachable Packets
				# already match its result is withheld rather than fizzling.
				if Resolve.transform_candidate_count(state, {
					"axis_target": params["axisTarget"], "axis_result": params["axisResult"],
				}) == 0:
					return {"eligible": false, "reason": "no valid Packet to transform"}
			Effects.BUFF, Effects.SHIELD:
				if _placement_candidate_count() == 0:
					return {"eligible": false, "reason": "no valid Packet for placement"}
			Effects.BOMB:
				# Countdown Bombs need a placeable Packet; immediate Bombs need
				# only an occupied coordinate, which a live board always has.
				if int(params.get("countdown", 0)) > 0 and _placement_candidate_count() == 0:
					return {"eligible": false, "reason": "no valid Packet for placement"}

	return {"eligible": true, "reason": ""}


static func _plan_is_all_drain(plan: Array) -> bool:
	if plan.is_empty():
		return false
	for op in plan:
		if op["effect_id"] != Effects.DRAIN:
			return false
	return true


## The dynamic System Function phase.
##
## Readiness is recomputed after every FULLY resolved Function, so charge a
## Function creates — an Effect-made Sync, a detonation, a cascade — can make
## another Program ready and let it act in the SAME phase.
##
## Termination is guaranteed by the at-most-once rule, not by an iteration
## budget: each active Program may activate once per phase, so the loop runs at
## most once per Program however much charge is generated.
func _run_system_function_phase(events: Array) -> void:
	var activated := {}

	while true:
		if state.has_winner():
			return

		# Readiness, validity, and the unfired set are ALL recomputed here,
		# after the previous Function resolved completely.
		var choices: Array = []
		var withheld: Array = []
		var units: Array = state.units[Types.Side.ENEMY]

		for i in units.size():
			if activated.has(i):
				continue
			var u: GameState.UnitState = units[i]
			var prog := Content.program(u.program_id)
			if u.charge < int(prog["cost"]):
				continue  ## not ready — not a withhold
			var verdict := _activation_eligibility(prog)
			if verdict["eligible"]:
				choices.append({"u": u, "i": i})
			else:
				# Ready but with nothing to act on: the charge is PRESERVED,
				# not spent on a no-op.
				withheld.append({
					"t": Types.EVT.WITHHOLD, "side": Types.Side.ENEMY,
					"program_id": prog["id"], "fn_id": prog["fn"]["id"],
					"reason": verdict["reason"],
				})

		if choices.is_empty():
			# Withholds are reported only on the final pass, so a Program that
			# was blocked early and became eligible later is not miscounted.
			events.append_array(withheld)
			return

		# Pick at random among the currently eligible. PRG_SET order is
		# charge-routing priority and must NOT acquire implicit activation
		# priority, so this deliberately does not take the first eligible.
		var pick: Dictionary = choices[state.rng.int_below(choices.size())]
		var u: GameState.UnitState = pick["u"]
		var prog := Content.program(u.program_id)
		activated[pick["i"]] = true
		u.charge -= int(prog["cost"])
		_cast_actor(Types.Side.ENEMY, {
			"kind": Types.OwnerKind.PROGRAM, "id": prog["id"], "name": prog["name"], "fn": prog["fn"],
		}, events)


func run_enemy_phase() -> Array:
	var events: Array = []
	if state.has_winner():
		return events
	state.phase = Types.Phase.ENEMY
	events.append({"t": Types.EVT.MSG, "text": "System turn"})

	# The same ordering the Hacker's turn uses: START_OF_TURN PASSIVEs resolve
	# fully, THEN countdowns tick. A HOST carrier fires at the start of BOTH
	# agents' turns; the resolution owner here is the System.
	_run_start_of_turn_passives(Types.Side.ENEMY, events)
	if state.has_winner():
		return _collect(events)

	# The ODANSHAY threshold sits HERE — after HOST START_OF_TURN, before
	# countdowns (§12). There is no Boss identity PASSIVE layer between them:
	# the BOS schema has no PASSIVES column, deliberately.
	if Boss.is_boss_battle(state):
		Boss.resolve_threshold(self, events)
		if state.has_winner():
			return _collect(events)

	_tick_countdowns(Types.Side.ENEMY, events)
	if state.has_winner():
		return _collect(events)

	_run_system_function_phase(events)
	if state.has_winner():
		return _collect(events)

	if state.config["enemy_matching"]:
		# Deadlock prevention guarantees a move after every settle, so the
		# guard is defensive only. Move selection scores against the System's
		# own bindings.
		var mv := Bot.pick_move(state.board, state.config, Types.Side.ENEMY)
		if not mv.is_empty():
			BoardOps.swap(state.board, mv["a"], mv["b"])
			events.append({"t": Types.EVT.SWAP, "a": mv["a"], "b": mv["b"]})
			Resolve.resolve_cascades(state, Types.Side.ENEMY, events, _match_budget(), Types.DamageSource.MATCH, {})
			if state.has_winner():
				return _collect(events)
	else:
		# One flat engine-wide timer rate for every System Program — never a
		# per-Program hardcoded table.
		for u in (state.units[Types.Side.ENEMY] as Array):
			var wasted := Resolve.add_unit_charge(state, u, Constants.ENEMY_TIMER_CHARGE_RATE)
			if wasted > 0:
				events.append({
					"t": Types.EVT.CHARGE_WASTE, "side": Types.Side.ENEMY,
					"owner_kind": Types.OwnerKind.PROGRAM, "program_id": u.program_id, "amount": wasted,
				})

	if state.has_winner():
		return _collect(events)

	# The final action of a NON-TERMINAL Boss turn (§10). The winner check above
	# is what makes it non-terminal: a battle that already ended places nothing.
	if Boss.is_boss_battle(state):
		Boss.place_end_of_turn(self, events)
		if state.has_winner():
			return _collect(events)

	state.turn += 1
	return _collect(events)

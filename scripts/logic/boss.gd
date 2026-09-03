class_name Boss
extends RefCounted

## The Boss mechanic layer.
##
## ---------------------------------------------------------------------------
## What is deliberately NOT here
## ---------------------------------------------------------------------------
##
## Everything a Boss shares with a System stays in the ordinary enemy path:
## Program charge routing, the dynamic Function phase, readiness, Drain gating,
## countdowns, SPAM/Bomb/Shield/Attacker semantics, HOST effects, Hacker UPGRADE
## PASSIVEs, Reinforced Connection, cascades, and damage attribution. A Boss is
## an ordinary opponent to all of it (authorization §6).
##
## What this file adds is per-Boss ORCHESTRATION, and nothing else:
##
##   ODANSHAY   the Override overlay, the start-of-turn CODESHATTER/REBOOT
##              threshold, and the end-of-turn placement with DATABEND fallback;
##   RAHNDAHL   the start-of-turn 2^n Capacitor discharge, then one placement;
##   NEHBOCYET  the start-of-turn bottom-row clear, and the Logic Bomb that
##              detonates wherever a settle leaves it in the bottom row;
##   ECHOFALL   axis concealment on alternate phases, and BRAINSCRAMBLE on the
##              first invalid move made while concealed.
##
## Beta 0.4 §4 is explicit that these stay hardcoded here rather than becoming
## PSV rows or a data-driven trigger language. The one abstraction taken is
## `_place_one_special`, because CAPACITOR and LOGIC_BOMB genuinely share a
## placement rule — preferred pool, fallback pool, silent overwrite — and
## writing it twice would have been two chances to get the fallback wrong.
##
## Every payload that deals damage is an ordinary authored Function
## (`FNC_018`-`FNC_022`) invoked through the existing Function → Effect
## machinery at zero charge cost. The single exception is RAHNDAHL's discharge,
## which is not an authored Function and therefore calls `Resolve.deal_damage`
## directly — §6.2 requires it to be an ordinary damage instance, not a new
## pipeline, so it takes the same Shield ordering as everything else.
##
## ---------------------------------------------------------------------------
## Boss mechanics never touch route or setup RNG
## ---------------------------------------------------------------------------
##
## Override target choice and DATABEND's board randomisation both draw from the
## battle's GAMEPLAY stream (§10). The route stream belongs to the Run layer and
## is not reachable from a battle at all, which is what keeps a given gameplay
## seed reproducible regardless of how the Run arrived here.


## Whether this battle's opponent is a Boss. Every hook below no-ops otherwise,
## so an ordinary System battle costs one comparison per turn edge.
static func is_boss_battle(state: GameState) -> bool:
	return state.identity.get("opponent_kind", Types.OpponentKind.SYS) == Types.OpponentKind.BOS


static func boss_id(state: GameState) -> String:
	return str(state.identity.get("opponent_id", ""))


# ---------------------------------------------------------------------------
# Per-Boss dispatch
# ---------------------------------------------------------------------------

## Every Boss rule that runs at the START of the Boss phase.
##
## Called from `Game.run_enemy_phase` at the point ODANSHAY's threshold has
## always occupied: after HOST START_OF_TURN PASSIVEs, before countdowns. The
## Bosses added in 0.4 all specify "the beginning of every Boss phase", and that
## is the same instant.
##
## The phase counter advances here, before any rule reads it, so "phase 1" means
## the first Boss phase of the battle for every Boss.
static func start_of_turn(game: Game, events: Array) -> void:
	var state := game.state
	state.boss_phase += 1

	match boss_id(state):
		Content.BOSS_ODANSHAY:
			resolve_threshold(game, events)
		Content.BOSS_RAHNDAHL:
			rahndahl_start(game, events)
		Content.BOSS_NEHBOCYET:
			nehbocyet_start(game, events)
		Content.BOSS_ECHOFALL:
			echofall_start(game, events)


## Every Boss rule that runs at the END of a non-terminal Boss phase.
##
## Only ODANSHAY acts here. The others place at the start of their own phase,
## which is what their rules say and also what leaves the placement visible to
## the Hacker for a full turn before it matters.
static func end_of_turn(game: Game, events: Array) -> void:
	if boss_id(game.state) == Content.BOSS_ODANSHAY:
		place_end_of_turn(game, events)


# ---------------------------------------------------------------------------
# Shared placement primitive
# ---------------------------------------------------------------------------

## Whether this Packet carries an overlay the BOSS owns.
##
## "Boss special" means any ENEMY-owned overlay, not merely the Boss-mechanic
## types (director, 2026-09-02). So the SHIELD its own SHIELDER placed protects
## its Packet from CAPACITOR exactly as an OVERRIDE does. That is the definition
## `override_targets` has always used; stating it once keeps the three mechanics
## from drifting apart.
static func has_boss_special(t: Tile) -> bool:
	return t != null and t.has_special() and t.special.owner == Types.Side.ENEMY


## Installs one Boss overlay, preferring Packets that carry no Boss special.
##
## `cells` is the full eligible set. It is split here rather than by the caller
## so the two-pool rule exists in exactly one place: a Packet carrying a Boss
## special is reachable ONLY when nothing else is, and an empty eligible set
## fizzles rather than forcing a placement.
##
## Overwriting is SILENT for either pool — the replaced overlay does not
## activate, awards no charge and deals no damage. Returns the cell used, or
## `Vector2i(-1, -1)` when the placement fizzled.
static func _place_one_special(
	state: GameState, cells: Array, type: Tile.Special.Type, events: Array
) -> Vector2i:
	var clear: Array = []
	var occupied: Array = []
	for p in cells:
		if has_boss_special(state.board[p.y][p.x]):
			occupied.append(p)
		else:
			clear.append(p)

	var pool: Array = clear if not clear.is_empty() else occupied
	if pool.is_empty():
		return Vector2i(-1, -1)

	# Shuffled rather than indexed, matching Override placement: one draw from
	# the gameplay stream, never the route stream.
	var shuffled: Array = pool.duplicate()
	state.rng.shuffle(shuffled)
	var cell: Vector2i = shuffled[0]

	var t: Tile = state.board[cell.y][cell.x]
	var sp := Tile.Special.new()
	sp.type = type
	sp.owner = Types.Side.ENEMY
	sp.seq = state.next_seq
	state.next_seq += 1
	t.special = sp
	events.append({"t": Types.EVT.SET_TILE, "p": cell, "view": Resolve._tile_view(t)})
	return cell


# ---------------------------------------------------------------------------
# BOS_02 RAHNDAHL — the Capacitor discharge
# ---------------------------------------------------------------------------

## How many Capacitors are currently installed on the Datastream.
static func capacitor_count(state: GameState) -> int:
	var n := 0
	for row in state.board:
		for t in row:
			if t != null and t.has_special() and t.special.type == Tile.Special.Type.CAPACITOR:
				n += 1
	return n


## Packets a Capacitor may attach to: any NON-NEUTRAL Packet (§6.3).
##
## A Hacker special does not disqualify a Packet — a Capacitor may overwrite
## one, and does so WITHOUT the Packet counting as occupied, which is exactly
## the distinction `_place_one_special` draws between the two pools.
static func capacitor_targets(state: GameState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var t: Tile = state.board[y][x]
			if t != null and not t.is_neutral():
				out.append(Vector2i(x, y))
	return out


## §6.1 — discharge for `2^n`, then place one Capacitor.
##
## The tick fires on EVERY Boss phase including the first, where n is zero and
## the damage is 1. That is authored, not an off-by-one: the Boss opens by
## drawing blood, and the number the player is watching is already growing.
##
## Order is load-bearing. The count is taken BEFORE placement, so a Capacitor
## placed this phase first contributes next phase; and a lethal discharge
## returns before placing, per §13.
static func rahndahl_start(game: Game, events: Array) -> void:
	var state := game.state
	var count := capacitor_count(state)

	# The exponent is bounded by the board, but the shift is still clamped: 64
	# Capacitors would overflow a 64-bit int and wrap NEGATIVE, turning lethal
	# damage into healing. The clamp sits far above any survivable value, so it
	# changes no reachable outcome — it only refuses to be absurd.
	var damage := 1 << mini(count, 30)

	var rec := _mechanic(state, "CAPACITOR_DISCHARGE", count, count)
	rec["damage"] = damage
	events.append(rec)

	# Ordinary damage: Shield and permanent Shield reduce it under the existing
	# ordering. Attributed the way ODANSHAY's CODESHATTER already is — the
	# ATTACKER bucket with no program_id, since a Boss owns no Program slot —
	# rather than inventing a damage source and a metrics field for one rule.
	Resolve.deal_damage(state, Types.Side.PLAYER, damage, {
		"source": Types.DamageSource.ATTACKER,
		"label": "RAHNDAHL capacitor discharge",
	}, events)

	if state.has_winner():
		return

	var cell := _place_one_special(state, capacitor_targets(state), Tile.Special.Type.CAPACITOR, events)
	var after := capacitor_count(state)
	if cell.x < 0:
		events.append(_mechanic(state, "CAPACITOR_FIZZLED", count, after))
		return
	var placed := _mechanic(state, "CAPACITOR_PLACED", count, after)
	placed["cell"] = cell
	events.append(placed)


# ---------------------------------------------------------------------------
# The Override overlay
# ---------------------------------------------------------------------------

## How many Overrides are currently installed on the Datastream.
static func override_count(state: GameState) -> int:
	var n := 0
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var t: Tile = state.board[y][x]
			if t != null and t.has_special() and t.special.type == Tile.Special.Type.OVERRIDE:
				n += 1
	return n


## The valid Override target set (§9).
##
## A target is an occupied **standard** Packet — neutrals have no axes and can
## never carry an overlay — that does not already carry a BOSS-owned special.
##
## A Hacker-owned special does NOT disqualify a Packet: the Override replaces
## it. Boss-owned specials, including existing Overrides, are excluded and are
## never silently overwritten.
##
## Row-major order, so the candidate list is deterministic before the shuffle
## that picks from it.
static func override_targets(state: GameState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var t: Tile = state.board[y][x]
			if t == null or t.is_neutral():
				continue
			if t.has_special() and t.special.owner == Types.Side.ENEMY:
				continue
			out.append(Vector2i(x, y))
	return out


## Install Overrides at the chosen cells as ONE mechanic resolution.
##
## The Packet's colour and shape are RETAINED, which is why placement creates no
## Sync and resolves none: nothing about the board's match state changed. It
## also deals no damage and grants no charge — an Override is a marker, and its
## only effect is to count toward the threshold.
##
## Returns how many Hacker-owned overlays were replaced, for the mechanic
## record.
static func place_overrides(state: GameState, cells: Array, events: Array) -> int:
	var overwrote := 0
	for p in cells:
		var t: Tile = state.board[p.y][p.x]
		if t == null:
			continue
		# Installing over a Hacker-owned special replaces it through ordinary
		# overlay-replacement semantics. The removed overlay stops contributing
		# its effect and its countdown; the underlying Packet is untouched.
		if t.has_special():
			overwrote += 1
		var sp := Tile.Special.new()
		sp.type = Tile.Special.Type.OVERRIDE
		sp.owner = Types.Side.ENEMY
		sp.seq = state.next_seq
		state.next_seq += 1
		t.special = sp
		events.append({"t": Types.EVT.SET_TILE, "p": p, "view": Resolve._tile_view(t)})
	return overwrote


# ---------------------------------------------------------------------------
# Start of the Boss turn — the threshold
# ---------------------------------------------------------------------------

## §12 — at `override_count >= 15`, fire CODESHATTER, check for a terminal
## state, then REBOOT if the Hacker survived.
##
## The comparison is `>=`, never `== 15`: Overrides arrive three at a time, so
## an exact test would step straight over the threshold.
##
## A check that finds nothing emits NO event, which keeps a quiet turn quiet in
## the log.
##
## This is not a phase transition. Overrides accumulate again afterwards and the
## threshold can fire on a later turn.
static func resolve_threshold(game: Game, events: Array) -> void:
	var state := game.state
	var count := override_count(state)
	if count < Content.OVERRIDE_THRESHOLD:
		return

	events.append(_mechanic(state, "THRESHOLD", count, count))

	# CODESHATTER is ordinary Function damage: it takes the normal Function
	# damage modifiers, is reduced by Shield and permanent Shield under the
	# existing ordering, and is NOT suppressed by Reinforced Connection — that
	# suppresses base Sync damage only.
	game.cast_boss_mechanic(Content.FN_CODESHATTER, events)

	# If CODESHATTER defeated the Hacker the battle is over: REBOOT does not
	# fire, countdowns do not tick, Boss Programs do not activate, and no
	# end-of-turn Overrides are placed.
	if state.has_winner():
		return

	# REBOOT wipes the Datastream as though a new battle began — every Packet
	# regenerated, every overlay removed (the accumulated Overrides with them),
	# and under the prevent-matches invariant the resulting arrangement contains
	# no Sync at all (D-032). The turn then continues from countdowns.
	game.cast_boss_mechanic(Content.FN_REBOOT, events)


# ---------------------------------------------------------------------------
# End of the Boss turn — placement, with DATABEND as the fallback
# ---------------------------------------------------------------------------

## §10 — the final action of every non-terminal Boss turn: place exactly three
## Overrides, or place NONE and DATABEND to make room.
##
## THE LOOP BOUND IS THE SHIPPED ALPHA'S, and the off-by-one matters:
## `attempt` runs 0..RETRY_LIMIT inclusive, which is **6 capacity checks and 5
## DATABEND activations** — the final iteration abandons rather than casting.
## A loop written `for i in RETRY_LIMIT` gives 5 checks and 4 DATABENDs.
##
## "Three or none" is deliberate. Placing one or two when three are unavailable
## would let the Boss creep toward the threshold from a board that cannot
## support the mechanic, which is the situation DATABEND exists to fix.
static func place_end_of_turn(game: Game, events: Array) -> void:
	var state := game.state
	for attempt in range(Content.OVERRIDE_DATABEND_RETRY_LIMIT + 1):
		if state.has_winner():
			return

		var targets := override_targets(state)
		var before := override_count(state)

		if targets.size() >= Content.OVERRIDE_PLACEMENT_COUNT:
			# Three DISTINCT targets, chosen from the GAMEPLAY stream, and all
			# chosen BEFORE any mutation so no placement can influence a later
			# choice.
			var pool: Array = targets.duplicate()
			state.rng.shuffle(pool)
			var cells := pool.slice(0, Content.OVERRIDE_PLACEMENT_COUNT)
			var overwrote := place_overrides(state, cells, events)
			var rec := _mechanic(state, "OVERRIDE_PLACED", before, override_count(state))
			rec["placed"] = cells.size()
			rec["cells"] = cells
			rec["overwrote"] = overwrote
			events.append(rec)
			return

		# Insufficient capacity: place NOTHING, then DATABEND.
		var short := _mechanic(state, "INSUFFICIENT_TARGETS", before, before)
		short["available"] = targets.size()
		short["attempt"] = attempt + 1
		events.append(short)

		if attempt == Content.OVERRIDE_DATABEND_RETRY_LIMIT:
			# The cap is reached. Place none and let the turn end cleanly —
			# never hang, recurse, or leave a partial placement. Recorded so the
			# condition is visible if it ever fires; with current content it
			# realistically does not.
			var done := _mechanic(state, "PLACEMENT_ABANDONED", before, before)
			done["available"] = targets.size()
			done["attempt"] = attempt + 1
			events.append(done)
			return

		# DATABEND resolves COMPLETELY — its Syncs, cascades, damage, and charge
		# are ordinary Boss-side output — before capacity is recomputed.
		game.cast_boss_mechanic(Content.FN_DATABEND, events)


static func _mechanic(state: GameState, kind: String, before: int, after: int) -> Dictionary:
	return {
		"t": Types.EVT.BOSS_MECHANIC,
		"boss_id": boss_id(state),
		"kind": kind,
		"count_before": before,
		"count_after": after,
	}


# ---------------------------------------------------------------------------
# BOS_03 NEHBOCYET — the bottom row and the Logic Bomb
# ---------------------------------------------------------------------------

## §7.1 — clear the bottom row, let the board settle, then arm the top row.
##
## The clear is Packet REMOVAL, not overlay clearing, and it is deliberately
## inert: no damage, no charge, and overlays on the removed Packets do not
## activate, because they are cleared rather than destroyed. Whatever the refill
## then produces IS ordinary — a Sync formed by falling Packets pays out
## normally, which is why the settle goes through `settle_after_effect` instead
## of a private path.
##
## Placement happens AFTER the settle so a bomb is never armed into a board that
## is still moving, and so the bomb the player sees at the top is the one they
## have a turn to deal with.
static func nehbocyet_start(game: Game, events: Array) -> void:
	var state := game.state
	var y := Constants.BOARD_HEIGHT - 1

	var cleared: Array[Vector2i] = []
	for x in Constants.BOARD_WIDTH:
		if state.board[y][x] != null:
			cleared.append(Vector2i(x, y))

	var rec := _mechanic(state, "BOTTOM_ROW_CLEARED", cleared.size(), 0)
	rec["cells"] = cleared
	events.append(rec)

	if not cleared.is_empty():
		events.append({"t": Types.EVT.DESTROY, "cells": cleared})
		for p in cleared:
			state.board[p.y][p.x] = null
		# Ordinary board pipeline. Any Logic Bomb that lands in the bottom row
		# as a result detonates through the post-settle hook, not from here.
		Resolve.settle_after_effect(state, Types.Side.ENEMY, Types.DamageSource.MATCH, "", events, game)

	if state.has_winner():
		return

	var cell := _place_one_special(state, logic_bomb_targets(state), Tile.Special.Type.LOGIC_BOMB, events)
	if cell.x < 0:
		events.append(_mechanic(state, "LOGIC_BOMB_FIZZLED", 0, 0))
		return
	var placed := _mechanic(state, "LOGIC_BOMB_PLACED", 0, 1)
	placed["cell"] = cell
	events.append(placed)


## Top-row Packets a Logic Bomb may be armed on (§7.2).
##
## Neutrals are excluded. §7.2 does not say so explicitly, but every other
## placement rule in the game does — Override skips them, and §6.3 states it
## outright for Capacitor — and a bomb riding a Packet that can never be Synced
## would reach the bottom by gravity alone. Recorded in the handback as the one
## place this build read past the authorization's silence.
static func logic_bomb_targets(state: GameState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in Constants.BOARD_WIDTH:
		var t: Tile = state.board[0][x]
		if t != null and not t.is_neutral():
			out.append(Vector2i(x, 0))
	return out


## Every Logic Bomb currently sitting in the bottom row, left to right.
##
## Left-to-right is the determinism §7.4 asks for: several bombs can qualify
## from one settle, and the order they fire in changes which of them is still
## alive when the Hacker dies.
static func settled_bombs(state: GameState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var y := Constants.BOARD_HEIGHT - 1
	for x in Constants.BOARD_WIDTH:
		var t: Tile = state.board[y][x]
		if t != null and t.has_special() and t.special.type == Tile.Special.Type.LOGIC_BOMB:
			out.append(Vector2i(x, y))
	return out


## The invariant: a settled board may not retain a Logic Bomb in the bottom row.
##
## Called from the end of `Resolve.resolve_cascades`, so it applies to movement
## from ANY source rather than to a list of sources someone has to remember to
## extend. Non-NEHBOCYET battles leave after one string comparison.
##
## Each qualifying bomb takes its ENTIRE carrier Packet with it. That removal is
## inert — no damage, no charge, no special activation — and the 40 damage comes
## solely from FNC_021, once per bomb, through ordinary Function resolution and
## therefore ordinary Shield interaction.
static func resolve_settled_bombs(game: Game, events: Array) -> void:
	var state := game.state
	# The chain is owned by the outermost call. Settling inside the loop below
	# re-enters here, and without this the "repeat until stable" would become an
	# unbounded recursion instead of a loop.
	if state.bomb_chain_active:
		return
	if not is_boss_battle(state) or boss_id(state) != Content.BOSS_NEHBOCYET:
		return

	state.bomb_chain_active = true
	while not state.has_winner():
		var cells := settled_bombs(state)
		if cells.is_empty():
			break

		var rec := _mechanic(state, "LOGIC_BOMB_TRIGGERED", cells.size(), 0)
		rec["cells"] = cells
		events.append(rec)

		# Carriers are removed BEFORE any Function fires, so a bomb cannot be
		# destroyed by another bomb's damage and skip its own detonation.
		events.append({"t": Types.EVT.DESTROY, "cells": cells})
		for p in cells:
			state.board[p.y][p.x] = null

		for _p in cells:
			if state.has_winner():
				break
			game.cast_boss_mechanic(Content.FN_LOGICBOMBEXPLODE, events)

		if state.has_winner():
			break

		# Re-settle, then look again. The recursive call this makes finds the
		# latch set and returns immediately, leaving the loop in charge.
		Resolve.settle_after_effect(state, Types.Side.ENEMY, Types.DamageSource.MATCH, "", events, game)

	state.bomb_chain_active = false


# ---------------------------------------------------------------------------
# BOS_04 ECHOFALL — axis concealment
# ---------------------------------------------------------------------------

## §8.1 — conceal on Boss phases 1, 3, 5 …
##
## Read off the Boss-phase counter rather than `turn` so the cadence keeps
## meaning what it says if turn accounting ever changes, and so a resumed save
## continues the same alternation (§8.5).
static func echofall_start(game: Game, events: Array) -> void:
	var state := game.state
	if state.boss_phase % 2 == 0:
		return

	# One draw from the GAMEPLAY stream, like every other Boss choice.
	state.hidden_axis = Types.ConcealAxis.COLOR if state.rng.int_below(2) == 0 else Types.ConcealAxis.SHAPE

	var rec := _mechanic(state, "AXIS_CONCEALED", -1, state.hidden_axis)
	rec["axis"] = Types.CONCEAL_AXIS_NAMES[state.hidden_axis]
	events.append(rec)


static func is_concealed(state: GameState) -> bool:
	return state.hidden_axis != -1


## Ends concealment, whatever ended it. Emits nothing when nothing was hidden,
## so an ordinary turn stays quiet in the log.
static func reveal(state: GameState, events: Array) -> void:
	if state.hidden_axis == -1:
		return
	var rec := _mechanic(state, "AXIS_REVEALED", state.hidden_axis, -1)
	rec["axis"] = Types.CONCEAL_AXIS_NAMES[state.hidden_axis]
	state.hidden_axis = -1
	events.append(rec)


## §8.4 — the Hacker's first board attempt while an axis is hidden.
##
## Called from `Game.attempt_swap` for a swap that produced no Sync. The board
## reveals either way; the punishment is only for the attempt made BLIND, which
## is why reveal happens here and later invalid attempts in the same phase pass
## through untouched.
##
## The move is not committed and the Hacker's board move is not consumed — an
## invalid swap already costs nothing, and §8.4 is explicit that BRAINSCRAMBLE
## does not change that.
static func echofall_punish_blind_move(game: Game, events: Array) -> void:
	var state := game.state
	if not is_boss_battle(state) or boss_id(state) != Content.BOSS_ECHOFALL:
		return
	if not is_concealed(state):
		return

	events.append(_mechanic(state, "BRAINSCRAMBLE", state.hidden_axis, -1))
	game.cast_boss_mechanic(Content.FN_BRAINSCRAMBLE, events)
	reveal(state, events)

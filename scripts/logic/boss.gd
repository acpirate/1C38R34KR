class_name Boss
extends RefCounted

## ODANSHAY's mechanic layer — the only Boss-specific gameplay in the build.
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
## This file adds exactly three things:
##
##   1. the Override overlay, its target rules, and its placement;
##   2. the start-of-turn threshold that fires CODESHATTER then REBOOT;
##   3. the end-of-turn placement attempt, with DATABEND as its fallback.
##
## The three payloads are ordinary authored Functions (`FNC_018/019/020`)
## invoked through the existing Function → Effect machinery at zero charge cost.
## There is no bespoke SHAKE and no bespoke ATTACK here (§7).
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

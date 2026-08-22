class_name Bot
extends RefCounted

## Side-agnostic move selection.
##
## Drives the System's turn when enemy matching is on, and the headless harness
## player. Deliberately a WEAK tier: prefer any move producing a 4+ Sync, else
## the first valid move. No look-ahead and no board evaluation — the bot is a
## floor indicator, not an opponent.
##
## Every scan is row-major with east and south neighbours only, and returns the
## FIRST qualifying move. That determinism is load-bearing: the differential
## harness drives whole battles through this, so a different scan order picks a
## different move and diverges everything after it.
##
## Consumes NO RNG.

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]


## Prefer a move producing a 4+ Sync — which includes every line clear — and
## otherwise take the first valid move found.
static func find_move(board: Array) -> Dictionary:
	var first_valid := {}
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			for d in DIRS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= Constants.BOARD_WIDTH or ny >= Constants.BOARD_HEIGHT:
					continue
				var a := Vector2i(x, y)
				var b := Vector2i(nx, ny)

				BoardOps.swap(board, a, b)
				var matches := MatchFinder.detect(board)
				var makes_big := false
				for m in matches:
					if m.length >= 4:
						makes_big = true
						break
				BoardOps.swap(board, a, b)

				if makes_big:
					return {"a": a, "b": b}
				if not matches.is_empty() and first_valid.is_empty():
					first_valid = {"a": a, "b": b}
	return first_valid


## Charge-aware tier for Reinforced Connection.
##
## Prefer-4 is a DAMAGE heuristic, and under suppressed base Sync damage it
## optimizes for a quantity that barely exists. This scores each valid move by
## how many synced Packets feed the ACTING side's Program bindings — it matches
## for CHARGE instead.
##
## Bindings differ per side, so the scorer reads the acting side's resolved
## Programs from loaded content rather than a table.
static func find_charge_move(board: Array, side: Types.Side) -> Dictionary:
	var bound_colors := {}
	var bound_shapes := {}
	for p in Content.programs_for(side):
		for c in (p["colors"] as Array):
			bound_colors[c] = true
		for s in (p["shapes"] as Array):
			bound_shapes[s] = true

	var best := {}
	var best_score := -1

	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			for d in DIRS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= Constants.BOARD_WIDTH or ny >= Constants.BOARD_HEIGHT:
					continue
				var a := Vector2i(x, y)
				var b := Vector2i(nx, ny)

				BoardOps.swap(board, a, b)
				var matches := MatchFinder.detect(board)
				var score := -1
				if not matches.is_empty():
					score = 0
					# Deduplicated across Syncs: a Packet in two overlapping
					# Syncs is one Packet of charge, not two.
					var seen := {}
					for m in matches:
						for c in m.cells:
							if seen.has(c):
								continue
							seen[c] = true
							var t: Tile = board[c.y][c.x]
							if t == null or t.is_neutral():
								continue
							if bound_colors.has(t.color):
								score += 1
							if bound_shapes.has(t.shape):
								score += 1
				BoardOps.swap(board, a, b)

				# Strictly greater, so ties keep the earliest move in scan order.
				if score > best_score:
					best_score = score
					best = {"a": a, "b": b}

	return best if best_score >= 0 else {}


## Config-aware selection. The charge-aware tier applies only when Reinforced
## Connection is on AND its sub-option has not been switched back to the classic
## heuristic.
static func pick_move(board: Array, config: Dictionary, side := Types.Side.PLAYER) -> Dictionary:
	if config["reinforced_connection"] and config["reinforced_charge_aware_bot"]:
		return find_charge_move(board, side)
	return find_move(board)


## Hint helper: a move producing a 4+ Sync, if one exists. The hint system shows
## nothing otherwise rather than suggesting a weak move.
static func find_hint_move(board: Array) -> Dictionary:
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			for d in DIRS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= Constants.BOARD_WIDTH or ny >= Constants.BOARD_HEIGHT:
					continue
				var a := Vector2i(x, y)
				var b := Vector2i(nx, ny)
				BoardOps.swap(board, a, b)
				var big := false
				for m in MatchFinder.detect(board):
					if m.length >= 4:
						big = true
						break
				BoardOps.swap(board, a, b)
				if big:
					return {"a": a, "b": b}
	return {}

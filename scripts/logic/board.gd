class_name BoardOps
extends RefCounted

## Board generation, swaps, deadlock detection, and the two reshuffle paths.
##
## RNG CONSUMPTION ORDER IS LOAD-BEARING. Every draw here must happen in exactly
## the same order as the alpha, or the same seed produces a different board and
## every downstream event diverges. That is the whole basis of the differential
## gate, so the sequencing below is deliberate rather than incidental.


## Carries the RNG and the monotonic Packet-id counter through generation.
class TileGen extends RefCounted:
	var rng: Rng
	var next_id := 0

	func _init(r: Rng, start_id: int) -> void:
		rng = r
		next_id = start_id


## Draws one Packet.
##
## Consumption order, which must not change: the id is taken first and does not
## touch the RNG; then ONE draw decides neutrality; and only if the Packet is
## standard are two further draws taken — colour, then shape.
static func random_tile(gen: TileGen) -> Tile:
	var id := gen.next_id
	gen.next_id += 1
	if gen.rng.next() < Constants.NEUTRAL_TILE_DROP_RATE:
		return Tile.neutral(id)
	var c := gen.rng.int_below(Constants.COLOR_COUNT)
	var s := gen.rng.int_below(Constants.SHAPE_COUNT)
	return Tile.standard(id, c, s)


static func empty_board() -> Array:
	var b: Array = []
	for y in Constants.BOARD_HEIGHT:
		var row: Array = []
		row.resize(Constants.BOARD_WIDTH)
		b.append(row)
	return b


## Would placing `t` at (x, y) complete a run of three with the two Packets
## already placed to its left or above it?
##
## Used during row-major fills to avoid pre-existing Syncs, so it only ever
## looks backwards — the cells ahead are not filled yet.
static func completes_run(board: Array, x: int, y: int, t: Tile) -> bool:
	if x >= 2 and _is_triple(board[y][x - 1], board[y][x - 2], t):
		return true
	if y >= 2 and _is_triple(board[y - 1][x], board[y - 2][x], t):
		return true
	return false


static func _is_triple(a: Tile, b: Tile, t: Tile) -> bool:
	if a == null or b == null:
		return false
	if t.is_neutral():
		return a.is_neutral() and b.is_neutral()
	if a.is_neutral() or b.is_neutral():
		return false
	if a.color == t.color and b.color == t.color:
		return true
	if a.shape == t.shape and b.shape == t.shape:
		return true
	return false


## The opening Datastream: no pre-existing Syncs, and at least one legal move.
##
## A dead starting board would only trigger the automatic reshuffle anyway, so
## the guarantee is made here directly rather than left to the first turn.
static func generate_initial(gen: TileGen) -> Array:
	for attempt in 1000:
		var board := empty_board()
		for y in Constants.BOARD_HEIGHT:
			for x in Constants.BOARD_WIDTH:
				var t := random_tile(gen)
				var guard := 0
				while completes_run(board, x, y, t) and guard < 200:
					t = random_tile(gen)
					guard += 1
				board[y][x] = t
		if MatchFinder.detect(board).is_empty() and has_any_valid_move(board):
			return board
	push_error("failed to generate a valid initial board")
	return empty_board()


static func swap(board: Array, a: Vector2i, b: Vector2i) -> void:
	var t = board[a.y][a.x]
	board[a.y][a.x] = board[b.y][b.x]
	board[b.y][b.x] = t


## Brute-force deadlock scan: tentatively swap every Packet with its east and
## south neighbour, test for a Sync, revert. Returns the first move found, in
## row-major order — deterministic, which matters because the bot consumes it.
static func find_valid_move(board: Array) -> Dictionary:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			for d in dirs:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= Constants.BOARD_WIDTH or ny >= Constants.BOARD_HEIGHT:
					continue
				var a := Vector2i(x, y)
				var b := Vector2i(nx, ny)
				swap(board, a, b)
				var ok := not MatchFinder.detect(board).is_empty()
				swap(board, a, b)
				if ok:
					return {"a": a, "b": b}
	return {}


static func has_any_valid_move(board: Array) -> bool:
	return not find_valid_move(board).is_empty()


## The automatic deadlock reshuffle: a PERMUTATION.
##
## Board composition is preserved exactly and only positions change. No free
## composition reroll on deadlock, and any Packet-converting investment survives
## it. Overlays persist with all their data because these are the same Tile
## objects, merely relocated.
##
## Contract: at least one legal move, and no pre-existing Sync — hence the
## permute-until-valid loop.
static func reshuffle(state: Dictionary) -> void:
	var tiles: Array[Tile] = []
	for row in (state["board"] as Array):
		for t in row:
			if t != null:
				tiles.append(t)

	for attempt in 1000:
		state["rng"].shuffle(tiles)
		var board := empty_board()
		var i := 0
		for y in Constants.BOARD_HEIGHT:
			for x in Constants.BOARD_WIDTH:
				board[y][x] = tiles[i]
				i += 1
		if MatchFinder.detect(board).is_empty() and has_any_valid_move(board):
			state["board"] = board
			return

	# Fallback for a composition with no arrangement we could find —
	# pathologically skewed, effectively impossible at 64 Packets. Regenerate the
	# non-special Packets with a constrained fill rather than softlock.
	var specials: Array[Tile] = []
	for t in tiles:
		if t.has_special():
			specials.append(t)

	for attempt in 1000:
		var board := empty_board()
		var cells: Array[Vector2i] = []
		for y in Constants.BOARD_HEIGHT:
			for x in Constants.BOARD_WIDTH:
				cells.append(Vector2i(x, y))
		state["rng"].shuffle(cells)
		for i in specials.size():
			var p: Vector2i = cells[i]
			board[p.y][p.x] = specials[i]

		var gen := TileGen.new(state["rng"], state["next_id"])
		for y in Constants.BOARD_HEIGHT:
			for x in Constants.BOARD_WIDTH:
				if board[y][x] != null:
					continue
				var t := random_tile(gen)
				var guard := 0
				while completes_run(board, x, y, t) and guard < 200:
					t = random_tile(gen)
					guard += 1
				board[y][x] = t
		state["next_id"] = gen.next_id

		if MatchFinder.detect(board).is_empty() and has_any_valid_move(board):
			state["board"] = board
			return

	push_error("failed to produce a valid reshuffle")


## EFFECT_SHAKE. One authoritative implementation, driven entirely by the typed
## parameters resolved from Function data.
##
## Returns false for the LEGAL FIZZLE: the Datastream is left completely
## unchanged, the caller keeps the paid activation cost, and nothing about RNG
## ownership or turn state is corrupted. All work happens on a scratch
## arrangement and is committed only on success.
##
## `owner` is the ACTIVATING side, needed only by the remove-enemy-overlays
## mode; the other modes are ownership-blind.
static func shake(state: Dictionary, params: Dictionary, owner: Types.Side) -> bool:
	var cells: Array[Vector2i] = []
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			cells.append(Vector2i(x, y))

	var replace: bool = params["boardComposition"] == Content.SHAKE_REPLACE
	var prevent_matches: bool = params["matches"] == Content.SHAKE_PREVENT_MATCHES
	var special_mode: int = params["specialGems"]

	var existing: Array[Tile] = []
	for row in (state["board"] as Array):
		for t in row:
			if t != null:
				existing.append(t)

	# A Shake over a board with holes is not a legal starting point — Shake is
	# only reachable from a settled Datastream. Fizzle rather than corrupt.
	if existing.size() != Constants.BOARD_WIDTH * Constants.BOARD_HEIGHT:
		return false

	for attempt in 1000:
		var draft := empty_board()
		var draft_next_id: int = state["next_id"]

		if replace:
			# REPLACE is not unconditionally destructive: a Packet whose overlay
			# this Shake RETAINS keeps both its overlay and its underlying axes,
			# at its own coordinate. That is what lets a Shake randomize the
			# non-special Packets and clear only the enemy's overlays, instead of
			# silently wiping the activating side's own board investment.
			var gen := TileGen.new(state["rng"], draft_next_id)
			for p in cells:
				var cur: Tile = state["board"][p.y][p.x]
				draft[p.y][p.x] = cur if _retains(cur, special_mode, owner) else random_tile(gen)
			draft_next_id = gen.next_id
		else:
			var order := existing.duplicate()
			state["rng"].shuffle(order)
			var i := 0
			for p in cells:
				draft[p.y][p.x] = order[i]
				i += 1

		# Under REARRANGE a retained overlay moves with its Packet automatically,
		# because these are the same objects relocated; a removed one is
		# stripped and the ordinary Packet kept. Under REPLACE the non-retained
		# cells were regenerated above and carry no prior state to strip.
		if not replace:
			for p in cells:
				var t: Tile = draft[p.y][p.x]
				if t != null and t.has_special() and not _retains(t, special_mode, owner):
					t.special = null

		# When matches are PREVENTED the result must satisfy the normal
		# post-generation invariants so no wave begins. When they are ALLOWED the
		# resulting Syncs are meant to resolve, so a pre-existing match is the
		# desired state and playability is re-established by the settle.
		var ok := true
		if prevent_matches:
			ok = MatchFinder.detect(draft).is_empty() and has_any_valid_move(draft)

		if ok:
			state["board"] = draft
			state["next_id"] = draft_next_id
			return true

		# REPLACE burns fresh ids per attempt; keep the counter monotonic so
		# Packet identity never repeats across attempts.
		state["next_id"] = draft_next_id

	return false  ## legal fizzle — board untouched


static func _retains(t: Tile, special_mode: int, owner: Types.Side) -> bool:
	if t == null or not t.has_special():
		return false
	if special_mode == Content.SHAKE_REMOVE_SPECIALS:
		return false
	if special_mode == Content.SHAKE_REMOVE_ENEMY_SPECIALS:
		return t.special.owner == owner
	return true  ## SHAKE_RETAIN_SPECIALS

extends RefCounted

## Board generation and Sync detection parity.
##
## This is the first point where RNG consumption ORDER becomes observable. The
## Packet distribution could match perfectly while the draw sequence differs,
## and every downstream event would then diverge from the first turn.
##
## The fixture pins the sequence itself: the exact board, the id counter, and
## the RNG state AFTER generation. Because generation redraws on a completed run
## and restarts entirely on a bad result, the number of draws consumed depends
## on the rejection path — a port that redraws at a different point lands on a
## different board and a different id counter.

const FIXTURE := "res://tests/fixtures/board.json"


func run(t: TestCase) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		t.group("board")
		t.check("fixture is readable", false)
		return
	var fixture = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(fixture) != TYPE_DICTIONARY:
		t.group("board")
		t.check("fixture parses", false)
		return

	for case_data in (fixture["cases"] as Array):
		_test_case(t, case_data)

	_test_completes_run(t)


func _test_case(t: TestCase, c: Dictionary) -> void:
	var seed_value := int(c["seed"])
	t.group("board / seed %d" % seed_value)

	var rng := Rng.new(seed_value)
	var gen := BoardOps.TileGen.new(rng, 1)
	var board := BoardOps.generate_initial(gen)

	t.eq_seq("generated board", _encode(board), _expected_board(c["board"]))
	# The id counter and RNG state are the sharp part: they encode how many
	# draws the rejection loops consumed, which the board alone does not reveal.
	t.eq("id counter after generation", gen.next_id, int(c["nextIdAfterGenerate"]))
	t.eq("RNG state after generation", rng.get_state(), int(c["rngStateAfterGenerate"]))

	# A settled board has no Syncs by construction — that IS the contract.
	t.check("no pre-existing Sync", MatchFinder.detect(board).is_empty())
	t.check("at least one legal move", BoardOps.has_any_valid_move(board))

	var expected_move = c["firstValidMove"]
	if expected_move != null:
		var move := BoardOps.find_valid_move(board)
		t.check("a valid move is found", not move.is_empty())
		if not move.is_empty():
			# Scan order is deterministic and the bot consumes it, so the FIRST
			# move found must be the same one, not merely a valid one.
			t.eq("first valid move a", [move["a"].x, move["a"].y], [int(expected_move[0][0]), int(expected_move[0][1])])
			t.eq("first valid move b", [move["b"].x, move["b"].y], [int(expected_move[1][0]), int(expected_move[1][1])])

	_test_disturbed(t, board, c)

	# Reshuffle is a permutation: same Packets, new positions.
	var state := {"board": board, "rng": rng, "next_id": gen.next_id}
	BoardOps.reshuffle(state)
	t.eq_seq("reshuffled board", _encode(state["board"]), _expected_board(c["reshuffled"]))
	t.eq("RNG state after reshuffle", rng.get_state(), int(c["rngStateAfterReshuffle"]))


## Detection is exercised against a deliberately disturbed board, because a
## settled one has nothing to detect.
func _test_disturbed(t: TestCase, board: Array, c: Dictionary) -> void:
	var disturbed: Array = c["disturbed"]
	if disturbed.is_empty():
		return
	var d: Dictionary = disturbed[0]

	var a := Vector2i(int(d["swap"][0][0]), int(d["swap"][0][1]))
	var b := Vector2i(int(d["swap"][1][0]), int(d["swap"][1][1]))
	BoardOps.swap(board, a, b)

	var matches := MatchFinder.detect(board)
	var expected: Array = d["matches"]
	t.eq("detected Sync count", matches.size(), expected.size())

	if matches.size() == expected.size():
		for i in matches.size():
			var m: MatchFinder.Match = matches[i]
			var e: Dictionary = expected[i]
			t.eq("Sync %d condition" % i, m.condition, int(e["condition"]))
			t.eq("Sync %d value" % i, m.value, int(e["value"]))
			t.eq("Sync %d length" % i, m.length, int(e["length"]))
			t.eq("Sync %d isLine" % i, m.is_line, bool(e["isLine"]))
			t.eq("Sync %d orientation" % i, m.orientation, int(e["orientation"]))
			# Cell ORDER matters: merges append in a defined sequence, and the
			# resolution wave iterates them.
			var got_cells := []
			for cell in m.cells:
				got_cells.append([cell.x, cell.y])
			var want_cells := []
			for cell in (e["cells"] as Array):
				want_cells.append([int(cell[0]), int(cell[1])])
			t.eq_seq("Sync %d cells" % i, got_cells, want_cells)

	var clears := MatchFinder.compute_line_clears(matches)
	var expected_clears: Array = d["lineClears"]
	t.eq("line clear count", clears.size(), expected_clears.size())
	if clears.size() == expected_clears.size():
		for i in clears.size():
			var lc: MatchFinder.LineClear = clears[i]
			t.eq("line clear %d orientation" % i, lc.orientation, int(expected_clears[i]["orientation"]))
			t.eq("line clear %d index" % i, lc.index, int(expected_clears[i]["index"]))

	BoardOps.swap(board, a, b)


## The generation-time run guard only ever looks backwards, because the cells
## ahead are not filled yet. Worth testing directly: it is easy to "improve"
## into a full neighbour check, which would change how many draws generation
## consumes and silently break seed parity.
func _test_completes_run(t: TestCase) -> void:
	t.group("board / completes_run")
	var board := BoardOps.empty_board()

	board[0][0] = Tile.standard(1, Types.PacketColor.RED, Types.PacketShape.CIRCLE)
	board[0][1] = Tile.standard(2, Types.PacketColor.RED, Types.PacketShape.SQUARE)
	var red := Tile.standard(3, Types.PacketColor.RED, Types.PacketShape.STAR)
	t.check("a third matching colour completes a horizontal run", BoardOps.completes_run(board, 2, 0, red))

	var blue := Tile.standard(4, Types.PacketColor.BLUE, Types.PacketShape.STAR)
	t.check("a different colour and shape does not", not BoardOps.completes_run(board, 2, 0, blue))

	# Shape runs qualify on the same terms as colour runs.
	board[1][0] = Tile.standard(5, Types.PacketColor.BLUE, Types.PacketShape.CROSS)
	board[1][1] = Tile.standard(6, Types.PacketColor.GREEN, Types.PacketShape.CROSS)
	var cross := Tile.standard(7, Types.PacketColor.YELLOW, Types.PacketShape.CROSS)
	t.check("a third matching shape completes a run", BoardOps.completes_run(board, 2, 1, cross))

	# Neutrals only run with neutrals — they have no axes to share.
	board[2][0] = Tile.neutral(8)
	board[2][1] = Tile.neutral(9)
	t.check("three neutrals complete a run", BoardOps.completes_run(board, 2, 2, Tile.neutral(10)))
	t.check("a standard Packet does not extend a neutral run", not BoardOps.completes_run(board, 2, 2, red))
	board[3][0] = Tile.standard(11, Types.PacketColor.RED, Types.PacketShape.CIRCLE)
	board[3][1] = Tile.standard(12, Types.PacketColor.RED, Types.PacketShape.CIRCLE)
	t.check("a neutral does not extend a standard run", not BoardOps.completes_run(board, 2, 3, Tile.neutral(13)))

	# Only looks backwards: nothing at x<2 can complete a horizontal run.
	t.check("x=1 cannot complete a horizontal run", not BoardOps.completes_run(board, 1, 0, red))


func _encode(board: Array) -> Array:
	var out := []
	for row in board:
		for tile in row:
			var t: Tile = tile
			out.append([t.id, 1 if t.is_neutral() else 0, t.color, t.shape])
	return out


## Godot's JSON parser yields floats for every number, and array equality is
## type-strict, so the fixture side is coerced to int.
func _expected_board(raw) -> Array:
	var out := []
	for cell in (raw as Array):
		out.append([int(cell[0]), int(cell[1]), int(cell[2]), int(cell[3])])
	return out

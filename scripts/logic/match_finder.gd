class_name MatchFinder
extends RefCounted

## Sync detection: straight-line runs of 3+, then blob merging.
##
## Named `match_finder` rather than `match` because `match` is a GDScript
## keyword.
##
## Base runs are detected PER AXIS — colour, shape, and neutral separately — and
## tagged with their condition and value. The merge pass then unions any two
## Syncs of the SAME condition and value whose Packets overlap or sit
## orthogonally adjacent, repeating until nothing merges. Colour and shape Syncs
## are different types and never merge into each other; different-axis Syncs
## that merely touch still do not combine.
##
## The merge is deliberately naive O(n²) over simultaneous Syncs. At 8×8 with a
## handful of matches this is microseconds — do not micro-optimize it.

enum Condition { COLOR = 0, SHAPE, NEUTRAL }
enum Orientation { NONE = -1, HORIZONTAL = 0, VERTICAL }


## One detected Sync.
class Match extends RefCounted:
	var cells: Array[Vector2i] = []
	var length := 0
	var condition: MatchFinder.Condition = MatchFinder.Condition.COLOR
	var value := 0  ## colour or shape index; 0 for neutral
	var is_line := false  ## every Packet shares one row or one column
	var orientation: MatchFinder.Orientation = MatchFinder.Orientation.NONE  ## meaningful only when is_line


## One qualifying row or column clear for a resolution wave. `index` is the row
## y for horizontal, the column x for vertical.
class LineClear extends RefCounted:
	var orientation: MatchFinder.Orientation = MatchFinder.Orientation.HORIZONTAL
	var index := 0

	func key() -> String:
		return "%d:%d" % [orientation, index]


## The axis key a Packet presents for a given condition, or -1 when it cannot
## participate. A neutral has no axes, so it matches only the neutral condition;
## a standard Packet never matches neutral.
static func _key_of(cell: Tile, cond: MatchFinder.Condition) -> int:
	if cell == null:
		return -1
	if cond == Condition.NEUTRAL:
		return 0 if cell.is_neutral() else -1
	if cell.is_neutral():
		return -1
	return cell.color if cond == Condition.COLOR else cell.shape


static func detect(board: Array) -> Array:
	var matches := _detect_base_runs(board)

	# Repeat-until-stable: same condition and value, touching or overlapping.
	var changed := true
	while changed:
		changed = false
		for i in matches.size():
			var merged := false
			for j in range(i + 1, matches.size()):
				var a: Match = matches[i]
				var b: Match = matches[j]
				if a.condition != b.condition or a.value != b.value:
					continue
				if not _touches_or_overlaps(a, b):
					continue
				matches[i] = _merge_two(a, b)
				matches.remove_at(j)
				changed = true
				merged = true
				break
			if merged:
				break

	return matches


static func _detect_base_runs(board: Array) -> Array:
	var out: Array = []
	for cond in [Condition.COLOR, Condition.SHAPE, Condition.NEUTRAL]:
		for y in Constants.BOARD_HEIGHT:
			var cells: Array[Tile] = []
			var points: Array[Vector2i] = []
			for x in Constants.BOARD_WIDTH:
				cells.append(board[y][x])
				points.append(Vector2i(x, y))
			_scan(cells, points, Orientation.HORIZONTAL, cond, out)
		for x in Constants.BOARD_WIDTH:
			var cells: Array[Tile] = []
			var points: Array[Vector2i] = []
			for y in Constants.BOARD_HEIGHT:
				cells.append(board[y][x])
				points.append(Vector2i(x, y))
			_scan(cells, points, Orientation.VERTICAL, cond, out)
	return out


## Walks one row or column, emitting every maximal run of 3+ equal keys. The
## loop runs one past the end so a run ending at the boundary is still emitted.
static func _scan(cells: Array, points: Array, orientation: MatchFinder.Orientation, cond: MatchFinder.Condition, out: Array) -> void:
	var n := cells.size()
	var run_key := -1
	var run_start := 0

	for i in range(n + 1):
		var k := _key_of(cells[i], cond) if i < n else -1
		if k == -1 or k != run_key:
			var length := i - run_start
			if run_key != -1 and length >= 3:
				var m := Match.new()
				for j in range(run_start, i):
					m.cells.append(points[j])
				m.length = length
				m.condition = cond
				m.value = run_key
				m.is_line = true
				m.orientation = orientation
				out.append(m)
			run_key = k
			run_start = i


## Two Syncs touch when any Packet of one equals or is orthogonally adjacent to
## any Packet of the other. Physically touching only — a one-Packet gap does not
## bridge them.
static func _touches_or_overlaps(a: Match, b: Match) -> bool:
	for ca in a.cells:
		for cb in b.cells:
			if absi(ca.x - cb.x) + absi(ca.y - cb.y) <= 1:
				return true
	return false


static func _merge_two(a: Match, b: Match) -> Match:
	var seen := {}
	var cells: Array[Vector2i] = []
	for c in a.cells:
		if not seen.has(c):
			seen[c] = true
			cells.append(c)
	for c in b.cells:
		if not seen.has(c):
			seen[c] = true
			cells.append(c)

	var same_row := true
	var same_col := true
	for c in cells:
		if c.y != cells[0].y:
			same_row = false
		if c.x != cells[0].x:
			same_col = false

	var m := Match.new()
	m.cells = cells
	m.length = cells.size()
	m.condition = a.condition
	m.value = a.value
	m.is_line = same_row or same_col
	if same_row:
		m.orientation = Orientation.HORIZONTAL
	elif same_col:
		m.orientation = Orientation.VERTICAL
	else:
		m.orientation = Orientation.NONE
	return m


## Damage-only multiplier by tier. A line of 6+ counts as the 5-line tier; a
## non-line 5+ as the non-line crit tier.
##
## A merge always produces at least 5 Packets — two 3-Packet runs sharing one
## Packet is 5 — so a non-line 4 cannot occur.
static func multiplier(m: Match) -> float:
	if m.length >= 5:
		return Constants.MATCH_5_LINE_MULTIPLIER if m.is_line else Constants.MATCH_5_NONLINE_MULTIPLIER
	if m.length == 4:
		return Constants.MATCH_4_MULTIPLIER
	return Constants.MATCH_3_MULTIPLIER


## The ONE authority for row/column-clear qualification.
##
## Within each resolution wave, union every Packet belonging directly to a
## detected colour-axis or shape-axis Sync; any contiguous run of
## LINE_CLEAR_RUN_LENGTH+ cells in that union triggers the corresponding clear.
##
## The player-visible directly-matched footprint controls qualification — not
## hidden group composition — so two adjacent but internally separate 3-matches
## CAN combine, and overlapping colour and shape Syncs CAN combine.
##
## Neutral Syncs are deliberately NOT folded into that union: a neutral has no
## axis to share, so a straight neutral run keeps its own standalone
## qualification instead.
##
## Only DIRECT match footprints contribute. Line-clear collateral, Bomb and
## countdown destruction, Function destruction, and prior line clears are all
## excluded — which is what makes the rule non-recursive.
static func compute_line_clears(matches: Array) -> Array:
	var union := {}
	for m in matches:
		if m.condition == Condition.NEUTRAL:
			continue
		for c in m.cells:
			union[c] = true

	var out: Array = []
	var seen := {}

	var add := func(orientation: MatchFinder.Orientation, index: int) -> void:
		var lc := LineClear.new()
		lc.orientation = orientation
		lc.index = index
		if seen.has(lc.key()):
			return
		seen[lc.key()] = true
		out.append(lc)

	# Maximal contiguous runs in the combined footprint, rows then columns. Each
	# loop runs one past the end so a run touching the edge still closes.
	for y in Constants.BOARD_HEIGHT:
		var run := 0
		for x in range(Constants.BOARD_WIDTH + 1):
			var on := x < Constants.BOARD_WIDTH and union.has(Vector2i(x, y))
			if on:
				run += 1
			else:
				if run >= Constants.LINE_CLEAR_RUN_LENGTH:
					add.call(Orientation.HORIZONTAL, y)
				run = 0

	for x in Constants.BOARD_WIDTH:
		var run := 0
		for y in range(Constants.BOARD_HEIGHT + 1):
			var on := y < Constants.BOARD_HEIGHT and union.has(Vector2i(x, y))
			if on:
				run += 1
			else:
				if run >= Constants.LINE_CLEAR_RUN_LENGTH:
					add.call(Orientation.VERTICAL, x)
				run = 0

	# A straight neutral run of 4+ clears its own row or column independently of
	# the colour/shape union.
	for m in matches:
		if m.condition != Condition.NEUTRAL or not m.is_line or m.length < Constants.LINE_CLEAR_RUN_LENGTH:
			continue
		if m.orientation == Orientation.HORIZONTAL:
			add.call(Orientation.HORIZONTAL, m.cells[0].y)
		elif m.orientation == Orientation.VERTICAL:
			add.call(Orientation.VERTICAL, m.cells[0].x)

	return out

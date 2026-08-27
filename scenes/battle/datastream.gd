class_name Datastream
extends Control

## The 8×8 board.
##
## Owns 64 `PacketView` children, one per cell, and nothing else. Sixty-four
## nodes is cheap, and per-Packet nodes make falls, swaps, and flashes
## straightforward to animate — a TileMapLayer would be faster and considerably
## harder to move individual cells around.
##
## Holds no game state. It renders view Dictionaries the logic layer produced
## and reports touches upward; it never decides anything.

signal packet_pressed(cell: Vector2i)
signal packet_dragged(from_cell: Vector2i, to_cell: Vector2i)

const GAP_RATIO := 0.06

var _cells: Array[PacketView] = []
var _selected := Vector2i(-1, -1)
var _drag_origin := Vector2i(-1, -1)
var _drag_start := Vector2.ZERO


func _ready() -> void:
	for i in Constants.BOARD_WIDTH * Constants.BOARD_HEIGHT:
		var p := PacketView.new()
		p.cell = Vector2i(i % Constants.BOARD_WIDTH, i / Constants.BOARD_WIDTH)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(p)
		_cells.append(p)
	resized.connect(_layout)
	_layout()


## The surround shows through the gaps between cells, so it is what draws the
## grid — the cells themselves carry no border.
func _draw() -> void:
	# Tiled, not stretched: the surround shows through the 6% gaps between cells
	# and IS the grid, so its texel scale has to stay constant as the board
	# resizes. Stretching one image across the board would make the grid's own
	# texture change size with the phone.
	draw_texture_rect(Graphics.pack().board_surround, Rect2(Vector2.ZERO, size), true)


func cell_size() -> float:
	var span := minf(size.x, size.y)
	return span / float(Constants.BOARD_WIDTH)


func _layout() -> void:
	var cs := cell_size()
	var gap := cs * GAP_RATIO
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var p := _cells[y * Constants.BOARD_WIDTH + x]
			p.position = home_of(Vector2i(x, y))
			p.size = Vector2(cs - gap, cs - gap)
	queue_redraw()


## Where a cell's view SITS when nothing is moving.
##
## Animation works by putting a node somewhere else and tweening it back here,
## so this has to be the single definition of "in place" — a second copy of the
## arithmetic is how a Packet ends up settling one gap off after a fall.
func home_of(cell: Vector2i) -> Vector2:
	var cs := cell_size()
	var gap := cs * GAP_RATIO
	return Vector2(cell.x * cs + gap * 0.5, cell.y * cs + gap * 0.5)


func at(cell: Vector2i) -> PacketView:
	if cell.x < 0 or cell.x >= Constants.BOARD_WIDTH or cell.y < 0 or cell.y >= Constants.BOARD_HEIGHT:
		return null
	return _cells[cell.y * Constants.BOARD_WIDTH + cell.x]


## Replaces the whole board. Used at battle start, after a Shake or reshuffle,
## and whenever playback is skipped — any point where incremental animation
## would be wrong or wasteful.
func set_grid(grid: Array) -> void:
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var v = grid[y][x]
			at(Vector2i(x, y)).view = {} if v == null else (v as Dictionary)
	settle()


func set_cell(cell: Vector2i, view) -> void:
	var p := at(cell)
	if p != null:
		p.view = {} if view == null else (view as Dictionary)


func set_selected(cell: Vector2i) -> void:
	if _selected == cell:
		return
	var prev := at(_selected)
	if prev != null:
		prev.selected = false
	_selected = cell
	var next := at(cell)
	if next != null:
		next.selected = true


func clear_targeting() -> void:
	for p in _cells:
		p.targeting = false


func set_targeting(cells: Array) -> void:
	clear_targeting()
	for c in cells:
		var p := at(c)
		if p != null:
			p.targeting = true


# ---------------------------------------------------------------------------
# Motion
#
# Every method here MOVES NODES and then leaves the grid model exactly as it
# found it: cell i always means cell i, and a view Dictionary always sits on the
# node for the cell it belongs to. Motion is transient decoration over a model
# that never moves, which is what keeps a skipped or interrupted animation from
# leaving the board describing a position the logic layer never produced.
#
# Each returns the tween so the caller can await it. Without that the playback
# loop's dwell and the animation's duration drift apart, and events start
# overlapping the tail of the previous one's motion.
# ---------------------------------------------------------------------------

## Two Packets trading places.
##
## The swap is the player's own input echoed back, and it is the one moment they
## need to see clearly — a swap that resolves as an instant board change reads
## as "something happened", not as "the move I made happened".
func slide(a: Vector2i, b: Vector2i, duration: float) -> Tween:
	var pa := at(a)
	var pb := at(b)
	if pa == null or pb == null:
		return null

	var va := pa.view
	var vb := pb.view
	pa.view = vb
	pb.view = va
	pa.position = home_of(b)
	pb.position = home_of(a)
	# Raised above their neighbours so the two in motion are never partly
	# occluded by the cells they are passing.
	move_child(pa, get_child_count() - 1)
	move_child(pb, get_child_count() - 1)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(pa, "position", home_of(a), duration).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(pb, "position", home_of(b), duration).set_trans(Tween.TRANS_QUAD)
	return tween


## Gravity. `moves` is the logic layer's own `[{from, to}]` list.
##
## Every view is read BEFORE any is written: a Packet can be both the source of
## one move and the destination of another within a single fall, and writing as
## we go would overwrite a view that a later move still needs.
func fall(moves: Array, duration: float) -> Tween:
	if moves.is_empty():
		return null

	var arriving := {}
	var departing := {}
	for m in moves:
		var from: Vector2i = m["from"]
		var to: Vector2i = m["to"]
		var node := at(from)
		if node == null:
			continue
		arriving[to] = node.view
		departing[from] = true

	# A cell that something left and nothing arrived at is now empty. Clearing
	# it first stops the vacated Packet from appearing to be in two places.
	for cell in departing:
		if not arriving.has(cell):
			at(cell).view = {}

	var tween := create_tween().set_parallel(true)
	for m in moves:
		var from: Vector2i = m["from"]
		var to: Vector2i = m["to"]
		if not arriving.has(to):
			continue
		var node := at(to)
		node.view = arriving[to]
		node.position = home_of(from)
		# Fall time scales with distance, so a Packet dropping six rows does not
		# arrive at the same instant as one dropping a single row. Everything
		# landing simultaneously is what makes gravity read as a teleport even
		# when it is animated.
		var rows := maxi(1, absi(to.y - from.y))
		tween.tween_property(node, "position", home_of(to), duration * sqrt(float(rows))) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return tween


## Refill. `tiles` is the logic layer's own `[{p, view}]` list.
##
## New Packets enter from above the board rather than materialising in place,
## staggered by row so a column arrives as a stream instead of a block.
func spawn(tiles: Array, duration: float) -> Tween:
	if tiles.is_empty():
		return null

	var cs := cell_size()

	# How many Packets each column is receiving. Refill always fills a column
	# from the top down, so a column taking `k` new Packets is filling rows
	# `0..k-1` — which is what lets the stack below be computed from the count
	# alone.
	var per_column := {}
	for entry in tiles:
		var cell: Vector2i = entry["p"]
		per_column[cell.x] = int(per_column.get(cell.x, 0)) + 1

	var tween := create_tween().set_parallel(true)
	for entry in tiles:
		var cell: Vector2i = entry["p"]
		var node := at(cell)
		if node == null:
			continue
		node.view = entry["view"]

		# A column's new Packets enter as a RIGID STACK: the one bound for the
		# lowest empty row starts just above the board, and each one above it
		# starts a further cell up. Every Packet in the column therefore travels
		# exactly `k` cells, so one duration moves them all at a single speed
		# and the column arrives in formation.
		#
		# The previous arithmetic cancelled `cell.y` out and started every
		# Packet at the same point, which meant they covered DIFFERENT distances
		# in the same time. The ones with least to travel crawled, and — being
		# slowest — were the last to settle, reading as a stall right before the
		# board came to rest.
		var k := int(per_column[cell.x])
		var rise := cell.y + (k - cell.y)  # == k; written out to show the stack
		node.position = home_of(cell) - Vector2(0, cs * float(rise))

		# Fall time scales with the square root of the distance, matching
		# `fall`, so a deep refill takes longer than a shallow one instead of
		# being rushed to fit a fixed budget.
		tween.tween_property(node, "position", home_of(cell), duration * sqrt(float(k))) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return tween


## Snaps every node back to its home position.
##
## Called whenever the board is rebuilt wholesale — battle start, reshuffle, or
## a skipped animation — because a node left mid-tween would otherwise keep the
## offset it had when the tween was abandoned.
func settle() -> void:
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			at(Vector2i(x, y)).position = home_of(Vector2i(x, y))


func cell_at_position(pos: Vector2) -> Vector2i:
	var cs := cell_size()
	if cs <= 0.0:
		return Vector2i(-1, -1)
	var cell := Vector2i(int(pos.x / cs), int(pos.y / cs))
	if cell.x < 0 or cell.x >= Constants.BOARD_WIDTH or cell.y < 0 or cell.y >= Constants.BOARD_HEIGHT:
		return Vector2i(-1, -1)
	return cell


## Tap to select, tap an adjacent Packet to swap, or press and drag toward a
## neighbour. Drag is resolved on release rather than continuously, so a sloppy
## touch does not fire a swap the player did not intend.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var pos: Vector2 = event.position
		if pressed:
			_drag_origin = cell_at_position(pos)
			_drag_start = pos
			return

		if _drag_origin.x < 0:
			return
		var travel := pos - _drag_start
		var threshold := cell_size() * 0.4

		if travel.length() < threshold:
			packet_pressed.emit(_drag_origin)
		else:
			# Snap the drag to the dominant axis: a diagonal gesture is a
			# horizontal or vertical intent, never both.
			var step := Vector2i(signi(int(travel.x)), 0) if absf(travel.x) > absf(travel.y) else Vector2i(0, signi(int(travel.y)))
			var dest := _drag_origin + step
			if dest.x >= 0 and dest.x < Constants.BOARD_WIDTH and dest.y >= 0 and dest.y < Constants.BOARD_HEIGHT:
				packet_dragged.emit(_drag_origin, dest)
		_drag_origin = Vector2i(-1, -1)

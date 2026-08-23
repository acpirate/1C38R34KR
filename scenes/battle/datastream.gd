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
	draw_rect(Rect2(Vector2.ZERO, size), PacketStyle.BOARD_SURROUND)


func cell_size() -> float:
	var span := minf(size.x, size.y)
	return span / float(Constants.BOARD_WIDTH)


func _layout() -> void:
	var cs := cell_size()
	var gap := cs * GAP_RATIO
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var p := _cells[y * Constants.BOARD_WIDTH + x]
			p.position = Vector2(x * cs + gap * 0.5, y * cs + gap * 0.5)
			p.size = Vector2(cs - gap, cs - gap)
	queue_redraw()


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

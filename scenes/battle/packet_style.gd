class_name PacketStyle
extends RefCounted

## THE PRESENTATION REGISTRY (D-014).
##
## The single mapping from frozen gameplay identity to visual appearance. This
## file is the alpha→final translation matrix: when the art pass lands,
## replacing a drawn shape with a sprite is a change here and nowhere else.
##
## **Frozen, and not this file's business:** `PacketColor` and `PacketShape` are
## enums `0..5`, and their ORDERING is load-bearing — weak sets derive as the
## enum-order complement of an authored strong set, so reordering them silently
## rewrites every System's and Hacker's weaknesses.
##
## **Swappable, and entirely this file's business:** what each of those twelve
## values looks like.
##
## Nothing outside this file may hard-code a colour value or a shape path.
## `test_presentation.gd` enforces that by banning hex literals elsewhere under
## `scenes/`, because the rule is only useful if it cannot quietly erode.
##
## The values below are the alpha's, carried over because copying twelve
## constants costs nothing and gives a legible board to play on. They are
## PLACEHOLDERS, not a target to reproduce faithfully — the shape glyphs in
## particular are expected to be replaced.


## Fill colour, indexed by `Types.PacketColor`.
const COLOR_FILL: Array[Color] = [
	Color("e04343"),  ## RED
	Color("ddcf3d"),  ## YELLOW
	Color("cf52cf"),  ## MAGENTA
	Color("43b953"),  ## GREEN
	Color("3fc4c4"),  ## CYAN
	Color("4a72e8"),  ## BLUE
]

## Border and glyph outline, indexed by `Types.PacketColor`.
const COLOR_BORDER: Array[Color] = [
	Color("79201f"),  ## RED
	Color("776e1a"),  ## YELLOW
	Color("6f2570"),  ## MAGENTA
	Color("1f5f28"),  ## GREEN
	Color("1c6666"),  ## CYAN
	Color("22397e"),  ## BLUE
]

const NEUTRAL_FILL := Color("4a4a52")
const NEUTRAL_BORDER := Color("2a2a30")
const GLYPH := Color("ffffff")
const BOARD_BACKGROUND := Color("1b1b22")

## Overlay tints, indexed by `Tile.Special.Type`.
const OVERLAY_TINT: Array[Color] = [
	Color("ff5a3c"),  ## BOMB
	Color("ffd24a"),  ## BUFF
	Color("6ad0ff"),  ## SHIELD
	Color("b04aff"),  ## OVERRIDE
]

const SELECTION := Color("ffffff")
const TARGETING := Color("ffe14a")

## Playback tints, applied as `modulate`.
##
## These live here for the same reason the palette does: they are appearance
## decisions, and the registry is only the one place for those if it holds ALL
## of them. Letting "just a flash colour" sit inline is how the rule erodes.
const TINT_NONE := Color(1, 1, 1)
const TINT_DESTROYED := Color(1, 1, 1, 0.35)
const TINT_BLAST := Color(1.8, 1.2, 0.8)
const TINT_INACTIVE := Color(0.65, 0.65, 0.65)


static func fill_for(is_neutral: bool, color_index: int) -> Color:
	return NEUTRAL_FILL if is_neutral else COLOR_FILL[color_index]


static func border_for(is_neutral: bool, color_index: int) -> Color:
	return NEUTRAL_BORDER if is_neutral else COLOR_BORDER[color_index]


## The glyph outline for one shape, as unit-square points in `[-1, 1]`.
##
## Returned as points rather than drawn here so the caller controls scale,
## centring, and whether it fills or strokes — and so a future sprite-based
## registry can replace this without every call site changing.
##
## A circle has no polygon, so it is signalled by an empty array and drawn by
## `draw_shape` below. That is the one special case, and it is contained here.
static func shape_points(shape_index: int) -> PackedVector2Array:
	match shape_index:
		Types.PacketShape.CIRCLE:
			return PackedVector2Array()
		Types.PacketShape.SQUARE:
			return PackedVector2Array([
				Vector2(-0.78, -0.78), Vector2(0.78, -0.78),
				Vector2(0.78, 0.78), Vector2(-0.78, 0.78),
			])
		Types.PacketShape.TRIANGLE:
			return PackedVector2Array([
				Vector2(0, -0.92), Vector2(0.88, 0.72), Vector2(-0.88, 0.72),
			])
		Types.PacketShape.DIAMOND:
			return PackedVector2Array([
				Vector2(0, -0.95), Vector2(0.8, 0), Vector2(0, 0.95), Vector2(-0.8, 0),
			])
		Types.PacketShape.STAR:
			return _star_points()
		Types.PacketShape.CROSS:
			var w := 0.32
			var r := 0.92
			return PackedVector2Array([
				Vector2(-w, -r), Vector2(w, -r), Vector2(w, -w), Vector2(r, -w),
				Vector2(r, w), Vector2(w, w), Vector2(w, r), Vector2(-w, r),
				Vector2(-w, w), Vector2(-r, w), Vector2(-r, -w), Vector2(-w, -w),
			])
	return PackedVector2Array()


static func _star_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var radius := 0.95 if i % 2 == 0 else 0.42
		var angle := -PI / 2.0 + i * PI / 5.0
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts


## Draws one Packet's glyph, centred on `centre` at `radius`.
##
## The whole shape vocabulary is drawn through this one function, so a change of
## representation — filled to stroked, polygon to sprite — happens once.
static func draw_shape(canvas: CanvasItem, shape_index: int, centre: Vector2, radius: float, fill: Color, outline: Color) -> void:
	if shape_index == Types.PacketShape.CIRCLE:
		canvas.draw_circle(centre, radius * 0.86, fill)
		canvas.draw_arc(centre, radius * 0.86, 0, TAU, 24, outline, radius * 0.12, true)
		return

	var unit := shape_points(shape_index)
	var pts := PackedVector2Array()
	for p in unit:
		pts.append(centre + p * radius)
	canvas.draw_colored_polygon(pts, fill)

	# Closed outline: repeat the first point so the final edge is stroked.
	var loop := pts.duplicate()
	loop.append(pts[0])
	canvas.draw_polyline(loop, outline, radius * 0.11, true)

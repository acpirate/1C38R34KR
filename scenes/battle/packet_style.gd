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

## The cell a Packet sits ON, and the surround the grid sits on.
##
## These exist because the Packet is a coloured glyph rather than a coloured
## field (see `packet.gd`): with no tile fill, the cell itself has to carry the
## grid, so its colour is now load-bearing rather than decorative.
const CELL_BACKGROUND := Color("26262e")
const BOARD_SURROUND := Color("111118")

## Neutral static. A neutral has no colour and no shape, so it must not read as
## an absence — an empty cell and an unmatchable Packet are different things.
## Drawn as per-cell noise from these two values.
const NEUTRAL_STATIC_DARK := Color("14141a")
const NEUTRAL_STATIC_LIGHT := Color("d8d8e2")

## Ownership badge fills. Player overlays are light, System overlays dark, each
## ringed and lettered in the other — the one convention that survives from the
## alpha unchanged, because it reads at thumb size with no legend.
const BADGE_PLAYER := Color("ffffff")
const BADGE_ENEMY := Color("000000")

# ---------------------------------------------------------------------------
# UI palette
#
# The registry holds the interface's colours for the same reason it holds the
# board's: a hard-coded panel background is exactly as expensive to hunt down
# later as a hard-coded Packet fill, and `test_presentation.gd` bans both.
# ---------------------------------------------------------------------------

## The wash a modal puts over what it interrupts. Deliberately translucent: the
## battle stays visible behind the pause menu, so it reads as suspended rather
## than exited.
const SCRIM := Color(0, 0, 0, 0.55)

const PANEL := Color("2a2a34")
const PANEL_DEEP := Color("23232c")
const PANEL_EDGE := Color("555555")
const CONTROL := Color("3a3a48")
const CONTROL_EDGE := Color("666666")
const BOX := Color("2c2c36")
const BOX_EDGE := Color("555555")

const TEXT := Color("eeeeee")
const TEXT_DIM := Color("aaaaaa")
const TEXT_FAINT := Color("9a9aa8")
const TEXT_HEADING := Color("ffffff")
const TEXT_STATUS := Color("f0e070")

## Amber is the alpha's "this is live / this is chosen" colour, everywhere. It
## marks a charged Program, a selected option, and an active build slot, and it
## is deliberately the same amber in all three so the meaning transfers.
const ACCENT := Color("e0a040")
const ACCENT_HOT := Color("ff9500")
const READY := Color("ffffff")

const LINK_BAR := Color("58c06a")
const ICE_BAR := Color("c05858")
const CHARGE_TRACK := Color("1c1c24")
const CHARGE_FILL := Color("6080c0")
const CHARGE_FILL_READY := Color("f0c040")
const CHARGE_TEXT_READY := Color("ffe080")

const DAMAGE := Color("ff5a5a")
const SYSTEM_TURN_FRAME := Color("e03030")

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

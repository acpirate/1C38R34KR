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
## ## What changed in beta 0.3.1
##
## The graphics pack now owns appearance, and this file's role split in two.
##
## **Still read at runtime:** the Packet palette (as the fallback when the
## palette SVG cannot be parsed), text colours, playback tints, the pause scrim,
## the neutral static, the badge polarity, and the MISSING checker.
##
## **Now read only by `tools/gen_assets.gd`:** every chrome colour below — panel,
## box, control, bars, edges. The game does not read them any more; the PNGs
## carry those values, and these constants are the SOURCE the pack is generated
## from. That is why they stay rather than moving into the tool: regenerating
## the pack from the same registry the renderer used is what makes v0 provably
## reproduce the whitebox instead of approximating it.
##
## Six members were deleted here in 0.3.1 — `SYSTEM_TURN_FRAME`, `NEUTRAL_FILL`,
## `NEUTRAL_BORDER`, `GLYPH`, `fill_for()` and `border_for()` — survivors of the
## beta 0.1 representation, when a Packet was a coloured square with a white
## glyph on it. Nothing had rendered them for two builds. `COLOR_BORDER` went
## with them under D-036: the outline is now a second tone inside the glyph
## texture, produced by the same modulate that produces the fill.


## Fill colour, indexed by `Types.PacketColor`.
const COLOR_FILL: Array[Color] = [
	Color("e04343"),  ## RED
	Color("ddcf3d"),  ## YELLOW
	Color("cf52cf"),  ## MAGENTA
	Color("43b953"),  ## GREEN
	Color("3fc4c4"),  ## CYAN
	Color("4a72e8"),  ## BLUE
]

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

## Overlay tints, indexed by `Tile.Special.Type`.
const OVERLAY_TINT: Array[Color] = [
	Color("ff5a3c"),  ## BOMB
	Color("ffd24a"),  ## BUFF
	Color("6ad0ff"),  ## SHIELD
	Color("b04aff"),  ## OVERRIDE
	# Beta 0.4. Both are Boss marks and both had to stay clear of OVERRIDE's
	# purple as well as of each other — the mark IS the type signal since
	# D-037 suspended the ring, so a shared tint hides a shared mechanic.
	Color("4affc8"),  ## CAPACITOR — stored charge, cool green
	Color("ff7a1f"),  ## LOGIC_BOMB — hazard orange, distinct from BOMB's red
]

## What a Packet is painted when ECHOFALL hides the COLOUR axis (beta 0.4 §8.2).
##
## White rather than a grey: the glyph texture carries its own darker outline,
## so modulating by white leaves a legible shape with an edge, where a mid grey
## would flatten the outline into the fill.
const CONCEALED_AXIS := Color.WHITE

## The diagnostic checker a missing graphics asset resolves to (beta 0.3.1).
##
## Deliberately hideous. §9.4 requires an element that lost its asset to LOOK
## broken — a tasteful fallback is indistinguishable from success, and would
## hide exactly the failure it exists to surface.
const MISSING_A := Color("ff00ff")
const MISSING_B := Color("000000")

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


## The glyph outline for one shape, as unit-square points in `[-1, 1]`.
##
## **No longer drawn by the game.** The renderer draws glyph TEXTURES now; this
## geometry is what `tools/gen_assets.gd` rasterises them from, so it remains the
## authoritative silhouette and a regenerated pack cannot drift from it.
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

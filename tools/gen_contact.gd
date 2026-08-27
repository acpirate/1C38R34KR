extends SceneTree

## Builds the Gate-B inspection sheets for Asset Pack v0.
##
## Run:  godot --headless -s res://tools/gen_contact.gd
##
## These are NOT pack assets and nothing in the game loads them. They exist so
## the director can judge the pack before the renderer is made to depend on it,
## which is the entire point of Gate B.
##
## The compositing here uses the same multiply `modulate` will use at runtime,
## so what you inspect is what the game will draw — not an approximation of it
## assembled by a browser with different blending rules.

const PACK := "res://assets/packs/v0"
const OUT := "res://staging/gate-b"

## Mirrors `gen_assets.gd`. The badge and its marks are separate textures drawn
## into one rect, so this sheet has to use the same span the pack was authored
## in or the composition it shows is not the one the renderer will produce.
const OVERLAY_SPAN := 1.38


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_packet_matrix()
	_overlay_composition()
	_scale_check()
	print("gate-b sheets written to %s" % OUT)
	quit()


## Sheet 1 — the six glyphs against the six palette colours.
##
## The point it proves: 36 combinations from 6 textures and 6 colours, with
## shape and colour still independent. If this sheet needed 36 PNGs the
## architecture would be wrong.
func _packet_matrix() -> void:
	var cell := 96
	var pad := 8
	var cols := Types.PacketColor.size()
	var rows := Types.PacketShape.size()
	var sheet := Image.create_empty(
		cols * (cell + pad) + pad, rows * (cell + pad) + pad, false, Image.FORMAT_RGBA8
	)
	sheet.fill(PacketStyle.BOARD_SURROUND)

	var bg := _load("battle/packet_cell")
	bg.resize(cell, cell, Image.INTERPOLATE_LANCZOS)

	for shape in rows:
		var glyph := _load("packet/glyph_%s" % _shape_name(shape))
		# The glyph draws at 0.46 of the cell as a RADIUS, so 92% of the cell
		# across — matching `packet.gd` exactly rather than filling the tile.
		var g := int(cell * 0.92)
		glyph.resize(g, g, Image.INTERPOLATE_LANCZOS)
		for colour in cols:
			var x := pad + colour * (cell + pad)
			var y := pad + shape * (cell + pad)
			sheet.blit_rect(bg, Rect2i(0, 0, cell, cell), Vector2i(x, y))
			var tinted := _tinted(glyph, PacketStyle.COLOR_FILL[colour])
			sheet.blend_rect(
				tinted, Rect2i(0, 0, g, g),
				Vector2i(x + (cell - g) / 2, y + (cell - g) / 2),
			)

	sheet.save_png("%s/sheet_packet_matrix.png" % OUT)


## Sheet 2 — overlay composition.
##
## Two things are being checked. CONCENTRICITY: badge and mark are separate
## PNGs drawn into one rect, and if their coordinate spaces disagree the mark
## sits off-centre — invisible in a directory listing. And DISTINCTNESS: with
## the type ring suspended (D-037) these four marks carry the whole type
## signal on their own, so they have to be told apart at badge size.
func _overlay_composition() -> void:
	var cell := 128
	var pad := 10
	var types := Tile.Special.Type.size()
	var sheet := Image.create_empty(
		2 * (cell + pad) + pad, types * (cell + pad) + pad, false, Image.FORMAT_RGBA8
	)
	sheet.fill(PacketStyle.BOARD_SURROUND)

	var bg := _load("battle/packet_cell")
	bg.resize(cell, cell, Image.INTERPOLATE_LANCZOS)

	var glyph := _load("packet/glyph_diamond")
	var g := int(cell * 0.92)
	glyph.resize(g, g, Image.INTERPOLATE_LANCZOS)
	var tinted := _tinted(glyph, PacketStyle.COLOR_FILL[Types.PacketColor.CYAN])

	# The badge spans 0.22 of the Packet as a radius, in the overlay space that
	# is 1.38× that radius across — see `gen_assets.gd`.
	var badge_px := int(cell * 0.22 * 2.0 * OVERLAY_SPAN)

	for t in types:
		for owner in 2:
			var x := pad + owner * (cell + pad)
			var y := pad + t * (cell + pad)
			sheet.blit_rect(bg, Rect2i(0, 0, cell, cell), Vector2i(x, y))
			sheet.blend_rect(
				tinted, Rect2i(0, 0, g, g), Vector2i(x + (cell - g) / 2, y + (cell - g) / 2)
			)

			var badge := _load("overlay/badge_%s" % ("player" if owner == 0 else "enemy"))
			badge.resize(badge_px, badge_px, Image.INTERPOLATE_LANCZOS)
			var at := Vector2i(x + (cell - badge_px) / 2, y + (cell - badge_px) / 2)
			sheet.blend_rect(badge, Rect2i(0, 0, badge_px, badge_px), at)

			# D-037 — the type ring is suspended, so the MARK is the whole type
			# signal, which is how the alpha has always carried it. D-038 makes
			# it art rather than a font character.
			#
			# The mark takes the badge's opposite colour, which is what keeps
			# ownership readable: dark on a Hacker badge, light on a System one.
			var mark_col: Color = PacketStyle.BADGE_ENEMY if owner == 0 else PacketStyle.BADGE_PLAYER
			var mark := _tinted(_load("overlay/mark_%s" % _special_name(t)), mark_col)
			# The badge face is 1/1.38 of the overlay span; the mark sits inside
			# it at roughly 70%, matching the old text's optical size.
			var mark_px := int(badge_px / OVERLAY_SPAN * 0.72)
			mark.resize(mark_px, mark_px, Image.INTERPOLATE_LANCZOS)
			sheet.blend_rect(
				mark, Rect2i(0, 0, mark_px, mark_px),
				Vector2i(x + (cell - mark_px) / 2, y + (cell - mark_px) / 2),
			)

	sheet.save_png("%s/sheet_overlay_composition.png" % OUT)


## Sheet 3 — the two scales a glyph actually has to survive.
##
## On the board it is ~118 px. As the binding swatch in `UnitBox` it is ~30 px,
## about a quarter the size, and an outline tuned for the large case closes up
## and muddies the silhouette at the small one. This sheet is the check for
## that, and it is the reason the outline was authored generously.
func _scale_check() -> void:
	var big := 118
	var small := 30
	var pad := 12
	var shapes := Types.PacketShape.size()
	var row_h := big + pad
	var sheet := Image.create_empty(
		shapes * (big + pad) + pad, row_h + small + pad * 2, false, Image.FORMAT_RGBA8
	)
	sheet.fill(PacketStyle.CELL_BACKGROUND)

	for shape in shapes:
		var src := _load("packet/glyph_%s" % _shape_name(shape))
		var colour: Color = PacketStyle.COLOR_FILL[shape % Types.PacketColor.size()]

		var a := _tinted(src, colour)
		a.resize(big, big, Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(a, Rect2i(0, 0, big, big), Vector2i(pad + shape * (big + pad), pad))

		var b := _tinted(src, colour)
		b.resize(small, small, Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(
			b, Rect2i(0, 0, small, small),
			Vector2i(pad + shape * (big + pad) + (big - small) / 2, row_h + pad),
		)

	sheet.save_png("%s/sheet_scale_check.png" % OUT)


## `modulate`, done exactly: multiply RGB, leave alpha alone.
func _tinted(src: Image, colour: Color) -> Image:
	var out := Image.create_empty(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			out.set_pixel(x, y, Color(c.r * colour.r, c.g * colour.g, c.b * colour.b, c.a))
	return out


func _load(key: String) -> Image:
	return Image.load_from_file("%s/%s.png" % [PACK, key])


func _shape_name(shape: int) -> String:
	return ["circle", "square", "triangle", "diamond", "star", "cross"][shape]


func _special_name(t: int) -> String:
	return ["bomb", "buff", "shield", "override"][t]

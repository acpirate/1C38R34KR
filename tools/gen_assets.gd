extends SceneTree

## Generates Asset Pack v0 (beta 0.3.1).
##
## Run:  godot --headless -s res://tools/gen_assets.gd
##
## ## Why the pack is generated rather than hand-authored
##
## v0 exists to validate the architecture, not to establish art direction, and
## its job is to "approximately reproduce the current functional presentation".
## The most reliable way to do that is to read the SAME registry the live
## renderer reads — so every colour below comes from `PacketStyle`, and a v0
## asset cannot drift from the whitebox it replaces.
##
## It also means the pack is REGENERABLE. If the contract shifts at Gate B, the
## answer is to edit this file and re-run it, not to redraw thirty PNGs.
##
## Nothing here runs in the game. This is a build tool.

const OUT := "res://assets/packs/v0"

## Supersample factor for anything with a curve or a diagonal. Shapes are
## rasterised at this multiple and boxed down, which is the whole anti-aliasing
## strategy — cheap, and it costs nothing at build time.
const SS := 4

## Glyph core inset. The glyph is ONE image carrying two tones: the silhouette
## at white and its outline at grey, so a single modulate produces the fill AND
## a proportionally darker outline (D-036).
##
## 0.86 is chosen for the SMALL case, not the large one. The glyph draws at
## ~118 px on the board and at ~30 px as the binding swatch in `UnitBox`; an
## outline tuned to look right at 118 closes up and muddies the silhouette at
## 30. This is the generous end of what still reads as an outline on the board.
const GLYPH_CORE := 0.86

const GLYPH_OUTLINE := Color("8c8c8c")

## The overlay coordinate space.
##
## The badge and the type ring are separate PNGs drawn into the SAME rect, so
## they must share one space or they will not concentrically align. The space
## spans the type ring's full extent: 1.28 × badge radius (its centreline) plus
## half its 0.2 thickness, which is 1.38 × badge radius.
const OVERLAY_SPAN := 1.38

var _manifest: Array[Dictionary] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for sub in ["chrome", "battle", "packet", "overlay", "icon"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%s" % [OUT, sub]))

	_chrome()
	_battle()
	_packet()
	_overlays()
	_icons()
	_text_art()

	_write_manifest()
	print("\nasset pack v0: %d PNGs written to %s" % [_manifest.size(), OUT])
	quit()


# ---------------------------------------------------------------------------
# Screen chrome — 14
# ---------------------------------------------------------------------------

func _chrome() -> void:
	# Tileable, not a fixed full-screen image: the phone is 1080×2340 and the
	# tablet 1200×1920, and one stretched image cannot serve both aspects
	# without distorting or letterboxing.
	_save("chrome/screen_bg", _solid(256, 256, PacketStyle.BOARD_BACKGROUND), 0, "tile")

	_save("chrome/panel", _box(48, PacketStyle.PANEL, 1, PacketStyle.PANEL_EDGE), 16)
	_save("chrome/button_normal", _box(48, PacketStyle.CONTROL, 1, PacketStyle.CONTROL_EDGE), 16)
	_save("chrome/button_pressed", _box(48, PacketStyle.PANEL_DEEP, 1, PacketStyle.ACCENT), 16)
	_save("chrome/button_disabled", _box(48, PacketStyle.PANEL_DEEP, 1, PacketStyle.PANEL_EDGE), 16)

	# NEW in v0 (§4.8). Selection is currently `modulate` alone, which collides
	# with `disabled` on the Build screen — both render as "dimmer". A 2 px
	# accent border is a different KIND of difference from a brightness change,
	# which is what makes the two states separable at a glance.
	_save("chrome/button_selected", _box(48, PacketStyle.CONTROL, 2, PacketStyle.ACCENT), 16)

	# Authored 8 px tall and rendered at px(2), not px(1): a one-pixel line from
	# a filtered texture is mush, and there is no art you can put in one pixel.
	_save("chrome/rule", _solid(64, 8, PacketStyle.PANEL_EDGE), 0, "stretch-x")

	_save("chrome/scroll_track", _solid(32, 32, PacketStyle.CHARGE_TRACK), 12)
	_save("chrome/scroll_thumb", _rounded(32, 32, 6, PacketStyle.CONTROL_EDGE), 12)

	_save("chrome/bar_track", _solid(32, 16, PacketStyle.CHARGE_TRACK), 6)
	_save("chrome/bar_fill_link", _solid(32, 16, PacketStyle.LINK_BAR), 6)
	_save("chrome/bar_fill_ice", _solid(32, 16, PacketStyle.ICE_BAR), 6)
	_save("chrome/bar_fill_charge", _solid(32, 16, PacketStyle.CHARGE_FILL), 6)
	_save("chrome/bar_fill_charge_ready", _solid(32, 16, PacketStyle.CHARGE_FILL_READY), 6)


# ---------------------------------------------------------------------------
# Battle chrome — 8
# ---------------------------------------------------------------------------

func _battle() -> void:
	_save("battle/avatar_box", _box(48, PacketStyle.BOX, 1, PacketStyle.CONTROL_EDGE), 16)

	# Four states, four textures. The border WIDTH carries as much of the
	# readiness story as the colour does — idle, charged, yours-and-charged, and
	# armed are 1, 2, 2 and 3 px — so each is a distinct image rather than one
	# box recoloured.
	_save("battle/program_box_idle", _box(48, PacketStyle.BOX, 1, PacketStyle.BOX_EDGE), 16)
	_save("battle/program_box_charged", _box(48, PacketStyle.BOX, 2, PacketStyle.ACCENT), 16)
	_save("battle/program_box_ready", _box(48, PacketStyle.BOX, 2, PacketStyle.READY), 16)
	_save("battle/program_box_armed", _box(48, PacketStyle.BOX, 3, PacketStyle.ACCENT_HOT), 16)

	_save("battle/board_surround", _solid(64, 64, PacketStyle.BOARD_SURROUND), 0, "tile")
	_save("battle/packet_cell", _solid(64, 64, PacketStyle.CELL_BACKGROUND), 16)
	_save("battle/build_slot", _slot(48), 16)


## The Build slot: the amber LEFT EDGE is the same mark a charged Program wears
## in battle, and it is load-bearing — the inventory rows below it deliberately
## have no accent. The 9-slice margin holds the bar at a fixed width while the
## row stretches.
func _slot(n: int) -> Image:
	var img := _box(n, PacketStyle.BOX, 1, PacketStyle.ACCENT)
	# 10 px, not 4. A 9-slice preserves the corner region 1:1, so the bar's
	# source width IS its screen width — where the StyleBoxFlat it replaces
	# computed `px(4)` ≈ 10. Authoring 4 here made the bar two and a half times
	# thinner than the whitebox, which is the kind of drift a skin pass is
	# supposed to avoid.
	img.fill_rect(Rect2i(0, 0, 10, n), PacketStyle.ACCENT)
	return img


# ---------------------------------------------------------------------------
# Packet — 8
# ---------------------------------------------------------------------------

func _packet() -> void:
	var names := ["circle", "square", "triangle", "diamond", "star", "cross"]
	for shape in Types.PacketShape.size():
		_save("packet/glyph_%s" % names[shape], _glyph(shape), 0)

	# Rect rings, not circular: these replace `draw_rect(..., false, width)`
	# around the whole cell, so they 9-slice like any other frame.
	_save("packet/ring_selected", _rect_ring(64, 5, PacketStyle.SELECTION), 12)
	_save("packet/ring_targeting", _rect_ring(64, 5, PacketStyle.TARGETING), 12)


## One Packet glyph: white core, grey outline, transparent elsewhere.
##
## Drawn from `PacketStyle.shape_points()` — the SAME geometry the live renderer
## uses — so a v0 glyph is the current silhouette, not a redrawing of it.
func _glyph(shape: int) -> Image:
	var n := 128
	var big := n * SS
	var img := Image.create_empty(big, big, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))

	# 4 px of margin at final scale, so the outline and its anti-aliasing have
	# somewhere to live and never touch the texture edge.
	var half := (big - 8 * SS) * 0.5
	var centre := Vector2(big, big) * 0.5

	if shape == Types.PacketShape.CIRCLE:
		# The circle's geometry is the one shape not expressed as a polygon —
		# `PacketStyle` signals it with an empty array and draws an arc.
		_disc(img, centre, half, GLYPH_OUTLINE)
		_disc(img, centre, half * GLYPH_CORE, Color.WHITE)
		img.resize(n, n, Image.INTERPOLATE_LANCZOS)
		return img

	var unit := PacketStyle.shape_points(shape)
	_polygon(img, _scaled(unit, centre, half), GLYPH_OUTLINE)
	_polygon(img, _scaled(unit, centre, half * GLYPH_CORE), Color.WHITE)
	img.resize(n, n, Image.INTERPOLATE_LANCZOS)
	return img


func _scaled(unit: PackedVector2Array, centre: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in unit:
		out.append(centre + p * radius)
	return out


# ---------------------------------------------------------------------------
# Overlays — 6
# ---------------------------------------------------------------------------

func _overlays() -> void:
	# Ownership is the badge FILL, ringed in its opposite: light for the Hacker,
	# dark for the System. It is the one convention that survives from the alpha
	# unchanged, because it reads at thumb size with no legend.
	_save("overlay/badge_player", _badge(PacketStyle.BADGE_PLAYER, PacketStyle.BADGE_ENEMY), 0)
	_save("overlay/badge_enemy", _badge(PacketStyle.BADGE_ENEMY, PacketStyle.BADGE_PLAYER), 0)

	var names := ["bomb", "buff", "shield", "override"]
	for t in Tile.Special.Type.size():
		_save("overlay/ring_%s" % names[t], _type_ring(PacketStyle.OVERLAY_TINT[t]), 0)

	# The badge's centre MARK, as art rather than as a character (D-038).
	#
	# These were `draw_string` glyphs — "S", "Ø", "?", "+" — pulled from
	# `ThemeDB.fallback_font`. Two problems with that. A font is a dependency
	# nobody chose: `Ø` in particular is not guaranteed to exist in whatever
	# face a device falls back to, and a missing glyph renders as a box on the
	# one mark that has to be unambiguous. And a letterform cannot be
	# art-directed — the art pass could restyle everything on screen EXCEPT the
	# four marks carrying the most specific information on the board.
	#
	# Authored white with alpha and tinted at runtime, so ownership keeps
	# working exactly as it does now: the mark takes the badge's opposite
	# colour, dark on a Hacker badge and light on a System one.
	#
	# With the type ring suspended (D-037), these become the SOLE type signal,
	# which is how the alpha has always done it. That raises the bar on their
	# legibility, so each is a silhouette rather than a letter.
	_save("overlay/mark_bomb", _mark_bomb(), 0)
	_save("overlay/mark_buff", _mark_buff(), 0)
	_save("overlay/mark_shield", _mark_shield(), 0)
	_save("overlay/mark_override", _mark_override(), 0)


## The ownership badge: a filled disc with a ring straddling its edge.
func _badge(face: Color, mark: Color) -> Image:
	var n := 128
	var big := n * SS
	var img := Image.create_empty(big, big, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))

	var centre := Vector2(big, big) * 0.5
	var badge_r := (big * 0.5) / OVERLAY_SPAN

	_disc(img, centre, badge_r, face)
	_annulus(img, centre, badge_r, badge_r * 0.16, mark)
	img.resize(n, n, Image.INTERPOLATE_LANCZOS)
	return img


## The special TYPE, as a thin outer ring.
##
## Type rides a ring rather than the badge face because the face is already
## spoken for by ownership, and both have to be readable at once.
func _type_ring(tint: Color) -> Image:
	var n := 128
	var big := n * SS
	var img := Image.create_empty(big, big, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))

	var centre := Vector2(big, big) * 0.5
	var badge_r := (big * 0.5) / OVERLAY_SPAN

	_annulus(img, centre, badge_r * 1.28, badge_r * 0.2, tint)
	img.resize(n, n, Image.INTERPOLATE_LANCZOS)
	return img


## A blank mark canvas plus the geometry helpers' shared setup. Every mark is
## authored in the same square so they read at one weight beside each other.
func _mark() -> Image:
	var img := Image.create_empty(64 * SS, 64 * SS, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	return img


## BOMB — a charge with a fuse.
##
## Reached only when a bomb has no countdown to show, which is the degenerate
## case: an armed bomb displays its remaining turns instead. The whitebox drew
## "?" here, which said "unknown" rather than "bomb". This is the one mark whose
## MEANING changed rather than just its rendering — flagged for the designer.
func _mark_bomb() -> Image:
	var img := _mark()
	var n := float(64 * SS)
	var centre := Vector2(n * 0.46, n * 0.58)
	_disc(img, centre, n * 0.30, Color.WHITE)
	_thick_line(img, centre + Vector2(n * 0.18, -n * 0.22),
		centre + Vector2(n * 0.34, -n * 0.42), n * 0.09, Color.WHITE)
	img.resize(64, 64, Image.INTERPOLATE_LANCZOS)
	return img


## BUFF — a plus. The one mark carried over unchanged, because a plus is
## already a silhouette rather than a letterform.
func _mark_buff() -> Image:
	var img := _mark()
	var n := 64 * SS
	var arm := int(n * 0.17)
	var span := int(n * 0.72)
	var off := (n - span) / 2
	img.fill_rect(Rect2i((n - arm) / 2, off, arm, span), Color.WHITE)
	img.fill_rect(Rect2i(off, (n - arm) / 2, span, arm), Color.WHITE)
	img.resize(64, 64, Image.INTERPOLATE_LANCZOS)
	return img


## SHIELD — a silhouette, replacing the letter "S".
##
## A shield is recognisable at badge size in a way a single letter is not, and
## it stops depending on a font having a legible capital S at ~40 px.
func _mark_shield() -> Image:
	var img := _mark()
	var n := float(64 * SS)
	var c := Vector2(n, n) * 0.5
	var r := n * 0.40
	_polygon(img, PackedVector2Array([
		c + Vector2(-0.95, -0.92) * r,
		c + Vector2(0.95, -0.92) * r,
		c + Vector2(0.95, 0.14) * r,
		c + Vector2(0.55, 0.66) * r,
		c + Vector2(0.0, 1.05) * r,
		c + Vector2(-0.55, 0.66) * r,
		c + Vector2(-0.95, 0.14) * r,
	]), Color.WHITE)
	img.resize(64, 64, Image.INTERPOLATE_LANCZOS)
	return img


## OVERRIDE — a slashed ring, which is what "Ø" was drawing anyway.
##
## The mark most worth taking off the font: `Ø` is the least likely of the four
## to exist in an arbitrary fallback face, and a missing glyph renders as a
## box on the Boss mechanic's only board-level signal.
func _mark_override() -> Image:
	var img := _mark()
	var n := float(64 * SS)
	var c := Vector2(n, n) * 0.5
	var r := n * 0.34
	_annulus(img, c, r, n * 0.115, Color.WHITE)
	_thick_line(img, c + Vector2(0.86, -0.86) * r, c + Vector2(-0.86, 0.86) * r,
		n * 0.115, Color.WHITE)
	img.resize(64, 64, Image.INTERPOLATE_LANCZOS)
	return img


# ---------------------------------------------------------------------------
# Icons — 4
# ---------------------------------------------------------------------------

func _icons() -> void:
	_save("icon/menu", _menu_icon(), 0)
	_save("icon/arrow_up", _arrow(true), 0)
	_save("icon/arrow_down", _arrow(false), 0)
	_save("icon/cancel", _cancel_icon(), 0)


func _menu_icon() -> Image:
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var bar_h := 6
	var inset := 10
	for i in 3:
		img.fill_rect(Rect2i(inset, 14 + i * 14, n - inset * 2, bar_h), PacketStyle.TEXT)
	return img


func _arrow(up: bool) -> Image:
	var n := 64
	var big := n * SS
	var img := Image.create_empty(big, big, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))

	var m := 12.0 * SS
	var pts := PackedVector2Array()
	if up:
		pts.append(Vector2(big * 0.5, m))
		pts.append(Vector2(big - m, big - m))
		pts.append(Vector2(m, big - m))
	else:
		pts.append(Vector2(m, m))
		pts.append(Vector2(big - m, m))
		pts.append(Vector2(big * 0.5, big - m))
	_polygon(img, pts, PacketStyle.TEXT)
	img.resize(n, n, Image.INTERPOLATE_LANCZOS)
	return img


## The cancel mark. Tapping an armed control is the standard cancel for every
## targeted Function, so this one icon serves whatever kind of target is being
## asked for.
func _cancel_icon() -> Image:
	var n := 64
	var big := n * SS
	var img := Image.create_empty(big, big, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))

	var m := 14.0 * SS
	var w := 5.0 * SS
	_thick_line(img, Vector2(m, m), Vector2(big - m, big - m), w, PacketStyle.DAMAGE)
	_thick_line(img, Vector2(big - m, m), Vector2(m, big - m), w, PacketStyle.DAMAGE)
	img.resize(n, n, Image.INTERPOLATE_LANCZOS)
	return img


# ---------------------------------------------------------------------------
# Text-derived art (beta 0.3.2)
# ---------------------------------------------------------------------------
#
# The title logo and the countdown digits are ART, not text: after this build no
# gameplay surface depends on a typeface at runtime (authorization §11.2, §12).
#
# They are nonetheless RASTERISED FROM THE BUNDLED FONTS at build time, which is
# what makes them coordinated rather than merely consistent — the digits are the
# game's own numerals and the wordmark is its own UI face. Hand-drawing either
# would have produced art that drifts from the interface around it.
#
# FreeType is CPU-side, so this works with no rendering device.

const SANS_BOLD := "res://assets/fonts/IBMPlexSans-SemiBold.ttf"
const MONO := "res://assets/fonts/IBMPlexMono-Regular.ttf"

## Countdown digits are authored on one square canvas so they compose without
## per-digit nudging. A monospace face makes that honest — every advance is
## already equal.
const DIGIT_PX := 96


func _text_art() -> void:
	# §12 — the start screen's wordmark. Tracked, because a title set solid at
	# this size reads as a word rather than a mark.
	_save("chrome/title_logo", _text_image(SANS_BOLD, "1C38R34KR", 180, 14), 0)

	# §11 — ten individually addressable digits, keyed by value.
	for d in 10:
		_save("overlay/digit_%d" % d, _digit_image(d), 0)


## One digit, centred on a fixed square canvas.
func _digit_image(d: int) -> Image:
	var glyph := _text_image(MONO, str(d), DIGIT_PX, 0)
	var canvas := Image.create_empty(DIGIT_PX, DIGIT_PX, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(1, 1, 1, 0))
	canvas.blend_rect(
		glyph, Rect2i(0, 0, glyph.get_width(), glyph.get_height()),
		Vector2i((DIGIT_PX - glyph.get_width()) / 2, (DIGIT_PX - glyph.get_height()) / 2),
	)
	return canvas


## Rasterises `text` to a tightly-cropped white image with coverage in alpha.
##
## White so the renderer tints it — the digits take the badge's mark colour, so
## ownership polarity keeps working exactly as it does for the type marks.
func _text_image(font_path: String, text: String, px: int, tracking: int) -> Image:
	var font := FontFile.new()
	if font.load_dynamic_font(font_path) != OK:
		push_error("gen_assets: could not load %s" % font_path)
		return _solid(8, 8, PacketStyle.MISSING_A)

	var rids := font.get_rids()
	if rids.is_empty():
		push_error("gen_assets: %s produced no font RID" % font_path)
		return _solid(8, 8, PacketStyle.MISSING_A)

	var rid: RID = rids[0]
	var ts := TextServerManager.get_primary_interface()
	var key := Vector2i(px, 0)

	# Two passes: measure, then draw. A single pass would need the canvas sized
	# before the glyph metrics are known.
	var ascent := ts.font_get_ascent(rid, px)
	var descent := ts.font_get_descent(rid, px)
	var width := 0.0
	var glyphs: Array = []
	for ch in text:
		var idx := ts.font_get_glyph_index(rid, px, ch.unicode_at(0), 0)
		ts.font_render_glyph(rid, key, idx)
		glyphs.append(idx)
		width += ts.font_get_glyph_advance(rid, px, idx).x + tracking

	var w := int(ceil(width)) + 4
	var h := int(ceil(ascent + descent)) + 4
	var out := Image.create_empty(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	out.fill(Color(1, 1, 1, 0))

	var pen := 2.0
	for idx in glyphs:
		var tex_idx := ts.font_get_glyph_texture_idx(rid, key, idx)
		if tex_idx >= 0:
			var atlas := ts.font_get_texture_image(rid, key, tex_idx)
			var uv := ts.font_get_glyph_uv_rect(rid, key, idx)
			var off := ts.font_get_glyph_offset(rid, key, idx)
			_blit_coverage(
				atlas, Rect2i(uv.position, uv.size), out,
				Vector2i(int(pen + off.x) + 2, int(ascent + off.y) + 2),
			)
		pen += ts.font_get_glyph_advance(rid, px, idx).x + tracking

	return _crop_to_content(out)


## Copies a glyph out of the font atlas as white-with-alpha.
##
## The atlas is LA8 — luminance and coverage. Only coverage matters here: the
## art is authored white so the renderer can tint it, exactly as the Packet
## glyphs and overlay marks are.
func _blit_coverage(atlas: Image, region: Rect2i, dest: Image, at: Vector2i) -> void:
	for y in region.size.y:
		for x in region.size.x:
			var sx := region.position.x + x
			var sy := region.position.y + y
			if sx < 0 or sy < 0 or sx >= atlas.get_width() or sy >= atlas.get_height():
				continue
			var src := atlas.get_pixel(sx, sy)
			# The atlas is LA8, which `get_pixel` surfaces as (l, l, l, a) with
			# luminance pinned at 1.0 across the glyph's whole bounding box.
			# Coverage lives in ALPHA alone — taking max(a, r) here filled every
			# box solid and turned the wordmark into nine white rectangles.
			var coverage: float = src.a
			if coverage <= 0.0:
				continue
			var dx := at.x + x
			var dy := at.y + y
			if dx < 0 or dy < 0 or dx >= dest.get_width() or dy >= dest.get_height():
				continue
			var prev := dest.get_pixel(dx, dy)
			dest.set_pixel(dx, dy, Color(1, 1, 1, maxf(prev.a, coverage)))


## Trims fully transparent rows and columns, so the caller controls padding
## rather than inheriting the font's.
func _crop_to_content(img: Image) -> Image:
	var min_x := img.get_width()
	var min_y := img.get_height()
	var max_x := -1
	var max_y := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return img
	return img.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))


# ---------------------------------------------------------------------------
# Raster primitives
# ---------------------------------------------------------------------------

func _solid(w: int, h: int, colour: Color) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(colour)
	return img


## A square chrome tile: flat fill, border drawn INWARD from the edge.
##
## Border width is authored in source pixels and matches what the StyleBoxFlat
## it replaces used, so nothing changes thickness on screen. 9-slicing keeps the
## border at the edge whatever the control's size, which is exactly what a
## StyleBoxFlat border did.
func _box(n: int, fill: Color, border: int, edge: Color) -> Image:
	var img := _solid(n, n, fill)
	for i in border:
		img.fill_rect(Rect2i(i, i, n - i * 2, 1), edge)
		img.fill_rect(Rect2i(i, n - 1 - i, n - i * 2, 1), edge)
		img.fill_rect(Rect2i(i, i, 1, n - i * 2), edge)
		img.fill_rect(Rect2i(n - 1 - i, i, 1, n - i * 2), edge)
	return img


## A rectangular ring: a band of `t` pixels just inside the edge, transparent
## within and without.
func _rect_ring(n: int, t: int, colour: Color) -> Image:
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for i in t:
		img.fill_rect(Rect2i(i, i, n - i * 2, 1), colour)
		img.fill_rect(Rect2i(i, n - 1 - i, n - i * 2, 1), colour)
		img.fill_rect(Rect2i(i, i, 1, n - i * 2), colour)
		img.fill_rect(Rect2i(n - 1 - i, i, 1, n - i * 2), colour)
	return img


func _rounded(w: int, h: int, radius: int, colour: Color) -> Image:
	var big_w := w * SS
	var big_h := h * SS
	var r := float(radius * SS)
	var img := Image.create_empty(big_w, big_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for y in big_h:
		for x in big_w:
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var cx := clampf(px, r, big_w - r)
			var cy := clampf(py, r, big_h - r)
			if Vector2(px - cx, py - cy).length() <= r:
				img.set_pixel(x, y, colour)
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	return img


func _disc(img: Image, centre: Vector2, radius: float, colour: Color) -> void:
	var lo := Vector2i(maxi(0, int(centre.x - radius) - 1), maxi(0, int(centre.y - radius) - 1))
	var hi := Vector2i(
		mini(img.get_width(), int(centre.x + radius) + 2),
		mini(img.get_height(), int(centre.y + radius) + 2),
	)
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			if Vector2(x + 0.5, y + 0.5).distance_to(centre) <= radius:
				img.set_pixel(x, y, colour)


## A ring whose band STRADDLES `radius`, matching `draw_arc`'s convention — the
## live renderer centres the stroke on the radius rather than drawing it inside.
func _annulus(img: Image, centre: Vector2, radius: float, thickness: float, colour: Color) -> void:
	var inner := radius - thickness * 0.5
	var outer := radius + thickness * 0.5
	var lo := Vector2i(maxi(0, int(centre.x - outer) - 1), maxi(0, int(centre.y - outer) - 1))
	var hi := Vector2i(
		mini(img.get_width(), int(centre.x + outer) + 2),
		mini(img.get_height(), int(centre.y + outer) + 2),
	)
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			if d >= inner and d <= outer:
				img.set_pixel(x, y, colour)


func _polygon(img: Image, pts: PackedVector2Array, colour: Color) -> void:
	if pts.size() < 3:
		return
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var x0 := maxi(0, int(lo.x) - 1)
	var y0 := maxi(0, int(lo.y) - 1)
	var x1 := mini(img.get_width(), int(hi.x) + 2)
	var y1 := mini(img.get_height(), int(hi.y) + 2)
	for y in range(y0, y1):
		for x in range(x0, x1):
			if _inside(pts, Vector2(x + 0.5, y + 0.5)):
				img.set_pixel(x, y, colour)


## Even-odd point-in-polygon. Handles the star and the cross, which are both
## concave and would break a convex-only test.
func _inside(pts: PackedVector2Array, p: Vector2) -> bool:
	var hit := false
	var n := pts.size()
	var j := n - 1
	for i in n:
		var a := pts[i]
		var b := pts[j]
		if (a.y > p.y) != (b.y > p.y):
			if p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
				hit = not hit
		j = i
	return hit


func _thick_line(img: Image, a: Vector2, b: Vector2, width: float, colour: Color) -> void:
	var d := b - a
	var length := d.length()
	if length <= 0.0:
		return
	var dir := d / length
	var normal := Vector2(-dir.y, dir.x) * (width * 0.5)
	_polygon(img, PackedVector2Array([a + normal, b + normal, b - normal, a - normal]), colour)


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

func _save(key: String, img: Image, slice_margin: int, stretch := "") -> void:
	var path := "%s/%s.png" % [OUT, key]
	var err := img.save_png(path)
	if err != OK:
		push_error("gen_assets: could not write %s (error %d)" % [path, err])
		return
	_manifest.append({
		"key": key.get_file(),
		"path": "%s.png" % key,
		"w": img.get_width(),
		"h": img.get_height(),
		"alpha": img.detect_alpha() != Image.ALPHA_NONE,
		"slice": slice_margin,
		"stretch": stretch,
	})
	print("  %-34s %4d×%-4d %s" % [
		key, img.get_width(), img.get_height(),
		"9-slice %d" % slice_margin if slice_margin > 0 else stretch,
	])


## The manifest is the Gate-B inspection index and the input to the contact
## sheet. Written as JSON so it can be read by something other than a human.
func _write_manifest() -> void:
	var f := FileAccess.open("%s/manifest.json" % OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"pack": "v0",
		"build": Content.GAME_VERSION,
		"count": _manifest.size(),
		"assets": _manifest,
	}, "  "))
	f.close()

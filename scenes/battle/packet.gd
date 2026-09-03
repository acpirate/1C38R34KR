class_name PacketView
extends Control

## One Packet on the Datastream.
##
## Draws itself from a view Dictionary — the same shape the logic layer puts in
## its events — rather than reading game state. That keeps the renderer strictly
## downstream: it can be reconstructed at any time from state alone, which is
## exactly what save and resume does.
##
## All appearance comes from `PacketStyle`. This file contains no colour value
## and no shape path (D-014).

## Overlay type names, in `Tile.Special.Type` order — the order the pack's mark
## and ring arrays are built in, so an index here is an index there.
##
## Taken from the logic layer rather than restated. It WAS restated, and beta
## 0.4 added two types: a private copy would have left every Capacitor and
## Logic Bomb drawing as a Bomb, since `find` returns -1 and the fallback is
## index 0. One list cannot disagree with itself.
const TYPE_NAMES := Resolve.SPECIAL_TYPE_NAMES

## The overlay's authored coordinate space, as a multiple of the badge radius.
## Mirrors `tools/gen_assets.gd`: badge and mark are separate textures drawn into
## one rect, so both sides have to agree on what that rect is.
const OVERLAY_SPAN := 1.38

## The live mark's size inside the badge face, as a multiple of the badge
## radius. Matches the optical size of the text it replaces.
const MARK_SCALE := 0.72

## Which cell this view occupies. Presentation-only: it seeds the neutral static
## so a given cell's noise is stable across redraws, and nothing else reads it.
var cell := Vector2i.ZERO

var view: Dictionary = {}:
	set(v):
		view = v
		queue_redraw()

var selected := false:
	set(v):
		selected = v
		queue_redraw()

var targeting := false:
	set(v):
		targeting = v
		queue_redraw()

## Which Packet axis ECHOFALL is hiding, or -1 for none (beta 0.4 §8.2).
##
## PRESENTATION ONLY. `view` still carries the true colour and shape, and every
## rule in the logic layer keeps reading them — this changes what is painted and
## nothing else, which is why it is a property of the view rather than a
## transformation applied to the data.
var hidden_axis := -1:
	set(v):
		hidden_axis = v
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var cell := rect.grow(-1.0)

	# The cell is drawn whether or not it holds a Packet, so the grid stays
	# continuous through a destroy or a fall instead of punching holes in itself.
	draw_texture_rect(Graphics.pack().packet_cell, cell, false)

	if view.is_empty():
		return

	var is_neutral: bool = str(view.get("kind", "standard")) == "neutral"

	if is_neutral:
		# A neutral has no colour and no shape, so it gets neither — it is
		# static. Still drawn procedurally (D-034): the noise is seeded per cell
		# so no two neutrals match, and a sprite cannot vary per cell.
		#
		# Concealment never touches a neutral: §8.2 requires neutrals to stay
		# recognisable as neutral rather than start looking matchable.
		_draw_static(cell)
	elif hidden_axis == Types.ConcealAxis.SHAPE:
		# Shape hidden: the static treatment, but carrying the Packet's REAL
		# colour. That is what keeps it distinguishable from a neutral, which
		# draws the same noise with no colour at all.
		_draw_static(cell, Graphics.palette(int(view.get("color", 0))))
	else:
		# The Packet IS the coloured glyph: no tile field behind it, sized so the
		# silhouette reaches near the cell edge. A white glyph on a coloured
		# square reads as a gem; this reads as a signal on a wire, and it leaves
		# the glyph's centre free for the ownership badge.
		#
		# ONE texture carries both tones — a white core and a grey outline — so
		# this single modulate produces the fill AND a proportionally darker edge
		# from one palette entry (D-036). Colour and shape stay independent, and
		# six glyphs cover thirty-six Packets.
		var radius := size.x * 0.46
		var glyph := Rect2(rect.get_center() - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		# Colour hidden: the real glyph, modulated white. The texture's white
		# core and grey outline survive, so the Packet still reads as a Packet
		# and its shape is still matchable by eye — only the axis is gone.
		var tint := (
			PacketStyle.CONCEALED_AXIS if hidden_axis == Types.ConcealAxis.COLOR
			else Graphics.palette(int(view.get("color", 0)))
		)
		draw_texture_rect(Graphics.glyph(int(view.get("shape", 0))), glyph, false, tint)

	if view.has("special"):
		_draw_overlay(rect, view["special"])

	if targeting:
		draw_style_box(Graphics.box(Graphics.pack().ring_targeting, 12), rect.grow(-1.0))
	elif selected:
		draw_style_box(Graphics.box(Graphics.pack().ring_selected, 12), rect.grow(-1.0))


## Deterministic per-cell noise, seeded from the cell coordinate.
##
## Stable on purpose: a texture that reshuffles every redraw reads as activity
## where there is none, and the board redraws constantly during playback. This
## uses its own arithmetic rather than `Rng` — nothing here may draw from the
## game's stream, or the renderer would be able to change the battle.
## `tint` multiplies both static tones. White — the default — is the ordinary
## neutral. ECHOFALL passes a Packet's real colour so a shape-concealed Packet
## is visibly a coloured thing rather than a neutral.
func _draw_static(area: Rect2, tint := Color.WHITE) -> void:
	draw_rect(area, PacketStyle.NEUTRAL_STATIC_DARK * tint, true)
	var steps := 6
	var step := area.size / float(steps)
	var h := (cell.x * 73856093) ^ (cell.y * 19349663)
	for y in steps:
		for x in steps:
			h = (h * 1103515245 + 12345) & 0x7fffffff
			if h % 5 < 2:
				draw_rect(Rect2(area.position + Vector2(x, y) * step, step), PacketStyle.NEUTRAL_STATIC_LIGHT * tint, true)


## Overlays read as a badge CENTRED in the glyph, not a full-Packet treatment:
## the Packet's own colour and shape stay legible around it, because the player
## still has to match it.
##
## Ownership is the badge's fill — light for the Hacker, dark for the System,
## each ringed and lettered in the other. That single convention carries
## ownership for every overlay type without a legend, which is why the badge is
## centred rather than tucked in a corner where it competes with nothing.
##
## An ARMED overlay shows its remaining countdown whatever it will eventually
## deliver. That distinction is load-bearing: a pending Buff contributes nothing
## until it delivers, and the board must not imply otherwise.
func _draw_overlay(rect: Rect2, special: Dictionary) -> void:
	var type_index := TYPE_NAMES.find(str(special.get("type", "bomb")))
	if type_index < 0:
		type_index = 0

	var player := str(special.get("owner", "player")) == "player"

	# The overlay is authored in one coordinate space spanning the type ring's
	# full extent — 1.38 × the badge radius — so the badge and its mark stay
	# concentric without either knowing the other's size. `gen_assets.gd` holds
	# the same constant.
	var badge_r := size.x * 0.22
	var span := badge_r * OVERLAY_SPAN
	var centre := rect.get_center()
	var area := Rect2(centre - Vector2(span, span), Vector2(span, span) * 2.0)

	# Ownership is the badge's FILL — light for the Hacker, dark for the System,
	# each ringed in the other. One convention carries ownership for every
	# overlay type without a legend, which is why the badge is centred rather
	# than tucked in a corner where it competes with nothing.
	draw_texture_rect(Graphics.badge(player), area, false)

	# D-037 — TYPE RING SUSPENDED.
	#
	# A beta-era addition the alpha never had: `view.ts` carries type on the
	# badge's centre mark ALONE. It was never recorded as a decision, and the
	# differential could not catch it because the scene layer has no automated
	# coverage.
	#
	# It cost more than it looked like. The ring pushed the overlay from the
	# alpha's 0.45 × cell to 0.61 — about 35% wider — which is most of why a
	# compact glyph all but disappeared underneath one. Removing it restores
	# alpha parity AND gives the Packet's shape back, in the same move.
	#
	# Suspended, not deleted: the question of how to distinguish overlays is with
	# the designer. `Graphics.ring()` and the four PNGs are retained so restoring
	# it is one line here and no change to the contract.
	#
	# draw_texture_rect(Graphics.ring(type_index), area, false)

	var mark: Color = PacketStyle.BADGE_ENEMY if player else PacketStyle.BADGE_PLAYER
	var countdown := int(special.get("countdown", 0))

	# An ARMED overlay shows its remaining countdown whatever it will eventually
	# deliver. That distinction is load-bearing: a pending Buff contributes
	# nothing until it delivers, and the board must not imply otherwise.
	if special.has("countdown") and countdown > 0:
		_draw_countdown(centre, badge_r, countdown, mark)
		return

	# D-038 — a LIVE overlay's type is art, not a font character.
	#
	# These were "S", "Ø", "?" and "+" from `ThemeDB.fallback_font`. `Ø` in
	# particular is not guaranteed to exist in whatever face a device falls back
	# to, and a missing glyph renders as a box — on the Boss mechanic's only
	# board-level signal. With the ring suspended this mark is the WHOLE type
	# signal, so it is authored as a silhouette rather than a letter.
	#
	# Tinted with the badge's opposite colour, so ownership keeps working exactly
	# as before.
	var m := badge_r * MARK_SCALE
	draw_texture_rect(
		Graphics.mark(type_index),
		Rect2(centre - Vector2(m, m), Vector2(m, m) * 2.0), false, mark,
	)


## The remaining turns on an armed overlay, composed from digit ART (§11).
##
## The last font dependency on the board, retired: after this nothing on the
## Datastream loads a typeface. The digits were drawn with
## `ThemeDB.fallback_font`, so a countdown's legibility depended on whatever
## face a device happened to supply — the same exposure D-038 removed from the
## four type marks.
##
## Composed left to right from the value's own digits, so a two-digit countdown
## already works (§11.3). Current content never exceeds 9, but the renderer not
## being ABLE to show 10 would be a limit hiding in the view layer.
##
## Multi-digit numbers narrow each glyph so the pair still fits inside the badge
## rather than spilling over its ring.
func _draw_countdown(centre: Vector2, badge_r: float, countdown: int, colour: Color) -> void:
	var text := str(maxi(0, countdown))
	var count := text.length()

	var height := badge_r * MARK_SCALE * 2.0
	var width := height if count == 1 else height * 0.62
	var total := width * count
	var x := centre.x - total * 0.5

	for ch in text:
		var d := ch.to_int()
		draw_texture_rect(
			Graphics.digit(d),
			Rect2(Vector2(x, centre.y - height * 0.5), Vector2(width, height)),
			false, colour,
		)
		x += width

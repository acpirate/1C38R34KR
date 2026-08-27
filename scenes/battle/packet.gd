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


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var cell := rect.grow(-1.0)

	# The cell is drawn whether or not it holds a Packet, so the grid stays
	# continuous through a destroy or a fall instead of punching holes in itself.
	draw_rect(cell, PacketStyle.CELL_BACKGROUND, true)

	if view.is_empty():
		return

	var is_neutral: bool = str(view.get("kind", "standard")) == "neutral"

	if is_neutral:
		# A neutral has no colour and no shape, so it gets neither — it is
		# static. That is also why it can never hold an overlay.
		_draw_static(cell)
	else:
		# The Packet IS the coloured glyph: no tile field behind it, filled in
		# its colour and outlined in that colour's dark shade, sized so the
		# silhouette reaches near the cell edge. A white glyph on a coloured
		# square reads as a gem; this reads as a signal on a wire, and it leaves
		# the glyph's centre free for the ownership badge.
		var color_index := int(view.get("color", 0))
		PacketStyle.draw_shape(
			self, int(view.get("shape", 0)),
			rect.get_center(), size.x * 0.46,
			PacketStyle.COLOR_FILL[color_index],
			PacketStyle.COLOR_BORDER[color_index],
		)

	if view.has("special"):
		_draw_overlay(rect, view["special"])

	if targeting:
		draw_rect(rect.grow(-1.0), PacketStyle.TARGETING, false, maxf(2.0, size.x * 0.07))
	elif selected:
		draw_rect(rect.grow(-1.0), PacketStyle.SELECTION, false, maxf(2.0, size.x * 0.07))


## Deterministic per-cell noise, seeded from the cell coordinate.
##
## Stable on purpose: a texture that reshuffles every redraw reads as activity
## where there is none, and the board redraws constantly during playback. This
## uses its own arithmetic rather than `Rng` — nothing here may draw from the
## game's stream, or the renderer would be able to change the battle.
func _draw_static(area: Rect2) -> void:
	draw_rect(area, PacketStyle.NEUTRAL_STATIC_DARK, true)
	var steps := 6
	var step := area.size / float(steps)
	var h := (cell.x * 73856093) ^ (cell.y * 19349663)
	for y in steps:
		for x in steps:
			h = (h * 1103515245 + 12345) & 0x7fffffff
			if h % 5 < 2:
				draw_rect(Rect2(area.position + Vector2(x, y) * step, step), PacketStyle.NEUTRAL_STATIC_LIGHT, true)


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
	# D-037 — the type ring is SUSPENDED. Left commented rather than deleted
	# because the decision is "not now", not "never"; see the block below.
	# var type_index := ["bomb", "buff", "shield", "override"].find(str(special.get("type", "bomb")))
	# if type_index < 0:
	# 	type_index = 0

	var player := str(special.get("owner", "player")) == "player"
	var face: Color = PacketStyle.BADGE_PLAYER if player else PacketStyle.BADGE_ENEMY
	var mark: Color = PacketStyle.BADGE_ENEMY if player else PacketStyle.BADGE_PLAYER

	var badge_r := size.x * 0.22
	var centre := rect.get_center()
	draw_circle(centre, badge_r, face)
	draw_arc(centre, badge_r, 0, TAU, 24, mark, badge_r * 0.16, true)

	# D-037 — TYPE RING SUSPENDED.
	#
	# This was a beta-era addition that the alpha never had: `view.ts` carries
	# type on the badge's centre mark ALONE, and nothing else. It was never
	# recorded as a decision, and the differential could not catch it because
	# the scene layer has no automated coverage.
	#
	# It also cost more than it looked like. The ring pushed the overlay from
	# the alpha's 0.45 × cell out to 0.61 — about 35% wider — which is most of
	# why a compact glyph (a diamond, a circle) all but disappears under an
	# overlay. Removing it restores alpha parity AND gives the Packet's shape
	# back, which is the same move twice.
	#
	# Suspended rather than deleted: the director is taking the question of how
	# to distinguish overlays to the designer, so this may return in some form.
	# `OVERLAY_TINT` and the four ring PNGs are retained for that reason.
	#
	# draw_arc(centre, badge_r * 1.28, 0, TAU, 24, PacketStyle.OVERLAY_TINT[type_index], badge_r * 0.2, true)

	var countdown := int(special.get("countdown", 0))
	var armed := special.has("countdown") and countdown > 0
	var text := str(countdown) if armed else _live_glyph(str(special.get("type", "bomb")))
	if text == "":
		return

	var font := ThemeDB.fallback_font
	var fs := int(badge_r * 1.5)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(
		font, centre + Vector2(-w * 0.5, badge_r * 0.52), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, mark,
	)


## What a LIVE overlay reads as, once it is no longer counting down.
func _live_glyph(type_name: String) -> String:
	match type_name:
		"shield":
			return "S"
		"override":
			return "Ø"
		"bomb":
			return "?"
		_:
			return "+"

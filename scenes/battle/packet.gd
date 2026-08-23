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
	if view.is_empty():
		return

	var rect := Rect2(Vector2.ZERO, size)
	var inset := rect.grow(-size.x * 0.04)
	var is_neutral: bool = str(view.get("kind", "standard")) == "neutral"
	var color_index := int(view.get("color", 0))

	var fill := PacketStyle.fill_for(is_neutral, color_index)
	var border := PacketStyle.border_for(is_neutral, color_index)
	var radius := size.x * 0.16

	draw_rect(inset, fill, true)
	draw_rect(inset, border, false, maxf(1.0, size.x * 0.05))

	# A neutral has no axes, so it carries no glyph — which is also why it can
	# never hold an overlay.
	if not is_neutral:
		PacketStyle.draw_shape(
			self, int(view.get("shape", 0)),
			rect.get_center(), size.x * 0.30,
			PacketStyle.GLYPH, border,
		)

	if view.has("special"):
		_draw_overlay(rect, view["special"])

	if targeting:
		draw_rect(rect.grow(-1.0), PacketStyle.TARGETING, false, maxf(2.0, size.x * 0.07))
	elif selected:
		draw_rect(rect.grow(-1.0), PacketStyle.SELECTION, false, maxf(2.0, size.x * 0.07))


## Overlays read as a corner badge rather than a full-Packet treatment, so the
## underlying colour and shape stay legible — the player still has to match it.
##
## An ARMED overlay shows its remaining countdown; a live one shows a dot. That
## distinction is load-bearing: a pending Buff contributes nothing until it
## delivers, and the board must not imply otherwise.
func _draw_overlay(rect: Rect2, special: Dictionary) -> void:
	var type_index := ["bomb", "buff", "shield", "override"].find(str(special.get("type", "bomb")))
	if type_index < 0:
		type_index = 0
	var tint: Color = PacketStyle.OVERLAY_TINT[type_index]

	var badge_r := size.x * 0.19
	var centre := Vector2(size.x - badge_r * 1.2, badge_r * 1.2)
	draw_circle(centre, badge_r, tint)
	draw_arc(centre, badge_r, 0, TAU, 20, PacketStyle.BOARD_BACKGROUND, badge_r * 0.22, true)

	# Ownership at a glance: the enemy's overlays get a dark ring.
	if str(special.get("owner", "player")) == "enemy":
		draw_arc(centre, badge_r * 1.35, 0, TAU, 20, PacketStyle.BOARD_BACKGROUND, badge_r * 0.3, true)

	if special.has("countdown"):
		var font := ThemeDB.fallback_font
		var text := str(int(special["countdown"]))
		var fs := int(badge_r * 1.6)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(
			font, centre + Vector2(-w * 0.5, badge_r * 0.55), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PacketStyle.BOARD_BACKGROUND,
		)

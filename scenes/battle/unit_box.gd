class_name UnitBox
extends Control

## One Program's control: binding, name, charge, and readiness.
##
## Used for BOTH sides. The System's Programs are drawn with the same box as the
## Hacker's because the System's charge state is information the player
## schedules around — hiding it turns every enemy activation into a surprise,
## and the alpha's two-column layout exists precisely to prevent that. The only
## difference is that the System's boxes do not accept input.
##
## Drawn rather than assembled from Labels and a ProgressBar: it is four pieces
## of text and two rects at a fixed size, and drawing it directly is both fewer
## nodes and far less fighting with container sizing on a phone.

signal pressed

const HEIGHT := 44.0

var label := "":
	set(v):
		label = v
		queue_redraw()

var charge := 0:
	set(v):
		charge = v
		queue_redraw()

var cost := 1:
	set(v):
		cost = maxi(1, v)
		queue_redraw()

## The Packet identity this Program draws charge from. Shown as a swatch in the
## same coloured-glyph style as the board, so the link between "this Packet" and
## "this Program fills" needs no explanation.
var binding_color := -1
var binding_shape := -1

## True only for a Hacker Program the player could fire right now. A charged
## System Program is charged, never "ready" — it is not the player's to fire.
var actionable := false:
	set(v):
		actionable = v
		queue_redraw()

## Set while this control is armed and waiting for a target. It stays lit while
## everything else dims, and carries the cancel marker.
var armed := false:
	set(v):
		armed = v
		queue_redraw()

## Set while some OTHER control is armed, so this one is not a legal thing to
## touch. Recedes rather than disappearing — the information stays readable.
var dimmed := false:
	set(v):
		dimmed = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_binding(color_index: int, shape_index: int) -> void:
	binding_color = color_index
	binding_shape = shape_index
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var charged := charge >= cost

	if dimmed:
		modulate = PacketStyle.TINT_INACTIVE
	else:
		modulate = PacketStyle.TINT_NONE

	draw_rect(rect, PacketStyle.BOX, true)

	# Border state carries the whole readiness story: idle, charged, and
	# charged-and-yours are three different edges rather than three shades of
	# the same one.
	var edge: Color = PacketStyle.BOX_EDGE
	var width := 1.0
	if charged:
		edge = PacketStyle.READY if actionable else PacketStyle.ACCENT
		width = 2.0
	if armed:
		edge = PacketStyle.ACCENT_HOT
		width = 3.0
	draw_rect(rect.grow(-width * 0.5), edge, false, width)

	var pad := 5.0
	var swatch := 15.0
	var text_x := pad + swatch + 5.0

	if binding_color >= 0 and binding_shape >= 0:
		PacketStyle.draw_shape(
			self, binding_shape,
			Vector2(pad + swatch * 0.5, pad + swatch * 0.5), swatch * 0.5,
			PacketStyle.COLOR_FILL[binding_color], PacketStyle.COLOR_BORDER[binding_color],
		)

	var font := ThemeDB.fallback_font
	var name_size := 13
	draw_string(
		font, Vector2(text_x, pad + swatch * 0.85), label,
		HORIZONTAL_ALIGNMENT_LEFT, size.x - text_x - pad, name_size, PacketStyle.TEXT,
	)

	var charge_text := "%d/%d" % [charge, cost]
	draw_string(
		font, Vector2(pad, size.y - 11.0), charge_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		PacketStyle.CHARGE_TEXT_READY if charged else PacketStyle.TEXT_DIM,
	)

	var bar := Rect2(pad, size.y - 8.0, size.x - pad * 2.0, 5.0)
	draw_rect(bar, PacketStyle.CHARGE_TRACK, true)
	var filled := bar
	filled.size.x = bar.size.x * minf(1.0, float(charge) / float(cost))
	draw_rect(filled, PacketStyle.CHARGE_FILL_READY if charged else PacketStyle.CHARGE_FILL, true)

	if armed:
		_draw_cancel(rect)


## The armed control's cancel affordance. Tapping an armed control is the
## standard cancel for every targeted Function, so the marker is identical
## whatever kind of target is being asked for.
func _draw_cancel(rect: Rect2) -> void:
	var m := 7.0
	var c := Vector2(rect.size.x - m - 6.0, rect.size.y * 0.5)
	draw_line(c + Vector2(-m, -m), c + Vector2(m, m), PacketStyle.DAMAGE, 3.0, true)
	draw_line(c + Vector2(m, -m), c + Vector2(-m, m), PacketStyle.DAMAGE, 3.0, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if not event.pressed:
			pressed.emit()

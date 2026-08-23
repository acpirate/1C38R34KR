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

## The alpha's 40 px box, scaled to this project's base viewport.
##
## Everything inside is derived from this height rather than fixed, so the box
## stays internally proportioned if it ever changes — a 40 px layout stretched
## to 100 px with 13 px text in it reads as a mostly-empty rectangle.
static func height() -> float:
	return float(UiTheme.px(40))

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

## True between a press and its release. See `_gui_input`.
var _latched := false


## Drops a latched press without emitting.
##
## Used when something upstream claims the gesture — a two-finger scroll that
## started on top of this control. Without it the latch survives, and the next
## release anywhere fires a Function the player never chose.
func release() -> void:
	_latched = false


func _init() -> void:
	custom_minimum_size.y = height()
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

	# Three rows in a fixed height: name, charge, bar. Proportions rather than
	# constants, so the box reads the same at any scale.
	var pad := size.y * 0.10
	var swatch := size.y * 0.30
	var text_x := pad + swatch + pad
	var bar_h := size.y * 0.11

	if binding_color >= 0 and binding_shape >= 0:
		PacketStyle.draw_shape(
			self, binding_shape,
			Vector2(pad + swatch * 0.5, pad + swatch * 0.5), swatch * 0.5,
			PacketStyle.COLOR_FILL[binding_color], PacketStyle.COLOR_BORDER[binding_color],
		)

	var font := ThemeDB.fallback_font

	# Shrink-to-fit rather than clip. Program names are authored content and
	# E-BOMBER is a good deal wider than WEASEL; a name that runs off the edge
	# of its own control is worse than one drawn a point smaller.
	var name_size := int(size.y * 0.28)
	var name_room := size.x - text_x - pad
	while name_size > 10 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > name_room:
		name_size -= 1
	draw_string(
		font, Vector2(text_x, pad + swatch * 0.82), label,
		HORIZONTAL_ALIGNMENT_LEFT, name_room, name_size, PacketStyle.TEXT,
	)

	var charge_size := int(size.y * 0.22)
	draw_string(
		font, Vector2(pad, size.y - bar_h * 2.2), "%d/%d" % [charge, cost],
		HORIZONTAL_ALIGNMENT_LEFT, -1, charge_size,
		PacketStyle.CHARGE_TEXT_READY if charged else PacketStyle.TEXT_DIM,
	)

	var bar := Rect2(pad, size.y - bar_h - pad * 0.5, size.x - pad * 2.0, bar_h)
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
	var m := rect.size.y * 0.18
	var c := Vector2(rect.size.x - m - rect.size.y * 0.15, rect.size.y * 0.5)
	var w := maxf(2.0, rect.size.y * 0.06)
	draw_line(c + Vector2(-m, -m), c + Vector2(m, m), PacketStyle.DAMAGE, w, true)
	draw_line(c + Vector2(m, -m), c + Vector2(-m, m), PacketStyle.DAMAGE, w, true)


## Press/release pairing, not release alone.
##
## Android delivers a tap as an `InputEventScreenTouch` AND an emulated
## `InputEventMouseButton`, so emitting on every release fired this control
## TWICE per tap. For a targeted Function that read as arming and instantly
## cancelling: the first press armed it, the second hit the tap-again-to-cancel
## path. Latching on press and consuming the latch on release makes the second
## release of the pair a no-op whichever event type arrives first.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventMouseButton):
		return
	if event.pressed:
		_latched = true
		return
	if _latched:
		_latched = false
		pressed.emit()

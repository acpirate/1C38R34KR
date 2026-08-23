class_name AvatarBox
extends Control

## One side's identity and its LINK or ICE.
##
## Deliberately not a Label plus a ProgressBar: the stat has to read as a single
## object — the number sits INSIDE the bar, the way the alpha does it — and
## Godot's ProgressBar puts its text on top of a theme it does not share with
## anything else here. Twenty lines of `_draw` is cheaper than fighting that.

const HEIGHT := 46.0

var title := ""
var stat := ""
var value := 0
var maximum := 1
var bar_color: Color = PacketStyle.LINK_BAR

## Shield and Buff totals, shown compactly and hidden at zero. Zero is the
## normal case, and a row of zeroes is noise that trains the eye to skip the
## corner where the non-zero value will eventually appear.
var shield := 0
var buff := 0


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_stat(v: int, m: int) -> void:
	value = maxi(0, v)
	maximum = maxi(1, m)
	queue_redraw()


func set_totals(shield_value: int, buff_value: int) -> void:
	shield = shield_value
	buff = buff_value
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, PacketStyle.BOX, true)
	draw_rect(rect.grow(-0.5), PacketStyle.CONTROL_EDGE, false, 1.0)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(5, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PacketStyle.TEXT)

	var parts := PackedStringArray()
	if buff > 0:
		parts.append("B +%d" % buff)
	if shield > 0:
		parts.append("S %d" % shield)
	if parts.size() > 0:
		draw_string(
			font, Vector2(5, 14), "  ".join(parts),
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10, 12, PacketStyle.CHARGE_TEXT_READY,
		)

	var bar := Rect2(4, size.y - 22, size.x - 8, 18)
	draw_rect(bar, PacketStyle.CHARGE_TRACK, true)
	var filled := bar
	filled.size.x = bar.size.x * clampf(float(value) / float(maximum), 0.0, 1.0)
	draw_rect(filled, bar_color, true)
	draw_rect(bar.grow(-0.5), PacketStyle.CONTROL_EDGE, false, 1.0)

	# Shrink-to-fit rather than truncate: "ICE 250/250" is longer than the two-
	# digit values this was first laid out against, and a clipped LINK total is
	# worse than a smaller one.
	var text := "%s %d/%d" % [stat, value, maximum]
	var fs := 12
	while fs > 8 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > bar.size.x - 10:
		fs -= 1
	draw_string(font, Vector2(bar.position.x + 6, bar.position.y + 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PacketStyle.TEXT_HEADING)

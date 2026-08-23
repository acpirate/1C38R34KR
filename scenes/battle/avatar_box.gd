class_name AvatarBox
extends Control

## One side's identity and its LINK or ICE.
##
## Deliberately not a Label plus a ProgressBar: the stat has to read as a single
## object — the number sits INSIDE the bar, the way the alpha does it — and
## Godot's ProgressBar puts its text on top of a theme it does not share with
## anything else here. Twenty lines of `_draw` is cheaper than fighting that.

## The alpha's 46 px avatar box, scaled to this project's base viewport. As with
## `UnitBox`, everything inside derives from this height.
static func height() -> float:
	return float(UiTheme.px(46))

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
	custom_minimum_size.y = height()
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
	var pad := size.y * 0.09
	var title_size := int(size.y * 0.26)
	var title_baseline := pad + title_size * 0.85

	# The System's display name can be long; the title shrinks to fit rather
	# than spilling into the Buff/Shield corner.
	var title_room := size.x - pad * 2.0
	while title_size > 10 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > title_room * 0.6:
		title_size -= 1
	draw_string(font, Vector2(pad, title_baseline), title, HORIZONTAL_ALIGNMENT_LEFT, title_room, title_size, PacketStyle.TEXT)

	var parts := PackedStringArray()
	if buff > 0:
		parts.append("B +%d" % buff)
	if shield > 0:
		parts.append("S %d" % shield)
	if parts.size() > 0:
		draw_string(
			font, Vector2(pad, title_baseline), "  ".join(parts),
			HORIZONTAL_ALIGNMENT_RIGHT, title_room, int(size.y * 0.24), PacketStyle.CHARGE_TEXT_READY,
		)

	var bar_h := size.y * 0.42
	var bar := Rect2(pad, size.y - bar_h - pad, size.x - pad * 2.0, bar_h)
	draw_rect(bar, PacketStyle.CHARGE_TRACK, true)
	var filled := bar
	filled.size.x = bar.size.x * clampf(float(value) / float(maximum), 0.0, 1.0)
	draw_rect(filled, bar_color, true)
	draw_rect(bar.grow(-0.5), PacketStyle.CONTROL_EDGE, false, 1.0)

	# Shrink-to-fit rather than truncate: "ICE 250/250" is longer than the two-
	# digit values this was first laid out against, and a clipped LINK total is
	# worse than a smaller one.
	var text := "%s %d/%d" % [stat, value, maximum]
	var fs := int(bar_h * 0.62)
	while fs > 10 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > bar.size.x - pad * 2.0:
		fs -= 1
	draw_string(
		font, Vector2(bar.position.x + pad, bar.position.y + bar_h * 0.5 + fs * 0.36), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PacketStyle.TEXT_HEADING,
	)

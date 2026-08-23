class_name UiTheme
extends RefCounted

## One Theme, built once and set on the root Control so every screen inherits it.
##
## The alternative is styling controls at each call site, which is how a UI ends
## up with four slightly different buttons. Every colour comes from
## `PacketStyle` — this file decides SHAPE (padding, border width, corner
## radius), the registry decides colour.


static func build() -> Theme:
	var theme := Theme.new()

	theme.set_stylebox("normal", "Button", _button_box(PacketStyle.CONTROL, PacketStyle.CONTROL_EDGE))
	theme.set_stylebox("hover", "Button", _button_box(PacketStyle.CONTROL, PacketStyle.ACCENT))
	theme.set_stylebox("pressed", "Button", _button_box(PacketStyle.PANEL_DEEP, PacketStyle.ACCENT))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# A disabled control keeps its shape and loses its contrast. Hiding it
	# instead would make the screen change size as state changes, which on a
	# phone moves the thing you were about to tap.
	var off := _button_box(PacketStyle.PANEL_DEEP, PacketStyle.PANEL_EDGE)
	theme.set_stylebox("disabled", "Button", off)

	theme.set_color("font_color", "Button", PacketStyle.TEXT)
	theme.set_color("font_hover_color", "Button", PacketStyle.TEXT_HEADING)
	theme.set_color("font_pressed_color", "Button", PacketStyle.TEXT_HEADING)
	theme.set_color("font_disabled_color", "Button", PacketStyle.TEXT_FAINT)
	theme.set_font_size("font_size", "Button", 16)

	theme.set_color("font_color", "Label", PacketStyle.TEXT)
	theme.set_font_size("font_size", "Label", 14)

	var field := StyleBoxFlat.new()
	field.bg_color = PacketStyle.CHARGE_TRACK
	field.border_color = PacketStyle.CONTROL_EDGE
	field.set_border_width_all(1)
	field.set_content_margin_all(6)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", PacketStyle.TEXT)

	return theme


static func _button_box(bg: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = edge
	box.set_border_width_all(1)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

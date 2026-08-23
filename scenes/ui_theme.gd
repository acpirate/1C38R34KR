class_name UiTheme
extends RefCounted

## One Theme, built once and set on the root Control so every screen inherits it.
##
## The alternative is styling controls at each call site, which is how a UI ends
## up with four slightly different buttons. Every colour comes from
## `PacketStyle`; this file decides SIZE and SHAPE.
##
## ## Why the numbers look large
##
## The design rule is: **text and controls are as large as they can be without
## overflowing.** A phone held at arm's length is not a monitor, and the beta's
## whole purpose is human playtesting — a readout nobody can read is a readout
## that does not exist.
##
## The sizes below are the alpha's, multiplied by `SCALE`. The alpha laid out
## against a 430 px CSS viewport; this project's base viewport is 1080 px wide
## and `canvas_items` stretch scales everything from that. Carrying the alpha's
## numbers across unchanged — which is what the first pass did — made every
## label two and a half times too small on a real device. The multiplier is
## named rather than baked in so that relationship stays visible: if the base
## viewport ever changes, this is the one number that moves.

## The alpha's design viewport, in CSS pixels.
const ALPHA_VIEWPORT := 430.0

## This project's base viewport width, from `project.godot`.
const BASE_VIEWPORT := 1080.0

const SCALE := BASE_VIEWPORT / ALPHA_VIEWPORT  ## ≈ 2.51


## An alpha CSS pixel measurement in this project's units.
static func px(alpha_px: float) -> int:
	return int(round(alpha_px * SCALE))


# Named sizes, each traceable to the alpha value it came from.
static func font_heading() -> int: return px(22)      ## .dialog h1
static func font_subheading() -> int: return px(15)   ## .dialog p
static func font_button() -> int: return px(19)       ## .dialog button
static func font_body() -> int: return px(15)         ## .metrics, .optline
static func font_small() -> int: return px(13)        ## .cfgnote
static func font_option_name() -> int: return px(18)  ## .optlist .optname

## Minimum tap target. The alpha's buttons come out around 45 px tall from
## padding plus line height; this rounds up rather than down, because a control
## that is slightly too tall costs a little screen and one that is slightly too
## short costs a mis-tap.
static func control_height() -> int: return px(46)


static func build() -> Theme:
	var theme := Theme.new()

	theme.set_stylebox("normal", "Button", _button_box(PacketStyle.CONTROL, PacketStyle.CONTROL_EDGE))
	theme.set_stylebox("hover", "Button", _button_box(PacketStyle.CONTROL, PacketStyle.ACCENT))
	theme.set_stylebox("pressed", "Button", _button_box(PacketStyle.PANEL_DEEP, PacketStyle.ACCENT))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# A disabled control keeps its shape and loses its contrast. Hiding it would
	# make the screen change size as state changes, which on a phone moves the
	# thing you were about to tap.
	theme.set_stylebox("disabled", "Button", _button_box(PacketStyle.PANEL_DEEP, PacketStyle.PANEL_EDGE))

	theme.set_color("font_color", "Button", PacketStyle.TEXT)
	theme.set_color("font_hover_color", "Button", PacketStyle.TEXT_HEADING)
	theme.set_color("font_pressed_color", "Button", PacketStyle.TEXT_HEADING)
	theme.set_color("font_disabled_color", "Button", PacketStyle.TEXT_FAINT)
	theme.set_font_size("font_size", "Button", font_button())

	theme.set_color("font_color", "Label", PacketStyle.TEXT)
	theme.set_font_size("font_size", "Label", font_body())

	var field := StyleBoxFlat.new()
	field.bg_color = PacketStyle.CHARGE_TRACK
	field.border_color = PacketStyle.CONTROL_EDGE
	field.set_border_width_all(1)
	field.set_content_margin_all(px(6))
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", PacketStyle.TEXT)
	theme.set_font_size("font_size", "LineEdit", font_button())

	return theme


static func _button_box(bg: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = edge
	box.set_border_width_all(1)
	box.content_margin_left = px(10)
	box.content_margin_right = px(10)
	box.content_margin_top = px(8)
	box.content_margin_bottom = px(8)
	return box

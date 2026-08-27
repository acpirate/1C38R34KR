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

	# Beta 0.3.1 — every stylebox below is now a `StyleBoxTexture` over an
	# asset-pack PNG rather than a flat colour. The MEASUREMENTS are unchanged:
	# content margins still come from `px()`, so nothing moves on screen and the
	# conversion is a change of skin, not of layout.
	#
	# 9-slicing is what makes that true. The source PNGs are 48×48 with a 16 px
	# margin, so corners never stretch and a 1 px border authored at the edge
	# stays 1 px at any control size — exactly what the `StyleBoxFlat` borders
	# they replace did.
	theme.set_stylebox("normal", "Button", _button_box(Graphics.pack().button_normal))
	theme.set_stylebox("pressed", "Button", _button_box(Graphics.pack().button_pressed))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# Hover is unreachable on both target devices, so the pack authors no art
	# for it (§4.8) and it borrows `normal`. If Windows becomes a target this is
	# where the distinct state goes back.
	theme.set_stylebox("hover", "Button", _button_box(Graphics.pack().button_normal))

	# A disabled control keeps its shape and loses its contrast. Hiding it would
	# make the screen change size as state changes, which on a phone moves the
	# thing you were about to tap.
	theme.set_stylebox("disabled", "Button", _button_box(Graphics.pack().button_disabled))

	theme.set_color("font_color", "Button", PacketStyle.TEXT)
	theme.set_color("font_hover_color", "Button", PacketStyle.TEXT_HEADING)
	theme.set_color("font_pressed_color", "Button", PacketStyle.TEXT_HEADING)
	theme.set_color("font_disabled_color", "Button", PacketStyle.TEXT_FAINT)
	theme.set_font_size("font_size", "Button", font_button())

	theme.set_color("font_color", "Label", PacketStyle.TEXT)
	theme.set_font_size("font_size", "Label", font_body())

	# A scrollbar wide enough to be a real target. Godot's default is a few
	# pixels — fine with a mouse, hopeless with a thumb. `TouchScroll`'s
	# two-finger gesture is the primary way to scroll; this is the visible
	# affordance that says the region scrolls at all, and the fallback for
	# anyone who reaches for the bar.
	theme.set_stylebox("scroll", "VScrollBar", _bar(Graphics.pack().scroll_track, 12))

	theme.set_stylebox("grabber", "VScrollBar", _bar(Graphics.pack().scroll_thumb, 12))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _bar(Graphics.pack().scroll_thumb, 12))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _bar(Graphics.pack().scroll_thumb, 12))

	# The seed entry is debug-only — the sole `LineEdit` in the game lives
	# behind `OS.is_debug_build()` — so the pack authors no art for it and it
	# keeps a flat box (§4.8). Its colours still come from the registry.
	var field := StyleBoxFlat.new()
	field.bg_color = PacketStyle.CHARGE_TRACK
	field.border_color = PacketStyle.CONTROL_EDGE
	field.set_border_width_all(1)
	field.set_content_margin_all(px(6))
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", PacketStyle.TEXT)
	theme.set_font_size("font_size", "LineEdit", font_button())

	return theme


## A 9-sliced chrome box carrying the button's content margins.
##
## A null texture yields the MISSING checker rather than a flat colour, so a
## pack that lost this asset looks broken instead of looking fine (§9.4).
static func _button_box(tex: Texture2D) -> StyleBoxTexture:
	var box := _sliced(tex, 16)
	box.content_margin_left = px(10)
	box.content_margin_right = px(10)
	box.content_margin_top = px(8)
	box.content_margin_bottom = px(8)
	return box


## Scrollbar chrome. The horizontal content margins are what give the bar its
## width — the same `px(7)` the flat boxes used, so the thumb stays a thumb-
## sized target.
static func _bar(tex: Texture2D, margin: int) -> StyleBoxTexture:
	var box := _sliced(tex, margin)
	box.content_margin_left = px(7)
	box.content_margin_right = px(7)
	return box


## The shared 9-slice setup.
##
## `axis_stretch_*` is STRETCH rather than TILE: these are flat fields with a
## border at the edge, and tiling a flat field is indistinguishable from
## stretching it while costing more draw calls. A textured fill would want TILE.
static func _sliced(tex: Texture2D, margin: int) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = tex if tex != null else Graphics.missing()
	box.set_texture_margin_all(margin)
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return box


# ---------------------------------------------------------------------------
# Safe area (beta 0.2 §20.1)
# ---------------------------------------------------------------------------
#
# Beta 0.1 protected only the battle screen, because it was the only screen that
# ran edge to edge. Beta 0.2 adds several top-level screens, so the policy moves
# here and every screen queries the same answer.
#
# Queried at runtime, never hardcoded: a cutout is per-device, and a constant
# that happened to suit the S25 would be wrong on the tablet and wrong again on
# the next phone.

## The safe-area inset, in this Control's coordinate space.
##
## `control_size` is the size of the Control the insets will be applied to.
## DisplayServer reports the safe area in PHYSICAL screen pixels, while the
## viewport is stretched, so the ratio between them is what converts one to the
## other. Getting this wrong is invisible on a device without a cutout and
## badly wrong on one with it.
##
## Returns zero insets when the display cannot answer — a desktop window, or a
## headless run. A screen that gets no insets is still laid out correctly; it
## just has nothing to avoid.
static func safe_area_insets(control_size: Vector2) -> Vector4i:
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if screen.x <= 0 or screen.y <= 0:
		return Vector4i.ZERO
	var scale_x := control_size.x / float(screen.x)
	var scale_y := control_size.y / float(screen.y)
	return Vector4i(
		int(safe.position.x * scale_x),
		int(safe.position.y * scale_y),
		int((screen.x - safe.end.x) * scale_x),
		int((screen.y - safe.end.y) * scale_y),
	)

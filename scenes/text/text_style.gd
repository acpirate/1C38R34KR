class_name TextStyles
extends RefCounted

## How a semantic class of text behaves inside the rectangle layout gives it.
##
## The governing rule, from the authorization: **layout supplies the available
## rectangle; text style decides how text behaves inside it.** So this file
## carries font, size, minimum size, fit policy, line count, alignment and
## colour — and no geometry at all. No positions, no widths, no margins.
##
## Presentation-side rather than in the logic layer, because resolving a style
## means touching `Font`, `Label` and `PacketStyle`.

## Where a style's colour role resolves to an actual colour.
##
## A naming layer over the presentation registry, NOT a recolouring system: every
## role below maps to a constant that already existed, so `text_style.csv` can
## say PRIMARY without becoming a stylesheet.
static func color_for(role: String) -> Color:
	match role:
		"PRIMARY": return PacketStyle.TEXT
		"SECONDARY": return PacketStyle.TEXT_DIM
		"FAINT": return PacketStyle.TEXT_FAINT
		"HEADING": return PacketStyle.TEXT_HEADING
		"STATUS": return PacketStyle.TEXT_STATUS
		"EMPHASIS": return PacketStyle.CHARGE_TEXT_READY
		"DAMAGE": return PacketStyle.DAMAGE
	push_error("text: unknown colour role '%s'" % role)
	return PacketStyle.TEXT


## One resolved style, ready to apply.
##
## Sizes arrive from the sheet in ALPHA CSS PIXELS and are scaled through
## `UiTheme.px()` here — the unit every other size in this project is authored
## in. Authoring device pixels would silently pin the game to one viewport.
class Entry extends RefCounted:
	var id := ""
	var font: Font = null
	var size := 0
	var minimum := 0
	var fit := "FIXED"
	var max_lines := 0
	var align := HORIZONTAL_ALIGNMENT_LEFT
	var color := Color.WHITE

	## Applies this style to a Label.
	##
	## One call rather than seven property assignments, so a component declares
	## which style it wants and nothing else — which is what stops per-control
	## typography drifting apart again.
	func apply_to(label: Label) -> void:
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", size)
		label.add_theme_color_override("font_color", color)
		label.horizontal_alignment = align

		match fit:
			"WRAP":
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				label.clip_text = false
				# 0 means "as many as the box allows" — the report and the
				# metrics body both want that.
				if max_lines > 0:
					label.max_lines_visible = max_lines
			"ELLIPSIS":
				label.autowrap_mode = TextServer.AUTOWRAP_OFF
				label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			"SHRINK":
				# Shrinking a Label is done by the CALLER, which knows the width
				# available; `size_to_fit` below is the shared implementation.
				# Nothing here can shrink on its own, which is the point of §5.2.
				label.autowrap_mode = TextServer.AUTOWRAP_OFF
				label.clip_text = false
			_:
				label.autowrap_mode = TextServer.AUTOWRAP_OFF

	## The largest size at or below nominal that fits `text` into `width`, never
	## below the declared minimum.
	##
	## This is the whole of §5.2's "no uncontrolled shrink": the floor comes from
	## the sheet, the loader refuses a SHRINK row without one, and a string that
	## still does not fit at the floor is drawn at the floor rather than
	## disappearing down to nothing.
	func size_to_fit(text: String, width: float) -> int:
		if fit != "SHRINK" or width <= 0.0:
			return size
		var px := size
		while px > minimum and font.get_string_size(text, align, -1, px).x > width:
			px -= 1
		return px


static var _cache := {}


## The resolved style for an ID.
##
## An unknown ID logs and falls back to BODY (§9) — readable rather than absent,
## because a screen with one unstyled label is recoverable and a screen with a
## missing label is a bug hunt.
static func of(style_id: String) -> Entry:
	if _cache.has(style_id):
		return _cache[style_id]

	var styles: Dictionary = Content.active().get("styles", {})
	var row: Dictionary = styles.get(style_id, {})
	if row.is_empty():
		push_error("text: unknown style '%s'" % style_id)
		if style_id != Vocab.FALLBACK_STYLE_ID:
			return of(Vocab.FALLBACK_STYLE_ID)
		return _emergency()

	var e := Entry.new()
	e.id = style_id
	e.font = Fonts.of(str(row["font_role"]), str(row["weight"]))
	e.size = UiTheme.px(int(row["nominal"]))
	e.minimum = UiTheme.px(int(row["minimum"]))
	e.fit = str(row["fit"])
	e.max_lines = int(row["max_lines"])
	e.color = color_for(str(row["color_role"]))
	match str(row["align"]):
		"CENTER": e.align = HORIZONTAL_ALIGNMENT_CENTER
		"RIGHT": e.align = HORIZONTAL_ALIGNMENT_RIGHT
		_: e.align = HORIZONTAL_ALIGNMENT_LEFT

	_cache[style_id] = e
	return e


## The last resort, when even the fallback style is missing from the sheet.
##
## Deliberately not a crash: a broken style sheet should still render a readable
## screen carrying the errors that explain it.
static func _emergency() -> Entry:
	var e := Entry.new()
	e.id = "EMERGENCY"
	e.font = Fonts.of(Vocab.FALLBACK_FONT_ROLE, "REGULAR")
	e.size = UiTheme.font_body()
	e.minimum = e.size
	e.color = PacketStyle.TEXT
	return e


## Cleared when content is reloaded, so a style cannot outlive the sheet it came
## from — the same reason `Passives.clear_cache()` exists.
static func clear_cache() -> void:
	_cache.clear()

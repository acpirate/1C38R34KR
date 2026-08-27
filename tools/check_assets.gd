extends SceneTree

## Sanity-checks Asset Pack v0 after generation.
##
## Run:  godot --headless -s res://tools/check_assets.gd
##
## Not a substitute for the Gate-B human inspection — this only catches the
## failures a human would MISS at a glance: a glyph whose two tones collapsed
## into one, an "alpha" asset that is actually opaque, a ring that is solid.

const OUT := "res://assets/packs/v0"


func _initialize() -> void:
	var problems: Array[String] = []

	for name in ["circle", "square", "triangle", "diamond", "star", "cross"]:
		problems.append_array(_check_glyph(name))

	problems.append_array(_check_ring("overlay/ring_override"))
	problems.append_array(_check_ring("packet/ring_selected"))
	problems.append_array(_check_badge("overlay/badge_player", true))
	problems.append_array(_check_badge("overlay/badge_enemy", false))
	problems.append_array(_check_palette())

	if problems.is_empty():
		print("asset pack v0: all structural checks passed")
	else:
		for p in problems:
			print("  FAIL  %s" % p)
		print("\n%d problem(s)" % problems.size())
	quit(0 if problems.is_empty() else 1)


## A glyph must carry BOTH tones: a white core, a mid-grey outline, and
## transparency outside. Collapsing to one tone is the failure that would make
## every Packet a flat silhouette, and it is invisible in a thumbnail.
func _check_glyph(name: String) -> Array[String]:
	var out: Array[String] = []
	var img := _load("packet/glyph_%s" % name)
	if img == null:
		return ["glyph_%s missing" % name]

	var n := img.get_width()
	var centre := img.get_pixel(n / 2, n / 2)
	var corner := img.get_pixel(1, 1)

	if centre.a < 0.99:
		out.append("glyph_%s: centre is not opaque (a=%.2f)" % [name, centre.a])
	if centre.r < 0.95 or centre.g < 0.95 or centre.b < 0.95:
		out.append("glyph_%s: core is not white (%s)" % [name, centre.to_html(false)])
	if corner.a > 0.01:
		out.append("glyph_%s: corner is not transparent (a=%.2f)" % [name, corner.a])

	# Look for the grey band anywhere in the image. Its position differs per
	# shape, so scan rather than sampling a guessed coordinate.
	var greys := 0
	for y in n:
		for x in n:
			var c := img.get_pixel(x, y)
			if c.a > 0.9 and absf(c.r - 0.55) < 0.12 and absf(c.r - c.g) < 0.02:
				greys += 1
	if greys < n:
		out.append("glyph_%s: outline tone barely present (%d px)" % [name, greys])
	return out


## A ring must be hollow — opaque band, transparent centre.
func _check_ring(key: String) -> Array[String]:
	var out: Array[String] = []
	var img := _load(key)
	if img == null:
		return ["%s missing" % key]
	var n := img.get_width()
	if img.get_pixel(n / 2, n / 2).a > 0.01:
		out.append("%s: centre is filled; a ring must be hollow" % key)
	if img.get_pixel(n / 2, 2).a < 0.5:
		out.append("%s: band is absent at the top edge" % key)
	return out


## The badge is the ownership signal: light face for the Hacker, dark for the
## System, each ringed in the other. If the face and its ring are the same
## tone, ownership stops being readable.
func _check_badge(key: String, light_face: bool) -> Array[String]:
	var out: Array[String] = []
	var img := _load(key)
	if img == null:
		return ["%s missing" % key]
	var n := img.get_width()
	var face := img.get_pixel(n / 2, n / 2)
	if face.a < 0.99:
		out.append("%s: face is not opaque" % key)
	if light_face and face.r < 0.9:
		out.append("%s: player badge face should be light (%s)" % [key, face.to_html(false)])
	if not light_face and face.r > 0.1:
		out.append("%s: system badge face should be dark (%s)" % [key, face.to_html(false)])
	return out


func _load(key: String) -> Image:
	var path := "%s/%s.png" % [OUT, key]
	if not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)


## Proves the palette path works BEFORE the renderer depends on it.
##
## D-033 ships the SVG in the pack and parses it at startup. The whole decision
## rests on the file still being readable as text after import — a texture
## importer would convert it and this would fail — so it is worth confirming
## here rather than discovering it on a device at Phase E.
func _check_palette() -> Array[String]:
	var out: Array[String] = []
	var path := "%s/packet_palette.svg" % OUT
	if not FileAccess.file_exists(path):
		return ["packet_palette.svg missing"]

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ["packet_palette.svg is not readable as text — the importer converted it"]

	# Enum ORDER, not alphabetical. A System's weak set is the enum-order
	# complement of its strong set, so index is identity.
	var ids := ["red", "yellow", "magenta", "green", "cyan", "blue"]
	var seen := {}
	for i in ids.size():
		var id := "packet_%s" % ids[i]
		var colour := _swatch(text, id)
		if colour == "":
			out.append("palette: no fill found for id '%s'" % id)
			continue
		if not colour.is_valid_html_color():
			out.append("palette: '%s' is not a valid colour (%s)" % [id, colour])
			continue
		if seen.has(colour):
			out.append("palette: '%s' duplicates '%s' (%s)" % [id, seen[colour], colour])
		seen[colour] = id

		# The parsed value must equal what the live renderer currently draws,
		# or v0 is not reproducing the whitebox it claims to reproduce.
		var expected: Color = PacketStyle.COLOR_FILL[i]
		if not Color(colour).is_equal_approx(expected):
			out.append("palette: '%s' is %s, registry has %s" % [
				id, colour, expected.to_html(false)
			])
	return out


## Reads one swatch's fill, accepting either the `fill` attribute or a `style`
## declaration — Inkscape writes whichever the object was created with, and a
## parser that only handles one of them breaks the first time the file is saved
## from the editor it exists for.
func _swatch(text: String, id: String) -> String:
	var at := text.find('id="%s"' % id)
	if at < 0:
		return ""
	var tag_end := text.find(">", at)
	if tag_end < 0:
		return ""
	var tag := text.substr(at, tag_end - at)

	var attr := RegEx.create_from_string(r'fill\s*[=:]\s*"?\s*(#[0-9a-fA-F]{6})')
	var m := attr.search(tag)
	return m.get_string(1) if m != null else ""

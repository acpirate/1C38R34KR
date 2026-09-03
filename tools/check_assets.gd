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
	problems.append_array(_check_marks())
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
##
## Uses `PacketPalette`, the SAME parser the game uses, rather than a second
## copy of the grammar. Two implementations is how a checker ends up certifying
## a file the game cannot actually read.
func _check_palette() -> Array[String]:
	var out: Array[String] = []
	var path := "%s/packet_palette.svg" % OUT
	if not FileAccess.file_exists(path):
		return ["packet_palette.svg missing"]

	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return ["packet_palette.svg is not readable as text — the importer converted it"]

	var fallback: Array[Color] = []
	for c in PacketStyle.COLOR_FILL:
		fallback.append(c)

	var parsed := PacketPalette.parse(text, fallback)
	for p in parsed.problems:
		out.append(p)

	# The parsed values must equal what the live renderer draws, or v0 is not
	# reproducing the whitebox it claims to reproduce.
	for i in parsed.colors.size():
		if not parsed.colors[i].is_equal_approx(PacketStyle.COLOR_FILL[i]):
			out.append("palette: entry %d is %s, registry has %s" % [
				i, parsed.colors[i].to_html(false), PacketStyle.COLOR_FILL[i].to_html(false)
			])
	return out


## The four overlay marks (D-038).
##
## With the type ring suspended these carry the WHOLE type signal, so the
## failure that matters is two of them being hard to tell apart — and the
## degenerate version of that, two of them being identical, is something a
## generator can produce silently by a copy-paste in one helper.
##
## They must also be white where opaque: the renderer tints them with the
## badge's opposite colour, and a mark authored in any other tone would come
## out wrong on one of the two owners.
func _check_marks() -> Array[String]:
	var out: Array[String] = []
	# Taken from the logic layer rather than restated. A private list here is a
	# list that silently stops covering new types: beta 0.4 added CAPACITOR
	# and LOGIC_BOMB and this checker went on validating four marks while the
	# packs shipped six.
	var names := Resolve.SPECIAL_TYPE_NAMES
	var coverage := {}

	for name in names:
		var img := _load("overlay/mark_%s" % name)
		if img == null:
			out.append("mark_%s missing" % name)
			continue

		var opaque := 0
		var off_white := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a < 0.9:
					continue
				opaque += 1
				if c.r < 0.95 or c.g < 0.95 or c.b < 0.95:
					off_white += 1

		var total := img.get_width() * img.get_height()
		if opaque < total / 40:
			out.append("mark_%s: almost nothing is drawn (%d px)" % [name, opaque])
		if opaque > total * 0.8:
			out.append("mark_%s: fills the canvas; it will not read inside a badge" % name)
		if off_white > opaque / 20:
			out.append("mark_%s: %d opaque px are not white, so tinting will be wrong" % [name, off_white])
		coverage[name] = opaque

	# Distinctness, cheaply: identical silhouettes give identical pixel counts.
	# This will not catch two marks that merely LOOK alike — that is the human's
	# job at Gate B — but it does catch the generator emitting one twice.
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: String = names[i]
			var b: String = names[j]
			if coverage.has(a) and coverage.has(b) and coverage[a] == coverage[b]:
				out.append("mark_%s and mark_%s have identical coverage" % [a, b])
	return out

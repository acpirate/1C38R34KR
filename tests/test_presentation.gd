extends RefCounted

## Enforces the presentation registry (D-014).
##
## The registry is only useful if it stays the ONE place identity maps to
## appearance. A single hard-coded colour elsewhere is harmless on its own and
## fatal in aggregate: the art pass then has to hunt through scenes instead of
## editing one file, which is exactly the retrofit cost the registry exists to
## avoid.
##
## So the rule is enforced rather than documented.

const REGISTRY := "res://scenes/battle/packet_style.gd"
const SCENES_DIR := "res://scenes"

## Six of each, and the ORDER is gameplay identity — weak sets derive as the
## enum-order complement, so a reorder silently rewrites every System's and
## Hacker's weaknesses.
const EXPECTED_ENTRIES := 6


func run(t: TestCase) -> void:
	_test_registry_shape(t)
	_test_no_scattered_colours(t)
	_test_shapes_are_distinct(t)
	_test_graphics_pack(t)
	_test_missing_asset_behaviour(t)
	_test_palette_source(t)


func _test_registry_shape(t: TestCase) -> void:
	t.group("presentation / registry")
	t.eq("a fill per colour", PacketStyle.COLOR_FILL.size(), EXPECTED_ENTRIES)
	t.eq("a border per colour", PacketStyle.COLOR_BORDER.size(), EXPECTED_ENTRIES)
	t.eq("fills cover the Color enum", PacketStyle.COLOR_FILL.size(), Types.PacketColor.size())
	t.eq("an overlay tint per type", PacketStyle.OVERLAY_TINT.size(), Tile.Special.Type.size())

	# Every shape resolves to something drawable. CIRCLE is the deliberate
	# exception: it has no polygon and is drawn as an arc.
	for shape in Types.PacketShape.size():
		var pts := PacketStyle.shape_points(shape)
		if shape == Types.PacketShape.CIRCLE:
			t.check("CIRCLE has no polygon, by design", pts.is_empty())
		else:
			t.check("shape %d has at least three points" % shape, pts.size() >= 3)


## No hex literal may appear under `scenes/` outside the registry.
func _test_no_scattered_colours(t: TestCase) -> void:
	t.group("presentation / no scattered colour values")
	var offenders: Array[String] = []
	var checked := 0

	for path in _gd_files(SCENES_DIR):
		if path == REGISTRY:
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		checked += 1

		var line_no := 0
		for line in text.split("\n"):
			line_no += 1
			var stripped := line.strip_edges()
			# Comments may name a colour when explaining why one is absent.
			if stripped.begins_with("#"):
				continue
			if _has_colour_literal(stripped):
				offenders.append("%s:%d  %s" % [path.get_file(), line_no, stripped])

	t.check("scene scripts were scanned", checked > 0)
	t.check("no colour literal outside the registry", offenders.is_empty())
	for o in offenders.slice(0, 8):
		printerr("        %s" % o)


## A `Color(...)` construction or a `#rrggbb` literal. Deliberately broad: the
## point is to catch appearance decisions leaking out of the registry, not to
## parse GDScript.
func _has_colour_literal(line: String) -> bool:
	if line.contains("Color(") or line.contains("Color8("):
		return true
	var re := RegEx.new()
	re.compile("#[0-9a-fA-F]{6}")
	return re.search(line) != null


func _gd_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


## Six shapes a player must tell apart at thumb size. Point counts differing is
## a weak proxy for visual distinctness, but it does catch the real regression:
## two shapes accidentally resolving to the same geometry.
func _test_shapes_are_distinct(t: TestCase) -> void:
	t.group("presentation / shapes are distinguishable")
	var seen := {}
	for shape in Types.PacketShape.size():
		var pts := PacketStyle.shape_points(shape)
		var key := ""
		for p in pts:
			key += "%.2f,%.2f;" % [p.x, p.y]
		t.check("shape %d is not a duplicate of another" % shape, not seen.has(key) or key == "")
		if key != "":
			seen[key] = shape


# ---------------------------------------------------------------------------
# The graphics catalog (beta 0.3.1)
# ---------------------------------------------------------------------------
#
# The scene layer has no automated coverage by design — layer purity is what
# makes the logic provable and is the same boundary that leaves the renderer
# unproven. These tests do not change that. What they DO cover is the one class
# of graphics failure a machine can see: the pack being incomplete.
#
# That matters because §9.4 forbids a silent fallback to the old whitebox. An
# element whose asset went missing must look broken, and "must look broken" is
# only safe if something guarantees assets are not missing in the first place.


func _test_graphics_pack(t: TestCase) -> void:
	t.group("presentation / graphics pack completeness")

	var problems := Graphics.load_pack()
	t.check("the pack loads with no problems", problems.is_empty())
	for p in problems.slice(0, 8):
		printerr("        %s" % p)

	t.check("a pack is loaded", Graphics.is_loaded())

	var pack := Graphics.pack()
	t.eq("a glyph per Packet shape", pack.packet_glyph.size(), Types.PacketShape.size())
	t.eq("a mark per special type", pack.overlay_mark.size(), Tile.Special.Type.size())

	# The ring is SUSPENDED, not removed (D-037). It stays in the contract so
	# restoring it is a renderer change rather than a schema change — and the
	# assertion stays so the retained assets cannot quietly rot.
	t.eq("a ring per special type, retained", pack.overlay_ring.size(), Tile.Special.Type.size())

	# Every array slot resolves to a real texture, not to MISSING. Indexing the
	# arrays directly here rather than through the accessor is deliberate: the
	# accessor is ALLOWED to substitute MISSING, so asking it would hide the
	# very gap this is looking for.
	for i in pack.packet_glyph.size():
		t.check("glyph %d is present" % i, pack.packet_glyph[i] != null)
	for i in pack.overlay_mark.size():
		t.check("mark %d is present" % i, pack.overlay_mark[i] != null)


func _test_missing_asset_behaviour(t: TestCase) -> void:
	t.group("presentation / a missing asset fails visibly")

	# An empty pack is what a catastrophically broken install looks like. The
	# requirement is that it degrades rather than crashes, so this asks an empty
	# pack for things it does not have.
	var empty := GraphicsPack.new()
	var missing := empty.validate()
	t.check("an empty pack reports itself incomplete", missing.size() > 0)
	t.check("it names the palette too", "palette_svg" in missing)

	var checker := Graphics.missing()
	t.check("there is a MISSING texture", checker != null)

	# Out-of-range keys degrade instead of throwing. The renderer indexes these
	# from game state, and game state must never be able to crash the view.
	Graphics.load_pack()
	t.check("a negative shape resolves", Graphics.glyph(-1) == checker)
	t.check("an over-range shape resolves", Graphics.glyph(999) == checker)
	t.check("an over-range special resolves", Graphics.mark(999) == checker)

	# ...and a VALID key must NOT resolve to the checker, or the test above
	# would pass just as happily against a pack containing nothing at all.
	t.check("a valid shape is not the checker", Graphics.glyph(Types.PacketShape.STAR) != checker)


func _test_palette_source(t: TestCase) -> void:
	t.group("presentation / palette comes from the SVG")

	var path := Graphics.pack().palette_svg
	t.check("the pack names a palette", not str(path).is_empty())
	t.check("the palette file exists", FileAccess.file_exists(path))

	# Readable as TEXT is the assumption D-033 rests on: the file is imported
	# `keep` so the texture importer does not convert it. If that ever changes
	# this is the test that says so, rather than a device showing grey Packets.
	var text := FileAccess.get_file_as_string(path)
	t.check("the palette is readable as text", not text.strip_edges().is_empty())

	var fallback: Array[Color] = []
	for c in PacketStyle.COLOR_FILL:
		fallback.append(c)

	var parsed := PacketPalette.parse(text, fallback)
	t.check("the palette parses cleanly", parsed.ok())
	for p in parsed.problems.slice(0, 6):
		printerr("        %s" % p)
	t.eq("six colours", parsed.colors.size(), Types.PacketColor.size())

	# Six DISTINCT colours. The parser accepts duplicates deliberately — a
	# palette file is the artist's to get wrong — but the shipped one should not
	# have any, and a duplicate here would mean two Packet identities that
	# cannot be told apart on the board.
	var seen := {}
	for c in parsed.colors:
		seen[c.to_html(false)] = true
	t.eq("all six are distinct", seen.size(), Types.PacketColor.size())

	# And the values must equal what the live renderer draws today, or v0 is not
	# reproducing the whitebox it claims to reproduce.
	for i in parsed.colors.size():
		t.check(
			"colour %d matches the registry" % i,
			parsed.colors[i].is_equal_approx(PacketStyle.COLOR_FILL[i]),
		)

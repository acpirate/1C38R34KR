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

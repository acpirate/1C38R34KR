extends RefCounted

## Area-pattern registry parity.
##
## Cell ORDER is checked, not just membership: the ordered cells are fingerprint
## input, so a port producing the same set in a different order would pass a
## set-equality check and still produce a different fingerprint. That failure
## would surface much later, as an unexplained fingerprint mismatch with no
## obvious cause.

const FIXTURE := "res://tests/fixtures/areas.json"


func run(t: TestCase) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		t.group("areas")
		t.check("fixture is readable", false)
		return
	var fixture = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(fixture) != TYPE_DICTIONARY:
		t.group("areas")
		t.check("fixture parses", false)
		return

	_test_order(t, fixture)
	_test_cells(t, fixture)
	_test_advance(t)


func _test_order(t: TestCase, fixture: Dictionary) -> void:
	t.group("areas / progression order")
	var expected: Array = fixture["order"]
	var actual := []
	for id in Areas.PATTERN_ORDER:
		actual.append(id)
	t.eq_seq("registry order", actual, expected)


func _test_cells(t: TestCase, fixture: Dictionary) -> void:
	t.group("areas / cells")
	var patterns: Dictionary = fixture["patterns"]
	t.eq("pattern count", Areas.patterns().size(), patterns.size())

	for id in patterns.keys():
		# Godot's JSON parser yields every number as a float, and GDScript array
		# equality is type-strict, so [0, 0] != [0.0, 0.0]. Coerce the fixture
		# side to int rather than loosening the comparison — the same coercion
		# will be needed wherever JSON fixtures meet integer game data.
		var expected := []
		for pair in (patterns[id] as Array):
			expected.append([int(pair[0]), int(pair[1])])

		# Compare as [x, y] pairs so a mismatch reports readable coordinates
		# rather than Vector2i versus Array.
		var actual := []
		for c in Areas.cells(id):
			actual.append([c.x, c.y])
		t.eq_seq("%s — %d cells in order" % [id, expected.size()], actual, expected)


func _test_advance(t: TestCase) -> void:
	t.group("areas / advance")
	t.eq("one step from the smallest", Areas.advance(Areas.SELF, 1), Areas.CARDINAL_1)
	t.eq("zero steps is a no-op", Areas.advance(Areas.SQUARE_3X3, 0), Areas.SQUARE_3X3)
	t.eq("negative steps is a no-op", Areas.advance(Areas.SQUARE_3X3, -3), Areas.SQUARE_3X3)
	# Saturates rather than wrapping or erroring — with one BIGGER_BOMB source
	# in current content a single step is the practical ceiling, but the
	# registry must behave at the top regardless.
	t.eq("saturates at the largest", Areas.advance(Areas.FAT_CROSS_3, 99), Areas.SQUARE_7X7_CROSS_4)
	t.eq("already largest stays", Areas.advance(Areas.SQUARE_7X7_CROSS_4, 1), Areas.SQUARE_7X7_CROSS_4)
	t.eq("unknown id is returned unchanged", Areas.advance("AREA_NONSENSE", 2), "AREA_NONSENSE")
	t.check("is_pattern_id accepts a real id", Areas.is_pattern_id(Areas.FAT_CROSS_2))
	t.check("is_pattern_id rejects a fake id", not Areas.is_pattern_id("AREA_NONSENSE"))

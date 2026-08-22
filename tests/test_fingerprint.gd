extends RefCounted

## Fingerprint parity, split into its two independent halves.
##
## The end-to-end check — does the loader produce `49c229cd-8ma`? — is the real
## gate, but on its own it only ever reports "different", leaving 11,170
## characters of canonical string to search. Pinning the hash and the serializer
## separately makes a failure say which half is wrong.

const FIXTURE := "res://tests/fixtures/hash.json"


func run(t: TestCase) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		t.group("fingerprint")
		t.check("fixture is readable", false)
		return
	var fixture = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(fixture) != TYPE_DICTIONARY:
		t.group("fingerprint")
		t.check("fixture parses", false)
		return

	_test_hash(t, fixture)
	_test_serialization(t, fixture)
	_test_structures(t)


func _test_hash(t: TestCase, fixture: Dictionary) -> void:
	t.group("fingerprint / djb2")
	for v in (fixture["vectors"] as Array):
		var input := str(v["input"])
		var label := input if input.length() <= 20 else input.substr(0, 17) + "..."
		# UTF-16 length is checked alongside the hash because it is not merely
		# an implementation detail — it IS the suffix of the fingerprint.
		t.eq("utf16 length of %s" % JSON.stringify(label), Fingerprint.utf16_units(input).size(), int(v["utf16_length"]))
		t.eq("djb2 of %s" % JSON.stringify(label), Fingerprint.djb2(input), str(v["hash"]))


func _test_serialization(t: TestCase, fixture: Dictionary) -> void:
	t.group("fingerprint / JS serialization forms")
	var s: Dictionary = fixture["serialization"]

	t.eq("integer", Fingerprint.stringify(1), str(s["integer_one"]))
	# JS renders an integral float without a decimal point.
	t.eq("integral float renders as an integer", Fingerprint.stringify(1.0), str(s["float_one"]))
	t.eq("negative", Fingerprint.stringify(-1), str(s["negative"]))
	t.eq("zero", Fingerprint.stringify(0), str(s["zero"]))
	t.eq("true", Fingerprint.stringify(true), str(s["true_value"]))
	t.eq("false", Fingerprint.stringify(false), str(s["false_value"]))
	t.eq("null", Fingerprint.stringify(null), str(s["null_value"]))
	t.eq("empty string", Fingerprint.stringify(""), str(s["empty_string"]))
	t.eq("embedded quote", Fingerprint.stringify('say "hi"'), str(s["quote_in_string"]))
	t.eq("backslash", Fingerprint.stringify("a\\b"), str(s["backslash"]))
	t.eq("newline", Fingerprint.stringify("a\nb"), str(s["newline"]))
	t.eq("tab", Fingerprint.stringify("a\tb"), str(s["tab"]))
	# Non-ASCII is emitted raw, not \u-escaped.
	t.eq("non-ascii is not escaped", Fingerprint.stringify("café"), str(s["unicode"]))
	t.eq("empty array", Fingerprint.stringify([]), str(s["empty_array"]))
	t.eq("empty object", Fingerprint.stringify({}), str(s["empty_object"]))
	# Key order is INSERTION order, not sorted — sorting would change every
	# fingerprint the alpha ever produced.
	var insertion_ordered := {}
	insertion_ordered["b"] = 2
	insertion_ordered["a"] = 1
	t.eq("object keys keep insertion order", Fingerprint.stringify(insertion_ordered), str(s["nested"]))
	t.eq("array of objects", Fingerprint.stringify([{"x": 1, "y": 2}]), str(s["array_of_objects"]))


## Shapes the real canonical string contains, checked against hand-written
## expectations so a regression in nesting or separators is caught here rather
## than as an opaque fingerprint mismatch.
func _test_structures(t: TestCase) -> void:
	t.group("fingerprint / composite shapes")
	t.eq("Vector2i serializes as {x,y}", Fingerprint.stringify(Vector2i(-1, 2)), '{"x":-1,"y":2}')

	var area := {}
	area["id"] = "AREA_SELF"
	area["cells"] = [Vector2i(0, 0)]
	t.eq("area entry", Fingerprint.stringify(area), '{"id":"AREA_SELF","cells":[{"x":0,"y":0}]}')
	t.eq(
		"area entry hashes as the alpha does",
		Fingerprint.djb2(Fingerprint.stringify(area)),
		"e69fcb74-16",
	)

	var cells := [Vector2i(-1, -1), Vector2i(0, -1)]
	t.eq("cell list", Fingerprint.stringify(cells), '[{"x":-1,"y":-1},{"x":0,"y":-1}]')
	t.eq("cell list hash", Fingerprint.djb2(Fingerprint.stringify(cells)), "04d746d5-w")

	var nested := {}
	nested["a"] = 1
	nested["b"] = [1, 2, 3]
	nested["c"] = {"d": "e"}
	nested["f"] = true
	nested["g"] = null
	t.eq("mixed nesting", Fingerprint.stringify(nested), '{"a":1,"b":[1,2,3],"c":{"d":"e"},"f":true,"g":null}')
	t.eq("mixed nesting hash", Fingerprint.of(nested), "a76b466b-1f")

	t.group("fingerprint / base36 suffix")
	t.eq("zero length", Fingerprint.djb2(""), "00001505-0")
	# 11170 is the canonical length of the current authored content; its base36
	# form is the '8ma' in the target fingerprint 49c229cd-8ma.
	t.eq("11170 in base36", Fingerprint.djb2("x".repeat(11170)).split("-")[1], "8ma")

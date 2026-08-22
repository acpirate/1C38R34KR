extends RefCounted

## D-009 gate: the GDScript mulberry32 must reproduce the alpha's sequence
## exactly. Every downstream verification rests on this, so it runs first and
## nothing else is trustworthy until it passes.

const FIXTURE := "res://tests/fixtures/rng_vectors.json"


func run(t: TestCase) -> void:
	var fixture := _load_fixture(t)
	if fixture.is_empty():
		return

	_test_imul_overflow(t)
	_test_draw_vectors(t, fixture)
	_test_state_progression(t, fixture)
	_test_int_samples(t, fixture)
	_test_shuffle_samples(t, fixture)
	_test_resume(t, fixture)


func _load_fixture(t: TestCase) -> Dictionary:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		t.group("rng")
		t.check("fixture %s is readable" % FIXTURE, false)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		t.group("rng")
		t.check("fixture parses as JSON object", false)
		return {}
	return parsed


## The split-halves `_imul` exists because a naive 32x32 multiply can exceed
## int64. This asserts the two forms agree wherever the naive form is safe, and
## documents whether the defensive version is actually necessary.
func _test_imul_overflow(t: TestCase) -> void:
	t.group("rng / imul")
	var cases := [
		[0, 0], [1, 1], [0xFFFF, 0xFFFF], [0x10000, 0x10000],
		[0xFFFFFFFF, 1], [0xFFFFFFFF, 2], [0x6d2b79f5, 0x6d2b79f5],
		[0xFFFFFFFF, 0xFFFFFFFF], [0x80000000, 0x80000000], [0x7FFFFFFF, 0x7FFFFFFF],
	]
	var naive_matches := true
	for c in cases:
		var split: int = Rng._imul(c[0], c[1])
		var naive: int = (c[0] * c[1]) & 0xFFFFFFFF
		if split != naive:
			naive_matches = false
		# The split form is the reference: verify it against exact modular math
		# done in a way that cannot overflow.
		var expected := _reference_imul(c[0], c[1])
		t.eq("imul(0x%X, 0x%X)" % [c[0], c[1]], split, expected)
	print("        note: naive 32x32 multiply %s the split form on these cases" % ("matches" if naive_matches else "DIVERGES from"))


## Independent modular multiply used only to check `_imul`. Accumulates by
## repeated shifting so no intermediate can overflow, at the cost of speed.
func _reference_imul(a: int, b: int) -> int:
	var result := 0
	var x := a & 0xFFFFFFFF
	var y := b & 0xFFFFFFFF
	while y > 0:
		if y & 1:
			result = (result + x) & 0xFFFFFFFF
		x = (x << 1) & 0xFFFFFFFF
		y >>= 1
	return result


func _test_draw_vectors(t: TestCase, fixture: Dictionary) -> void:
	t.group("rng / draw vectors")
	for v in fixture["vectors"]:
		var seed_value := int(v["seed"])
		var expected: Array = v["draws"]
		var rng := Rng.new(seed_value)
		var actual := []
		actual.resize(expected.size())
		for i in expected.size():
			actual[i] = rng.next_u32()
		t.eq_seq("seed %d — %d draws" % [seed_value, expected.size()], actual, expected)


## mulberry32 advances state by a constant per call regardless of output, so
## this also catches a masking error that the draw comparison might survive.
func _test_state_progression(t: TestCase, fixture: Dictionary) -> void:
	t.group("rng / state")
	for v in fixture["vectors"]:
		var seed_value := int(v["seed"])
		var states: Dictionary = v["states"]
		var rng := Rng.new(seed_value)
		var drawn := 0
		var checkpoints := states.keys()
		checkpoints.sort_custom(func(a, b): return int(a) < int(b))
		for key in checkpoints:
			var n := int(key)
			while drawn < n:
				rng.next_u32()
				drawn += 1
			t.eq("seed %d state after %d draws" % [seed_value, n], rng.get_state(), int(states[key]))


func _test_int_samples(t: TestCase, fixture: Dictionary) -> void:
	t.group("rng / int_below")
	var samples: Dictionary = fixture["int_samples"]
	for key in samples.keys():
		var n := int(key)
		var expected: Array = samples[key]
		var rng := Rng.new(1337)
		var actual := []
		for i in expected.size():
			actual.append(rng.int_below(n))
		t.eq_seq("int_below(%d)" % n, actual, expected)


func _test_shuffle_samples(t: TestCase, fixture: Dictionary) -> void:
	t.group("rng / shuffle")
	var samples: Dictionary = fixture["shuffle_samples"]
	for key in samples.keys():
		var seed_value := int(key)
		var expected: Array = samples[key]
		var rng := Rng.new(seed_value)
		var arr := []
		for i in expected.size():
			arr.append(i)
		rng.shuffle(arr)
		t.eq_seq("shuffle seed %d" % seed_value, arr, expected)


## D-022 depends on this: makeRNG(getState()) must continue the identical
## sequence, or a resumed battle silently diverges from an uninterrupted one.
func _test_resume(t: TestCase, fixture: Dictionary) -> void:
	t.group("rng / resume")
	var r: Dictionary = fixture["resume"]
	var rng := Rng.new(int(r["seed"]))
	var before := []
	for i in (r["before"] as Array).size():
		before.append(rng.next_u32())
	t.eq_seq("pre-save draws", before, r["before"])
	t.eq("captured state", rng.get_state(), int(r["state"]))

	var resumed := Rng.new(int(r["state"]))
	var after := []
	for i in (r["after"] as Array).size():
		after.append(resumed.next_u32())
	t.eq_seq("draws after resume from state", after, r["after"])

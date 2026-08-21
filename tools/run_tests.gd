extends SceneTree

## Headless test runner.
##
##   godot --headless -s res://tools/run_tests.gd
##
## Exits 0 when every test passes, 1 otherwise, so CI and the agent loop can
## gate on the exit code. Game logic must stay free of Node/scene-tree
## dependencies so it can be exercised from here without a rendering context.

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run_all()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _run_all() -> void:
	_test_rng_is_deterministic()
	_test_csv_data_is_present()


func check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		printerr("  FAIL  %s" % label)


## Deterministic RNG is load-bearing for the balance harness ported from the
## alpha: identical seeds must produce identical runs.
func _test_rng_is_deterministic() -> void:
	print("rng")
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 1337
	b.seed = 1337
	var seq_a := []
	var seq_b := []
	for i in 32:
		seq_a.append(a.randi())
		seq_b.append(b.randi())
	check("same seed yields same sequence", seq_a == seq_b)

	var c := RandomNumberGenerator.new()
	c.seed = 1338
	check("different seed diverges", c.randi() != seq_a[0])


## The ten authored datasets are the content source of truth, carried over
## from the alpha unchanged apart from filenames.
func _test_csv_data_is_present() -> void:
	print("data")
	var expected := [
		"bos", "dek", "fnc", "hak", "hst",
		"prg_h", "prg_s", "psv", "sys", "upg",
	]
	for name in expected:
		var path := "res://data/%s.csv" % name
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			check("%s.csv opens" % name, false)
			continue
		var header := file.get_csv_line()
		file.close()
		check("%s.csv opens with a header row" % name, header.size() > 1)

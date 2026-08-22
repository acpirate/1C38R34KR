extends RefCounted

## The ten authored datasets are the content source of truth, carried over from
## the alpha unchanged apart from filenames.
##
## D-007: these are marked `importer="keep"` so Godot's csv_translation importer
## leaves them alone, and `*.csv` is in the export include filter so the raw
## files ship inside the APK. Without both, reads pass in the editor and fail on
## device. Full parsing and validation arrive in Phase 2; this only asserts the
## files are present and readable.

const EXPECTED := ["bos", "dek", "fnc", "hak", "hst", "prg_h", "prg_s", "psv", "sys", "upg"]


func run(t: TestCase) -> void:
	t.group("data files")
	for name in EXPECTED:
		var path := "res://data/%s.csv" % name
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			t.check("%s.csv opens" % name, false)
			continue
		var header := file.get_csv_line()
		file.close()
		t.check("%s.csv has a header row" % name, header.size() > 1)

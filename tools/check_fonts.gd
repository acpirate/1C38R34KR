extends SceneTree

## Proves the bundled fonts cover every character the game can display.
##
## Run:  godot --headless -s res://tools/check_fonts.gd
##
## Authorization §10: "Do not assume a font supports every currently used symbol
## merely because common Latin text renders." That is exactly the failure this
## exists to prevent — a missing glyph renders as a hollow box, and the one
## character most likely to be absent (`→`) appears in a single battle message
## nobody would think to go looking at.
##
## Runs against the REAL corpus rather than a guessed one: printable ASCII, the
## non-ASCII characters found in scene string literals, and every character in
## the content CSVs. So adding a Packet named "Ω" fails here rather than on a
## device.

const FONT_DIR := "res://assets/fonts"
const DATA_DIR := "res://data"
const SCENES_DIR := "res://scenes"

## The three characters beyond ASCII that reach the screen today. Held as a
## constant AND rediscovered from source below — the constant documents intent,
## the scan catches a fourth arriving without anyone updating this file.
const KNOWN_EXTRA := ["·", "—", "→"]


func _initialize() -> void:
	var corpus := _corpus()
	print("corpus: %d distinct characters" % corpus.size())

	var fonts := _bundled_fonts()
	if fonts.is_empty():
		push_error("check_fonts: no .ttf or .otf under %s" % FONT_DIR)
		print("FAILED — no bundled fonts")
		quit(1)
		return

	var failures := 0
	for path in fonts:
		failures += _check_one(path, corpus)

	if failures == 0:
		print("\nall %d bundled font(s) cover the corpus" % fonts.size())
		quit(0)
	else:
		print("\n%d coverage failure(s)" % failures)
		quit(1)


func _check_one(path: String, corpus: Array) -> int:
	# Through the resource system, exactly as the game does — a checker that
	# loads differently from the runtime can certify a font the game cannot use.
	var font := ResourceLoader.load(path) as Font
	if font == null:
		push_error("check_fonts: %s did not load as a Font" % path)
		print("  FAIL  %-32s unreadable" % path.get_file())
		return 1

	var missing := PackedStringArray()
	for ch in corpus:
		if not font.has_char(ch.unicode_at(0)):
			missing.append("U+%04X %s" % [ch.unicode_at(0), ch])

	if missing.is_empty():
		print("  ok    %-32s %s" % [path.get_file(), font.get_font_name()])
		return 0

	print("  FAIL  %-32s missing %d: %s" % [
		path.get_file(), missing.size(), ", ".join(missing).substr(0, 90)
	])
	return 1


## Every character the game can put on screen.
##
## Three sources, because leaving any one out would let a gap through: the ASCII
## range the UI assumes, the literals in scene code, and the authored content.
func _corpus() -> Array:
	var seen := {}

	# Printable ASCII. Included wholesale rather than scanned — a string the game
	# does not use today is one edit away from existing, and no font that is a
	# plausible UI choice will fail this.
	for c in range(0x20, 0x7F):
		seen[String.chr(c)] = true

	for ch in KNOWN_EXTRA:
		seen[ch] = true

	for ch in _chars_in_dir(DATA_DIR, ".csv", false):
		seen[ch] = true
	for ch in _chars_in_dir(SCENES_DIR, ".gd", true):
		seen[ch] = true

	var out := seen.keys()
	out.sort()
	return out


## Characters appearing in files under `dir`.
##
## `literals_only` restricts a scan to double-quoted spans, because a section
## sign in a doc comment is not a glyph the font has to carry — counting it would
## inflate the corpus and could reject a perfectly good font.
func _chars_in_dir(dir_path: String, suffix: String, literals_only: bool) -> Array:
	var out := {}
	for path in _files(dir_path, suffix):
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		if not literals_only:
			for ch in text:
				if ch.unicode_at(0) >= 0x20:
					out[ch] = true
			continue

		for line in text.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue
			var quoted := false
			for ch in line:
				if ch == '"':
					quoted = not quoted
					continue
				if quoted and ch.unicode_at(0) >= 0x20:
					out[ch] = true
	return out.keys()


func _bundled_fonts() -> Array:
	var out: Array = []
	for suffix in [".ttf", ".otf"]:
		out.append_array(_files(FONT_DIR, suffix))
	out.sort()
	return out


func _files(dir_path: String, suffix: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_files(full, suffix))
		elif name.ends_with(suffix):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out

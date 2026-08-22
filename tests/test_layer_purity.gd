extends RefCounted

## Handoff §4 / authorization §8: the logic layer must stay independent of the
## Godot scene tree.
##
## This is not a style rule. It is what keeps the game headlessly testable, and
## therefore what makes the differential gate possible at all. Enforced by a
## test rather than by review because the drift happens one convenient
## `get_tree()` at a time, and catching it on the day it lands is far cheaper
## than unpicking it three phases later.

const LOGIC_DIR := "res://scripts/logic"

const FORBIDDEN := {
	"extends Node": "logic classes must extend RefCounted, never Node",
	"get_tree(": "the scene tree is presentation state",
	"create_tween(": "animation belongs to the renderer",
	"Input.": "input is presentation state",
	"DisplayServer.": "display APIs are presentation state",
	"await ": "logic resolves synchronously; playback is the renderer's job",
}


func run(t: TestCase) -> void:
	t.group("layer purity")
	var files := _gd_files(LOGIC_DIR)
	t.check("logic directory contains scripts", files.size() > 0)

	for path in files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			t.check("%s is readable" % path, false)
			continue
		var text := f.get_as_text()
		f.close()

		# Strip comment lines so documentation may name these APIs when
		# explaining why they are absent.
		var code_lines := PackedStringArray()
		for line in text.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue
			code_lines.append(line)
		var code := "\n".join(code_lines)

		for needle in FORBIDDEN:
			t.check("%s does not use `%s` — %s" % [path.get_file(), needle, FORBIDDEN[needle]], not code.contains(needle))


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

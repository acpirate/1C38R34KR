class_name Csv
extends RefCounted

## CSV parser for the ten authored datasets — a literal port of the alpha's
## `src/logic/data/csv.ts`.
##
## Godot's `FileAccess.get_csv_line()` is deliberately NOT used. It handles
## quoting, but not the behaviours the rest of the pipeline depends on:
##
##  - 1-based source line tracking, which every validation diagnostic reports
##  - skipping wholly empty rows rather than yielding `[""]`
##  - UTF-8 BOM stripping
##  - reporting an unterminated quoted field as a structural error
##
## Diverging on any of those would either change validation output or change
## what gets fingerprinted, so the parser is ported rather than substituted.
##
## A row is `{ line: int, fields: PackedStringArray }`, and `rows[0]` is the
## header when one is present.


## Returns `{ rows: Array[Dictionary], error: String }`. `error` is empty on
## success; a non-empty error means the text was structurally malformed and the
## rows returned are partial.
static func parse(text: String) -> Dictionary:
	var src := text
	if src.length() > 0 and src.unicode_at(0) == 0xFEFF:
		src = src.substr(1)

	var rows: Array[Dictionary] = []
	var fields := PackedStringArray()
	var field := ""
	var in_quotes := false
	var line := 1
	var row_start_line := 1
	# Whether the current row has any content at all — characters or delimiters.
	# Distinguishes a genuinely empty line from a row of empty fields.
	var anything := false

	var i := 0
	var n := src.length()
	while i < n:
		var c := src[i]

		if in_quotes:
			if c == '"':
				if i + 1 < n and src[i + 1] == '"':
					field += '"'
					i += 1
				else:
					in_quotes = false
			else:
				if c == "\n":
					line += 1
				field += c
			i += 1
			continue

		if c == '"':
			in_quotes = true
			anything = true
		elif c == ",":
			fields.append(field)
			field = ""
			anything = true
		elif c == "\n" or c == "\r":
			if c == "\r" and i + 1 < n and src[i + 1] == "\n":
				i += 1
			if anything or field != "" or fields.size() > 0:
				fields.append(field)
				field = ""
				if fields.size() > 1 or fields[0] != "":
					rows.append({"line": row_start_line, "fields": fields})
				fields = PackedStringArray()
				anything = false
			line += 1
			row_start_line = line
		else:
			field += c
			anything = true

		i += 1

	if in_quotes:
		return {
			"rows": rows,
			"error": "unterminated quoted field starting near line %d" % row_start_line,
		}

	if anything or field != "" or fields.size() > 0:
		fields.append(field)
		if fields.size() > 1 or fields[0] != "":
			rows.append({"line": row_start_line, "fields": fields})

	return {"rows": rows, "error": ""}


## Reads and parses a dataset from `res://`. Returns the same shape as `parse`,
## with a read failure reported through the same `error` channel so callers
## have one path to handle.
static func parse_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {
			"rows": [] as Array[Dictionary],
			"error": "cannot open %s (error %d)" % [path, FileAccess.get_open_error()],
		}
	var text := f.get_as_text()
	f.close()
	return parse(text)

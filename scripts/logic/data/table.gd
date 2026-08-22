class_name DataTable
extends RefCounted

## A validated dataset table: header checked, rows bound by column NAME.
##
## Header binding is by name rather than position, so authored column order is
## irrelevant and a spreadsheet reorder cannot silently shift every field by
## one. Unknown, duplicate, and missing columns are all hard errors — an
## unrecognised column usually means a stale export, and guessing at intent is
## exactly the silent repair the contract forbids.

var file := ""
var dataset := ""
var header: PackedStringArray = PackedStringArray()
var rows: Array[Dictionary] = []

var _index := {}


## Returns null when the header does not validate, having recorded every reason.
## A null return stops that dataset from contributing rows, but the load
## continues so the author sees all problems at once rather than one per run.
static func read(
	path: String,
	dataset_name: String,
	expected_header: Array,
	issues: DataIssues
) -> DataTable:
	var parsed := Csv.parse_file(path)
	var file_name := path.get_file()

	if parsed["error"] != "":
		issues.error({
			"dataset": dataset_name, "file": file_name,
			"reason": "CSV structure invalid: %s" % parsed["error"],
		})
		return null

	var parsed_rows: Array = parsed["rows"]
	if parsed_rows.is_empty():
		issues.error({
			"dataset": dataset_name, "file": file_name,
			"reason": "file is empty (no header row)",
		})
		return null

	var t := DataTable.new()
	t.file = file_name
	t.dataset = dataset_name

	# Header cells are trimmed only — the leading-apostrophe normalization
	# applies to data cells, not header names.
	var header_row: Dictionary = parsed_rows[0]
	for h in (header_row["fields"] as PackedStringArray):
		t.header.append(h.strip_edges())

	if not t._validate_header(expected_header, int(header_row["line"]), issues):
		return null

	for i in range(1, parsed_rows.size()):
		var r: Dictionary = parsed_rows[i]
		var fields: PackedStringArray = r["fields"]
		if fields.size() != t.header.size():
			issues.error({
				"dataset": dataset_name, "file": file_name, "row": int(r["line"]),
				"expected": "%d fields" % t.header.size(),
				"value": "%d fields" % fields.size(),
				"reason": "row field count does not match header",
			})
		t.rows.append({"line": int(r["line"]), "fields": fields})

	return t


func _validate_header(expected_header: Array, line: int, issues: DataIssues) -> bool:
	var expected_joined := ",".join(expected_header)
	var seen := {}
	var ok := true

	for h in header:
		if not expected_header.has(h):
			issues.error({
				"dataset": dataset, "file": file, "row": line, "field": h,
				"expected": expected_joined, "reason": "unknown header column",
			})
			ok = false
		elif seen.has(h):
			issues.error({
				"dataset": dataset, "file": file, "row": line, "field": h,
				"reason": "duplicate header column",
			})
			ok = false
		seen[h] = true

	for h in expected_header:
		if not seen.has(h):
			issues.error({
				"dataset": dataset, "file": file, "row": line, "field": h,
				"expected": expected_joined, "reason": "missing required header column",
			})
			ok = false

	if ok:
		for i in header.size():
			_index[header[i]] = i
	return ok


## Reads one cell, applying the spreadsheet-safe normalization once, here, for
## every data cell of every dataset — before any field-specific trimming,
## parsing, resolution, validation, or fingerprinting.
func get_cell(row_i: int, column: String) -> String:
	if not _index.has(column):
		return ""
	var fields: PackedStringArray = rows[row_i]["fields"]
	var idx: int = _index[column]
	if idx >= fields.size():
		return ""
	return Vocab.strip_leading_apostrophe(fields[idx])


func line_of(row_i: int) -> int:
	return int(rows[row_i]["line"])


func row_count() -> int:
	return rows.size()


# ---------------------------------------------------------------------------
# Shared field parsing
# ---------------------------------------------------------------------------

## Colon-separated enum token list. Duplicates have no defined meaning in this
## position, so they are rejected rather than collapsed.
##
## Returns null on any problem, having recorded every reason found — the caller
## treats null as "this row cannot be resolved" and moves on.
static func parse_token_list(
	raw: String,
	vocab: Dictionary,
	ctx: Dictionary,
	issues: DataIssues
) -> Array:
	if raw.strip_edges() == "":
		var c := ctx.duplicate()
		c["value"] = raw
		c["reason"] = "at least one entry is required"
		issues.error(c)
		return []

	var out: Array = []
	var seen := {}
	var ok := true

	for token_raw in raw.split(":"):
		var token := token_raw.strip_edges()
		if token == "":
			var c := ctx.duplicate()
			c["value"] = raw
			c["reason"] = "blank token in list"
			issues.error(c)
			ok = false
			continue
		if seen.has(token):
			var c := ctx.duplicate()
			c["value"] = token
			c["reason"] = "duplicate token in list"
			issues.error(c)
			ok = false
			continue
		seen[token] = true
		if not vocab.has(token):
			var c := ctx.duplicate()
			c["value"] = token
			c["expected"] = "|".join(vocab.keys())
			c["reason"] = "unknown enum value"
			issues.error(c)
			ok = false
			continue
		out.append(vocab[token])

	return out if ok else []


## Colon-separated stable-ID reference list. Resolution against the target
## dataset happens later, once every dataset has been read; this validates
## shape and prefix only.
##
## The prefix check is what rejects a Hacker Program smuggled into a System
## build — a mistake that would otherwise resolve successfully and misbehave in
## combat rather than at load.
##
## `allow_duplicates` is true where repeats carry defined meaning: duplicate
## PASSIVE references stack, so rejecting them would forbid authored content.
##
## Returns an empty array on failure, having recorded every reason. Callers
## distinguish failure from a legitimately empty list via `required`.
static func parse_ref_list(
	raw: String,
	prefix: String,
	required: bool,
	allow_duplicates: bool,
	ctx: Dictionary,
	issues: DataIssues
) -> Array:
	if raw.strip_edges() == "":
		if required:
			var c := ctx.duplicate()
			c["value"] = raw
			c["reason"] = "at least one entry is required"
			issues.error(c)
		return []

	var out: Array = []
	var seen := {}
	var ok := true

	for token_raw in raw.split(":"):
		var token := token_raw.strip_edges()
		if token == "":
			var c := ctx.duplicate()
			c["value"] = raw
			c["reason"] = "blank token in list"
			issues.error(c)
			ok = false
			continue
		if not allow_duplicates and seen.has(token):
			var c := ctx.duplicate()
			c["value"] = token
			c["reason"] = "duplicate token in list"
			issues.error(c)
			ok = false
			continue
		seen[token] = true
		if not token.begins_with(prefix):
			var c := ctx.duplicate()
			c["value"] = token
			c["expected"] = "%s*" % prefix
			c["reason"] = "wrong ID prefix for this reference"
			issues.error(c)
			ok = false
			continue
		out.append(token)

	return out if ok else []


## A reference list of an exact length — a Hacker/Deck portfolio or a System
## build. Authored order is gameplay-significant (charge-routing priority), so
## this never sorts and never silently deduplicates.
static func parse_sized_ref_list(
	raw: String,
	prefix: String,
	size: int,
	ctx: Dictionary,
	issues: DataIssues
) -> Array:
	var ids := parse_ref_list(raw, prefix, true, false, ctx, issues)
	if ids.is_empty():
		return []
	if ids.size() != size:
		var c := ctx.duplicate()
		c["value"] = raw.strip_edges()
		c["expected"] = "exactly %d %s* references" % [size, prefix]
		c["reason"] = "PRG_SET must contain exactly %d distinct Programs" % size
		issues.error(c)
		return []
	return ids


## A bounded integer field with an explicit accepted range.
## Returns `{ok: bool, value: int}`.
static func read_int(raw: String, min_v: int, max_v: int, ctx: Dictionary, issues: DataIssues) -> Dictionary:
	var p := Vocab.parse_int_field(raw)
	if not p["present"] or not p["valid"]:
		var c := ctx.duplicate()
		var trimmed := raw.strip_edges()
		if trimmed != "":
			c["value"] = trimmed
		c["expected"] = "integer %d-%d" % [min_v, max_v]
		c["reason"] = "%s must be an integer" % ctx.get("field", "value")
		issues.error(c)
		return {"ok": false, "value": 0}

	var v: int = p["value"]
	if v < min_v or v > max_v:
		var c := ctx.duplicate()
		c["value"] = raw.strip_edges()
		c["expected"] = "%d-%d" % [min_v, max_v]
		c["reason"] = "%s is out of range" % ctx.get("field", "value")
		issues.error(c)
		return {"ok": false, "value": 0}

	return {"ok": true, "value": v}


## `Y` / `N` / blank, where blank means N. Case-SENSITIVE, unlike `in_pool` —
## the alpha accepts only uppercase here, and loosening it would accept content
## the alpha rejects.
## Returns `{ok: bool, value: bool}`.
static func read_start_charged(raw: String, ctx: Dictionary, issues: DataIssues) -> Dictionary:
	var t := raw.strip_edges()
	if t == "" or t == "N":
		return {"ok": true, "value": false}
	if t == "Y":
		return {"ok": true, "value": true}
	var c := ctx.duplicate()
	c["field"] = "startCharged"
	c["value"] = t
	c["expected"] = "Y|N|blank"
	c["reason"] = "invalid startCharged token"
	issues.error(c)
	return {"ok": false, "value": false}


## A compound colon-delimited integer-enum tuple. `0` is a supplied value, not
## absence. Exact length, token type, and allowed range are all validated here
## so runtime never parses the raw string.
## Returns `{ok: bool, values: Array[int]}`.
static func read_tuple(raw: String, fields: Array, ctx: Dictionary, issues: DataIssues) -> Dictionary:
	var tokens := raw.split(":")
	if tokens.size() != fields.size():
		var names := PackedStringArray()
		for f in fields:
			names.append(f["name"])
		var c := ctx.duplicate()
		c["value"] = raw.strip_edges()
		c["expected"] = ":".join(names)
		c["reason"] = "tuple must have exactly %d colon-delimited values" % fields.size()
		issues.error(c)
		return {"ok": false, "values": []}

	var out: Array[int] = []
	var ok := true
	for i in fields.size():
		var f: Dictionary = fields[i]
		var tok := tokens[i].strip_edges()
		var p := Vocab.parse_int_field(tok)
		var range_text := "%s %d-%d" % [f["name"], f["min"], f["max"]]
		if not p["present"] or not p["valid"]:
			var c := ctx.duplicate()
			c["value"] = tok
			c["expected"] = range_text
			c["reason"] = "malformed tuple value for %s" % f["name"]
			issues.error(c)
			ok = false
			continue
		var v: int = p["value"]
		if v < int(f["min"]) or v > int(f["max"]):
			var c := ctx.duplicate()
			c["value"] = tok
			c["expected"] = range_text
			c["reason"] = "tuple value out of range for %s" % f["name"]
			issues.error(c)
			ok = false
			continue
		out.append(v)

	return {"ok": ok, "values": out if ok else []}


## Display names are required to be nonempty and uppercase.
## Returns `{ok: bool, value: String}`.
static func check_name(raw: String, ctx: Dictionary, issues: DataIssues) -> Dictionary:
	var name := raw.strip_edges()
	if name == "":
		var c := ctx.duplicate()
		c["field"] = "name"
		c["value"] = raw
		c["reason"] = "name must be nonempty"
		issues.error(c)
		return {"ok": false, "value": ""}
	if name != name.to_upper():
		var c := ctx.duplicate()
		c["field"] = "name"
		c["value"] = name
		c["reason"] = "name must be uppercase"
		issues.error(c)
		return {"ok": false, "value": ""}
	return {"ok": true, "value": name}


## `in_pool`: blank or `y` includes the row in random generation, `n` excludes
## it. Deliberate selection screens ignore the flag entirely and always list
## everything, so this governs random routing only.
static func parse_in_pool(raw: String, ctx: Dictionary, issues: DataIssues) -> bool:
	var t := raw.strip_edges().to_lower()
	if t == "" or t == "y":
		return true
	if t == "n":
		return false
	var c := ctx.duplicate()
	c["value"] = raw.strip_edges()
	c["expected"] = "y|n|blank"
	c["reason"] = "invalid in_pool token"
	issues.error(c)
	return true

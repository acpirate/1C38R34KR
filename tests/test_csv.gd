extends RefCounted

## CSV parser parity against the alpha, plus the edge cases the datasets do not
## currently exercise but the parser must still handle correctly.
##
## Parsing sits upstream of validation and fingerprinting, so a divergence here
## would surface as a confusing failure much further along.

const FIXTURE := "res://tests/fixtures/csv_rows.json"


func run(t: TestCase) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		t.group("csv")
		t.check("fixture is readable", false)
		return
	var fixture = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(fixture) != TYPE_DICTIONARY:
		t.group("csv")
		t.check("fixture parses", false)
		return

	_test_datasets(t, fixture)
	_test_edge_cases(t)


func _test_datasets(t: TestCase, fixture: Dictionary) -> void:
	t.group("csv / authored datasets")
	var datasets: Dictionary = fixture["datasets"]
	for key in datasets.keys():
		var expected: Dictionary = datasets[key]
		var expected_rows: Array = expected["rows"]
		var parsed := Csv.parse_file("res://data/%s.csv" % key)

		if parsed["error"] != "":
			t.check("%s.csv parses without a structural error" % key, false)
			continue

		var rows: Array = parsed["rows"]
		t.eq("%s.csv row count" % key, rows.size(), expected_rows.size())
		if rows.size() != expected_rows.size():
			continue

		# Line numbers and field contents both matter: diagnostics report the
		# line, and the fields are what everything downstream is built from.
		#
		# Compared COLUMN-WISE by header name, not positionally, since beta
		# 0.3.2. The beta's sheets no longer carry the alpha's presentation
		# columns — BIO, GRAPHICS, display_text, DESCRIPT, the Boss passive
		# description, and the PASSIVE display template all moved to the text
		# framework or were deleted as POC stubs. A positional comparison would
		# fail on every row of seven sheets and say nothing useful.
		#
		# What this still proves is the part that matters: every column the two
		# builds SHARE is byte-identical.
		#
		# The narrowing is the PLAN WORKING, not a loss. The 0.3.0 handback said
		# the oracle stops adjudicating the moment content moves; content has now
		# moved, deliberately, and alpha fidelity becomes less relevant the
		# further the beta goes. Holding the old comparison would have meant
		# holding the beta to a shape it has outgrown. Recorded as D-045.
		var want_header: Array = expected_rows[0]["fields"]
		var got_header := []
		for v in (rows[0]["fields"] as PackedStringArray):
			got_header.append(v)
		var shared: Array = []
		for h in got_header:
			if want_header.has(h):
				shared.append(h)
		t.check("%s.csv shares columns with the alpha" % key, shared.size() > 0)

		var line_mismatch := -1
		var field_mismatch := -1
		for i in rows.size():
			var got: Dictionary = rows[i]
			var want: Dictionary = expected_rows[i]
			if int(got["line"]) != int(want["line"]) and line_mismatch < 0:
				line_mismatch = i
			var got_fields := []
			for v in (got["fields"] as PackedStringArray):
				got_fields.append(v)
			var want_fields: Array = want["fields"]
			for h in shared:
				var gi := got_header.find(h)
				var wi := want_header.find(h)
				if gi < 0 or wi < 0 or gi >= got_fields.size() or wi >= want_fields.size():
					continue
				if got_fields[gi] != want_fields[wi] and field_mismatch < 0:
					field_mismatch = i
		t.check("%s.csv line numbers (first mismatch row %d)" % [key, line_mismatch], line_mismatch < 0)
		t.check("%s.csv field contents (first mismatch row %d)" % [key, field_mismatch], field_mismatch < 0)


## Behaviours the authored data happens not to contain today, but which the
## parser must get right — a future dataset edit will reach them, and a silent
## regression here would corrupt content rather than fail loudly.
func _test_edge_cases(t: TestCase) -> void:
	t.group("csv / edge cases")

	var bom := Csv.parse(String.chr(0xFEFF) + "a,b\n1,2\n")
	t.eq("BOM is stripped from the first field", (bom["rows"][0]["fields"] as PackedStringArray)[0], "a")

	var quoted := Csv.parse("a,\"b,c\",d\n")
	t.eq("a quoted comma stays inside its field", (quoted["rows"][0]["fields"] as PackedStringArray)[1], "b,c")
	t.eq("quoted row field count", (quoted["rows"][0]["fields"] as PackedStringArray).size(), 3)

	var escaped := Csv.parse("a,\"say \"\"hi\"\"\",c\n")
	t.eq("doubled quotes unescape to one", (escaped["rows"][0]["fields"] as PackedStringArray)[1], 'say "hi"')

	var newline_in_quotes := Csv.parse("a,\"line1\nline2\",c\nx,y,z\n")
	t.eq("a quoted newline does not split the row", (newline_in_quotes["rows"] as Array).size(), 2)
	t.eq("the embedded newline is preserved", (newline_in_quotes["rows"][0]["fields"] as PackedStringArray)[1], "line1\nline2")
	# The second row starts on source line 3 because the quoted field consumed
	# line 2 — this is exactly what makes hand-rolling the parser necessary.
	t.eq("line tracking survives an embedded newline", int(newline_in_quotes["rows"][1]["line"]), 3)

	var crlf := Csv.parse("a,b\r\n1,2\r\n")
	t.eq("CRLF yields two rows", (crlf["rows"] as Array).size(), 2)
	t.eq("CR is not left on the field", (crlf["rows"][0]["fields"] as PackedStringArray)[1], "b")

	var blanks := Csv.parse("a,b\n\n\n1,2\n\n")
	t.eq("wholly empty rows are skipped", (blanks["rows"] as Array).size(), 2)
	t.eq("the row after blanks keeps its true line number", int(blanks["rows"][1]["line"]), 4)

	var empty_fields := Csv.parse("a,,c\n")
	t.eq("a row of empty fields is kept", (empty_fields["rows"] as Array).size(), 1)
	t.eq("the empty middle field is preserved", (empty_fields["rows"][0]["fields"] as PackedStringArray)[1], "")

	var unterminated := Csv.parse("a,\"b\n")
	t.check("an unterminated quote is a structural error", unterminated["error"] != "")

	var no_trailing_newline := Csv.parse("a,b\n1,2")
	t.eq("a final row without a newline is kept", (no_trailing_newline["rows"] as Array).size(), 2)

	t.eq("empty input yields no rows", (Csv.parse("")["rows"] as Array).size(), 0)

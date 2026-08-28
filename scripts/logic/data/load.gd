class_name ContentLoader
extends RefCounted

## The content pipeline: parse, validate, resolve, fingerprint.
##
## Contract, unchanged from the alpha:
##   - every dataset is read and every rule runs, so an author sees all problems
##     at once rather than one per attempt
##   - any error blocks startup; warnings do not
##   - invalid data is never silently repaired, and there is no fallback content
##   - no default System, no hardcoded gameplay content
##
## Dataset roles are identified by the manifest below AND independently
## cross-checked by ID prefix, so a file placed in the wrong slot fails loudly
## rather than resolving into the wrong layer.

const DATA_DIR := "res://data"

## Manifest: role to filename. The beta shortened the alpha's filenames; the
## contents are byte-identical.
const FILES := {
	"hacker_programs": "prg_h.csv",
	"system_programs": "prg_s.csv",
	"functions": "fnc.csv",
	"hackers": "hak.csv",
	"passives": "psv.csv",
	"decks": "dek.csv",
	"systems": "sys.csv",
	"hosts": "hst.csv",
	"upgrades": "upg.csv",
	"bosses": "bos.csv",
	"text_content": "text_content.csv",
	"text_style": "text_style.csv",
	"font_refs": "font_refs.csv",
}

var issues := DataIssues.new()

var program_rows: Array[Dictionary] = []
var function_rows: Array[Dictionary] = []
var hacker_rows: Array[Dictionary] = []
var passive_rows: Array[Dictionary] = []
var deck_rows: Array[Dictionary] = []
var system_rows: Array[Dictionary] = []
var host_rows: Array[Dictionary] = []
var upgrade_rows: Array[Dictionary] = []
var boss_rows: Array[Dictionary] = []

## Text framework stores (beta 0.3.2). Dictionaries rather than row arrays: every
## consumer is a keyed lookup, and a duplicate key is an authoring error the
## reader rejects rather than a shape the runtime has to resolve.
var text_rows := {}    ## "CATEGORY/REF_ID" -> EN
var style_rows := {}   ## STYLE_ID -> resolved row
var font_rows := {}    ## "ROLE/WEIGHT" -> res:// path


func _path(role: String) -> String:
	return "%s/%s" % [DATA_DIR, FILES[role]]


# ---------------------------------------------------------------------------
# Program datasets
# ---------------------------------------------------------------------------

## Hacker and System Programs share a schema and differ only by ID prefix.
## The prefix is what independently cross-checks the manifest's dataset role.
func read_programs(role: String, dataset: String, prefix: String) -> void:
	var path := _path(role)
	var table := DataTable.read(path, dataset, Vocab.PROGRAM_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var id := table.get_cell(i, "PRG_ID").strip_edges()
		var ctx := {"dataset": dataset, "file": table.file, "row": table.line_of(i), "id": id}

		if id == "":
			var c := ctx.duplicate()
			c["field"] = "PRG_ID"
			c["reason"] = "PRG_ID is required"
			issues.error(c)
			continue
		if not id.begins_with(prefix):
			var c := ctx.duplicate()
			c["field"] = "PRG_ID"
			c["value"] = id
			c["expected"] = "%s*" % prefix
			c["reason"] = "wrong Program ID prefix for this dataset"
			issues.error(c)
			continue

		var name := DataTable.check_name(table.get_cell(i, "name"), ctx, issues)

		var colors_ctx := ctx.duplicate()
		colors_ctx["field"] = "colors"
		var colors := DataTable.parse_token_list(table.get_cell(i, "colors"), Vocab.COLOR_TOKENS, colors_ctx, issues)

		var shapes_ctx := ctx.duplicate()
		shapes_ctx["field"] = "shapes"
		var shapes := DataTable.parse_token_list(table.get_cell(i, "shapes"), Vocab.SHAPE_TOKENS, shapes_ctx, issues)

		var function_id := _read_single_function_ref(table.get_cell(i, "functions"), ctx)

		if not name["ok"] or colors.is_empty() or shapes.is_empty() or function_id == "":
			continue

		program_rows.append({
			"file": table.file,
			"dataset": dataset,
			"row": table.line_of(i),
			"id": id,
			"name": name["value"],
			"colors": colors,
			"shapes": shapes,
			"function_id": function_id,
			"notes": table.get_cell(i, "notes").strip_edges(),
		})


## Exactly one Function reference per Program. A colon here means someone tried
## to give a Program two Functions, which is a different mistake from a missing
## reference and gets its own message.
func _read_single_function_ref(raw: String, ctx: Dictionary) -> String:
	var fn := raw.strip_edges()
	var c := ctx.duplicate()
	c["field"] = "functions"

	if fn == "":
		c["reason"] = "exactly one FNC_* reference is required"
		issues.error(c)
		return ""
	if fn.contains(":"):
		c["value"] = fn
		c["reason"] = "exactly one Function per Program is permitted"
		issues.error(c)
		return ""
	if not fn.begins_with("FNC_"):
		c["value"] = fn
		c["expected"] = "FNC_*"
		c["reason"] = "not a Function ID"
		issues.error(c)
		return ""
	return fn


# ---------------------------------------------------------------------------
# Function dataset
# ---------------------------------------------------------------------------

func read_functions() -> void:
	var path := _path("functions")
	var table := DataTable.read(path, DataIssues.DATASET_FUNCTIONS, Vocab.FUNCTION_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var id := table.get_cell(i, "FNC_ID").strip_edges()
		var ctx := {
			"dataset": DataIssues.DATASET_FUNCTIONS, "file": table.file,
			"row": table.line_of(i), "id": id,
		}

		if id == "":
			var c := ctx.duplicate()
			c["field"] = "FNC_ID"
			c["reason"] = "FNC_ID is required"
			issues.error(c)
			continue
		if not id.begins_with("FNC_"):
			var c := ctx.duplicate()
			c["field"] = "FNC_ID"
			c["value"] = id
			c["expected"] = "FNC_*"
			c["reason"] = "wrong Function ID prefix"
			issues.error(c)
			continue

		var name := DataTable.check_name(table.get_cell(i, "name"), ctx, issues)

		# Cost 0 is legal here so a PASSIVE carrier payload can state its true
		# cost. It is NOT legal on a Function a Program or Deck fields — a
		# charge pool's capacity IS its Function's cost, so a zero-cost assigned
		# Function would hold no pool and fire free every turn. That check runs
		# in the cross-reference phase, where the assignments are known.
		var cost_ctx := ctx.duplicate()
		cost_ctx["field"] = "cost"
		var cost := DataTable.read_int(table.get_cell(i, "cost"), 0, 9999, cost_ctx, issues)

		var payload_raw := table.get_cell(i, "payload").strip_edges()
		if payload_raw == "":
			var c := ctx.duplicate()
			c["field"] = "payload"
			c["reason"] = "payload is required"
			issues.error(c)

		var start_charged := DataTable.read_start_charged(table.get_cell(i, "startCharged"), ctx, issues)

		if not name["ok"] or not cost["ok"] or payload_raw == "" or not start_charged["ok"]:
			continue

		# Raw discrete-parameter and axis columns are captured here and
		# validated against the Effect contract later, once the payload has been
		# expanded and the acting Effect is known.
		var params := {}
		for p in Effects.PARAM_NAMES:
			params[p] = table.get_cell(i, p)
		var axes := {}
		for a in Effects.AXIS_NAMES:
			axes[a] = table.get_cell(i, a)

		function_rows.append({
			"file": table.file,
			"row": table.line_of(i),
			"id": id,
			"name": name["value"],
			"cost": cost["value"],
			"payload_raw": payload_raw,
			"notes": table.get_cell(i, "notes").strip_edges(),
			"params": params,
			"axes": axes,
			"tuple_raw": table.get_cell(i, "params"),
			"start_charged": start_charged["value"],
		})


# ---------------------------------------------------------------------------
# PASSIVE dataset
# ---------------------------------------------------------------------------

## One dataset defines every passive in the game; Hackers, Systems, HOSTs, and
## UPGRADEs all reference rows from it. The selected coded `passive_effect`
## picks the contract that validates everything else on the row.
func read_passives() -> void:
	var table := DataTable.read(_path("passives"), DataIssues.DATASET_PASSIVES, Vocab.PASSIVE_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var id := table.get_cell(i, "PASSIVE_ID").strip_edges()
		var ctx := {
			"dataset": DataIssues.DATASET_PASSIVES, "file": table.file,
			"row": table.line_of(i), "id": id,
		}

		if id == "":
			var c := ctx.duplicate()
			c["field"] = "PASSIVE_ID"
			c["reason"] = "PASSIVE_ID is required"
			issues.error(c)
			continue
		if not id.begins_with("PSV_"):
			var c := ctx.duplicate()
			c["field"] = "PASSIVE_ID"
			c["value"] = id
			c["expected"] = "PSV_*"
			c["reason"] = "wrong PASSIVE ID prefix"
			issues.error(c)
			continue

		var effect_raw := table.get_cell(i, "passive_effect").strip_edges()
		if not PassiveEffects.is_effect_id(effect_raw):
			var c := ctx.duplicate()
			c["field"] = "passive_effect"
			c["value"] = effect_raw
			c["expected"] = "|".join(PassiveEffects.ids())
			c["reason"] = "unknown PASSIVE effect type"
			issues.error(c)
			continue
		var contract := PassiveEffects.contract(effect_raw)

		var activation_ok := _check_passive_activation(table.get_cell(i, "activation"), effect_raw, contract, ctx)
		var scope_ok := _check_passive_scope(table.get_cell(i, "agent_scope"), ctx)
		var payload := _check_passive_payload(table.get_cell(i, "function_payload"), effect_raw, contract, ctx)
		var tuple := _check_passive_params(table.get_cell(i, "params"), effect_raw, contract, ctx)
		var display_ok := _check_passive_display(_passive_template(id), contract, ctx)

		if not (activation_ok and scope_ok and payload["ok"] and tuple["ok"] and display_ok):
			continue

		# Enum tokens render in player-facing title case (RED becomes Red);
		# scope and numeric tokens render exactly as authored.
		var tokens: Array = tuple["tokens"]
		var shown: Array[String] = []
		for k in contract["params"].size():
			var kind: int = contract["params"][k]
			shown.append(Vocab.title_case(tokens[k]) if kind == PassiveEffects.ParamKind.COLOR else tokens[k])

		var template := _passive_template(id)

		passive_rows.append({
			"file": table.file,
			"row": table.line_of(i),
			"id": id,
			"effect_type": effect_raw,
			"activation": table.get_cell(i, "activation").strip_edges(),
			"agent_scope": table.get_cell(i, "agent_scope").strip_edges(),
			"color": tuple["color"],
			"all_scope": tuple["all_scope"],
			"magnitude": tuple["magnitude"],
			"function_id": payload["function_id"],
			"display": _expand_display(template, shown),
			"display_template": template,
			"param_tokens": tokens,
		})


## A PASSIVE's display template, from `text_content.csv`.
##
## Moved out of `psv.csv` in beta 0.3.2, but the CONTRACT did not move: the
## template's positional `%0`/`%1` tokens are still checked against the effect's
## declared params at load, because that validator knows how many params an
## effect has and that a COLOUR renders title-cased. Only storage changed
## (D-043).
##
## Requires `read_text_content()` to have run first — enforced by ordering in
## `read_all()`, and a missing row is reported by the display check rather than
## silently yielding an empty string.
func _passive_template(passive_id: String) -> String:
	return str(text_rows.get("PASSIVE_TEXT/%s" % passive_id, ""))


# ---------------------------------------------------------------------------
# Text framework sheets (beta 0.3.2)
# ---------------------------------------------------------------------------

## `what the game says`, keyed `CATEGORY/REF_ID`.
##
## The EN column is NOT stripped. Whitespace inside a string is content — the
## battle log indents sub-messages with leading spaces — and the loader stripping
## it would destroy authored copy the way the spreadsheet round trip already
## does (AN-011).
func read_text_content() -> void:
	var table := DataTable.read(_path("text_content"), DataIssues.DATASET_TEXT_CONTENT, Vocab.TEXT_CONTENT_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var category := table.get_cell(i, "SEMANTIC_CATEGORY").strip_edges()
		var ref_id := table.get_cell(i, "REF_ID").strip_edges()
		var en := table.get_cell(i, "EN")

		var c := {
			"dataset": DataIssues.DATASET_TEXT_CONTENT, "file": table.file,
			"row": table.line_of(i), "id": ref_id,
		}
		if category == "" or ref_id == "":
			c["reason"] = "text row needs both SEMANTIC_CATEGORY and REF_ID"
			issues.error(c)
			continue

		var key := "%s/%s" % [category, ref_id]
		if text_rows.has(key):
			c["reason"] = "duplicate text row %s" % key
			issues.error(c)
			continue
		text_rows[key] = en


## How a semantic class of text behaves inside the rectangle layout gives it.
func read_text_styles() -> void:
	var table := DataTable.read(_path("text_style"), DataIssues.DATASET_TEXT_STYLE, Vocab.TEXT_STYLE_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var id := table.get_cell(i, "STYLE_ID").strip_edges()
		var c := {
			"dataset": DataIssues.DATASET_TEXT_STYLE, "file": table.file,
			"row": table.line_of(i), "id": id,
		}
		if id == "":
			c["reason"] = "style row needs a STYLE_ID"
			issues.error(c)
			continue
		if style_rows.has(id):
			c["reason"] = "duplicate STYLE_ID"
			issues.error(c)
			continue

		var fit := table.get_cell(i, "FIT_MODE").strip_edges().to_upper()
		var align := table.get_cell(i, "H_ALIGN").strip_edges().to_upper()
		var colour := table.get_cell(i, "COLOR_ROLE").strip_edges().to_upper()
		var weight := table.get_cell(i, "WEIGHT").strip_edges().to_upper()
		var nominal := int(table.get_cell(i, "NOMINAL_SIZE").strip_edges())
		var minimum := int(table.get_cell(i, "MIN_SIZE").strip_edges())

		var ok := true
		for pair in [[fit, Vocab.FIT_MODES, "FIT_MODE"], [align, Vocab.H_ALIGNS, "H_ALIGN"],
				[colour, Vocab.COLOR_ROLES, "COLOR_ROLE"], [weight, Vocab.FONT_WEIGHTS, "WEIGHT"]]:
			if not (pair[1] as Array).has(pair[0]):
				var f := c.duplicate()
				f["field"] = pair[2]
				f["value"] = pair[0]
				f["expected"] = "|".join(pair[1])
				f["reason"] = "unknown %s" % pair[2]
				issues.error(f)
				ok = false

		# §5.2 — no uncontrolled shrink. A style that may reduce its size must
		# declare where it stops, and the floor must actually be a floor.
		if nominal <= 0:
			var f := c.duplicate()
			f["field"] = "NOMINAL_SIZE"
			f["reason"] = "NOMINAL_SIZE must be positive"
			issues.error(f)
			ok = false
		if fit == "SHRINK" and minimum <= 0:
			var f := c.duplicate()
			f["field"] = "MIN_SIZE"
			f["reason"] = "SHRINK requires a positive MIN_SIZE"
			issues.error(f)
			ok = false
		if minimum > nominal:
			var f := c.duplicate()
			f["field"] = "MIN_SIZE"
			f["reason"] = "MIN_SIZE %d exceeds NOMINAL_SIZE %d" % [minimum, nominal]
			issues.error(f)
			ok = false

		if not ok:
			continue

		style_rows[id] = {
			"id": id,
			"font_role": table.get_cell(i, "FONT_ROLE").strip_edges().to_upper(),
			"weight": weight,
			"nominal": nominal,
			"minimum": minimum,
			"fit": fit,
			"max_lines": int(table.get_cell(i, "MAX_LINES").strip_edges()),
			"align": align,
			"color_role": colour,
		}


## Semantic font roles to bundled files, keyed `ROLE/WEIGHT`.
func read_font_refs() -> void:
	var table := DataTable.read(_path("font_refs"), DataIssues.DATASET_FONT_REFS, Vocab.FONT_REFS_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var role := table.get_cell(i, "FONT_ROLE").strip_edges().to_upper()
		var weight := table.get_cell(i, "WEIGHT").strip_edges().to_upper()
		var file := table.get_cell(i, "FONT_FILE").strip_edges()
		var c := {
			"dataset": DataIssues.DATASET_FONT_REFS, "file": table.file,
			"row": table.line_of(i), "id": "%s/%s" % [role, weight],
		}
		if role == "" or file == "":
			c["reason"] = "font row needs a FONT_ROLE and a FONT_FILE"
			issues.error(c)
			continue
		if not Vocab.FONT_WEIGHTS.has(weight):
			c["field"] = "WEIGHT"
			c["expected"] = "|".join(Vocab.FONT_WEIGHTS)
			c["reason"] = "unknown WEIGHT"
			issues.error(c)
			continue

		# §6.2 — production text must not fall back to a device font. A missing
		# file is a content error, caught here rather than at first draw.
		var res := "res://%s" % file if not file.begins_with("res://") else file
		if not FileAccess.file_exists(res):
			c["field"] = "FONT_FILE"
			c["value"] = file
			c["reason"] = "bundled font file not found"
			issues.error(c)
			continue

		font_rows["%s/%s" % [role, weight]] = res


## The effect/activation pairing is part of the contract, not a free
## combination: a continual modifier authored START_OF_TURN is a content error,
## not a mode the runtime silently accommodates.
func _check_passive_activation(raw: String, effect_raw: String, contract: Dictionary, ctx: Dictionary) -> bool:
	var activation := raw.strip_edges()
	var c := ctx.duplicate()
	c["field"] = "activation"
	c["value"] = activation

	if not PassiveEffects.is_activation(activation):
		c["expected"] = "CONTINUAL|START_OF_TURN"
		c["reason"] = "unknown PASSIVE activation"
		issues.error(c)
		return false

	var expected: String = PassiveEffects.ACTIVATION_NAMES[contract["activation"]]
	if activation != expected:
		c["expected"] = expected
		c["reason"] = "%s only supports %s" % [effect_raw, expected]
		issues.error(c)
		return false
	return true


## Required and validated for every row. HOST-supplied instances ignore it at
## RUNTIME rather than having it blanked here, so a log can still report what
## the data actually said.
func _check_passive_scope(raw: String, ctx: Dictionary) -> bool:
	var scope := raw.strip_edges()
	if PassiveEffects.is_agent_scope(scope):
		return true
	var c := ctx.duplicate()
	c["field"] = "agent_scope"
	c["value"] = scope
	c["expected"] = "OWNER|ENEMY"
	c["reason"] = "unknown PASSIVE agent scope"
	issues.error(c)
	return false


## CARRIER requires exactly one Function reference; every continual effect
## forbids one outright.
func _check_passive_payload(raw: String, effect_raw: String, contract: Dictionary, ctx: Dictionary) -> Dictionary:
	var payload := raw.strip_edges()
	var c := ctx.duplicate()
	c["field"] = "function_payload"

	if contract["payload"] == PassiveEffects.Payload.REQUIRED:
		if payload == "":
			c["expected"] = "FNC_*"
			c["reason"] = "%s requires a Function payload" % effect_raw
			issues.error(c)
			return {"ok": false, "function_id": ""}
		if not payload.begins_with("FNC_"):
			c["value"] = payload
			c["expected"] = "FNC_*"
			c["reason"] = "wrong Function ID prefix in PASSIVE payload"
			issues.error(c)
			return {"ok": false, "function_id": ""}
		if payload.contains(":"):
			c["value"] = payload
			c["expected"] = "exactly one FNC_* reference"
			c["reason"] = "a PASSIVE payload names exactly one Function"
			issues.error(c)
			return {"ok": false, "function_id": ""}
		return {"ok": true, "function_id": payload}

	if payload != "":
		c["value"] = payload
		c["reason"] = "%s does not take a Function payload" % effect_raw
		issues.error(c)
		return {"ok": false, "function_id": ""}
	return {"ok": true, "function_id": ""}


## The typed parameter tuple, validated by the selected effect. An empty
## contract tuple means the column must be BLANK — a populated one is an
## authoring error, not a value to ignore.
func _check_passive_params(raw: String, effect_raw: String, contract: Dictionary, ctx: Dictionary) -> Dictionary:
	var params_raw := raw.strip_edges()
	var kinds: Array = contract["params"]
	var result := {"ok": true, "tokens": [] as Array, "color": null, "all_scope": false, "magnitude": null}

	if kinds.is_empty():
		if params_raw != "":
			var c := ctx.duplicate()
			c["field"] = "params"
			c["value"] = params_raw
			c["reason"] = "%s takes no parameters" % effect_raw
			issues.error(c)
			result["ok"] = false
		return result

	var tokens: Array[String] = []
	for t in params_raw.split(":"):
		tokens.append(t.strip_edges())

	if params_raw == "" or tokens.size() != kinds.size():
		var expected := PackedStringArray()
		for k in kinds:
			expected.append(["color", "scope", "positiveInt"][k])
		var c := ctx.duplicate()
		c["field"] = "params"
		c["value"] = params_raw
		c["expected"] = ":".join(expected)
		c["reason"] = "PASSIVE params must have exactly %d colon-delimited values" % kinds.size()
		issues.error(c)
		result["ok"] = false
		return result

	result["tokens"] = tokens
	for i in kinds.size():
		var kind: int = kinds[i]
		var tok: String = tokens[i]
		var c := ctx.duplicate()
		c["field"] = "params"

		if tok == "":
			c["value"] = params_raw
			c["reason"] = "blank token in PASSIVE params"
			issues.error(c)
			result["ok"] = false
			continue

		match kind:
			PassiveEffects.ParamKind.COLOR:
				# The canonical three-letter token. A stale export spelling
				# YELLOW fails here rather than acquiring a one-off alias.
				if not Vocab.COLOR_TOKENS.has(tok):
					c["value"] = tok
					c["expected"] = "|".join(Vocab.COLOR_TOKENS.keys())
					c["reason"] = "unknown color enum value in PASSIVE params"
					issues.error(c)
					result["ok"] = false
					continue
				result["color"] = Vocab.COLOR_TOKENS[tok]
			PassiveEffects.ParamKind.SCOPE:
				if tok != PassiveEffects.ALL_SCOPE_TOKEN:
					c["value"] = tok
					c["expected"] = PassiveEffects.ALL_SCOPE_TOKEN
					c["reason"] = "unknown scope value in PASSIVE params"
					issues.error(c)
					result["ok"] = false
					continue
				result["all_scope"] = true
			_:
				var p := Vocab.parse_int_field(tok)
				if not p["present"] or not p["valid"] or int(p["value"]) < 1 or int(p["value"]) > 999999:
					c["value"] = tok
					c["expected"] = "positive integer"
					c["reason"] = "invalid magnitude in PASSIVE params"
					issues.error(c)
					result["ok"] = false
					continue
				result["magnitude"] = int(p["value"])

	return result


## Presentation only, never gameplay authority. `%N` refers to the zero-based
## ordered parameter tokens; an unsupported or out-of-range placeholder is a
## startup error rather than a string that renders wrong in play.
##
## May be BLANK: a carrier with no display renders as its payload Function's
## player-facing name instead.
func _check_passive_display(raw: String, contract: Dictionary, ctx: Dictionary) -> bool:
	var template := raw.strip_edges()
	var kinds: Array = contract["params"]
	var ok := true

	var re := RegEx.new()
	re.compile("%([0-9]*)")
	for m in re.search_all(template):
		var digits := m.get_string(1)
		var c := ctx.duplicate()
		c["field"] = "display"
		c["value"] = m.get_string(0)

		if digits == "":
			c["reason"] = "unsupported PASSIVE display placeholder (expected %N)"
			issues.error(c)
			ok = false
			continue
		if digits.to_int() >= kinds.size():
			c["expected"] = "no placeholders" if kinds.is_empty() else "%%0-%%%d" % (kinds.size() - 1)
			c["reason"] = "PASSIVE display placeholder out of range"
			issues.error(c)
			ok = false

	return ok


func _expand_display(template: String, shown: Array) -> String:
	var re := RegEx.new()
	re.compile("%([0-9]+)")
	var out := template
	# Replace from the end so earlier replacements cannot shift later offsets.
	var matches := re.search_all(template)
	for i in range(matches.size() - 1, -1, -1):
		var m := matches[i]
		var idx := m.get_string(1).to_int()
		if idx < shown.size():
			out = out.substr(0, m.get_start()) + str(shown[idx]) + out.substr(m.get_end())
	return out


# ---------------------------------------------------------------------------
# Identity datasets
# ---------------------------------------------------------------------------

## Shared opening for every identity row: the stable ID and its prefix.
## Returns an empty context dictionary when the row cannot proceed.
func _row_ctx(table: DataTable, i: int, dataset: String, id_field: String, prefix: String, label: String) -> Dictionary:
	var id := table.get_cell(i, id_field).strip_edges()
	var ctx := {"dataset": dataset, "file": table.file, "row": table.line_of(i), "id": id}

	if id == "":
		var c := ctx.duplicate()
		c["field"] = id_field
		c["reason"] = "%s is required" % id_field
		issues.error(c)
		return {}
	if not id.begins_with(prefix):
		var c := ctx.duplicate()
		c["field"] = id_field
		c["value"] = id
		c["expected"] = "%s*" % prefix
		c["reason"] = "wrong %s ID prefix" % label
		issues.error(c)
		return {}
	return ctx


func _field_ctx(ctx: Dictionary, field: String) -> Dictionary:
	var c := ctx.duplicate()
	c["field"] = field
	return c


## A PASSIVE reference list that may legitimately be EMPTY — a Hacker or System
## with none, or a zero-PASSIVE HOST such as THRESHOLD. Duplicates are permitted
## because repeated qualifying PASSIVEs stack additively.
func _optional_passive_refs(raw: String, ctx: Dictionary) -> Array:
	if raw.strip_edges() == "":
		return []
	return DataTable.parse_ref_list(raw, "PSV_", true, true, ctx, issues)


func read_hosts() -> void:
	var table := DataTable.read(_path("hosts"), DataIssues.DATASET_HOSTS, Vocab.HOST_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var ctx := _row_ctx(table, i, DataIssues.DATASET_HOSTS, "HOST_ID", "HST_", "HOST")
		if ctx.is_empty():
			continue

		var name := DataTable.check_name(table.get_cell(i, "name"), ctx, issues)
		var raw_passives := table.get_cell(i, "passives")
		var passive_ids := _optional_passive_refs(raw_passives, _field_ctx(ctx, "passives"))
		var in_pool := DataTable.parse_in_pool(table.get_cell(i, "in_pool"), _field_ctx(ctx, "in_pool"), issues)

		# Zero PASSIVEs is VALID here — THRESHOLD is the fixed Battle 1
		# battlefield and deliberately contributes nothing.
		if not name["ok"] or (raw_passives.strip_edges() != "" and passive_ids.is_empty()):
			continue

		host_rows.append({
			"file": table.file, "row": table.line_of(i), "id": ctx["id"],
			"name": name["value"], "passive_ids": passive_ids, "in_pool": in_pool,
		})


func read_upgrades() -> void:
	var table := DataTable.read(_path("upgrades"), DataIssues.DATASET_UPGRADES, Vocab.UPGRADE_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var ctx := _row_ctx(table, i, DataIssues.DATASET_UPGRADES, "UPGRADE_ID", "UPG_", "UPGRADE")
		if ctx.is_empty():
			continue

		var name := DataTable.check_name(table.get_cell(i, "name"), ctx, issues)
		var raw_passives := table.get_cell(i, "passives")
		var passive_ids := _optional_passive_refs(raw_passives, _field_ctx(ctx, "passives"))

		if not name["ok"] or (raw_passives.strip_edges() != "" and passive_ids.is_empty()):
			continue

		# An UPGRADE that grants nothing is a reward the player cannot perceive.
		# A warning rather than an error: it is legal, just almost certainly a
		# mistake, and blocking startup over it would be heavy-handed.
		if passive_ids.is_empty():
			var c := _field_ctx(ctx, "passives")
			c["reason"] = "UPGRADE grants no PASSIVEs — it will present as an empty reward"
			issues.warn(c)

		upgrade_rows.append({
			"file": table.file, "row": table.line_of(i), "id": ctx["id"],
			"name": name["value"], "passive_ids": passive_ids,
		})


func read_hackers() -> void:
	var table := DataTable.read(_path("hackers"), DataIssues.DATASET_HACKERS, Vocab.HACKER_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var ctx := _row_ctx(table, i, DataIssues.DATASET_HACKERS, "HAK_ID", "HAK_", "Hacker")
		if ctx.is_empty():
			continue

		var name := DataTable.check_name(table.get_cell(i, "name"), ctx, issues)
		var base_link := DataTable.read_int(table.get_cell(i, "BASE_LINK"), 1, 9999, _field_ctx(ctx, "BASE_LINK"), issues)
		var colors := DataTable.parse_token_list(table.get_cell(i, "STRONG_COLORS"), Vocab.COLOR_TOKENS, _field_ctx(ctx, "STRONG_COLORS"), issues)
		var shapes := DataTable.parse_token_list(table.get_cell(i, "STRONG_SHAPES"), Vocab.SHAPE_TOKENS, _field_ctx(ctx, "STRONG_SHAPES"), issues)
		var portfolio := DataTable.parse_sized_ref_list(
			table.get_cell(i, "PRG_SET"), "PRG_H_", Content.PORTFOLIO_SIZE, _field_ctx(ctx, "PRG_SET"), issues
		)
		var raw_passives := table.get_cell(i, "PASSIVES")
		var passive_ids := _optional_passive_refs(raw_passives, _field_ctx(ctx, "PASSIVES"))

		if not name["ok"] or not base_link["ok"] or colors.is_empty() or shapes.is_empty() or portfolio.is_empty():
			continue
		if raw_passives.strip_edges() != "" and passive_ids.is_empty():
			continue

		hacker_rows.append({
			"file": table.file, "row": table.line_of(i), "id": ctx["id"],
			"name": name["value"], "base_link": base_link["value"],
			"strong_colors": colors, "strong_shapes": shapes,
			"portfolio": portfolio, "passive_ids": passive_ids,
			# Presentation placeholders: retained verbatim, never interpreted.
		})


func read_decks() -> void:
	var table := DataTable.read(_path("decks"), DataIssues.DATASET_DECKS, Vocab.DECK_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var ctx := _row_ctx(table, i, DataIssues.DATASET_DECKS, "DEK_ID", "DEK_", "Deck")
		if ctx.is_empty():
			continue

		var name := DataTable.check_name(table.get_cell(i, "name"), ctx, issues)
		var add_link := DataTable.read_int(table.get_cell(i, "ADD_LINK"), 0, 9999, _field_ctx(ctx, "ADD_LINK"), issues)
		var portfolio := DataTable.parse_sized_ref_list(
			table.get_cell(i, "PRG_SET"), "PRG_H_", Content.PORTFOLIO_SIZE, _field_ctx(ctx, "PRG_SET"), issues
		)

		# Exactly one Deck Function. More than one is an error rather than a
		# take-the-first, because which one was intended is unknowable.
		var fn_refs := DataTable.parse_ref_list(
			table.get_cell(i, "FUNCTIONS"), "FNC_", true, false, _field_ctx(ctx, "FUNCTIONS"), issues
		)
		var function_id := ""
		if not fn_refs.is_empty():
			if fn_refs.size() != 1:
				var c := _field_ctx(ctx, "FUNCTIONS")
				c["value"] = table.get_cell(i, "FUNCTIONS").strip_edges()
				c["expected"] = "exactly one FNC_* reference"
				c["reason"] = "exactly one Deck Function is permitted"
				issues.error(c)
			else:
				function_id = fn_refs[0]

		if not name["ok"] or not add_link["ok"] or portfolio.is_empty() or function_id == "":
			continue

		deck_rows.append({
			"file": table.file, "row": table.line_of(i), "id": ctx["id"],
			"name": name["value"], "add_link": add_link["value"],
			"portfolio": portfolio, "function_id": function_id,
		})


func read_systems() -> void:
	var table := DataTable.read(_path("systems"), DataIssues.DATASET_SYSTEMS, Vocab.SYSTEM_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var ctx := _row_ctx(table, i, DataIssues.DATASET_SYSTEMS, "SYS_ID", "SYS_", "System")
		if ctx.is_empty():
			continue

		var name := DataTable.check_name(table.get_cell(i, "name"), ctx, issues)
		# Base maximum ICE. Run escalation is applied on top as an additive
		# modifier, never baked in here.
		var base_ice := DataTable.read_int(table.get_cell(i, "BASE_ICE"), 1, 9999, _field_ctx(ctx, "BASE_ICE"), issues)
		var colors := DataTable.parse_token_list(table.get_cell(i, "STRONG_COLORS"), Vocab.COLOR_TOKENS, _field_ctx(ctx, "STRONG_COLORS"), issues)
		var shapes := DataTable.parse_token_list(table.get_cell(i, "STRONG_SHAPES"), Vocab.SHAPE_TOKENS, _field_ctx(ctx, "STRONG_SHAPES"), issues)
		var programs := DataTable.parse_sized_ref_list(
			table.get_cell(i, "PRG_SET"), "PRG_S_", Content.SYSTEM_BUILD_SIZE, _field_ctx(ctx, "PRG_SET"), issues
		)
		var raw_passives := table.get_cell(i, "PASSIVES")
		var passive_ids := _optional_passive_refs(raw_passives, _field_ctx(ctx, "PASSIVES"))
		var in_pool := DataTable.parse_in_pool(table.get_cell(i, "in_pool"), _field_ctx(ctx, "in_pool"), issues)

		if not name["ok"] or not base_ice["ok"] or colors.is_empty() or shapes.is_empty() or programs.is_empty():
			continue
		if raw_passives.strip_edges() != "" and passive_ids.is_empty():
			continue

		system_rows.append({
			"file": table.file, "row": table.line_of(i), "id": ctx["id"],
			"name": name["value"], "base_ice": base_ice["value"],
			"strong_colors": colors, "strong_shapes": shapes,
			"programs": programs, "passive_ids": passive_ids, "in_pool": in_pool,
		})


## Structurally close to a System, and deliberately its own reader: a Boss has
## no PASSIVES column, its ICE is not subject to Run escalation, and its
## `in_pool` is inert because Boss Selection is explicit. Collapsing the two
## would make every one of those differences an implicit special case.
func read_bosses() -> void:
	var table := DataTable.read(_path("bosses"), DataIssues.DATASET_BOSSES, Vocab.BOSS_HEADER, issues)
	if table == null:
		return

	for i in table.row_count():
		var ctx := _row_ctx(table, i, DataIssues.DATASET_BOSSES, "BOS_ID", "BOS_", "Boss")
		if ctx.is_empty():
			continue

		var name := DataTable.check_name(table.get_cell(i, "name"), ctx, issues)
		# Unlike a System's, this is the FINAL Boss-battle ICE — the Run's
		# additive escalation modifier is never applied on top.
		var base_ice := DataTable.read_int(table.get_cell(i, "BASE_ICE"), 1, 9999, _field_ctx(ctx, "BASE_ICE"), issues)
		var colors := DataTable.parse_token_list(table.get_cell(i, "STRONG_COLORS"), Vocab.COLOR_TOKENS, _field_ctx(ctx, "STRONG_COLORS"), issues)
		var shapes := DataTable.parse_token_list(table.get_cell(i, "STRONG_SHAPES"), Vocab.SHAPE_TOKENS, _field_ctx(ctx, "STRONG_SHAPES"), issues)
		# A Boss fields the existing four-Program enemy model, so PRG_SET
		# resolves through exactly the System build parser rather than acquiring
		# speculative variable-size support.
		var programs := DataTable.parse_sized_ref_list(
			table.get_cell(i, "PRG_SET"), "PRG_S_", Content.SYSTEM_BUILD_SIZE, _field_ctx(ctx, "PRG_SET"), issues
		)
		# Parsed for schema completeness and fingerprinting only — deliberately
		# NOT a selection filter, since Boss Selection lists every valid row.
		var in_pool := DataTable.parse_in_pool(table.get_cell(i, "in_pool"), _field_ctx(ctx, "in_pool"), issues)

		if not name["ok"] or not base_ice["ok"] or colors.is_empty() or shapes.is_empty() or programs.is_empty():
			continue

		boss_rows.append({
			"file": table.file, "row": table.line_of(i), "id": ctx["id"],
			"name": name["value"], "base_ice": base_ice["value"],
			"strong_colors": colors, "strong_shapes": shapes,
			"programs": programs, "in_pool": in_pool,
			# Presentation only: never mechanic authority and never fingerprinted.
		})


## The full pipeline. Every stage runs regardless of earlier failures, so an
## author sees every problem in one pass rather than one per attempt.
##
## Returns `{ok, fingerprint, issues}`. `ok` is false iff any error exists —
## and a false `ok` means startup stops. There is no partial content.
func load_all() -> Dictionary:
	read_all()
	parse_payloads()
	resolve_effect_params()
	build_plans()

	check_duplicate_ids(program_rows, DataIssues.DATASET_HACKER_PROGRAMS, "PRG_ID")
	check_duplicate_ids(function_rows, DataIssues.DATASET_FUNCTIONS, "FNC_ID")
	check_duplicate_ids(passive_rows, DataIssues.DATASET_PASSIVES, "PASSIVE_ID")
	check_duplicate_ids(hacker_rows, DataIssues.DATASET_HACKERS, "HAK_ID")
	check_duplicate_ids(deck_rows, DataIssues.DATASET_DECKS, "DEK_ID")
	check_duplicate_ids(system_rows, DataIssues.DATASET_SYSTEMS, "SYS_ID")
	check_duplicate_ids(host_rows, DataIssues.DATASET_HOSTS, "HOST_ID")
	check_duplicate_ids(upgrade_rows, DataIssues.DATASET_UPGRADES, "UPGRADE_ID")
	check_duplicate_ids(boss_rows, DataIssues.DATASET_BOSSES, "BOS_ID")

	check_required_ids(function_rows, Vocab.REQUIRED_FNC_IDS, DataIssues.DATASET_FUNCTIONS, FILES["functions"])
	check_required_ids(passive_rows, Vocab.REQUIRED_PSV_IDS, DataIssues.DATASET_PASSIVES, FILES["passives"])
	check_required_ids(hacker_rows, Vocab.REQUIRED_HAK_IDS, DataIssues.DATASET_HACKERS, FILES["hackers"])
	check_required_ids(deck_rows, Vocab.REQUIRED_DEK_IDS, DataIssues.DATASET_DECKS, FILES["decks"])
	check_required_ids(system_rows, Vocab.REQUIRED_SYS_IDS, DataIssues.DATASET_SYSTEMS, FILES["systems"])
	check_required_ids(host_rows, Vocab.REQUIRED_HST_IDS, DataIssues.DATASET_HOSTS, FILES["hosts"])
	check_required_ids(upgrade_rows, Vocab.REQUIRED_UPG_IDS, DataIssues.DATASET_UPGRADES, FILES["upgrades"])
	check_required_ids(boss_rows, Vocab.REQUIRED_BOS_IDS, DataIssues.DATASET_BOSSES, FILES["bosses"])

	check_references()
	check_zero_cost_assignments()
	check_carrier_executability()
	check_cross_portfolio()
	check_minimum_content()

	check_duplicate_display_names()
	check_unreferenced_functions()
	check_unreferenced_passives()

	if issues.has_errors():
		return {"ok": false, "fingerprint": "", "issues": issues}
	return {
		"ok": true,
		"fingerprint": compute_fingerprint(),
		"issues": issues,
		"content": build_resolved(),
	}


## Turns validated rows into the immutable records the runtime reads.
##
## Everything here has already passed validation, so this stage resolves
## references rather than checking them — a reference that could fail would have
## been reported long before reaching this point.
##
## Cross-links are stored as resolved OBJECTS, not IDs, so combat never walks a
## map mid-resolution. Stable IDs remain on each record for saves and logs,
## which is the one place identity must survive as text.
func build_resolved() -> Dictionary:
	var fn_by_id := {}
	for f in function_rows:
		fn_by_id[f["id"]] = {
			"id": f["id"],
			"name": f["name"],
			"cost": f["cost"],
			"composite": payloads[f["id"]]["kind"] == "composite",
			"plan": plans.get(f["id"], []),
			"notes": f["notes"],
			# A directly assigned owner starts each battle with charge equal to
			# cost when true. Ignored when the Function only ever runs as a
			# composite child, which pays nothing.
			"start_charged": f["start_charged"],
		}

	var psv_by_id := {}
	for s in passive_rows:
		psv_by_id[s["id"]] = {
			"id": s["id"],
			"effect_type": s["effect_type"],
			"activation": s["activation"],
			"agent_scope": s["agent_scope"],
			"color": s["color"],
			"all_scope": s["all_scope"],
			"magnitude": s["magnitude"],
			"function_id": s["function_id"],
			"display": s["display"],
			"display_template": s["display_template"],
			"param_tokens": s["param_tokens"],
		}

	var prg_by_id := {}
	for p in program_rows:
		var fn: Dictionary = fn_by_id[p["function_id"]]
		prg_by_id[p["id"]] = {
			"id": p["id"],
			"side": Types.Side.PLAYER if p["dataset"] == DataIssues.DATASET_HACKER_PROGRAMS else Types.Side.ENEMY,
			"name": p["name"],
			"colors": p["colors"],
			"shapes": p["shapes"],
			"function_id": p["function_id"],
			"fn": fn,
			"cost": fn["cost"],
			# A charge pool's capacity IS its Function's cost — which is exactly
			# why a zero-cost Function may not be assigned here.
			"charge_cap": fn["cost"],
			"notes": p["notes"],
		}

	return {
		"fingerprint": compute_fingerprint(),
		"game_version": Content.GAME_VERSION,
		"programs": prg_by_id,
		"functions": fn_by_id,
		"passives": psv_by_id,
		"hackers": _resolve_identity(hacker_rows, psv_by_id, fn_by_id),
		"decks": _resolve_identity(deck_rows, psv_by_id, fn_by_id),
		"systems": _resolve_identity(system_rows, psv_by_id, fn_by_id),
		"hosts": _resolve_identity(host_rows, psv_by_id, fn_by_id),
		"upgrades": _resolve_identity(upgrade_rows, psv_by_id, fn_by_id),
		"bosses": _resolve_identity(boss_rows, psv_by_id, fn_by_id),

		# Text framework (beta 0.3.2). Carried in the same resolved dictionary as
		# everything else so there is ONE published content object — a second
		# channel would be the competing source of truth §15 forbids.
		"text": text_rows,
		"styles": style_rows,
		"fonts": font_rows,
	}


## Copies a row and attaches its resolved PASSIVE list and Deck Function.
## Rows that carry neither are passed through unchanged.
func _resolve_identity(rows: Array, psv_by_id: Dictionary, fn_by_id: Dictionary) -> Dictionary:
	var out := {}
	for r in rows:
		var rec: Dictionary = r.duplicate(true)
		if r.has("passive_ids"):
			var resolved: Array = []
			for pid in (r["passive_ids"] as Array):
				resolved.append(psv_by_id[pid])
			rec["passives"] = resolved
		if r.has("function_id") and fn_by_id.has(r["function_id"]):
			rec["fn"] = fn_by_id[r["function_id"]]
		out[r["id"]] = rec
	return out


## Reads all ten datasets. Every reader runs regardless of earlier failures, so
## an author sees every problem in one pass.
func read_all() -> void:
	# Text FIRST. PASSIVE display templates now live in `text_content.csv`, so
	# `read_passives()` cannot validate its param contract until the strings
	# exist. Ordering carries that dependency rather than a lazy lookup.
	read_text_content()
	read_text_styles()
	read_font_refs()

	read_programs("hacker_programs", DataIssues.DATASET_HACKER_PROGRAMS, "PRG_H_")
	read_programs("system_programs", DataIssues.DATASET_SYSTEM_PROGRAMS, "PRG_S_")
	read_functions()
	read_passives()
	read_hosts()
	read_upgrades()
	read_hackers()
	read_decks()
	read_systems()
	read_bosses()


# ---------------------------------------------------------------------------
# Duplicate and required-ID checks
# ---------------------------------------------------------------------------

## Stable IDs are content identity, so a duplicate is never a merge — it is an
## authoring mistake that would otherwise silently shadow one of the two rows.
func check_duplicate_ids(rows: Array[Dictionary], dataset: String, field: String) -> void:
	var seen := {}
	for r in rows:
		var id: String = r["id"]
		if seen.has(id):
			issues.error({
				"dataset": dataset, "file": r["file"], "row": r["row"], "id": id,
				"field": field, "value": id,
				"reason": "duplicate record ID (first seen on row %d)" % seen[id],
			})
			continue
		seen[id] = r["row"]


# ---------------------------------------------------------------------------
# Payload grammar
# ---------------------------------------------------------------------------

## A Function is either a LEAF that invokes one coded Effect, or a one-level
## COMPOSITE that invokes leaf Functions in order.
##
## One-level nesting is what makes cycles structurally impossible rather than
## something to detect: a composite may only reference leaves, so no chain can
## ever return to its start.
##
## Populates `payloads`: id to `{kind, effect_id, children}`. A Function absent
## from the map failed validation and has already reported why.
var payloads := {}


func parse_payloads() -> void:
	var fn_ids := {}
	for f in function_rows:
		fn_ids[f["id"]] = true

	for f in function_rows:
		var ctx := {
			"dataset": DataIssues.DATASET_FUNCTIONS, "file": f["file"],
			"row": f["row"], "id": f["id"], "field": "payload",
		}
		var raw: String = f["payload_raw"]
		var tokens: Array[String] = []
		var has_blank := false
		for tk in raw.split(":"):
			var t := tk.strip_edges()
			if t == "":
				has_blank = true
			tokens.append(t)

		if has_blank:
			var c := ctx.duplicate()
			c["value"] = raw
			c["reason"] = "blank token in payload"
			issues.error(c)
			continue

		var effect_tokens: Array[String] = []
		var fn_tokens: Array[String] = []
		var bad_token := ""
		for t in tokens:
			if t.begins_with("EFFECT_"):
				effect_tokens.append(t)
			elif t.begins_with("FNC_"):
				fn_tokens.append(t)
			elif bad_token == "":
				bad_token = t

		if effect_tokens.size() + fn_tokens.size() != tokens.size():
			var c := ctx.duplicate()
			c["value"] = bad_token
			c["expected"] = "EFFECT_* or FNC_*"
			c["reason"] = "payload entry is neither an Effect ID nor a Function ID"
			issues.error(c)
			continue

		if not effect_tokens.is_empty() and not fn_tokens.is_empty():
			var c := ctx.duplicate()
			c["value"] = raw
			c["reason"] = "payload may not mix EFFECT_* and FNC_* entries"
			issues.error(c)
			continue

		if effect_tokens.size() > 1:
			var c := ctx.duplicate()
			c["value"] = raw
			c["reason"] = "a leaf payload must be exactly one EFFECT_* ID"
			issues.error(c)
			continue

		if effect_tokens.size() == 1:
			if not Effects.is_effect_id(effect_tokens[0]):
				var c := ctx.duplicate()
				c["value"] = effect_tokens[0]
				c["reason"] = "unknown Effect ID"
				issues.error(c)
				continue
			payloads[f["id"]] = {"kind": "leaf", "effect_id": effect_tokens[0], "children": []}
		else:
			if fn_tokens.has(f["id"]):
				var c := ctx.duplicate()
				c["value"] = f["id"]
				c["reason"] = "self-reference in payload is invalid"
				issues.error(c)
				continue
			# Repeats are allowed and intentional: a composite may invoke the
			# same child twice.
			payloads[f["id"]] = {"kind": "composite", "effect_id": "", "children": fn_tokens}

	_check_composite_children(fn_ids)


## Composite children must exist and be LEAF Functions. Rejecting
## composite-of-composite is what enforces one-level nesting, and with it the
## impossibility of a cycle.
func _check_composite_children(fn_ids: Dictionary) -> void:
	for f in function_rows:
		var id: String = f["id"]
		if not payloads.has(id) or payloads[id]["kind"] != "composite":
			continue

		var ctx := {
			"dataset": DataIssues.DATASET_FUNCTIONS, "file": f["file"],
			"row": f["row"], "id": id, "field": "payload",
		}
		var ok := true
		for child in (payloads[id]["children"] as Array):
			if not fn_ids.has(child):
				var c := ctx.duplicate()
				c["value"] = child
				c["reason"] = "payload references an unknown Function ID"
				issues.error(c)
				ok = false
			elif not payloads.has(child):
				# The child failed its own payload validation and has already
				# reported why; adding a second message here would be noise.
				ok = false
			elif payloads[child]["kind"] == "composite":
				var c := ctx.duplicate()
				c["value"] = child
				c["reason"] = "a composite Function may not reference another composite Function (one-level nesting only)"
				issues.error(c)
				ok = false

		if not ok:
			payloads.erase(id)


# ---------------------------------------------------------------------------
# Effect parameter contracts
# ---------------------------------------------------------------------------

## Resolved leaf parameters, keyed by Function ID.
var fn_params := {}


## Validates each leaf Function's discrete columns and compound tuple against
## its Effect's contract, and resolves them into typed values so runtime never
## re-parses raw text.
##
## Anything the contract does not claim is *unused* and warns when populated.
## Silence there would let a stray value sit in a column doing nothing for
## months, looking authored.
func resolve_effect_params() -> void:
	for f in function_rows:
		var id: String = f["id"]
		if not payloads.has(id):
			continue

		var p: Dictionary = payloads[id]
		var ctx := {
			"dataset": DataIssues.DATASET_FUNCTIONS, "file": f["file"],
			"row": f["row"], "id": id,
		}

		if p["kind"] == "composite":
			_warn_unused_on_composite(f, ctx)
			continue

		var contract := Effects.contract(str(p["effect_id"]))
		var out := {}
		var ok := _resolve_discrete_params(f, contract, str(p["effect_id"]), ctx, out)
		if not _resolve_tuple(f, contract, str(p["effect_id"]), ctx, out):
			ok = false
		if not _resolve_axes(f, contract, str(p["effect_id"]), ctx, out):
			ok = false

		if ok:
			fn_params[id] = out


## The Transform axis columns.
##
## The colon is INTERSECTION: `GRE:TRI` means "green triangles", never "green
## or triangular". There is deliberately no OR targeting, no multi-value axis,
## and no negation — which is why two tokens of the same kind are rejected
## rather than unioned.
func _resolve_axes(f: Dictionary, contract: Dictionary, effect_id: String, ctx: Dictionary, out: Dictionary) -> bool:
	var declared: Array = contract["axes"]
	var axes: Dictionary = f["axes"]
	var ok := true

	for col in Effects.AXIS_NAMES:
		var raw := str(axes[col]).strip_edges()

		if not declared.has(col):
			if raw != "":
				var c := _field_ctx(ctx, col)
				c["value"] = raw
				c["reason"] = "populated parameter is unused by %s" % effect_id
				issues.warn(c)
			continue

		if raw == "":
			var c := _field_ctx(ctx, col)
			c["reason"] = "missing required parameter for %s" % effect_id
			issues.error(c)
			ok = false
			continue

		var tokens: Array[String] = []
		var has_blank := false
		for tk in raw.split(":"):
			var t := tk.strip_edges()
			if t == "":
				has_blank = true
			tokens.append(t)

		if has_blank:
			var c := _field_ctx(ctx, col)
			c["value"] = raw
			c["reason"] = "blank token in axis list"
			issues.error(c)
			ok = false
			continue

		if tokens.size() > 2:
			var c := _field_ctx(ctx, col)
			c["value"] = raw
			c["expected"] = "<AXIS> or <COLOR>:<SHAPE>"
			c["reason"] = "an axis list holds at most one color and one shape"
			issues.error(c)
			ok = false
			continue

		# NEU and ALL are whole-Packet tokens and never combine with an axis.
		var whole := ""
		for t in tokens:
			if t == Content.AXIS_NEUTRAL or t == Content.AXIS_ALL:
				whole = t

		if whole != "":
			if tokens.size() != 1:
				var c := _field_ctx(ctx, col)
				c["value"] = raw
				c["expected"] = whole
				c["reason"] = "%s selects whole Packets and cannot be combined with an axis" % whole
				issues.error(c)
				ok = false
				continue

			if col == "axisTarget":
				var kind := Content.AxisTargetKind.NEU if whole == Content.AXIS_NEUTRAL else Content.AxisTargetKind.ALL
				out["axisTarget"] = {"token": raw, "kind": kind, "color": null, "shape": null}
			else:
				# ALL is a target, not a result: "turn these into everything"
				# has no meaning.
				if whole == Content.AXIS_ALL:
					var c := _field_ctx(ctx, col)
					c["value"] = raw
					c["expected"] = "%s|<COLOR>|<SHAPE>|<COLOR>:<SHAPE>" % Content.AXIS_NEUTRAL
					c["reason"] = "ALL is not a transform RESULT"
					issues.error(c)
					ok = false
					continue
				out["axisResult"] = {"token": raw, "neutral": true, "color": null, "shape": null}
			continue

		# Axis-specific form: at most one colour and at most one shape.
		var color = null
		var shape = null
		var axes_ok := true
		for t in tokens:
			if Vocab.COLOR_TOKENS.has(t):
				if color != null:
					var c := _field_ctx(ctx, col)
					c["value"] = raw
					c["reason"] = "an axis list holds at most one color"
					issues.error(c)
					axes_ok = false
					break
				color = Vocab.COLOR_TOKENS[t]
			elif Vocab.SHAPE_TOKENS.has(t):
				if shape != null:
					var c := _field_ctx(ctx, col)
					c["value"] = raw
					c["reason"] = "an axis list holds at most one shape"
					issues.error(c)
					axes_ok = false
					break
				shape = Vocab.SHAPE_TOKENS[t]
			else:
				var allowed := PackedStringArray([Content.AXIS_NEUTRAL])
				if col == "axisTarget":
					allowed.append(Content.AXIS_ALL)
				allowed.append_array(PackedStringArray(Vocab.COLOR_TOKENS.keys()))
				allowed.append_array(PackedStringArray(Vocab.SHAPE_TOKENS.keys()))
				var c := _field_ctx(ctx, col)
				c["value"] = t
				c["expected"] = "|".join(allowed)
				c["reason"] = "unknown axis token"
				issues.error(c)
				axes_ok = false
				break

		if not axes_ok:
			ok = false
			continue

		if col == "axisTarget":
			out["axisTarget"] = {"token": raw, "kind": Content.AxisTargetKind.AXIS, "color": color, "shape": shape}
		else:
			out["axisResult"] = {"token": raw, "neutral": false, "color": color, "shape": shape}

	return ok


## A composite pays the parent cost once and delegates everything else to its
## children, so every discrete parameter column on its own row is unused.
func _warn_unused_on_composite(f: Dictionary, ctx: Dictionary) -> void:
	var params: Dictionary = f["params"]
	for col in Effects.PARAM_NAMES:
		if str(params[col]).strip_edges() != "":
			var c := ctx.duplicate()
			c["field"] = col
			c["value"] = params[col]
			c["reason"] = "populated parameter is unused by a composite Function"
			issues.warn(c)
	if str(f["tuple_raw"]) != "":
		var c := ctx.duplicate()
		c["field"] = "params"
		c["value"] = f["tuple_raw"]
		c["reason"] = "populated parameter is unused by a composite Function"
		issues.warn(c)


func _resolve_discrete_params(f: Dictionary, contract: Dictionary, effect_id: String, ctx: Dictionary, out: Dictionary) -> bool:
	var params: Dictionary = f["params"]
	var required: Array = contract["required"]
	var optional: Array = contract["optional"]
	var ok := true

	for col in Effects.PARAM_NAMES:
		var raw: String = params[col]
		var is_required := required.has(col)

		# An OPTIONAL column is validated when supplied and simply absent
		# otherwise. Blank is MEANINGFUL here — it selects immediate Bomb
		# resolution — so it is neither an error nor an unused-parameter warning.
		if not is_required and optional.has(col) and col != "areaPattern":
			var parsed := Vocab.parse_int_field(raw)
			if not parsed["present"]:
				continue
			if not parsed["valid"]:
				var c := _field_ctx(ctx, col)
				c["value"] = raw.strip_edges()
				c["expected"] = "non-negative integer"
				c["reason"] = "invalid %s for %s" % [col, effect_id]
				issues.error(c)
				ok = false
				continue
			# countdown 0 explicitly means "resolve immediately"; a negative
			# value cannot reach here because the integer syntax rejects signs.
			if int(parsed["value"]) > 9999:
				var c := _field_ctx(ctx, col)
				c["value"] = raw.strip_edges()
				c["expected"] = "0-9999"
				c["reason"] = "parameter out of range"
				issues.error(c)
				ok = false
				continue
			out[col] = int(parsed["value"])
			continue

		if col == "areaPattern":
			if not _resolve_area_pattern(raw, is_required, effect_id, ctx, out):
				ok = false
			continue

		var parsed := Vocab.parse_int_field(raw)
		if is_required:
			if not parsed["present"] or not parsed["valid"]:
				var c := _field_ctx(ctx, col)
				if raw.strip_edges() != "":
					c["value"] = raw.strip_edges()
				c["expected"] = "positive integer"
				c["reason"] = "missing or invalid required parameter for %s" % effect_id
				issues.error(c)
				ok = false
				continue

			# `quantity` means "up to this many valid targets", so an authored
			# maximum may legitimately exceed the board's cell count — COERCE
			# uses 99 to mean "every eligible Packet". 99 is an ORDINARY number
			# here, never a sentinel, and fewer targets simply means fewer
			# deployments.
			var lo := 1
			var hi := 999999
			if col == "quantity":
				hi = 999
			elif col == "countdown":
				hi = 9999

			var v := int(parsed["value"])
			if v < lo or v > hi:
				var c := _field_ctx(ctx, col)
				c["value"] = raw.strip_edges()
				c["expected"] = "%d-%d" % [lo, hi]
				c["reason"] = "parameter out of range"
				issues.error(c)
				ok = false
				continue
			out[col] = v
		elif parsed["present"]:
			# Populated-but-unused warns, including a numeric 0.
			var c := _field_ctx(ctx, col)
			c["value"] = raw.strip_edges()
			c["reason"] = "populated parameter is unused by %s" % effect_id
			issues.warn(c)

	return ok


func _resolve_area_pattern(raw: String, is_required: bool, effect_id: String, ctx: Dictionary, out: Dictionary) -> bool:
	var t := raw.strip_edges()
	var expected := "|".join(Areas.patterns().keys())

	if is_required:
		if t == "":
			var c := _field_ctx(ctx, "areaPattern")
			c["expected"] = expected
			c["reason"] = "missing required parameter for %s" % effect_id
			issues.error(c)
			return false
		if not Areas.is_pattern_id(t):
			var c := _field_ctx(ctx, "areaPattern")
			c["value"] = t
			c["expected"] = expected
			c["reason"] = "unknown area pattern"
			issues.error(c)
			return false
		out["areaPattern"] = t
		return true

	if t != "":
		var c := _field_ctx(ctx, "areaPattern")
		c["value"] = t
		c["reason"] = "populated parameter is unused by %s" % effect_id
		issues.warn(c)
	return true


func _resolve_tuple(f: Dictionary, contract: Dictionary, effect_id: String, ctx: Dictionary, out: Dictionary) -> bool:
	var tuple_fields: Array = contract["tuple"]
	var raw: String = f["tuple_raw"]

	if tuple_fields.is_empty():
		if raw != "":
			var c := _field_ctx(ctx, "params")
			c["value"] = raw
			c["reason"] = "populated parameter is unused by %s" % effect_id
			issues.warn(c)
		return true

	if raw == "":
		var names := PackedStringArray()
		for tf in tuple_fields:
			names.append(tf["name"])
		var c := _field_ctx(ctx, "params")
		c["expected"] = ":".join(names)
		c["reason"] = "missing required params tuple for %s" % effect_id
		issues.error(c)
		return false

	var parsed := DataTable.read_tuple(raw, tuple_fields, _field_ctx(ctx, "params"), issues)
	if not parsed["ok"]:
		return false

	var vals: Array = parsed["values"]
	match effect_id:
		Effects.BOMB:
			out["bomb"] = {"targeting": vals[0], "dealDamage": vals[1], "gainCharge": vals[2]}
		Effects.LINESLICE:
			out["line"] = {
				"dimension": vals[0], "targeting": vals[1], "specialRetention": vals[2],
				"dealDamage": vals[3], "gainCharge": vals[4],
			}
		Effects.TRANSFORM:
			out["transform"] = {"targeting": vals[0], "specialPacketTreatment": vals[1]}
		Effects.SHAKE:
			out["shake"] = {
				"boardComposition": vals[0], "specialGems": vals[1],
				"matches": vals[2], "cascades": vals[3],
			}
			# Valid data whose combination is inert: with matches disabled, the
			# cascade mode has nothing to act on.
			if vals[2] == Content.SHAKE_PREVENT_MATCHES and vals[3] != Content.SHAKE_CASCADE_NONE:
				var c := _field_ctx(ctx, "params")
				c["value"] = raw
				c["reason"] = "EFFECT_SHAKE matches are disabled while a nonzero cascade mode is supplied — the cascade mode is currently ignored"
				issues.warn(c)

	return true


# ---------------------------------------------------------------------------
# Plan assembly
# ---------------------------------------------------------------------------

## Expanded execution plans, keyed by Function ID. A leaf has one op; a
## composite has one op per child reference, in payload order.
var plans := {}


## Whether an op asks the player to pick something, and for what.
##
## Resolved once here rather than recomputed at runtime, because targeting is
## no longer a property of the Effect alone: Bomb, LineSlice, and Transform each
## select it per row through their typed tuple. The same Effect is targeted on
## one row and random on the next.
static func resolve_target(effect_id: String, params: Dictionary) -> Types.TargetKind:
	var contract := Effects.contract(effect_id)
	if contract["targeted"]:
		var kind: int = contract["target_kind"]
		return kind if kind != Types.TargetKind.NONE else Types.TargetKind.UNIT

	var targeting = null
	for key in ["bomb", "line", "transform"]:
		if params.has(key):
			targeting = params[key]["targeting"]
			break

	if targeting == Content.TARGETING_TARGETED:
		var kind: int = contract["target_kind"]
		return kind if kind != Types.TargetKind.NONE else Types.TargetKind.PACKET
	return Types.TargetKind.NONE


func _build_plan(fn_id: String) -> Array:
	if not payloads.has(fn_id):
		return []
	var payload: Dictionary = payloads[fn_id]

	if payload["kind"] == "leaf":
		if not fn_params.has(fn_id):
			return []
		var effect_id: String = payload["effect_id"]
		var params: Dictionary = fn_params[fn_id]
		return [{
			"fn_id": fn_id,
			"effect_id": effect_id,
			"params": params,
			"target": resolve_target(effect_id, params),
		}]

	# Children are validated leaves, so this recursion is exactly one level
	# deep and cannot loop.
	var plan: Array = []
	for child in (payload["children"] as Array):
		var child_plan := _build_plan(child)
		if child_plan.is_empty():
			return []
		plan.append_array(child_plan)
	return plan


## Builds every Function's plan and enforces the targeting-order rules against
## the RESOLVED per-op target — so a Bomb row configured for random placement
## is correctly not targeted, while the same Effect configured for player
## selection is.
func build_plans() -> void:
	for f in function_rows:
		var id: String = f["id"]
		var plan := _build_plan(id)
		if plan.is_empty():
			continue  # upstream errors already reported

		var ctx := {
			"dataset": DataIssues.DATASET_FUNCTIONS, "file": f["file"],
			"row": f["row"], "id": id, "field": "payload",
		}
		var ok := true

		var targeted_indices: Array[int] = []
		var drain_count := 0
		for i in plan.size():
			var op: Dictionary = plan[i]
			if op["target"] != Types.TargetKind.NONE:
				targeted_indices.append(i)
			if op["effect_id"] == Effects.DRAIN:
				drain_count += 1

		if drain_count > 1:
			var c := ctx.duplicate()
			c["reason"] = "two Drain operations in one expanded payload are invalid"
			issues.error(c)
			ok = false

		# At most one targeted operation, and it must run first. Anything else
		# would mean asking the player to pick a Packet partway through a
		# resolution that has already changed the board under them.
		if targeted_indices.size() > 1:
			var c := ctx.duplicate()
			c["reason"] = "more than one non-random targeted operation in one expanded payload"
			issues.error(c)
			ok = false
		elif targeted_indices.size() == 1 and targeted_indices[0] != 0:
			var c := ctx.duplicate()
			c["reason"] = "a non-random targeted operation must be the first expanded operation"
			issues.error(c)
			ok = false

		if ok:
			plans[id] = plan


# ---------------------------------------------------------------------------
# Fingerprint
# ---------------------------------------------------------------------------

## Builds the canonical structure and hashes it. Must reproduce the alpha's
## value byte-for-byte for identical content.
##
## What is INCLUDED is everything gameplay-affecting; what is EXCLUDED is
## presentation — display names, BIO, GRAPHICS, notes, PASSIVE display text,
## and BOSS_PASSIVE_DESCRIPTION. That split is the point: fixing a typo in
## flavour copy must never invalidate a player's save.
##
## Derived values are excluded too. Weak sets are the enum-order complement of
## the authored strong sets, so fingerprinting both would be duplicate
## authority.
func compute_fingerprint() -> String:
	var used_areas := {}
	var fn_norm := _fingerprint_functions(used_areas)

	# Every registered pattern is included, not just those the FNC rows name:
	# PSV_BIGGER_BOMB can advance an authored Bomb into any larger pattern, so
	# the whole ordered registry is gameplay-affecting.
	for id in Areas.PATTERN_ORDER:
		used_areas[id] = true
	var area_ids := used_areas.keys()
	area_ids.sort()
	var areas: Array = []
	for id in area_ids:
		var entry := {}
		entry["id"] = id
		entry["cells"] = Areas.cells(id)
		areas.append(entry)

	var canonical := {}
	canonical["schema"] = Content.DATA_SCHEMA_VERSION
	canonical["hacker"] = _fingerprint_programs(DataIssues.DATASET_HACKER_PROGRAMS, "player")
	canonical["system"] = _fingerprint_programs(DataIssues.DATASET_SYSTEM_PROGRAMS, "enemy")
	canonical["functions"] = fn_norm
	canonical["areas"] = areas
	canonical["areaOrder"] = Areas.PATTERN_ORDER
	canonical["hackers"] = _fingerprint_hackers()
	canonical["passives"] = _fingerprint_passives()
	canonical["decks"] = _fingerprint_decks()
	canonical["systems"] = _fingerprint_systems()
	canonical["hosts"] = _fingerprint_hosts()
	canonical["upgrades"] = _fingerprint_upgrades()
	canonical["bosses"] = _fingerprint_bosses()

	return Fingerprint.of(canonical)


## Rows sorted by stable ID, so authored row order never changes the
## fingerprint — only authored content does.
func _sorted_by_id(rows: Array) -> Array:
	var out := rows.duplicate()
	out.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return out


## Programs keep FILE order rather than being sorted: they are emitted as the
## resolved per-side lists, which is how the runtime holds them.
func _fingerprint_programs(dataset: String, side: String) -> Array:
	var out: Array = []
	for p in program_rows:
		if p["dataset"] != dataset:
			continue
		var e := {}
		e["id"] = p["id"]
		e["side"] = side
		e["colors"] = p["colors"]
		e["shapes"] = p["shapes"]
		e["fn"] = p["function_id"]
		out.append(e)
	return out


func _fingerprint_functions(used_areas: Dictionary) -> Array:
	var out: Array = []
	for f in _sorted_by_id(function_rows):
		var id: String = f["id"]
		var e := {}
		e["id"] = id
		e["cost"] = f["cost"]
		e["sc"] = f["start_charged"]

		var plan_out: Array = []
		for op in (plans.get(id, []) as Array):
			var params: Dictionary = op["params"]
			if params.has("areaPattern"):
				used_areas[params["areaPattern"]] = true

			var o := {}
			o["fn"] = op["fn_id"]
			o["effect"] = op["effect_id"]
			o["q"] = params.get("quantity", null)
			o["cd"] = params.get("countdown", null)
			o["ap"] = params.get("areaPattern", null)
			o["mag"] = params.get("magnitude", null)
			o["dmg"] = params.get("damage", null)
			o["shake"] = _tuple_array(params, "shake", ["boardComposition", "specialGems", "matches", "cascades"])
			o["bomb"] = _tuple_array(params, "bomb", ["targeting", "dealDamage", "gainCharge"])
			o["line"] = _tuple_array(params, "line", ["dimension", "targeting", "specialRetention", "dealDamage", "gainCharge"])
			o["xf"] = _tuple_array(params, "transform", ["targeting", "specialPacketTreatment"])
			o["at"] = _axis_target(params)
			o["ar"] = _axis_result(params)
			o["tgt"] = _target_name(op["target"])
			plan_out.append(o)

		e["plan"] = plan_out
		out.append(e)
	return out


func _tuple_array(params: Dictionary, key: String, fields: Array):
	if not params.has(key):
		return null
	var t: Dictionary = params[key]
	var out: Array = []
	for f in fields:
		out.append(t[f])
	return out


## The whole axis-target object reaches the fingerprint, and JavaScript omits
## undefined properties — so a whole-Packet target serializes as `{token, kind}`
## with no colour or shape keys at all, not as explicit nulls.
func _axis_target(params: Dictionary):
	if not params.has("axisTarget"):
		return null
	var at: Dictionary = params["axisTarget"]
	var e := {}
	e["token"] = at["token"]
	e["kind"] = ["NEU", "ALL", "AXIS"][at["kind"]]
	if at["color"] != null:
		e["color"] = at["color"]
	if at["shape"] != null:
		e["shape"] = at["shape"]
	return e


## The result contributes only its resolved axes, as a two-element array. An
## unauthored axis is null — which is meaningful: a single-axis result PRESERVES
## the other axis rather than clearing it.
func _axis_result(params: Dictionary):
	if not params.has("axisResult"):
		return null
	var ar: Dictionary = params["axisResult"]
	return [ar["color"], ar["shape"]]


func _target_name(target: int):
	match target:
		Types.TargetKind.UNIT:
			return "unit"
		Types.TargetKind.PACKET:
			return "packet"
		_:
			return null


func _fingerprint_hackers() -> Array:
	var out: Array = []
	for h in _sorted_by_id(hacker_rows):
		var e := {}
		e["id"] = h["id"]
		e["link"] = h["base_link"]
		e["sc"] = h["strong_colors"]
		e["ss"] = h["strong_shapes"]
		e["psv"] = h["passive_ids"]
		# Portfolio ORDER is mandatory input: it determines the default build
		# and the inventory's source display.
		e["prg"] = h["portfolio"]
		out.append(e)
	return out


func _fingerprint_passives() -> Array:
	var out: Array = []
	for s in _sorted_by_id(passive_rows):
		var e := {}
		e["id"] = s["id"]
		e["effect"] = s["effect_type"]
		e["act"] = s["activation"]
		e["scope"] = s["agent_scope"]
		e["color"] = s["color"]
		# The alpha models this as `true` or absent, never `false`.
		e["all"] = true if s["all_scope"] else null
		e["mag"] = s["magnitude"]
		e["fn"] = null if str(s["function_id"]) == "" else s["function_id"]
		out.append(e)
	return out


func _fingerprint_decks() -> Array:
	var out: Array = []
	for d in _sorted_by_id(deck_rows):
		var e := {}
		e["id"] = d["id"]
		e["add"] = d["add_link"]
		e["fn"] = d["function_id"]
		e["prg"] = d["portfolio"]
		out.append(e)
	return out


func _fingerprint_systems() -> Array:
	var out: Array = []
	for s in _sorted_by_id(system_rows):
		var e := {}
		e["id"] = s["id"]
		e["ice"] = s["base_ice"]
		e["sc"] = s["strong_colors"]
		e["ss"] = s["strong_shapes"]
		# PRG_SET order matters: it is charge-routing priority.
		e["prg"] = s["programs"]
		e["psv"] = s["passive_ids"]
		e["pool"] = s["in_pool"]
		out.append(e)
	return out


func _fingerprint_hosts() -> Array:
	var out: Array = []
	for h in _sorted_by_id(host_rows):
		var e := {}
		e["id"] = h["id"]
		e["psv"] = h["passive_ids"]
		e["pool"] = h["in_pool"]
		out.append(e)
	return out


func _fingerprint_upgrades() -> Array:
	var out: Array = []
	for u in _sorted_by_id(upgrade_rows):
		var e := {}
		e["id"] = u["id"]
		e["psv"] = u["passive_ids"]
		out.append(e)
	return out


func _fingerprint_bosses() -> Array:
	var out: Array = []
	for b in _sorted_by_id(boss_rows):
		var e := {}
		e["id"] = b["id"]
		e["ice"] = b["base_ice"]
		e["sc"] = b["strong_colors"]
		e["ss"] = b["strong_shapes"]
		e["prg"] = b["programs"]
		e["pool"] = b["in_pool"]
		out.append(e)
	return out


# ---------------------------------------------------------------------------
# Cross-dataset checks
# ---------------------------------------------------------------------------

## Duplicate display names are VALID — they warn rather than block. Two records
## may legitimately share a name, but it is nearly always an authoring slip, and
## it makes every log and character sheet ambiguous.
##
## Scanned in a fixed order across every named dataset, so which row is reported
## as the duplicate and which as the original is deterministic.
func check_duplicate_display_names() -> void:
	var seen := {}
	var groups := [
		[program_rows, ""],  # Programs carry their own dataset name per row
		[function_rows, DataIssues.DATASET_FUNCTIONS],
		[hacker_rows, DataIssues.DATASET_HACKERS],
		[deck_rows, DataIssues.DATASET_DECKS],
		[system_rows, DataIssues.DATASET_SYSTEMS],
		[host_rows, DataIssues.DATASET_HOSTS],
		[upgrade_rows, DataIssues.DATASET_UPGRADES],
		[boss_rows, DataIssues.DATASET_BOSSES],
	]

	for g in groups:
		var rows: Array = g[0]
		var dataset: String = g[1]
		for r in rows:
			var name: String = r["name"]
			if seen.has(name):
				issues.warn({
					"dataset": r.get("dataset", dataset), "file": r["file"], "row": r["row"],
					"id": r["id"], "field": "name", "value": name,
					"reason": "duplicate display name (also used by %s)" % seen[name],
				})
			else:
				seen[name] = r["id"]


## A Function row nothing can reach is dead content — it looks authored but can
## never fire. A warning rather than an error, because a row staged ahead of the
## build that uses it is legitimate.
##
## References come from four places, and missing any of them would produce a
## false warning on genuinely live content.
func check_unreferenced_functions() -> void:
	var referenced := {}
	for p in program_rows:
		referenced[p["function_id"]] = true
	for d in deck_rows:
		referenced[d["function_id"]] = true
	# A PASSIVE carrier payload is a real reference — it is exactly how GREENING
	# and SNEAK reach the board.
	for s in passive_rows:
		if str(s["function_id"]) != "":
			referenced[s["function_id"]] = true
	# ODANSHAY's mechanic payloads are referenced by CODE rather than by data,
	# because the Boss schema deliberately has no MECHANIC_ID column. They are
	# real references all the same and must not warn as dead rows.
	for id in Content.BOSS_MECHANIC_FUNCTION_IDS:
		referenced[id] = true

	for f in function_rows:
		if not referenced.has(f["id"]):
			issues.warn({
				"dataset": DataIssues.DATASET_FUNCTIONS, "file": f["file"], "row": f["row"], "id": f["id"],
				"reason": "valid Function row is not referenced by any Program, Deck, composite payload, or PASSIVE",
			})


## A PASSIVE row is referenced when ANY source kind cites it.
func check_unreferenced_passives() -> void:
	var referenced := {}
	for group in [hacker_rows, system_rows, host_rows, upgrade_rows]:
		for r in group:
			for pid in (r["passive_ids"] as Array):
				referenced[pid] = true

	for s in passive_rows:
		if not referenced.has(s["id"]):
			issues.warn({
				"dataset": DataIssues.DATASET_PASSIVES, "file": s["file"], "row": s["row"], "id": s["id"],
				"reason": "valid PASSIVE row is not referenced by any Hacker, System, HOST, or UPGRADE",
			})


## Every stable-ID reference must resolve to a loaded record. Unresolved
## references are errors rather than dropped entries: silently ignoring one
## would ship content that looks authored and does nothing.
func check_references() -> void:
	var fn_ids := _id_set(function_rows)
	var psv_ids := _id_set(passive_rows)
	var prg_h := {}
	var prg_s := {}
	for p in program_rows:
		if p["dataset"] == DataIssues.DATASET_HACKER_PROGRAMS:
			prg_h[p["id"]] = true
		else:
			prg_s[p["id"]] = true

	for p in program_rows:
		_require_ref(p["function_id"], fn_ids, p, p["dataset"], "functions", "a loaded FNC_* Function", "references an unknown Function ID")

	for d in deck_rows:
		_require_ref(d["function_id"], fn_ids, d, DataIssues.DATASET_DECKS, "FUNCTIONS", "a loaded FNC_* Function", "references an unknown Function ID")
		for pid in (d["portfolio"] as Array):
			_require_ref(pid, prg_h, d, DataIssues.DATASET_DECKS, "PRG_SET", "a loaded PRG_H_* Program", "PRG_SET references an unknown Hacker Program ID")

	for h in hacker_rows:
		for pid in (h["portfolio"] as Array):
			_require_ref(pid, prg_h, h, DataIssues.DATASET_HACKERS, "PRG_SET", "a loaded PRG_H_* Program", "PRG_SET references an unknown Hacker Program ID")
		for sid in (h["passive_ids"] as Array):
			_require_ref(sid, psv_ids, h, DataIssues.DATASET_HACKERS, "PASSIVES", "a loaded PSV_* PASSIVE", "references an unknown PASSIVE ID")

	for s in system_rows:
		for pid in (s["programs"] as Array):
			_require_ref(pid, prg_s, s, DataIssues.DATASET_SYSTEMS, "PRG_SET", "a loaded PRG_S_* Program", "PRG_SET references an unknown System Program ID")
		for sid in (s["passive_ids"] as Array):
			_require_ref(sid, psv_ids, s, DataIssues.DATASET_SYSTEMS, "PASSIVES", "a loaded PSV_* PASSIVE", "references an unknown PASSIVE ID")

	for b in boss_rows:
		for pid in (b["programs"] as Array):
			_require_ref(pid, prg_s, b, DataIssues.DATASET_BOSSES, "PRG_SET", "a loaded PRG_S_* Program", "PRG_SET references an unknown System Program ID")

	for h in host_rows:
		for sid in (h["passive_ids"] as Array):
			_require_ref(sid, psv_ids, h, DataIssues.DATASET_HOSTS, "passives", "a loaded PSV_* PASSIVE", "references an unknown PASSIVE ID")

	for u in upgrade_rows:
		for sid in (u["passive_ids"] as Array):
			_require_ref(sid, psv_ids, u, DataIssues.DATASET_UPGRADES, "passives", "a loaded PSV_* PASSIVE", "references an unknown PASSIVE ID")

	for s in passive_rows:
		if str(s["function_id"]) != "":
			_require_ref(s["function_id"], fn_ids, s, DataIssues.DATASET_PASSIVES, "function_payload", "a loaded FNC_* Function", "references an unknown Function ID")


func _id_set(rows: Array) -> Dictionary:
	var out := {}
	for r in rows:
		out[r["id"]] = true
	return out


func _require_ref(ref, known: Dictionary, row: Dictionary, dataset: String, field: String, expected: String, reason: String) -> void:
	if known.has(ref):
		return
	issues.error({
		"dataset": dataset, "file": row["file"], "row": row["row"], "id": row["id"],
		"field": field, "value": ref, "expected": expected, "reason": reason,
	})


## A charge pool's capacity IS its Function's cost, so a zero-cost Function
## fielded by a Program or Deck would hold no pool and fire free every turn.
##
## Cost 0 stays legal for a Function reached only through a PASSIVE, boss, or
## mechanic payload, where no charge is paid — which is exactly what
## FNC_016/017 and ODANSHAY's FNC_018/019/020 are.
func check_zero_cost_assignments() -> void:
	var directly_assigned := {}
	for p in program_rows:
		if not directly_assigned.has(p["function_id"]):
			directly_assigned[p["function_id"]] = p["id"]
	for d in deck_rows:
		if not directly_assigned.has(d["function_id"]):
			directly_assigned[d["function_id"]] = d["id"]

	for f in function_rows:
		if int(f["cost"]) > 0:
			continue
		if not directly_assigned.has(f["id"]):
			continue
		issues.error({
			"dataset": DataIssues.DATASET_FUNCTIONS, "file": f["file"], "row": f["row"],
			"id": f["id"], "field": "cost", "value": "0",
			"expected": "a positive cost for a Program- or Deck-assigned Function",
			"reason": "zero-cost Function is directly assigned to %s — its charge pool would have no capacity" % directly_assigned[f["id"]],
		})


## A START_OF_TURN payload must be executable with NO player target selection:
## the trigger fires inside turn setup, and there is no asynchronous
## start-of-turn targeting flow. A carrier needing a manual target is
## unsupported content, reported rather than silently auto-resolved.
func check_carrier_executability() -> void:
	for s in passive_rows:
		var fn_id := str(s["function_id"])
		if fn_id == "" or not plans.has(fn_id):
			continue
		for op in (plans[fn_id] as Array):
			if op["target"] != Types.TargetKind.NONE:
				issues.error({
					"dataset": DataIssues.DATASET_PASSIVES, "file": s["file"], "row": s["row"],
					"id": s["id"], "field": "function_payload", "value": fn_id,
					"reason": "START_OF_TURN payload requires a manual target, which cannot be supplied during turn setup",
				})
				break


## Every Deck is compatible with every Hacker, so EVERY pairing must be able to
## produce a valid six-Program inventory. Overlap is a content error rather than
## a warning: there are no owned Program instances and no duplicate copies of a
## PRG_ID, so an overlapping pairing simply cannot yield six distinct Programs.
func check_cross_portfolio() -> void:
	for h in hacker_rows:
		for d in deck_rows:
			var overlap: Array[String] = []
			for pid in (h["portfolio"] as Array):
				if (d["portfolio"] as Array).has(pid):
					overlap.append(pid)

			if not overlap.is_empty():
				issues.error({
					"dataset": DataIssues.DATASET_CONTENT, "file": d["file"], "id": d["id"],
					"field": "PRG_SET", "value": ":".join(overlap),
					"reason": "Hacker %s and Deck %s portfolios overlap — the pairing cannot produce %d distinct Programs" % [
						h["id"], d["id"], Content.INVENTORY_SIZE,
					],
				})
				continue

			var combined := {}
			for pid in (h["portfolio"] as Array):
				combined[pid] = true
			for pid in (d["portfolio"] as Array):
				combined[pid] = true
			if combined.size() != Content.INVENTORY_SIZE:
				issues.error({
					"dataset": DataIssues.DATASET_CONTENT, "file": d["file"], "id": d["id"],
					"field": "PRG_SET",
					"reason": "Hacker %s and Deck %s cannot produce %d distinct Programs" % [
						h["id"], d["id"], Content.INVENTORY_SIZE,
					],
				})


## Random encounter selection samples the loaded catalog, so an empty catalog is
## not a playable state — and must never be papered over with a synthesized
## default System.
func check_minimum_content() -> void:
	if system_rows.is_empty():
		issues.error({"dataset": DataIssues.DATASET_SYSTEMS, "file": FILES["systems"], "reason": "at least one valid System is required"})
	if host_rows.is_empty():
		issues.error({"dataset": DataIssues.DATASET_HOSTS, "file": FILES["hosts"], "reason": "at least one valid HOST is required"})
	if boss_rows.is_empty():
		issues.error({"dataset": DataIssues.DATASET_BOSSES, "file": FILES["bosses"], "reason": "at least one valid Boss is required"})
	if upgrade_rows.size() < Content.MIN_UPGRADE_ROWS:
		issues.error({
			"dataset": DataIssues.DATASET_UPGRADES, "file": FILES["upgrades"],
			"value": str(upgrade_rows.size()), "expected": "at least %d" % Content.MIN_UPGRADE_ROWS,
			"reason": "too few valid UPGRADE rows",
		})

	# A pool that excludes everything leaves random routing with nothing to
	# choose, which is a content error rather than a runtime surprise.
	var pooled_systems := 0
	for s in system_rows:
		if s["in_pool"]:
			pooled_systems += 1
	if not system_rows.is_empty() and pooled_systems == 0:
		issues.error({"dataset": DataIssues.DATASET_SYSTEMS, "file": FILES["systems"], "field": "in_pool", "reason": "no System is in the random pool"})

	var pooled_hosts := 0
	for h in host_rows:
		if h["in_pool"]:
			pooled_hosts += 1
	if not host_rows.is_empty() and pooled_hosts == 0:
		issues.error({"dataset": DataIssues.DATASET_HOSTS, "file": FILES["hosts"], "field": "in_pool", "reason": "no HOST is in the random pool"})


## Required rows are required by PRESENCE. Their values are validated by the
## schema and contract rules, with the dataset as final authority on what those
## values are.
func check_required_ids(rows: Array[Dictionary], required: Array, dataset: String, file: String) -> void:
	var present := {}
	for r in rows:
		present[r["id"]] = true
	for id in required:
		if not present.has(id):
			issues.error({
				"dataset": dataset, "file": file, "id": id,
				"reason": "required record is missing",
			})

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
		var display_ok := _check_passive_display(table.get_cell(i, "display"), contract, ctx)

		if not (activation_ok and scope_ok and payload["ok"] and tuple["ok"] and display_ok):
			continue

		# Enum tokens render in player-facing title case (RED becomes Red);
		# scope and numeric tokens render exactly as authored.
		var tokens: Array = tuple["tokens"]
		var shown: Array[String] = []
		for k in contract["params"].size():
			var kind: int = contract["params"][k]
			shown.append(Vocab.title_case(tokens[k]) if kind == PassiveEffects.ParamKind.COLOR else tokens[k])

		var template := table.get_cell(i, "display").strip_edges()

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

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
			"display_text": table.get_cell(i, "display_text").strip_edges(),
			"graphics": table.get_cell(i, "graphics_ref").strip_edges(),
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
			"display_text": table.get_cell(i, "display_text").strip_edges(),
			"graphics": table.get_cell(i, "graphics_ref").strip_edges(),
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
			"bio": table.get_cell(i, "BIO").strip_edges(),
			"graphics": table.get_cell(i, "GRAPHICS").strip_edges(),
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
			"descript": table.get_cell(i, "DESCRIPT").strip_edges(),
			"graphics": table.get_cell(i, "GRAPHICS").strip_edges(),
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
			"bio": table.get_cell(i, "BIO").strip_edges(),
			"graphics": table.get_cell(i, "GRAPHICS").strip_edges(),
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
			"passive_description": table.get_cell(i, "BOSS_PASSIVE_DESCRIPTION").strip_edges(),
			"bio": table.get_cell(i, "BIO").strip_edges(),
			"graphics": table.get_cell(i, "GRAPHICS").strip_edges(),
		})


## Reads all ten datasets. Every reader runs regardless of earlier failures, so
## an author sees every problem in one pass.
func read_all() -> void:
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

		if ok:
			fn_params[id] = out


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

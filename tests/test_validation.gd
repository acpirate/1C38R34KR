extends RefCounted

## Negative tests for the validation guard rails.
##
## The fingerprint match proves the happy path exhaustively, but it cannot prove
## these rules EXIST — they only fire on invalid content, and content is valid.
## A rule silently missing from the port would look identical to a rule that
## passes, right up until a designer edits a spreadsheet and ships something
## broken.
##
## Each test constructs the minimal invalid state directly rather than
## round-tripping a crafted CSV, so a failure names the rule rather than a
## fixture.


func run(t: TestCase) -> void:
	_test_full_load(t)
	_test_zero_cost_assignment(t)
	_test_unresolved_references(t)
	_test_cross_portfolio_overlap(t)
	_test_minimum_content(t)
	_test_carrier_executability(t)
	_test_duplicate_ids(t)


## The whole pipeline on real content, as startup runs it.
func _test_full_load(t: TestCase) -> void:
	t.group("validation / full load of authored content")
	var loader := ContentLoader.new()
	var result := loader.load_all()

	t.check("authored content loads", result["ok"])
	for e in loader.issues.errors().slice(0, 8):
		printerr("        %s" % DataIssues.format(e))
	t.eq("fingerprint", str(result["fingerprint"]), "49c229cd-8ma")
	t.eq("warnings are unchanged", loader.issues.warning_count, 5)
	t.eq("no errors", loader.issues.error_count, 0)


## A charge pool's capacity IS its Function's cost, so a zero-cost assigned
## Function would hold no pool and fire free every turn.
func _test_zero_cost_assignment(t: TestCase) -> void:
	t.group("validation / zero-cost assigned Function")

	var loader := ContentLoader.new()
	loader.function_rows = [_fn_row("FNC_900", 0)]
	loader.program_rows = [_prg_row("PRG_H_900", "FNC_900")]
	loader.check_zero_cost_assignments()
	t.check("a Program fielding a zero-cost Function is rejected", loader.issues.has_errors())

	# The same Function reached only through a PASSIVE payload is legal — that
	# is exactly what the carrier and mechanic payloads are.
	var ok_loader := ContentLoader.new()
	ok_loader.function_rows = [_fn_row("FNC_901", 0)]
	ok_loader.passive_rows = [{
		"file": "psv.csv", "row": 2, "id": "PSV_900", "effect_type": PassiveEffects.CARRIER,
		"activation": "START_OF_TURN", "agent_scope": "OWNER", "color": null, "all_scope": false,
		"magnitude": null, "function_id": "FNC_901", "display": "", "display_template": "",
		"param_tokens": [],
	}]
	ok_loader.check_zero_cost_assignments()
	t.check("a zero-cost PASSIVE payload is permitted", not ok_loader.issues.has_errors())

	# A positive-cost assigned Function is of course fine.
	var pos := ContentLoader.new()
	pos.function_rows = [_fn_row("FNC_902", 3)]
	pos.program_rows = [_prg_row("PRG_H_902", "FNC_902")]
	pos.check_zero_cost_assignments()
	t.check("a positive-cost assigned Function is permitted", not pos.issues.has_errors())


## An unresolved reference must be an error, never a dropped entry — silently
## ignoring one ships content that looks authored and does nothing.
func _test_unresolved_references(t: TestCase) -> void:
	t.group("validation / unresolved references")

	var loader := ContentLoader.new()
	loader.program_rows = [_prg_row("PRG_H_900", "FNC_NOPE")]
	loader.check_references()
	t.check("a Program naming an unknown Function is rejected", loader.issues.has_errors())

	var psv := ContentLoader.new()
	psv.hacker_rows = [_hak_row(["PRG_H_001", "PRG_H_002", "PRG_H_005"], ["PSV_NOPE"])]
	psv.program_rows = [_prg_row("PRG_H_001", "FNC_001"), _prg_row("PRG_H_002", "FNC_002"), _prg_row("PRG_H_005", "FNC_005")]
	psv.function_rows = [_fn_row("FNC_001", 1), _fn_row("FNC_002", 1), _fn_row("FNC_005", 1)]
	psv.check_references()
	t.check("a Hacker naming an unknown PASSIVE is rejected", psv.issues.has_errors())


## Every Deck pairs with every Hacker, so an overlapping pairing cannot produce
## six distinct Programs — there are no duplicate copies of a PRG_ID.
func _test_cross_portfolio_overlap(t: TestCase) -> void:
	t.group("validation / cross-portfolio overlap")

	var loader := ContentLoader.new()
	loader.hacker_rows = [_hak_row(["PRG_H_001", "PRG_H_002", "PRG_H_003"], [])]
	loader.deck_rows = [_dek_row(["PRG_H_003", "PRG_H_004", "PRG_H_005"])]
	loader.check_cross_portfolio()
	t.check("an overlapping Hacker/Deck pairing is rejected", loader.issues.has_errors())

	var ok_loader := ContentLoader.new()
	ok_loader.hacker_rows = [_hak_row(["PRG_H_001", "PRG_H_002", "PRG_H_005"], [])]
	ok_loader.deck_rows = [_dek_row(["PRG_H_003", "PRG_H_004", "PRG_H_006"])]
	ok_loader.check_cross_portfolio()
	t.check("a disjoint pairing produces six distinct Programs", not ok_loader.issues.has_errors())


## An empty catalog is not a playable state, and must never be papered over
## with a synthesized default.
func _test_minimum_content(t: TestCase) -> void:
	t.group("validation / minimum content")

	var empty := ContentLoader.new()
	empty.check_minimum_content()
	t.check("empty catalogs are rejected", empty.issues.error_count >= 4)

	# A pool that excludes everything leaves random routing nothing to choose.
	var no_pool := ContentLoader.new()
	no_pool.system_rows = [_sys_row("SYS_01", false)]
	no_pool.host_rows = [_hst_row("HST_01", false)]
	no_pool.boss_rows = [{"file": "bos.csv", "row": 2, "id": "BOS_01"}]
	no_pool.upgrade_rows = [
		{"file": "upg.csv", "row": 2, "id": "UPG_01"}, {"file": "upg.csv", "row": 3, "id": "UPG_02"},
		{"file": "upg.csv", "row": 4, "id": "UPG_03"}, {"file": "upg.csv", "row": 5, "id": "UPG_04"},
	]
	no_pool.check_minimum_content()
	var pool_errors := 0
	for e in no_pool.issues.errors():
		if str(e.get("field", "")) == "in_pool":
			pool_errors += 1
	t.eq("an empty random pool is rejected for both Systems and HOSTs", pool_errors, 2)


## A START_OF_TURN payload fires inside turn setup, where there is no way to ask
## the player for a target.
func _test_carrier_executability(t: TestCase) -> void:
	t.group("validation / carrier executability")

	var loader := ContentLoader.new()
	loader.passive_rows = [{
		"file": "psv.csv", "row": 2, "id": "PSV_900", "effect_type": PassiveEffects.CARRIER,
		"activation": "START_OF_TURN", "agent_scope": "OWNER", "color": null, "all_scope": false,
		"magnitude": null, "function_id": "FNC_900", "display": "", "display_template": "",
		"param_tokens": [],
	}]
	loader.plans = {
		"FNC_900": [{
			"fn_id": "FNC_900", "effect_id": Effects.DRAIN, "params": {},
			"target": Types.TargetKind.UNIT,
		}],
	}
	loader.check_carrier_executability()
	t.check("a carrier needing a manual target is rejected", loader.issues.has_errors())

	var ok_loader := ContentLoader.new()
	ok_loader.passive_rows = loader.passive_rows
	ok_loader.plans = {
		"FNC_900": [{
			"fn_id": "FNC_900", "effect_id": Effects.TRANSFORM, "params": {},
			"target": Types.TargetKind.NONE,
		}],
	}
	ok_loader.check_carrier_executability()
	t.check("an untargeted carrier is permitted", not ok_loader.issues.has_errors())


## Stable IDs are content identity, so a duplicate is an authoring mistake that
## would otherwise silently shadow one of the two rows.
func _test_duplicate_ids(t: TestCase) -> void:
	t.group("validation / duplicate IDs")
	var loader := ContentLoader.new()
	loader.function_rows = [_fn_row("FNC_900", 1), _fn_row("FNC_900", 2)]
	loader.check_duplicate_ids(loader.function_rows, DataIssues.DATASET_FUNCTIONS, "FNC_ID")
	t.check("a duplicate record ID is rejected", loader.issues.has_errors())


# --- minimal row builders -------------------------------------------------

func _fn_row(id: String, cost: int) -> Dictionary:
	return {
		"file": "fnc.csv", "row": 2, "id": id, "name": "TEST", "cost": cost,
		"payload_raw": "EFFECT_ATTACK", "notes": "", "params": {}, "axes": {},
		"tuple_raw": "", "start_charged": false,
	}


func _prg_row(id: String, fn: String) -> Dictionary:
	return {
		"file": "prg_h.csv", "dataset": DataIssues.DATASET_HACKER_PROGRAMS, "row": 2,
		"id": id, "name": "TEST", "colors": [0], "shapes": [0], "function_id": fn, "notes": "",
	}


func _hak_row(portfolio: Array, passives: Array) -> Dictionary:
	return {
		"file": "hak.csv", "row": 2, "id": "HAK_01", "name": "TEST", "base_link": 100,
		"strong_colors": [0], "strong_shapes": [0], "portfolio": portfolio,
		"passive_ids": passives, "bio": "", "graphics": "",
	}


func _dek_row(portfolio: Array) -> Dictionary:
	return {
		"file": "dek.csv", "row": 2, "id": "DEK_01", "name": "TEST", "add_link": 50,
		"portfolio": portfolio, "function_id": "FNC_010", "descript": "", "graphics": "",
	}


func _sys_row(id: String, in_pool: bool) -> Dictionary:
	return {
		"file": "sys.csv", "row": 2, "id": id, "name": "TEST", "base_ice": 100,
		"strong_colors": [0], "strong_shapes": [0], "programs": [], "passive_ids": [],
		"in_pool": in_pool, "bio": "", "graphics": "",
	}


func _hst_row(id: String, in_pool: bool) -> Dictionary:
	return {
		"file": "hst.csv", "row": 2, "id": id, "name": "TEST", "passive_ids": [],
		"in_pool": in_pool, "display_text": "", "graphics": "",
	}

extends RefCounted

## Content pipeline tests. Grows as each dataset reader lands.
##
## The authored data is expected to load cleanly, so any error here is either a
## port defect or a genuine content problem — and the diagnostics are detailed
## enough to tell which.


func run(t: TestCase) -> void:
	_test_program_readers(t)
	_test_function_reader(t)
	_test_passive_reader(t)
	_test_prefix_crosscheck(t)


func _test_program_readers(t: TestCase) -> void:
	t.group("load / Program datasets")
	var loader := ContentLoader.new()
	loader.read_programs("hacker_programs", DataIssues.DATASET_HACKER_PROGRAMS, "PRG_H_")
	loader.read_programs("system_programs", DataIssues.DATASET_SYSTEM_PROGRAMS, "PRG_S_")

	_report_unexpected(t, loader, "Program datasets")
	t.eq("Program rows read", loader.program_rows.size(), 14)

	var hacker_ids := []
	var system_ids := []
	for r in loader.program_rows:
		if r["dataset"] == DataIssues.DATASET_HACKER_PROGRAMS:
			hacker_ids.append(r["id"])
		else:
			system_ids.append(r["id"])

	t.eq_seq("Hacker Program IDs in file order", hacker_ids, Vocab.REQUIRED_PRG_H_IDS)
	t.eq_seq("System Program IDs in file order", system_ids, Vocab.REQUIRED_PRG_S_IDS)

	loader.check_duplicate_ids(loader.program_rows, DataIssues.DATASET_HACKER_PROGRAMS, "PRG_ID")
	t.check("no duplicate Program IDs", not loader.issues.has_errors())

	# Colour and shape bindings resolve to enum values, not raw tokens.
	var first: Dictionary = loader.program_rows[0]
	t.check("colours resolved to enum values", (first["colors"] as Array).size() > 0)
	for c in (first["colors"] as Array):
		t.check("colour %s is a valid enum value" % c, c >= 0 and c < Constants.COLOR_COUNT)
	for s in (first["shapes"] as Array):
		t.check("shape %s is a valid enum value" % s, s >= 0 and s < Constants.SHAPE_COUNT)


func _test_function_reader(t: TestCase) -> void:
	t.group("load / Function dataset")
	var loader := ContentLoader.new()
	loader.read_functions()

	_report_unexpected(t, loader, "Function dataset")
	t.eq("Function rows read", loader.function_rows.size(), 20)

	var ids := []
	for r in loader.function_rows:
		ids.append(r["id"])
	t.eq_seq("Function IDs in file order", ids, Vocab.REQUIRED_FNC_IDS)

	loader.check_required_ids(loader.function_rows, Vocab.REQUIRED_FNC_IDS, DataIssues.DATASET_FUNCTIONS, "fnc.csv")
	t.check("every required Function is present", not loader.issues.has_errors())

	# Zero cost is legal at the row level — it is only illegal once a Program or
	# Deck fields the Function, which the cross-reference phase checks.
	var zero_cost := []
	for r in loader.function_rows:
		if int(r["cost"]) == 0:
			zero_cost.append(r["id"])
	t.eq_seq(
		"zero-cost Functions are the PASSIVE and mechanic payloads",
		zero_cost,
		["FNC_016", "FNC_017", "FNC_018", "FNC_019", "FNC_020"],
	)

	# The discrete parameter and axis columns are captured raw; contract
	# validation happens later, once the acting Effect is known.
	var first: Dictionary = loader.function_rows[0]
	t.eq("all discrete parameter columns captured", (first["params"] as Dictionary).size(), Effects.PARAM_NAMES.size())
	t.eq("both axis columns captured", (first["axes"] as Dictionary).size(), Effects.AXIS_NAMES.size())


func _test_passive_reader(t: TestCase) -> void:
	t.group("load / PASSIVE dataset")
	var loader := ContentLoader.new()
	loader.read_passives()

	_report_unexpected(t, loader, "PASSIVE dataset")
	t.eq("PASSIVE rows read", loader.passive_rows.size(), 9)

	var ids := []
	for r in loader.passive_rows:
		ids.append(r["id"])
	t.eq_seq("PASSIVE IDs in file order", ids, Vocab.REQUIRED_PSV_IDS)

	var by_id := {}
	for r in loader.passive_rows:
		by_id[r["id"]] = r

	# The only CARRIER rows are the ones with a Function payload, and every
	# continual effect must have none — the contract enforces both directions.
	var carriers := []
	for r in loader.passive_rows:
		if r["effect_type"] == PassiveEffects.CARRIER:
			carriers.append(r["id"])
			t.check("%s carries a Function payload" % r["id"], str(r["function_id"]) != "")
			t.eq("%s activates at turn start" % r["id"], str(r["activation"]), "START_OF_TURN")
		else:
			t.check("%s has no Function payload" % r["id"], str(r["function_id"]) == "")
			t.eq("%s is continual" % r["id"], str(r["activation"]), "CONTINUAL")
	t.check("at least one CARRIER is authored", carriers.size() > 0)

	# Typed params resolve to values, not raw tokens.
	for r in loader.passive_rows:
		var contract := PassiveEffects.contract(str(r["effect_type"]))
		var kinds: Array = contract["params"]
		if kinds.has(PassiveEffects.ParamKind.COLOR):
			t.check("%s resolved a colour" % r["id"], r["color"] != null)
		if kinds.has(PassiveEffects.ParamKind.SCOPE):
			t.check("%s resolved ALL scope" % r["id"], r["all_scope"] == true)
		if kinds.has(PassiveEffects.ParamKind.POSITIVE_INT):
			t.check("%s resolved a magnitude" % r["id"], r["magnitude"] != null)
		if kinds.is_empty():
			t.eq("%s has no param tokens" % r["id"], (r["param_tokens"] as Array).size(), 0)

	# Display is presentation only. Placeholders must be expanded, so no bare
	# %N may survive into the rendered string.
	for r in loader.passive_rows:
		t.check(
			"%s display has no unexpanded placeholder" % r["id"],
			not str(r["display"]).contains("%"),
		)


## The ID prefix independently cross-checks the manifest's dataset role, so a
## file placed in the wrong slot fails loudly rather than resolving into the
## wrong layer. Worth an explicit test: it is a rule that only ever fires when
## something has already gone wrong.
func _test_prefix_crosscheck(t: TestCase) -> void:
	t.group("load / prefix cross-check")
	var loader := ContentLoader.new()
	# Read the System Program file while claiming it is the Hacker Program
	# dataset. Every row should be rejected on its prefix.
	loader.read_programs("system_programs", DataIssues.DATASET_HACKER_PROGRAMS, "PRG_H_")
	t.check("a mis-slotted dataset produces errors", loader.issues.has_errors())
	t.eq("no rows are accepted from it", loader.program_rows.size(), 0)

	var saw_prefix_error := false
	for e in loader.issues.errors():
		if str(e.get("reason", "")).contains("wrong Program ID prefix"):
			saw_prefix_error = true
	t.check("the failure names the prefix as the reason", saw_prefix_error)


func _report_unexpected(t: TestCase, loader: ContentLoader, label: String) -> void:
	var errs := loader.issues.errors()
	t.check("%s load without errors" % label, errs.is_empty())
	for e in errs.slice(0, 5):
		printerr("        %s" % DataIssues.format(e))

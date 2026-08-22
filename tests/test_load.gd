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
	_test_identity_datasets(t)
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


## All ten datasets read together, as startup does it.
func _test_identity_datasets(t: TestCase) -> void:
	t.group("load / all ten datasets")
	var loader := ContentLoader.new()
	loader.read_all()

	var errs := loader.issues.errors()
	t.check("authored content reads without errors", errs.is_empty())
	for e in errs.slice(0, 8):
		printerr("        %s" % DataIssues.format(e))

	t.eq("Programs", loader.program_rows.size(), 14)
	t.eq("Functions", loader.function_rows.size(), 20)
	t.eq("PASSIVEs", loader.passive_rows.size(), 9)
	t.eq("HOSTs", loader.host_rows.size(), 5)
	t.eq("UPGRADEs", loader.upgrade_rows.size(), 4)
	t.eq("Hackers", loader.hacker_rows.size(), 1)
	t.eq("Decks", loader.deck_rows.size(), 1)
	t.eq("Systems", loader.system_rows.size(), 3)
	t.eq("Bosses", loader.boss_rows.size(), 1)

	# Every required record is present under its stable ID.
	loader.check_required_ids(loader.hacker_rows, Vocab.REQUIRED_HAK_IDS, DataIssues.DATASET_HACKERS, "hak.csv")
	loader.check_required_ids(loader.deck_rows, Vocab.REQUIRED_DEK_IDS, DataIssues.DATASET_DECKS, "dek.csv")
	loader.check_required_ids(loader.system_rows, Vocab.REQUIRED_SYS_IDS, DataIssues.DATASET_SYSTEMS, "sys.csv")
	loader.check_required_ids(loader.host_rows, Vocab.REQUIRED_HST_IDS, DataIssues.DATASET_HOSTS, "hst.csv")
	loader.check_required_ids(loader.upgrade_rows, Vocab.REQUIRED_UPG_IDS, DataIssues.DATASET_UPGRADES, "upg.csv")
	loader.check_required_ids(loader.boss_rows, Vocab.REQUIRED_BOS_IDS, DataIssues.DATASET_BOSSES, "bos.csv")
	t.check("every required identity record is present", not loader.issues.has_errors())

	# The pinned beta 0.1 identities resolve by stable ID, not by row position.
	var hacker: Dictionary = loader.hacker_rows[0]
	t.eq("pinned Hacker is HAK_01", str(hacker["id"]), Content.DEFAULT_HACKER_ID)
	t.eq("Hacker portfolio size", (hacker["portfolio"] as Array).size(), Content.PORTFOLIO_SIZE)
	var deck: Dictionary = loader.deck_rows[0]
	t.eq("pinned Deck is DEK_01", str(deck["id"]), Content.DEFAULT_DECK_ID)
	t.eq("Deck portfolio size", (deck["portfolio"] as Array).size(), Content.PORTFOLIO_SIZE)
	t.check("Deck names exactly one Function", str(deck["function_id"]).begins_with("FNC_"))

	# Every System and Boss fields exactly four System Programs, in authored
	# order — that order is charge-routing priority, not decoration.
	for s in loader.system_rows:
		t.eq("%s build size" % s["id"], (s["programs"] as Array).size(), Content.SYSTEM_BUILD_SIZE)
		for p in (s["programs"] as Array):
			t.check("%s fields a System Program" % s["id"], str(p).begins_with("PRG_S_"))
	for b in loader.boss_rows:
		t.eq("%s build size" % b["id"], (b["programs"] as Array).size(), Content.SYSTEM_BUILD_SIZE)

	# THRESHOLD is the fixed Battle 1 battlefield and contributes nothing —
	# zero PASSIVEs must be accepted, not treated as a missing value.
	var threshold_found := false
	for h in loader.host_rows:
		if str(h["id"]) == "HST_01":
			threshold_found = true
			t.eq("THRESHOLD contributes no PASSIVEs", (h["passive_ids"] as Array).size(), 0)
	t.check("HST_01 is present", threshold_found)

	# Warnings do not block startup, and are compared against the alpha's actual
	# diagnostics rather than a count — a count match can be a coincidence,
	# while dataset/id/reason proves the RULES ported and names which is missing.
	loader.check_duplicate_display_names()
	loader.check_unreferenced_functions()
	loader.check_unreferenced_passives()
	_compare_diagnostics(t, loader)
	_test_payload_grammar(t)


func _test_payload_grammar(t: TestCase) -> void:
	t.group("load / payload grammar")
	var loader := ContentLoader.new()
	loader.read_all()
	loader.parse_payloads()

	var errs := loader.issues.errors()
	t.check("every authored payload parses", errs.is_empty())
	for e in errs.slice(0, 5):
		printerr("        %s" % DataIssues.format(e))

	t.eq("every Function has a resolved payload", loader.payloads.size(), loader.function_rows.size())

	var leaves := 0
	var composites := 0
	for id in loader.payloads:
		var p: Dictionary = loader.payloads[id]
		if p["kind"] == "leaf":
			leaves += 1
			t.check("%s names a registered Effect" % id, Effects.is_effect_id(str(p["effect_id"])))
		else:
			composites += 1
			t.check("%s has children" % id, (p["children"] as Array).size() > 0)
			# One-level nesting: every child must be a leaf. This is what makes
			# cycles structurally impossible rather than something to detect.
			for child in (p["children"] as Array):
				t.check(
					"%s child %s is a leaf" % [id, child],
					loader.payloads.has(child) and loader.payloads[child]["kind"] == "leaf",
				)
	t.check("the content includes leaf Functions", leaves > 0)
	print("        %d leaf, %d composite" % [leaves, composites])

	t.group("load / Effect parameter contracts")
	loader.resolve_effect_params()
	var perrs := loader.issues.errors()
	t.check("every authored Function satisfies its Effect contract", perrs.is_empty())
	for e in perrs.slice(0, 5):
		printerr("        %s" % DataIssues.format(e))

	t.eq("every leaf Function resolved parameters", loader.fn_params.size(), leaves)

	# Typed tuples are resolved into named fields, so runtime never re-parses
	# the raw string and a positional mistake cannot survive to combat.
	for id in loader.fn_params:
		var params: Dictionary = loader.fn_params[id]
		var effect_id: String = loader.payloads[id]["effect_id"]
		var contract := Effects.contract(effect_id)

		for req in (contract["required"] as Array):
			t.check("%s supplies required %s" % [id, req], params.has(req))

		if not (contract["tuple"] as Array).is_empty():
			var tuple_keys := {
				Effects.BOMB: "bomb", Effects.LINESLICE: "line",
				Effects.TRANSFORM: "transform", Effects.SHAKE: "shake",
			}
			var key: String = tuple_keys.get(effect_id, "")
			t.check("%s resolved its %s tuple" % [id, effect_id], key != "" and params.has(key))

		if params.has("areaPattern"):
			t.check("%s names a registered area pattern" % id, Areas.is_pattern_id(str(params["areaPattern"])))

	# The alpha's warning set is unchanged by this phase on current content:
	# every authored row uses exactly the columns its Effect claims.
	t.eq("no new warnings from contract validation", loader.issues.warning_count, 0)

	# Transform axes resolve to typed values. Current content is COERCE
	# (NEU -> YEL:STR), GREENING (ALL -> GRE), and SNEAK (ALL -> MAG).
	t.group("load / Transform axis grammar")
	var transforms := []
	for id in loader.fn_params:
		if loader.payloads[id]["effect_id"] == Effects.TRANSFORM:
			transforms.append(id)
	t.eq("three Transform Functions are authored", transforms.size(), 3)

	for id in transforms:
		var params: Dictionary = loader.fn_params[id]
		t.check("%s resolved an axisTarget" % id, params.has("axisTarget"))
		t.check("%s resolved an axisResult" % id, params.has("axisResult"))
		var at: Dictionary = params["axisTarget"]
		var ar: Dictionary = params["axisResult"]
		# A whole-Packet target carries no axis; an AXIS target carries at
		# least one.
		if at["kind"] == Content.AxisTargetKind.AXIS:
			t.check("%s AXIS target names an axis" % id, at["color"] != null or at["shape"] != null)
		else:
			t.check("%s whole-Packet target has no axis" % id, at["color"] == null and at["shape"] == null)
		# ALL is never a result — "turn these into everything" has no meaning.
		t.check("%s result is not ALL" % id, str(ar["token"]) != Content.AXIS_ALL)

	_test_fingerprint_match(t, loader)


## The end-to-end gate: does the whole parse, normalize, and resolve path
## produce the alpha's fingerprint byte-for-byte?
func _test_fingerprint_match(t: TestCase, loader: ContentLoader) -> void:
	t.group("load / fingerprint")
	loader.build_plans()

	var errs := loader.issues.errors()
	t.check("plans build without errors", errs.is_empty())
	for e in errs.slice(0, 5):
		printerr("        %s" % DataIssues.format(e))

	t.eq("every Function has a plan", loader.plans.size(), loader.function_rows.size())

	var f := FileAccess.open("res://tests/fixtures/content.json", FileAccess.READ)
	if f == null:
		t.check("content fixture is readable", false)
		return
	var fixture = JSON.parse_string(f.get_as_text())
	f.close()

	var actual := loader.compute_fingerprint()
	var expected := str(fixture["fingerprint"])
	t.eq("fingerprint matches the alpha", actual, expected)

	if actual != expected:
		# The suffix is the canonical string's length in base36, so comparing it
		# separately says whether the content differs in SIZE or only in bytes —
		# a materially different search either way.
		printerr("        canonical length (base36): got %s, want %s" % [
			actual.split("-")[1], expected.split("-")[1],
		])


func _compare_diagnostics(t: TestCase, loader: ContentLoader) -> void:
	t.group("load / diagnostics match the alpha")
	var f := FileAccess.open("res://tests/fixtures/content.json", FileAccess.READ)
	if f == null:
		t.check("content fixture is readable", false)
		return
	var fixture = JSON.parse_string(f.get_as_text())
	f.close()

	var expected: Array = fixture["issues"]
	var expected_warnings := []
	for e in expected:
		if str(e["severity"]) == "warning":
			expected_warnings.append("%s/%s/%s" % [e["dataset"], e["id"], e["reason"]])

	var actual_warnings := []
	for w in loader.issues.warnings():
		actual_warnings.append("%s/%s/%s" % [w.get("dataset", ""), w.get("id", ""), w.get("reason", "")])

	expected_warnings.sort()
	actual_warnings.sort()
	t.eq_seq("warnings match the alpha exactly", actual_warnings, expected_warnings)
	t.eq("error count matches the alpha", loader.issues.error_count, int(fixture["error_count"]))


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

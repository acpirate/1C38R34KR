extends SceneTree

## Headless test runner.
##
##   godot --headless -s res://tools/run_tests.gd
##
## Exits 0 when every test passes, 1 otherwise, so CI, the build gate, and the
## agent loop can all gate on the exit code. Game logic stays free of
## Node/scene-tree dependencies so it can be exercised from here without a
## rendering context — enforced by test_layer_purity.gd rather than by habit.

const SUITES := [
	# RNG first: D-009 makes it the gate on everything downstream.
	"res://tests/test_rng.gd",
	"res://tests/test_constants.gd",
	# Phase 2 — content pipeline, in dependency order.
	"res://tests/test_areas.gd",
	"res://tests/test_csv.gd",
	"res://tests/test_registries.gd",
	"res://tests/test_fingerprint.gd",
	"res://tests/test_load.gd",
	"res://tests/test_validation.gd",
	# Phase 3 — battle core.
	"res://tests/test_board.gd",
	"res://tests/test_passives.gd",
	"res://tests/test_charge_routing.gd",
	# Phase 5 — presentation.
	"res://tests/test_presentation.gd",
	# Beta 0.2 Phase A — the Run session model. Ahead of persistence because the
	# save envelope is built around these shapes.
	"res://tests/test_run_state.gd",
	# Phase B — route generation, which the state model above is the substrate
	# for. Fixture parity against the alpha lives here.
	"res://tests/test_route.gd",
	# Phase C — battle creation from committed Run state.
	"res://tests/test_run_battle.gd",
	# Phase 6 — persistence, accounting.
	"res://tests/test_save.gd",
	# Phase D — the session envelope wrapped around that battle record.
	"res://tests/test_session_save.gd",
	"res://tests/test_metrics.gd",
	"res://tests/test_layer_purity.gd",
	"res://tests/test_data_present.gd",
]


func _initialize() -> void:
	var t := TestCase.new()
	var missing := 0

	for path in SUITES:
		print(path.get_file().trim_suffix(".gd"))
		var script: Script = load(path)
		# A script with a parse error still loads as an object but cannot be
		# instantiated. Calling new() on it raises a runtime error that aborts
		# _initialize, which would leave quit() unreachable and spin the main
		# loop forever — a hang instead of a failure. Check first.
		if script == null or not script.can_instantiate():
			printerr("  could not instantiate %s — parse error?" % path)
			missing += 1
			continue
		var suite = script.new()
		suite.run(t)

	print("")
	if missing > 0:
		printerr("%d suite(s) failed to load" % missing)
	print("%d passed, %d failed" % [t.passed, t.failed])
	quit(1 if (t.failed > 0 or missing > 0) else 0)


## Belt and braces: if _initialize ever aborts before reaching quit(), end the
## process on the first idle frame rather than hanging a CI job or an agent.
func _process(_delta: float) -> bool:
	printerr("run_tests: reached the main loop without quitting — aborting")
	return true

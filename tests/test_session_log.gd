extends RefCounted

## Beta 0.2 Phase G — Run/session observability.
##
## The bar §19 sets is "sufficient for diagnosis and analysis", explicitly NOT
## alpha menu-log schema parity. So this asserts the properties that make the
## stream usable — every record joinable to its Run, offers recorded before the
## choice, acquisition order preserved, the terminal package complete — rather
## than exact field-for-field shapes that would only make the tests brittle.
##
## Authorization §22 coverage: 18 (logs sufficient for diagnosis).

func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("session log")
		t.check("content loads", false)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()

	_test_one_pipeline(t)
	_test_run_walk(t)
	_test_quick_random(t)

	LogStore.clear()
	Content.clear()
	Passives.clear_cache()


## §19 — one instrumentation pipeline. The session stream is a fourth stream in
## the EXISTING store, not a parallel system with its own file handling, budget,
## or trim policy.
func _test_one_pipeline(t: TestCase) -> void:
	t.group("one pipeline")

	t.check("session is a budgeted LogStore stream", LogStore.BUDGET.has(SessionLog.STREAM))
	t.check("battle streams are untouched", LogStore.BUDGET.has("battles") and LogStore.BUDGET.has("turns"))
	t.eq("and there are exactly four", LogStore.BUDGET.size(), 4)


func _test_run_walk(t: TestCase) -> void:
	t.group("a Run leaves a readable trail")

	LogStore.clear()

	var boss_id: String = Content.all_bosses()[0]["id"]
	var seed_value := 90210
	SessionLog.boss_offered([boss_id])
	var setup := RunSetup.commit_boss(boss_id, Constants.default_settings(), seed_value)
	SessionLog.boss_selected(seed_value, boss_id)
	SessionLog.run_created(seed_value, boss_id)
	setup = setup.commit_hacker(Content.DEFAULT_HACKER_ID)
	SessionLog.hacker_selected(setup.route_seed, Content.DEFAULT_HACKER_ID)
	var r := setup.commit_deck(Content.DEFAULT_DECK_ID)
	SessionLog.deck_selected(r.route_seed, Content.DEFAULT_DECK_ID, r.inventory, r.build)

	# Walk all four routes, treating every battle as won.
	for i in Run.RUN_LENGTH:
		SessionLog.path_offered(r)
		r.select_path(0)
		SessionLog.path_selected(r, 0)
		if r.step == Run.RUN_LENGTH:
			r.enter_pending_boss_battle()
			SessionLog.run_stopped(r)
			break
		SessionLog.battle_started(r, "test-battle-%d" % r.step)
		SessionLog.run_result(r, true, "ADVANCE")
		r.advance_after_victory()

	var records := _read(SessionLog.STREAM)
	t.check("records were written", records.size() > 0)

	# The Run seed is the join key. Without it on every record a log holding two
	# interleaved Runs is unreadable.
	var events := PackedStringArray()
	for rec in records:
		events.append(str(rec["e"]))
		if str(rec["e"]) != SessionLog.BOSS_OFFERED:
			t.eq("record %s carries its Run" % rec["e"], int(rec["run"]), seed_value)
		t.check("record %s carries a fingerprint" % rec["e"], str(rec.get("fp", "")) != "")
		t.check("record %s is timestamped" % rec["e"], str(rec.get("at", "")) != "")

	# The setup sequence is present and in order.
	for required in [
		SessionLog.BOSS_OFFERED, SessionLog.BOSS_SELECTED, SessionLog.RUN_CREATED,
		SessionLog.HACKER_SELECTED, SessionLog.DECK_SELECTED, SessionLog.RUN_STOPPED,
	]:
		t.check("%s was recorded" % required, events.has(required))

	# Offers are recorded BEFORE the choice, so a selection can be read against
	# what it was chosen from rather than in isolation.
	var first_offer := Array(events).find(SessionLog.PATH_OFFERED)
	var first_pick := Array(events).find(SessionLog.PATH_SELECTED)
	t.check("offers precede the selection", first_offer >= 0 and first_offer < first_pick)

	# Every route generation is recorded, including the final Boss route.
	var offered := _of(records, SessionLog.PATH_OFFERED)
	t.eq("one offer record per battle", offered.size(), Run.RUN_LENGTH)
	for rec in offered:
		t.eq("offers are recorded in full", (rec["offers"] as Array).size(), Content.PATH_CHOICE_COUNT)
		# The stream state is what makes an offer reproducible in the harness
		# rather than merely reported.
		t.check("route state is recorded", rec.has("route_state"))

	var last_offer: Dictionary = offered[offered.size() - 1]
	t.eq("the final route is the Boss route", str(last_offer["offers"][0]["opponent_kind"]), "BOS")
	t.check("and the exhaustion flag is recorded", last_offer.has("upgrade_exhausted"))

	# Acquisition order is gameplay state, so it is carried whole rather than
	# reconstructed by replaying records.
	var picks := _of(records, SessionLog.PATH_SELECTED)
	t.eq("one selection per battle", picks.size(), Run.RUN_LENGTH)
	for i in picks.size():
		t.eq("acquisitions accumulate by step %d" % (i + 1), (picks[i]["upgrades"] as Array).size(), i + 1)

	# A battle record joins routing to how the battle actually went.
	var started := _of(records, SessionLog.RUN_BATTLE_STARTED)
	t.check("battles are recorded", started.size() > 0)
	t.check("with the join key into the battle streams", str(started[0]["battle_id"]) != "")
	t.eq("and the encounter ICE", int(started[0]["ice"]), 100)

	# The terminal record is what beta 0.3 reads first: it must carry the whole
	# committed package, not a reference to it.
	var stopped := _of(records, SessionLog.RUN_STOPPED)
	t.eq("the stop is recorded once", stopped.size(), 1)
	var stop: Dictionary = stopped[0]
	t.eq("phase", str(stop["phase"]), "PENDING_BOSS_BATTLE")
	t.eq("Boss", str(stop["boss_id"]), boss_id)
	t.check("HOST", str(stop["host_id"]) != "")
	t.eq("every UPGRADE", (stop["upgrades"] as Array).size(), Content.all_upgrades().size())
	t.eq("Boss ICE", int(stop["ice"]), int(Content.boss(boss_id)["base_ice"]))
	t.check("build", (stop["build"] as Array).size() == Content.ACTIVE_BUILD_SIZE)


func _test_quick_random(t: TestCase) -> void:
	t.group("random quick match")

	LogStore.clear()
	var rng := Rng.new(4242)
	var rolled := Session.random_quick_match_setup(rng)
	SessionLog.quick_random_rolled(4242, rolled["system_id"], rolled["host_id"], rolled["build"])

	var records := _of(_read(SessionLog.STREAM), SessionLog.QUICK_RANDOM_ROLLED)
	t.eq("the roll is recorded", records.size(), 1)
	# Random Quick Match has no Run, so the setup seed carries reproducibility
	# in place of the run seed.
	t.eq("no Run is claimed", int(records[0]["run"]), 0)
	t.eq("the setup seed is recorded", int(records[0]["setup_seed"]), 4242)
	t.eq("System", str(records[0]["system_id"]), str(rolled["system_id"]))
	t.eq("HOST", str(records[0]["host_id"]), str(rolled["host_id"]))
	t.eq("build", records[0]["build"], rolled["build"])


func _read(stream: String) -> Array:
	var path := "user://logs/%s.jsonl" % stream
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var text := f.get_as_text()
	f.close()
	var out: Array = []
	for line in text.split("\n", false):
		var parsed = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			out.append(parsed)
	return out


func _of(records: Array, event: String) -> Array:
	var out: Array = []
	for r in records:
		if str(r["e"]) == event:
			out.append(r)
	return out

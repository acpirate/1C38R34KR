extends RefCounted

## Beta 0.2 Phase D — session persistence.
##
## The proof burden here is deliberately bounded (authorization §16). The beta
## 0.1 battle serializer and its continuation proof are reused unchanged, so
## this does NOT re-prove that a battle resumes deterministically. What it does
## prove is that the Run state wrapped around that battle survives, that
## committed progress cannot be lost, and that route offers cannot be rerolled
## by saving and reloading.
##
## Per D-030 there is deliberately NO cross-version migration test: a schema bump
## rejects old saves and that is the finished behaviour.
##
## Authorization §22 coverage: 2, 3, 4, 5, 19, 20, 33, 34.

func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("session save")
		t.check("content loads", false)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()

	_test_setup_resume(t)
	_test_run_round_trip(t)
	_test_offers_survive_verbatim(t)
	_test_battle_in_run(t)
	_test_rejections(t)
	_test_file_round_trip(t)

	SessionSave.clear()
	Content.clear()
	Passives.clear_cache()


## §22.3 / §22.4 — committed setup progress survives a restart, and resume lands
## on the screen after the last commitment.
func _test_setup_resume(t: TestCase) -> void:
	t.group("setup resume")

	var boss_id: String = Content.all_bosses()[0]["id"]
	var setup := RunSetup.commit_boss(boss_id, Constants.default_settings(), 616)

	var after_boss := SessionSave.from_dict(SessionSave.setup_to_dict(setup))
	t.check("a setup with no Hacker restores", after_boss["ok"])
	t.eq("mode is RUN_SETUP", after_boss["mode"], "RUN_SETUP")
	t.eq("Boss survives", after_boss["setup"].boss_id, boss_id)
	t.eq("resumes to Hacker Selection", after_boss["setup"].step, Types.SetupStep.HACKER)
	t.eq("route stream survives", after_boss["setup"].route_rng_state, setup.route_rng_state)
	t.eq("settings snapshot survives", after_boss["setup"].settings, setup.settings)

	var with_hacker := setup.commit_hacker(Content.DEFAULT_HACKER_ID)
	var after_hacker := SessionSave.from_dict(SessionSave.setup_to_dict(with_hacker))
	t.check("a setup with a Hacker restores", after_hacker["ok"])
	t.eq("Hacker survives", after_hacker["setup"].hacker_id, Content.DEFAULT_HACKER_ID)
	t.eq("resumes to Deck Selection", after_hacker["setup"].step, Types.SetupStep.DECK)

	# Resuming setup and continuing must reach the same Run an uninterrupted
	# session would — the route stream is the part that could silently drift.
	var direct := with_hacker.commit_deck(Content.DEFAULT_DECK_ID)
	var resumed: RunSetup = after_hacker["setup"]
	var via_save := resumed.commit_deck(Content.DEFAULT_DECK_ID)
	t.eq("resumed setup produces the same offers", via_save.pending_path.to_dict(), direct.pending_path.to_dict())
	t.eq("and the same route state", via_save.route_rng_state, direct.route_rng_state)


func _test_run_round_trip(t: TestCase) -> void:
	t.group("Run round trip")

	var r := _run_on_build()
	r.replace_in_build(0, r.inactive_programs()[0])

	var restored := SessionSave.from_dict(SessionSave.run_to_dict(r, null))
	t.check("a Run with no battle restores", restored["ok"])
	var back: Run = restored["run"]

	# §22.2 — everything committed survives.
	t.eq("Boss", back.boss_id, r.boss_id)
	t.eq("step", back.step, r.step)
	t.eq("Hacker", back.hacker_id, r.hacker_id)
	t.eq("Deck", back.deck_id, r.deck_id)
	t.eq("committed opponent", back.opponent_id, r.opponent_id)
	t.eq("committed HOST", back.host_id, r.host_id)
	t.eq("acquired UPGRADEs, in order", back.upgrade_ids, r.upgrade_ids)
	t.eq("edited build", back.build, r.build)
	t.eq("build origin", back.build_origin, r.build_origin)
	t.eq("inventory", back.inventory, r.inventory)
	t.eq("frozen LINK ceiling", back.hacker_max_link, r.hacker_max_link)
	t.eq("frozen settings", back.settings, r.settings)
	t.eq("route stream", back.route_rng_state, r.route_rng_state)
	t.eq("phase", back.phase, r.phase)
	t.check("restored Run is well formed", back.problems().is_empty())

	# `max_cascade_steps` uses null as an explicit infinity sentinel. Coercing it
	# to 0 on the way back would silently cap cascades at zero rather than
	# leaving them unlimited — a quiet gameplay change, not a crash.
	var infinite := _run_on_build()
	infinite.settings["max_cascade_steps"] = Constants.CASCADE_STEPS_INFINITE
	var infinite_back: Run = SessionSave.from_dict(SessionSave.run_to_dict(infinite, null))["run"]
	t.check("the infinity sentinel survives as null", infinite_back.settings["max_cascade_steps"] == null)

	# §22.28 — the beta 0.2 stop point is a saveable state, since beta 0.3 has
	# to pick it up from disk.
	var parked := _run_on_build()
	parked.step = Run.RUN_LENGTH
	parked.opponent_kind = Types.OpponentKind.BOS
	parked.opponent_id = parked.boss_id
	parked.enter_pending_boss_battle()
	var parked_back := SessionSave.from_dict(SessionSave.run_to_dict(parked, null))
	t.check("PENDING_BOSS_BATTLE restores", parked_back["ok"])
	t.check("still parked at the stop point", parked_back["run"].is_pending_boss_battle())
	t.check("opponent is still the Boss", parked_back["run"].opponent_is_boss())


## §22.19 / §22.20 — the offers a player was looking at come back EXACTLY, and
## reloading consumes no route RNG. This is the anti-reroll proof.
func _test_offers_survive_verbatim(t: TestCase) -> void:
	t.group("offers cannot be rerolled")

	var r := _committed_run()
	var before := r.pending_path.to_dict()
	var state_before := r.route_rng_state

	var back: Run = SessionSave.from_dict(SessionSave.run_to_dict(r, null))["run"]
	t.eq("offers restored verbatim", back.pending_path.to_dict(), before)
	t.eq("route stream did not advance", back.route_rng_state, state_before)
	t.eq("offers are still for the same step", back.pending_path.step, r.pending_path.step)

	# Selecting from the RESTORED offers commits the same package the player was
	# shown, not a fresh roll.
	var shown: Dictionary = back.pending_path.offers[1].to_dict()
	back.select_path(1)
	t.eq("committed the offered opponent", back.opponent_id, shown["opponent_id"])
	t.eq("committed the offered HOST", back.host_id, shown["host_id"])
	t.check("acquired the offered UPGRADE", back.upgrade_ids.has(shown["upgrade_id"]))

	# A full save-and-reload at every path choice must reach the same Run as an
	# uninterrupted walk. This is the representative interrupted-Run check §16
	# asks for, rather than an exhaustive per-screen matrix.
	var straight := _committed_run()
	var interrupted := _committed_run()
	for step in [2, 3]:
		straight.select_path(0)
		straight.open_path_choice(step)
		interrupted = SessionSave.from_dict(SessionSave.run_to_dict(interrupted, null))["run"]
		interrupted.select_path(0)
		interrupted = SessionSave.from_dict(SessionSave.run_to_dict(interrupted, null))["run"]
		interrupted.open_path_choice(step)
	t.eq("an interrupted Run reaches the same offers", interrupted.pending_path.to_dict(), straight.pending_path.to_dict())
	t.eq("and the same route state", interrupted.route_rng_state, straight.route_rng_state)
	t.eq("and the same acquisitions", interrupted.upgrade_ids, straight.upgrade_ids)


func _test_battle_in_run(t: TestCase) -> void:
	t.group("a battle inside a Run")

	var r := _run_on_build()
	r.phase = Types.SessionPhase.ACTIVE_BATTLE
	var state := Session.create_run_battle(r, 99)

	var restored := SessionSave.from_dict(SessionSave.run_to_dict(r, state))
	t.check("a Run with a battle restores", restored["ok"])
	t.check("the battle came back", restored["state"] != null)
	t.eq("battle identity is intact", restored["state"].identity["opponent_id"], r.opponent_id)
	t.eq("the Run came back too", restored["run"].step, r.step)

	# The battle and the Run around it must describe the SAME encounter. A
	# mismatch means two sessions were spliced, which is not recoverable.
	var spliced := SessionSave.run_to_dict(r, state)
	spliced["run"]["host_id"] = "HST_05" if r.host_id != "HST_05" else "HST_04"
	t.check("a battle and Run that disagree are rejected", not SessionSave.from_dict(spliced)["ok"])

	var upgrade_mismatch := SessionSave.run_to_dict(r, state)
	upgrade_mismatch["run"]["upgrade_ids"] = []
	t.check("mismatched UPGRADEs are rejected", not SessionSave.from_dict(upgrade_mismatch)["ok"])

	# A phase that contradicts the envelope's contents is incoherent.
	var no_battle := SessionSave.run_to_dict(r, null)
	no_battle["run"]["phase"] = "ACTIVE_BATTLE"
	t.check("ACTIVE_BATTLE with no battle is rejected", not SessionSave.from_dict(no_battle)["ok"])

	var stray_battle := SessionSave.run_to_dict(r, state)
	stray_battle["run"]["phase"] = "PENDING_BUILD"
	t.check("a battle held in a battle-less phase is rejected", not SessionSave.from_dict(stray_battle)["ok"])


## Invalid data is REJECTED, never quietly repaired. A save that cannot be
## trusted is discarded honestly rather than patched into something playable
## that is not what the player left.
func _test_rejections(t: TestCase) -> void:
	t.group("rejections")

	var r := _run_on_build()

	# D-030: a beta 0.1 save has no envelope and simply does not load. There is
	# deliberately no migration path.
	var bare_battle := SaveState.to_dict(Session.create_run_battle(r, 1))
	t.check("a beta 0.1 bare battle record is rejected", not SessionSave.from_dict(bare_battle)["ok"])

	var wrong_schema := SessionSave.run_to_dict(r, null)
	wrong_schema["schema"] = SessionSave.SCHEMA + 1
	t.check("a foreign envelope schema is rejected", not SessionSave.from_dict(wrong_schema)["ok"])

	var wrong_fp := SessionSave.run_to_dict(r, null)
	wrong_fp["fingerprint"] = "not-this-content"
	var fp_result := SessionSave.from_dict(wrong_fp)
	t.check("a content change invalidates the save", not fp_result["ok"])
	t.check("and says why", str(fp_result["reason"]).contains("fingerprint"))

	var bad_mode := SessionSave.run_to_dict(r, null)
	bad_mode["mode"] = "SOMETHING_ELSE"
	t.check("an unknown mode is rejected", not SessionSave.from_dict(bad_mode)["ok"])

	# §22.33 — unresolvable references are rejected rather than defaulted.
	for field in ["boss_id", "hacker_id", "deck_id", "host_id", "opponent_id"]:
		var broken := SessionSave.run_to_dict(r, null)
		broken["run"][field] = "NOPE_01"
		t.check("an unknown %s is rejected" % field, not SessionSave.from_dict(broken)["ok"])

	var bad_upgrade := SessionSave.run_to_dict(r, null)
	bad_upgrade["run"]["upgrade_ids"] = ["UPG_99"]
	t.check("an unknown UPGRADE is rejected", not SessionSave.from_dict(bad_upgrade)["ok"])

	# §22.34 — a duplicate acquisition cannot be produced by the transitions,
	# but a hand-edited save can carry one.
	var dupe := SessionSave.run_to_dict(r, null)
	dupe["run"]["upgrade_ids"] = [r.upgrade_ids[0], r.upgrade_ids[0]]
	t.check("duplicate acquired UPGRADEs are rejected", not SessionSave.from_dict(dupe)["ok"])

	var bad_build := SessionSave.run_to_dict(r, null)
	bad_build["run"]["build"] = (bad_build["run"]["build"] as Array).slice(0, 3)
	t.check("an illegal build is rejected", not SessionSave.from_dict(bad_build)["ok"])

	var bad_step := SessionSave.run_to_dict(r, null)
	bad_step["run"]["step"] = 9
	t.check("an out-of-range step is rejected", not SessionSave.from_dict(bad_step)["ok"])

	var bad_phase := SessionSave.run_to_dict(r, null)
	bad_phase["run"]["phase"] = "SOMEWHERE"
	t.check("an unknown phase is rejected", not SessionSave.from_dict(bad_phase)["ok"])

	# A committed Run can never wear a setup phase — those belong to RunSetup.
	var setup_phase := SessionSave.run_to_dict(r, null)
	setup_phase["run"]["phase"] = "SETUP_DECK"
	t.check("a committed Run carrying a setup phase is rejected", not SessionSave.from_dict(setup_phase)["ok"])

	# Setup claiming to be past the Hacker screen with no Hacker committed.
	var setup := RunSetup.commit_boss(Content.all_bosses()[0]["id"], Constants.default_settings(), 1)
	var impossible := SessionSave.setup_to_dict(setup)
	impossible["setup"]["step"] = "DECK"
	t.check("setup on DECK with no committed Hacker is rejected", not SessionSave.from_dict(impossible)["ok"])


func _test_file_round_trip(t: TestCase) -> void:
	t.group("file round trip")

	SessionSave.clear()
	t.check("no save to start", not SessionSave.exists())
	t.check("reading nothing fails cleanly", not SessionSave.read()["ok"])

	var r := _run_on_build()
	t.check("wrote the session", SessionSave.write(SessionSave.run_to_dict(r, null)))
	t.check("a save now exists", SessionSave.exists())

	var read_back := SessionSave.read()
	t.check("read it back", read_back["ok"])
	t.eq("through the file, the Run is intact", read_back["run"].opponent_id, r.opponent_id)
	t.eq("and its acquisitions", read_back["run"].upgrade_ids, r.upgrade_ids)

	# Quick Match still round-trips through the same file, via the entry points
	# the existing battle screen and title use.
	var qm := Session.create_quick_match("SYS_01", "HST_02", 4, Session.default_build())
	t.check("Quick Match writes through the envelope", SaveState.write(qm))
	var qm_back := SaveState.read()
	t.check("Quick Match reads back", qm_back["ok"])
	t.eq("as the same battle", qm_back["state"].battle_id, qm.battle_id)

	# A Run save must not be handed to the Quick Match entry point as though it
	# were a battle — that would strip the Run around it.
	SessionSave.write(SessionSave.run_to_dict(r, null))
	t.check("the Quick Match reader refuses a Run save", not SaveState.read()["ok"])

	SessionSave.clear()
	t.check("cleared", not SessionSave.exists())


func _run_on_build() -> Run:
	var r := _committed_run()
	r.select_path(0)
	return r


func _committed_run() -> Run:
	var setup := RunSetup.commit_boss(Content.all_bosses()[0]["id"], Constants.default_settings(), 1234)
	setup = setup.commit_hacker(Content.DEFAULT_HACKER_ID)
	return setup.commit_deck(Content.DEFAULT_DECK_ID)

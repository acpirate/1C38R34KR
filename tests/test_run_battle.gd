extends RefCounted

## Beta 0.2 Phase C — integration with the battle engine.
##
## Battle creation from committed Run state, the normal ICE ladder, UPGRADE
## PASSIVE assembly through the EXISTING beta 0.1 runtime, Run Build editing,
## and retry/progression.
##
## Authorization §22 coverage: 9, 10, 11, 16, 17, 18, 22, 29.

func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("run battle")
		t.check("content loads", false)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()

	_test_ice_ladder(t)
	_test_battle_from_run(t)
	_test_upgrade_passives(t)
	_test_passive_cache_key(t)
	_test_build_editing(t)
	_test_retry_and_progression(t)
	_test_boss_battle_refused(t)

	Content.clear()
	Passives.clear_cache()


func _test_ice_ladder(t: TestCase) -> void:
	t.group("Run ICE ladder")

	var settings := Constants.default_settings()
	var sys_id := "SYS_01"
	var base := int(Content.system(sys_id)["base_ice"])

	# §22.11 / §22.17 / §22.18 — BASE + 0 / 50 / 100 for Battles 1-3.
	t.eq("battle 1 is BASE + 0", Run.resolve_run_ice(settings, Types.OpponentKind.SYS, sys_id, 1), base)
	t.eq("battle 2 is BASE + 50", Run.resolve_run_ice(settings, Types.OpponentKind.SYS, sys_id, 2), base + 50)
	t.eq("battle 3 is BASE + 100", Run.resolve_run_ice(settings, Types.OpponentKind.SYS, sys_id, 3), base + 100)

	# A Boss takes its AUTHORED ICE with no modifier. ODANSHAY's 250 is already
	# the final value; applying step 4's +150 would make it 400.
	var boss_id: String = Content.all_bosses()[0]["id"]
	var boss_base := int(Content.boss(boss_id)["base_ice"])
	t.eq(
		"a Boss takes its authored ICE unmodified",
		Run.resolve_run_ice(settings, Types.OpponentKind.BOS, boss_id, 4),
		boss_base
	)
	# The double-count failure: applying step 4's +150 on top of the Boss's own
	# base would give 400. That is the mistake the Boss branch exists to prevent.
	t.check(
		"the step-4 modifier is not applied on top of the Boss base",
		Run.resolve_run_ice(settings, Types.OpponentKind.BOS, boss_id, 4) != boss_base + 150
	)
	# Worth knowing when reading these numbers: ODANSHAY's authored 250 is
	# EXACTLY what a 100-base System would reach through the step-4 modifier, so
	# the correct and the double-counting-free-but-wrong paths agree here by
	# coincidence of authoring. Only the 400 case distinguishes them, which is
	# why the check above is phrased against the Boss's own base rather than
	# against the System ladder.
	t.eq("the authored Boss ICE coincides with the step-4 ladder value", boss_base, base + 150)

	# Normal LINK OFF replaces both, for every encounter, and is never combined
	# with the base or the step modifier.
	var manual := Constants.default_settings()
	manual["normal_link"] = false
	manual["manual_system_ice"] = 321
	for step in [1, 2, 3]:
		t.eq(
			"manual ICE overrides step %d entirely" % step,
			Run.resolve_run_ice(manual, Types.OpponentKind.SYS, sys_id, step),
			321
		)
	t.eq(
		"manual ICE covers a Boss too",
		Run.resolve_run_ice(manual, Types.OpponentKind.BOS, boss_id, 4),
		321
	)


func _test_battle_from_run(t: TestCase) -> void:
	t.group("battle from committed Run state")

	var r := _run_on_build()
	var s := Session.create_run_battle(r, 555)
	t.check("battle created", s != null)

	# Everything was decided earlier and is read, not rederived.
	t.eq("opponent carried from the committed path", s.identity["opponent_id"], r.opponent_id)
	t.eq("HOST carried from the committed path", s.identity["host_id"], r.host_id)
	t.eq("build carried from the Run", s.identity["hacker_programs"], r.build)
	t.eq("Hacker carried from setup", s.identity["hacker_id"], r.hacker_id)
	t.eq("Deck carried from setup", s.identity["deck_id"], r.deck_id)
	t.eq("acquired UPGRADEs reach the battle", s.identity["upgrade_ids"], r.upgrade_ids)
	t.eq("opponent is a System", s.identity["opponent_kind"], Types.OpponentKind.SYS)

	# §22.11 — the ICE the Run resolved, not the System's bare BASE_ICE.
	t.eq("enemy ICE is the encounter value", s.hp[Types.Side.ENEMY], r.encounter_ice())
	# The LINK ceiling frozen at setup, not recomputed from current settings.
	t.eq("player LINK is the Run's frozen maximum", s.hp[Types.Side.PLAYER], r.hacker_max_link)

	# The Run's frozen settings drive the battle, so a later menu edit cannot
	# reach a battle already under way.
	r.settings["manual_system_ice"] = 9999
	var s2 := Session.create_run_battle(r, 555)
	t.eq("normal LINK still governs", s2.hp[Types.Side.ENEMY], r.encounter_ice())

	# A fresh battle each time: no charge, no board carried over.
	t.eq("battle starts on turn 1", s.turn, 1)
	t.eq("battle starts undecided", s.winner, -1)
	for u in s.units[Types.Side.PLAYER]:
		var prog := Content.program(u.program_id)
		if not prog["fn"]["start_charged"]:
			t.eq("Program %s starts empty" % u.program_id, u.charge, 0)


func _test_upgrade_passives(t: TestCase) -> void:
	t.group("UPGRADE PASSIVEs")

	var upgrade_ids: Array = []
	for u in Content.all_upgrades():
		upgrade_ids.append(u["id"])

	var r := _run_on_build()
	r.upgrade_ids = [upgrade_ids[0]]
	Passives.clear_cache()
	var one := Session.create_run_battle(r, 1)
	var one_active := Passives.active(one.identity)

	var r2 := _run_on_build()
	r2.upgrade_ids = upgrade_ids.duplicate()
	Passives.clear_cache()
	var all := Session.create_run_battle(r2, 1)
	var all_active := Passives.active(all.identity)

	# §22.16 — UPGRADEs contribute through the EXISTING passive runtime; more
	# acquired means more active instances.
	t.check("more UPGRADEs contribute more PASSIVEs", all_active.size() >= one_active.size())

	# Source attribution: UPGRADE PASSIVEs are Hacker-owned whatever their
	# authored agent scope says about which side the effect lands on.
	var upg_seen := 0
	for inst in all_active:
		if inst.source_kind == Types.PassiveSourceKind.UPG:
			upg_seen += 1
			t.check("UPGRADE PASSIVE %s is player-owned" % inst.source_id, inst.owner == Types.Side.PLAYER)
			t.check("UPGRADE PASSIVE names its UPGRADE" % [], upgrade_ids.has(inst.source_id))
	t.check("UPGRADE PASSIVEs are present at all", upg_seen > 0)

	# Acquisition order is preserved into the instance list, because it is
	# START_OF_TURN resolution order rather than a display convenience.
	var order: Array = []
	for inst in all_active:
		if inst.source_kind == Types.PassiveSourceKind.UPG and not order.has(inst.source_id):
			order.append(inst.source_id)
	t.eq("UPGRADE PASSIVEs follow acquisition order", order, upgrade_ids)

	# A Run with no UPGRADEs must behave exactly like Quick Match did.
	var bare := _run_on_build()
	bare.upgrade_ids = []
	Passives.clear_cache()
	var bare_active := Passives.active(Session.create_run_battle(bare, 1).identity)
	for inst in bare_active:
		t.check("no UPGRADE PASSIVEs without UPGRADEs", inst.source_kind != Types.PassiveSourceKind.UPG)


## The cache-key regression. `Passives.active()` memoizes on the identity's
## cache key; if that key omits the acquired UPGRADEs, two Run battles sharing a
## Hacker, opponent, and HOST collide and the second silently fights with the
## first's PASSIVE set.
##
## Beta 0.1 could omit them safely because Quick Match has none.
func _test_passive_cache_key(t: TestCase) -> void:
	t.group("PASSIVE cache key")

	var upgrade_ids: Array = []
	for u in Content.all_upgrades():
		upgrade_ids.append(u["id"])

	Passives.clear_cache()

	var early := _run_on_build()
	early.upgrade_ids = [upgrade_ids[0]]
	var early_state := Session.create_run_battle(early, 7)

	var late := _run_on_build()
	late.upgrade_ids = upgrade_ids.duplicate()
	var late_state := Session.create_run_battle(late, 7)

	# Same Hacker, same opponent, same HOST — only the UPGRADEs differ.
	t.eq("same opponent", early_state.identity["opponent_id"], late_state.identity["opponent_id"])
	t.eq("same HOST", early_state.identity["host_id"], late_state.identity["host_id"])
	t.check(
		"cache keys differ when the acquired UPGRADEs differ",
		early_state.identity["cache_key"] != late_state.identity["cache_key"]
	)

	# And the memoized lists really are different, which is the failure the key
	# exists to prevent.
	var early_count := Passives.active(early_state.identity).size()
	var late_count := Passives.active(late_state.identity).size()
	t.check("the second battle does not inherit the first's PASSIVEs", late_count != early_count)


func _test_build_editing(t: TestCase) -> void:
	t.group("Run Build")

	var r := _run_on_build()
	var original: Array = r.build.duplicate()

	# §22.10 — four distinct inventory Programs, always. There is no invalid
	# intermediate state to pass through.
	t.check("starting build is legal", Content.is_valid_build(r.build, r.inventory))
	t.eq("inactive Programs make up the rest of the inventory",
		r.inactive_programs().size(), r.inventory.size() - r.build.size())

	var spare: String = r.inactive_programs()[0]
	t.check("swapping in an inactive Program succeeds", r.replace_in_build(0, spare))
	t.eq("slot took the new Program", r.build[0], spare)
	t.check("build is still legal", Content.is_valid_build(r.build, r.inventory))
	t.eq("editing marks the build as player-edited", r.build_origin, Types.BuildOrigin.PLAYER_EDITED)

	# A swap that would duplicate is refused rather than allowed and validated.
	t.check("cannot duplicate a Program already in the build", not r.replace_in_build(1, r.build[2]))
	t.check("cannot swap in something outside the inventory", not r.replace_in_build(1, "PRG_H_999"))
	t.check("cannot address a slot that does not exist", not r.replace_in_build(9, spare))

	# Order is charge-routing priority, so reordering is a gameplay edit.
	var before: Array = r.build.duplicate()
	t.check("moving a slot down succeeds", r.move_build_slot(0, 1))
	t.eq("the two slots swapped", r.build[0], before[1])
	t.eq("and the other way", r.build[1], before[0])
	t.check("cannot move off the top", not r.move_build_slot(0, -1))
	t.check("cannot move off the bottom", not r.move_build_slot(r.build.size() - 1, 1))
	t.check("build is still legal after reordering", Content.is_valid_build(r.build, r.inventory))
	t.check("the Run is still well formed", r.problems().is_empty())
	t.check("the build actually changed", r.build != original)


func _test_retry_and_progression(t: TestCase) -> void:
	t.group("retry and progression")

	var r := _run_on_build()
	var opponent := r.opponent_id
	var host := r.host_id
	var upgrades: Array = r.upgrade_ids.duplicate()
	var spare: String = r.inactive_programs()[0]
	r.replace_in_build(0, spare)
	var edited: Array = r.build.duplicate()

	# §22.22 — a retry is the SAME encounter with the SAME build. Nothing is
	# rerolled and no reward is granted twice.
	r.retry_battle()
	t.eq("retry keeps the build", r.build, edited)
	t.eq("retry keeps the opponent", r.opponent_id, opponent)
	t.eq("retry keeps the HOST", r.host_id, host)
	t.eq("retry grants no further UPGRADE", r.upgrade_ids, upgrades)
	t.eq("retry returns to Build", r.phase, Types.SessionPhase.PENDING_BUILD)
	t.check("no offers are pending on a retry", r.pending_path == null)

	# The retried battle is built from the same committed state.
	var again := Session.create_run_battle(r, 3)
	t.eq("retried battle faces the same opponent", again.identity["opponent_id"], opponent)
	t.eq("retried battle uses the edited build", again.identity["hacker_programs"], edited)

	# §22.16 — winning carries the build forward into the next encounter.
	t.check("advancing after a victory opens the next path", r.advance_after_victory())
	t.eq("Run moved to step 2", r.step, 2)
	t.eq("build carried forward", r.build, edited)
	t.check("offers are pending for the new step", r.pending_path != null)

	# `build_origin` records the origin of the COMMITTED build and moves only on
	# confirmation. CARRIED_RUN belongs to the Build SCREEN's own state, which
	# `opening_build_origin` supplies — stamping it onto the Run when a path
	# opens was a port defect the Phase E harness caught (P-028).
	t.eq("advancing does not restamp the committed origin", r.build_origin, Types.BuildOrigin.PLAYER_EDITED)
	t.eq("battle 1 opens Build on the default", _run_on_build().opening_build_origin(), Types.BuildOrigin.DEFAULT)
	t.eq("later battles carry forward", r.opening_build_origin(), Types.BuildOrigin.CARRIED_RUN)
	t.check("confirming stamps the screen's origin", r.confirm_build(Types.BuildOrigin.CARRIED_RUN))
	t.eq("and the Run now records it", r.build_origin, Types.BuildOrigin.CARRIED_RUN)

	# At the last step there is no next path — the caller stops instead.
	var last := _run_on_build()
	last.step = Run.RUN_LENGTH
	t.check("no progression past the last step", not last.advance_after_victory())
	t.eq("and the Run stays on the last step", last.step, Run.RUN_LENGTH)


## §22.29 / §12 — beta 0.2 must never fabricate the Boss encounter.
func _test_boss_battle_refused(t: TestCase) -> void:
	t.group("Boss battle refused")

	var r := _run_on_build()
	r.step = Run.RUN_LENGTH
	r.opponent_kind = Types.OpponentKind.BOS
	r.opponent_id = r.boss_id

	t.check("creating a Boss battle is refused", Session.create_run_battle(r, 1) == null)

	# And it refuses rather than quietly substituting a System, which is the
	# failure mode that would look like a working Battle 4.
	r.enter_pending_boss_battle()
	t.check("the Run parks at the stop point instead", r.is_pending_boss_battle())
	t.check("opponent is still the Boss", r.opponent_is_boss())

	# A Run still sitting on a Path Choice has no committed encounter to build.
	var unchosen := _committed_run()
	t.check("no battle without a committed path", Session.create_run_battle(unchosen, 1) == null)


## A Run that has committed its Battle 1 path and is sitting on Build.
func _run_on_build() -> Run:
	var r := _committed_run()
	r.select_path(0)
	return r


func _committed_run() -> Run:
	var setup := RunSetup.commit_boss(Content.all_bosses()[0]["id"], Constants.default_settings(), 808)
	setup = setup.commit_hacker(Content.DEFAULT_HACKER_ID)
	return setup.commit_deck(Content.DEFAULT_DECK_ID)

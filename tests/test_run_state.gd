extends RefCounted

## Beta 0.2 Phase A — the Run session model.
##
## Covers the state shapes, the setup transitions, route-RNG isolation and
## persistence, UPGRADE acquisition, and the PENDING_BOSS_BATTLE stop. Route
## OFFER GENERATION is Phase B and is not exercised here.
##
## Authorization §22 coverage in this file: 1 (partial — Boss commit creates the
## Run), 2, 3, 4, 20, 21, 34.

func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("run state")
		t.check("content loads", false)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()

	_test_encounter_table(t)
	_test_pools(t)
	_test_setup_transitions(t)
	_test_route_rng(t)
	_test_upgrade_acquisition(t)
	_test_pending_boss_battle(t)
	_test_offer_round_trip(t)
	_test_invariants(t)

	Content.clear()
	Passives.clear_cache()


func _test_encounter_table(t: TestCase) -> void:
	t.group("encounter table")

	t.eq("run length", Run.RUN_LENGTH, 4)
	t.eq("battle 1 ICE modifier", Run.encounter_for(1)["ice_modifier"], 0)
	t.eq("battle 2 ICE modifier", Run.encounter_for(2)["ice_modifier"], 50)
	t.eq("battle 3 ICE modifier", Run.encounter_for(3)["ice_modifier"], 100)

	# Carried deliberately and never applied: a Boss takes its authored BASE_ICE
	# with no modifier, and a Boss is the only step-4 opponent. Asserted so that
	# deleting the row is a deliberate act rather than a tidy-up.
	t.eq("battle 4 modifier exists but is dead data", Run.encounter_for(4)["ice_modifier"], 150)

	t.eq("next step from 1", Run.next_step(1), 2)
	t.eq("next step from 3", Run.next_step(3), 4)
	t.eq("no step after the last", Run.next_step(4), 0)


func _test_pools(t: TestCase) -> void:
	t.group("random pools")

	var all_sys := Content.all_systems()
	var pool_sys := Content.pool_systems()
	var all_hst := Content.all_hosts()
	var pool_hst := Content.pool_hosts()

	t.check("every System is listed for deliberate selection", all_sys.size() == 3)
	t.check("the intro System is held out of the random pool", pool_sys.size() == 2)
	t.check("every HOST is listed", all_hst.size() == 5)
	t.check("THRESHOLD is held out of the random pool", pool_hst.size() == 4)

	# `in_pool` governs what may be ROLLED, not what may be chosen. If these two
	# ever coincide the distinction has been lost.
	t.check("pools are a strict subset of the listings", pool_sys.size() < all_sys.size())

	for s in pool_sys:
		t.check("pooled System %s is not the intro System" % s["id"], s["id"] != Content.INITIAL_SYSTEM_ID)
	for h in pool_hst:
		t.check("pooled HOST %s is not THRESHOLD" % h["id"], h["id"] != Content.INITIAL_HOST_ID)

	t.check("at least four UPGRADEs for four decisions", Content.all_upgrades().size() >= Content.MIN_UPGRADE_ROWS)
	t.check("at least one Boss", Content.all_bosses().size() >= 1)


func _test_setup_transitions(t: TestCase) -> void:
	t.group("setup transitions")

	var boss_id: String = Content.all_bosses()[0]["id"]
	var setup := RunSetup.commit_boss(boss_id, Constants.default_settings(), 12345)

	# §22.2 — Boss commit creates the Run state.
	t.check("Boss commit produces a Run in setup", setup != null)
	t.eq("Boss persisted immediately", setup.boss_id, boss_id)
	# §22.3 — and parks on Hacker Selection, which is what resume returns to.
	t.eq("setup parks on Hacker Selection", setup.step, Types.SetupStep.HACKER)
	t.eq("resume phase is SETUP_HACKER", setup.phase(), Types.SessionPhase.SETUP_HACKER)
	t.eq("no Hacker committed yet", setup.hacker_id, "")

	# §22.4 — committing the Hacker advances to Deck Selection.
	var after_hacker := setup.commit_hacker(Content.DEFAULT_HACKER_ID)
	t.check("Hacker commit succeeds", after_hacker != null)
	t.eq("Hacker persisted", after_hacker.hacker_id, Content.DEFAULT_HACKER_ID)
	t.eq("setup advances to Deck Selection", after_hacker.step, Types.SetupStep.DECK)
	t.eq("resume phase is SETUP_DECK", after_hacker.phase(), Types.SessionPhase.SETUP_DECK)

	# The Boss is fixed from commitment: nothing downstream may change it.
	t.eq("Boss untouched by Hacker commit", after_hacker.boss_id, boss_id)
	t.eq("route stream untouched by Hacker commit", after_hacker.route_rng_state, setup.route_rng_state)

	# Transitions return new state rather than mutating in place, so a caller
	# holding the earlier state cannot observe it change under them.
	t.eq("earlier setup state is unchanged", setup.step, Types.SetupStep.HACKER)

	# The settings snapshot is taken at BOSS commitment and is authoritative for
	# the whole Run — editing the menu afterwards must not reach into it.
	var menu := Constants.default_settings()
	var snapshot_setup := RunSetup.commit_boss(boss_id, menu, 1)
	menu["normal_link"] = not menu["normal_link"]
	t.check(
		"later menu edits do not mutate the Run snapshot",
		snapshot_setup.settings["normal_link"] != menu["normal_link"]
	)

	# An unknown ID is rejected rather than defaulted. A Run committed to a Boss
	# that does not exist is not a playable state.
	t.check("unknown Boss rejected", RunSetup.commit_boss("BOS_NOPE", Constants.default_settings(), 1) == null)
	t.check("unknown Hacker rejected", setup.commit_hacker("HAK_NOPE") == null)


func _test_route_rng(t: TestCase) -> void:
	t.group("route RNG")

	var r := _run_at_step(1)
	r.route_rng_state = Rng.new(99).get_state()

	# §22.20 — the stream survives a reload. Resuming from the persisted state
	# continues the sequence rather than restarting it.
	var stream := r.route_rng()
	var first: Array = []
	for i in 5:
		first.append(stream.next_u32())
	r.store_route_rng(stream)

	var resumed := r.route_rng()
	var after: Array = []
	for i in 5:
		after.append(resumed.next_u32())

	var uninterrupted := Rng.new(99)
	var expected: Array = []
	for i in 10:
		expected.append(uninterrupted.next_u32())

	t.eq_seq("draws before the save match an uninterrupted run", first, expected.slice(0, 5))
	t.eq_seq("draws after resume continue the same stream", after, expected.slice(5, 10))

	# §22.21 — route generation must not perturb gameplay RNG. The two are
	# separate instances, so advancing one cannot touch the other.
	var gameplay := Rng.new(7)
	var gameplay_expected: Array = []
	var control := Rng.new(7)
	for i in 5:
		gameplay_expected.append(control.next_u32())

	var route := r.route_rng()
	for i in 20:
		route.next_u32()
	r.store_route_rng(route)

	var gameplay_actual: Array = []
	for i in 5:
		gameplay_actual.append(gameplay.next_u32())
	t.eq_seq("gameplay stream is untouched by route draws", gameplay_actual, gameplay_expected)


func _test_upgrade_acquisition(t: TestCase) -> void:
	t.group("UPGRADE acquisition")

	var upgrades := Content.all_upgrades()
	var a: String = upgrades[0]["id"]
	var b: String = upgrades[1]["id"]

	var acquired := Run.acquire_upgrade([], a)
	t.eq("first acquisition", acquired, [a])

	acquired = Run.acquire_upgrade(acquired, b)
	t.eq("acquisition order is preserved", acquired, [a, b])

	# Idempotent by ID. The one-remaining duplicate-offer case acquires exactly
	# once however it is chosen. §22.26.
	var twice := Run.acquire_upgrade(acquired, a)
	t.eq("re-acquiring an owned UPGRADE is a no-op", twice, [a, b])

	# Acquisition returns new state rather than mutating the caller's array.
	t.eq("source array is not mutated", acquired, [a, b])

	# The eligible pool is everything not yet acquired, in authored order.
	var r := _run_at_step(2)
	r.upgrade_ids = [a]
	var eligible := r.eligible_upgrades()
	t.eq("acquired UPGRADE is excluded from the pool", eligible.size(), upgrades.size() - 1)
	for u in eligible:
		t.check("eligible UPGRADE %s is not the acquired one" % u["id"], u["id"] != a)
	if eligible.size() > 0:
		t.eq("eligible pool keeps authored order", eligible[0]["id"], b)


func _test_pending_boss_battle(t: TestCase) -> void:
	t.group("PENDING_BOSS_BATTLE")

	var r := _run_at_step(Run.RUN_LENGTH)
	r.opponent_kind = Types.OpponentKind.BOS
	r.opponent_id = r.boss_id
	r.phase = Types.SessionPhase.PENDING_BUILD

	t.check("not pending the Boss battle before Build is confirmed", not r.is_pending_boss_battle())

	# §22.28 — confirming the final Build enters the stop state.
	r.enter_pending_boss_battle()
	t.check("entered PENDING_BOSS_BATTLE", r.is_pending_boss_battle())
	t.eq("phase spelling", Types.SESSION_PHASE_NAMES[r.phase], "PENDING_BOSS_BATTLE")

	# §22.29 / §12 — the committed package is the Boss, never a substituted
	# System. This is the assertion that catches a "just put a SYS there" fix.
	t.check("opponent is the Boss", r.opponent_is_boss())
	t.eq("opponent is the Run's committed Boss", r.opponent_id, r.boss_id)
	t.eq("committed HOST survives", r.host_id, Content.INITIAL_HOST_ID)

	# The Run is parked, NOT complete. Beta 0.3 consumes this state.
	t.check("still a valid Run", r.problems().is_empty())
	t.eq("still on the last step", r.step, Run.RUN_LENGTH)


func _test_offer_round_trip(t: TestCase) -> void:
	t.group("offers persist verbatim")

	var upgrades := Content.all_upgrades()
	var p := Run.PendingPath.new()
	p.step = 2
	p.upgrade_exhausted = false
	p.offers = [
		Run.PathOffer.new(0, Types.OpponentKind.SYS, "SYS_01", "HST_02", upgrades[0]["id"]),
		Run.PathOffer.new(1, Types.OpponentKind.SYS, "SYS_02", "HST_03", upgrades[1]["id"]),
	]

	# §22.19 — reloading a Path Choice restores exactly what was offered. A
	# round trip is the necessary half of that; Phase D adds the reload proof
	# that no route RNG is consumed on the way back in.
	var restored := Run.PendingPath.from_dict(p.to_dict())
	t.check("round trip succeeds", restored != null)
	t.eq("step survives", restored.step, p.step)
	t.eq("offer count survives", restored.offers.size(), p.offers.size())
	for i in p.offers.size():
		t.eq("offer %d index" % i, restored.offers[i].index, p.offers[i].index)
		t.eq("offer %d opponent kind" % i, restored.offers[i].opponent_kind, p.offers[i].opponent_kind)
		t.eq("offer %d opponent" % i, restored.offers[i].opponent_id, p.offers[i].opponent_id)
		t.eq("offer %d HOST" % i, restored.offers[i].host_id, p.offers[i].host_id)
		t.eq("offer %d UPGRADE" % i, restored.offers[i].upgrade_id, p.offers[i].upgrade_id)

	# A Boss offer must survive as a Boss. Collapsing it to a SYS on the way
	# through a save is exactly the failure §12 exists to prevent.
	var boss_offer := Run.PathOffer.new(0, Types.OpponentKind.BOS, "BOS_01", "HST_04", upgrades[0]["id"])
	var boss_restored := Run.PathOffer.from_dict(boss_offer.to_dict())
	t.eq("Boss offer stays a Boss", boss_restored.opponent_kind, Types.OpponentKind.BOS)
	t.eq("Boss offer keeps its BOS_ID", boss_restored.opponent_id, "BOS_01")

	# Malformed records are rejected rather than repaired.
	t.check("unknown opponent kind rejected", Run.PathOffer.from_dict({"opponent_kind": "NOPE"}) == null)
	t.check("wrong offer count rejected", Run.PendingPath.from_dict({"step": 1, "offers": []}) == null)
	t.check(
		"out-of-range step rejected",
		Run.PendingPath.from_dict({"step": 9, "offers": [boss_offer.to_dict(), boss_offer.to_dict()]}) == null
	)


func _test_invariants(t: TestCase) -> void:
	t.group("Run invariants")

	var r := _run_at_step(1)
	t.check("a well-formed Run has no problems", r.problems().is_empty())

	# The pending-path invariant: phase and data must agree, in both directions.
	r.phase = Types.SessionPhase.PENDING_PATH
	r.pending_path = null
	t.check("PENDING_PATH with no offers is rejected", not r.problems().is_empty())

	var p := Run.PendingPath.new()
	p.step = 1
	p.offers = [
		Run.PathOffer.new(0, Types.OpponentKind.SYS, "SYS_01", "HST_02", "UPG_01"),
		Run.PathOffer.new(1, Types.OpponentKind.SYS, "SYS_02", "HST_03", "UPG_02"),
	]
	r.pending_path = p
	t.check("PENDING_PATH with offers is valid", r.problems().is_empty())

	r.phase = Types.SessionPhase.PENDING_BUILD
	t.check("offers held outside PENDING_PATH are rejected", not r.problems().is_empty())

	# Offers must belong to the step the Run is actually on.
	r.phase = Types.SessionPhase.PENDING_PATH
	p.step = 3
	t.check("offers for the wrong step are rejected", not r.problems().is_empty())

	# §22.34 — duplicate acquisitions reject cleanly rather than being deduped
	# on read. `acquire_upgrade` cannot produce this; a hand-edited save can.
	var d := _run_at_step(2)
	d.upgrade_ids = ["UPG_01", "UPG_01"]
	t.check("duplicate acquired UPGRADE is rejected", not d.problems().is_empty())

	# A committed Run can never wear a setup phase — those belong to RunSetup.
	var s := _run_at_step(1)
	s.phase = Types.SessionPhase.SETUP_HACKER
	t.check("committed Run carrying a setup phase is rejected", not s.problems().is_empty())

	# §22.33 — a Run with no Boss is not a Run.
	var b := _run_at_step(1)
	b.boss_id = ""
	t.check("missing Boss is rejected", not b.problems().is_empty())

	var o := _run_at_step(1)
	o.step = 7
	t.check("out-of-range step is rejected", not o.problems().is_empty())

	# The build invariant: four distinct inventory Programs, never a partial.
	var v := _run_at_step(1)
	v.build = v.build.slice(0, 3)
	t.check("short build is rejected", not v.problems().is_empty())

	var dup := _run_at_step(1)
	dup.build = [dup.build[0], dup.build[0], dup.build[2], dup.build[3]]
	t.check("build with a repeated Program is rejected", not dup.problems().is_empty())

	var alien := _run_at_step(1)
	alien.build = [alien.build[0], alien.build[1], alien.build[2], "PRG_H_999"]
	t.check("build naming a Program outside the inventory is rejected", not alien.problems().is_empty())


## A committed Run parked on Build, as Phase B's `commit_setup_deck` will
## produce it. Built by hand here because the route generators are Phase B.
func _run_at_step(step: int) -> Run:
	var r := Run.new()
	r.boss_id = Content.all_bosses()[0]["id"]
	r.step = step
	r.settings = Constants.default_settings()
	r.hacker_id = Content.DEFAULT_HACKER_ID
	r.deck_id = Content.DEFAULT_DECK_ID
	r.hacker_max_link = 150
	r.inventory = Content.inventory_program_ids(r.hacker_id, r.deck_id)
	r.build = Content.default_build(r.hacker_id, r.deck_id)
	r.build_origin = Types.BuildOrigin.DEFAULT
	r.opponent_kind = Types.OpponentKind.SYS
	r.opponent_id = Content.INITIAL_SYSTEM_ID
	r.host_id = Content.INITIAL_HOST_ID
	r.route_rng_state = Rng.new(1).get_state()
	r.phase = Types.SessionPhase.PENDING_BUILD
	return r

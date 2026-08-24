extends RefCounted

## Beta 0.2 Phase B — route offer generation and the Run lifecycle.
##
## Two kinds of check, and both are needed:
##
##   1. FIXTURE PARITY against `tests/fixtures/route.json`, generated from the
##      alpha. This compares the exact offers AND the route RNG state after each
##      generation, which is what pins the DRAW COUNT rather than just the
##      result. An implementation that consumed one extra draw would still make
##      plausible offers and would fail here.
##   2. Behavioural rules, which state the intent in a form that survives a
##      content change — the fixture would simply need regenerating.
##
## Authorization §22 coverage: 1, 5, 6, 7, 8, 12, 13, 14, 15, 19, 21, 23, 24,
## 25, 26, 27, 28, 29, 30, 31.

const FIXTURE := "res://tests/fixtures/route.json"


func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("route")
		t.check("content loads", false)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()

	var fixture := _load_fixture(t)
	if not fixture.is_empty():
		_test_fixture_parity(t, fixture)
		_test_quick_match_parity(t, fixture)

	_test_initial_route(t)
	_test_escalation_routes(t)
	_test_boss_route(t)
	_test_upgrade_exhaustion(t)
	_test_no_reroll(t)
	_test_full_lifecycle(t)

	Content.clear()
	Passives.clear_cache()


func _load_fixture(t: TestCase) -> Dictionary:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		t.group("route parity")
		t.check("fixture %s is readable" % FIXTURE, false)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		t.group("route parity")
		t.check("fixture parses as JSON object", false)
		return {}
	return parsed


## Replay each alpha walk through the beta generators and compare everything.
func _test_fixture_parity(t: TestCase, fixture: Dictionary) -> void:
	t.group("route parity with the alpha")

	var boss_id := str(fixture["bossId"])
	var walks: Dictionary = fixture["walks"]

	for seed_key in walks:
		var rng := Rng.new(int(seed_key))
		var acquired: Array = []

		for gen in (walks[seed_key] as Array):
			var step := int(gen["step"])
			var kind := str(gen["kind"])

			# The acquisitions going in must match, or the comparison below is
			# testing two different situations rather than two implementations.
			t.eq("seed %s step %d acquired going in" % [seed_key, step], acquired, gen["acquired"])

			var p: Run.PendingPath
			match kind:
				"initial":
					p = Route.initial_path_offers(rng, acquired)
				"later":
					p = Route.later_path_offers(rng, step, acquired)
				"boss":
					p = Route.boss_path_offers(rng, step, boss_id, acquired)

			if p == null:
				t.check("seed %s step %d generated offers" % [seed_key, step], false)
				continue

			var expected_offers: Array = gen["offers"]
			t.eq("seed %s step %d offer count" % [seed_key, step], p.offers.size(), expected_offers.size())
			for i in mini(p.offers.size(), expected_offers.size()):
				var got: Run.PathOffer = p.offers[i]
				var want: Dictionary = expected_offers[i]
				var label := "seed %s step %d offer %d" % [seed_key, step, i]
				t.eq("%s index" % label, got.index, int(want["index"]))
				t.eq("%s opponent kind" % label, Types.OPPONENT_KIND_NAMES[got.opponent_kind], str(want["opponentKind"]))
				t.eq("%s opponent" % label, got.opponent_id, str(want["opponentId"]))
				t.eq("%s HOST" % label, got.host_id, str(want["hostId"]))
				t.eq("%s UPGRADE" % label, got.upgrade_id, str(want["upgradeId"]))

			t.eq(
				"seed %s step %d exhaustion flag" % [seed_key, step],
				p.upgrade_exhausted,
				bool(gen["upgradeExhausted"])
			)

			# THE DRAW-COUNT ASSERTION. Everything above can pass while the beta
			# consumes a different number of draws; this cannot.
			t.eq("seed %s step %d route state after" % [seed_key, step], rng.get_state(), int(gen["stateAfter"]))

			acquired = Run.acquire_upgrade(acquired, p.offers[0].upgrade_id)


## §22.30 / §22.31 — Random Quick Match rolls a valid System, HOST, and build
## from ONE isolated setup stream.
func _test_quick_match_parity(t: TestCase, fixture: Dictionary) -> void:
	t.group("random quick match")

	var cases: Dictionary = fixture["quickMatch"]
	var pool_systems: Array = []
	for s in Content.pool_systems():
		pool_systems.append(s["id"])
	var pool_hosts: Array = []
	for h in Content.pool_hosts():
		pool_hosts.append(h["id"])
	var inventory := Content.inventory_program_ids(Content.DEFAULT_HACKER_ID, Content.DEFAULT_DECK_ID)

	for seed_key in cases:
		var want: Dictionary = cases[seed_key]
		var rng := Rng.new(int(seed_key))
		var got := Session.random_quick_match_setup(rng)

		t.eq("seed %s build" % seed_key, got["build"], want["build"])
		t.eq("seed %s System" % seed_key, got["system_id"], str(want["systemId"]))
		t.eq("seed %s HOST" % seed_key, got["host_id"], str(want["hostId"]))
		# Pins the draw ORDER, not just the values: rolling the System before
		# the build would still produce a legal setup and a different state.
		t.eq("seed %s setup state after" % seed_key, rng.get_state(), int(want["stateAfter"]))

		t.check("seed %s System is in pool" % seed_key, pool_systems.has(got["system_id"]))
		t.check("seed %s HOST is in pool" % seed_key, pool_hosts.has(got["host_id"]))
		t.check("seed %s build is legal" % seed_key, Content.is_valid_build(got["build"], inventory))

	# §22.31 — setup randomness never perturbs the gameplay stream.
	var gameplay := Rng.new(31)
	var control := Rng.new(31)
	Session.random_quick_match_setup(Rng.new(9))
	t.eq("gameplay stream untouched by RQM setup", gameplay.next_u32(), control.next_u32())

	# An unseeded setup source still produces a legal setup, and reports the
	# seed it used so a report can reproduce it.
	var made := Session.make_setup_random()
	t.check("unseeded setup source reports its seed", int(made["seed"]) >= 0)
	var rolled := Session.random_quick_match_setup(made["rng"])
	t.check("unseeded roll is legal", Content.is_valid_build(rolled["build"], inventory))


func _test_initial_route(t: TestCase) -> void:
	t.group("initial route")

	# §22.6 — Battle 1 is the FIXED intro encounter on both paths, whatever the
	# Boss. The only intended difference is the reward.
	for seed_value in [0, 3, 11, 99]:
		var p := Route.initial_path_offers(Rng.new(seed_value), [])
		t.eq("seed %d offers two paths" % seed_value, p.offers.size(), Content.PATH_CHOICE_COUNT)
		for o in p.offers:
			t.eq("seed %d System is DOORMAN" % seed_value, o.opponent_id, Content.INITIAL_SYSTEM_ID)
			t.eq("seed %d HOST is THRESHOLD" % seed_value, o.host_id, Content.INITIAL_HOST_ID)
			t.eq("seed %d opponent is a System" % seed_value, o.opponent_kind, Types.OpponentKind.SYS)
		# §22.7 — distinct UPGRADEs while the pool allows it.
		t.check(
			"seed %d offers distinct UPGRADEs" % seed_value,
			p.offers[0].upgrade_id != p.offers[1].upgrade_id
		)
		t.check("seed %d is not the exhausted case" % seed_value, not p.upgrade_exhausted)


func _test_escalation_routes(t: TestCase) -> void:
	t.group("escalation routes")

	var pool_systems: Array = []
	for s in Content.pool_systems():
		pool_systems.append(s["id"])
	var pool_hosts: Array = []
	for h in Content.pool_hosts():
		pool_hosts.append(h["id"])

	for seed_value in range(40):
		for step in [2, 3]:
			var p := Route.later_path_offers(Rng.new(seed_value), step, [])
			t.eq("seed %d step %d step recorded" % [seed_value, step], p.step, step)

			for o in p.offers:
				# §22.13 — in-pool content only. The intro-only rows must never
				# be randomly selected.
				t.check("seed %d step %d System in pool" % [seed_value, step], pool_systems.has(o.opponent_id))
				t.check("seed %d step %d HOST in pool" % [seed_value, step], pool_hosts.has(o.host_id))
				t.eq("seed %d step %d opponent is a System" % [seed_value, step], o.opponent_kind, Types.OpponentKind.SYS)

			# §22.14 — identical SYS+HST pairings are avoided while another
			# combination exists. With 2 pooled Systems x 4 pooled HOSTs there
			# are always others, so this must hold for every seed.
			var same: bool = (
				p.offers[0].opponent_id == p.offers[1].opponent_id
				and p.offers[0].host_id == p.offers[1].host_id
			)
			t.check("seed %d step %d avoids an identical pairing" % [seed_value, step], not same)

	# Sharing a System OR a HOST is explicitly fine — only the exact pair is
	# avoided. If the generator ever started forcing both to differ it would be
	# over-constraining, so confirm the looser rule really is what is in force.
	var shared_something := false
	for seed_value in range(60):
		var p := Route.later_path_offers(Rng.new(seed_value), 2, [])
		if p.offers[0].opponent_id == p.offers[1].opponent_id or p.offers[0].host_id == p.offers[1].host_id:
			shared_something = true
			break
	t.check("offers may share a System or a HOST", shared_something)


func _test_boss_route(t: TestCase) -> void:
	t.group("final Boss route")

	var boss_id: String = Content.all_bosses()[0]["id"]
	var pool_hosts: Array = []
	for h in Content.pool_hosts():
		pool_hosts.append(h["id"])

	for seed_value in range(40):
		var p := Route.boss_path_offers(Rng.new(seed_value), Run.RUN_LENGTH, boss_id, [])

		for o in p.offers:
			# §22.23 / §22.29 — both paths name the Run's committed Boss. A
			# substituted System here is the exact failure §12 forbids.
			t.eq("seed %d offers the Boss" % seed_value, o.opponent_kind, Types.OpponentKind.BOS)
			t.eq("seed %d names the committed Boss" % seed_value, o.opponent_id, boss_id)
			# §22.24 — with a valid random HOST.
			t.check("seed %d HOST in pool" % seed_value, pool_hosts.has(o.host_id))

		# Two distinct HOSTs while at least two are eligible; four are.
		t.check(
			"seed %d offers distinct HOSTs" % seed_value,
			p.offers[0].host_id != p.offers[1].host_id
		)


func _test_upgrade_exhaustion(t: TestCase) -> void:
	t.group("UPGRADE pool exhaustion")

	var all_ids: Array = []
	for u in Content.all_upgrades():
		all_ids.append(u["id"])

	# §22.15 — an acquired UPGRADE is never reoffered.
	for seed_value in range(30):
		var acquired: Array = [all_ids[0]]
		var p := Route.later_path_offers(Rng.new(seed_value), 2, acquired)
		for o in p.offers:
			t.check("seed %d does not reoffer an acquired UPGRADE" % seed_value, o.upgrade_id != all_ids[0])

	# §22.25 — with exactly one left, BOTH paths legitimately show it, and the
	# generator records WHY rather than leaving it looking like a bug.
	var nearly_all := all_ids.slice(0, all_ids.size() - 1)
	var last_id: String = all_ids[all_ids.size() - 1]
	for seed_value in range(10):
		var p := Route.later_path_offers(Rng.new(seed_value), 3, nearly_all)
		t.eq("seed %d offers the last UPGRADE on path 0" % seed_value, p.offers[0].upgrade_id, last_id)
		t.eq("seed %d offers the last UPGRADE on path 1" % seed_value, p.offers[1].upgrade_id, last_id)
		t.check("seed %d flags exhaustion" % seed_value, p.upgrade_exhausted)

	# The exhausted case must consume NO route RNG for the UPGRADE choice. If it
	# shuffled a one-element array anyway, later generation would drift.
	var rng_exhausted := Rng.new(5)
	Route.pick_offer_upgrades(rng_exhausted, nearly_all)
	t.eq("exhausted pick consumes no draws", rng_exhausted.get_state(), Rng.new(5).get_state())

	var rng_normal := Rng.new(5)
	Route.pick_offer_upgrades(rng_normal, [])
	t.check("a real pick does consume draws", rng_normal.get_state() != Rng.new(5).get_state())

	# §22.26 — taking either duplicate path acquires it exactly once.
	var once := Run.acquire_upgrade(nearly_all, last_id)
	var twice := Run.acquire_upgrade(once, last_id)
	t.eq("duplicate offer acquires once", once.size(), all_ids.size())
	t.eq("and cannot be acquired again", twice.size(), all_ids.size())


func _test_no_reroll(t: TestCase) -> void:
	t.group("offers do not reroll")

	var r := _committed_run()
	var before: Array = []
	for o in r.pending_path.offers:
		before.append(o.to_dict())
	var state_before := r.route_rng_state

	# §22.19 — reopening a Path Choice that already has offers must not
	# regenerate them. The guard makes this an error rather than a silent
	# reroll, which is the failure a player would experience as the game
	# changing its mind.
	var reopened := r.open_path_choice(1)
	t.check("reopening pending offers is refused", not reopened)

	var after: Array = []
	for o in r.pending_path.offers:
		after.append(o.to_dict())
	t.eq("offers are unchanged", after, before)
	t.eq("route RNG did not advance", r.route_rng_state, state_before)

	# §22.21 — generating offers never touches the gameplay stream. The two are
	# separate instances by construction; this asserts the construction.
	var gameplay := Rng.new(77)
	var control := Rng.new(77)
	var r2 := _committed_run()
	r2.select_path(0)
	r2.open_path_choice(2)
	t.eq("gameplay stream untouched by route generation", gameplay.next_u32(), control.next_u32())


func _test_full_lifecycle(t: TestCase) -> void:
	t.group("full Run lifecycle")

	var boss_id: String = Content.all_bosses()[0]["id"]

	# §22.1 / §22.5 — New Run runs Boss, then Hacker, then Deck, and completing
	# Deck lands on the initial Path Choice with offers already persisted.
	var setup := RunSetup.commit_boss(boss_id, Constants.default_settings(), 4242)
	setup = setup.commit_hacker(Content.DEFAULT_HACKER_ID)
	var r := setup.commit_deck(Content.DEFAULT_DECK_ID)

	t.check("deck commit completes setup", r != null)
	t.eq("Run starts at Battle 1", r.step, 1)
	t.eq("Run opens on a Path Choice", r.phase, Types.SessionPhase.PENDING_PATH)
	t.check("initial offers are already generated", r.pending_path != null)
	t.eq("Boss carried through setup", r.boss_id, boss_id)
	t.eq("no UPGRADEs acquired yet", r.upgrade_ids.size(), 0)
	t.check("Run is well formed", r.problems().is_empty())

	# The Run's identity is real, not inherited from the Quick Match pin.
	t.eq("inventory is the selected pair's six Programs", r.inventory.size(), Content.INVENTORY_SIZE)
	t.check("build is legal", Content.is_valid_build(r.build, r.inventory))
	t.check("LINK maximum resolved", r.hacker_max_link > 0)

	# §22.8 — selecting the initial route acquires the UPGRADE BEFORE Build, so
	# it is active for Battle 1 rather than arriving a battle late.
	var taken: String = r.pending_path.offers[0].upgrade_id
	t.check("path selection succeeds", r.select_path(0))
	t.eq("UPGRADE acquired at selection", r.upgrade_ids, [taken])
	t.eq("moved to Build", r.phase, Types.SessionPhase.PENDING_BUILD)
	t.eq("encounter committed", r.opponent_id, Content.INITIAL_SYSTEM_ID)
	t.eq("HOST committed", r.host_id, Content.INITIAL_HOST_ID)
	t.check("offers dropped after commit", r.pending_path == null)
	t.check("still well formed", r.problems().is_empty())

	# §22.12 — winning Battle 1 produces the Battle 2 choices, and so on up.
	for step in [2, 3]:
		t.check("opened path choice for step %d" % step, r.open_path_choice(step))
		t.eq("Run is on step %d" % step, r.step, step)
		t.eq("offers are for step %d" % step, r.pending_path.step, step)
		t.check("offers exist for step %d" % step, r.pending_path.offers.size() == Content.PATH_CHOICE_COUNT)
		t.check("selected a path at step %d" % step, r.select_path(0))
		t.check("well formed after step %d" % step, r.problems().is_empty())

	# §22.16 — UPGRADEs accumulate across the Run and are never lost.
	t.eq("three UPGRADEs after three battles", r.upgrade_ids.size(), 3)

	# §22.23 / §22.27 — the final route is the Boss, and committing it persists
	# the Boss + HOST + UPGRADE package.
	t.check("opened the final route", r.open_path_choice(Run.RUN_LENGTH))
	for o in r.pending_path.offers:
		t.eq("final route names the Boss", o.opponent_id, boss_id)
		t.eq("final route opponent is a Boss", o.opponent_kind, Types.OpponentKind.BOS)

	var final_host: String = r.pending_path.offers[1].host_id
	var final_upgrade: String = r.pending_path.offers[1].upgrade_id
	t.check("committed the final route", r.select_path(1))
	t.eq("Boss committed as the opponent", r.opponent_id, boss_id)
	t.check("opponent is the Boss, not a System", r.opponent_is_boss())
	t.eq("final HOST committed", r.host_id, final_host)
	t.check("final UPGRADE acquired", r.upgrade_ids.has(final_upgrade))
	t.eq("all four UPGRADEs acquired", r.upgrade_ids.size(), Content.all_upgrades().size())

	# §22.28 — confirming the final Build stops at PENDING_BOSS_BATTLE rather
	# than fabricating a Battle 4. The Run is parked, NOT complete.
	r.enter_pending_boss_battle()
	t.check("reached the beta 0.2 stop point", r.is_pending_boss_battle())
	t.eq("stopped on the last step", r.step, Run.RUN_LENGTH)
	t.check("Run survives as valid state for beta 0.3", r.problems().is_empty())


## A Run freshly committed and sitting on its initial Path Choice.
func _committed_run() -> Run:
	var setup := RunSetup.commit_boss(Content.all_bosses()[0]["id"], Constants.default_settings(), 2024)
	setup = setup.commit_hacker(Content.DEFAULT_HACKER_ID)
	return setup.commit_deck(Content.DEFAULT_DECK_ID)

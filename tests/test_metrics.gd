extends RefCounted

## Metrics and logging.
##
## The load-bearing test here is the BUCKET IDENTITY. Every counter in this
## module is a running sum, and a running sum is the easiest thing in the world
## to get subtly wrong: attribute one increment to two buckets and the totals
## still look plausible while every ratio derived from them is a lie. So rather
## than asserting individual numbers against hand-computed expectations — which
## would only re-derive the implementation — the tests play real battles and
## assert the relationship the buckets are DEFINED by:
##
##     match + attacker + bomb + lineslice + transform + passive + buff == total
##
## `cascade` is deliberately excluded: it is cross-cutting, overlapping the
## others rather than adding to them.
##
## The second test is continuation. A save whose metrics restore to something
## plausible but wrong is worse than one that fails loudly, so the check is that
## an interrupted battle finishes with the SAME figures as an uninterrupted one.

const BUILD: Array[String] = ["PRG_H_001", "PRG_H_002", "PRG_H_005", "PRG_H_006"]


func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("metrics")
		t.check("content loads", false)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()

	_test_buckets_reconcile(t)
	_test_roster_seeding(t)
	_test_passive_instances_are_not_merged(t)
	_test_levels(t)
	_test_turn_stream_by_level(t)
	_test_continuation(t)

	Content.clear()
	Passives.clear_cache()


## The identity, over a spread of Systems and HOSTs so several damage sources
## and at least one PASSIVE actually fire.
func _test_buckets_reconcile(t: TestCase) -> void:
	t.group("metrics / disjoint buckets reconcile")

	for spec in [["SYS_01", "HST_01", 3], ["SYS_02", "HST_03", 11], ["SYS_03", "HST_05", 21]]:
		var state := _play(str(spec[0]), str(spec[1]), int(spec[2]))
		var m := state.metrics
		var label := "%s/%s seed %d" % spec

		for side in 2:
			var s: Metrics.SideMetrics = m.side(side)
			var summed := s.match_damage + s.attacker_damage + s.bomb_damage \
				+ s.lineslice_damage + s.transform_damage + s.passive_damage \
				+ s.buff_damage_added
			# Compared with a tolerance rather than for equality. The analytical
			# splits are pre-floor floats that a Shield rescales proportionally,
			# so the sum is exact in real arithmetic and off by an ulp in
			# floating point. Rounding each bucket first would hide a genuine
			# attribution error inside the rounding.
			t.check("%s side %d buckets sum to total (%.4f vs %d)" % [label, side, summed, s.total_damage],
				absf(summed - float(s.total_damage)) < 0.001)

		# The battle actually did something — otherwise the identity above is
		# the trivial 0 == 0 and proves nothing at all.
		var dealt := m.side(Types.Side.PLAYER).total_damage + m.side(Types.Side.ENEMY).total_damage
		t.check("%s dealt damage" % label, dealt > 0)
		t.check("%s counted turns" % label, m.turns > 0)
		t.check("%s recorded a winner" % label, m.winner != -1)

		# Damage credited to a side must be damage the other side actually lost.
		var ice_lost: int = int(state.config["enemy_hp"]) - state.hp[Types.Side.ENEMY]
		t.eq("%s Hacker damage equals ICE lost" % label,
			m.side(Types.Side.PLAYER).total_damage, ice_lost)
		var link_lost: int = int(state.config["player_hp"]) - state.hp[Types.Side.PLAYER]
		t.eq("%s System damage equals LINK lost" % label,
			m.side(Types.Side.ENEMY).total_damage, link_lost)


## Seeded from the ACTIVE roster only. A Program sitting in inventory has no
## slot, so a report cannot imply it was fielded.
func _test_roster_seeding(t: TestCase) -> void:
	t.group("metrics / seeded from the active roster")
	var state := Session.create_quick_match("SYS_01", "HST_01", 5, BUILD, {}, true)
	var units: Dictionary = state.metrics.side(Types.Side.PLAYER).units

	t.eq("one slot per active Program", units.size(), BUILD.size())
	for pid in BUILD:
		t.check("%s has a slot" % pid, units.has(pid))

	# PRG_H_003 and PRG_H_004 are in the Hacker's portfolio but not this build.
	var inventory: Array = []
	inventory.append_array(Content.hacker(Content.DEFAULT_HACKER_ID)["portfolio"])
	inventory.append_array(Content.deck(Content.DEFAULT_DECK_ID)["portfolio"])
	var benched := 0
	for pid in inventory:
		if not BUILD.has(pid):
			benched += 1
			t.check("benched %s has no slot" % pid, not units.has(pid))
	t.check("the fixture actually benches something", benched > 0)


## The same PASSIVE row supplied by two sources is two instances and both apply.
## Keying by PASSIVE ID alone would merge them and make stacking unauditable —
## which is a rule the metrics must be able to demonstrate, not just obey.
func _test_passive_instances_are_not_merged(t: TestCase) -> void:
	t.group("metrics / PASSIVE instances stay separable")

	var a := {"passive_id": "PSV_001", "source_kind": Types.PassiveSourceKind.HAK, "source_id": "HAK_01"}
	var b := {"passive_id": "PSV_001", "source_kind": Types.PassiveSourceKind.HST, "source_id": "HST_02"}
	t.check("same PASSIVE from two sources keys differently",
		Metrics.passive_key(a) != Metrics.passive_key(b))

	var m := Metrics.create(BUILD, [])
	Metrics.consume(m, [
		{"t": Types.EVT.PASSIVE, "side": Types.Side.PLAYER, "cause": a, "damage": 3},
		{"t": Types.EVT.PASSIVE, "side": Types.Side.PLAYER, "cause": b, "damage": 5},
		{"t": Types.EVT.PASSIVE, "side": Types.Side.PLAYER, "cause": a, "damage": 2},
	])
	var passives: Dictionary = m.side(Types.Side.PLAYER).passives
	t.eq("two instances tracked", passives.size(), 2)
	t.eq("first instance accumulates", passives[Metrics.passive_key(a)].damage, 5)
	t.eq("first instance counts triggers", passives[Metrics.passive_key(a)].triggers, 2)
	t.eq("second instance stays separate", passives[Metrics.passive_key(b)].damage, 5)
	t.eq("second instance counts triggers", passives[Metrics.passive_key(b)].triggers, 1)


func _test_levels(t: TestCase) -> void:
	t.group("logging / levels")
	t.eq("three levels", BattleLog.LEVEL_NAMES.size(), 3)
	t.eq("debug builds default to VERBOSE",
		BattleLog.default_level(true), BattleLog.Level.VERBOSE)
	t.eq("release builds default to BASIC",
		BattleLog.default_level(false), BattleLog.Level.BASIC)
	# COMPLETE is an explicit opt-in and must never be reached by defaulting.
	t.check("COMPLETE is never a default",
		BattleLog.default_level(true) != BattleLog.Level.COMPLETE
		and BattleLog.default_level(false) != BattleLog.Level.COMPLETE)

	t.eq("names round-trip", BattleLog.parse_level("COMPLETE"), BattleLog.Level.COMPLETE)
	t.eq("an unknown name falls back to BASIC",
		BattleLog.parse_level("nonsense"), BattleLog.Level.BASIC)


## BASIC keeps no per-turn stream, VERBOSE does, and COMPLETE additionally keeps
## the readable mirror. High-value events survive at EVERY level — that is the
## whole reason they were promoted out of the turn record.
func _test_turn_stream_by_level(t: TestCase) -> void:
	t.group("logging / retention by level")
	var restore := BattleLog.level()

	BattleLog.set_level(BattleLog.Level.BASIC)
	var basic := _play("SYS_01", "HST_05", 7)
	t.eq("BASIC writes no turn records", basic.log.turns.size(), 0)

	BattleLog.set_level(BattleLog.Level.VERBOSE)
	var verbose := _play("SYS_01", "HST_05", 7)
	t.check("VERBOSE writes turn records", verbose.log.turns.size() > 0)
	t.check("VERBOSE omits the readable mirror",
		not (verbose.log.turns[0] as Dictionary).has("actions"))

	BattleLog.set_level(BattleLog.Level.COMPLETE)
	var complete := _play("SYS_01", "HST_05", 7)
	t.check("COMPLETE keeps the readable mirror",
		(complete.log.turns[0] as Dictionary).has("actions"))

	# The identical battle at three levels must produce identical OUTCOMES.
	# If logging could perturb anything, the differential gate would be
	# measuring the log level rather than the port.
	t.eq("level does not change the winner", verbose.winner, basic.winner)
	t.eq("level does not change the turn count", verbose.turn, basic.turn)
	t.eq("level does not change final ICE",
		verbose.hp[Types.Side.ENEMY], basic.hp[Types.Side.ENEMY])
	t.eq("COMPLETE does not change the winner", complete.winner, basic.winner)
	t.eq("COMPLETE does not change final ICE",
		complete.hp[Types.Side.ENEMY], basic.hp[Types.Side.ENEMY])
	t.eq("metrics are identical across levels",
		verbose.metrics.side(Types.Side.PLAYER).total_damage,
		basic.metrics.side(Types.Side.PLAYER).total_damage)

	# Turn records are bounded in memory, not merely on disk.
	t.check("turn records stay under the in-memory cap",
		verbose.log.turns.size() <= BattleLog.MAX_TURNS_IN_MEMORY)
	t.check("event records stay under the in-memory cap",
		verbose.log.events.size() <= BattleLog.MAX_EVENTS_IN_MEMORY)

	BattleLog.set_level(restore)


## THE test. Metrics that restore to something plausible and then diverge are
## worse than metrics that fail loudly, because the discrepancy surfaces far
## from its cause.
func _test_continuation(t: TestCase) -> void:
	t.group("metrics / resume continues identically")
	var restore := BattleLog.level()
	BattleLog.set_level(BattleLog.Level.VERBOSE)

	for spec in [["SYS_01", "HST_01", 3, 2], ["SYS_02", "HST_04", 11, 3]]:
		var sys := str(spec[0])
		var host := str(spec[1])
		var seed_value := int(spec[2])
		var save_after := int(spec[3])
		var label := "%s/%s seed %d saved at turn %d" % spec

		# Uninterrupted.
		var a := Session.create_quick_match(sys, host, seed_value, BUILD, {}, true)
		var a_game := Game.new(a)
		a_game.start_player_phase()
		_advance(a_game, a, save_after)
		_finish(a_game, a)

		# Interrupted at the same point, restored, then finished.
		var b := Session.create_quick_match(sys, host, seed_value, BUILD, {}, true)
		var b_game := Game.new(b)
		b_game.start_player_phase()
		_advance(b_game, b, save_after)

		var restored := SaveState.from_dict(SaveState.to_dict(b))
		if not restored["ok"]:
			t.check(label, false)
			printerr("        %s" % restored["reason"])
			continue
		var r: GameState = restored["state"]
		t.check("%s restores its accounting" % label, r.metrics != null and r.log != null)
		if r.metrics == null:
			continue
		_finish(Game.new(r), r)

		for side in 2:
			var expected: Metrics.SideMetrics = a.metrics.side(side)
			var actual: Metrics.SideMetrics = r.metrics.side(side)
			t.eq("%s side %d total damage" % [label, side], actual.total_damage, expected.total_damage)
			t.check("%s side %d Sync damage" % [label, side],
				is_equal_approx(actual.match_damage, expected.match_damage))
			t.check("%s side %d bomb damage" % [label, side],
				is_equal_approx(actual.bomb_damage, expected.bomb_damage))
			t.eq("%s side %d charge wasted" % [label, side],
				actual.charge_wasted_total, expected.charge_wasted_total)
			t.eq("%s side %d Packets destroyed" % [label, side],
				actual.tiles_destroyed, expected.tiles_destroyed)
			t.eq("%s side %d Deck charge" % [label, side],
				actual.deck.charge_from_neutral, expected.deck.charge_from_neutral)

		t.eq("%s detonations" % label, r.metrics.detonations, a.metrics.detonations)
		t.eq("%s reshuffles" % label, r.metrics.auto_reshuffles, a.metrics.auto_reshuffles)
		t.eq("%s System withholds" % label, r.metrics.system_withholds, a.metrics.system_withholds)
		t.eq("%s winner" % label, r.metrics.winner, a.metrics.winner)

	BattleLog.set_level(restore)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _play(sys: String, host: String, seed_value: int) -> GameState:
	var state := Session.create_quick_match(sys, host, seed_value, BUILD, {}, true)
	var game := Game.new(state)
	game.start_player_phase()
	_finish(game, state)
	return state


func _advance(game: Game, state: GameState, turns: int) -> void:
	for i in turns:
		if state.has_winner():
			return
		_fire_ready(game, state)
		if state.has_winner():
			return
		var mv := Bot.pick_move(state.board, state.config)
		if mv.is_empty():
			return
		game.attempt_swap(mv["a"], mv["b"])
		if state.has_winner():
			return
		game.run_enemy_phase()
		if state.has_winner():
			return
		game.start_player_phase()


func _finish(game: Game, state: GameState) -> void:
	var safety := 0
	while not state.has_winner() and safety < 500:
		safety += 1
		_fire_ready(game, state)
		if state.has_winner():
			break
		var mv := Bot.pick_move(state.board, state.config)
		if mv.is_empty():
			break
		game.attempt_swap(mv["a"], mv["b"])
		if state.has_winner():
			break
		game.run_enemy_phase()
		if state.has_winner():
			break
		game.start_player_phase()


func _fire_ready(game: Game, state: GameState) -> void:
	var units: Array = state.units[Types.Side.PLAYER]
	for i in units.size():
		if state.has_winner():
			return
		var u: GameState.UnitState = units[i]
		var prog := Content.program(u.program_id)
		if u.charge < int(prog["cost"]):
			continue
		game.fire_program(i, _target_for(state, prog["fn"]))
	if state.has_winner():
		return
	var deck := Content.deck(state.identity["deck_id"])
	if state.deck_charge >= int(deck["fn"]["cost"]):
		game.fire_deck_function(_target_for(state, deck["fn"]))


func _target_for(state: GameState, fn: Dictionary):
	var plan: Array = fn["plan"]
	if plan.is_empty():
		return null
	match plan[0]["target"]:
		Types.TargetKind.UNIT:
			var enemy: Array = state.units[Types.Side.ENEMY]
			var best := 0
			for i in enemy.size():
				if enemy[i].charge > enemy[best].charge:
					best = i
			return {"kind": Types.TargetKind.UNIT, "idx": best}
		Types.TargetKind.PACKET:
			for y in Constants.BOARD_HEIGHT:
				for x in Constants.BOARD_WIDTH:
					if state.board[y][x] != null:
						return {"kind": Types.TargetKind.PACKET, "p": Vector2i(x, y)}
			return null
		_:
			return null

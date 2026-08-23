extends RefCounted

## Save/resume determinism (D-022).
##
## The important test here is CONTINUATION, not round-trip equality. A round
## trip passes with an incompletely captured RNG state, a dropped countdown
## overlay, or a lost stamped area pattern — the restored state looks identical
## and then diverges the moment it is played.
##
## So: run a battle to turn K, save, restore into a fresh state, play both to
## completion, and require the resulting event streams to be identical. Only the
## continuation can see what the snapshot missed.

const BUILD: Array[String] = ["PRG_H_001", "PRG_H_002", "PRG_H_005", "PRG_H_006"]


func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("save")
		t.check("content loads", false)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()

	_test_round_trip(t)
	_test_rejections(t)
	_test_resume_determinism(t)

	Content.clear()
	Passives.clear_cache()


## The cheap check. Necessary but not sufficient — see the continuation test.
func _test_round_trip(t: TestCase) -> void:
	t.group("save / round trip")
	var state := Session.create_quick_match("SYS_01", "HST_01", 5, BUILD)
	var game := Game.new(state)
	game.start_player_phase()

	# Play a few turns so the state is genuinely mid-battle: charge accumulated,
	# board disturbed, RNG advanced.
	_advance(game, state, 3)

	var restored := SaveState.from_dict(SaveState.to_dict(state))
	t.check("a mid-battle save restores", restored["ok"])
	if not restored["ok"]:
		printerr("        %s" % restored["reason"])
		return

	var r: GameState = restored["state"]
	t.eq("turn", r.turn, state.turn)
	t.eq("Hacker LINK", r.hp[Types.Side.PLAYER], state.hp[Types.Side.PLAYER])
	t.eq("System ICE", r.hp[Types.Side.ENEMY], state.hp[Types.Side.ENEMY])
	t.eq("Deck charge", r.deck_charge, state.deck_charge)
	# The RNG is restored from its STATE, not its seed — resuming from the seed
	# would replay the battle from the beginning.
	t.eq("RNG state", r.rng.get_state(), state.rng.get_state())
	t.eq("Packet id counter", r.next_id, state.next_id)
	t.eq("overlay sequence counter", r.next_seq, state.next_seq)

	for side in 2:
		var a: Array = state.units[side]
		var b: Array = r.units[side]
		t.eq("unit count side %d" % side, b.size(), a.size())
		for i in a.size():
			t.eq("side %d unit %d charge" % [side, i], b[i].charge, a[i].charge)

	var board_matches := true
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var o: Tile = state.board[y][x]
			var n: Tile = r.board[y][x]
			if (o == null) != (n == null):
				board_matches = false
				continue
			if o == null:
				continue
			if o.id != n.id or o.kind != n.kind or o.color != n.color or o.shape != n.shape:
				board_matches = false
			if o.has_special() != n.has_special():
				board_matches = false
			elif o.has_special():
				# Every stamped parameter must survive, or a later detonation
				# resolves under different rules than the ones it was armed with.
				if o.special.seq != n.special.seq or o.special.countdown != n.special.countdown \
					or o.special.area_pattern != n.special.area_pattern \
					or o.special.delivers != n.special.delivers \
					or o.special.magnitude != n.special.magnitude:
					board_matches = false
	t.check("board and overlays restore exactly", board_matches)


## Invalid saves are rejected, never silently repaired.
func _test_rejections(t: TestCase) -> void:
	t.group("save / rejections")
	var state := Session.create_quick_match("SYS_01", "HST_01", 5, BUILD)

	var wrong_schema := SaveState.to_dict(state)
	wrong_schema["schema"] = 99
	t.check("a foreign schema is rejected", not SaveState.from_dict(wrong_schema)["ok"])

	# A save whose content no longer matches is rejected rather than restored
	# against different rules than it was made under.
	var wrong_fingerprint := SaveState.to_dict(state)
	wrong_fingerprint["fingerprint"] = "deadbeef-0"
	var r := SaveState.from_dict(wrong_fingerprint)
	t.check("a mismatched fingerprint is rejected", not r["ok"])
	t.check("and says why", str(r["reason"]).contains("fingerprint"))

	var stale_build := SaveState.to_dict(state)
	stale_build["units"][0][0]["program_id"] = "PRG_H_999"
	t.check("an unknown Program is rejected", not SaveState.from_dict(stale_build)["ok"])

	var bad_phase := SaveState.to_dict(state)
	bad_phase["phase"] = "nonsense"
	t.check("an unknown phase is rejected", not SaveState.from_dict(bad_phase)["ok"])


## THE test. A save that restores perfectly and then plays differently is worse
## than one that fails loudly, because the divergence surfaces far from its
## cause.
func _test_resume_determinism(t: TestCase) -> void:
	t.group("save / resume continues identically")

	for spec in [["SYS_01", "HST_01", 3, 2], ["SYS_02", "HST_04", 11, 3], ["SYS_03", "HST_05", 21, 4]]:
		var sys := str(spec[0])
		var host := str(spec[1])
		var seed_value := int(spec[2])
		var save_after := int(spec[3])

		# Uninterrupted: play to the end, recording everything after turn K.
		var a_state := Session.create_quick_match(sys, host, seed_value, BUILD)
		var a_game := Game.new(a_state)
		a_game.start_player_phase()
		_advance(a_game, a_state, save_after)
		var uninterrupted := _finish(a_game, a_state)

		# Interrupted: identical battle, saved at turn K, restored, then finished.
		var b_state := Session.create_quick_match(sys, host, seed_value, BUILD)
		var b_game := Game.new(b_state)
		b_game.start_player_phase()
		_advance(b_game, b_state, save_after)

		var restored := SaveState.from_dict(SaveState.to_dict(b_state))
		if not restored["ok"]:
			t.check("%s/%s seed %d saves at turn %d" % [sys, host, seed_value, save_after], false)
			continue
		var resumed: GameState = restored["state"]
		var resumed_events := _finish(Game.new(resumed), resumed)

		t.eq_seq(
			"%s/%s seed %d resumed after turn %d plays identically" % [sys, host, seed_value, save_after],
			resumed_events, uninterrupted,
		)


## Plays `turns` complete turns, or stops early if the battle ends.
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


## Plays to completion, returning a compact signature of every event — enough
## to catch a divergence, small enough to diff readably.
func _finish(game: Game, state: GameState) -> Array:
	var out: Array = []
	var safety := 0
	while not state.has_winner() and safety < 500:
		safety += 1
		_collect(out, _fire_ready_events(game, state))
		if state.has_winner():
			break
		var mv := Bot.pick_move(state.board, state.config)
		if mv.is_empty():
			break
		_collect(out, game.attempt_swap(mv["a"], mv["b"])["events"])
		if state.has_winner():
			break
		_collect(out, game.run_enemy_phase())
		if state.has_winner():
			break
		_collect(out, game.start_player_phase())
	# The final board and LINK/ICE are appended so a divergence in state that
	# somehow produced identical events would still be caught.
	out.append("final %d/%d turn %d winner %d" % [
		state.hp[Types.Side.PLAYER], state.hp[Types.Side.ENEMY], state.turn, state.winner,
	])
	return out


func _collect(out: Array, events: Array) -> void:
	for ev in events:
		out.append(TraceNorm.stringify(TraceNorm.normalize_event(ev)))


func _fire_ready(game: Game, state: GameState) -> void:
	_fire_ready_events(game, state)


func _fire_ready_events(game: Game, state: GameState) -> Array:
	var out: Array = []
	var units: Array = state.units[Types.Side.PLAYER]
	for i in units.size():
		if state.has_winner():
			break
		var u: GameState.UnitState = units[i]
		var prog := Content.program(u.program_id)
		if u.charge < int(prog["cost"]):
			continue
		out.append_array(game.fire_program(i, _target_for(state, prog["fn"])))
	if not state.has_winner():
		var deck := Content.deck(state.identity["deck_id"])
		if state.deck_charge >= int(deck["fn"]["cost"]):
			out.append_array(game.fire_deck_function(_target_for(state, deck["fn"])))
	return out


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

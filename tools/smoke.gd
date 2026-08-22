extends SceneTree

## Plays a complete battle headlessly, bot versus bot.
##
##   godot --headless -s res://tools/smoke.gd
##
## The first end-to-end exercise of the whole engine: content loading, board
## generation, Function activation, the enemy's dynamic Function phase,
## cascades, damage, charge routing, and the win condition.
##
## This is a SMOKE test, not a parity test. It answers "does a battle run to
## completion without erroring" — the differential harness answers whether it
## runs the same way the alpha does.

const BUILD: Array[String] = ["PRG_H_001", "PRG_H_002", "PRG_H_005", "PRG_H_006"]
const SAFETY := 2000


func _initialize() -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		printerr("content failed to load:")
		for e in loader.issues.errors().slice(0, 10):
			printerr("  %s" % DataIssues.format(e))
		quit(1)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()
	print("content ok — fingerprint %s" % result["fingerprint"])

	var failures := 0
	for spec in [["SYS_01", "HST_01", 1], ["SYS_02", "HST_03", 7], ["SYS_03", "HST_05", 42]]:
		if not _play(str(spec[0]), str(spec[1]), int(spec[2])):
			failures += 1

	print("")
	print("%s" % ("all battles completed" if failures == 0 else "%d battle(s) failed" % failures))
	quit(1 if failures > 0 else 0)


func _play(system_id: String, host_id: String, seed_value: int) -> bool:
	var state := Session.create_quick_match(system_id, host_id, seed_value, BUILD)
	var game := Game.new(state)

	var events := game.start_player_phase()
	var total_events := events.size()
	var safety := 0

	while not state.has_winner() and safety < SAFETY:
		safety += 1

		# Fire every charged Program, then the Deck Function, then commit the
		# turn-ending Sync. Mirrors the driver the differential harness will use.
		total_events += _fire_ready(game, state)

		var mv := Bot.pick_move(state.board, state.config)
		if mv.is_empty():
			printerr("  %s/%s seed %d — deadlock prevention failed" % [system_id, host_id, seed_value])
			return false

		var swap_result := game.attempt_swap(mv["a"], mv["b"])
		total_events += (swap_result["events"] as Array).size()
		if not swap_result["matched"]:
			printerr("  %s/%s seed %d — bot chose a non-matching swap" % [system_id, host_id, seed_value])
			return false

		if state.has_winner():
			break
		total_events += game.run_enemy_phase().size()
		if state.has_winner():
			break
		total_events += game.start_player_phase().size()

	if not state.has_winner():
		printerr("  %s/%s seed %d — battle did not finish in %d turns" % [system_id, host_id, seed_value, SAFETY])
		return false

	var winner := "Hacker" if state.winner == Types.Side.PLAYER else "System"
	print("  %s on %s seed %-5d → %s wins on turn %-3d  (LINK %d, ICE %d, %d events)" % [
		system_id, host_id, seed_value, winner, state.turn,
		maxi(0, state.hp[Types.Side.PLAYER]), maxi(0, state.hp[Types.Side.ENEMY]), total_events,
	])
	return true


## Fires every charged Program in build order, then the Deck Function.
##
## Targeted Functions get a deterministic policy: the enemy slot holding the
## most charge for a unit target, and the fullest row's leftmost Packet for a
## coordinate target.
func _fire_ready(game: Game, state: GameState) -> int:
	var n := 0
	var units: Array = state.units[Types.Side.PLAYER]
	for i in units.size():
		if state.has_winner():
			break
		var u: GameState.UnitState = units[i]
		var prog := Content.program(u.program_id)
		if u.charge < int(prog["cost"]):
			continue
		n += (game.fire_program(i, _target_for(state, prog["fn"])) as Array).size()

	if not state.has_winner():
		var deck := Content.deck(state.identity["deck_id"])
		if state.deck_charge >= int(deck["fn"]["cost"]):
			n += (game.fire_deck_function(_target_for(state, deck["fn"])) as Array).size()
	return n


func _target_for(state: GameState, fn: Dictionary):
	var plan: Array = fn["plan"]
	if plan.is_empty():
		return null
	match plan[0]["target"]:
		Types.TargetKind.UNIT:
			var best := 0
			var enemy: Array = state.units[Types.Side.ENEMY]
			for i in enemy.size():
				if enemy[i].charge > enemy[best].charge:
					best = i
			return {"kind": Types.TargetKind.UNIT, "idx": best}
		Types.TargetKind.PACKET:
			var best_p := Vector2i(-1, -1)
			var best_count := 0
			for y in Constants.BOARD_HEIGHT:
				var count := 0
				var first := -1
				for x in Constants.BOARD_WIDTH:
					if state.board[y][x] != null:
						count += 1
						if first < 0:
							first = x
				if count > best_count and first >= 0:
					best_count = count
					best_p = Vector2i(first, y)
			if best_p.x < 0:
				return null
			return {"kind": Types.TargetKind.PACKET, "p": best_p}
		_:
			return null

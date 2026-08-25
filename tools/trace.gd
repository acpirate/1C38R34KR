extends SceneTree

## Emits the normalized event stream of deterministic battles, for comparison
## against the alpha's `scripts/trace.ts`.
##
##   godot --headless -s res://tools/trace.gd -- --seeds 0-199
##   godot --headless -s res://tools/trace.gd -- --sys SYS_01 --host HST_02
##   godot --headless -s res://tools/trace.gd -- --full --seed 42
##
## THE DRIVER BELOW IS FROZEN (D-017). It reproduces `scripts/bot.ts` and
## `batch.ts`'s loop exactly, tie-break for tie-break, because those tie-breaks
## determine every event in the trace. A correct rules port paired with a driver
## that scans rows bottom-up diverges on essentially every battle — and presents
## as a rules bug.
##
## Every rule in the table below is load-bearing:
##
##   Programs considered in ascending build index
##   unit target   → enemy slot with the MOST charge, ties by LOWEST index
##   packet target → fullest row, ties by TOPMOST; LEFTMOST occupied cell in it
##   packet target resolving to nothing → does not fire, keeps its charge
##   loop order    → abilities, deck, move, swap, enemy phase, next player phase
##   safety cap    → 2000 iterations
##
## Consumes no RNG of its own.

const SAFETY := 2000

## Wall-clock and presentation state: no gameplay meaning, and cannot match
## across engines.
const EXCLUDED := [&"thinkTime", &"hintShown"]


func _initialize() -> void:
	var args := _parse_args()

	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		for e in loader.issues.errors().slice(0, 10):
			printerr(DataIssues.format(e))
		quit(1)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()

	for variant in args["variants"]:
		var settings := _settings_for(variant)
		if settings.is_empty():
			printerr("unknown variant %s" % variant)
			quit(1)
			return
		for sys in args["systems"]:
			for host in args["hosts"]:
				for seed_value in args["seeds"]:
					var t := _play(sys, host, variant, settings, seed_value, args["full"])
					if t.is_empty():
						quit(1)
						return
					if args["full"]:
						for line in (t["records"] as Array):
							print(line)
					else:
						print(JSON.stringify({
							"sys": t["sys"], "host": t["host"], "variant": t["variant"],
							"seed": t["seed"], "events": t["events"], "turns": t["turns"],
							"winner": t["winner"], "hash": t["hash"],
						}))
	quit(0)


func _settings_for(variant: String) -> Dictionary:
	var s := Constants.default_settings()
	match variant:
		"default":
			return s
		"reinforced":
			s["reinforced_connection"] = true
			return s
		"timer":
			s["enemy_matching"] = false
			return s
		"uncapped":
			s["max_cascade_steps"] = null
			return s
	return {}


# ---------------------------------------------------------------------------
# The frozen driver
# ---------------------------------------------------------------------------

## Fires every charged Program in the active build, in index order.
func _bot_fire_abilities(game: Game, state: GameState, feed: Callable) -> void:
	var units: Array = state.units[Types.Side.PLAYER]
	for i in units.size():
		if state.has_winner():
			return
		var u: GameState.UnitState = units[i]
		var prog := Content.program(u.program_id)
		if u.charge < int(prog["cost"]):
			continue
		match Game._function_target_kind(prog["fn"]):
			Types.TargetKind.UNIT:
				feed.call(game.fire_program(i, {"kind": Types.TargetKind.UNIT, "idx": _highest_charge_enemy(state)}))
			Types.TargetKind.PACKET:
				var p := _fullest_row_cell(state)
				if p.x >= 0:
					feed.call(game.fire_program(i, {"kind": Types.TargetKind.PACKET, "p": p}))
			_:
				feed.call(game.fire_program(i))


## D-018 — the Deck Function, which the frozen pass cannot reach: the Deck pool
## lives outside the unit list entirely. A sibling function rather than an edit
## to the frozen one.
func _bot_fire_deck(game: Game, state: GameState, feed: Callable) -> void:
	if state.has_winner():
		return
	var deck := Content.deck(state.identity["deck_id"])
	var fn: Dictionary = deck["fn"]
	if state.deck_charge < int(fn["cost"]):
		return
	match Game._function_target_kind(fn):
		Types.TargetKind.UNIT:
			feed.call(game.fire_deck_function({"kind": Types.TargetKind.UNIT, "idx": _highest_charge_enemy(state)}))
		Types.TargetKind.PACKET:
			var p := _fullest_row_cell(state)
			if p.x >= 0:
				feed.call(game.fire_deck_function({"kind": Types.TargetKind.PACKET, "p": p}))
		_:
			feed.call(game.fire_deck_function())


## The enemy slot holding the most charge. Ties resolve to the LOWEST index,
## matching `indexOf(Math.max(...))`.
func _highest_charge_enemy(state: GameState) -> int:
	var enemy: Array = state.units[Types.Side.ENEMY]
	var best := 0
	var best_charge: int = enemy[0].charge if not enemy.is_empty() else 0
	for i in enemy.size():
		if enemy[i].charge > best_charge:
			best_charge = enemy[i].charge
			best = i
	return best


## The fullest row's leftmost occupied cell. Strictly greater wins, so ties
## resolve to the TOPMOST row.
func _fullest_row_cell(state: GameState) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_count := 0
	for y in Constants.BOARD_HEIGHT:
		var count := 0
		var first := -1
		for x in Constants.BOARD_WIDTH:
			if state.board[y][x] != null:
				count += 1
				if first < 0:
					first = x
		if count <= best_count:
			continue
		if first < 0:
			continue
		best_count = count
		best = Vector2i(first, y)
	return best


# ---------------------------------------------------------------------------
# Battle execution
# ---------------------------------------------------------------------------

func _play(sys: String, host: String, variant: String, settings: Dictionary, seed_value: int, keep_records: bool) -> Dictionary:
	# Beta 0.3 §20 — a `BOS_*` id in `--sys` selects a BOSS opponent, mirroring
	# the alpha instrument exactly so the two remain comparable. Quick Match
	# itself stays System-only; this is the headless fixture route, matching the
	# alpha's `headlessBoss` (Alpha 0.7.0 §45).
	var state := (
		Session.create_boss_trace_battle(sys, host, seed_value, Session.default_build(), settings)
		if sys.begins_with("BOS_")
		else Session.create_quick_match(sys, host, seed_value, Session.default_build(), settings)
	)
	var game := Game.new(state)

	var ctx := {"count": 0, "records": [] as Array, "hash": HashingContext.new()}
	ctx["hash"].start(HashingContext.HASH_SHA256)

	var feed := func(events) -> void:
		for ev in (events as Array):
			var line := _record(ev)
			if line == "":
				continue
			ctx["hash"].update((line + "\n").to_utf8_buffer())
			ctx["count"] += 1
			if keep_records:
				(ctx["records"] as Array).append(line)

	feed.call(game.start_player_phase())
	var safety := 0
	while not state.has_winner() and safety < SAFETY:
		safety += 1
		_bot_fire_abilities(game, state, feed)
		if state.has_winner():
			break
		_bot_fire_deck(game, state, feed)
		if state.has_winner():
			break

		var mv := Bot.pick_move(state.board, state.config)
		if mv.is_empty():
			printerr("deadlock prevention failed (%s/%s/%s seed %d)" % [sys, host, variant, seed_value])
			return {}
		feed.call(game.attempt_swap(mv["a"], mv["b"])["events"])
		if not state.has_winner():
			feed.call(game.run_enemy_phase())
		if not state.has_winner():
			feed.call(game.start_player_phase())

	if not state.has_winner():
		printerr("battle did not finish (%s/%s/%s seed %d)" % [sys, host, variant, seed_value])
		return {}

	var digest: PackedByteArray = ctx["hash"].finish()
	return {
		"sys": sys, "host": host, "variant": variant, "seed": seed_value,
		"events": ctx["count"], "turns": state.turn,
		"winner": Types.SIDE_NAMES[state.winner],
		"hash": digest.hex_encode().substr(0, 16),
		"records": ctx["records"],
	}


# ---------------------------------------------------------------------------
# Normalization
# ---------------------------------------------------------------------------

## One canonical line per event, or "" for an excluded one.
##
## Enums serialize as the alpha's STRING forms, because the alpha is the
## reference and its spelling is what the comparison is against.
func _record(ev: Dictionary) -> String:
	var t := StringName(ev["t"])
	if EXCLUDED.has(t):
		return ""
	return TraceNorm.stringify(TraceNorm.normalize_event(ev))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

func _parse_args() -> Dictionary:
	var raw := OS.get_cmdline_user_args()
	var opts := {}
	var full := false
	var i := 0
	while i < raw.size():
		var a: String = raw[i]
		if a == "--full":
			full = true
			i += 1
			continue
		if a.begins_with("--") and i + 1 < raw.size():
			opts[a.substr(2)] = raw[i + 1]
			i += 2
			continue
		i += 1

	var seed_spec: String = opts.get("seeds", opts.get("seed", "0"))
	return {
		"full": full,
		"seeds": _parse_seeds(seed_spec),
		"systems": str(opts.get("sys", "SYS_01,SYS_02,SYS_03")).split(","),
		"hosts": str(opts.get("host", "HST_01,HST_02,HST_03,HST_04,HST_05")).split(","),
		"variants": str(opts.get("variant", "default")).split(","),
	}


func _parse_seeds(spec: String) -> Array[int]:
	var out: Array[int] = []
	if spec.contains("-"):
		var parts := spec.split("-")
		for v in range(int(parts[0]), int(parts[1]) + 1):
			out.append(v)
		return out
	for part in spec.split(","):
		out.append(int(part))
	return out

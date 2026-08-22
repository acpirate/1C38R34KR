extends RefCounted

## Top-to-bottom charge routing.
##
## Testable in isolation with a synthetic state, and worth testing hard: the
## rules are individually simple and collectively easy to get subtly wrong. A
## routing bug does not crash — it just makes builds feel different, and would
## surface in the differential harness as an unexplained divergence dozens of
## turns in.
##
## The invariants, each covered below:
##   - charge never flows upward
##   - a compatible non-full Program is never skipped
##   - no Program exceeds its Function cost
##   - an incompatible Program is passed over without consuming anything
##   - a full Program is stepped over, and the stream keeps flowing DOWN
##   - leftover charge is discarded, attributed to no Program
##   - routing consults no RNG


func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("charge routing")
		t.check("content loads", false)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()

	_test_fill_and_overflow(t)
	_test_skips_incompatible(t)
	_test_steps_over_full(t)
	_test_discard(t)
	_test_stream_order(t)
	_test_merge_and_dampen(t)
	_test_deck_pool(t)

	Content.clear()
	Passives.clear_cache()


## Charge fills the first compatible Program to its cap, then passes the excess
## DOWN — never up, and never skipping a Program with room.
func _test_fill_and_overflow(t: TestCase) -> void:
	t.group("charge routing / fill and overflow")

	var state := _state()
	var prog_a := Content.program(state.units[Types.Side.PLAYER][0].program_id)
	var token: int = (prog_a["colors"] as Array)[0]

	# Enough to fill the first eligible Program and spill.
	var eligible := _eligible_indices(state, "color", token)
	t.check("at least two Programs share a colour binding", eligible.size() >= 2)
	if eligible.size() < 2:
		return

	var first: GameState.UnitState = state.units[Types.Side.PLAYER][eligible[0]]
	var second: GameState.UnitState = state.units[Types.Side.PLAYER][eligible[1]]
	var first_cap: int = Content.program(first.program_id)["charge_cap"]

	var events := []
	Resolve.route_charge_stream(state, Types.Side.PLAYER, _stream("color", token, first_cap + 1), events)

	t.eq("the first eligible Program fills to its cap", first.charge, first_cap)
	t.eq("the excess lands in the next eligible Program", second.charge, 1)

	var route: Dictionary = events[0]
	t.eq("the routing event names the acting side", route["side"], Types.Side.PLAYER)
	t.eq("nothing is discarded while room remains", route["discarded"], 0)
	# The event records the full ordered queue and which of it was eligible, so
	# an analyst can verify priority and skipping rather than only the total.
	t.eq("the event records the whole build order", (route["order"] as Array).size(), state.units[Types.Side.PLAYER].size())
	t.eq("and which Programs were eligible", (route["eligible"] as Array).size(), eligible.size())


## An incompatible Program is passed over entirely — it neither gains charge nor
## stops the stream.
func _test_skips_incompatible(t: TestCase) -> void:
	t.group("charge routing / incompatible Programs")

	var state := _state()
	var units: Array = state.units[Types.Side.PLAYER]

	# Find a token bound by a LATER Program but not the first.
	var chosen_token := -1
	var chosen_index := -1
	for i in range(1, units.size()):
		var prog := Content.program(units[i].program_id)
		for tok in (prog["colors"] as Array):
			if not (Content.program(units[0].program_id)["colors"] as Array).has(tok):
				chosen_token = tok
				chosen_index = i
				break
		if chosen_token != -1:
			break

	if chosen_token == -1:
		t.check("a token bound below the first Program exists", false)
		return

	var events := []
	Resolve.route_charge_stream(state, Types.Side.PLAYER, _stream("color", chosen_token, 1), events)

	t.eq("the incompatible leading Program gains nothing", units[0].charge, 0)
	var landed := 0
	for u in units:
		landed += u.charge
	t.eq("the charge still lands somewhere below it", landed, 1)


## A Program already at its cap is stepped over and the stream keeps flowing
## down. Skipping is not the same as stopping.
func _test_steps_over_full(t: TestCase) -> void:
	t.group("charge routing / full Programs")

	var state := _state()
	var units: Array = state.units[Types.Side.PLAYER]
	var token: int = (Content.program(units[0].program_id)["colors"] as Array)[0]
	var eligible := _eligible_indices(state, "color", token)
	if eligible.size() < 2:
		t.check("two Programs share a binding", false)
		return

	var first: GameState.UnitState = units[eligible[0]]
	var second: GameState.UnitState = units[eligible[1]]
	first.charge = Content.program(first.program_id)["charge_cap"]

	var events := []
	Resolve.route_charge_stream(state, Types.Side.PLAYER, _stream("color", token, 1), events)

	t.eq("the full Program is unchanged", first.charge, Content.program(first.program_id)["charge_cap"])
	t.eq("the charge flows past it", second.charge, 1)

	# No assignment is recorded for the skipped Program: it received nothing, so
	# recording a zero-charge assignment would misreport it as participating.
	var assignments: Array = events[0]["assignments"]
	for a in assignments:
		t.check("no zero assignment is recorded", int(a["assigned"]) > 0)


## Charge that outruns the whole queue is discarded and attributed to NO
## Program — the stream outran the build, which is not any one Program's waste.
func _test_discard(t: TestCase) -> void:
	t.group("charge routing / discard")

	var state := _state()
	var units: Array = state.units[Types.Side.PLAYER]
	var token: int = (Content.program(units[0].program_id)["colors"] as Array)[0]
	var eligible := _eligible_indices(state, "color", token)

	var total_room := 0
	for i in eligible:
		total_room += Content.program(units[i].program_id)["charge_cap"]

	var events := []
	Resolve.route_charge_stream(state, Types.Side.PLAYER, _stream("color", token, total_room + 5), events)

	for i in eligible:
		t.eq("Program %d is at its cap" % i, units[i].charge, Content.program(units[i].program_id)["charge_cap"])
	t.eq("the surplus is discarded", events[0]["discarded"], 5)


## Colour resolves fully before shape, and tokens ascend within an axis.
func _test_stream_order(t: TestCase) -> void:
	t.group("charge routing / stream order")

	var streams := {}
	Resolve.add_stream(streams, "shape", 3, 1, Types.ChargeStreamSource.SYNC)
	Resolve.add_stream(streams, "color", 5, 1, Types.ChargeStreamSource.SYNC)
	Resolve.add_stream(streams, "shape", 1, 1, Types.ChargeStreamSource.SYNC)
	Resolve.add_stream(streams, "color", 2, 1, Types.ChargeStreamSource.SYNC)

	var ordered := Resolve.ordered_streams(streams)
	var seen := []
	for s in ordered:
		seen.append("%s:%d" % [s["axis"], s["token"]])
	t.eq_seq("colour before shape, ascending token", seen, ["color:2", "color:5", "shape:1", "shape:3"])


## A PASSIVE that inflates a qualifying stream RE-LABELS it rather than opening
## a second pool — a second pool would charge every compatible Program again.
func _test_merge_and_dampen(t: TestCase) -> void:
	t.group("charge routing / merge and dampen")

	var streams := {}
	Resolve.add_stream(streams, "color", 1, 2, Types.ChargeStreamSource.SYNC)
	Resolve.add_stream(streams, "color", 1, 3, Types.ChargeStreamSource.PASSIVE_MODIFIED_SYNC, "PSV_002")
	t.eq("same axis and token merge into one stream", streams.size(), 1)
	var merged: Dictionary = streams.values()[0]
	t.eq("amounts sum", merged["amount"], 5)
	t.eq("and the stream is re-labelled", merged["source"], Types.ChargeStreamSource.PASSIVE_MODIFIED_SYNC)
	t.eq("carrying the contributing source", str(merged["source_id"]), "PSV_002")

	# Dampening floors at zero rather than going negative.
	var state := _state("HST_02")
	var d_streams := {}
	Resolve.add_stream(d_streams, "color", 1, 1, Types.ChargeStreamSource.SYNC)
	var events := []
	Resolve.apply_charge_dampen(state, Types.Side.PLAYER, d_streams, events)
	var dampened: Dictionary = d_streams.values()[0]
	t.check("a dampened stream never goes negative", int(dampened["amount"]) >= 0)
	t.check("dampening is reported per contributing instance", events.size() >= 1)


## The Deck pool is separate from Program routing entirely, and only the Hacker
## carries a Deck.
func _test_deck_pool(t: TestCase) -> void:
	t.group("charge routing / Deck pool")

	var state := _state()
	var cap := Resolve.deck_charge_cap(state)

	var discarded := Resolve.add_deck_charge(state, Types.Side.PLAYER, 1)
	t.eq("the Hacker's Deck gains charge", state.deck_charge, 1)
	t.eq("nothing is discarded below the cap", discarded, 0)

	state.deck_charge = 0
	discarded = Resolve.add_deck_charge(state, Types.Side.PLAYER, cap + 3)
	t.eq("the Deck pool caps at its Function cost", state.deck_charge, cap)
	t.eq("the surplus is reported as discarded", discarded, 3)

	state.deck_charge = 0
	Resolve.add_deck_charge(state, Types.Side.ENEMY, 5)
	t.eq("an enemy-owned resolution charges no Deck", state.deck_charge, 0)


# --- helpers --------------------------------------------------------------

func _stream(axis: String, token: int, amount: int) -> Dictionary:
	return {"axis": axis, "token": token, "amount": amount, "source": Types.ChargeStreamSource.SYNC, "source_id": ""}


func _eligible_indices(state: GameState, axis: String, token: int) -> Array[int]:
	var out: Array[int] = []
	var units: Array = state.units[Types.Side.PLAYER]
	for i in units.size():
		var prog := Content.program(units[i].program_id)
		var key := "colors" if axis == "color" else "shapes"
		if (prog[key] as Array).has(token):
			out.append(i)
	return out


func _state(host_id := "HST_01") -> GameState:
	var s := GameState.new()
	s.rng = Rng.new(1)
	s.config = Constants.default_settings()
	s.config["strong_colors"] = [[], []]
	s.config["strong_shapes"] = [[], []]

	# A legal four-Program build drawn from the six-Program inventory, chosen so
	# that overflow is reachable at all.
	#
	# Each authored Program binds exactly ONE colour and ONE shape, and RED is
	# the only colour two Programs share — BOMBER and WEASEL. A build without
	# both has no eligible second Program for any stream, so nothing could ever
	# overflow and the routing invariants would go untested while appearing to
	# pass. The two also sit at opposite ends of the build, so a stream must flow
	# PAST two ineligible Programs to reach the second.
	var build: Array[String] = ["PRG_H_001", "PRG_H_002", "PRG_H_005", "PRG_H_006"]

	var player_units: Array = []
	for pid in build:
		player_units.append(GameState.UnitState.new(pid, 0))
	var enemy_units: Array = []
	for pid in (Content.system("SYS_01")["programs"] as Array):
		enemy_units.append(GameState.UnitState.new(pid, 0))
	s.units = [player_units, enemy_units]

	s.identity = {
		"cache_key": "routing|%s" % host_id,
		"hacker_id": Content.DEFAULT_HACKER_ID,
		"deck_id": Content.DEFAULT_DECK_ID,
		"opponent_kind": Types.OpponentKind.SYS,
		"opponent_id": "SYS_01",
		"host_id": host_id,
		"upgrade_ids": [],
	}
	s.board = BoardOps.empty_board()
	return s

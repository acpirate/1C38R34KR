extends RefCounted

## The three Bosses added in beta 0.4, and the Boss Attack mode.
##
## Kept out of `test_boss.gd` deliberately: that file is ODANSHAY's regression
## and its value is that it has not changed. These Bosses have no alpha
## counterpart at all (§16), so this file IS their oracle — every assertion here
## is the authorization read back, not a comparison against something else.
##
## Fixtures build boards by hand rather than playing to a position. A Capacitor
## count of four is one line here and an unreachable accident otherwise.

const SHIELD_MAGNITUDE := 40


func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("boss 0.4")
		t.check("content loads", false)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()

	_test_rahndahl_scaling(t)
	_test_rahndahl_shield(t)
	_test_rahndahl_order(t)
	_test_rahndahl_lethal(t)
	_test_rahndahl_placement_pools(t)
	_test_rahndahl_fizzle(t)
	_test_capacitor_is_inert(t)

	_test_nehbocyet_row_clear(t)
	_test_nehbocyet_placement_pools(t)
	_test_nehbocyet_fizzle(t)
	_test_logic_bomb_invariant(t)
	_test_logic_bomb_multiple(t)
	_test_logic_bomb_other_movement_source(t)

	_test_echofall_cadence(t)
	_test_echofall_axis_distribution(t)
	_test_echofall_identity_untouched(t)
	_test_echofall_valid_move(t)
	_test_echofall_invalid_move(t)
	_test_echofall_no_second_punishment(t)
	_test_echofall_lethal(t)
	_test_echofall_save_resume(t)

	_test_boss_attack_construction(t)
	_test_boss_attack_no_ladder(t)
	_test_boss_attack_roster(t)

	Content.clear()
	Passives.clear_cache()


# ---------------------------------------------------------------------------
# BOS_02 RAHNDAHL
# ---------------------------------------------------------------------------

## §17.3 — the discharge is `2^n` for the Capacitors present BEFORE the tick.
func _test_rahndahl_scaling(t: TestCase) -> void:
	t.group("RAHNDAHL / discharge scales as 2^n")
	for n in [0, 1, 2, 3, 4, 6]:
		var s := _boss_state(Content.BOSS_RAHNDAHL)
		_seed_specials(s, n, Tile.Special.Type.CAPACITOR, Types.Side.ENEMY)
		var before: int = s.hp[Types.Side.PLAYER]
		var g := Game.new(s)
		var events: Array = []
		Boss.rahndahl_start(g, events)
		t.eq("%d Capacitors deal %d" % [n, 1 << n], before - s.hp[Types.Side.PLAYER], 1 << n)


## §6.2 — an ordinary damage instance, so Shield reduces it like anything else.
func _test_rahndahl_shield(t: TestCase) -> void:
	t.group("RAHNDAHL / Shield reduces the tick")
	var s := _boss_state(Content.BOSS_RAHNDAHL)
	_seed_specials(s, 5, Tile.Special.Type.CAPACITOR, Types.Side.ENEMY)
	# A Hacker-owned Shield on the Hacker's own side of the ledger.
	_give_special(s, _nth_standard(s, 40), Tile.Special.Type.SHIELD, Types.Side.PLAYER, SHIELD_MAGNITUDE)

	var shield: int = Resolve.shield_value(s, Types.Side.PLAYER)
	t.check("the fixture actually carries Shield", shield > 0)

	var before: int = s.hp[Types.Side.PLAYER]
	var g := Game.new(s)
	Boss.rahndahl_start(g, [])
	var dealt: int = before - s.hp[Types.Side.PLAYER]
	t.eq("32 damage arrives reduced by the Shield", dealt, maxi(0, 32 - shield))


## §6.1 — the count is taken BEFORE placement, so this phase's new Capacitor
## first contributes on the next phase.
func _test_rahndahl_order(t: TestCase) -> void:
	t.group("RAHNDAHL / tick precedes placement")
	var s := _boss_state(Content.BOSS_RAHNDAHL)
	var before: int = s.hp[Types.Side.PLAYER]
	var g := Game.new(s)
	var events: Array = []
	Boss.rahndahl_start(g, events)

	t.eq("an empty board still ticks for 1", before - s.hp[Types.Side.PLAYER], 1)
	t.eq("and one Capacitor is now installed", Boss.capacitor_count(s), 1)

	var before2: int = s.hp[Types.Side.PLAYER]
	Boss.rahndahl_start(g, [])
	t.eq("so the SECOND phase ticks for 2", before2 - s.hp[Types.Side.PLAYER], 2)


## §13 — a lethal discharge ends the sequence: no Capacitor is placed.
func _test_rahndahl_lethal(t: TestCase) -> void:
	t.group("RAHNDAHL / lethal tick places nothing")
	var s := _boss_state(Content.BOSS_RAHNDAHL)
	_seed_specials(s, 8, Tile.Special.Type.CAPACITOR, Types.Side.ENEMY)
	s.hp[Types.Side.PLAYER] = 10  # 2^8 = 256 is comfortably lethal

	var g := Game.new(s)
	var events: Array = []
	Boss.rahndahl_start(g, events)

	t.check("the Hacker is defeated", s.has_winner())
	t.eq("the Capacitor count is unchanged", Boss.capacitor_count(s), 8)
	t.eq("and no placement was recorded", _of_kind(events, "CAPACITOR_PLACED").size(), 0)


## §6.3 — the two pools, and what may be overwritten from each.
func _test_rahndahl_placement_pools(t: TestCase) -> void:
	t.group("RAHNDAHL / placement pools")

	# A Hacker special does NOT push its Packet into the fallback pool, so a
	# board whose only specials are the Hacker's still places into the first.
	var s := _boss_state(Content.BOSS_RAHNDAHL)
	var hacker_cell := _nth_standard(s, 0)
	_give_special(s, hacker_cell, Tile.Special.Type.BOMB, Types.Side.PLAYER)
	var g := Game.new(s)
	Boss.rahndahl_start(g, [])
	t.eq("one Capacitor placed", Boss.capacitor_count(s), 1)

	# Every eligible Packet carries a BOSS special, so the fallback pool is the
	# only one left and a Boss special is overwritten.
	var s2 := _boss_state(Content.BOSS_RAHNDAHL)
	var eligible := Boss.capacitor_targets(s2)
	for p in eligible:
		_give_special(s2, p, Tile.Special.Type.OVERRIDE, Types.Side.ENEMY)
	var overrides_before: int = _count_type(s2, Tile.Special.Type.OVERRIDE)
	var g2 := Game.new(s2)
	Boss.rahndahl_start(g2, [])
	t.eq("a Capacitor still lands", Boss.capacitor_count(s2), 1)
	t.eq(
		"by replacing exactly one Boss special",
		_count_type(s2, Tile.Special.Type.OVERRIDE), overrides_before - 1
	)

	# With ONE Packet free of Boss specials, that is the one chosen — every
	# time, whatever the seed, because the preferred pool has a single member.
	for seed_value in [1, 2, 3, 9, 41]:
		var s3 := _boss_state(Content.BOSS_RAHNDAHL, seed_value)
		var free_cell := _nth_standard(s3, 3)
		for p in Boss.capacitor_targets(s3):
			if p != free_cell:
				_give_special(s3, p, Tile.Special.Type.OVERRIDE, Types.Side.ENEMY)
		var g3 := Game.new(s3)
		Boss.rahndahl_start(g3, [])
		var tile: Tile = s3.board[free_cell.y][free_cell.x]
		t.check(
			"seed %d prefers the Packet with no Boss special" % seed_value,
			tile.has_special() and tile.special.type == Tile.Special.Type.CAPACITOR
		)


## §6.3 — no eligible non-neutral Packet at all means the placement fizzles.
func _test_rahndahl_fizzle(t: TestCase) -> void:
	t.group("RAHNDAHL / no eligible Packet fizzles")
	var s := _boss_state(Content.BOSS_RAHNDAHL)
	_make_all_neutral(s)
	var g := Game.new(s)
	var events: Array = []
	Boss.rahndahl_start(g, events)
	t.eq("nothing was placed", Boss.capacitor_count(s), 0)
	t.eq("and the fizzle is recorded", _of_kind(events, "CAPACITOR_FIZZLED").size(), 1)
	t.check("the battle continues", not s.has_winner())


## §6.3 — a Capacitor has no on-destroy effect; removing its carrier removes it.
func _test_capacitor_is_inert(t: TestCase) -> void:
	t.group("RAHNDAHL / a destroyed Capacitor does nothing")
	var s := _boss_state(Content.BOSS_RAHNDAHL)
	var cell := _nth_standard(s, 5)
	_give_special(s, cell, Tile.Special.Type.CAPACITOR, Types.Side.ENEMY)

	var hp_before: int = s.hp[Types.Side.PLAYER]
	var enemy_hp_before: int = s.hp[Types.Side.ENEMY]
	var charge_before: int = _total_charge(s)

	s.board[cell.y][cell.x] = null
	var events: Array = []
	Resolve.apply_gravity_and_refill(s, events)

	t.eq("no damage to the Hacker", s.hp[Types.Side.PLAYER], hp_before)
	t.eq("no damage to the Boss", s.hp[Types.Side.ENEMY], enemy_hp_before)
	t.eq("no charge awarded", _total_charge(s), charge_before)
	t.eq("and the Capacitor is gone with it", Boss.capacitor_count(s), 0)


# ---------------------------------------------------------------------------
# BOS_03 NEHBOCYET
# ---------------------------------------------------------------------------

## §7.1 — the row is REMOVED, inertly, and the board refills.
func _test_nehbocyet_row_clear(t: TestCase) -> void:
	t.group("NEHBOCYET / the bottom row is cleared inertly")
	var s := _boss_state(Content.BOSS_NEHBOCYET)
	var y := Constants.BOARD_HEIGHT - 1

	# Overlays on the doomed row, one of each ownership. Neither may activate.
	_give_special(s, Vector2i(0, y), Tile.Special.Type.BOMB, Types.Side.PLAYER)
	_give_special(s, Vector2i(1, y), Tile.Special.Type.OVERRIDE, Types.Side.ENEMY)

	var ids_before := _row_ids(s, y)
	var hp_before: int = s.hp[Types.Side.PLAYER]
	var enemy_before: int = s.hp[Types.Side.ENEMY]
	var charge_before: int = _total_charge(s)

	var g := Game.new(s)
	var events: Array = []
	Boss.nehbocyet_start(g, events)

	t.eq("the clear is recorded", _of_kind(events, "BOTTOM_ROW_CLEARED").size(), 1)
	t.check("every original bottom-row Packet is gone", _row_ids(s, y) != ids_before)
	t.eq("the row is full again after the refill", _row_filled(s, y), Constants.BOARD_WIDTH)

	# The clear itself is inert: the Bomb sitting in the doomed row was cleared,
	# not destroyed, so it never detonated. Anything the REFILL then Syncs is
	# ordinary and may legitimately deal damage, which is why the assertion is
	# about the detonation rather than about the Hacker's LINK.
	t.eq("the cleared Bomb did not detonate", _of_kind_evt(events, Types.EVT.DETONATE).size(), 0)
	t.check("the Boss dealt itself no damage clearing its own row", s.hp[Types.Side.ENEMY] == enemy_before)
	t.check("and the Hacker was not healed by it", s.hp[Types.Side.PLAYER] <= hp_before)
	t.check("charge accounting stayed coherent", _total_charge(s) >= charge_before)


## §7.2 — top row only, preferred pool first, fallback may overwrite a Boss
## special.
func _test_nehbocyet_placement_pools(t: TestCase) -> void:
	t.group("NEHBOCYET / Logic Bomb placement pools")

	var s := _boss_state(Content.BOSS_NEHBOCYET)
	var g := Game.new(s)
	Boss.nehbocyet_start(g, [])
	var placed := _cells_of_type(s, Tile.Special.Type.LOGIC_BOMB)
	t.eq("exactly one Logic Bomb is armed", placed.size(), 1)
	t.eq("in the top row", placed[0].y, 0)

	# Only one top-row Packet is free of Boss specials: it must be chosen.
	for seed_value in [4, 5, 6, 17]:
		var s2 := _boss_state(Content.BOSS_NEHBOCYET, seed_value)
		_make_top_row_standard(s2)
		var free_cell := Vector2i(3, 0)
		for x in Constants.BOARD_WIDTH:
			if x != free_cell.x:
				_give_special(s2, Vector2i(x, 0), Tile.Special.Type.OVERRIDE, Types.Side.ENEMY)
		# Place directly rather than through the row clear, so the board the
		# pools are computed from is exactly the one set up here.
		var cell := Boss._place_one_special(
			s2, Boss.logic_bomb_targets(s2), Tile.Special.Type.LOGIC_BOMB, []
		)
		t.eq("seed %d takes the only Boss-special-free Packet" % seed_value, cell, free_cell)

	# Every top-row Packet carries a Boss special: the fallback overwrites one.
	var s3 := _boss_state(Content.BOSS_NEHBOCYET)
	_make_top_row_standard(s3)
	for x in Constants.BOARD_WIDTH:
		_give_special(s3, Vector2i(x, 0), Tile.Special.Type.OVERRIDE, Types.Side.ENEMY)
	var cell3 := Boss._place_one_special(
		s3, Boss.logic_bomb_targets(s3), Tile.Special.Type.LOGIC_BOMB, []
	)
	t.check("a Logic Bomb still lands", cell3.x >= 0)
	t.eq("replacing one Override", _count_type(s3, Tile.Special.Type.OVERRIDE), Constants.BOARD_WIDTH - 1)


## §7.2 — no valid top-row target fizzles rather than forcing a placement.
func _test_nehbocyet_fizzle(t: TestCase) -> void:
	t.group("NEHBOCYET / no top-row target fizzles")
	var s := _boss_state(Content.BOSS_NEHBOCYET)
	for x in Constants.BOARD_WIDTH:
		_make_neutral(s, Vector2i(x, 0))
	var cell := Boss._place_one_special(
		s, Boss.logic_bomb_targets(s), Tile.Special.Type.LOGIC_BOMB, []
	)
	t.eq("placement fizzled", cell, Vector2i(-1, -1))
	t.eq("and nothing was armed", _count_type(s, Tile.Special.Type.LOGIC_BOMB), 0)


## §7.3/§7.4 — THE invariant: a settled board may not retain a Logic Bomb in the
## bottom row. The carrier goes, FNC_021 fires once, and nothing else does.
func _test_logic_bomb_invariant(t: TestCase) -> void:
	t.group("NEHBOCYET / a settled bottom-row bomb cannot remain")
	var s := _boss_state(Content.BOSS_NEHBOCYET)
	var y := Constants.BOARD_HEIGHT - 1
	var cell := Vector2i(2, y)
	_make_standard(s, cell)
	_give_special(s, cell, Tile.Special.Type.LOGIC_BOMB, Types.Side.ENEMY)

	var hp_before: int = s.hp[Types.Side.PLAYER]
	var g := Game.new(s)
	var events: Array = []
	Boss.resolve_settled_bombs(g, events)

	t.eq("no Logic Bomb survives in the bottom row", Boss.settled_bombs(s).size(), 0)
	t.eq("none survives anywhere", _count_type(s, Tile.Special.Type.LOGIC_BOMB), 0)
	t.eq("the trigger is recorded once", _of_kind(events, "LOGIC_BOMB_TRIGGERED").size(), 1)
	t.eq(
		"and the Hacker took exactly FNC_021's authored damage",
		hp_before - s.hp[Types.Side.PLAYER], _authored_damage(t, Content.FN_LOGICBOMBEXPLODE)
	)


## §7.4 — several bombs qualifying from ONE settle each fire once.
func _test_logic_bomb_multiple(t: TestCase) -> void:
	t.group("NEHBOCYET / every qualifying bomb fires once")
	var s := _boss_state(Content.BOSS_NEHBOCYET)
	var y := Constants.BOARD_HEIGHT - 1
	var cells := [Vector2i(1, y), Vector2i(4, y), Vector2i(6, y)]
	for c in cells:
		_make_standard(s, c)
		_give_special(s, c, Tile.Special.Type.LOGIC_BOMB, Types.Side.ENEMY)

	var hp_before: int = s.hp[Types.Side.PLAYER]
	var g := Game.new(s)
	var events: Array = []
	Boss.resolve_settled_bombs(g, events)

	var per_bomb := _authored_damage(t, Content.FN_LOGICBOMBEXPLODE)
	t.check(
		"three bombs deal at least three times FNC_021",
		hp_before - s.hp[Types.Side.PLAYER] >= per_bomb * 3
	)
	t.eq("the board is stable", Boss.settled_bombs(s).size(), 0)
	# The chain may find further bombs after the settle; what must not happen is
	# the loop failing to terminate or leaving one behind.
	t.check("the chain terminated", not s.bomb_chain_active)


## §7.3 — the rule is source-independent. Proven through a movement source that
## is NOT the Boss row clear: an ordinary Hacker Sync.
func _test_logic_bomb_other_movement_source(t: TestCase) -> void:
	t.group("NEHBOCYET / the trigger is source-independent")
	var s := _boss_state(Content.BOSS_NEHBOCYET)
	var y := Constants.BOARD_HEIGHT - 1

	# A bomb one row above the bottom, with the bottom-row Packet beneath it
	# removed: any settle drops it into the bottom row.
	var cell := Vector2i(3, y - 1)
	_make_standard(s, cell)
	_give_special(s, cell, Tile.Special.Type.LOGIC_BOMB, Types.Side.ENEMY)
	s.board[y][3] = null

	var hp_before: int = s.hp[Types.Side.PLAYER]
	var g := Game.new(s)
	var events: Array = []
	# Gravity alone, through the ordinary settle path rather than the Boss's.
	Resolve.settle_after_effect(s, Types.Side.PLAYER, Types.DamageSource.MATCH, "", events, g)

	t.eq("the fallen bomb did not survive the settle", Boss.settled_bombs(s).size(), 0)
	t.check(
		"and it detonated",
		hp_before - s.hp[Types.Side.PLAYER] >= _authored_damage(t, Content.FN_LOGICBOMBEXPLODE)
	)


# ---------------------------------------------------------------------------
# BOS_04 ECHOFALL
# ---------------------------------------------------------------------------

## §8.1 — conceal on Boss phases 1, 3, 5; phases 2 and 4 add nothing new.
func _test_echofall_cadence(t: TestCase) -> void:
	t.group("ECHOFALL / conceals on alternate phases")
	var s := _boss_state(Content.BOSS_ECHOFALL)
	var g := Game.new(s)

	for phase in range(1, 7):
		s.boss_phase = phase - 1
		s.hidden_axis = -1
		var events: Array = []
		Boss.start_of_turn(g, events)
		var concealed := Boss.is_concealed(s)
		if phase % 2 == 1:
			t.check("phase %d conceals" % phase, concealed)
		else:
			t.check("phase %d does not" % phase, not concealed)


## §17.5 — the axis comes from the deterministic battle RNG, and BOTH values are
## reachable. A rule that always picked one would pass every other assertion.
func _test_echofall_axis_distribution(t: TestCase) -> void:
	t.group("ECHOFALL / both axes are reachable and deterministic")
	var seen := {}
	for seed_value in range(40):
		var s := _boss_state(Content.BOSS_ECHOFALL, seed_value)
		var g := Game.new(s)
		Boss.start_of_turn(g, [])
		seen[s.hidden_axis] = true
	t.check("COLOR occurs", seen.has(Types.ConcealAxis.COLOR))
	t.check("SHAPE occurs", seen.has(Types.ConcealAxis.SHAPE))

	# Same seed, same axis — the choice is on the gameplay stream, not chance.
	var a := _boss_state(Content.BOSS_ECHOFALL, 12)
	var b := _boss_state(Content.BOSS_ECHOFALL, 12)
	Boss.start_of_turn(Game.new(a), [])
	Boss.start_of_turn(Game.new(b), [])
	t.eq("the same seed hides the same axis", a.hidden_axis, b.hidden_axis)


## §8.2 — concealment changes presentation and NOTHING about the Packets.
func _test_echofall_identity_untouched(t: TestCase) -> void:
	t.group("ECHOFALL / Packet identity is untouched")
	var s := _boss_state(Content.BOSS_ECHOFALL)
	var identity_before: Array = _board_identity(s)
	var specials_before: Array = _all_specials(s)

	var g := Game.new(s)
	Boss.start_of_turn(g, [])
	t.check("an axis is hidden", Boss.is_concealed(s))
	t.eq_seq("every colour and shape is unchanged", _board_identity(s), identity_before)
	t.eq_seq("and every overlay is still present", _all_specials(s), specials_before)

	# Matching still sees the real board.
	var real: int = MatchFinder.detect(s.board).size()
	s.hidden_axis = -1
	t.eq("the match finder is indifferent to concealment", MatchFinder.detect(s.board).size(), real)


## §8.4 — a VALID move reveals and resolves, with no BRAINSCRAMBLE.
func _test_echofall_valid_move(t: TestCase) -> void:
	t.group("ECHOFALL / a valid concealed move is not punished")
	var s := _boss_state(Content.BOSS_ECHOFALL)
	s.hidden_axis = Types.ConcealAxis.COLOR
	s.phase = Types.Phase.PLAYER_PRE

	var mv := _find_valid_swap(s)
	if mv.is_empty():
		t.check("the fixture offers a valid swap", false)
		return

	var hp_before: int = s.hp[Types.Side.PLAYER]
	var g := Game.new(s)
	var out := g.attempt_swap(mv["a"], mv["b"])

	t.check("the Sync resolved", bool(out["matched"]))
	t.check("the board is revealed", not Boss.is_concealed(s))
	t.check(
		"the Hacker took no BRAINSCRAMBLE damage",
		hp_before - s.hp[Types.Side.PLAYER] < _authored_damage(t, Content.FN_BRAINSCRAMBLE)
			or _of_kind(out["events"], "BRAINSCRAMBLE").is_empty()
	)
	t.eq("no BRAINSCRAMBLE was recorded", _of_kind(out["events"], "BRAINSCRAMBLE").size(), 0)


## §8.4 — an INVALID move commits nothing, fires FNC_022 once, and reveals.
func _test_echofall_invalid_move(t: TestCase) -> void:
	t.group("ECHOFALL / an invalid concealed move is punished once")
	var s := _boss_state(Content.BOSS_ECHOFALL)
	s.hidden_axis = Types.ConcealAxis.SHAPE
	s.phase = Types.Phase.PLAYER_PRE

	var mv := _find_invalid_swap(s)
	if mv.is_empty():
		t.check("the fixture offers an invalid swap", false)
		return

	var identity_before := _board_identity(s)
	var hp_before: int = s.hp[Types.Side.PLAYER]
	var g := Game.new(s)
	var out := g.attempt_swap(mv["a"], mv["b"])

	t.check("the move did not resolve", not bool(out["matched"]))
	t.eq_seq("the board was not committed", _board_identity(s), identity_before)
	t.eq("BRAINSCRAMBLE fired exactly once", _of_kind(out["events"], "BRAINSCRAMBLE").size(), 1)
	t.eq(
		"for FNC_022's authored damage",
		hp_before - s.hp[Types.Side.PLAYER], _authored_damage(t, Content.FN_BRAINSCRAMBLE)
	)
	t.check("the board is now revealed", not Boss.is_concealed(s))
	t.eq("and the Hacker may still act", s.phase, Types.Phase.PLAYER_PRE)


## §8.4 — after the reveal, a further invalid attempt is an ordinary miss.
func _test_echofall_no_second_punishment(t: TestCase) -> void:
	t.group("ECHOFALL / no second punishment after the reveal")
	var s := _boss_state(Content.BOSS_ECHOFALL)
	s.hidden_axis = Types.ConcealAxis.COLOR
	s.phase = Types.Phase.PLAYER_PRE

	var mv := _find_invalid_swap(s)
	if mv.is_empty():
		t.check("the fixture offers an invalid swap", false)
		return

	var g := Game.new(s)
	g.attempt_swap(mv["a"], mv["b"])
	var hp_after_first: int = s.hp[Types.Side.PLAYER]

	var out := g.attempt_swap(mv["a"], mv["b"])
	t.eq("the second attempt fires nothing", _of_kind(out["events"], "BRAINSCRAMBLE").size(), 0)
	t.eq("and costs nothing", s.hp[Types.Side.PLAYER], hp_after_first)


## §8.4 — lethal BRAINSCRAMBLE ends the battle rather than returning control.
func _test_echofall_lethal(t: TestCase) -> void:
	t.group("ECHOFALL / lethal BRAINSCRAMBLE ends the battle")
	var s := _boss_state(Content.BOSS_ECHOFALL)
	s.hidden_axis = Types.ConcealAxis.COLOR
	s.phase = Types.Phase.PLAYER_PRE
	s.hp[Types.Side.PLAYER] = 1

	var mv := _find_invalid_swap(s)
	if mv.is_empty():
		t.check("the fixture offers an invalid swap", false)
		return

	var g := Game.new(s)
	g.attempt_swap(mv["a"], mv["b"])
	t.check("the battle is over", s.has_winner())
	t.eq("the Boss won", s.winner, Types.Side.ENEMY)


## §8.5 / §15 — a save taken while concealed resumes to the same concealment and
## the same future cadence.
func _test_echofall_save_resume(t: TestCase) -> void:
	t.group("ECHOFALL / concealment survives save and resume")
	var s := _boss_state(Content.BOSS_ECHOFALL)
	var g := Game.new(s)
	Boss.start_of_turn(g, [])
	t.check("concealed before the save", Boss.is_concealed(s))

	var restored: Dictionary = SaveState.from_dict(SaveState.to_dict(s))
	if not bool(restored["ok"]):
		t.check("the save round-trips", false)
		return
	var s2: GameState = restored["state"]

	t.eq("the same axis is hidden", s2.hidden_axis, s.hidden_axis)
	t.eq("the Boss-phase counter is preserved", s2.boss_phase, s.boss_phase)

	# The cadence continues rather than restarting: the next phase is even and
	# must NOT conceal anew.
	var axis_before: int = s2.hidden_axis
	Boss.start_of_turn(Game.new(s2), [])
	t.eq("the next phase adds no new concealment", s2.hidden_axis, axis_before)


# ---------------------------------------------------------------------------
# Boss Attack
# ---------------------------------------------------------------------------

## §10.2 — the default Hacker side, and the canonical build rather than a copy.
func _test_boss_attack_construction(t: TestCase) -> void:
	t.group("Boss Attack / default build and identities")
	var build := Session.default_build()
	var s := Session.create_boss_attack(
		Content.BOSS_NEHBOCYET, Content.BOSS_ATTACK_HOST_ID, 4242, build
	)

	t.eq("the selected Boss is the opponent", str(s.identity["opponent_id"]), Content.BOSS_NEHBOCYET)
	t.eq("as a Boss", int(s.identity["opponent_kind"]), Types.OpponentKind.BOS)
	t.eq("the Hacker is CR45H", str(s.identity["hacker_id"]), Content.DEFAULT_HACKER_ID)
	t.eq("the Deck is AGIMA", str(s.identity["deck_id"]), Content.DEFAULT_DECK_ID)
	t.eq("the HOST is THRESHOLD", str(s.identity["host_id"]), Content.BOSS_ATTACK_HOST_ID)
	t.eq("no UPGRADEs are carried", (s.identity["upgrade_ids"] as Array).size(), 0)
	t.eq_seq("the canonical default build is reused", s.identity["hacker_programs"], build)
	t.eq(
		"and the mode identifies itself honestly",
		int(s.identity["opponent_selection_source"]), Types.SystemSelectionSource.BOSS_ATTACK
	)

	# §10.4 — the same seed reproduces the same battle.
	var again := Session.create_boss_attack(
		Content.BOSS_NEHBOCYET, Content.BOSS_ATTACK_HOST_ID, 4242, build
	)
	t.eq_seq("replaying the seed rebuilds the same board", _board_identity(again), _board_identity(s))

	var other := Session.create_boss_attack(
		Content.BOSS_NEHBOCYET, Content.BOSS_ATTACK_HOST_ID, 4243, build
	)
	t.check("a fresh seed does not", _board_identity(other) != _board_identity(s))


## §10.3 — authored ICE, with no Run ladder modifier anywhere near it.
func _test_boss_attack_no_ladder(t: TestCase) -> void:
	t.group("Boss Attack / authored ICE without the Run ladder")
	var build := Session.default_build()
	for b in Content.all_bosses():
		var id: String = str(b["id"])
		var s := Session.create_boss_attack(id, Content.BOSS_ATTACK_HOST_ID, 7, build)
		t.eq("%s enters at its authored ICE" % id, s.hp[Types.Side.ENEMY], int(b["base_ice"]))
		t.eq("%s is at 350 this build" % id, int(b["base_ice"]), 350)


## §17.6 — the chooser is data-driven: every authored Boss, and only those.
func _test_boss_attack_roster(t: TestCase) -> void:
	t.group("Boss Attack / the roster is the content")
	var bosses := Content.all_bosses()
	t.eq("four Bosses are authored", bosses.size(), 4)

	var ids: Array = []
	for b in bosses:
		ids.append(str(b["id"]))
	t.eq_seq("in ID order", ids, ["BOS_01", "BOS_02", "BOS_03", "BOS_04"])

	for b in bosses:
		t.check(
			"%s has a display name in the text sheet" % b["id"],
			Text.name_of(str(b["id"])) != ""
		)
		t.eq(
			"%s carries the shared Program set" % b["id"],
			(b["programs"] as Array).size(), Content.SYSTEM_BUILD_SIZE
		)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## A Boss battle against `boss_id`, with no UPGRADEs so a measurement is of the
## Boss rather than of the Hacker's acquisitions.
func _boss_state(boss_id: String, seed_value := 777) -> GameState:
	Passives.clear_cache()
	return Session.create_boss_attack(
		boss_id, Content.BOSS_ATTACK_HOST_ID, seed_value, Session.default_build(), {}, false
	)


func _give_special(
	s: GameState, p: Vector2i, type: Tile.Special.Type, owner: Types.Side, magnitude := -1
) -> void:
	var tile: Tile = s.board[p.y][p.x]
	if tile == null:
		return
	var sp := Tile.Special.new()
	sp.type = type
	sp.owner = owner
	sp.magnitude = magnitude
	sp.seq = s.next_seq
	s.next_seq += 1
	tile.special = sp


## Installs `n` specials of one type on the first `n` eligible Packets.
func _seed_specials(s: GameState, n: int, type: Tile.Special.Type, owner: Types.Side) -> void:
	var placed := 0
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			if placed >= n:
				return
			var tile: Tile = s.board[y][x]
			if tile == null or tile.is_neutral():
				continue
			_give_special(s, Vector2i(x, y), type, owner)
			placed += 1


func _nth_standard(s: GameState, n: int) -> Vector2i:
	var seen := 0
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var tile: Tile = s.board[y][x]
			if tile == null or tile.is_neutral():
				continue
			if seen == n:
				return Vector2i(x, y)
			seen += 1
	return Vector2i(0, 0)


func _make_standard(s: GameState, p: Vector2i) -> void:
	var tile: Tile = s.board[p.y][p.x]
	if tile != null and tile.is_neutral():
		tile.kind = Tile.Kind.STANDARD
		tile.color = 0
		tile.shape = 0


func _make_neutral(s: GameState, p: Vector2i) -> void:
	var tile: Tile = s.board[p.y][p.x]
	if tile != null:
		tile.kind = Tile.Kind.NEUTRAL


func _make_all_neutral(s: GameState) -> void:
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			_make_neutral(s, Vector2i(x, y))


func _make_top_row_standard(s: GameState) -> void:
	for x in Constants.BOARD_WIDTH:
		_make_standard(s, Vector2i(x, 0))


func _count_type(s: GameState, type: Tile.Special.Type) -> int:
	return _cells_of_type(s, type).size()


func _cells_of_type(s: GameState, type: Tile.Special.Type) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var tile: Tile = s.board[y][x]
			if tile != null and tile.has_special() and tile.special.type == type:
				out.append(Vector2i(x, y))
	return out


func _row_ids(s: GameState, y: int) -> Array:
	var out: Array = []
	for x in Constants.BOARD_WIDTH:
		var tile: Tile = s.board[y][x]
		out.append(-1 if tile == null else tile.id)
	return out


func _row_filled(s: GameState, y: int) -> int:
	var n := 0
	for x in Constants.BOARD_WIDTH:
		if s.board[y][x] != null:
			n += 1
	return n


## Colour, shape and kind for every cell — what concealment must NOT change.
func _board_identity(s: GameState) -> Array:
	var out: Array = []
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var tile: Tile = s.board[y][x]
			out.append("-" if tile == null else "%d:%d:%d" % [tile.kind, tile.color, tile.shape])
	return out


func _all_specials(s: GameState) -> Array:
	var out: Array = []
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var tile: Tile = s.board[y][x]
			if tile != null and tile.has_special():
				out.append("%d,%d:%d:%d" % [x, y, tile.special.type, tile.special.owner])
	return out


func _total_charge(s: GameState) -> int:
	var n := s.deck_charge
	for side in [Types.Side.PLAYER, Types.Side.ENEMY]:
		for u in (s.units[side] as Array):
			n += u.charge
	return n


## An adjacent pair whose swap produces a Sync.
func _find_valid_swap(s: GameState) -> Dictionary:
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := Vector2i(x, y)
				var b: Vector2i = a + d
				if b.x >= Constants.BOARD_WIDTH or b.y >= Constants.BOARD_HEIGHT:
					continue
				BoardOps.swap(s.board, a, b)
				var hit := not MatchFinder.detect(s.board).is_empty()
				BoardOps.swap(s.board, a, b)
				if hit:
					return {"a": a, "b": b}
	return {}


## An adjacent pair whose swap produces nothing.
func _find_invalid_swap(s: GameState) -> Dictionary:
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := Vector2i(x, y)
				var b: Vector2i = a + d
				if b.x >= Constants.BOARD_WIDTH or b.y >= Constants.BOARD_HEIGHT:
					continue
				BoardOps.swap(s.board, a, b)
				var hit := not MatchFinder.detect(s.board).is_empty()
				BoardOps.swap(s.board, a, b)
				if not hit:
					return {"a": a, "b": b}
	return {}


func _of_kind(events: Array, kind: String) -> Array:
	var out: Array = []
	for e in events:
		if e.get("t", "") == Types.EVT.BOSS_MECHANIC and str(e.get("kind", "")) == kind:
			out.append(e)
	return out


func _of_kind_evt(events: Array, evt: StringName) -> Array:
	var out: Array = []
	for e in events:
		if e.get("t", "") == evt:
			out.append(e)
	return out


## A Function's authored damage, read out of its effect PLAN.
##
## The key is `plan`, not `ops`. Getting that wrong is not a wrong number: in
## GDScript a missing Dictionary key aborts the calling function, so the helper
## returned 0 and every assertion below it in that test stopped running while
## the suite still counted them. That is exactly the 0.3.1 failure this comment
## used to describe in the abstract — written here while repeating it. The shape
## is asserted rather than assumed so it cannot come back quietly.
func _authored_damage(t: TestCase, fn_id: String) -> int:
	var row: Dictionary = Content.function(fn_id)
	t.check("%s has an effect plan" % fn_id, row.has("plan"))
	if not row.has("plan"):
		return -1

	for step in (row["plan"] as Array):
		var params: Dictionary = step.get("params", {})
		if params.has("damage"):
			return int(params["damage"])

	t.check("%s's plan deals damage" % fn_id, false)
	return -1

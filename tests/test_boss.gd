extends RefCounted

## Beta 0.3 Phases C-E — the ODANSHAY mechanic layer.
##
## Covers the Override overlay and its target rules, the end-of-turn placement
## with its DATABEND fallback and bounded retry, and the start-of-turn threshold
## with CODESHATTER and REBOOT.
##
## Authorization §21 coverage: 14-24 (Override), 25-28 (DATABEND), 29-45
## (threshold / CODESHATTER / REBOOT).

func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("boss")
		t.check("content loads", false)
		return
	Content.set_active(result["content"])
	Passives.clear_cache()

	_test_target_legality(t)
	_test_placement(t)
	_test_placement_batch(t)
	_test_insufficient_targets(t)
	_test_threshold_boundary(t)
	_test_threshold_sequence(t)
	_test_reboot(t)
	_test_zero_cost(t)
	_test_retry_preserves_encounter(t)
	_test_mid_boss_save(t)
	_test_metrics(t)

	Content.clear()
	Passives.clear_cache()


# ---------------------------------------------------------------------------
# Override targets and placement
# ---------------------------------------------------------------------------

## §21.16 / §21.17 — a Boss-owned special is an illegal target; a Hacker-owned
## one is legal and gets replaced.
func _test_target_legality(t: TestCase) -> void:
	t.group("Override target legality")

	var s := _boss_state()
	var all := Boss.override_targets(s)
	t.eq("every standard Packet starts eligible", all.size(), _standard_count(s))

	# A neutral has no axes and can never carry an overlay.
	var neutral_at := Vector2i(0, 0)
	s.board[0][0] = Tile.neutral(9001)
	t.check("a neutral is not a target", not Boss.override_targets(s).has(neutral_at))

	# A BOSS-owned overlay excludes the Packet.
	_give_special(s, Vector2i(1, 0), Tile.Special.Type.OVERRIDE, Types.Side.ENEMY)
	t.check("an existing Override is not a target", not Boss.override_targets(s).has(Vector2i(1, 0)))
	_give_special(s, Vector2i(2, 0), Tile.Special.Type.BOMB, Types.Side.ENEMY)
	t.check("a Boss Bomb is not a target either", not Boss.override_targets(s).has(Vector2i(2, 0)))

	# A HACKER-owned overlay does NOT exclude it — the Override replaces it.
	_give_special(s, Vector2i(3, 0), Tile.Special.Type.BOMB, Types.Side.PLAYER)
	t.check("a Hacker special IS a valid target", Boss.override_targets(s).has(Vector2i(3, 0)))

	# Ownership is what matters, not the overlay type.
	t.eq("only Boss-owned overlays and the neutral are excluded",
		Boss.override_targets(s).size(), _standard_count(s) - 2)


## §21.14 / §21.15 — placement preserves the Packet and produces no damage,
## charge, or Sync.
func _test_placement(t: TestCase) -> void:
	t.group("Override placement")

	var s := _boss_state()
	var p := Vector2i(4, 4)
	var before: Tile = s.board[p.y][p.x]
	var color := before.color
	var shape := before.shape
	var tile_id := before.id
	var hp_before: Array = s.hp.duplicate()
	var charge_before := _enemy_charge(s)

	var events: Array = []
	Boss.place_overrides(s, [p], events)

	var after: Tile = s.board[p.y][p.x]
	t.eq("colour preserved", after.color, color)
	t.eq("shape preserved", after.shape, shape)
	t.eq("the same Packet, not a replacement", after.id, tile_id)
	t.check("it carries an Override", after.has_special() and after.special.type == Tile.Special.Type.OVERRIDE)
	t.eq("owned by the Boss", after.special.owner, Types.Side.ENEMY)
	t.eq("counted", Boss.override_count(s), 1)

	# Placement is a marker, not an attack.
	t.eq("no damage dealt", s.hp, hp_before)
	t.eq("no charge granted", _enemy_charge(s), charge_before)
	for e in events:
		t.check("no damage event", e["t"] != Types.EVT.DAMAGE)
		t.check("no charge-route event", e["t"] != Types.EVT.CHARGE_ROUTE)

	# §21.17 — replacing a Hacker overlay leaves exactly one Boss Override, and
	# the removed overlay stops contributing.
	var s2 := _boss_state()
	# Pick a STANDARD cell: a neutral cannot carry an overlay at all, so
	# hardcoding a coordinate makes the test depend on the board roll.
	var target := _first_standard(s2)
	_give_special(s2, target, Tile.Special.Type.BOMB, Types.Side.PLAYER)
	var overwrote := Boss.place_overrides(s2, [target], [])
	var replaced: Tile = s2.board[target.y][target.x]
	t.eq("the replacement is recorded", overwrote, 1)
	t.eq("exactly one overlay remains", replaced.special.type, Tile.Special.Type.OVERRIDE)
	t.eq("and it is the Boss's", replaced.special.owner, Types.Side.ENEMY)
	t.eq("only one Override on the board", Boss.override_count(s2), 1)


## §21.18 / §21.19 / §21.20 — three distinct targets, chosen from the gameplay
## stream before any mutation.
func _test_placement_batch(t: TestCase) -> void:
	t.group("end-of-turn placement")

	var s := _boss_state()
	var game := Game.new(s)
	var events: Array = []
	Boss.place_end_of_turn(game, events)

	t.eq("exactly three placed", Boss.override_count(s), Content.OVERRIDE_PLACEMENT_COUNT)

	var placed := _of_kind(events, "OVERRIDE_PLACED")
	t.eq("one placement record", placed.size(), 1)
	t.eq("it says three", int(placed[0]["placed"]), Content.OVERRIDE_PLACEMENT_COUNT)
	t.eq("count before", int(placed[0]["count_before"]), 0)
	t.eq("count after", int(placed[0]["count_after"]), Content.OVERRIDE_PLACEMENT_COUNT)

	var cells: Array = placed[0]["cells"]
	var seen := {}
	for c in cells:
		t.check("target %s is distinct" % c, not seen.has(c))
		seen[c] = true

	# §21.20 — the same gameplay seed picks the same targets, and a different
	# seed generally does not. That is what "gameplay RNG selects targets" means
	# operationally.
	var a := _boss_state(31337)
	var b := _boss_state(31337)
	var ea: Array = []
	var eb: Array = []
	Boss.place_end_of_turn(Game.new(a), ea)
	Boss.place_end_of_turn(Game.new(b), eb)
	t.eq("same seed, same targets", _of_kind(ea, "OVERRIDE_PLACED")[0]["cells"], _of_kind(eb, "OVERRIDE_PLACED")[0]["cells"])

	# Placement must not disturb the board's match state — it changes no axes.
	var s3 := _boss_state()
	var matches_before := MatchFinder.detect(s3.board).size()
	Boss.place_end_of_turn(Game.new(s3), [])
	t.eq("placement creates no new Sync", MatchFinder.detect(s3.board).size(), matches_before)


## §21.21 / §21.22 / §21.24 — with fewer than three targets, place NONE, then
## DATABEND. Exhausting the cap exits cleanly with no partial placement.
func _test_insufficient_targets(t: TestCase) -> void:
	t.group("insufficient targets")

	# Cap exhaustion needs a board DATABEND CANNOT recover capacity from, which
	# takes some care: DATABEND retains Boss overlays but regenerates every
	# other cell and then resolves the resulting Syncs — and resolution destroys
	# Packets, overlays included, which frees targets again. On an ordinary
	# board that is the mechanic working, and capacity recovers on the first
	# attempt.
	#
	# So: make every cell standard first (no neutrals left to regenerate), then
	# blanket it in Boss Overrides. Now REPLACE retains all 64, regenerates
	# nothing, creates no Sync, and capacity genuinely never recovers.
	var s := _boss_state()
	_make_all_standard_match_free(s)
	t.eq("the prepared board has no Sync waiting", MatchFinder.detect(s.board).size(), 0)
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			_give_special(s, Vector2i(x, y), Tile.Special.Type.OVERRIDE, Types.Side.ENEMY)
	var full := Boss.override_count(s)
	t.eq("every cell is now overridden", full, Constants.BOARD_WIDTH * Constants.BOARD_HEIGHT)

	var events: Array = []
	Boss.place_end_of_turn(Game.new(s), events)

	t.eq("no target exists", Boss.override_targets(s).size(), 0)
	t.eq("nothing was placed", Boss.override_count(s), full)
	# "Three or none" — never a partial one or two. The count being UNCHANGED is
	# the property; a modular check would only hold on boards whose size happens
	# to divide by three.
	t.eq("not a partial one or two either", Boss.override_count(s), full)
	t.eq("no placement record", _of_kind(events, "OVERRIDE_PLACED").size(), 0)

	# §21.23 — the shipped bound, and the off-by-one it hides: `attempt` runs
	# 0..LIMIT inclusive, so there are LIMIT+1 capacity checks and LIMIT
	# DATABEND casts. A loop written `for i in LIMIT` gets both numbers wrong.
	var short := _of_kind(events, "INSUFFICIENT_TARGETS")
	t.eq("capacity checked LIMIT+1 times", short.size(), Content.OVERRIDE_DATABEND_RETRY_LIMIT + 1)
	t.eq("attempts are numbered from 1", int(short[0]["attempt"]), 1)
	t.eq("up to LIMIT+1", int(short[short.size() - 1]["attempt"]), Content.OVERRIDE_DATABEND_RETRY_LIMIT + 1)

	var databends := 0
	for e in events:
		if e["t"] == Types.EVT.ABILITY and str(e.get("fn", "")) == Content.FN_DATABEND:
			databends += 1
	t.eq("DATABEND fired LIMIT times, not LIMIT+1", databends, Content.OVERRIDE_DATABEND_RETRY_LIMIT)

	var abandoned := _of_kind(events, "PLACEMENT_ABANDONED")
	t.eq("the turn ends with an explicit abandon", abandoned.size(), 1)
	t.eq("recording the count it gave up at", int(abandoned[0]["count_after"]), full)


# ---------------------------------------------------------------------------
# Threshold, CODESHATTER, REBOOT
# ---------------------------------------------------------------------------

## §21.29 / §21.30 / §21.31 — `>= 15`, never `== 15`.
func _test_threshold_boundary(t: TestCase) -> void:
	t.group("threshold boundary")

	for n in [Content.OVERRIDE_THRESHOLD - 1, Content.OVERRIDE_THRESHOLD, Content.OVERRIDE_THRESHOLD + 2]:
		var s := _boss_state()
		_seed_overrides(s, n)
		var events: Array = []
		Boss.resolve_threshold(Game.new(s), events)
		var fired := _of_kind(events, "THRESHOLD").size() > 0
		if n < Content.OVERRIDE_THRESHOLD:
			t.check("%d Overrides does not trigger" % n, not fired)
		else:
			t.check("%d Overrides triggers" % n, fired)

	# Overrides arrive three at a time, so an `== 15` test would step over the
	# threshold entirely. Confirm a count that is never exactly 15 still fires.
	var s2 := _boss_state()
	_seed_overrides(s2, Content.OVERRIDE_THRESHOLD + 2)
	var e2: Array = []
	Boss.resolve_threshold(Game.new(s2), e2)
	t.check("a count above the threshold still fires", _of_kind(e2, "THRESHOLD").size() == 1)


## §21.34 / §21.39 / §21.40 / §21.45 — CODESHATTER's damage, the terminal check
## between it and REBOOT, and re-arming.
func _test_threshold_sequence(t: TestCase) -> void:
	t.group("threshold sequence")

	# No UPGRADEs: BRACER reduces damage from ALL sources by 1, so a Run that
	# acquired it would see 69 rather than the authored 70. That modifier
	# APPLYING is correct (§21.36) and is asserted separately below; this
	# measures the raw value.
	var s := _boss_state(777, false)
	_seed_overrides(s, Content.OVERRIDE_THRESHOLD)
	var link_before: int = s.hp[Types.Side.PLAYER]
	var events: Array = []
	Boss.resolve_threshold(Game.new(s), events)

	# Order: THRESHOLD record, then CODESHATTER, then REBOOT.
	var order := PackedStringArray()
	for e in events:
		if e["t"] == Types.EVT.BOSS_MECHANIC:
			order.append(str(e["kind"]))
		elif e["t"] == Types.EVT.ABILITY:
			order.append(str(e.get("fn", "")))
	var i_threshold := Array(order).find("THRESHOLD")
	var i_shatter := Array(order).find(Content.FN_CODESHATTER)
	var i_reboot := Array(order).find(Content.FN_REBOOT)
	t.check("threshold is recorded first", i_threshold >= 0 and i_threshold < i_shatter)
	t.check("CODESHATTER fires before REBOOT", i_shatter >= 0 and i_shatter < i_reboot)

	# §21.34 — the authored raw damage, with no modifier in play.
	var raw := int(Content.function(Content.FN_CODESHATTER)["damage"])
	t.eq("the authored damage is 70", raw, 70)
	t.eq("CODESHATTER dealt it", link_before - s.hp[Types.Side.PLAYER], raw)

	# §21.36 — ordinary Function-damage modifiers DO apply. BRACER reduces
	# damage from all sources by 1, so the same sequence with UPGRADEs acquired
	# lands one lower. This is the positive half of "CODESHATTER is ordinary
	# Function damage" rather than a bespoke payload.
	var modified := _boss_state(777, true)
	_seed_overrides(modified, Content.OVERRIDE_THRESHOLD)
	var link_mod: int = modified.hp[Types.Side.PLAYER]
	Boss.resolve_threshold(Game.new(modified), [])
	t.check(
		"a damage-reducing UPGRADE modifies CODESHATTER",
		link_mod - modified.hp[Types.Side.PLAYER] < raw
	)

	# §21.45 — not a phase transition: Overrides accumulate and fire again.
	var s2 := _boss_state()
	_seed_overrides(s2, Content.OVERRIDE_THRESHOLD)
	var g2 := Game.new(s2)
	Boss.resolve_threshold(g2, [])
	t.eq("REBOOT cleared the Overrides", Boss.override_count(s2), 0)
	_seed_overrides(s2, Content.OVERRIDE_THRESHOLD)
	var again: Array = []
	Boss.resolve_threshold(g2, again)
	t.check("the threshold can fire again later", _of_kind(again, "THRESHOLD").size() == 1)

	# §21.39 — a CODESHATTER that defeats the Hacker stops the sequence: REBOOT
	# does not fire.
	var lethal := _boss_state()
	_seed_overrides(lethal, Content.OVERRIDE_THRESHOLD)
	lethal.hp[Types.Side.PLAYER] = 1
	var le: Array = []
	Boss.resolve_threshold(Game.new(lethal), le)
	t.check("the Hacker is defeated", lethal.has_winner())
	var fired_reboot := false
	for e in le:
		if e["t"] == Types.EVT.ABILITY and str(e.get("fn", "")) == Content.FN_REBOOT:
			fired_reboot = true
	t.check("REBOOT did not fire after a lethal CODESHATTER", not fired_reboot)


## §21.41 / §21.42 / §21.43 — REBOOT clears the board and, per D-032, leaves an
## arrangement containing NO match.
func _test_reboot(t: TestCase) -> void:
	t.group("REBOOT")

	var s := _boss_state()
	_seed_overrides(s, 6)
	_give_special(s, Vector2i(7, 7), Tile.Special.Type.BOMB, Types.Side.PLAYER)
	var identity_before: Dictionary = s.identity.duplicate(true)

	var game := Game.new(s)
	game.cast_boss_mechanic(Content.FN_REBOOT, [])

	# §21.41 — every overlay, both sides', is gone.
	var specials := 0
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var tile: Tile = s.board[y][x]
			if tile != null and tile.has_special():
				specials += 1
	t.eq("no overlay survives REBOOT", specials, 0)
	t.eq("the Overrides went with them", Boss.override_count(s), 0)

	# §21.43 / D-032 — the POSITIVE form. The alpha's tuple carries
	# SHAKE_PREVENT_MATCHES, so the regenerated board contains no Sync at all.
	# Asserting "none was resolved" would pass against a board full of pre-made
	# Syncs waiting for the Hacker to collect.
	t.eq("the regenerated board contains zero matches", MatchFinder.detect(s.board).size(), 0)

	# §21.42 — non-board PASSIVE state is untouched. REBOOT is a board effect.
	t.eq("identity is unchanged", s.identity, identity_before)
	Passives.clear_cache()
	var upg := 0
	for inst in Passives.active(s.identity):
		if inst.source_kind == Types.PassiveSourceKind.UPG:
			upg += 1
	t.check("UPGRADE PASSIVEs still active after REBOOT", upg > 0)


## §21.35 / §7 — the payloads are zero-cost: they consume no Boss Program charge.
func _test_zero_cost(t: TestCase) -> void:
	t.group("payloads cost no charge")

	for fn_id in [Content.FN_CODESHATTER, Content.FN_REBOOT, Content.FN_DATABEND]:
		var s := _boss_state()
		# Fill the Boss's pools so any spend would be visible.
		for u in (s.units[Types.Side.ENEMY] as Array):
			u.charge = int(Content.program(u.program_id)["charge_cap"])
		var before := _enemy_charge(s)
		Game.new(s).cast_boss_mechanic(fn_id, [])
		t.eq("%s spent no Program charge" % fn_id, _enemy_charge(s), before)


# ---------------------------------------------------------------------------
# Phase F — result and session integration
# ---------------------------------------------------------------------------

## §21.47 / §21.48 — losing to the Boss uses the ordinary Run-loss path, and the
## retry is the SAME encounter. Nothing rerolls and no reward is granted twice.
func _test_retry_preserves_encounter(t: TestCase) -> void:
	t.group("Boss retry")

	var r := Run.new()
	r.boss_id = Content.BOSS_MECHANIC_BOSS_ID
	r.step = Run.RUN_LENGTH
	r.settings = Constants.default_settings()
	r.hacker_id = Content.DEFAULT_HACKER_ID
	r.deck_id = Content.DEFAULT_DECK_ID
	r.hacker_max_link = 150
	r.inventory = Content.inventory_program_ids(r.hacker_id, r.deck_id)
	r.build = Content.default_build(r.hacker_id, r.deck_id)
	for u in Content.all_upgrades():
		r.upgrade_ids.append(u["id"])
	r.opponent_kind = Types.OpponentKind.BOS
	r.opponent_id = Content.BOSS_MECHANIC_BOSS_ID
	r.host_id = "HST_03"
	r.phase = Types.SessionPhase.ACTIVE_BATTLE

	var boss_before := r.boss_id
	var host_before := r.host_id
	var upgrades_before: Array = r.upgrade_ids.duplicate()
	var build_before: Array = r.build.duplicate()

	r.retry_battle()

	t.eq("retry returns to Build", r.phase, Types.SessionPhase.PENDING_BUILD)
	t.eq("the Boss is unchanged", r.boss_id, boss_before)
	t.eq("the committed HOST is not rerolled", r.host_id, host_before)
	t.eq("no UPGRADE is granted again", r.upgrade_ids, upgrades_before)
	t.eq("the Build is preserved", r.build, build_before)
	t.eq("still the last step", r.step, Run.RUN_LENGTH)
	t.check("still facing the Boss", r.opponent_is_boss())
	t.check("no route was generated", r.pending_path == null)

	# The retried battle is built from the same committed package.
	var again := Session.create_run_battle(r, 99)
	t.eq("same opponent", again.identity["opponent_id"], boss_before)
	t.eq("same HOST", again.identity["host_id"], host_before)
	t.eq("same UPGRADEs", again.identity["upgrade_ids"], upgrades_before)
	t.eq("Boss ICE is still the authored value", again.hp[Types.Side.ENEMY],
		int(Content.boss(boss_before)["base_ice"]))


## §17 / §21.49 — a representative mid-Boss save. One check, not a matrix: the
## authorization is explicit that this should not multiply into a
## save-at-every-mechanic-step program.
func _test_mid_boss_save(t: TestCase) -> void:
	t.group("mid-Boss save")

	var s := _boss_state()
	# Get the battle into a state worth saving: Overrides on the board, a
	# Hacker overlay among them, and charge in the Boss's pools.
	_seed_overrides(s, 7)
	_give_special(s, _last_standard(s), Tile.Special.Type.BOMB, Types.Side.PLAYER)
	for u in (s.units[Types.Side.ENEMY] as Array):
		u.charge = 3
	s.turn = 6

	var overrides_before := Boss.override_count(s)
	var restored := SaveState.from_dict(SaveState.to_dict(s))
	t.check("the battle restores", restored["ok"])
	var back: GameState = restored["state"]

	# Boss identity survives as a Boss, not as a System.
	t.eq("opponent kind", back.identity["opponent_kind"], Types.OpponentKind.BOS)
	t.eq("opponent", back.identity["opponent_id"], Content.BOSS_MECHANIC_BOSS_ID)
	t.eq("HOST", back.identity["host_id"], s.identity["host_id"])
	t.eq("acquired UPGRADEs", back.identity["upgrade_ids"], s.identity["upgrade_ids"])
	t.eq("Build", back.identity["hacker_programs"], s.identity["hacker_programs"])
	t.eq("current Boss ICE", back.hp[Types.Side.ENEMY], s.hp[Types.Side.ENEMY])
	t.eq("turn", back.turn, s.turn)

	# The Override board state is the Boss-specific half, and it is what a
	# generic overlay serializer could plausibly lose.
	t.eq("every Override restored", Boss.override_count(back), overrides_before)
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var a: Tile = s.board[y][x]
			var b: Tile = back.board[y][x]
			t.check("cell %d,%d overlay presence matches" % [x, y], a.has_special() == b.has_special())
			if a.has_special():
				t.eq("cell %d,%d overlay type" % [x, y], b.special.type, a.special.type)
				t.eq("cell %d,%d overlay owner" % [x, y], b.special.owner, a.special.owner)

	# Boss Program charge restores, so a resumed Boss turn is not handed free or
	# missing charge.
	t.eq("Boss Program charge", _enemy_charge(back), _enemy_charge(s))

	# And the restored battle still behaves as a Boss battle.
	t.check("still recognised as a Boss battle", Boss.is_boss_battle(back))


# ---------------------------------------------------------------------------
# Phase G — telemetry
# ---------------------------------------------------------------------------

## §18 — Boss aggregates come off the EXISTING event funnel, not a parallel Boss
## accounting tree, and they survive resume like every other counter.
func _test_metrics(t: TestCase) -> void:
	t.group("Boss metrics")

	var s := _boss_state()
	Session.attach_accounting(s)
	var game := Game.new(s)

	# A placement batch, then a threshold sequence.
	var events: Array = []
	Boss.place_end_of_turn(game, events)
	_seed_overrides(s, Content.OVERRIDE_THRESHOLD)
	Boss.resolve_threshold(game, events)
	Metrics.consume(s.metrics, events)

	t.eq("three Overrides counted", s.metrics.overrides_placed, Content.OVERRIDE_PLACEMENT_COUNT)
	t.check("the peak was recorded", s.metrics.overrides_peak >= Content.OVERRIDE_THRESHOLD)
	t.eq("one threshold trigger", s.metrics.threshold_triggers, 1)
	t.eq("one CODESHATTER", s.metrics.codeshatter_activations, 1)
	t.eq("one REBOOT", s.metrics.reboot_activations, 1)

	# The peak is the diagnostically useful figure: total placed says how busy
	# the mechanic was, the peak says how close the board came to firing it.
	t.check("peak is at least the total placed", s.metrics.overrides_peak >= Content.OVERRIDE_PLACEMENT_COUNT)

	# Boss activations must NOT become phantom per-Program rows — the Boss owns
	# no Program slot, so crediting its ID would corrupt the Program figures.
	var enemy := s.metrics.side(Types.Side.ENEMY)
	t.check("no phantom Program row for the Boss", not enemy.units.has(Content.BOSS_MECHANIC_BOSS_ID))

	# §18 / beta 0.1's resume contract: the accumulator is part of the save, so a
	# battle continued from disk reports the same figures.
	var restored := SaveState.from_dict(SaveState.to_dict(s))
	var back: GameState = restored["state"]
	t.eq("Overrides placed survives resume", back.metrics.overrides_placed, s.metrics.overrides_placed)
	t.eq("peak survives resume", back.metrics.overrides_peak, s.metrics.overrides_peak)
	t.eq("threshold count survives resume", back.metrics.threshold_triggers, s.metrics.threshold_triggers)
	t.eq("CODESHATTER count survives resume", back.metrics.codeshatter_activations, s.metrics.codeshatter_activations)
	t.eq("REBOOT count survives resume", back.metrics.reboot_activations, s.metrics.reboot_activations)

	# An ordinary System battle carries the same record shape with the Boss
	# fields simply at zero — one battle record, not two.
	var qm := Session.create_quick_match("SYS_01", "HST_02", 5, Session.default_build(), {}, true)
	t.eq("a System battle places no Overrides", qm.metrics.overrides_placed, 0)
	t.eq("and triggers no threshold", qm.metrics.threshold_triggers, 0)
	t.check("but has the fields", qm.metrics.to_dict().has("overrides_peak"))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## A Boss battle: ODANSHAY, the intro HOST, every UPGRADE acquired.
func _boss_state(seed_value := 777, with_upgrades := true) -> GameState:
	var r := Run.new()
	r.boss_id = Content.BOSS_MECHANIC_BOSS_ID
	r.step = Run.RUN_LENGTH
	r.settings = Constants.default_settings()
	r.hacker_id = Content.DEFAULT_HACKER_ID
	r.deck_id = Content.DEFAULT_DECK_ID
	r.hacker_max_link = 150
	r.inventory = Content.inventory_program_ids(r.hacker_id, r.deck_id)
	r.build = Content.default_build(r.hacker_id, r.deck_id)
	if with_upgrades:
		for u in Content.all_upgrades():
			r.upgrade_ids.append(u["id"])
	r.opponent_kind = Types.OpponentKind.BOS
	r.opponent_id = Content.BOSS_MECHANIC_BOSS_ID
	r.host_id = Content.INITIAL_HOST_ID
	r.phase = Types.SessionPhase.PENDING_BUILD
	Passives.clear_cache()
	return Session.create_run_battle(r, seed_value, false)


## Install `n` Boss Overrides in row-major order.
func _seed_overrides(s: GameState, n: int) -> void:
	var placed := 0
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			if placed >= n:
				return
			var tile: Tile = s.board[y][x]
			if tile == null or tile.is_neutral():
				continue
			_give_special(s, Vector2i(x, y), Tile.Special.Type.OVERRIDE, Types.Side.ENEMY)
			placed += 1


func _give_special(s: GameState, p: Vector2i, type: Tile.Special.Type, owner: Types.Side) -> void:
	var tile: Tile = s.board[p.y][p.x]
	if tile == null or tile.is_neutral():
		return
	var sp := Tile.Special.new()
	sp.type = type
	sp.owner = owner
	sp.seq = s.next_seq
	s.next_seq += 1
	tile.special = sp


## Replace every neutral with a standard Packet chosen so the board still
## contains NO match.
##
## Needed because DATABEND regenerates exactly the cells it does not retain. A
## board that is entirely Boss-overridden retains everything and regenerates
## nothing — but only if there are no neutrals left, since a neutral carries no
## overlay and is therefore always regenerated. Substituting a fixed colour and
## shape would instead create a Sync, which cascades, destroys Packets, and
## frees the capacity the test is trying to withhold.
func _make_all_standard_match_free(s: GameState) -> void:
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var cell: Tile = s.board[y][x]
			if cell == null or not cell.is_neutral():
				continue
			for c in Constants.COLOR_COUNT:
				var placed := false
				for sh in Constants.SHAPE_COUNT:
					s.board[y][x] = Tile.standard(cell.id, c, sh)
					if MatchFinder.detect(s.board).is_empty():
						placed = true
						break
				if placed:
					break


## The first standard (axis-bearing) cell, row-major. Used instead of a
## hardcoded coordinate so a board roll that puts a neutral there cannot make a
## test fail for an unrelated reason.
func _first_standard(s: GameState) -> Vector2i:
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var tile: Tile = s.board[y][x]
			if tile != null and not tile.is_neutral():
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## The last standard cell, row-major — far from the ones `_seed_overrides`
## consumes, so the two do not collide.
func _last_standard(s: GameState) -> Vector2i:
	var found := Vector2i(-1, -1)
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var tile: Tile = s.board[y][x]
			if tile != null and not tile.is_neutral() and not tile.has_special():
				found = Vector2i(x, y)
	return found


func _standard_count(s: GameState) -> int:
	var n := 0
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var tile: Tile = s.board[y][x]
			if tile != null and not tile.is_neutral():
				n += 1
	return n


func _enemy_charge(s: GameState) -> int:
	var total := 0
	for u in (s.units[Types.Side.ENEMY] as Array):
		total += u.charge
	return total


func _of_kind(events: Array, kind: String) -> Array:
	var out: Array = []
	for e in events:
		if e["t"] == Types.EVT.BOSS_MECHANIC and str(e["kind"]) == kind:
			out.append(e)
	return out

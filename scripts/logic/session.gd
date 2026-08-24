class_name Session
extends RefCounted

## Battle construction.
##
## Beta 0.1 covers Constructed Quick Match only: the Hacker and Deck are pinned
## by stable ID, and the System and HOST are deliberately chosen. Run setup,
## routes, and UPGRADEs arrive in 0.2.
##
## Effective LINK/ICE and the per-side strong sets are resolved HERE, once, and
## stamped into the battle's config — which is immutable for its lifetime. That
## is what makes a battle's identity self-contained: a later content edit cannot
## change how an in-flight battle behaves.


## The default active build: the Hacker's portfolio in authored order, then the
## Deck's, truncated to the build size.
##
## Portfolio order is authored content and is gameplay-significant, so this
## derives the build rather than naming Programs — a content edit changes the
## default build, as it should.
## Constructed Quick Match's pinned pair. Beta 0.2 moved the derivation itself
## into `Content.default_build`, which a Run needs parameterized by its own
## selected identity; this stays as the Quick Match entry point so the pin lives
## in one place. Behaviour is unchanged — same portfolio slots, same order.
static func default_build() -> Array:
	return Content.default_build(Content.DEFAULT_HACKER_ID, Content.DEFAULT_DECK_ID)


# ---------------------------------------------------------------------------
# Random Quick Match setup (beta 0.2)
# ---------------------------------------------------------------------------

## An isolated SETUP random source.
##
## Deliberately its own instance so that generating a build or rolling an
## opponent cannot consume or perturb the battle's gameplay stream: a `Game`
## seeds its RNG independently at construction, so the board, refills, and AI
## sequence for a given gameplay seed are unaffected by setup randomness.
##
## The seed is returned so a run can be reproduced from the log.
static func make_setup_random(seed_value: int = -1) -> Dictionary:
	var s := seed_value if seed_value >= 0 else (randi() & 0x7FFFFFFF)
	return {"rng": Rng.new(s), "seed": s}


## Four distinct inventory Programs in an explicitly randomized order.
##
## One shuffle gives both properties — sampling without replacement AND a
## random order — which is why it shuffles the whole inventory and takes a
## slice rather than picking four times.
static func random_build(inventory: Array, rng: Rng) -> Array:
	var pool := inventory.duplicate()
	rng.shuffle(pool)
	return pool.slice(0, Content.ACTIVE_BUILD_SIZE)


## Roll a complete Random Quick Match: build, then System, then HOST.
##
## THAT ORDER IS THE CONTRACT, not a convenience. All three come from ONE
## isolated setup stream, and the alpha draws the build first. Rolling the
## System before the build would produce a different — still legal — result for
## the same seed. Pinned by the fixture in `tests/fixtures/route.json`.
##
## Random Quick Match acquires no UPGRADEs, involves no Boss, and never writes
## to Constructed Quick Match's remembered build. It produces an ordinary
## standalone battle and opens no Build screen.
static func random_quick_match_setup(rng: Rng) -> Dictionary:
	var inventory := Content.inventory_program_ids(Content.DEFAULT_HACKER_ID, Content.DEFAULT_DECK_ID)
	return {
		"build": random_build(inventory, rng),
		"system_id": Route.random_system(rng),
		"host_id": Route.random_host(rng),
	}


## Builds a playable Quick Match.
##
## `build` is the ordered active build — exactly four distinct inventory
## Programs, top to bottom. That order is charge-routing priority.
static func create_quick_match(
	system_id: String,
	host_id: String,
	seed_value: int,
	build: Array,
	settings: Dictionary = {},
	# Accounting is opt-in. The differential harness runs thousands of battles
	# that want neither, and paying for records nobody reads would show up
	# directly in the parity run's wall clock.
	with_accounting := false,
) -> GameState:
	var hacker := Content.hacker(Content.DEFAULT_HACKER_ID)
	var deck := Content.deck(Content.DEFAULT_DECK_ID)
	var sys := Content.system(system_id)

	var s := GameState.new()
	s.rng = Rng.new(seed_value)
	s.next_id = 1
	s.next_seq = 1
	s.turn = 1
	s.phase = Types.Phase.PLAYER_PRE
	s.winner = -1
	s.battle_id = "qm-%s-%s-%d" % [system_id, host_id, seed_value]

	var cfg := settings.duplicate() if not settings.is_empty() else Constants.default_settings()
	# Under Normal LINK the maxima come from the selected identities; with it
	# off the manual settings replace both.
	if cfg["normal_link"]:
		cfg["player_hp"] = int(hacker["base_link"]) + int(deck["add_link"])
		cfg["enemy_hp"] = int(sys["base_ice"])
	else:
		cfg["player_hp"] = int(cfg["manual_hacker_link"])
		cfg["enemy_hp"] = int(cfg["manual_system_ice"])

	# Each side's strong sets come from its OWN authored identity. Weak sets are
	# the enum-order complement and are therefore never stored — deriving them
	# from one authority is what keeps the two from drifting.
	cfg["strong_colors"] = [hacker["strong_colors"], sys["strong_colors"]]
	cfg["strong_shapes"] = [hacker["strong_shapes"], sys["strong_shapes"]]
	s.config = cfg

	s.hp = [cfg["player_hp"], cfg["enemy_hp"]]

	s.identity = {
		"cache_key": "%s|%s|%s" % [Content.DEFAULT_HACKER_ID, system_id, host_id],
		"hacker_id": Content.DEFAULT_HACKER_ID,
		"deck_id": Content.DEFAULT_DECK_ID,
		"opponent_kind": Types.OpponentKind.SYS,
		"opponent_id": system_id,
		"opponent_selection_source": Types.SystemSelectionSource.QUICK_CONSTRUCTED,
		"host_id": host_id,
		"upgrade_ids": [],
		"hacker_programs": build,
		"system_programs": sys["programs"],
		"deck_function_id": deck["function_id"],
		"selection_source": Types.SelectionSource.EXPLICIT_SELECTION,
		"build_origin": Types.BuildOrigin.DEFAULT,
	}

	s.units = [_units_for(build), _units_for(sys["programs"])]
	# A directly assigned Function that starts charged begins at its full pool.
	s.deck_charge = int(deck["fn"]["cost"]) if deck["fn"]["start_charged"] else 0

	var gen := BoardOps.TileGen.new(s.rng, s.next_id)
	s.board = BoardOps.generate_initial(gen)
	s.next_id = gen.next_id

	if with_accounting:
		attach_accounting(s)

	return s


## Attaches a metrics accumulator and a battle log to a state that has none.
##
## Seeded from the battle's ACTIVE roster on both sides, so an inventory Program
## that is not in the build has no metrics slot to be confused by.
static func attach_accounting(s: GameState) -> void:
	var player_ids: Array = []
	for u in (s.units[Types.Side.PLAYER] as Array):
		player_ids.append(u.program_id)
	var enemy_ids: Array = []
	for u in (s.units[Types.Side.ENEMY] as Array):
		enemy_ids.append(u.program_id)
	s.metrics = Metrics.create(player_ids, enemy_ids)
	s.metrics.turns = s.turn
	s.log = BattleLog.new(s.battle_id)


static func _units_for(program_ids: Array) -> Array:
	var out: Array = []
	for pid in program_ids:
		var prog := Content.program(pid)
		var charge := int(prog["charge_cap"]) if prog["fn"]["start_charged"] else 0
		out.append(GameState.UnitState.new(pid, charge))
	return out

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
static func default_build() -> Array:
	var hacker := Content.hacker(Content.DEFAULT_HACKER_ID)
	var deck := Content.deck(Content.DEFAULT_DECK_ID)
	var inventory: Array = []
	inventory.append_array(hacker["portfolio"])
	inventory.append_array(deck["portfolio"])

	# Hacker portfolio Programs 1 and 2, then Deck portfolio Programs 1 and 2.
	var build: Array = []
	build.append(inventory[0])
	build.append(inventory[1])
	build.append(inventory[Content.PORTFOLIO_SIZE])
	build.append(inventory[Content.PORTFOLIO_SIZE + 1])
	return build


## Builds a playable Quick Match.
##
## `build` is the ordered active build — exactly four distinct inventory
## Programs, top to bottom. That order is charge-routing priority.
static func create_quick_match(
	system_id: String,
	host_id: String,
	seed_value: int,
	build: Array,
	settings: Dictionary = {}
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

	return s


static func _units_for(program_ids: Array) -> Array:
	var out: Array = []
	for pid in program_ids:
		var prog := Content.program(pid)
		var charge := int(prog["charge_cap"]) if prog["fn"]["start_charged"] else 0
		out.append(GameState.UnitState.new(pid, charge))
	return out

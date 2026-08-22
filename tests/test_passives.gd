extends RefCounted

## Resolved content assembly and the PASSIVE runtime.
##
## The stacking rule is the thing worth testing hardest: an instance is NOT
## identified by its PASSIVE_ID, so the same row supplied by two sources is two
## instances that both apply. A port that deduplicated by ID would quietly halve
## several effects and pass every other test in the suite.


func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("passives")
		t.check("content loads", false)
		return

	Content.set_active(result["content"])
	Passives.clear_cache()

	_test_resolved_content(t)
	_test_instance_assembly(t)
	_test_scope_resolution(t)
	_test_stacking(t)
	_test_start_of_turn_order(t)

	Content.clear()
	Passives.clear_cache()


func _test_resolved_content(t: TestCase) -> void:
	t.group("content / resolution")

	var prog := Content.program("PRG_H_001")
	t.eq("Program resolves by stable ID", str(prog["id"]), "PRG_H_001")
	t.eq("Program is player-side", prog["side"], Types.Side.PLAYER)
	# Cross-links are resolved OBJECTS, so combat never walks a map mid-battle.
	t.check("Program carries its resolved Function", (prog["fn"] as Dictionary).has("plan"))
	# A charge pool's capacity IS its Function's cost — the invariant that makes
	# a zero-cost assigned Function illegal.
	t.eq("charge cap equals Function cost", prog["charge_cap"], prog["fn"]["cost"])

	var sys_prog := Content.program("PRG_S_001")
	t.eq("System Program is enemy-side", sys_prog["side"], Types.Side.ENEMY)

	t.eq("player Program count", Content.programs_for(Types.Side.PLAYER).size(), 6)
	t.eq("enemy Program count", Content.programs_for(Types.Side.ENEMY).size(), 8)

	var hacker := Content.hacker(Content.DEFAULT_HACKER_ID)
	t.eq("Hacker resolves", str(hacker["id"]), "HAK_01")
	t.eq("Hacker PASSIVEs resolved to objects", (hacker["passives"] as Array).size(), (hacker["passive_ids"] as Array).size())

	var deck := Content.deck(Content.DEFAULT_DECK_ID)
	t.check("Deck carries its resolved Function", (deck["fn"] as Dictionary).has("plan"))

	t.eq("fingerprint travels with the content", Content.fingerprint(), "49c229cd-8ma")


## THRESHOLD contributes nothing, so a battle on it has only the Hacker's own
## PASSIVEs — a useful baseline before the stacking cases.
func _test_instance_assembly(t: TestCase) -> void:
	t.group("passives / instance assembly")

	var identity := _identity("SYS_01", "HST_01", [])
	var instances := Passives.active(identity)

	var hacker := Content.hacker("HAK_01")
	var sys := Content.system("SYS_01")
	var expected := (hacker["passives"] as Array).size() + (sys["passives"] as Array).size()
	t.eq("instance count on an empty HOST", instances.size(), expected)

	# Canonical order: Hacker, System, HOST, then UPGRADEs.
	if instances.size() > 0:
		t.eq("Hacker instances come first", instances[0].source_kind, Types.PassiveSourceKind.HAK)
		t.eq("and are Hacker-owned", instances[0].owner, Types.Side.PLAYER)

	# A HOST instance is unowned. That is a deliberate third category, not a
	# missing value: collapsing it into an agent would lose the causal fact that
	# the battlefield did it.
	var weeds := _identity("SYS_01", "HST_05", [])
	var host_instances := []
	for inst in Passives.active(weeds):
		if inst.source_kind == Types.PassiveSourceKind.HST:
			host_instances.append(inst)
	t.check("WEEDS supplies a HOST instance", host_instances.size() > 0)
	if host_instances.size() > 0:
		t.eq("a HOST instance is unowned", host_instances[0].owner, Passives.NO_OWNER)


func _test_scope_resolution(t: TestCase) -> void:
	t.group("passives / scope")

	var identity := _identity("SYS_01", "HST_05", [])
	for inst in Passives.active(identity):
		if inst.source_kind == Types.PassiveSourceKind.HST:
			# A HOST ignores the authored agent_scope entirely and applies to
			# both agents symmetrically.
			t.check("HOST instance affects the player", Passives.affects(inst, Types.Side.PLAYER))
			t.check("HOST instance affects the enemy", Passives.affects(inst, Types.Side.ENEMY))
		elif inst.owner != Passives.NO_OWNER:
			var scope: String = inst.passive["agent_scope"]
			if scope == "OWNER":
				t.check("%s OWNER affects its supplier" % inst.passive["id"], Passives.affects(inst, inst.owner))
				t.check("%s OWNER spares the opponent" % inst.passive["id"], not Passives.affects(inst, Types.opponent_of(inst.owner)))
			else:
				t.check("%s ENEMY affects the opponent" % inst.passive["id"], Passives.affects(inst, Types.opponent_of(inst.owner)))
				t.check("%s ENEMY spares its supplier" % inst.passive["id"], not Passives.affects(inst, inst.owner))


## PSV_003 is referenced by BITMIRE (a HOST) and by L33TSK1LL (an UPGRADE). With
## both present those are two instances that BOTH apply — the single most
## important property of the PASSIVE layer.
func _test_stacking(t: TestCase) -> void:
	t.group("passives / stacking by source")

	var host_only := _identity("SYS_01", "HST_02", [])
	var both := _identity("SYS_01", "HST_02", ["UPG_03"])

	# PSV_003 is authored ENEMY-scoped, so the two sources land differently:
	# BITMIRE is a HOST and therefore unowned, applying to BOTH agents, while
	# L33TSK1LL is Hacker-owned and so hits the Hacker's opponent only. The
	# stacking is visible on the ENEMY side — checking the player would test the
	# scope rules rather than the stacking rule, and would correctly find one
	# instance in both cases.
	t.eq(
		"the player is dampened by the HOST alone",
		Passives.affecting(both, PassiveEffects.CHARGE_DAMPEN, Types.Side.PLAYER).size(),
		Passives.affecting(host_only, PassiveEffects.CHARGE_DAMPEN, Types.Side.PLAYER).size(),
	)

	var enemy_host_only := Passives.affecting(host_only, PassiveEffects.CHARGE_DAMPEN, Types.Side.ENEMY).size()
	var enemy_both := Passives.affecting(both, PassiveEffects.CHARGE_DAMPEN, Types.Side.ENEMY).size()
	t.check("the HOST alone dampens the enemy", enemy_host_only >= 1)
	t.eq("the same PSV row from a second source is a SECOND instance", enemy_both, enemy_host_only + 1)

	# Magnitude stacks additively simply by counting instances.
	var host_dampen := Passives.charge_dampen(host_only, Types.Side.ENEMY)
	var both_dampen := Passives.charge_dampen(both, Types.Side.ENEMY)
	t.check("dampening magnitude stacks additively", both_dampen > host_dampen)

	# An UPGRADE is always Hacker-owned, whatever side its effect lands on.
	for inst in Passives.active(both):
		if inst.source_kind == Types.PassiveSourceKind.UPG:
			t.eq("UPGRADE instances are Hacker-owned", inst.owner, Types.Side.PLAYER)

	# Permanent Shield is not a Packet and is summed from instances.
	var bracer := _identity("SYS_01", "HST_01", ["UPG_01"])
	t.check("BRACER supplies permanent Shield", Passives.permanent_shield(bracer, Types.Side.PLAYER) > 0)
	t.eq("and none to the enemy", Passives.permanent_shield(bracer, Types.Side.ENEMY), 0)

	# VERDUN advances Bombs one NAMED step per active instance.
	var verdun := _identity("SYS_01", "HST_04", [])
	t.eq("VERDUN advances Bombs one step", Passives.bigger_bomb_steps(verdun, Types.Side.PLAYER), 1)


## HOST first, then the ACTIVE agent's own, then UPGRADEs — and UPGRADE
## triggers belong to the Hacker's turn only.
func _test_start_of_turn_order(t: TestCase) -> void:
	t.group("passives / start-of-turn order")

	var identity := _identity("SYS_01", "HST_05", ["UPG_04"])

	var player_order := Passives.start_of_turn(identity, Types.Side.PLAYER)
	var seen_non_host := false
	var order_ok := true
	for inst in player_order:
		if inst.source_kind == Types.PassiveSourceKind.HST:
			if seen_non_host:
				order_ok = false
		else:
			seen_non_host = true
	t.check("HOST triggers resolve before any other source", order_ok)

	var has_upgrade := false
	for inst in player_order:
		if inst.source_kind == Types.PassiveSourceKind.UPG:
			has_upgrade = true
	t.check("SNEAKERS triggers on the Hacker's turn", has_upgrade)

	var enemy_order := Passives.start_of_turn(identity, Types.Side.ENEMY)
	var enemy_has_upgrade := false
	for inst in enemy_order:
		if inst.source_kind == Types.PassiveSourceKind.UPG:
			enemy_has_upgrade = true
	t.check("UPGRADE triggers never fire on the System's turn", not enemy_has_upgrade)

	# Every returned instance is genuinely triggered — a continual modifier
	# appearing here would fire an effect that is meant to apply passively.
	for inst in player_order:
		t.eq("%s is START_OF_TURN" % inst.passive["id"], str(inst.passive["activation"]), "START_OF_TURN")


func _identity(system_id: String, host_id: String, upgrades: Array) -> Dictionary:
	return {
		"cache_key": "%s|%s|%s" % [system_id, host_id, ":".join(PackedStringArray(upgrades))],
		"hacker_id": Content.DEFAULT_HACKER_ID,
		"deck_id": Content.DEFAULT_DECK_ID,
		"opponent_kind": Types.OpponentKind.SYS,
		"opponent_id": system_id,
		"host_id": host_id,
		"upgrade_ids": upgrades,
	}

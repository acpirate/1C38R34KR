class_name Route
extends RefCounted

## Route offer generation — the two encounter packages offered before every Run
## battle.
##
## A Run is a sequence of PATH CHOICES: the player picks one of two offered
## `SYS + HST + UPG` packages, and the choice is committed BEFORE the Build
## screen opens so the build can be edited against a known encounter.
##
## ---------------------------------------------------------------------------
## DRAW ORDER IS PART OF THE CONTRACT
## ---------------------------------------------------------------------------
##
## Every generator here consumes the route stream in exactly the order the alpha
## does, and the fixed-seed fixture in `tests/fixtures/route.json` is generated
## from the alpha and compared against these functions. A "cleaner"
## implementation that produced the same *kind* of result while consuming a
## different number of draws would pass every behavioural test in this file and
## silently make that fixture meaningless.
##
## The four places it matters, all load-bearing:
##
##   1. UPGRADEs are picked FIRST, before any System or HOST.
##   2. `pick_offer_upgrades` shuffles the WHOLE eligible array and takes the
##      first two — it is not two picks — and consumes NO draws at all when only
##      one UPGRADE remains.
##   3. `later_path_offers` resolves the distinct-pair rule with a RETRY LOOP
##      over the ordinary sampler (two draws per attempt), not by exclusion.
##   4. `boss_path_offers` retries the HOST only (one draw per attempt).
##
## Do not "optimize" any of these. See port-notes P-018.


## One valid loaded System, sampled with replacement from the RANDOM pool.
##
## Repeats across Run battles are allowed: there is no shuffle bag and no
## anti-repeat rule beyond the within-one-offer pair rule below.
static func random_system(rng: Rng) -> String:
	var pool := Content.pool_systems()
	return pool[rng.int_below(pool.size())]["id"]


static func random_host(rng: Rng) -> String:
	var pool := Content.pool_hosts()
	return pool[rng.int_below(pool.size())]["id"]


## The eligible UPGRADE pool is every valid row not already acquired this Run.
##
## Offer DISTINCT IDs whenever at least two remain. When exactly one remains,
## both paths legitimately show it and that is not a validation error — it is
## the intended endgame of a four-UPGRADE pool and four acquisition decisions.
##
## Returns `{"ids": Array, "exhausted": bool}`, or an empty Dictionary when the
## pool is empty — unreachable with valid content, but a content change must not
## produce an offer carrying no reward at all.
static func pick_offer_upgrades(rng: Rng, acquired: Array) -> Dictionary:
	var eligible: Array = []
	for u in Content.all_upgrades():
		if not acquired.has(u["id"]):
			eligible.append(u["id"])

	if eligible.is_empty():
		push_error("no eligible UPGRADE remains for a path offer")
		return {}

	# The one-remaining case consumes NO route RNG. Shuffling a single-element
	# array would still be a draw in some implementations; the alpha returns
	# before touching the stream, and so must this.
	if eligible.size() == 1:
		var ids: Array = []
		for i in Content.PATH_CHOICE_COUNT:
			ids.append(eligible[0])
		return {"ids": ids, "exhausted": true}

	rng.shuffle(eligible)
	return {"ids": eligible.slice(0, Content.PATH_CHOICE_COUNT), "exhausted": false}


## Battle 1's offers. Both paths are the FIXED DOORMAN + THRESHOLD encounter;
## the only intended difference is the UPGRADE, so the player's first real
## decision is which reward to take.
static func initial_path_offers(rng: Rng, acquired: Array) -> Run.PendingPath:
	var upgrades := pick_offer_upgrades(rng, acquired)
	if upgrades.is_empty():
		return null

	var p := Run.PendingPath.new()
	p.step = 1
	p.upgrade_exhausted = upgrades["exhausted"]
	for i in Content.PATH_CHOICE_COUNT:
		p.offers.append(Run.PathOffer.new(
			i,
			Types.OpponentKind.SYS,
			Content.INITIAL_SYSTEM_ID,
			Content.INITIAL_HOST_ID,
			upgrades["ids"][i],
		))
	return p


## Offers for Battles 2 and 3: one valid System and one valid HOST per path,
## independently randomized from the in-pool subsets, plus one eligible UPGRADE.
##
## The pair rule: avoid two identical `SYS + HST` pairs within ONE offer whenever
## another valid combination exists. Sharing a System OR a HOST is fine, and
## repeating a PRIOR battle's encounter is fine — this is deliberately a retry
## loop over the ordinary sampler rather than a shuffle-bag or no-repeat policy.
static func later_path_offers(rng: Rng, step: int, acquired: Array) -> Run.PendingPath:
	var upgrades := pick_offer_upgrades(rng, acquired)
	if upgrades.is_empty():
		return null

	var p := Run.PendingPath.new()
	p.step = step
	p.upgrade_exhausted = upgrades["exhausted"]

	var pairs: Array = []
	for i in Content.PATH_CHOICE_COUNT:
		var combos := Content.pool_systems().size() * Content.pool_hosts().size()
		var opponent_id := random_system(rng)
		var host_id := random_host(rng)
		if combos > 1:
			# The guard bounds an unlucky stream rather than expressing a rule.
			# On the first iteration `pairs` is empty, so this never spins.
			var guard := 0
			while _has_pair(pairs, opponent_id, host_id) and guard < 32:
				opponent_id = random_system(rng)
				host_id = random_host(rng)
				guard += 1
		pairs.append({"opponent_id": opponent_id, "host_id": host_id})
		p.offers.append(Run.PathOffer.new(
			i, Types.OpponentKind.SYS, opponent_id, host_id, upgrades["ids"][i]
		))
	return p


## The FINAL path offers. Both paths lead to the Boss the player committed at
## New Run start; only the HOST and, pool permitting, the UPGRADE differ.
##
## There is deliberately no random Boss routing and no normal System opponent at
## Battle 4. Beta 0.2 generates and commits this package but stops before the
## battle itself — see `Run.enter_pending_boss_battle`.
static func boss_path_offers(rng: Rng, step: int, boss_id: String, acquired: Array) -> Run.PendingPath:
	var upgrades := pick_offer_upgrades(rng, acquired)
	if upgrades.is_empty():
		return null

	var p := Run.PendingPath.new()
	p.step = step
	p.upgrade_exhausted = upgrades["exhausted"]

	var hosts: Array = []
	for i in Content.PATH_CHOICE_COUNT:
		var host_id := random_host(rng)
		# Avoid offering the same `Boss + HST` pair twice while at least two
		# eligible HOSTs exist. With current content THRESHOLD is out of the
		# random pool and four escalation HOSTs remain, so two distinct HOSTs
		# are the normal outcome. If future content leaves exactly one eligible
		# HOST, a duplicate is ALLOWED rather than failing route generation.
		if Content.pool_hosts().size() > 1:
			var guard := 0
			while hosts.has(host_id) and guard < 32:
				host_id = random_host(rng)
				guard += 1
		hosts.append(host_id)
		p.offers.append(Run.PathOffer.new(
			i, Types.OpponentKind.BOS, boss_id, host_id, upgrades["ids"][i]
		))
	return p


## Dispatch by step: Battle 1 is the fixed intro, Battle 4 routes to the Boss,
## everything between is an escalation route.
##
## Kept in one place so no caller has to remember which step is special — a
## `step == 1` check scattered across the session layer is exactly how the intro
## encounter would eventually be generated randomly by accident.
static func offers_for_step(rng: Rng, step: int, boss_id: String, acquired: Array) -> Run.PendingPath:
	if step == 1:
		return initial_path_offers(rng, acquired)
	if step == Run.RUN_LENGTH:
		return boss_path_offers(rng, step, boss_id, acquired)
	return later_path_offers(rng, step, acquired)


static func _has_pair(pairs: Array, opponent_id: String, host_id: String) -> bool:
	for p in pairs:
		if p["opponent_id"] == opponent_id and p["host_id"] == host_id:
			return true
	return false

extends SceneTree

## Emits the normalized SESSION state of deterministic Runs, for comparison
## against the alpha through `tools/gen/run_trace_alpha.ts`.
##
##   godot --headless -s res://tools/run_trace.gd -- --seeds 0-199
##   godot --headless -s res://tools/run_trace.gd -- --seed 42 --full
##
## ---------------------------------------------------------------------------
## What this compares, and what it deliberately does not
## ---------------------------------------------------------------------------
##
## This walks the Run/progression layer ONLY. It plays no battles: every
## encounter is treated as won, because battle behaviour is already proven by
## DEEPSCAN and re-running it here would be paying twice for the same evidence.
##
## What it compares is the externally meaningful session state the authorization
## names (§21.2): offered and committed identities, acquisition order, in-pool
## legality, the resolved encounter ICE, and the route stream's progression.
##
## ---------------------------------------------------------------------------
## The record format is an ordered ARRAY of tokens, not an object
## ---------------------------------------------------------------------------
##
## Hashing a stringified object across two languages means depending on key
## order surviving GDScript Dictionary iteration, JavaScript object property
## order, and both serializers agreeing on number formatting. Tokens joined in a
## fixed order have none of those failure modes, and a divergence points at a
## field rather than at the serializer.
##
## THE CHOICE POLICY IS PART OF THE COMPARISON. Both engines must take the same
## path at every fork or the walks diverge legitimately and prove nothing.

const PATH_FIELD_SEP := ":"
const TOKEN_SEP := "|"


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

	var boss_id: String = Content.all_bosses()[0]["id"]
	for seed_value in args["seeds"]:
		var lines := _walk(seed_value, boss_id)
		if args["full"]:
			print("# seed %d" % seed_value)
			for line in lines:
				print(line)
		else:
			print(JSON.stringify({"seed": seed_value, "hash": _hash(lines)}))

	quit(0)


## One complete Run walk, as normalized lines.
##
## Every battle is treated as won. A defeat/retry path would exercise the same
## route code with an extra no-op, so it adds nothing here — retry is covered
## behaviourally in `test_run_battle.gd`.
func _walk(seed_value: int, boss_id: String) -> Array:
	var lines: Array = []

	var setup := RunSetup.commit_boss(boss_id, Constants.default_settings(), seed_value)
	setup = setup.commit_hacker(Content.DEFAULT_HACKER_ID)
	var r := setup.commit_deck(Content.DEFAULT_DECK_ID)

	lines.append(TOKEN_SEP.join([
		"setup",
		r.boss_id,
		r.hacker_id,
		r.deck_id,
		str(r.hacker_max_link),
		",".join(PackedStringArray(r.inventory)),
		",".join(PackedStringArray(r.build)),
	] as PackedStringArray))

	while true:
		lines.append(_offers_line(r))

		var choice := _choose(seed_value, r.step)
		r.select_path(choice)
		lines.append(_committed_line(r, choice))

		if r.step == Run.RUN_LENGTH:
			# The beta 0.2 stop. The Run holds a committed Boss package and does
			# NOT proceed to a battle or mark itself complete.
			r.enter_pending_boss_battle()
			lines.append(TOKEN_SEP.join([
				"stop",
				Types.SESSION_PHASE_NAMES[r.phase],
				str(r.step),
				r.opponent_id,
				r.host_id,
				",".join(PackedStringArray(r.upgrade_ids)),
			] as PackedStringArray))
			break

		if not r.advance_after_victory():
			lines.append("error|advance refused at step %d" % r.step)
			break

	return lines


func _offers_line(r: Run) -> String:
	var parts: Array = ["offers", str(r.pending_path.step)]
	for o in r.pending_path.offers:
		parts.append(PATH_FIELD_SEP.join([
			str(o.index),
			Types.OPPONENT_KIND_NAMES[o.opponent_kind],
			o.opponent_id,
			o.host_id,
			o.upgrade_id,
		] as PackedStringArray))
	parts.append("exhausted=%s" % ("1" if r.pending_path.upgrade_exhausted else "0"))
	parts.append("route=%d" % r.route_rng_state)
	return TOKEN_SEP.join(PackedStringArray(parts))


func _committed_line(r: Run, choice: int) -> String:
	return TOKEN_SEP.join([
		"commit",
		str(r.step),
		str(choice),
		Types.OPPONENT_KIND_NAMES[r.opponent_kind],
		r.opponent_id,
		r.host_id,
		",".join(PackedStringArray(r.upgrade_ids)),
		",".join(PackedStringArray(r.build)),
		Types.BUILD_ORIGIN_NAMES[r.build_origin],
		# Resolved ICE, including the Boss rule at step 4. A port that applied
		# the step-4 modifier on top of the Boss's authored base diverges here.
		"ice=%d" % r.encounter_ice(),
		"route=%d" % r.route_rng_state,
	] as PackedStringArray)


## The choice policy, which BOTH engines must reproduce exactly.
##
## Alternating on seed and step so a body of seeds covers taking the left path,
## the right path, and every mixture, rather than only ever walking one edge of
## the tree.
static func _choose(seed_value: int, step: int) -> int:
	return (seed_value + step) % Content.PATH_CHOICE_COUNT


func _hash(lines: Array) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for line in lines:
		ctx.update((str(line) + "\n").to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


func _parse_args() -> Dictionary:
	var out := {"seeds": [0], "full": false}
	var argv := OS.get_cmdline_user_args()
	var i := 0
	while i < argv.size():
		match argv[i]:
			"--seeds":
				i += 1
				out["seeds"] = _parse_range(argv[i])
			"--seed":
				i += 1
				out["seeds"] = [int(argv[i])]
			"--full":
				out["full"] = true
		i += 1
	return out


## Accepts `0-199` or `3`.
static func _parse_range(spec: String) -> Array:
	var out: Array = []
	if spec.contains("-"):
		var halves := spec.split("-")
		for v in range(int(halves[0]), int(halves[1]) + 1):
			out.append(v)
	else:
		out.append(int(spec))
	return out


func _process(_delta: float) -> bool:
	printerr("run_trace: reached the main loop without quitting — aborting")
	return true

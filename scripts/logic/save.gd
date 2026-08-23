class_name SaveState
extends RefCounted

## Save serialization for an active battle.
##
## Schema 1 — a NEW format for a new engine. Alpha saves are not readable and
## there is no migration path: an alpha save has no equivalent of this state and
## restoring one would mean inventing it.
##
## The discipline carried over from the alpha is the valuable part:
##
##   - identity is stored as STABLE IDs, never as copied definitions, so
##     immutable content resolves through the fingerprint rather than being
##     duplicated into every save
##   - a mismatched fingerprint, unknown ID, or stale build is REJECTED rather
##     than silently defaulted — invalid data is never quietly repaired
##   - RNG state is persisted, because a resumed battle must continue the same
##     sequence an uninterrupted one would
##
## That last point is why the test for this is a CONTINUATION test rather than a
## round-trip equality test: a round trip passes with an incompletely captured
## RNG state, a dropped countdown, or a lost stamped area pattern. Continuing to
## the end and comparing the event stream does not.

const SCHEMA := 1
const SAVE_PATH := "user://save.json"


static func to_dict(state: GameState) -> Dictionary:
	return {
		"schema": SCHEMA,
		"game_version": Content.GAME_VERSION,
		# Immutable definitions are NOT copied in. They resolve through this
		# fingerprint, so a content edit invalidates the save honestly instead of
		# silently changing what the battle meant.
		"fingerprint": Content.fingerprint(),
		"battle_id": state.battle_id,
		"turn": state.turn,
		"phase": Types.PHASE_NAMES[state.phase],
		"winner": null if state.winner == -1 else Types.SIDE_NAMES[state.winner],
		"rng_state": state.rng.get_state(),
		"next_id": state.next_id,
		"next_seq": state.next_seq,
		"hp": state.hp.duplicate(),
		"deck_charge": state.deck_charge,
		"units": [_units_to_array(state.units[0]), _units_to_array(state.units[1])],
		"identity": state.identity.duplicate(true),
		"config": _config_to_dict(state.config),
		"board": _board_to_array(state.board),
	}


static func _units_to_array(units: Array) -> Array:
	var out: Array = []
	for u in units:
		out.append({"program_id": u.program_id, "charge": u.charge})
	return out


## Enum-valued settings cross the boundary as their string forms, matching the
## alpha's spelling so a save is readable next to one of its traces.
static func _config_to_dict(config: Dictionary) -> Dictionary:
	var out := config.duplicate(true)
	out["strong_colors"] = [config["strong_colors"][0], config["strong_colors"][1]]
	out["strong_shapes"] = [config["strong_shapes"][0], config["strong_shapes"][1]]
	return out


static func _board_to_array(board: Array) -> Array:
	var out: Array = []
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			var t: Tile = board[y][x]
			# A concluded battle's board may legitimately hold gaps: resolution
			# halts at game over rather than continuing to settle.
			if t == null:
				out.append(null)
				continue
			var rec := {"id": t.id, "kind": t.kind, "color": t.color, "shape": t.shape}
			if t.has_special():
				rec["special"] = _special_to_dict(t.special)
			out.append(rec)
	return out


## An armed overlay carries the parameters STAMPED on it when it was armed —
## its countdown, what it delivers, and the resolved area pattern. Persisting
## all of it is what makes "a save, a resume, and a later detonation all agree"
## true by construction rather than by luck.
static func _special_to_dict(sp: Tile.Special) -> Dictionary:
	return {
		"type": sp.type, "owner": sp.owner, "countdown": sp.countdown,
		"delivers": sp.delivers, "area_pattern": sp.area_pattern,
		"magnitude": sp.magnitude, "program_id": sp.program_id, "fn_id": sp.fn_id,
		"deal_damage": sp.deal_damage, "gain_charge": sp.gain_charge, "seq": sp.seq,
	}


# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------

## Returns `{ok, state, reason}`.
##
## Every rejection is explicit. Restoring a save that no longer matches its
## content would mean inventing state, which is exactly the silent repair the
## contract forbids.
static func from_dict(data: Dictionary) -> Dictionary:
	if int(data.get("schema", -1)) != SCHEMA:
		return _reject("save schema %s is not %d" % [data.get("schema", "absent"), SCHEMA])
	if str(data.get("fingerprint", "")) != Content.fingerprint():
		return _reject("content fingerprint does not match this build")

	var s := GameState.new()
	s.battle_id = str(data["battle_id"])
	s.turn = int(data["turn"])
	s.phase = Types.value_of(Types.PHASE_NAMES, str(data["phase"]))
	if s.phase < 0:
		return _reject("unknown phase '%s'" % data["phase"])

	var winner = data.get("winner", null)
	s.winner = -1 if winner == null else Types.value_of(Types.SIDE_NAMES, str(winner))

	# The RNG is reconstructed FROM ITS STATE, not from the original seed:
	# makeRNG(state) resumes the exact sequence, which is what continuation
	# determinism rests on.
	s.rng = Rng.new(int(data["rng_state"]))
	s.next_id = int(data["next_id"])
	s.next_seq = int(data["next_seq"])
	s.deck_charge = int(data["deck_charge"])
	s.hp = [int(data["hp"][0]), int(data["hp"][1])]
	s.identity = (data["identity"] as Dictionary).duplicate(true)
	s.config = _config_from_dict(data["config"])

	var units := _units_from_array(data["units"])
	if not units["ok"]:
		return _reject(units["reason"])
	s.units = units["units"]

	s.board = _board_from_array(data["board"])
	return {"ok": true, "state": s, "reason": ""}


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "state": null, "reason": reason}


## A Program ID that no longer resolves means the content changed under the
## save. Rejected rather than dropped: a battle missing a Program from its build
## is not the battle that was saved.
static func _units_from_array(raw: Array) -> Dictionary:
	var sides: Array = []
	for side_raw in raw:
		var side: Array = []
		for u in (side_raw as Array):
			var pid := str(u["program_id"])
			if Content.program(pid).is_empty():
				return {"ok": false, "reason": "save references unknown Program '%s'" % pid}
			side.append(GameState.UnitState.new(pid, int(u["charge"])))
		sides.append(side)
	return {"ok": true, "units": sides, "reason": ""}


static func _config_from_dict(raw: Dictionary) -> Dictionary:
	var out := raw.duplicate(true)
	# JSON gives every number as a float; the settings are compared and used as
	# ints and bools, so they are coerced back here rather than at each use.
	for key in ["player_hp", "enemy_hp", "manual_hacker_link", "manual_system_ice", "hint_delay_seconds"]:
		if out.has(key) and out[key] != null:
			out[key] = int(out[key])
	if out.has("max_cascade_steps") and out["max_cascade_steps"] != null:
		out["max_cascade_steps"] = int(out["max_cascade_steps"])
	for side in 2:
		out["strong_colors"][side] = _to_int_array(out["strong_colors"][side])
		out["strong_shapes"][side] = _to_int_array(out["strong_shapes"][side])
	return out


static func _to_int_array(raw) -> Array:
	var out: Array = []
	for v in (raw as Array):
		out.append(int(v))
	return out


static func _board_from_array(raw: Array) -> Array:
	var board := BoardOps.empty_board()
	for i in raw.size():
		var rec = raw[i]
		if rec == null:
			continue
		var x := i % Constants.BOARD_WIDTH
		var y := i / Constants.BOARD_WIDTH
		var t := Tile.new()
		t.id = int(rec["id"])
		t.kind = int(rec["kind"])
		t.color = int(rec["color"])
		t.shape = int(rec["shape"])
		if rec.has("special"):
			t.special = _special_from_dict(rec["special"])
		board[y][x] = t
	return board


static func _special_from_dict(raw: Dictionary) -> Tile.Special:
	var sp := Tile.Special.new()
	sp.type = int(raw["type"])
	sp.owner = int(raw["owner"])
	sp.countdown = int(raw["countdown"])
	sp.delivers = str(raw["delivers"])
	sp.area_pattern = str(raw["area_pattern"])
	sp.magnitude = int(raw["magnitude"])
	sp.program_id = str(raw["program_id"])
	sp.fn_id = str(raw["fn_id"])
	sp.deal_damage = int(raw["deal_damage"])
	sp.gain_charge = int(raw["gain_charge"])
	sp.seq = int(raw["seq"])
	return sp


# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

static func write(state: GameState) -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(to_dict(state)))
	f.close()
	return true


static func read() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return _reject("no save present")
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return _reject("cannot read %s" % SAVE_PATH)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return _reject("save is not valid JSON")
	return from_dict(parsed)


static func clear() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

class_name SessionSave
extends RefCounted

## The SESSION save envelope.
##
## Beta 0.1 saved a battle and nothing else, because a Quick Match is always
## inside one. A Run is saveable with NO battle at all — parked on a Path
## Choice, on a pre-battle Build, on a result, or on the beta 0.2
## `PENDING_BOSS_BATTLE` stop — so the battle record becomes a MEMBER of a
## session envelope rather than the top level.
##
## ---------------------------------------------------------------------------
## Two schemas, versioned independently
## ---------------------------------------------------------------------------
##
## `SCHEMA` here versions the ENVELOPE. The nested battle record keeps its own
## `SaveState.SCHEMA`, unchanged and still written and validated by the beta 0.1
## serializer. That serializer carries the continuation proof this build has no
## reason to re-earn, so it is reused verbatim rather than folded in.
##
## ---------------------------------------------------------------------------
## Old saves are rejected, never migrated
## ---------------------------------------------------------------------------
##
## A beta 0.1 save has no envelope, so it does not load. That is the finished
## behaviour and not a stopgap (D-030): for the whole pre-release beta line, a
## version bump invalidates saves and they are discarded. No migration path, no
## compatibility shim, no test that a save survives a version boundary.
##
## What IS required is that a save survives within a version, which is what the
## resume tests cover.

const SCHEMA := 3
const SAVE_PATH := "user://save.json"


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

## A Run in setup: committed Boss, whatever identity is committed, and nothing
## that does not exist yet.
static func setup_to_dict(s: RunSetup) -> Dictionary:
	return _base(Types.MODE_NAMES[Types.Mode.RUN] + "_SETUP", Types.SESSION_PHASE_NAMES[s.phase()], {
		"setup": s.to_dict(),
	})


## A committed Run, with its battle when one is in progress.
##
## `battle` is null while the Run sits on a Path Choice, a Build, or the
## PENDING_BOSS_BATTLE stop. Through beta 0.1 a save required a battle, which
## would have silently dropped every one of those.
static func run_to_dict(r: Run, state: GameState) -> Dictionary:
	return _base(Types.MODE_NAMES[Types.Mode.RUN], Types.SESSION_PHASE_NAMES[r.phase], {
		"run": r.to_dict(),
		"battle": null if state == null else SaveState.to_dict(state),
	})


## A Quick Match, which always has a battle.
static func quick_match_to_dict(state: GameState) -> Dictionary:
	var phase := (
		Types.SESSION_PHASE_NAMES[Types.SessionPhase.PENDING_RESULT]
		if state.has_winner()
		else Types.SESSION_PHASE_NAMES[Types.SessionPhase.ACTIVE_BATTLE]
	)
	return _base(Types.MODE_NAMES[Types.Mode.QUICK_MATCH], phase, {
		"battle": SaveState.to_dict(state),
	})


static func _base(mode: String, phase: String, extra: Dictionary) -> Dictionary:
	var out := {
		"schema": SCHEMA,
		"game_version": Content.GAME_VERSION,
		# Immutable definitions are NOT copied in. They resolve through this
		# fingerprint, so a content edit invalidates the save honestly instead of
		# silently changing what the session meant.
		"fingerprint": Content.fingerprint(),
		"mode": mode,
		"phase": phase,
	}
	out.merge(extra)
	return out


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

## Restores a session.
##
## Returns `{ok, mode, setup, run, state, reason}`. On failure `ok` is false and
## `reason` says why — every rejection is reported rather than repaired, so a
## save that cannot be trusted is discarded honestly instead of being silently
## patched into something playable that is not what the player left.
static func from_dict(data: Dictionary) -> Dictionary:
	if int(data.get("schema", -1)) != SCHEMA:
		return _reject("session schema %s is not %d" % [data.get("schema", "absent"), SCHEMA])
	if str(data.get("fingerprint", "")) != Content.fingerprint():
		return _reject("content fingerprint does not match this build")

	var mode := str(data.get("mode", ""))

	if mode == "RUN_SETUP":
		var setup := RunSetup.from_dict(data.get("setup", {}))
		if setup == null:
			return _reject("setup state is not valid against current content")
		return {"ok": true, "mode": mode, "setup": setup, "run": null, "state": null, "reason": ""}

	if mode == "RUN":
		var r := Run.from_dict(data.get("run", {}))
		if r == null:
			return _reject("run state is not valid against current content")

		# The phase must agree with what is actually in the envelope. A Run
		# claiming ACTIVE_BATTLE with no battle record, or holding a battle it
		# says it is not in, is incoherent rather than recoverable.
		var has_battle := data.get("battle", null) != null
		var wants_battle := (
			r.phase == Types.SessionPhase.ACTIVE_BATTLE
			or r.phase == Types.SessionPhase.PENDING_RESULT
		)
		if wants_battle and not has_battle:
			return _reject("phase %s has no battle record" % Types.SESSION_PHASE_NAMES[r.phase])
		if has_battle and not wants_battle:
			return _reject("phase %s carries a battle it cannot be in" % Types.SESSION_PHASE_NAMES[r.phase])

		var state: GameState = null
		if has_battle:
			var restored := SaveState.from_dict(data["battle"])
			if not restored["ok"]:
				return _reject(restored["reason"])
			state = restored["state"]
			# The battle must be the one this Run committed to. A mismatch means
			# two different sessions were spliced together.
			if state.identity["opponent_id"] != r.opponent_id:
				return _reject("battle opponent does not match the Run's committed encounter")
			if state.identity["host_id"] != r.host_id:
				return _reject("battle HOST does not match the Run's committed encounter")
			if state.identity["upgrade_ids"] != r.upgrade_ids:
				return _reject("battle UPGRADEs do not match the Run's acquisitions")

		return {"ok": true, "mode": mode, "setup": null, "run": r, "state": state, "reason": ""}

	if mode == "QUICK_MATCH":
		if data.get("battle", null) == null:
			return _reject("a Quick Match save has no battle")
		var restored := SaveState.from_dict(data["battle"])
		if not restored["ok"]:
			return _reject(restored["reason"])
		return {
			"ok": true, "mode": mode, "setup": null, "run": null,
			"state": restored["state"], "reason": "",
		}

	return _reject("unknown session mode '%s'" % mode)


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "mode": "", "setup": null, "run": null, "state": null, "reason": reason}


# ---------------------------------------------------------------------------
# File access
# ---------------------------------------------------------------------------
#
# One writer for one path. `SaveState` no longer owns the file — a second writer
# to `user://save.json` is how a Run save and a Quick Match save would overwrite
# each other.

static func write(envelope: Dictionary) -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(envelope))
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


## Whether a save exists at all. Cheaper than reading one, and the title screen
## asks this before deciding whether to offer Continue.
static func exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

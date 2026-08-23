class_name LogStore
extends RefCounted

## Bounded persistence for `BattleLog` records.
##
## The alpha ran against a ~5 MB localStorage budget and re-serialized its whole
## history on every append. Godot gives us a real filesystem, so the quota
## strategy need not be copied literally — but "a real filesystem" is not a
## budget, and an unbounded log on a phone is a slow-motion disk leak. The cap
## stays; only the mechanism changes.
##
## Three streams, one file each, newline-delimited JSON:
##
## - `battles.jsonl` — one record per completed battle (final metrics plus the
##   content identity stamp). This is the AUTHORITY for everything
##   battle-static; the other two join to it by `battle_id`.
## - `turns.jsonl` — compact per-turn records, VERBOSE and above.
## - `events.jsonl` — high-value events, every level.
##
## Append is O(new bytes). Trimming reads and rewrites one file, and happens
## only when that file exceeds its cap — not on every write.

const DIR := "user://logs"

## Per-stream byte caps. Turns and events are the volume; battle records are one
## per battle and are the most valuable thing here, so they get room to survive
## a long session of noisy ones.
const BUDGET := {
	"battles": 1024 * 1024,
	"turns": 2 * 1024 * 1024,
	"events": 2 * 1024 * 1024,
}

## Fraction of a file kept when it is trimmed. Trimming to exactly the cap would
## mean re-trimming on nearly every subsequent append; taking a real bite makes
## the rewrite rare.
const TRIM_RETAIN := 0.7


static func _path(stream: String) -> String:
	return DIR.path_join("%s.jsonl" % stream)


static func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(DIR) == OK


## Appends records, then trims the stream if it has outgrown its budget.
##
## Failure to write a log is never fatal and never propagates: a full or
## read-only filesystem must not end a battle. It is reported once and dropped.
static func append(stream: String, records: Array) -> void:
	if records.is_empty():
		return
	if not _ensure_dir():
		push_warning("LogStore: could not create %s — logging disabled this session" % DIR)
		return

	var path := _path(stream)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		push_warning("LogStore: could not open %s (%d)" % [path, FileAccess.get_open_error()])
		return
	f.seek_end()
	for r in records:
		# JSON.stringify, not var_to_str: these files are meant to be readable
		# by the same tooling that reads the alpha's exports.
		f.store_line(JSON.stringify(r))
	var size := f.get_length()
	f.close()

	if size > int(BUDGET.get(stream, BUDGET["events"])):
		_trim(path, int(BUDGET.get(stream, BUDGET["events"])))


## Drops the OLDEST records until the file fits. Oldest-first because the
## interesting question is almost always "what happened recently", and a log
## that discards the newest entry to protect an old one answers the wrong one.
static func _trim(path: String, budget: int) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var lines := f.get_as_text().split("\n", false)
	f.close()

	var target := int(budget * TRIM_RETAIN)
	var kept := PackedStringArray()
	var total := 0
	# Walk backwards, keeping newest first, then reverse — so the cut lands on
	# the oldest records without measuring the whole file twice.
	for i in range(lines.size() - 1, -1, -1):
		var line := lines[i]
		total += line.length() + 1
		if total > target:
			break
		kept.append(line)
	kept.reverse()

	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return
	for line in kept:
		out.store_line(line)
	out.close()


## Writes one completed battle: the battle-level record plus whatever the log
## accumulated. Called once, at the end of a battle.
static func flush_battle(state: GameState, metrics: Metrics.Battle, log: BattleLog) -> void:
	if log == null:
		return

	append("battles", [{
		"v": Content.GAME_VERSION,
		"ls": BattleLog.LOGGING_SCHEMA_VERSION,
		"ms": BattleLog.METRICS_SCHEMA_VERSION,
		"lvl": BattleLog.level_name(BattleLog.level()),
		"battle_id": state.battle_id,
		"fp": Content.fingerprint(),
		"ended_at": Time.get_datetime_string_from_system(true),
		"winner": state.winner,
		"turns": state.turn,
		"config": state.config,
		# The identity stamp is the join target for every turn and event record,
		# which is why it is written once here and never repeated into them.
		"identity": state.identity,
		"metrics": {} if metrics == null else metrics.to_dict(),
	}])

	append("turns", log.turns)
	append("events", log.events)
	log.turns.clear()
	log.events.clear()


## Deletes every stream. The one destructive operation here, and it exists so a
## tester can start an investigation from a known-empty state rather than
## grepping past a week of unrelated battles.
static func clear() -> void:
	for stream in BUDGET:
		var path := _path(stream)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

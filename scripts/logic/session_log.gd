class_name SessionLog
extends RefCounted

## Structured observability for Run setup, routing, and progression.
##
## ---------------------------------------------------------------------------
## One pipeline, one more stream
## ---------------------------------------------------------------------------
##
## This is NOT a second instrumentation system (authorization §19). Records go
## through `LogStore.append` exactly as battle records do, into a fourth
## newline-delimited stream beside `battles`, `turns`, and `events`. The budget
## and trim policy are the existing ones.
##
## ---------------------------------------------------------------------------
## What these records are for
## ---------------------------------------------------------------------------
##
## They answer development and analysis questions — why did this Run offer that
## System, when was this UPGRADE acquired, what package did the Run stop on.
## They deliberately do NOT reproduce the alpha's menu-log schema, which has no
## consumer here; §19 explicitly prefers compact records over shape parity.
##
## Every record carries `run`, the Run's route seed. That is what makes a whole
## Run reassemblable from a log file with one grep, and what makes a Run reported
## from a device replayable in the harness.
##
## Written at BASIC and above. The volume argument that gates per-turn logging
## does not apply: a complete Run produces around a dozen of these.

const STREAM := "session"

## Setup and identity.
const BOSS_OFFERED := "BOSS_OFFERED"
const BOSS_SELECTED := "BOSS_SELECTED"
const HACKER_SELECTED := "HACKER_SELECTED"
const DECK_SELECTED := "DECK_SELECTED"
const RUN_CREATED := "RUN_CREATED"

## Routing and rewards.
const PATH_OFFERED := "PATH_OFFERED"
const PATH_SELECTED := "PATH_SELECTED"

## Progression.
const RUN_BATTLE_STARTED := "RUN_BATTLE_STARTED"
const RUN_RESULT := "RUN_RESULT"
const RUN_STOPPED := "RUN_STOPPED"
const RUN_COMPLETED := "RUN_COMPLETED"
const RUN_ABANDONED := "RUN_ABANDONED"

## Quick Match.
const QUICK_RANDOM_ROLLED := "QUICK_RANDOM_ROLLED"


static func _emit(event: String, run_seed: int, fields: Dictionary) -> void:
	var rec := {
		"v": Content.GAME_VERSION,
		"ls": BattleLog.LOGGING_SCHEMA_VERSION,
		"lvl": BattleLog.level_name(BattleLog.level()),
		"at": Time.get_datetime_string_from_system(true),
		"fp": Content.fingerprint(),
		"e": event,
		"run": run_seed,
	}
	rec.merge(fields)
	LogStore.append(STREAM, [rec])


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## What the player was actually shown, before what they picked. Recorded
## separately so a selection can be read against its alternatives rather than in
## isolation — "chose ODANSHAY" means something different when it was the only
## row than when it was one of six.
static func boss_offered(boss_ids: Array) -> void:
	_emit(BOSS_OFFERED, 0, {"boss_ids": boss_ids.duplicate()})


static func boss_selected(run_seed: int, boss_id: String) -> void:
	_emit(BOSS_SELECTED, run_seed, {"boss_id": boss_id})


## The destructive New-Run boundary. `route_seed` doubles as the Run's identity
## and as the value that reproduces its entire route sequence.
static func run_created(run_seed: int, boss_id: String) -> void:
	_emit(RUN_CREATED, run_seed, {"boss_id": boss_id, "route_seed": run_seed})


static func hacker_selected(run_seed: int, hacker_id: String) -> void:
	_emit(HACKER_SELECTED, run_seed, {"hacker_id": hacker_id})


static func deck_selected(run_seed: int, deck_id: String, inventory: Array, build: Array) -> void:
	_emit(DECK_SELECTED, run_seed, {
		"deck_id": deck_id,
		"inventory": inventory.duplicate(),
		"build": build.duplicate(),
	})


# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------

## Both offers, in full, plus the route stream state they were generated from.
##
## The stream state is the diagnostically valuable part: with it and the run
## seed, an offer that looks wrong can be regenerated in the harness rather than
## argued about from a screenshot.
static func path_offered(r: Run) -> void:
	var offers: Array = []
	for o in r.pending_path.offers:
		offers.append(o.to_dict())
	_emit(PATH_OFFERED, r.route_seed, {
		"step": r.pending_path.step,
		"offers": offers,
		"upgrade_exhausted": r.pending_path.upgrade_exhausted,
		"route_state": r.route_rng_state,
	})


## The committed package, and the acquisition list AFTER it.
##
## `upgrades` is the whole ordered list rather than just the new ID, because
## acquisition order is gameplay state (it is START_OF_TURN resolution order)
## and reconstructing it by replaying every prior record would be fragile.
static func path_selected(r: Run, index: int) -> void:
	_emit(PATH_SELECTED, r.route_seed, {
		"step": r.step,
		"index": index,
		"opponent_kind": Types.OPPONENT_KIND_NAMES[r.opponent_kind],
		"opponent_id": r.opponent_id,
		"host_id": r.host_id,
		"upgrades": r.upgrade_ids.duplicate(),
	})


# ---------------------------------------------------------------------------
# Progression
# ---------------------------------------------------------------------------

## `battle_id` is the join key into the `battles`, `turns`, and `events` streams,
## which is what connects a Run's routing decisions to how the battle actually
## went.
static func battle_started(r: Run, battle_id: String) -> void:
	_emit(RUN_BATTLE_STARTED, r.route_seed, {
		"step": r.step,
		"battle_id": battle_id,
		"opponent_kind": Types.OPPONENT_KIND_NAMES[r.opponent_kind],
		"opponent_id": r.opponent_id,
		"host_id": r.host_id,
		"ice": r.encounter_ice(),
		"link": r.hacker_max_link,
		"build": r.build.duplicate(),
		"build_origin": Types.BUILD_ORIGIN_NAMES[r.build_origin],
		"upgrades": r.upgrade_ids.duplicate(),
	})


static func run_result(r: Run, won: bool, action: String) -> void:
	_emit(RUN_RESULT, r.route_seed, {
		"step": r.step,
		"outcome": Types.NATURAL_OUTCOME_NAMES[
			Types.NaturalOutcome.NATURAL_VICTORY if won else Types.NaturalOutcome.NATURAL_DEFEAT
		],
		"action": action,
	})


## Beta 0.2's terminal state, and now the handoff into Battle 4: the complete
## committed package the Boss battle consumes.
static func run_stopped(r: Run) -> void:
	_emit(RUN_STOPPED, r.route_seed, {
		"phase": Types.SESSION_PHASE_NAMES[r.phase],
		"step": r.step,
		"boss_id": r.boss_id,
		"host_id": r.host_id,
		"upgrades": r.upgrade_ids.duplicate(),
		"build": r.build.duplicate(),
		"link": r.hacker_max_link,
		"ice": r.encounter_ice(),
	})


## §15.1 — the Run finished. The counterpart to `RUN_STOPPED`: that record meant
## beta 0.2 declined to fight the Boss, this one means the Boss lost.
static func run_completed(r: Run, turns: int) -> void:
	_emit(RUN_COMPLETED, r.route_seed, {
		"boss_id": r.boss_id,
		"host_id": r.host_id,
		"upgrades": r.upgrade_ids.duplicate(),
		"build": r.build.duplicate(),
		"boss_ice": r.encounter_ice(),
		"turns": turns,
	})


static func run_abandoned(r: Run) -> void:
	_emit(RUN_ABANDONED, r.route_seed, {"step": r.step, "upgrades": r.upgrade_ids.duplicate()})


# ---------------------------------------------------------------------------
# Quick Match
# ---------------------------------------------------------------------------

## The rolled setup, with the seed that produced it. Random Quick Match has no
## Run, so `run` is 0 and the setup seed carries the reproducibility instead.
## BOTH seeds are recorded, and they are deliberately separate fields.
##
## `setup_seed` reproduces the SELECTION — which build, System, and HOST were
## rolled. `gameplay_seed` reproduces the BOARD. Conflating them into one number
## would reintroduce exactly the coupling §17 forbids, and neither one alone
## reproduces the match.
static func quick_random_rolled(
	setup_seed: int, gameplay_seed: int, system_id: String, host_id: String, build: Array
) -> void:
	_emit(QUICK_RANDOM_ROLLED, 0, {
		"setup_seed": setup_seed,
		"gameplay_seed": gameplay_seed,
		"system_id": system_id,
		"host_id": host_id,
		"build": build.duplicate(),
	})

class_name Types
extends RefCounted

## Shared gameplay vocabulary — the GDScript counterpart of the alpha's
## `src/logic/types.ts`.
##
## Every string-union type in the alpha becomes an enum here. GDScript has no
## union types and no compile-time checking of string literals, so circulating
## raw strings inside the logic layer would trade TypeScript's safety for
## typo-shaped bugs that surface as silent behaviour changes. Strings appear
## only at the save and log boundaries, via the explicit converters below.
##
## Nothing in this file may depend on the scene tree (handoff §4).


# ---------------------------------------------------------------------------
# Packet identity
# ---------------------------------------------------------------------------

## D-014: these values are FROZEN. Weak sets derive as the enum-order
## complement of an authored strong set, so reordering these silently rewrites
## every System's and Hacker's weaknesses. Six of each, exactly.
##
## Their *appearance* is not frozen and is expected to change — that mapping
## lives in one place, `scenes/battle/packet_style.gd`, and nowhere else.
## FORCED RENAME from the alpha's `Color` / `Shape`: Godot has a builtin
## `Color` type, and GDScript rejects an enum that shadows a builtin name.
## Renamed symmetrically to keep the pair readable. The *values* — which are
## what actually matter — are unchanged.
enum PacketColor { RED = 0, YELLOW, MAGENTA, GREEN, CYAN, BLUE }
enum PacketShape { CIRCLE = 0, SQUARE, TRIANGLE, DIAMOND, STAR, CROSS }

# COLOR_COUNT / SHAPE_COUNT live in constants.gd, mirroring the alpha's split.


# ---------------------------------------------------------------------------
# Agents and battle lifecycle
# ---------------------------------------------------------------------------

enum Side { PLAYER = 0, ENEMY }

enum Phase { PLAYER_PRE = 0, RESOLVING, ENEMY, OVER }

enum Mode { QUICK_MATCH = 0, RUN }

## Natural outcomes and wizard actions are recorded separately in the alpha: a
## later wizard decision never overwrites a battle's natural result.
enum NaturalOutcome { NATURAL_VICTORY = 0, NATURAL_DEFEAT }

enum WizardAction { FORCE_WIN = 0, RESTART_LOST_BATTLE, RESTART_RUN }

## Which identity layer an encounter's opponent comes from. A Boss is a
## distinct layer, never a System with a flag, and must never be stored,
## logged, or displayed as a `SYS_ID`. Parsed in beta 0.1; not routed to
## until 0.3.
enum OpponentKind { SYS = 0, BOS }

enum SelectionSource { EXPLICIT_SELECTION = 0, QUICK_MATCH_DEFAULT }

enum SystemSelectionSource { RUN_RANDOM = 0, QUICK_RANDOM, QUICK_CONSTRUCTED, HEADLESS_PINNED }

enum BuildOrigin { DEFAULT = 0, RANDOM, REMEMBERED_CONSTRUCTED, CARRIED_RUN, PLAYER_EDITED }

## Which setup screen a Run in setup resumes to. Boss Selection is deliberately
## absent: committing a Boss is what CREATES the Run, so no persisted state ever
## resumes *to* the Boss screen (beta 0.2 authorization §4.1).
enum SetupStep { HACKER = 0, DECK }

## Where a session is parked. Beta 0.1 needed no such vocabulary because a Quick
## Match is always inside a battle; a Run is saveable with no battle at all, so
## the phase becomes real state.
##
## The first six spellings are the alpha's `serializeSession()` phases, kept
## verbatim so a beta save reads next to an alpha trace — the same discipline
## `SaveState._config_to_dict` already follows for settings.
##
## `PENDING_BOSS_BATTLE` was beta 0.2's stopping place, holding a fully committed
## Boss + HOST + UPGRADE package. Beta 0.3 passes straight through it into the
## Boss battle, so ordinary play no longer parks here — it survives because a
## beta 0.2 save may still carry it, and resuming one continues into Battle 4
## rather than dead-ending.
##
## `RUN_COMPLETE` is beta 0.3's terminal state: ODANSHAY's ICE reached zero and
## the Run is finished. No fifth route, battle, or reward follows it.
enum SessionPhase {
	SETUP_HACKER = 0,
	SETUP_DECK,
	PENDING_PATH,
	PENDING_BUILD,
	ACTIVE_BATTLE,
	PENDING_RESULT,
	PENDING_BOSS_BATTLE,
	RUN_COMPLETE,
}


# ---------------------------------------------------------------------------
# Attribution
# ---------------------------------------------------------------------------

## What acted. `BOSS` exists because ODANSHAY's mechanic pays no cost and owns
## no charge pool, yet its actor ID must remain the Boss itself.
enum OwnerKind { PROGRAM = 0, DECK, PASSIVE, BOSS }

## Which content kind supplied a PASSIVE instance. The same PASSIVE referenced
## by two sources is two instances that both apply — never deduplicated by ID.
enum PassiveSourceKind { HAK = 0, SYS, HST, UPG }

## Auditable readiness of a Drain target at target-resolution time.
enum Readiness { READY = 0, CHARGING, EMPTY }

## The disjoint causal damage buckets. Totals must equal the sum of attributed
## contributions, so these must stay mutually exclusive.
enum DamageSource { MATCH = 0, ATTACKER, BOMB, LINESLICE, TRANSFORM }

## Which Packet axis ECHOFALL hides. PRESENTATION only — the board's real
## colour and shape are what every rule keeps reading (beta 0.4 §8.2).
enum ConcealAxis { COLOR = 0, SHAPE }

## Where a routed charge stream came from.
enum ChargeStreamSource { SYNC = 0, CASCADE, PASSIVE_MODIFIED_SYNC, EFFECT_DESTRUCTION, EFFECT_TRANSFORM }

## What a targeted activation selected: nothing, one opposing Program slot
## (Drain), or one Packet coordinate. Deliberately no target list and no
## partial multi-target state.
enum TargetKind { NONE = 0, UNIT, PACKET }


## NOTE — house convention, established here because it bites everywhere:
## enum type annotations must use the QUALIFIED form (`Types.Side`), even
## inside this file. GDScript treats the bare `Side` written inside the class
## and the `Types.Side` seen by an external caller as different named types,
## and rejects passing one where the other is expected. Always qualify.
static func opponent_of(s: Types.Side) -> Types.Side:
	if s == Types.Side.PLAYER:
		return Types.Side.ENEMY
	return Types.Side.PLAYER


# ---------------------------------------------------------------------------
# Event registry
# ---------------------------------------------------------------------------

## The logic layer emits ordered events; scenes and metrics consume them. The
## event stream is the logic/render boundary and the substrate of the
## differential gate, so event names are never written as bare string literals —
## use `Types.EVT.DAMAGE`, never `"damage"`.
##
## Values match the alpha's `t` discriminator exactly. Order and content of the
## stream are compared byte-for-byte against the alpha (D-019), so an extra,
## missing, or reordered event is a test failure by design.
const EVT := {
	ABILITY = &"ability",
	AUTO_RESHUFFLE = &"autoReshuffle",
	BOARD = &"board",
	BOSS_MECHANIC = &"bossMechanic",
	CASCADE_DEPTH = &"cascadeDepth",
	CHARGE_ROUTE = &"chargeRoute",
	CHARGE_WASTE = &"chargeWaste",
	COUNTDOWN = &"countdown",
	COUNTDOWN_DELIVERED = &"countdownDelivered",
	DAMAGE = &"damage",
	DECK_CHARGE = &"deckCharge",
	DESTROY = &"destroy",
	DETONATE = &"detonate",
	FALL = &"fall",
	HINT_SHOWN = &"hintShown",
	LINE_CLEAR = &"lineClear",
	MSG = &"msg",
	NO_MATCH = &"noMatch",
	OP = &"op",
	OVER = &"over",
	PASSIVE = &"passive",
	PLACED = &"placed",
	REVERT = &"revert",
	SET_TILE = &"setTile",
	SHAKE = &"shake",
	SHIELD = &"shield",
	SHIELD_REMOVED = &"shieldRemoved",
	SPAWN = &"spawn",
	SWAP = &"swap",
	TARGETED = &"targeted",
	THINK_TIME = &"thinkTime",
	TILE_STATS = &"tileStats",
	TRANSFORM = &"transform",
	WITHHOLD = &"withhold",
}

## Events excluded from differential traces because they carry wall-clock or
## presentation state rather than gameplay (addendum §A7). Normalizing these
## away prevents false divergences; normalizing anything else away would hide
## real ones.
const NON_DETERMINISTIC_EVENTS := [&"thinkTime", &"hintShown"]


## Debug-only guard against typo'd or malformed events. Compiled out of release
## builds by its caller. Key-level shape checks per event type are added as
## each event is implemented in Phase 3.
static func validate_event(evt: Dictionary) -> bool:
	if not evt.has("t"):
		push_error("event has no 't' discriminator: %s" % [evt])
		return false
	var name := StringName(evt["t"])
	if not EVT.values().has(name):
		push_error("unknown event type '%s' — add it to Types.EVT" % name)
		return false
	return true


# ---------------------------------------------------------------------------
# String boundary
# ---------------------------------------------------------------------------
#
# Used only when crossing into a save file, a log record, or a trace. The
# spellings must match the alpha exactly: traces are compared against it, and a
# save records identity as stable strings.

const SIDE_NAMES := ["player", "enemy"]
const PHASE_NAMES := ["playerPre", "resolving", "enemy", "over"]
const MODE_NAMES := ["QUICK_MATCH", "RUN"]
const NATURAL_OUTCOME_NAMES := ["NATURAL_VICTORY", "NATURAL_DEFEAT"]
const WIZARD_ACTION_NAMES := ["WIZARD_FORCE_WIN", "WIZARD_RESTART_LOST_BATTLE", "WIZARD_RESTART_RUN"]
const OPPONENT_KIND_NAMES := ["SYS", "BOS"]
const SELECTION_SOURCE_NAMES := ["EXPLICIT_SELECTION", "QUICK_MATCH_DEFAULT"]
const SYSTEM_SELECTION_SOURCE_NAMES := ["RUN_RANDOM", "QUICK_RANDOM", "QUICK_CONSTRUCTED", "HEADLESS_PINNED"]
const BUILD_ORIGIN_NAMES := ["DEFAULT", "RANDOM", "REMEMBERED_CONSTRUCTED", "CARRIED_RUN", "PLAYER_EDITED"]
const SETUP_STEP_NAMES := ["HACKER", "DECK"]
const SESSION_PHASE_NAMES := [
	"SETUP_HACKER", "SETUP_DECK", "PENDING_PATH", "PENDING_BUILD",
	"ACTIVE_BATTLE", "PENDING_RESULT", "PENDING_BOSS_BATTLE", "RUN_COMPLETE",
]
const OWNER_KIND_NAMES := ["program", "deck", "passive", "boss"]
const PASSIVE_SOURCE_KIND_NAMES := ["HAK", "SYS", "HST", "UPG"]
const READINESS_NAMES := ["READY", "CHARGING", "EMPTY"]
const DAMAGE_SOURCE_NAMES := ["match", "attacker", "bomb", "lineslice", "transform"]
const CONCEAL_AXIS_NAMES := ["color", "shape"]
const CHARGE_STREAM_SOURCE_NAMES := [
	"SYNC", "CASCADE", "PASSIVE_MODIFIED_SYNC", "EFFECT_DESTRUCTION", "EFFECT_TRANSFORM",
]


static func name_of(names: Array, value: int) -> String:
	if value < 0 or value >= names.size():
		push_error("enum value %d out of range for %s" % [value, names])
		return ""
	return names[value]


## Returns -1 when unknown. Callers at the save boundary must treat that as a
## rejection: the alpha never silently repairs invalid persisted state, and
## neither does this.
static func value_of(names: Array, text: String) -> int:
	return names.find(text)

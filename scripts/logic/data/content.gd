class_name Content
extends RefCounted

## Resolved content: the typed, validated result of loading the ten datasets,
## plus the structural constants that describe it.
##
## Strings are resolved to typed values at startup; combat never re-parses a
## colon-delimited list. Anything that reaches this module has already passed
## validation — there is no partial content and no fallback.


# ---------------------------------------------------------------------------
# Structural constants
# ---------------------------------------------------------------------------

## The beta line's own version string. Deliberately NOT the alpha's
## `alpha-0.7.0`: it stamps saves and logs, and claiming the alpha's identity
## would make a beta save look restorable to alpha tooling.
const GAME_VERSION := "beta-0.1.0"

## Bumped independently of the game version — it changes only when the shape of
## fingerprinted content changes. It is fingerprint input, so it must match the
## alpha's value or every fingerprint differs.
const DATA_SCHEMA_VERSION := 6

const PORTFOLIO_SIZE := 3
const INVENTORY_SIZE := PORTFOLIO_SIZE * 2
const ACTIVE_BUILD_SIZE := 4
const SYSTEM_BUILD_SIZE := 4

## Beta 0.1 pins the Hacker and Deck rather than offering selection screens
## (authorization §2.1). Resolved by stable ID — never by first row, row count,
## display name, or file order — and a missing ID fails validation rather than
## silently choosing another row.
const DEFAULT_HACKER_ID := "HAK_01"
const DEFAULT_DECK_ID := "DEK_01"

const HEADLESS_SYSTEM_ID := "SYS_01"
const HEADLESS_HOST_ID := "HST_01"

## Run-layer content, parsed and validated in beta 0.1 but not routed to until
## 0.2 and 0.3 respectively.
const INITIAL_SYSTEM_ID := "SYS_03"  ## DOORMAN, the fixed Battle 1 opponent
const INITIAL_HOST_ID := "HST_01"  ## THRESHOLD
const MIN_UPGRADE_ROWS := 4
const PATH_CHOICE_COUNT := 2

## Boss layer — validated in beta 0.1, implemented in 0.3.
const BOSS_MECHANIC_BOSS_ID := "BOS_01"  ## ODANSHAY
const FN_DATABEND := "FNC_018"
const FN_REBOOT := "FNC_019"
const FN_CODESHATTER := "FNC_020"
const BOSS_MECHANIC_FUNCTION_IDS: Array[String] = [FN_DATABEND, FN_REBOOT, FN_CODESHATTER]
const OVERRIDE_PLACEMENT_COUNT := 3
const OVERRIDE_THRESHOLD := 15
const OVERRIDE_DATABEND_RETRY_LIMIT := 5


# ---------------------------------------------------------------------------
# Effect tuple vocabularies
# ---------------------------------------------------------------------------
#
# These are the meanings of the integer enum values inside each Effect's
# compound `params` tuple. Named here rather than left as bare integers,
# because `1` appearing in four different tuple positions means four different
# things.

## EFFECT_SHAKE: boardComposition
const SHAKE_REARRANGE := 0  ## permute the existing Packet objects
const SHAKE_REPLACE := 1  ## regenerate affected Packets as ordinary ones

## EFFECT_SHAKE: specialGems
const SHAKE_RETAIN_SPECIALS := 0
const SHAKE_REMOVE_SPECIALS := 1
## Removes only the overlays the activating side does NOT own. Mirrors
## SPECIALS_RETAIN_OWN rather than inventing a third vocabulary.
const SHAKE_REMOVE_ENEMY_SPECIALS := 2

## EFFECT_SHAKE: matches
const SHAKE_PREVENT_MATCHES := 0
const SHAKE_ALLOW_MATCHES := 1

## EFFECT_SHAKE: cascades
const SHAKE_CASCADE_NONE := 0  ## the initial post-Shake wave only
const SHAKE_CASCADE_CONFIGURED := 1  ## the battle's saved cascade limit
const SHAKE_CASCADE_UNTIL_STABLE := 2  ## ignore the finite limit

## Shared targeting / payout vocabulary.
const TARGETING_RANDOM := 0
const TARGETING_TARGETED := 1
const DEAL_DAMAGE_YES := 0
const DEAL_DAMAGE_NO := 1
const GAIN_CHARGE_YES := 0
const GAIN_CHARGE_NO := 1

## EFFECT_LINESLICE: dimension
const LINE_DIMENSION_ROW := 0
const LINE_DIMENSION_COLUMN := 1

## Shared special-Packet handling, used by both LineSlice and Transform so the
## two cannot drift apart.
const SPECIALS_DESTROY := 0
const SPECIALS_RETAIN_ALL := 1
const SPECIALS_RETAIN_OWN := 2


# ---------------------------------------------------------------------------
# Transform axis grammar
# ---------------------------------------------------------------------------
#
# The colon is INTERSECTION in both axis columns: `GRE:TRI` means "green
# triangles", never "green or triangular". There is no OR targeting, no
# multi-value axis, and no negation.

const AXIS_NEUTRAL := "NEU"
const AXIS_ALL := "ALL"

## Which Packets an EFFECT_TRANSFORM may target.
##   NEU  — neutral Packets only
##   ALL  — every Packet, neutrals included
##   AXIS — standard Packets matching every authored axis; a single authored
##          axis leaves the other free. Neutrals are NEVER eligible here,
##          because a neutral has no axis to match against.
enum AxisTargetKind { NEU = 0, ALL, AXIS }


## The resolved content, installed once at startup and never reloaded during a
## session. Held as a static rather than passed through every call, matching the
## alpha's `setActiveContent` / `getContent` pair.
static var _active: Dictionary = {}


static func set_active(c: Dictionary) -> void:
	_active = c


static func active() -> Dictionary:
	if _active.is_empty():
		push_error("content accessed before it was loaded — startup order bug")
	return _active


static func is_loaded() -> bool:
	return not _active.is_empty()


## Cleared between headless battles in the differential harness so one run
## cannot inherit another's content.
static func clear() -> void:
	_active = {}


# ---------------------------------------------------------------------------
# Accessors
# ---------------------------------------------------------------------------
#
# Every lookup is by STABLE ID and every miss is an error rather than a null
# return. Content is validated before it is installed, so a miss here means a
# logic bug upstream — silently returning null would push the failure somewhere
# far less diagnosable.

static func _lookup(kind: String, id: String) -> Dictionary:
	var c := active()
	var table: Dictionary = c.get(kind, {})
	if not table.has(id):
		push_error("unknown %s id '%s'" % [kind, id])
		return {}
	return table[id]


static func program(id: String) -> Dictionary:
	return _lookup("programs", id)


static func function(id: String) -> Dictionary:
	return _lookup("functions", id)


static func passive(id: String) -> Dictionary:
	return _lookup("passives", id)


static func hacker(id: String) -> Dictionary:
	return _lookup("hackers", id)


static func deck(id: String) -> Dictionary:
	return _lookup("decks", id)


static func system(id: String) -> Dictionary:
	return _lookup("systems", id)


static func host(id: String) -> Dictionary:
	return _lookup("hosts", id)


static func upgrade(id: String) -> Dictionary:
	return _lookup("upgrades", id)


static func boss(id: String) -> Dictionary:
	return _lookup("bosses", id)


static func fingerprint() -> String:
	return active().get("fingerprint", "")


## Programs belonging to one side, in content order — which is the order that
## becomes charge-routing priority.
static func programs_for(side: Types.Side) -> Array:
	var out: Array = []
	for id in active()["programs"]:
		var p: Dictionary = active()["programs"][id]
		if p["side"] == side:
			out.append(p)
	return out

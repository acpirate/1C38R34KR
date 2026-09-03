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
## Stamped on saves, battle records, and session records. Deliberately NOT part
## of the content fingerprint — that is `DATA_SCHEMA_VERSION` plus the content
## rows — so bumping it cannot invalidate differential parity or reinterpret a
## battle. It identifies the BUILD; the fingerprint identifies the CONTENT.
const GAME_VERSION := "beta-0.3.2.2"

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

## Boss layer — validated in beta 0.1, ODANSHAY implemented in 0.3, the other
## three Bosses in 0.4.
## The HOST Boss Attack always plays (§10.2). THRESHOLD contributes no HOST
## passive, so a Boss test measures the Boss and not the HOST.
const BOSS_ATTACK_HOST_ID := "HST_01"

const BOSS_ODANSHAY := "BOS_01"
const BOSS_RAHNDAHL := "BOS_02"
const BOSS_NEHBOCYET := "BOS_03"
const BOSS_ECHOFALL := "BOS_04"

## Retained under its old name: it is what the ODANSHAY-specific tests and the
## differential harness ask for, and they mean that Boss rather than "whichever
## Boss has a mechanic" — which, since 0.4, is all of them.
const BOSS_MECHANIC_BOSS_ID := BOSS_ODANSHAY

const FN_DATABEND := "FNC_018"
const FN_REBOOT := "FNC_019"
const FN_CODESHATTER := "FNC_020"
const FN_LOGICBOMBEXPLODE := "FNC_021"
const FN_BRAINSCRAMBLE := "FNC_022"

## Zero-cost payloads invoked only from Boss code. Listing them here is what
## keeps the loader from warning that nothing references them — they are reached
## through `Game.cast_boss_mechanic`, not through any Program or Deck.
const BOSS_MECHANIC_FUNCTION_IDS: Array[String] = [
	FN_DATABEND, FN_REBOOT, FN_CODESHATTER,
	FN_LOGICBOMBEXPLODE, FN_BRAINSCRAMBLE,
]
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


## Resolve an opponent through the identity UNION rather than by guessing a
## registry.
##
## Anything holding a battle identity — the battle screen, logging, metrics —
## must go through this. Calling `system()` with a `BOS_ID` reports an unknown
## id and returns an empty Dictionary, and the caller then indexes it and
## aborts mid-refresh, which is how the Boss battle shipped with a header
## reading "SYSTEM / ICE 0/1" while the battle underneath was perfectly correct.
static func opponent(kind: Types.OpponentKind, id: String) -> Dictionary:
	return boss(id) if kind == Types.OpponentKind.BOS else system(id)


## The same, taken straight from a battle identity.
static func opponent_of_identity(identity: Dictionary) -> Dictionary:
	return opponent(identity["opponent_kind"], str(identity["opponent_id"]))


static func fingerprint() -> String:
	return active().get("fingerprint", "")


# ---------------------------------------------------------------------------
# Ordered listings and the random pools
# ---------------------------------------------------------------------------
#
# The alpha keeps an explicit `*Order` array beside each registry. GDScript
# Dictionaries preserve insertion order and the loader inserts in CSV row order,
# so iterating the registry IS the authored order, and a parallel array would be
# a second thing to keep in sync. Recorded in port-notes.
#
# Order is not cosmetic: route generation shuffles the eligible UPGRADE array in
# this order, so changing it changes which UPGRADEs a given route seed offers.

static func _ordered(kind: String) -> Array:
	var out: Array = []
	var table: Dictionary = active().get(kind, {})
	for id in table:
		out.append(table[id])
	return out


static func all_systems() -> Array:
	return _ordered("systems")


static func all_hosts() -> Array:
	return _ordered("hosts")


static func all_upgrades() -> Array:
	return _ordered("upgrades")


static func all_bosses() -> Array:
	return _ordered("bosses")


## The RANDOM pools. Route offer generation and Random Quick Match sample from
## these, never from the full listing.
##
## Deliberate selection screens still list EVERYTHING (director ruling
## 2026-08-11): `in_pool` governs what may be ROLLED, not what may be chosen.
## With current content DOORMAN and THRESHOLD are the intro-only rows held out
## of the pools, leaving two Systems and four HOSTs.
##
## The loader rejects content where either pool is empty, so on validated
## content these cannot return an empty array — a content bug surfaces at
## startup rather than as a silent default here.
static func pool_systems() -> Array:
	return _in_pool(all_systems())


static func pool_hosts() -> Array:
	return _in_pool(all_hosts())


static func _in_pool(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		if r["in_pool"]:
			out.append(r)
	return out


# ---------------------------------------------------------------------------
# Inventory and the default build
# ---------------------------------------------------------------------------
#
# Parameterized by identity, because a Run selects its own Hacker and Deck.
# Beta 0.1 only ever needed the pinned Constructed pair, so `Session` derived
# the build inline from the two DEFAULT_* constants.

## The fixed six-Program inventory a build is drawn from: the Hacker's portfolio
## in authored order, then the Deck's.
static func inventory_program_ids(hacker_id: String, deck_id: String) -> Array:
	var out: Array = []
	out.append_array(hacker(hacker_id)["portfolio"])
	out.append_array(deck(deck_id)["portfolio"])
	return out


## The DEFAULT build: Hacker portfolio entries 1 and 2, then Deck portfolio
## entries 1 and 2.
##
## Derived from portfolio ORDER, never from a hardcoded list of Program IDs — a
## content edit changes the default build, as it should. Portfolio order is
## authored content and gameplay-significant (it becomes charge-routing
## priority), so this must not be reordered for convenience.
static func default_build(hacker_id: String, deck_id: String) -> Array:
	var half := int(ACTIVE_BUILD_SIZE / 2.0)
	var out: Array = []
	var hacker_portfolio: Array = hacker(hacker_id)["portfolio"]
	var deck_portfolio: Array = deck(deck_id)["portfolio"]
	for i in half:
		out.append(hacker_portfolio[i])
	for i in half:
		out.append(deck_portfolio[i])
	return out


## Whether `build` is a legal active build for this inventory: exactly
## ACTIVE_BUILD_SIZE entries, all distinct, all drawn from the inventory.
static func is_valid_build(build: Array, inventory: Array) -> bool:
	if build.size() != ACTIVE_BUILD_SIZE:
		return false
	var seen := {}
	for pid in build:
		if seen.has(pid) or not inventory.has(pid):
			return false
		seen[pid] = true
	return true


## Programs belonging to one side, in content order — which is the order that
## becomes charge-routing priority.
static func programs_for(side: Types.Side) -> Array:
	var out: Array = []
	for id in active()["programs"]:
		var p: Dictionary = active()["programs"][id]
		if p["side"] == side:
			out.append(p)
	return out

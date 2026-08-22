extends RefCounted

## Authorization §12: no balance changes during the port.
##
## Easy to state, easy to violate by mistranscribing a single number, and
## invisible afterwards — a wrong damage tier does not crash, it just makes the
## game quietly different. So it is checked mechanically against a fixture
## generated from the alpha rather than trusted to review.
##
## The alpha→GDScript name mapping is spelled out rather than derived, so the
## translation itself is auditable.

const FIXTURE := "res://tests/fixtures/constants.json"

## Reading constants by name needs the script as an *object*. A `class_name`
## identifier is a type, so `Constants.get_script_constant_map()` is a parse
## error — and `preload` does not help, because the parser resolves it back to
## the same named type. A runtime `load()` into a `Script`-typed variable does
## work: that value is an object, so its instance methods are callable.
const CONSTANTS_PATH := "res://scripts/logic/constants.gd"

## alpha name → GDScript name. Every entry in the fixture must appear here, and
## a missing one is a failure: that is what catches a constant added to the
## alpha and never ported.
const NAME_MAP := {
	"BOARD_WIDTH": "BOARD_WIDTH",
	"BOARD_HEIGHT": "BOARD_HEIGHT",
	"COLOR_COUNT": "COLOR_COUNT",
	"SHAPE_COUNT": "SHAPE_COUNT",
	"NEUTRAL_TILE_DROP_RATE": "NEUTRAL_TILE_DROP_RATE",
	"DAMAGE_PER_TILE_LOW_COLOR": "DAMAGE_PER_TILE_LOW_COLOR",
	"DAMAGE_PER_TILE_HIGH_COLOR": "DAMAGE_PER_TILE_HIGH_COLOR",
	"DAMAGE_PER_TILE_NEUTRAL": "DAMAGE_PER_TILE_NEUTRAL",
	"DAMAGE_PER_TILE_LOW_SHAPE": "DAMAGE_PER_TILE_LOW_SHAPE",
	"DAMAGE_PER_TILE_HIGH_SHAPE": "DAMAGE_PER_TILE_HIGH_SHAPE",
	"CHARGE_PER_TILE_COLOR_MATCH": "CHARGE_PER_TILE_COLOR_MATCH",
	"CHARGE_PER_TILE_SHAPE_MATCH": "CHARGE_PER_TILE_SHAPE_MATCH",
	"MATCH_3_MULTIPLIER": "MATCH_3_MULTIPLIER",
	"MATCH_4_MULTIPLIER": "MATCH_4_MULTIPLIER",
	"MATCH_5_LINE_MULTIPLIER": "MATCH_5_LINE_MULTIPLIER",
	"MATCH_5_NONLINE_MULTIPLIER": "MATCH_5_NONLINE_MULTIPLIER",
	"LINE_CLEAR_RUN_LENGTH": "LINE_CLEAR_RUN_LENGTH",
	"DECK_CHARGE_PER_NEUTRAL_TILE": "DECK_CHARGE_PER_NEUTRAL_TILE",
	"MANUAL_LINK_DEFAULT": "MANUAL_LINK_DEFAULT",
	"ENEMY_TIMER_CHARGE_RATE": "ENEMY_TIMER_CHARGE_RATE",
	"CHARGE_CAP_EQUALS_COST": "CHARGE_CAP_EQUALS_COST",
}

## alpha settings key → GDScript settings key.
const SETTINGS_MAP := {
	"enemyMatching": "enemy_matching",
	"singleAxisPayout": "single_axis_payout",
	"maxCascadeSteps": "max_cascade_steps",
	"reinforcedConnection": "reinforced_connection",
	"normalLink": "normal_link",
	"manualHackerLink": "manual_hacker_link",
	"manualSystemIce": "manual_system_ice",
	"hintEnabled": "hint_enabled",
	"hintDelaySeconds": "hint_delay_seconds",
	"reinforcedChargeAwareBot": "reinforced_charge_aware_bot",
}


func run(t: TestCase) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		t.group("constants")
		t.check("fixture %s is readable" % FIXTURE, false)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		t.group("constants")
		t.check("fixture parses", false)
		return

	var alpha: Dictionary = parsed["constants"]
	_test_scalars(t, alpha)
	_test_settings(t, alpha)
	_test_enum_ordering(t)


func _test_scalars(t: TestCase, alpha: Dictionary) -> void:
	t.group("constants / engine values")
	var constants_script: Script = load(CONSTANTS_PATH)
	var const_map: Dictionary = constants_script.get_script_constant_map()
	for alpha_name in alpha.keys():
		if alpha_name == "DEFAULT_BATTLE_SETTINGS":
			continue
		if not NAME_MAP.has(alpha_name):
			t.check("alpha constant %s is mapped to a GDScript name" % alpha_name, false)
			continue
		var gd_name: String = NAME_MAP[alpha_name]
		if not const_map.has(gd_name):
			t.check("Constants defines %s" % gd_name, false)
			continue
		# int/float compare numerically in GDScript, which is what we want:
		# JS serializes 1.0 as 1, so MATCH_3_MULTIPLIER arrives as an int.
		t.eq(alpha_name, const_map[gd_name], alpha[alpha_name])


func _test_settings(t: TestCase, alpha: Dictionary) -> void:
	t.group("constants / default battle settings")
	var alpha_settings: Dictionary = alpha["DEFAULT_BATTLE_SETTINGS"]
	var ours := Constants.default_settings()

	t.eq("setting count", ours.size(), alpha_settings.size())

	for alpha_key in alpha_settings.keys():
		if not SETTINGS_MAP.has(alpha_key):
			t.check("alpha setting %s is mapped" % alpha_key, false)
			continue
		var gd_key: String = SETTINGS_MAP[alpha_key]
		if not ours.has(gd_key):
			t.check("GDScript settings contain %s" % gd_key, false)
			continue
		t.eq(alpha_key, ours[gd_key], alpha_settings[alpha_key])

	# The infinity sentinel is null, deliberately not a large integer. The
	# §6.1 differential variation depends on the distinction surviving.
	t.eq("default max_cascade_steps is 0, meaning capped", ours["max_cascade_steps"], 0)
	t.check("CASCADE_STEPS_INFINITE is null, not an integer", Constants.CASCADE_STEPS_INFINITE == null)

	# default_settings() must hand back a mutable copy — the harness builds the
	# §6.1 variations by mutating it.
	var copy := Constants.default_settings()
	copy["normal_link"] = false
	t.check("default_settings() returns an independent copy", Constants.default_settings()["normal_link"] == true)


## D-014: enum ordering is load-bearing, because weak sets derive as the
## enum-order complement of an authored strong set. A reorder here silently
## rewrites every System's and Hacker's weaknesses, and would pass every other
## test in the suite.
func _test_enum_ordering(t: TestCase) -> void:
	t.group("constants / frozen enum ordering")
	t.eq("PacketColor.RED", Types.PacketColor.RED, 0)
	t.eq("PacketColor.YELLOW", Types.PacketColor.YELLOW, 1)
	t.eq("PacketColor.MAGENTA", Types.PacketColor.MAGENTA, 2)
	t.eq("PacketColor.GREEN", Types.PacketColor.GREEN, 3)
	t.eq("PacketColor.CYAN", Types.PacketColor.CYAN, 4)
	t.eq("PacketColor.BLUE", Types.PacketColor.BLUE, 5)
	t.eq("PacketShape.CIRCLE", Types.PacketShape.CIRCLE, 0)
	t.eq("PacketShape.SQUARE", Types.PacketShape.SQUARE, 1)
	t.eq("PacketShape.TRIANGLE", Types.PacketShape.TRIANGLE, 2)
	t.eq("PacketShape.DIAMOND", Types.PacketShape.DIAMOND, 3)
	t.eq("PacketShape.STAR", Types.PacketShape.STAR, 4)
	t.eq("PacketShape.CROSS", Types.PacketShape.CROSS, 5)
	t.eq("PacketColor size matches COLOR_COUNT", Types.PacketColor.size(), Constants.COLOR_COUNT)
	t.eq("PacketShape size matches SHAPE_COUNT", Types.PacketShape.size(), Constants.SHAPE_COUNT)
	t.eq("Side.PLAYER opposes ENEMY", Types.opponent_of(Types.Side.PLAYER), Types.Side.ENEMY)
	t.eq("Side.ENEMY opposes PLAYER", Types.opponent_of(Types.Side.ENEMY), Types.Side.PLAYER)

	t.group("constants / event registry")
	t.eq("EVT entry count", Types.EVT.size(), 34)
	t.check("validate_event rejects an event with no discriminator", not Types.validate_event({}))
	t.check("validate_event rejects an unknown type", not Types.validate_event({"t": "nonsense"}))
	t.check("validate_event accepts a known type", Types.validate_event({"t": Types.EVT.DAMAGE}))

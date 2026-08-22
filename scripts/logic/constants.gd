class_name Constants
extends RefCounted

## Tunable engine constants — the single source of every gameplay-affecting
## number that is NOT Program/Function/Hacker/Deck/PASSIVE content. Content
## lives in the ten CSV datasets; nothing here duplicates it and there is no
## hardcoded content fallback.
##
## Ported verbatim from the alpha's `src/logic/constants.ts`. Authorization §12:
## **no balance changes.** If a value looks wrong, report it — do not fix it. A
## port that also retunes cannot be differentially verified, because every
## divergence becomes ambiguous between "port bug" and "intended change".


const BOARD_WIDTH := 8
const BOARD_HEIGHT := 8

const COLOR_COUNT := 6
const SHAPE_COUNT := 6

## 8% of newly generated Packets (initial fill, refills, shake/reshuffle output)
## are neutral; the remaining 92% split evenly across the 36 colour/shape combos.
const NEUTRAL_TILE_DROP_RATE := 0.08

## Sync damage tiers. A COLOR Sync damages via the tile's colour tier, a SHAPE
## Sync via its shape tier, resolved against the acting side's own strong sets.
const DAMAGE_PER_TILE_LOW_COLOR := 1
const DAMAGE_PER_TILE_HIGH_COLOR := 2
const DAMAGE_PER_TILE_NEUTRAL := 2
const DAMAGE_PER_TILE_LOW_SHAPE := 1
const DAMAGE_PER_TILE_HIGH_SHAPE := 2

## Charge is always flat per qualifying sliced Packet — it never uses the
## damage multipliers below.
const CHARGE_PER_TILE_COLOR_MATCH := 1
const CHARGE_PER_TILE_SHAPE_MATCH := 1

## Damage-only multipliers.
const MATCH_3_MULTIPLIER := 1.0
const MATCH_4_MULTIPLIER := 1.0  ## 4-line clears the full row/column
const MATCH_5_LINE_MULTIPLIER := 1.5  ## crit AND clears row/column
const MATCH_5_NONLINE_MULTIPLIER := 1.5  ## merged same-axis blob of 5+: crit, no clear

## A contiguous run of this many directly matched cells in a resolution wave's
## combined footprint triggers its row/column clear.
const LINE_CLEAR_RUN_LENGTH := 4

## Charge the active Deck Function gains per NEUTRAL Packet sliced during its
## owner's qualifying Sync resolution. Bomb destruction explicitly grants none.
const DECK_CHARGE_PER_NEUTRAL_TILE := 1

## Fallback maximum LINK/ICE, used only for the manual settings' defaults when
## Normal LINK is OFF. Under Normal LINK — the default — effective LINK/ICE come
## from the selected Hacker, Deck, and encounter, never from this value.
const MANUAL_LINK_DEFAULT := 150

## The System's flat per-turn charge rate in timer-charge mode
## (`enemy_matching` off). An approved exception to the no-hardcoded-content
## rule: one flat rate applied uniformly to every System Program, never a
## per-Program table.
const ENEMY_TIMER_CHARGE_RATE := 3

## Every Program's charge is capped at its pool capacity (its Function's cost);
## overflow is discarded at the moment charge is added. The Deck Function's pool
## follows the same rule.
const CHARGE_CAP_EQUALS_COST := true

## `max_cascade_steps` uses null as an explicit infinity sentinel, NOT a large
## integer — the distinction is load-bearing in the alpha and at the save and
## trace boundaries. The addendum §A7 §6.1 variation sets this to null; the
## default of 0 means capped at zero. Do not invert them.
const CASCADE_STEPS_INFINITE = null

## Per-battle settings defaults.
##
## Strong/weak sets and effective LINK/ICE are resolved per battle from the
## selected identities, so they are deliberately absent here.
##
## `enemy_matching` defaults to true (director ruling, alpha 0.6.0): the System
## takes a real turn — ticking countdowns, running its Function phase, and
## making one Sync — instead of receiving the flat timer rate. Timer mode
## remains fully supported and is one of the §6.1 differential variations.
const DEFAULT_BATTLE_SETTINGS := {
	enemy_matching = true,
	single_axis_payout = false,
	max_cascade_steps = 0,
	reinforced_connection = false,
	normal_link = true,
	manual_hacker_link = MANUAL_LINK_DEFAULT,
	manual_system_ice = MANUAL_LINK_DEFAULT,
	hint_enabled = false,
	hint_delay_seconds = 7,
	reinforced_charge_aware_bot = true,
}


## Const dictionaries are read-only; callers that need to vary a setting take a
## copy. Used by the differential harness to build the §6.1 variations.
static func default_settings() -> Dictionary:
	return DEFAULT_BATTLE_SETTINGS.duplicate()


## A tile is "strong" for a side when its colour/shape is in that side's
## RESOLVED strong set, paying the HIGH damage tier for that side; LOW
## otherwise. Each side's sets come from its own authored identity — the
## System's are no longer the Hacker's complement.
static func is_strong_color(config: Dictionary, side: Types.Side, color: Types.PacketColor) -> bool:
	return (config["strong_colors"][side] as Array).has(color)


static func is_strong_shape(config: Dictionary, side: Types.Side, shape: Types.PacketShape) -> bool:
	return (config["strong_shapes"][side] as Array).has(shape)

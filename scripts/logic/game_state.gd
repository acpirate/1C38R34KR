class_name GameState
extends RefCounted

## The complete state of one battle.
##
## Held as an object rather than a Dictionary because it is passed through every
## resolution function and mutated constantly — a typo'd key in that traffic
## would be a silent no-op rather than an error.
##
## Immutable for the battle's lifetime: `identity` and `config`. Everything else
## is live state.

var board: Array = []
var rng: Rng = null
var next_id := 1

## Global overlay placement order. Armed overlays tick oldest-first, so this is
## gameplay-affecting rather than bookkeeping.
var next_seq := 1

## Indexed by Types.Side.
var hp := [0, 0]

## One slot per resolved Program, in content order. Indexed by Types.Side.
var units := [[], []]

## The active Deck's independent charge pool for its directly assigned Function.
## Capped at that Function's cost, reset from `start_charged` at battle start,
## and never persisted between encounters.
##
## Deck-owned, NOT a Program — and therefore never an eligible Drain target.
var deck_charge := 0

var identity := {}
var phase := Types.Phase.PLAYER_PRE
var winner: int = -1  ## Types.Side, or -1 while the battle continues
var turn := 1
var config := {}

## Collision-resistant and stable across save and restore. Normalized out of
## differential traces, since it is identity rather than behaviour.
var battle_id := ""


## A charge pool bound to a resolved Program by stable ID.
##
## Program properties — cost, bindings, Function — live in the resolved content
## model and never here, so a content edit cannot leave a battle holding a stale
## copy of them.
class UnitState extends RefCounted:
	var program_id := ""
	var charge := 0

	func _init(pid: String, c: int = 0) -> void:
		program_id = pid
		charge = c


func has_winner() -> bool:
	return winner != -1


func units_for(side: Types.Side) -> Array:
	return units[side]


func hp_of(side: Types.Side) -> int:
	return hp[side]


func set_hp(side: Types.Side, value: int) -> void:
	hp[side] = value


func tile_at(p: Vector2i) -> Tile:
	if p.y < 0 or p.y >= Constants.BOARD_HEIGHT or p.x < 0 or p.x >= Constants.BOARD_WIDTH:
		return null
	return board[p.y][p.x]


func set_tile(p: Vector2i, t: Tile) -> void:
	board[p.y][p.x] = t


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < Constants.BOARD_WIDTH and p.y >= 0 and p.y < Constants.BOARD_HEIGHT


## Every occupied coordinate, row-major. Iteration order is deterministic
## because several resolution paths depend on it.
func occupied_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in Constants.BOARD_HEIGHT:
		for x in Constants.BOARD_WIDTH:
			if board[y][x] != null:
				out.append(Vector2i(x, y))
	return out

class_name Tile
extends RefCounted

## One Packet on the Datastream.
##
## Mutated constantly during resolution, so this is a reference type rather than
## a value: the reshuffle and REARRANGE paths relocate the same objects, and
## identity is what makes "the overlay moves with its Packet" true by
## construction rather than by copying fields around.

enum Kind { STANDARD = 0, NEUTRAL }

var id := 0
var kind := Kind.STANDARD

## Standard Packets only. A neutral has no axes — which is why it can never
## carry an overlay and is never eligible for axis-specific targeting.
var color: int = -1
var shape: int = -1

## Only standard Packets can be special. Null when the Packet carries nothing.
var special: Special = null


static func standard(tile_id: int, c: int, s: int) -> Tile:
	var t := Tile.new()
	t.id = tile_id
	t.kind = Kind.STANDARD
	t.color = c
	t.shape = s
	return t


static func neutral(tile_id: int) -> Tile:
	var t := Tile.new()
	t.id = tile_id
	t.kind = Kind.NEUTRAL
	return t


func is_neutral() -> bool:
	return kind == Kind.NEUTRAL


func has_special() -> bool:
	return special != null


## A board overlay: bomb, buff, shield, or Boss Override.
##
## An armed overlay carries BOTH its remaining countdown and the Effect it will
## deliver, plus the parameters resolved when it was armed. That is what makes
## "resolved parameters must not silently change while the object is armed" true
## by construction — a Function edited between arming and delivery cannot reach
## back and alter what is already in flight.
class Special extends RefCounted:
	## Beta 0.4 appends CAPACITOR and LOGIC_BOMB. New members go on the END:
	## the ordinal is the key into `overlay_mark`/`overlay_ring` in every
	## graphics pack, so inserting one would silently repoint existing art.
	enum Type { BOMB = 0, BUFF, SHIELD, OVERRIDE, CAPACITOR, LOGIC_BOMB }

	var type := Type.BOMB
	var owner := Types.Side.PLAYER

	## Armed overlays only — bombs and PENDING buffs. A buff with a positive
	## countdown contributes NO magnitude until delivery.
	var countdown: int = -1

	## What this overlay delivers at zero. Present iff `countdown` is; absent
	## means the overlay is already live.
	var delivers := ""

	var area_pattern := ""  ## bombs only — blast footprint from Function data
	var magnitude: int = -1  ## buff / shield — per-Packet bonus from data

	## Attribution, carried for metrics and logging.
	var program_id := ""
	var fn_id := ""

	var deal_damage: int = -1  ## bombs only
	var gain_charge: int = -1  ## bombs only

	## Global placement order. Armed overlays tick oldest-first, so this is
	## gameplay-affecting rather than bookkeeping.
	var seq := 0

	func is_armed() -> bool:
		return countdown > 0

	func duplicate_special() -> Special:
		var s := Special.new()
		s.type = type
		s.owner = owner
		s.countdown = countdown
		s.delivers = delivers
		s.area_pattern = area_pattern
		s.magnitude = magnitude
		s.program_id = program_id
		s.fn_id = fn_id
		s.deal_damage = deal_damage
		s.gain_charge = gain_charge
		s.seq = seq
		return s

class_name Areas
extends RefCounted

## Area-Pattern Registry — stable IDs mapped to EXPLICIT coordinate sets, never
## derived from catalog numbers at runtime.
##
## Coordinate convention: (0,0) is the source/detonating Packet, +x right,
## +y down. Out-of-board coordinates are clipped by the consumer at resolution
## time; clipping never changes which pattern is in use.
##
## Each entry is a strict superset of the one before it, and the registry order
## IS the progression order that `PSV_BIGGER_BOMB` advances along.
##
## CELL ORDER IS SIGNIFICANT. The ordered cells are fingerprint input, so a port
## producing the same set in a different order would pass a set-equality check
## and still change the fingerprint. The construction below preserves
## first-seen order exactly as the alpha's `union()` does.

const SELF := "AREA_SELF"
const CARDINAL_1 := "AREA_CARDINAL_1"
const SQUARE_3X3 := "AREA_SQUARE_3X3"
const SQUARE_3X3_CARDINAL_2 := "AREA_SQUARE_3X3_CARDINAL_2"
const FAT_CROSS_2 := "AREA_FAT_CROSS_2"
const SQUARE_5X5 := "AREA_SQUARE_5X5"
const FAT_CROSS_3 := "AREA_FAT_CROSS_3"
const SQUARE_7X7_CROSS_4 := "AREA_SQUARE_7X7_CROSS_4"

## The one progression authority, in ascending unclipped-footprint order.
## `PSV_BIGGER_BOMB` advances a pattern by index along this list; UI and combat
## both read it here rather than keeping a second catalog.
const PATTERN_ORDER: Array[String] = [
	SELF,
	CARDINAL_1,
	SQUARE_3X3,
	SQUARE_3X3_CARDINAL_2,
	FAT_CROSS_2,
	SQUARE_5X5,
	FAT_CROSS_3,
	SQUARE_7X7_CROSS_4,
]

static var _patterns: Dictionary = {}


## Built lazily because GDScript `const` cannot hold computed values, and the
## cumulative patterns are constructed rather than typed out. Construction, not
## runtime derivation: the result is cached and the stored coordinate sets are
## what every consumer reads.
static func patterns() -> Dictionary:
	if _patterns.is_empty():
		_build()
	return _patterns


static func cells(id: String) -> Array[Vector2i]:
	var p := patterns()
	if not p.has(id):
		return [] as Array[Vector2i]
	return p[id]


static func is_pattern_id(s: String) -> bool:
	return patterns().has(s)


## Advance `steps` NAMED steps, saturating at the largest registered pattern.
## Edge clipping never changes the step: this operates on names, not on how many
## cells survive the board bounds. `steps <= 0` returns the input unchanged.
static func advance(id: String, steps: int) -> String:
	if steps <= 0:
		return id
	var i := PATTERN_ORDER.find(id)
	if i < 0:
		return id
	return PATTERN_ORDER[mini(i + steps, PATTERN_ORDER.size() - 1)]


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

static func _build() -> void:
	var self_only: Array[Vector2i] = [Vector2i(0, 0)]

	# catalog 1 — AREA_SELF plus the four cardinal neighbours, in N/E/S/W order.
	var cardinal_1: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	]

	# catalog 2 — every coordinate in the centered 3x3, row-major from top-left.
	var square_3x3: Array[Vector2i] = []
	for y in [-1, 0, 1]:
		for x in [-1, 0, 1]:
			square_3x3.append(Vector2i(x, y))

	# catalog 3 — the 3x3 plus one Packet in each cardinal direction at distance
	# 2. Thirteen cells at board centre; deliberately NO distance-2 diagonals.
	var square_3x3_cardinal_2 := _union([
		square_3x3,
		[Vector2i(0, -2), Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0)] as Array[Vector2i],
	])

	# catalog 4 — the 3x3-plus-cardinals with 3-wide bars at distance 2.
	# 21 cells: the 5x5 square minus its four corners.
	var fat_cross_2 := _union([square_3x3_cardinal_2, _cardinal_bars(2, 1)])

	# catalog 5 — the fat cross plus the four (+-2,+-2) corners. 25 cells.
	var square_5x5 := _union([fat_cross_2, _square(2)])

	# catalog 6 — 3 cells in each cardinal direction at distance 3. 37 cells.
	var fat_cross_3 := _union([square_5x5, _cardinal_bars(3, 1)])

	# catalog 7 — 7x7 square plus 5 cells in each cardinal direction. 69 cells
	# unclipped, which on the 8x8 Datastream always clips to the whole board.
	var square_7x7_cross_4 := _union([fat_cross_3, _square(3), _cardinal_bars(4, 2)])

	_patterns = {
		SELF: self_only,
		CARDINAL_1: cardinal_1,
		SQUARE_3X3: square_3x3,
		SQUARE_3X3_CARDINAL_2: square_3x3_cardinal_2,
		FAT_CROSS_2: fat_cross_2,
		SQUARE_5X5: square_5x5,
		FAT_CROSS_3: fat_cross_3,
		SQUARE_7X7_CROSS_4: square_7x7_cross_4,
	}


## A perpendicular bar of `half * 2 + 1` cells centered on each cardinal
## direction at `dist`. Emission order per offset is N, E, S, W — which is part
## of the resulting first-seen order and therefore of the fingerprint.
static func _cardinal_bars(dist: int, half: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for o in range(-half, half + 1):
		out.append(Vector2i(o, -dist))
		out.append(Vector2i(dist, o))
		out.append(Vector2i(o, dist))
		out.append(Vector2i(-dist, o))
	return out


static func _square(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			out.append(Vector2i(x, y))
	return out


## Deduplicate while preserving first-seen order, so a cumulative pattern reads
## as "everything smaller, then what this step adds".
static func _union(groups: Array) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for g in groups:
		for o in g:
			if seen.has(o):
				continue
			seen[o] = true
			out.append(o)
	return out

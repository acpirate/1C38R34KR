class_name Rng
extends RefCounted

## Seedable RNG — an exact port of the alpha's mulberry32 (`src/logic/rng.ts`).
##
## D-009: Godot's own `RandomNumberGenerator` is PCG32 and produces a
## completely different sequence. Substituting it would forfeit the differential
## gate, which is the only mechanical check available on the rules translation.
## This must reproduce `tests/fixtures/rng_vectors.json` exactly.
##
## The JavaScript original:
##
##     s = (s + 0x6d2b79f5) >>> 0;
##     let t = s;
##     t = Math.imul(t ^ (t >>> 15), t | 1);
##     t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
##     return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
##
## Four hazards, all handled below:
##
## 1. GDScript `int` is 64-bit signed; JS bitwise ops are 32-bit. Every
##    intermediate is masked back to 32 bits.
## 2. `Math.imul` is a wrapping 32-bit multiply. Two masked uint32 operands can
##    produce a product up to ~1.8e19, which exceeds int64's ~9.2e18 maximum, so
##    `_imul` splits the operands into 16-bit halves rather than relying on
##    overflow behaviour. See `test_rng.gd`, which asserts the split form and
##    the naive form agree.
## 3. `>>>` is an unsigned right shift. On a value already masked non-negative,
##    GDScript's `>>` is equivalent — but the mask must come first, every time.
## 4. The final division is by a float, not an integer.
##
## Signed-versus-unsigned never matters for the XOR/OR/AND steps: the low 32
## bits are identical under either interpretation. The one place it could
## matter — `t ^= t + imul(...)`, where JS adds two *signed* int32 without
## truncating — is safe because the sum is congruent mod 2^32 either way, and
## only the low 32 bits survive the XOR.

const MASK := 0xFFFFFFFF
const ADD := 0x6d2b79f5
const TWO32 := 4294967296.0

var _s: int


## `seed_value` is the raw internal state, matching `makeRNG(seed)`. Passing a
## previous `get_state()` therefore resumes the exact sequence, which is what
## save/resume determinism depends on (D-022).
func _init(seed_value: int) -> void:
	_s = seed_value & MASK


## Wrapping 32-bit multiply, equivalent to `Math.imul`.
## Split into 16-bit halves so the intermediate product cannot exceed int64.
static func _imul(a: int, b: int) -> int:
	var a_lo := a & 0xFFFF
	var a_hi := (a >> 16) & 0xFFFF
	var b_lo := b & 0xFFFF
	var b_hi := (b >> 16) & 0xFFFF
	# The hi*hi term contributes only above bit 32, so it is dropped.
	var cross := (a_hi * b_lo + a_lo * b_hi) & 0xFFFF
	return (a_lo * b_lo + (cross << 16)) & MASK


## The raw uint32 the algorithm produces before its final division.
## Tests compare on this rather than the float, so no float formatting
## difference between JS and GDScript can register as a divergence.
func next_u32() -> int:
	_s = (_s + ADD) & MASK
	var t := _s
	t = _imul(t ^ (t >> 15), t | 1)
	t = t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & MASK)
	return (t ^ (t >> 14)) & MASK


## Float in [0, 1).
func next() -> float:
	return float(next_u32()) / TWO32


## Integer in [0, n). Mirrors `Math.floor(next() * n)` — the float multiply is
## deliberate, because that is the form the alpha uses and an integer
## reformulation could round differently at the boundary.
func int_below(n: int) -> int:
	return int(floor(next() * n))


func pick(a: Array):
	return a[int(floor(next() * a.size()))]


## In-place Fisher-Yates, descending, matching the alpha exactly. A port that
## iterated ascending would consume the same draws in a different order and
## produce a different permutation.
func shuffle(a: Array) -> Array:
	var i := a.size() - 1
	while i > 0:
		var j := int(floor(next() * (i + 1)))
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
		i -= 1
	return a


## Internal state, so a battle can be saved and resumed deterministically.
func get_state() -> int:
	return _s

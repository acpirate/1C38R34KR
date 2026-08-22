class_name Fingerprint
extends RefCounted

## Content fingerprint — a byte-exact port of the alpha's `computeFingerprint`.
##
## The fingerprint gates save compatibility and stamps every differential trace.
## A fingerprint that merely *exists* is useless; one that MATCHES the alpha's
## for identical content proves the whole parse, normalize, and resolve path
## ported faithfully. That is why authorization §15.3 keeps the requirement.
##
## Two halves, pinned separately by `test_fingerprint.gd` so a mismatch says
## which one is wrong rather than leaving 11,170 characters to search:
##
##   1. `stringify` — reproduces JavaScript's `JSON.stringify` output
##   2. `djb2`      — the hash and its `${hex8}-${length36}` format
##
## Godot's own `JSON.stringify()` cannot be used: it does not guarantee JS's
## exact number formatting or escaping, and the whole point is byte equality.

const HASH_SEED := 5381
const MASK := 0xFFFFFFFF


## `h = ((h << 5) + h + charCodeAt(i)) >>> 0`, formatted as
## `${hex8}-${utf16Length.toString(36)}`.
##
## Iterates UTF-16 CODE UNITS, not codepoints. JavaScript strings are UTF-16 and
## `charCodeAt` yields units, so a character outside the BMP contributes two.
## GDScript strings are UTF-32, so a codepoint-based loop would diverge on any
## non-BMP character — and would also report a different length in the suffix.
## Authored content is ASCII today, which is precisely why this would go
## unnoticed until the day someone pastes an emoji into a notes column.
static func djb2(s: String) -> String:
	var units := utf16_units(s)
	var h := HASH_SEED
	for u in units:
		h = (((h << 5) & MASK) + h + u) & MASK
	return "%08x-%s" % [h, _to_base36(units.size())]


## The UTF-16 code units of `s`, computing surrogate pairs directly from
## codepoints rather than round-tripping through a byte buffer, which would
## raise byte-order and BOM questions with no upside.
static func utf16_units(s: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in s.length():
		var cp := s.unicode_at(i)
		if cp <= 0xFFFF:
			out.append(cp)
		else:
			var v := cp - 0x10000
			out.append(0xD800 + (v >> 10))
			out.append(0xDC00 + (v & 0x3FF))
	return out


static func _to_base36(n: int) -> String:
	if n == 0:
		return "0"
	const DIGITS := "0123456789abcdefghijklmnopqrstuvwxyz"
	var out := ""
	var v := n
	while v > 0:
		out = DIGITS[v % 36] + out
		v /= 36
	return out


# ---------------------------------------------------------------------------
# Canonical serialization
# ---------------------------------------------------------------------------

## Reproduces JavaScript `JSON.stringify` for the value shapes the fingerprint
## contains: dictionaries, arrays, strings, integers, and booleans.
##
## Key order is INSERTION order, matching JS object property order — the alpha
## does not sort, and sorting here would change every fingerprint.
static func stringify(value) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			return _float_to_js(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return _quote(str(value))
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			for k in (value as Dictionary):
				parts.append("%s:%s" % [_quote(str(k)), stringify(value[k])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			var items := PackedStringArray()
			for v in value:
				items.append(stringify(v))
			return "[%s]" % ",".join(items)
		TYPE_VECTOR2I:
			# The alpha stores area offsets as `{x, y}` objects, in that key
			# order. Vector2i is the natural GDScript carrier, so it serializes
			# to the same shape rather than forcing callers to unpack it.
			return '{"x":%d,"y":%d}' % [value.x, value.y]
		_:
			push_error("fingerprint: unsupported value type %d" % typeof(value))
			return "null"


## JS renders an integral float without a decimal point: `1.0` serializes as
## `1`. A5 established that no fingerprinted value is non-integer, so a genuine
## fraction here means content changed shape and the mismatch should be loud.
static func _float_to_js(f: float) -> String:
	if f == floor(f) and abs(f) < 9007199254740992.0:
		return str(int(f))
	push_error("fingerprint: non-integer value %f — JS float formatting is not reproduced" % f)
	return str(f)


## JSON string escaping as JS performs it: quote, backslash, the five short
## control escapes, and `\u00XX` for any other control character. Non-ASCII is
## emitted RAW, not `\u`-escaped — `JSON.stringify("café")` is `"café"`.
static func _quote(s: String) -> String:
	var out := "\""
	for i in s.length():
		var cp := s.unicode_at(i)
		match cp:
			0x22: out += "\\\""
			0x5C: out += "\\\\"
			0x08: out += "\\b"
			0x0C: out += "\\f"
			0x0A: out += "\\n"
			0x0D: out += "\\r"
			0x09: out += "\\t"
			_:
				if cp < 0x20:
					out += "\\u%04x" % cp
				else:
					out += String.chr(cp)
	return out + "\""


## Convenience: canonicalize then hash, which is what the loader calls.
static func of(value) -> String:
	return djb2(stringify(value))

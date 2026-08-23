class_name TraceNorm
extends RefCounted

## Normalizes a GDScript event into the alpha's canonical JSON form, so the two
## engines' streams can be compared byte for byte.
##
## This is REPRESENTATIONAL normalization only — the narrow set the addendum
## sanctions: key naming, enum spelling, coordinate shape, key order, and float
## formatting. It must never smooth over a gameplay difference, because doing so
## would make the gate quietly report agreement it has not established.
##
## The alpha is the reference, so its spellings win: camelCase keys, string
## enums, `{x, y}` coordinates.


## snake_case → the alpha's camelCase. A key absent from this map passes through
## unchanged, which is correct for the many single-word keys.
const KEY_MAP := {
	"owner_kind": "ownerKind",
	"program_id": "programId",
	"fn_id": "fnId",
	"effect_id": "effectId",
	"crit_extra": "critExtra",
	"buff_bonus": "buffBonus",
	"color_raw": "colorRaw",
	"shape_raw": "shapeRaw",
	"cascade_raw": "cascadeRaw",
	"passive_raw": "passiveRaw",
	"pre_shield": "preShield",
	"stream_source": "streamSource",
	"source_id": "sourceId",
	"overflow_out": "overflowOut",
	"target_program_id": "targetProgramId",
	"target_readiness": "targetReadiness",
	"target_charge_before": "targetChargeBefore",
	"target_charge_after": "targetChargeAfter",
	"target_cost": "targetCost",
	"target_tile": "targetTile",
	"direct_damage": "directDamage",
	"direct_charge": "directCharge",
	"axis_target": "axisTarget",
	"axis_result": "axisResult",
	"result_color": "resultColor",
	"result_shape": "resultShape",
	"tier2_used": "tier2Used",
	"specials_retained": "specialsRetained",
	"specials_destroyed": "specialsDestroyed",
	"passive_id": "passiveId",
	"source_kind": "sourceKind",
}

## Keys whose integer value is an enum, and the name table that decodes it.
##
## Only unambiguous keys appear here. `kind` deliberately does not: it names a
## Packet kind in one event and an overlay kind in another, so those are emitted
## as strings at source instead of guessed at here.
const ENUM_KEYS := {
	"side": "side",
	"target": "side",
	"owner": "side",
	"winner": "side",
	"source": "damage_source",
	"owner_kind": "owner_kind",
	"stream_source": "charge_stream_source",
	"target_readiness": "readiness",
	"source_kind": "passive_source_kind",
	"orientation": "orientation",
}

const ORIENTATION_NAMES := ["h", "v"]


static func _decode(table: String, value: int) -> String:
	match table:
		"side": return Types.SIDE_NAMES[value]
		"damage_source": return Types.DAMAGE_SOURCE_NAMES[value]
		"owner_kind": return Types.OWNER_KIND_NAMES[value]
		"charge_stream_source": return Types.CHARGE_STREAM_SOURCE_NAMES[value]
		"readiness": return Types.READINESS_NAMES[value]
		"passive_source_kind": return Types.PASSIVE_SOURCE_KIND_NAMES[value]
		"orientation": return ORIENTATION_NAMES[value]
	return str(value)


## `target` is a Side in a damage event but a COORDINATE in a targeted event, so
## it cannot be decoded by key name alone either. These event types are the ones
## where `target` is a coordinate.
const COORDINATE_TARGET_EVENTS := [&"targeted"]


static func normalize_event(ev: Dictionary) -> Dictionary:
	var t := StringName(ev["t"])
	var out := {}
	for k in ev:
		if k == "t":
			out["t"] = String(t)
			continue
		var value = ev[k]
		var key: String = KEY_MAP.get(k, k)

		# A null optional is omitted, matching JavaScript's treatment of an
		# undefined property — emitting it as null would be a spurious difference.
		if value == null:
			continue

		if k == "target" and COORDINATE_TARGET_EVENTS.has(t):
			out[key] = _normalize_value(value)
			continue

		if ENUM_KEYS.has(k) and typeof(value) == TYPE_INT:
			out[key] = _decode(ENUM_KEYS[k], value)
			continue

		out[key] = _normalize_value(value)
	return out


static func _normalize_value(v):
	match typeof(v):
		TYPE_NIL:
			return null
		TYPE_VECTOR2I:
			return {"x": v.x, "y": v.y}
		TYPE_DICTIONARY:
			var out := {}
			for k in (v as Dictionary):
				var value = v[k]
				if value == null:
					continue
				var key: String = KEY_MAP.get(k, k)
				if ENUM_KEYS.has(k) and typeof(value) == TYPE_INT:
					out[key] = _decode(ENUM_KEYS[k], value)
				else:
					out[key] = _normalize_value(value)
			return out
		TYPE_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY:
			var out := []
			for item in v:
				out.append(_normalize_value(item))
			return out
		TYPE_STRING_NAME:
			return String(v)
		_:
			return v


## Canonical JSON with SORTED keys, so insertion order can never register as a
## difference. Godot's `JSON.stringify` is not used: it gives no ordering
## guarantee and does not match JavaScript's number formatting.
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
			return Fingerprint._quote(str(value))
		TYPE_DICTIONARY:
			var keys := (value as Dictionary).keys()
			keys.sort()
			var parts := PackedStringArray()
			for k in keys:
				parts.append("%s:%s" % [Fingerprint._quote(str(k)), stringify(value[k])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var items := PackedStringArray()
			for item in value:
				items.append(stringify(item))
			return "[%s]" % ",".join(items)
		TYPE_VECTOR2I:
			return '{"x":%d,"y":%d}' % [value.x, value.y]
	return "null"


## Matches the alpha's normalizer: integral floats render as integers, and a
## genuine fraction is fixed to six decimals so representation drift between the
## two engines is not mistaken for divergence.
static func _float_to_js(f: float) -> String:
	if f == floor(f) and absf(f) < 9007199254740992.0:
		return str(int(f))
	var s := "%.6f" % f
	# JavaScript's Number(v.toFixed(6)) drops trailing zeros; match that.
	s = s.rstrip("0")
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s

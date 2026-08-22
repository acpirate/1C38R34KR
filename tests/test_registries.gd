extends RefCounted

## Effect and PASSIVE registry parity.
##
## These are validation contracts, so a divergence does not misbehave visibly —
## it silently accepts content the alpha would reject, or rejects content the
## alpha accepts. Neither surfaces until someone edits a spreadsheet months
## later and gets an inexplicable result, which is exactly why they are pinned
## against a fixture rather than eyeballed.

const FIXTURE := "res://tests/fixtures/registries.json"

## The alpha's target kinds are strings; ours are enum values.
const TARGET_KIND_NAMES := {
	"unit": Types.TargetKind.UNIT,
	"packet": Types.TargetKind.PACKET,
}

## Alpha PASSIVE param kinds are strings; ours are enum values.
const PARAM_KIND_NAMES := {
	"color": PassiveEffects.ParamKind.COLOR,
	"scope": PassiveEffects.ParamKind.SCOPE,
	"positiveInt": PassiveEffects.ParamKind.POSITIVE_INT,
}


func run(t: TestCase) -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		t.group("registries")
		t.check("fixture is readable", false)
		return
	var fixture = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(fixture) != TYPE_DICTIONARY:
		t.group("registries")
		t.check("fixture parses", false)
		return

	_test_param_names(t, fixture)
	_test_effects(t, fixture)
	_test_passives(t, fixture)


func _test_param_names(t: TestCase, fixture: Dictionary) -> void:
	t.group("registries / parameter vocabularies")
	var expected_params := []
	for v in (fixture["effect_param_names"] as Array):
		expected_params.append(str(v))
	var actual_params := []
	for v in Effects.PARAM_NAMES:
		actual_params.append(v)
	t.eq_seq("discrete parameter columns", actual_params, expected_params)

	var expected_axes := []
	for v in (fixture["effect_axis_names"] as Array):
		expected_axes.append(str(v))
	var actual_axes := []
	for v in Effects.AXIS_NAMES:
		actual_axes.append(v)
	t.eq_seq("axis columns", actual_axes, expected_axes)


func _test_effects(t: TestCase, fixture: Dictionary) -> void:
	t.group("registries / effects")
	var expected: Dictionary = fixture["effects"]
	t.eq("registered effect count", Effects.registry().size(), expected.size())

	for id in expected.keys():
		var want: Dictionary = expected[id]
		var got := Effects.contract(id)
		if got.is_empty():
			t.check("%s is registered" % id, false)
			continue

		t.eq_seq("%s required" % id, _strings(got["required"]), _strings(want["required"]))
		t.eq_seq("%s optional" % id, _strings(got["optional"]), _strings(want["optional"]))
		t.eq("%s targeted" % id, got["targeted"], want["targeted"])
		t.eq_seq("%s axes" % id, _strings(got["axes"]), _strings(want["axes"]))

		# A null target kind in the alpha means the Effect never asks for one.
		var want_kind = want["targetKind"]
		var expected_kind: int = Types.TargetKind.NONE if want_kind == null else TARGET_KIND_NAMES[str(want_kind)]
		t.eq("%s target kind" % id, got["target_kind"], expected_kind)

		# Tuple field ORDER and ranges both matter: the tuple is positional, so
		# a reordered field would silently reinterpret every authored value.
		var want_tuple: Array = want["tuple"]
		var got_tuple: Array = got["tuple"]
		t.eq("%s tuple arity" % id, got_tuple.size(), want_tuple.size())
		if got_tuple.size() == want_tuple.size():
			for i in want_tuple.size():
				var wf: Dictionary = want_tuple[i]
				var gf: Dictionary = got_tuple[i]
				t.eq("%s tuple[%d] name" % [id, i], gf["name"], str(wf["name"]))
				t.eq("%s tuple[%d] min" % [id, i], gf["min"], int(wf["min"]))
				t.eq("%s tuple[%d] max" % [id, i], gf["max"], int(wf["max"]))


func _test_passives(t: TestCase, fixture: Dictionary) -> void:
	t.group("registries / passives")
	var expected: Dictionary = fixture["passives"]
	t.eq("registered passive-effect count", PassiveEffects.registry().size(), expected.size())

	for id in expected.keys():
		var want: Dictionary = expected[id]
		var got := PassiveEffects.contract(id)
		if got.is_empty():
			t.check("%s is registered" % id, false)
			continue

		var want_params := []
		for p in (want["params"] as Array):
			want_params.append(PARAM_KIND_NAMES[str(p)])
		t.eq_seq("%s params" % id, got["params"], want_params)

		# The activation is part of the contract, not a free combination: a
		# continual modifier authored as START_OF_TURN is a content error.
		t.eq(
			"%s activation" % id,
			PassiveEffects.ACTIVATION_NAMES[got["activation"]],
			str(want["activation"]),
		)
		var want_payload := "required" if got["payload"] == PassiveEffects.Payload.REQUIRED else "forbidden"
		t.eq("%s payload" % id, want_payload, str(want["payload"]))

	t.check("CONTINUAL is a recognized activation", PassiveEffects.is_activation("CONTINUAL"))
	t.check("nonsense is not an activation", not PassiveEffects.is_activation("SOMETIMES"))
	t.check("OWNER is a recognized scope", PassiveEffects.is_agent_scope("OWNER"))
	t.check("nonsense is not a scope", not PassiveEffects.is_agent_scope("EVERYONE"))


func _strings(a) -> Array:
	var out := []
	for v in (a as Array):
		out.append(str(v))
	return out

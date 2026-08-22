class_name TestCase
extends RefCounted

## Minimal assertion context shared by every test file.
##
## Deliberately tiny: this build's real verification muscle is the differential
## harness (D-019), not a unit-test framework. This exists to make per-rule
## checks readable and to give the runner an exit code.

var passed := 0
var failed := 0
var _group := ""


func group(name: String) -> void:
	_group = name
	print("  %s" % name)


func check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("    FAIL  %s / %s" % [_group, label])


## Equality with the actual and expected values reported on failure. Use this
## over `check` wherever a mismatch would otherwise be undiagnosable.
func eq(label: String, actual, expected) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		printerr("    FAIL  %s / %s" % [_group, label])
		printerr("          expected: %s" % [expected])
		printerr("          actual:   %s" % [actual])


## Compares long integer sequences without emitting one result per element.
## Reports the first divergence with its index, which is what makes an RNG or
## trace mismatch tractable.
func eq_seq(label: String, actual: Array, expected: Array) -> void:
	if actual.size() != expected.size():
		failed += 1
		printerr("    FAIL  %s / %s — length %d, expected %d" % [_group, label, actual.size(), expected.size()])
		return
	for i in actual.size():
		if actual[i] != expected[i]:
			failed += 1
			printerr("    FAIL  %s / %s — first divergence at index %d" % [_group, label, i])
			printerr("          expected: %s" % [expected[i]])
			printerr("          actual:   %s" % [actual[i]])
			return
	passed += 1

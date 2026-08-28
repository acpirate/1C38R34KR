class_name DataIssues
extends RefCounted

## Structured validation diagnostics.
##
## Every issue carries dataset, file, row, record ID, field, supplied value,
## expected form, and reason. That completeness is the point: content is
## authored in a spreadsheet by someone who is not reading GDScript, so a
## diagnostic that says only "invalid row" costs far more than it saves.
##
## Contract, unchanged from the alpha:
##   - all issues are collected, not thrown on first failure
##   - any error blocks startup; warnings do not
##   - invalid data is never silently repaired, and there is no content fallback

enum Severity { ERROR = 0, WARNING }

const DATASET_HACKER_PROGRAMS := "hacker-programs"
const DATASET_SYSTEM_PROGRAMS := "system-programs"
const DATASET_FUNCTIONS := "functions"
const DATASET_HACKERS := "hackers"
const DATASET_PASSIVES := "passives"
const DATASET_DECKS := "decks"
const DATASET_SYSTEMS := "systems"
const DATASET_HOSTS := "hosts"
const DATASET_UPGRADES := "upgrades"
const DATASET_BOSSES := "bosses"
const DATASET_TEXT_CONTENT := "text-content"
const DATASET_TEXT_STYLE := "text-style"
const DATASET_FONT_REFS := "font-refs"
const DATASET_CONTENT := "content"

var issues: Array[Dictionary] = []
var error_count := 0
var warning_count := 0


## `fields` accepts any of: dataset, file, row, id, field, value, expected,
## reason. Absent keys are omitted from the formatted output rather than
## rendered as empty, matching the alpha.
func error(fields: Dictionary) -> void:
	var i := fields.duplicate()
	i["severity"] = Severity.ERROR
	issues.append(i)
	error_count += 1


func warn(fields: Dictionary) -> void:
	var i := fields.duplicate()
	i["severity"] = Severity.WARNING
	issues.append(i)
	warning_count += 1


func has_errors() -> bool:
	return error_count > 0


func errors() -> Array[Dictionary]:
	return issues.filter(func(i): return i["severity"] == Severity.ERROR)


func warnings() -> Array[Dictionary]:
	return issues.filter(func(i): return i["severity"] == Severity.WARNING)


## Mirrors the alpha's `formatIssue` field order and separators so headless
## output stays comparable between the two implementations.
static func format(i: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append("[ERROR]" if i.get("severity", Severity.ERROR) == Severity.ERROR else "[WARNING]")
	parts.append(str(i.get("dataset", "")))

	var file := str(i.get("file", ""))
	if i.has("row"):
		file += ":%d" % int(i["row"])
	parts.append(file)

	if i.has("id") and str(i["id"]) != "":
		parts.append("id=%s" % i["id"])
	if i.has("field") and str(i["field"]) != "":
		parts.append("field=%s" % i["field"])
	if i.has("value"):
		parts.append("value=%s" % JSON.stringify(str(i["value"])))
	if i.has("expected") and str(i["expected"]) != "":
		parts.append("expected=%s" % i["expected"])
	parts.append("— %s" % i.get("reason", ""))

	return " ".join(parts.filter(func(p): return p != ""))


func format_all() -> PackedStringArray:
	var out := PackedStringArray()
	for i in issues:
		out.append(format(i))
	return out

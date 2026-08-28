class_name Text
extends RefCounted

## What the game says — the one place a player-facing string comes from.
##
## Callers ask for `(SEMANTIC_CATEGORY, REF_ID)` and never for a row index or a
## file. That is the whole contract: swapping copy, or eventually a language,
## means editing `text_content.csv` and nothing else.
##
## ## Why this is in the logic layer
##
## Because it is DATA, and it holds no scene reference — the same reason
## `Content` lives here. What matters for layer purity is the other direction:
## nothing under `scripts/logic/` may CALL this. Logs and records carry stable
## object IDs, and a display name is resolved presentation-side (D-041). That is
## what keeps a log record stable when someone fixes a typo, and what makes
## `ATTACKER` unambiguous when both a Hacker and a System Program are named it.

## Category names, so a caller writes `Text.PROGRAM_NAME` rather than a string
## literal that a typo turns into a MISSING marker at runtime.
const PROGRAM_NAME := "PROGRAM_NAME"
const SYSTEM_NAME := "SYSTEM_NAME"
const BOSS_NAME := "BOSS_NAME"
const HACKER_NAME := "HACKER_NAME"
const DECK_NAME := "DECK_NAME"
const HOST_NAME := "HOST_NAME"
const UPGRADE_NAME := "UPGRADE_NAME"
const FUNCTION_NAME := "FUNCTION_NAME"
const PASSIVE_TEXT := "PASSIVE_TEXT"
const UI_SCREEN_TITLE := "UI_SCREEN_TITLE"
const UI_SCREEN_PROMPT := "UI_SCREEN_PROMPT"
const UI_BUTTON_TEXT := "UI_BUTTON_TEXT"
const UI_STATUS_TEXT := "UI_STATUS_TEXT"

## Which category a content ID belongs to, by prefix.
##
## Exists so a caller holding an opaque id — a Program in a metrics row, an
## opponent of unknown kind — can ask for its name without first working out
## what it is. The opponent union (`SYS`/`BOS`) is exactly this problem, and
## P-042 was what happened when a caller guessed.
const PREFIX_CATEGORY := {
	"PRG_H_": PROGRAM_NAME,
	"PRG_S_": PROGRAM_NAME,
	"SYS_": SYSTEM_NAME,
	"BOS_": BOSS_NAME,
	"HAK_": HACKER_NAME,
	"DEK_": DECK_NAME,
	"HST_": HOST_NAME,
	"UPG_": UPGRADE_NAME,
	"FNC_": FUNCTION_NAME,
	"PSV_": PASSIVE_TEXT,
}


## The string for one semantic key.
##
## A missing row renders `[MISSING: CATEGORY / REF_ID]` and logs an error (§9).
## Visible rather than blank: an empty label looks like a layout bug and gets
## chased in the wrong file, while the marker names exactly which row to author.
static func get_text(category: String, ref_id: String) -> String:
	var table: Dictionary = Content.active().get("text", {})
	var key := "%s/%s" % [category, ref_id]
	if table.has(key):
		return str(table[key])

	push_error("text: missing row %s" % key)
	return "[MISSING: %s / %s]" % [category, ref_id]


## The string for a key, with `{token}` placeholders substituted.
##
## Every token in the template must be supplied. An unresolved one is left
## visible as `{token}` and logged — the same reasoning as a missing row, and the
## reason §8 asks for validation rather than silent substitution.
##
## Extra arguments are NOT an error: a caller passing a superset is harmless, and
## rejecting it would make one shared argument dictionary impossible.
static func format(category: String, ref_id: String, args: Dictionary) -> String:
	return fill(get_text(category, ref_id), args, "%s/%s" % [category, ref_id])


## Substitutes `{token}` in an already-retrieved template.
##
## Separate from `format` because PASSIVE text arrives pre-expanded from the
## loader, and the battle log composes a line from parts.
static func fill(template: String, args: Dictionary, where := "") -> String:
	var out := template
	for token in args:
		out = out.replace("{%s}" % token, str(args[token]))

	# Anything still in braces was never supplied. Report it once with its key,
	# so the failure names the row rather than just appearing on screen.
	var rx := RegEx.create_from_string(r"\{(\w+)\}")
	var unresolved := rx.search_all(out)
	if not unresolved.is_empty():
		var names := PackedStringArray()
		for m in unresolved:
			names.append(m.get_string(1))
		push_error("text: unresolved placeholder(s) %s in %s" % [
			", ".join(names), where if where != "" else template
		])
	return out


## A gameplay object's display name, from its ID alone.
##
## The category is derived from the ID prefix, so a caller does not have to know
## whether an opponent is a System or a Boss — the mistake P-042 made.
static func name_of(ref_id: String) -> String:
	for prefix in PREFIX_CATEGORY:
		if ref_id.begins_with(prefix):
			return get_text(PREFIX_CATEGORY[prefix], ref_id)

	push_error("text: no category for id '%s'" % ref_id)
	return "[MISSING: ? / %s]" % ref_id


## Whether a row exists, without logging or rendering a marker.
##
## For callers that legitimately branch on absence rather than treating it as an
## error — a UI that hides an optional line instead of showing a marker.
static func has(category: String, ref_id: String) -> bool:
	return Content.active().get("text", {}).has("%s/%s" % [category, ref_id])

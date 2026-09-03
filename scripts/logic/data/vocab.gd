class_name Vocab
extends RefCounted

## CSV token vocabularies, dataset headers, and required record IDs.
##
## Headers are matched exactly and bound by NAME, so authored column order is
## irrelevant. Retired header names are deliberately NOT accepted as aliases:
## a stale spreadsheet export fails the header check rather than being silently
## reinterpreted. That rule is why `SKILL`, `BASE_LINK`-on-a-System, and a `BOS`
## sheet missing `BOSS_PASSIVE_DESCRIPTION` are all hard errors.


# ---------------------------------------------------------------------------
# Enum token vocabularies — 3-letter uppercase codes
# ---------------------------------------------------------------------------

const COLOR_TOKENS := {
	"RED": Types.PacketColor.RED,
	"YEL": Types.PacketColor.YELLOW,
	"MAG": Types.PacketColor.MAGENTA,
	"GRE": Types.PacketColor.GREEN,
	"CYA": Types.PacketColor.CYAN,
	"BLU": Types.PacketColor.BLUE,
}

const SHAPE_TOKENS := {
	"CIR": Types.PacketShape.CIRCLE,
	"SQU": Types.PacketShape.SQUARE,
	"TRI": Types.PacketShape.TRIANGLE,
	"DIA": Types.PacketShape.DIAMOND,
	"STR": Types.PacketShape.STAR,
	"CRO": Types.PacketShape.CROSS,
}

## The recognized vocabularies in ENUM order. Weak sets are calculated
## complements over these, so a derived set always presents in recognized order
## regardless of the order the strong set was authored in.
const RECOGNIZED_COLORS: Array[int] = [0, 1, 2, 3, 4, 5]
const RECOGNIZED_SHAPES: Array[int] = [0, 1, 2, 3, 4, 5]


# ---------------------------------------------------------------------------
# Dataset headers
# ---------------------------------------------------------------------------

const PROGRAM_HEADER: Array[String] = ["PRG_ID", "name", "colors", "shapes", "functions", "notes"]

const FUNCTION_HEADER: Array[String] = [
	"FNC_ID", "name", "cost", "payload", "notes", "quantity", "countdown",
	"areaPattern", "magnitude", "damage", "params", "startCharged",
	"axisTarget", "axisResult",
]

const HACKER_HEADER: Array[String] = [
	"HAK_ID", "name", "BASE_LINK", "STRONG_COLORS", "STRONG_SHAPES", "PRG_SET",
	"PASSIVES",
]

## `display` moved to `text_content.csv` as `PASSIVE_TEXT` in beta 0.3.2. The
## template's positional `%0`/`%1` tokens are still validated against each
## effect's param contract at load — only where the string is STORED changed.
const PASSIVE_HEADER: Array[String] = [
	"PASSIVE_ID", "passive_effect", "params", "activation", "function_payload",
	"agent_scope", "notes",
]

const DECK_HEADER: Array[String] = ["DEK_ID", "name", "ADD_LINK", "PRG_SET", "FUNCTIONS"]

## The durability column is BASE_ICE, never BASE_LINK.
const SYSTEM_HEADER: Array[String] = [
	"SYS_ID", "name", "in_pool", "BASE_ICE", "STRONG_COLORS", "STRONG_SHAPES",
	"PRG_SET", "PASSIVES",
]

## HOST carries `in_pool`; UPGRADE does not, because UPGRADE eligibility is Run
## state (acquired or not) rather than authored content.
const HOST_HEADER: Array[String] = ["HOST_ID", "name", "passives", "in_pool", "notes"]
const UPGRADE_HEADER: Array[String] = ["UPGRADE_ID", "name", "passives", "notes"]

# ---------------------------------------------------------------------------
# Text framework (beta 0.3.2)
# ---------------------------------------------------------------------------
#
# Three sheets that load through the ordinary content path, so they get the same
# header contract, the same issue reporting, and the same shipping mechanism as
# every other datasheet. Authorization §15: no second pipeline.

const TEXT_CONTENT_HEADER: Array[String] = ["SEMANTIC_CATEGORY", "REF_ID", "EN"]
const TEXT_STYLE_HEADER: Array[String] = [
	"STYLE_ID", "FONT_ROLE", "WEIGHT", "NOMINAL_SIZE", "MIN_SIZE",
	"FIT_MODE", "MAX_LINES", "H_ALIGN", "COLOR_ROLE",
]
const FONT_REFS_HEADER: Array[String] = ["FONT_ROLE", "WEIGHT", "FONT_FILE"]

## How text behaves inside the rectangle layout gives it (§5.2).
##
## Deliberately four. `SHRINK` is the only one that may reduce the authored
## size, and it is the only one that requires a `MIN_SIZE` — which is what makes
## "no uncontrolled shrink until it fits" enforceable rather than aspirational.
const FIT_MODES: Array[String] = ["FIXED", "SHRINK", "WRAP", "ELLIPSIS"]

const H_ALIGNS: Array[String] = ["LEFT", "CENTER", "RIGHT"]

## Semantic text colours. A naming layer over `PacketStyle`, NOT a recolouring
## system — every role resolves to a constant that already existed.
const COLOR_ROLES: Array[String] = [
	"PRIMARY", "SECONDARY", "FAINT", "HEADING", "STATUS", "EMPHASIS", "DAMAGE",
]

const FONT_WEIGHTS: Array[String] = ["REGULAR", "BOLD"]

## The style every unknown `STYLE_ID` falls back to. Must exist in the sheet.
const FALLBACK_STYLE_ID := "BODY"

## The font role an unknown role falls back to. Must exist in `font_refs.csv`.
const FALLBACK_FONT_ROLE := "UI_SANS"

## Deliberately NOT the System header: no `PASSIVES` column and no
## `MECHANIC_ID`. A Boss contributes no identity PASSIVEs, and ODANSHAY's
## Override mechanic is code keyed to `BOS_01` rather than a data-driven
## scripting field, so no column is invented to hold it.
## No `in_pool`: the column was dropped from the workbook in Beta 0.4 because
## it never governed anything. Boss Selection lists every authored row, so the
## flag had no reader — see `read_bosses`.
const BOSS_HEADER: Array[String] = [
	"BOS_ID", "name", "BASE_ICE", "STRONG_COLORS", "STRONG_SHAPES",
	"PRG_SET",
]


# ---------------------------------------------------------------------------
# Required record IDs
# ---------------------------------------------------------------------------
#
# Presence is required; the VALUES are validated by the schema and contract
# rules, with the dataset as final authority on what those values are.

const REQUIRED_FNC_IDS: Array[String] = [
	"FNC_001", "FNC_002", "FNC_003", "FNC_004", "FNC_005",
	"FNC_006", "FNC_007", "FNC_008", "FNC_009", "FNC_010",
	"FNC_011", "FNC_012", "FNC_013", "FNC_014", "FNC_015",
	"FNC_016", "FNC_017",
	# Zero-cost Boss mechanic payloads, never directly assigned.
	# 018-020 ODANSHAY, 021 NEHBOCYET, 022 ECHOFALL.
	"FNC_018", "FNC_019", "FNC_020", "FNC_021", "FNC_022",
]

const REQUIRED_PRG_H_IDS: Array[String] = [
	"PRG_H_001", "PRG_H_002", "PRG_H_003", "PRG_H_004", "PRG_H_005", "PRG_H_006",
]

## PRG_S_004 DISABLER remains required content regardless of which Systems
## currently field it.
const REQUIRED_PRG_S_IDS: Array[String] = [
	"PRG_S_001", "PRG_S_002", "PRG_S_003", "PRG_S_004",
	"PRG_S_005", "PRG_S_006", "PRG_S_007", "PRG_S_008",
]

const REQUIRED_HAK_IDS: Array[String] = ["HAK_01"]
const REQUIRED_PSV_IDS: Array[String] = [
	"PSV_001", "PSV_002", "PSV_003", "PSV_004", "PSV_005",
	"PSV_006", "PSV_007", "PSV_008", "PSV_009",
]
const REQUIRED_DEK_IDS: Array[String] = ["DEK_01"]
const REQUIRED_SYS_IDS: Array[String] = ["SYS_01", "SYS_02", "SYS_03"]
const REQUIRED_HST_IDS: Array[String] = ["HST_01", "HST_02", "HST_03", "HST_04", "HST_05"]
const REQUIRED_UPG_IDS: Array[String] = ["UPG_01", "UPG_02", "UPG_03", "UPG_04"]
const REQUIRED_BOS_IDS: Array[String] = ["BOS_01"]


# ---------------------------------------------------------------------------
# Value normalization
# ---------------------------------------------------------------------------

## Spreadsheets prefix a cell with a single apostrophe to force text mode, so
## `'0:1:0:0:1` and `'7` survive editing as literal strings.
##
## Remove EXACTLY one leading apostrophe: a second is data (`''VALUE` becomes
## `'VALUE`), and embedded or trailing apostrophes are never touched. This runs
## BEFORE trimming, so a quoted-then-padded cell normalizes the same way an
## unquoted one does — which is what makes fingerprints agree across two
## authorings of the same content.
static func strip_leading_apostrophe(raw: String) -> String:
	return raw.substr(1) if raw.begins_with("'") else raw


## Blank or whitespace-only means absent. Only plain non-negative integer digits
## are valid syntax — no sign, decimal point, exponent, or hex.
##
## Returns `{present: bool, valid: bool, value: int}`.
static func parse_int_field(raw: String) -> Dictionary:
	var t := raw.strip_edges()
	if t == "":
		return {"present": false, "valid": true, "value": 0}
	for i in t.length():
		var c := t.unicode_at(i)
		if c < 48 or c > 57:
			return {"present": true, "valid": false, "value": 0}
	# GDScript ints are 64-bit; a value this long is out of any sane range and
	# is rejected rather than silently truncated.
	if t.length() > 18:
		return {"present": true, "valid": false, "value": 0}
	return {"present": true, "valid": true, "value": t.to_int()}


static func title_case(t: String) -> String:
	if t == "":
		return t
	return t.substr(0, 1).to_upper() + t.substr(1).to_lower()

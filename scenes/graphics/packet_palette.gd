class_name PacketPalette
extends RefCounted

## Reads the six Packet colours out of `packet_palette.svg`.
##
## ## Why the SVG is parsed rather than compiled away
##
## D-033: the SVG is the director's lossless handoff channel for colour, not a
## live art pipeline. Given the choice between hardcoding the values and
## shipping the file, shipping it wins for one reason — a hardcoded copy can
## silently drift from the document that is supposed to define it, and
## drift-between-stale-prose-and-live-runtime has already cost this project
## twice (P-043). Parsing makes drift structurally impossible.
##
## The file is imported with `importer="keep"` and shipped by
## `include_filter="*.csv,*.svg"`, the same mechanism the content CSVs use.
##
## Lives here rather than in a tool so the game and `tools/check_assets.gd`
## share ONE parser. Two implementations of the same grammar is how a checker
## ends up certifying a file the game cannot read.

## Swatch ids, in `Types.PacketColor` ENUM ORDER.
##
## Not alphabetical, and not the order the intent document listed them in. A
## System's weak set is derived as the enum-order complement of its strong set,
## so an index here is gameplay identity — reordering this array silently
## rewrites every weakness in the game.
const IDS := ["packet_red", "packet_yellow", "packet_magenta", "packet_green", "packet_cyan", "packet_blue"]


## The result of a parse: six colours, and everything that went wrong.
##
## Both are returned rather than one or the other because §10 wants missing
## assets to fail VISIBLY without crashing — the caller needs usable colours to
## keep drawing AND a list to report.
class Result extends RefCounted:
	var colors: Array[Color] = []
	var problems: PackedStringArray = PackedStringArray()

	func ok() -> bool:
		return problems.is_empty()


## Parses the SVG text against `fallback`, which supplies any swatch that could
## not be read. `fallback` must carry one entry per id.
static func parse(svg_text: String, fallback: Array[Color]) -> Result:
	var out := Result.new()

	if svg_text.strip_edges().is_empty():
		out.problems.append("palette: the SVG is empty or unreadable as text")
		out.colors = fallback.duplicate()
		return out

	var seen := {}
	for i in IDS.size():
		var id: String = IDS[i]
		var raw := _fill_of(svg_text, id)

		if raw == "":
			out.problems.append("palette: no fill found for id '%s'" % id)
			out.colors.append(fallback[i])
			continue
		if not raw.is_valid_html_color():
			out.problems.append("palette: '%s' is not a colour (%s)" % [id, raw])
			out.colors.append(fallback[i])
			continue

		# A duplicate is reported but ACCEPTED. Two identical Packet colours
		# would be a miserable board, but it is the director's board to make
		# miserable — this is a palette file, and refusing to load it over a
		# taste question would be the tool overruling the artist.
		if seen.has(raw):
			out.problems.append("palette: '%s' duplicates '%s' (%s)" % [id, seen[raw], raw])
		seen[raw] = id
		out.colors.append(Color.from_string(raw, fallback[i]))

	return out


## One swatch's fill.
##
## Accepts `fill="#rrggbb"` and `style="...fill:#rrggbb..."` because Inkscape
## writes whichever the object was created with, and converts between them on
## save. A parser that handled only one form would break the first time the file
## came back from the editor it exists for.
static func _fill_of(svg_text: String, id: String) -> String:
	var at := svg_text.find('id="%s"' % id)
	if at < 0:
		return ""
	var close := svg_text.find(">", at)
	if close < 0:
		return ""

	var tag := svg_text.substr(at, close - at)
	var rx := RegEx.create_from_string(r'fill\s*[=:]\s*"?\s*(#[0-9a-fA-F]{6})')
	var m := rx.search(tag)
	return m.get_string(1) if m != null else ""

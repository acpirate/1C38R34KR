class_name Graphics
extends RefCounted

## The one way the game reaches the graphics pack.
##
## Screens ask for semantics — `Graphics.pack().button_normal`,
## `Graphics.glyph(shape)` — and never for a path. Centralising it here is what
## makes replacing the whole look a single `.tres` swap, and what stops asset
## filenames from scattering back through the scene layer (authorization §9.3).
##
## Static because there is exactly one pack for the life of the process and no
## screen should be able to hold a different one. `load()` is called once at
## startup, before any screen is built.

const DEFAULT_PACK := "res://assets/packs/v0/pack.tres"

## Where packs live. A directory here holding a `pack.tres` is a skin.
const PACKS_DIR := "res://assets/packs"

static var _pack: GraphicsPack = null
static var _palette: Array[Color] = []
static var _missing: Texture2D = null
static var _problems := PackedStringArray()

## The loaded pack's directory name, for the skin picker to display.
static var _current_name := ""

## Memoised 9-slice boxes, keyed on [texture, margin]. Cleared with the pack.
static var _boxes := {}


## Loads and validates a pack. Returns every problem found, empty on success.
##
## Reports ALL failures together rather than stopping at the first: a pack that
## is short six assets should say so once, not six launches in a row. Same
## reasoning the content loader already uses.
static func load_pack(path := DEFAULT_PACK) -> PackedStringArray:
	_problems = PackedStringArray()
	_pack = null
	_palette = []
	_boxes.clear()

	if not ResourceLoader.exists(path):
		_problems.append("graphics: no pack at '%s'" % path)
		_use_fallback_palette()
		return _problems

	var res := ResourceLoader.load(path)
	if res is not GraphicsPack:
		_problems.append("graphics: '%s' is not a GraphicsPack" % path)
		_use_fallback_palette()
		return _problems

	_pack = res
	# "…/packs/<name>/pack.tres" -> "<name>"
	_current_name = path.get_base_dir().get_file()
	for key in _pack.validate():
		_problems.append("graphics: missing required asset '%s'" % key)

	_load_palette()
	return _problems


## Every skin installed in this build, by name, sorted.
##
## Discovered rather than listed: adding a skin should mean adding a directory,
## not editing code. A directory counts as a skin when it holds a `pack.tres` —
## an authoring bundle or a half-built pack is skipped rather than offered and
## then failing to load.
##
## `DirAccess` reads the export's file table, so this works in a shipped build
## as well as in the project directory — which is the kind of claim this project
## has learned to verify on a device rather than assume.
static func installed_packs() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(PACKS_DIR)
	if dir == null:
		return out

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			if ResourceLoader.exists("%s/%s/pack.tres" % [PACKS_DIR, name]):
				out.append(name)
		name = dir.get_next()
	dir.list_dir_end()

	out.sort()
	return out


## The pack currently loaded, by name.
static func current_pack_name() -> String:
	return _current_name


## Loads a skin by name rather than by path.
static func load_pack_named(name: String) -> PackedStringArray:
	return load_pack("%s/%s/pack.tres" % [PACKS_DIR, name])


## Problems from the last `load_pack`, for a caller that wants them later.
static func problems() -> PackedStringArray:
	return _problems


static func is_loaded() -> bool:
	return _pack != null


## The pack. Never null once `load_pack` has run — an unloaded pack returns an
## empty one so a caller reading a field gets `null` and therefore the MISSING
## texture, rather than a crash on a nil dereference.
static func pack() -> GraphicsPack:
	if _pack == null:
		_pack = GraphicsPack.new()
	return _pack


## One Packet glyph, keyed by `Types.PacketShape`.
##
## A function rather than raw array access so an out-of-range key degrades to
## MISSING instead of throwing. The renderer indexes this from game state, and
## game state is the one thing that must never be able to crash the view.
static func glyph(shape_index: int) -> Texture2D:
	return _at(pack().packet_glyph, shape_index)


## The centre mark of an overlay badge, keyed by `Tile.Special.Type`. Since
## D-037 this carries the whole type signal.
static func mark(type_index: int) -> Texture2D:
	return _at(pack().overlay_mark, type_index)


## One countdown numeral, keyed by DIGIT VALUE rather than by index into a
## string — so composing a multi-digit number is a loop over its digits and
## nothing has to parse anything (§11.3).
static func digit(value: int) -> Texture2D:
	return _at(pack().countdown_digit, value)


## The suspended type ring, keyed by `Tile.Special.Type` (D-037).
##
## Nothing calls this today. It exists so that restoring the ring is a renderer
## change and not a contract change.
static func ring(type_index: int) -> Texture2D:
	return _at(pack().overlay_ring, type_index)


## The ownership badge. Ownership is the badge's FILL — light for the Hacker,
## dark for the System — which is the convention that carries ownership for
## every overlay type without a legend.
static func badge(is_player: bool) -> Texture2D:
	var t: Texture2D = pack().badge_player if is_player else pack().badge_enemy
	return t if t != null else missing()


## One Packet colour, keyed by `Types.PacketColor`.
##
## Comes from the palette SVG when it could be read and from `PacketStyle` when
## it could not, so the board is always drawable.
static func palette(color_index: int) -> Color:
	if _palette.is_empty():
		_use_fallback_palette()
	if color_index < 0 or color_index >= _palette.size():
		return PacketStyle.COLOR_FILL[0]
	return _palette[color_index]


## The diagnostic texture a missing asset resolves to.
##
## Deliberately hideous, and deliberately NOT the procedural whitebox it
## replaced. §9.4 — an element that lost its asset has to LOOK broken, because
## a tasteful fallback is indistinguishable from success and would hide exactly
## the failure this exists to surface.
##
## Generated rather than shipped: an asset pack cannot be trusted to contain the
## texture that reports the asset pack is broken.
static func missing() -> Texture2D:
	if _missing != null:
		return _missing

	var n := 32
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var odd := ((x / 8) + (y / 8)) % 2 == 1
			img.set_pixel(x, y, PacketStyle.MISSING_A if odd else PacketStyle.MISSING_B)
	_missing = ImageTexture.create_from_image(img)
	return _missing


## A cached 9-sliced StyleBox for `tex`.
##
## For `_draw` code that needs nine-patch behaviour. `draw_texture_rect`
## STRETCHES the whole image, which is fine for a flat fill and wrong for
## anything with a border: a 2 px edge in a 48 px source becomes a 24 px slab on
## a 590 px-wide control, and the wider the control the worse it gets. That is
## visible on a device and invisible in a unit test.
##
## Cached because the board redraws constantly and there are sixty-four Packets:
## building a StyleBox per draw call would allocate thousands of them a second
## for no reason. Keyed on the texture and margin, so a pack swap yields new
## boxes rather than stale ones.
static func box(tex: Texture2D, margin: int) -> StyleBoxTexture:
	var key := [tex, margin]
	if _boxes.has(key):
		return _boxes[key]

	var b := StyleBoxTexture.new()
	b.texture = tex if tex != null else missing()
	b.set_texture_margin_all(margin)
	b.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	b.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_boxes[key] = b
	return b


static func _at(arr: Array[Texture2D], i: int) -> Texture2D:
	if i < 0 or i >= arr.size() or arr[i] == null:
		return missing()
	return arr[i]


static func _load_palette() -> void:
	var path := str(pack().palette_svg)
	if path.is_empty():
		_problems.append("graphics: the pack names no palette SVG")
		_use_fallback_palette()
		return

	if not FileAccess.file_exists(path):
		_problems.append("graphics: no palette SVG at '%s'" % path)
		_use_fallback_palette()
		return

	var result := PacketPalette.parse(
		FileAccess.get_file_as_string(path), _fallback_colors()
	)
	_palette = result.colors
	for p in result.problems:
		_problems.append("graphics: %s" % p)


static func _use_fallback_palette() -> void:
	_palette = _fallback_colors()


## The registry's own values, which are the alpha's. Using these when the SVG
## cannot be read means a broken palette file costs the CONFIGURABILITY of the
## colours, never the playability of the board.
static func _fallback_colors() -> Array[Color]:
	var out: Array[Color] = []
	for c in PacketStyle.COLOR_FILL:
		out.append(c)
	return out

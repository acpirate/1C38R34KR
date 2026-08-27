extends SceneTree

## Builds `pack.tres` from the assets on disk.
##
## Run:  godot --headless -s res://tools/gen_pack_resource.gd
##
## Generated rather than hand-authored for the same reason the pack itself is:
## forty-four resource paths maintained by hand drift the first time an asset is
## renamed, and the failure is silent until someone opens the screen holding the
## stale one. Here the resource is derived from the files that actually exist,
## and re-running it after any pack change is the whole maintenance story.

const PACK := "res://assets/packs/v0"

## Semantic key → file, for the single-texture fields. The key is the exported
## property name on `GraphicsPack`; the value is its path within the pack.
const SINGLES := {
	"screen_bg": "chrome/screen_bg",
	"panel": "chrome/panel",
	"button_normal": "chrome/button_normal",
	"button_pressed": "chrome/button_pressed",
	"button_selected": "chrome/button_selected",
	"button_disabled": "chrome/button_disabled",
	"rule": "chrome/rule",
	"scroll_track": "chrome/scroll_track",
	"scroll_thumb": "chrome/scroll_thumb",
	"bar_track": "chrome/bar_track",
	"bar_fill_link": "chrome/bar_fill_link",
	"bar_fill_ice": "chrome/bar_fill_ice",
	"bar_fill_charge": "chrome/bar_fill_charge",
	"bar_fill_charge_ready": "chrome/bar_fill_charge_ready",
	"avatar_box": "battle/avatar_box",
	"program_box_idle": "battle/program_box_idle",
	"program_box_charged": "battle/program_box_charged",
	"program_box_ready": "battle/program_box_ready",
	"program_box_armed": "battle/program_box_armed",
	"board_surround": "battle/board_surround",
	"packet_cell": "battle/packet_cell",
	"build_slot": "battle/build_slot",
	"ring_selected": "packet/ring_selected",
	"ring_targeting": "packet/ring_targeting",
	"badge_player": "overlay/badge_player",
	"badge_enemy": "overlay/badge_enemy",
	"icon_menu": "icon/menu",
	"icon_arrow_up": "icon/arrow_up",
	"icon_arrow_down": "icon/arrow_down",
	"icon_cancel": "icon/cancel",
}

## ENUM ORDER, and it is load-bearing in both cases — a Packet's shape index and
## a special's type index are gameplay identity, so an array built in the wrong
## order renders the right art against the wrong state.
const SHAPES := ["circle", "square", "triangle", "diamond", "star", "cross"]
const SPECIALS := ["bomb", "buff", "shield", "override"]


func _initialize() -> void:
	var pack := GraphicsPack.new()
	var missing := PackedStringArray()

	for key in SINGLES:
		var tex := _texture("%s/%s.png" % [PACK, SINGLES[key]])
		if tex == null:
			missing.append(str(key))
		pack.set(key, tex)

	pack.packet_glyph = _series("packet/glyph_%s", SHAPES, missing)
	pack.overlay_mark = _series("overlay/mark_%s", SPECIALS, missing)
	pack.overlay_ring = _series("overlay/ring_%s", SPECIALS, missing)
	pack.palette_svg = "%s/packet_palette.svg" % PACK

	if not missing.is_empty():
		for m in missing:
			push_error("gen_pack_resource: no texture for '%s'" % m)
		print("FAILED — %d asset(s) missing; pack.tres not written" % missing.size())
		quit(1)
		return

	# Validate the resource by its OWN contract before writing it. Writing a
	# pack that fails `validate()` would move the failure to launch, which is
	# exactly where this tool exists to stop it happening.
	var problems := pack.validate()
	if not problems.is_empty():
		for p in problems:
			push_error("gen_pack_resource: incomplete — %s" % p)
		print("FAILED — pack does not satisfy its own contract")
		quit(1)
		return

	var path := "%s/pack.tres" % PACK
	var err := ResourceSaver.save(pack, path)
	if err != OK:
		push_error("gen_pack_resource: could not write %s (error %d)" % [path, err])
		quit(1)
		return

	print("wrote %s" % path)
	print("  %d single textures" % SINGLES.size())
	print("  %d glyphs, %d marks, %d rings (suspended)" % [
		pack.packet_glyph.size(), pack.overlay_mark.size(), pack.overlay_ring.size()
	])
	print("  palette: %s" % pack.palette_svg)
	quit()


func _series(pattern: String, names: Array, missing: PackedStringArray) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for n in names:
		var key := pattern % n
		var tex := _texture("%s/%s.png" % [PACK, key])
		if tex == null:
			missing.append(key)
		out.append(tex)
	return out


func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path)
	return res as Texture2D

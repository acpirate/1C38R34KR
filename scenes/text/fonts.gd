class_name Fonts
extends RefCounted

## Semantic font roles to loaded font resources.
##
## Styles reference a ROLE, never a filename (§6.3), so swapping a typeface means
## editing `font_refs.csv` and nothing else. That is the whole reason this
## indirection exists.
##
## ## Why a role has a weight
##
## `font_refs.csv` is keyed `(FONT_ROLE, WEIGHT)`. Without the weight, "UI sans
## bold" would have to be a second ROLE — and then changing the sans family
## would mean editing two role rows and every style that named the bold one,
## which is exactly the coupling §6.3 exists to prevent.

static var _cache := {}
static var _warned := {}


## The font for a role and weight.
##
## Missing entries degrade in the order §9 asks for: the role's REGULAR weight,
## then the fallback role, then Godot's own default. The last step is a fallback
## of last resort, not the production path — §6.2 requires production text to
## come from a bundled resource, and a load that gets that far has already
## logged an error naming the row to fix.
static func of(role: String, weight := "REGULAR") -> Font:
	var key := "%s/%s" % [role, weight]
	if _cache.has(key):
		return _cache[key]

	var fonts: Dictionary = Content.active().get("fonts", {})
	var path := str(fonts.get(key, ""))

	if path == "" and weight != "REGULAR":
		_warn_once(key, "text: no %s weight for role '%s', using REGULAR" % [weight, role])
		return of(role, "REGULAR")

	if path == "" and role != Vocab.FALLBACK_FONT_ROLE:
		_warn_once(key, "text: unknown font role '%s', using %s" % [role, Vocab.FALLBACK_FONT_ROLE])
		return of(Vocab.FALLBACK_FONT_ROLE, weight)

	if path == "":
		_warn_once(key, "text: no bundled font for '%s' — falling back to the engine default" % key)
		var fallback := ThemeDB.fallback_font
		_cache[key] = fallback
		return fallback

	# `ResourceLoader`, not `FontFile.load_dynamic_font`: the .ttf is imported to
	# a .fontdata resource and the authored path does not exist in an exported
	# build. Reading the source file works on desktop and fails on device.
	var res := ResourceLoader.load(path)
	var font := res as Font
	if font == null:
		_warn_once(key, "text: '%s' did not load as a Font" % path)
		var fallback := ThemeDB.fallback_font
		_cache[key] = fallback
		return fallback

	_cache[key] = font
	return font


## Logs a given failure once.
##
## A font is asked for on every style resolution and every redraw; without this
## a single missing row would fill the device log and bury everything else,
## which is how a real diagnostic gets lost.
static func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_error(message)


static func clear_cache() -> void:
	_cache.clear()
	_warned.clear()

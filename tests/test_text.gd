extends RefCounted

## The text framework (beta 0.3.2).
##
## Covers the three sheets' contracts, semantic lookup, placeholder formatting,
## style resolution and fit policy, font-role resolution, and the failure
## behaviour §9 requires.
##
## The failure cases matter as much as the happy ones: "missing text fails
## visibly" is only true if something proves the marker actually appears, and a
## fallback that silently returns the wrong thing is worse than a crash.

func run(t: TestCase) -> void:
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		t.group("text")
		t.check("content loads", false)
		return
	Content.set_active(result["content"])
	TextStyles.clear_cache()
	Fonts.clear_cache()

	_test_content(t)
	_test_placeholders(t)
	_test_name_of(t)
	_test_styles(t)
	_test_fonts(t)
	_test_sheet_integrity(t)

	Content.clear()
	TextStyles.clear_cache()
	Fonts.clear_cache()


func _test_content(t: TestCase) -> void:
	t.group("text / semantic lookup")

	t.eq("a Program name resolves", Text.get_text(Text.PROGRAM_NAME, "PRG_H_001"), "BOMBER")
	t.eq("a Boss name resolves", Text.get_text(Text.BOSS_NAME, "BOS_01"), "ODANSHAY")
	t.eq("a UI button resolves", Text.get_text(Text.UI_BUTTON_TEXT, "GAME_UI_PAUSE_RESUME"), "Resume")

	# The two mirrored names are why logs carry IDs (D-041): the same string
	# names a Hacker Program and a System Program, so a name is not an identity.
	t.eq("mirrored name, Hacker side", Text.get_text(Text.PROGRAM_NAME, "PRG_H_003"), "ATTACKER")
	t.eq("mirrored name, System side", Text.get_text(Text.PROGRAM_NAME, "PRG_S_003"), "ATTACKER")

	t.check("has() finds a present row", Text.has(Text.PROGRAM_NAME, "PRG_H_001"))
	t.check("has() reports an absent row", not Text.has(Text.PROGRAM_NAME, "PRG_H_999"))

	# §9 — a missing row is VISIBLE, not blank. An empty label reads as a layout
	# bug and gets chased in the wrong file.
	var missing := Text.get_text(Text.PROGRAM_NAME, "PRG_H_999")
	t.check("a missing row renders a marker", missing.begins_with("[MISSING:"))
	t.check("the marker names the category", missing.contains("PROGRAM_NAME"))
	t.check("the marker names the ref", missing.contains("PRG_H_999"))


func _test_placeholders(t: TestCase) -> void:
	t.group("text / placeholders")

	t.eq(
		"named tokens substitute",
		Text.fill("Battle {current} of {total}", {"current": 3, "total": 4}),
		"Battle 3 of 4",
	)
	t.eq(
		"a token repeated twice fills twice",
		Text.fill("{x} and {x}", {"x": "A"}),
		"A and A",
	)
	# Extra args are deliberately NOT an error: one shared argument dictionary
	# should be usable across several templates.
	t.eq(
		"unused arguments are harmless",
		Text.fill("just {a}", {"a": 1, "b": 2}),
		"just 1",
	)
	# §8 — an unresolved token stays VISIBLE rather than rendering blank.
	t.eq(
		"an unresolved token is left in place",
		Text.fill("Battle {current} of {total}", {"current": 3}),
		"Battle 3 of {total}",
	)

	t.eq(
		"format() retrieves and fills",
		Text.format(Text.UI_STATUS_TEXT, "GAME_UI_BATTLE_TURN", {"turn": 7}),
		"Turn 7",
	)


func _test_name_of(t: TestCase) -> void:
	t.group("text / name from id alone")

	# The point of `name_of`: a caller holding an opaque id does not have to
	# know what kind of thing it is. Guessing is what P-042 did.
	t.eq("Hacker Program", Text.name_of("PRG_H_001"), "BOMBER")
	t.eq("System Program", Text.name_of("PRG_S_001"), "E-BOMBER")
	t.eq("System", Text.name_of("SYS_01"), "BOUNCER")
	t.eq("Boss", Text.name_of("BOS_01"), "ODANSHAY")
	t.eq("HOST", Text.name_of("HST_01"), "THRESHOLD")
	t.eq("UPGRADE", Text.name_of("UPG_01"), "BRACER")
	t.eq("Function", Text.name_of("FNC_001"), "BOMB")

	# A System id and a Boss id resolve through the same call — the union that
	# P-042 got wrong by choosing a registry.
	t.check("a Boss id does not resolve as a System", Text.name_of("BOS_01") != Text.name_of("SYS_01"))

	t.check("an unknown prefix is marked", Text.name_of("ZZZ_01").begins_with("[MISSING:"))


func _test_styles(t: TestCase) -> void:
	t.group("text / styles")

	var body := TextStyles.of("BODY")
	t.check("a style resolves", body != null)
	t.check("it carries a font", body.font != null)
	t.check("its size is scaled to the viewport", body.size > 15)

	# §5.2 — SHRINK never goes below its declared floor, and the loader refuses
	# a SHRINK row that declares none.
	var shrink := TextStyles.of("PROGRAM_NAME_BATTLE")
	t.eq("a SHRINK style declares its policy", shrink.fit, "SHRINK")
	t.check("its floor is below nominal", shrink.minimum < shrink.size)
	t.check("its floor is positive", shrink.minimum > 0)

	# An impossible width must stop at the floor rather than shrinking to
	# nothing — the failure mode "shrink until it fits" produces.
	t.eq(
		"an unfittable string stops at the minimum",
		shrink.size_to_fit("A VERY LONG PROGRAM NAME INDEED", 1.0),
		shrink.minimum,
	)
	t.eq(
		"a string that fits keeps the nominal size",
		shrink.size_to_fit("X", 10000.0),
		shrink.size,
	)
	# A non-SHRINK style must not resize whatever it is asked.
	t.eq(
		"a FIXED style ignores the available width",
		TextStyles.of("SCREEN_HEADING").size_to_fit("XXXXXXXXXXXXXXXXXXXX", 1.0),
		TextStyles.of("SCREEN_HEADING").size,
	)

	# §9 — an unknown style falls back readably rather than vanishing.
	var unknown := TextStyles.of("NO_SUCH_STYLE")
	t.check("an unknown style still yields a usable entry", unknown != null and unknown.font != null)
	t.check("and it is the declared fallback", unknown.id == Vocab.FALLBACK_STYLE_ID)

	# Colour roles are a naming layer over the registry, not new colours.
	t.eq("PRIMARY resolves to the registry", TextStyles.color_for("PRIMARY"), PacketStyle.TEXT)
	t.eq("DAMAGE resolves to the registry", TextStyles.color_for("DAMAGE"), PacketStyle.DAMAGE)


func _test_fonts(t: TestCase) -> void:
	t.group("text / fonts")

	var sans := Fonts.of("UI_SANS", "REGULAR")
	var bold := Fonts.of("UI_SANS", "BOLD")
	var mono := Fonts.of("UI_MONO", "REGULAR")

	t.check("the sans role loads", sans != null)
	t.check("the bold weight loads", bold != null)
	t.check("the mono role loads", mono != null)

	# §6.2 — production text must come from a bundled resource, not a device
	# fallback. Distinct objects prove three real files were loaded.
	t.check("bold is a different resource from regular", sans != bold)
	t.check("mono is a different resource from sans", sans != mono)
	t.check("the bundled font is not the engine fallback", sans != ThemeDB.fallback_font)

	# Monospace is the reason UI_MONO exists: report columns should align.
	var w1 := mono.get_string_size("111", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var w2 := mono.get_string_size("888", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	t.check("mono digits are tabular", absf(w1 - w2) < 0.5)

	# An unknown role degrades to the fallback role rather than to nothing.
	t.check("an unknown role still yields a font", Fonts.of("NO_SUCH_ROLE", "REGULAR") != null)


## The sheets' own integrity — the things a hand edit or a spreadsheet round
## trip can break without anyone noticing.
func _test_sheet_integrity(t: TestCase) -> void:
	t.group("text / sheet integrity")

	var text: Dictionary = Content.active().get("text", {})
	var styles: Dictionary = Content.active().get("styles", {})
	t.check("text rows loaded", text.size() > 100)
	t.check("style rows loaded", styles.size() > 5)

	# The declared fallbacks must exist, or §9's degradation has nowhere to go.
	t.check("the fallback style exists", styles.has(Vocab.FALLBACK_STYLE_ID))
	t.check("the fallback font role exists", Content.active().get("fonts", {}).has(
		"%s/REGULAR" % Vocab.FALLBACK_FONT_ROLE
	))

	# Every style names a font role that resolves.
	for id in styles:
		var role: String = styles[id]["font_role"]
		t.check("style %s names a loadable role" % id, Fonts.of(role, styles[id]["weight"]) != null)

	# Every gameplay object has a name. A Program without one renders a MISSING
	# marker in the middle of a battle, which is the loudest possible place.
	for id in Content.active()["programs"]:
		t.check("program %s has a name" % id, Text.has(Text.PROGRAM_NAME, id))
	for id in Content.active()["functions"]:
		t.check("function %s has a name" % id, Text.has(Text.FUNCTION_NAME, id))

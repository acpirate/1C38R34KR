extends Control

## Screen flow: Title → System Selection → HOST Selection → Build → Battle →
## Result.
##
## Beta 0.1 is Constructed Quick Match only. The Hacker and Deck are pinned by
## stable ID, so there are no selection screens for them; Runs, routes, and
## UPGRADEs arrive in 0.2.
##
## Whitebox throughout: Godot's default theme, no custom widgets, no imported
## fonts. Effort saved here is effort available for the differential harness,
## which is where the real risk lives.

const TITLE := "1C38R34KR"

var _shell: MarginContainer
var _panel: PanelContainer
var _root: VBoxContainer
var _content: Control

## The state of the battle currently on screen, kept so the result screen can
## report on it after the battle scene has been freed.
var _finished_state: GameState = null

var _system_id := ""
var _host_id := ""
var _build: Array = []
var _seed := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Set once on the root: every screen and the battle scene inherit it, so
	# there is exactly one place a control's appearance is decided.
	theme = UiTheme.build()

	# Debug builds log at VERBOSE and release at BASIC. COMPLETE is never
	# reached by defaulting — it retains the readable mirror and every ordinary
	# charge route, so it is an explicit diagnostic opt-in.
	BattleLog.set_level(BattleLog.default_level(OS.is_debug_build()))

	var bg := ColorRect.new()
	bg.color = PacketStyle.BOARD_BACKGROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Content validation runs before anything is shown. Any error blocks
	# startup with a readable report rather than a half-built screen — there is
	# no fallback content and no default System.
	var loader := ContentLoader.new()
	var result := loader.load_all()
	if not result["ok"]:
		_show_validation_failure(loader)
		return

	Content.set_active(result["content"])
	Passives.clear_cache()
	_show_title(result["fingerprint"])


func _show_validation_failure(loader: ContentLoader) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)

	var head := Label.new()
	head.text = "CONTENT VALIDATION FAILED — %d error(s)" % loader.issues.error_count
	box.add_child(head)

	var body := RichTextLabel.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lines := PackedStringArray()
	for e in loader.issues.errors():
		lines.append(DataIssues.format(e))
	body.text = "\n".join(lines)
	box.add_child(body)


# ---------------------------------------------------------------------------
# Screens
# ---------------------------------------------------------------------------

## Every menu is one bordered panel on the letterboxed background, rather than
## controls floating on the page. On a phone that reads as a dialog you are
## being asked to answer, which is what each of these screens actually is.
##
## `compact` shrinks the panel to its content and centres it — right for the
## title and the result, which are a heading and three buttons. The list screens
## pass `false` and take the full height, because they have a list to show and a
## short panel would just move the scrolling inside a smaller window.
func _fresh_screen(compact := false) -> VBoxContainer:
	if _shell != null:
		_shell.queue_free()

	_shell = MarginContainer.new()
	_shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shell.add_theme_constant_override("margin_left", UiTheme.px(10))
	_shell.add_theme_constant_override("margin_right", UiTheme.px(10))
	_shell.add_theme_constant_override("margin_top", UiTheme.px(12))
	_shell.add_theme_constant_override("margin_bottom", UiTheme.px(12))
	add_child(_shell)

	var host: Control = _shell
	if compact:
		var centre := CenterContainer.new()
		_shell.add_child(centre)
		host = centre

	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = UiTheme.px(250)

	var style := StyleBoxFlat.new()
	style.bg_color = PacketStyle.PANEL
	style.border_color = PacketStyle.PANEL_EDGE
	style.set_border_width_all(1)
	style.set_content_margin_all(UiTheme.px(14))
	_panel.add_theme_stylebox_override("panel", style)
	host.add_child(_panel)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", UiTheme.px(8))
	_panel.add_child(_root)
	return _root


## Bold, letter-spaced, upper case. It is the alpha's most recognisable piece of
## identity and costs one font-size override to keep.
func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", UiTheme.font_heading())
	l.add_theme_color_override("font_color", PacketStyle.TEXT_HEADING)
	_root.add_child(l)


## The grey line under a heading: what this screen is asking for, in one phrase.
func _subheading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", UiTheme.font_subheading())
	l.add_theme_color_override("font_color", PacketStyle.TEXT_DIM)
	_root.add_child(l)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = UiTheme.control_height()
	b.pressed.connect(action)
	_root.add_child(b)
	return b


func _divider() -> void:
	var line := ColorRect.new()
	line.color = PacketStyle.PANEL_EDGE
	line.custom_minimum_size.y = maxi(1, UiTheme.px(1))
	_root.add_child(line)


func _show_title(fingerprint: String) -> void:
	_fresh_screen(true)
	_heading(TITLE)
	_subheading("beta 0.1")

	# Continue appears only for a save this build can actually restore. A save
	# from different content is rejected rather than offered and then failed.
	var saved := SaveState.read()
	if saved["ok"]:
		var s: GameState = saved["state"]
		_button("Continue — turn %d" % s.turn, func(): _resume(s))

	_button("Constructed Quick Match", _show_system_select)

	_divider()

	var stamp := Label.new()
	# The fingerprint on the title screen is deliberate: it identifies exactly
	# which content a device build is running, which is the first question worth
	# asking when a device behaves unlike the harness.
	stamp.text = "content %s" % fingerprint
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.add_theme_font_size_override("font_size", UiTheme.font_small())
	stamp.add_theme_color_override("font_color", PacketStyle.TEXT_FAINT)
	_root.add_child(stamp)


## Lists every valid loaded System with the facts a choice depends on. `in_pool`
## is deliberately ignored here — that flag governs random routing only, so a
## tester can always field a specific encounter.
func _show_system_select() -> void:
	var options: Array = []
	for id in Content.active()["systems"]:
		var s := Content.system(id)
		options.append({
			"id": str(id),
			"name": "%s [%s]" % [s["name"], id],
			# Both halves of the matchup. Weak is the complement of Strong and so
			# is derivable, but the player is choosing what to play INTO — making
			# them compute it from six colours and six shapes in their head is
			# the kind of hidden arithmetic that makes a choice feel arbitrary.
			"lines": [
				"ICE %d" % int(s["base_ice"]),
				"Strong: %s, %s" % [
					_token_list(s["strong_colors"], Vocab.COLOR_TOKENS),
					_token_list(s["strong_shapes"], Vocab.SHAPE_TOKENS),
				],
				"Weak:   %s, %s" % [
					_token_list(_complement(s["strong_colors"], Constants.COLOR_COUNT), Vocab.COLOR_TOKENS),
					_token_list(_complement(s["strong_shapes"], Constants.SHAPE_COUNT), Vocab.SHAPE_TOKENS),
				],
			],
		})

	var choose := func(id):
		_system_id = id
		_show_host_select()
	_show_chooser("SELECT SYSTEM", "Choose the System you will breach", options, choose)


func _show_host_select() -> void:
	var options: Array = []
	for id in Content.active()["hosts"]:
		var h := Content.host(id)
		var passives: Array = h["passives"]
		var effect := "no PASSIVEs"
		if not passives.is_empty():
			var parts := PackedStringArray()
			for p in passives:
				# A carrier with no authored display renders as its payload
				# Function's name rather than as a blank line.
				var text := str(p["display"])
				if text == "":
					text = str(Content.function(str(p["function_id"]))["name"])
				parts.append(text)
			effect = ", ".join(parts)
		options.append({
			"id": str(id),
			"name": "%s [%s]" % [h["name"], id],
			"lines": [effect],
		})

	var choose := func(id):
		_host_id = id
		_show_build()
	_show_chooser("SELECT HOST", "Choose the HOST you will run from", options, choose, _show_system_select)


## Select-then-confirm, rather than commit-on-tap.
##
## On a phone a mis-tap on a scrolling list is common and, with commit-on-tap,
## unrecoverable — it drops you into the next screen having chosen something you
## did not read. Marking a card and confirming separately costs one extra tap
## and makes every wrong one free.
func _show_chooser(title: String, prompt: String, options: Array, on_choose: Callable, on_back = null) -> void:
	_fresh_screen()
	_heading(title)
	_subheading(prompt)

	var chosen := {"id": ""}
	var confirm := Button.new()
	var cards: Array[Button] = []

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UiTheme.px(6))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for opt in options:
		var card := Button.new()
		card.text = "%s\n%s" % [opt["name"], "\n".join(PackedStringArray(opt["lines"]))]
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.custom_minimum_size.y = UiTheme.px(64)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Wrap, and never let the text set the control's minimum width. A Button
		# sizes itself to its longest line by default, which on a fixed-width
		# phone panel pushes the whole layout wider than the screen instead of
		# wrapping — ARENA's PASSIVE description is long enough to do exactly
		# that.
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.clip_text = true
		var oid := str(opt["id"])
		card.pressed.connect(func():
			chosen["id"] = oid
			confirm.disabled = false
			for c in cards:
				c.modulate = PacketStyle.TINT_INACTIVE
			card.modulate = PacketStyle.TINT_NONE)
		card.modulate = PacketStyle.TINT_INACTIVE
		list.add_child(card)
		cards.append(card)

	confirm.text = "Choose"
	confirm.custom_minimum_size.y = UiTheme.control_height()
	confirm.disabled = true
	confirm.pressed.connect(func():
		if chosen["id"] != "":
			on_choose.call(str(chosen["id"])))
	_root.add_child(confirm)

	if on_back is Callable:
		_button("Back", on_back)


## The Build screen: four active Programs drawn from the six-Program inventory,
## in explicit order. That order is charge-routing priority, not decoration,
## which is why it is shown and editable rather than implied.
func _show_build() -> void:
	if _build.is_empty():
		_build = Session.default_build()
	_fresh_screen()
	_heading("BUILD")
	_subheading("ACTIVE BUILD (top to bottom) — order is charge priority")

	var inventory: Array = []
	inventory.append_array(Content.hacker(Content.DEFAULT_HACKER_ID)["portfolio"])
	inventory.append_array(Content.deck(Content.DEFAULT_DECK_ID)["portfolio"])

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UiTheme.px(6))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for slot in _build.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTheme.px(4))

		# Each slot shows what it IS, not just its name: the binding it draws
		# charge from and the Function it will fire. Those two facts are the
		# whole basis for ordering the build, and a bare name hides both.
		var current := Content.program(_build[slot])
		var summary := Button.new()
		summary.text = "%d. %s\n%s — %s (%d)" % [
			slot + 1, current["name"],
			_binding_text(current),
			current["fn"]["name"], int(current["cost"]),
		]
		summary.alignment = HORIZONTAL_ALIGNMENT_LEFT
		summary.custom_minimum_size.y = UiTheme.px(52)
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.clip_text = true
		summary.disabled = true
		# The amber left edge is the same mark a charged Program carries in
		# battle: this slot is live. It is not decoration — the inventory rows
		# below deliberately do not have it.
		summary.add_theme_stylebox_override("disabled", _slot_box())
		# It is disabled because it is a readout, not because it is unavailable
		# — so it keeps full contrast.
		summary.add_theme_color_override("font_disabled_color", PacketStyle.TEXT)
		row.add_child(summary)

		# ▲▼ reorder. Charge routes down the build in order, so moving a slot is
		# a real decision and gets its own control rather than being implied by
		# which Program you pick.
		var moves := VBoxContainer.new()
		moves.add_theme_constant_override("separation", UiTheme.px(2))
		moves.add_child(_move_button("▲", slot, -1))
		moves.add_child(_move_button("▼", slot, 1))
		row.add_child(moves)
		list.add_child(row)

		# Two rows of three rather than one row of six. At a size the text is
		# actually readable at, six controls across is wider than the screen —
		# and a row that overflows takes the entire panel with it.
		var swap_row := GridContainer.new()
		swap_row.columns = 3
		swap_row.add_theme_constant_override("h_separation", UiTheme.px(4))
		swap_row.add_theme_constant_override("v_separation", UiTheme.px(4))
		for pid in inventory:
			var prog := Content.program(pid)
			var b := Button.new()
			b.text = str(prog["name"])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.clip_text = true
			b.custom_minimum_size.y = UiTheme.px(34)
			# A Program already elsewhere in the build cannot be added twice:
			# the build is four DISTINCT Programs.
			b.disabled = _build.has(pid) and _build[slot] != pid
			b.modulate = PacketStyle.TINT_NONE if _build[slot] == pid else PacketStyle.TINT_INACTIVE
			var s := slot
			var p := str(pid)
			b.pressed.connect(func():
				_build[s] = p
				_show_build())
			swap_row.add_child(b)
		list.add_child(swap_row)

	if OS.is_debug_build():
		var seed_row := HBoxContainer.new()
		var seed_label := Label.new()
		seed_label.text = "seed"
		seed_row.add_child(seed_label)
		var seed_field := LineEdit.new()
		seed_field.text = str(_seed)
		seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Seed entry is the highest-leverage diagnostic: it makes a battle
		# observed on the phone reproducible in the headless harness.
		seed_field.text_changed.connect(func(t): _seed = int(t))
		seed_row.add_child(seed_field)
		_root.add_child(seed_row)

	_button("Begin", _start_battle)


## The Packet identities a Program draws charge from, in words. Full names, not
## a swatch: the Build screen is where a player learns what a binding IS, and
## the battle screen is where the swatch then means something.
func _binding_text(prog: Dictionary) -> String:
	var parts := PackedStringArray()
	var colors := _token_list(prog["colors"], Vocab.COLOR_TOKENS)
	var shapes := _token_list(prog["shapes"], Vocab.SHAPE_TOKENS)
	if colors != "":
		parts.append(colors)
	if shapes != "":
		parts.append(shapes)
	return " + ".join(parts) if parts.size() > 0 else "unbound"


func _slot_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PacketStyle.BOX
	# StyleBoxFlat paints one border colour, so the accent has to be the whole
	# border. At 1px on three sides and 4px on the left it still reads as an
	# edge bar rather than a highlighted box.
	box.border_color = PacketStyle.ACCENT
	box.set_border_width_all(1)
	box.border_width_left = maxi(2, UiTheme.px(4))
	box.content_margin_left = UiTheme.px(10)
	box.content_margin_right = UiTheme.px(10)
	box.content_margin_top = UiTheme.px(8)
	box.content_margin_bottom = UiTheme.px(8)
	return box


func _move_button(glyph: String, slot: int, delta: int) -> Button:
	var b := Button.new()
	b.text = glyph
	b.custom_minimum_size = Vector2(UiTheme.px(44), UiTheme.px(22))
	var dest := slot + delta
	b.disabled = dest < 0 or dest >= _build.size()
	if not b.disabled:
		b.pressed.connect(func():
			var moved = _build[slot]
			_build[slot] = _build[dest]
			_build[dest] = moved
			_show_build())
	return b


## The enum-order complement of an authored strong set — which is exactly how
## the logic layer derives a weak set, so this display cannot drift from the
## rule it reports.
func _complement(strong: Array, count: int) -> Array:
	var out: Array = []
	for i in count:
		if not strong.has(i):
			out.append(i)
	return out


func _token_list(values: Array, vocab: Dictionary) -> String:
	var names := PackedStringArray()
	for v in values:
		for token in vocab:
			if vocab[token] == v:
				names.append(token)
				break
	return "/".join(names)


# ---------------------------------------------------------------------------
# Battle
# ---------------------------------------------------------------------------

func _start_battle() -> void:
	_enter_battle(Session.create_quick_match(_system_id, _host_id, _seed, _build, {}, true))


## A save written before accounting existed, or by a harness run that carried
## none, resumes without it rather than starting a fresh accumulator mid-battle
## — half a battle's figures presented as a whole battle's would be worse than
## none at all.
func _resume(state: GameState) -> void:
	_enter_battle(state)


func _enter_battle(state: GameState) -> void:
	if _shell != null:
		_shell.queue_free()
		_shell = null
		_panel = null
		_root = null

	_finished_state = state

	var screen := BattleScreen.new()
	screen.setup(state)
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.battle_finished.connect(_on_battle_finished)
	screen.quit_requested.connect(func():
		# The save is written by the battle screen; this only returns to the
		# title, which then offers Continue.
		_content.queue_free()
		_content = null
		_show_title(Content.fingerprint()))
	_content = screen
	add_child(screen)


func _on_battle_finished(winner: int) -> void:
	# A concluded battle is not resumable, so its save is cleared rather than
	# left to offer a Continue that would restore a finished battle.
	SaveState.clear()
	if _finished_state != null:
		LogStore.flush_battle(_finished_state, _finished_state.metrics, _finished_state.log)
	_show_result(winner)


func _show_result(winner: int) -> void:
	if _content != null:
		_content.queue_free()
		_content = null

	var won := winner == Types.Side.PLAYER
	# Not compact: the report needs room to scroll. The exits stay above it, so
	# they remain reachable without scrolling past the whole thing.
	_fresh_screen(_finished_state == null or _finished_state.metrics == null)
	_heading("VICTORY" if won else "DEFEAT")
	_subheading("System ICE breached." if won else "Hacker LINK severed.")

	# The exits sit ABOVE the report, so they stay reachable on a phone without
	# scrolling past it. When metrics land in Phase 6 the report goes below this
	# divider and gets its own scroll region — the buttons do not move.
	#
	# Same seed replays an identical battle, which is the only reliable way to
	# reproduce a visual bug: a fresh seed means a fresh board.
	_button("Replay this seed", _start_battle)
	_button("New battle", func():
		_seed += 1
		_start_battle())
	_button("Back to title", func(): _show_title(Content.fingerprint()))

	_divider()

	var stamp := Label.new()
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stamp.add_theme_color_override("font_color", PacketStyle.TEXT_FAINT)
	stamp.text = "seed %d · content %s" % [_seed, Content.fingerprint()]
	_root.add_child(stamp)

	if _finished_state != null and _finished_state.metrics != null:
		_show_metrics(_finished_state)


## The battle report, in its own scroll region below the exits.
##
## Left-aligned and plain-text on purpose: this is a diagnostic readout, and a
## tester comparing it against a harness run needs to read values, not admire a
## chart. Per-Program lines carry the stable content ID for exactly that reason
## — it is what makes a screenshot of this screen actionable.
func _show_metrics(state: GameState) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = UiTheme.px(150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_color_override("font_color", PacketStyle.TEXT_DIM)
	body.text = "\n".join(_metrics_lines(state))
	scroll.add_child(body)


func _metrics_lines(state: GameState) -> PackedStringArray:
	var m := state.metrics
	var out := PackedStringArray()

	out.append("BATTLE")
	out.append("Turns to resolution: %d" % m.turns)
	out.append("Sync-locks (auto-reshuffles): %d" % m.auto_reshuffles)
	out.append("Detonations: %d" % m.detonations)
	out.append("System withholds: %d" % m.system_withholds)
	out.append("System shields — created %d, sliced %d" % [m.enemy_shield_created, m.enemy_shield_removed])
	out.append("Shielded hits: %d, damage prevented: %d" % [m.enemy_shield_instances, m.enemy_shield_prevented])

	_append_side(out, m, Types.Side.PLAYER, "HACKER")
	_append_side(out, m, Types.Side.ENEMY, "SYSTEM")
	return out


func _append_side(out: PackedStringArray, m: Metrics.Battle, side: Types.Side, title: String) -> void:
	var s := m.side(side)
	out.append("")
	out.append(title)
	out.append("Total damage dealt: %d" % s.total_damage)
	# Rounded for display only. The stored values are pre-floor floats — a
	# Shield rescales them proportionally — and rounding here rather than in the
	# accumulator is what keeps the buckets summing to the total exactly.
	out.append("Sync-caused (incl. its cascades): %d" % roundi(s.match_damage))
	out.append("bomb-caused (incl. its cascades): %d" % roundi(s.bomb_damage))
	out.append("line-slice-caused (incl. its cascades): %d" % roundi(s.lineslice_damage))
	out.append("transform-caused (incl. its cascades): %d" % roundi(s.transform_damage))
	out.append("Function-caused (incl. its cascades): %d" % roundi(s.attacker_damage))
	out.append("PASSIVE-caused: %d" % roundi(s.passive_damage))
	out.append("Buff added: %d" % roundi(s.buff_damage_added))
	out.append("Deepest cascade: %d RNG rounds" % s.deepest_cascade)
	out.append("Line clears: %d" % s.line_clears)

	var contested := s.contention_tiles
	var destroyed := s.tiles_destroyed
	var pct := (100.0 * float(contested) / float(destroyed)) if destroyed > 0 else 0.0
	out.append("Opponent-bound Packets sliced: %d of %d (%.1f%%)" % [contested, destroyed, pct])
	out.append("Charge wasted (no Program could take it): %d" % s.charge_wasted_total)

	# Ordered by the battle's own roster rather than by the metrics Dictionary,
	# so the report reads in charge-routing priority order — the same order the
	# Build screen presented.
	for u in (state_units(m, side)):
		var um: Metrics.Unit = s.units.get(u, null)
		if um == null:
			continue
		var prog := Content.program(u)
		out.append("%s [%s]: fired %d, effect %d" % [
			prog["name"], u, um.fires, roundi(um.effect),
		])

	if side == Types.Side.PLAYER and _finished_state != null:
		var deck := Content.deck(_finished_state.identity["deck_id"])
		out.append("%s [%s deck]: fired %d, neutral charge %d (wasted %d)" % [
			deck["name"], deck["id"], s.deck.fires,
			s.deck.charge_from_neutral, s.deck.charge_wasted,
		])

	for key in s.passives:
		var p: Metrics.Passive = s.passives[key]
		out.append("%s via %s: %d trigger(s), %d damage" % [
			p.passive_id, p.source_id, p.triggers, roundi(p.damage),
		])


## The side's Program IDs in roster order, read from the battle rather than from
## the metrics map — a Dictionary's iteration order is insertion order, which is
## not the order the player built.
func state_units(_m: Metrics.Battle, side: Types.Side) -> Array:
	var out: Array = []
	if _finished_state == null:
		return out
	for u in (_finished_state.units[side] as Array):
		out.append(u.program_id)
	return out

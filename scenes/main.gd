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

## The gameplay seed of the battle IN PLAY. Recorded so Replay reproduces the
## battle that was actually played rather than re-rolling a new one.
var _gameplay_seed := 0

## A seed the tester has PINNED through the debug field, or -1 for none.
##
## F-002: beta 0.1 used one `_seed` field initialised to 0 for both purposes, so
## every battle in a release build — where the debug field does not exist —
## started on the same board forever. The alpha never passes a seed at all and
## draws a fresh one per battle; this restores that, while keeping the pinned
## seed available as the diagnostic it was meant to be.
##
## The field starts EMPTY. A blank field means "roll one"; only a typed value
## pins. Pre-populating it with the current seed would silently re-pin whatever
## the last battle used, which is the behaviour being fixed.
var _seed_override := -1

## The build the Quick Match currently IN PLAY is using.
##
## Deliberately distinct from `_build`, which is the CONSTRUCTED working build.
## Random Quick Match rolls its own and must not overwrite the remembered
## constructed one — but "Replay this seed" still has to replay the build that
## was actually played. The alpha keeps this in its session for the same reason;
## collapsing the two makes a replay silently swap the loadout.
var _qm_build: Array = []

## The active session. At most one of these is non-null: a Run part-way through
## setup, or a committed Run. Both null means Quick Match, which keeps its
## selections in the fields above.
var _setup: RunSetup = null
var _run: Run = null

## The origin the Build screen currently on display opened with. Committed to
## the Run when the player confirms — the alpha's split between a Build screen's
## own state and the Run's committed build (see port-notes P-028).
var _build_origin: Types.BuildOrigin = Types.BuildOrigin.DEFAULT


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# GRAPHICS FIRST — before the Theme, and before content.
	#
	# `UiTheme.build()` now bakes pack textures into its styleboxes, so it has
	# to run after the pack is available or every button on every screen would
	# be built against a null texture and render as the MISSING checker. The
	# Theme is built once and inherited, so there is no second chance.
	#
	# Ahead of content too, because the content-failure screen is itself a
	# themed screen: if content is broken, the report saying so should still be
	# readable. Graphics has no dependency on content, so the order costs
	# nothing.
	#
	# Unlike content, this does NOT block (authorization §10). There is no
	# fallback content and no default System, so a content error leaves nothing
	# to show; a graphics error has the MISSING checker by design, and refusing
	# to launch would turn a cosmetic fault into an unplayable game. Every
	# problem is reported at once, and the checker makes the failure impossible
	# to miss on the screen that lost the asset.
	for problem in Graphics.load_pack():
		push_error(problem)

	# Set once on the root: every screen and the battle scene inherit it, so
	# there is exactly one place a control's appearance is decided.
	theme = UiTheme.build()

	# Debug builds log at VERBOSE and release at BASIC. COMPLETE is never
	# reached by defaulting — it retains the readable mirror and every ordinary
	# charge route, so it is an explicit diagnostic opt-in.
	BattleLog.set_level(BattleLog.default_level(OS.is_debug_build()))

	add_child(UiTheme.background())

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
	# §20.1 — the safe area is applied HERE, at the shell every menu is built
	# into, rather than screen by screen. Beta 0.2 adds five top-level screens;
	# opting each one in individually is how one of them gets missed, and a
	# missed one is unreachable controls under a cutout rather than a visible bug.
	var insets := UiTheme.safe_area_insets(size)
	_shell.add_theme_constant_override("margin_left", UiTheme.px(10) + insets.x)
	_shell.add_theme_constant_override("margin_right", UiTheme.px(10) + insets.z)
	_shell.add_theme_constant_override("margin_top", UiTheme.px(12) + insets.y)
	_shell.add_theme_constant_override("margin_bottom", UiTheme.px(12) + insets.w)
	add_child(_shell)

	var host: Control = _shell
	if compact:
		var centre := CenterContainer.new()
		_shell.add_child(centre)
		host = centre

	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = UiTheme.px(250)

	_panel.add_theme_stylebox_override("panel", UiTheme.panel_box())
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
	var line := UiTheme.rule()
	_root.add_child(line)


func _show_title(fingerprint: String) -> void:
	_fresh_screen(true)
	_heading(TITLE)
	# Derived from GAME_VERSION rather than typed, so a version bump cannot leave
	# the title screen claiming the previous build. It read "beta 0.2" through
	# the whole of 0.3 development because it was a literal.
	_subheading(Content.GAME_VERSION.replace("beta-", "beta ").trim_suffix(".0"))

	# Leaving the title drops whatever session was on screen, so nothing stale
	# survives into a new one.
	_setup = null
	_run = null

	# Continue appears only for a save this build can actually restore. A save
	# from different content is rejected rather than offered and then failed.
	var saved := SessionSave.read()
	if saved["ok"]:
		_button(_continue_label(saved), func(): _resume_session(saved))

	_button("New Run", _show_boss_select)
	_button("Constructed Quick Match", func():
		_run = null
		_show_system_select())
	_button("Random Quick Match", _start_random_quick_match)

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

	# TouchScroll, not ScrollContainer: these regions are wall-to-wall Buttons,
	# and a Button eats the one-finger drag that would otherwise scroll.
	var scroll := TouchScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

	# A Run builds against its OWN selected Hacker and Deck, and against a known
	# encounter. Quick Match keeps the pinned pair.
	var inventory: Array = []
	if _run != null:
		inventory = _run.inventory
		# §20 — Run context above the build. The encounter is committed by this
		# point, so what it is should not be something the player has to carry
		# in their head from the previous screen.
		for line in _run_context_lines():
			var ctx := Label.new()
			ctx.text = line
			ctx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ctx.add_theme_font_size_override("font_size", UiTheme.font_small())
			ctx.add_theme_color_override("font_color", PacketStyle.TEXT_DIM)
			_root.add_child(ctx)
		_divider()
	else:
		inventory.append_array(Content.hacker(Content.DEFAULT_HACKER_ID)["portfolio"])
		inventory.append_array(Content.deck(Content.DEFAULT_DECK_ID)["portfolio"])

	# TouchScroll, not ScrollContainer: these regions are wall-to-wall Buttons,
	# and a Button eats the one-finger drag that would otherwise scroll.
	var scroll := TouchScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UiTheme.px(6))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var active := _active_build()
	for slot in active.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTheme.px(4))

		# Each slot shows what it IS, not just its name: the binding it draws
		# charge from and the Function it will fire. Those two facts are the
		# whole basis for ordering the build, and a bare name hides both.
		var current := Content.program(active[slot])
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
		moves.add_child(_move_button(Graphics.pack().icon_arrow_up, slot, -1))
		moves.add_child(_move_button(Graphics.pack().icon_arrow_down, slot, 1))
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
			b.disabled = active.has(pid) and active[slot] != pid
			b.modulate = PacketStyle.TINT_NONE if active[slot] == pid else PacketStyle.TINT_INACTIVE
			var s := slot
			var p := str(pid)
			b.pressed.connect(func():
				_edit_replace(s, p)
				_show_build())
			swap_row.add_child(b)
		list.add_child(swap_row)

	if OS.is_debug_build():
		var seed_row := HBoxContainer.new()
		var seed_label := Label.new()
		seed_label.text = "seed"
		seed_row.add_child(seed_label)
		var seed_field := LineEdit.new()
		# EMPTY means "roll a fresh seed", and the placeholder shows what the
		# last battle actually used so it can be typed back in to reproduce it.
		# Pre-filling the field would re-pin that seed silently, which is the
		# F-002 behaviour being fixed.
		seed_field.text = ""
		seed_field.placeholder_text = "random (last: %d)" % _gameplay_seed
		seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Seed entry is the highest-leverage diagnostic: it makes a battle
		# observed on the phone reproducible in the headless harness.
		seed_field.text_changed.connect(func(t):
			_seed_override = int(t) if t.strip_edges() != "" else -1)
		seed_row.add_child(seed_field)
		_root.add_child(seed_row)

	if _run != null:
		_button("Begin battle %d" % _run.step, _start_run_battle)
		# Debug-only Force Win (D-029). It lives HERE, before the battle, rather
		# than on the defeat screen: the point is to reach a later battle
		# without playing the earlier ones, and a control that first requires
		# playing a battle to completion saves nothing. Deliberately minimal —
		# no RESTART_RUN, no availability matrix, no wizard log record.
		if OS.is_debug_build() and not _run.opponent_is_boss():
			_button("[debug] Skip battle %d" % _run.step, func():
				_run.confirm_build(_build_origin)
				_advance_run())
	else:
		_button("Begin", _start_battle)


## The build the Build screen is editing. A Run owns its own; Quick Match keeps
## the remembered constructed one, and the two are deliberately never shared.
func _active_build() -> Array:
	return _run.build if _run != null else _build


## Build edits go through the Run so the invariant — four DISTINCT inventory
## Programs — is enforced in one place, and so an edit marks the build as
## player-edited rather than leaving it looking carried-forward.
func _edit_replace(slot: int, program_id: String) -> void:
	if _run != null:
		if _run.replace_in_build(slot, program_id):
			_build_origin = Types.BuildOrigin.PLAYER_EDITED
	else:
		_build[slot] = program_id


func _edit_move(slot: int, delta: int) -> void:
	if _run != null:
		if _run.move_build_slot(slot, delta):
			_build_origin = Types.BuildOrigin.PLAYER_EDITED
	else:
		var dest := slot + delta
		var moved = _build[slot]
		_build[slot] = _build[dest]
		_build[dest] = moved


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


## The active Build slot's box.
##
## The amber left edge is now painted into the texture rather than faked with an
## asymmetric border. A `StyleBoxFlat` paints ONE border colour, so the accent
## had to be the whole frame at 1px with a 4px left; the texture can simply have
## an accent bar down its left and an ordinary edge elsewhere, which is what it
## always meant.
func _slot_box() -> StyleBoxTexture:
	return UiTheme.slot_box()


func _move_button(icon: Texture2D, slot: int, delta: int) -> Button:
	var b := Button.new()
	b.icon = icon
	b.expand_icon = true
	b.custom_minimum_size = Vector2(UiTheme.px(44), UiTheme.px(22))
	var dest := slot + delta
	b.disabled = dest < 0 or dest >= _active_build().size()
	if not b.disabled:
		b.pressed.connect(func():
			_edit_move(slot, delta)
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

## The gameplay seed for a NEWLY started battle: the pinned one if the tester
## typed a value, otherwise a fresh draw.
##
## Deliberately its own source, unrelated to setup RNG. Setup randomness picks
## identities; this picks the board, and §17 requires the two never to feed each
## other.
func _next_gameplay_seed() -> int:
	if _seed_override >= 0:
		return _seed_override
	return int(Session.make_setup_random()["seed"])


## Starts a CONSTRUCTED Quick Match from the build currently on the Build screen.
func _start_battle() -> void:
	_qm_build = _build.duplicate()
	_gameplay_seed = _next_gameplay_seed()
	_replay_battle()


## Replays the Quick Match in play — the same identities, the same build, and
## the same gameplay seed. Used by both result-screen exits, so neither can
## drift from what was actually played.
func _replay_battle() -> void:
	_enter_battle(
		Session.create_quick_match(_system_id, _host_id, _gameplay_seed, _qm_build, {}, true),
		"Quick Match",
	)


## A save written before accounting existed, or by a harness run that carried
## none, resumes without it rather than starting a fresh accumulator mid-battle
## — half a battle's figures presented as a whole battle's would be worse than
## none at all.
func _resume(state: GameState) -> void:
	_enter_battle(state, "Quick Match")


## `context` is what the pause menu will call this battle.
##
## Passed in by each entry point rather than inferred from `_run`, because
## inference is how AN-008 happened in the first place: a value that was correct
## when it was written, with nothing downstream that would notice when it
## stopped being. Four callers, four explicit answers, and a new fifth caller
## cannot forget — the parameter has no default.
func _enter_battle(state: GameState, context: String) -> void:
	if _shell != null:
		_shell.queue_free()
		_shell = null
		_panel = null
		_root = null

	_finished_state = state

	var screen := BattleScreen.new()
	screen.context_line = context
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
	if _finished_state != null:
		LogStore.flush_battle(_finished_state, _finished_state.metrics, _finished_state.log)

	if _run != null:
		# A Run OUTLIVES its battles. The save is rewritten without the battle
		# record rather than cleared, so quitting from the result screen still
		# comes back to a Run in progress.
		var won := winner == Types.Side.PLAYER
		SessionLog.run_result(_run, won, "ADVANCE" if won else "RETRY")
		if won:
			_run.phase = Types.SessionPhase.PENDING_BUILD
		else:
			_run.retry_battle()
		SessionSave.write(SessionSave.run_to_dict(_run, null))
		_show_run_result(winner)
		return

	# A concluded Quick Match is not resumable, so its save is cleared rather
	# than left to offer a Continue that would restore a finished battle.
	SessionSave.clear()
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
	_button("Replay this seed", _replay_battle)
	_button("New battle", func():
		# A new battle means a new board. With a seed pinned, step it so the
		# tester still walks a reproducible sequence instead of replaying one
		# board forever.
		if _seed_override >= 0:
			_seed_override += 1
		_gameplay_seed = _next_gameplay_seed()
		_replay_battle())
	_button("Back to title", func(): _show_title(Content.fingerprint()))

	_divider()

	var stamp := Label.new()
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stamp.add_theme_color_override("font_color", PacketStyle.TEXT_FAINT)
	stamp.text = "seed %d · content %s" % [_gameplay_seed, Content.fingerprint()]
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
	var scroll := TouchScroll.new()
	scroll.custom_minimum_size.y = UiTheme.px(150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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


# ---------------------------------------------------------------------------
# Run setup and progression (beta 0.2)
# ---------------------------------------------------------------------------
#
# The order is fixed: New Run -> Boss -> Hacker -> Deck -> Path -> Build ->
# Battle, then Path -> Build -> Battle for each battle after the first.
#
# Every screen below persists at its COMMITMENT, not on arrival. A highlighted
# card is never Run state — the select-then-confirm split `_show_chooser`
# already provides is exactly the line between "looking at" and "chose".


## What Continue offers, phrased so a stale save is recognisable before it is
## resumed rather than after.
func _continue_label(saved: Dictionary) -> String:
	match str(saved["mode"]):
		"RUN_SETUP":
			var s: RunSetup = saved["setup"]
			return "Continue Run — %s setup" % Content.boss(s.boss_id)["name"]
		"RUN":
			var r: Run = saved["run"]
			if r.is_pending_boss_battle():
				return "Continue Run — Boss route ready"
			return "Continue Run — battle %d of %d" % [r.step, Run.RUN_LENGTH]
		_:
			return "Continue — turn %d" % (saved["state"] as GameState).turn


func _resume_session(saved: Dictionary) -> void:
	match str(saved["mode"]):
		"RUN_SETUP":
			_setup = saved["setup"]
			_run = null
			# Resume lands on the screen AFTER the last commitment, which is
			# exactly what the persisted setup step records.
			if _setup.step == Types.SetupStep.HACKER:
				_show_hacker_select()
			else:
				_show_deck_select()
		"RUN":
			_setup = null
			_run = saved["run"]
			if saved["state"] != null:
				_enter_battle(saved["state"], _run_battle_context())
			else:
				_resume_run_screen()
		_:
			_setup = null
			_run = null
			_resume(saved["state"])


## Where a committed Run with no battle in progress belongs.
func _resume_run_screen() -> void:
	match _run.phase:
		Types.SessionPhase.PENDING_PATH:
			_show_path_choice()
		Types.SessionPhase.PENDING_BOSS_BATTLE:
			# A beta 0.2 save parked at the old stop point. Beta 0.3 consumes it
			# rather than dead-ending: the committed package is already complete,
			# so the Run resumes at the pre-battle Build for Battle 4.
			_build_origin = _run.build_origin
			_show_build()
		Types.SessionPhase.RUN_COMPLETE:
			_show_run_complete()
		_:
			_build_origin = _run.build_origin
			_show_build()


# ---- setup ----

## Boss Selection. The DESTRUCTIVE New-Run boundary: confirming here replaces
## any existing save, so it is the one selection that discards prior progress.
func _show_boss_select() -> void:
	var options: Array = []
	for b in Content.all_bosses():
		options.append({
			"id": str(b["id"]),
			"name": "%s [%s]" % [b["name"], b["id"]],
			"lines": [
				"ICE %d" % int(b["base_ice"]),
				"Strong: %s, %s" % [
					_token_list(b["strong_colors"], Vocab.COLOR_TOKENS),
					_token_list(b["strong_shapes"], Vocab.SHAPE_TOKENS),
				],
			],
		})

	var offered: Array = []
	for o in options:
		offered.append(o["id"])
	SessionLog.boss_offered(offered)

	var choose := func(id):
		# The route seed is drawn ONCE, here, so the whole Run's route
		# randomness comes from one persisted, gameplay-isolated stream.
		var seeded := Session.make_setup_random()
		var seed_value := int(seeded["seed"])
		_setup = RunSetup.commit_boss(str(id), Constants.default_settings(), seed_value)
		_run = null
		if _setup == null:
			return
		SessionLog.boss_selected(seed_value, str(id))
		SessionLog.run_created(seed_value, str(id))
		SessionSave.write(SessionSave.setup_to_dict(_setup))
		_show_hacker_select()

	_show_chooser(
		"SELECT BOSS",
		"The Run ends here. Chosen now, fought last.",
		options, choose, func(): _show_title(Content.fingerprint())
	)


func _show_hacker_select() -> void:
	var options: Array = []
	for id in Content.active()["hackers"]:
		var h := Content.hacker(id)
		options.append({
			"id": str(id),
			"name": "%s [%s]" % [h["name"], id],
			"lines": [
				"LINK %d" % int(h["base_link"]),
				"Strong: %s, %s" % [
					_token_list(h["strong_colors"], Vocab.COLOR_TOKENS),
					_token_list(h["strong_shapes"], Vocab.SHAPE_TOKENS),
				],
			],
		})

	var choose := func(id):
		var next := _setup.commit_hacker(str(id))
		if next == null:
			return
		_setup = next
		SessionLog.hacker_selected(_setup.route_seed, str(id))
		SessionSave.write(SessionSave.setup_to_dict(_setup))
		_show_deck_select()

	# No Back to Boss Selection: the Boss is committed and fixed for the Run.
	# Offering a way back that could not actually change it would be a lie.
	_show_chooser("SELECT HACKER", "Choose who runs this breach", options, choose)


func _show_deck_select() -> void:
	var options: Array = []
	for id in Content.active()["decks"]:
		var d := Content.deck(id)
		options.append({
			"id": str(id),
			"name": "%s [%s]" % [d["name"], id],
			"lines": [
				"+%d LINK" % int(d["add_link"]),
				"Function: %s" % str(d["fn"]["name"]),
			],
		})

	var choose := func(id):
		# Committing the Deck completes setup and generates the Battle 1 offers,
		# which persist immediately — they are state, not a screen.
		var r := _setup.commit_deck(str(id))
		if r == null:
			return
		_run = r
		_setup = null
		SessionLog.deck_selected(_run.route_seed, str(id), _run.inventory, _run.build)
		SessionLog.path_offered(_run)
		SessionSave.write(SessionSave.run_to_dict(_run, null))
		_show_path_choice()

	_show_chooser("SELECT DECK", "Choose the Deck you carry", options, choose)


# ---- path choice ----

## The Path Choice. Two complete encounter packages; taking one commits the
## opponent, the HOST, and the reward together.
func _show_path_choice() -> void:
	var pending := _run.pending_path
	var options: Array = []
	for o in pending.offers:
		var enemy := (
			Content.boss(o.opponent_id)
			if o.opponent_kind == Types.OpponentKind.BOS
			else Content.system(o.opponent_id)
		)
		var upgrade := Content.upgrade(o.upgrade_id)
		var host := Content.host(o.host_id)
		options.append({
			"id": str(o.index),
			"name": "%s%s" % [
				str(enemy["name"]),
				"  ·  BOSS" if o.opponent_kind == Types.OpponentKind.BOS else "",
			],
			"lines": [
				"ICE %d" % Run.resolve_run_ice(_run.settings, o.opponent_kind, o.opponent_id, pending.step),
				"HOST: %s — %s" % [str(host["name"]), _passive_summary(host)],
				"UPGRADE: %s — %s" % [str(upgrade["name"]), _passive_summary(upgrade)],
			],
		})

	var choose := func(id):
		if not _run.select_path(int(id)):
			return
		SessionLog.path_selected(_run, int(id))
		# The UPGRADE is acquired HERE, before Build, so it is active for the
		# battle it was offered alongside — including Battle 1.
		_build_origin = _run.opening_build_origin()
		SessionSave.write(SessionSave.run_to_dict(_run, null))
		_show_build()

	var exhausted := ""
	if pending.upgrade_exhausted:
		exhausted = "  ·  one UPGRADE remains, so both paths offer it"
	_show_chooser(
		"BATTLE %d OF %d" % [pending.step, Run.RUN_LENGTH],
		"Choose your route%s" % exhausted,
		options, choose
	)


## An identity's PASSIVEs in words, for a card. Falls back to the payload
## Function's name when a carrier has no authored display text.
func _passive_summary(row: Dictionary) -> String:
	var passives: Array = row.get("passives", [])
	if passives.is_empty():
		return "no PASSIVEs"
	var parts := PackedStringArray()
	for p in passives:
		var text := str(p["display"])
		if text == "":
			text = str(Content.function(str(p["function_id"]))["name"])
		parts.append(text)
	return ", ".join(parts)


# ---- run context, battle, result ----

## The Run's standing facts, shown above Build so the encounter being built
## against is never something the player has to remember from the last screen.
func _run_context_lines() -> PackedStringArray:
	var enemy := (
		Content.boss(_run.opponent_id)
		if _run.opponent_is_boss()
		else Content.system(_run.opponent_id)
	)
	var out := PackedStringArray()
	out.append("Battle %d of %d  ·  vs %s  ·  ICE %d" % [
		_run.step, Run.RUN_LENGTH, str(enemy["name"]), _run.encounter_ice(),
	])
	out.append("HOST %s  ·  LINK %d" % [str(Content.host(_run.host_id)["name"]), _run.hacker_max_link])
	if _run.upgrade_ids.is_empty():
		out.append("UPGRADEs: none yet")
	else:
		var names := PackedStringArray()
		for uid in _run.upgrade_ids:
			names.append(str(Content.upgrade(uid)["name"]))
		out.append("UPGRADEs: %s" % ", ".join(names))
	out.append("Boss: %s" % str(Content.boss(_run.boss_id)["name"]))
	return out


func _start_run_battle() -> void:
	_run.confirm_build(_build_origin)

	# F-002 applies to Run battles too. The alpha does not pass a seed to
	# `createRunBattle` either, so every Run battle draws a fresh board; beta
	# 0.1's fixed seed would otherwise have made all four battles of every Run
	# identical in a release build.
	_gameplay_seed = _next_gameplay_seed()
	var state := Session.create_run_battle(_run, _gameplay_seed)
	if state == null:
		return
	SessionLog.battle_started(_run, state.battle_id)
	_run.phase = Types.SessionPhase.ACTIVE_BATTLE
	SessionSave.write(SessionSave.run_to_dict(_run, state))
	_enter_battle(state, _run_battle_context())


## What a Run battle is, in one line, for the pause menu.
##
## Names the step and the opponent rather than the mode. "Run" would be accurate
## and useless; a paused player already knows they are in a Run and wants to
## know WHICH battle and against WHAT — the same two facts the Build screen
## leads with.
func _run_battle_context() -> String:
	if _run == null:
		return "Quick Match"
	var enemy := Content.opponent_of_identity({
		"opponent_kind": _run.opponent_kind, "opponent_id": _run.opponent_id,
	})
	var name := str(enemy.get("name", "?"))
	if _run.opponent_kind == Types.OpponentKind.BOS:
		return "Battle %d of %d · %s" % [_run.step, Run.RUN_LENGTH, name]
	return "Battle %d of %d · vs %s" % [_run.step, Run.RUN_LENGTH, name]


## §15.1 — the Run is over: ODANSHAY's ICE reached zero.
##
## The save is CLEARED here rather than kept. A finished Run is not resumable,
## and offering Continue on one would restore a Run with nothing left to do.
func _show_run_complete() -> void:
	if _content != null:
		_content.queue_free()
		_content = null

	var boss_name := str(Content.boss(_run.boss_id)["name"])
	_fresh_screen(true)
	_heading("RUN COMPLETE")
	_subheading("%s is breached." % boss_name)

	for line in _run_context_lines():
		var l := Label.new()
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", UiTheme.font_body())
		l.add_theme_color_override("font_color", PacketStyle.TEXT_DIM)
		_root.add_child(l)

	_divider()
	_button("Back to title", func():
		SessionSave.clear()
		_show_title(Content.fingerprint()))

	if _finished_state != null and _finished_state.metrics != null:
		_show_metrics(_finished_state)


## §12.1 — the beta 0.2 stop point.
##
## The Run holds a complete, committed Boss + HOST + UPGRADE package and is
## deliberately NOT marked complete: beta 0.3 picks this state up from disk.
func _show_pending_boss_battle() -> void:
	if _content != null:
		_content.queue_free()
		_content = null

	_fresh_screen(true)
	_heading("ROUTE COMMITTED")
	_subheading("Boss battle port continues in Beta 0.3")

	for line in _run_context_lines():
		var l := Label.new()
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", UiTheme.font_body())
		l.add_theme_color_override("font_color", PacketStyle.TEXT_DIM)
		_root.add_child(l)

	_divider()
	# The Run is PRESERVED, not ended. Returning to the title and continuing
	# comes straight back here.
	_button("Back to title", func(): _show_title(Content.fingerprint()))


## The result of a Run battle. Progression, retry, and abandonment live here; a
## Quick Match keeps its own result screen.
func _show_run_result(winner: int) -> void:
	if _content != null:
		_content.queue_free()
		_content = null

	var won := winner == Types.Side.PLAYER
	_fresh_screen(true)
	_heading("VICTORY" if won else "DEFEAT")
	# Name the opponent rather than saying "System" over a Boss (§16). The Run
	# context below already reads ODANSHAY; the headline saying otherwise was the
	# same assumption that broke the battle header.
	var enemy_name := str(Content.opponent_of_identity({
		"opponent_kind": _run.opponent_kind, "opponent_id": _run.opponent_id,
	})["name"])
	_subheading(
		"%s breached — battle %d of %d." % [enemy_name, _run.step, Run.RUN_LENGTH]
		if won else "Hacker LINK severed."
	)

	if won:
		_button(
			"Complete Run" if _run.step == Run.RUN_LENGTH else "Continue Run",
			_advance_run
		)
	else:
		# A retry is the SAME encounter with the SAME build — nothing rerolls
		# and no reward is granted twice.
		_button("Retry battle %d" % _run.step, func():
			_run.retry_battle()
			_build_origin = _run.opening_build_origin()
			SessionSave.write(SessionSave.run_to_dict(_run, null))
			_show_build())

	_button("Abandon Run", func():
		SessionLog.run_abandoned(_run)
		SessionSave.clear()
		_show_title(Content.fingerprint()))

	_divider()
	for line in _run_context_lines():
		var l := Label.new()
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", UiTheme.font_small())
		l.add_theme_color_override("font_color", PacketStyle.TEXT_FAINT)
		_root.add_child(l)

	if _finished_state != null and _finished_state.metrics != null:
		_show_metrics(_finished_state)


## Progress past a won battle. At the last step there is no next route — the Run
## has already committed its Boss package, and beating ODANSHAY ends the Run
## rather than advancing it.
func _advance_run() -> void:
	if _run.advance_after_victory():
		SessionLog.path_offered(_run)
		SessionSave.write(SessionSave.run_to_dict(_run, null))
		_show_path_choice()
		return

	# §15.1 — Boss down. Terminal: no fifth route, no further reward.
	_run.complete_run()
	SessionLog.run_completed(_run, _finished_state.turn if _finished_state != null else 0)
	SessionSave.write(SessionSave.run_to_dict(_run, null))
	_show_run_complete()


# ---- random quick match ----

## §14 — one isolated setup stream rolls the build, then the System, then the
## HOST, and the battle starts WITHOUT opening Build.
##
## It acquires no UPGRADEs, involves no Boss, and never writes to Constructed
## Quick Match's remembered build — which is why `_build` is left alone here.
func _start_random_quick_match() -> void:
	_run = null
	_setup = null
	var seeded := Session.make_setup_random()
	var rolled := Session.random_quick_match_setup(seeded["rng"])
	_system_id = str(rolled["system_id"])
	_host_id = str(rolled["host_id"])
	# The ROLLED build becomes the one in play; the gameplay seed is drawn
	# separately so setup and gameplay randomness stay independent (§17).
	_gameplay_seed = _next_gameplay_seed()
	SessionLog.quick_random_rolled(
		int(seeded["seed"]), _gameplay_seed, _system_id, _host_id, rolled["build"]
	)
	# `_build` — the remembered constructed build — is left untouched. Both
	# halves matter: replaying must use what was played, and a random match must
	# not overwrite the build the player assembled by hand.
	_qm_build = (rolled["build"] as Array).duplicate()
	_replay_battle()

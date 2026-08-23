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

var _root: VBoxContainer
var _content: Control

var _system_id := ""
var _host_id := ""
var _build: Array = []
var _seed := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

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

func _fresh_screen() -> VBoxContainer:
	if _root != null:
		_root.queue_free()
	_root = VBoxContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("separation", 10)
	_root.offset_left = 16
	_root.offset_top = 24
	_root.offset_right = -16
	_root.offset_bottom = -24
	add_child(_root)
	return _root


func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(l)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 48
	b.pressed.connect(action)
	_root.add_child(b)
	return b


func _show_title(fingerprint: String) -> void:
	_fresh_screen()
	_heading(TITLE)
	_heading("beta 0.1")

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(spacer)

	# Continue appears only for a save this build can actually restore. A save
	# from different content is rejected rather than offered and then failed.
	var saved := SaveState.read()
	if saved["ok"]:
		var s: GameState = saved["state"]
		_button("Continue — turn %d" % s.turn, func(): _resume(s))

	_button("Constructed Quick Match", _show_system_select)

	var stamp := Label.new()
	# The fingerprint on the title screen is deliberate: it identifies exactly
	# which content a device build is running, which is the first question worth
	# asking when a device behaves unlike the harness.
	stamp.text = "content %s" % fingerprint
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(stamp)


## Lists every valid loaded System with the facts a choice depends on. `in_pool`
## is deliberately ignored here — that flag governs random routing only, so a
## tester can always field a specific encounter.
func _show_system_select() -> void:
	_fresh_screen()
	_heading("Select System")

	for id in Content.active()["systems"]:
		var s := Content.system(id)
		var label := "%s   ICE %d\n%s / %s" % [
			s["name"], s["base_ice"],
			_token_list(s["strong_colors"], Vocab.COLOR_TOKENS),
			_token_list(s["strong_shapes"], Vocab.SHAPE_TOKENS),
		]
		var sid := str(id)
		var b := _button(label, func():
			_system_id = sid
			_show_host_select())
		b.custom_minimum_size.y = 64


func _show_host_select() -> void:
	_fresh_screen()
	_heading("Select HOST")

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
		var hid := str(id)
		var b := _button("%s\n%s" % [h["name"], effect], func():
			_host_id = hid
			_show_build())
		b.custom_minimum_size.y = 64


## The Build screen: four active Programs drawn from the six-Program inventory,
## in explicit order. That order is charge-routing priority, not decoration,
## which is why it is shown and editable rather than implied.
func _show_build() -> void:
	if _build.is_empty():
		_build = Session.default_build()
	_fresh_screen()
	_heading("Build — tap to swap in, order is charge priority")

	var inventory: Array = []
	inventory.append_array(Content.hacker(Content.DEFAULT_HACKER_ID)["portfolio"])
	inventory.append_array(Content.deck(Content.DEFAULT_DECK_ID)["portfolio"])

	for slot in _build.size():
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%d." % (slot + 1)
		row.add_child(lbl)

		for pid in inventory:
			var prog := Content.program(pid)
			var b := Button.new()
			b.text = str(prog["name"])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# A Program already elsewhere in the build cannot be added twice:
			# the build is four DISTINCT Programs.
			b.disabled = _build.has(pid) and _build[slot] != pid
			b.modulate = PacketStyle.TINT_NONE if _build[slot] == pid else PacketStyle.TINT_INACTIVE
			var s := slot
			var p := str(pid)
			b.pressed.connect(func():
				_build[s] = p
				_show_build())
			row.add_child(b)
		_root.add_child(row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(spacer)

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
	_enter_battle(Session.create_quick_match(_system_id, _host_id, _seed, _build))


func _resume(state: GameState) -> void:
	_enter_battle(state)


func _enter_battle(state: GameState) -> void:
	if _root != null:
		_root.queue_free()
		_root = null

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
	_show_result(winner)


func _show_result(winner: int) -> void:
	if _content != null:
		_content.queue_free()
		_content = null

	_fresh_screen()
	_heading("Hacker wins" if winner == Types.Side.PLAYER else "System wins")

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(spacer)

	# Same seed replays an identical battle — the only reliable way to
	# reproduce a visual bug, since a fresh seed means a fresh board.
	_button("Replay this seed", _start_battle)
	_button("New battle", func():
		_seed += 1
		_start_battle())
	_button("Back to title", func(): _show_title(Content.fingerprint()))

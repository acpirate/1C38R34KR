class_name BattleScreen
extends Control

## The battle screen: Datastream, ICE and LINK, Program rows, and event
## playback.
##
## Logic resolves a turn completely and synchronously; this plays the resulting
## event list back over time. The renderer never drives rules — it consumes an
## ordered list and animates it, which is what keeps the engine headlessly
## runnable and the two verifiable against each other.
##
## Playback is interruptible and skippable from the outset. Retrofitting a skip
## path is painful, and without one a human cannot test at speed.

signal battle_finished(winner: int)
signal quit_requested

const PLAYBACK_SPEEDS := [1.0, 2.0, 4.0, 0.25]

var state: GameState
var game: Game

var _stream: Datastream
var _hacker_box: AvatarBox
var _system_box: AvatarBox
var _turn_label: Label
var _message: Label
var _player_boxes: Array[UnitBox] = []
var _system_boxes: Array[UnitBox] = []
var _deck_box: UnitBox
var _speed_button: Button
var _pause_scrim: ColorRect
var _pause_panel: PanelContainer
var _log_overlay: RichTextLabel

var _playing := false
var _skip_requested := false
var _speed_index := 0
var _selected := Vector2i(-1, -1)

## Set when an activation is waiting for the player to pick a target. Cancelling
## must cost nothing: the charge has not been spent yet, because target validity
## is checked before payment.
var _pending_target := {}

var _recent_events: Array[String] = []

## The visible scrollback. Several narrative lines land per turn, so one label
## showing only the newest is worse than useless — it implies the last thing
## that happened was the only thing that happened.
var _messages: Array[String] = []


func setup(s: GameState) -> void:
	state = s
	game = Game.new(s)


func _ready() -> void:
	_build_ui()
	_refresh_all()
	if game != null:
		await _play(game.start_player_phase())


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = PacketStyle.BOARD_BACKGROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", UiTheme.px(6))
	add_child(root)
	_apply_safe_area(root)

	# --- header: both sides' standing, and the pause control between them ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiTheme.px(6))
	root.add_child(header)

	_hacker_box = AvatarBox.new()
	_hacker_box.title = "HACKER"
	_hacker_box.stat = "LINK"
	_hacker_box.bar_color = PacketStyle.LINK_BAR
	header.add_child(_hacker_box)

	var menu := Button.new()
	menu.text = "≡"
	menu.custom_minimum_size = Vector2(UiTheme.px(44), AvatarBox.height())
	menu.pressed.connect(_toggle_pause)
	header.add_child(menu)

	_system_box = AvatarBox.new()
	_system_box.title = "SYSTEM"
	_system_box.stat = "ICE"
	_system_box.bar_color = PacketStyle.ICE_BAR
	header.add_child(_system_box)

	# --- Program grid: the Hacker's build on the left, the System's on the
	# right, both visible at all times. Seeing the System's charge fill is what
	# turns a turn into a decision instead of a reaction; it is the single
	# biggest thing the alpha's battle screen gets right.
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", UiTheme.px(6))
	root.add_child(grid)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", UiTheme.px(4))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(left)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", UiTheme.px(4))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(right)

	for i in maxi(Content.ACTIVE_BUILD_SIZE, Content.SYSTEM_BUILD_SIZE):
		var mine := UnitBox.new()
		var idx := i
		mine.pressed.connect(func(): _on_program_pressed(idx))
		left.add_child(mine)
		_player_boxes.append(mine)

		var theirs := UnitBox.new()
		theirs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.add_child(theirs)
		_system_boxes.append(theirs)

	# The Deck Function sits under the Hacker's Programs and matches them: it is
	# a fifth control with its own pool, not a Program, and beta 0.1 does not yet
	# distinguish it further.
	_deck_box = UnitBox.new()
	_deck_box.pressed.connect(_on_deck_pressed)
	left.add_child(_deck_box)

	# --- board, square on any phone ---
	var frame := AspectRatioContainer.new()
	frame.ratio = 1.0
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(frame)

	_stream = Datastream.new()
	_stream.packet_pressed.connect(_on_packet_pressed)
	_stream.packet_dragged.connect(_on_packet_dragged)
	frame.add_child(_stream)

	_turn_label = Label.new()
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_font_size_override("font_size", UiTheme.font_small())
	_turn_label.add_theme_color_override("font_color", PacketStyle.TEXT_FAINT)
	root.add_child(_turn_label)

	# A short scrollback rather than one overwritten line. A turn produces
	# several narrative messages in quick succession, and with a single label
	# every one but the last is gone before it can be read — which makes the
	# playback useless for diagnosing what actually happened.
	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.y = UiTheme.px(64)
	_message.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_message.add_theme_font_size_override("font_size", UiTheme.font_body())
	_message.add_theme_color_override("font_color", PacketStyle.TEXT_STATUS)
	root.add_child(_message)

	root.add_child(_build_debug_bar())

	_log_overlay = RichTextLabel.new()
	_log_overlay.custom_minimum_size.y = UiTheme.px(60)
	_log_overlay.visible = false
	_log_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_log_overlay)

	_build_pause_panel()


## The pause menu, reached from the header's `≡`.
##
## Save and Quit lives in here rather than on the battle screen because it is
## only legal at a stable boundary — never mid-playback, when `GameState` is
## already ahead of the board the player can see — and a control that is
## disabled most of the time is better out of the main layout entirely.
func _build_pause_panel() -> void:
	# A scrim plus a centred panel, not a full-screen takeover: the board stays
	# visible behind it, so pausing reads as suspending the battle rather than
	# leaving it. The scrim also swallows taps meant for the panel and misses.
	_pause_scrim = ColorRect.new()
	_pause_scrim.color = PacketStyle.SCRIM
	_pause_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_scrim.visible = false
	add_child(_pause_scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_scrim.add_child(centre)

	_pause_panel = PanelContainer.new()
	_pause_panel.custom_minimum_size.x = UiTheme.px(250)

	var style := StyleBoxFlat.new()
	style.bg_color = PacketStyle.PANEL
	style.border_color = PacketStyle.PANEL_EDGE
	style.set_border_width_all(1)
	style.set_content_margin_all(UiTheme.px(16))
	_pause_panel.add_theme_stylebox_override("panel", style)
	centre.add_child(_pause_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.px(8))
	_pause_panel.add_child(box)

	var head := Label.new()
	head.text = "PAUSED"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", UiTheme.font_heading())
	head.add_theme_color_override("font_color", PacketStyle.TEXT_HEADING)
	box.add_child(head)

	var mode := Label.new()
	mode.text = "Quick Match"
	mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode.add_theme_font_size_override("font_size", UiTheme.font_subheading())
	mode.add_theme_color_override("font_color", PacketStyle.TEXT_DIM)
	box.add_child(mode)

	var resume := Button.new()
	resume.text = "Resume"
	resume.custom_minimum_size.y = UiTheme.control_height()
	resume.pressed.connect(_toggle_pause)
	box.add_child(resume)

	var save := Button.new()
	save.text = "Save and Quit"
	save.custom_minimum_size.y = UiTheme.control_height()
	save.pressed.connect(_on_save_and_quit)
	box.add_child(save)

	_divider(box)

	# The same reason the title screen carries the content fingerprint: a tester
	# looking at a screenshot should be able to say what rules produced it.
	var note := Label.new()
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", UiTheme.font_small())
	note.add_theme_color_override("font_color", PacketStyle.TEXT_FAINT)
	note.text = "seed %d · content %s" % [_battle_seed(), Content.fingerprint()]
	box.add_child(note)


func _divider(box: Control) -> void:
	var line := ColorRect.new()
	line.color = PacketStyle.PANEL_EDGE
	line.custom_minimum_size.y = maxi(1, UiTheme.px(1))
	box.add_child(line)


## Pausing is refused mid-playback for the same reason saving is: the board on
## screen is behind the state, so anything offered here would act on a position
## the player cannot see.
func _toggle_pause() -> void:
	if _playing:
		return
	_pause_scrim.visible = not _pause_scrim.visible


## The safe area keeps status text and controls clear of a display cutout and
## rounded corners. Queried rather than hardcoded, because a cutout is
## per-device.
func _apply_safe_area(root: Control) -> void:
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if screen.x <= 0 or screen.y <= 0:
		return
	var scale_x := size.x / float(screen.x)
	var scale_y := size.y / float(screen.y)
	root.offset_left = safe.position.x * scale_x + UiTheme.px(6)
	root.offset_top = safe.position.y * scale_y + UiTheme.px(6)
	root.offset_right = -((screen.x - safe.end.x) * scale_x + UiTheme.px(6))
	root.offset_bottom = -((screen.y - safe.end.y) * scale_y + UiTheme.px(6))


# ---------------------------------------------------------------------------
# Diagnostics (D-012) — debug builds only
# ---------------------------------------------------------------------------

func _build_debug_bar() -> Control:
	var bar := HBoxContainer.new()
	if not OS.is_debug_build():
		bar.visible = false
		return bar

	_speed_button = Button.new()
	_speed_button.pressed.connect(_cycle_speed)
	bar.add_child(_speed_button)
	_update_speed_button()

	# The highest-leverage diagnostic: it turns "something looked wrong on the
	# phone" into a seed that replays in the headless harness with a full trace.
	var seed_label := Label.new()
	seed_label.text = "  seed %d  " % _battle_seed()
	bar.add_child(seed_label)

	bar.add_child(_debug_button("charge", _grant_charge))
	bar.add_child(_debug_button("win", func(): _force_outcome(Types.Side.ENEMY)))
	bar.add_child(_debug_button("lose", func(): _force_outcome(Types.Side.PLAYER)))
	bar.add_child(_debug_button("log", func():
		_log_overlay.visible = not _log_overlay.visible))
	return bar


func _debug_button(label: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(action)
	return b


func _battle_seed() -> int:
	var parts := state.battle_id.split("-")
	return int(parts[parts.size() - 1]) if parts.size() > 0 else 0


func _cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % PLAYBACK_SPEEDS.size()
	_update_speed_button()


## GDScript's format operator has no `%g`, and using one raises
## "unsupported format character" at runtime rather than failing to compile —
## so the button silently never got a label.
func _update_speed_button() -> void:
	if _speed_button == null:
		return
	var speed: float = PLAYBACK_SPEEDS[_speed_index]
	_speed_button.text = ("%dx" % int(speed)) if speed >= 1.0 else ("%.2fx" % speed)


## Fills every Program pool. Function activation, targeting, cancel-without-
## spend, composites, and fizzles are the densest cluster of rules in the game
## and are otherwise unreachable until charge accumulates.
func _grant_charge() -> void:
	for u in (state.units[Types.Side.PLAYER] as Array):
		u.charge = int(Content.program(u.program_id)["charge_cap"])
	state.deck_charge = Resolve.deck_charge_cap(state)
	_refresh_programs()


## Ends the battle through `Game.force_outcome`, which deals lethal damage down
## the ordinary path and through the ordinary event funnel. The renderer does
## not reach into `Resolve` itself — doing so is what let this shortcut skip
## metrics and report a battle with zero damage in it.
func _force_outcome(loser: Types.Side) -> void:
	if _playing or state.has_winner():
		return
	_play(game.force_outcome(loser))


# ---------------------------------------------------------------------------
# Event playback
# ---------------------------------------------------------------------------

## Consumes the logic layer's ordered events.
##
## `GameState` is already final before playback begins, so a skip is always safe
## — it simply stops animating and snaps to the settled board.
func _play(events: Array) -> void:
	if events.is_empty():
		_refresh_all()
		return

	_playing = true
	_skip_requested = false

	for ev in events:
		_note(ev)
		if _skip_requested:
			continue
		await _play_one(ev)

	_playing = false
	_refresh_all()

	if state.has_winner():
		battle_finished.emit(state.winner)


func _play_one(ev: Dictionary) -> void:
	var t := StringName(ev["t"])
	var speed: float = PLAYBACK_SPEEDS[_speed_index]

	match t:
		# The swap is the player's own input echoed back — the one moment they
		# most need to see. Animated as an actual slide rather than a board
		# rebuild, because an instant change reads as "something happened"
		# rather than as "the move I made happened". A revert slides too: that
		# the Packets went and came back is exactly the feedback an illegal
		# swap owes the player.
		Types.EVT.SWAP, Types.EVT.REVERT:
			await _animate(_stream.slide(ev["a"], ev["b"], 0.20 / speed), 0.20 / speed)

		Types.EVT.DESTROY:
			for c in (ev["cells"] as Array):
				var p := _stream.at(c)
				if p != null:
					p.modulate = PacketStyle.TINT_DESTROYED
			await _pause(0.20 / speed)
			for c in (ev["cells"] as Array):
				var p := _stream.at(c)
				if p != null:
					p.view = {}
					p.modulate = PacketStyle.TINT_NONE

		Types.EVT.FALL:
			await _animate(_stream.fall(ev["moves"], 0.16 / speed), 0.26 / speed)

		# The base is lower than it looks because `spawn` now scales it by the
		# depth of the refill — a single Packet dropping in takes 0.13, a full
		# eight-cell column about 0.37.
		Types.EVT.SPAWN:
			await _animate(_stream.spawn(ev["tiles"], 0.13 / speed), 0.22 / speed)

		# A wholesale replacement — reshuffle or Shake. There is no motion to
		# describe, so it snaps and holds long enough to be noticed.
		Types.EVT.BOARD:
			_refresh_board()
			await _pause(0.22 / speed)

		# One event per Packet, so each conversion gets its OWN beat and a
		# flash. A Transform changes several Packets at once and the logic layer
		# emits them individually; playing them as a single board refresh threw
		# that away and made a three-Packet GREENING look like one instant edit.
		Types.EVT.SET_TILE:
			var cell: Vector2i = ev["p"]
			var view := _stream.at(cell)
			if view != null:
				view.modulate = PacketStyle.TINT_BLAST
				await _pause(0.10 / speed)
				_stream.set_cell(cell, ev["view"])
				await _pause(0.16 / speed)
				view.modulate = PacketStyle.TINT_NONE
			else:
				_refresh_board()
				await _pause(0.16 / speed)
		Types.EVT.DETONATE:
			for c in (ev["cells"] as Array):
				var p := _stream.at(c)
				if p != null:
					p.modulate = PacketStyle.TINT_BLAST
			await _pause(0.34 / speed)
			for c in (ev["cells"] as Array):
				var p := _stream.at(c)
				if p != null:
					p.modulate = PacketStyle.TINT_NONE

		# Narrative events. These previously had NO dwell, which is why a turn
		# appeared to resolve instantly: the board moved, but nothing said what
		# had acted or why.
		Types.EVT.ABILITY:
			# The header for an activation. Kept even where a later message
			# repeats the name, because it is the only event that fires for
			# EVERY activation — several Effects emit no message at all.
			_log("%s fires %s" % [_who(ev.get("side", 0)), ev.get("name", "?")])
			_refresh_programs()
			# WHICH control fired, shown on the control itself. A Function whose
			# Effect touches no Packet — a Drain, a Buff — otherwise produced no
			# visible change anywhere, so firing it looked like nothing at all
			# happened. The board is not the only thing that needs to animate.
			_flash_unit(ev)
			await _pause(0.40 / speed)
		# TRANSFORM, PLACED, and COUNTDOWN_DELIVERED get dwell but no line of
		# their own: the logic layer already emits a player-facing message for
		# each, and narrating them twice pushes the rest of the turn out of a
		# four-line log.
		Types.EVT.TRANSFORM:
			await _pause(0.30 / speed)
		Types.EVT.PLACED:
			await _pause(0.20 / speed)
		Types.EVT.COUNTDOWN:
			_refresh_board()
			await _pause(0.24 / speed)
		Types.EVT.COUNTDOWN_DELIVERED:
			await _pause(0.30 / speed)
		Types.EVT.SHAKE:
			await _pause(0.24 / speed)
		Types.EVT.LINE_CLEAR:
			_log("  line clear")
			await _pause(0.24 / speed)
		Types.EVT.WITHHOLD:
			# Worth surfacing: a ready Program that declines to act looks
			# identical to one that is not charged unless it says so.
			_log("  %s withheld — %s" % [ev.get("program_id", "?"), ev.get("reason", "")])
			await _pause(0.30 / speed)
		Types.EVT.OP:
			if not ev.get("resolved", true):
				_log("  fizzled")
				await _pause(0.24 / speed)

		Types.EVT.DAMAGE:
			_refresh_bars()
			_float_damage(int(ev.get("target", 0)), int(ev.get("amount", 0)))
			_log("  %d damage to %s" % [int(ev.get("amount", 0)), _who(ev.get("target", 0))])
			await _pause(0.24 / speed)
		Types.EVT.SHIELD:
			_refresh_bars()
			_log("  shield absorbed %d" % int(ev.get("prevented", 0)))
			await _pause(0.24 / speed)
		Types.EVT.MSG:
			_log(str(ev["text"]))
			await _pause(0.42 / speed)
		Types.EVT.AUTO_RESHUFFLE:
			_refresh_board()
			await _pause(0.45 / speed)
		Types.EVT.OVER:
			_refresh_all()
			_log("Hacker wins" if ev["winner"] == Types.Side.PLAYER else "System wins")
		_:
			pass


func _who(side) -> String:
	return "Hacker" if int(side) == Types.Side.PLAYER else "System"


## Pulses the control that just fired.
##
## Found by matching the event's stable Program ID against the side's roster
## rather than by slot index, because a PASSIVE-caused activation carries the
## PASSIVE's ID and belongs to no slot at all — in that case nothing flashes,
## which is correct: no control fired.
func _flash_unit(ev: Dictionary) -> void:
	var boxes := _player_boxes if int(ev.get("side", 0)) == Types.Side.PLAYER else _system_boxes
	var target: UnitBox = null

	if int(ev.get("owner_kind", Types.OwnerKind.PROGRAM)) == Types.OwnerKind.DECK:
		target = _deck_box
	else:
		var units: Array = state.units[int(ev.get("side", 0))]
		var program_id := str(ev.get("program_id", ""))
		for i in mini(units.size(), boxes.size()):
			if units[i].program_id == program_id:
				target = boxes[i]
				break

	if target == null:
		return
	target.modulate = PacketStyle.TINT_BLAST
	var tween := create_tween()
	tween.tween_property(target, "modulate", PacketStyle.TINT_NONE, 0.35)


## A `-N` that rises off the struck side's box and fades.
##
## Worth the twelve lines: a cascade lands several damage events in under a
## second, and a bar that just shrinks says nothing about how many hits it took
## or how big each was. The scrollback records them, but the floater is what
## makes the sequence legible while it happens.
func _float_damage(target_side: int, amount: int) -> void:
	if amount <= 0:
		return
	var anchor: Control = _hacker_box if target_side == Types.Side.PLAYER else _system_box
	var tag := Label.new()
	tag.text = "-%d" % amount
	tag.add_theme_color_override("font_color", PacketStyle.DAMAGE)
	tag.add_theme_font_size_override("font_size", UiTheme.px(26))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.position = anchor.global_position + Vector2(anchor.size.x * 0.5, anchor.size.y * 0.5)
	add_child(tag)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(tag, "position:y", tag.position.y - UiTheme.px(34), 0.6)
	tween.tween_property(tag, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(tag.queue_free)


## Appends to the visible scrollback, keeping the most recent few lines.
func _log(line: String) -> void:
	_messages.append(line)
	while _messages.size() > 4:
		_messages.pop_front()
	_message.text = "\n".join(_messages)


func _pause(seconds: float) -> void:
	await get_tree().create_timer(maxf(0.01, seconds)).timeout


## Awaits a motion tween, falling back to a plain dwell when there was nothing
## to animate.
##
## The fallback matters: `slide`, `fall`, and `spawn` all return null for an
## empty or impossible move, and awaiting a null tween would drop the beat
## entirely — which is the same instant-board-change problem the animation was
## added to fix, just in a rarer case.
func _animate(tween: Tween, fallback: float) -> void:
	if tween == null:
		await _pause(fallback)
		return
	await tween.finished
	# Positions are authoritative again the moment the tween ends. Snapping here
	# rather than trusting the tween's final frame means a skip mid-flight
	# cannot leave a Packet parked between cells.
	_stream.settle()


## An on-screen tail of recent events. Diagnoses most playback and ordering
## problems without a cable.
func _note(ev: Dictionary) -> void:
	if not OS.is_debug_build():
		return
	_recent_events.append(str(ev["t"]))
	while _recent_events.size() > 20:
		_recent_events.pop_front()
	if _log_overlay != null and _log_overlay.visible:
		_log_overlay.text = " → ".join(_recent_events)


func skip() -> void:
	_skip_requested = true


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_board()
	_refresh_bars()
	_refresh_programs()
	_turn_label.text = "Turn %d" % state.turn


func _refresh_board() -> void:
	_stream.set_grid(Resolve._grid_view(state.board))
	_stream.set_selected(_selected)


func _refresh_bars() -> void:
	_hacker_box.set_stat(state.hp[Types.Side.PLAYER], state.config["player_hp"])
	_hacker_box.set_totals(
		Resolve.shield_value(state, Types.Side.PLAYER),
		Resolve.buff_bonus(state, Types.Side.PLAYER),
	)
	_system_box.title = str(Content.system(state.identity["opponent_id"])["name"])
	_system_box.set_stat(state.hp[Types.Side.ENEMY], state.config["enemy_hp"])
	_system_box.set_totals(
		Resolve.shield_value(state, Types.Side.ENEMY),
		Resolve.buff_bonus(state, Types.Side.ENEMY),
	)


func _refresh_programs() -> void:
	var interactive := not _playing and not state.has_winner()
	var targeting := not _pending_target.is_empty()

	_fill_side(_player_boxes, Types.Side.PLAYER, interactive, targeting)
	_fill_side(_system_boxes, Types.Side.ENEMY, false, false)

	var deck := Content.deck(state.identity["deck_id"])
	var deck_cost := int(deck["fn"]["cost"])
	_deck_box.label = str(deck["name"])
	_deck_box.charge = state.deck_charge
	_deck_box.cost = deck_cost
	_deck_box.actionable = interactive and state.deck_charge >= deck_cost
	var deck_armed := targeting and str(_pending_target["source"].get("kind", "")) == "deck"
	_deck_box.armed = deck_armed
	_deck_box.dimmed = targeting and not deck_armed


## The Deck control carries no binding swatch: its charge comes from neutral
## Packets, which by definition have neither a colour nor a shape to show.
func _fill_side(boxes: Array[UnitBox], side: Types.Side, interactive: bool, targeting: bool) -> void:
	var units: Array = state.units[side]
	for i in boxes.size():
		var box := boxes[i]
		if i >= units.size():
			box.visible = false
			continue
		box.visible = true
		var u: GameState.UnitState = units[i]
		var prog := Content.program(u.program_id)
		box.label = str(prog["name"])
		box.charge = u.charge
		box.cost = int(prog["cost"])
		box.set_binding(_first_or(prog["colors"]), _first_or(prog["shapes"]))
		box.actionable = interactive and u.charge >= int(prog["cost"])
		var armed := targeting \
			and str(_pending_target["source"].get("kind", "")) == "program" \
			and int(_pending_target["source"].get("idx", -1)) == i
		box.armed = armed
		box.dimmed = targeting and not armed


## A Program may be bound to several Packet identities; the swatch shows the
## first, which is enough to make the charge relationship visible without
## turning a 44px box into a legend.
func _first_or(values: Array) -> int:
	return int(values[0]) if values.size() > 0 else -1


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## Writes the save and leaves. Refused mid-playback: `GameState` is already
## final while events are still animating, so saving then would persist a
## position ahead of what the player can see — and cancel any targeting, whose
## charge has not been spent.
func _on_save_and_quit() -> void:
	if _playing or state.has_winner():
		return
	_cancel_targeting()
	if SaveState.write(state):
		quit_requested.emit()
	else:
		_log("Save failed")


func _on_program_pressed(idx: int) -> void:
	if _playing or state.has_winner():
		return
	var u: GameState.UnitState = state.units[Types.Side.PLAYER][idx]
	var fn: Dictionary = Content.program(u.program_id)["fn"]
	_begin_activation({"kind": "program", "idx": idx}, fn)


func _on_deck_pressed() -> void:
	if _playing or state.has_winner():
		return
	_begin_activation({"kind": "deck"}, Content.deck(state.identity["deck_id"])["fn"])


## An untargeted Function fires immediately. A targeted one enters targeting
## mode and waits; tapping the armed control again cancels without spending
## charge, because nothing has been paid yet.
func _begin_activation(source: Dictionary, fn: Dictionary) -> void:
	if not _pending_target.is_empty() and _pending_target["source"] == source:
		_cancel_targeting()
		return

	var need := Game._function_target_kind(fn)
	if need == Types.TargetKind.NONE:
		_fire(source, null)
		return

	if need == Types.TargetKind.UNIT:
		# Beta 0.1 has no enemy-slot picker, so Drain targets the fullest slot.
		# A deliberate whitebox simplification, not a rules decision.
		_fire(source, {"kind": Types.TargetKind.UNIT, "idx": _fullest_enemy_slot()})
		return

	_pending_target = {"source": source}
	_log("Choose a Packet — tap the Function again to cancel")
	_stream.set_targeting(state.occupied_cells())
	# Redrawn so the armed control lights and every other one recedes: "what can
	# I tap right now?" is answered by the layout, with no extra text.
	_refresh_programs()


func _cancel_targeting() -> void:
	if _pending_target.is_empty():
		return
	_pending_target = {}
	_stream.clear_targeting()
	_log("Targeting cancelled")
	_refresh_programs()


func _fullest_enemy_slot() -> int:
	var enemy: Array = state.units[Types.Side.ENEMY]
	var best := 0
	for i in enemy.size():
		if enemy[i].charge > enemy[best].charge:
			best = i
	return best


func _fire(source: Dictionary, target) -> void:
	_pending_target = {}
	_stream.clear_targeting()
	var events: Array = []
	if source["kind"] == "deck":
		events = game.fire_deck_function(target)
	else:
		events = game.fire_program(int(source["idx"]), target)
	await _play(events)


func _on_packet_pressed(cell: Vector2i) -> void:
	if _playing or state.has_winner():
		return

	if not _pending_target.is_empty():
		_fire(_pending_target["source"], {"kind": Types.TargetKind.PACKET, "p": cell})
		return

	if _selected.x < 0:
		_selected = cell
		_stream.set_selected(cell)
		return

	if _selected == cell:
		_selected = Vector2i(-1, -1)
		_stream.set_selected(_selected)
		return

	if absi(_selected.x - cell.x) + absi(_selected.y - cell.y) == 1:
		var from := _selected
		_selected = Vector2i(-1, -1)
		_stream.set_selected(_selected)
		await _commit_swap(from, cell)
		return

	# A non-adjacent tap MOVES the selection rather than failing — the player
	# almost certainly meant to pick a different Packet.
	_selected = cell
	_stream.set_selected(cell)


func _on_packet_dragged(from_cell: Vector2i, to_cell: Vector2i) -> void:
	if _playing or state.has_winner() or not _pending_target.is_empty():
		return
	_selected = Vector2i(-1, -1)
	_stream.set_selected(_selected)
	await _commit_swap(from_cell, to_cell)


## An invalid swap animates, reverts, and does NOT consume the turn — the logic
## layer emits the revert, so the renderer only has to play it.
func _commit_swap(a: Vector2i, b: Vector2i) -> void:
	var result := game.attempt_swap(a, b)
	await _play(result["events"])
	if not result["matched"]:
		return
	if state.has_winner():
		return
	await _play(game.run_enemy_phase())
	if state.has_winner():
		return
	await _play(game.start_player_phase())

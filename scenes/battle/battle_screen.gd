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

const PLAYBACK_SPEEDS := [1.0, 2.0, 4.0, 0.25]

var state: GameState
var game: Game

var _stream: Datastream
var _ice_bar: ProgressBar
var _link_bar: ProgressBar
var _ice_label: Label
var _link_label: Label
var _turn_label: Label
var _message: Label
var _program_rows: VBoxContainer
var _deck_button: Button
var _speed_button: Button
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
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	_apply_safe_area(root)

	# --- enemy ---
	_ice_label = Label.new()
	_ice_bar = ProgressBar.new()
	_ice_bar.custom_minimum_size.y = 18
	_ice_bar.show_percentage = false
	root.add_child(_ice_label)
	root.add_child(_ice_bar)

	_turn_label = Label.new()
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_turn_label)

	# --- board, square on any phone ---
	var frame := AspectRatioContainer.new()
	frame.ratio = 1.0
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(frame)

	_stream = Datastream.new()
	_stream.packet_pressed.connect(_on_packet_pressed)
	_stream.packet_dragged.connect(_on_packet_dragged)
	frame.add_child(_stream)

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.y = 34
	root.add_child(_message)

	# --- player ---
	_program_rows = VBoxContainer.new()
	_program_rows.add_theme_constant_override("separation", 4)
	root.add_child(_program_rows)

	_deck_button = Button.new()
	_deck_button.pressed.connect(_on_deck_pressed)
	root.add_child(_deck_button)

	_link_bar = ProgressBar.new()
	_link_bar.custom_minimum_size.y = 18
	_link_bar.show_percentage = false
	_link_label = Label.new()
	root.add_child(_link_bar)
	root.add_child(_link_label)

	root.add_child(_build_debug_bar())

	_log_overlay = RichTextLabel.new()
	_log_overlay.custom_minimum_size.y = 90
	_log_overlay.visible = false
	_log_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_log_overlay)


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
	root.offset_left = safe.position.x * scale_x + 8
	root.offset_top = safe.position.y * scale_y + 8
	root.offset_right = -((screen.x - safe.end.x) * scale_x + 8)
	root.offset_bottom = -((screen.y - safe.end.y) * scale_y + 8)


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


## Ends the battle by dealing lethal damage through the ordinary damage path,
## rather than setting the winner directly. A diagnostic that reaches behind the
## rules eventually produces a bug report about the rules.
func _force_outcome(loser: Types.Side) -> void:
	if _playing or state.has_winner():
		return
	var events: Array = []
	Resolve.deal_damage(state, loser, state.hp[loser] + 9999, {
		"source": Types.DamageSource.ATTACKER, "label": "debug",
	}, events)
	_play(events)


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
		Types.EVT.SWAP, Types.EVT.REVERT:
			_refresh_board()
			await _pause(0.12 / speed)
		Types.EVT.DESTROY:
			for c in (ev["cells"] as Array):
				var p := _stream.at(c)
				if p != null:
					p.modulate = PacketStyle.TINT_DESTROYED
			await _pause(0.14 / speed)
			_refresh_board()
			for c in (ev["cells"] as Array):
				var p := _stream.at(c)
				if p != null:
					p.modulate = PacketStyle.TINT_NONE
		Types.EVT.FALL, Types.EVT.SPAWN, Types.EVT.SET_TILE, Types.EVT.BOARD:
			_refresh_board()
			await _pause(0.08 / speed)
		Types.EVT.DETONATE:
			for c in (ev["cells"] as Array):
				var p := _stream.at(c)
				if p != null:
					p.modulate = PacketStyle.TINT_BLAST
			await _pause(0.18 / speed)
			for c in (ev["cells"] as Array):
				var p := _stream.at(c)
				if p != null:
					p.modulate = PacketStyle.TINT_NONE
		Types.EVT.DAMAGE, Types.EVT.SHIELD:
			_refresh_bars()
			await _pause(0.10 / speed)
		Types.EVT.MSG:
			_message.text = str(ev["text"])
			await _pause(0.12 / speed)
		Types.EVT.OVER:
			_refresh_all()
			_message.text = "Hacker wins" if ev["winner"] == Types.Side.PLAYER else "System wins"
		_:
			pass


func _pause(seconds: float) -> void:
	await get_tree().create_timer(maxf(0.01, seconds)).timeout


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
	var link_max: int = state.config["player_hp"]
	var ice_max: int = state.config["enemy_hp"]
	_link_bar.max_value = link_max
	_link_bar.value = maxi(0, state.hp[Types.Side.PLAYER])
	_ice_bar.max_value = ice_max
	_ice_bar.value = maxi(0, state.hp[Types.Side.ENEMY])

	var shield_p := Resolve.shield_value(state, Types.Side.PLAYER)
	var shield_e := Resolve.shield_value(state, Types.Side.ENEMY)
	_link_label.text = "LINK %d / %d%s" % [maxi(0, state.hp[Types.Side.PLAYER]), link_max, ("   shield %d" % shield_p) if shield_p > 0 else ""]
	_ice_label.text = "%s   ICE %d / %d%s" % [
		Content.system(state.identity["opponent_id"])["name"],
		maxi(0, state.hp[Types.Side.ENEMY]), ice_max,
		("   shield %d" % shield_e) if shield_e > 0 else "",
	]


func _refresh_programs() -> void:
	for child in _program_rows.get_children():
		child.queue_free()

	var units: Array = state.units[Types.Side.PLAYER]
	for i in units.size():
		var u: GameState.UnitState = units[i]
		var prog := Content.program(u.program_id)
		var cost := int(prog["cost"])
		var ready := u.charge >= cost

		var row := HBoxContainer.new()
		var b := Button.new()
		b.text = "%s  %d/%d" % [prog["name"], u.charge, cost]
		b.disabled = not ready or _playing or state.has_winner()
		var idx := i
		b.pressed.connect(func(): _on_program_pressed(idx))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		_program_rows.add_child(row)

	var deck := Content.deck(state.identity["deck_id"])
	var deck_cost := int(deck["fn"]["cost"])
	_deck_button.text = "%s  %d/%d" % [deck["name"], state.deck_charge, deck_cost]
	_deck_button.disabled = state.deck_charge < deck_cost or _playing or state.has_winner()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

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
	_message.text = "Choose a Packet — tap the Function again to cancel"
	_stream.set_targeting(state.occupied_cells())


func _cancel_targeting() -> void:
	_pending_target = {}
	_stream.clear_targeting()
	_message.text = "Targeting cancelled"


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

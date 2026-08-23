class_name TouchScroll
extends ScrollContainer

## A ScrollContainer that can be scrolled with two fingers anywhere inside it.
##
## ## Why this exists
##
## Godot's built-in touch drag-scroll only works where the gesture reaches the
## ScrollContainer. On the Build screen almost every pixel is a Button, and a
## Button consumes the touch — so a one-finger drag presses controls instead of
## scrolling, and the only way to scroll is to find a sliver of background or to
## hit the scrollbar itself. That is a puzzle, not an interface.
##
## Widening the scrollbar helps and is done too (see `UiTheme`), but it is still
## a small target at the edge of a phone held one-handed. **Two fingers anywhere
## inside the region scrolls it**, whatever is underneath.
##
## ## How it bypasses the controls
##
## `_input` runs BEFORE the viewport hands events to `_gui_input`, so this sees
## a touch before the Button under it does. Once two fingers are down it marks
## every subsequent touch event handled, and the controls underneath never see
## them.
##
## The first finger's press has already reached a Button by the time the second
## arrives, so that Button is sitting latched. `_release_controls` walks the
## subtree and clears it — otherwise the control stays visually pressed for the
## whole gesture, and on release fires the action the player was trying to
## scroll past.

## Fingers required. Two, because one is the press gesture and three is awkward
## on a phone held in one hand.
const FINGERS := 2

## Touch index -> current position, for every finger currently down INSIDE this
## region. Fingers that land outside are ignored, so a two-finger gesture
## spanning two scroll regions does not drive both.
var _touches := {}

var _scrolling := false
var _last_centre := Vector2.ZERO


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if not _contains(event.position):
			return
		_touches[event.index] = event.position
		if _touches.size() >= FINGERS and not _scrolling:
			_begin()
			get_viewport().set_input_as_handled()
		return

	# A finger lifting during a scroll gesture must be swallowed too, or the
	# control underneath receives a release it never got a press for.
	if _scrolling:
		get_viewport().set_input_as_handled()
	_touches.erase(event.index)
	if _touches.size() < FINGERS:
		_scrolling = false


func _on_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if not _scrolling:
		return

	var centre := _centre()
	# Scrolling is the inverse of the finger movement: the content follows the
	# fingers, so dragging down reveals what is above.
	scroll_vertical -= int(centre.y - _last_centre.y)
	_last_centre = centre
	get_viewport().set_input_as_handled()


func _begin() -> void:
	_scrolling = true
	_last_centre = _centre()
	_release_controls(self)


## The average of the fingers down, so the gesture does not jump when one finger
## moves more than the other.
func _centre() -> Vector2:
	var sum := Vector2.ZERO
	for index in _touches:
		sum += _touches[index]
	return sum / float(_touches.size())


func _contains(global_point: Vector2) -> bool:
	return Rect2(global_position, size).has_point(global_point)


## Clears any button the first finger already latched.
##
## `BaseButton` fires on RELEASE, and this gesture swallows the release — so
## without this the control would stay drawn as pressed for the whole scroll and
## then, on the next real tap anywhere, look like it had been activated.
func _release_controls(node: Node) -> void:
	for child in node.get_children():
		if child is BaseButton:
			(child as BaseButton).button_pressed = false
		elif child is UnitBox:
			(child as UnitBox).release()
		_release_controls(child)

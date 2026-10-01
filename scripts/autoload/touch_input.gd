extends Node
## TouchInput - Translates touch gestures into camera and mouse actions (autoload).
##
## The engine's touch->mouse emulation is disabled (see project.godot), so
## this node is the single translator between touch input and the game:
##
##   * tap                  -> synthetic left mouse click (UI and world)
##   * one-finger drag      -> camera pan, or terrain painting while a tool
##                             is active (synthetic mouse press/motion/release)
##   * two-finger drag      -> camera pan (midpoint) + zoom (pinch distance)
##   * two-finger tap       -> synthetic right click (cancel / close menus)
##
## Desktop mouse input is completely unaffected: it never comes through
## this node. All synthesized events are pushed through the normal viewport
## input pipeline, so buttons, panels and world clicks behave exactly as
## they do with a mouse.

## Set by the main scene (the isometric camera). Null disables gestures.
var camera: Camera2D = null
## Set by the main scene: func() -> bool, true while a tool is selected or
## a stroke is in progress (one-finger drags then paint instead of panning).
var paint_mode_provider: Callable = func() -> bool: return false

const TAP_DISTANCE := 12.0
const TAP_DURATION_MS := 400

enum Gesture { NONE, TAP_PENDING, PANNING, PAINTING }

var _touches: Dictionary = {}  # index -> {"pos": Vector2, "start": Vector2, "start_ms": int}
var _gesture: int = Gesture.NONE
var _last_drag_pos: Vector2 = Vector2.ZERO
var _two_finger: Dictionary = {}  # {"start_ms": int, "mid_start": Vector2, "dist_start": float, "moved": bool}
var _suppressed_single: bool = false  # a remaining finger after a two-finger gesture

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)
	# InputEventScreenPinch is deliberately ignored: the two-finger distance
	# math below already zooms, and pinch events would double-apply it.

# =============================================================================
# GESTURE STATE MACHINE
# =============================================================================

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_pressed(event.index, event.position)
	else:
		_touch_released(event.index, event.position)

func _touch_pressed(index: int, pos: Vector2) -> void:
	_touches[index] = {
		"pos": pos,
		"start": pos,
		"start_ms": Time.get_ticks_msec(),
	}
	_suppressed_single = false

	if _touches.size() == 2:
		# A second finger joined: cancel whatever the first finger was doing
		# (camera pan or a paint stroke) and enter two-finger camera mode.
		_cancel_paint_stroke()
		_two_finger = {
			"start_ms": Time.get_ticks_msec(),
			"mid_prev": _midpoint(),
			"dist_prev": _pinch_distance(),
			"moved": false,
		}
		_gesture = Gesture.NONE
	elif _touches.size() == 1:
		_gesture = Gesture.TAP_PENDING
		_last_drag_pos = pos
	else:
		# Three or more fingers: the first two tracked fingers keep driving
		# the camera gesture.
		_two_finger["moved"] = true

func _touch_released(index: int, pos: Vector2) -> void:
	var was_two_finger: bool = _two_finger.size() > 0 and _touches.size() == 2
	var info: Dictionary = _touches.get(index, {})
	_touches.erase(index)

	if was_two_finger and _touches.size() < 2:
		# The two-finger gesture ended.
		if _is_two_finger_tap():
			_synthesize_click(_midpoint_before_release(pos), MOUSE_BUTTON_RIGHT)
		_two_finger = {}
		# Any remaining finger must not fire a tap (it belonged to the
		# gesture), so rebase it and suppress its release-click.
		for remaining in _touches.values():
			remaining["start"] = remaining["pos"]
			remaining["start_ms"] = Time.get_ticks_msec()
		_suppressed_single = true
		_gesture = Gesture.NONE
		return

	if _touches.size() == 0:
		_finish_single_touch(info, pos)
	else:
		_gesture = Gesture.NONE

func _finish_single_touch(info: Dictionary, pos: Vector2) -> void:
	var gesture: int = _gesture
	_gesture = Gesture.NONE
	if info.is_empty():
		return
	if gesture == Gesture.PAINTING:
		# End the stroke: release the synthetic mouse button.
		_synthesize_mouse_button(MOUSE_BUTTON_LEFT, false, _last_drag_pos)
		return
	if _suppressed_single:
		_suppressed_single = false
		return
	var elapsed: int = Time.get_ticks_msec() - int(info["start_ms"])
	if elapsed > TAP_DURATION_MS:
		return
	if pos.distance_to(Vector2(info["start"])) > TAP_DISTANCE:
		return
	# A genuine tap: click whatever is under the finger.
	_synthesize_click(pos, MOUSE_BUTTON_LEFT)

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	var info: Dictionary = _touches[event.index]
	info["pos"] = event.position
	_touches[event.index] = info

	if _two_finger.size() > 0 and _touches.size() >= 2:
		# Two-finger camera control: pan with the midpoint, zoom with the
		# distance. This also keeps firing while a paint stroke was
		# interrupted, so the stroke stays cancelled.
		_track_two_finger()
		return

	# Single-finger gesture (two-finger mode is handled above).
	if _touches.size() != 1:
		return
	var start: Vector2 = info["start"]
	var moved: float = event.position.distance_to(start)

	if _gesture == Gesture.TAP_PENDING:
		if moved > TAP_DISTANCE:
			if _is_paint_mode():
				_gesture = Gesture.PAINTING
				_synthesize_mouse_button(MOUSE_BUTTON_LEFT, true, start)
			elif _camera_panning_allowed():
				_gesture = Gesture.PANNING
			else:
				_gesture = Gesture.NONE  # e.g. main menu backdrop: do nothing
		# Advance the reference point so the next drag's delta does not
		# re-count the movement that crossed the threshold.
		_last_drag_pos = event.position
		return

	if _gesture == Gesture.PAINTING:
		# Keep the synthetic mouse button pressed while the finger moves.
		_synthesize_mouse_motion(event.position)
	elif _gesture == Gesture.PANNING:
		camera.pan_screen_offset(event.position - _last_drag_pos)
	_last_drag_pos = event.position

func _track_two_finger() -> void:
	if _two_finger.is_empty():
		return
	var mid: Vector2 = _midpoint()
	var dist: float = _pinch_distance()
	# Deltas are relative to the previous event, so panning/zooming track the
	# fingers instead of accumulating.
	var d_mid: Vector2 = mid - Vector2(_two_finger["mid_prev"])
	var prev_dist: float = float(_two_finger["dist_prev"])
	var d_dist: float = dist - prev_dist
	if d_mid.length() > TAP_DISTANCE or absf(d_dist) > TAP_DISTANCE:
		_two_finger["moved"] = true
	# Zoom is anchored to the live midpoint so the course under the fingers
	# stays under the fingers.
	if prev_dist > 0.5 and absf(d_dist) > 0.5 and camera:
		camera.zoom_by_factor(dist / prev_dist, mid)
	if d_mid.length() > 0.5 and camera:
		camera.pan_screen_offset(d_mid)
	_two_finger["mid_prev"] = mid
	_two_finger["dist_prev"] = dist

func _is_two_finger_tap() -> bool:
	if _two_finger.is_empty():
		return false
	var elapsed: int = Time.get_ticks_msec() - int(_two_finger["start_ms"])
	return elapsed <= TAP_DURATION_MS and not bool(_two_finger["moved"])

func _midpoint() -> Vector2:
	var positions: Array[Vector2] = []
	for info in _touches.values():
		positions.append(Vector2(info["pos"]))
		if positions.size() == 2:
			break
	if positions.size() < 2:
		return Vector2.ZERO
	return (positions[0] + positions[1]) / 2.0

func _midpoint_before_release(last_pos: Vector2) -> Vector2:
	# The just-released finger's final position is not in _touches anymore.
	var other: Vector2 = Vector2.ZERO
	var found: bool = false
	for info in _touches.values():
		other = Vector2(info["pos"])
		found = true
		break
	return (last_pos + other) / 2.0 if found else last_pos

func _pinch_distance() -> float:
	var positions: Array[Vector2] = []
	for info in _touches.values():
		positions.append(Vector2(info["pos"]))
		if positions.size() == 2:
			break
	if positions.size() < 2:
		return 0.0
	return positions[0].distance_to(positions[1])

func _is_paint_mode() -> bool:
	if paint_mode_provider.is_valid():
		return bool(paint_mode_provider.call())
	return false

func _camera_panning_allowed() -> bool:
	if camera == null:
		return false
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.get("current_mode") == GameManager.GameMode.MAIN_MENU:
		return false
	return true

# =============================================================================
# SYNTHETIC MOUSE EVENTS
# =============================================================================

## Push a full press+release click at `pos` through the normal input
## pipeline (a preceding motion event sets hover state for the GUI).
func _synthesize_click(pos: Vector2, button: MouseButton) -> void:
	_synthesize_mouse_motion(pos)
	_synthesize_mouse_button(button, true, pos)
	_synthesize_mouse_button(button, false, pos)

func _synthesize_mouse_button(button: MouseButton, pressed: bool, pos: Vector2) -> void:
	var vp: Viewport = get_viewport()
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	vp.push_input(ev, true)

func _synthesize_mouse_motion(pos: Vector2) -> void:
	var vp: Viewport = get_viewport()
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	vp.push_input(ev, true)

## End an in-progress paint stroke (release the synthetic mouse button).
func _cancel_paint_stroke() -> void:
	if _gesture == Gesture.PAINTING:
		_gesture = Gesture.NONE
		_synthesize_mouse_button(MOUSE_BUTTON_LEFT, false, _last_drag_pos)

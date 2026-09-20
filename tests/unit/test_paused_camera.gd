extends GutTest
## Tests for camera control while the game is paused.
##
## Pausing the game freezes the simulation by dropping Engine.time_scale to 0
## (see test_pause_system.gd). The camera is player UI, not part of the
## simulation, so it must stay fully controllable while paused:
##   - keyboard panning (WASD) and wheel zoom run on wall-clock time
##   - full-screen pause/settings overlays swallow every pointer event, so
##     they must forward the ones over their dimmed backdrop to the camera

# Test double that lets us simulate pointer hover (headless runs never report
# a hovered control, because there is no real mouse).
class _ProbePauseMenu extends PauseMenu:
	var fake_hovered: Control = null

	func _get_hovered_control() -> Control:
		return fake_hovered

var _camera: IsometricCamera = null
var _menu: PauseMenu = null
# Lambda capture of a local var would be by-value, so signal results are
# tracked in a member.
var _resumed_flag: bool = false


func after_each() -> void:
	_release_key(KEY_W)
	_release_key(KEY_A)
	_release_key(KEY_S)
	_release_key(KEY_D)
	# Free immediately (not queue_free) — GUT counts the test script's
	# children when the last test finishes, before another frame could flush
	# queued frees.
	if _camera != null and is_instance_valid(_camera):
		_camera.free()
		_camera = null
	if _menu != null and is_instance_valid(_menu):
		_menu.free()
		_menu = null
	GameManager.is_paused = false
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	GameManager.set_mode(GameManager.GameMode.MAIN_MENU)


# --- Keyboard panning while paused ---

func test_camera_pans_with_keyboard_while_menu_paused() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.is_paused = true
	assert_eq(Engine.time_scale, 0.0, "precondition: engine must be frozen")

	_camera = await _spawn_camera(Vector2(2000, 1000))
	var hour_before := GameManager.current_hour

	_press_key(KEY_D)  # pan right
	await _await_real_seconds(0.5)
	_release_key(KEY_D)

	var dx := _camera.global_position.x - 2000.0
	assert_gt(dx, 100.0, "camera should pan right while the game is paused (dx=%.1f)" % dx)
	assert_eq(_camera.global_position.y, 1000.0, "horizontal panning must not move the camera vertically")
	assert_eq(GameManager.current_hour, hour_before, "simulation clock must stay frozen while the camera moves")

func test_camera_pans_with_keyboard_while_speed_paused() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)  # what Space / the || button does
	assert_eq(Engine.time_scale, 0.0, "precondition: engine must be frozen")

	_camera = await _spawn_camera(Vector2(2000, 1000))

	_press_key(KEY_W)  # pan up (screen space -y)
	await _await_real_seconds(0.5)
	_release_key(KEY_W)

	assert_lt(_camera.global_position.y, 1000.0 - 100.0, "camera should pan up while speed-paused")
	assert_eq(GameManager.current_speed, GameManager.GameSpeed.PAUSED, "panning must not unpause the game")

func test_camera_still_pans_during_normal_play() -> void:
	# Regression guard for the wall-clock rewrite: normal play must behave
	# the same as before.
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	assert_eq(Engine.time_scale, 1.0, "precondition: engine running at 1x")

	_camera = await _spawn_camera(Vector2(2000, 1000))

	_press_key(KEY_A)  # pan left
	await _await_real_seconds(0.5)
	_release_key(KEY_A)

	assert_lt(_camera.global_position.x, 2000.0 - 100.0, "camera should pan left during normal play")


# --- Mouse zoom / drag while paused (no overlay — e.g. Space pause) ---

func test_camera_zooms_with_wheel_while_paused() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.is_paused = true
	assert_eq(Engine.time_scale, 0.0, "precondition: engine must be frozen")

	_camera = await _spawn_camera(Vector2(2000, 1000))
	var zoom_before := _camera.get_zoom_level()

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_camera._unhandled_input(wheel)

	await _await_real_seconds(0.4)
	var zoom_after := _camera.get_zoom_level()
	# With the default (non-inverted) scroll, wheel-up targets a smaller zoom.
	assert_lt(zoom_after, zoom_before, "zoom must change while the game is paused")

func test_camera_middle_drag_pans_while_paused() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.is_paused = true
	assert_eq(Engine.time_scale, 0.0, "precondition: engine must be frozen")

	_camera = await _spawn_camera(Vector2(2000, 1000))

	_camera._unhandled_input(_middle_button_event(true, Vector2(300, 300)))
	assert_true(_camera.is_dragging(), "middle-button press should start a camera drag")

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(150, 300)  # drag 150px left
	motion.relative = Vector2(-150, 0)
	_camera._unhandled_input(motion)
	await _await_real_seconds(0.2)
	# Dragging the pointer left moves the camera right (standard map drag).
	assert_gt(_camera.global_position.x, 2000.0 + 75.0, "dragging should pan the camera while paused")

	_camera._unhandled_input(_middle_button_event(false, Vector2(150, 300)))
	assert_false(_camera.is_dragging(), "middle-button release should end the camera drag")


# --- Pause menu: forward backdrop events, ignore panel events ---

func test_pause_menu_forwards_backdrop_middle_drag_to_camera() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.is_paused = true
	assert_eq(Engine.time_scale, 0.0, "precondition: engine must be frozen")

	_camera = await _spawn_camera(Vector2(2000, 1000))
	_menu = await _spawn_probe_menu()
	_menu.camera = _camera

	_menu.fake_hovered = _menu._bg  # pointer over the dimmed backdrop
	_menu._input(_middle_button_event(true, Vector2(300, 300)))
	assert_true(_camera.is_dragging(), "middle-button press over the backdrop should start a camera drag")

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(200, 300)  # drag 100px left
	motion.relative = Vector2(-100, 0)
	_menu.fake_hovered = _find_button_in(_menu)  # pointer crosses the panel mid-drag
	_menu._input(motion)
	await _await_real_seconds(0.2)
	assert_gt(_camera.global_position.x, 2000.0 + 50.0, "drag should keep flowing even when the pointer crosses the menu panel")

	_menu._input(_middle_button_event(false, Vector2(200, 300)))
	assert_false(_camera.is_dragging(), "middle-button release over the panel should still end the camera drag")

func test_pause_menu_forwards_wheel_over_backdrop() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.is_paused = true

	_camera = await _spawn_camera(Vector2(2000, 1000))
	_menu = await _spawn_probe_menu()
	_menu.camera = _camera

	_menu.fake_hovered = _menu._bg
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_menu._input(wheel)

	await _await_real_seconds(0.4)
	assert_lt(_camera.get_zoom_level(), 1.0, "wheel over the backdrop should zoom while paused")

func test_pause_menu_does_not_forward_events_over_the_panel() -> void:
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.is_paused = true

	_camera = await _spawn_camera(Vector2(2000, 1000))
	_menu = await _spawn_probe_menu()
	_menu.camera = _camera

	var button := _find_button_in(_menu)
	assert_ne(button, null, "precondition: the pause menu has buttons")
	_menu.fake_hovered = button

	_menu._input(_middle_button_event(true, Vector2(300, 300)))
	assert_false(_camera.is_dragging(), "middle-button press over the menu panel must not move the camera")

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_menu._input(wheel)
	await _await_real_seconds(0.3)
	assert_eq(_camera.get_zoom_level(), 1.0, "wheel over the menu panel must not zoom")

func test_pause_menu_escape_still_resumes() -> void:
	_menu = await _spawn_probe_menu()
	_camera = await _spawn_camera(Vector2(2000, 1000))
	_menu.camera = _camera

	_resumed_flag = false
	_menu.resume_requested.connect(func(): _resumed_flag = true)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	_menu._input(esc)
	assert_true(_resumed_flag, "Escape must still resume the game")


# --- Helpers ---

func _spawn_camera(at: Vector2) -> IsometricCamera:
	var cam := IsometricCamera.new()
	cam.position = at
	add_child(cam)
	await get_tree().process_frame
	return cam

func _spawn_probe_menu() -> PauseMenu:
	var menu := _ProbePauseMenu.new()
	menu.hide()  # keep the full-rect overlay away from the GUT UI
	add_child(menu)
	await get_tree().process_frame
	return menu

func _find_button_in(root: Control) -> Button:
	for child in root.find_children("", "Button", true, false):
		return child as Button
	return null

func _middle_button_event(pressed: bool, at: Vector2 = Vector2.ZERO) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_MIDDLE
	ev.pressed = pressed
	ev.position = at
	return ev

func _press_key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)

func _release_key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = false
	Input.parse_input_event(ev)

## Awaits `seconds` of real (wall-clock) time. Frames keep processing while
## Engine.time_scale == 0 — they just receive a zero delta — so counting
## frames until the wall clock has advanced is reliable even while paused.
func _await_real_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

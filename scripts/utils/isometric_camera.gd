extends Camera2D
class_name IsometricCamera
## IsometricCamera - Enhanced camera controller with smooth zoom and subtle follow
##
## The camera is player-controlled UI, not part of the simulation: it always
## runs on wall-clock time, so it keeps panning/zooming while the game is
## paused (Engine.time_scale == 0) and stays at a constant real-world speed
## at any game speed.

@export var pan_speed: float = 800.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0
@export var smoothing_speed: float = 15.0
@export var zoom_smoothing_speed: float = 10.0
@export var bounds_enabled: bool = true
@export var bounds_min: Vector2 = Vector2(-2000, -2000)
@export var bounds_max: Vector2 = Vector2(6000, 4000)

# Subtle follow settings (for cursor-aware movement)
# NOTE: Disabled by default as it can cause unwanted camera drift
@export var subtle_follow_enabled: bool = false
@export var subtle_follow_strength: float = 0.02
@export var subtle_follow_deadzone: float = 100.0

var _target_position: Vector2
var _smoothed_position: Vector2
var _target_zoom: float
## Multiplies the player's design zoom to get the actual zoom. The Screen
## adapter drives it so the visible course area tracks the 1600x1000
## reference view on large windows while staying tappable on small ones.
## All public zoom APIs (set/get_zoom_level, focus_on, ...) work in design
## units; only the rendered `zoom` carries this factor.
var _world_scale: float = 1.0
var _is_dragging: bool = false
var _drag_start_mouse: Vector2
var _drag_start_camera: Vector2

var _last_wall_ms: int = 0
var _pointer_position: Vector2 = Vector2.ZERO
var _has_pointer: bool = false

# Shake state
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_tween: Tween = null

func _ready() -> void:
	_target_position = global_position
	_smoothed_position = global_position
	_target_zoom = zoom.x
	_last_wall_ms = Time.get_ticks_msec()
	# Pick up the responsive world scale before the first frame renders.
	# (Main re-applies it and tracks Screen.changed afterwards.)
	if has_node("/root/Screen"):
		apply_world_scale(Screen.world_scale)
	# Disable Godot's built-in smoothing — we handle it manually in _apply_movement
	# to avoid the one-frame lag that causes bouncing on rapid direction changes.
	position_smoothing_enabled = false

func _process(_delta: float) -> void:
	# Use wall-clock time instead of the frame delta: pausing the game drops
	# Engine.time_scale to 0, which makes the scaled delta 0 and would freeze
	# the camera along with the simulation. Measuring real time keeps the
	# camera fully controllable while paused (and at a constant speed at any
	# game speed).
	var now_ms := Time.get_ticks_msec()
	if _last_wall_ms < 0:
		_last_wall_ms = now_ms
	var real_delta := float(now_ms - _last_wall_ms) / 1000.0
	_last_wall_ms = now_ms
	# Guard against huge jumps (window minimized, OS sleep, debugger pause).
	real_delta = minf(real_delta, 0.1)
	_handle_keyboard_input(real_delta)
	_handle_subtle_follow(real_delta)
	_apply_movement(real_delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_pointer_position = event.position
		_has_pointer = true

func _unhandled_input(event: InputEvent) -> void:
	handle_input_event(event, false)

## Processes a camera input event (middle-drag pan, wheel/pinch zoom,
## bracket-key zoom).
##
## Full-screen overlays (pause menu, settings, ...) swallow every pointer
## event before it can reach _unhandled_input. Such overlays may call this
## directly so the player can keep looking around while the game is paused —
## after verifying the pointer is over their non-interactive backdrop, in
## which case they must pass `bypass_ui_hover_check = true`.
func handle_input_event(event: InputEvent, bypass_ui_hover_check: bool = false) -> void:
	if event is InputEventMouseButton:
		# Skip camera input when mouse is over a UI control.
		# On web exports, wheel events may not be consumed by the GUI system
		# even when hovering over panels/menus, causing unwanted zoom.
		if not bypass_ui_hover_check and get_viewport().gui_get_hovered_control() != null:
			return
		var scroll_direction := 1.0 if GameManager.invert_zoom_scroll else -1.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera_smooth(scroll_direction * zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera_smooth(-scroll_direction * zoom_speed)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_dragging = event.pressed
			if event.pressed:
				_drag_start_mouse = event.position
				_drag_start_camera = global_position

	if event is InputEventMouseMotion and _is_dragging:
		var drag_offset = event.position - _drag_start_mouse
		_target_position = _drag_start_camera - drag_offset / zoom.x

	# Mac trackpad pinch-to-zoom gesture
	if event is InputEventMagnifyGesture:
		var pinch_zoom_speed = 0.5
		var pinch_direction := -1.0 if GameManager.invert_zoom_scroll else 1.0
		_zoom_camera_smooth((1.0 - event.factor) * pinch_zoom_speed * pinch_direction)

	# Keyboard zoom hotkeys: ] to zoom in, [ to zoom out
	if event is InputEventKey and event.pressed:
		# Don't process any gameplay hotkeys while in main menu
		if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
			return
		# Don't process hotkeys if a text input has focus
		var focused = get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			return
		if event.keycode == KEY_BRACKETRIGHT:
			_zoom_camera_smooth(zoom_speed * 2)
		elif event.keycode == KEY_BRACKETLEFT:
			_zoom_camera_smooth(-zoom_speed * 2)

func _handle_keyboard_input(delta: float) -> void:
	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var direction := Vector2.ZERO
	if Input.is_action_pressed("camera_pan_up"): direction.y -= 1
	if Input.is_action_pressed("camera_pan_down"): direction.y += 1
	if Input.is_action_pressed("camera_pan_left"): direction.x -= 1
	if Input.is_action_pressed("camera_pan_right"): direction.x += 1

	if direction != Vector2.ZERO:
		direction = direction.normalized()
		# Move camera in screen space (visual direction) instead of isometric coordinates
		_target_position += direction * pan_speed * delta / zoom.x

func _handle_subtle_follow(delta: float) -> void:
	if not subtle_follow_enabled or _is_dragging:
		return

	var viewport_size = get_viewport_rect().size
	var viewport_center = viewport_size / 2.0
	var mouse_pos = get_viewport().get_mouse_position()

	# Calculate offset from center
	var offset_from_center = mouse_pos - viewport_center

	# Only apply if outside deadzone
	if offset_from_center.length() > subtle_follow_deadzone:
		var follow_direction = offset_from_center.normalized()
		var follow_strength = (offset_from_center.length() - subtle_follow_deadzone) / viewport_center.length()
		follow_strength = clamp(follow_strength, 0.0, 1.0)

		# Apply subtle movement toward mouse
		_target_position += follow_direction * subtle_follow_strength * follow_strength * pan_speed * delta / zoom.x

func _zoom_camera_smooth(zoom_delta: float) -> void:
	# Update the target directly: _apply_movement() eases the actual zoom
	# toward it every frame using wall-clock time, so zooming keeps working
	# while the engine is frozen (tweens would not — they scale with
	# Engine.time_scale).
	_target_zoom = clamp(_target_zoom + zoom_delta, min_zoom, max_zoom)

func _apply_movement(delta: float) -> void:
	if bounds_enabled:
		_target_position.x = clamp(_target_position.x, bounds_min.x, bounds_max.x)
		_target_position.y = clamp(_target_position.y, bounds_min.y, bounds_max.y)

	# Smooth zoom with easing (clamped to prevent overshoot on frame spikes).
	# The design zoom is resolved to a real zoom through _world_scale so the
	# course keeps its reference physical size at any window size.
	var zoom_diff = _target_zoom - _design_zoom()
	var new_zoom = _design_zoom() + zoom_diff * min(zoom_smoothing_speed * delta, 1.0)
	zoom = Vector2(new_zoom * _world_scale, new_zoom * _world_scale)

	# Manual position smoothing (exponential decay, same frame as input)
	var weight = 1.0 - exp(-smoothing_speed * delta)
	_smoothed_position = _smoothed_position.lerp(_target_position, weight)

	# Apply position with shake offset
	global_position = _smoothed_position + _shake_offset

# =============================================================================
# PUBLIC API
# =============================================================================

func is_dragging() -> bool:
	return _is_dragging

func focus_on(world_position: Vector2, instant: bool = false) -> void:
	_target_position = world_position
	if instant:
		_smoothed_position = world_position
		global_position = world_position

func focus_on_smooth(world_position: Vector2, duration: float = 0.5) -> void:
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "_target_position", world_position, duration)

func get_mouse_world_position() -> Vector2:
	if _has_pointer:
		return get_canvas_transform().affine_inverse() * _pointer_position
	return get_global_mouse_position()

func set_zoom_level(level: float, instant: bool = false) -> void:
	var clamped = clamp(level, min_zoom, max_zoom)
	if instant:
		_target_zoom = clamped
		zoom = Vector2(clamped * _world_scale, clamped * _world_scale)
	else:
		_zoom_camera_smooth(clamped - _target_zoom)

func get_zoom_level() -> float:
	return _design_zoom()

## The player's chosen zoom, in design units (min_zoom..max_zoom). The
## rendered `zoom` property additionally carries the responsive
## `_world_scale` factor, so internal code that converts screen pixels to
## world units must keep dividing by the raw `zoom`.
func _design_zoom() -> float:
	if _world_scale <= 0.0:
		return zoom.x
	return zoom.x / _world_scale

## Scale the rendered zoom so the world keeps the same physical size as the
## reference view for the current window. Called on startup and on every
## window resize/rotation (see the Screen adapter).
func apply_world_scale(world_scale: float) -> void:
	if world_scale <= 0.0:
		return
	# Re-render the current design zoom under the new world scale so a
	# world-scale change never causes a zoom wobble or a smoothing glitch.
	var design_zoom: float = _target_zoom if _world_scale <= 0.0 else zoom.x / _world_scale
	_world_scale = world_scale
	zoom = Vector2(design_zoom * world_scale, design_zoom * world_scale)

## Pan the camera by a screen-space delta (window pixels). Used by touch
## gestures; the middle-mouse pan uses the same conversion inline.
func pan_screen_offset(delta: Vector2) -> void:
	if zoom.x <= 0.0:
		return
	_target_position -= delta / zoom.x

## Zoom by `factor` (1.0 = no change) anchored at screen position `center`
## (window pixels): the world point under `center` stays under it. Used by
## the two-finger pinch gesture.
func zoom_by_factor(factor: float, center: Vector2) -> void:
	if factor <= 0.0 or factor == 1.0:
		return
	var z_old: float = _target_zoom
	var z_new: float = clampf(z_old * factor, min_zoom, max_zoom)
	if z_new == z_old:
		return
	# Screen pixels convert to world units through the *rendered* zoom
	# (design zoom x world scale), so the anchor math must use both.
	var offset := center - get_viewport_rect().size / 2.0
	_target_position += offset / (z_old * _world_scale) - offset / (z_new * _world_scale)
	_target_zoom = z_new

# =============================================================================
# CAMERA SHAKE
# =============================================================================

func shake(intensity: float = 5.0, duration: float = 0.2) -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()

	_shake_tween = create_tween()

	var shake_count = int(duration / 0.03)
	for i in range(shake_count):
		var shake_offset_target = Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		# Decay intensity over time
		var decay = 1.0 - (float(i) / shake_count)
		shake_offset_target *= decay

		_shake_tween.tween_property(self, "_shake_offset", shake_offset_target, 0.03)

	_shake_tween.tween_property(self, "_shake_offset", Vector2.ZERO, 0.05)

func micro_shake(intensity: float = 2.0) -> void:
	shake(intensity, 0.1)

# =============================================================================
# ZOOM TO POINT (Zoom centered on a world position)
# =============================================================================

func zoom_to_point(world_position: Vector2, new_zoom_level: float, duration: float = 0.3) -> void:
	var clamped_zoom = clamp(new_zoom_level, min_zoom, max_zoom)

	# Focus on the point while zooming
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_parallel(true)

	tween.tween_property(self, "_target_position", world_position, duration)
	tween.tween_property(self, "_target_zoom", clamped_zoom, duration)

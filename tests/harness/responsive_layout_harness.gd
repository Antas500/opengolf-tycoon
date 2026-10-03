extends Node
## Run: godot --headless --path . res://tests/harness/responsive_layout_harness.tscn
##
## Drives the real main scene through window sizes that cover phone, tablet
## and desktop, and checks that the responsive adapters (Screen, the
## IsometricCamera world scale, the compact HUD, the clamped popup panels
## and the TouchInput gesture wiring) all track the live window size.

var main: Node
var failures := 0

class GestureSentinel:
	extends Node
	var mouse_events: Array = []
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			mouse_events.append(event)

func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("RESPONSIVE: %s: %s" % ["PASS" if ok else "FAIL", description])

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _set_window(width: int, height: int) -> void:
	get_window().size = Vector2i(width, height)
	await _frames(4)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var screen: Node = get_node("/root/Screen")
	var touch: Node = get_node("/root/TouchInput")

	# ------------------------------------------------------------------
	# Phone portrait: compact HUD, 1:1 world scale, reachable main menu.
	# ------------------------------------------------------------------
	await _set_window(390, 844)
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await _frames(6)

	_check(screen.is_compact(), "390x844 window is compact")
	_check(absf(screen.world_scale - 1.0) < 0.001,
		"phone world scale is 1:1 (got %s)" % screen.world_scale)
	_check(main.mini_map.get("_map_size") == 120, "minimap is the compact 120px size")
	_check(absf(main.hud_status_column.custom_minimum_size.x - 150.0) < 1.0,
		"status column is the compact 150px width")
	_check(main.bottom_bar.offset_top <= -190.0, "bottom bar stays at its full height on phones")
	_check(absf(main.hud_status_column.offset_right + 8.0) < 1.0, "status column stays in the corner")

	# The main menu must fit (scrollable) with its six actions reachable.
	var menu_buttons: Array = _find_buttons(main.main_menu)
	_check(menu_buttons.size() == 6, "main menu shows six actions on phones (got %d)" % menu_buttons.size())
	var menu_fits := true
	for button in menu_buttons:
		var rect: Rect2 = button.get_global_rect()
		if rect.size.x > 390.0 or rect.size.y < 30.0:
			menu_fits = false
	_check(menu_fits, "main menu buttons fit the phone width and stay tappable")

	# Touch gestures are wired to the live camera.
	_check(touch.camera == main.camera, "TouchInput is wired to the main camera")
	_check(touch.paint_mode_provider.is_valid(), "TouchInput paint provider is wired")

	# ------------------------------------------------------------------
	# Phone landscape (rotation): still compact, layout re-flows.
	# ------------------------------------------------------------------
	await _set_window(844, 390)
	_check(screen.is_compact(), "844x390 (rotated phone) stays compact")
	_check(absf(screen.world_scale - 1.0) < 0.001, "rotated phone keeps 1:1 world scale")
	_check(absf(main.mini_map.offset_bottom + 190.0) < 1.0,
		"minimap re-docks above the bottom bar after rotation")

	# ------------------------------------------------------------------
	# Tablet: compact off once wide enough, world scale tracks the window.
	# ------------------------------------------------------------------
	await _set_window(1024, 768)
	_check(not screen.is_compact(), "1024x768 tablet is not compact")
	_check(absf(screen.world_scale - 0.879) < 0.01, "tablet world scale tracks the reference view")
	_check(main.mini_map.get("_map_size") == 180, "tablet restores the standard minimap")

	# ------------------------------------------------------------------
	# Desktop: the reference design — compact off, scale 1.0, standard HUD.
	# ------------------------------------------------------------------
	await _set_window(1600, 1000)
	_check(not screen.is_compact(), "1600x1000 desktop is not compact")
	_check(absf(screen.world_scale - 1.0) < 0.001, "desktop world scale is 1.0")
	_check(absf(main.hud_status_column.custom_minimum_size.x - 210.0) < 1.0,
		"desktop status column is the standard width")
	_check(main.mini_map.get("_map_size") == 180, "desktop minimap is the standard size")

	# A bigger desktop scales the world up with the window.
	await _set_window(1920, 1080)
	_check(absf(screen.world_scale - 1.08) < 0.01, "1920x1080 world scale is 1.08")
	_check(absf(main.camera.zoom.x - 1.08) < 0.05,
		"the rendered camera zoom carries the world scale (got %s)" % main.camera.zoom.x)

	# ------------------------------------------------------------------
	# Popup panels clamp to the phone screen and clear the bottom bar.
	# ------------------------------------------------------------------
	await _set_window(390, 844)
	var panel: CenteredPanel = main.financial_panel
	panel.show_centered()
	await _frames(3)
	var rect: Rect2 = panel.get_rect()
	var phone_viewport: Vector2 = get_viewport().get_visible_rect().size
	_check(Rect2(Vector2.ZERO, phone_viewport).encloses(rect),
		"financial panel is fully on a 390px phone")
	_check(rect.end.y <= phone_viewport.y - 190.0 + 0.5,
		"financial panel stays clear of the bottom bar")
	_check(rect.size.y <= phone_viewport.y - 24.0 - 198.0 + 1.0,
		"financial panel is clamped to the available height")

	# Resize while open: the panel re-clamps to the desktop area.
	await _set_window(1600, 1000)
	rect = panel.get_rect()
	_check(rect.size.y > 500.0, "financial panel regrows when the window enlarges (got %s)" % rect.size.y)
	_check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(rect),
		"financial panel stays on screen after the resize")
	panel.hide()

	# ------------------------------------------------------------------
	# Touch: with the menu gone, a tap synthesizes a real left click and a
	# one-finger drag pans the camera.
	# ------------------------------------------------------------------
	var menu: Node = main.main_menu
	menu.queue_free()
	main.main_menu = null
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	await _frames(3)

	var sentinel := GestureSentinel.new()
	add_child(sentinel)
	var tap_pos := Vector2(195, 300)
	_push_touch(true, 0, tap_pos)
	_push_touch(false, 0, tap_pos)
	await _frames(3)
	var saw_left_click := false
	for ev in sentinel.mouse_events:
		if ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and ev.position.distance_to(tap_pos) < 1.0:
			saw_left_click = true
	_check(saw_left_click, "tap synthesizes a left click at the finger position")

	var cam_x_before: float = main.camera._target_position.x
	var cam_y_before: float = main.camera._target_position.y
	_push_touch(true, 0, Vector2(200, 300))
	_push_drag(0, Vector2(260, 320))
	_push_drag(0, Vector2(320, 340))
	_push_touch(false, 0, Vector2(320, 340))
	await _frames(3)
	sentinel.queue_free()
	var dx: float = main.camera._target_position.x - cam_x_before
	var dy: float = main.camera._target_position.y - cam_y_before
	_check(absf(dx) > 20.0 and absf(dy) > 10.0, "one-finger drag pans the camera (moved %s, %s)" % [dx, dy])

	# ------------------------------------------------------------------
	# World map: the globe and the location list stay on screen at both the
	# desktop reference size and a phone, where they stack vertically.
	# ------------------------------------------------------------------
	var world: Node = get_node("/root/WorldMap")
	world.new_world(world.default_options())
	main._show_world_map_screen(false)
	await _frames(3)
	var world_screen: Node = main.get_node("UI/HUD/WorldMapScreen")
	var world_view: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var globe_rect: Rect2 = world_screen.globe.get_global_rect()
	_check(world_view.encloses(globe_rect), "desktop globe is fully on screen (%s)" % globe_rect)
	_check(world_screen._rows.size() == WorldLocations.get_all().size(),
		"every location has a list row")
	var list_rect: Rect2 = world_screen._list_box.get_global_rect()
	_check(list_rect.position.x > globe_rect.position.x,
		"desktop list sits beside the globe")

	await _set_window(844, 390)
	await _frames(4)
	world_view = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	globe_rect = world_screen.globe.get_global_rect()
	_check(world_view.encloses(globe_rect), "rotated-phone globe is fully on screen (%s)" % globe_rect)
	_check(globe_rect.size.x <= world_view.size.x and globe_rect.position.y > 0.0,
		"compact layout puts the globe above the list")
	main._close_world_map()

	print("RESPONSIVE: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _push_touch(pressed: bool, index: int, pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = pos
	get_viewport().push_input(ev, true)

func _push_drag(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	get_viewport().push_input(ev, true)

## Every Button under a node, for menu layout checks.
func _find_buttons(node: Node) -> Array:
	var found: Array = []
	if node == null:
		return found
	if node is Button:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_buttons(child))
	return found

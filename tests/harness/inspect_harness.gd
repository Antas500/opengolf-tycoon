extends Node
## Run: godot --headless --path . res://tests/harness/inspect_harness.tscn

var viewport: SubViewport
var main: Node2D
var failures := 0

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.handle_input_locally = true
	add_child(viewport)
	main = load("res://scenes/main/main.tscn").instantiate()
	viewport.add_child(main)
	_run.call_deferred()

func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("INSPECT: %s: %s" % ["PASS" if ok else "FAIL", description])

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not main.tile_inspector.visible, "Inspector hidden on main menu")
	# Exercise gameplay UI without generating an entire course.
	main.main_menu.queue_free()
	main.main_menu = null
	GameManager.set_mode(GameManager.GameMode.BUILDING)
	main._set_gameplay_ui_visible(true)
	await get_tree().process_frame
	_check(not main.tile_inspector.visible, "Showing HUD does not show inspector")
	var menu: Control = main.left_controls.get_node("MenuControls")
	var feed: Control = main.left_controls.get_node("FeedBtn")
	_check(feed.position.y >= menu.position.y + menu.size.y, "Feed is below Menu")
	_check(main.inspect_btn.position.y >= feed.position.y + feed.size.y, "Inspect is below Feed")
	_check(main.inspect_btn.position.y >= menu.position.y + menu.size.y, "Inspect is below Menu")
	_check(main.left_controls.size.y <= UIConstants.BOTTOM_BAR_HEIGHT, "Controls still fit the bottom bar")

	# Feed toggle: the button that used to live on the Club tab now rides in the
	# left control stack and opens the same event feed panel.
	main.feed_btn.pressed.emit()
	_check(main.event_feed_panel.visible, "Feed button opens the event feed")
	main.feed_btn.pressed.emit()
	_check(not main.event_feed_panel.visible, "Feed button closes the event feed")
	main._update_feed_unread(3)
	_check(main.feed_btn.text == "Feed (3)", "Unread count badges the Feed button")
	main._update_feed_unread(0)
	_check(main.feed_btn.text == "Feed", "Unread count clears the badge")

	# Map toggle: an icon button in the minimap's bottom-left corner, not in the stack.
	var map_btn: Button = main.map_btn
	_check(not main.left_controls.is_ancestor_of(map_btn), "Map button left the control stack")
	_check(map_btn.get_parent() == main.mini_map.get_parent(), "Map button is a minimap sibling")
	_check(map_btn.icon != null and map_btn.text.is_empty(), "Map button uses a map icon")
	var map_rect: Rect2 = main.mini_map.get_global_rect()
	var btn_rect: Rect2 = map_btn.get_global_rect()
	_check(map_rect.encloses(btn_rect), "Map button sits inside the minimap bounds")
	_check(btn_rect.position.x - map_rect.position.x <= 4.0 and map_rect.end.y - btn_rect.end.y <= 4.0,
		"Map button is in the minimap's bottom-left corner")
	var covers_map := false
	for corner in [btn_rect.position, Vector2(btn_rect.end.x, btn_rect.position.y), btn_rect.end, Vector2(btn_rect.position.x, btn_rect.end.y)]:
		if main.mini_map._is_within_map(corner - map_rect.position):
			covers_map = true
	_check(not covers_map, "Map button does not cover the minimap diamond")
	_check(map_btn.button_pressed and main.mini_map.visible, "Map starts shown and pressed")
	map_btn.button_pressed = false
	_check(not main.mini_map.visible and map_btn.is_visible_in_tree(), "Map button hides minimap but stays visible")
	map_btn.button_pressed = true
	_check(main.mini_map.visible, "Map button shows minimap again")
	main.mini_map.visible = false
	_check(not map_btn.button_pressed, "Hiding minimap (Tab) unpresses Map button")
	main.mini_map.visible = true
	_check(map_btn.button_pressed, "Showing minimap re-presses Map button")

	main._on_tool_selected(TerrainTypes.Type.FAIRWAY)
	main.inspect_btn.button_pressed = true
	_check(main.inspect_mode and main._has_active_tool(), "Inspect toggles on")
	_check(main.current_tool == -1 and not main.terrain_toolbar.has_selection(), "Inspect clears terrain tool")
	_check(not main.placement_preview.terrain_painting_enabled, "Inspect hides paint preview")
	main._start_painting()
	_check(not main.is_painting, "Inspect cannot paint")

	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	viewport.push_input(escape, true)
	await get_tree().process_frame
	_check(not main.inspect_mode and not main.inspect_btn.button_pressed, "Escape deselects Inspect")
	_check(main.pause_menu == null, "Escape does not open Menu while inspecting")

	main.inspect_btn.button_pressed = true
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	main._unhandled_input(right_click)
	_check(not main.inspect_mode, "Right-click exits Inspect")

	for tool in ["terrain", "building", "tree", "decoration", "elevation", "bulldozer"]:
		main.inspect_btn.button_pressed = true
		match tool:
			"terrain": main._on_tool_selected(TerrainTypes.Type.ROUGH)
			"building": main._on_building_type_selected_from_toolbar("restroom")
			"tree": main._on_tool_selected(TerrainTypes.Type.OAK)
			"decoration": main._on_decoration_type_selected_from_toolbar("fountain")
			"elevation": main._on_elevation_tool_pressed(ElevationTool.TOOL_VERTEX)
			"bulldozer": main._on_bulldozer_pressed()
		_check(not main.inspect_mode and not main.inspect_btn.button_pressed, "%s exits Inspect" % tool)
		main.inspect_btn.button_pressed = true
		_check(not main.elevation_tool.is_active() and not main.bulldozer_mode \
			and main.placement_manager.placement_mode == PlacementManager.PlacementMode.NONE,
			"Inspect cancels %s" % tool)

	# Feed real pointer motion through the viewport to exercise picking and UI occlusion.
	main.camera.focus_on(main.terrain_grid.grid_to_screen_center(Vector2i(64, 64)), true)
	main.camera.force_update_scroll()
	var motion := InputEventMouseMotion.new()
	motion.position = viewport.get_visible_rect().size * 0.5
	viewport.push_input(motion, true)
	await get_tree().process_frame
	main._update_tile_inspector()
	_check(main.tile_inspector.visible, "Hover over course shows details")
	var hovered_tile: Vector2i = main.terrain_grid.screen_to_grid(main.camera.get_mouse_world_position())
	_check(main.tile_inspector._title.text == "Inspect • Tile (%d, %d)" % [hovered_tile.x, hovered_tile.y],
		"Hover picks the tile using the camera and terrain projection")
	var money_before := GameManager.money
	main.terrain_grid.set_tile(hovered_tile, TerrainTypes.Type.BUNKER)
	var depth_before: int = main.terrain_grid.get_bunker_depth(hovered_tile)
	for modifier in ["none", "shift", "ctrl"]:
		var click := InputEventMouseButton.new()
		click.position = motion.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.shift_pressed = modifier == "shift"
		click.ctrl_pressed = modifier == "ctrl"
		viewport.push_input(click, true)
		click.pressed = false
		viewport.push_input(click, true)
	_check(not main.is_painting and not main._measuring and GameManager.money == money_before,
		"Normal and modified Inspect clicks neither paint, measure nor spend")
	_check(main.terrain_grid.get_bunker_depth(hovered_tile) == depth_before,
		"Shift-click in Inspect does not alter bunker depth")
	main._on_view_rotate_cw()
	main.camera.force_update_scroll()
	main._update_tile_inspector()
	_check(main.inspect_mode and main.tile_inspector.visible, "Inspect survives rotation")
	GameManager.set_speed(GameManager.GameSpeed.PAUSED)
	main._update_tile_inspector()
	_check(main.tile_inspector.visible, "Speed pause still allows inspection")
	motion.position = main.inspect_btn.get_global_rect().get_center()
	viewport.push_input(motion, true)
	await get_tree().process_frame
	main._update_tile_inspector()
	_check(not main.tile_inspector.visible, "Hover over HUD hides details")

	main.tile_inspector.show_tile(main.terrain_grid, main.entity_layer, Vector2i(1, 1), Vector2(100, 100))
	GameManager.is_paused = true
	main._update_tile_inspector()
	_check(not main.tile_inspector.visible, "Pause/menu hides hover details")
	GameManager.is_paused = false
	main.inspect_btn.button_pressed = false
	_check(not main.inspect_mode and not main.tile_inspector.visible, "Button toggles Inspect off")
	print("INSPECT: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

extends GutTest
## Tests for responsive popup panel layout (CenteredPanel) and the compact
## HUD pieces (MiniMap, HUDStatusColumn) driven by window size.

func _set_window(w: int, h: int) -> void:
	get_window().size = Vector2i(w, h)
	await get_tree().process_frame
	await get_tree().process_frame

func test_panel_clamps_to_available_area_on_a_phone_window() -> void:
	await _set_window(390, 844)
	var panel: CenteredPanel = autofree(CenteredPanel.new())
	var content := Control.new()
	content.custom_minimum_size = Vector2(500, 700)
	panel.add_child(content)
	add_child(panel)
	panel.show_centered()
	await get_tree().process_frame
	await get_tree().process_frame

	var viewport := get_viewport().get_visible_rect().size
	var area := Screen.available_panel_rect()
	assert_lte(panel.size.x, area.size.x + 0.5)
	assert_lte(panel.size.y, area.size.y + 0.5)
	# Fully on screen...
	assert_true(Rect2(Vector2.ZERO, viewport).encloses(panel.get_rect()))
	# ...and clear of the bottom bar.
	assert_lte(panel.position.y + panel.size.y, viewport.y - Screen.bottom_bar_height() + 0.5)
	# Content no longer fits vertically -> lazily wrapped in a ScrollContainer.
	assert_true(panel.get_node_or_null("ResponsiveScroll") != null)

func test_panel_uses_natural_size_on_a_desktop_window() -> void:
	await _set_window(1600, 1000)
	var panel: CenteredPanel = autofree(CenteredPanel.new())
	var content := Control.new()
	content.custom_minimum_size = Vector2(400, 300)
	panel.add_child(content)
	add_child(panel)
	panel.show_centered()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_almost_eq(panel.size.x, 400.0, 1.0)
	assert_almost_eq(panel.size.y, 300.0, 1.0)
	# Centered within the available area (symmetric horizontal margins ->
	# the same as the viewport center; vertically above the bottom bar).
	var area := Screen.available_panel_rect()
	assert_almost_eq(panel.position.x, area.position.x + (area.size.x - 400.0) / 2.0, 1.0)
	assert_almost_eq(panel.position.y, area.position.y + (area.size.y - 300.0) / 2.0, 1.0)
	# Small content never gets a scroll wrapper.
	assert_true(panel.get_node_or_null("ResponsiveScroll") == null)

func test_panel_clamps_width_when_content_is_wide() -> void:
	await _set_window(390, 844)
	var panel: CenteredPanel = autofree(CenteredPanel.new())
	var content := Control.new()
	content.custom_minimum_size = Vector2(900, 200)
	panel.add_child(content)
	add_child(panel)
	panel.show_centered()
	await get_tree().process_frame
	await get_tree().process_frame
	var area := Screen.available_panel_rect()
	assert_almost_eq(panel.size.x, area.size.x, 1.0)
	assert_almost_eq(panel.size.y, 200.0, 1.0)

func test_minimap_switches_between_standard_and_compact() -> void:
	var grid: TerrainGrid = autofree(TerrainGrid.new())
	grid.grid_width = 16
	grid.grid_height = 16
	add_child(grid)
	var mini: MiniMap = autofree(MiniMap.new())
	mini.setup(grid, null, null)
	add_child(mini)

	await _set_window(1600, 1000)
	mini.apply_screen()
	assert_eq(mini.get("_map_size"), MiniMap.MAP_SIZE)
	assert_eq(mini.get_map_total_size(), Vector2(MiniMap.MAP_SIZE + 4, MiniMap.MAP_SIZE / 2.0 + 4))

	await _set_window(390, 844)
	mini.apply_screen()
	assert_eq(mini.get("_map_size"), MiniMap.COMPACT_MAP_SIZE)
	assert_eq(mini.get_map_total_size(), Vector2(MiniMap.COMPACT_MAP_SIZE + 4, MiniMap.COMPACT_MAP_SIZE / 2.0 + 4))

	# Explicit sizing wins over the window.
	mini.set_map_size(100)
	assert_eq(mini.get("_map_size"), 100)
	assert_eq(mini.get_map_total_size(), Vector2(104, 54))

func test_status_column_uses_compact_width_on_narrow_windows() -> void:
	await _set_window(1600, 1000)
	var column: HUDStatusColumn = autofree(HUDStatusColumn.new())
	add_child(column)
	assert_almost_eq(column.custom_minimum_size.x, float(UIConstants.HUD_COLUMN_WIDTH), 0.5)
	assert_false(column.get("_collapsed"))

	await _set_window(390, 844)
	column.apply_screen()
	assert_almost_eq(column.custom_minimum_size.x, 150.0, 0.5)
	# Crossing into compact collapses the details to keep the course view clear.
	assert_true(column.get("_collapsed"))

	# Going back to a desktop window restores the width but stays collapsed
	# (the player chose to see the details or not).
	await _set_window(1600, 1000)
	column.apply_screen()
	assert_almost_eq(column.custom_minimum_size.x, float(UIConstants.HUD_COLUMN_WIDTH), 0.5)
	assert_true(column.get("_collapsed"))

extends GutTest

var toolbar: TerrainToolbar

func before_each() -> void:
	toolbar = TerrainToolbar.new()
	add_child_autofree(toolbar)

func test_bottom_bar_fits_two_rows_of_course_tiles() -> void:
	assert_eq(UIConstants.BOTTOM_BAR_HEIGHT, 190, "Bottom bar should be tall enough for two tile rows")
	assert_lte(toolbar.get_combined_minimum_size().y, float(UIConstants.BOTTOM_BAR_HEIGHT),
		"Toolbar content must fit inside the bottom bar")

func test_course_and_hazard_tiles_share_one_two_row_group() -> void:
	var surfaces := [TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.ROUGH,
		TerrainTypes.Type.GREEN, TerrainTypes.Type.TEE_BOX]
	var hazards := [TerrainTypes.Type.BUNKER, TerrainTypes.Type.WATER,
		TerrainTypes.Type.OUT_OF_BOUNDS]
	var grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.FAIRWAY].get_parent()
	assert_eq(grid.columns, TerrainToolbar.COURSE_TILE_COLUMNS)
	for tool_type in surfaces + hazards:
		assert_eq(toolbar._tool_buttons[tool_type].get_parent(), grid,
			"Course and hazard tiles should live in the same group")
	for tool_type in surfaces:
		assert_lt(toolbar._tool_buttons[tool_type].get_index(), grid.columns, "Surfaces on row 1")
	for tool_type in hazards:
		assert_gte(toolbar._tool_buttons[tool_type].get_index(), grid.columns, "Hazards on row 2")

func test_hazard_row_is_shifted_right_into_the_notches_of_the_surface_row() -> void:
	await _settle_layout()
	var grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.FAIRWAY].get_parent()
	var pitch := grid.tile_size.x + grid.h_separation
	var hazard_count := grid.get_child_count() - grid.columns

	for i in hazard_count:
		var hazard: Control = grid.get_child(grid.columns + i)
		var above_left: Control = grid.get_child(i)
		var above_right: Control = grid.get_child(i + 1)

		# Half a tile to the right: centred on the gap between the tiles above.
		assert_almost_eq(hazard.position.x, (above_left.position.x + above_right.position.x) * 0.5,
			0.01, "Hazard %d should sit in the notch between two surfaces" % i)
		assert_almost_eq(hazard.position.x - above_left.position.x, pitch * 0.5, 0.01,
			"Hazard %d should be shifted half a tile to the right" % i)

		# Half a tile down: tucked up into the row above instead of stacked,
		# below the breathing room kept above the first row.
		assert_almost_eq(hazard.position.y,
			grid.v_padding + grid.tile_size.y * 0.5 + grid.v_separation, 0.01,
			"Hazard %d should tuck up into the notches of the surface row" % i)
		assert_lt(hazard.position.y, grid.tile_size.y,
			"Hazard %d should rise into the row above, not sit below it" % i)

func test_interlocking_rows_never_overlap_each_others_diamonds() -> void:
	await _settle_layout()
	var grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.FAIRWAY].get_parent()
	var tile := grid.tile_size

	# A row 2 tile's top vertex must stay outside both diamonds above it.
	for i in grid.get_child_count() - grid.columns:
		var hazard: Control = grid.get_child(grid.columns + i)
		var vertex := hazard.position + Vector2(tile.x * 0.5, 0.0)
		for j in [i, i + 1]:
			var above: Control = grid.get_child(j)
			assert_false(TerrainTileButton.point_on_tile(vertex - above.position),
				"Hazard %d should not cover the diamond of row 1 tile %d" % [i, j])

func test_tile_buttons_only_answer_inside_the_diamond() -> void:
	var tile := TerrainTileButton.TILE_SIZE
	assert_true(TerrainTileButton.point_on_tile(tile * 0.5), "The middle of the tile is clickable")
	assert_true(TerrainTileButton.point_on_tile(Vector2(tile.x * 0.5, 2.0)), "So is the top vertex")
	assert_false(TerrainTileButton.point_on_tile(Vector2.ZERO),
		"The empty corner of the bounding box is not")
	assert_false(TerrainTileButton.point_on_tile(Vector2(tile.x, tile.y)),
		"Nor is the opposite corner")

func test_building_tiles_always_fill_two_rows() -> void:
	for count in [1, 2, 7, 16, 17]:
		var registry := {}
		for i in count:
			registry["b%d" % i] = {"name": "B%d" % i, "size": [1, 1], "cost": 100, "operating_cost": 0}
		toolbar.set_building_registry(registry)
		var columns: int = toolbar._building_shelf.columns
		var rows := ceili(float(count) / columns)
		assert_eq(rows, mini(count, TerrainToolbar.TILE_ROWS),
			"%d buildings should be laid out in two rows" % count)

func test_two_rows_of_big_tiles_fill_the_toolbar_page_height() -> void:
	var tile := TerrainTileButton.BUTTON_SIZE
	# Two interlocking rows: 1.5 tiles, the gap where row 2 tucks into row 1,
	# and the breathing room above and below the rows.
	var two_rows := tile.y * 1.5 + TerrainToolbar.TILE_V_SEPARATION \
			+ 2.0 * TerrainToolbar.TILE_V_PADDING
	# Tab bar, panel margins and the horizontal scrollbar shown when a page overflows.
	var page_height := float(UIConstants.BOTTOM_BAR_HEIGHT) - 39.0
	assert_gt(tile.y, 42.0, "Tiles should be bigger than the old 84x42 cells")
	assert_lte(two_rows + 2.0, page_height, "Two rows (plus drop shadow) fit the page")
	assert_gte(two_rows, page_height - 8.0, "Two rows should fill the page height")

	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	toolbar.set_building_registry(registry)
	await _settle_layout()
	var course_grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.FAIRWAY].get_parent()
	assert_almost_eq(course_grid.get_combined_minimum_size().y, two_rows, 0.01)
	assert_almost_eq(toolbar._building_shelf.get_combined_minimum_size().y, two_rows, 0.01)
	assert_lte(toolbar.get_combined_minimum_size().y, float(UIConstants.BOTTOM_BAR_HEIGHT))

func test_tile_rows_keep_space_above_below_and_between_them() -> void:
	var padding: int = TerrainToolbar.TILE_V_PADDING
	var gap: int = TerrainToolbar.TILE_V_SEPARATION
	assert_gt(padding, 0, "Rows should not touch the top of the page")
	assert_gt(gap, 8, "The interlocking rows should have more room between them")

	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	toolbar.set_building_registry(registry)
	await _settle_layout()

	for grid in [toolbar._tool_buttons[TerrainTypes.Type.FAIRWAY].get_parent(),
			toolbar._building_shelf]:
		var tiles: TileHoneycomb = grid
		assert_eq(tiles.v_padding, padding, "Both tabs keep the same breathing room")
		assert_eq(tiles.v_separation, gap, "Both tabs keep the same inter-row gap")

		# Space above the first row and below the last row.
		var first_tile: Control = tiles.get_child(0)
		assert_almost_eq(first_tile.position.y, float(padding), 0.01,
			"The first row starts below the breathing room")
		var last_row_bottom: float = 0.0
		for child in tiles.get_children():
			var tile: Control = child
			last_row_bottom = maxf(last_row_bottom, tile.position.y + tiles.tile_size.y)
		assert_almost_eq(tiles.get_combined_minimum_size().y - last_row_bottom,
			float(padding), 0.01, "The last row ends above the breathing room")

		# Space between the two rows: row 2 sits a full half tile plus the gap
		# below row 1, so the diamonds never touch.
		var row_two: Control = tiles.get_child(tiles.columns)
		assert_almost_eq(row_two.position.y - first_tile.position.y,
			tiles.tile_size.y * 0.5 + float(gap), 0.01,
			"Row 2 is tucked a half tile plus the gap below row 1")
		assert_gt(row_two.position.y - first_tile.position.y, tiles.tile_size.y * 0.5,
			"Row 2 must not touch the row above it")

## Containers lay their children out over the next frame.
func _settle_layout() -> void:
	await wait_frames(2)

func test_toolbar_has_nine_tabs() -> void:
	assert_eq(toolbar._tab_bar.tab_count, 9, "Toolbar should have 9 tabs")
	assert_eq(toolbar._pages.size(), 9, "Toolbar should have 9 pages")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.TERRAIN), "Terrain")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.IMPROVEMENTS), "Improvements")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.BUILDINGS), "Buildings")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.ELEVATION), "Elevation")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.HOLES), "Holes")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.GOLFERS), "Golfers")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.PLAYER), "Player")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.CLUB), "Club")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.STAFF), "Staff")

func test_all_pages_are_horizontal_scroll_containers() -> void:
	for i in toolbar._pages.size():
		var page = toolbar._pages[i]
		assert_not_null(page, "Page %d should not be null" % i)
		assert_eq(page.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO,
			"Page %d should have horizontal scroll mode AUTO" % i)
		assert_eq(page.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
			"Page %d should have vertical scroll mode DISABLED" % i)
		assert_gt(page.get_child_count(), 0, "Page %d should have content child" % i)
		var content = page.get_child(0)
		assert_true(content is HBoxContainer, "Page %d content container should be HBoxContainer" % i)

func test_tab_selection_toggles_visibility() -> void:
	toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	assert_true(toolbar._pages[TerrainToolbar.Tab.TERRAIN].visible)
	assert_false(toolbar._pages[TerrainToolbar.Tab.IMPROVEMENTS].visible)

	toolbar.select_tab(TerrainToolbar.Tab.IMPROVEMENTS)
	assert_false(toolbar._pages[TerrainToolbar.Tab.TERRAIN].visible)
	assert_true(toolbar._pages[TerrainToolbar.Tab.IMPROVEMENTS].visible)

	toolbar.select_tab(TerrainToolbar.Tab.BUILDINGS)
	assert_false(toolbar._pages[TerrainToolbar.Tab.IMPROVEMENTS].visible)
	assert_true(toolbar._pages[TerrainToolbar.Tab.BUILDINGS].visible)

func test_tool_selection_and_signals() -> void:
	watch_signals(toolbar)

	toolbar._on_tool_button_pressed(TerrainTypes.Type.FAIRWAY)
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.FAIRWAY])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.FAIRWAY)
	assert_true(toolbar.has_selection())

	toolbar._on_tool_button_pressed(TerrainTypes.Type.GREEN)
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.GREEN])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.GREEN)
	assert_true(toolbar._green_preset_group.visible, "Green presets should be visible when Green is selected")

	toolbar.clear_selection()
	assert_eq(toolbar.get_current_tool(), -1)
	assert_false(toolbar.has_selection())
	assert_false(toolbar._green_preset_group.visible, "Green presets should be hidden when cleared")

func test_terrain_paint_tools_are_isometric_course_tiles() -> void:
	var paint_tools := [TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.ROUGH,
		TerrainTypes.Type.GREEN, TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.BUNKER,
		TerrainTypes.Type.WATER, TerrainTypes.Type.OUT_OF_BOUNDS]
	for tool_type in paint_tools:
		var button: ToolButton = toolbar._tool_buttons[tool_type]
		assert_true(button is TerrainTileButton, "%s should be a tile button" % button.tool_name)
		assert_null(button.icon, "Terrain swatches should not use the old square sprite icons")
		assert_eq(button.text, "", "The name is drawn on the tile, not as button text")
		var labels := button.get_children().filter(func(child): return child is Label)
		assert_eq(labels.size(), 1, "The name is the only caption on the tile")
		assert_eq(button._name_label.text, button.tool_name)
		assert_false(button._name_label.text.contains(button.hotkey),
			"The shortcut number is no longer drawn on the tile")
		assert_eq(button._name_label.size, TerrainTileButton.BUTTON_SIZE,
			"The name spans the tile so its text centres on the diamond")
		assert_eq(button._name_label.position, Vector2.ZERO)
		assert_true(button._name_label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"Clicking a label should still select the tool")
		assert_false(button.accessibility_description.is_empty(),
			"The shortcut still reaches assistive tech")
		assert_eq(button.cost, TerrainTypes.get_placement_cost(tool_type))

	# Other pages and non-painting actions retain their familiar ToolButtons.
	assert_false(toolbar._tool_buttons[TerrainTypes.Type.PATH] is TerrainTileButton)
	assert_false(toolbar._tool_buttons["bulldozer"] is TerrainTileButton)
	assert_false(toolbar._open_hole_buttons[0] is TerrainTileButton)

func test_building_choices_use_the_course_tile_design() -> void:
	var registry := {
		"clubhouse": {"name": "Clubhouse", "size": [4, 4], "cost": 10000, "operating_cost": 100},
		"bench": {"name": "Bench", "size": [1, 1], "cost": 200, "operating_cost": 0},
	}
	toolbar.set_building_registry(registry)

	assert_true(toolbar._building_shelf is TileHoneycomb)
	assert_eq(toolbar._building_shelf.columns, TerrainToolbar.building_tile_columns(registry.size()))
	assert_eq(toolbar._building_shelf.get_child_count(), registry.size())
	for button in toolbar._building_shelf.get_children():
		assert_true(button is BuildingTileButton, "Building choices should use isometric tile buttons")
		assert_true(button is TerrainTileButton, "Building tiles should share the Course/Hazards button base")
		assert_eq(button.custom_minimum_size, TerrainTileButton.BUTTON_SIZE)
		assert_eq(button.text, "", "Building names should be drawn on the tile")
		assert_eq(button._name_label.size, TerrainTileButton.BUTTON_SIZE)
		assert_not_null(button._building_art)

	var bench: BuildingTileButton = toolbar._building_shelf.get_child(1)
	assert_eq(bench.tool_name, "Bench")
	assert_eq(bench.cost, 200)
	assert_eq(bench.maintenance, 0)
	assert_eq(bench.tooltip_text, "", "Only the rich TooltipManager popup should appear on hover")

	watch_signals(toolbar)
	bench.pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "building_selected", ["bench"])

func test_buildings_tab_has_no_heading_or_info_section() -> void:
	var page: ScrollContainer = toolbar._pages[TerrainToolbar.Tab.BUILDINGS]
	var texts: Array[String] = []
	for label in page.find_children("*", "Label", true, false):
		if label.get_parent() is TerrainTileButton:
			continue  # Building names drawn on the tiles themselves
		texts.append(label.text)
	assert_false(texts.has("FACILITIES"), "Buildings tab should not show a FACILITIES heading")
	assert_false(texts.has("INFO"), "Buildings tab should not show an INFO section")
	assert_eq(page.find_children("*", "VSeparator", true, false).size(), 0,
		"Buildings tab should not keep a separator for the removed INFO section")

func test_tile_previews_use_course_shader_and_neighboring_grass() -> void:
	var corners := TerrainTileButton.tile_corners()
	assert_eq(corners.size(), 4)
	assert_eq(corners[1].x - corners[3].x, TerrainTileButton.TILE_SIZE.x)
	assert_eq(corners[2].y - corners[0].y, TerrainTileButton.TILE_SIZE.y)
	assert_eq(TerrainTileButton.TILE_SIZE.x, TerrainTileButton.TILE_SIZE.y * 2,
		"The swatch has the same 2:1 footprint as a projected grid cell")

	for tool_type in [TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.GREEN,
			TerrainTypes.Type.BUNKER, TerrainTypes.Type.WATER, TerrainTypes.Type.OUT_OF_BOUNDS]:
		var button: TerrainTileButton = toolbar._tool_buttons[tool_type]
		var tile: Polygon2D = button.get_child(1)
		assert_eq(tile.polygon, corners)
		assert_eq(tile.texture.get_size(), Vector2(1, 1))
		assert_eq(tile.uv[0], Vector2(0.5, 0))
		assert_eq(tile.uv[1], Vector2(1, 0.5))
		var mat := button._surface_material
		assert_eq(mat.shader, preload("res://shaders/course_surface.gdshader"))
		assert_eq(mat.get_shader_parameter("grid_size"), Vector2(3, 3))
		assert_eq(mat.get_shader_parameter("grid_axis_x"), Vector2(32, 16))
		assert_eq(mat.get_shader_parameter("grid_axis_y"), Vector2(-32, 16))
		var image: Image = mat.get_shader_parameter("terrain_data").get_image()
		assert_eq(image.get_size(), Vector2i(3, 3))
		assert_eq(roundi(image.get_pixel(1, 1).r * 255.0), tool_type)
		assert_eq(roundi(image.get_pixel(0, 1).r * 255.0), TerrainTypes.Type.GRASS)
		assert_eq(roundi(image.get_pixel(2, 1).r * 255.0), TerrainTypes.Type.GRASS)

func test_terrain_tile_highlight_and_click_still_select_the_tool() -> void:
	watch_signals(toolbar)
	var button: TerrainTileButton = toolbar._tool_buttons[TerrainTypes.Type.WATER]
	button.pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.WATER])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.WATER)
	assert_true(button.is_selected())
	assert_eq(button._outline.default_color, UIConstants.COLOR_GOLD)
	assert_eq(button._name_label.get_theme_color("font_color"), UIConstants.COLOR_GOLD,
		"The selected tile's name is picked out in gold")

	toolbar.clear_selection()
	assert_false(button.is_selected())
	assert_eq(button._outline.default_color, UIConstants.COLOR_BORDER)

func test_tile_previews_follow_course_theme_colors() -> void:
	var button: TerrainTileButton = toolbar._tool_buttons[TerrainTypes.Type.WATER]
	var original_colors := TilesetGenerator._active_colors.duplicate()
	var recolored := original_colors.duplicate()
	recolored["water"] = Color("d0478c")
	recolored["fringe"] = Color("808044")
	TilesetGenerator.set_theme_colors(recolored)
	EventBus.theme_changed.emit(0)

	var palette: Image = button._surface_material.get_shader_parameter("palette").get_image()
	assert_eq(palette.get_pixel(TerrainTypes.Type.WATER, 0).to_html(false),
		Color("d0478c").to_html(false))
	assert_eq(button._surface_material.get_shader_parameter("fringe_color"), Color("808044"))

	TilesetGenerator.set_theme_colors(original_colors)
	EventBus.theme_changed.emit(0)

func test_brush_size_controls() -> void:
	watch_signals(toolbar)

	toolbar.set_brush_size(1)
	assert_eq(toolbar.get_brush_size(), 1)

	toolbar._on_brush_increase()
	assert_eq(toolbar.get_brush_size(), 3)
	assert_signal_emitted_with_parameters(toolbar, "brush_size_changed", [3])

	toolbar._on_brush_increase()
	assert_eq(toolbar.get_brush_size(), 5)

	toolbar._on_brush_decrease()
	assert_eq(toolbar.get_brush_size(), 3)
	assert_signal_emitted_with_parameters(toolbar, "brush_size_changed", [3])

func test_green_preset_toggle() -> void:
	watch_signals(toolbar)

	toolbar._on_green_preset_pressed("medium")
	assert_eq(toolbar.get_active_green_preset(), "medium")
	assert_signal_emitted_with_parameters(toolbar, "green_preset_selected", ["medium"])

	# Toggle off when clicked again
	toolbar._on_green_preset_pressed("medium")
	assert_eq(toolbar.get_active_green_preset(), "")
	assert_signal_emitted_with_parameters(toolbar, "green_preset_selected", [""])

func test_holes_tab_has_hbox_hole_list() -> void:
	assert_not_null(toolbar.hole_list, "hole_list should exist")
	assert_true(toolbar.hole_list is HBoxContainer, "hole_list should be an HBoxContainer")

	# Add a sample hole row and verify containment
	var row = HBoxContainer.new()
	row.name = "HoleRow1"
	toolbar.hole_list.add_child(row)
	assert_true(toolbar.hole_list.has_node("HoleRow1"))
	row.queue_free()

func test_golfers_tab_lists_are_horizontal_and_populate() -> void:
	assert_not_null(toolbar._active_golfers_box, "_active_golfers_box should exist")
	assert_true(toolbar._active_golfers_box is HBoxContainer, "_active_golfers_box should be HBoxContainer")
	assert_not_null(toolbar._recent_rounds_box, "_recent_rounds_box should exist")
	assert_true(toolbar._recent_rounds_box is HBoxContainer, "_recent_rounds_box should be HBoxContainer")

	# Test data provider
	toolbar.golfer_data_provider = func() -> Array:
		return [
			{"id": 1, "name": "Golfer Alice", "tier": 1, "hole": 2, "strokes": 3, "mood": 0.8},
			{"id": 2, "name": "Golfer Bob", "tier": 2, "hole": 5, "strokes": 4, "mood": 0.5},
		]

	toolbar.record_completed_round({
		"name": "Golfer Alice", "strokes": 72, "par": 72, "day": 1, "tier": 1, "owner": false
	})

	toolbar._refresh_golfer_lists()
	assert_eq(toolbar._active_golfers_box.get_child_count(), 2, "Should have 2 active golfer rows")
	assert_eq(toolbar._recent_rounds_box.get_child_count(), 1, "Should have 1 recent round row")

func test_feed_unread_badge() -> void:
	toolbar.set_feed_unread(5)
	assert_eq(toolbar._feed_button.text, "Feed (5)")

	toolbar.set_feed_unread(0)
	assert_eq(toolbar._feed_button.text, "Feed")

func test_action_signals() -> void:
	watch_signals(toolbar)

	toolbar._on_tool_button_pressed("open_hole")
	assert_signal_emitted(toolbar, "open_hole_pressed")

	toolbar._on_tool_button_pressed("tree")
	assert_signal_emitted(toolbar, "tree_placement_pressed")

	toolbar._on_tool_button_pressed("rock")
	assert_signal_emitted(toolbar, "rock_placement_pressed")

	toolbar._on_tool_button_pressed("building")
	assert_signal_emitted(toolbar, "building_placement_pressed")

	toolbar._on_tool_button_pressed("decoration")
	assert_signal_emitted(toolbar, "decoration_placement_pressed")

	toolbar._on_tool_button_pressed("raise")
	assert_signal_emitted(toolbar, "raise_elevation_pressed")

	toolbar._on_tool_button_pressed("lower")
	assert_signal_emitted(toolbar, "lower_elevation_pressed")

	toolbar._on_tool_button_pressed("mound")
	assert_signal_emitted_with_parameters(toolbar, "sculpt_terrain_pressed", [true])

	toolbar._on_tool_button_pressed("hollow")
	assert_signal_emitted_with_parameters(toolbar, "sculpt_terrain_pressed", [false])

	toolbar._on_tool_button_pressed("bulldozer")
	assert_signal_emitted(toolbar, "bulldozer_pressed")

	toolbar._on_tool_button_pressed("play_course")
	assert_signal_emitted(toolbar, "play_course_pressed")

	toolbar._on_tool_button_pressed("tournaments")
	assert_signal_emitted(toolbar, "tournaments_pressed")

	toolbar._on_tool_button_pressed("land")
	assert_signal_emitted(toolbar, "land_pressed")

	toolbar._on_tool_button_pressed("marketing")
	assert_signal_emitted(toolbar, "marketing_pressed")

	toolbar._on_tool_button_pressed("milestones")
	assert_signal_emitted(toolbar, "milestones_pressed")

	toolbar._on_tool_button_pressed("feed")
	assert_signal_emitted(toolbar, "feed_pressed")

	toolbar._on_tool_button_pressed("scorecard")
	assert_signal_emitted(toolbar, "scorecard_pressed")

func test_open_hole_button_is_disabled_until_a_pair_is_ready() -> void:
	toolbar.set_open_hole_state(false, "Paint a tee box to go with the waiting green.")
	for button in toolbar._open_hole_buttons:
		assert_true(button.disabled, "Open Hole must wait for a tee box and a cup")
		assert_string_contains(button.tool_description, "Paint a tee box")

	toolbar.set_open_hole_state(true, "")
	for button in toolbar._open_hole_buttons:
		assert_false(button.disabled)

func test_brush_limit_caps_the_brush_for_the_selected_tool() -> void:
	toolbar.set_brush_size(5)
	assert_eq(toolbar.effective_brush_size(), 5)

	toolbar.set_brush_limit(1)
	assert_eq(toolbar.effective_brush_size(), 1)
	assert_eq(toolbar._brush_labels[0].text, "1x1")
	for button in toolbar._brush_buttons:
		assert_true(button.disabled, "A 1x1 cap leaves nothing to change")

	toolbar.set_brush_limit(HoleLayout.UNLIMITED_BRUSH)
	assert_eq(toolbar.effective_brush_size(), 5)
	assert_eq(toolbar._brush_labels[0].text, "5x5")
	for button in toolbar._brush_buttons:
		assert_false(button.disabled)

func test_green_presets_hide_while_the_green_carries_a_cup() -> void:
	toolbar._on_tool_button_pressed(TerrainTypes.Type.GREEN)
	assert_true(toolbar._green_preset_group.visible)

	toolbar.set_brush_limit(1)  # Green With Hole: one tile, no preset shape
	assert_false(toolbar._green_preset_group.visible)

	toolbar.set_brush_limit(HoleLayout.UNLIMITED_BRUSH)  # Green Without Hole
	assert_true(toolbar._green_preset_group.visible)

func test_staff_tab_embeds_staff_management() -> void:
	assert_false(toolbar.has_signal("staff_pressed"),
		"Staff management is inline in the tab; it should not open a popup")
	assert_false(toolbar._tool_buttons.has("staff"),
		"Staff tab should not keep a Staff Management launcher button")
	assert_not_null(toolbar._staff_panel, "Staff tab should embed a StaffPanel")
	assert_true(toolbar._staff_panel is StaffPanel)
	assert_eq(toolbar._staff_panel.get_parent().get_parent(), toolbar._pages[TerrainToolbar.Tab.STAFF],
		"StaffPanel should live on the Staff tab page")

	var labels: Array[String] = []
	for label in toolbar._staff_panel.find_children("*", "Label", true, false):
		labels.append(label.text)
	assert_true(labels.has("CONDITION"), "Staff tab should show course condition")
	assert_true(labels.has("HIRE STAFF"), "Staff tab should show hire buttons")
	assert_true(labels.has("CURRENT STAFF"), "Staff tab should show the roster")
	assert_true(labels.has("EFFECTS"), "Staff tab should show staff effects")
	assert_eq(toolbar._staff_panel._hire_buttons.size(), 4, "Four staff types can be hired")

	# Selecting the Staff tab refreshes the embedded panel rather than emitting a popup signal.
	toolbar.select_tab(TerrainToolbar.Tab.STAFF)
	assert_true(toolbar._pages[TerrainToolbar.Tab.STAFF].visible)
	assert_true(toolbar._staff_panel.visible)

func test_mouse_wheel_horizontal_scroll_input() -> void:
	var scroll: ScrollContainer = toolbar._pages[TerrainToolbar.Tab.TERRAIN]
	scroll.scroll_horizontal = 100

	# Mouse wheel down -> scroll right (increase horizontal offset)
	var event_down = InputEventMouseButton.new()
	event_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event_down.pressed = true
	toolbar._on_scroll_gui_input(event_down, scroll)
	assert_eq(scroll.scroll_horizontal, 150)

	# Mouse wheel up -> scroll left (decrease horizontal offset)
	var event_up = InputEventMouseButton.new()
	event_up.button_index = MOUSE_BUTTON_WHEEL_UP
	event_up.pressed = true
	toolbar._on_scroll_gui_input(event_up, scroll)
	assert_eq(scroll.scroll_horizontal, 100)

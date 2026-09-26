extends GutTest

var toolbar: TerrainToolbar

func before_each() -> void:
	toolbar = TerrainToolbar.new()
	add_child_autofree(toolbar)

func test_bottom_bar_fits_two_rows_of_course_tiles() -> void:
	assert_eq(UIConstants.BOTTOM_BAR_HEIGHT, 190, "Bottom bar should be tall enough for two tile rows")
	assert_lte(toolbar.get_combined_minimum_size().y, float(UIConstants.BOTTOM_BAR_HEIGHT),
		"Toolbar content must fit inside the bottom bar")

## The Course Terrain tiles in reading order: the top row runs from the tee to
## the water, the bottom row pairs each playing surface with its trouble tiles.
const TOP_ROW := [TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.GREEN,
	TerrainTypes.Type.BUNKER, TerrainTypes.Type.ROUGH, TerrainTypes.Type.POT_BUNKER,
	TerrainTypes.Type.STREAM, TerrainTypes.Type.WATER]
const BOTTOM_ROW := [TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.FIRM_FAIRWAY,
	TerrainTypes.Type.DEEP_ROUGH, TerrainTypes.Type.WASTE_BUNKER, TerrainTypes.Type.BRUSH,
	TerrainTypes.Type.ROCKS, TerrainTypes.Type.OUT_OF_BOUNDS]

func test_course_tiles_share_one_group_in_top_and_bottom_rows() -> void:
	var grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX].get_parent()
	var landscape_count := 4 + CourseTheme.get_tree_types(GameManager.current_theme).size()
	assert_eq(grid.columns, TOP_ROW.size() + ceili(float(landscape_count) / 2.0))
	assert_eq(grid.flow_children().size(),
		TOP_ROW.size() + BOTTOM_ROW.size() + landscape_count,
		"All course and landscape tiles share exactly two rows")
	for tool_type in TOP_ROW + BOTTOM_ROW:
		assert_eq(toolbar._tool_buttons[tool_type].get_parent(), grid,
			"Course tiles should live in the same group")

	# Reading order: the tiles take slots in the order they are children. The
	# nestled Open Hole button is not a tile, so it holds no slot (see
	# test_open_hole_nests_into_the_notch_between_the_tee_and_green_tiles).
	var tiles: Array[Control] = grid.flow_children()
	for slot in TOP_ROW.size():
		assert_eq(tiles.find(toolbar._tool_buttons[TOP_ROW[slot]]), slot,
			"%s is tile %d of the top row" % [TerrainTypes.get_type_name(TOP_ROW[slot]), slot])
	for slot in BOTTOM_ROW.size():
		assert_eq(tiles.find(toolbar._tool_buttons[BOTTOM_ROW[slot]]), grid.columns + slot,
			"%s is tile %d of the bottom row" % [TerrainTypes.get_type_name(BOTTOM_ROW[slot]), slot])

	# The rows are drawn staggered: the bottom row sits half a tile below the top.
	await _settle_layout()
	var top_y: float = toolbar._tool_buttons[TOP_ROW[0]].position.y
	for tool_type in TOP_ROW:
		assert_almost_eq(toolbar._tool_buttons[tool_type].position.y, top_y, 0.01,
			"%s sits on the top row" % TerrainTypes.get_type_name(tool_type))
	for tool_type in BOTTOM_ROW:
		assert_almost_eq(toolbar._tool_buttons[tool_type].position.y,
			top_y + grid.tile_size.y * 0.5 + grid.v_separation, 0.01,
			"%s sits on the bottom row" % TerrainTypes.get_type_name(tool_type))

func test_bottom_row_is_shifted_right_into_the_notches_of_the_top_row() -> void:
	await _settle_layout()
	var grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX].get_parent()
	var pitch := grid.tile_size.x + grid.h_separation
	var tiles: Array[Control] = grid.flow_children()
	var bottom_count := tiles.size() - grid.columns

	for i in bottom_count:
		var below: Control = tiles[grid.columns + i]
		var above_left: Control = tiles[i]

		# Half a tile to the right of the tile above: the row is staggered.
		assert_almost_eq(below.position.x - above_left.position.x, pitch * 0.5, 0.01,
			"Bottom row tile %d should be shifted half a tile to the right" % i)
		if i + 1 < grid.columns:
			# Centred on the gap between the two tiles above it.
			var above_right: Control = tiles[i + 1]
			assert_almost_eq(below.position.x,
				(above_left.position.x + above_right.position.x) * 0.5, 0.01,
				"Bottom row tile %d should sit in the notch between two top row tiles" % i)

		# Half a tile down: tucked into the row above instead of stacked below
		# it, while staying clear of the breathing room above the first row.
		assert_almost_eq(below.position.y,
			grid.v_padding + grid.tile_size.y * 0.5 + grid.v_separation, 0.01,
			"Bottom row tile %d should tuck up into the notches of the top row" % i)
		assert_lt(below.position.y, grid.v_padding + grid.tile_size.y,
			"Bottom row tile %d should rise into the row above, not sit below it" % i)

func test_interlocking_rows_never_overlap_each_others_diamonds() -> void:
	await _settle_layout()
	var grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX].get_parent()
	var tile := grid.tile_size

	# A bottom row tile's top vertex must stay outside every diamond above it,
	# including the last tile, which overhangs the end of the top row.
	var tiles: Array[Control] = grid.flow_children()
	for i in tiles.size() - grid.columns:
		var below: Control = tiles[grid.columns + i]
		var vertex := below.position + Vector2(tile.x * 0.5, 0.0)
		for above in tiles.slice(0, grid.columns):
			assert_false(TerrainTileButton.point_on_tile(vertex - above.position),
				"Bottom row tile %d should not cover the diamond of top row tile %d"
					% [i, above.get_index()])

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
	assert_gt(tile.y, 42.0, "Tiles should be bigger than the old 84x42 cells")

	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))["buildings"]
	toolbar.set_building_registry(registry)
	await _settle_layout()
	var course_grid: TileHoneycomb = toolbar._tool_buttons[TerrainTypes.Type.FAIRWAY].get_parent()
	assert_almost_eq(course_grid.get_combined_minimum_size().y, two_rows, 0.01)
	assert_almost_eq(toolbar._building_shelf.get_combined_minimum_size().y, two_rows, 0.01)
	assert_lte(toolbar.get_combined_minimum_size().y, float(UIConstants.BOTTOM_BAR_HEIGHT))

	# The page the tiles sit on: the bottom bar less the tab bar, the panel
	# margins and the horizontal scrollbar shown when a page overflows.
	var page_height: float = toolbar._pages[TerrainToolbar.Tab.TERRAIN].size.y
	assert_lte(two_rows + 2.0, page_height, "Two rows (plus drop shadow) fit the page")
	assert_gte(two_rows, page_height - 8.0, "Two rows should fill the page height")

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

## The diamond's four vertices plus the midpoints of its edges: enough points to
## show a nestled button is clear of the tiles either side of it.
func _diamond_samples(box: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for corner in OpenHoleNotchButton.diamond_corners(box):
		points.append(corner)
	points.append(box * Vector2(0.25, 0.25))
	points.append(box * Vector2(0.75, 0.25))
	points.append(box * Vector2(0.75, 0.75))
	points.append(box * Vector2(0.25, 0.75))
	return points

## The improvement shelf's decoration tiles, in shelf order: the leading path
## tile is a painting tool rather than a catalogue entry, so catalogue
## assertions skip it.
func _catalogue_tiles() -> Array:
	return toolbar._decoration_shelf.get_children().filter(
		func(tile): return tile != toolbar._path_tile)

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

func test_all_pages_scroll_horizontally_behind_fixed_chrome() -> void:
	for i in toolbar._pages.size():
		var page = toolbar._pages[i]
		assert_not_null(page, "Page %d should not be null" % i)
		var scroll: ScrollContainer = toolbar.page_scroll(i)
		assert_not_null(scroll, "Page %d should hold a scroll container" % i)
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO,
			"Page %d should have horizontal scroll mode AUTO" % i)
		assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
			"Page %d should have vertical scroll mode DISABLED" % i)
		assert_gt(scroll.get_child_count(), 0, "Page %d should have content child" % i)
		var content = scroll.get_child(0)
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

func test_bulldozer_pins_to_the_removal_tabs_bottom_left_corners() -> void:
	assert_eq(toolbar._bulldozer_buttons.size(), 2,
		"One pinned Bulldozer per tab whose tiles it can remove")
	for tab in [TerrainToolbar.Tab.IMPROVEMENTS, TerrainToolbar.Tab.BUILDINGS]:
		var page: Control = toolbar._pages[tab]
		var found := page.find_children("*", "BulldozerButton", false, false)
		assert_eq(found.size(), 1, "%s page pins exactly one Bulldozer" % toolbar._tab_bar.get_tab_title(tab))
		var btn: BulldozerButton = found[0]
		# Anchored to the page's bottom-left corner, clear of the page edges.
		assert_almost_eq(btn.anchor_left, 0.0, 0.001, "Anchored to the left edge")
		assert_almost_eq(btn.anchor_top, 1.0, 0.001, "Anchored to the bottom edge")
		assert_almost_eq(btn.anchor_right, 0.0, 0.001, "Anchored to the left edge")
		assert_almost_eq(btn.anchor_bottom, 1.0, 0.001, "Anchored to the bottom edge")
		assert_almost_eq(btn.offset_left, BulldozerButton.CORNER_MARGIN, 0.01)
		assert_almost_eq(btn.offset_bottom, -BulldozerButton.CORNER_MARGIN, 0.01)
		# A round button: square bounds of the fixed diameter, circular hit face.
		assert_eq(btn.custom_minimum_size,
			Vector2(BulldozerButton.BUTTON_DIAMETER, BulldozerButton.BUTTON_DIAMETER))
		assert_true(btn._has_point(btn.size * 0.5), "The circle face is clickable")
		assert_false(btn._has_point(Vector2(1, 1)),
			"The bounding box corners fall through to the tiles underneath")
		assert_string_contains(btn.accessibility_description, "Course Terrain tiles are not affected",
			"The tooltip explains the Bulldozer's scope")
	# The Course Terrain page pins nothing: ground tiles are never bulldozed.
	assert_eq(toolbar._pages[TerrainToolbar.Tab.TERRAIN].find_children(
		"*", "BulldozerButton", true, false).size(), 0,
		"Course Terrain has no Bulldozer button")

func test_bulldozer_buttons_trigger_and_share_the_mode_state() -> void:
	watch_signals(toolbar)
	var buttons: Array = toolbar._bulldozer_buttons

	# Pressing a pinned button stays on its own tab and starts bulldozer mode.
	toolbar.select_tab(TerrainToolbar.Tab.IMPROVEMENTS)
	buttons[0].pressed.emit()
	assert_signal_emitted(toolbar, "bulldozer_pressed")
	assert_true(toolbar._pages[TerrainToolbar.Tab.IMPROVEMENTS].visible,
		"Pressing the pinned Bulldozer keeps its tab open")

	toolbar.select_tab(TerrainToolbar.Tab.BUILDINGS)
	buttons[1].pressed.emit()
	assert_signal_emitted(toolbar, "bulldozer_pressed")
	assert_true(toolbar._pages[TerrainToolbar.Tab.BUILDINGS].visible,
		"Pressing the pinned Bulldozer keeps its tab open")

	# Both circles report the mode: gold ring while it runs, quiet when it ends.
	toolbar.set_bulldozer_active(true)
	for btn in buttons:
		assert_true(btn.is_active(), "The pinned Bulldozer shows the mode is on")
	toolbar.set_bulldozer_active(false)
	for btn in buttons:
		assert_false(btn.is_active(), "The pinned Bulldozer shows the mode is off")

func test_tool_selection_and_signals() -> void:
	watch_signals(toolbar)

	toolbar._on_tool_button_pressed(TerrainTypes.Type.FAIRWAY)
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.FAIRWAY])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.FAIRWAY)
	assert_true(toolbar.has_selection())

	toolbar._on_tool_button_pressed(TerrainTypes.Type.GREEN)
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.GREEN])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.GREEN)

	toolbar.clear_selection()
	assert_eq(toolbar.get_current_tool(), -1)
	assert_false(toolbar.has_selection())

func test_terrain_paint_tools_are_isometric_course_tiles() -> void:
	# The walking path paints the course as much as any of these, so it is drawn
	# as a tile too — it just lives in the Improvements honeycomb.
	var paint_tools := [TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.ROUGH,
		TerrainTypes.Type.GREEN, TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.BUNKER,
		TerrainTypes.Type.WATER, TerrainTypes.Type.OUT_OF_BOUNDS, TerrainTypes.Type.PATH]
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

	# Non-painting actions retain their familiar ToolButtons. The Bulldozer is
	# no longer a Course Terrain tool at all — it is pinned to the Improvements
	# and Buildings tabs, whose tiles it can remove.
	assert_false(toolbar._tool_buttons.has("bulldozer"), "The Bulldozer is not a Course Terrain tool")
	assert_false(toolbar._open_hole_buttons[0] is TerrainTileButton)

func test_building_choices_use_the_course_tile_design() -> void:
	var registry := {
		"clubhouse": {"name": "Clubhouse", "size": [4, 4], "cost": 10000, "operating_cost": 100},
		"bench": {"name": "Bench", "size": [1, 1], "cost": 200, "operating_cost": 0},
	}
	toolbar.set_building_registry(registry)

	assert_true(toolbar._building_shelf is TileHoneycomb)
	assert_eq(toolbar._building_shelf.columns, TerrainToolbar.tile_columns(registry.size()))
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
	var page: Control = toolbar._pages[TerrainToolbar.Tab.BUILDINGS]
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

func test_green_tile_flag_tracks_the_next_green_type() -> void:
	var button: TerrainTileButton = toolbar._tool_buttons[TerrainTypes.Type.GREEN]
	assert_true(toolbar.green_will_place_cup(), "A new course's first green carries a cup")
	assert_true(button.shows_green_with_hole_flag(), "Green With Hole is marked with a flag")
	assert_true(button._cup_flag.visible)
	assert_string_contains(button.tool_description, "Green With Hole")

	toolbar.set_green_placement_state(false)
	assert_false(toolbar.green_will_place_cup())
	assert_false(button.shows_green_with_hole_flag(), "Green Without Hole has no flag")
	assert_false(button._cup_flag.visible)
	assert_string_contains(button.tool_description, "Green Without Hole")
	assert_string_contains(button.accessibility_description, "selected brush")

func test_every_course_terrain_tile_says_it_replaces_the_others() -> void:
	var sentence := TerrainTypes.REPLACES_ANY_COURSE_TILE
	for tool_type in TOP_ROW + BOTTOM_ROW + [TerrainTypes.Type.FLOWER_BED]:
		var button: TerrainTileButton = toolbar._tool_buttons[tool_type]
		assert_string_contains(button.tool_description, sentence,
			"%s tells the player it replaces any other Course Terrain tile" % button.tool_name)
	for key in ["boulder_small", "rock", "boulder_large"]:
		assert_string_contains(toolbar._tool_buttons[key].tool_description, sentence,
			"Boulder tiles replace any other Course Terrain tile")
	for tree_type in CourseTheme.get_tree_types(GameManager.current_theme):
		assert_string_contains(toolbar._tool_buttons["tree_" + str(tree_type)].tool_description, sentence,
			"Tree tiles replace any other Course Terrain tile")
	# The Path tool is an improvement laid over ground, not a Course Terrain tile.
	assert_false(toolbar._tool_buttons[TerrainTypes.Type.PATH].tool_description.contains(sentence),
		"The walking path does not replace course terrain")
	toolbar.set_green_placement_state(false)
	assert_string_contains(toolbar._tool_buttons[TerrainTypes.Type.GREEN].tool_description, sentence,
		"Switching the green between with-hole and without keeps the replacement note")

func test_course_terrain_tab_has_no_green_size_presets() -> void:
	var terrain_content: HBoxContainer = toolbar.page_content(TerrainToolbar.Tab.TERRAIN)
	assert_eq(terrain_content.get_child_count(), 3,
		"The terrain tab contains the tools, separator, unified tile grid, with no extra separator or preset group")

## Open Hole pairs the tee box and the green, so the Course Terrain tab nestles
## the action into the notch between those two tiles instead of leaving it in the
## tools column at the far edge of the tab.
func test_open_hole_nests_into_the_notch_between_the_tee_and_green_tiles() -> void:
	await _settle_layout()
	var grid: TileHoneycomb = toolbar._course_tiles
	var tee: Control = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX]
	var green: Control = toolbar._tool_buttons[TerrainTypes.Type.GREEN]
	var open_hole: OpenHoleNotchButton = toolbar._open_hole_buttons[0]

	assert_true(open_hole is OpenHoleNotchButton, "Open Hole is drawn as a notch cell, not a wide button")
	assert_eq(open_hole.get_parent(), grid, "Open Hole lives on the Course Terrain honeycomb")
	assert_true(grid.is_notch_child(open_hole), "The action fills a notch instead of a tile slot")
	assert_false(grid.flow_children().has(open_hole),
		"A nestled child takes no slot, so the tiles keep their rows")
	assert_eq(open_hole.tool_name, "Open Hole")
	assert_eq(open_hole.hotkey, "H")
	assert_eq(open_hole.caption(), "[H]",
		"A notch cell is too small for the name: it carries the hotkey chip")
	assert_string_contains(open_hole.tool_description, "tee box",
		"The hover tooltip still explains what the action does")

	# Tucked between the two tiles' facing edges, its bottom point on the point
	# where those edges meet and its top point level with the top of the row.
	var tee_centre := tee.position + tee.size * 0.5
	var green_centre := green.position + green.size * 0.5
	var centre := open_hole.position + open_hole.size * 0.5
	# Where the two tiles meet: the tee box's right vertex and the green's left
	# vertex face each other across the honeycomb's gap.
	var meet := (tee.position + Vector2(tee.size.x, tee.size.y * 0.5)
		+ green.position + Vector2(0.0, green.size.y * 0.5)) * 0.5
	assert_almost_eq(centre.x, (tee_centre.x + green_centre.x) * 0.5, 0.01,
		"The diamond is centred between the tee box and the green")
	assert_almost_eq(centre.x, meet.x, 0.01, "Centred on the point where the two tiles meet")
	assert_almost_eq(centre.y + open_hole.size.y * 0.5, meet.y, 0.01,
		"Its bottom point sits on the point where the tee box and the green meet")
	assert_almost_eq(centre.y - open_hole.size.y * 0.5, tee.position.y, 0.01,
		"Its top point is level with the top of the tiles' row")
	# Half a course cell: an isometric diamond narrower than the notch cell, so
	# it keeps daylight from the tiles, and exactly as tall, so its points line
	# up with the grid it drops into.
	assert_almost_eq(open_hole.size.x, open_hole.size.y * 2.0, 0.01,
		"The notch cell is an isometric diamond, like the tiles")
	var notch := grid.notch_cell_size()
	assert_lt(open_hole.size.x, notch.x, "Narrower than the notch, so it clears the tiles")
	assert_almost_eq(open_hole.size.y, notch.y, 0.01, "As tall as the notch: its points meet the grid")
	assert_almost_eq((grid.notch_centre(0) - centre).length(), 0.0, 0.01,
		"The honeycomb centres the action in the tee/green notch")
	for tile in [tee, green]:
		for point in _diamond_samples(open_hole.size):
			assert_false(TerrainTileButton.point_on_tile(open_hole.position + point - tile.position),
				"The Open Hole diamond stays clear of the %s tile" % tile.tool_name)

	# Only the diamond answers to the mouse.
	assert_true(open_hole._has_point(open_hole.size * 0.5), "The middle of the diamond is clickable")
	assert_false(open_hole._has_point(Vector2(1, 1)),
		"The empty corner of its bounding box falls through to the tiles underneath")

	# Pressing it still opens the hole.
	watch_signals(toolbar)
	open_hole.pressed.emit()
	assert_signal_emitted(toolbar, "open_hole_pressed")

func test_open_hole_notch_does_not_shift_the_course_tiles() -> void:
	await _settle_layout()
	var tiles: Array[Control] = toolbar._course_tiles.flow_children()
	assert_eq(tiles.find(toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX]), 0,
		"The tee box still opens the top row")
	assert_eq(tiles.find(toolbar._tool_buttons[TerrainTypes.Type.GREEN]), 1,
		"The green still follows it, with nothing wedged between them")
	assert_eq(tiles.find(toolbar._tool_buttons[TerrainTypes.Type.BUNKER]), 2,
		"The rest of the top row is untouched")
	for slot in BOTTOM_ROW.size():
		assert_eq(tiles.find(toolbar._tool_buttons[BOTTOM_ROW[slot]]),
			toolbar._course_tiles.columns + slot,
			"%s keeps its bottom row slot" % TerrainTypes.get_type_name(BOTTOM_ROW[slot]))

## The nestled diamond reports the action's availability in its own ring: gold
## while a tee box and a cup are waiting to be paired, grey while they are not.
func test_open_hole_notch_ring_tracks_whether_a_hole_can_be_opened() -> void:
	var open_hole: OpenHoleNotchButton = toolbar._open_hole_buttons[0]

	toolbar.set_open_hole_state(false, "Paint a tee box to go with the waiting green.")
	assert_true(open_hole.disabled)
	assert_eq(open_hole._ring_color(), OpenHoleNotchButton.COLOR_RING_DISABLED,
		"The ring is grey while no hole can be opened")
	assert_string_contains(open_hole.tool_description, "Paint a tee box")

	toolbar.set_open_hole_state(true, "")
	assert_false(open_hole.disabled)
	assert_eq(open_hole._ring_color(), UIConstants.COLOR_GOLD,
		"The ring turns gold the moment the pair is ready")
	assert_string_contains(open_hole.tool_description, "waiting tee box")

## Switching themes rebuilds the landscape catalogue around the nestled action:
## the tile flow is reshuffled, and the Open Hole button must not be moved into
## a row with it.
func test_theme_changes_keep_the_open_hole_between_the_tee_and_green() -> void:
	var original_theme: int = GameManager.current_theme
	var open_hole: OpenHoleNotchButton = toolbar._open_hole_buttons[0]
	for theme in [CourseTheme.Type.DESERT, CourseTheme.Type.PARKLAND,
			CourseTheme.Type.DESERT, CourseTheme.Type.PARKLAND]:
		GameManager.current_theme = theme
		EventBus.theme_changed.emit(theme)
		await _settle_layout()

		var grid: TileHoneycomb = toolbar._course_tiles
		assert_true(grid.is_notch_child(open_hole), "The action stays nestled, never a tile")
		assert_almost_eq(
			(open_hole.position + open_hole.size * 0.5).distance_to(grid.notch_centre(0)), 0.0, 0.01,
			"A rebuilt catalogue leaves the action in the tee/green notch")
		var tiles: Array[Control] = grid.flow_children()
		assert_eq(tiles.find(toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX]), 0)
		assert_eq(tiles.find(toolbar._tool_buttons[TerrainTypes.Type.GREEN]), 1)
		assert_false(tiles.has(open_hole), "The catalogue rebuild never turns it into a tile")
	GameManager.current_theme = original_theme
	EventBus.theme_changed.emit(original_theme)

func test_course_terrain_tools_column_keeps_only_the_brush_controls() -> void:
	var column: Control = toolbar.page_content(TerrainToolbar.Tab.TERRAIN).get_child(0)
	assert_eq(column.name, "TerrainToolsColumn")
	assert_eq(column.find_children("*", "OpenHoleNotchButton", true, false).size(), 0,
		"The Open Hole action no longer stands in the column")
	for button in column.find_children("*", "ToolButton", true, false):
		assert_ne(button.tool_name, "Open Hole")
	assert_eq(column.get_child_count(), 3,
		"The column is the BRUSH label, the brush stepper and the brush shape picker")
	assert_eq((column.get_child(0) as Label).text, "BRUSH")
	var stepper: HBoxContainer = column.get_child(1)
	assert_eq(stepper.get_child_count(), 3, "The stepper: -, the size it is set to, +")
	for child in stepper.get_children():
		if child is Button:
			assert_has(toolbar._brush_buttons, child, "The toolbar drives this stepper")
	assert_has(toolbar._brush_shape_buttons, column.get_child(2),
		"And this round/square picker")

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
	assert_signal_emitted_with_parameters(toolbar, "tree_selected", [
		CourseTheme.get_tree_types(GameManager.current_theme)[0]])

	toolbar._on_tool_button_pressed("rock")
	assert_signal_emitted_with_parameters(toolbar, "rock_selected", ["medium"])

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

func test_staff_tab_embeds_staff_management() -> void:
	assert_false(toolbar.has_signal("staff_pressed"),
		"Staff management is inline in the tab; it should not open a popup")
	assert_false(toolbar._tool_buttons.has("staff"),
		"Staff tab should not keep a Staff Management launcher button")
	assert_not_null(toolbar._staff_panel, "Staff tab should embed a StaffPanel")
	assert_true(toolbar._staff_panel is StaffPanel)
	assert_eq(toolbar._staff_panel.get_parent().get_parent(), toolbar.page_scroll(TerrainToolbar.Tab.STAFF),
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
	var scroll: ScrollContainer = toolbar.page_scroll(TerrainToolbar.Tab.TERRAIN)
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

func test_flower_bed_boulders_and_trees_are_terrain_tiles_in_course_terrain_tab() -> void:
	# Flower Bed is a TerrainTileButton in the Course Terrain tab
	var fb_btn: ToolButton = toolbar._tool_buttons[TerrainTypes.Type.FLOWER_BED]
	assert_true(fb_btn is TerrainTileButton, "Flower Bed should be a TerrainTileButton")
	assert_eq(TerrainToolbar.TOOL_TAB_MAP[TerrainTypes.Type.FLOWER_BED], TerrainToolbar.Tab.TERRAIN,
		"Flower Bed should belong to the Course Terrain tab")
	assert_eq(fb_btn.tool_name, "Flower Bed")
	assert_eq(fb_btn.get_parent(), toolbar._course_tiles,
		"Flower Bed should live on the unified honeycomb in Course Terrain tab")

	# Boulders are BoulderTileButtons (which inherit TerrainTileButton) in Course Terrain tab
	for b_id in ["boulder_small", "rock", "boulder_large"]:
		var b_btn: ToolButton = toolbar._tool_buttons[b_id]
		assert_true(b_btn is BoulderTileButton, "%s should be a BoulderTileButton" % b_id)
		assert_true(b_btn is TerrainTileButton, "%s should be a TerrainTileButton" % b_id)
		assert_eq(b_btn.get_parent(), toolbar._course_tiles,
			"%s should live on the unified honeycomb in Course Terrain tab" % b_id)

	assert_eq(toolbar._tool_buttons["boulder_small"].tool_name, "Small Boulder")
	assert_eq(toolbar._tool_buttons["rock"].tool_name, "Boulders")
	assert_eq(toolbar._tool_buttons["boulder_large"].tool_name, "Large Boulder")

	# Theme Trees for default theme (PARKLAND) are TreeTileButtons in Course Terrain tab
	var theme_trees: Array = CourseTheme.get_tree_types(CourseTheme.Type.PARKLAND)
	for tree_type in theme_trees:
		var t_id: String = "tree_" + str(tree_type)
		var t_btn: ToolButton = toolbar._tool_buttons[t_id]
		assert_true(t_btn is TreeTileButton, "%s should be a TreeTileButton" % t_id)
		assert_true(t_btn is TerrainTileButton, "%s should be a TerrainTileButton" % t_id)
		assert_eq(t_btn.get_parent(), toolbar._course_tiles,
			"%s should live on the unified honeycomb in Course Terrain tab" % t_id)

	# The unified honeycomb itself sits inside Course Terrain page and has 2 interlocking rows
	assert_not_null(toolbar._course_tiles)
	assert_eq(toolbar._course_tiles.get_parent().get_parent(),
		toolbar.page_content(TerrainToolbar.Tab.TERRAIN),
		"Unified honeycomb should live in Course Terrain tab")
	var total_landscape_tiles: int = 1 + 3 + theme_trees.size()
	assert_eq(toolbar._course_tiles.columns, TOP_ROW.size() + ceili(float(total_landscape_tiles) / 2.0),
		"Unified honeycomb should be laid out in two interlocking rows")
	var course_group: Control = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX].get_parent().get_parent()
	var landscape_group: Control = toolbar._course_tiles.get_parent()
	assert_eq(landscape_group, course_group,
		"Nature & Landscaping should share the course tile group")

func test_improvements_tab_holds_paths_and_every_decoration_tile() -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/decorations.json"))["decorations"]
	toolbar.set_decoration_registry(registry)

	var imp_hbox: HBoxContainer = toolbar.page_content(TerrainToolbar.Tab.IMPROVEMENTS)

	# Verify Trees, Boulders, Flower Bed are NOT in Improvements tab
	var tool_names: Array[String] = []
	for btn in imp_hbox.find_children("*", "ToolButton", true, false):
		tool_names.append(btn.tool_name)

	assert_false(tool_names.has("Trees"), "Improvements tab must not contain Trees")
	assert_false(tool_names.has("Boulders"), "Improvements tab must not contain Boulders")
	assert_false(tool_names.has("Flower Bed"), "Improvements tab must not contain Flower Bed")
	assert_true(tool_names.has("Path"), "Improvements tab should contain Path")
	assert_false(tool_names.has("Decorations"),
		"The Garden Shed's Decorations button is replaced by the decoration tiles")

	# The garden shed catalogue now lives in the tab as tiles, with the walking
	# path sharing their honeycomb.
	assert_eq(toolbar._decoration_shelf.get_child_count(),
		registry.size() + TerrainToolbar.IMPROVEMENTS_LEAD_TILES,
		"Every decoration from the garden shed should be a tile")
	for dec_type in registry:
		var tile: DecorationTileButton = toolbar._decoration_tiles[dec_type]
		assert_not_null(tile, "%s should have a tile" % dec_type)
		assert_eq(tile.get_parent(), toolbar._decoration_shelf)
		assert_eq(tile.decoration_type, dec_type)
		assert_eq(tile.tool_name, registry[dec_type]["name"])
		assert_eq(tile.get_parent().get_parent().get_parent(), imp_hbox,
			"The decoration shelf should sit in the Improvements tab")

func test_path_tile_leads_the_improvements_honeycomb() -> void:
	# The path is no longer a lone button in a PATHS box: it sits in the tile
	# honeycomb on the right of the tab, in slot 0 — the first tile of the top row.
	var shelf: TileHoneycomb = toolbar._decoration_shelf
	var path_tile: TerrainTileButton = toolbar._path_tile
	assert_true(path_tile is TerrainTileButton, "The path is drawn as a course tile")
	assert_eq(path_tile.get_parent(), shelf, "The path belongs to the improvements honeycomb")
	assert_eq(path_tile.get_index(), 0, "The path is the honeycomb's first tile")
	assert_same(toolbar._tool_buttons[TerrainTypes.Type.PATH], path_tile,
		"The path tile is what the toolbar highlights when the tool is selected")

	toolbar.set_decoration_registry({"bench": {"name": "Bench", "category": "furniture"},
		"statue": {"name": "Statue", "category": "sculptures"},
		"bed": {"name": "Bed", "category": "landscaping"},
		"pool": {"name": "Pool", "category": "water"}})
	assert_eq(shelf.get_child(0), path_tile,
		"Rebuilding the catalogue puts the path back at the head of the top row")
	await _settle_layout()
	var top_row_y: float = path_tile.position.y
	assert_almost_eq(shelf.get_child(1).position.y, top_row_y, 0.01,
		"The first decoration follows the path along the top row")
	assert_gt(shelf.get_child(3).position.y, top_row_y,
		"The row below sits in the notches under the path's row")

	var imp_hbox: HBoxContainer = toolbar.page_content(TerrainToolbar.Tab.IMPROVEMENTS)
	assert_false(imp_hbox.find_children("*", "Label", true, false)
		.any(func(label): return label.text == "PATHS"),
		"The path has no box of its own now it shares the tile shelf")

	# Picking the tile selects the tool and keeps the Improvements tab open.
	toolbar.select_tab(TerrainToolbar.Tab.BUILDINGS)
	watch_signals(toolbar)
	path_tile.pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.PATH])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.PATH)
	assert_eq(toolbar._tab_bar.current_tab, TerrainToolbar.Tab.IMPROVEMENTS)

func test_path_tile_previews_the_trail_over_the_ground_it_crosses() -> void:
	# A path is a thin trail laid on top of the ground, so its tile shows turf
	# with a ribbon across it instead of a full tile of paving.
	var path_tile: TerrainTileButton = toolbar._path_tile
	var image: Image = path_tile._surface_material.get_shader_parameter("terrain_data").get_image()
	assert_eq(roundi(image.get_pixel(1, 1).r * 255.0), TerrainTypes.Type.ROUGH,
		"The tile previews the rough a walking path is cut through, not cart-path paving")
	assert_eq(roundi(image.get_pixel(0, 1).r * 255.0), TerrainTypes.Type.ROUGH,
		"The turf runs to the edges of the tile: the path paints no patch of ground")
	assert_eq(roundi(image.get_pixel(2, 2).r * 255.0), TerrainTypes.Type.ROUGH,
		"The whole tile is ground the trail crosses")

	var art: Node2D = path_tile.get_node("WalkingPathPreviewArt")
	assert_eq(art.get_child_count(), 3, "A rim, the dirt, and a paler centre line")
	var band: Polygon2D = art.get_child(1)
	var center := TerrainTileButton.BUTTON_SIZE * 0.5
	var along := Vector2(TerrainTileButton.TILE_SIZE.x * 0.5, TerrainTileButton.TILE_SIZE.y * 0.5)
	# The ribbon's ends are the midpoints of the two tile edges it joins, so a
	# lone tile reads as a piece of one continuous trail.
	assert_eq((band.polygon[0] + band.polygon[3]) * 0.5, center - along * 0.5,
		"The trail starts at the shared edge with the neighbour up-left")
	assert_eq((band.polygon[1] + band.polygon[2]) * 0.5, center + along * 0.5,
		"and ends at the shared edge with the neighbour down-right")
	for corner in band.polygon:
		assert_true(TerrainTileButton.point_on_tile(corner),
			"The trail stays inside the diamond: %s" % corner)
	assert_eq(band.color, WalkingPathOverlay.DIRT_COLOR,
		"The preview uses the overlay's own dirt colours")

func test_decoration_tiles_use_the_course_tile_design() -> void:
	var registry := {
		"rose_border": {"name": "Rose Border", "category": "landscaping", "cost": 120,
			"daily_upkeep": 3, "description": "Roses for the walks."},
		"fountain": {"name": "Fountain", "category": "water", "cost": 500,
			"daily_upkeep": 15, "description": "A sparkling water feature.",
			"unlock": {"type": "reputation", "value": 99}},
	}
	toolbar.set_decoration_registry(registry)

	assert_true(toolbar._decoration_shelf is TileHoneycomb)
	assert_eq(toolbar._decoration_shelf.columns, TerrainToolbar.tile_columns(
		registry.size() + TerrainToolbar.IMPROVEMENTS_LEAD_TILES),
		"The shelf's rows count the leading path tile as well as the catalogue")
	assert_eq(toolbar._decoration_shelf.get_child_count(),
		registry.size() + TerrainToolbar.IMPROVEMENTS_LEAD_TILES)
	assert_eq(toolbar._decoration_shelf.v_padding, TerrainToolbar.TILE_V_PADDING,
		"The decoration shelf keeps the same breathing room as the other tile tabs")

	for button in _catalogue_tiles():
		assert_true(button is DecorationTileButton, "Decorations should use isometric tile buttons")
		assert_true(button is TerrainTileButton, "Decoration tiles share the Course Terrain button base")
		assert_eq(button.custom_minimum_size, TerrainTileButton.BUTTON_SIZE)
		assert_eq(button.text, "", "Decoration names should be drawn on the tile")
		assert_eq(button._name_label.size, TerrainTileButton.BUTTON_SIZE)
		assert_eq(button.tooltip_text, "", "Only the rich TooltipManager popup should appear")
		assert_not_null(button._decoration_art, "Each tile previews the artwork used on the course")
		assert_false(button.accessibility_description.is_empty())

	var roses: DecorationTileButton = toolbar._decoration_tiles["rose_border"]
	assert_eq(roses.cost, 120)
	assert_eq(roses.maintenance, 3, "Daily upkeep reaches the tooltip footer")
	assert_string_contains(roses.tool_description, "Landscaping")
	assert_string_contains(roses.tool_description, "Roses for the walks.")

	watch_signals(toolbar)
	roses.pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "decoration_selected", ["rose_border"])

func test_decoration_shelf_keeps_the_garden_shed_category_order() -> void:
	var registry := {
		"statue": {"name": "Statue", "category": "sculptures"},
		"bench": {"name": "Bench", "category": "furniture"},
		"bed": {"name": "Bed", "category": "landscaping"},
		"pool": {"name": "Pool", "category": "water"},
		"unknown": {"name": "Oddity"},
	}
	toolbar.set_decoration_registry(registry)

	var order: Array[String] = []
	for child in _catalogue_tiles():
		order.append(child.decoration_type)
	assert_eq(order, ["bed", "pool", "bench", "statue", "unknown"],
		"Decorations should be listed category by category, in shed order")
	assert_eq(toolbar._decoration_shelf.get_child(0), toolbar._path_tile,
		"The path still leads the row the catalogue is laid out in")

func test_locked_decorations_stay_on_the_shelf_until_earned() -> void:
	var registry := {
		"topiary": {"name": "Topiary", "category": "landscaping", "cost": 200, "daily_upkeep": 8},
		"statue": {"name": "Golfer Statue", "category": "sculptures", "cost": 1000,
			"daily_upkeep": 10, "unlock": {"type": "star_rating", "value": 5}},
	}
	toolbar.set_decoration_registry(registry)

	var open_tile: DecorationTileButton = toolbar._decoration_tiles["topiary"]
	var locked_tile: DecorationTileButton = toolbar._decoration_tiles["statue"]
	assert_false(open_tile.disabled, "Decorations without a requirement are selectable")
	assert_true(locked_tile.disabled, "Locked decorations stay on the shelf, greyed out")
	assert_true(locked_tile.locked, "The tile knows it is locked")
	assert_almost_eq(locked_tile.modulate.a, 0.65, 0.001, "A locked tile is dimmed like a disabled tool")
	assert_string_contains(locked_tile.tool_description, "Locked")
	assert_string_contains(locked_tile.tool_description, "5★ rating")
	assert_string_contains(locked_tile.tool_description, "Sculptures")

	# Clicking a locked tile never starts a placement.
	watch_signals(toolbar)
	toolbar._on_decoration_card_pressed("statue")
	assert_signal_not_emitted(toolbar, "decoration_selected")

	# A course that earns the fifth star unlocks it on the next refresh.
	var stars: int = GameManager.course_rating.get("stars", 0)
	GameManager.course_rating["stars"] = 5
	toolbar.refresh_decoration_unlocks()
	assert_false(locked_tile.disabled, "Meeting the requirement unlocks the tile")
	assert_false(locked_tile.tool_description.contains("Locked"))
	GameManager.course_rating["stars"] = stars
	toolbar.refresh_decoration_unlocks()
	assert_true(locked_tile.disabled, "Losing the rating locks the tile again")

func test_decoration_unlocks_follow_the_live_course_state() -> void:
	var registry := {
		"bench": {"name": "Bench", "category": "furniture", "unlock":
			{"type": "holes_built", "value": 99}},
	}
	toolbar.set_decoration_registry(registry)
	var tile: DecorationTileButton = toolbar._decoration_tiles["bench"]
	assert_true(tile.disabled, "A course with fewer than 99 holes starts locked")
	assert_string_contains(tile.tool_description, "99 holes")

func test_improvements_decorations_fill_the_page_without_overflowing() -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/decorations.json"))["decorations"]
	toolbar.set_decoration_registry(registry)
	toolbar.select_tab(TerrainToolbar.Tab.IMPROVEMENTS)
	await _settle_layout()

	var tile := TerrainTileButton.BUTTON_SIZE
	var two_rows := tile.y * 1.5 + TerrainToolbar.TILE_V_SEPARATION \
			+ 2.0 * TerrainToolbar.TILE_V_PADDING
	assert_almost_eq(toolbar._decoration_shelf.get_combined_minimum_size().y, two_rows, 0.01,
		"28 decorations plus the path should fill exactly two interlocking rows")
	assert_eq(toolbar._decoration_shelf.columns,
		ceili(float(registry.size() + TerrainToolbar.IMPROVEMENTS_LEAD_TILES) / 2.0))
	assert_lte(toolbar.get_combined_minimum_size().y, float(UIConstants.BOTTOM_BAR_HEIGHT),
		"The Improvements tab must fit inside the bottom bar")

func test_every_decoration_tile_shows_course_artwork() -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/decorations.json"))["decorations"]
	for dec_type in registry:
		assert_true(DecorationTileArt.has_art(dec_type),
			"%s should have artwork for its tile" % dec_type)

func test_decoration_shelf_rebuild_leaves_no_stale_tiles() -> void:
	var first := {"a": {"name": "A", "category": "landscaping"}}
	var second := {"b": {"name": "B", "category": "water"}, "c": {"name": "C", "category": "water"}}
	toolbar.set_decoration_registry(first)
	toolbar.set_decoration_registry(second)

	assert_eq(toolbar._decoration_shelf.get_child_count(), 3,
		"Replacing the catalogue should immediately drop the old tiles")
	assert_false(toolbar._decoration_tiles.has("a"))
	assert_eq(toolbar._decoration_shelf.columns, 2,
		"Two decorations plus the leading path tile need two columns")
	assert_eq(toolbar._decoration_shelf.get_child(0), toolbar._path_tile,
		"The path survives the rebuild, at the head of the top row")

func test_theme_change_updates_tree_tiles_in_course_terrain_tab() -> void:
	# Switch theme to DESERT
	GameManager.current_theme = CourseTheme.Type.DESERT
	EventBus.theme_changed.emit(CourseTheme.Type.DESERT)

	var desert_trees: Array = CourseTheme.get_tree_types(CourseTheme.Type.DESERT)
	for tree_type in desert_trees:
		var t_id: String = "tree_" + str(tree_type)
		assert_true(toolbar._tool_buttons.has(t_id),
			"Course Terrain tab should contain Desert tree %s" % tree_type)
		assert_true(toolbar._tool_buttons[t_id] is TreeTileButton)

	# Reset theme back to PARKLAND
	GameManager.current_theme = CourseTheme.Type.PARKLAND
	EventBus.theme_changed.emit(CourseTheme.Type.PARKLAND)

func test_tree_and_boulder_tile_selection_signals() -> void:
	watch_signals(toolbar)

	# Selecting a tree tile emits tree_selected with the tree type
	toolbar._on_tool_button_pressed("tree_oak")
	assert_signal_emitted_with_parameters(toolbar, "tree_selected", ["oak"])
	assert_true(toolbar.has_selection())

	# Selecting a boulder tile emits rock_selected with the boulder size
	toolbar._on_tool_button_pressed("boulder_small")
	assert_signal_emitted_with_parameters(toolbar, "rock_selected", ["small"])
	assert_true(toolbar.has_selection())

	# Selecting Flower Bed selects tool TerrainTypes.Type.FLOWER_BED
	toolbar._on_tool_button_pressed(TerrainTypes.Type.FLOWER_BED)
	assert_signal_emitted_with_parameters(toolbar, "tool_selected", [TerrainTypes.Type.FLOWER_BED])
	assert_eq(toolbar.get_current_tool(), TerrainTypes.Type.FLOWER_BED)


func test_theme_changes_keep_one_honeycomb_without_stale_tiles() -> void:
	var original_theme: int = GameManager.current_theme
	var tee: ToolButton = toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX]
	var grid := toolbar._course_tiles
	for theme in [CourseTheme.Type.DESERT, CourseTheme.Type.PARKLAND,
			CourseTheme.Type.DESERT, CourseTheme.Type.PARKLAND]:
		GameManager.current_theme = theme
		EventBus.theme_changed.emit(theme)
		var trees: Array = CourseTheme.get_tree_types(theme)
		assert_eq(grid.flow_children().size(), 18 + trees.size(),
			"Theme refresh must immediately remove old tiles, even within one frame")
		assert_eq(grid.columns, ceili(float(grid.flow_children().size()) / 2.0))
		assert_same(toolbar._tool_buttons[TerrainTypes.Type.TEE_BOX], tee,
			"Theme changes must preserve course tile state")
		for key in toolbar._tool_buttons:
			if str(key).begins_with("tree_"):
				assert_has(trees, str(key).trim_prefix("tree_"), "No stale tree tools")
		var tiles: Array[Control] = grid.flow_children()
		for slot in BOTTOM_ROW.size():
			assert_eq(tiles.find(toolbar._tool_buttons[BOTTOM_ROW[slot]]), grid.columns + slot)
		assert_eq(toolbar._pages[TerrainToolbar.Tab.TERRAIN].find_children(
			"*", "TileHoneycomb", true, false).size(), 1)
	GameManager.current_theme = original_theme
	EventBus.theme_changed.emit(original_theme)

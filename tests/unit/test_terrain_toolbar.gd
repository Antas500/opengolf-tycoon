extends GutTest

var toolbar: TerrainToolbar

func before_each() -> void:
	toolbar = TerrainToolbar.new()
	add_child_autofree(toolbar)

func test_bottom_bar_height_is_reduced() -> void:
	assert_eq(UIConstants.BOTTOM_BAR_HEIGHT, 120, "Bottom bar height should be reduced to 120px")

func test_toolbar_has_nine_tabs() -> void:
	assert_eq(toolbar._tab_bar.tab_count, 9, "Toolbar should have 9 tabs")
	assert_eq(toolbar._pages.size(), 9, "Toolbar should have 9 pages")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.TERRAIN), "Terrain")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.IMPROVEMENTS), "Improve")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.BUILDINGS), "Build")
	assert_eq(toolbar._tab_bar.get_tab_title(TerrainToolbar.Tab.ELEVATION), "Elev")
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

	toolbar._on_tool_button_pressed("staff")
	assert_signal_emitted(toolbar, "staff_pressed")

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

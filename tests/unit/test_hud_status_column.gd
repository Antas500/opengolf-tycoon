extends GutTest
## Tests for HUDStatusColumn — the top-right vertical stats column that
## replaced the old full-width top bar.

var parent: Control
var column: HUDStatusColumn

func before_each() -> void:
	# Stand in for UI/HUD so the column's right-edge anchors have something to
	# anchor against.
	parent = Control.new()
	parent.size = Vector2(1600, 1000)
	add_child_autofree(parent)

	column = HUDStatusColumn.new()
	parent.add_child(column)
	column.owner = null

func after_each() -> void:
	if is_instance_valid(column):
		column.queue_free()

# --- Layout ---

func test_column_is_anchored_to_top_right() -> void:
	assert_eq(column.anchor_left, 1.0, "Left edge should anchor to the right side")
	assert_eq(column.anchor_right, 1.0, "Right edge should anchor to the right side")
	assert_eq(column.anchor_top, 0.0, "Top edge should anchor to the top")
	assert_eq(column.grow_horizontal, Control.GROW_DIRECTION_BEGIN,
		"Column should grow leftwards from the right edge")

func test_column_does_not_span_full_width() -> void:
	var width: float = column.offset_right - column.offset_left
	assert_eq(width, float(UIConstants.HUD_COLUMN_WIDTH),
		"Column should be a fixed narrow width, not full-screen")
	assert_lt(width, parent.size.x * 0.25,
		"Column should occupy a small fraction of the viewport width")

func test_column_sits_inside_the_top_right_corner() -> void:
	await wait_frames(2)
	var rect: Rect2 = column.get_rect()
	assert_almost_eq(rect.end.x, parent.size.x - UIConstants.HUD_COLUMN_MARGIN, 1.0,
		"Right edge should be inset from the viewport's right edge by the margin")
	assert_almost_eq(rect.position.y, float(UIConstants.HUD_COLUMN_MARGIN), 1.0,
		"Column should start just below the top of the viewport")
	assert_gt(rect.position.x, parent.size.x * 0.5,
		"Column should live in the right half of the screen")

func test_column_is_taller_than_it_is_wide() -> void:
	await wait_frames(2)
	var rect := column.get_rect()
	assert_gt(rect.size.y, rect.size.x,
		"A column stacks vertically, so it should be taller than wide")

func test_occupied_height_tracks_content() -> void:
	await wait_frames(2)
	assert_gt(column.get_occupied_height(), 0.0,
		"Occupied height should be reported for other HUD elements to clear")
	assert_almost_eq(column.get_occupied_height(), column.offset_bottom, 0.5)

# --- Stat rows ---

func test_all_stats_are_stacked_in_one_vbox() -> void:
	var col: Node = column.get_node("Column")
	assert_true(col is VBoxContainer, "Stats should be stacked in a VBoxContainer")
	assert_gt(col.get_child_count(), 3, "Column should contain several stacked rows")

func test_every_stat_is_present() -> void:
	# Each stat control should exist and be parented under the column
	for control in [
		column._game_mode_label, column._money_button, column._money_trend,
		column._date_label, column._time_label, column._reputation_button,
		column._rating_button, column._weather_label, column._wind_label,
	]:
		assert_not_null(control, "Stat control should exist")
		assert_true(column.is_ancestor_of(control), "Stat control should live in the column")

func test_stat_rows_are_vertically_ordered() -> void:
	await wait_frames(2)
	var money_y: float = column._money_button.global_position.y
	var date_y: float = column._date_label.global_position.y
	var wind_y: float = column._wind_label.global_position.y
	assert_lt(money_y, date_y, "Funds should sit above the date")
	assert_lt(date_y, wind_y, "Date should sit above the wind row")

func test_date_and_time_are_separate_rows() -> void:
	await wait_frames(2)
	assert_lt(column._date_label.global_position.y, column._time_label.global_position.y,
		"Date and time are split onto their own rows in the column")

# --- Collapsing ---

func test_starts_expanded() -> void:
	assert_false(column.is_collapsed(), "Column should start expanded")
	assert_true(column._details.visible)

func test_collapse_hides_details_but_keeps_funds() -> void:
	await wait_frames(2)
	var expanded_height: float = column.get_occupied_height()

	column.set_collapsed(true)
	await wait_frames(2)

	assert_true(column.is_collapsed())
	assert_false(column._details.visible, "Detail rows should hide when collapsed")
	assert_true(column._money_button.visible, "Funds stay visible when collapsed")
	assert_lt(column.get_occupied_height(), expanded_height,
		"Collapsed column should be shorter")

func test_collapse_emits_signal_and_round_trips() -> void:
	watch_signals(column)
	column.set_collapsed(true)
	assert_signal_emitted_with_parameters(column, "collapsed_changed", [true])

	column.set_collapsed(false)
	await wait_frames(2)
	assert_signal_emitted_with_parameters(column, "collapsed_changed", [false])
	assert_false(column.is_collapsed())
	assert_true(column._details.visible)

# --- Signals ---

func test_click_signals_fire() -> void:
	watch_signals(column)

	column._on_money_pressed()
	assert_signal_emitted(column, "money_clicked")

	column._on_reputation_pressed()
	assert_signal_emitted(column, "reputation_clicked")

	column._on_rating_pressed()
	assert_signal_emitted(column, "rating_clicked")

# --- Formatting ---

func test_money_is_thousands_separated() -> void:
	assert_eq(column._format_number(50000), "50,000")
	assert_eq(column._format_number(-1250), "-1,250")
	assert_eq(column._format_number(0), "0")

func test_rating_display_and_color() -> void:
	column.update_rating(4.5)
	assert_string_contains(column._rating_button.text, "(4.5)")
	assert_eq(column._rating_button.get_theme_color("font_color"), UIConstants.COLOR_GOLD,
		"High ratings should be gold")

	column.update_rating(1.2)
	assert_eq(column._rating_button.get_theme_color("font_color"), UIConstants.COLOR_DANGER,
		"Low ratings should be red")

func test_wind_direction_names() -> void:
	assert_eq(column._get_direction_name(0.0), "N")
	assert_eq(column._get_direction_name(90.0), "E")
	assert_eq(column._get_direction_name(180.0), "S")
	assert_eq(column._get_direction_name(270.0), "W")

# --- Clearance for other right-docked HUD panels ---

func test_clearance_reports_below_the_column() -> void:
	column.add_to_group(UIConstants.HUD_COLUMN_GROUP)
	await wait_frames(2)
	var clearance: float = UIConstants.get_hud_column_clearance(column)
	assert_gt(clearance, column.get_occupied_height(),
		"Clearance should leave a gap below the column")

func test_clearance_falls_back_without_a_column() -> void:
	var clearance: float = UIConstants.get_hud_column_clearance(null)
	assert_gt(clearance, 0.0, "Fallback clearance should be positive")

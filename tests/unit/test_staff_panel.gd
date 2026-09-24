extends GutTest
## Tests for the inline Staff tab management UI.

var _previous_staff_manager
var staff_manager: StaffManager
var panel: StaffPanel

func before_each() -> void:
	_previous_staff_manager = GameManager.staff_manager
	staff_manager = StaffManager.new()
	add_child_autofree(staff_manager)
	GameManager.staff_manager = staff_manager
	panel = StaffPanel.new()
	add_child_autofree(panel)

func after_each() -> void:
	GameManager.staff_manager = _previous_staff_manager

func test_builds_hire_roster_and_status_without_a_window_chrome() -> void:
	assert_eq(panel._hire_buttons.size(), 4)
	assert_not_null(panel._condition_bar)
	assert_not_null(panel._staff_list_container)
	assert_eq(panel._condition_bar.value, 100.0)
	assert_string_contains(panel._payroll_label.text, "$0")
	assert_eq(panel._staff_list_container.get_child_count(), 1)
	assert_eq(panel._staff_list_container.get_child(0).text, "No staff hired")

	var titles: Array[String] = []
	for label in panel.find_children("*", "Label", true, false):
		titles.append(label.text)
	assert_false(titles.has("Staff Management"), "Title/close chrome belonged to the old popup")
	assert_eq(panel.find_children("*", "Button", true, false).filter(
		func(btn): return btn.text == "X"
	).size(), 0, "No window-close or fire-X buttons in the toolbar tab")

func test_hiring_adds_a_roster_row_and_updates_payroll() -> void:
	panel._on_hire_pressed(StaffManager.StaffType.GROUNDSKEEPER)
	assert_eq(staff_manager.hired_staff.size(), 1)
	assert_eq(staff_manager.get_daily_payroll(),
		StaffManager.STAFF_DATA[StaffManager.StaffType.GROUNDSKEEPER]["base_salary"])
	assert_string_contains(panel._payroll_label.text, "$%d" % staff_manager.get_daily_payroll())
	assert_eq(panel._staff_list_container.get_child_count(), 1)
	var row = panel._staff_list_container.get_child(0)
	assert_true(row is HBoxContainer)
	var fire_buttons = row.find_children("*", "Button", true, false)
	assert_eq(fire_buttons.size(), 1)
	assert_eq(fire_buttons[0].text, "Fire")
	assert_string_contains(panel._hire_buttons[StaffManager.StaffType.GROUNDSKEEPER].text, "×1")

func test_firing_clears_the_roster() -> void:
	panel._on_hire_pressed(StaffManager.StaffType.MARSHAL)
	panel._on_hire_pressed(StaffManager.StaffType.PRO_SHOP)
	assert_eq(staff_manager.hired_staff.size(), 2)
	panel._on_fire_pressed(0)
	assert_eq(staff_manager.hired_staff.size(), 1)
	assert_eq(panel._staff_list_container.get_child_count(), 1)
	panel._on_fire_pressed(0)
	assert_eq(staff_manager.hired_staff.size(), 0)
	assert_eq(panel._staff_list_container.get_child(0).text, "No staff hired")
	assert_string_contains(panel._payroll_label.text, "$0")

func test_effects_reflect_hired_staff() -> void:
	assert_string_contains(panel._pace_label.text, "60%")
	assert_string_contains(panel._pro_shop_label.text, "+$0")
	panel._on_hire_pressed(StaffManager.StaffType.MARSHAL)
	panel._on_hire_pressed(StaffManager.StaffType.PRO_SHOP)
	assert_string_contains(panel._pace_label.text, "75%")
	assert_string_contains(panel._pro_shop_label.text, "+$5")
	assert_string_contains(panel._cart_label.text, "70%")
	panel._on_hire_pressed(StaffManager.StaffType.CART_OPERATOR)
	assert_string_contains(panel._cart_label.text, "85%")

func test_condition_bar_color_tracks_course_condition() -> void:
	staff_manager.course_condition = 0.4
	staff_manager.condition_changed.emit(0.4)
	assert_eq(panel._condition_bar.value, 40.0)
	assert_string_contains(panel._condition_label.text, "Poor")
	assert_eq(panel._bar_fill_style.bg_color, UIConstants.COLOR_DANGER)

	staff_manager.course_condition = 0.8
	panel.refresh()
	assert_eq(panel._condition_bar.value, 80.0)
	assert_string_contains(panel._condition_label.text, "Good")
	assert_eq(panel._bar_fill_style.bg_color, UIConstants.COLOR_SUCCESS)

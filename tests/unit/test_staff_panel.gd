extends GutTest
## Tests for the inline Staff tab management UI.
##
## The tab keeps exactly two sections: HIRE STAFF (a standard and a premium
## button per job) and CURRENT STAFF (payroll, weeds, and a row per employee with
## Move Area and Fire buttons).

var _previous_staff_manager
var _previous_weed_manager
var staff_manager: StaffManager
var weed_manager: WeedManager
var panel: StaffPanel

func before_each() -> void:
	_previous_staff_manager = GameManager.staff_manager
	_previous_weed_manager = GameManager.weed_manager
	staff_manager = StaffManager.new()
	add_child_autofree(staff_manager)
	weed_manager = WeedManager.new()
	add_child_autofree(weed_manager)
	GameManager.staff_manager = staff_manager
	GameManager.weed_manager = weed_manager
	panel = StaffPanel.new()
	add_child_autofree(panel)

func after_each() -> void:
	GameManager.staff_manager = _previous_staff_manager
	GameManager.weed_manager = _previous_weed_manager

func test_builds_only_hire_and_current_staff_sections() -> void:
	assert_eq(panel._hire_buttons.size(), 8, "Two hire buttons per job type")
	assert_not_null(panel._roster_container)
	assert_string_contains(panel._payroll_label.text, "$0")
	assert_string_contains(panel._weed_label.text, "0")
	assert_eq(panel._roster_container.get_child_count(), 1)
	assert_eq(panel._roster_container.get_child(0).text, "No staff hired")

	var titles: Array[String] = []
	for label in panel.find_children("*", "Label", true, false):
		titles.append(label.text)
	assert_true(titles.has("HIRE STAFF"), "Hire section belongs in the tab")
	assert_true(titles.has("CURRENT STAFF"), "Roster section belongs in the tab")
	assert_false(titles.has("CONDITION"), "Condition section was removed")
	assert_false(titles.has("EFFECTS"), "Effects section was removed")
	assert_false(titles.has("Staff Management"), "Title/close chrome belonged to the old popup")

func test_every_job_offers_standard_and_premium() -> void:
	for job in [
		StaffManager.Job.GROUNDSKEEPER,
		StaffManager.Job.GREETER,
		StaffManager.Job.MARSHAL,
		StaffManager.Job.DRINKS_VENDOR,
	]:
		var types: Array = staff_manager.get_types_for_job(job)
		assert_eq(types.size(), 2, "Each job has a standard and a premium type")
		for staff_type in types:
			assert_true(panel._hire_buttons.has(staff_type),
				"Job %d should offer a hire button for type %d" % [job, staff_type])
			assert_string_contains(panel._hire_buttons[staff_type].text,
				StaffManager.STAFF_DATA[staff_type].name)

func test_premium_hire_is_more_expensive_and_better() -> void:
	for job in [
		StaffManager.Job.GROUNDSKEEPER,
		StaffManager.Job.GREETER,
		StaffManager.Job.MARSHAL,
		StaffManager.Job.DRINKS_VENDOR,
	]:
		var types: Array = staff_manager.get_types_for_job(job)
		var standard: Dictionary = StaffManager.STAFF_DATA[types[0]]
		var premium: Dictionary = StaffManager.STAFF_DATA[types[1]]
		assert_gt(premium.base_salary, standard.base_salary, "Premium costs more")
		assert_gt(premium.area_radius, standard.area_radius, "Premium covers more ground")
		assert_gt(premium.move_speed, standard.move_speed, "Premium moves faster")
		assert_gt(premium.work_speed, standard.work_speed, "Premium works faster")

func test_hiring_adds_a_roster_row_and_updates_payroll() -> void:
	panel._on_hire_pressed(StaffManager.StaffType.GROUNDSKEEPER)
	assert_eq(staff_manager.hired_staff.size(), 1)
	assert_eq(staff_manager.get_daily_payroll(),
		StaffManager.STAFF_DATA[StaffManager.StaffType.GROUNDSKEEPER].base_salary)
	assert_string_contains(panel._payroll_label.text, "$%d" % staff_manager.get_daily_payroll())
	assert_eq(panel._roster_container.get_child_count(), 1)
	var row = panel._roster_container.get_child(0)
	assert_true(row is HBoxContainer)
	var buttons = row.find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 2, "Each row has Move Area and Fire")
	assert_eq(buttons[0].text, "Area")
	assert_eq(buttons[1].text, "Fire")
	assert_string_contains(panel._hire_buttons[StaffManager.StaffType.GROUNDSKEEPER].text, "×1")

func test_firing_clears_the_roster() -> void:
	panel._on_hire_pressed(StaffManager.StaffType.RANGER)
	panel._on_hire_pressed(StaffManager.StaffType.SODA_VENDOR)
	assert_eq(staff_manager.hired_staff.size(), 2)
	panel._on_fire_pressed(0)
	assert_eq(staff_manager.hired_staff.size(), 1)
	assert_eq(panel._roster_container.get_child_count(), 1)
	panel._on_fire_pressed(0)
	assert_eq(staff_manager.hired_staff.size(), 0)
	assert_eq(panel._roster_container.get_child(0).text, "No staff hired")
	assert_string_contains(panel._payroll_label.text, "$0")

func test_move_area_button_requests_area_mode() -> void:
	panel._on_hire_pressed(StaffManager.StaffType.TECHNICIAN)
	watch_signals(panel)
	panel._on_area_pressed(0)
	assert_signal_emitted_with_parameters(panel, "area_move_requested", [0])
	assert_eq(panel._area_mode_index, 0)
	# Pressing the same row again cancels the mode.
	panel._on_area_pressed(0)
	assert_signal_emitted_with_parameters(panel, "area_move_requested", [-1])
	assert_eq(panel._area_mode_index, -1)

func test_weed_count_is_surfaced_for_groundskeepers() -> void:
	weed_manager.growth[Vector2i(3, 4)] = 0.5
	weed_manager.growth[Vector2i(9, 9)] = 0.4
	panel.refresh()
	assert_string_contains(panel._weed_label.text, "2")
	assert_eq(staff_manager.get_weed_count(), 2)

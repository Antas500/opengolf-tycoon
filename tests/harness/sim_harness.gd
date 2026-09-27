extends Node
## Headless smoke-test harness: boots the real game, quick-starts a course,
## simulates many in-game days at ULTRA speed, exercises UI panels, view
## rotation, save/load — anything that would surface runtime errors/warnings.
##
## Run:  godot --headless --path . res://tests/harness/sim_harness.tscn

const DAYS_TO_SIMULATE := 12
const FRAMES_PER_DAY := 500

var main: Node2D


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await _frames(10)
	print("HARNESS: quick-starting new game")
	main._on_main_menu_quick_start("Harness Course", 0)
	await _frames(60)

	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.ULTRA)

	await _exercise_staff()

	for day in range(DAYS_TO_SIMULATE):
		print("HARNESS: === day %d ===" % GameManager.current_day)
		await _exercise_panels(day)
		await _exercise_staff_day(day)
		await _frames(FRAMES_PER_DAY)

		# Force the day to close like a player fast-forwarding, then let the
		# regular end-of-day flow (summary -> continue) run.
		if not GameManager.is_end_of_day_pending():
			GameManager.force_end_day()
		await _frames(120)
		var hud: Control = main.get_node("UI/HUD")
		var summary: Control = hud.get_node_or_null("EndOfDaySummary")
		if summary:
			summary.continue_pressed.emit()
		else:
			GameManager.advance_to_next_day()
		await _frames(30)

		if day == 5:
			print("HARNESS: saving game")
			SaveManager.save_game("harness_slot")
			await _frames(30)
		if day == 8:
			print("HARNESS: loading game")
			SaveManager.load_game("harness_slot")
			await _frames(60)
			GameManager.set_mode(GameManager.GameMode.SIMULATING)
			GameManager.set_speed(GameManager.GameSpeed.ULTRA)

	print("HARNESS: done, quitting")
	SaveManager.delete_save("harness_slot")
	await _frames(5)
	get_tree().quit(0)


## Hire one of every staff type and confirm each gets a body on the course.
func _exercise_staff() -> void:
	print("HARNESS: hiring one of every staff type")
	var staff_manager: StaffManager = GameManager.staff_manager
	for staff_type in [
		StaffManager.StaffType.GROUNDSKEEPER,
		StaffManager.StaffType.TECHNICIAN,
		StaffManager.StaffType.CLUB_PRO,
		StaffManager.StaffType.CELEBRITY,
		StaffManager.StaffType.RANGER,
		StaffManager.StaffType.MARSHALL,
		StaffManager.StaffType.SODA_VENDOR,
		StaffManager.StaffType.CART_REFRESHER,
	]:
		staff_manager.hire_staff(staff_type)
	await _frames(20)
	if main.staff_container.get_child_count() != staff_manager.hired_staff.size():
		push_error("HARNESS: staff bodies (%d) do not match the roster (%d)" % [
			main.staff_container.get_child_count(), staff_manager.hired_staff.size()])
	# Move the first employee's area across the course, then show the Staff tab.
	main._on_staff_area_move_requested(0)
	main._handle_staff_area_click(Vector2i(74, 64))
	await _frames(5)
	main.terrain_toolbar.select_tab(TerrainToolbar.Tab.STAFF)
	await _frames(5)

## Each day: nudge an area, then let weeds/condition tick over.
func _exercise_staff_day(day: int) -> void:
	var staff_manager: StaffManager = GameManager.staff_manager
	if staff_manager.hired_staff.is_empty():
		return
	print("HARNESS: staff day %d (weeds %d)" % [day, staff_manager.get_weed_count()])
	main._on_staff_area_move_requested(day % staff_manager.hired_staff.size())
	main._handle_staff_area_click(Vector2i(60 + day, 64 + day))
	await _frames(5)

func _exercise_panels(day: int) -> void:
	# Rotate through panels a couple at a time so each gets exercised without
	# piling them all on screen at once.
	var toggles: Array[StringName] = [
		&"_toggle_analytics_panel",
		&"_toggle_milestones_panel",
		&"_toggle_course_scorecard_panel",
		&"_toggle_course_rating_panel",
		&"_toggle_event_feed",
		&"_toggle_land_panel",
		&"_toggle_marketing_panel",
		&"_toggle_tournament_panel",
		&"_toggle_seasonal_calendar",
		&"_toggle_hotkey_panel",
		&"_toggle_weather_debug_panel",
		&"_toggle_season_debug_panel",
		&"_toggle_terrain_debug_overlay",
	]
	var a: StringName = toggles[day % toggles.size()]
	var b: StringName = toggles[(day * 5 + 3) % toggles.size()]
	for fn: StringName in [a, b]:
		print("HARNESS: toggle ", fn)
		main.call(fn)
		await _frames(5)
		main.call(fn)
		await _frames(5)

	# View rotation + minimap.
	main._on_view_rotate_cw()
	await _frames(5)
	main._on_view_rotate_cw()
	await _frames(5)
	main._on_view_rotate_ccw()
	await _frames(5)
	main._on_map_toggled(true)
	await _frames(5)
	main._on_map_toggled(false)
	await _frames(5)

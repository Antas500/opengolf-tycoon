extends SceneTree
## End-to-end check that hiring staff puts them on the course.
##
## Boots the real game, quick-starts a course, hires one of each job category,
## moves a designated area, then confirms the groundskeeper walks to a weed
## inside that area and pulls it.
##
## Note: this script deliberately avoids referencing autoload/class_name globals
## (GameManager.…, StaffManager.…) in its own source. A `-s` SceneTree script is
## compiled before the autoloads are registered, so those identifiers would fail
## to resolve. Everything is reached through `root.get_node(...)` instead.
##
## Run:  godot --headless --path . -s tests/integration/staff_on_course.gd

var main: Node

func _initialize() -> void:
	call_deferred("run")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	seed(90210)
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._on_main_menu_quick_start("Staff Course", 0)
	await _frames(10)

	var gm = root.get_node("GameManager")
	var staff_manager = gm.staff_manager
	assert(gm.weed_manager != null, "WeedManager should be wired")
	gm.set_mode(gm.GameMode.SIMULATING)
	gm.set_speed(gm.GameSpeed.ULTRA)

	# Hire one of each job category and confirm bodies appear on the course.
	for staff_type in [
		staff_manager.StaffType.GROUNDSKEEPER,
		staff_manager.StaffType.CELEBRITY,
		staff_manager.StaffType.RANGER,
		staff_manager.StaffType.SODA_VENDOR,
	]:
		assert(staff_manager.hire_staff(staff_type), "Hire should succeed")
	await _frames(10)
	assert(main.staff_container.get_child_count() == 4,
		"Every hire should get a body on the course, got %d" % main.staff_container.get_child_count())

	# Move the groundskeeper's designated area onto an open tile.
	var groundskeeper_index = 0
	main._on_staff_area_move_requested(groundskeeper_index)
	assert(main._staff_area_mode_index == groundskeeper_index, "Area mode should engage")
	var target_tile := Vector2i(8, 8)
	main._handle_staff_area_click(target_tile)
	assert(staff_manager.get_staff_area(groundskeeper_index) == target_tile,
		"Designated area should move to the clicked tile")
	assert(main._staff_area_mode_index == -1, "Area mode should end after the click")

	# Put a weed right where the groundskeeper is assigned and let them work.
	assert(gm.weed_manager.spawn_weed(target_tile, 0.5))
	var record: Dictionary = staff_manager.hired_staff[groundskeeper_index]
	var entity = staff_manager.get_entity(int(record.staff_id))
	assert(entity != null, "Groundskeeper should have a body")
	entity.global_position = gm.terrain_grid.grid_to_screen_center(target_tile)

	var deadline: int = Time.get_ticks_msec() + 30000
	while gm.weed_manager.has_weed(target_tile) and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(not gm.weed_manager.has_weed(target_tile),
		"Groundskeeper should have walked over and pulled the weed")

	# Firing removes the body from the course.
	var before: int = main.staff_container.get_child_count()
	assert(staff_manager.fire_staff(groundskeeper_index))
	await _frames(3)
	assert(main.staff_container.get_child_count() < before, "Fired staff leave the course")

	print("STAFF_ON_COURSE_OK")
	quit(0)

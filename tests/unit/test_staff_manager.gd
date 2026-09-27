extends GutTest
## Tests for the reworked StaffManager: job types, two tiers per job, designated
## areas, payroll, pace effect and weed-driven course condition.

var _previous_staff_manager
var _previous_weed_manager
var staff_manager: StaffManager
var weed_manager: WeedManager
var grid: TerrainGrid

func before_each() -> void:
	_previous_staff_manager = GameManager.staff_manager
	_previous_weed_manager = GameManager.weed_manager
	staff_manager = StaffManager.new()
	add_child_autofree(staff_manager)
	weed_manager = WeedManager.new()
	add_child_autofree(weed_manager)
	GameManager.staff_manager = staff_manager
	GameManager.weed_manager = weed_manager

	grid = TerrainGrid.new()
	grid.grid_width = 24
	grid.grid_height = 24
	add_child_autofree(grid)
	for x in range(24):
		for y in range(24):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.FAIRWAY)
	weed_manager.setup(grid, null)

func after_each() -> void:
	GameManager.staff_manager = _previous_staff_manager
	GameManager.weed_manager = _previous_weed_manager

# --- Job / tier data ---------------------------------------------------------

func test_every_job_has_two_staff_types() -> void:
	assert_eq(StaffManager.STAFF_DATA.size(), 8, "Four jobs x two staff types")
	for job in [
		StaffManager.Job.GROUNDSKEEPER,
		StaffManager.Job.GREETER,
		StaffManager.Job.MARSHAL,
		StaffManager.Job.DRINKS_VENDOR,
	]:
		var types: Array = staff_manager.get_types_for_job(job)
		assert_eq(types.size(), 2)
		assert_eq(staff_manager.get_job_for_type(types[0]), job)
		assert_eq(staff_manager.get_job_for_type(types[1]), job)

func test_premium_outperforms_standard_for_every_job() -> void:
	for job in [
		StaffManager.Job.GROUNDSKEEPER,
		StaffManager.Job.GREETER,
		StaffManager.Job.MARSHAL,
		StaffManager.Job.DRINKS_VENDOR,
	]:
		var types: Array = staff_manager.get_types_for_job(job)
		var standard: Dictionary = StaffManager.STAFF_DATA[types[0]]
		var premium: Dictionary = StaffManager.STAFF_DATA[types[1]]
		assert_eq(int(standard.tier), StaffManager.Tier.STANDARD)
		assert_eq(int(premium.tier), StaffManager.Tier.PREMIUM)
		assert_gt(premium.base_salary, standard.base_salary)
		assert_gt(premium.area_radius, standard.area_radius)
		assert_gt(premium.move_speed, standard.move_speed)
		assert_gt(premium.work_speed, standard.work_speed)

# --- Hiring / firing / payroll ----------------------------------------------

func test_hire_adds_a_staff_member_with_an_area() -> void:
	assert_true(staff_manager.hire_staff(StaffManager.StaffType.CLUB_PRO))
	assert_eq(staff_manager.hired_staff.size(), 1)
	var record: Dictionary = staff_manager.hired_staff[0]
	assert_eq(int(record.type), StaffManager.StaffType.CLUB_PRO)
	assert_eq(int(record.salary), StaffManager.STAFF_DATA[StaffManager.StaffType.CLUB_PRO].base_salary)
	assert_almost_eq(float(record.area_radius),
		float(StaffManager.STAFF_DATA[StaffManager.StaffType.CLUB_PRO].area_radius), 0.001)
	assert_true(record.has("area_center"))

func test_hire_rejects_unknown_type() -> void:
	assert_false(staff_manager.hire_staff(999))

func test_fire_removes_and_updates_payroll() -> void:
	staff_manager.hire_staff(StaffManager.StaffType.GROUNDSKEEPER)
	staff_manager.hire_staff(StaffManager.StaffType.CELEBRITY)
	var payroll := staff_manager.get_daily_payroll()
	assert_true(payroll > 0)
	assert_true(staff_manager.fire_staff(0))
	assert_eq(staff_manager.hired_staff.size(), 1)
	assert_eq(staff_manager.get_daily_payroll(), payroll - StaffManager.STAFF_DATA[StaffManager.StaffType.GROUNDSKEEPER].base_salary)
	assert_false(staff_manager.fire_staff(5))

func test_counts_by_job_and_tier() -> void:
	staff_manager.hire_staff(StaffManager.StaffType.RANGER)
	staff_manager.hire_staff(StaffManager.StaffType.MARSHALL)
	staff_manager.hire_staff(StaffManager.StaffType.SODA_VENDOR)
	assert_eq(staff_manager.get_staff_count_by_job(StaffManager.Job.MARSHAL), 2)
	assert_eq(staff_manager.get_staff_count_by_job(StaffManager.Job.DRINKS_VENDOR), 1)
	assert_eq(staff_manager.get_staff_count_by_tier(StaffManager.Tier.PREMIUM), 1)
	assert_eq(staff_manager.get_staff_count_by_tier(StaffManager.Tier.STANDARD), 2)

# --- Designated areas --------------------------------------------------------

func test_move_staff_area_sets_the_center() -> void:
	staff_manager.hire_staff(StaffManager.StaffType.TECHNICIAN)
	assert_true(staff_manager.move_staff_area(0, Vector2i(3, 7)))
	assert_eq(staff_manager.get_staff_area(0), Vector2i(3, 7))
	assert_false(staff_manager.move_staff_area(4, Vector2i(1, 1)))

# --- Pace effect -------------------------------------------------------------

func test_marshals_raise_the_pace_modifier() -> void:
	var base := staff_manager.get_pace_modifier()
	staff_manager.hire_staff(StaffManager.StaffType.RANGER)
	var with_ranger := staff_manager.get_pace_modifier()
	assert_gt(with_ranger, base)
	staff_manager.hire_staff(StaffManager.StaffType.MARSHALL)
	assert_gt(staff_manager.get_pace_modifier(), with_ranger)
	assert_lte(staff_manager.get_pace_modifier(), 1.0)

func test_non_marshals_do_not_change_pace() -> void:
	var base := staff_manager.get_pace_modifier()
	staff_manager.hire_staff(StaffManager.StaffType.CELEBRITY)
	staff_manager.hire_staff(StaffManager.StaffType.CART_REFRESHER)
	assert_almost_eq(staff_manager.get_pace_modifier(), base, 0.0001)

# --- Course condition follows weeds -----------------------------------------

func test_no_weeds_means_pristine_condition() -> void:
	staff_manager.process_daily_maintenance()
	assert_almost_eq(staff_manager.course_condition, 1.0, 0.001)

func test_weeds_lower_condition_without_groundskeepers() -> void:
	for i in 10:
		weed_manager.spawn_weed(Vector2i(i, 0), 0.5)
	staff_manager.process_daily_maintenance()
	assert_lt(staff_manager.course_condition, 1.0,
		"Unmanaged weeds must drag the course condition down")

func test_groundskeepers_soften_the_weed_penalty() -> void:
	for i in 10:
		weed_manager.spawn_weed(Vector2i(i, 0), 0.5)
	var unstaffed: StaffManager = StaffManager.new()
	add_child_autofree(unstaffed)
	unstaffed.weed_manager = weed_manager
	unstaffed.process_daily_maintenance()

	staff_manager.hire_staff(StaffManager.StaffType.GROUNDSKEEPER)
	staff_manager.process_daily_maintenance()
	assert_gt(staff_manager.course_condition, unstaffed.course_condition,
		"A hired groundskeeper should improve the outcome")

func test_condition_description_bands() -> void:
	staff_manager.course_condition = 0.95
	assert_eq(staff_manager.get_condition_description(), "Pristine")
	staff_manager.course_condition = 0.8
	assert_eq(staff_manager.get_condition_description(), "Good")
	staff_manager.course_condition = 0.6
	assert_eq(staff_manager.get_condition_description(), "Fair")
	staff_manager.course_condition = 0.4
	assert_eq(staff_manager.get_condition_description(), "Poor")
	staff_manager.course_condition = 0.1
	assert_eq(staff_manager.get_condition_description(), "Terrible")

# --- Serialization -----------------------------------------------------------

func test_serialize_round_trip_keeps_roster_and_areas() -> void:
	staff_manager.hire_staff(StaffManager.StaffType.CELEBRITY)
	staff_manager.hire_staff(StaffManager.StaffType.SODA_VENDOR)
	staff_manager.move_staff_area(0, Vector2i(11, 12))
	staff_manager.course_condition = 0.42
	var data := staff_manager.serialize()

	var restored: StaffManager = StaffManager.new()
	add_child_autofree(restored)
	restored.weed_manager = weed_manager
	restored.deserialize(data)

	assert_eq(restored.hired_staff.size(), 2)
	assert_eq(int(restored.hired_staff[0].type), StaffManager.StaffType.CELEBRITY)
	assert_eq(restored.get_staff_area(0), Vector2i(11, 12))
	assert_almost_eq(restored.course_condition, 0.42, 0.001)
	assert_eq(restored.get_daily_payroll(), staff_manager.get_daily_payroll())

func test_clear_all_staff_empties_the_roster() -> void:
	staff_manager.hire_staff(StaffManager.StaffType.RANGER)
	staff_manager.clear_all_staff()
	assert_eq(staff_manager.hired_staff.size(), 0)
	assert_eq(staff_manager.get_daily_payroll(), 0)
	assert_eq(staff_manager.course_condition, 1.0)
	assert_eq(staff_manager.next_staff_id, 1)

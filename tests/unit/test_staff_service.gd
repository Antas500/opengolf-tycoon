extends GutTest
## Tests for on-course staff serving golfers: greeters cheer, marshals restore
## pace, drinks vendors quench thirst — and each service respects a cooldown.

func _make_golfer() -> Golfer:
	var golfer := Golfer.new()
	golfer.golfer_id = 900 + randi() % 100
	golfer.golfer_name = "Guest"
	golfer.current_mood = 0.5
	golfer.needs = GolferNeeds.new()
	golfer.needs.setup(GolferTier.Tier.CASUAL, 0.5)
	return golfer

func test_greeter_cheers_a_golfer_up() -> void:
	var golfer: Golfer = autofree(_make_golfer())
	var before: float = golfer.current_mood
	golfer.receive_greeting(0.08)
	assert_gt(golfer.current_mood, before, "A greeting should lift the golfer's mood")

func test_greeter_service_sets_a_cooldown() -> void:
	var golfer: Golfer = autofree(_make_golfer())
	golfer.receive_greeting(0.08)
	assert_gt(golfer.staff_help_cooldown, 0.0)
	assert_false(golfer.is_staff_service_available(), "A fresh service blocks repeats")

func test_marshal_restores_pace() -> void:
	var golfer: Golfer = autofree(_make_golfer())
	golfer.needs.pace = 0.1
	golfer.receive_pace_help(0.35)
	assert_gt(golfer.needs.pace, 0.1, "A marshal should get the group moving again")

func test_vendor_quenches_thirst() -> void:
	var golfer: Golfer = autofree(_make_golfer())
	golfer.needs.thirst = 0.2
	var before: float = golfer.current_mood
	golfer.receive_drink(0.5)
	assert_gt(golfer.needs.thirst, 0.2, "A drinks vendor should quench thirst")
	assert_gt(golfer.current_mood, before, "and leave the golfer happier")

func test_cooldown_blocks_a_second_service() -> void:
	var golfer: Golfer = autofree(_make_golfer())
	golfer.needs.thirst = 0.2
	golfer.receive_drink(0.5)
	var after_first: float = golfer.needs.thirst
	golfer.receive_drink(0.5)
	assert_almost_eq(golfer.needs.thirst, after_first, 0.0001,
		"Stacked vendors should not double-serve the same golfer")

func test_staff_member_services_a_golfer_in_range() -> void:
	# A staff member's job completion routes through the golfer's service method.
	var golfer: Golfer = autofree(_make_golfer())
	golfer.needs.thirst = 0.2
	var member: StaffMember = autofree(StaffMember.new())
	member.job = StaffManager.Job.DRINKS_VENDOR
	member.effect = 0.5
	member.work_speed = 1.0
	member._work_golfer = golfer
	member.set_terrain_grid(_identity_grid())
	member.global_position = Vector2.ZERO
	golfer.global_position = Vector2.ZERO
	member._service_golfer("receive_drink")
	assert_gt(golfer.needs.thirst, 0.2, "Service in range should land")

func test_staff_member_ignores_a_golfer_out_of_range() -> void:
	var golfer: Golfer = autofree(_make_golfer())
	golfer.needs.thirst = 0.2
	var member: StaffMember = autofree(StaffMember.new())
	member.job = StaffManager.Job.DRINKS_VENDOR
	member.effect = 0.5
	member.set_terrain_grid(_identity_grid())
	member.global_position = Vector2.ZERO
	golfer.global_position = Vector2(500, 500)
	member._service_golfer("receive_drink")
	assert_almost_eq(golfer.needs.thirst, 0.2, 0.0001, "Too far away means no service")

## A 1:1 grid/world projection so screen_to_grid_point is the identity.
func _identity_grid() -> TerrainGrid:
	var grid := TerrainGrid.new()
	grid.grid_width = 64
	grid.grid_height = 64
	add_child_autofree(grid)
	return grid

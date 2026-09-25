extends GutTest

func test_initial_budget_and_refund() -> void:
	var profile := PlayerGolferProfile.new()
	assert_eq(profile.remaining(), 10)
	for i in 10:
		assert_true(profile.allocate(i, 1))
	assert_eq(profile.remaining(), 0)
	assert_false(profile.allocate(0, 1))
	assert_almost_eq(profile.bonus(0), 0.1, 0.0001)
	assert_true(profile.allocate(0, -1))
	assert_false(profile.allocate(0, -1))
	assert_true(profile.allocate(1, 1))

func test_locked_profile_and_round_trip() -> void:
	var profile := PlayerGolferProfile.new()
	profile.allocate(4, 1)
	profile.golfer_name = "My Golfer"
	profile.appearance.shirt_color = "123456"
	profile.initialized = true
	var loaded := PlayerGolferProfile.from_data(JSON.parse_string(JSON.stringify(profile.serialize())))
	assert_eq(loaded.golfer_name, "My Golfer")
	assert_eq(loaded.appearance.shirt_color, "123456")
	assert_eq(loaded.points[4], 1)
	assert_false(loaded.allocate(4, 1))
	assert_gt(loaded.normalized_skill(4), 0.5)

func test_legacy_save_and_skill_caps() -> void:
	var profile := PlayerGolferProfile.from_data({})
	assert_false(profile.initialized)
	assert_eq(profile.remaining(), 10)
	profile = PlayerGolferProfile.from_data({"initialized": true, "points": [1000, -5, 0, 0, 0, 0, 0, 0, 0, 0]})
	assert_eq(profile.points[0] * 10, 990)
	assert_eq(profile.points[1], 0)
	assert_lt(profile.normalized_skill(0), 1.0)

func test_uninitialized_save_cannot_exceed_budget() -> void:
	var profile := PlayerGolferProfile.from_data({"points": [99, 99, 99, 99, 99, 99, 99, 99, 99, 99]})
	assert_eq(profile.points[0], 10)
	assert_eq(profile.points[1], 0)
	assert_eq(profile.remaining(), 0)

func test_special_shapes_only_on_tee_and_fairway() -> void:
	for terrain in TerrainTypes.Type.values():
		assert_true(Golfer.shape_allowed(0, terrain))
		for shape in [1, 2, 3]:
			assert_eq(Golfer.shape_allowed(shape, terrain), terrain in [TerrainTypes.Type.TEE_BOX,
				TerrainTypes.Type.FAIRWAY, TerrainTypes.Type.FIRM_FAIRWAY])
	assert_false(Golfer.shape_allowed(4, TerrainTypes.Type.FAIRWAY))

func test_player_waits_off_green_but_putting_is_automatic() -> void:
	var saved_grid = GameManager.terrain_grid
	var grid: TerrainGrid = autofree(TerrainGrid.new())
	GameManager.terrain_grid = grid
	var golfer: Golfer = autofree(Golfer.new())
	golfer.player_profile = PlayerGolferProfile.new()
	golfer.ball_position = Vector2i(10, 10)
	golfer.ball_position_precise = Vector2(10, 10)
	golfer.current_state = Golfer.State.PREPARING_SHOT
	grid._grid[golfer.ball_position] = TerrainTypes.Type.FAIRWAY
	assert_true(golfer.awaits_player_shot())
	golfer._process_preparing_shot(100.0)
	assert_eq(golfer.current_strokes, 0)
	assert_eq(golfer.preparation_time, 0.0)
	grid._grid[golfer.ball_position] = TerrainTypes.Type.GREEN
	assert_false(golfer.awaits_player_shot())
	golfer.current_state = Golfer.State.WATCHING
	grid._grid[golfer.ball_position] = TerrainTypes.Type.FAIRWAY
	assert_false(golfer.awaits_player_shot())
	assert_false(golfer.play_shot(Vector2i(15, 10)))
	GameManager.terrain_grid = saved_grid

func test_player_range_power_and_punch() -> void:
	var saved_grid = GameManager.terrain_grid
	var grid: TerrainGrid = autofree(TerrainGrid.new())
	GameManager.terrain_grid = grid
	var golfer: Golfer = autofree(Golfer.new())
	golfer.player_profile = PlayerGolferProfile.new()
	golfer.ball_position = Vector2i(10, 10)
	grid._grid[golfer.ball_position] = TerrainTypes.Type.TEE_BOX
	var target := Vector2i(60, 10)
	var normal := golfer.player_aim(target).x
	golfer.player_profile.allocate(0, 1)
	golfer.player_profile.allocate(1, 1)
	assert_gt(golfer.player_aim(target).x, normal)
	golfer.player_punch = true
	assert_lt(golfer.player_aim(target).x, normal)
	GameManager.terrain_grid = saved_grid

func _fill_fairway(grid: TerrainGrid, size: int = 60) -> void:
	for x in range(size):
		for y in range(size):
			grid._grid[Vector2i(x, y)] = TerrainTypes.Type.FAIRWAY

func _ready_preview_golfer(grid: TerrainGrid, terrain: int) -> Golfer:
	var golfer: Golfer = autofree(Golfer.new())
	golfer.player_profile = PlayerGolferProfile.new()
	golfer.ball_position = Vector2i(10, 10)
	golfer.ball_position_precise = Vector2(10, 10)
	golfer.current_state = Golfer.State.PREPARING_SHOT
	grid._grid[golfer.ball_position] = terrain
	return golfer

func test_shot_preview_is_deterministic_and_matches_execution() -> void:
	var saved_grid = GameManager.terrain_grid
	var grid: TerrainGrid = autofree(TerrainGrid.new())
	_fill_fairway(grid)
	GameManager.terrain_grid = grid
	var golfer := _ready_preview_golfer(grid, TerrainTypes.Type.TEE_BOX)
	var target := Vector2i(10, 34)
	var preview := golfer.preview_shot(target)
	assert_false(preview.is_empty(), "Owner aiming off the green gets a preview")
	assert_eq(preview.club_name, "Driver")
	assert_true(preview.clamped, "Aim past the club's range is reported as clamped")
	assert_almost_eq(preview.aim.distance_to(preview.origin), preview.max_range, 0.75, "Aim is clamped to the club range")

	# Deterministic: the same aim always yields the same arc and roll.
	var repeat := golfer.preview_shot(target)
	assert_eq(preview.carry, repeat.carry, "Carry has no random miss")
	assert_eq(preview.rest, repeat.rest, "Roll has no random variance")
	assert_eq(preview.roll_path.size(), repeat.roll_path.size())
	assert_eq(preview.roll_path[preview.roll_path.size() - 1], repeat.roll_path[repeat.roll_path.size() - 1])

	# It is the execution model with the error terms zeroed, not a copy of it.
	var shot := golfer._calculate_shot(golfer.ball_position, Vector2i(preview.aim), true)
	assert_eq(preview.carry, shot.carry_position_precise)
	assert_eq(preview.rest, shot.landing_position_precise)

	# Arc and roll are coherent: straight aim, carry on the line, roll past it.
	assert_almost_eq(preview.carry.x, preview.origin.x, 0.05, "Straight shot carries on the aim line")
	assert_gt(preview.carry.distance_to(preview.origin), 0.0)
	assert_gt(preview.rest.distance_to(preview.origin), preview.carry.distance_to(preview.origin), "Ball rolls forward")
	assert_almost_eq(preview.roll_path[0].distance_to(preview.carry), 0.0, 0.001, "Roll trail starts at the carry point")
	assert_almost_eq(preview.roll_path[preview.roll_path.size() - 1].distance_to(preview.rest), 0.0, 0.001)
	assert_gt(preview.carry_yards, 0)
	assert_gt(preview.roll_yards, 0)
	# Out-of-range aim still shows the clamped shot, and the mouse target it came from.
	assert_gt(preview.raw_target.distance_to(preview.origin), preview.aim.distance_to(preview.origin),
		"Raw mouse target sits beyond the clamped aim point")

func test_preview_ignores_shank_and_miss_tendency() -> void:
	var saved_grid = GameManager.terrain_grid
	var grid: TerrainGrid = autofree(TerrainGrid.new())
	_fill_fairway(grid)
	GameManager.terrain_grid = grid
	var golfer := _ready_preview_golfer(grid, TerrainTypes.Type.TEE_BOX)
	golfer.miss_tendency = 1.0  # worst slice bias
	var target := Vector2i(10, 22)
	var preview := golfer.preview_shot(target)
	var shot := golfer._calculate_shot(golfer.ball_position, Vector2i(preview.aim), true)
	assert_almost_eq(float(shot.miss_angle_deg), 0.0, 0.0001, "Previewed shot carries no miss angle")
	assert_false(shot.is_shank, "Previewed shot cannot be a shank")
	assert_almost_eq(preview.carry.x, preview.origin.x, 0.05, "Preview lands on the aim line despite the slice tendency")
	GameManager.terrain_grid = saved_grid

func test_preview_reflects_shapes_punch_and_backspin() -> void:
	var saved_grid = GameManager.terrain_grid
	var saved_wind = GameManager.wind_system
	GameManager.wind_system = null
	var grid: TerrainGrid = autofree(TerrainGrid.new())
	_fill_fairway(grid)
	GameManager.terrain_grid = grid
	var golfer := _ready_preview_golfer(grid, TerrainTypes.Type.FAIRWAY)
	var target := Vector2i(10, 20)

	var straight := golfer.preview_shot(target)
	assert_almost_eq(float(straight.shape_bend_deg), 0.0, 0.001)

	golfer.player_shape = 2  # draw (R to L)
	var draw := golfer.preview_shot(target)
	assert_almost_eq(float(draw.shape_bend_deg), -8.0, 0.001)
	assert_ne(draw.carry, straight.carry, "A draw bends the landing point")
	golfer.player_shape = 1  # fade (L to R)
	var fade := golfer.preview_shot(target)
	assert_almost_eq(float(fade.shape_bend_deg), 8.0, 0.001)
	var fade_carry: Vector2 = fade.carry
	var draw_carry: Vector2 = draw.carry
	var straight_carry: Vector2 = straight.carry
	var mirrored := (fade_carry + draw_carry) * 0.5
	# Mirroring is exact on the circle; the midpoint sits cos(8°) along the aim line.
	assert_almost_eq(mirrored.x, straight_carry.x, 0.15, "Fade and draw mirror each other")
	assert_almost_eq(mirrored.y, straight_carry.y, 0.15)
	assert_gt(fade_carry.distance_to(straight_carry), 0.1, "Fade visibly bends off the straight line")

	golfer.player_shape = 3  # high backspin
	var backspin := golfer.preview_shot(target)
	assert_true(backspin.is_backspin, "Backspin shape spins the ball back")
	assert_gt(float(backspin.arc_scale), 1.0, "Backspin raises the arc")
	assert_lt(backspin.rest.distance_to(backspin.origin), backspin.carry.distance_to(backspin.origin),
		"Backspin rolls backwards toward the ball")
	assert_eq(backspin.roll_path.size(), 2, "Backspin rolls straight back along the shot line")

	golfer.player_shape = 0
	golfer.player_punch = true
	var punch := golfer.preview_shot(target)
	assert_lt(float(punch.arc_scale), 1.0, "Punch flattens the arc")
	assert_lt(punch.carry.distance_to(punch.origin), straight.carry.distance_to(straight.origin), "Punch is shorter")
	var straight_ratio: float = straight.rollout_tiles / straight.carry.distance_to(straight.origin)
	var punch_ratio: float = punch.rollout_tiles / punch.carry.distance_to(punch.origin)
	assert_almost_eq(punch_ratio, straight_ratio * 1.5, 0.05, "Punch rolls out 150% of the normal roll")
	GameManager.wind_system = saved_wind
	GameManager.terrain_grid = saved_grid

func test_preview_unavailable_outside_the_owner_turn() -> void:
	var saved_grid = GameManager.terrain_grid
	var grid: TerrainGrid = autofree(TerrainGrid.new())
	_fill_fairway(grid)
	GameManager.terrain_grid = grid
	var golfer := _ready_preview_golfer(grid, TerrainTypes.Type.FAIRWAY)
	assert_false(golfer.preview_shot(Vector2i(10, 20)).is_empty())
	golfer.current_state = Golfer.State.WALKING
	assert_true(golfer.preview_shot(Vector2i(10, 20)).is_empty(), "No guide while walking")
	golfer.current_state = Golfer.State.PREPARING_SHOT
	assert_true(golfer.preview_shot(Vector2i(-5, -5)).is_empty(), "No guide for off-map aim")
	assert_true(golfer.preview_shot(golfer.ball_position).is_empty(), "No guide aimed at the ball itself")
	# Shapes that the lie does not allow fall back to straight, as play_shot() does.
	grid._grid[golfer.ball_position] = TerrainTypes.Type.ROUGH
	golfer.player_shape = 1
	assert_almost_eq(float(golfer.preview_shot(Vector2i(10, 20)).shape_bend_deg), 0.0, 0.001)
	assert_eq(golfer.player_shape, 0, "Illegal shape resets on the guide preview")
	GameManager.terrain_grid = saved_grid

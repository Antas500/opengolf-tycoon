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
			assert_eq(Golfer.shape_allowed(shape, terrain), terrain in [TerrainTypes.Type.TEE_BOX, TerrainTypes.Type.FAIRWAY])
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

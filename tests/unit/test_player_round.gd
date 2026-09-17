extends GutTest
## Integration coverage with real golfer/ball scenes and the round UI.
var fixture: Node2D
var rounds: PlayerRoundManager
var golfers: GolferManager
var saved: Dictionary

func before_each() -> void:
	saved = {"course": GameManager.course_data, "grid": GameManager.terrain_grid,
		"profile": GameManager.player_profile, "mode": GameManager.current_mode,
		"speed": GameManager.current_speed, "paused": GameManager.is_paused,
		"tournament": GameManager.tournament_manager}
	GameManager.tournament_manager = null
	GameManager.is_paused = false
	GameManager.player_profile = PlayerGolferProfile.new()
	GameManager.current_course = GameManager.CourseData.new()
	var hole := GameManager.HoleData.new()
	hole.tee_position = Vector2i(10, 10)
	hole.hole_position = Vector2i(16, 10)
	hole.par = 3
	GameManager.course_data.add_hole(hole)
	var grid: TerrainGrid = autofree(TerrainGrid.new())
	for x in range(40):
		for y in range(40):
			grid._grid[Vector2i(x, y)] = TerrainTypes.Type.FAIRWAY
	grid._grid[hole.tee_position] = TerrainTypes.Type.TEE_BOX
	grid._grid[hole.hole_position] = TerrainTypes.Type.GREEN
	GameManager.terrain_grid = grid
	GameManager.set_mode(GameManager.GameMode.BUILDING)
	fixture = Node2D.new()
	add_child_autofree(fixture)
	var entities := Node2D.new()
	entities.name = "Entities"
	fixture.add_child(entities)
	for title in ["Golfers", "Balls"]:
		var container := Node2D.new()
		container.name = title
		entities.add_child(container)
	golfers = GolferManager.new()
	golfers.name = "GolferManager"
	fixture.add_child(golfers)
	var balls := BallManager.new()
	fixture.add_child(balls)
	balls.set_terrain_grid(grid)
	var camera := IsometricCamera.new()
	fixture.add_child(camera)
	var hud := Control.new()
	fixture.add_child(hud)
	rounds = PlayerRoundManager.new()
	fixture.add_child(rounds)
	rounds.setup(golfers, camera, hud)

func after_each() -> void:
	rounds.leave_round()
	golfers.clear_all_golfers()
	await get_tree().process_frame
	GameManager.current_course = saved.course
	GameManager.terrain_grid = saved.grid
	GameManager.player_profile = saved.profile
	GameManager.tournament_manager = saved.tournament
	GameManager.is_paused = saved.paused
	GameManager.set_mode(saved.mode)
	GameManager.set_speed(saved.speed)

func _start(kind: int) -> void:
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds.mode_picker.select(kind)
	rounds.start_round()
	rounds._process(0.0)

func test_setup_cancel_does_not_spend_points() -> void:
	rounds.open_setup()
	assert_true(rounds.start_button.disabled)
	rounds.draft.allocate(0, 1)
	rounds.leave_round()
	assert_false(GameManager.player_profile.initialized)
	assert_eq(GameManager.player_profile.remaining(), 10)

func test_practice_waits_for_input_and_restores_visitors() -> void:
	var visitor := golfers.spawn_tournament_golfer(GolferTier.Tier.CASUAL, 99)
	_start(0)
	assert_eq(rounds.participants.size(), 1)
	assert_true(rounds.player.awaits_player_shot())
	assert_eq(rounds.player.golfer_name, "Test Owner")
	assert_false(rounds.player._use_sprites)
	assert_eq(rounds.player.body.color, Color(GameManager.player_profile.appearance.shirt_color))
	assert_eq(visitor.process_mode, Node.PROCESS_MODE_DISABLED)
	rounds.player._process_preparing_shot(30)
	assert_eq(rounds.player.current_strokes, 0)
	rounds.leave_round()
	assert_eq(GameManager.current_mode, GameManager.GameMode.BUILDING)
	assert_eq(visitor.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_eq(golfers.active_golfers.size(), 1)
	assert_true(GameManager.player_profile.initialized)

func test_pro_selection_and_tournament_results() -> void:
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.mode_picker.select(1)
	rounds.pro_picker.select(2)
	rounds.start_round()
	assert_eq(rounds.participants.size(), 2)
	assert_eq(rounds.participants[1].golfer_name, "Pro Riley")
	rounds.leave_round()
	_start(2)
	assert_eq(rounds.participants.size(), 4)
	for golfer in rounds.participants:
		golfer.current_strokes = 3
		golfer.ball_position = Vector2i(16, 10)
		golfer.ball_position_precise = Vector2(16, 10)
		golfer.current_state = Golfer.State.IDLE
	rounds._process(0.0)
	assert_false(rounds.active)
	assert_true(rounds.busy)
	for golfer in rounds.participants:
		assert_eq(golfer.hole_scores.size(), 1)
		assert_eq(golfer.total_strokes, 3)
	assert_string_contains(rounds.content.get_child(1).text, "Tie:")
	rounds.leave_round()
	assert_eq(golfers.active_golfers.size(), 0)

func test_no_open_holes_rejected() -> void:
	GameManager.course_data.holes[0].is_open = false
	rounds.open_setup()
	assert_false(rounds.busy)

func test_mode_change_cleans_up_round() -> void:
	_start(0)
	GameManager.set_mode(GameManager.GameMode.MAIN_MENU)
	assert_false(rounds.busy)
	assert_eq(golfers.active_golfers.size(), 0)

func test_real_shot_rejects_double_click_and_round_can_finish() -> void:
	_start(0)
	var owner := rounds.player
	owner.walk_speed = 120
	assert_true(owner.play_shot(Vector2i(16, 10)))
	assert_false(owner.play_shot(Vector2i(16, 10)))
	assert_eq(owner.current_strokes, 1)
	# Exercise real swing, ball flight, rollout, walking, putting and pickup.
	Engine.time_scale = 3.0
	for step in 160:
		if not rounds.active:
			break
		if owner.awaits_player_shot():
			owner.play_shot(Vector2i(16, 10))
		await get_tree().create_timer(0.5).timeout
	Engine.time_scale = 1.0
	assert_false(rounds.active, "Real round reaches its results screen")
	assert_eq(owner.hole_scores.size(), 1)

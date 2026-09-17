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
	assert_eq(visitor.process_mode, Node.PROCESS_MODE_INHERIT, "Visitors are not disabled during round")
	assert_true(rounds.hud.visible, "Management HUD remains visible during play")
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
	assert_eq(rounds.participants[0].group_id, rounds.participants[1].group_id, "Participants share the same group ID")
	assert_true(rounds.hud.visible, "Management HUD is visible")
	rounds.leave_round()
	_start(2)
	assert_eq(rounds.participants.size(), 4)
	assert_eq(rounds.participants[0].group_id, rounds.participants[1].group_id)
	assert_eq(rounds.participants[1].group_id, rounds.participants[2].group_id)
	assert_eq(rounds.participants[2].group_id, rounds.participants[3].group_id)
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

func test_player_round_plays_as_group_with_etiquette() -> void:
	# Start a round vs a pro
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds.mode_picker.select(1)  # Vs Pro
	rounds.pro_picker.select(0)   # Pro Alex
	rounds.start_round()
	rounds._process(0.0)

	assert_eq(GameManager.current_mode, GameManager.GameMode.SIMULATING, "Game mode is SIMULATING")
	assert_true(rounds.hud.visible, "Management HUD is visible")
	assert_eq(rounds.participants.size(), 2)

	var p := rounds.player
	var pro := rounds.participants[1]

	# Both should have the same group_id
	assert_eq(p.group_id, pro.group_id, "Player and Pro share group_id")
	assert_gte(p.group_id, 0, "Group ID is a valid non-negative group ID")

	# Hole 1 tee off order: lowest golfer_id (player spawned first) has honor
	assert_eq(p.current_state, Golfer.State.PREPARING_SHOT, "Player has honor on Hole 1 tee")
	assert_true(p.awaits_player_shot(), "Player awaits input")
	assert_eq(pro.current_state, Golfer.State.IDLE, "Pro waits their turn on the tee")

	# Player takes tee shot
	assert_true(p.play_shot(Vector2i(14, 10)))
	assert_eq(p.current_strokes, 1)

	# While player is swinging/watching/walking, pro is next on tee
	# Advance pro to take tee shot
	p._change_state(Golfer.State.WALKING)
	golfers._update_golfers(0.0)
	assert_eq(pro.current_state, Golfer.State.PREPARING_SHOT, "Pro tees off next in group order")

	rounds.leave_round()

func test_concurrent_visitors_and_player_group() -> void:
	# Spawn a visitor group before player round
	var v1 := golfers.spawn_tournament_golfer(GolferTier.Tier.CASUAL, 10)
	var v2 := golfers.spawn_tournament_golfer(GolferTier.Tier.BEGINNER, 10)
	assert_eq(golfers.active_golfers.size(), 2)

	# Start owner round vs pro
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.mode_picker.select(1)
	rounds.start_round()
	rounds._process(0.0)

	# Both groups should coexist in active_golfers
	assert_eq(golfers.active_golfers.size(), 4, "4 golfers total (2 visitors + 2 player group)")
	assert_eq(v1.process_mode, Node.PROCESS_MODE_INHERIT, "Visitor 1 remains active")
	assert_eq(v2.process_mode, Node.PROCESS_MODE_INHERIT, "Visitor 2 remains active")
	assert_ne(v1.group_id, rounds.player.group_id, "Visitor group ID is different from player group ID")
	assert_eq(v1.group_id, v2.group_id, "Visitors share their own group ID")
	assert_eq(rounds.player.group_id, rounds.participants[1].group_id, "Player and opponent share their own group ID")
	assert_true(rounds.hud.visible, "Management HUD remains visible")
	assert_eq(GameManager.current_mode, GameManager.GameMode.SIMULATING, "Simulation mode remains active")

	# Leaving round only removes player group, visitors remain untouched
	rounds.leave_round()
	assert_eq(golfers.active_golfers.size(), 2, "Only visitors remain after owner round ends")
	assert_true(is_instance_valid(v1), "Visitor 1 is still valid")
	assert_true(is_instance_valid(v2), "Visitor 2 is still valid")

func test_group_badges_on_player_group() -> void:
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.mode_picker.select(1) # Vs Pro (group size 2)
	rounds.start_round()
	rounds._process(0.0)

	var p := rounds.player
	var pro := rounds.participants[1]
	var badge_p := p.get_node_or_null("InfoContainer/GroupBadge") as Label
	var badge_pro := pro.get_node_or_null("InfoContainer/GroupBadge") as Label
	assert_not_null(badge_p, "Player has group badge node")
	assert_not_null(badge_pro, "Pro has group badge node")
	assert_true(badge_p.visible, "Player group badge is visible for multi-player group")
	assert_true(badge_pro.visible, "Pro group badge is visible for multi-player group")
	assert_eq(badge_p.text, "Group %d" % (p.group_id + 1), "Badge displays correct group number")
	assert_eq(badge_pro.text, badge_p.text, "Both golfers display the same group badge text")

	rounds.leave_round()

func test_aim_guide_shows_intended_arc_and_roll() -> void:
	_start(0)
	var guide: AimGuide = rounds.aim_guide
	assert_not_null(guide, "Starting a round creates the aim guide")
	rounds.update_aim_guide(Vector2i(16, 10))
	assert_false(guide.preview.is_empty(), "Guide follows the owner's aim")
	var preview := guide.preview
	assert_gt(int(preview.carry_yards), 0, "Guide reports the intended carry")
	assert_gt(int(preview.roll_yards), 0, "Guide reports the roll after landing")
	assert_gt(int(preview.get("roll_path", PackedVector2Array()).size()), 1, "Guide traces the roll path")
	var geometry := AimGuide.build_geometry(GameManager.terrain_grid, preview)
	assert_false(geometry.is_empty(), "Guide geometry projects the preview")
	assert_almost_eq(Vector2(geometry.arc[geometry.arc.size() - 1]).distance_to(geometry.carry), 0.0, 0.5,
		"Arc ends on the guide's carry point")

	# The guide disappears whenever it is not the owner's shot to hit.
	rounds.player.current_state = Golfer.State.WALKING
	rounds.update_aim_guide(Vector2i(16, 10))
	assert_true(guide.preview.is_empty(), "Guide clears while the owner walks")
	rounds.player.current_state = Golfer.State.PREPARING_SHOT
	rounds.update_aim_guide(Vector2i(16, 10))
	assert_false(guide.preview.is_empty(), "Guide returns with the owner's turn")

	rounds.leave_round()
	assert_true(guide.preview.is_empty(), "Guide clears when the round ends")

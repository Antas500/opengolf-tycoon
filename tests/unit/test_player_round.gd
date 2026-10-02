extends GutTest
## Integration coverage with real golfer/ball scenes and the round UI.
var fixture: Node2D
var rounds: PlayerRoundManager
var golfers: GolferManager
var hud: Control
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
	GameManager.set_mode(GameManager.GameMode.SIMULATING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
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
	hud = Control.new()
	fixture.add_child(hud)
	rounds = PlayerRoundManager.new()
	fixture.add_child(rounds)
	rounds.setup(golfers, camera, hud)

func after_each() -> void:
	rounds.leave_round()
	golfers.clear_all_golfers()
	await get_tree().process_frame
	GameManager.current_course = saved.course
	GameManager.terrain_grid = saved.grid if is_instance_valid(saved.grid) else null
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

## Click a shot-type button the way the mouse does: the toggle flips, then the
## press is delivered.
func _press_shot(bar: ShotTypeBar, shape: int) -> void:
	var button := bar.shot_button(shape)
	button.button_pressed = true
	button.pressed.emit()

## The lie under the owner's ball.
func _set_lie(lie: int) -> void:
	var tile := Vector2i(rounds.player.ball_position_precise.round())
	GameManager.terrain_grid._grid[tile] = lie

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
	assert_eq(rounds.shot_bar.shot_count(), 5, "One button per shot type")
	assert_eq(rounds.shot_bar.shot_button(4).text, "Punch")
	_press_shot(rounds.shot_bar, 4)
	assert_eq(rounds.player.player_shape, 4, "Low punch is selected as a shot shape")
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
	assert_eq(GameManager.current_mode, GameManager.GameMode.SIMULATING)
	assert_eq(visitor.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_eq(golfers.active_golfers.size(), 1)
	assert_true(GameManager.player_profile.initialized)

func test_pro_selection_and_tie_results() -> void:
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
	_start(1)
	assert_eq(rounds.participants.size(), 2)
	assert_eq(rounds.mode_picker.item_count, 2, "Only practice and vs pro formats remain")
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
	var player_golfer := rounds.player
	player_golfer.walk_speed = 120
	var resting_target := Vector2(16, 10)
	assert_true(player_golfer.play_shot_to_rest(resting_target))
	assert_false(player_golfer.play_shot_to_rest(resting_target))
	assert_eq(player_golfer.current_strokes, 1)
	# Exercise real swing, ball flight, rollout, walking, putting and pickup.
	Engine.time_scale = 3.0
	for step in 160:
		if not rounds.active:
			break
		if player_golfer.awaits_player_shot():
			player_golfer.play_shot(Vector2i(16, 10))
		await get_tree().create_timer(0.5).timeout
	Engine.time_scale = 1.0
	assert_false(rounds.active, "Real round reaches its results screen")
	assert_eq(player_golfer.hole_scores.size(), 1)

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
	assert_eq(preview.anchor_type, "center", "Explicit tile aiming selects the tile centre")
	assert_eq(preview.rest, Vector2(16, 10), "The expected roll ends on the selected anchor")
	var geometry := AimGuide.build_geometry(GameManager.terrain_grid, preview)
	assert_false(geometry.is_empty(), "Guide geometry projects the preview")
	assert_almost_eq(Vector2(geometry.arc[geometry.arc.size() - 1]).distance_to(geometry.carry), 0.0, 0.5,
		"Arc ends on the guide's carry point")
	assert_almost_eq(Vector2(geometry.trajectory[geometry.trajectory.size() - 1]).distance_to(geometry.rest), 0.0,
		0.01, "The combined trajectory reaches its snapped rest point")

	# The guide disappears whenever it is not the owner's shot to hit.
	rounds.player.current_state = Golfer.State.WALKING
	rounds.update_aim_guide(Vector2i(16, 10))
	assert_true(guide.preview.is_empty(), "Guide clears while the owner walks")
	rounds.player.current_state = Golfer.State.PREPARING_SHOT
	rounds.update_aim_guide(Vector2i(16, 10))
	assert_false(guide.preview.is_empty(), "Guide returns with the owner's turn")

	rounds.leave_round()
	assert_true(guide.preview.is_empty(), "Guide clears when the round ends")

func test_camera_focuses_only_when_aiming_shot() -> void:
	rounds.open_setup()
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.mode_picker.select(1) # Vs Pro
	rounds.start_round()

	var p := rounds.player
	var pro := rounds.participants[1]
	var cam := rounds.camera

	# Reset aiming state and set camera target away from player
	rounds._was_aiming = false
	cam._target_position = Vector2(999, 999)

	# When player awaits shot (needs to aim), _process focuses camera on player
	assert_true(p.awaits_player_shot(), "Player needs to aim shot")
	rounds._process(0.0)
	assert_eq(cam._target_position, p.global_position, "Camera moves to focus on player character when aiming")

	# While player continues aiming, camera is not forced every frame
	cam._target_position = Vector2(500, 500) # User panned camera
	rounds._process(0.0)
	assert_eq(cam._target_position, Vector2(500, 500), "Camera allows manual panning while aiming")

	# When player is walking (not aiming), camera does not track player or opponent
	p._change_state(Golfer.State.WALKING)
	rounds._process(0.0)
	assert_eq(cam._target_position, Vector2(500, 500), "Camera does not follow player walking")

	# When opponent is preparing shot, camera does not jump to opponent
	p._change_state(Golfer.State.IDLE)
	pro._change_state(Golfer.State.PREPARING_SHOT)
	rounds._process(0.0)
	assert_eq(cam._target_position, Vector2(500, 500), "Camera does not focus on opponent")

	# When turn returns to player to aim, camera moves to focus on player character
	pro._change_state(Golfer.State.IDLE)
	p._change_state(Golfer.State.PREPARING_SHOT)
	assert_true(p.awaits_player_shot())
	rounds._process(0.0)
	assert_eq(cam._target_position, p.global_position, "Camera focuses on player when turn to aim arrives")

	rounds.leave_round()

func test_embedded_player_navigation_and_setup() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	assert_eq(tab.buttons.size(), 3)
	assert_eq(tab.buttons[PlayerTab.PAGE_PLAY].text, "Play Course")
	assert_eq(tab.buttons[PlayerTab.PAGE_SKILLS].text, "Player Skills")
	assert_false(rounds.busy, "Editing a player does not reserve a round")
	assert_null(rounds.overlay, "Embedded setup creates no floating overlay")
	assert_true(tab.pages[PlayerTab.PAGE_EDIT].is_ancestor_of(rounds.name_edit))
	assert_true(tab.pages[PlayerTab.PAGE_SKILLS].is_ancestor_of(rounds.points_label))
	assert_true(tab.pages[PlayerTab.PAGE_PLAY].is_ancestor_of(rounds.pro_picker))
	var starters := 0
	for child in tab.pages[PlayerTab.PAGE_PLAY].find_children("*", "Button", true, false):
		if child.has_meta("owner_round_start"):
			starters += 1
	assert_eq(starters, 2, "Play Course combines the practice and vs pro starters")
	for index in 3:
		tab.buttons[index].pressed.emit()
		for page in 3:
			assert_eq(tab.pages[page].get_parent().visible, page == index)
		assert_false(tab.aim_scroll.visible, "The aiming view stays hidden outside a round")

func test_embedded_round_uses_aim_page_and_returns_to_setup() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds._start_embedded(1)
	assert_true(rounds.active)
	assert_eq(rounds.participants.size(), 2)
	assert_eq(tab.selected, PlayerTab.PAGE_PLAY)
	assert_true(tab.aim_page.is_ancestor_of(rounds.status))
	assert_true(tab.aim_scroll.visible, "Play Course swaps to the aiming view while playing")
	assert_false(tab.pages[PlayerTab.PAGE_PLAY].visible, "Setup content hides during the round")
	assert_null(rounds.overlay)
	assert_false(rounds.name_edit.editable, "Appearance stays locked during the round")
	rounds.leave_round()
	assert_false(rounds.busy)
	assert_true(rounds.name_edit.editable)
	assert_false(tab.aim_scroll.visible, "Play Course returns to setup after the round")
	assert_true(tab.pages[PlayerTab.PAGE_PLAY].visible)
	var starters := 0
	for child in tab.pages[PlayerTab.PAGE_PLAY].find_children("*", "Button", true, false):
		if child.has_meta("owner_round_start"):
			starters += 1
	assert_eq(starters, 2, "Rebuilding does not duplicate round-start buttons")

func test_embedded_round_requires_skill_allocation() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	rounds._start_embedded(0)
	assert_false(rounds.busy)
	assert_eq(tab.selected, PlayerTab.PAGE_SKILLS)

## The shot-type buttons are separate buttons running along the top of the Play
## Course page, one per shot type, above the aiming columns — no drop-down.
func test_shot_buttons_run_along_the_top_of_the_play_course_page() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds._start_embedded(0)
	rounds._process(0.0)
	await wait_frames(2)

	var bar := tab.shot_bar
	var labels: Array[String] = []
	for shape in bar.shot_count():
		labels.append(bar.shot_button(shape).text)
	assert_eq(labels, ["Straight", "Fade", "Draw", "Backspin", "Punch"],
		"Every shot type gets its own button")
	for shape in bar.shot_count():
		assert_false(bar.shot_button(shape) is OptionButton, "No shot hides behind a menu")
	assert_true(bar.is_ancestor_of(bar.shot_button(0)), "The buttons are the Play Course row")
	assert_lte(bar.get_global_rect().end.y, tab.aim_scroll.get_global_rect().position.y + 1,
		"The shot buttons run above the aiming columns")
	assert_lte(bar.get_combined_minimum_size().y, tab.aim_view.size.y,
		"The row fits inside the Play Course page")

	# The row is live on the owner's turn and lights the shot the golfer will hit.
	assert_true(bar.is_ready_for_shot(), "The row is live while the owner aims")
	assert_true(bar.shot_button(0).button_pressed, "Straight leads by default")
	_press_shot(bar, 2)
	assert_eq(rounds.player.player_shape, 2, "Pressing Draw selects the draw shot")
	assert_true(bar.shot_button(2).button_pressed, "The pressed shot stays lit")
	assert_false(bar.shot_button(0).button_pressed, "Only one shot is lit at a time")
	var fairway_range := rounds.player.player_max_distance(Golfer.Club.IRON)
	_press_shot(bar, 4)
	assert_true(rounds.player.is_player_punch(), "Punch is a normal press on the row")
	assert_almost_eq(rounds.player.player_max_distance(Golfer.Club.IRON), fairway_range * 0.7, 0.001,
		"The lit button is the shot the golfer will hit")
	_assert_shelf_fits(tab.aim_page)

	# Off the tee and fairway the bend shots grey out and an illegal choice falls
	# back to straight, exactly as Golfer.play_shot() does.
	_press_shot(bar, 2)
	assert_eq(rounds.player.player_shape, 2, "Draw is selected from the fairway")
	_set_lie(TerrainTypes.Type.ROUGH)
	rounds._process(0.0)
	assert_true(bar.shot_button(1).disabled, "Fade needs a tee or fairway")
	assert_true(bar.shot_button(2).disabled, "Draw needs a tee or fairway")
	assert_true(bar.shot_button(3).disabled, "Backspin needs a tee or fairway")
	assert_false(bar.shot_button(0).disabled, "Straight works from the rough")
	assert_false(bar.shot_button(4).disabled, "Low punch works from the rough")
	assert_eq(rounds.player.player_shape, 0, "An illegal shape falls back to straight")
	assert_true(bar.shot_button(0).button_pressed, "The row follows the fallback")

	# Waiting for an opponent greys the whole row out instead of hiding it.
	_set_lie(TerrainTypes.Type.FAIRWAY)
	rounds.player._change_state(Golfer.State.WALKING)
	rounds._process(0.0)
	assert_false(bar.is_ready_for_shot(), "The row is dead between shots")
	for shape in bar.shot_count():
		assert_true(bar.shot_button(shape).disabled, "Every shot greys out while waiting")

## Exercise the real toolbar so header, panel margins and scrollbars count
## against the same height budget as the course tiles.
func _embedded_toolbar() -> TerrainToolbar:
	var toolbar := TerrainToolbar.new()
	fixture.add_child(toolbar)
	toolbar.size = Vector2(1000, UIConstants.BOTTOM_BAR_HEIGHT)
	var panel := TournamentPanel.new()
	panel.embedded = true
	toolbar.player_tab.add_persistent(panel)
	var tournaments := TournamentManager.new()
	fixture.add_child(tournaments)
	panel.setup(tournaments)
	rounds.attach_player_tab(toolbar.player_tab)
	toolbar.select_tab(TerrainToolbar.Tab.PLAYER)
	return toolbar

func _assert_shelf_fits(shelf: HBoxContainer) -> void:
	var scroll := shelf.get_parent() as ScrollContainer
	assert_lte(scroll.size.y, scroll.get_parent().size.y, "Scroll viewport fits the allocated tab height")
	# The shot-type row rides above the shelf: the two together must fit the page.
	var view := scroll.get_parent() as VBoxContainer
	if view != null:
		assert_lte(view.get_combined_minimum_size().y, view.size.y,
			"The shot buttons and the control columns share the page height")
		for child in view.get_children():
			if child is ShotTypeBar:
				assert_lte(child.get_combined_minimum_size().y, child.size.y, "The shot row keeps its height")
				assert_lte(child.get_combined_minimum_size().x, child.size.x, "The shot row spans the tab")
				assert_lte(child.get_global_rect().end.y, scroll.get_global_rect().position.y + 1,
					"The shot buttons run above the aiming columns")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_false(scroll.get_v_scroll_bar().visible, "No vertical scrolling in the Player tab")
	var available := scroll.size.y
	if scroll.get_h_scroll_bar().visible:
		available -= scroll.get_h_scroll_bar().size.y
	assert_lte(shelf.get_combined_minimum_size().y, available,
		"All content fits above the horizontal scrollbar")
	for control in shelf.find_children("*", "Control", true, false):
		if control.is_visible_in_tree() and not control is Popup:
			assert_lte(control.get_global_rect().end.y, scroll.get_global_rect().position.y + available + 1,
				"%s stays inside the shelf" % control.get_class())

func test_embedded_pages_fit_toolbar_and_overflow_horizontally() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	for width in [1000, 600, 1600]:
		toolbar.size.x = width
		for index in 3:
			tab.select(index)
			await wait_frames(5)
			assert_eq(toolbar.size.y, float(UIConstants.BOTTOM_BAR_HEIGHT), "Switching pages never grows the bar")
			_assert_shelf_fits(tab.pages[index])
			if width == 600:
				var scroll := tab.pages[index].get_parent() as ScrollContainer
				assert_true(scroll.get_h_scroll_bar().visible, "Narrow pages scroll sideways")
				var navigation_x := tab.buttons[0].global_position.x
				var event := InputEventMouseButton.new()
				event.button_index = MOUSE_BUTTON_WHEEL_DOWN
				event.pressed = true
				tab._on_scroll_gui_input(event, scroll)
				assert_gt(scroll.scroll_horizontal, 0, "Mouse wheel scrolls horizontally")
				assert_eq(tab.buttons[0].global_position.x, navigation_x,
					"Navigation stays pinned while content scrolls")
	toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await wait_frames(5)
	assert_eq(toolbar.size.y, float(UIConstants.BOTTOM_BAR_HEIGHT))

func test_embedded_tournament_survives_rebuilds_and_fits_all_states() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	var panel: TournamentPanel
	for child in tab.pages[PlayerTab.PAGE_PLAY].get_children():
		if child is TournamentPanel:
			panel = child
	for state in TournamentSystem.TournamentState.values():
		panel._tournament_manager.current_tournament_state = state
		panel._tournament_manager.current_tournament_tier = 0
		panel._tournament_manager.tournament_results = {
			"winner_name": "Tournament Winner", "winning_score": 70, "par": 72}
		panel._refresh_display()
		rounds._build_setup()
		await wait_frames(5)
		assert_eq(panel.get_parent(), tab.pages[PlayerTab.PAGE_PLAY])
		_assert_shelf_fits(tab.pages[PlayerTab.PAGE_PLAY])

## The game's top-left score corner, as main.gd builds it: the round card first,
## the tournament board docked under it.
func _scores_dock() -> ScoresDock:
	var dock := ScoresDock.new()
	hud.add_child(dock)
	rounds.attach_scores_panel(dock.round_scores)
	return dock

func test_tournament_board_and_shot_controls_share_the_corner() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	var dock := _scores_dock()
	var leaderboard := TournamentLeaderboard.new()
	dock.attach_leaderboard(leaderboard)
	leaderboard.show_for_tournament("Local Tournament", 12)
	leaderboard.register_golfer(0, "Owner", 0, true)

	var owner_golfer := golfers.spawn_tournament_golfer(GolferTier.Tier.SERIOUS, 99)
	owner_golfer.player_profile = GameManager.player_profile
	rounds.begin_tournament_aim(owner_golfer)
	await wait_frames(5)
	assert_true(rounds.tournament_aim)
	assert_eq(tab.selected, PlayerTab.PAGE_PLAY)
	assert_true(tab.playing)
	assert_true(tab.aim_scroll.visible)
	assert_true(dock.is_ancestor_of(leaderboard), "Tournament scores live in the top-left corner")
	assert_false(tab.aim_page.is_ancestor_of(leaderboard),
		"Tournament scores no longer sit in the Play Course page")
	assert_true(tab.aim_page.is_ancestor_of(rounds.status), "Tournament shot status stays with the controls")
	assert_true(tab.aim_page.is_ancestor_of(rounds._tournament_hud_column))
	_assert_shelf_fits(tab.aim_page)

func test_scores_dock_hugs_the_top_left_corner() -> void:
	var dock := _scores_dock()
	var leaderboard := TournamentLeaderboard.new()
	dock.attach_leaderboard(leaderboard)
	await wait_frames(2)
	assert_eq(dock.anchor_left, 0.0)
	assert_eq(dock.anchor_top, 0.0)
	assert_eq(dock.offset_left, float(UIConstants.HUD_COLUMN_MARGIN))
	assert_eq(dock.offset_top, float(UIConstants.HUD_COLUMN_MARGIN))
	assert_true(dock.round_scores.get_parent() == dock, "The round card leads the corner")
	assert_true(leaderboard.get_parent() == dock, "The board docks under it")
	leaderboard.show_for_tournament("Local Tournament", 4)
	await wait_frames(2)
	assert_eq(dock.size.x, float(ScoresDock.WIDTH),
		"The corner is wide enough for the board's columns")
	for i in 40:
		leaderboard.register_golfer(i, "Golfer %d" % i, i)
	await wait_frames(2)
	assert_eq(leaderboard._scroll.custom_minimum_size.y,
		TournamentLeaderboard.DOCK_BODY_MAX_HEIGHT,
		"A big field is capped so the board cannot run down the screen")
	assert_true(leaderboard._scroll.get_v_scroll_bar().visible, "The rest of the field scrolls")

func test_practice_round_scores_read_out_top_left() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	var dock := _scores_dock()
	var card := dock.round_scores
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds._start_embedded(1)
	await wait_frames(2)
	assert_true(card.visible, "The round card shows while playing")
	assert_eq(card.title_label.text, "Vs Pro · Pro Alex")
	assert_false(tab.aim_page.is_ancestor_of(card), "The scorecard is out of the Play Course page")
	assert_true(dock.is_ancestor_of(card), "The scorecard sits in the top-left corner")
	var rows := card.score_rows()
	assert_eq(rows.size(), 2, "One row per player in the group")
	assert_eq(rows[0].name, "Test Owner (you)")
	assert_eq(rows[0].value, "-", "No holes in yet")
	# One hole in: the card shows the score against par and the holes completed.
	var owner_golfer: Golfer = rounds.player
	owner_golfer.hole_scores.append({"hole": 1, "strokes": 2, "par": 3})
	owner_golfer.total_strokes = 2
	owner_golfer.total_par = 3
	rounds._process(0.0)
	assert_eq(card.score_rows()[0].value, "-1 · thru 1")
	await wait_frames(2)
	assert_true(card._scroll.custom_minimum_size.y < RoundScoresPanel.MAX_BODY_HEIGHT,
		"A short card does not reserve empty space over the course")
	rounds.leave_round()
	await wait_frames(2)
	assert_false(card.visible, "Leaving the round drops the card")

func test_round_complete_scores_land_on_the_card() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	var dock := _scores_dock()
	var card := dock.round_scores
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds._start_embedded(0)
	await wait_frames(2)
	for golfer in rounds.participants:
		golfer.hole_scores.clear()
		for hole in 18:
			golfer.hole_scores.append({"hole": hole + 1, "strokes": 4, "par": 4})
		golfer.total_strokes = 72
		golfer.total_par = 72
	rounds._show_results()
	await wait_frames(2)
	assert_eq(card.title_label.text, "Round complete")
	var lines: Array[String] = []
	for child in card.body.get_children():
		if child is Label:
			lines.append(child.text)
	assert_true(lines.any(func(line): return line.begins_with("Test Owner — 72 strokes")),
		"The card carries the finished scorecard: " + str(lines))
	assert_true("Hole 18: 4 / Par 4" in lines, "Every hole of the card is on it")
	assert_eq(card._scroll.custom_minimum_size.y, RoundScoresPanel.MAX_BODY_HEIGHT,
		"A long card is capped so it cannot cover the course")
	assert_true(card._scroll.get_v_scroll_bar().visible, "The rest of the card scrolls")
	var return_buttons := 0
	for button in tab.aim_page.find_children("*", "Button", true, false):
		if button.text == "Return to management":
			return_buttons += 1
	assert_eq(return_buttons, 1, "The round page keeps the way out of the round")

func test_embedded_aim_and_full_scorecards_fit_toolbar() -> void:
	var toolbar := _embedded_toolbar()
	var tab := toolbar.player_tab
	for i in 10:
		rounds.draft.allocate(i, 1)
	rounds.name_edit.text = "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
	rounds._start_embedded(2)
	rounds._process(0.0)
	await wait_frames(5)
	_assert_shelf_fits(tab.aim_page)
	assert_false(tab.pages[PlayerTab.PAGE_PLAY].get_parent().visible,
		"Setup scrollbar is hidden during a round")
	for golfer in rounds.participants:
		golfer.hole_scores.clear()
		for hole in 18:
			golfer.hole_scores.append({"hole": hole + 1, "strokes": 4, "par": 4})
	rounds._show_results()
	await wait_frames(5)
	_assert_shelf_fits(tab.aim_page)
	assert_eq(toolbar.size.y, float(UIConstants.BOTTOM_BAR_HEIGHT))

func test_save_skills_button_removed_and_skills_save_automatically() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	# Verify that no button with text "Save skills" exists anywhere in the Player Skills page
	var skill_page := tab.pages[PlayerTab.PAGE_SKILLS]
	for button in skill_page.find_children("*", "Button", true, false):
		assert_ne(button.text, "Save skills", "Save skills button must not exist")

	# Verify skills save automatically whenever changed
	assert_eq(GameManager.player_profile.points[0], 0)
	assert_true(rounds.allocate_skill(0, 1), "Allocating a point succeeds")
	assert_eq(GameManager.player_profile.points[0], 1, "Skill automatically saved to player_profile")
	assert_eq(rounds.draft.points[0], 1)

	assert_true(rounds.allocate_skill(0, -1), "Refunding a point succeeds")
	assert_eq(GameManager.player_profile.points[0], 0, "Refund automatically saved to player_profile")

func test_skills_auto_save_and_take_effect_for_next_shot_mid_round() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	# Allocate initial 10 points
	for i in 10:
		rounds.allocate_skill(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds._start_embedded(0)
	rounds._process(0.0)

	assert_true(rounds.active, "Round is active")
	assert_not_null(rounds.player, "Player golfer is spawned")

	# Skills page controls must remain enabled during an active round
	var skill_page := tab.pages[PlayerTab.PAGE_SKILLS]
	for button in skill_page.find_children("*", "Button", true, false):
		assert_false(button.disabled, "Skill adjustment buttons must remain enabled during round")

	# Record initial driving skill and driver distance
	var initial_driving_skill := rounds.player.driving_skill
	var initial_driver_dist := rounds.player.player_max_distance(Golfer.Club.DRIVER)
	var initial_accuracy_skill := rounds.player.accuracy_skill

	# Mid-round: change skills (e.g. shift a point from Power Hitter to Long Driver, and add to Accurate Irons)
	# First refund 1 from skill 0 (Power Hitter)
	assert_true(rounds.allocate_skill(0, -1))
	# Add to skill 1 (Long Driver)
	assert_true(rounds.allocate_skill(1, 1))

	# Verify skills auto-saved to GameManager.player_profile
	assert_eq(GameManager.player_profile.points[0], 0, "Power Hitter points updated in profile")
	assert_eq(GameManager.player_profile.points[1], 2, "Long Driver points updated in profile")

	# Verify skills are immediately in effect on the golfer for the next shot
	assert_almost_eq(rounds.player.driving_skill, GameManager.player_profile.normalized_skill(1), 0.0001,
		"Player driving_skill updated immediately")
	assert_gt(rounds.player.driving_skill, initial_driving_skill,
		"Driving skill increased after allocating more points to Long Driver")

	# Verify driver distance reflects the new skills immediately
	var new_driver_dist := rounds.player.player_max_distance(Golfer.Club.DRIVER)
	# Long Driver adds to driver bonus, so distance factor for driver is now higher
	assert_almost_eq(new_driver_dist, float(Golfer.CLUB_STATS[Golfer.Club.DRIVER].max_distance) * 0.7 * (1.0 + 0.2), 0.01,
		"Driver distance reflects updated Long Driver skill immediately")

	# Verify aim guide / shot preview reflects the updated skills
	var preview := rounds.player.preview_shot(Vector2i(30, 10))
	assert_false(preview.is_empty(), "Preview shot is available")
	assert_almost_eq(preview.max_range, new_driver_dist, 0.01,
		"Preview shot max range matches updated skill distance")

	# Take shot and verify it succeeds with new skills in effect
	assert_true(rounds.player.play_shot(Vector2i(30, 10)), "Shot executes with new skills in effect")

	rounds.leave_round()

func test_putting_skill_auto_saves_and_takes_effect_for_next_putt() -> void:
	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	for i in 10:
		rounds.allocate_skill(i, 1)
	rounds.name_edit.text = "Test Owner"
	rounds._start_embedded(0)
	rounds._process(0.0)

	var initial_putting_skill := rounds.player.putting_skill

	# Reallocate: shift point from Luck (index 9) to Accurate Putter (index 4)
	assert_true(rounds.allocate_skill(9, -1))
	assert_true(rounds.allocate_skill(4, 1))

	assert_eq(GameManager.player_profile.points[4], 2, "Accurate Putter updated in GameManager.player_profile")
	assert_gt(rounds.player.putting_skill, initial_putting_skill,
		"Golfer putting_skill immediately reflects new Accurate Putter skill for next putt")

	rounds.leave_round()

func test_skills_change_mid_round_with_tournament_manager_present() -> void:
	var tm := TournamentManager.new()
	fixture.add_child(tm)
	GameManager.tournament_manager = tm

	var tab := PlayerTab.new()
	fixture.add_child(tab)
	rounds.attach_player_tab(tab)
	for i in 10:
		rounds.allocate_skill(i, 1)
	rounds.name_edit.text = "Course Golfer"
	rounds._start_embedded(0)
	rounds._process(0.0)

	assert_true(rounds.active, "Course round is active")
	assert_not_null(rounds.player, "Player golfer is present")

	# Change skills while playing the course with TournamentManager active in GameManager
	assert_true(rounds.allocate_skill(0, -1), "Refunding skill mid-round succeeds with TournamentManager present")
	assert_true(rounds.allocate_skill(3, 1), "Allocating skill mid-round succeeds with TournamentManager present")
	assert_eq(GameManager.player_profile.points[0], 0)
	assert_eq(GameManager.player_profile.points[3], 2)
	assert_almost_eq(rounds.player.accuracy_skill, GameManager.player_profile.normalized_skill(3), 0.0001)

	# Also verify sync_player_skills updates SimGolfer if present in field
	var sg := tm._make_player_sim_golfer()
	tm._sim_field = [sg]
	assert_true(rounds.allocate_skill(3, -1))
	assert_true(rounds.allocate_skill(1, 1))
	assert_almost_eq(sg.driving_skill, GameManager.player_profile.normalized_skill(1), 0.0001,
		"TournamentManager SimGolfer skills update when player skills change")

	rounds.leave_round()

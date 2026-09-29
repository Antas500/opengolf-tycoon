extends Node2D
class_name PlayerRoundManager
## Owner rounds run alongside the management simulation as a normal group.
signal session_opened

const PROS = ["Pro Alex", "Pro Morgan", "Pro Riley"]
var player_tab: PlayerTab
## Top-left score card owned by the game HUD (null in isolated tools and tests,
## which fall back to putting the scorecards on the round page).
var scores: RoundScoresPanel = null
var busy := false
var active := false
var player: Golfer
var participants: Array[Golfer] = []
var manager: GolferManager
var camera: IsometricCamera
var hud: Control
var layer: CanvasLayer
var entry: Button = null  # Legacy floating button; replaced by the toolbar's Player tab
var overlay: Control
var content: VBoxContainer
var status: Label
var shapes: OptionButton
var punch: CheckButton
var draft: PlayerGolferProfile
var name_edit: LineEdit
var mode_picker: OptionButton
var pro_picker: OptionButton
var skill_labels: Array[Label] = []
var points_label: Label
var start_button: Button
var previous_mode: int
var previous_speed: int
var previous_camera: Vector2
var round_kind := 0
var aim_guide: AimGuide
var _was_aiming: bool = false
var _tournament_hud_column: VBoxContainer = null
## True while aiming for the owner's golfer inside a running tournament. The
## TournamentManager owns that round; this flag only tells our _process to skip
## the owner-round bookkeeping (driving the sim, showing round results) and to
## leave the golfer on the course when aiming ends.
var tournament_aim: bool = false

func setup(golfers: GolferManager, view: IsometricCamera, management_hud: Control) -> void:
	manager = golfers
	camera = view
	hud = management_hud
	aim_guide = AimGuide.new()
	add_child(aim_guide)
	layer = CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	EventBus.game_mode_changed.connect(_on_mode_changed)
	EventBus.load_completed.connect(_on_load_completed)
	EventBus.new_game_started.connect(_on_new_game_started)

func _exit_tree() -> void:
	if EventBus.game_mode_changed.is_connected(_on_mode_changed):
		EventBus.game_mode_changed.disconnect(_on_mode_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)

func _on_mode_changed(_old: int, mode: int) -> void:
	if busy and mode == GameManager.GameMode.MAIN_MENU:
		leave_round(false)

func _on_new_game_started() -> void:
	_on_load_completed(true)

func _on_load_completed(_success: bool) -> void:
	if busy:
		leave_round(false)
	elif is_instance_valid(player_tab):
		_build_setup()

func _make_panel(full_screen: bool) -> void:
	if is_instance_valid(player_tab):
		# The Play Course tab swaps its setup sections for the aiming HUD.
		content = PlayerTab.add_column(player_tab.clear_aim_page(), 320)
		player_tab.set_playing(true)
		player_tab.select(PlayerTab.PAGE_PLAY)
		return
	if is_instance_valid(overlay):
		overlay.queue_free()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP if full_screen else Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	var panel := PanelContainer.new()
	overlay.add_child(panel)
	panel.position = Vector2(20, 56) if not full_screen else Vector2(40, 40)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, minf(760, get_viewport_rect().size.y - 100)) if full_screen else Vector2(340, 240)
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	if is_instance_valid(player_tab):
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	content.add_child(button)
	return button

func attach_player_tab(tab: PlayerTab) -> void:
	player_tab = tab
	open_setup()

## Hand the manager the top-left score card the HUD docked in the corner.
func attach_scores_panel(panel: RoundScoresPanel) -> void:
	scores = panel

func open_setup() -> void:
	if is_instance_valid(player_tab):
		if busy:
			# Mid-round: jump to the Play Course tab showing the aiming HUD.
			player_tab.select(PlayerTab.PAGE_PLAY)
			return
		_build_setup()
		return
	if busy or GameManager.is_paused:
		return
	if GameManager.get_open_hole_count() == 0:
		EventBus.notify("Open at least one complete hole before playing.", "warning")
		return
	if GameManager.tournament_manager and GameManager.tournament_manager.is_tournament_in_progress():
		EventBus.notify("Tournament running - Play It Out on the Tournament shelf first.", "warning")
		return
	busy = true
	previous_mode = GameManager.current_mode
	previous_speed = GameManager.current_speed
	previous_camera = camera.global_position if is_instance_valid(camera) else Vector2.ZERO
	session_opened.emit()
	_build_setup()

func _build_setup() -> void:
	draft = PlayerGolferProfile.from_data(GameManager.player_profile.serialize())
	# A rebuilt page means no round is showing: drop whatever scores the last
	# one left on the card.
	if is_instance_valid(scores):
		scores.dismiss()
	if is_instance_valid(player_tab):
		player_tab.set_playing(false)
		for index in [PlayerTab.PAGE_EDIT, PlayerTab.PAGE_SKILLS]:
			player_tab.clear_page(index)
		player_tab.clear_aim_page()
		# The management tournament panel survives on the Play Course page.
		player_tab.clear_play_page()
		content = PlayerTab.add_column(player_tab.pages[PlayerTab.PAGE_EDIT])
	else:
		_make_panel(true)
	_label("PLAY YOUR COURSE")
	_label("Your golfer")
	name_edit = LineEdit.new()
	name_edit.max_length = 32
	name_edit.text = draft.golfer_name
	content.add_child(name_edit)
	if is_instance_valid(player_tab):
		_button("Save player", _save_player)
	var color_index := 0
	for key in PlayerGolferProfile.COLORS:
		if is_instance_valid(player_tab) and color_index % 3 == 0:
			content = PlayerTab.add_column(player_tab.pages[PlayerTab.PAGE_EDIT], 260)
		color_index += 1
		var row := HBoxContainer.new()
		content.add_child(row)
		var label := Label.new()
		label.text = key.replace("_", " ").capitalize()
		label.custom_minimum_size.x = 140 if is_instance_valid(player_tab) else 180
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var color := ColorPickerButton.new()
		color.color = Color(draft.appearance[key])
		color.edit_alpha = false
		color.custom_minimum_size = Vector2(100, 28)
		color.color_changed.connect(func(value: Color): draft.appearance[key] = value.to_html(false))
		row.add_child(color)
	if is_instance_valid(player_tab):
		# Short round-choice sections share one horizontally scrolling shelf.
		# Practice Round leads the first column with Play vs Pro stacked below it.
		content = PlayerTab.add_column(player_tab.pages[PlayerTab.PAGE_PLAY])
		# The stacked column must stay under the shelf's ~150px height budget
		# (the tab has no vertical scrollbar), so its rows sit tighter than the
		# other columns' default spacing.
		content.add_theme_constant_override("separation", 2)
		_label("Practice Round")
		mode_picker = OptionButton.new()
		for title in ["Practice round", "Play vs a Pro"]:
			mode_picker.add_item(title)
		mode_picker.hide()  # Each section starts its own format below.
		content.add_child(mode_picker)
		var practice_button := _button("Start practice round", _start_embedded.bind(0))
		practice_button.set_meta("owner_round_start", true)
		_label("Play vs Pro")
		pro_picker = OptionButton.new()
		for pro in PROS:
			pro_picker.add_item(pro)
		content.add_child(pro_picker)
		var pro_button := _button("Play selected pro", _start_embedded.bind(1))
		pro_button.set_meta("owner_round_start", true)
		content = PlayerTab.add_column(player_tab.pages[PlayerTab.PAGE_SKILLS], 250)
	else:
		_label("Round format")
		mode_picker = OptionButton.new()
		for title in ["Practice round", "Play vs a Pro"]:
			mode_picker.add_item(title)
		content.add_child(mode_picker)
		pro_picker = OptionButton.new()
		for pro in PROS:
			pro_picker.add_item(pro)
		pro_picker.disabled = true
		content.add_child(pro_picker)
		mode_picker.item_selected.connect(func(index: int): pro_picker.disabled = index != 1)
	points_label = _label("")
	_label("Each point adds 10% bonus. Maximum per skill: 990%.")
	if is_instance_valid(player_tab):
		_button("Save skills", _save_player)
	skill_labels.clear()
	for i in PlayerGolferProfile.SKILLS.size():
		if is_instance_valid(player_tab) and i % 3 == 0:
			content = PlayerTab.add_column(player_tab.pages[PlayerTab.PAGE_SKILLS], 290)
		var row := HBoxContainer.new()
		content.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		skill_labels.append(label)
		for change in [-1, 1]:
			var button := Button.new()
			button.text = "+" if change == 1 else "−"
			button.disabled = draft.initialized
			button.pressed.connect(func():
				draft.allocate(i, change)
				_refresh_skills())
			row.add_child(button)
	if is_instance_valid(player_tab):
		player_tab.restage_persistent()
		start_button = null
	else:
		start_button = _button("Tee off", start_round)
		_button("Cancel", leave_round)
	_refresh_skills()

func _refresh_skills() -> void:
	points_label.text = "Skills locked for this golfer" if draft.initialized else "%d of 10 points remaining" % draft.remaining()
	for i in skill_labels.size():
		skill_labels[i].text = "%s: %d%%" % [PlayerGolferProfile.SKILLS[i], draft.points[i] * 10]
	if is_instance_valid(start_button):
		start_button.disabled = not draft.initialized and draft.remaining() != 0

func _save_player() -> void:
	if busy:
		return
	draft.golfer_name = name_edit.text.strip_edges()
	if draft.golfer_name.is_empty():
		draft.golfer_name = "Course Owner"
	GameManager.player_profile = PlayerGolferProfile.from_data(draft.serialize())

func _start_embedded(kind: int) -> void:
	if busy or GameManager.is_paused:
		EventBus.notify("Finish the current round and unpause before starting.", "info")
		return
	if GameManager.get_open_hole_count() == 0:
		EventBus.notify("Open at least one complete hole before playing.", "warning")
		return
	if GameManager.tournament_manager and GameManager.tournament_manager.is_tournament_in_progress():
		EventBus.notify("Tournament running - Play It Out on the Tournament shelf first.", "warning")
		return
	if not draft.initialized and draft.remaining() != 0:
		EventBus.notify("Allocate all 10 points in Player Skills first.", "info")
		player_tab.select(PlayerTab.PAGE_SKILLS)
		return
	busy = true
	previous_mode = GameManager.current_mode
	previous_speed = GameManager.current_speed
	previous_camera = camera.global_position if is_instance_valid(camera) else Vector2.ZERO
	mode_picker.select(kind)
	session_opened.emit()
	start_round()

func start_round() -> void:
	if not draft.initialized and draft.remaining() != 0:
		return
	if GameManager.get_open_hole_count() == 0:
		return
	draft.golfer_name = name_edit.text.strip_edges()
	if draft.golfer_name.is_empty():
		draft.golfer_name = "Course Owner"
	draft.initialized = true
	GameManager.player_profile = draft
	round_kind = mode_picker.selected
	var opponent := pro_picker.selected
	active = true
	if is_instance_valid(player_tab):
		# Lock the Edit Player and Player Skills pages while the round runs.
		for index in [PlayerTab.PAGE_EDIT, PlayerTab.PAGE_SKILLS]:
			for control in player_tab.pages[index].find_children("*", "Control", true, false):
				if control is BaseButton:
					control.disabled = true
				elif control is LineEdit:
					control.editable = false

	# Ensure simulation is active so all golfers can play (day always runs)
	if GameManager.current_mode != GameManager.GameMode.SIMULATING:
		GameManager.set_mode(GameManager.GameMode.SIMULATING)
		GameManager.set_speed(GameManager.GameSpeed.NORMAL)

	# Assign a shared group ID so the player and opponents play as a single group
	var group_id: int = manager.next_group_id
	manager.next_group_id += 1

	player = _spawn(draft.golfer_name, GolferTier.Tier.CASUAL, group_id)
	player.player_profile = draft
	player.driving_skill = draft.normalized_skill(1)
	player.accuracy_skill = draft.normalized_skill(3)
	player.putting_skill = draft.normalized_skill(4)
	player.recovery_skill = draft.normalized_skill(8)
	player.miss_tendency = 0.0
	player.apply_player_appearance(draft)

	if round_kind == 1:
		_spawn(PROS[opponent], GolferTier.Tier.PRO, group_id)

	# Position all participants at the tee of the first open hole
	var course_data = GameManager.course_data
	if course_data and not course_data.holes.is_empty():
		var first_open_idx = manager._find_next_open_hole(0, course_data)
		if first_open_idx < course_data.holes.size():
			var first_hole = course_data.holes[first_open_idx]
			var tee_pos = first_hole.tee_position
			var tee_screen = GameManager.terrain_grid.grid_to_screen_center(tee_pos) if GameManager.terrain_grid else Vector2.ZERO
			for golfer in participants:
				golfer.ball_position = tee_pos
				golfer.ball_position_precise = Vector2(tee_pos)
				golfer.global_position = tee_screen

	# Immediately trigger group update to determine tee honor and advance first shooter
	if is_instance_valid(manager):
		manager._update_golfers(0.0)

	_make_panel(false)
	_label("PLAY THE COURSE · " + ["Practice", "Vs Pro"][round_kind])
	status = _label("")
	if is_instance_valid(scores):
		# The scores read out in the top-left corner of the screen: the round
		# title, then a row per player (Practice Round / Vs Pro · Pro Alex).
		scores.begin(["Practice Round", "Vs Pro · " + PROS[opponent]][round_kind])
	if is_instance_valid(player_tab):
		status.add_theme_font_size_override("font_size", 12)
		status.autowrap_mode = TextServer.AUTOWRAP_OFF
		content = PlayerTab.add_column(player_tab.aim_page)
	shapes = OptionButton.new()
	for title in ["Straight shot", "Fade shot (L to R)", "Draw shot (R to L)", "High backspin shot"]:
		shapes.add_item(title)
	shapes.item_selected.connect(func(index: int): player.player_shape = index)
	content.add_child(shapes)
	punch = CheckButton.new()
	punch.text = "Low punch shot"
	punch.toggled.connect(func(value: bool): player.player_punch = value)
	content.add_child(punch)
	if is_instance_valid(player_tab):
		_button("End round / Return to management", leave_round)
		content = PlayerTab.add_column(player_tab.aim_page, 420)
	var instructions := _label("Aim with the mouse · Click to shoot\nYellow arc = intended carry · dotted trail = roll until it stops\nGuide assumes a clean strike; wind, lie and slope still apply.\nPutting on the green is automatic.")
	if is_instance_valid(player_tab):
		instructions.add_theme_font_size_override("font_size", 14)
	else:
		_button("End round / Return to management", leave_round)
	_was_aiming = false

func _spawn(golfer_name: String, tier: int, group_id: int) -> Golfer:
	var golfer := manager.spawn_tournament_golfer(tier, group_id)
	golfer.is_owner_round = true
	golfer.golfer_name = golfer_name
	golfer._update_visual()
	participants.append(golfer)
	return golfer

# ============================================================================
# TOURNAMENT AIMING
# ============================================================================
## Aim for the owner's golfer inside a running tournament. The TournamentManager
## still owns the round — it spawns the field, scores it and settles the event —
## so this only mirrors what an owner round does for shot input: the aim guide,
## the shape/punch controls, camera focus and click-to-shoot. Putting off the
## player's turn stays automatic (Golfer.awaits_player_shot() is false on green).
func begin_tournament_aim(owner: Golfer) -> void:
	if not is_instance_valid(owner) or owner.player_profile == null:
		return
	player = owner
	active = true
	busy = true
	tournament_aim = true
	previous_camera = camera.global_position if is_instance_valid(camera) else Vector2.ZERO
	previous_speed = GameManager.current_speed
	session_opened.emit()
	# The live tournament board is the score display for this round; the owner's
	# round card would only repeat it, so it steps aside.
	if is_instance_valid(scores):
		scores.dismiss()
	_build_tournament_aim_hud()

## Stop aiming for a tournament golfer. Leaves the golfer on the course — the
## TournamentManager clears it — and leaves the scorecard visible in the Play
## Course tab after the shot controls are removed.
func end_tournament_aim() -> void:
	if not tournament_aim:
		return
	tournament_aim = false
	active = false
	busy = false
	_was_aiming = false
	player = null
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if is_instance_valid(aim_guide):
		aim_guide.clear()
	if is_instance_valid(_tournament_hud_column):
		_tournament_hud_column.queue_free()
		_tournament_hud_column = null
	if is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	content = null

## Tournament shots use the same aiming page as practice and pro rounds: this
## column is the shot controls only. The live leaderboard keeps the scores in the
## HUD's top-left corner (ScoresDock), above the course view.
func _build_tournament_aim_hud() -> void:
	if is_instance_valid(player_tab):
		player_tab.set_playing(true)
		player_tab.select(PlayerTab.PAGE_PLAY)
		_tournament_hud_column = PlayerTab.add_column(player_tab.aim_page, 320)
		_tournament_hud_column.add_theme_constant_override("separation", 1)
		content = _tournament_hud_column
	else:
		# Fallback for isolated use without the game's Player tab.
		_make_panel(false)
		content.add_theme_constant_override("separation", 6)

	status = _label("Your tournament round")
	status.add_theme_font_size_override("font_size", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	shapes = OptionButton.new()
	shapes.custom_minimum_size.y = 24
	for title in ["Straight shot", "Fade shot (L to R)", "Draw shot (R to L)", "High backspin shot"]:
		shapes.add_item(title)
	shapes.item_selected.connect(func(index: int):
		if is_instance_valid(player):
			player.player_shape = index)
	content.add_child(shapes)
	punch = CheckButton.new()
	punch.custom_minimum_size.y = 24
	punch.text = "Low punch shot"
	punch.toggled.connect(func(value: bool):
		if is_instance_valid(player):
			player.player_punch = value)
	content.add_child(punch)
	var settle_button := _button("Settle tournament (skip your round)", _on_settle_tournament)
	settle_button.custom_minimum_size.y = 24
	var instructions := _label("Aim + click · Yellow: carry · Dots: roll")
	instructions.add_theme_font_size_override("font_size", 11)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.tooltip_text = "Aim with the mouse · Click to shoot\nYellow arc = intended carry · dotted trail = roll until it stops\nGuide assumes a clean strike; wind, lie and slope still apply.\nPutting on the green is automatic."
	_was_aiming = false

## Skip the rest of the event from the cards as they stand (the Tournament
## shelf's "Play It Out"). Ends aiming first so the HUD is gone before the field
## is settled.
func _on_settle_tournament() -> void:
	if GameManager.tournament_manager:
		end_tournament_aim()
		GameManager.tournament_manager.simulate_remaining_and_complete()

func _process(delta: float) -> void:
	if is_instance_valid(entry):
		entry.visible = not busy and GameManager.current_mode == GameManager.GameMode.SIMULATING
	if not active or GameManager.is_paused or not is_instance_valid(player):
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		if is_instance_valid(aim_guide):
			aim_guide.clear()
		return

	if not tournament_aim:
		# Owner round: this manager drives the group simulation forward and
		# decides when the round is over. A tournament round is owned by the
		# TournamentManager, which already advances the golfers and settles the
		# event, so here we only supply aiming for the owner.
		if is_instance_valid(manager):
			manager._update_golfers(delta)

		var finished := true
		for golfer in participants:
			if golfer.current_state != Golfer.State.FINISHED:
				finished = false
				break
		if finished:
			_show_results()
			return

	var is_ready := player.awaits_player_shot()
	var terrain: int = GameManager.terrain_grid.get_tile(Vector2i(player.ball_position_precise.round())) if GameManager.terrain_grid else -1
	for i in range(1, 4):
		shapes.set_item_disabled(i, not Golfer.shape_allowed(i, terrain))
	if not Golfer.shape_allowed(player.player_shape, terrain):
		player.player_shape = 0
		shapes.select(0)
	shapes.disabled = not is_ready
	punch.disabled = not is_ready
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if is_ready else Input.CURSOR_ARROW)
	update_aim_guide()

	# Track active shooter: the owner first (a tournament pairing has no local
	# participants list), then any owner-round opponent.
	var active_shooter: Golfer = null
	if player.current_state in [Golfer.State.PREPARING_SHOT, Golfer.State.SWINGING, Golfer.State.WATCHING]:
		active_shooter = player
	else:
		for golfer in participants:
			if golfer != player and golfer.current_state in [Golfer.State.PREPARING_SHOT, Golfer.State.SWINGING, Golfer.State.WATCHING]:
				active_shooter = golfer
				break

	# Focus camera on the player's character only when the user needs to aim their shot
	if is_ready and not _was_aiming:
		if is_instance_valid(player) and is_instance_valid(camera):
			camera.focus_on(player.global_position)
	_was_aiming = is_ready

	# Status text
	var hole_num = mini(player.current_hole + 1, GameManager.course_data.holes.size()) if GameManager.course_data else 1
	var action_text = ""
	if is_ready:
		action_text = "Your turn — Aim and click to shoot"
	elif active_shooter == player:
		action_text = "Automatic putting..." if terrain == TerrainTypes.Type.GREEN else "Taking shot..."
	elif active_shooter != null:
		action_text = "%s is shooting..." % active_shooter.golfer_name
	elif player.current_state == Golfer.State.WALKING:
		action_text = "Walking to ball..."
	elif player.current_state == Golfer.State.FINISHED:
		action_text = "You've holed out — waiting for the field"
	else:
		action_text = "Waiting for turn..."

	status.text = "%s · Hole %d · Stroke %d\n%s" % [player.golfer_name, hole_num, player.current_strokes + 1, action_text]
	if not tournament_aim:
		_update_live_scores()

## The top-left card carries the running scores: every player's score against par
## and how many holes they have in. Rows refresh in place, so this can run from
## `_process` without rebuilding the card each frame.
func _update_live_scores() -> void:
	if not is_instance_valid(scores):
		return
	var rows: Array = []
	for golfer in participants:
		if not is_instance_valid(golfer):
			continue
		rows.append({
			"name": golfer.golfer_name + (" (you)" if golfer == player else ""),
			"value": _score_text(golfer),
			"color": _score_color(golfer),
		})
	scores.set_scores(rows)

## "-1 · thru 4" once a card is filling up, "-" until the first hole is in.
func _score_text(golfer: Golfer) -> String:
	if golfer.hole_scores.is_empty():
		return "-"
	return "%s · thru %d" % [_format_diff(golfer.total_strokes - golfer.total_par),
		golfer.hole_scores.size()]

func _score_color(golfer: Golfer) -> Color:
	if golfer.hole_scores.is_empty():
		return UIConstants.COLOR_TEXT_DIM
	return UIConstants.get_score_color(golfer.total_strokes - golfer.total_par)

func _format_diff(diff: int) -> String:
	if diff == 0:
		return "E"
	return "%+d" % diff

## Refresh the aim guide for the mouse position, or for an explicit grid target
## (`target_override`, used by tests). The guide clears whenever the owner is not
## lining up a shot: walking, opponents' turns, automatic putting, results screen.
func update_aim_guide(target_override: Vector2i = Vector2i(-1, -1)) -> void:
	if not is_instance_valid(aim_guide):
		return
	var grid: TerrainGrid = GameManager.terrain_grid
	if not active or GameManager.is_paused or not is_instance_valid(grid) or not is_instance_valid(player) or not player.awaits_player_shot():
		aim_guide.clear()
		return
	var target := target_override
	if target == Vector2i(-1, -1):
		target = grid.screen_to_grid(get_global_mouse_position())
	aim_guide.show_preview(player.preview_shot(target))

func _unhandled_input(event: InputEvent) -> void:
	if not active or GameManager.is_paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_instance_valid(player) and player.awaits_player_shot() and GameManager.terrain_grid:
			var target: Vector2i = GameManager.terrain_grid.screen_to_grid(get_global_mouse_position())
			if player.play_shot(target):
				get_viewport().set_input_as_handled()

func _show_results() -> void:
	active = false
	_was_aiming = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if is_instance_valid(aim_guide):
		aim_guide.clear()
	_make_panel(true)
	participants.sort_custom(func(a: Golfer, b: Golfer): return a.total_strokes < b.total_strokes)
	var result := _result_text()
	if is_instance_valid(scores):
		# The final cards belong on the top-left card with the live scores. The
		# round page keeps the way out of the round.
		scores.begin("Round complete", result)
		for golfer in participants:
			scores.add_heading("%s — %d strokes (%s)" % [golfer.golfer_name,
				golfer.total_strokes, _format_diff(golfer.total_strokes - golfer.total_par)])
			for hole in golfer.hole_scores:
				scores.add_line("Hole %d: %d / Par %d" % [hole.hole, hole.strokes, hole.par])
		_label("ROUND COMPLETE")
		_button("Return to management", leave_round)
		return
	_show_results_on_page(result)

## "Winner: Pro Alex" / "Tie: A, B" once a match is over, empty for a solo round.
func _result_text() -> String:
	if round_kind <= 0 or participants.is_empty():
		return ""
	var winners: Array[String] = []
	for golfer in participants:
		if golfer.total_strokes == participants[0].total_strokes:
			winners.append(golfer.golfer_name)
	return ("Tie: " if winners.size() > 1 else "Winner: ") + ", ".join(winners)

## Scorecard fallback for rounds with no top-left card to write to (isolated
## tools and tests): the round page carries the cards as it always did.
func _show_results_on_page(result: String) -> void:
	_label("ROUND COMPLETE")
	if not result.is_empty():
		var result_label := _label(result)
		result_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if is_instance_valid(player_tab):
		_button("Return to management", leave_round)
	for golfer in participants:
		if is_instance_valid(player_tab):
			content = PlayerTab.add_column(player_tab.aim_page, 280)
		var summary := _label("%s — %d strokes (%s)" % [golfer.golfer_name, golfer.total_strokes, _format_diff(golfer.total_strokes - golfer.total_par)])
		summary.autowrap_mode = TextServer.AUTOWRAP_OFF
		var card_lines := ""
		for i in golfer.hole_scores.size():
			if is_instance_valid(player_tab) and i % 4 == 0 and i > 0:
				_label(card_lines.trim_suffix("\n"))
				content = PlayerTab.add_column(player_tab.aim_page, 280)
				var heading := _label(golfer.golfer_name + " · continued")
				heading.autowrap_mode = TextServer.AUTOWRAP_OFF
				card_lines = ""
			var hole: Dictionary = golfer.hole_scores[i]
			card_lines += "Hole %d: %d / Par %d\n" % [hole.hole, hole.strokes, hole.par]
		_label(card_lines.trim_suffix("\n"))
	if not is_instance_valid(player_tab):
		_button("Return to management", leave_round)

func leave_round(_restore_mode: bool = true) -> void:
	var was_tournament_aim := tournament_aim
	var had_round := busy
	if is_instance_valid(scores):
		scores.dismiss()
	active = false
	busy = false
	_was_aiming = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if is_instance_valid(aim_guide):
		aim_guide.clear()
	if not was_tournament_aim:
		# Owner round: remove the participants we spawned. A tournament golfer
		# belongs to the TournamentManager, which clears it on its own.
		for golfer in participants:
			if is_instance_valid(golfer):
				manager.remove_golfer(golfer.golfer_id)
	tournament_aim = false
	participants.clear()
	player = null
	if is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	content = null
	if had_round:
		if is_instance_valid(camera):
			camera.focus_on(previous_camera)
		# Day always runs in SIMULATING — keep simulation active after owner round
		if GameManager.current_mode != GameManager.GameMode.SIMULATING:
			GameManager.set_mode(GameManager.GameMode.SIMULATING)
		GameManager.set_speed(previous_speed if GameManager.current_mode == GameManager.GameMode.SIMULATING else GameManager.GameSpeed.NORMAL)

	if is_instance_valid(player_tab):
		_build_setup()

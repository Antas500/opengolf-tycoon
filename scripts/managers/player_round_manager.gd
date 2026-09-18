extends Node2D
class_name PlayerRoundManager
## Owner rounds run alongside the management simulation as a normal group.
signal session_opened

const PROS = ["Pro Alex", "Pro Morgan", "Pro Riley"]
var busy := false
var active := false
var player: Golfer
var participants: Array[Golfer] = []
var manager: GolferManager
var camera: IsometricCamera
var hud: Control
var layer: CanvasLayer
var entry: Button
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

func setup(golfers: GolferManager, view: IsometricCamera, management_hud: Control) -> void:
	manager = golfers
	camera = view
	hud = management_hud
	aim_guide = AimGuide.new()
	add_child(aim_guide)
	layer = CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	entry = Button.new()
	entry.text = "Play the Course"
	entry.position = Vector2(20, 76)
	entry.pressed.connect(open_setup)
	layer.add_child(entry)
	EventBus.game_mode_changed.connect(_on_mode_changed)
	EventBus.load_completed.connect(_on_load_completed)

func _exit_tree() -> void:
	if EventBus.game_mode_changed.is_connected(_on_mode_changed):
		EventBus.game_mode_changed.disconnect(_on_mode_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)

func _on_mode_changed(_old: int, mode: int) -> void:
	if busy and mode == GameManager.GameMode.MAIN_MENU:
		leave_round(false)

func _on_load_completed(_success: bool) -> void:
	if busy:
		leave_round(false)

func _make_panel(full_screen: bool) -> void:
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
	content.add_child(label)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	content.add_child(button)
	return button

func open_setup() -> void:
	if busy or GameManager.is_paused:
		return
	if GameManager.get_open_hole_count() == 0:
		EventBus.notify("Open at least one complete hole before playing.", "warning")
		return
	if GameManager.tournament_manager and GameManager.tournament_manager.is_tournament_in_progress():
		EventBus.notify("Finish the management tournament before playing a round.", "warning")
		return
	busy = true
	previous_mode = GameManager.current_mode
	previous_speed = GameManager.current_speed
	previous_camera = camera.global_position if is_instance_valid(camera) else Vector2.ZERO
	session_opened.emit()
	entry.hide()
	draft = PlayerGolferProfile.from_data(GameManager.player_profile.serialize())
	_make_panel(true)
	_label("PLAY YOUR COURSE")
	_label("Your golfer")
	name_edit = LineEdit.new()
	name_edit.max_length = 32
	name_edit.text = draft.golfer_name
	content.add_child(name_edit)
	for key in PlayerGolferProfile.COLORS:
		var row := HBoxContainer.new()
		content.add_child(row)
		var label := Label.new()
		label.text = key.replace("_", " ").capitalize()
		label.custom_minimum_size.x = 180
		row.add_child(label)
		var color := ColorPickerButton.new()
		color.color = Color(draft.appearance[key])
		color.edit_alpha = false
		color.custom_minimum_size = Vector2(100, 28)
		color.color_changed.connect(func(value: Color): draft.appearance[key] = value.to_html(false))
		row.add_child(color)
	_label("Round format")
	mode_picker = OptionButton.new()
	for title in ["Practice round", "Play vs a Pro", "Begin Tournament (4 golfers)"]:
		mode_picker.add_item(title)
	content.add_child(mode_picker)
	pro_picker = OptionButton.new()
	for pro in PROS:
		pro_picker.add_item(pro)
	content.add_child(pro_picker)
	pro_picker.disabled = true
	mode_picker.item_selected.connect(func(index: int): pro_picker.disabled = index != 1)
	points_label = _label("")
	_label("Each point adds 10% bonus. Maximum per skill: 990%.")
	skill_labels.clear()
	for i in PlayerGolferProfile.SKILLS.size():
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
	start_button = _button("Tee off", start_round)
	_button("Cancel", leave_round)
	_refresh_skills()

func _refresh_skills() -> void:
	points_label.text = "Skills locked for this golfer" if draft.initialized else "%d of 10 points remaining" % draft.remaining()
	for i in skill_labels.size():
		skill_labels[i].text = "%s: %d%%" % [PlayerGolferProfile.SKILLS[i], draft.points[i] * 10]
	start_button.disabled = not draft.initialized and draft.remaining() != 0

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
	elif round_kind == 2:
		for pro in PROS:
			_spawn(pro, GolferTier.Tier.PRO, group_id)

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
	_label("PLAY THE COURSE · " + ["Practice", "Vs Pro", "Tournament"][round_kind])
	status = _label("")
	shapes = OptionButton.new()
	for title in ["Straight shot", "Fade shot (L to R)", "Draw shot (R to L)", "High backspin shot"]:
		shapes.add_item(title)
	shapes.item_selected.connect(func(index: int): player.player_shape = index)
	content.add_child(shapes)
	punch = CheckButton.new()
	punch.text = "Low punch shot"
	punch.toggled.connect(func(value: bool): player.player_punch = value)
	content.add_child(punch)
	_label("Aim with the mouse · Click to shoot\nYellow arc = intended carry · dotted trail = roll until it stops\nGuide assumes a clean strike; wind, lie and slope still apply.\nPutting on the green is automatic.")
	_button("End round / Return to management", leave_round)
	_was_aiming = false

func _spawn(golfer_name: String, tier: int, group_id: int) -> Golfer:
	var golfer := manager.spawn_tournament_golfer(tier, group_id)
	golfer.is_owner_round = true
	golfer.golfer_name = golfer_name
	golfer._update_visual()
	participants.append(golfer)
	return golfer

func _process(delta: float) -> void:
	if not is_instance_valid(entry):
		return
	entry.visible = not busy and GameManager.current_mode == GameManager.GameMode.SIMULATING
	if not active or GameManager.is_paused:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		if is_instance_valid(aim_guide):
			aim_guide.clear()
		return

	# Drive group simulation forward via GolferManager
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

	var ready := player.awaits_player_shot()
	var terrain: int = GameManager.terrain_grid.get_tile(Vector2i(player.ball_position_precise.round())) if GameManager.terrain_grid else -1
	for i in range(1, 4):
		shapes.set_item_disabled(i, not Golfer.shape_allowed(i, terrain))
	if not Golfer.shape_allowed(player.player_shape, terrain):
		player.player_shape = 0
		shapes.select(0)
	shapes.disabled = not ready
	punch.disabled = not ready
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if ready else Input.CURSOR_ARROW)
	update_aim_guide()

	# Track active shooter in the group
	var active_shooter: Golfer = null
	for golfer in participants:
		if golfer.current_state in [Golfer.State.PREPARING_SHOT, Golfer.State.SWINGING, Golfer.State.WATCHING]:
			active_shooter = golfer
			break

	# Focus camera on the player's character only when the user needs to aim their shot
	if ready and not _was_aiming:
		if is_instance_valid(player) and is_instance_valid(camera):
			camera.focus_on(player.global_position)
	_was_aiming = ready

	# Status text
	var hole_num = mini(player.current_hole + 1, GameManager.course_data.holes.size()) if GameManager.course_data else 1
	var action_text = ""
	if ready:
		action_text = "Your turn — Aim and click to shoot"
	elif active_shooter == player:
		action_text = "Automatic putting..." if terrain == TerrainTypes.Type.GREEN else "Taking shot..."
	elif active_shooter != null:
		action_text = "%s is shooting..." % active_shooter.golfer_name
	elif player.current_state == Golfer.State.WALKING:
		action_text = "Walking to ball..."
	else:
		action_text = "Waiting for turn..."

	status.text = "%s · Hole %d · Stroke %d\n%s" % [player.golfer_name, hole_num, player.current_strokes + 1, action_text]
	for golfer in participants:
		var g_hole = mini(golfer.current_hole + 1, GameManager.course_data.holes.size()) if GameManager.course_data else 1
		status.text += "\n%s: %d strokes · Hole %d" % [golfer.golfer_name, golfer.total_strokes + golfer.current_strokes, g_hole]

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
		if is_instance_valid(player) and player.awaits_player_shot():
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
	_label("ROUND COMPLETE")
	participants.sort_custom(func(a: Golfer, b: Golfer): return a.total_strokes < b.total_strokes)
	if round_kind > 0:
		var winners: Array[String] = []
		for golfer in participants:
			if golfer.total_strokes == participants[0].total_strokes:
				winners.append(golfer.golfer_name)
		_label(("Tie: " if winners.size() > 1 else "Winner: ") + ", ".join(winners))
	for golfer in participants:
		_label("%s — %d strokes (%+d)" % [golfer.golfer_name, golfer.total_strokes, golfer.total_strokes - golfer.total_par])
		var scores := ""
		for hole in golfer.hole_scores:
			scores += "Hole %d: %d / Par %d\n" % [hole.hole, hole.strokes, hole.par]
		_label(scores)
	_button("Return to management", leave_round)

func leave_round(restore_mode: bool = true) -> void:
	var had_round := busy
	active = false
	busy = false
	_was_aiming = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if is_instance_valid(aim_guide):
		aim_guide.clear()
	for golfer in participants:
		if is_instance_valid(golfer):
			manager.remove_golfer(golfer.golfer_id)
	participants.clear()
	player = null
	if is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	if had_round:
		if is_instance_valid(camera):
			camera.focus_on(previous_camera)
		# Day always runs in SIMULATING — keep simulation active after owner round
		if GameManager.current_mode != GameManager.GameMode.SIMULATING:
			GameManager.set_mode(GameManager.GameMode.SIMULATING)
		GameManager.set_speed(previous_speed if GameManager.current_mode == GameManager.GameMode.SIMULATING else GameManager.GameSpeed.NORMAL)

extends Node2D
class_name PlayerRoundManager
## Owner rounds run beside, not inside, the revenue tournament system.
signal session_opened

const PROS = ["Pro Alex", "Pro Morgan", "Pro Riley"]
var busy := false
var active := false
var player: Golfer
var participants: Array[Golfer] = []
var visitors: Dictionary = {}
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
var previous_hud_visible := true
var round_kind := 0
var last_state := -1

func setup(golfers: GolferManager, view: IsometricCamera, management_hud: Control) -> void:
	manager = golfers
	camera = view
	hud = management_hud
	layer = CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	entry = Button.new()
	entry.text = "Play the Course"
	entry.position = Vector2(20, 76)
	entry.pressed.connect(open_setup)
	layer.add_child(entry)
	EventBus.game_mode_changed.connect(_on_mode_changed)

func _on_mode_changed(_old: int, mode: int) -> void:
	if busy and mode != GameManager.GameMode.PLAYING:
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
	panel.position = Vector2(24, 110) if not full_screen else Vector2(40, 40)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, minf(760, get_viewport_rect().size.y - 100)) if full_screen else Vector2(390, 280)
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
	previous_camera = camera.global_position
	for golfer in manager.get_active_golfers():
		visitors[golfer] = golfer.process_mode
		golfer.process_mode = Node.PROCESS_MODE_DISABLED
	GameManager.set_mode(GameManager.GameMode.PLAYING)
	GameManager.set_speed(GameManager.GameSpeed.NORMAL)
	session_opened.emit()
	previous_hud_visible = hud.visible
	hud.hide()
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
	player = _spawn(draft.golfer_name, GolferTier.Tier.CASUAL)
	player.player_profile = draft
	player.driving_skill = draft.normalized_skill(1)
	player.accuracy_skill = draft.normalized_skill(3)
	player.putting_skill = draft.normalized_skill(4)
	player.recovery_skill = draft.normalized_skill(8)
	player.miss_tendency = 0.0
	player.apply_player_appearance(draft)
	if round_kind == 1:
		_spawn(PROS[opponent], GolferTier.Tier.PRO)
	elif round_kind == 2:
		for pro in PROS:
			_spawn(pro, GolferTier.Tier.PRO)
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
	_label("Aim with the mouse · Click to shoot\nLine shows expected carry; wind and skill affect results.\nPutting on the green is automatic.")
	_button("End round / Return to management", leave_round)
	last_state = -1

func _spawn(golfer_name: String, tier: int) -> Golfer:
	var golfer := manager.spawn_tournament_golfer(tier, -1000 - participants.size())
	golfer.is_owner_round = true
	golfer.golfer_name = golfer_name
	golfer._update_visual()
	participants.append(golfer)
	return golfer

func _process(_delta: float) -> void:
	if not is_instance_valid(entry):
		return
	entry.visible = not busy and GameManager.current_mode in [GameManager.GameMode.BUILDING, GameManager.GameMode.SIMULATING]
	if not active or GameManager.is_paused:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		queue_redraw()
		return
	var finished := true
	for golfer in participants:
		if golfer.current_state == Golfer.State.IDLE:
			manager._advance_golfer(golfer)
		if golfer.current_state != Golfer.State.FINISHED:
			finished = false
	if finished:
		_show_results()
		return
	var ready := player.awaits_player_shot()
	var terrain: int = GameManager.terrain_grid.get_tile(Vector2i(player.ball_position_precise.round()))
	for i in range(1, 4):
		shapes.set_item_disabled(i, not Golfer.shape_allowed(i, terrain))
	if not Golfer.shape_allowed(player.player_shape, terrain):
		player.player_shape = 0
		shapes.select(0)
	shapes.disabled = not ready
	punch.disabled = not ready
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if ready else Input.CURSOR_ARROW)
	if player.current_state != last_state or player.current_state == Golfer.State.WALKING:
		camera.focus_on(player.global_position)
	last_state = player.current_state
	status.text = "%s · Hole %d · Stroke %d\n%s" % [player.golfer_name, mini(player.current_hole + 1, GameManager.course_data.holes.size()), player.current_strokes + 1,
		"Aim and click to shoot" if ready else ("Automatic putting" if terrain == TerrainTypes.Type.GREEN else "Walking / watching the shot")]
	for golfer in participants:
		status.text += "\n%s: %d strokes · %d holes finished" % [golfer.golfer_name, golfer.total_strokes + golfer.current_strokes, golfer.hole_scores.size()]
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not active or GameManager.is_paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var target: Vector2i = GameManager.terrain_grid.screen_to_grid(get_global_mouse_position())
		player.play_shot(target)
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not active or GameManager.is_paused or not is_instance_valid(player) or not player.awaits_player_shot():
		return
	var grid: TerrainGrid = GameManager.terrain_grid
	var target := grid.screen_to_grid(get_global_mouse_position())
	if not grid.is_valid_position(target):
		return
	var aim := player.player_aim(target)
	var direction := Vector2(aim - player.ball_position)
	var angle := deg_to_rad(8.0 if player.player_shape == 1 else (-8.0 if player.player_shape == 2 else 0.0))
	var origin := Vector2(player.ball_position)
	var points := PackedVector2Array()
	for i in range(25):
		var t := i / 24.0
		points.append(to_local(grid.grid_to_screen_precise(origin + direction.rotated(angle * t) * t)))
	draw_polyline(points, Color(1, 0.92, 0.4, 0.9), 2.5, true)
	draw_arc(points[-1], 7, 0, TAU, 24, Color.YELLOW, 2, true)

func _show_results() -> void:
	active = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	queue_redraw()
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
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	for golfer in participants:
		if is_instance_valid(golfer):
			manager.remove_golfer(golfer.golfer_id)
	participants.clear()
	player = null
	for golfer in visitors:
		if is_instance_valid(golfer):
			golfer.process_mode = visitors[golfer]
	visitors.clear()
	if is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	hud.visible = previous_hud_visible
	if had_round:
		camera.focus_on(previous_camera)
		if restore_mode:
			GameManager.set_mode(previous_mode)
			GameManager.set_speed(previous_speed)
	queue_redraw()

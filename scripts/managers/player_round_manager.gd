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
## The shot-type row on the Play Course tab (PlayerTab builds it): one button per
## shot type, replacing the old drop-down selector. Falls back to a row built
## into the floating panel when there is no Player tab (isolated tools, tests).
var shot_bar: ShotTypeBar
var draft: PlayerGolferProfile
var name_edit: LineEdit
## The Edit Player page's Golfer Skin controls: the picker for the skin the
## owner wears and one colour button per Re-color Group it carries (see
## _build_skin_controls). `_skin_controls` is the column they are rebuilt in.
var _skin_controls: VBoxContainer = null
var _skin_picker: OptionButton = null
var _skin_preview: Golfer = null
var _skin_preview_box: Control = null
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

## The Edit Player page's Golfer Skin controls: which skin the owner's golfer
## wears and a colour swatch for each Re-color Group that skin carries - the same
## groups the Edit Golfer Skins screen paints onto the sprite. Changing one
## writes the skin out (the player's own copy of it) and re-dresses the golfers
## on the course, so the owner sees the result during a round.
##
## The tab has no vertical scrolling - the page has to fit the bottom bar (see
## tests/unit/test_player_round.gd) - so this is one picker row with a small
## preview and one row of swatches, not a list of colour rows like the studio's.
func _build_skin_controls() -> void:
	_skin_controls = content
	_label("Golfer skin")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)

	_skin_picker = OptionButton.new()
	_skin_picker.name = "GolferSkinPicker"
	_skin_picker.tooltip_text = "Which Golfer Skin your golfer wears. The Edit Golfer Skins screen paints them."
	_skin_picker.custom_minimum_size = Vector2(180, 28)
	_skin_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skin_picker.set_meta("editable_while_playing", true)
	_skin_picker.item_selected.connect(_on_golfer_skin_selected)
	row.add_child(_skin_picker)

	_skin_preview_box = Control.new()
	_skin_preview_box.name = "SkinPreview"
	_skin_preview_box.custom_minimum_size = Vector2(48, 48)
	_skin_preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_skin_preview_box)
	_skin_preview = Golfer.new()
	_skin_preview.name = "SkinPreviewGolfer"
	_skin_preview.set_physics_process(false)
	_skin_preview_box.add_child(_skin_preview)

	_refresh_skin_controls()


## Fill the picker and the colour swatches in for the skin the owner wears right
## now. The groups come with the skin, so this runs again on every change.
func _refresh_skin_controls() -> void:
	if _skin_picker == null or _skin_controls == null:
		return
	var library := GolferSkins.library
	var skins := library.skins()
	_skin_picker.clear()
	for index in skins.size():
		_skin_picker.add_item(skins[index].display_name)
		_skin_picker.set_item_metadata(index, skins[index].id)
	var worn := GolferSkins.player_skin()
	for index in skins.size():
		if worn != null and skins[index].id == worn.id:
			_skin_picker.select(index)
	# One colour swatch per Re-color Group of the worn skin, under a heading.
	for child in _skin_controls.get_children():
		if child.has_meta("skin_group_row"):
			_skin_controls.remove_child(child)
			child.queue_free()
	if worn == null:
		return
	_label("Group colours")
	var swatches := HBoxContainer.new()
	swatches.set_meta("skin_group_row", true)
	swatches.add_theme_constant_override("separation", 4)
	_skin_controls.add_child(swatches)
	for group in worn.group_list():
		var group_id := int(group.get("id", 0))
		var swatch := ColorPickerButton.new()
		swatch.name = "SkinGroupColor%s" % str(group.get("name", "")).replace(" ", "")
		swatch.text = str(group.get("symbol", ""))
		swatch.color = group.get("color", Color.WHITE)
		swatch.edit_alpha = false
		swatch.custom_minimum_size = Vector2(30, 28)
		swatch.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		swatch.tooltip_text = "The colour %s is drawn in on this skin" % str(group.get("name", ""))
		swatch.set_meta("editable_while_playing", true)
		swatch.color_changed.connect(_on_skin_group_color_changed.bind(group_id))
		swatches.add_child(swatch)
	_refresh_skin_preview()


func _refresh_skin_preview() -> void:
	if _skin_preview == null or _skin_preview_box == null:
		return
	_skin_preview.player_profile = draft
	_skin_preview.position = _skin_preview_box.custom_minimum_size * 0.5
	if not _skin_preview.use_skin_sprites():
		return
	var sprite := _skin_preview.sprite_node()
	if sprite != null and sprite.sprite_frames.has_animation("idle_south"):
		sprite.play("idle_south")


## Wear one of the Golfer Skins: it belongs to the player rather than to the
## round, so GolferSkins writes the choice to the user settings at once.
func _on_golfer_skin_selected(index: int) -> void:
	if _skin_picker == null or index < 0 or index >= _skin_picker.item_count:
		return
	var chosen := GolferSkins.library.get_skin(str(_skin_picker.get_item_metadata(index)))
	if chosen == null:
		return
	GolferSkins.set_player_skin(chosen)
	GolferSkins.skins_changed.emit()
	_refresh_skin_controls()


## Re-colour one Re-color Group of the skin the owner wears. The skin is the
## player's own from here on (a shipped skin is copied to user://golfer_skins
## first), and the profile's matching appearance key keeps up with it.
func _on_skin_group_color_changed(color: Color, group_id: int) -> void:
	var skin := GolferSkins.player_skin()
	if skin == null:
		return
	if not GolferSkins.library.ensure_editable(skin):
		return
	if not skin.set_group_color(group_id, color):
		return
	GolferSkins.library.save_skin(skin)
	GolferSkins.skins_changed.emit()
	var key := GolferSkin.profile_key_for_group(str(skin.group_by_id(group_id).get("name", "")))
	if not key.is_empty():
		draft.appearance[key] = color.to_html(false)
	_refresh_skin_preview()


## The PlayerGolferProfile colour keys the Golfer Skin the owner wears does not
## name as a Re-color Group: those are the player's own colours, with no sprite
## to change.
func _standalone_profile_colors() -> Array:
	var worn := GolferSkins.player_skin()
	if worn == null:
		return PlayerGolferProfile.COLORS.duplicate()
	var named := []
	for group in worn.group_list():
		var key := GolferSkin.profile_key_for_group(str(group.get("name", "")))
		if not key.is_empty():
			named.append(key)
	var remaining := []
	for key in PlayerGolferProfile.COLORS:
		if not named.has(key):
			remaining.append(key)
	return remaining


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

## Point the shot-type buttons at the owner: the Play Course tab runs the row
## along its top, so a round only has to listen for presses and mirror the
## golfer's shot back onto it. Without the tab (isolated tools and tests) the row
## is built into the panel instead, so shot selection works the same way.
func _build_shot_controls() -> void:
	if is_instance_valid(player_tab):
		shot_bar = player_tab.shot_bar
	else:
		shot_bar = ShotTypeBar.new()
		content.add_child(shot_bar)
	if not shot_bar.shape_selected.is_connected(_on_shot_shape_selected):
		shot_bar.shape_selected.connect(_on_shot_shape_selected)
	shot_bar.select_shape(player.player_shape if is_instance_valid(player) else 0)
	shot_bar.set_ready(false)

func _on_shot_shape_selected(shape: int) -> void:
	if is_instance_valid(player):
		player.player_shape = shape

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
		# The golfer's skin and the colours of its Re-color Groups. These stay
		# editable during a round - dressing the owner is not part of the play
		# loop being protected (see start_round).
		content = PlayerTab.add_column(player_tab.pages[PlayerTab.PAGE_EDIT], 300)
		_build_skin_controls()
	# The player's own colours. The five the Golfer Skins name - Shirt, Pants,
	# Cap, Hair, Skin - are the colours of that skin's Re-color Groups and are
	# edited above (they follow into these fields); what is left here is the
	# appearance the polygon golfer falls back on when a skin has no sprites.
	var standalone := _standalone_profile_colors()
	var color_index := 0
	for key in standalone:
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
			button.pressed.connect(allocate_skill.bind(i, change))
			row.add_child(button)
	if is_instance_valid(player_tab):
		player_tab.restage_persistent()
		start_button = null
	else:
		start_button = _button("Tee off", start_round)
		_button("Cancel", leave_round)
	_refresh_skills()

func allocate_skill(index: int, change: int) -> bool:
	if draft == null:
		draft = PlayerGolferProfile.from_data(GameManager.player_profile.serialize())
	if not draft.allocate(index, change, true):
		return false
	_save_skills()
	_refresh_skills()
	return true

func _save_skills() -> void:
	if GameManager.player_profile == null:
		GameManager.player_profile = PlayerGolferProfile.new()
	GameManager.player_profile.points = draft.points.duplicate()
	if is_instance_valid(player):
		player.player_profile = GameManager.player_profile
		player.driving_skill = GameManager.player_profile.normalized_skill(1)
		player.accuracy_skill = GameManager.player_profile.normalized_skill(3)
		player.putting_skill = GameManager.player_profile.normalized_skill(4)
		player.recovery_skill = GameManager.player_profile.normalized_skill(8)
		if player.awaits_player_shot():
			update_aim_guide()
	if GameManager.tournament_manager and GameManager.tournament_manager.has_method("sync_player_skills"):
		GameManager.tournament_manager.sync_player_skills()

func _refresh_skills() -> void:
	points_label.text = "%d of 10 points remaining" % draft.remaining()
	for i in skill_labels.size():
		if i < PlayerGolferProfile.SKILLS.size():
			skill_labels[i].text = "%s: %d%%" % [PlayerGolferProfile.SKILLS[i], draft.points[i] * 10]
	if is_instance_valid(start_button):
		start_button.disabled = draft.remaining() != 0

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
	if draft.remaining() != 0:
		EventBus.notify("Allocate all 10 points in Player Skills first.", "info")
		player_tab.select(PlayerTab.PAGE_SKILLS)
		return
	busy = true
	previous_mode = GameManager.current_mode
	previous_speed = GameManager.current_speed
	previous_camera = camera.global_position if is_instance_valid(camera) else Vector2.ZERO
	mode_picker.select(clampi(kind, 0, maxi(0, mode_picker.item_count - 1)))
	session_opened.emit()
	start_round()

func start_round() -> void:
	if draft.remaining() != 0:
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
		# Lock the Edit Player page while the round runs - except the Golfer
		# Skin controls, which the player is meant to be able to reach during a
		# round (they only ever change how a golfer is drawn).
		for control in player_tab.pages[PlayerTab.PAGE_EDIT].find_children("*", "Control", true, false):
			if control.has_meta("editable_while_playing"):
				continue
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
	_build_shot_controls()
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
func begin_tournament_aim(owner_golfer: Golfer) -> void:
	if not is_instance_valid(owner_golfer) or owner_golfer.player_profile == null:
		return
	player = owner_golfer
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
	_build_shot_controls()
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
		# Nothing to aim at: grey the shot row out rather than leave a stale
		# selection lit while the round is paused or over.
		if is_instance_valid(shot_bar):
			shot_bar.set_ready(false)
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

	var is_ready := player.awaits_player_shot() and (not is_instance_valid(player_tab) or player_tab.selected == PlayerTab.PAGE_PLAY)
	var terrain: int = GameManager.terrain_grid.get_tile(Vector2i(player.ball_position_precise.round())) if GameManager.terrain_grid else -1
	if is_instance_valid(shot_bar):
		shot_bar.set_ready(is_ready)
		# Keep the row on the golfer's shot; a lie that no longer allows it
		# falls back to straight here, exactly as the execution guard does.
		shot_bar.select_shape(player.player_shape)
		shot_bar.update_for_lie(terrain)
		player.player_shape = shot_bar.selected_shape()
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
	elif player.current_state == Golfer.State.LEAVING:
		action_text = "Back to the clubhouse..."
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

## Refresh the guide for the mouse position, snapping the intended resting point
## to the nearest tile centre or vertex. Explicit tile-centre overrides are used
## by tests. The guide clears when the owner is not lining up a shot.
func update_aim_guide(target_override: Vector2i = Vector2i(-1, -1)) -> void:
	if not is_instance_valid(aim_guide):
		return
	var grid: TerrainGrid = GameManager.terrain_grid
	if not active or GameManager.is_paused or not is_instance_valid(grid) or not is_instance_valid(player) or not player.awaits_player_shot():
		aim_guide.clear()
		return
	if is_instance_valid(player_tab) and player_tab.selected != PlayerTab.PAGE_PLAY:
		aim_guide.clear()
		return
	var target: Vector2
	var anchor_type := ""
	if target_override == Vector2i(-1, -1):
		var anchor := grid.snap_world_to_tile_anchor(get_global_mouse_position())
		if anchor.is_empty():
			aim_guide.clear()
			return
		target = anchor.point
		anchor_type = anchor.anchor_type
	else:
		# Explicit tile overrides are useful to tests and resolve to that tile's
		# centre in the precise shot-aim coordinate system.
		target = Vector2(target_override)
	aim_guide.show_preview(player.preview_shot_to_rest(target, anchor_type))

func _unhandled_input(event: InputEvent) -> void:
	if not active or GameManager.is_paused:
		return
	if is_instance_valid(player_tab) and player_tab.selected != PlayerTab.PAGE_PLAY:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_instance_valid(player) and player.awaits_player_shot() and GameManager.terrain_grid:
			var grid: TerrainGrid = GameManager.terrain_grid
			var anchor := grid.snap_world_to_tile_anchor(get_global_mouse_position())
			if not anchor.is_empty() and player.play_shot_to_rest(anchor.point):
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

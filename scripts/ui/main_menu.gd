extends Control
class_name MainMenu
## MainMenu - Title screen with New Game (theme selection), Load, and Quit

signal new_game_requested(course_name: String, theme_type: int)
signal quick_start_requested(course_name: String, theme_type: int)
signal prebuilt_course_requested(course_name: String, theme_type: int, package_id: String)
signal load_game_requested()
signal settings_requested()
signal credits_requested()

var _theme_cards: Array = []
var _selected_theme: int = CourseTheme.Type.PARKLAND
var _selected_difficulty: int = DifficultyPresets.Preset.NORMAL
var _course_name_input: LineEdit = null
var _difficulty_buttons: Array = []
var _money_label: Label = null

## True on phones / small browser windows: narrower layout, scrollable.
func _is_compact_layout() -> bool:
	return has_node("/root/Screen") and Screen.is_compact()

func _ready() -> void:
	# Full-screen dark background
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.12, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Center everything in a VBoxContainer. The scroll wrapper keeps the whole
	# menu reachable on short screens (small phones, narrow browser windows)
	# while the center container keeps desktop layouts exactly as before.
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(scroll)

	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var compact := _is_compact_layout()
	var window_size := get_viewport().get_visible_rect().size

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12 if compact else 16)
	if compact:
		main_vbox.custom_minimum_size = Vector2(window_size.x - 48.0, 0)
	else:
		main_vbox.custom_minimum_size = Vector2(900, 720)
	center.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.text = "OpenGolf Tycoon"
	# Scale the title to the window width so it never overflows a phone.
	title.add_theme_font_size_override("font_size", int(clampf(window_size.x / 16.0, 26.0, 42.0)))
	title.add_theme_color_override("font_color", Color(0.85, 0.95, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(title)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Design. Build. Manage."
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.7, 0.5))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(subtitle)

	# Money display (visible when returning from a game with funds)
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 18)
	_money_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_money_display()
	main_vbox.add_child(_money_label)

	# Course name input
	var name_row = HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_label = Label.new()
	name_label.text = "Course Name: "
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7))
	name_row.add_child(name_label)

	_course_name_input = LineEdit.new()
	_course_name_input.text = "My Golf Course"
	if compact:
		# Narrow window: the field takes whatever width is left.
		_course_name_input.custom_minimum_size = Vector2(0, 35)
		_course_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		_course_name_input.custom_minimum_size = Vector2(300, 35)
	_course_name_input.add_theme_font_size_override("font_size", 16)
	name_row.add_child(_course_name_input)
	main_vbox.add_child(name_row)

	# Difficulty selector row (wraps to a 2x2 grid on narrow windows)
	if compact:
		var diff_label = Label.new()
		diff_label.text = "Difficulty"
		diff_label.add_theme_font_size_override("font_size", 16)
		diff_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7))
		main_vbox.add_child(diff_label)

		var diff_grid = GridContainer.new()
		diff_grid.columns = 2
		diff_grid.add_theme_constant_override("h_separation", 8)
		diff_grid.add_theme_constant_override("v_separation", 8)
		for preset in DifficultyPresets.get_all_presets():
			var mods = DifficultyPresets.get_modifiers(preset)
			var btn = Button.new()
			btn.text = mods["name"]
			btn.tooltip_text = mods["description"]
			btn.custom_minimum_size = Vector2(0, 32)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 14)
			btn.set_meta("preset", preset)
			btn.pressed.connect(_on_difficulty_selected.bind(preset))
			diff_grid.add_child(btn)
			_difficulty_buttons.append(btn)
		main_vbox.add_child(diff_grid)
	else:
		var diff_row = HBoxContainer.new()
		diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
		diff_row.add_theme_constant_override("separation", 12)

		var diff_label = Label.new()
		diff_label.text = "Difficulty: "
		diff_label.add_theme_font_size_override("font_size", 16)
		diff_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7))
		diff_row.add_child(diff_label)

		for preset in DifficultyPresets.get_all_presets():
			var mods = DifficultyPresets.get_modifiers(preset)
			var btn = Button.new()
			btn.text = mods["name"]
			btn.tooltip_text = mods["description"]
			btn.custom_minimum_size = Vector2(100, 32)
			btn.add_theme_font_size_override("font_size", 14)
			btn.set_meta("preset", preset)
			btn.pressed.connect(_on_difficulty_selected.bind(preset))
			diff_row.add_child(btn)
			_difficulty_buttons.append(btn)

		main_vbox.add_child(diff_row)
	_update_difficulty_selection()

	# Theme selection label
	var theme_label = Label.new()
	theme_label.text = "Select Course Theme"
	theme_label.add_theme_font_size_override("font_size", 20)
	theme_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.7))
	theme_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(theme_label)

	# Theme cards grid (2 columns on narrow windows so cards stay readable)
	var grid = GridContainer.new()
	grid.columns = 2 if compact else 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(grid)

	for theme_type in CourseTheme.get_all_types():
		var card = _create_theme_card(theme_type, compact)
		grid.add_child(card)
		_theme_cards.append(card)

	# Update initial selection visual
	_update_card_selection()

	# Buttons: single centered rows on desktop, a two-column full-width grid
	# on narrow windows (taller targets are easier to tap on touch screens).
	var saves = SaveManager.get_save_list()
	# [text, min_size, font, tooltip, callable]
	var actions: Array = []
	if not saves.is_empty():
		var latest = saves[0]
		actions.append(["Continue", Vector2(140, 45), 18,
			"%s - Day %d" % [latest.get("course_name", ""), latest.get("day", 0)],
			_on_continue_pressed.bind(latest.get("name", ""))])
	actions.append(["New Game", Vector2(140, 45), 18, "", _on_start_pressed])
	actions.append(["Quick Start", Vector2(140, 45), 18,
		"Start with a pre-built 9-hole course — jump straight in!", _on_quick_start_pressed])
	actions.append(["Prebuilt Course", Vector2(160, 45), 16,
		"Start with a professionally designed course layout", _on_prebuilt_pressed])
	actions.append(["Load Game", Vector2(140, 45), 16, "", _on_load_pressed])
	actions.append(["Settings", Vector2(120, 38), 15, "", _on_settings_pressed])
	actions.append(["Credits", Vector2(120, 38), 15, "", _on_credits_pressed])
	if OS.get_name() == "Web":  # Download button - only shown in web builds
		actions.append(["Download", Vector2(120, 38), 15,
			"Download the desktop version for better performance", _on_download_pressed])
	actions.append(["Quit", Vector2(100, 38), 15, "", _on_quit_pressed])

	if compact:
		var action_grid = GridContainer.new()
		action_grid.columns = 2
		action_grid.add_theme_constant_override("h_separation", 8)
		action_grid.add_theme_constant_override("v_separation", 8)
		for action in actions:
			var btn = Button.new()
			btn.text = str(action[0])
			if str(action[3]) != "":
				btn.tooltip_text = str(action[3])
			btn.custom_minimum_size = Vector2(0, 44)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 15)
			btn.pressed.connect(action[4])
			action_grid.add_child(btn)
		main_vbox.add_child(action_grid)
	else:
		# Row 1: main actions (Continue appears when saves exist)
		var btn_row = HBoxContainer.new()
		btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_row.add_theme_constant_override("separation", 16)
		# Row 2: Settings, Credits, [Download], Quit
		var btn_row2 = HBoxContainer.new()
		btn_row2.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_row2.add_theme_constant_override("separation", 16)
		for i in actions.size():
			var btn = Button.new()
			btn.text = str(actions[i][0])
			if str(actions[i][3]) != "":
				btn.tooltip_text = str(actions[i][3])
			btn.custom_minimum_size = actions[i][1]
			btn.add_theme_font_size_override("font_size", actions[i][2])
			btn.pressed.connect(actions[i][4])
			if i < 5:
				btn_row.add_child(btn)
			else:
				btn_row2.add_child(btn)
		main_vbox.add_child(btn_row)
		main_vbox.add_child(btn_row2)

	# Version label
	var version = Label.new()
	version.text = "v0.4.3"
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(version)

func _create_theme_card(theme_type: int, compact: bool = false) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 76) if compact else Vector2(280, 82)
	if compact:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta("theme_type", theme_type)

	# Make clickable
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(theme_type))

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Theme name with accent color
	var accent = CourseTheme.get_accent_color(theme_type)
	var name_label = Label.new()
	name_label.text = CourseTheme.get_theme_name(theme_type)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", accent)
	vbox.add_child(name_label)

	# Description
	var desc = Label.new()
	desc.text = CourseTheme.get_description(theme_type)
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size = Vector2(0, 0) if compact else Vector2(250, 0)
	vbox.add_child(desc)

	# Modifier hints
	var modifiers = CourseTheme.get_gameplay_modifiers(theme_type)
	var hints = []
	if modifiers.wind_base_strength > 1.2:
		hints.append("Strong wind")
	elif modifiers.wind_base_strength < 0.8:
		hints.append("Calm wind")
	if modifiers.distance_modifier > 1.02:
		hints.append("+Distance")
	if modifiers.maintenance_cost_multiplier < 0.8:
		hints.append("Low upkeep")
	elif modifiers.maintenance_cost_multiplier > 1.2:
		hints.append("High upkeep")
	if modifiers.green_fee_baseline >= 50:
		hints.append("Premium fees")
	elif modifiers.green_fee_baseline <= 20:
		hints.append("Budget fees")

	if not hints.is_empty():
		var hint_label = Label.new()
		hint_label.text = " | ".join(hints)
		hint_label.add_theme_font_size_override("font_size", 10)
		hint_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.5))
		vbox.add_child(hint_label)

	return card

func _on_card_input(event: InputEvent, theme_type: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_selected_theme = theme_type
		_update_card_selection()

func _update_card_selection() -> void:
	for card in _theme_cards:
		var theme_type = card.get_meta("theme_type")
		var style = StyleBoxFlat.new()

		if theme_type == _selected_theme:
			var accent = CourseTheme.get_accent_color(theme_type)
			style.bg_color = UIConstants.COLOR_PRIMARY_PRESSED
			style.border_color = accent
			style.set_border_width_all(2)
		else:
			style.bg_color = UIConstants.COLOR_BG_PANEL
			style.border_color = UIConstants.COLOR_BORDER
			style.set_border_width_all(1)

		style.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", style)

func _on_difficulty_selected(preset: int) -> void:
	_selected_difficulty = preset
	_update_difficulty_selection()

func _update_difficulty_selection() -> void:
	for btn in _difficulty_buttons:
		var preset = btn.get_meta("preset")
		if preset == _selected_difficulty:
			btn.modulate = Color(1.0, 1.0, 1.0)
			# Highlight selected button
			var style = StyleBoxFlat.new()
			style.bg_color = UIConstants.COLOR_PRIMARY
			style.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", style)
		else:
			btn.modulate = Color(0.7, 0.7, 0.7)
			# Remove override to use default style
			btn.remove_theme_stylebox_override("normal")

func get_selected_difficulty() -> int:
	return _selected_difficulty

func _on_continue_pressed(save_name: String) -> void:
	SaveManager.load_game(save_name)

func _on_start_pressed() -> void:
	var course_name = _course_name_input.text.strip_edges()
	if course_name.is_empty():
		course_name = "My Golf Course"
	new_game_requested.emit(course_name, _selected_theme)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("quick_start"):
		_on_quick_start_pressed()
		get_viewport().set_input_as_handled()

func _on_quick_start_pressed() -> void:
	var course_name = _course_name_input.text.strip_edges()
	if course_name.is_empty():
		course_name = "My Golf Course"
	quick_start_requested.emit(course_name, _selected_theme)

func _update_money_display() -> void:
	if not _money_label:
		return
	if GameManager.money > 0:
		_money_label.text = "Bank: $%s" % _format_money(GameManager.money)
		_money_label.visible = true
	else:
		_money_label.visible = false

static func _format_money(amount: int) -> String:
	var s = str(abs(amount))
	var result = ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	return result

func _on_prebuilt_pressed() -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "Prebuilt Course Packages"
	dialog.ok_button_text = "Cancel"
	dialog.min_size = Vector2(440, 0)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	# Show current money
	var money_label = Label.new()
	money_label.text = "Your money: $%s" % _format_money(GameManager.money)
	money_label.add_theme_font_size_override("font_size", 15)
	money_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	vbox.add_child(money_label)

	vbox.add_child(HSeparator.new())

	var packages = [
		{"id": "starter", "name": "Starter Pack", "desc": "3 holes (Par 4 + 3 + 5)", "cost": 25000},
		{"id": "executive", "name": "Executive 9", "desc": "9 par-3 holes — quick rounds", "cost": 75000},
		{"id": "standard9", "name": "Standard 9", "desc": "9 mixed holes (Par 36)", "cost": 100000},
		{"id": "championship18", "name": "Championship 18", "desc": "18 holes (Par 72)", "cost": 200000},
	]

	for pkg in packages:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var info = VBoxContainer.new()
		info.add_theme_constant_override("separation", 2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_lbl = Label.new()
		name_lbl.text = pkg.name
		name_lbl.add_theme_font_size_override("font_size", 14)
		info.add_child(name_lbl)

		var desc_lbl = Label.new()
		desc_lbl.text = pkg.desc
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		info.add_child(desc_lbl)
		row.add_child(info)

		var cost_lbl = Label.new()
		cost_lbl.text = "$%dk" % (pkg.cost / 1000)
		cost_lbl.add_theme_font_size_override("font_size", 13)
		cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
		cost_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cost_lbl)

		var buy_btn = Button.new()
		buy_btn.text = "Build"
		buy_btn.custom_minimum_size = Vector2(70, 30)
		buy_btn.disabled = GameManager.money < pkg.cost
		if buy_btn.disabled:
			buy_btn.tooltip_text = "Need $%d (you have $%d)" % [pkg.cost, GameManager.money]
		else:
			buy_btn.tooltip_text = "Start a new game with this course layout"
		var pkg_id = pkg.id
		buy_btn.pressed.connect(func():
			dialog.queue_free()
			_start_prebuilt_course(pkg_id, pkg.cost)
		)
		row.add_child(buy_btn)

		vbox.add_child(row)

	vbox.add_child(HSeparator.new())

	var note = Label.new()
	note.text = "Starts a new game with the selected course.\nYour money carries over (minus the package cost)."
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(note)

	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()


func _start_prebuilt_course(package_id: String, cost: int) -> void:
	# Deduct cost from current money before emitting
	# (main.gd will preserve this money across new_game)
	GameManager.money -= cost
	var course_name = _course_name_input.text.strip_edges()
	if course_name.is_empty():
		course_name = "My Golf Course"
	prebuilt_course_requested.emit(course_name, _selected_theme, package_id)


func _on_load_pressed() -> void:
	load_game_requested.emit()

func _on_settings_pressed() -> void:
	settings_requested.emit()

func _on_credits_pressed() -> void:
	credits_requested.emit()

func _on_download_pressed() -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "Download Desktop Version"
	dialog.ok_button_text = "Close"
	dialog.min_size = Vector2(360, 200)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	var info = Label.new()
	info.text = "Desktop versions run faster and support saving to disk."
	info.add_theme_font_size_override("font_size", 14)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(info)

	var base_url = "https://golf.kennyatx.com/downloads/"
	var platforms = [
		["Windows", base_url + "windows"],
		["macOS", base_url + "macos"],
		["Linux", base_url + "linux"],
	]
	for platform in platforms:
		var btn = Button.new()
		btn.text = "Download for " + platform[0]
		btn.custom_minimum_size = Vector2(300, 36)
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(OS.shell_open.bind(platform[1]))
		vbox.add_child(btn)

	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()

func _on_quit_pressed() -> void:
	get_tree().quit()

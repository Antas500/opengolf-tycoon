extends Control
class_name MainMenu
## MainMenu - Title screen.
##
## Six actions only: Start New Game (company setup → world map), Quick Start
## (default options → world map), Continue (newest save), Load Game, Settings
## and Quit.

signal start_new_game_requested()
signal quick_start_requested()
signal continue_requested(save_name: String)
signal load_game_requested()
signal settings_requested()
signal quit_requested()

var _continue_button: Button = null
var _load_button: Button = null

## True on phones / small browser windows: narrower layout, scrollable.
func _is_compact_layout() -> bool:
	return has_node("/root/Screen") and Screen.is_compact()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.12, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# The scroll wrapper keeps the whole menu reachable on short screens
	# (small phones, narrow browser windows).
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
	main_vbox.add_theme_constant_override("separation", 14 if compact else 18)
	if compact:
		main_vbox.custom_minimum_size = Vector2(window_size.x - 48.0, 0)
	else:
		main_vbox.custom_minimum_size = Vector2(520, 0)
	center.add_child(main_vbox)

	var title = Label.new()
	title.text = "OpenGolf Tycoon"
	title.add_theme_font_size_override("font_size", int(clampf(window_size.x / 16.0, 26.0, 42.0)))
	title.add_theme_color_override("font_color", Color(0.85, 0.95, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Design. Build. Manage."
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.7, 0.5))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(subtitle)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	main_vbox.add_child(spacer)

	# Six actions: Start New Game, Quick Start, Continue, Load Game, Settings, Quit.
	var saves = SaveManager.get_save_list()
	var latest: Dictionary = saves[0] if not saves.is_empty() else {}

	var start_btn = _make_button("Start New Game", 20, 52,
		"Set up your golf company, then choose where to build your first course")
	start_btn.pressed.connect(func(): start_new_game_requested.emit())
	main_vbox.add_child(start_btn)

	var quick_btn = _make_button("Quick Start", 20, 52,
		"Jump straight in: random company name, Normal difficulty, $100,000 and all features on")
	quick_btn.pressed.connect(func(): quick_start_requested.emit())
	main_vbox.add_child(quick_btn)

	_continue_button = _make_button("Continue", 18, 46, "")
	_continue_button.disabled = latest.is_empty()
	if latest.is_empty():
		_continue_button.tooltip_text = "No saved games yet"
	else:
		_continue_button.tooltip_text = "%s — Day %d (%s)" % [
			latest.get("course_name", ""), latest.get("day", 0), latest.get("name", "")]
	_continue_button.pressed.connect(func(): continue_requested.emit(continue_save_name()))
	main_vbox.add_child(_continue_button)

	_load_button = _make_button("Load Game", 18, 46, "Choose a saved game")
	_load_button.disabled = saves.is_empty()
	if saves.is_empty():
		_load_button.tooltip_text = "No saved games yet"
	_load_button.pressed.connect(func(): load_game_requested.emit())
	main_vbox.add_child(_load_button)

	var settings_btn = _make_button("Settings", 16, 40, "Audio, display and gameplay options")
	settings_btn.pressed.connect(func(): settings_requested.emit())
	main_vbox.add_child(settings_btn)

	var quit_btn = _make_button("Quit", 16, 40, "Leave the game")
	quit_btn.pressed.connect(func(): quit_requested.emit())
	main_vbox.add_child(quit_btn)

	var version = Label.new()
	version.text = "v0.4.5"
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(version)

## The newest save name, or an empty string when there is none.
func continue_save_name() -> String:
	var saves = SaveManager.get_save_list()
	if saves.is_empty():
		return ""
	return str(saves[0].get("name", ""))

func _make_button(text: String, font_size: int, height: int, tooltip: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(0, height if _is_compact_layout() else int(height * 0.8))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", font_size)
	return btn

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("quick_start"):
		quick_start_requested.emit()
		get_viewport().set_input_as_handled()

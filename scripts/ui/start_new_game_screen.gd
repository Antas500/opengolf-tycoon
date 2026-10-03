extends Control
class_name StartNewGameScreen
## StartNewGameScreen - Company setup shown after "Start New Game".
##
## Collects the company name, difficulty, starting budget, how many holes the
## first course should start with, and which game features are enabled. The
## Next button hands those options to the World Map screen, where the player
## buys the location for their first course.

signal next_requested(options: Dictionary)
signal back_requested()

## -1 is GameManager.UNLIMITED_MONEY (kept literal so this file has no
## autoload dependency at parse time).
const MONEY_OPTIONS: Array[int] = [100000, 150000, 200000, -1]
const HOLE_OPTIONS: Array[int] = [0, 3, 6, 9, 18]

var _company_input: LineEdit = null
var _difficulty_buttons: Array = []
var _money_buttons: Array = []
var _hole_buttons: Array = []
var _feature_boxes: Dictionary = {}
var _hole_hint: Label = null

var _difficulty: int = DifficultyPresets.Preset.NORMAL
var _money: int = 100000
var _holes: int = 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "StartNewGameScreen"

	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.12, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(scroll)

	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var compact := has_node("/root/Screen") and Screen.is_compact()
	var window_size := get_viewport().get_visible_rect().size

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10 if compact else 14)
	vbox.custom_minimum_size = Vector2(window_size.x - 48.0, 0) if compact else Vector2(720, 0)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "Start New Game"
	title.add_theme_font_size_override("font_size", int(clampf(window_size.x / 22.0, 22.0, 34.0)))
	title.add_theme_color_override("font_color", Color(0.85, 0.95, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_build_company_row(vbox, compact)
	_build_difficulty_section(vbox)
	_build_money_section(vbox)
	_build_holes_section(vbox)
	_build_features_section(vbox)
	_build_action_row(vbox)
	_update_selection_styles()

## ── Sections ─────────────────────────────────────────────────────────────

func _build_company_row(parent: VBoxContainer, compact: bool) -> void:
	parent.add_child(_section_label("Company Name"))
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)

	_company_input = LineEdit.new()
	_company_input.text = WorldLocations.random_company_name()
	_company_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_company_input.custom_minimum_size = Vector2(0 if compact else 320, 36)
	_company_input.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	_company_input.max_length = 40
	row.add_child(_company_input)

	var random_btn = Button.new()
	random_btn.text = "Random"
	random_btn.tooltip_text = "Pick a random company name"
	random_btn.custom_minimum_size = Vector2(90, 36)
	random_btn.pressed.connect(func():
		_company_input.text = WorldLocations.random_company_name())
	row.add_child(random_btn)

	parent.add_child(row)

func _build_difficulty_section(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("Difficulty"))
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	for preset in DifficultyPresets.get_all_presets():
		var modifiers := DifficultyPresets.get_modifiers(preset)
		var btn = _make_choice_button(str(modifiers.get("name", "Normal")), str(modifiers.get("description", "")))
		btn.set_meta("value", preset)
		btn.pressed.connect(_select_difficulty.bind(preset))
		row.add_child(btn)
		_difficulty_buttons.append(btn)
	parent.add_child(row)

func _build_money_section(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("Starting Money"))
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	for option in MONEY_OPTIONS:
		var btn = _make_choice_button(_money_label(option), "The company's opening balance. Location prices, land and buildings all come out of it.")
		btn.set_meta("value", option)
		btn.pressed.connect(_select_money.bind(option))
		row.add_child(btn)
		_money_buttons.append(btn)
	parent.add_child(row)

func _build_holes_section(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("Generated Holes on the First Course"))
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	for count in HOLE_OPTIONS:
		var btn = _make_choice_button(str(count), _holes_tooltip(count))
		btn.set_meta("value", count)
		btn.pressed.connect(_select_holes.bind(count))
		row.add_child(btn)
		_hole_buttons.append(btn)

	_hole_hint = Label.new()
	_hole_hint.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_hole_hint.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	_hole_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hole_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(row)
	box.add_child(_hole_hint)

	parent.add_child(box)

func _build_features_section(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("Enabled Game Features"))
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)

	var features := [
		[WorldMap.FEATURE_WEATHER, "Weather", "Storms and clouds change how often golfers come out and how they play."],
		[WorldMap.FEATURE_WIND, "Wind", "Wind pushes shots off line and changes how far they carry."],
		[WorldMap.FEATURE_SEASONS, "Seasons", "Demand, upkeep and weather shift with the calendar year."],
	]
	for feature in features:
		var check = CheckBox.new()
		check.text = str(feature[1])
		check.tooltip_text = str(feature[2])
		check.button_pressed = true
		check.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
		row.add_child(check)
		_feature_boxes[str(feature[0])] = check
	parent.add_child(row)

func _build_action_row(parent: VBoxContainer) -> void:
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)

	var back = Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 42)
	back.pressed.connect(func(): back_requested.emit())
	row.add_child(back)

	var next = Button.new()
	next.text = "Next"
	next.tooltip_text = "Choose the location for your first course"
	next.custom_minimum_size = Vector2(160, 42)
	next.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_LG)
	next.pressed.connect(_on_next_pressed)
	row.add_child(next)

	parent.add_child(row)

## ── Selection ────────────────────────────────────────────────────────────

func _select_difficulty(preset: int) -> void:
	_difficulty = preset
	_update_selection_styles()

func _select_money(option: int) -> void:
	_money = option
	_update_selection_styles()

func _select_holes(count: int) -> void:
	_holes = count
	_update_selection_styles()

func _update_selection_styles() -> void:
	_style_group(_difficulty_buttons, _difficulty)
	_style_group(_money_buttons, _money)
	_style_group(_hole_buttons, _holes)
	if _hole_hint:
		if _holes == 0:
			_hole_hint.text = "Build every hole yourself — the tutorial walks you through the first one."
		else:
			_hole_hint.text = "%d holes (%d par) are laid out for you on the location you buy. You can change them afterwards." % [
				_holes, GeneratedCourse.get_par_for_count(_holes)]

func _style_group(buttons: Array, selected: int) -> void:
	for btn in buttons:
		var is_selected := int(btn.get_meta("value")) == selected
		btn.modulate = Color(1.0, 1.0, 1.0) if is_selected else Color(0.72, 0.72, 0.72)
		if is_selected:
			var style = StyleBoxFlat.new()
			style.bg_color = UIConstants.COLOR_PRIMARY
			style.border_color = UIConstants.COLOR_GOLD
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", style)
		else:
			btn.remove_theme_stylebox_override("normal")

## ── Helpers ──────────────────────────────────────────────────────────────

func get_options() -> Dictionary:
	var company := _company_input.text.strip_edges() if _company_input else ""
	if company.is_empty():
		company = WorldLocations.random_company_name()
	var features: Dictionary = {}
	for key in _feature_boxes:
		features[key] = _feature_boxes[key].button_pressed
	return {
		"company_name": company,
		"difficulty": _difficulty,
		"starting_money": _money,
		"generated_holes": _holes,
		"features": features,
	}

func _on_next_pressed() -> void:
	next_requested.emit(get_options())

func _make_choice_button(text: String, tooltip: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(96, 38)
	btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	return btn

func _section_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_LG)
	label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.7))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

static func _money_label(option: int) -> String:
	if option == -1:
		return "Unlimited"
	return "$%s" % _group_digits(option)

static func _holes_tooltip(count: int) -> String:
	if count == 0:
		return "Start with an empty plot and build every hole yourself."
	return "%d holes are generated for your first course (Par %d)." % [count, GeneratedCourse.get_par_for_count(count)]

static func _group_digits(amount: int) -> String:
	var s := str(absi(amount))
	var result := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	return result

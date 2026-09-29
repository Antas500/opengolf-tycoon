extends CenteredPanel
class_name SeasonDebugPanel
## Debug panel for season manipulation and day skipping (F4)

signal close_requested

var _season_buttons: Array[Button] = []
var _current_label: Label = null

const SEASON_NAMES := ["Spring", "Summer", "Fall", "Winter"]

func _build_ui() -> void:
	custom_minimum_size = Vector2(380, 280)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title row with close button
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title := Label.new()
	title.text = "Season Debug (F4)"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(func(): close_requested.emit())
	title_row.add_child(close_btn)

	# Current status
	_current_label = Label.new()
	_current_label.add_theme_font_size_override("font_size", 12)
	_current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_current_label)

	vbox.add_child(HSeparator.new())

	# Season jump buttons
	var season_label := Label.new()
	season_label.text = "Jump to Season"
	season_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(season_label)

	var button_grid := GridContainer.new()
	button_grid.columns = 4
	button_grid.add_theme_constant_override("h_separation", 4)
	button_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(button_grid)

	for i in range(SEASON_NAMES.size()):
		var btn := Button.new()
		btn.text = SEASON_NAMES[i]
		btn.custom_minimum_size = Vector2(80, 30)
		btn.pressed.connect(_on_season_button.bind(i))
		button_grid.add_child(btn)
		_season_buttons.append(btn)

	vbox.add_child(HSeparator.new())

	# Modifier display
	var mod_label := Label.new()
	mod_label.text = "Current Modifiers"
	mod_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(mod_label)

	vbox.add_child(HSeparator.new())

	# Day control buttons
	var day_label := Label.new()
	day_label.text = "Day Controls"
	day_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(day_label)

	var day_row := HBoxContainer.new()
	day_row.add_theme_constant_override("separation", 8)
	vbox.add_child(day_row)

	var next_day_btn := Button.new()
	next_day_btn.text = "Next Day"
	next_day_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_day_btn.pressed.connect(_on_next_day)
	day_row.add_child(next_day_btn)

	var skip_btn := Button.new()
	skip_btn.text = "Skip 30 Days"
	skip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skip_btn.pressed.connect(_on_skip_30_days)
	day_row.add_child(skip_btn)

func show_centered() -> void:
	_update_display()
	super.show_centered()

func _update_display() -> void:
	if not _current_label:
		return

	var day = GameManager.current_day
	var season = SeasonSystem.get_season(day)
	var season_name = SeasonSystem.get_season_name(season)
	var spawn_mod = SeasonSystem.get_spawn_modifier(season)
	var maint_mod = SeasonSystem.get_maintenance_modifier(season)

	_current_label.text = "%s %s (Day %d) | Demand: %d%% | Maint: %d%%" % [
		season_name, GameCalendar.format_date_short(day), day,
		int(spawn_mod * 100), int(maint_mod * 100)
	]

	# Highlight active season button
	for i in range(_season_buttons.size()):
		if i == season:
			_season_buttons[i].add_theme_color_override("font_color", SeasonSystem.get_season_color(season))
		else:
			_season_buttons[i].remove_theme_color_override("font_color")

func _on_season_button(target_season: int) -> void:
	# Jump to day 1 of the target season by setting current_day directly
	var date := GameCalendar.get_date(GameManager.current_day)
	var year := int(date.year)
	var start_month: int = SeasonSystem.SEASON_START_MONTHS[target_season]
	# Winter (and any season whose start month is already past) targets the
	# next calendar year; seasons later this year stay in this year.
	if start_month <= int(date.month):
		year += 1
	var target_day: int = GameCalendar._days_from_civil(year, start_month, 1) - GameCalendar._EPOCH_DAYS + 1

	var old_season = SeasonSystem.get_season(GameManager.current_day)
	GameManager.current_day = target_day
	var new_season = SeasonSystem.get_season(target_day)

	if old_season != new_season:
		EventBus.season_changed.emit(old_season, new_season)

	# Regenerate weather for the new day
	if GameManager.weather_system:
		GameManager.weather_system.generate_daily_weather()
	if GameManager.wind_system:
		GameManager.wind_system.generate_daily_wind()

	EventBus.day_changed.emit(GameManager.current_day)
	EventBus.notify("Jumped to %s (Day %d)" % [SeasonSystem.get_season_name(new_season), target_day], "info")
	_update_display()

func _on_next_day() -> void:
	# Force one daily rollover immediately (bypasses the 3.5 s timer)
	GameManager._complete_day()
	_update_display()

func _on_skip_30_days() -> void:
	# Advance 30 days by directly manipulating current_day
	var old_season = SeasonSystem.get_season(GameManager.current_day)
	GameManager.current_day += 30
	var new_season = SeasonSystem.get_season(GameManager.current_day)

	if old_season != new_season:
		EventBus.season_changed.emit(old_season, new_season)

	# Regenerate weather and wind
	if GameManager.weather_system:
		GameManager.weather_system.generate_daily_weather()
	if GameManager.wind_system:
		GameManager.wind_system.generate_daily_wind()

	EventBus.day_changed.emit(GameManager.current_day)
	EventBus.notify("Skipped 30 days to Day %d" % GameManager.current_day, "info")
	_update_display()

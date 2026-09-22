extends PanelContainer
class_name HUDStatusColumn
## HUDStatusColumn - Vertical status readout docked to the top-right corner.
##
## Replaces the old full-width top bar. Every stat that used to be spread
## across the top of the screen (game mode, money, date/time, reputation,
## course rating, weather, wind) is now stacked as a compact label/value
## column, freeing the whole top edge of the viewport for the course view.
##
## The column sizes itself to its content and can be collapsed to a single
## summary row via the header button (or `set_collapsed()`).

signal money_clicked()
signal reputation_clicked()
signal rating_clicked()
signal collapsed_changed(is_collapsed: bool)

# UI References
var _game_mode_icon: Label
var _game_mode_label: Label
var _collapse_button: Button
var _details: VBoxContainer
var _money_button: Button
var _money_trend: Label
var _date_label: Label
var _time_label: Label
var _reputation_button: Button
var _weather_icon: Label
var _weather_label: Label
var _wind_label: Label
var _rating_button: Button

# State
var _last_money: int = 0
var _money_trend_value: int = 0
var _collapsed: bool = false

var _last_effectively_paused: bool = false

func _ready() -> void:
	add_to_group(UIConstants.HUD_COLUMN_GROUP)
	_apply_anchors()
	var eb := get_node_or_null("/root/EventBus")
	if eb and eb.has_signal("load_completed"):
		eb.load_completed.connect(func(_success): _update_all())
	_build_ui()
	_connect_signals()
	_update_all()
	minimum_size_changed.connect(_refresh_height)
	_refresh_height()

func _process(_delta: float) -> void:
	# The pause flag is set from several places that don't emit signals
	# (pause menu, end-of-day summary, game over, speed controls), so poll
	# the effective pause state and refresh the mode label when it changes.
	if not is_inside_tree():
		return
	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	var effectively_paused = gm.get("is_paused") == true or gm.get("current_speed") == 0
	if effectively_paused != _last_effectively_paused:
		_last_effectively_paused = effectively_paused
		_update_game_mode()

func _build_ui() -> void:
	custom_minimum_size = Vector2(UIConstants.HUD_COLUMN_WIDTH, 0)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# Column panel style — rounded card instead of an edge-to-edge bar
	var style = StyleBoxFlat.new()
	style.bg_color = UIConstants.COLOR_BG_PANEL
	style.set_border_width_all(1)
	style.border_color = UIConstants.COLOR_BORDER
	style.set_corner_radius_all(6)
	style.content_margin_left = UIConstants.MARGIN_MD
	style.content_margin_top = UIConstants.MARGIN_SM
	style.content_margin_right = UIConstants.MARGIN_MD
	style.content_margin_bottom = UIConstants.MARGIN_SM
	add_theme_stylebox_override("panel", style)

	var column = VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	add_child(column)

	# --- Header: game mode badge + collapse toggle ---
	var header = HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", UIConstants.SEPARATION_MD)
	column.add_child(header)

	_game_mode_icon = Label.new()
	_game_mode_icon.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	header.add_child(_game_mode_icon)

	_game_mode_label = Label.new()
	_game_mode_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_game_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_game_mode_label)

	_collapse_button = Button.new()
	_collapse_button.flat = true
	_collapse_button.text = "-"
	_collapse_button.focus_mode = Control.FOCUS_NONE
	_collapse_button.custom_minimum_size = Vector2(20, 18)
	_collapse_button.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_collapse_button.tooltip_text = "Collapse / expand the status column"
	_collapse_button.pressed.connect(func(): set_collapsed(not _collapsed))
	header.add_child(_collapse_button)

	column.add_child(_create_separator())

	# --- Money (always visible, even when collapsed) ---
	var money_value = HBoxContainer.new()
	money_value.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	money_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money_value.alignment = BoxContainer.ALIGNMENT_END

	_money_button = Button.new()
	_money_button.flat = true
	_money_button.focus_mode = Control.FOCUS_NONE
	_money_button.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	_money_button.pressed.connect(_on_money_pressed)
	_money_button.tooltip_text = "Click to view financial details"
	money_value.add_child(_money_button)

	_money_trend = Label.new()
	_money_trend.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_money_trend.custom_minimum_size = Vector2(10, 0)
	money_value.add_child(_money_trend)

	column.add_child(_create_row("Funds", money_value))

	# --- Collapsible details ---
	_details = VBoxContainer.new()
	_details.name = "Details"
	_details.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	column.add_child(_details)

	# Date / time
	_date_label = _create_value_label(UIConstants.FONT_SIZE_BASE)
	_details.add_child(_create_row("Date", _date_label))

	_time_label = _create_value_label(UIConstants.FONT_SIZE_BASE)
	_details.add_child(_create_row("Time", _time_label))

	_details.add_child(_create_separator())

	# Reputation
	_reputation_button = Button.new()
	_reputation_button.flat = true
	_reputation_button.focus_mode = Control.FOCUS_NONE
	_reputation_button.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_BASE)
	_reputation_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reputation_button.pressed.connect(_on_reputation_pressed)
	_reputation_button.tooltip_text = "Course reputation (click for rating details)"
	_details.add_child(_create_row("Reputation", _reputation_button))

	# Course rating
	_rating_button = Button.new()
	_rating_button.flat = true
	_rating_button.focus_mode = Control.FOCUS_NONE
	_rating_button.text = "-- (-.--)"
	_rating_button.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_BASE)
	_rating_button.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	_rating_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rating_button.pressed.connect(_on_rating_pressed)
	_rating_button.tooltip_text = "Course rating (click for details)"
	_details.add_child(_create_row("Rating", _rating_button))

	_details.add_child(_create_separator())

	# Weather
	var weather_value = HBoxContainer.new()
	weather_value.add_theme_constant_override("separation", UIConstants.SEPARATION_SM)
	weather_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weather_value.alignment = BoxContainer.ALIGNMENT_END

	_weather_icon = Label.new()
	_weather_icon.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	weather_value.add_child(_weather_icon)

	_weather_label = _create_value_label(UIConstants.FONT_SIZE_BASE)
	_weather_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	weather_value.add_child(_weather_label)

	_details.add_child(_create_row("Weather", weather_value))

	# Wind
	_wind_label = _create_value_label(UIConstants.FONT_SIZE_BASE)
	_details.add_child(_create_row("Wind", _wind_label))

## Build a "label ....... value" row. `value` may be any Control.
func _create_row(title: String, value: Control) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", UIConstants.SEPARATION_LG)

	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	title_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title_label)

	if not (value is BoxContainer):
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	return row

func _create_value_label(font_size: int) -> Label:
	var label = Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _create_separator() -> HSeparator:
	var sep = HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.modulate = Color(1, 1, 1, 0.25)
	return sep

# =============================================================================
# LAYOUT
# =============================================================================

## Pin the column to the top-right corner of its parent.
func _apply_anchors() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	offset_left = -(UIConstants.HUD_COLUMN_WIDTH + UIConstants.HUD_COLUMN_MARGIN)
	offset_right = -UIConstants.HUD_COLUMN_MARGIN
	offset_top = UIConstants.HUD_COLUMN_MARGIN
	_refresh_height()

## Keep the panel exactly as tall as its content (anchored controls need an
## explicit bottom offset).
func _refresh_height() -> void:
	offset_bottom = offset_top + get_combined_minimum_size().y

## Height the column currently occupies, including its top margin. Other HUD
## elements use this to avoid overlapping it.
func get_occupied_height() -> float:
	return offset_bottom

func is_collapsed() -> bool:
	return _collapsed

func set_collapsed(collapsed: bool) -> void:
	if _collapsed == collapsed:
		return
	_collapsed = collapsed
	if _details:
		_details.visible = not collapsed
	if _collapse_button:
		_collapse_button.text = "+" if collapsed else "-"
	_refresh_height()
	collapsed_changed.emit(_collapsed)

func _connect_signals() -> void:
	# Connect to EventBus signals
	if has_node("/root/EventBus"):
		var eb = get_node("/root/EventBus")
		eb.money_changed.connect(_on_money_changed)
		eb.day_changed.connect(_on_day_changed)
		eb.hour_changed.connect(_on_hour_changed)
		eb.reputation_changed.connect(_on_reputation_changed)
		eb.weather_changed.connect(_on_weather_changed)
		eb.wind_changed.connect(_on_wind_changed)
		eb.game_mode_changed.connect(_on_game_mode_changed)

func _update_all() -> void:
	_update_game_mode()
	_update_money()
	_update_day_time()
	_update_reputation()
	_update_weather()
	_update_wind()

func _update_game_mode() -> void:
	if not has_node("/root/GameManager"):
		return
	var gm = get_node("/root/GameManager")
	var mode = gm.get("current_mode")
	if mode == null:
		mode = 0

	# GameManager.GameMode enum: MAIN_MENU=0, BUILDING=1 (legacy), SIMULATING=2, PLAYING=3, PAUSED=4
	# Day always runs — BUILDING is kept for save compatibility but maps to PLAYING.
	# The game is effectively paused when the pause flag is set (pause menu,
	# end-of-day summary, game over) or the speed control is on pause.
	var effectively_paused = gm.get("is_paused") == true or gm.get("current_speed") == 0
	match mode:
		1, 2, 3, 4:  # BUILDING (legacy), SIMULATING, PLAYING, PAUSED
			if effectively_paused:
				_game_mode_icon.text = "||"
				_game_mode_label.text = "PAUSED"
				_game_mode_icon.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
				_game_mode_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
			else:
				_game_mode_icon.text = ">"
				_game_mode_label.text = "PLAYING"
				_game_mode_icon.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)
				_game_mode_label.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)
		_:
			_game_mode_icon.text = "?"
			_game_mode_label.text = "MENU"
			_game_mode_icon.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
			_game_mode_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)

func _update_money() -> void:
	if not has_node("/root/GameManager"):
		return
	var gm = get_node("/root/GameManager")
	var money = gm.get("money")
	if money == null:
		money = GameManager.DEFAULT_STARTING_MONEY

	_money_button.text = "$ %s" % _format_number(money)

	# Color based on balance
	if money < 0:
		_money_button.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)
	elif money < 5000:
		_money_button.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
	else:
		_money_button.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)

	# Trend indicator
	if _money_trend_value > 0:
		_money_trend.text = "^"
		_money_trend.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)
	elif _money_trend_value < 0:
		_money_trend.text = "v"
		_money_trend.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)
	else:
		_money_trend.text = ""

	_last_money = money

func _update_day_time() -> void:
	if not has_node("/root/GameManager"):
		return
	var gm = get_node("/root/GameManager")
	var day = gm.get("current_day")
	var hour = gm.get("current_hour")
	if day == null:
		day = 1
	if hour == null:
		hour = 6.0

	var hour_int = int(hour)
	var minute = int((hour - hour_int) * 60)
	var am_pm = "AM" if hour_int < 12 else "PM"
	var display_hour = hour_int if hour_int <= 12 else hour_int - 12
	if display_hour == 0:
		display_hour = 12

	var season = SeasonSystem.get_season(day)
	var season_name = SeasonSystem.get_season_name(season)
	var day_in_season = SeasonSystem.get_day_in_season(day)
	var year = SeasonSystem.get_year(day)
	_date_label.text = "%s D%d Y%d" % [season_name, day_in_season, year]
	_time_label.text = "%d:%02d %s" % [display_hour, minute, am_pm]

func _update_reputation() -> void:
	if not has_node("/root/GameManager"):
		return
	var gm = get_node("/root/GameManager")
	var rep = gm.get("reputation")
	if rep == null:
		rep = 50.0

	_reputation_button.text = "%d%%" % int(rep)

	# Color based on reputation
	if rep >= 75:
		_reputation_button.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)
	elif rep >= 40:
		_reputation_button.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
	else:
		_reputation_button.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)

func _update_weather() -> void:
	if not has_node("/root/GameManager"):
		_weather_icon.text = "* *"
		_weather_label.text = "Sunny"
		return

	var gm = get_node("/root/GameManager")
	var weather_system = gm.get("weather_system")
	if weather_system == null:
		_weather_icon.text = "* *"
		_weather_label.text = "Sunny"
		return

	var weather_type = weather_system.get("weather_type")
	if weather_type == null:
		weather_type = 0

	_weather_icon.text = UIConstants.get_weather_icon(weather_type)
	_weather_label.text = UIConstants.get_weather_name(weather_type)

	# Color based on weather
	match weather_type:
		0:  # SUNNY
			_weather_icon.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
		1, 2:  # PARTLY_CLOUDY, OVERCAST
			_weather_icon.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
		_:  # RAIN
			_weather_icon.add_theme_color_override("font_color", UIConstants.COLOR_INFO)

func _update_wind() -> void:
	if not has_node("/root/GameManager"):
		_wind_label.text = "0 mph"
		return

	var gm = get_node("/root/GameManager")
	var wind_system = gm.get("wind_system")
	if wind_system == null:
		_wind_label.text = "0 mph"
		return

	var speed = wind_system.get("wind_speed")
	var direction = wind_system.get("wind_direction")
	if speed == null:
		speed = 0.0
	if direction == null:
		direction = 0.0

	# Convert radians to degrees for direction name
	var degrees = fmod(rad_to_deg(direction) + 360.0, 360.0)
	var dir_name = _get_direction_name(degrees)
	_wind_label.text = "%s %d mph" % [dir_name, int(speed)]

	# Color based on wind speed
	if speed < 5:
		_wind_label.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)
	elif speed < 15:
		_wind_label.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
	else:
		_wind_label.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)

func _get_direction_name(degrees: float) -> String:
	var dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var index = int(round(degrees / 45.0)) % 8
	return dirs[index]

func _format_number(num: int) -> String:
	var str_num = str(abs(num))
	var result = ""
	var count = 0
	for i in range(str_num.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_num[i] + result
		count += 1
	if num < 0:
		result = "-" + result
	return result

# Signal handlers
func _on_money_pressed() -> void:
	money_clicked.emit()

func _on_reputation_pressed() -> void:
	reputation_clicked.emit()

func _on_rating_pressed() -> void:
	rating_clicked.emit()

func update_rating(stars: float) -> void:
	var display := CourseRatingSystem.get_star_display(stars)
	_rating_button.text = "%s (%.1f)" % [display, stars]
	if stars >= 4.0:
		_rating_button.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	elif stars >= 3.0:
		_rating_button.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)
	elif stars >= 2.0:
		_rating_button.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
	else:
		_rating_button.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)

func _on_money_changed(old_amount: int, new_amount: int) -> void:
	_money_trend_value = new_amount - old_amount
	_update_money()

func _on_day_changed(_new_day: int) -> void:
	_update_day_time()

func _on_hour_changed(_new_hour: float) -> void:
	_update_day_time()

func _on_reputation_changed(_old_rep: float, _new_rep: float) -> void:
	_update_reputation()

func _on_weather_changed(_weather_type: int, _intensity: float) -> void:
	_update_weather()

func _on_wind_changed(_direction: float, _speed: float) -> void:
	_update_wind()

func _on_game_mode_changed(_old_mode: int, _new_mode: int) -> void:
	_update_game_mode()

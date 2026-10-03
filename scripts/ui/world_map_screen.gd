extends Control
class_name WorldMapScreen
## WorldMapScreen - The company's globe: buy locations and switch between them.
##
## Left: the draggable GlobeMap with a marker per location. Right: the location
## list with each location's name, theme, size and cost, plus its action button
## (Buy / Play). Bottom: Reset World, which re-rolls how much land every
## unowned location starts with — and therefore what it costs.
##
## The screen is opened from the main menu (Start New Game / Quick Start) and
## from the pause menu (World Map). It never starts a course itself: it asks
## Main to play a location through `play_location_requested`.

signal play_location_requested(location_id: String)
signal back_requested()

const ROW_HEIGHT := 56
## Shorter rows on narrow windows, where vertical space is scarce.
const COMPACT_ROW_HEIGHT := 48
const ROW_SELECTED_BG := Color(0.22, 0.36, 0.28, 1.0)
## Below this window height the globe and the list do not stack: a stacked
## globe (min 240px) plus a list (min 260px) needs the room, and a squat window
## would push the list off the bottom of the screen entirely.
const STACKED_MIN_HEIGHT := 660.0

var globe: GlobeMap = null
var _list_box: VBoxContainer = null
var _rows: Dictionary = {}
var _money_label: Label = null
var _summary_label: Label = null
var _hint_label: Label = null
var _selected_id: String = ""
var _first_show: bool = true
## True on phones / small browser windows (tighter padding, shorter row text).
var _compact: bool = false
## True while the built layout stacks the globe above the list.
var _stacked_built: bool = false

func _ready() -> void:
	name = "WorldMapScreen"
	_build()
	# Narrow windows stack the globe above the list when they are tall enough to
	# hold both; a live resize or rotation that changes the arrangement (or the
	# compact flag) rebuilds the screen.
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	if WorldMap.locations.is_empty():
		WorldMap.new_world(WorldMap.default_options())
	refresh()

func _on_screen_changed(_size: Vector2, _scale: float) -> void:
	if Screen.is_compact() == _compact and _stacked() == _stacked_built:
		return
	_build()
	refresh()

## True when the globe goes above the list rather than beside it.
func _stacked() -> bool:
	if not has_node("/root/Screen") or not Screen.is_compact():
		return false
	return Screen.window_size.y >= STACKED_MIN_HEIGHT

## Build (or rebuild) the whole screen for the current window size.
func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_selected_id = "" if _rows.is_empty() else _selected_id

	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.10, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var compact := has_node("/root/Screen") and Screen.is_compact()
	_compact = compact
	_stacked_built = _stacked()
	var pad := 10 if compact else 18
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	add_child(margin)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	root_vbox.add_child(_build_header())
	root_vbox.add_child(_build_body(compact, _stacked_built))

## ── Layout ───────────────────────────────────────────────────────────────

func _build_header() -> Control:
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	var back = Button.new()
	back.text = "< Back"
	back.tooltip_text = "Back to the main menu"
	back.custom_minimum_size = Vector2(96, 40)
	back.pressed.connect(func(): back_requested.emit())
	header.add_child(back)

	var title_box = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.custom_minimum_size = Vector2(0, 0)

	var title = Label.new()
	title.text = "World Map"
	title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XL)
	title.add_theme_color_override("font_color", Color(0.85, 0.95, 0.75))
	title_box.add_child(title)

	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_summary_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	# Long company/feature summaries must never widen the screen past the
	# window: clip instead, and keep the short form on compact layouts.
	_summary_label.clip_text = true
	_summary_label.custom_minimum_size = Vector2(0, 0)
	title_box.add_child(_summary_label)
	header.add_child(title_box)

	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XL)
	_money_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_label.clip_text = true
	_money_label.custom_minimum_size = Vector2(0, 0)
	header.add_child(_money_label)

	return header

func _build_body(compact: bool, stacked: bool) -> Control:
	# Wide windows (and squat ones) read globe-left / list-right; a tall narrow
	# window (portrait phone, portrait tablet) stacks the globe above the list.
	var body: BoxContainer = VBoxContainer.new() if stacked else HBoxContainer.new()
	body.add_theme_constant_override("separation", 10 if compact else 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Globe panel (left / top)
	var globe_panel = PanelContainer.new()
	globe_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	globe_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if stacked:
		globe_panel.custom_minimum_size = Vector2(0, 240)
	var globe_style = StyleBoxFlat.new()
	globe_style.bg_color = UIConstants.COLOR_BG_PANEL
	globe_style.border_color = UIConstants.COLOR_BORDER
	globe_style.set_border_width_all(1)
	globe_style.set_corner_radius_all(6)
	globe_panel.add_theme_stylebox_override("panel", globe_style)

	var globe_box = VBoxContainer.new()
	globe_box.add_theme_constant_override("separation", 6)
	globe_panel.add_child(globe_box)

	globe = GlobeMap.new()
	globe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	globe.location_clicked.connect(_on_globe_location_clicked)
	globe_box.add_child(globe)

	_hint_label = Label.new()
	_hint_label.text = "Drag the globe to spin it  ·  Scroll to zoom  ·  Click a marker or a location in the list"
	_hint_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	_hint_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.clip_text = true
	_hint_label.custom_minimum_size = Vector2(0, 0)
	globe_box.add_child(_hint_label)

	body.add_child(globe_panel)

	# Location list (right / bottom). It always fills the height it is given:
	# with a shrink flag the panel collapses to its bare minimum and the rows
	# (and their Buy / Play buttons) get clipped away entirely.
	var list_panel = PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(0, 260) if stacked else Vector2(430, 260)
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if stacked else Control.SIZE_FILL
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_theme_stylebox_override("panel", globe_style)

	var list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 6)
	list_panel.add_child(list_box)

	var list_title = Label.new()
	list_title.text = "Course Locations"
	list_title.clip_text = true
	list_title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_LG)
	list_title.add_theme_color_override("font_color", Color(0.8, 0.9, 0.7))
	list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_box.add_child(list_title)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Room for four rows even if an outer container squeezes the panel.
	scroll.custom_minimum_size = Vector2(0, 4 * ROW_HEIGHT + 8)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_box.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_box)

	var footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)

	var reset = Button.new()
	reset.text = "Reset World"
	reset.tooltip_text = "Re-roll how much land each unowned location starts with. More ready land means a higher price; locations you own never change."
	reset.custom_minimum_size = Vector2(140, 38)
	reset.pressed.connect(_on_reset_world_pressed)
	footer.add_child(reset)

	var close = Button.new()
	close.text = "Close"
	close.tooltip_text = "Return to the menu (Escape)"
	close.custom_minimum_size = Vector2(100, 38)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func(): back_requested.emit())
	footer.add_child(close)

	list_box.add_child(footer)
	body.add_child(list_panel)

	return body

## ── Refresh ──────────────────────────────────────────────────────────────

## Rebuild the list and the globe markers from WorldMap state.
func refresh() -> void:
	if not is_instance_valid(_list_box) or not is_instance_valid(globe):
		return
	for child in _list_box.get_children():
		child.queue_free()
	_rows.clear()

	var markers: Array = []
	for def in WorldLocations.get_all():
		var id := str(def["id"])
		var state := _row_state(def)
		markers.append(state)
		var row := _build_row(state, _compact)
		_list_box.add_child(row)
		_rows[id] = row
		row.gui_input.connect(_on_row_input.bind(id))

	globe.set_locations(markers)
	if _selected_id.is_empty() or not _rows.has(_selected_id):
		# Default to the player's current course, else the first location.
		_selected_id = WorldMap.active_location_id if WorldMap.is_owned(WorldMap.active_location_id) \
			else str(WorldLocations.get_all()[0]["id"])
	if _first_show:
		_first_show = false
		globe.set_selected(_selected_id)
		globe.look_at_location(_selected_id)
	else:
		globe.set_selected(_selected_id)
	_update_header()
	_update_row_styles()

func _update_header() -> void:
	var difficulty_name := DifficultyPresets.get_preset_name(WorldMap.difficulty)
	var features: Array = []
	for key in WorldMap.FEATURE_KEYS:
		if bool(WorldMap.features.get(key, true)):
			features.append(str(key).capitalize())
	if features.is_empty():
		features.append("No features")
	if _compact:
		_summary_label.text = "%s  ·  %s  ·  %d holes" % [
			WorldMap.company_name, difficulty_name, WorldMap.generated_holes]
	else:
		_summary_label.text = "%s  ·  %s  ·  %d generated holes  ·  %s" % [
			WorldMap.company_name, difficulty_name, WorldMap.generated_holes, ", ".join(features)]
	_money_label.text = _format_money(GameManager.money) if not GameManager.unlimited_money \
		else "Unlimited"

## Everything a row (and the matching globe marker) needs to render.
func _row_state(def: Dictionary) -> Dictionary:
	var id := str(def["id"])
	var owned := WorldMap.is_owned(id)
	return {
		"id": id,
		"name": str(def["name"]),
		"region": str(def.get("region", "")),
		"theme_name": CourseTheme.get_theme_name(int(def["theme"])),
		"size_name": WorldLocations.get_size_name(int(def["size"])),
		"parcels": WorldMap.get_total_parcels(id),
		"ready": WorldMap.get_unlocked_parcels(id).size(),
		"price": WorldMap.get_price(id),
		"owned": owned,
		"active": id == WorldMap.active_location_id,
		"affordable": owned or GameManager.can_afford(WorldMap.get_price(id)),
		"lat": float(def.get("lat", 0.0)),
		"lon": float(def.get("lon", 0.0)),
	}

func _build_row(state: Dictionary, compact: bool = false) -> PanelContainer:
	var row = PanelContainer.new()
	# Compact rows are shorter so a squat window still shows a useful slice of
	# the list instead of one clipped row.
	row.custom_minimum_size = Vector2(0, COMPACT_ROW_HEIGHT if compact else ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_meta("location_id", state["id"])
	row.tooltip_text = "%s — %s\n%s (%d holes) · %d of %d plots ready to build on\n%s" % [
		state["name"], state["region"], state["size_name"],
		WorldLocations.get_hole_capacity(WorldLocations.get_definition(state["id"])["size"]),
		state["ready"], state["parcels"],
		WorldLocations.get_definition(state["id"]).get("description", "")]

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8 if compact else 10)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 3 if compact else 6)
	margin.add_theme_constant_override("margin_bottom", 3 if compact else 6)
	row.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)

	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(0, 0)
	hbox.add_child(info)

	var name_label = Label.new()
	name_label.text = "%s  ·  %s" % [state["name"], state["region"]] if state["region"] != "" else str(state["name"])
	name_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	name_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT)
	name_label.clip_text = true
	info.add_child(name_label)

	var detail = Label.new()
	detail.text = "%s · %s" % [state["theme_name"], state["size_name"]] if compact \
		else "%s · %s · %d/%d plots ready" % [
			state["theme_name"], state["size_name"], state["ready"], state["parcels"]]
	detail.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	detail.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	detail.clip_text = true
	info.add_child(detail)

	var cost = Label.new()
	cost.text = "Owned" if state["owned"] else _format_money(state["price"])
	cost.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_MD)
	cost.add_theme_color_override("font_color",
		UIConstants.COLOR_SUCCESS if state["owned"] else (Color(0.9, 0.8, 0.3) if state["affordable"] else UIConstants.COLOR_DANGER))
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.custom_minimum_size = Vector2(64 if compact else 84, 0)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(cost)

	var action = Button.new()
	action.custom_minimum_size = Vector2(64 if compact else 76, 30 if compact else 34)
	action.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_BASE)
	if state["owned"]:
		if state["active"]:
			action.text = "Playing"
			action.disabled = true
			action.tooltip_text = "This is the course you are playing right now"
		else:
			action.text = "Play"
			action.tooltip_text = "Switch to this course — the course you leave keeps every change"
			action.pressed.connect(func(): play_location_requested.emit(state["id"]))
	else:
		action.text = "Buy"
		action.disabled = not state["affordable"]
		action.tooltip_text = "Buy %s for %s and unlock %d plots of land to build on" % [
			state["name"], _format_money(state["price"]), state["ready"]] if state["affordable"] \
			else "You need %s to buy %s" % [_format_money(state["price"]), state["name"]]
		action.pressed.connect(_on_buy_pressed.bind(state["id"]))
	hbox.add_child(action)

	return row

## ── Interaction ──────────────────────────────────────────────────────────

func _on_row_input(event: InputEvent, location_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select_location(location_id)

func _on_globe_location_clicked(location_id: String) -> void:
	select_location(location_id)
	globe.look_at_location(location_id)

## Highlight a location in the list (and on the globe).
func select_location(location_id: String) -> void:
	if not _rows.has(location_id):
		return
	_selected_id = location_id
	globe.set_selected(location_id)
	_update_row_styles()

func _update_row_styles() -> void:
	for id in _rows:
		var row: PanelContainer = _rows[id]
		var selected: bool = id == _selected_id
		var style = StyleBoxFlat.new()
		style.bg_color = ROW_SELECTED_BG if selected else UIConstants.COLOR_BG_BUTTON
		style.border_color = UIConstants.COLOR_GOLD if selected else UIConstants.COLOR_BORDER
		style.set_border_width_all(2 if selected else 1)
		style.set_corner_radius_all(4)
		row.add_theme_stylebox_override("panel", style)

func _on_buy_pressed(location_id: String) -> void:
	if WorldMap.buy_location(location_id):
		select_location(location_id)
		globe.look_at_location(location_id)
	refresh()

func _on_reset_world_pressed() -> void:
	var dialog := ConfirmDialog.new(
		"Reset the world?\n\nEvery location you have not bought yet gets a new amount of land ready to build on, so its price changes. Locations you own are untouched.",
		"Reset World", "Cancel", UIConstants.COLOR_WARNING)
	add_child(dialog)
	dialog.confirmed.connect(func():
		WorldMap.reset_world()
		refresh()
		EventBus.notify("World reset — location prices and ready land re-rolled.", "info"))
	dialog.cancelled.connect(func(): pass)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

static func _format_money(amount: int) -> String:
	var s := str(absi(amount))
	var result := "$"
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	return result

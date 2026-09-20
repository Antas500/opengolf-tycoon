extends PanelContainer
class_name TerrainToolbar
## TerrainToolbar - Tabbed toolbar docked on the right end of the bottom bar.
##
## Nine tabs:
##  - Course Terrain: terrain painting, hazards, create hole, bulldozer, brush size
##  - Improvements:   objects (trees, rocks, paths, flowers) and decorations
##  - Buildings:      amenity buildings catalogue
##  - Elevation:      sculpting controls and brush size
##  - Holes:          course holes list (rows are filled by main.gd)
##  - Golfers:        who is on the course and recent rounds
##  - Player:         play the course, tournaments, player skills
##  - Club:           land, marketing, milestones, feed, scorecard
##  - Staff:          staff management
##
## Build tools emit the same signals as the old stack-based designer panel, so
## main.gd wiring is unchanged. Menu buttons emit request signals that main.gd
## routes to the matching panels.

signal tool_selected(tool_type: int)
signal create_hole_pressed
signal tree_placement_pressed
signal rock_placement_pressed
signal building_placement_pressed
signal decoration_placement_pressed
signal raise_elevation_pressed
signal sculpt_terrain_pressed(raising: bool)
signal lower_elevation_pressed
signal bulldozer_pressed
signal staff_pressed
signal brush_size_changed(new_size: int)
signal green_preset_selected(preset_name: String)
signal play_course_pressed
signal tournaments_pressed
signal land_pressed
signal marketing_pressed
signal milestones_pressed
signal feed_pressed
signal scorecard_pressed
signal golfer_row_clicked(golfer_id: int)

enum Tab { TERRAIN, IMPROVEMENTS, BUILDINGS, ELEVATION, HOLES, GOLFERS, PLAYER, CLUB, STAFF }

const TAB_TITLES := {
	Tab.TERRAIN: "Terrain",
	Tab.IMPROVEMENTS: "Improve",
	Tab.BUILDINGS: "Build",
	Tab.ELEVATION: "Elev",
	Tab.HOLES: "Holes",
	Tab.GOLFERS: "Golfers",
	Tab.PLAYER: "Player",
	Tab.CLUB: "Club",
	Tab.STAFF: "Staff",
}

const TAB_TOOLTIPS := {
	Tab.TERRAIN: "Course Terrain",
	Tab.IMPROVEMENTS: "Improvements",
	Tab.BUILDINGS: "Buildings",
	Tab.ELEVATION: "Elevation",
	Tab.HOLES: "Course Holes",
	Tab.GOLFERS: "Golfers",
	Tab.PLAYER: "Player",
	Tab.CLUB: "Club",
	Tab.STAFF: "Staff",
}

const TOOL_ROW_HEIGHT := 32
const MAX_RECENT_ROUNDS := 30

## Per-tab layout. Row kinds:
##   {"label": str}                     small section header
##   {"tools": [defs], "columns": int}  ToolButton grid ("brush" def = brush size widget)
##   {"green_presets": true}            green size presets (shown for the Green tool)
##   {"hint": str}                      muted helper text
##   {"hole_list": true}                course holes list (filled by main.gd)
##   {"golfers": true}                  golfer activity lists
##   {"player_actions": true}           Play the Course / Tournaments buttons
##   {"player_skills": true}            owner golfer skill readout
const TAB_LAYOUT: Array = [
	# Tab.TERRAIN
	[
		{"label": "Course terrain"},
		{"tools": [
			{"type": TerrainTypes.Type.FAIRWAY, "name": "Fairway", "icon": "[=]", "hotkey": "1", "desc": "Mowed playing surface for approach shots"},
			{"type": TerrainTypes.Type.ROUGH, "name": "Rough", "icon": "[~]", "hotkey": "2", "desc": "Longer grass bordering fairways"},
			{"type": TerrainTypes.Type.GREEN, "name": "Green", "icon": "[O]", "hotkey": "3", "desc": "Putting surface around the hole"},
			{"type": TerrainTypes.Type.TEE_BOX, "name": "Tee Box", "icon": "[T]", "hotkey": "4", "desc": "Starting area for each hole"},
		]},
		{"label": "Hazards"},
		{"tools": [
			{"type": TerrainTypes.Type.BUNKER, "name": "Bunker", "icon": "[:]", "hotkey": "5", "desc": "Sand trap hazard"},
			{"type": TerrainTypes.Type.WATER, "name": "Water", "icon": "[w]", "hotkey": "6", "desc": "Water hazard with penalty"},
			{"type": TerrainTypes.Type.OUT_OF_BOUNDS, "name": "Out of Bounds", "icon": "[X]", "hotkey": "7", "desc": "Boundary area with stroke penalty"},
			{"type": "create_hole", "name": "Create Hole", "icon": "[H]", "hotkey": "H", "desc": "Define tee box, green, and flag"},
			{"type": "bulldozer", "name": "Bulldozer", "icon": "[D]", "hotkey": "X", "desc": "Removes trees, rocks, flowers, decorations"},
			{"brush": true},
		]},
		{"green_presets": true},
	],
	# Tab.IMPROVEMENTS
	[
		{"label": "Objects"},
		{"tools": [
			{"type": "tree", "name": "Trees", "icon": "[^]", "hotkey": "T", "desc": "Adds beauty and obstacles"},
			{"type": "rock", "name": "Rocks", "icon": "[*]", "hotkey": "R", "desc": "Decorative rock formations"},
			{"type": TerrainTypes.Type.PATH, "name": "Path", "icon": "[.]", "hotkey": "8", "desc": "Walking path for golfers"},
			{"type": TerrainTypes.Type.FLOWER_BED, "name": "Flower Bed", "icon": "[f]", "hotkey": "F", "desc": "Colorful landscaping"},
		]},
		{"label": "Decorations"},
		{"tools": [
			{"type": "decoration", "name": "Decorations", "icon": "[✦]", "hotkey": "O", "desc": "Aesthetic decorations for course rating"},
		], "columns": 1},
		{"hint": "Decorations raise your course rating and golfer mood."},
	],
	# Tab.BUILDINGS
	[
		{"label": "Buildings"},
		{"tools": [
			{"type": "building", "name": "Buildings", "icon": "[B]", "hotkey": "B", "desc": "Place amenity buildings"},
		], "columns": 1},
		{"hint": "Open the catalogue to place clubhouses, shops and amenities."},
	],
	# Tab.ELEVATION
	[
		{"label": "Elevation controls"},
		{"tools": [
			{"type": "mound", "name": "Rolling hill", "icon": "∩", "hotkey": "", "desc": "Sculpt a rounded hill with gently tapering slopes"},
			{"type": "hollow", "name": "Hollow", "icon": "∪", "hotkey": "", "desc": "Carve a soft valley; preserves water, paths, and buildings"},
			{"type": "raise", "name": "Raise", "icon": "[+]", "hotkey": "+", "desc": "Raise terrain elevation"},
			{"type": "lower", "name": "Lower", "icon": "[-]", "hotkey": "-", "desc": "Lower terrain elevation"},
		]},
		{"brush": true},
	],
	# Tab.HOLES
	[
		{"label": "Course holes"},
		{"hole_list": true},
		{"hint": "Create holes with the Terrain tab's Create Hole tool."},
	],
	# Tab.GOLFERS
	[
		{"golfers": true},
	],
	# Tab.PLAYER
	[
		{"player_actions": true},
		{"label": "Player skills"},
		{"player_skills": true},
	],
	# Tab.CLUB
	[
		{"tools": [
			{"type": "land", "name": "Land", "icon": "[L]", "hotkey": "L", "desc": "Buy land parcels to expand the course"},
			{"type": "marketing", "name": "Marketing", "icon": "[M]", "hotkey": "M", "desc": "Marketing campaigns to attract golfers"},
			{"type": "milestones", "name": "Milestones", "icon": "[G]", "hotkey": "G", "desc": "Goals and achievements"},
			{"type": "feed", "name": "Feed", "icon": "[N]", "hotkey": "N", "desc": "Course event feed"},
			{"type": "scorecard", "name": "Scorecard", "icon": "[K]", "hotkey": "K", "desc": "Course scorecard and records"},
		]},
	],
	# Tab.STAFF
	[
		{"label": "Staff"},
		{"tools": [
			{"type": "staff", "name": "Staff Management", "icon": "[P]", "hotkey": "P", "desc": "Manage course maintenance staff"},
		], "columns": 1},
		{"hint": "Hire groundskeepers to keep the course in playing shape."},
	],
]

var hole_list: VBoxContainer = null  # Course holes rows (filled by main.gd)
var golfer_data_provider: Callable = Callable()  # -> Array of golfer row dicts

var _current_tool: int = -1
var _tool_buttons: Dictionary = {}  # tool_type -> ToolButton
var _tab_bar: TabBar
var _pages: Array[ScrollContainer] = []
var _brush_size: int = 1
var _brush_labels: Array[Label] = []
var _green_preset_row: HBoxContainer = null
var _green_preset_buttons: Dictionary = {}  # preset_name -> Button
var _active_green_preset: String = ""
var _active_golfers_box: VBoxContainer = null
var _recent_rounds_box: VBoxContainer = null
var _recent_rounds: Array[Dictionary] = []
var _skill_labels: Array[Label] = []
var _player_points_label: Label = null
var _feed_button: Button = null
var _feed_unread: int = 0
var _refresh_timer: Timer
const BRUSH_SIZES = [1, 3, 5, 7, 9]

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	# Panel style — docked flush into the bottom bar corner
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = UIConstants.COLOR_BG_PANEL
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_right = 0
	panel_style.corner_radius_bottom_left = 0
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = UIConstants.COLOR_BORDER
	add_theme_stylebox_override("panel", panel_style)

	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Modest minimum width so the tab bar still fits; the toolbar now fills the
	# entire rest of the bottom bar instead of being pushed right by a spacer.
	custom_minimum_size = Vector2(360, 0)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 4)
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(main_vbox)

	_build_tab_bar(main_vbox)

	# One scrollable page per tab; only the active page is visible.
	for tab_index in TAB_LAYOUT.size():
		var page = _build_page(TAB_LAYOUT[tab_index])
		page.visible = tab_index == Tab.TERRAIN
		main_vbox.add_child(page)
		_pages.append(page)

	_build_refresh_timer()

func _build_tab_bar(parent: VBoxContainer) -> void:
	_tab_bar = TabBar.new()
	_tab_bar.focus_mode = Control.FOCUS_NONE
	_tab_bar.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)

	# Compact tab styles so all nine tabs fit side by side
	var tab_selected = StyleBoxFlat.new()
	tab_selected.bg_color = UIConstants.COLOR_PRIMARY
	tab_selected.corner_radius_top_left = 5
	tab_selected.corner_radius_top_right = 5
	tab_selected.content_margin_left = 6
	tab_selected.content_margin_right = 6
	tab_selected.content_margin_top = 4
	tab_selected.content_margin_bottom = 4
	tab_selected.border_width_bottom = 2
	tab_selected.border_color = UIConstants.COLOR_GOLD

	var tab_unselected = StyleBoxFlat.new()
	tab_unselected.bg_color = UIConstants.COLOR_BG_BUTTON
	tab_unselected.corner_radius_top_left = 5
	tab_unselected.corner_radius_top_right = 5
	tab_unselected.content_margin_left = 6
	tab_unselected.content_margin_right = 6
	tab_unselected.content_margin_top = 4
	tab_unselected.content_margin_bottom = 4
	tab_unselected.border_width_bottom = 2
	tab_unselected.border_color = UIConstants.COLOR_BORDER

	var tab_panel = StyleBoxFlat.new()
	tab_panel.bg_color = Color(UIConstants.COLOR_BG_DARK, 0.0)
	tab_panel.content_margin_top = 2

	_tab_bar.add_theme_stylebox_override("tab_selected", tab_selected)
	_tab_bar.add_theme_stylebox_override("tab_unselected", tab_unselected)
	_tab_bar.add_theme_stylebox_override("panel", tab_panel)
	_tab_bar.add_theme_color_override("font_selected_color", UIConstants.COLOR_TEXT)
	_tab_bar.add_theme_color_override("font_unselected_color", UIConstants.COLOR_TEXT_DIM)

	for tab_index in TAB_LAYOUT.size():
		_tab_bar.add_tab(TAB_TITLES[tab_index])
		_tab_bar.set_tab_tooltip(tab_index, TAB_TOOLTIPS[tab_index])

	_tab_bar.tab_changed.connect(_on_tab_changed)
	parent.add_child(_tab_bar)

func _build_page(rows: Array) -> ScrollContainer:
	var page = ScrollContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(vbox)

	for row in rows:
		if row.has("label"):
			vbox.add_child(_make_section_label(row["label"]))
		elif row.has("tools"):
			vbox.add_child(_make_tool_grid(row["tools"], row.get("columns", 2)))
		elif row.has("green_presets"):
			_green_preset_row = _make_green_preset_row()
			_green_preset_row.visible = false
			vbox.add_child(_green_preset_row)
		elif row.has("brush"):
			vbox.add_child(_make_brush_row())
		elif row.has("hint"):
			vbox.add_child(_make_hint_label(row["hint"]))
		elif row.has("hole_list"):
			_add_hole_list(vbox)
		elif row.has("golfers"):
			_add_golfer_lists(vbox)
		elif row.has("player_actions"):
			_add_player_actions(vbox)
		elif row.has("player_skills"):
			_add_player_skills(vbox)

	return page

# =============================================================================
# Row builders
# =============================================================================

func _make_section_label(text: String) -> Label:
	var label = Label.new()
	label.text = text.capitalize()
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	return label

func _make_hint_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	return label

func _make_tool_grid(tool_defs: Array, columns: int = 2) -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for tool_def in tool_defs:
		if tool_def.has("brush"):
			grid.add_child(_make_brush_row())
		else:
			_add_tool_button(grid, tool_def)
	return grid

func _add_tool_button(parent: Control, tool_def: Dictionary) -> void:
	var tool_type = tool_def["type"]
	var cost = 0
	var maintenance = 0
	if tool_type is int:
		cost = TerrainTypes.get_placement_cost(tool_type)
		maintenance = TerrainTypes.get_maintenance_cost(tool_type)
	else:
		var costs = _get_special_tool_costs(tool_type)
		cost = costs.get("cost", 0)
		maintenance = costs.get("maintenance", 0)

	var btn = ToolButton.create(tool_type, tool_def["name"], tool_def.get("icon", ""),
		tool_def.get("hotkey", ""), tool_def.get("desc", ""), cost, maintenance)
	btn.tool_pressed.connect(_on_tool_button_pressed)
	parent.add_child(btn)

	# Compact metrics so the toolbar fits inside the bottom bar
	btn.custom_minimum_size = Vector2(0, TOOL_ROW_HEIGHT)
	btn.clip_text = true
	btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	btn.add_theme_constant_override("icon_max_width", 18)

	if tool_type is String and tool_type == "feed":
		_feed_button = btn
	elif not (tool_type is String and _is_menu_action(tool_type)):
		_tool_buttons[tool_type] = btn

func _is_menu_action(tool_type: String) -> bool:
	return tool_type in ["land", "marketing", "milestones", "feed", "scorecard", "tournaments", "play_course"]

func _make_brush_row() -> HBoxContainer:
	var brush_row = HBoxContainer.new()
	brush_row.alignment = BoxContainer.ALIGNMENT_CENTER
	brush_row.add_theme_constant_override("separation", 4)
	brush_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var brush_title = Label.new()
	brush_title.text = "Brush"
	brush_title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	brush_title.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	brush_row.add_child(brush_title)

	var brush_decrease = Button.new()
	brush_decrease.text = "-"
	brush_decrease.custom_minimum_size = Vector2(24, 24)
	brush_decrease.pressed.connect(_on_brush_decrease)
	brush_row.add_child(brush_decrease)

	var brush_label = Label.new()
	brush_label.text = "%dx%d" % [_brush_size, _brush_size]
	brush_label.custom_minimum_size = Vector2(34, 0)
	brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brush_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	brush_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	brush_row.add_child(brush_label)
	_brush_labels.append(brush_label)

	var brush_increase = Button.new()
	brush_increase.text = "+"
	brush_increase.custom_minimum_size = Vector2(24, 24)
	brush_increase.pressed.connect(_on_brush_increase)
	brush_row.add_child(brush_increase)

	return brush_row

func _make_green_preset_row() -> HBoxContainer:
	var preset_row = HBoxContainer.new()
	preset_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preset_row.add_theme_constant_override("separation", 4)

	var preset_title = Label.new()
	preset_title.text = "Green"
	preset_title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	preset_title.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	preset_row.add_child(preset_title)

	for preset_name in ["small", "medium", "large"]:
		var preset_btn = Button.new()
		preset_btn.text = preset_name.substr(0, 1).to_upper()
		preset_btn.tooltip_text = "%s green (%d tiles)" % [preset_name.capitalize(), TerrainGrid.GREEN_PRESETS[preset_name].size()]
		preset_btn.custom_minimum_size = Vector2(28, 24)
		preset_btn.pressed.connect(_on_green_preset_pressed.bind(preset_name))
		preset_row.add_child(preset_btn)
		_green_preset_buttons[preset_name] = preset_btn

	return preset_row

func _add_hole_list(parent: VBoxContainer) -> void:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	hole_list = VBoxContainer.new()
	hole_list.add_theme_constant_override("separation", 2)
	hole_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hole_list)

func _add_golfer_lists(parent: VBoxContainer) -> void:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	vbox.add_child(_make_section_label("On the course"))
	_active_golfers_box = VBoxContainer.new()
	_active_golfers_box.add_theme_constant_override("separation", 1)
	_active_golfers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_active_golfers_box)

	vbox.add_child(_make_section_label("Recent rounds"))
	_recent_rounds_box = VBoxContainer.new()
	_recent_rounds_box.add_theme_constant_override("separation", 1)
	_recent_rounds_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_recent_rounds_box)

func _add_player_actions(parent: VBoxContainer) -> void:
	var grid = GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)

	_add_tool_button(grid, {"type": "play_course", "name": "Play the Course", "icon": "▶", "hotkey": "", "desc": "Grab your clubs and play a round on your own course"})
	_add_tool_button(grid, {"type": "tournaments", "name": "Tournaments", "icon": "[U]", "hotkey": "U", "desc": "Host tournaments to earn prestige and revenue"})

func _add_player_skills(parent: VBoxContainer) -> void:
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 1)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)

	for i in PlayerGolferProfile.SKILLS.size():
		var label = Label.new()
		label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		_skill_labels.append(label)

	_player_points_label = Label.new()
	_player_points_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	_player_points_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	parent.add_child(_player_points_label)
	_refresh_player_skills()

func _build_refresh_timer() -> void:
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_on_refresh_tick)
	add_child(_refresh_timer)

# =============================================================================
# Costs for string-typed tools/actions
# =============================================================================

func _get_special_tool_costs(tool_type: String) -> Dictionary:
	match tool_type:
		"tree":
			return {"cost": 20, "maintenance": 0}
		"rock":
			return {"cost": 15, "maintenance": 0}
		"bulldozer":
			return {"cost": 5, "maintenance": 0}
	return {"cost": 0, "maintenance": 0}

# =============================================================================
# Tab handling
# =============================================================================

func _on_tab_changed(tab_index: int) -> void:
	_show_page(tab_index)

func _show_page(tab_index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == tab_index
	match tab_index:
		Tab.GOLFERS:
			_refresh_golfer_lists()
		Tab.PLAYER:
			_refresh_player_skills()

func select_tab(tab_index: int) -> void:
	_tab_bar.current_tab = tab_index
	_show_page(tab_index)

func _tab_index_for_tool(tool_type) -> int:
	for tab_index in TAB_LAYOUT.size():
		for row in TAB_LAYOUT[tab_index]:
			if not row.has("tools"):
				continue
			for tool_def in row["tools"]:
				if tool_def.has("type") and typeof(tool_def["type"]) == typeof(tool_type) and tool_def["type"] == tool_type:
					return tab_index
	return -1

func _reveal_tab_for_tool(tool_type) -> void:
	var tab_index = _tab_index_for_tool(tool_type)
	if tab_index >= 0:
		select_tab(tab_index)

func _on_refresh_tick() -> void:
	if not is_visible_in_tree():
		return
	match _tab_bar.current_tab:
		Tab.GOLFERS:
			_refresh_golfer_lists()
		Tab.PLAYER:
			_refresh_player_skills()

# =============================================================================
# Golfer tab
# =============================================================================

func record_completed_round(data: Dictionary) -> void:
	_recent_rounds.push_front(data)
	if _recent_rounds.size() > MAX_RECENT_ROUNDS:
		_recent_rounds.resize(MAX_RECENT_ROUNDS)
	if is_visible_in_tree() and _tab_bar.current_tab == Tab.GOLFERS:
		_refresh_golfer_lists()

func _refresh_golfer_lists() -> void:
	if _active_golfers_box == null or _recent_rounds_box == null:
		return

	for child in _active_golfers_box.get_children():
		child.queue_free()
	for child in _recent_rounds_box.get_children():
		child.queue_free()

	var rows: Array = []
	if golfer_data_provider.is_valid():
		rows = golfer_data_provider.call()

	if rows.is_empty():
		_active_golfers_box.add_child(_make_empty_label("No golfers on the course right now."))
	else:
		for row_data in rows:
			_active_golfers_box.add_child(_make_golfer_row(row_data))

	if _recent_rounds.is_empty():
		_recent_rounds_box.add_child(_make_empty_label("No rounds played yet."))
	else:
		for round_data in _recent_rounds:
			_recent_rounds_box.add_child(_make_round_row(round_data))

func _make_empty_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	return label

func _make_golfer_row(row_data: Dictionary) -> Control:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var mood: float = row_data.get("mood", 0.5)
	var mood_dot = Label.new()
	mood_dot.text = "●"
	mood_dot.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	if mood >= 0.66:
		mood_dot.add_theme_color_override("font_color", UIConstants.COLOR_MOOD_HAPPY)
	elif mood >= 0.33:
		mood_dot.add_theme_color_override("font_color", UIConstants.COLOR_MOOD_NEUTRAL)
	else:
		mood_dot.add_theme_color_override("font_color", UIConstants.COLOR_MOOD_UNHAPPY)
	mood_dot.tooltip_text = "Mood: %d%%" % int(mood * 100)
	row.add_child(mood_dot)

	var golfer_btn = Button.new()
	golfer_btn.flat = true
	golfer_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	golfer_btn.clip_text = true
	golfer_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	golfer_btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	golfer_btn.text = "%s · %s · Hole %d · %d strokes" % [
		row_data.get("name", "Golfer"),
		GolferTier.get_tier_name(row_data.get("tier", 1)),
		row_data.get("hole", 1),
		row_data.get("strokes", 0),
	]
	golfer_btn.tooltip_text = "Click to follow this golfer"
	golfer_btn.pressed.connect(_on_golfer_row_pressed.bind(row_data.get("id", -1)))
	row.add_child(golfer_btn)
	return row

func _make_round_row(round_data: Dictionary) -> Control:
	var diff: int = int(round_data.get("strokes", 0)) - int(round_data.get("par", 0))
	var label = Label.new()
	label.clip_text = true
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	label.text = "%s%s — %d (%s%d) · Day %d" % [
		"★ " if round_data.get("owner", false) else "",
		round_data.get("name", "Golfer"),
		round_data.get("strokes", 0),
		"+" if diff > 0 else "",
		diff,
		round_data.get("day", 1),
	]
	label.add_theme_color_override("font_color", UIConstants.get_score_color(diff))
	label.tooltip_text = "%s's round (%s)" % [
		round_data.get("name", "Golfer"),
		GolferTier.get_tier_name(round_data.get("tier", 1)),
	]
	return label

func _on_golfer_row_pressed(golfer_id: int) -> void:
	if golfer_id >= 0:
		golfer_row_clicked.emit(golfer_id)

# =============================================================================
# Player tab
# =============================================================================

func _refresh_player_skills() -> void:
	if _player_points_label == null:
		return
	var profile: PlayerGolferProfile = GameManager.player_profile
	if profile == null:
		return
	for i in _skill_labels.size():
		_skill_labels[i].text = "%s %d%%" % [PlayerGolferProfile.SKILLS[i], profile.points[i] * 10]
	if profile.initialized:
		_player_points_label.text = "Skill points are locked in for this golfer"
	else:
		_player_points_label.text = "%d of 10 skill points remaining" % profile.remaining()

# =============================================================================
# Club tab
# =============================================================================

func set_feed_unread(count: int) -> void:
	_feed_unread = count
	if _feed_button:
		_feed_button.text = "Feed (%d)" % count if count > 0 else "Feed"

# =============================================================================
# Tool selection
# =============================================================================

func _on_tool_button_pressed(tool_type) -> void:
	_reveal_tab_for_tool(tool_type)

	if tool_type is int:
		_current_tool = tool_type
		_update_selection_highlight()
		_update_green_preset_visibility()
		tool_selected.emit(tool_type)
	else:
		# Handle special tool types and menu actions
		match tool_type:
			"tree":
				tree_placement_pressed.emit()
			"rock":
				rock_placement_pressed.emit()
			"building":
				building_placement_pressed.emit()
			"decoration":
				decoration_placement_pressed.emit()
			"create_hole":
				create_hole_pressed.emit()
			"mound":
				sculpt_terrain_pressed.emit(true)
			"hollow":
				sculpt_terrain_pressed.emit(false)
			"raise":
				raise_elevation_pressed.emit()
			"lower":
				lower_elevation_pressed.emit()
			"bulldozer":
				bulldozer_pressed.emit()
			"staff":
				staff_pressed.emit()
			"play_course":
				play_course_pressed.emit()
			"tournaments":
				tournaments_pressed.emit()
			"land":
				land_pressed.emit()
			"marketing":
				marketing_pressed.emit()
			"milestones":
				milestones_pressed.emit()
			"feed":
				feed_pressed.emit()
			"scorecard":
				scorecard_pressed.emit()

func _update_selection_highlight() -> void:
	# Reset all buttons
	for tool_type in _tool_buttons.keys():
		var btn = _tool_buttons[tool_type]
		if btn is ToolButton:
			btn.set_selected(false)

	# Highlight current tool
	if _current_tool in _tool_buttons:
		var btn = _tool_buttons[_current_tool]
		if btn is ToolButton:
			btn.set_selected(true)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	# Don't process any gameplay hotkeys while in main menu
	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# Don't process if Ctrl/Cmd is held (those are for undo/save)
		if event.is_command_or_control_pressed():
			return

		# Don't process hotkeys if a text input has focus
		var focused = get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			return

		if event.shift_pressed:
			match event.keycode:
				KEY_1:  # Shift+1 = !
					select_tab(Tab.TERRAIN)
					_on_tool_button_pressed(TerrainTypes.Type.BUNKER)
					get_viewport().set_input_as_handled()
					return
				KEY_EQUAL:  # Shift+= = +
					_on_tool_button_pressed("raise")
					get_viewport().set_input_as_handled()
					return
				KEY_MINUS:  # Shift+- = _
					_on_tool_button_pressed("lower")
					get_viewport().set_input_as_handled()
					return
				KEY_R:  # Shift+R = routing overlay (handled in main.gd)
					return

		# Check for tool hotkeys
		match event.keycode:
			KEY_EQUAL:  # = opens the Course Terrain tab
				select_tab(Tab.TERRAIN)
				get_viewport().set_input_as_handled()
			KEY_PERIOD:  # . opens the Improvements tab
				select_tab(Tab.IMPROVEMENTS)
				get_viewport().set_input_as_handled()
			KEY_E:  # E opens the Elevation tab
				select_tab(Tab.ELEVATION)
				get_viewport().set_input_as_handled()
			KEY_MINUS:  # - for lower elevation
				_on_tool_button_pressed("lower")
			KEY_1:
				_on_tool_button_pressed(TerrainTypes.Type.FAIRWAY)
			KEY_2:
				_on_tool_button_pressed(TerrainTypes.Type.ROUGH)
			KEY_3:
				_on_tool_button_pressed(TerrainTypes.Type.GREEN)
			KEY_4:
				_on_tool_button_pressed(TerrainTypes.Type.TEE_BOX)
			KEY_5:
				_on_tool_button_pressed(TerrainTypes.Type.BUNKER)
			KEY_6:
				_on_tool_button_pressed(TerrainTypes.Type.WATER)
			KEY_7:
				_on_tool_button_pressed(TerrainTypes.Type.OUT_OF_BOUNDS)
			KEY_8:
				_on_tool_button_pressed(TerrainTypes.Type.PATH)
			KEY_T:
				_on_tool_button_pressed("tree")
			KEY_R:
				_on_tool_button_pressed("rock")
			KEY_F:
				_on_tool_button_pressed(TerrainTypes.Type.FLOWER_BED)
			KEY_B:
				_on_tool_button_pressed("building")
			KEY_O:
				_on_tool_button_pressed("decoration")
			KEY_H:
				_on_tool_button_pressed("create_hole")
			KEY_X:
				_on_tool_button_pressed("bulldozer")
			KEY_P:
				select_tab(Tab.STAFF)
				_on_tool_button_pressed("staff")

# =============================================================================
# Public API (unchanged contract with main.gd)
# =============================================================================

func set_current_tool(tool_type: int) -> void:
	_current_tool = tool_type
	_update_selection_highlight()

func get_current_tool() -> int:
	return _current_tool

func clear_selection() -> void:
	"""Clear all button selections (null selector state)"""
	_current_tool = -1  # Invalid tool type indicates no selection
	_update_selection_highlight()
	_update_green_preset_visibility()

func has_selection() -> bool:
	"""Check if any terrain tool is currently selected"""
	return _current_tool >= 0 and _current_tool in _tool_buttons

func get_brush_size() -> int:
	return _brush_size

func _on_brush_decrease() -> void:
	var idx = BRUSH_SIZES.find(_brush_size)
	if idx > 0:
		_brush_size = BRUSH_SIZES[idx - 1]
		_update_brush_label()
		brush_size_changed.emit(_brush_size)

func _on_brush_increase() -> void:
	var idx = BRUSH_SIZES.find(_brush_size)
	if idx < BRUSH_SIZES.size() - 1:
		_brush_size = BRUSH_SIZES[idx + 1]
		_update_brush_label()
		brush_size_changed.emit(_brush_size)

func _update_brush_label() -> void:
	for label in _brush_labels:
		if is_instance_valid(label):
			label.text = "%dx%d" % [_brush_size, _brush_size]

func _update_green_preset_visibility() -> void:
	if _green_preset_row:
		_green_preset_row.visible = (_current_tool == TerrainTypes.Type.GREEN)
		if _current_tool != TerrainTypes.Type.GREEN:
			_active_green_preset = ""
			_update_green_preset_highlight()

func _on_green_preset_pressed(preset_name: String) -> void:
	if _active_green_preset == preset_name:
		_active_green_preset = ""  # Toggle off
	else:
		_active_green_preset = preset_name
	_update_green_preset_highlight()
	green_preset_selected.emit(_active_green_preset)

func _update_green_preset_highlight() -> void:
	for pname in _green_preset_buttons:
		var btn: Button = _green_preset_buttons[pname]
		if pname == _active_green_preset:
			btn.add_theme_color_override("font_color", UIConstants.COLOR_PRIMARY_HOVER)
		else:
			btn.remove_theme_color_override("font_color")

func get_active_green_preset() -> String:
	return _active_green_preset

func set_brush_size(value: int) -> void:
	if value in BRUSH_SIZES:
		_brush_size = value
		_update_brush_label()
		brush_size_changed.emit(value)

func set_view_state(_orientation: int, _isometric: bool) -> void:
	# View controls live in the bottom bar's left side; kept as no-op for compatibility.
	pass

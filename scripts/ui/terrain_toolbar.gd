extends PanelContainer
class_name TerrainToolbar
## TerrainToolbar - Tabbed toolbar docked on the right end of the bottom bar.
##
## Nine tabs:
##  - Course Terrain: tools column (open hole, bulldozer, brush) before one course, hazard & landscape tiles honeycomb
##  - Improvements:   paths and decorations
##  - Buildings:      amenity buildings catalogue
##  - Elevation:      sculpting controls and brush size
##  - Holes:          course holes list (rows are filled by main.gd)
##  - Golfers:        who is on the course and recent rounds
##  - Player:         play the course, tournaments, player skills
##  - Club:           land, marketing, milestones, feed, scorecard
##  - Staff:          hire/fire staff, course condition, payroll, and effects
##
## Content within tabs is laid out horizontally and scrolls horizontally when
## overflowing the available tab width.

signal course_review_pressed
signal tool_selected(tool_type: int)
signal open_hole_pressed
signal tree_selected(tree_type: String)
signal rock_selected(rock_size: String)
signal building_placement_pressed
signal building_selected(building_type: String)
signal decoration_placement_pressed
signal raise_elevation_pressed
signal sculpt_terrain_pressed(raising: bool)
signal lower_elevation_pressed
signal bulldozer_pressed
signal brush_size_changed(new_size: int)
signal brush_shape_changed(round_shape: bool)
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
	Tab.IMPROVEMENTS: "Improvements",
	Tab.BUILDINGS: "Buildings",
	Tab.ELEVATION: "Elevation",
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

const TOOL_TAB_MAP := {
	TerrainTypes.Type.TEE_BOX: Tab.TERRAIN,
	TerrainTypes.Type.GREEN: Tab.TERRAIN,
	TerrainTypes.Type.BUNKER: Tab.TERRAIN,
	TerrainTypes.Type.ROUGH: Tab.TERRAIN,
	TerrainTypes.Type.POT_BUNKER: Tab.TERRAIN,
	TerrainTypes.Type.STREAM: Tab.TERRAIN,
	TerrainTypes.Type.WATER: Tab.TERRAIN,
	TerrainTypes.Type.FAIRWAY: Tab.TERRAIN,
	TerrainTypes.Type.FIRM_FAIRWAY: Tab.TERRAIN,
	TerrainTypes.Type.DEEP_ROUGH: Tab.TERRAIN,
	TerrainTypes.Type.WASTE_BUNKER: Tab.TERRAIN,
	TerrainTypes.Type.BRUSH: Tab.TERRAIN,
	TerrainTypes.Type.ROCKS: Tab.TERRAIN,
	TerrainTypes.Type.OUT_OF_BOUNDS: Tab.TERRAIN,
	"open_hole": Tab.TERRAIN,
	"bulldozer": Tab.TERRAIN,
	"tree": Tab.TERRAIN,
	"rock": Tab.TERRAIN,
	"boulder_small": Tab.TERRAIN,
	"boulder_medium": Tab.TERRAIN,
	"boulder_large": Tab.TERRAIN,
	TerrainTypes.Type.PATH: Tab.IMPROVEMENTS,
	TerrainTypes.Type.FLOWER_BED: Tab.TERRAIN,
	"decoration": Tab.IMPROVEMENTS,
	"building": Tab.BUILDINGS,
	"mound": Tab.ELEVATION,
	"hollow": Tab.ELEVATION,
	"raise": Tab.ELEVATION,
	"lower": Tab.ELEVATION,
	"play_course": Tab.PLAYER,
	"tournaments": Tab.PLAYER,
	"land": Tab.CLUB,
	"marketing": Tab.CLUB,
	"milestones": Tab.CLUB,
	"feed": Tab.CLUB,
	"scorecard": Tab.CLUB,
}

## Shift + number keys pick the extra course tiles: the harsher variants of
## Rough (2), Bunker (5) and Water (6), then Rocks (7) and Brush (8).
const SHIFT_TERRAIN_HOTKEYS := {
	KEY_2: TerrainTypes.Type.DEEP_ROUGH,
	KEY_5: TerrainTypes.Type.POT_BUNKER,
	KEY_6: TerrainTypes.Type.STREAM,
	KEY_7: TerrainTypes.Type.ROCKS,
	KEY_8: TerrainTypes.Type.BRUSH,
}

const TOOL_ROW_HEIGHT := 30
const COURSE_TILE_COLUMNS := 7  # Top row runs tee -> water, bottom row fairway -> out of bounds
const TILE_ROWS := 2  # Course and building tiles always sit in two interlocking rows
## Vertical rhythm of the tile rows: two rows of TerrainTileButton.BUTTON_SIZE
## tiles span 1.5 tiles, plus the gap where the lower row tucks into the
## notches of the row above, plus the breathing room kept above the first row
## and below the last — together filling the toolbar page height without the
## rows touching each other or the edges of the page.
const TILE_H_SEPARATION := 8
const TILE_V_SEPARATION := 20
const TILE_V_PADDING := 20
const MAX_RECENT_ROUNDS := 30
const BRUSH_SIZES := [1, 3, 5, 7, 9]
const OPEN_HOLE_TOOLTIP := "Pair the waiting tee box with the waiting green with a hole"
const OPEN_HOLE_BLOCKED_TOOLTIP := "Needs exactly one unused tee box and one unused green with a hole"

var hole_list: HBoxContainer = null  # Course holes rows (filled by main.gd)
var golfer_data_provider: Callable = Callable()  # -> Array of golfer row dicts

var _current_tool: int = -1
var _tool_buttons: Dictionary = {}  # tool_type -> ToolButton
var _tab_bar: TabBar = null
var _pages: Array[ScrollContainer] = []
var _brush_size: int = 1
var _round_brush := true
var _brush_limit: int = HoleLayout.UNLIMITED_BRUSH  # 1 = current tool paints a single tile
var _brush_labels: Array[Label] = []
var _brush_buttons: Array[Button] = []
var _brush_shape_buttons: Array[OptionButton] = []
var _open_hole_buttons: Array[ToolButton] = []
var _green_tile_button: TerrainTileButton = null
var _tee_tile_button: TerrainTileButton = null
var _green_places_cup := true
var _tee_box_can_place: bool = true
var _tee_box_blocker: String = ""
var _active_golfers_box: HBoxContainer = null
var _recent_rounds_box: HBoxContainer = null
var _recent_rounds: Array[Dictionary] = []
var _skill_labels: Array[Label] = []
var _player_points_label: Label = null
var _feed_button: Button = null
var _building_registry: Dictionary = {}
var _building_shelf: TileHoneycomb = null
var _course_tiles: TileHoneycomb = null
var _landscape_buttons: Array[Node] = []
var _selected_string_tool: String = ""
var _feed_unread: int = 0
var _refresh_timer: Timer = null
var _staff_panel: StaffPanel = null

func _ready() -> void:
	_build_ui()
	EventBus.theme_changed.connect(_on_theme_changed)

func _exit_tree() -> void:
	if EventBus.theme_changed.is_connected(_on_theme_changed):
		EventBus.theme_changed.disconnect(_on_theme_changed)

func _build_ui() -> void:
	# Panel style — docked flush into the bottom bar corner
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = UIConstants.COLOR_BG_PANEL
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_right = 0
	panel_style.corner_radius_bottom_left = 0
	panel_style.content_margin_left = 0
	panel_style.content_margin_right = 0
	panel_style.content_margin_top = 2
	panel_style.content_margin_bottom = 2
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 0
	panel_style.border_color = UIConstants.COLOR_BORDER
	add_theme_stylebox_override("panel", panel_style)

	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(300, 0)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 2)
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(main_vbox)

	_build_tab_bar(main_vbox)

	var pages_container = PanelContainer.new()
	var pages_style = StyleBoxEmpty.new()
	pages_container.add_theme_stylebox_override("panel", pages_style)
	pages_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(pages_container)

	# Build one horizontally-scrollable page per tab
	for tab_index in TAB_TITLES.size():
		var page = _build_page(tab_index)
		page.visible = (tab_index == Tab.TERRAIN)
		pages_container.add_child(page)
		_pages.append(page)

	_build_refresh_timer()

func _build_tab_bar(parent: VBoxContainer) -> void:
	_tab_bar = TabBar.new()
	_tab_bar.focus_mode = Control.FOCUS_NONE
	_tab_bar.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	_tab_bar.scrolling_enabled = true
	_tab_bar.tab_alignment = TabBar.ALIGNMENT_LEFT
	_tab_bar.custom_minimum_size = Vector2(0, 24)

	# Compact tab styles
	var tab_selected = StyleBoxFlat.new()
	tab_selected.bg_color = UIConstants.COLOR_PRIMARY
	tab_selected.corner_radius_top_left = 4
	tab_selected.corner_radius_top_right = 4
	tab_selected.content_margin_left = 8
	tab_selected.content_margin_right = 8
	tab_selected.content_margin_top = 2
	tab_selected.content_margin_bottom = 2
	tab_selected.border_width_bottom = 2
	tab_selected.border_color = UIConstants.COLOR_GOLD

	var tab_unselected = StyleBoxFlat.new()
	tab_unselected.bg_color = UIConstants.COLOR_BG_BUTTON
	tab_unselected.corner_radius_top_left = 4
	tab_unselected.corner_radius_top_right = 4
	tab_unselected.content_margin_left = 8
	tab_unselected.content_margin_right = 8
	tab_unselected.content_margin_top = 2
	tab_unselected.content_margin_bottom = 2
	tab_unselected.border_width_bottom = 2
	tab_unselected.border_color = UIConstants.COLOR_BORDER

	var tab_panel = StyleBoxFlat.new()
	tab_panel.bg_color = Color(UIConstants.COLOR_BG_DARK, 0.0)
	tab_panel.content_margin_top = 0
	tab_panel.content_margin_bottom = 0

	_tab_bar.add_theme_stylebox_override("tab_selected", tab_selected)
	_tab_bar.add_theme_stylebox_override("tab_unselected", tab_unselected)
	_tab_bar.add_theme_stylebox_override("tab_hovered", tab_selected)
	_tab_bar.add_theme_stylebox_override("panel", tab_panel)
	_tab_bar.add_theme_color_override("font_selected_color", UIConstants.COLOR_TEXT)
	_tab_bar.add_theme_color_override("font_unselected_color", UIConstants.COLOR_TEXT_DIM)
	_tab_bar.add_theme_color_override("font_hovered_color", UIConstants.COLOR_TEXT)

	for tab_index in TAB_TITLES.size():
		_tab_bar.add_tab(TAB_TITLES[tab_index])
		_tab_bar.set_tab_tooltip(tab_index, TAB_TOOLTIPS[tab_index])

	_tab_bar.tab_changed.connect(_on_tab_changed)
	parent.add_child(_tab_bar)

func _build_page(tab_index: int) -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.gui_input.connect(_on_scroll_gui_input.bind(scroll))

	var h_bar = scroll.get_h_scroll_bar()
	if h_bar:
		h_bar.custom_minimum_size = Vector2(0, 4)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	scroll.add_child(hbox)

	match tab_index:
		Tab.TERRAIN:
			_build_terrain_tab(hbox)
		Tab.IMPROVEMENTS:
			_build_improvements_tab(hbox)
		Tab.BUILDINGS:
			_build_buildings_tab(hbox)
		Tab.ELEVATION:
			_build_elevation_tab(hbox)
		Tab.HOLES:
			_build_holes_tab(hbox)
		Tab.GOLFERS:
			_build_golfers_tab(hbox)
		Tab.PLAYER:
			_build_player_tab(hbox)
		Tab.CLUB:
			_build_club_tab(hbox)
		Tab.STAFF:
			_build_staff_tab(hbox)

	return scroll

func _on_scroll_gui_input(event: InputEvent, scroll: ScrollContainer) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll.scroll_horizontal = maxi(0, scroll.scroll_horizontal - 50)
			scroll.accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll.scroll_horizontal += 50
			scroll.accept_event()

# =============================================================================
# Tab Builders (Horizontal Layouts)
# =============================================================================

func _build_terrain_tab(hbox: HBoxContainer) -> void:
	# The Open Hole action, the Bulldozer and the brush stack in one column
	# before the tiles so the most-used course tools sit first in the tab.
	hbox.add_child(_make_terrain_tools_column())

	hbox.add_child(_make_separator())

	# The course tiles share one honeycomb of two rows, the bottom row shifted
	# half a tile right so each diamond drops into a notch between the two tiles
	# above it. Top row: Tee Box, Green, Bunker, Rough, Pot Bunker, Stream,
	# Water. Bottom row: Fairway, Firm Fairway, Deep Rough, Waste Bunker,
	# Brush, Rocks, Out of Bounds.
	var tiles_grid = TileHoneycomb.new()
	_course_tiles = tiles_grid
	tiles_grid.name = "CourseTilesGrid"
	tiles_grid.columns = COURSE_TILE_COLUMNS
	tiles_grid.tile_size = TerrainTileButton.BUTTON_SIZE
	tiles_grid.h_separation = TILE_H_SEPARATION
	tiles_grid.v_separation = TILE_V_SEPARATION
	tiles_grid.v_padding = TILE_V_PADDING
	tiles_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Top row: the tee and the green first, then the hazards and trouble.
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.TEE_BOX, "name": "Tee Box", "hotkey": "4", "desc": "Tee for one hole — a single tile (1x1). Only one tee box may wait on the course at a time", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.GREEN, "name": "Green", "hotkey": "3", "desc": "Next green placement is a Green With Hole (one tile with a cup). The flag on this tile shows when it will place a cup.", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.BUNKER, "name": "Bunker", "hotkey": "5", "desc": "Sand trap hazard", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.ROUGH, "name": "Rough", "hotkey": "2", "desc": "Longer grass bordering fairways", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.POT_BUNKER, "name": "Pot Bunker", "hotkey": "Shift+5", "desc": "Small, deep bunker with a steep stacked-turf face. Wedge only, and the ball barely advances", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.STREAM, "name": "Stream", "hotkey": "Shift+6", "desc": "Running water hazard with a one-stroke penalty. Paint it in lines; golfers can still walk across", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.WATER, "name": "Water", "hotkey": "6", "desc": "Water hazard with penalty", "tile_preview": true})
	# Bottom row: playing surfaces and natural ground, each variant beside its parent.
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.FAIRWAY, "name": "Fairway", "hotkey": "1", "desc": "Mowed playing surface for approach shots", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.FIRM_FAIRWAY, "name": "Firm Fairway", "hotkey": "9", "desc": "Fast-running links turf: a tight lie, and balls bound on and roll about 60% farther", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.DEEP_ROUGH, "name": "Deep Rough", "hotkey": "Shift+2", "desc": "Knee-high grass that grabs rolling balls. Shots from it lose accuracy and 40% of their distance", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.WASTE_BUNKER, "name": "Waste Bunker", "hotkey": "0", "desc": "Natural sandy scrubland. Not a hazard: plays like sandy rough and needs no upkeep", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.BRUSH, "name": "Brush", "hotkey": "Shift+8", "desc": "Dense scrub that swallows the ball. Only a wedge hacks it out", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.ROCKS, "name": "Rocks", "hotkey": "Shift+7", "desc": "Stony ground: the worst lie on the course, wedge only", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.OUT_OF_BOUNDS, "name": "Out of Bounds", "hotkey": "7", "desc": "Boundary area with stroke penalty", "tile_preview": true})
	# The grid carries its own breathing room above and below the rows, so it
	# keeps that spacing instead of stretching to fill the whole page height.
	hbox.add_child(_make_tab_group("", tiles_grid, true))

	_populate_landscape_tiles()

## Open Hole, Bulldozer and the brush controls stacked vertically. This column
## opens the Course Terrain tab so the tools sit before the tile honeycomb.
## Buttons use a compact 26px height (matching the brush stepper) so the whole
## column still fits inside the 190px bottom bar. ToolButton._ready() resets
## custom_minimum_size, so the compact height is applied on ready instead.
func _make_terrain_tools_column() -> VBoxContainer:
	const COLUMN_BUTTON_HEIGHT := 26
	var column = VBoxContainer.new()
	column.name = "TerrainToolsColumn"
	column.add_theme_constant_override("separation", 2)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var open_hole_btn := _add_tool_button(column, {"type": "open_hole", "name": "Open Hole", "icon": "[H]", "hotkey": "H", "desc": OPEN_HOLE_TOOLTIP})
	_open_hole_buttons.append(open_hole_btn)
	_make_column_button_compact(open_hole_btn, COLUMN_BUTTON_HEIGHT)

	var bulldozer_btn := _add_tool_button(column, {"type": "bulldozer", "name": "Bulldozer", "icon": "[D]", "hotkey": "X", "desc": "Removes trees, boulders, rocky ground, brush, flowers, decorations"})
	_make_column_button_compact(bulldozer_btn, COLUMN_BUTTON_HEIGHT)

	column.add_child(_make_small_group_label("BRUSH"))

	var brush_row := _create_brush_row()
	brush_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brush_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(brush_row)

	var shape := _create_brush_shape()
	shape.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shape.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(shape)

	_apply_brush_limit()
	return column

## Size a ToolButton for vertical stacking in the tools column: full width,
## compact height. Applied on ready so ToolButton._ready() cannot overwrite it.
func _make_column_button_compact(btn: ToolButton, height: int) -> void:
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if btn.is_node_ready():
		btn.custom_minimum_size = Vector2(0, height)
	else:
		btn.ready.connect(
			func() -> void: btn.custom_minimum_size = Vector2(0, height),
			CONNECT_ONE_SHOT
		)

func _build_improvements_tab(hbox: HBoxContainer) -> void:
	var path_box = HBoxContainer.new()
	path_box.add_theme_constant_override("separation", 4)
	path_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add_tool_button(path_box, {"type": TerrainTypes.Type.PATH, "name": "Path", "icon": "[.]", "hotkey": "8", "desc": "Walking path for golfers"})
	hbox.add_child(_make_tab_group("PATHS", path_box))

	hbox.add_child(_make_separator())

	var dec_box = HBoxContainer.new()
	dec_box.add_theme_constant_override("separation", 4)
	dec_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add_tool_button(dec_box, {"type": "decoration", "name": "Decorations", "icon": "[✦]", "hotkey": "O", "desc": "Aesthetic decorations for course rating"})
	hbox.add_child(_make_tab_group("DECORATIONS", dec_box))

	hbox.add_child(_make_separator())

	hbox.add_child(_make_tip_label("Decorations & walking paths raise course aesthetics and pace of play."))

func _on_theme_changed(_theme: int) -> void:
	_populate_landscape_tiles()

func _populate_landscape_tiles() -> void:
	if not is_instance_valid(_course_tiles):
		return
	# Detach old landscape tiles immediately so repeated theme changes cannot
	# leave duplicate tiles in the layout or stale entries in the tool lookup.
	for key in _tool_buttons.keys():
		if _tool_buttons[key] in _landscape_buttons:
			_tool_buttons.erase(key)
	for child in _landscape_buttons:
		_course_tiles.remove_child(child)
		child.queue_free()
	_landscape_buttons.clear()

	var theme_id: int = CourseTheme.Type.PARKLAND
	if GameManager:
		theme_id = GameManager.current_theme
	var theme_trees: Array = CourseTheme.get_tree_types(theme_id)
	var total_tiles: int = 1 + 3 + theme_trees.size()
	_course_tiles.columns = COURSE_TILE_COLUMNS + ceili(float(total_tiles) / TILE_ROWS)

	# 1. Flower Bed terrain tile
	var fb_btn := _add_tool_button(_course_tiles, {
		"type": TerrainTypes.Type.FLOWER_BED,
		"name": "Flower Bed",
		"hotkey": "Shift+F",
		"desc": "Colorful landscaping",
		"tile_preview": true
	})
	_tool_buttons[TerrainTypes.Type.FLOWER_BED] = fb_btn

	# 2. Boulder tiles
	var boulder_configs = [
		{"size": "small", "name": "Small Boulder", "tool_id": "boulder_small"},
		{"size": "medium", "name": "Boulders", "tool_id": "rock"},
		{"size": "large", "name": "Large Boulder", "tool_id": "boulder_large"}
	]
	for b_cfg in boulder_configs:
		var r_data: Dictionary = Rock.ROCK_PROPERTIES.get(b_cfg["size"], {}).duplicate(true)
		r_data["name"] = b_cfg["name"]
		var b_btn := BoulderTileButton.new()
		b_btn.configure_boulder(b_cfg["size"], r_data)
		b_btn.tool_pressed.connect(_on_tool_button_pressed)
		_course_tiles.add_child(b_btn)
		b_btn.custom_minimum_size = TerrainTileButton.BUTTON_SIZE
		b_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var b_tool_id: String = str(b_cfg["tool_id"])
		_tool_buttons[b_tool_id] = b_btn
		if b_cfg["size"] == "medium":
			_tool_buttons["boulder_medium"] = b_btn

	# 3. Theme Trees
	var first_tree_btn: TreeTileButton = null
	for tree_type in theme_trees:
		var t_data: Dictionary = TreeEntity.TREE_PROPERTIES.get(tree_type, {}).duplicate(true)
		var t_btn := TreeTileButton.new()
		t_btn.configure_tree(str(tree_type), t_data)
		t_btn.tool_pressed.connect(_on_tool_button_pressed)
		_course_tiles.add_child(t_btn)
		t_btn.custom_minimum_size = TerrainTileButton.BUTTON_SIZE
		t_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tool_id: String = "tree_" + str(tree_type)
		_tool_buttons[tool_id] = t_btn
		if first_tree_btn == null:
			first_tree_btn = t_btn
			_tool_buttons["tree"] = t_btn

	# Extend both existing course rows, rather than starting another honeycomb.
	# Keeping the first seven tiles in each row preserves the course layout.
	_landscape_buttons.assign(_course_tiles.get_children().slice(COURSE_TILE_COLUMNS * TILE_ROWS))
	for i in _course_tiles.columns - COURSE_TILE_COLUMNS:
		_course_tiles.move_child(_landscape_buttons[i], COURSE_TILE_COLUMNS + i)
	_update_selection_highlight()

func _build_buildings_tab(hbox: HBoxContainer) -> void:
	# Facilities use the same interlocking isometric buttons as Course & Hazards,
	# laid out in two rows (columns follow the catalogue size, see
	# _populate_building_shelf) so the big tiles fill the toolbar height; the
	# page scrolls sideways when the catalogue is wider than the window.
	_building_shelf = TileHoneycomb.new()
	_building_shelf.name = "BuildingShelf"
	_building_shelf.columns = building_tile_columns(_building_registry.size())
	_building_shelf.tile_size = TerrainTileButton.BUTTON_SIZE
	_building_shelf.h_separation = TILE_H_SEPARATION
	_building_shelf.v_separation = TILE_V_SEPARATION
	_building_shelf.v_padding = TILE_V_PADDING
	_building_shelf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_building_shelf.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# No group heading or INFO blurb: the tiles speak for themselves and the
	# rich hover tooltip carries each facility's cost and upkeep.
	# The shelf carries its own breathing room above and below the rows, so it
	# keeps that spacing instead of stretching to fill the whole page height.
	hbox.add_child(_make_tab_group("", _building_shelf, true))
	_populate_building_shelf()

func set_building_registry(registry: Dictionary) -> void:
	_building_registry = registry.duplicate(true)
	_populate_building_shelf()

func _populate_building_shelf() -> void:
	if not is_instance_valid(_building_shelf):
		return
	for child in _building_shelf.get_children():
		_building_shelf.remove_child(child)
		child.queue_free()
	_building_shelf.columns = building_tile_columns(_building_registry.size())
	for building_type in _building_registry:
		var data: Dictionary = _building_registry[building_type]
		var button := BuildingTileButton.new()
		button.configure_building(str(building_type), data)
		button.pressed.connect(_on_building_card_pressed.bind(str(building_type)))
		_building_shelf.add_child(button)

## Columns needed to lay `count` building tiles out in TILE_ROWS rows.
static func building_tile_columns(count: int) -> int:
	return maxi(1, ceili(float(count) / TILE_ROWS))

func _on_building_card_pressed(building_type: String) -> void:
	_reveal_tab_for_tool("building")
	building_selected.emit(building_type)

func _build_elevation_tab(hbox: HBoxContainer) -> void:
	var sculpt_box = HBoxContainer.new()
	sculpt_box.add_theme_constant_override("separation", 4)
	sculpt_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add_tool_button(sculpt_box, {"type": "mound", "name": "Rolling Hill", "icon": "∩", "hotkey": "", "desc": "Sculpt a rounded hill with gently tapering slopes"})
	_add_tool_button(sculpt_box, {"type": "hollow", "name": "Hollow", "icon": "∪", "hotkey": "", "desc": "Carve a soft valley; preserves water, paths, and buildings"})
	hbox.add_child(_make_tab_group("SCULPT", sculpt_box))

	hbox.add_child(_make_separator())

	var step_box = HBoxContainer.new()
	step_box.add_theme_constant_override("separation", 4)
	step_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add_tool_button(step_box, {"type": "raise", "name": "Raise", "icon": "[+]", "hotkey": "+", "desc": "Raise terrain elevation"})
	_add_tool_button(step_box, {"type": "lower", "name": "Lower", "icon": "[-]", "hotkey": "-", "desc": "Lower terrain elevation"})
	hbox.add_child(_make_tab_group("STEP", step_box))

	hbox.add_child(_make_separator())

	hbox.add_child(_make_brush_group())

func _build_holes_tab(hbox: HBoxContainer) -> void:
	var actions_box = HBoxContainer.new()
	actions_box.add_theme_constant_override("separation", 4)
	actions_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var open_hole_btn := _add_tool_button(actions_box, {"type": "open_hole", "name": "Open Hole", "icon": "[H]", "hotkey": "H", "desc": OPEN_HOLE_TOOLTIP})
	_open_hole_buttons.append(open_hole_btn)
	hbox.add_child(_make_tab_group("ACTIONS", actions_box))

	hbox.add_child(_make_separator())

	var holes_group = VBoxContainer.new()
	holes_group.add_theme_constant_override("separation", 2)
	holes_group.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holes_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl = Label.new()
	lbl.text = "COURSE HOLES"
	lbl.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	holes_group.add_child(lbl)

	hole_list = HBoxContainer.new()
	hole_list.name = "HoleList"
	hole_list.add_theme_constant_override("separation", 6)
	hole_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hole_list.alignment = BoxContainer.ALIGNMENT_BEGIN
	holes_group.add_child(hole_list)

	hbox.add_child(holes_group)

func _build_golfers_tab(hbox: HBoxContainer) -> void:
	var on_course_group = VBoxContainer.new()
	on_course_group.add_theme_constant_override("separation", 2)
	on_course_group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lbl1 = Label.new()
	lbl1.text = "ON THE COURSE"
	lbl1.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl1.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	on_course_group.add_child(lbl1)

	_active_golfers_box = HBoxContainer.new()
	_active_golfers_box.add_theme_constant_override("separation", 4)
	_active_golfers_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_active_golfers_box.alignment = BoxContainer.ALIGNMENT_CENTER
	on_course_group.add_child(_active_golfers_box)
	hbox.add_child(on_course_group)

	hbox.add_child(_make_separator())

	var recent_group = VBoxContainer.new()
	recent_group.add_theme_constant_override("separation", 2)
	recent_group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lbl2 = Label.new()
	lbl2.text = "RECENT ROUNDS"
	lbl2.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl2.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	recent_group.add_child(lbl2)

	_recent_rounds_box = HBoxContainer.new()
	_recent_rounds_box.add_theme_constant_override("separation", 6)
	_recent_rounds_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recent_rounds_box.alignment = BoxContainer.ALIGNMENT_CENTER
	recent_group.add_child(_recent_rounds_box)
	hbox.add_child(recent_group)

func _build_player_tab(hbox: HBoxContainer) -> void:
	var actions_box = HBoxContainer.new()
	actions_box.add_theme_constant_override("separation", 4)
	actions_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add_tool_button(actions_box, {"type": "play_course", "name": "Play Course", "icon": "▶", "hotkey": "", "desc": "Grab your clubs and play a round on your own course"})
	_add_tool_button(actions_box, {"type": "tournaments", "name": "Tournaments", "icon": "[U]", "hotkey": "U", "desc": "Host tournaments to earn prestige and revenue"})
	hbox.add_child(_make_tab_group("ACTIONS", actions_box))

	hbox.add_child(_make_separator())

	var skills_box = HBoxContainer.new()
	skills_box.add_theme_constant_override("separation", 8)
	skills_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skills_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_skill_labels.clear()
	for i in PlayerGolferProfile.SKILLS.size():
		var label = Label.new()
		label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
		skills_box.add_child(label)
		_skill_labels.append(label)
	hbox.add_child(_make_tab_group("OWNER SKILLS", skills_box))

	hbox.add_child(_make_separator())

	var points_box = HBoxContainer.new()
	points_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	points_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_player_points_label = Label.new()
	_player_points_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	_player_points_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	points_box.add_child(_player_points_label)
	hbox.add_child(_make_tab_group("POINTS", points_box))

	_refresh_player_skills()

func _build_club_tab(hbox: HBoxContainer) -> void:
	var ops_box = HBoxContainer.new()
	ops_box.add_theme_constant_override("separation", 4)
	ops_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add_tool_button(ops_box, {"type": "land", "name": "Land", "icon": "[L]", "hotkey": "L", "desc": "Buy land parcels to expand the course"})
	_add_tool_button(ops_box, {"type": "marketing", "name": "Marketing", "icon": "[M]", "hotkey": "M", "desc": "Marketing campaigns to attract golfers"})
	_add_tool_button(ops_box, {"type": "milestones", "name": "Milestones", "icon": "[G]", "hotkey": "G", "desc": "Goals and achievements"})
	_add_tool_button(ops_box, {"type": "feed", "name": "Feed", "icon": "[N]", "hotkey": "N", "desc": "Course event feed"})
	_add_tool_button(ops_box, {"type": "scorecard", "name": "Scorecard", "icon": "[K]", "hotkey": "K", "desc": "Course scorecard and records"})
	ops_box.add_child(_make_review_button())
	hbox.add_child(_make_tab_group("OPERATIONS", ops_box))

	hbox.add_child(_make_separator())

	hbox.add_child(_make_tip_label("Expand land parcels, launch marketing campaigns, track milestones and check course records."))

func _build_staff_tab(hbox: HBoxContainer) -> void:
	# Staff management lives in the tab itself — condition, hire/fire, roster, effects.
	_staff_panel = StaffPanel.new()
	_staff_panel.name = "StaffPanel"
	_staff_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_staff_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_staff_panel)

# =============================================================================
# Helper Widgets
# =============================================================================

func _make_tab_group(title: String, content: Control, center_content: bool = false) -> VBoxContainer:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if not title.is_empty():
		var lbl = Label.new()
		lbl.text = title.to_upper()
		lbl.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		lbl.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
		group.add_child(lbl)

	# Tile grids already carry their own breathing room above and below the
	# rows, so they keep their natural height instead of stretching to fill it.
	if center_content:
		content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(content)
	return group

func _make_separator() -> VSeparator:
	var sep = VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 28)
	sep.modulate = Color(1, 1, 1, 0.2)
	return sep

func _make_tip_label(text: String) -> Control:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lbl_title = Label.new()
	lbl_title.text = "INFO"
	lbl_title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl_title.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	group.add_child(lbl_title)

	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(lbl)
	return group

func _add_tool_button(parent: Control, tool_def: Dictionary) -> ToolButton:
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

	var btn: ToolButton
	if tool_def.get("tile_preview", false):
		btn = TerrainTileButton.new()
		btn.configure(tool_type, tool_def["name"], "", tool_def.get("hotkey", ""),
			tool_def.get("desc", ""), cost, maintenance)
	else:
		btn = ToolButton.create(tool_type, tool_def["name"], tool_def.get("icon", ""),
			tool_def.get("hotkey", ""), tool_def.get("desc", ""), cost, maintenance)
	btn.tool_pressed.connect(_on_tool_button_pressed)
	parent.add_child(btn)

	if btn is TerrainTileButton:
		btn.custom_minimum_size = TerrainTileButton.BUTTON_SIZE
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		btn.custom_minimum_size = Vector2(0, TOOL_ROW_HEIGHT)
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
		btn.add_theme_constant_override("icon_max_width", 18)

	if tool_type is String and tool_type == "feed":
		_feed_button = btn
	elif not (tool_type is String and _is_menu_action(tool_type)):
		_tool_buttons[tool_type] = btn
		if tool_type is int:
			if tool_type == TerrainTypes.Type.GREEN:
				_green_tile_button = btn as TerrainTileButton
			elif tool_type == TerrainTypes.Type.TEE_BOX:
				_tee_tile_button = btn as TerrainTileButton

	return btn

func _is_menu_action(tool_type: String) -> bool:
	return tool_type in ["land", "marketing", "milestones", "feed", "scorecard", "tournaments", "play_course"]

func _make_small_group_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	return lbl

## Brush size stepper row ("-" label "+"). Shared by the Terrain tab's tools
## column and the Elevation tab's brush group; the caller sets size flags.
func _create_brush_row() -> HBoxContainer:
	var brush_row = HBoxContainer.new()
	brush_row.alignment = BoxContainer.ALIGNMENT_CENTER
	brush_row.add_theme_constant_override("separation", 3)

	var brush_decrease = Button.new()
	brush_decrease.text = "-"
	brush_decrease.custom_minimum_size = Vector2(24, 26)
	brush_decrease.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	brush_decrease.pressed.connect(_on_brush_decrease)
	brush_row.add_child(brush_decrease)
	_brush_buttons.append(brush_decrease)

	var brush_label = Label.new()
	brush_label.text = "%dx%d" % [_brush_size, _brush_size]
	brush_label.custom_minimum_size = Vector2(30, 0)
	brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brush_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	brush_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	brush_row.add_child(brush_label)
	_brush_labels.append(brush_label)

	var brush_increase = Button.new()
	brush_increase.text = "+"
	brush_increase.custom_minimum_size = Vector2(24, 26)
	brush_increase.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	brush_increase.pressed.connect(_on_brush_increase)
	brush_row.add_child(brush_increase)
	_brush_buttons.append(brush_increase)
	return brush_row

## Round/square brush shape picker. Shared like the brush row above.
func _create_brush_shape() -> OptionButton:
	var shape := OptionButton.new()
	shape.add_item("Round")
	shape.add_item("Square")
	shape.select(0 if _round_brush else 1)
	shape.tooltip_text = "Round brush for natural contours, square for precise edges"
	shape.custom_minimum_size = Vector2(78, 22)
	shape.focus_mode = Control.FOCUS_NONE
	shape.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	shape.item_selected.connect(_on_brush_shape_selected)
	_brush_shape_buttons.append(shape)
	return shape

func _make_brush_group() -> VBoxContainer:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	group.add_child(_make_small_group_label("BRUSH"))

	var brush_row := _create_brush_row()
	brush_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(brush_row)

	group.add_child(_create_brush_shape())
	_apply_brush_limit()
	return group

func _make_review_button() -> Button:
	var review := Button.new()
	review.text = "Review"
	review.tooltip_text = "Course review and next steps"
	review.custom_minimum_size = Vector2(72, TOOL_ROW_HEIGHT)
	review.size_flags_vertical = Control.SIZE_EXPAND_FILL
	review.pressed.connect(func(): course_review_pressed.emit())
	return review

func _make_review_group() -> VBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_make_review_button())
	return _make_tab_group("REVIEW", row)

func _build_refresh_timer() -> void:
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_on_refresh_tick)
	add_child(_refresh_timer)

# =============================================================================
# Costs for special string tools
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
		_pages[i].visible = (i == tab_index)
	match tab_index:
		Tab.GOLFERS:
			_refresh_golfer_lists()
		Tab.PLAYER:
			_refresh_player_skills()
		Tab.STAFF:
			if _staff_panel:
				_staff_panel.refresh()

func select_tab(tab_index: int) -> void:
	if tab_index >= 0 and tab_index < _pages.size():
		_tab_bar.current_tab = tab_index
		_show_page(tab_index)

func _tab_index_for_tool(tool_type) -> int:
	if tool_type is String and (tool_type.begins_with("tree_") or tool_type.begins_with("boulder_")):
		return Tab.TERRAIN
	return TOOL_TAB_MAP.get(tool_type, -1)

func _reveal_tab_for_tool(tool_type) -> void:
	var tab_index = _tab_index_for_tool(tool_type)
	if tab_index >= 0:
		select_tab(tab_index)

func _on_refresh_tick() -> void:
	if not is_visible_in_tree():
		return
	if _tab_bar and _tab_bar.current_tab == Tab.GOLFERS:
		_refresh_golfer_lists()
	elif _tab_bar and _tab_bar.current_tab == Tab.PLAYER:
		_refresh_player_skills()

# =============================================================================
# Golfer tab
# =============================================================================

func record_completed_round(data: Dictionary) -> void:
	_recent_rounds.push_front(data)
	if _recent_rounds.size() > MAX_RECENT_ROUNDS:
		_recent_rounds.resize(MAX_RECENT_ROUNDS)
	if is_visible_in_tree() and _tab_bar and _tab_bar.current_tab == Tab.GOLFERS:
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
		_active_golfers_box.add_child(_make_empty_label("No golfers on the course."))
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
	row.add_theme_constant_override("separation", 3)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

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
	golfer_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	golfer_btn.clip_text = false
	golfer_btn.custom_minimum_size = Vector2(0, 26)
	golfer_btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	golfer_btn.text = "%s (%s) · H%d · %d str" % [
		row_data.get("name", "Golfer"),
		GolferTier.get_tier_name(row_data.get("tier", 1)),
		row_data.get("hole", 1),
		row_data.get("strokes", 0),
	]
	golfer_btn.tooltip_text = "%s (%s) on Hole %d (%d strokes) - Click to follow" % [
		row_data.get("name", "Golfer"),
		GolferTier.get_tier_name(row_data.get("tier", 1)),
		row_data.get("hole", 1),
		row_data.get("strokes", 0),
	]
	golfer_btn.pressed.connect(_on_golfer_row_pressed.bind(row_data.get("id", -1)))
	row.add_child(golfer_btn)
	return row

func _make_round_row(round_data: Dictionary) -> Control:
	var diff: int = int(round_data.get("strokes", 0)) - int(round_data.get("par", 0))
	var label = Label.new()
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	label.text = "%s%s: %d (%s%d) · D%d" % [
		"★ " if round_data.get("owner", false) else "",
		round_data.get("name", "Golfer"),
		round_data.get("strokes", 0),
		"+" if diff > 0 else "",
		diff,
		round_data.get("day", 1),
	]
	label.add_theme_color_override("font_color", UIConstants.get_score_color(diff))
	label.tooltip_text = "%s's round (%s) on Day %d: %d strokes (%+d)" % [
		round_data.get("name", "Golfer"),
		GolferTier.get_tier_name(round_data.get("tier", 1)),
		round_data.get("day", 1),
		round_data.get("strokes", 0),
		diff,
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
		if i < PlayerGolferProfile.SKILLS.size():
			_skill_labels[i].text = "%s %d%%" % [PlayerGolferProfile.SKILLS[i], profile.points[i] * 10]
	if profile.initialized:
		_player_points_label.text = "Skills locked"
	else:
		_player_points_label.text = "%d of 10 pts remaining" % profile.remaining()

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
	# Tee Box is unselectable while an unused tee waits on the course.
	if tool_type is int and tool_type == TerrainTypes.Type.TEE_BOX and not _tee_box_can_place:
		if _current_tool == TerrainTypes.Type.TEE_BOX:
			clear_selection()
		return

	_reveal_tab_for_tool(tool_type)

	if tool_type is int:
		_current_tool = tool_type
		_selected_string_tool = ""
		_update_selection_highlight()
		tool_selected.emit(tool_type)
	else:
		var s_tool := str(tool_type)
		if s_tool.begins_with("tree_"):
			var tree_type := s_tool.substr(5)
			_current_tool = -1
			_selected_string_tool = s_tool
			_update_selection_highlight()
			tree_selected.emit(tree_type)
		elif s_tool == "tree":
			_current_tool = -1
			_selected_string_tool = s_tool
			_update_selection_highlight()
			var theme_trees: Array = CourseTheme.get_tree_types(GameManager.current_theme) if GameManager else ["oak"]
			var first_tree: String = theme_trees[0] if not theme_trees.is_empty() else "oak"
			tree_selected.emit(first_tree)
		elif s_tool.begins_with("boulder_"):
			var size := s_tool.substr(8)
			_current_tool = -1
			_selected_string_tool = s_tool
			_update_selection_highlight()
			rock_selected.emit(size)
		elif s_tool == "rock":
			_current_tool = -1
			_selected_string_tool = s_tool
			_update_selection_highlight()
			rock_selected.emit("medium")
		else:
			match tool_type:
				"building":
					building_placement_pressed.emit()
				"decoration":
					decoration_placement_pressed.emit()
				"open_hole":
					open_hole_pressed.emit()
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
	for tool_type in _tool_buttons.keys():
		var btn = _tool_buttons[tool_type]
		if is_instance_valid(btn) and btn is ToolButton:
			var is_match = false
			if typeof(tool_type) == typeof(_current_tool) and tool_type == _current_tool:
				is_match = true
			elif not _selected_string_tool.is_empty() and str(tool_type) == _selected_string_tool:
				is_match = true
			btn.set_selected(is_match)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_command_or_control_pressed():
			return

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
				# Deep Rough, Pot Bunker, Stream, Rocks, Brush
				KEY_2, KEY_5, KEY_6, KEY_7, KEY_8:
					_on_tool_button_pressed(SHIFT_TERRAIN_HOTKEYS[event.keycode])
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
			KEY_MINUS:
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
			KEY_9:
				_on_tool_button_pressed(TerrainTypes.Type.FIRM_FAIRWAY)
			KEY_0:
				_on_tool_button_pressed(TerrainTypes.Type.WASTE_BUNKER)
			KEY_T:
				select_tab(Tab.TERRAIN)
				var theme_trees: Array = CourseTheme.get_tree_types(GameManager.current_theme) if GameManager else ["oak"]
				var first_tree: String = theme_trees[0] if not theme_trees.is_empty() else "oak"
				_on_tool_button_pressed("tree_" + first_tree)
			KEY_R:
				select_tab(Tab.TERRAIN)
				_on_tool_button_pressed("rock")
			KEY_F:
				if event.shift_pressed:
					select_tab(Tab.TERRAIN)
					_on_tool_button_pressed(TerrainTypes.Type.FLOWER_BED)
			KEY_B:
				_on_tool_button_pressed("building")
			KEY_O:
				_on_tool_button_pressed("decoration")
			KEY_H:
				_on_tool_button_pressed("open_hole")
			KEY_X:
				_on_tool_button_pressed("bulldozer")
			KEY_P:
				select_tab(Tab.STAFF)
				get_viewport().set_input_as_handled()

# =============================================================================
# Public API
# =============================================================================

func set_current_tool(tool_type: int) -> void:
	# Prevent selecting Tee when an unused tee waits.
	if tool_type == TerrainTypes.Type.TEE_BOX and not _tee_box_can_place:
		clear_selection()
		return
	_current_tool = tool_type
	_selected_string_tool = ""
	_update_selection_highlight()

func get_current_tool() -> int:
	return _current_tool

func clear_selection() -> void:
	_current_tool = -1
	_selected_string_tool = ""
	_update_selection_highlight()

func has_selection() -> bool:
	return (_current_tool >= 0 and _current_tool in _tool_buttons) or (not _selected_string_tool.is_empty() and _selected_string_tool in _tool_buttons)

func get_brush_size() -> int:
	return _brush_size

func _on_brush_shape_selected(index: int) -> void:
	_round_brush = index == 0
	for button in _brush_shape_buttons:
		if is_instance_valid(button) and button.selected != index:
			button.set_block_signals(true)
			button.select(index)
			button.set_block_signals(false)
	brush_shape_changed.emit(_round_brush)

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
	var shown: int = effective_brush_size()
	for label in _brush_labels:
		if is_instance_valid(label):
			label.text = "%dx%d" % [shown, shown]

## The brush size the selected tool actually paints with. Tee boxes, and a green
## that is about to become a Green With Hole, are capped at a single tile.
func effective_brush_size() -> int:
	if _brush_limit != HoleLayout.UNLIMITED_BRUSH:
		return mini(_brush_size, _brush_limit)
	return _brush_size

## Cap (or uncap) the brush for the selected tool: 1 = single tile, 0 = no cap.
func set_brush_limit(limit: int) -> void:
	if _brush_limit == limit:
		return
	_brush_limit = limit
	_apply_brush_limit()

func _apply_brush_limit() -> void:
	var locked: bool = _brush_limit == 1
	for button in _brush_buttons:
		if is_instance_valid(button):
			button.disabled = locked
	for shape in _brush_shape_buttons:
		if is_instance_valid(shape):
			shape.disabled = locked
	_update_brush_label()

func set_brush_size(value: int) -> void:
	if value in BRUSH_SIZES:
		_brush_size = value
		_update_brush_label()
		brush_size_changed.emit(value)

## Keep the Green tile's flag and tooltip in sync with what the next green paints.
func set_green_placement_state(places_cup: bool) -> void:
	_green_places_cup = places_cup
	if not is_instance_valid(_green_tile_button):
		return
	_green_tile_button.set_green_places_cup(places_cup)
	if places_cup:
		_green_tile_button.tool_description = \
				"The next placement will be a Green With Hole: one tile with a cup and flag."
	else:
		_green_tile_button.tool_description = \
				"The next placement will be a Green Without Hole. It uses the selected brush and adds no cup."
	_green_tile_button.accessibility_description = "%s Shortcut %s." % [
		_green_tile_button.tool_description, _green_tile_button.hotkey]

func green_will_place_cup() -> bool:
	return _green_places_cup

## Enable/disable the Open Hole buttons and explain what is still missing.
func set_open_hole_state(can_open: bool, reason: String = "") -> void:
	for button in _open_hole_buttons:
		if not is_instance_valid(button):
			continue
		button.disabled = not can_open
		button.tool_description = OPEN_HOLE_TOOLTIP if can_open or reason.is_empty() \
				else "%s. %s" % [OPEN_HOLE_BLOCKED_TOOLTIP, reason]

## Grey out, unselect and make unselectable the Tee tile while an unused tee waits.
func set_tee_box_state(can_place: bool, reason: String = "") -> void:
	_tee_box_can_place = can_place
	_tee_box_blocker = reason
	var btn: ToolButton = _tool_buttons.get(TerrainTypes.Type.TEE_BOX, null) as ToolButton
	if not is_instance_valid(btn):
		btn = _tee_tile_button
	if not is_instance_valid(btn):
		return

	# If the tee was selected and now becomes unavailable, unselect it.
	if not can_place and _current_tool == TerrainTypes.Type.TEE_BOX:
		clear_selection()

	btn.disabled = not can_place

	# Greyed out visual — modulate plus outline handled in TerrainTileButton,
	# but also set here so the change is immediate even if _update_visual_state
	# hasn't run yet.
	if not can_place:
		btn.modulate = Color(0.45, 0.45, 0.45, 0.65)
		var base_desc := "Tee for one hole — a single tile (1x1). Only one tee box may wait on the course at a time"
		if not reason.is_empty():
			btn.tool_description = "%s (%s)" % [base_desc, reason]
		else:
			btn.tool_description = "%s (Blocked — a tee box is already waiting. Open the hole first (H).)" % base_desc
	else:
		btn.modulate = Color(1, 1, 1, 1)
		btn.tool_description = "Tee for one hole — a single tile (1x1). Only one tee box may wait on the course at a time"

	btn.accessibility_description = "%s Shortcut %s." % [btn.tool_description, btn.hotkey]

	# Ensure the diamond outline reflects the disabled state immediately.
	if btn.has_method("_update_visual_state"):
		btn._update_visual_state()

func set_view_state(_orientation: int, _isometric: bool) -> void:
	pass
